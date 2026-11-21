extends RefCounted
## Conversations persistées dans <dossier>/<id>.json (user://chats/ en réel). Un index léger en mémoire
## (titre, assistant, texte de recherche) évite de recharger les messages ; chaque conversation est liée à un assistant.
## Message : {role: user|assistant|note, content, files?, images? (base64), assistant?, calls? (délégations), model?}

const U := preload("res://ui/universe.gd")

var dir := "user://chats/"
var export_dir := ""  # vide = dossier Documents
var index: Array = []  # entrées {id, title, pinned, assistant, model, created, updated, text, n}


func _init(d := "user://chats/") -> void:
	dir = d
	DirAccess.make_dir_recursive_absolute(dir)


# ------------------------------------------------------------------ Fonctions pures

static func new_chat(assistant := 0, model := "") -> Dictionary:
	var t := Time.get_unix_time_from_system()
	return {"id": "%d_%04x" % [int(t), randi() % 65536], "title": "", "pinned": false, "assistant": assistant,
			"model": model, "created": t, "updated": t, "messages": []}


static func approx_tokens(text: String) -> int:
	return int(ceil(text.length() / 3.6))


static func entry_of(c: Dictionary) -> Dictionary:
	var parts: PackedStringArray = [str(c.get("title", ""))]
	for m in c.get("messages", []):
		if m.get("role", "") != "note":
			parts.append(str(m.get("content", "")))
	return {"id": c.id, "title": c.get("title", ""), "pinned": c.get("pinned", false), "assistant": int(c.get("assistant", 0)),
			"model": c.get("model", ""), "created": c.get("created", 0.0), "updated": c.get("updated", 0.0),
			"text": "\n".join(parts).to_lower(), "n": (c.get("messages", []) as Array).size()}


static func display_title(e: Dictionary) -> String:
	var t := str(e.get("title", "")).strip_edges()
	return t if t != "" else "Nouvelle conversation"


## Indice du jour local (pour Aujourd'hui / Hier).
static func day_of(t: float) -> int:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0))
	return int(floor((t + bias * 60.0) / 86400.0))


## Groupes [[libellé, [entrées]]] : Épinglées, Aujourd'hui, Hier, Cette semaine, Plus ancien (tri par date décroissante).
static func group(entries: Array, now: float) -> Array:
	var es := entries.duplicate()
	es.sort_custom(func(a, b): return float(a.updated) > float(b.updated))
	var order := ["Épinglées", "Aujourd'hui", "Hier", "Cette semaine", "Plus ancien"]
	var buckets := {}
	for k in order:
		buckets[k] = []
	var today := day_of(now)
	for e in es:
		var k := "Plus ancien"
		if e.get("pinned", false):
			k = "Épinglées"
		else:
			var d := today - day_of(float(e.updated))
			if d <= 0:
				k = "Aujourd'hui"
			elif d == 1:
				k = "Hier"
			elif d < 7:
				k = "Cette semaine"
		buckets[k].append(e)
	var out: Array = []
	for k in order:
		if not buckets[k].is_empty():
			out.append([k, buckets[k]])
	return out


## Recherche plein texte (tous les mots) + filtre par assistant (-1 = tous).
static func search(entries: Array, q: String, assistant := -1) -> Array:
	var words := q.strip_edges().to_lower().split(" ", false)
	return entries.filter(func(e):
		if assistant >= 0 and int(e.assistant) != assistant:
			return false
		for w in words:
			if w not in str(e.text):
				return false
		return true)


## Messages au format API pour l'assistant `ai` (les notes sont ignorées, les autres assistants sont nommés).
static func api_messages(c: Dictionary, ai: int, upto := -1) -> Array:
	var out: Array = []
	var msgs: Array = c.get("messages", [])
	var n := msgs.size() if upto < 0 else upto
	for i in n:
		var m: Dictionary = msgs[i]
		match m.get("role", ""):
			"user":
				var txt := str(m.get("content", ""))
				for f in m.get("files", []):
					txt += "\n\n--- Fichier : %s ---\n%s\n--- fin ---" % [f.name, f.get("text", "")]
				var d := {"role": "user", "content": txt}
				if not (m.get("images", []) as Array).is_empty():
					d["images"] = m.images
				out.append(d)
			"assistant":
				var who := int(m.get("assistant", ai))
				var txt2 := str(m.get("content", ""))
				if txt2 == "":
					continue
				if who != ai:
					txt2 = "(%s) %s" % [U.get_u(who).name, txt2]
				out.append({"role": "assistant", "content": txt2})
	return out


static func to_markdown(c: Dictionary) -> String:
	var s := "# %s\n\n" % display_title(c)
	s += "*Assistant : %s · Modèle : %s · %s*\n\n" % [U.get_u(int(c.get("assistant", 0))).name, c.get("model", ""),
			Time.get_datetime_string_from_unix_time(int(c.get("updated", 0)), true)]
	for m in c.get("messages", []):
		match m.get("role", ""):
			"user":
				s += "## Moi\n\n%s\n\n" % m.get("content", "")
				for f in m.get("files", []):
					s += "*Fichier joint : %s*\n\n" % f.name
				if not (m.get("images", []) as Array).is_empty():
					s += "*(%d image jointe)*\n\n" % (m.images as Array).size()
			"assistant":
				s += "## %s\n\n" % U.get_u(int(m.get("assistant", c.get("assistant", 0)))).name
				for k in m.get("calls", []):
					s += "> **%s demande à %s** : %s\n>\n> %s\n\n" % [U.get_u(int(k.from)).name, U.get_u(int(k.to)).name,
							str(k.question).replace("\n", " "), str(k.answer).replace("\n", "\n> ")]
				s += "%s\n\n" % m.get("content", "")
			"note":
				s += "*%s*\n\n" % m.get("text", "")
	return s


static func safe_name(t: String) -> String:
	var re := RegEx.create_from_string("[^\\p{L}\\p{N}_ -]")
	var n := re.sub(t, "", true).strip_edges().replace(" ", "_")
	return n.left(48) if n != "" else "conversation"


# ------------------------------------------------------------------ Stockage

func path(id: String) -> String:
	return dir + id + ".json"


func load_index() -> void:
	index.clear()
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".json"):
			var c := load_chat(f.trim_suffix(".json"))
			if not c.is_empty():
				index.append(entry_of(c))


func load_chat(id: String) -> Dictionary:
	if not FileAccess.file_exists(path(id)):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path(id)))
	return d if d is Dictionary and d.has("id") else {}


func save(c: Dictionary) -> void:
	var f := FileAccess.open(path(c.id), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(c))
	f.close()
	var e := entry_of(c)
	for i in index.size():
		if index[i].id == c.id:
			index[i] = e
			return
	index.append(e)


## Supprime et renvoie la conversation (pour « Annuler »).
func delete(id: String) -> Dictionary:
	var c := load_chat(id)
	DirAccess.remove_absolute(path(id))
	index = index.filter(func(e): return e.id != id)
	return c


func patch(id: String, changes: Dictionary) -> void:
	var c := load_chat(id)
	if c.is_empty():
		return
	for k in changes:
		c[k] = changes[k]
	save(c)


func export_md(c: Dictionary) -> String:
	var d := export_dir
	if d == "":
		d = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		if d == "":
			d = OS.get_environment("HOME") + "/Documents"
	DirAccess.make_dir_recursive_absolute(d)
	var p := "%s/%s_%s.md" % [d, safe_name(display_title(c)), Time.get_date_string_from_unix_time(int(c.get("updated", 0)))]
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(to_markdown(c))
	f.close()
	return p
