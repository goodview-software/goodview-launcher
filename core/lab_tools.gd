extends RefCounted
## Outils des zones du plan (lecture seule) : fichiers de l'utilisateur et calcul. Tout reste dans le dossier personnel,
## jamais dans les dossiers cachés (.ssh, .config…), avec des limites de taille pour ne pas noyer le modèle.

const Attach := preload("res://core/attach.gd")
const MAX_READ := 6000
const MAX_LIST := 60
const MAX_HITS := 20
const MAX_VISIT := 3000


static func schema() -> Array:
	return [
		_fn("lister_dossier", "Liste les fichiers et sous-dossiers d'un dossier de l'utilisateur.",
			{"chemin": {"type": "string", "description": "Chemin du dossier (ex. ~/Documents)"}}, ["chemin"]),
		_fn("lire_fichier", "Lit le début d'un fichier texte ou code de l'utilisateur.",
			{"chemin": {"type": "string", "description": "Chemin du fichier"}}, ["chemin"]),
		_fn("chercher_texte", "Cherche un mot dans les fichiers texte/code d'un dossier (récursif).",
			{"dossier": {"type": "string", "description": "Dossier de départ"}, "mot": {"type": "string", "description": "Texte à chercher"}}, ["dossier", "mot"]),
		_fn("calculer", "Évalue une expression mathématique (ex. 3*(2+4)/5, sqrt(2), pow(2,10)).",
			{"expression": {"type": "string", "description": "Expression à calculer"}}, ["expression"]),
	]


static func _fn(name: String, desc: String, props: Dictionary, req: Array) -> Dictionary:
	return {"type": "function", "function": {"name": name, "description": desc,
			"parameters": {"type": "object", "properties": props, "required": req}}}


## Chemin sûr (sous HOME, sans segment caché) ou "" si refusé.
static func safe_path(p: String) -> String:
	var home := OS.get_environment("HOME")
	if home == "":
		return ""
	p = p.strip_edges()
	if p.begins_with("~"):
		p = home + p.substr(1)
	if not p.is_absolute_path():
		p = home.path_join(p)
	p = p.simplify_path()
	if p != home and not p.begins_with(home + "/"):
		return ""
	for seg in p.substr(home.length()).split("/", false):
		if seg.begins_with("."):
			return ""
	return p


static func run(name: String, args: Dictionary) -> String:
	match name:
		"lister_dossier":
			return _list(str(args.get("chemin", "")))
		"lire_fichier":
			return _read(str(args.get("chemin", "")))
		"chercher_texte":
			return _search(str(args.get("dossier", "")), str(args.get("mot", "")))
		"calculer":
			return _calc(str(args.get("expression", "")))
	return "Outil inconnu : " + name


static func _list(path: String) -> String:
	var p := safe_path(path)
	if p == "" or not DirAccess.dir_exists_absolute(p):
		return "Dossier refusé ou introuvable."
	var out: PackedStringArray = []
	var dirs := DirAccess.get_directories_at(p)
	var files := DirAccess.get_files_at(p)
	for n in dirs:
		if not n.begins_with("."):
			out.append(n + "/")
	for n in files:
		if not n.begins_with("."):
			out.append(n)
	if out.is_empty():
		return "(dossier vide)"
	var shown := out.slice(0, MAX_LIST)
	return "\n".join(shown) + ("\n… (%d autres)" % (out.size() - MAX_LIST) if out.size() > MAX_LIST else "")


static func _read(path: String) -> String:
	var p := safe_path(path)
	if p == "" or not FileAccess.file_exists(p):
		return "Fichier refusé ou introuvable."
	var r := Attach.read(p)
	if r.kind != "text":
		return "Fichier non texte (%s)." % str(r.error if r.error != "" else r.kind)
	var t := str(r.text)
	return t.left(MAX_READ) + ("\n… (tronqué)" if t.length() > MAX_READ or r.truncated else "")


static func _search(dir: String, word: String) -> String:
	var p := safe_path(dir)
	word = word.strip_edges().to_lower()
	if p == "" or not DirAccess.dir_exists_absolute(p) or word == "":
		return "Dossier refusé/introuvable ou mot vide."
	var hits: PackedStringArray = []
	var state := {"visited": 0}
	_walk(p, word, 0, hits, state)
	if hits.is_empty():
		return "Aucun résultat."
	return "\n".join(hits)


static func _walk(dir: String, word: String, depth: int, hits: PackedStringArray, st: Dictionary) -> void:
	if depth > 4 or hits.size() >= MAX_HITS or st.visited > MAX_VISIT:
		return
	for f in DirAccess.get_files_at(dir):
		if f.begins_with(".") or f.get_extension().to_lower() not in Attach.TEXT_EXTS:
			continue
		st.visited += 1
		var fp := dir.path_join(f)
		if FileAccess.get_size(fp) > 500000:
			continue
		var n := 0
		for line in FileAccess.get_file_as_string(fp).split("\n"):
			n += 1
			if word in line.to_lower():
				hits.append("%s:%d: %s" % [fp, n, line.strip_edges().left(120)])
				if hits.size() >= MAX_HITS:
					return
				break  # une occurrence par fichier suffit
	for sub in DirAccess.get_directories_at(dir):
		if not sub.begins_with(".") and sub != "node_modules":
			_walk(dir.path_join(sub), word, depth + 1, hits, st)


static func _calc(expr: String) -> String:
	var e := Expression.new()
	if e.parse(expr.strip_edges()) != OK:
		return "Expression invalide : " + e.get_error_text()
	var v = e.execute([], null, false)
	if e.has_execute_failed():
		return "Calcul impossible."
	return str(v)
