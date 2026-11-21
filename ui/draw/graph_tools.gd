extends RefCounted
## Outils que l'assistant du graphe appelle pour créer / modifier des éléments de la scène.
## Le modèle ne donne jamais de coordonnées : creer_diagramme place tout automatiquement (arbre, ligne ou grille).
## Les éléments créés ont la couleur d'accent (AI_COLOR) pour qu'on voie ce que l'IA a fait.

const Geom := preload("res://ui/draw/geom.gd")
const AI_COLOR := "4de1b4"
const COLORS := {"rouge": "f87171", "vert": "4de1b4", "bleu": "60a5fa", "jaune": "fbbf24", "violet": "a78bfa",
		"orange": "fb923c", "rose": "ff8fb1", "gris": "98a2b0", "blanc": "e8ecf1"}
const SHAPES := ["rectangle", "ellipse", "diamond"]
const GAP_X := 50.0
const GAP_Y := 70.0
const MAX_NODES := 40


static func schema() -> Array:
	var node := {"type": "object", "properties": {
		"id": {"type": "string", "description": "Identifiant court (optionnel) pour les liens"},
		"texte": {"type": "string", "description": "Texte du nœud, court"},
		"forme": {"type": "string", "enum": SHAPES, "description": "rectangle (défaut), ellipse ou diamond (décision)"}}, "required": ["texte"]}
	var link := {"type": "object", "properties": {
		"de": {"type": "string", "description": "id ou texte du nœud de départ"},
		"vers": {"type": "string", "description": "id ou texte du nœud d'arrivée"},
		"texte": {"type": "string", "description": "Étiquette de la flèche (optionnel)"}}, "required": ["de", "vers"]}
	return [
		_fn("creer_diagramme", "Crée un schéma complet (nœuds + flèches) avec mise en page automatique. À préférer pour tout schéma, organigramme, plan, arbre d'étapes.",
			{"noeuds": {"type": "array", "items": node, "description": "Les nœuds du schéma"},
			"liens": {"type": "array", "items": link, "description": "Les flèches entre nœuds"},
			"disposition": {"type": "string", "enum": ["arbre", "ligne", "grille"], "description": "arbre (haut vers bas, défaut), ligne (gauche vers droite) ou grille"}}, ["noeuds"]),
		_fn("lister_elements", "Liste les éléments du tableau (id, type, texte). À appeler avant de modifier ou supprimer.", {}, []),
		_fn("ajouter_forme", "Ajoute une forme avec du texte.",
			{"type": {"type": "string", "enum": SHAPES}, "texte": {"type": "string"}}, ["type", "texte"]),
		_fn("ajouter_texte", "Ajoute un texte libre.", {"texte": {"type": "string"}}, ["texte"]),
		_fn("relier", "Ajoute une flèche entre deux éléments existants.",
			{"de": {"type": "string", "description": "id ou texte"}, "vers": {"type": "string", "description": "id ou texte"}, "texte": {"type": "string"}}, ["de", "vers"]),
		_fn("modifier", "Change le texte et/ou la couleur d'un élément existant.",
			{"id": {"type": "string", "description": "id ou texte actuel"}, "texte": {"type": "string"},
			"couleur": {"type": "string", "description": "rouge, vert, bleu, jaune, violet, orange, rose, gris, blanc ou #hex"}}, ["id"]),
		_fn("supprimer", "Supprime des éléments (jamais les zones de chat).",
			{"ids": {"type": "array", "items": {"type": "string"}, "description": "ids ou textes"}}, ["ids"]),
	]


static func _fn(name: String, desc: String, props: Dictionary, req: Array) -> Dictionary:
	return {"type": "function", "function": {"name": name, "description": desc,
			"parameters": {"type": "object", "properties": props, "required": req}}}


## Exécute un outil. created reçoit les ids créés (pour les sélectionner ensuite). center : centre de la vue (monde).
static func run(sc, name: String, args: Dictionary, center: Vector2, created: Array) -> String:
	match name:
		"creer_diagramme":
			return _diagram(sc, args, center, created)
		"lister_elements":
			return _list(sc)
		"ajouter_forme":
			var t := str(args.get("type", "rectangle"))
			return _add_shape(sc, t if t in SHAPES else "rectangle", str(args.get("texte", "")), center, created)
		"ajouter_texte":
			return _add_text(sc, str(args.get("texte", "")), center, created)
		"relier":
			return _link(sc, str(args.get("de", "")), str(args.get("vers", "")), str(args.get("texte", "")), created)
		"modifier":
			return _modify(sc, args)
		"supprimer":
			return _delete(sc, args.get("ids", []))
	return "Outil inconnu : " + name


# ------------------------------------------------------------------ utilitaires

static func wrap_text(text: String, width := 22) -> String:
	var lines: PackedStringArray = []
	var cur := ""
	for w in text.strip_edges().replace("\n", " ").split(" ", false):
		if cur != "" and cur.length() + 1 + w.length() > width:
			lines.append(cur)
			cur = w
		else:
			cur = w if cur == "" else cur + " " + w
	if cur != "":
		lines.append(cur)
	return "\n".join(lines)


static func color_of(c: String) -> String:
	c = c.strip_edges().to_lower().trim_prefix("#")
	if COLORS.has(c):
		return str(COLORS[c])
	if c.length() == 6 and c.is_valid_hex_number():
		return c
	return ""


static func label_of(el: Dictionary) -> String:
	match str(el.get("type", "")):
		"text":
			return str(el.get("text", ""))
		"zone":
			return str(el.get("title", ""))
		"frame":
			return str(el.get("name", ""))
	return str(el.get("label", ""))


## Retrouve un élément par id exact, sinon par texte (insensible à la casse).
static func resolve(sc, key: String) -> Dictionary:
	key = key.strip_edges()
	var el: Dictionary = sc.get_el(key)
	if not el.is_empty():
		return el
	var k := key.to_lower().replace("\n", " ")
	for e in sc.els:
		if label_of(e).to_lower().replace("\n", " ") == k and k != "":
			return e
	return {}


## Zone libre à droite du contenu existant (ou autour du centre de la vue si le tableau est vide).
static func origin(sc, center: Vector2, size: Vector2) -> Vector2:
	var ids: Array = []
	for e in sc.els:
		if e.type != "arrow":
			ids.append(e.id)
	if ids.is_empty():
		return center - size * 0.5
	var b: Rect2 = sc.bounds_of(ids)
	return Vector2(b.end.x + 120.0, b.position.y)


static func _node_size(text: String) -> Vector2:
	var m := Geom.measure(text, 20.0)
	return Vector2(clampf(m.x + 40.0, 110.0, 280.0), clampf(m.y + 30.0, 56.0, 170.0))


static func _make_shape(sc, shape: String, text: String, p: Vector2, size: Vector2) -> Dictionary:
	var el: Dictionary = sc.make(shape, p.x, p.y)
	el.w = size.x
	el.h = size.y
	el.label = text
	el.fontSize = 20.0
	el.stroke = AI_COLOR
	el.fillStyle = "aucun"
	sc.add(el)
	return el


static func _make_arrow(sc, a: Dictionary, b: Dictionary, label: String) -> Dictionary:
	var ar: Dictionary = sc.make("arrow", 0.0, 0.0)
	ar.points = [[0.0, 0.0], [10.0, 10.0]]
	ar.start = str(a.id)
	ar.end = str(b.id)
	ar.label = label
	ar.stroke = AI_COLOR
	ar.endHead = "arrow"
	sc.add(ar)
	Geom.refresh_arrow(sc, ar)
	sc.mark(ar)
	return ar


# ------------------------------------------------------------------ outils

static func _diagram(sc, args: Dictionary, center: Vector2, created: Array) -> String:
	var raw = args.get("noeuds", [])
	if not (raw is Array) or (raw as Array).is_empty():
		return "Erreur : « noeuds » doit être une liste non vide."
	var nodes: Array = []  # {key, text, shape}
	for n in raw:
		if nodes.size() >= MAX_NODES:
			break
		if n is Dictionary:
			var tx := str(n.get("texte", n.get("text", ""))).strip_edges()
			if tx != "":
				var sh := str(n.get("forme", "rectangle"))
				nodes.append({"key": str(n.get("id", "")), "text": tx, "shape": sh if sh in SHAPES else "rectangle"})
		elif str(n).strip_edges() != "":
			nodes.append({"key": "", "text": str(n).strip_edges(), "shape": "rectangle"})
	if nodes.is_empty():
		return "Erreur : aucun nœud avec du texte."
	var index := {}
	for i in nodes.size():
		if nodes[i].key != "":
			index[str(nodes[i].key).to_lower()] = i
		index[str(nodes[i].text).to_lower()] = i
	var edges: Array = []
	var ls = args.get("liens", [])
	if ls is Array:
		for l in ls:
			if l is Dictionary:
				var a := str(l.get("de", l.get("from", ""))).strip_edges().to_lower()
				var b := str(l.get("vers", l.get("to", ""))).strip_edges().to_lower()
				if index.has(a) and index.has(b) and index[a] != index[b]:
					edges.append([int(index[a]), int(index[b]), str(l.get("texte", ""))])
	var mode := str(args.get("disposition", "arbre"))
	var n_count := nodes.size()
	# niveaux
	var level: Array = []
	level.resize(n_count)
	level.fill(0)
	if mode == "arbre":
		for _it in n_count:
			var ch := false
			for e in edges:
				if int(level[e[1]]) < int(level[e[0]]) + 1 and int(level[e[0]]) + 1 < n_count:
					level[e[1]] = int(level[e[0]]) + 1
					ch = true
			if not ch:
				break
	var cols := 1
	if mode == "grille":
		cols = maxi(1, int(ceil(sqrt(float(n_count)))))
	# tailles
	var cw := 0.0
	var ch2 := 0.0
	var sizes: Array = []
	for n in nodes:
		n.text = wrap_text(str(n.text))
		var s := _node_size(str(n.text))
		sizes.append(s)
		cw = maxf(cw, s.x)
		ch2 = maxf(ch2, s.y)
	# positions (cellules)
	var cells: Array = []  # Vector2(col, row)
	if mode == "arbre":
		var per := {}
		for i in n_count:
			var lv: int = level[i]
			per[lv] = int(per.get(lv, 0)) + 1
		var seen := {}
		var maxc := 0
		for k in per:
			maxc = maxi(maxc, int(per[k]))
		for i in n_count:
			var lv2: int = level[i]
			var idx: int = int(seen.get(lv2, 0))
			seen[lv2] = idx + 1
			cells.append(Vector2(idx + (maxc - int(per[lv2])) * 0.5, lv2))
	elif mode == "ligne":
		for i in n_count:
			cells.append(Vector2(i, 0))
	else:
		for i in n_count:
			cells.append(Vector2(i % cols, i / cols))
	var total := Vector2(0, 0)
	for c in cells:
		total.x = maxf(total.x, (c.x + 1.0) * (cw + GAP_X))
		total.y = maxf(total.y, (c.y + 1.0) * (ch2 + GAP_Y))
	var org := origin(sc, center, total)
	var els: Array = []
	for i in n_count:
		var c: Vector2 = cells[i]
		var s: Vector2 = sizes[i]
		var p := org + Vector2(c.x * (cw + GAP_X) + (cw - s.x) * 0.5, c.y * (ch2 + GAP_Y) + (ch2 - s.y) * 0.5)
		var el := _make_shape(sc, str(nodes[i].shape), str(nodes[i].text), p, s)
		els.append(el)
		created.append(el.id)
	for e in edges:
		var ar := _make_arrow(sc, els[e[0]], els[e[1]], str(e[2]))
		created.append(ar.id)
	var ids: PackedStringArray = []
	for i in n_count:
		ids.append("%s=%s" % [str(nodes[i].text).replace("\n", " ").left(24), str(els[i].id)])
	return "Diagramme créé : %d nœuds, %d flèches. ids : %s" % [n_count, edges.size(), " ; ".join(ids)]


static func _list(sc) -> String:
	var out: PackedStringArray = []
	for e in sc.els:
		if e.type == "freedraw":
			continue
		var t := label_of(e).replace("\n", " ").left(60)
		if e.type == "arrow":
			var a: Dictionary = sc.get_el(str(e.get("start", "")))
			var b: Dictionary = sc.get_el(str(e.get("end", "")))
			out.append("%s | flèche | %s -> %s %s" % [e.id, label_of(a).replace("\n", " ").left(30), label_of(b).replace("\n", " ").left(30), t])
		else:
			out.append("%s | %s | %s" % [e.id, e.type, t])
		if out.size() >= 80:
			out.append("… (liste tronquée)")
			break
	return "\n".join(out) if not out.is_empty() else "(tableau vide)"


static func _add_shape(sc, shape: String, text: String, center: Vector2, created: Array) -> String:
	text = wrap_text(text)
	var s := _node_size(text)
	var el := _make_shape(sc, shape, text, origin(sc, center, s), s)
	created.append(el.id)
	return "Forme ajoutée (id %s)." % el.id


static func _add_text(sc, text: String, center: Vector2, created: Array) -> String:
	var el: Dictionary = sc.make("text", 0.0, 0.0)
	el.text = text
	el.stroke = AI_COLOR
	Geom.fit_text(el)
	var p := origin(sc, center, Vector2(el.w, el.h))
	el.x = p.x
	el.y = p.y
	sc.add(el)
	created.append(el.id)
	return "Texte ajouté (id %s)." % el.id


static func _link(sc, de: String, vers: String, text: String, created: Array) -> String:
	var a := resolve(sc, de)
	var b := resolve(sc, vers)
	if a.is_empty() or b.is_empty() or a.id == b.id:
		return "Erreur : élément introuvable (utilise lister_elements)."
	if a.type == "arrow" or b.type == "arrow":
		return "Erreur : on ne relie pas une flèche."
	var ar := _make_arrow(sc, a, b, text)
	created.append(ar.id)
	return "Flèche ajoutée."


static func _modify(sc, args: Dictionary) -> String:
	var el := resolve(sc, str(args.get("id", "")))
	if el.is_empty():
		return "Erreur : élément introuvable (utilise lister_elements)."
	var done: PackedStringArray = []
	if args.has("texte"):
		var t := str(args.texte)
		match str(el.type):
			"text":
				el.text = t
				Geom.fit_text(el)
				done.append("texte")
			"zone":
				el.title = t
				done.append("titre")
			"frame":
				el.name = t
				done.append("nom")
			_:
				el.label = wrap_text(t) if el.type in SHAPES else t
				done.append("texte")
	if args.has("couleur"):
		var c := color_of(str(args.couleur))
		if c == "":
			return "Erreur : couleur inconnue (rouge, vert, bleu, jaune, violet, orange, rose, gris, blanc ou #hex)."
		if el.type != "zone":
			el.stroke = c
			done.append("couleur")
	sc.mark(el)
	sc.refresh_arrows({el.id: true})
	return "Modifié (%s)." % ", ".join(done) if not done.is_empty() else "Rien à modifier."


static func _delete(sc, ids) -> String:
	var list: Array = ids if ids is Array else [ids]
	var del: Array = []
	var refused := 0
	for k in list:
		var el := resolve(sc, str(k))
		if el.is_empty():
			continue
		if el.type == "zone":
			refused += 1
		elif el.id not in del:
			del.append(el.id)
	if not del.is_empty():
		sc.remove(del)
	return "%d élément(s) supprimé(s)%s." % [del.size(), " ; les zones de chat sont protégées" if refused > 0 else ""]
