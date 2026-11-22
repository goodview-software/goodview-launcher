extends RefCounted
## Les 8 mascottes = 8 assistants identiques pour tous publics (aucun prompt de base), chacun avec sa charte de couleurs.
## UN SEUL tableau à éditer : ALL. L'indice = numéro de variante de mascotte (avatar_id du profil partagé).
## model = modèle Ollama préféré ; fallback = modèles de repli ; sinon on prend un modèle installé.
## anim.speed / anim.bounce : personnalité d'animation (vitesse des images, amplitude du rebond).

const ALL := [
	{"id": "goody", "name": "Goody", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "4de1b4", "bg": "0e1116", "card": "171b22", "card_hi": "1e242d", "field": "232a34",
		"motto": "Pose ta question", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 1.0, "bounce": 1.0}, "vision": false,
		"personality": "",
		"prompt": ""},
	{"id": "rosie", "name": "Rosie", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "ff8fb1", "bg": "160b0e", "card": "201217", "card_hi": "29191e", "field": "332227",
		"motto": "Pose ta question", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 0.85, "bounce": 0.7}, "vision": false,
		"personality": "",
		"prompt": ""},
	{"id": "bleu", "name": "Bleu", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "6aa8ff", "bg": "0b0f16", "card": "121820", "card_hi": "192029", "field": "222933",
		"motto": "Pose ta question", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 0.9, "bounce": 0.6}, "vision": false,
		"personality": "",
		"prompt": ""},
	{"id": "ambre", "name": "Ambre", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "ffa24d", "bg": "16100b", "card": "201912", "card_hi": "292119", "field": "332a22",
		"motto": "Pose ta question", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 1.15, "bounce": 0.9}, "vision": false,
		"personality": "",
		"prompt": ""},
	{"id": "mauve", "name": "Mauve", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "b58bff", "bg": "0f0b16", "card": "171220", "card_hi": "1f1929", "field": "282233",
		"motto": "Pose ta question", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 0.8, "bounce": 1.2}, "vision": false,
		"personality": "",
		"prompt": ""},
	{"id": "soleil", "name": "Soleil", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "ffd84d", "bg": "16130b", "card": "201d12", "card_hi": "292519", "field": "332f22",
		"motto": "Pose ta question", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 1.2, "bounce": 1.4}, "vision": false,
		"personality": "",
		"prompt": ""},
	{"id": "braise", "name": "Braise", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "ff6b6b", "bg": "160b0b", "card": "201212", "card_hi": "291919", "field": "332222",
		"motto": "Pose ta question", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 1.3, "bounce": 1.1}, "vision": false,
		"personality": "",
		"prompt": ""},
	{"id": "brume", "name": "Brume", "role": "assistant", "specialty": "Assistant pour tous",
		"accent": "c9d1da", "bg": "131416", "card": "1b1e20", "card_hi": "232629", "field": "2c2f33",
		"motto": "Pose ta question", "model": "gemma3:4b", "fallback": ["qwen3:8b", "llama3.1:8b"], "temp": 0.7,
		"anim": {"speed": 0.7, "bounce": 0.5}, "vision": true,
		"personality": "",
		"prompt": ""},
]

## Animations disponibles (feuille mascot/goody_extra.png : ligne = variante*4 + indice).
const EXTRA_ANIMS := ["talk", "think", "call", "listen"]
## Mode d'un assistant -> animation de mascotte.
const MODE_ANIM := {"idle": "idle", "talk": "talk", "think": "think", "call": "call", "listen": "listen", "done": "happy", "error": "sad", "off": "off"}


static func count() -> int:
	return ALL.size()


static func get_u(i: int) -> Dictionary:
	return ALL[clampi(i, 0, ALL.size() - 1)]


static func color(i: int, key := "accent") -> Color:
	return Color(str(get_u(i)[key]))


## Bloc "theme" du profil partagé (lu par les autres apps).
static func shared_theme(i: int) -> Dictionary:
	var u := get_u(i)
	return {"name": u.name, "accent": "#" + u.accent, "bg": "#" + u.bg, "card": "#" + u.card}


static func anim_for(mode: String) -> String:
	return MODE_ANIM.get(mode, "idle")


## Retrouve un assistant par nom (insensible à la casse/accents simples) ; -1 si inconnu.
static func find(name: String) -> int:
	var n := name.strip_edges().to_lower().trim_prefix("@")
	for i in ALL.size():
		if str(ALL[i].name).to_lower() == n or str(ALL[i].id) == n:
			return i
	return -1


## Mention « @Nom » au début d'un message : {index, text} (index -1 si aucune).
static func parse_mention(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.begins_with("@"):
		var sp := t.find(" ")
		var nm := t.substr(1, sp - 1 if sp > 0 else -1)
		var i := find(nm)
		if i >= 0:
			return {"index": i, "text": t.substr(sp + 1).strip_edges() if sp > 0 else ""}
	return {"index": -1, "text": text}


static func _base(n: String) -> String:
	return n.split(":")[0]


## Modèle à utiliser : préféré s'il est installé, sinon repli, sinon n'importe quel installé (le plus petit).
## installed : [{name, size}] ou [String].
static func pick_model(i: int, installed: Array, exclude := []) -> String:
	var names: Array = []
	for m in installed:
		var nm := str(m.name) if m is Dictionary else str(m)
		if not is_broken(nm) and not (nm in exclude):
			names.append(nm)
	if names.is_empty():
		return ""
	var u := get_u(i)
	var wants: Array = [u.model] + (u.fallback as Array)
	for w in wants:
		var ws := str(w)
		for n in names:
			if n == ws or (":" not in ws and _base(n) == ws) or n == ws + ":latest":
				return n
	if u.get("vision", false):
		for n in names:
			if is_vision(n):
				return n
	return names[0]


## Modèles connus pour ne plus se charger avec Ollama récent (architecture mllama).
const BROKEN := ["mllama", "llama3.2-vision"]

static func is_broken(model: String) -> bool:
	var m := model.to_lower()
	for k in BROKEN:
		if k in m:
			return true
	return false


static func is_vision(model: String) -> bool:
	var m := model.to_lower()
	if is_broken(m):
		return false
	for k in ["gemma3", "llava", "minicpm-v", "qwen2.5vl", "qwen3-vl", "llama4", "moondream", "bakllava"]:
		if k in m:
			return true
	return false


## Aucun prompt de base : seules les consignes de l'utilisateur (réglages) sont envoyées par l'orchestre.
static func system_prompt(_i: int, _can_delegate: bool) -> String:
	return ""


static func team_list(except := -1) -> String:
	var l: PackedStringArray = []
	for j in ALL.size():
		if j != except:
			l.append("%s (%s)" % [ALL[j].name, ALL[j].specialty])
	return "; ".join(l)
