extends "res://pages/page.gd"
## Plan 2D : on pose des zones (rectangles) ; dans chacune on parle avec un assistant. « Clôturer » fige la zone et
## en tire une synthèse ; on tire un fil (●) d'une zone vers une autre pour la nourrir de cette synthèse.
## Données : zones {id,x,y,w,h,title,ai,msgs[{role,content}],summary,closed} + liens {from,to}, sauvées dans user://board.json.

const U := preload("res://ui/universe.gd")
const MD := preload("res://ui/markdown.gd")
const Ollama := preload("res://core/ollama.gd")
const Attach := preload("res://core/attach.gd")
const LabTools := preload("res://core/lab_tools.gd")
const Orchestra := preload("res://core/orchestra.gd")
const Sketch := preload("res://ui/sketch.gd")
const MAX_TOOL_ROUNDS := 4
const FILE := "user://board.json"  # ancien fichier unique (migré vers le plan 1)
const PLANS_DIR := "user://boards/"
const PLANS_INDEX := "user://boards/index.json"
const FRAME_COLORS := ["4de1b4", "ff8fb1", "fbbf24", "60a5fa", "a78bfa", "f87171"]
const IMG_DIR := "user://board_img/"
## Types de zones : titre par défaut, mode par défaut, consigne donnée à l'IA.
const KINDS := {
	"problem": {"label": "Problème", "title": "Le problème", "mode": "etapes", "w": 340.0, "h": 280.0,
		"prompt": "Cette zone sert à formuler le problème : aide à le clarifier (objectif, contraintes, critères de réussite) en posant au plus 3 questions précises."},
	"ideas": {"label": "Idées", "title": "Idées", "mode": "brainstorm", "w": 320.0, "h": 260.0,
		"prompt": "Cette zone sert à produire des idées et pistes de solution."},
	"proscons": {"label": "Pour / contre", "title": "Pour / contre", "mode": "critique", "w": 320.0, "h": 260.0,
		"prompt": "Cette zone sert à peser une option : liste clairement les arguments pour, puis contre, puis ton verdict."},
	"decision": {"label": "Décision", "title": "Décision", "mode": "synthese", "w": 320.0, "h": 260.0,
		"prompt": "Cette zone sert à décider : compare les options reçues selon des critères explicites et recommande-en une, avec les risques restants."},
	"note": {"label": "Note", "title": "Note", "mode": "libre", "w": 300.0, "h": 220.0, "prompt": ""},
	"image": {"label": "Image", "title": "Image", "mode": "libre", "w": 340.0, "h": 380.0,
		"prompt": "Cette zone contient une image que tu peux voir. Décris-la précisément quand on te le demande, puis réponds aux questions à son sujet."},
}
## Types de fils : ce que la zone source apporte à la zone d'arrivée.
const LINK_ORDER := ["feed", "critique", "compare", "merge"]
const LINKS := {
	"feed": ["nourrit", "Contexte et base de travail"],
	"critique": ["critique", "Contenu à critiquer (points faibles, risques, ce qui manque)"],
	"compare": ["compare", "Contenus à comparer entre eux (critères explicites)"],
	"merge": ["fusionne", "Contenus à fusionner en une proposition cohérente (réconcilie les contradictions)"],
}
const DEBATE_TURNS := 4
const MODES := {
	"libre": ["Libre", ""],
	"brainstorm": ["Brainstorm", "Mode brainstorm : propose beaucoup d'idées variées et originales, sans les juger, en liste courte."],
	"avocat": ["Avocat du diable", "Mode avocat du diable : conteste, cherche les failles, les risques et les contre-exemples."],
	"critique": ["Critique", "Mode critique constructive : évalue ce qui est proposé, ses points forts, ses faiblesses et comment l'améliorer."],
	"etapes": ["Pas à pas", "Mode pas à pas : raisonne par étapes numérotées et vérifie chaque étape avant de conclure."],
	"synthese": ["Synthèse", "Mode synthèse : résume et structure l'essentiel, en pesant les options."],
}
const PORT_R := 9.0
const PORT_DX := 14.0
const MAX_HISTORY := 14
const CTX_CAP := 1500

var zones: Array = []
var links: Array = []
var nodes := {}  # id -> Zone
var pan := Vector2(24, 24)
var zoom := 1.0
const ZMIN := 0.12
const ZMAX := 2.0
const LOD := 0.5  # en dessous, les zones ne montrent que leur titre
var canvas: Control
var world: Control
var imgs := {}  # id de zone image -> {b64, tex}
var menu: PopupMenu
var view_menu: PopupMenu
var plans: Array = []  # [{id, name}]
var plan_id := ""
var frames: Array = []  # cadres {id,x,y,w,h,title,color}
var fnodes := {}
var search_e: LineEdit
var help_btn: Button
var help_panel: PanelContainer
var help_txt: RichTextLabel
var sketch  # couche de dessin (ui/sketch.gd)
var _rename: ConfirmationDialog
var _rename_e: LineEdit
var _deb := {}  # zones en débat
var reqs := {}  # id -> Ollama.Req en cours
var drag_from := ""
var drag_pos := Vector2.ZERO
var _dirty := false
var _save_t := 0.0


func _init() -> void:
	page_title = "Plan"
	has_back = true


# ------------------------------------------------------------------ Construction

func build() -> void:
	head_title.text = "Plan"
	menu = PopupMenu.new()
	for k in KINDS:
		menu.add_item(str(KINDS[k].label), KINDS.keys().find(k))
	menu.add_separator()
	menu.add_item("Cadre (regrouper des zones)", 100)
	menu.id_pressed.connect(func(i: int):
		if i == 100:
			_add_frame()
		else:
			_add_zone(str(KINDS.keys()[i])))
	add_child(menu)
	var add := W.Btn.new("+ Zone", "primary")
	add.size_name = "sm"
	add.tooltip_text = "Nouvelle zone (choisis son type)"
	add.pressed.connect(func(): menu.popup(Rect2i(Vector2i(add.get_screen_position() + Vector2(0, add.size.y)), Vector2i(0, 0))))
	head_right.add_child(add)
	view_menu = PopupMenu.new()
	view_menu.id_pressed.connect(_on_view_menu)
	add_child(view_menu)
	var fit := W.Btn.new("Vue", "ghost")
	fit.size_name = "sm"
	fit.tooltip_text = "Cadrer toutes les zones / exporter le raisonnement (molette : zoom, glisser le fond : déplacer)"
	fit.pressed.connect(func():
		_build_view_menu()
		view_menu.popup(Rect2i(Vector2i(fit.get_screen_position() + Vector2(0, fit.size.y)), Vector2i(0, 0))))
	head_right.add_child(fit)
	var qc := W.Btn.new("Chat", "ghost")
	qc.size_name = "sm"
	qc.tooltip_text = "Chat rapide (conversation classique)"
	qc.pressed.connect(func(): router.go_tab("chat"))
	head_right.add_child(qc)
	scroll.visible = false
	canvas = Canvas.new()
	canvas.board = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(100, 300)
	canvas.clip_contents = true
	canvas.set_meta("k_nolint", true)
	_outer.add_child(canvas)
	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.position = pan
	world.scale = Vector2(zoom, zoom)
	canvas.add_child(world)
	search_e = LineEdit.new()
	search_e.placeholder_text = "Rechercher dans le plan… (Entrée : aller à la 1re zone)"
	search_e.visible = false
	search_e.position = Vector2(10, 10)
	search_e.custom_minimum_size = Vector2(280, 0)
	search_e.text_changed.connect(_apply_search)
	search_e.text_submitted.connect(func(_t: String): _goto_first_match())
	canvas.add_child(search_e)
	sketch = Sketch.new(self)
	sketch.attach(canvas, world)
	help_btn = Button.new()
	help_btn.text = "?"
	help_btn.tooltip_text = "Aide : comment marchent les fils (nourrit, critique, compare, fusionne)"
	help_btn.custom_minimum_size = Vector2(44, 44)
	help_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help_btn.offset_left = -54
	help_btn.offset_right = -10
	help_btn.offset_top = 10
	help_btn.offset_bottom = 54
	help_btn.pressed.connect(func():
		help_panel.visible = not help_panel.visible
		if help_panel.visible:
			_fill_help())
	canvas.add_child(help_btn)
	help_panel = PanelContainer.new()
	help_panel.visible = false
	help_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	help_panel.offset_left = -390
	help_panel.offset_right = -10
	help_panel.offset_top = 60
	help_panel.offset_bottom = 460
	help_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var hs := StyleBoxFlat.new()
	hs.bg_color = T.CARD
	hs.border_color = T.OK
	hs.set_border_width_all(2)
	hs.set_content_margin_all(10)
	help_panel.add_theme_stylebox_override("panel", hs)
	help_txt = RichTextLabel.new()
	help_txt.bbcode_enabled = true
	help_txt.selection_enabled = true
	help_txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help_panel.add_child(help_txt)
	canvas.add_child(help_panel)
	_rename = ConfirmationDialog.new()
	_rename.title = "Renommer le plan"
	_rename.set_meta("k_nolint", true)
	_rename_e = LineEdit.new()
	_rename.add_child(_rename_e)
	_rename.confirmed.connect(func():
		_plan_entry()["name"] = _rename_e.text.strip_edges() if _rename_e.text.strip_edges() != "" else "Plan"
		_save_index())
	add_child(_rename)
	if ctx.models.is_empty():
		_load_models()
	_init_plans()
	_load()
	if zones.is_empty() and frames.is_empty():
		_add_zone("problem", "De quoi allons-nous parler aujourd'hui ?")
	get_window().files_dropped.connect(_on_drop)
	_spawn_all()
	_refresh_all()
	_apply_view()


func _process(dt: float) -> void:
	if _dirty:
		_save_t += dt
		if _save_t > 0.8:
			_save()


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_drop):
		get_window().files_dropped.disconnect(_on_drop)
	for id in reqs:
		if reqs[id] != null:
			(reqs[id] as Ollama.Req).cancel()
	if _dirty:
		_save()


func _add_zone(kind := "note", title := "", at := Vector2.INF) -> Dictionary:
	var K_: Dictionary = KINDS[kind]
	var c := at
	if c == Vector2.INF:
		c = c2w(canvas.size * 0.5) - Vector2(float(K_.w) * 0.5, float(K_.h) * 0.4) if canvas != null and canvas.size.x > 10 else Vector2(40, 40)
		c += Vector2(randf_range(-30, 30), randf_range(-30, 30))
	var d := {"id": "z%d%03d" % [Time.get_ticks_msec(), randi() % 1000], "x": c.x, "y": c.y, "w": K_.w, "h": K_.h,
			"title": title if title != "" else str(K_.title), "ai": int(ctx.active), "kind": kind, "mode": K_.mode,
			"msgs": [], "summary": "", "closed": false, "img": ""}
	if kind == "image":
		var vi := _vision_ai()
		if vi >= 0:
			d.ai = vi
	zones.append(d)
	if canvas != null and world != null:
		_spawn(d)
		_refresh_all()
		_touch()
	return d


## Assistant à vision (Brume par défaut) ; -1 si aucun modèle vision n'est installé.
func _vision_ai() -> int:
	for i in U.count():
		if U.get_u(i).get("vision", false):
			return i
	return -1


func _spawn(d: Dictionary) -> void:
	var z := Zone.new()
	z.board = self
	z.d = d
	world.add_child(z)
	nodes[d.id] = z
	_load_img(str(d.id), str(d.get("img", "")))
	z.build_ui()
	z.refresh()
	if zoom < LOD:
		z.set_lod(true)


func _zone(id: String) -> Dictionary:
	for d in zones:
		if d.id == id:
			return d
	return {}


func _touch() -> void:
	_dirty = true
	_save_t = 0.0
	if canvas != null:
		canvas.queue_redraw()
	if sketch != null:
		sketch.redraw()


func _refresh_all() -> void:
	if help_panel != null and help_panel.visible:
		_fill_help()
	for id in nodes:
		(nodes[id] as Zone).refresh()
	if canvas != null:
		canvas.queue_redraw()


# ------------------------------------------------------------------ Navigation (zoom / vue)

func w2c(v: Vector2) -> Vector2:
	return pan + v * zoom


func c2w(v: Vector2) -> Vector2:
	return (v - pan) / zoom


func _apply_view() -> void:
	world.position = pan
	world.scale = Vector2(zoom, zoom)
	var lod := zoom < LOD
	for id in nodes:
		(nodes[id] as Zone).set_lod(lod)
	for id in fnodes:
		(fnodes[id] as Frame).set_lod(lod)
	canvas.queue_redraw()
	_touch()


## Zoom centré sur un point du canevas (molette / pincement).
func zoom_at(cpos: Vector2, factor: float) -> void:
	var nz := clampf(zoom * factor, ZMIN, ZMAX)
	if is_equal_approx(nz, zoom):
		return
	var wp := c2w(cpos)
	zoom = nz
	pan = cpos - wp * zoom
	_apply_view()


## Cadre toutes les zones dans la vue.
func fit_all() -> void:
	if zones.is_empty() or canvas.size.x < 10:
		return
	var r := Rect2(float(zones[0].x), float(zones[0].y), float(zones[0].w), float(zones[0].h))
	for d in zones:
		r = r.merge(Rect2(float(d.x), float(d.y), float(d.w), float(d.h)))
	r = r.grow(40.0)
	zoom = clampf(minf(canvas.size.x / r.size.x, canvas.size.y / r.size.y), ZMIN, 1.0)
	pan = canvas.size * 0.5 - r.get_center() * zoom
	_apply_view()


func focus_zone(id: String) -> void:
	var d := _zone(id)
	if d.is_empty():
		return
	zoom = 1.0
	pan = canvas.size * 0.5 - Vector2(float(d.x) + float(d.w) * 0.5, float(d.y) + float(d.h) * 0.5)
	_apply_view()


func _input(e: InputEvent) -> void:
	if canvas == null or not is_visible_in_tree():
		return
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var cp := canvas.get_local_mouse_position()
		if not Rect2(Vector2.ZERO, canvas.size).has_point(cp):
			return
		# sur une zone, la molette fait défiler son texte (Ctrl ou vue éloignée : zoom)
		if zone_at(c2w(cp)) != "" and not e.ctrl_pressed and zoom >= LOD:
			return
		zoom_at(cp, 1.12 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and sketch != null and sketch.key(e):
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.pressed and e.keycode == KEY_F and (e.ctrl_pressed or e.meta_pressed):
		_toggle_search()
		get_viewport().set_input_as_handled()
	elif e is InputEventMagnifyGesture:
		var cp2 := canvas.get_local_mouse_position()
		if Rect2(Vector2.ZERO, canvas.size).has_point(cp2):
			zoom_at(cp2, e.factor)


# ------------------------------------------------------------------ Liens

func add_link(a: String, b: String) -> void:
	if a == b or a == "" or b == "":
		return
	for l in links:
		if l.from == a and l.to == b:
			return
	links.append({"from": a, "to": b, "type": "feed"})
	_refresh_all()
	_touch()


func cycle_link(i: int) -> void:
	var t := str(links[i].get("type", "feed"))
	links[i]["type"] = LINK_ORDER[(LINK_ORDER.find(t) + 1) % LINK_ORDER.size()]
	_refresh_all()
	_touch()


func remove_link(i: int) -> void:
	links.remove_at(i)
	_refresh_all()
	_touch()


func zone_at(world_pos: Vector2, except := "") -> String:
	for i in range(zones.size() - 1, -1, -1):
		var d: Dictionary = zones[i]
		if d.id != except and Rect2(float(d.x), float(d.y), float(d.w), float(d.h)).has_point(world_pos):
			return d.id
	return ""


func delete_zone(id: String) -> void:
	if reqs.has(id):
		if reqs[id] != null:
			(reqs[id] as Ollama.Req).cancel()
		reqs.erase(id)
	var dz := _zone(id)
	if not dz.is_empty() and str(dz.get("img", "")) != "":
		DirAccess.remove_absolute(str(dz.img))
	imgs.erase(id)
	zones = zones.filter(func(d): return d.id != id)
	links = links.filter(func(l): return l.from != id and l.to != id)
	if nodes.has(id):
		(nodes[id] as Zone).queue_free()
		nodes.erase(id)
	_refresh_all()
	_touch()


## Texte reçu par une zone depuis ses zones sources (synthèse si clôturée, sinon fin de la discussion).
func _src_body(s: Dictionary) -> String:
	var body := str(s.summary).strip_edges()
	if not (s.closed and body != ""):
		var tr: PackedStringArray = []
		for m in s.msgs:
			tr.append("%s : %s" % ["Utilisateur" if m.role == "user" else "Assistant", str(m.content)])
		body = "\n".join(tr)
		body = body.right(CTX_CAP) if body.length() > CTX_CAP else body
	return body


func incoming_context(id: String) -> String:
	var groups := {}
	for l in links:
		if l.to != id:
			continue
		var s := _zone(str(l.from))
		var body := _src_body(s) if not s.is_empty() else ""
		if body != "":
			var t := str(l.get("type", "feed"))
			groups[t] = str(groups.get(t, "")) + "[Zone « %s »]\n%s\n\n" % [str(s.title), body]
	var out: PackedStringArray = []
	for t in LINK_ORDER:
		if groups.has(t):
			out.append("### %s\n%s" % [str(LINKS[t][1]), str(groups[t]).strip_edges()])
	return "\n\n".join(out)


## Empreinte du contenu des sources (change quand une source est modifiée) : sert à repérer les zones périmées.
func incoming_sig(id: String) -> String:
	var parts: PackedStringArray = []
	for l in links:
		if l.to == id:
			var s := _zone(str(l.from))
			if not s.is_empty():
				parts.append(str(_src_body(s).hash()))
	return ",".join(parts)


func is_stale(d: Dictionary) -> bool:
	return not (d.msgs as Array).is_empty() and str(d.get("fed_sig", "")) != incoming_sig(str(d.id))


func has_sources(id: String) -> bool:
	for l in links:
		if l.to == id:
			return true
	return false


## Premier message automatique d'une zone d'après le type de ses fils entrants.
func run_from_sources(id: String) -> void:
	var d := _zone(id)
	var kinds := {}
	for l in links:
		if l.to == id:
			kinds[str(l.get("type", "feed"))] = true
	var asks: PackedStringArray = []
	if kinds.has("critique"):
		asks.append("Critique le contenu des zones liées.")
	if kinds.has("compare"):
		asks.append("Compare les contenus des zones liées.")
	if kinds.has("merge"):
		asks.append("Fusionne les contenus des zones liées en une proposition cohérente.")
	if kinds.has("feed") or asks.is_empty():
		asks.append("Utilise le contexte des zones liées pour avancer sur le sujet de cette zone (« %s »)." % str(d.title))
	send(id, " ".join(asks))


# ------------------------------------------------------------------ Discussion

func _system(d: Dictionary, who := -1) -> String:
	var s := U.system_prompt(int(d.ai) if who < 0 else who, false)
	s += "\nTu travailles dans une zone d'un plan de réflexion (titre : « %s »). Sois concis." % str(d.title)
	var kp := str(KINDS[d.kind].prompt)
	if kp != "":
		s += "\n" + kp
	var mp := str(MODES[d.mode][1])
	if mp != "":
		s += "\n" + mp
	var c := incoming_context(str(d.id))
	if c != "":
		s += "\nContexte venant des zones liées à celle-ci (à utiliser comme base de travail) :\n" + c
	return s


func _model(d: Dictionary, who := -1) -> String:
	var ai_i := int(d.ai) if who < 0 else who
	if d.kind == "image":
		var m := ctx.model_for(ai_i)
		if ctx.model_is_vision(m):
			return m
		for x in ctx.models:
			if ctx.model_is_vision(str(x.name)):
				return str(x.name)
		return ""
	return ctx.model_for(ai_i)


func send(id: String, text: String) -> void:
	var d := _zone(id)
	text = text.strip_edges()
	if d.is_empty() or text == "" or reqs.has(id) or _deb.has(id) or d.closed:
		return
	d.msgs.append({"role": "user", "content": text})
	d.msgs.append({"role": "assistant", "content": ""})
	_stream(d, _history(d, d.msgs.size() - 1), func(t: String): d.msgs[d.msgs.size() - 1].content = t)


## Débat : l'assistant de la zone et un adversaire alternent (DEBATE_TURNS tours). Rappuyer arrête le débat.
func debate(id: String) -> void:
	var d := _zone(id)
	if d.is_empty() or d.closed:
		return
	if _deb.has(id):
		_deb.erase(id)
		if reqs.has(id) and reqs[id] != null:
			(reqs[id] as Ollama.Req).cancel()
		_refresh_all()
		return
	if reqs.has(id):
		return
	var a := int(d.ai)
	var b := int(d.get("ai2", -1))
	if b < 0 or b == a or b >= U.count():
		b = (a + 1) % U.count()
		d["ai2"] = b
	_deb[id] = true
	_refresh_all()
	var topic := str(d.title)
	for m in d.msgs:
		if m.role == "user":
			topic = str(m.content)
	for r in DEBATE_TURNS:
		if not _deb.has(id) or not is_instance_valid(self):
			break
		var who := a if r % 2 == 0 else b
		var other := b if who == a else a
		d.msgs.append({"role": "assistant", "content": "", "ai": who})
		var idx: int = d.msgs.size() - 1
		var h := _history(d, idx, who)
		h[0].content += "\nTu débats avec %s sur le sujet de cette zone. %s Réponds en 4 phrases maximum, directement à son dernier argument, sans répéter." % [
			str(U.get_u(other).name), "Défends une position claire." if r < 2 else "Cherche maintenant une position commune, ou le point de désaccord décisif."]
		if h.size() == 1:
			h.append({"role": "user", "content": topic})
		elif h[h.size() - 1].role != "user":
			h.append({"role": "user", "content": "Poursuis le débat."})
		await _stream(d, h, func(t: String): d.msgs[idx].content = t, who)
	_deb.erase(id)
	if is_instance_valid(self):
		_refresh_all()
		_touch()


func close_zone(id: String) -> void:
	var d := _zone(id)
	if d.is_empty() or reqs.has(id) or _deb.has(id):
		return
	if d.closed:
		d.closed = false
		_refresh_all()
		_touch()
		return
	if d.msgs.is_empty():
		d.summary = ""
		d.closed = true
		_refresh_all()
		_touch()
		return
	var h := _history(d, d.msgs.size())
	h.append({"role": "user", "content": "Clôture la discussion : rédige la synthèse (le raisonnement suivi puis la conclusion), en Markdown, 10 lignes maximum, pour la transmettre à une autre zone."})
	d.summary = ""
	d.closed = true
	_stream(d, h, func(t: String): d.summary = t)


func _history(d: Dictionary, upto: int, who := -1) -> Array:
	var cur := int(d.ai) if who < 0 else who
	var h: Array = [{"role": "system", "content": _system(d, who)}]
	var from := maxi(0, upto - MAX_HISTORY)
	for i in range(from, upto):
		var m: Dictionary = d.msgs[i]
		if m.role == "assistant" and int(m.get("ai", cur)) != cur:
			h.append({"role": "user", "content": "[%s] %s" % [str(U.get_u(int(m.ai)).name), str(m.content)]})  # un autre assistant (débat)
		else:
			h.append({"role": m.role, "content": m.content})
	if d.kind == "image" and imgs.has(d.id):
		for m in h:
			if m.role == "user":
				m["images"] = [imgs[d.id].b64]  # l'image accompagne le premier message
				break
	return h


func _stream(d: Dictionary, msgs: Array, setter: Callable, who := -1) -> void:
	var id := str(d.id)
	d["fed_sig"] = incoming_sig(id)
	reqs[id] = null  # réservé pendant le chargement des modèles
	_refresh_all()
	if ctx.models.is_empty():
		await _load_models()
		if not is_instance_valid(self) or not reqs.has(id):
			return
	var model := _model(d, who)
	if model == "":
		setter.call("(Aucun modèle vision installé : installe-en un, par ex. gemma3 ou qwen2.5vl, via Ollama.)" if d.kind == "image" else "(Aucun modèle Ollama disponible : installe-en un depuis l'Assistant IA.)")
		_finish(id)
		return
	var use_tools: bool = bool(d.get("tools", true)) and d.kind != "image" and Ollama.supports_tools(model)
	if use_tools:
		msgs[0].content += "\nTu disposes d'outils en lecture seule (fichiers de l'utilisateur, calcul). Utilise-les quand c'est utile, sans les annoncer."
	var opts := {"temperature": float(U.get_u(int(d.ai) if who < 0 else who).temp), "num_predict": 700}
	var total := ""  # texte déjà fixé par les tours précédents (outils)
	for round_i in MAX_TOOL_ROUNDS + 1:
		var req: Ollama.Req = ctx.ollama.chat(model, msgs, opts, LabTools.schema() if use_tools and round_i < MAX_TOOL_ROUNDS else [])
		reqs[id] = req
		var acc := [""]
		var calls: Array = []
		_refresh_all()
		req.line.connect(func(l: Dictionary):
			var m: Dictionary = l.get("message", {})
			var c := str(m.get("content", ""))
			if c != "" and is_instance_valid(self):
				acc[0] += c
				var shown: String = Ollama.strip_think(acc[0]) if "<think>" in acc[0] else acc[0]
				setter.call(total + shown)
				if nodes.has(id):
					(nodes[id] as Zone).render()
			for tc in m.get("tool_calls", []):
				calls.append(tc))
		var r: Array = await req.finished
		if not is_instance_valid(self):
			return
		var text: String = Ollama.strip_think(acc[0])
		if not r[0]:
			if str(r[1]) != "cancel":
				setter.call(total + text + "\n(Erreur : %s)" % Ollama.friendly(str(r[1]), str(r[2]), model))
			break
		if calls.is_empty() or not reqs.has(id):
			setter.call(total + text)
			break
		# --- exécution des outils puis nouveau tour
		msgs.append({"role": "assistant", "content": text, "tool_calls": Orchestra.clean_calls(calls)})
		total += text + ("\n\n" if text.strip_edges() != "" else "")
		for tc in calls:
			var f: Dictionary = tc.get("function", {})
			var nm := str(f.get("name", ""))
			var args = f.get("arguments", {})
			if args is String:
				args = JSON.parse_string(args)
			if not (args is Dictionary):
				args = {}
			var res := LabTools.run(nm, args)
			total += "> 🔧 %s(%s)\n" % [nm, ", ".join((args as Dictionary).values().map(func(x): return str(x).left(60)))]
			msgs.append({"role": "tool", "content": res, "tool_name": nm})
		setter.call(total)
	_finish(id)


## Liste les modèles Ollama installés (la page Chat le fait déjà ; le plan doit aussi pouvoir le faire seul).
func _load_models() -> void:
	var res: Array = await ctx.ollama.collect(ctx.ollama.tags())
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if res[0] and not res[3].is_empty():
		var ms: Array = []
		for m in res[3][0].get("models", []):
			ms.append({"name": str(m.get("name", "")), "size": float(m.get("size", 0))})
		ms.sort_custom(func(a, b): return a.size < b.size)
		ctx.models = ms
		ctx.prefetch_caps()


func _finish(id: String) -> void:
	reqs.erase(id)
	_refresh_all()
	_touch()


# ------------------------------------------------------------------ Images

func _load_img(id: String, path: String) -> void:
	if path == "" or not FileAccess.file_exists(path):
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	var im := Image.new()
	if im.load_jpg_from_buffer(bytes) != OK:
		return
	imgs[id] = {"b64": Marshalls.raw_to_base64(bytes), "tex": ImageTexture.create_from_image(im)}


func set_image(id: String, path: String) -> bool:
	var d := _zone(id)
	if d.is_empty():
		return false
	var r := Attach.read(path)
	if r.kind != "image":
		ctx.notify("%s : image attendue (png, jpg, webp…)" % path.get_file(), "error")
		return false
	DirAccess.make_dir_recursive_absolute(IMG_DIR)
	var file := IMG_DIR + id + ".jpg"
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(Marshalls.base64_to_raw(str(r.b64)))
	f.close()
	d.img = file
	_load_img(id, file)
	if nodes.has(id):
		(nodes[id] as Zone).refresh()
	_touch()
	return true


func pick_image(id: String) -> void:
	var fp: Control = K.FilePicker.new()
	fp.files_selected.connect(func(paths: PackedStringArray):
		if not paths.is_empty():
			set_image(id, paths[0]))
	fp.open_in(router, OS.get_environment("HOME"))


## Dépôt d'un fichier sur le plan : sur une zone image -> remplace ; ailleurs -> crée une zone image.
func _on_drop(files: PackedStringArray) -> void:
	if not is_visible_in_tree() or canvas == null:
		return
	var cp := canvas.get_local_mouse_position()
	var wp := c2w(cp)
	for path in files:
		if str(path).get_extension().to_lower() not in Attach.IMG_EXTS:
			continue
		var zid := zone_at(wp)
		var d := _zone(zid)
		if d.is_empty() or d.kind != "image":
			d = _add_zone("image", "", wp - Vector2(170, 40))
			zid = str(d.id)
		set_image(zid, path)
		wp += Vector2(30, 30)


# ------------------------------------------------------------------ Plans (plusieurs projets)

func _plan_entry() -> Dictionary:
	for e in plans:
		if e.id == plan_id:
			return e
	return {}


func _plan_file(id := "") -> String:
	return PLANS_DIR + (plan_id if id == "" else id) + ".json"


func _init_plans() -> void:
	DirAccess.make_dir_recursive_absolute(PLANS_DIR)
	var v = JSON.parse_string(FileAccess.get_file_as_string(PLANS_INDEX)) if FileAccess.file_exists(PLANS_INDEX) else null
	if v is Dictionary and not (v.get("plans", []) as Array).is_empty():
		plans = v.plans
		plan_id = str(v.get("current", plans[0].id))
	else:
		plans = [{"id": "p1", "name": "Plan 1"}]
		plan_id = "p1"
		if FileAccess.file_exists(FILE):  # migration de l'ancien plan unique
			DirAccess.copy_absolute(FILE, _plan_file("p1"))
		_save_index()
	if _plan_entry().is_empty():
		plan_id = str(plans[0].id)


func _save_index() -> void:
	var f := FileAccess.open(PLANS_INDEX, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"plans": plans, "current": plan_id}))


func _clear_nodes() -> void:
	for id in reqs:
		if reqs[id] != null:
			(reqs[id] as Ollama.Req).cancel()
	reqs.clear()
	_deb.clear()
	for id in nodes:
		(nodes[id] as Node).queue_free()
	for id in fnodes:
		(fnodes[id] as Node).queue_free()
	nodes.clear()
	fnodes.clear()
	zones = []
	links = []
	frames = []
	imgs.clear()
	if sketch != null:
		sketch.clear()


func switch_plan(id: String) -> void:
	if id == plan_id:
		return
	_save()
	_clear_nodes()
	plan_id = id
	_save_index()
	pan = Vector2(24, 24)
	zoom = 1.0
	_load()
	if zones.is_empty() and frames.is_empty():
		_add_zone("problem", "De quoi allons-nous parler aujourd'hui ?")
	_spawn_all()
	_refresh_all()
	_apply_view()


func _new_plan() -> void:
	var id := "p%d" % Time.get_ticks_msec()
	plans.append({"id": id, "name": "Plan %d" % (plans.size() + 1)})
	_save()
	_clear_nodes()
	plan_id = id
	_save_index()
	pan = Vector2(24, 24)
	zoom = 1.0
	_add_zone("problem", "De quoi allons-nous parler ?")
	_apply_view()
	_save()


func _delete_plan() -> void:
	if plans.size() <= 1:
		ctx.notify("Il faut garder au moins un plan.", "error")
		return
	var old := plan_id
	var next := ""
	for e in plans:
		if e.id != old:
			next = str(e.id)
			break
	_dirty = false
	for d in zones:
		if str(d.get("img", "")) != "":
			DirAccess.remove_absolute(str(d.img))
	DirAccess.remove_absolute(_plan_file(old))
	plans = plans.filter(func(e): return e.id != old)
	_clear_nodes()
	plan_id = next
	_save_index()
	_load()
	_spawn_all()
	_refresh_all()
	_apply_view()


func _build_view_menu() -> void:
	view_menu.clear()
	view_menu.add_item("Tout voir", 0)
	view_menu.add_item("Rechercher (Ctrl+F)", 2)
	view_menu.add_item("Exporter en Markdown", 1)
	view_menu.add_separator("Plans")
	for i in plans.size():
		view_menu.add_radio_check_item(str(plans[i].name), 1000 + i)
		view_menu.set_item_checked(view_menu.get_item_index(1000 + i), plans[i].id == plan_id)
	view_menu.add_item("+ Nouveau plan", 3)
	view_menu.add_item("Renommer ce plan…", 4)
	view_menu.add_item("Supprimer ce plan", 5)


func _on_view_menu(i: int) -> void:
	match i:
		0:
			fit_all()
		1:
			export_markdown()
		2:
			_toggle_search()
		3:
			_new_plan()
		4:
			_rename_e.text = str(_plan_entry().get("name", ""))
			_rename.popup_centered(Vector2i(320, 110))
		5:
			_delete_plan()
		_:
			if i >= 1000 and i - 1000 < plans.size():
				switch_plan(str(plans[i - 1000].id))


# ------------------------------------------------------------------ Cadres

func _add_frame() -> void:
	var c := c2w(canvas.size * 0.5) - Vector2(220, 160) if canvas.size.x > 10 else Vector2(0, 0)
	var f := {"id": "f%d" % Time.get_ticks_msec(), "x": c.x, "y": c.y, "w": 480.0, "h": 340.0, "title": "Thème",
			"color": FRAME_COLORS[frames.size() % FRAME_COLORS.size()]}
	frames.append(f)
	_spawn_frame(f)
	_touch()


func _spawn_frame(f: Dictionary) -> void:
	var fr := Frame.new()
	fr.board = self
	fr.d = f
	world.add_child(fr)
	world.move_child(fr, 0)  # derrière les zones
	fnodes[f.id] = fr
	fr.build_ui()
	fr.set_lod(zoom < LOD)


func delete_frame(id: String) -> void:
	frames = frames.filter(func(f): return f.id != id)
	if fnodes.has(id):
		(fnodes[id] as Node).queue_free()
		fnodes.erase(id)
	_touch()


func _spawn_all() -> void:
	for f in frames:
		_spawn_frame(f)
	for d in zones:
		_spawn(d)


# ------------------------------------------------------------------ Aide (fils)

func _fill_help() -> void:
	var acc := T.OK.to_html(false)
	var out: PackedStringArray = []
	out.append("[b][color=#%s]Comment marchent les fils[/color][/b]" % acc)
	out.append("Un fil envoie ce qu'une zone a conclu vers une autre. Texte envoyé : la [b]synthèse[/b] si la zone de départ est clôturée, sinon la fin de sa discussion.\n")
	out.append("[b]Clic sur l'étiquette[/b] du fil = change son type · [b]clic droit[/b] = le supprime.\n")
	out.append("[color=#%s]■ nourrit[/color] : l'arrivée s'appuie sur la source comme base de travail." % acc)
	out.append("[color=#%s]■ critique[/color] : l'arrivée critique la source (faiblesses, risques, oublis)." % acc)
	out.append("[color=#%s]■ compare[/color] : l'arrivée met plusieurs sources en balance, critère par critère. [b]Il faut au moins 2 fils compare vers la même zone.[/b]" % acc)
	out.append("[color=#%s]■ fusionne[/color] : l'arrivée réunit plusieurs sources en une seule proposition et règle leurs contradictions. [b]Au moins 2 fils aussi.[/b]\n" % acc)
	out.append("Ensuite, le bouton [b]Lancer[/b] de la zone d'arrivée démarre l'IA. Si une source change après coup : bordure orange ⚠ et bouton [b]Relancer[/b].\n")
	out.append("[b][color=#%s]Dans ton plan[/color][/b]" % acc)
	if links.is_empty():
		out.append("Aucun fil pour l'instant : tire le rond ● d'une zone vers une autre.")
	var count := {}
	for l in links:
		var t := str(l.get("type", "feed"))
		count[str(l.to) + "|" + t] = int(count.get(str(l.to) + "|" + t, 0)) + 1
	for l in links:
		var a := _zone(str(l.from))
		var b := _zone(str(l.to))
		if a.is_empty() or b.is_empty():
			continue
		var t := str(l.get("type", "feed"))
		var src := "sa synthèse" if (a.closed and str(a.summary).strip_edges() != "") else "la fin de sa discussion (pas encore clôturée)"
		var eff := ""
		match t:
			"feed":
				eff = "« %s » reçoit %s de « %s » comme base de travail." % [str(b.title), src, str(a.title)]
			"critique":
				eff = "« %s » va critiquer %s de « %s »." % [str(b.title), src, str(a.title)]
			"compare":
				eff = "« %s » va comparer %s de « %s » avec les autres sources." % [str(b.title), src, str(a.title)]
				if int(count[str(l.to) + "|compare"]) < 2:
					eff += " [color=#fbbf24]Il n'y a qu'un fil compare : relie une 2e zone à « %s » pour avoir quelque chose à comparer.[/color]" % str(b.title)
			"merge":
				eff = "« %s » va fusionner %s de « %s » avec les autres sources." % [str(b.title), src, str(a.title)]
				if int(count[str(l.to) + "|merge"]) < 2:
					eff += " [color=#fbbf24]Un seul fil fusionne : ajoute une 2e source vers « %s ».[/color]" % str(b.title)
		out.append("• [b]« %s » → « %s »[/b] (%s)\n  %s" % [str(a.title), str(b.title), str(LINKS[t][0]), eff])
	help_txt.text = "\n".join(out)


# ------------------------------------------------------------------ Recherche

func _toggle_search() -> void:
	search_e.visible = not search_e.visible
	if search_e.visible:
		search_e.grab_focus()
	else:
		search_e.text = ""
		_apply_search("")


func _match(d: Dictionary, q: String) -> bool:
	if q == "":
		return true
	if q in str(d.title).to_lower() or q in str(d.summary).to_lower():
		return true
	for m in d.msgs:
		if q in str(m.content).to_lower():
			return true
	return false


func _apply_search(q: String) -> void:
	q = q.strip_edges().to_lower()
	for d in zones:
		if nodes.has(d.id):
			(nodes[d.id] as Control).modulate = Color(1, 1, 1, 1.0 if _match(d, q) else 0.25)


func _goto_first_match() -> void:
	var q := search_e.text.strip_edges().to_lower()
	for d in zones:
		if q != "" and _match(d, q):
			focus_zone(str(d.id))
			return


# ------------------------------------------------------------------ Export

func export_markdown() -> void:
	var order := zones.duplicate()
	order.sort_custom(func(a, b): return float(a.x) < float(b.x) if absf(float(a.x) - float(b.x)) > 60.0 else float(a.y) < float(b.y))
	var out: PackedStringArray = ["# Plan de réflexion", ""]
	for d in order:
		var st := "clôturée" if d.closed else "ouverte"
		out.append("## %s" % str(d.title))
		out.append("*%s · %s · %s · %s*" % [KINDS[d.kind].label, MODES[d.mode][0], str(U.get_u(int(d.ai)).name), st])
		var src: PackedStringArray = []
		for l in links:
			if l.to == d.id:
				var sz := _zone(str(l.from))
				if not sz.is_empty():
					src.append(str(sz.title))
		if not src.is_empty():
			out.append("*Nourrie par : %s*" % ", ".join(src))
		out.append("")
		if d.closed and str(d.summary).strip_edges() != "":
			out.append("**Synthèse**\n\n" + str(d.summary).strip_edges())
		else:
			for m in d.msgs:
				out.append("**%s** : %s\n" % ["Toi" if m.role == "user" else str(U.get_u(int(d.ai)).name), str(m.content).strip_edges()])
		out.append("")
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if dir == "":
		dir = OS.get_environment("HOME")
	var t := Time.get_datetime_dict_from_system()
	var path := "%s/plan_%04d-%02d-%02d_%02d%02d.md" % [dir, t.year, t.month, t.day, t.hour, t.minute]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		ctx.notify("Export impossible dans " + dir, "error")
		return
	f.store_string("\n".join(out))
	f.close()
	ctx.notify("Exporté : " + path)


# ------------------------------------------------------------------ Sauvegarde

func _save() -> void:
	_dirty = false
	_save_t = 0.0
	var f := FileAccess.open(_plan_file(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"zones": zones, "links": links, "frames": frames, "shapes": sketch.to_save(), "pan": [pan.x, pan.y], "zoom": zoom}))


func _load() -> void:
	if not FileAccess.file_exists(_plan_file()):
		return
	var v = JSON.parse_string(FileAccess.get_file_as_string(_plan_file()))
	if v is Dictionary:
		zones = v.get("zones", [])
		links = v.get("links", [])
		frames = v.get("frames", [])
		sketch.load_shapes(v.get("shapes", []))
		var p = v.get("pan", [24, 24])
		pan = Vector2(float(p[0]), float(p[1]))
		zoom = clampf(float(v.get("zoom", 1.0)), ZMIN, ZMAX)
		if world != null:
			world.position = pan
			world.scale = Vector2(zoom, zoom)
		for d in zones:
			d["closed"] = bool(d.get("closed", false))
			d["kind"] = str(d.get("kind", "note")) if KINDS.has(str(d.get("kind", "note"))) else "note"
			d["mode"] = str(d.get("mode", "libre")) if MODES.has(str(d.get("mode", "libre"))) else "libre"
			d["img"] = str(d.get("img", ""))
			d["msgs"] = d.get("msgs", [])
			d["summary"] = str(d.get("summary", ""))
		# une réponse interrompue (appli fermée en cours de route) ne laisse pas de zone « en écriture »


# ------------------------------------------------------------------ Canevas (fond, fils, ports)

class Canvas extends Control:
	var board: Node
	var panning := false

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_default_cursor_shape = Control.CURSOR_DRAG

	func _process(_dt: float) -> void:
		if board != null and (board.drag_from != "" or not board.reqs.is_empty()):
			queue_redraw()

	static func bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
		var u := 1.0 - t
		return p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t

	func port_pos(d: Dictionary) -> Vector2:
		return board.w2c(Vector2(float(d.x) + float(d.w), float(d.y) + float(d.h) * 0.5)) + Vector2(PORT_DX, 0)

	func _curve(a: Vector2, b: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 29:
			pts.append(bez(a, a + Vector2(90, 0), b - Vector2(90, 0), b, i / 28.0))
		return pts

	func _draw() -> void:
		if board == null:
			return
		if board.sketch != null and board.sketch.has_bound():
			board.sketch.redraw()  # flèches collées : suivent les zones déplacées
		var T = board.T
		var gs: float = 24.0 * board.zoom
		while gs < 12.0:
			gs *= 4.0
		var off := Vector2(fposmod(board.pan.x, gs), fposmod(board.pan.y, gs))
		var x := off.x
		while x < size.x:
			var y := off.y
			while y < size.y:
				draw_rect(Rect2(floorf(x), floorf(y), 2, 2), Color(1, 1, 1, 0.07))
				y += gs
			x += gs
		for i in board.links.size():
			var l: Dictionary = board.links[i]
			var a: Dictionary = board._zone(str(l.from))
			var b: Dictionary = board._zone(str(l.to))
			if a.is_empty() or b.is_empty():
				continue
			var col: Color = board.U.color(int(a.ai))
			var pts := _curve(port_pos(a), board.w2c(Vector2(float(b.x), float(b.y) + float(b.h) * 0.5)) + Vector2(-4, 0))
			var solid: bool = a.closed
			for k in pts.size() - 1:
				if solid or k % 2 == 0:
					draw_line(pts[k], pts[k + 1], Color(col, 0.95 if solid else 0.55), 3.0)
			var e := pts[pts.size() - 1]
			draw_colored_polygon(PackedVector2Array([e, e + Vector2(-12, -7), e + Vector2(-12, 7)]), col)
			var m := pts[14]
			var lt := str(board.LINKS[str(l.get("type", "feed"))][0])
			var br := Rect2(m - Vector2(34, 9), Vector2(68, 18))
			draw_rect(br, T.CARD_HI)
			draw_rect(br, col, false, 2.0)
			draw_string(get_theme_default_font(), Vector2(br.position.x, br.position.y + 13), lt, HORIZONTAL_ALIGNMENT_CENTER, br.size.x, 11, T.TEXT)
		for d in board.zones:
			var col2: Color = board.U.color(int(d.ai))
			var p := port_pos(d)
			var zr: float = float(d.x) + float(d.w)
			draw_line(board.w2c(Vector2(zr, float(d.y) + float(d.h) * 0.5)), p, col2, 3.0)
			draw_circle(p, PORT_R, col2 if d.closed else T.BG)
			draw_arc(p, PORT_R, 0, TAU, 20, col2, 3.0)
		if board.drag_from != "":
			var s: Dictionary = board._zone(board.drag_from)
			if not s.is_empty():
				var c: Color = board.U.color(int(s.ai))
				var pts2 := _curve(port_pos(s), board.drag_pos)
				for k in pts2.size() - 1:
					draw_line(pts2[k], pts2[k + 1], Color(c, 0.8), 3.0)
		if board.zones.size() <= 1:
			draw_string(get_theme_default_font(), Vector2(14, size.y - 14),
				"Glisse le rond ● vers une autre zone pour la nourrir. Clic sur un fil : change son type ; clic droit : le supprime.",
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 12, board.T.DIM)

	func _gui_input(e: InputEvent) -> void:
		if board == null:
			return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			# clic droit sur l'étiquette d'un fil : le supprime
			for i in board.links.size():
				var l2: Dictionary = board.links[i]
				var a2: Dictionary = board._zone(str(l2.from))
				var b2: Dictionary = board._zone(str(l2.to))
				if a2.is_empty() or b2.is_empty():
					continue
				var pts2 := _curve(port_pos(a2), board.w2c(Vector2(float(b2.x), float(b2.y) + float(b2.h) * 0.5)) + Vector2(-4, 0))
				if Rect2(pts2[14] - Vector2(34, 9), Vector2(68, 18)).has_point(e.position):
					board.remove_link(i)
					return
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				for d in board.zones:
					if port_pos(d).distance_to(e.position) < PORT_R + 6.0:
						board.drag_from = str(d.id)
						board.drag_pos = e.position
						return
				for i in board.links.size():
					var l: Dictionary = board.links[i]
					var a: Dictionary = board._zone(str(l.from))
					var b: Dictionary = board._zone(str(l.to))
					if a.is_empty() or b.is_empty():
						continue
					var pts := _curve(port_pos(a), board.w2c(Vector2(float(b.x), float(b.y) + float(b.h) * 0.5)) + Vector2(-4, 0))
					if Rect2(pts[14] - Vector2(34, 9), Vector2(68, 18)).has_point(e.position):
						board.cycle_link(i)  # clic : change le type du fil (nourrit / critique / compare / fusionne)
						return
				if board.sketch.sel_press(e.position, e.double_click):
					return
				panning = true
			else:
				if board.sketch.dragging:
					board.sketch.sel_release(e.position)
					return
				if board.drag_from != "":
					board.add_link(board.drag_from, board.zone_at(board.c2w(e.position), board.drag_from))
					board.drag_from = ""
					queue_redraw()
				if panning:
					panning = false
					board._touch()
		elif e is InputEventMouseMotion:
			if board.sketch.dragging:
				board.sketch.sel_motion(e.position)
			elif board.drag_from != "":
				board.drag_pos = e.position
				queue_redraw()
			elif panning:
				board.pan += e.relative
				board.world.position = board.pan
				queue_redraw()


# ------------------------------------------------------------------ Zone (rectangle)

class Zone extends PanelContainer:
	var board: Node
	var d: Dictionary
	var title_e: LineEdit
	var who: OptionButton
	var close_b: Button
	var info: Label
	var logv: RichTextLabel
	var chip: Label
	var mode_o: OptionButton
	var pic: Control
	var an: Button
	var launch: Button
	var deb: Button
	var who2: OptionButton
	var tools_c: CheckBox
	var input_row: HBoxContainer
	var input: LineEdit
	var mode := ""
	var grab := Vector2.ZERO
	var lod := false

	func build_ui() -> void:
		position = Vector2(float(d.x), float(d.y))
		custom_minimum_size = Vector2(250, 190)
		size = Vector2(float(d.w), float(d.h))
		mouse_filter = Control.MOUSE_FILTER_STOP
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 6)
		add_child(v)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 4)
		head.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(head)
		var grip := Label.new()
		grip.text = "⠿"
		grip.mouse_filter = Control.MOUSE_FILTER_PASS
		head.add_child(grip)
		title_e = LineEdit.new()
		title_e.text = str(d.title)
		title_e.flat = true
		title_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_e.custom_minimum_size.x = 60
		title_e.text_changed.connect(func(t: String):
			d.title = t
			board._touch())
		head.add_child(title_e)
		who = OptionButton.new()
		for i in board.U.count():
			who.add_item(str(board.U.get_u(i).name), i)
		who.select(int(d.ai))
		who.item_selected.connect(func(i: int):
			d.ai = i
			refresh()
			board._refresh_all()
			board._touch())
		head.add_child(who)
		close_b = Button.new()
		close_b.pressed.connect(func(): board.close_zone(str(d.id)))
		head.add_child(close_b)
		var del := Button.new()
		del.text = "✕"
		del.tooltip_text = "Supprimer la zone"
		del.pressed.connect(func(): board.delete_zone(str(d.id)))
		head.add_child(del)
		var row2 := HBoxContainer.new()
		row2.add_theme_constant_override("separation", 6)
		row2.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(row2)
		chip = Label.new()
		chip.text = "◼ " + str(board.KINDS[d.kind].label).to_upper()
		chip.add_theme_font_size_override("font_size", 11)
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		row2.add_child(chip)
		mode_o = OptionButton.new()
		var mi := 0
		for mk in board.MODES:
			mode_o.add_item(str(board.MODES[mk][0]), mi)
			mode_o.set_item_metadata(mi, mk)
			if mk == d.mode:
				mode_o.select(mi)
			mi += 1
		mode_o.item_selected.connect(func(i: int):
			d.mode = str(mode_o.get_item_metadata(i))
			board._touch())
		mode_o.tooltip_text = "Mode de raisonnement de l'IA dans cette zone"
		row2.add_child(mode_o)
		tools_c = CheckBox.new()
		tools_c.text = "Outils"
		tools_c.button_pressed = bool(d.get("tools", true))
		tools_c.tooltip_text = "Laisse l'IA lire tes fichiers (lecture seule, dossier personnel) et calculer"
		tools_c.toggled.connect(func(v: bool):
			d["tools"] = v
			board._touch())
		row2.add_child(tools_c)
		who2 = OptionButton.new()
		for i in board.U.count():
			who2.add_item("vs " + str(board.U.get_u(i).name), i)
		who2.select(int(d.get("ai2", (int(d.ai) + 1) % board.U.count())))
		who2.tooltip_text = "Adversaire pour le débat"
		who2.item_selected.connect(func(i: int):
			d["ai2"] = i
			board._touch())
		row2.add_child(who2)
		info = Label.new()
		info.add_theme_font_size_override("font_size", 11)
		info.add_theme_color_override("font_color", board.T.DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(info)
		if d.kind == "image":
			pic = PicBox.new()
			pic.board = board
			pic.d = d
			v.add_child(pic)
		logv = RichTextLabel.new()
		logv.bbcode_enabled = true
		logv.scroll_following = true
		logv.selection_enabled = true
		logv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		logv.custom_minimum_size.y = 60
		v.add_child(logv)
		input_row = HBoxContainer.new()
		v.add_child(input_row)
		if d.kind == "image":
			an = Button.new()
			an.text = "Analyser"
			an.tooltip_text = "Lance l'IA vision sur l'image"
			an.pressed.connect(func(): board.send(str(d.id), "Analyse cette image : décris ce que tu vois en détail, puis ce qu'on peut en tirer."))
			input_row.add_child(an)
		launch = Button.new()
		launch.text = "Lancer"
		launch.tooltip_text = "Lance l'IA à partir des zones liées (selon le type de chaque fil)"
		launch.pressed.connect(func(): board.run_from_sources(str(d.id)))
		input_row.add_child(launch)
		deb = Button.new()
		deb.text = "Débat"
		deb.tooltip_text = "Fait débattre deux assistants (rappuie pour arrêter)"
		deb.pressed.connect(func(): board.debate(str(d.id)))
		input_row.add_child(deb)
		input = LineEdit.new()
		input.placeholder_text = "Parle dans cette zone…"
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		input.text_submitted.connect(func(t: String):
			input.text = ""
			board.send(str(d.id), t))
		input_row.add_child(input)
		var sb := Button.new()
		sb.text = "➤"
		sb.pressed.connect(func():
			var t := input.text
			input.text = ""
			board.send(str(d.id), t))
		input_row.add_child(sb)

	func refresh() -> void:
		var col: Color = board.U.color(int(d.ai))
		var sbx := StyleBoxFlat.new()
		sbx.bg_color = board.T.CARD
		sbx.border_color = col if not d.closed else col.darkened(0.2)
		sbx.set_border_width_all(2)
		sbx.content_margin_left = 8
		sbx.content_margin_right = 8
		sbx.content_margin_top = 6
		sbx.content_margin_bottom = 18  # poignée de redimensionnement
		if d.closed:
			sbx.bg_color = board.T.CARD.darkened(0.15)
		add_theme_stylebox_override("panel", sbx)
		var busy: bool = board.reqs.has(d.id)
		close_b.text = "Rouvrir" if d.closed else "Clôturer"
		close_b.disabled = busy
		input_row.visible = not d.closed
		input.editable = not busy
		chip.add_theme_color_override("font_color", col)
		var stale: bool = board.is_stale(d)
		var debating: bool = board._deb.has(d.id)
		launch.visible = board.has_sources(str(d.id))
		launch.text = "Relancer" if stale else "Lancer"
		launch.disabled = busy
		deb.text = "Stop" if debating else "Débat"
		deb.disabled = busy and not debating
		who2.disabled = busy
		who2.visible = d.kind != "image"
		tools_c.visible = d.kind != "image"
		deb.visible = d.kind != "image"
		if stale:
			sbx.border_color = board.T.WARN
			add_theme_stylebox_override("panel", sbx)
		mode_o.disabled = busy
		if pic != null:
			pic.queue_redraw()
		if an != null:
			an.visible = board.imgs.has(d.id)
			an.disabled = busy
		var src: PackedStringArray = []
		for l in board.links:
			if l.to == d.id:
				var s: Dictionary = board._zone(str(l.from))
				if not s.is_empty():
					src.append(str(s.title))
		info.visible = not src.is_empty() or stale
		info.text = ("⚠ sources modifiées depuis la dernière réponse. " if stale else "") + ("↤ nourrie par : " + ", ".join(src) if not src.is_empty() else "")
		render()
		queue_redraw()

	func render() -> void:
		var accent: String = board.U.color(int(d.ai)).to_html(false)
		var out: PackedStringArray = []
		for m in d.msgs:
			if m.role == "user":
				out.append("[color=#98a2b0]Toi :[/color] " + board.MD.esc(str(m.content)))
			else:
				var pre := ""
				if m.has("ai"):
					pre = "[color=#%s][b]%s :[/b][/color] " % [board.U.color(int(m.ai)).to_html(false), str(board.U.get_u(int(m.ai)).name)]
				out.append(pre + board.MD.to_bbcode(str(m.content), accent))
		if d.closed:
			out.append("[color=#%s][b]— Synthèse —[/b][/color]\n%s" % [accent, board.MD.to_bbcode(str(d.summary), accent)])
		logv.text = "\n\n".join(out)

	func _draw() -> void:
		var col: Color = board.U.color(int(d.ai))
		for i in 3:
			draw_rect(Rect2(size.x - 6 - i * 4, size.y - 6, 2, 2), Color(col, 0.8))
			draw_rect(Rect2(size.x - 6, size.y - 6 - i * 4, 2, 2), Color(col, 0.8))

	func set_lod(v: bool) -> void:
		lod = v
		var vb: Node = title_e.get_parent().get_parent()
		for c in vb.get_children():
			if c != title_e.get_parent():
				c.visible = not v if c != info else (not v and info.text != "")
		for c in title_e.get_parent().get_children():
			if c != title_e:
				c.visible = not v
		title_e.editable = not v
		title_e.mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP
		title_e.add_theme_font_size_override("font_size", clampi(int(18.0 / maxf(board.zoom, 0.12)), 16, 120) if v else 16)
		if not v:
			refresh()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				move_to_front()
				if lod and e.double_click:
					board.focus_zone(str(d.id))
					return
				var wm: Vector2 = board.c2w(board.canvas.get_local_mouse_position())
				if not lod and e.position.x > size.x - 22 and e.position.y > size.y - 22:
					mode = "resize"
					grab = wm - size
				elif lod or e.position.y < 40:
					mode = "drag"
					grab = wm - position
				else:
					mode = ""
			else:
				if mode != "":
					board._touch()
				mode = ""
		elif e is InputEventMouseMotion and mode != "":
			var wm2: Vector2 = board.c2w(board.canvas.get_local_mouse_position())
			if mode == "drag":
				position = wm2 - grab
				d.x = position.x
				d.y = position.y
			else:
				size = (wm2 - grab).max(custom_minimum_size)
				d.w = size.x
				d.h = size.y
			board.canvas.queue_redraw()
			queue_redraw()


## Tableau image (cadre pixel art) : clic pour choisir une image, ou dépôt d'un fichier sur la zone.
class PicBox extends Control:
	var board: Node
	var d: Dictionary

	func _init() -> void:
		custom_minimum_size = Vector2(0, 130)
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		size_flags_stretch_ratio = 1.6
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _draw() -> void:
		var col: Color = board.U.color(int(d.ai))
		var wood := Color("7a5636")
		draw_rect(Rect2(Vector2.ZERO, size), Color("2e1f13"))
		draw_rect(Rect2(Vector2(3, 3), size - Vector2(6, 6)), wood)
		draw_rect(Rect2(Vector2(10, 10), size - Vector2(20, 20)), Color("0b0e13"))
		var inner := Rect2(Vector2(12, 12), size - Vector2(24, 24))
		if board.imgs.has(d.id):
			var tex: Texture2D = board.imgs[d.id].tex
			var k := minf(inner.size.x / tex.get_width(), inner.size.y / tex.get_height())
			var sz := Vector2(tex.get_width(), tex.get_height()) * k
			draw_texture_rect(tex, Rect2(inner.get_center() - sz * 0.5, sz), false)
		else:
			for i in 8:
				draw_rect(Rect2(inner.position.x + i * (inner.size.x / 8.0), inner.position.y, 6, 2), Color(col, 0.7))
				draw_rect(Rect2(inner.position.x + i * (inner.size.x / 8.0), inner.end.y - 2, 6, 2), Color(col, 0.7))
			draw_string(get_theme_default_font(), Vector2(inner.position.x, inner.get_center().y + 4), "Clique ou dépose une image ici",
				HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, 13, Color(col, 0.9))
		for c in [Vector2(6, 6), Vector2(size.x - 8, 6), Vector2(6, size.y - 8), Vector2(size.x - 8, size.y - 8)]:
			draw_rect(Rect2(c, Vector2(3, 3)), Color("c9a227"))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
			board.pick_image(str(d.id))


## Cadre coloré pour regrouper des zones par thème : le déplacer emporte les zones qu'il contient.
class Frame extends Control:
	var board: Node
	var d: Dictionary
	var bar: Control
	var title_e: LineEdit
	var tools: HBoxContainer
	var handle: Control
	var mode := ""
	var grab := Vector2.ZERO
	var held: Array = []  # zones emportées [{d, node, off}]
	var lod := false

	func build_ui() -> void:
		position = Vector2(float(d.x), float(d.y))
		size = Vector2(float(d.w), float(d.h))
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar = Control.new()
		bar.mouse_filter = Control.MOUSE_FILTER_STOP
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
		bar.offset_bottom = 38
		bar.gui_input.connect(_bar_input)
		add_child(bar)
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 6
		h.offset_right = -6
		h.mouse_filter = Control.MOUSE_FILTER_PASS
		bar.add_child(h)
		title_e = LineEdit.new()
		title_e.text = str(d.title)
		title_e.flat = true
		title_e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_e.text_changed.connect(func(t: String):
			d.title = t
			board._touch())
		h.add_child(title_e)
		tools = HBoxContainer.new()
		h.add_child(tools)
		var cb := Button.new()
		cb.text = "◼"
		cb.tooltip_text = "Changer la couleur"
		cb.pressed.connect(func():
			var i: int = board.FRAME_COLORS.find(str(d.color))
			d.color = board.FRAME_COLORS[(i + 1) % board.FRAME_COLORS.size()]
			queue_redraw()
			board._touch())
		tools.add_child(cb)
		var xb := Button.new()
		xb.text = "✕"
		xb.tooltip_text = "Supprimer le cadre (les zones restent)"
		xb.pressed.connect(func(): board.delete_frame(str(d.id)))
		tools.add_child(xb)
		handle = Control.new()
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		handle.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		handle.offset_left = -26
		handle.offset_top = -26
		handle.gui_input.connect(_handle_input)
		add_child(handle)

	func set_lod(v: bool) -> void:
		lod = v
		tools.visible = not v
		title_e.editable = not v
		title_e.mouse_filter = Control.MOUSE_FILTER_IGNORE if v else Control.MOUSE_FILTER_STOP
		title_e.add_theme_font_size_override("font_size", clampi(int(22.0 / maxf(board.zoom, 0.12)), 16, 140) if v else 16)
		handle.visible = not v
		queue_redraw()

	func _draw() -> void:
		var col := Color(str(d.color))
		draw_rect(Rect2(Vector2.ZERO, size), Color(col, 0.07))
		draw_rect(Rect2(Vector2.ZERO, size), Color(col, 0.55), false, 2.0)
		draw_rect(Rect2(0, 0, size.x, 38), Color(col, 0.18))
		for i in 3:
			draw_rect(Rect2(size.x - 8 - i * 5, size.y - 5, 2, 2), Color(col, 0.9))
			draw_rect(Rect2(size.x - 5, size.y - 8 - i * 5, 2, 2), Color(col, 0.9))

	func _wm() -> Vector2:
		return board.c2w(board.canvas.get_local_mouse_position())

	func _bar_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				mode = "drag"
				grab = _wm() - position
				held.clear()
				var r := Rect2(position, size)
				for z in board.zones:
					if r.has_point(Vector2(float(z.x) + float(z.w) * 0.5, float(z.y) + float(z.h) * 0.5)) and board.nodes.has(z.id):
						held.append({"d": z, "node": board.nodes[z.id], "off": Vector2(float(z.x), float(z.y)) - position})
			else:
				mode = ""
				board._touch()
		elif e is InputEventMouseMotion and mode == "drag":
			position = _wm() - grab
			d.x = position.x
			d.y = position.y
			for hz in held:
				var np: Vector2 = position + hz.off
				hz.d.x = np.x
				hz.d.y = np.y
				(hz.node as Control).position = np
			board.canvas.queue_redraw()

	func _handle_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				mode = "resize"
				grab = _wm() - size
			else:
				mode = ""
				board._touch()
		elif e is InputEventMouseMotion and mode == "resize":
			size = (_wm() - grab).max(Vector2(200, 120))
			d.w = size.x
			d.h = size.y
			queue_redraw()
