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
const Surface := preload("res://ui/draw/surface.gd")
const Bars := preload("res://ui/draw/bars.gd")
const Geom := preload("res://ui/draw/geom.gd")
const Assist := preload("res://ui/draw/assist.gd")
const Chat := preload("res://ui/draw/chat.gd")
const ChatBar := preload("res://ui/draw/chatbar.gd")
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
const MAX_HISTORY := 14
const CTX_CAP := 1500

var scene  # modèle de scène (ui/draw/scene.gd) : zones, cadres, flèches, formes dans une seule liste ordonnée
var canvas: Control  # surface (ui/draw/surface.gd) : vue, rendu, outils
var world: Control  # hôte des zones (suit pan/zoom)
var bars: Control
var nodes := {}  # id -> Zone
var imgs := {}  # id d'élément image / de zone image -> {b64, tex}
var _img_miss := {}
var menu: PopupMenu
var view_menu: PopupMenu
var plans: Array = []  # [{id, name}]
var plan_id := ""
var search_e: LineEdit
var help_btn: Button
var assist
var chat_bar
var help_panel: PanelContainer
var help_txt: RichTextLabel
var _rename: ConfirmationDialog
var _rename_e: LineEdit
var _deb := {}  # zones en débat
var reqs := {}  # id -> Ollama.Req en cours
var _dirty := false
var _save_t := 0.0
var _links: Array = []
var _links_rev := -1


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
	menu.add_item("Cadre (regrouper des éléments)", 100)
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
	fit.tooltip_text = "Tout voir, rechercher, exporter, plans (molette : défiler, Ctrl+molette : zoom, Espace+glisser : déplacer)"
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
	canvas = Surface.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas.custom_minimum_size = Vector2(100, 300)
	canvas.set_meta("k_nolint", true)
	_outer.add_child(canvas)
	canvas.setup(self)
	scene = canvas.scene
	world = canvas.world
	scene.on_clone = _on_clone
	scene.zone_added.connect(_spawn)
	scene.zone_removed.connect(_on_zone_removed)
	scene.msg_removed.connect(_on_zone_removed)  # même nettoyage : annule la requête d'un nœud de chat supprimé
	bars = Bars.new()
	canvas.add_child(bars)
	bars.setup(canvas)
	search_e = LineEdit.new()
	search_e.placeholder_text = "Rechercher dans le plan… (Entrée : aller à la 1re zone)"
	search_e.visible = false
	search_e.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	search_e.offset_left = -170
	search_e.offset_right = 170
	search_e.offset_top = -56
	search_e.offset_bottom = -12
	search_e.grow_vertical = Control.GROW_DIRECTION_BEGIN
	search_e.text_changed.connect(_apply_search)
	search_e.text_submitted.connect(func(_t: String): _goto_first_match())
	canvas.add_child(search_e)
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
	assist = Assist.new()
	canvas.add_child(assist)
	assist.setup(self)
	chat_bar = ChatBar.new()
	canvas.add_child(chat_bar)
	chat_bar.setup(self)
	var ai_btn := Button.new()
	ai_btn.text = "✨"
	ai_btn.tooltip_text = "Parler à l'IA (Entrée : chat en nœuds · Ctrl+Entrée : éditer le graphe)"
	ai_btn.custom_minimum_size = Vector2(44, 44)
	ai_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ai_btn.offset_left = -108
	ai_btn.offset_right = -64
	ai_btn.offset_top = 10
	ai_btn.offset_bottom = 54
	ai_btn.pressed.connect(func(): open_assist("chat"))
	canvas.add_child(ai_btn)
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
	if scene.els.is_empty():
		_add_zone("problem", "De quoi allons-nous parler aujourd'hui ?")
	get_window().files_dropped.connect(_on_drop)
	_refresh_all()


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
	if canvas != null:
		canvas.edit_commit()
	if _dirty:
		_save()


## Les zones (éléments de type « zone » de la scène), dans l'ordre des calques.
## Entrée sur le tableau : ouvre la barre de saisie (mode "chat" : nœuds de conversation ; "graph" : édition du graphe).
func open_assist(mode := "chat") -> void:
	if assist != null:
		assist.open(mode)


func zones() -> Array:
	return scene.zones()


## Fils entre zones : flèches liées aux deux extrémités et portant un type (nourrit/critique/compare/fusionne).
func links() -> Array:
	if _links_rev == scene.rev:
		return _links
	_links_rev = scene.rev
	_links = []
	var seen := {}
	for a in scene.arrows():
		var t := str(a.get("link", ""))
		if t == "":
			continue
		var fa: Dictionary = _zone(str(a.start))
		var fb: Dictionary = _zone(str(a.end))
		if fa.is_empty() or fb.is_empty() or fa.id == fb.id or seen.has(str(a.start) + ">" + str(a.end)):
			continue
		seen[str(a.start) + ">" + str(a.end)] = true
		_links.append({"from": str(a.start), "to": str(a.end), "type": t if LINKS.has(t) else "feed", "arrow": str(a.id)})
	return _links


func _add_zone(kind := "note", title := "", at := Vector2.INF) -> Dictionary:
	var K_: Dictionary = KINDS[kind]
	var c := at
	if c == Vector2.INF:
		c = canvas.c2w(canvas.size * 0.5) - Vector2(float(K_.w) * 0.5, float(K_.h) * 0.4) if canvas != null and canvas.size.x > 10 else Vector2(40, 40)
		c += Vector2(randf_range(-30, 30), randf_range(-30, 30))
	var d := {"id": scene.uid("z"), "type": "zone", "x": c.x, "y": c.y, "w": K_.w, "h": K_.h, "angle": 0.0, "locked": false, "group": "", "opacity": 100.0,
			"title": title if title != "" else str(K_.title), "ai": int(ctx.active), "kind": kind, "mode": K_.mode,
			"msgs": [], "summary": "", "closed": false, "img": ""}
	if kind == "image":
		var vi := _vision_ai()
		if vi >= 0:
			d.ai = vi
	scene.add(d)
	scene.select([d.id])
	scene.commit()
	canvas.tools.after_create()
	_refresh_all()
	_touch()
	return d


## Assistant à vision (Brume par défaut) ; -1 si aucun modèle vision n'est installé.
func _vision_ai() -> int:
	for i in U.count():
		if U.get_u(i).get("vision", false):
			return i
	return -1


func _norm_zone(d: Dictionary) -> void:
	d["closed"] = bool(d.get("closed", false))
	d["kind"] = str(d.get("kind", "note")) if KINDS.has(str(d.get("kind", "note"))) else "note"
	d["mode"] = str(d.get("mode", "libre")) if MODES.has(str(d.get("mode", "libre"))) else "libre"
	d["img"] = str(d.get("img", ""))
	d["msgs"] = d.get("msgs", [])
	d["summary"] = str(d.get("summary", ""))
	d["title"] = str(d.get("title", "Zone"))
	d["ai"] = clampi(int(d.get("ai", 0)), 0, maxi(U.count() - 1, 0))


func _spawn(d: Dictionary) -> void:
	if nodes.has(d.id) or world == null:
		return
	_norm_zone(d)
	var z := Zone.new()
	z.board = self
	z.d = d
	world.add_child(z)
	nodes[d.id] = z
	_load_img(str(d.id), str(d.get("img", "")))
	z.build_ui()
	z.refresh()
	sync_order()


func _on_zone_removed(id: String) -> void:
	if reqs.has(id):
		if reqs[id] != null:
			(reqs[id] as Ollama.Req).cancel()
		reqs.erase(id)
	_deb.erase(id)
	if nodes.has(id):
		(nodes[id] as Node).queue_free()
		nodes.erase(id)


func _zone(id: String) -> Dictionary:
	var e: Dictionary = scene.by_id.get(id, {}) if scene != null else {}
	return e if str(e.get("type", "")) == "zone" else {}


func _touch() -> void:
	_dirty = true
	_save_t = 0.0
	if scene != null:
		scene.mark_links()
		canvas.redraw()


func touch() -> void:
	_touch()


func _refresh_all() -> void:
	if help_panel != null and help_panel.visible:
		_fill_help()
	for id in nodes:
		(nodes[id] as Zone).refresh()
	if scene != null:
		scene.mark_links()
		canvas.redraw()


## Recopie la géométrie des éléments « zone » sur leurs nœuds (déplacement, redimensionnement, annuler…).
func sync_zones(ids: Dictionary) -> void:
	var list: Array = ids.keys() if not ids.is_empty() else nodes.keys()
	for id in list:
		if not nodes.has(id):
			continue
		var d := _zone(str(id))
		if d.is_empty():
			continue
		var z: Control = nodes[id]
		z.position = Vector2(float(d.x), float(d.y))
		z.size = Vector2(float(d.w), float(d.h)).max(z.custom_minimum_size)
		z.modulate.a = float(d.get("opacity", 100.0)) / 100.0 * float(z.get_meta("sdim", 1.0))


func sync_order() -> void:
	var i := 0
	for d in zones():
		if nodes.has(d.id):
			world.move_child(nodes[d.id], i)
			i += 1


func links_changed() -> void:
	_refresh_all()
	_touch()


func on_lod(_v: bool) -> void:
	pass


func zone_color(d: Dictionary) -> Color:
	return U.color(int(d.get("ai", 0)))


func link_style(a: Dictionary) -> Dictionary:
	var s := _zone(str(a.get("start", "")))
	var t := str(a.get("link", "feed"))
	return {"color": U.color(int(s.get("ai", 0))) if not s.is_empty() else T.OK, "dashed": not bool(s.get("closed", false)),
			"name": str(LINKS[t if LINKS.has(t) else "feed"][0])}


func next_frame_color() -> String:
	var n := 0
	for e in scene.els:
		if e.type == "frame":
			n += 1
	return str(FRAME_COLORS[n % FRAME_COLORS.size()])


func _on_clone(old: String, new: String, el: Dictionary) -> void:
	var key := "img" if el.type == "zone" else ("file" if el.type == "image" else "")
	if key == "" or str(el.get(key, "")) == "":
		return
	var src := str(el[key])
	if FileAccess.file_exists(src):
		var dst := IMG_DIR + new + ".jpg"
		DirAccess.make_dir_recursive_absolute(IMG_DIR)
		DirAccess.copy_absolute(src, dst)
		el[key] = dst


# ------------------------------------------------------------------ Navigation (zoom / vue)

func w2c(v: Vector2) -> Vector2:
	return canvas.w2c(v)


func c2w(v: Vector2) -> Vector2:
	return canvas.c2w(v)


## Cadre tout le plan dans la vue.
func fit_all() -> void:
	canvas.fit_all()


func focus_zone(id: String) -> void:
	var d := _zone(id)
	if d.is_empty():
		return
	canvas.center_on(Geom.center(d), 1.0)


func _input(e: InputEvent) -> void:
	if canvas == null or not is_visible_in_tree():
		return
	if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		# Ctrl+molette : zoom partout (même sur une zone) ; sinon la molette défile le texte ou la vue
		if (e.ctrl_pressed or e.meta_pressed) and Rect2(Vector2.ZERO, canvas.size).has_point(canvas.get_local_mouse_position()):
			canvas.wheel(e)
			get_viewport().set_input_as_handled()
	elif e is InputEventKey and e.keycode == KEY_F and e.pressed and (e.ctrl_pressed or e.meta_pressed):
		_toggle_search()
		get_viewport().set_input_as_handled()
	elif e is InputEventKey and canvas.tools.key(e):
		get_viewport().set_input_as_handled()
	elif e is InputEventMagnifyGesture or e is InputEventPanGesture:
		var cp := canvas.get_local_mouse_position()
		if Rect2(Vector2.ZERO, canvas.size).has_point(cp):
			if e is InputEventMagnifyGesture:
				canvas.zoom_at(cp, e.factor, false)
			else:
				canvas.pan_by(-e.delta * 12.0)
	elif e is InputEventScreenTouch or e is InputEventScreenDrag:
		canvas.touch_event(e)


# ------------------------------------------------------------------ Liens

func cycle_link(a: Dictionary) -> void:
	var t := str(a.get("link", "feed"))
	a["link"] = LINK_ORDER[(LINK_ORDER.find(t) + 1) % LINK_ORDER.size()]
	scene.mark(a)
	scene.commit()
	links_changed()


func zone_at(world_pos: Vector2, except := "") -> String:
	var zs := zones()
	for i in range(zs.size() - 1, -1, -1):
		var d: Dictionary = zs[i]
		if d.id != except and Rect2(float(d.x), float(d.y), float(d.w), float(d.h)).has_point(world_pos):
			return d.id
	return ""


func delete_zone(id: String) -> void:
	if _zone(id).is_empty():
		return
	scene.remove([id])
	scene.commit()
	links_changed()
	canvas.sel_changed.emit()


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
	for l in links():
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
	for l in links():
		if l.to == id:
			var s := _zone(str(l.from))
			if not s.is_empty():
				parts.append(str(_src_body(s).hash()))
	return ",".join(parts)


func is_stale(d: Dictionary) -> bool:
	return not (d.msgs as Array).is_empty() and str(d.get("fed_sig", "")) != incoming_sig(str(d.id))


func has_sources(id: String) -> bool:
	for l in links():
		if l.to == id:
			return true
	return false


## Premier message automatique d'une zone d'après le type de ses fils entrants.
func run_from_sources(id: String) -> void:
	var d := _zone(id)
	var kinds := {}
	for l in links():
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
	if str(d.get("model", "")) != "":  # un nœud de chat peut imposer son modèle
		return str(d.model)
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
	d["sug"] = []
	await _stream(d, _history(d, d.msgs.size() - 1), func(t: String): d.msgs[d.msgs.size() - 1].content = t)
	if is_instance_valid(self) and not _zone(id).is_empty() and d.kind != "image":
		_suggest(d)


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


# ------------------------------------------------------------------ Chat en nœuds

## Aspect d'un nœud de chat : couleur et nom (toi / l'assistant).
func msg_style(el: Dictionary) -> Dictionary:
	if str(el.get("role", "user")) == "user":
		return {"color": T.DIM.lightened(0.15), "name": "Toi"}
	var ai := int(el.get("ai", 0))
	return {"color": U.color(ai), "name": str(U.get_u(ai).name)}


func _ai_name(i: int) -> String:
	return str(U.get_u(i).name)


func _chat_system(ai: int) -> String:
	return U.system_prompt(ai, false) + "\nTu discutes dans un arbre de conversation : chaque message est un nœud du plan et tu ne vois que le chemin qui mène au dernier message. Sois concis."


func _view_spot() -> Vector2:
	if canvas != null and canvas.size.x > 10.0:
		return canvas.c2w(canvas.size * 0.5) - Vector2(Chat.W * 0.5, 120.0)
	return Vector2(40, 40)


func _chat_focus(el: Dictionary) -> void:
	scene.select([el.id])
	canvas.sel_changed.emit()
	canvas.ensure_visible(Rect2(float(el.x), float(el.y), float(el.w), minf(float(el.h), 320.0)))
	_touch()


## J'écris : un nœud « utilisateur » apparaît (réponse au nœud parent_id, ou nouvelle racine), puis l'IA répond en
## streaming dans un nœud enfant. Retourne le nœud de l'IA (la coroutine se termine quand la réponse est finie).
func chat_say(text: String, parent_id := "", ai := -1, fork := false) -> Dictionary:
	text = text.strip_edges()
	if text == "":
		return {}
	if ai < 0:
		ai = int(ctx.active)
	var u: Dictionary = Chat.add_msg(scene, "user", text, parent_id, ai, fork, _view_spot())
	var a: Dictionary = Chat.add_msg(scene, "assistant", "", str(u.id), ai)
	_chat_focus(a)
	await _chat_answer(a)
	return a


## Régénérer : nouvelle réponse (nouveau frère) au même message ; pour un nœud « utilisateur », une réponse enfant.
func chat_regen(id: String, ai := -1) -> Dictionary:
	var el: Dictionary = scene.get_el(id)
	if not Chat.is_msg(el):
		return {}
	var u: Dictionary = el if str(el.role) == "user" else Chat.parent_of(scene, el)
	if u.is_empty():
		return {}
	if ai < 0:
		ai = int(el.get("ai", ctx.active))
	var a: Dictionary = Chat.add_msg(scene, "assistant", "", str(u.id), ai)
	_chat_focus(a)
	await _chat_answer(a)
	return a


func _chat_answer(a: Dictionary) -> void:
	var id := str(a.id)
	var u: Dictionary = Chat.parent_of(scene, a)
	if u.is_empty():
		return
	var ai := int(a.get("ai", 0))
	a["done"] = false
	a["text"] = ""
	var msgs: Array = Chat.history(scene, str(u.id), _chat_system(ai), ai, _ai_name)
	scene.mark(a)
	var setter := func(t: String):
		if scene.by_id.get(id, {}) != a:  # nœud supprimé (ou annulé) pendant l'écriture
			chat_stop(id)
			return
		a["text"] = t
		scene.mark(a)
		Chat.layout(scene, a)
		_touch()
	await _stream(a, msgs, setter, ai)
	if not is_instance_valid(self) or scene.by_id.get(id, {}) != a:
		return
	if str(a.text).strip_edges() == "":
		a["text"] = "(arrêté)"
	a["done"] = true
	scene.mark(a)
	Chat.layout(scene, a)
	Chat.push_down(scene, a)
	scene.commit()  # toute la demande (nœud utilisateur + réponse) = une étape Ctrl+Z
	canvas.sel_changed.emit()
	_touch()


func chat_stop(id: String) -> void:
	var r = reqs.get(id)
	if r != null:
		(r as Ollama.Req).cancel()
	elif reqs.has(id):
		reqs.erase(id)


func chat_busy(id: String) -> bool:
	return reqs.has(id)


## Ouvre la barre de saisie pour répondre au nœud id (fork : nouvelle branche, placée à droite des réponses existantes).
func chat_reply(id: String, fork := false) -> void:
	if id != "" and Chat.is_msg(scene.get_el(id)):
		scene.select([id])
		canvas.sel_changed.emit()
	if assist != null:
		assist.open("chat")
		assist.fork = fork
		assist._sync_target()


func chat_tidy() -> void:
	var sel: Array = scene.selected().filter(func(e): return Chat.is_msg(e))
	var rs: Array = [Chat.root_of(scene, str(sel[0].id))] if not sel.is_empty() else Chat.roots(scene)
	var moved: Array = []
	for r in rs:
		moved.append_array(Chat.tidy(scene, str(r.id)))
	if not moved.is_empty():
		scene.commit()
		scene.touch()
		_touch()


# ------------------------------------------------------------------ Cartes proposées (pistes)

func suggest_on() -> bool:
	return bool(ctx.store.get_s("lab", "suggest", true))


func _cheap_model() -> String:
	for m in ctx.models:  # triés par taille croissante : le plus léger d'abord
		var n := str(m.name)
		if not ctx.model_is_vision(n) and not U.is_broken(n):
			return n
	return ""


## Après une réponse, demande au plus petit modèle 3 pistes (cartes) pour avancer ; elles s'affichent en boutons sous le chat.
func _suggest(d: Dictionary) -> void:
	if not suggest_on() or d.msgs.size() < 2:
		return
	var id := str(d.id)
	var model := _cheap_model()
	if model == "":
		return
	var last_q := ""
	var last_a := ""
	for i in range(d.msgs.size() - 1, -1, -1):
		if last_a == "" and d.msgs[i].role == "assistant":
			last_a = str(d.msgs[i].content)
		elif last_a != "" and d.msgs[i].role == "user":
			last_q = str(d.msgs[i].content)
			break
	if last_a.strip_edges() == "" or last_a.begins_with("("):
		return
	var sys := "Tu aides à explorer un sujet. Propose 3 cartes (pistes) pour avancer ensuite. Réponds UNIQUEMENT par un tableau JSON de 3 objets {\"titre\": 2 à 4 mots, \"question\": une phrase à poser à une IA pour creuser cette piste, \"type\": un parmi problem, ideas, proscons, decision, note}. Pistes variées (approfondir, comparer, risques, plan d'action…). Aucun autre texte."
	var msgs: Array = [{"role": "system", "content": sys},
		{"role": "user", "content": "Zone : %s\nQuestion : %s\nRéponse : %s" % [str(d.title), last_q.left(400), last_a.left(1200)]}]
	var req: Ollama.Req = ctx.ollama.chat(model, msgs, {"temperature": 0.5, "num_predict": 260}, [], false)
	var res: Array = await ctx.ollama.collect(req)
	if not is_instance_valid(self) or _zone(id).is_empty() or not res[0] or res[3].is_empty():
		return
	var txt := Ollama.strip_think(str(res[3][0].get("message", {}).get("content", "")))
	# les petits modèles renvoient tantôt un tableau, tantôt des objets séparés (parfois en blocs ```json) : on extrait chaque {…}
	var arr: Array = []
	for m in RegEx.create_from_string("\\{[^{}]*\\}").search_all(txt):
		var o = JSON.parse_string(m.get_string())
		if o is Dictionary:
			arr.append(o)
	var out: Array = []
	for it in arr:
		if it is Dictionary and str(it.get("titre", "")).strip_edges() != "" and str(it.get("question", "")).strip_edges() != "":
			var k := str(it.get("type", "note"))
			out.append({"titre": str(it.titre).strip_edges().left(34), "question": str(it.question).strip_edges().left(300), "type": k if KINDS.has(k) and k != "image" else "note"})
	d["sug"] = out.slice(0, 3)
	if nodes.has(id):
		(nodes[id] as Zone).refresh()
	_touch()


## Un fil « nourrit » entre deux zones (flèche liée).
func link_zones(a: String, b: String, type := "feed") -> void:
	var za := _zone(a)
	if za.is_empty() or _zone(b).is_empty():
		return
	var el := {"id": scene.uid("l"), "type": "arrow", "x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0, "stroke": zone_color(za).to_html(false), "strokeWidth": 3.0,
			"arrowType": "round", "start": a, "end": b, "link": type, "endHead": "triangle", "points": [[0.0, 0.0], [10.0, 10.0]]}
	scene._sanitize(el)
	scene.add(el)
	Geom.refresh_arrow(scene, el)
	scene.mark(el)
	links_changed()


## Crée une carte à droite de la zone (liée par un fil) ; si question != "", l'IA y répond tout de suite.
func spawn_card(from_id: String, title: String, question: String, kind := "note") -> void:
	var src := _zone(from_id)
	if src.is_empty():
		return
	var K_: Dictionary = KINDS[kind if KINDS.has(kind) else "note"]
	var pos := Vector2(float(src.x) + float(src.w) + 120.0, float(src.y))
	var tries := 0
	while tries < 12 and _overlaps(pos, Vector2(float(K_.w), float(K_.h))):
		pos.y += float(K_.h) + 30.0
		tries += 1
	var d := _add_zone(kind if KINDS.has(kind) else "note", title, pos)
	d.ai = int(src.ai)
	d["mode"] = str(src.get("mode", "libre")) if kind == "note" else d.mode
	link_zones(from_id, str(d.id))
	scene.commit()
	if nodes.has(d.id):
		(nodes[d.id] as Zone).refresh()
	if question.strip_edges() != "":
		send(str(d.id), question)


func _overlaps(pos: Vector2, sz: Vector2) -> bool:
	var r := Rect2(pos, sz).grow(10.0)
	for z in zones():
		if r.intersects(Rect2(float(z.x), float(z.y), float(z.w), float(z.h))):
			return true
	return false


## Pose la question dans une NOUVELLE carte liée (la réponse y arrive).
func ask_in_card(from_id: String, question: String) -> void:
	question = question.strip_edges()
	if question == "":
		return
	var t := question.left(30) + ("…" if question.length() > 30 else "")
	spawn_card(from_id, t, question, "note")


# ------------------------------------------------------------------ Images

func _load_img(id: String, path: String) -> void:
	if path == "" or _img_miss.has(path):
		return
	if not FileAccess.file_exists(path):
		_img_miss[path] = true
		return
	var bytes := FileAccess.get_file_as_bytes(path)
	var im := Image.new()
	if im.load_jpg_from_buffer(bytes) != OK:
		_img_miss[path] = true
		return
	imgs[id] = {"b64": Marshalls.raw_to_base64(bytes), "tex": ImageTexture.create_from_image(im)}


## Texture d'un élément « image » (chargée à la demande).
func image_tex(el: Dictionary) -> Texture2D:
	var id := str(el.id)
	if not imgs.has(id):
		_load_img(id, str(el.get("file", "")))
	return imgs[id].tex if imgs.has(id) else null


func set_image(id: String, path: String) -> bool:
	var d := _zone(id)
	if d.is_empty():
		return false
	var r := Attach.read(path)
	if r.kind != "image":
		ctx.notify("%s : image attendue (png, jpg, webp…)" % path.get_file(), "error")
		return false
	DirAccess.make_dir_recursive_absolute(IMG_DIR)
	var file: String = IMG_DIR + id + ".jpg"
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


## Crée un élément image (jpg dans user://board_img/) à partir d'octets jpg.
func _image_element(bytes: PackedByteArray, at: Vector2) -> void:
	var im := Image.new()
	if im.load_jpg_from_buffer(bytes) != OK:
		return
	var id: String = scene.uid("e")
	DirAccess.make_dir_recursive_absolute(IMG_DIR)
	var file: String = IMG_DIR + id + ".jpg"
	var f := FileAccess.open(file, FileAccess.WRITE)
	if f == null:
		return
	f.store_buffer(bytes)
	f.close()
	var k := minf(360.0 / maxf(im.get_width(), im.get_height()), 1.0)
	var el: Dictionary = scene.make("image", at.x - im.get_width() * k * 0.5, at.y - im.get_height() * k * 0.5)
	el.id = id
	el.w = im.get_width() * k
	el.h = im.get_height() * k
	el.file = file
	el.stroke = "9ca3af"
	scene.add(el)
	scene.select([id])
	scene.commit()
	canvas.tools.after_create()
	_touch()


func add_image_file(path: String, at: Vector2) -> void:
	var r := Attach.read(path)
	if r.kind != "image":
		ctx.notify("%s : image attendue (png, jpg, webp…)" % path.get_file(), "error")
		return
	_image_element(Marshalls.base64_to_raw(str(r.b64)), at)


func add_image_from_image(im: Image, at: Vector2) -> void:
	if im != null and not im.is_empty():
		_image_element(im.save_jpg_to_buffer(0.9), at)


func add_image_dialog() -> void:
	var fp: Control = K.FilePicker.new()
	fp.files_selected.connect(func(paths: PackedStringArray):
		if not paths.is_empty():
			add_image_file(paths[0], canvas.c2w(canvas.size * 0.5)))
	fp.open_in(router, OS.get_environment("HOME"))


## Dépôt d'un fichier sur le plan : sur une zone image -> remplace ; ailleurs -> crée un élément image.
func _on_drop(files: PackedStringArray) -> void:
	if not is_visible_in_tree() or canvas == null:
		return
	var cp := canvas.get_local_mouse_position()
	var wp := c2w(cp)
	for path in files:
		if str(path).get_extension().to_lower() not in Attach.IMG_EXTS:
			continue
		var d := _zone(zone_at(wp))
		if not d.is_empty() and d.kind == "image":
			set_image(str(d.id), path)
		else:
			add_image_file(path, wp)
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
	scene.clear()  # émet zone_removed pour chaque zone : les nœuds sont libérés
	for id in nodes.keys():
		(nodes[id] as Node).queue_free()
	nodes.clear()
	imgs.clear()
	_img_miss.clear()


func switch_plan(id: String) -> void:
	if id == plan_id:
		return
	canvas.edit_commit()
	_save()
	_clear_nodes()
	plan_id = id
	_save_index()
	canvas.set_view(Vector2(24, 24), 1.0)
	_load()
	if scene.els.is_empty():
		_add_zone("problem", "De quoi allons-nous parler aujourd'hui ?")
	_refresh_all()


func _new_plan() -> void:
	var id := "p%d" % Time.get_ticks_msec()
	plans.append({"id": id, "name": "Plan %d" % (plans.size() + 1)})
	canvas.edit_commit()
	_save()
	_clear_nodes()
	plan_id = id
	_save_index()
	scene.reset_history()
	canvas.set_view(Vector2(24, 24), 1.0)
	_add_zone("problem", "De quoi allons-nous parler ?")
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
	for d in zones():
		if str(d.get("img", "")) != "":
			DirAccess.remove_absolute(str(d.img))
	for e in scene.els:
		if e.type == "image" and str(e.get("file", "")) != "":
			DirAccess.remove_absolute(str(e.file))
	DirAccess.remove_absolute(_plan_file(old))
	plans = plans.filter(func(e): return e.id != old)
	_clear_nodes()
	plan_id = next
	_save_index()
	_load()
	_refresh_all()


func _build_view_menu() -> void:
	view_menu.clear()
	view_menu.add_item("Tout voir", 0)
	view_menu.add_item("Rechercher (Ctrl+F)", 2)
	view_menu.add_item("Exporter en Markdown", 1)
	view_menu.add_check_item("Pistes de cartes après chaque réponse", 6)
	view_menu.set_item_checked(view_menu.get_item_index(6), suggest_on())
	view_menu.add_item("Exporter en PNG (sélection ou tout)", 6)
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
		6:
			ctx.store.set_s("lab", "suggest", not suggest_on())
			ctx.store.save_cfg()
		6:
			export_png()
		_:
			if i >= 1000 and i - 1000 < plans.size():
				switch_plan(str(plans[i - 1000].id))


# ------------------------------------------------------------------ Cadres

func _add_frame() -> void:
	var c := c2w(canvas.size * 0.5) - Vector2(240, 170) if canvas.size.x > 10 else Vector2(0, 0)
	var f: Dictionary = scene.make("frame", c.x, c.y)
	f.w = 480.0
	f.h = 340.0
	f.name = "Thème"
	f.stroke = next_frame_color()
	scene.add(f, 0)  # derrière tout le reste
	scene.select([f.id])
	scene.commit()
	canvas.tools.after_create()
	_touch()


# ------------------------------------------------------------------ Aide (fils)

func _fill_help() -> void:
	var acc := T.OK.to_html(false)
	var out: PackedStringArray = []
	out.append("[b][color=#%s]Comment marchent les fils[/color][/b]" % acc)
	out.append("Un fil envoie ce qu'une zone a conclu vers une autre. Texte envoyé : la [b]synthèse[/b] si la zone de départ est clôturée, sinon la fin de sa discussion.\n")
	out.append("[b]Clic sur l'étiquette[/b] du fil = change son type · [b]clic droit[/b] sur l'étiquette = le supprime. Un fil est une flèche liée aux deux zones : outil [b]Flèche (A)[/b] de l'une à l'autre, ou le rond ● d'une zone sélectionnée.\n")
	out.append("[color=#%s]■ nourrit[/color] : l'arrivée s'appuie sur la source comme base de travail." % acc)
	out.append("[color=#%s]■ critique[/color] : l'arrivée critique la source (faiblesses, risques, oublis)." % acc)
	out.append("[color=#%s]■ compare[/color] : l'arrivée met plusieurs sources en balance, critère par critère. [b]Il faut au moins 2 fils compare vers la même zone.[/b]" % acc)
	out.append("[color=#%s]■ fusionne[/color] : l'arrivée réunit plusieurs sources en une seule proposition et règle leurs contradictions. [b]Au moins 2 fils aussi.[/b]\n" % acc)
	out.append("[b]Entrée[/b] sur le tableau : on discute avec l'IA [b]en nœuds[/b]. Ton message est un nœud, la réponse un nœud enfant ; sélectionne n'importe quel nœud puis Entrée pour y répondre (branche). Le chemin racine → nœud sélectionné est mis en relief et c'est lui que le modèle reçoit.")
	out.append("[b]Ctrl+Entrée[/b] (ou Maj+Entrée, ou le bouton « Éditer le graphe ») : l'[b]assistant du graphe[/b] crée et modifie des schémas ; Ctrl+Z annule tout ce qu'il vient de faire.\n")
	out.append("Ensuite, le bouton [b]Lancer[/b] de la zone d'arrivée démarre l'IA. Si une source change après coup : bordure orange ⚠ et bouton [b]Relancer[/b].\n")
	out.append("[b][color=#%s]Dans ton plan[/color][/b]" % acc)
	if links().is_empty():
		out.append("Aucun fil pour l'instant : tire une flèche d'une zone vers une autre (outil Flèche, ou le rond ● d'une zone sélectionnée).")
	var count := {}
	for l in links():
		var t := str(l.get("type", "feed"))
		count[str(l.to) + "|" + t] = int(count.get(str(l.to) + "|" + t, 0)) + 1
	for l in links():
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
	out.append("\n[b][color=#%s]Dessin (comme Excalidraw)[/color][/b]" % acc)
	out.append("V/1 sélection · H main · R/2 rectangle · D/3 losange · O/4 ellipse · A/5 flèche · L/6 ligne · P/7 crayon · T/8 texte · 9 image · E gomme · F cadre · Q verrou.")
	out.append("Molette : défiler (Maj : côté) · Ctrl+molette : zoom · Espace+glisser : déplacer · Maj+1 : tout voir · Maj+2 : la sélection.")
	out.append("Ctrl+Z / Ctrl+Maj+Z annuler/rétablir · Ctrl+D dupliquer (ou Alt+glisser) · Ctrl+G grouper · Ctrl+] / [ ordre · Ctrl+' grille · Ctrl+Maj+E export PNG.")
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
	scene.search_q = q
	canvas.redraw()
	for d in zones():
		if nodes.has(d.id):
			var dim := 1.0 if _match(d, q) else 0.25
			(nodes[d.id] as Control).set_meta("sdim", dim)
			(nodes[d.id] as Control).modulate = Color(1, 1, 1, dim * float(d.get("opacity", 100.0)) / 100.0)


func _goto_first_match() -> void:
	var q := search_e.text.strip_edges().to_lower()
	for d in zones():
		if q != "" and _match(d, q):
			focus_zone(str(d.id))
			return
	for m in scene.msgs():
		if q != "" and Chat.matches(m, q):
			scene.select([m.id])
			canvas.sel_changed.emit()
			canvas.center_on(Geom.center(m), maxf(canvas.t_zoom, 0.6))
			return


# ------------------------------------------------------------------ Export

func export_markdown() -> void:
	var order := zones().duplicate()
	order.sort_custom(func(a, b): return float(a.x) < float(b.x) if absf(float(a.x) - float(b.x)) > 60.0 else float(a.y) < float(b.y))
	var out: PackedStringArray = ["# Plan de réflexion", ""]
	for d in order:
		var st := "clôturée" if d.closed else "ouverte"
		out.append("## %s" % str(d.title))
		out.append("*%s · %s · %s · %s*" % [KINDS[d.kind].label, MODES[d.mode][0], str(U.get_u(int(d.ai)).name), st])
		var src: PackedStringArray = []
		for l in links():
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
	out.append_array(Chat.markdown(scene, _ai_name))
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


func export_png() -> void:
	canvas.edit_commit()
	var path: String = await canvas.export_png(true)
	if not is_instance_valid(self):
		return
	if path == "":
		ctx.notify("Export PNG impossible (plan vide ou dossier Documents inaccessible).", "error")
	else:
		ctx.notify("Exporté : " + path)


# ------------------------------------------------------------------ Sauvegarde

func _save() -> void:
	_dirty = false
	_save_t = 0.0
	var f := FileAccess.open(_plan_file(), FileAccess.WRITE)
	if f != null:
		var v: Dictionary = scene.to_dict()
		v["pan"] = [canvas.pan.x, canvas.pan.y]
		v["zoom"] = canvas.zoom
		v["grid"] = canvas.grid_on
		f.store_string(JSON.stringify(v))


func _load() -> void:
	var v = null
	if FileAccess.file_exists(_plan_file()):
		v = JSON.parse_string(FileAccess.get_file_as_string(_plan_file()))
	if v is Dictionary:
		scene.load_dict(v, func(ai: int) -> String: return U.color(ai).to_html(false))
		var p = v.get("pan", [24, 24])
		canvas.set_view(Vector2(float(p[0]), float(p[1])), float(v.get("zoom", 1.0)))
		canvas.grid_on = bool(v.get("grid", false))
		_links_rev = -1
	else:
		scene.load_dict({"elements": []})


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
	var chips: HFlowContainer
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
		chips = HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		chips.add_theme_constant_override("v_separation", 4)
		v.add_child(chips)
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
		var cb := Button.new()
		cb.text = "↗"
		cb.tooltip_text = "Poser la question dans une nouvelle carte liée (la réponse arrive dans la carte)"
		cb.pressed.connect(func():
			var t := input.text
			input.text = ""
			board.ask_in_card(str(d.id), t))
		input_row.add_child(cb)
		hook(title_e, true)
		for ch in get_children():
			hook(ch)

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
		for l in board.links():
			if l.to == d.id:
				var s: Dictionary = board._zone(str(l.from))
				if not s.is_empty():
					src.append(str(s.title))
		for c in chips.get_children():
			chips.remove_child(c)
			c.queue_free()
		var sugs: Array = d.get("sug", []) if not d.closed and not busy else []
		chips.visible = not sugs.is_empty()
		for sg in sugs:
			var bt := Button.new()
			bt.text = "＋ " + str(sg.titre)
			bt.tooltip_text = str(sg.question)
			bt.pressed.connect(func():
				d["sug"] = (d.get("sug", []) as Array).filter(func(x): return x != sg)
				board.spawn_card(str(d.id), str(sg.titre), str(sg.question), str(sg.type)))
			chips.add_child(bt)
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

	## Les clics sur le bandeau / les marges sont traités par le moteur de scène (sélection, déplacement) ;
	## un clic dans le contenu agit sur le contenu (et sélectionne la zone).
	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and (e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN or e.button_index == MOUSE_BUTTON_WHEEL_LEFT or e.button_index == MOUSE_BUTTON_WHEEL_RIGHT):
			board.canvas.wheel(e)
			accept_event()
		elif e is InputEventMouseButton or e is InputEventMouseMotion:
			board.canvas.tools.event(e)

	## Branche un enfant : un clic gauche sélectionne la zone (sans bloquer l'enfant) ; avec `drag`, un clic sur une zone
	## non sélectionnée (ou un geste en cours) est confié au moteur de scène pour pouvoir la déplacer par ce point.
	func hook(c: Control, drag := false) -> void:
		if c.has_meta("hooked"):
			return
		c.set_meta("hooked", true)
		c.gui_input.connect(func(e: InputEvent):
			var tl = board.canvas.tools
			if tl.tool != "select":
				return
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				if not board.scene.sel.has(d.id) or board.scene.sel.size() > 1:
					if drag:
						c.accept_event()
						tl.event(e)
					else:
						tl.select_only(str(d.id))
			elif drag and tl.busy() and (e is InputEventMouseMotion or (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT)):
				c.accept_event()
				tl.event(e))
		for ch in c.get_children():
			if ch is Control:
				hook(ch)


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
