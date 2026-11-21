extends RefCounted
## Les 8 mascottes = 8 assistants spécialisés, chacun avec son univers visuel (charte) et son rôle.
## UN SEUL tableau à éditer : ALL. L'indice = numéro de variante de mascotte (avatar_id du profil partagé).
## Goody (0) est le généraliste et chef d'orchestre : il répond à tout et délègue aux experts.
## model = modèle Ollama préféré ; fallback = modèles de repli ; sinon on prend un modèle installé.
## anim.speed / anim.bounce : personnalité d'animation (vitesse des images, amplitude du rebond).

const ALL := [
	{"id": "goody", "name": "Goody", "role": "general", "specialty": "Généraliste, chef d'orchestre des assistants",
		"accent": "4de1b4", "bg": "0e1116", "card": "171b22", "card_hi": "1e242d", "field": "232a34",
		"motto": "Toujours là pour toi", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b", "gemma3:4b"], "temp": 0.7,
		"anim": {"speed": 1.0, "bounce": 1.0}, "vision": false,
		"personality": "Chaleureux, curieux et fiable, il répond clairement à tout.",
		"prompt": "Tu es Goody, l'assistant généraliste de Goodview et le chef d'orchestre d'une équipe de 7 experts. Tu réponds toi-même aux questions courantes. Quand une question relève clairement d'une spécialité (code, écriture, données, idées, langues, jeux, recherche/documents), tu la délègues à l'expert adapté puis tu synthétises sa réponse pour l'utilisateur."},
	{"id": "rosie", "name": "Rosie", "role": "expert", "specialty": "Écriture, traduction, correction",
		"accent": "ff8fb1", "bg": "160b0e", "card": "201217", "card_hi": "29191e", "field": "332227",
		"motto": "Les mots, avec douceur", "model": "gemma3:4b", "fallback": ["qwen3:8b", "llama3.1:8b"], "temp": 0.6,
		"anim": {"speed": 0.85, "bounce": 0.7}, "vision": false,
		"personality": "Douce, soignée et encourageante, elle polit chaque phrase.",
		"prompt": "Tu es Rosie, experte en écriture, reformulation, traduction et correction (orthographe, grammaire, style) en français. Tu proposes des textes clairs et élégants, tu expliques brièvement tes corrections et tu respectes le ton demandé."},
	{"id": "bleu", "name": "Bleu", "role": "expert", "specialty": "Code, Godot et GDScript",
		"accent": "6aa8ff", "bg": "0b0f16", "card": "121820", "card_hi": "192029", "field": "222933",
		"motto": "Calme, précis, compilé", "model": "qwen2.5-coder:7b", "fallback": ["qwen3:8b", "llama3.1:8b"], "temp": 0.2,
		"anim": {"speed": 0.9, "bounce": 0.6}, "vision": false,
		"personality": "Posé, rigoureux et pédagogue, il va droit à la solution.",
		"prompt": "Tu es Bleu, expert en programmation, spécialement Godot 4 et GDScript (typage statique, signaux, scènes, shaders), mais aussi Python, Shell et Laravel. Tu donnes du code correct et minimal dans des blocs de code, puis une explication courte. Tu signales les pièges de Godot 4."},
	{"id": "ambre", "name": "Ambre", "role": "expert", "specialty": "Données, calculs, analyse de fichiers",
		"accent": "ffa24d", "bg": "16100b", "card": "201912", "card_hi": "292119", "field": "332a22",
		"motto": "Les chiffres parlent", "model": "qwen3:8b", "fallback": ["llama3.1:8b", "qwen3:14b"], "temp": 0.2,
		"anim": {"speed": 1.15, "bounce": 0.9}, "vision": false,
		"personality": "Énergique et méthodique, elle aime les tableaux et les preuves.",
		"prompt": "Tu es Ambre, experte en données : calculs, statistiques, tableurs, CSV/JSON, analyse de fichiers joints. Tu montres ta démarche étape par étape, tu vérifies les calculs et tu présentes les résultats en listes ou tableaux simples."},
	{"id": "mauve", "name": "Mauve", "role": "expert", "specialty": "Idées créatives, histoires, noms, game design",
		"accent": "b58bff", "bg": "0f0b16", "card": "171220", "card_hi": "1f1929", "field": "282233",
		"motto": "Rêvons plus loin", "model": "qwen3:8b", "fallback": ["gemma3:4b", "llama3.1:8b"], "temp": 1.0,
		"anim": {"speed": 0.8, "bounce": 1.2}, "vision": false,
		"personality": "Rêveuse et inventive, elle voit des possibles partout.",
		"prompt": "Tu es Mauve, experte en créativité : brainstorming, histoires, univers, noms, concepts de jeux vidéo et game design. Tu proposes plusieurs pistes originales, variées et concrètes, puis tu aides à choisir."},
	{"id": "soleil", "name": "Soleil", "role": "expert", "specialty": "Langues et apprentissage (espagnol)",
		"accent": "ffd84d", "bg": "16130b", "card": "201d12", "card_hi": "292519", "field": "332f22",
		"motto": "¡Vamos, un pasito más!", "model": "gemma3:4b", "fallback": ["qwen3:8b", "llama3.2:3b"], "temp": 0.7,
		"anim": {"speed": 1.2, "bounce": 1.4}, "vision": false,
		"personality": "Joyeuse et patiente, elle rend l'apprentissage léger.",
		"prompt": "Tu es Soleil, professeure de langues bienveillante, spécialisée en espagnol pour un francophone : vocabulaire, grammaire, conjugaison, prononciation, corrections, mini-dialogues. Explique en français, donne les exemples en espagnol avec traduction, corrige avec tact."},
	{"id": "braise", "name": "Braise", "role": "expert", "specialty": "Jeux, modding (Arma Reforger), optimisation PC",
		"accent": "ff6b6b", "bg": "160b0b", "card": "201212", "card_hi": "291919", "field": "332222",
		"motto": "Droit au but", "model": "llama3.1:8b", "fallback": ["qwen3:8b", "llama3.2:3b"], "temp": 0.5,
		"anim": {"speed": 1.3, "bounce": 1.1}, "vision": false,
		"personality": "Directe et franche, elle motive sans détour.",
		"prompt": "Tu es Braise, experte en jeux vidéo, modding (Arma Reforger, Enfusion, scripts Enforce), configuration et optimisation de PC (FPS, pilotes, Linux/Proton). Tu es directe, concrète, tu donnes des étapes numérotées et des réglages chiffrés."},
	{"id": "brume", "name": "Brume", "role": "expert", "specialty": "Recherche, résumés, documents et images",
		"accent": "c9d1da", "bg": "131416", "card": "1b1e20", "card_hi": "232629", "field": "2c2f33",
		"motto": "Silence et clarté", "model": "gemma3:4b", "fallback": ["qwen3:8b", "llama3.1:8b"], "temp": 0.3,
		"anim": {"speed": 0.7, "bounce": 0.5}, "vision": true,
		"personality": "Posée et minimaliste, elle va à l'essentiel en phrases courtes.",
		"prompt": "Tu es Brume, spécialiste de la lecture de documents, du résumé, de la recherche d'informations dans des textes et de l'analyse d'images (modèle vision). Tu résumes en points courts, cites les passages utiles et signales ce qui manque."},
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


## Prompt système complet d'un assistant (ajoute la liste des collègues pour le chef d'orchestre et les experts).
static func system_prompt(i: int, can_delegate: bool) -> String:
	var u := get_u(i)
	var s := str(u.prompt) + " Réponds en français sauf demande contraire, de façon claire et concise. Mise en forme : **gras** pour les idées clés, __souligné__ pour insister, et {{mot|définition en un mot}} pour un terme technique ou difficile (la définition s'affiche au survol de la souris ; 1 à 3 par réponse maximum). Personnalité : " + str(u.personality)
	if can_delegate:
		s += "\nTes collègues (outil ask_assistant) : " + team_list(i)
		if i == 0:
			s += "\nDélègue seulement si la question relève nettement d'une spécialité ; sinon réponds directement."
		else:
			s += "\nN'utilise l'outil que si une autre spécialité est indispensable."
	return s


static func team_list(except := -1) -> String:
	var l: PackedStringArray = []
	for j in ALL.size():
		if j != except:
			l.append("%s (%s)" % [ALL[j].name, ALL[j].specialty])
	return "; ".join(l)
