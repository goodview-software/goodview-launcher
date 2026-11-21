extends Control
## Barres du plan façon Excalidraw : pilule d'outils centrée en haut, panneau de propriétés à gauche, contrôles de zoom
## et d'historique en bas à gauche. Tout est dessiné par des « Cell » (un seul type de contrôle, icônes vectorielles).

const T := preload("res://ui/theme.gd")
const Geom := preload("res://ui/draw/geom.gd")
const Joystick := preload("res://ui/draw/joystick.gd")
const CELL := 44.0
const COLORS := ["e8ecf1", "ff6b6b", "fbbf24", "4de1b4", "60a5fa", "a78bfa", "ff8fb1", "9ca3af"]
const TOOLS := [["lock", "Verrou : garde l'outil actif (Q)", ""], ["|"], ["hand", "Main : déplacer la vue (H)", "H"], ["select", "Sélection (V ou 1)", "1"],
		["rectangle", "Rectangle (R ou 2)", "2"], ["diamond", "Losange (D ou 3)", "3"], ["ellipse", "Ellipse (O ou 4)", "4"], ["arrow", "Flèche (A ou 5)", "5"],
		["line", "Ligne (L ou 6)", "6"], ["freedraw", "Crayon (P ou 7)", "7"], ["text", "Texte (T ou 8)", "8"], ["image", "Image (9)", "9"],
		["eraser", "Gomme (E ou 0)", "0"], ["|"], ["frame", "Cadre (F)", "F"]]

var S
var toolbar: PanelContainer
var tb_scroll: ScrollContainer
var panel: PanelContainer
var zoombar: PanelContainer
var joy: Control
var zoom_cell: Control
var undo_cell: Control
var redo_cell: Control
var style_btn: Control
var panel_open := false
var _cells: Array = []  # [{c, key, val}]
var _tool_cells := {}
var _secs := {}
var _opacity: HSlider
var _dirty := true


func setup(s) -> void:
	S = s
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_toolbar()
	_build_panel()
	_build_zoombar()
	joy = Joystick.new()
	add_child(joy)
	joy.setup(S)
	S.tool_changed.connect(_mark)
	S.sel_changed.connect(_mark)
	S.view_changed.connect(_zoom_label)
	S.scene.changed.connect(_mark)
	S.resized.connect(layout)
	layout()
	refresh()


func _mark() -> void:
	_dirty = true
	set_process(true)


func _zoom_label() -> void:
	if zoom_cell != null:
		var txt := "%d%%" % int(round(S.zoom * 100.0))
		if (zoom_cell as Cell).a != txt:
			(zoom_cell as Cell).a = txt
			zoom_cell.queue_redraw()


func _process(_dt: float) -> void:
	if _dirty:
		_dirty = false
		refresh()
	set_process(_dirty)


func _box(pad := 6) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = T.CARD
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(pad)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(p)
	return p


func _cell(kind: String, a, b, tip: String, cb: Callable, size := Vector2(CELL, CELL)) -> Cell:
	var c := Cell.new()
	c.kind = kind
	c.a = a
	c.b = b
	c.tooltip_text = tip
	c.custom_minimum_size = size
	c.pressed.connect(cb)
	return c


func _build_toolbar() -> void:
	toolbar = _box(5)
	tb_scroll = ScrollContainer.new()
	tb_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	toolbar.add_child(tb_scroll)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	tb_scroll.add_child(h)
	for t in TOOLS:
		if t[0] == "|":
			var sep := ColorRect.new()
			sep.color = Color(1, 1, 1, 0.12)
			sep.custom_minimum_size = Vector2(2, 28)
			sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			h.add_child(sep)
			continue
		var id: String = t[0]
		var cb: Callable = (func(): S.tools.toggle_lock()) if id == "lock" else (func(): S.tools.set_tool(id))
		var c := _cell("icon", id, str(t[2]), str(t[1]), cb)
		_tool_cells[id] = c
		h.add_child(c)


func layout() -> void:
	if S == null or toolbar == null:
		return
	var cw: float = S.size.x
	var content_w: float = (tb_scroll.get_child(0) as Control).get_combined_minimum_size().x + 14.0
	var w := minf(content_w, cw - 76.0)
	toolbar.size = Vector2(w, CELL + 14.0)
	toolbar.position = Vector2(clampf((cw - w) * 0.5, 8.0, maxf(cw - w - 64.0, 8.0)), 8)
	var narrow := cw < 720.0
	style_btn.visible = narrow
	panel.position = Vector2(8, 70)
	var joy_h := Joystick.SIZE + 8.0
	panel.size = Vector2(212, clampf(S.size.y - 70.0 - 72.0 - joy_h, 120.0, 900.0))
	zoombar.position = Vector2(8, S.size.y - zoombar.size.y - 8)
	# joystick : au-dessus des contrôles de zoom, sans les recouvrir ; masqué si le canevas est trop bas
	joy.visible = S.size.y >= 340.0
	joy.position = Vector2(12, zoombar.position.y - Joystick.SIZE - 8.0)
	S.block_rect = Rect2(joy.position, joy.size) if joy.visible else Rect2()


func _sec(title: String, key: String) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", T.DIM)
	v.add_child(l)
	_secs[key] = v
	return v


func _row(parent: Control, cols := 4) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", 4)
	g.add_theme_constant_override("v_separation", 4)
	parent.add_child(g)
	return g


func _opt(g: Control, kind: String, a, key: String, val, tip: String) -> void:
	var c := _cell(kind, a, val, tip, func(): S.tools.set_style(key, val))
	g.add_child(c)
	_cells.append({"c": c, "key": key, "val": val})


func _build_panel() -> void:
	panel = _box(8)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	var s: VBoxContainer
	s = _sec("Trait", "stroke")
	var g := _row(s)
	for col in COLORS:
		_opt(g, "swatch", col, "stroke", col, "#" + col)
	v.add_child(s)
	s = _sec("Fond", "bg")
	g = _row(s)
	_opt(g, "swatch", "transparent", "bg", "transparent", "Transparent")
	for col in COLORS:
		_opt(g, "swatch", col, "bg", col, "#" + col)
	v.add_child(s)
	s = _sec("Remplissage", "fill")
	g = _row(s)
	for f in [["hachure", "Hachures"], ["croise", "Hachures croisées"], ["plein", "Plein"], ["aucun", "Aucun"]]:
		_opt(g, "fill", f[0], "fillStyle", f[0], f[1])
	v.add_child(s)
	s = _sec("Épaisseur", "width")
	g = _row(s)
	for wv in [1.0, 2.0, 4.0]:
		_opt(g, "linew", wv, "strokeWidth", wv, "Épaisseur %d" % int(wv))
	v.add_child(s)
	s = _sec("Style de trait", "style")
	g = _row(s)
	for st in [["plein", "Plein"], ["tirets", "Tirets"], ["points", "Points"]]:
		_opt(g, "lines", st[0], "strokeStyle", st[0], st[1])
	v.add_child(s)
	s = _sec("Tremblé (sloppiness)", "rough")
	g = _row(s)
	for r in [[0, "Architecte"], [1, "Artiste"], [2, "Caricaturiste"]]:
		_opt(g, "rough", r[0], "roughness", r[0], r[1])
	v.add_child(s)
	s = _sec("Arêtes", "edges")
	g = _row(s)
	_opt(g, "edge", "sharp", "roundness", "sharp", "Vives")
	_opt(g, "edge", "round", "roundness", "round", "Arrondies")
	v.add_child(s)
	s = _sec("Type de flèche", "atype")
	g = _row(s)
	for a in [["sharp", "Droite"], ["round", "Courbe"], ["elbow", "Coudée"]]:
		_opt(g, "atype", a[0], "arrowType", a[0], a[1])
	v.add_child(s)
	s = _sec("Pointe de début", "head0")
	g = _row(s, 5)
	for hd in ["none", "arrow", "triangle", "bar", "dot"]:
		_opt(g, "head", hd, "startHead", hd, "Pointe : " + hd)
	v.add_child(s)
	s = _sec("Pointe de fin", "head1")
	g = _row(s, 5)
	for hd in ["none", "arrow", "triangle", "bar", "dot"]:
		_opt(g, "head", hd, "endHead", hd, "Pointe : " + hd)
	v.add_child(s)
	s = _sec("Taille du texte", "font")
	g = _row(s)
	for f in [[16, "S"], [20, "M"], [28, "L"], [40, "XL"]]:
		_opt(g, "text", f[1], "fontSize", f[0], "Taille %s" % f[1])
	v.add_child(s)
	s = _sec("Opacité", "opacity")
	_opacity = HSlider.new()
	_opacity.min_value = 0
	_opacity.max_value = 100
	_opacity.step = 10
	_opacity.custom_minimum_size = Vector2(0, CELL)
	_opacity.value_changed.connect(func(val: float):
		if not _dirty_slider:
			S.tools.set_style("opacity", val, false))
	_opacity.drag_ended.connect(func(_c: bool): S.scene.commit())
	s.add_child(_opacity)
	v.add_child(s)
	s = _sec("Calques", "layers")
	g = _row(s)
	for o in [["back", "Arrière-plan (Ctrl+Maj+[)"], ["backward", "Reculer (Ctrl+[)"], ["forward", "Avancer (Ctrl+])"], ["front", "Premier plan (Ctrl+Maj+])"]]:
		g.add_child(_cell("icon", "z_" + o[0], "", o[1], func(): S.tools.order(o[0])))
	v.add_child(s)
	s = _sec("Actions", "actions")
	g = _row(s)
	g.add_child(_cell("icon", "dup", "", "Dupliquer (Ctrl+D)", func(): S.tools.duplicate_sel()))
	g.add_child(_cell("icon", "trash", "", "Supprimer (Suppr)", func(): S.tools.delete_sel()))
	g.add_child(_cell("icon", "unlock", "", "Verrouiller / déverrouiller (Ctrl+Maj+L)", func(): S.tools.toggle_lock_sel()))
	g.add_child(_cell("icon", "group", "", "Grouper (Ctrl+G) ; Ctrl+Maj+G dégroupe", func(): S.tools.group_sel()))
	v.add_child(s)
	panel.visible = false


var _dirty_slider := false


func _build_zoombar() -> void:
	zoombar = _box(4)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 3)
	zoombar.add_child(h)
	h.add_child(_cell("icon", "minus", "", "Zoom arrière (Ctrl+-)", func(): S.zoom_at(S.size * 0.5, 0.8)))
	zoom_cell = _cell("text", "100%", "", "Zoom 100 % (Ctrl+0) ; Maj+1 : tout voir ; Maj+2 : la sélection", func(): S.zoom_to(1.0), Vector2(62, CELL))
	h.add_child(zoom_cell)
	h.add_child(_cell("icon", "plus", "", "Zoom avant (Ctrl+=)", func(): S.zoom_at(S.size * 0.5, 1.25)))
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.12)
	sep.custom_minimum_size = Vector2(2, 28)
	sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(sep)
	undo_cell = _cell("icon", "undo", "", "Annuler (Ctrl+Z)", func(): S.tools.undo())
	redo_cell = _cell("icon", "redo", "", "Rétablir (Ctrl+Maj+Z)", func(): S.tools.redo())
	h.add_child(undo_cell)
	h.add_child(redo_cell)
	style_btn = _cell("text", "Style", "", "Afficher / masquer les propriétés", func():
		panel_open = not panel_open
		refresh(), Vector2(62, CELL))
	h.add_child(style_btn)
	zoombar.size = Vector2(CELL * 5 + 62 * 2 + 30, CELL + 8)


func _show(key: String, on: bool) -> void:
	if _secs.has(key):
		(_secs[key] as Control).visible = on


func refresh() -> void:
	if S == null:
		return
	var tl = S.tools
	for id in _tool_cells:
		var c: Cell = _tool_cells[id]
		c.sel = (tl.locked if id == "lock" else (id == tl.tool and id != "image"))
		if id == "lock":
			c.a = "lock" if tl.locked else "unlock"
		c.queue_redraw()
	_zoom_label()
	(undo_cell as Cell).dim = not S.scene.can_undo()
	(redo_cell as Cell).dim = not S.scene.can_redo()
	undo_cell.queue_redraw()
	redo_cell.queue_redraw()
	# propriétés : visibles pour une sélection ou un outil de tracé
	var types := {}
	var els: Array = S.scene.selected()
	for el in els:
		types[el.type] = true
	if els.is_empty() and tl.tool in tl.DRAW + ["text"]:
		types[tl.tool] = true
	var show: bool = not types.is_empty()
	if S.size.x < 720.0:
		show = show and panel_open
	panel.visible = show
	var shape: bool = types.has("rectangle") or types.has("diamond") or types.has("ellipse")
	var lin: bool = types.has("arrow") or types.has("line") or types.has("freedraw")
	_show("stroke", types.size() > 0 and not (types.size() == 1 and (types.has("zone") or types.has("image"))))
	_show("bg", shape)
	_show("fill", shape)
	_show("width", shape or lin)
	_show("style", shape or lin)
	_show("rough", shape or lin)
	_show("edges", types.has("rectangle"))
	_show("atype", types.has("arrow"))
	_show("head0", types.has("arrow"))
	_show("head1", types.has("arrow"))
	_show("font", types.has("text") or shape)
	_show("layers", not els.is_empty())
	_show("actions", not els.is_empty())
	var first: Dictionary = els[0] if not els.is_empty() else {}
	for ce in _cells:
		var cur = first.get(str(ce.key), S.scene.style.get(str(ce.key))) if not first.is_empty() else S.scene.style.get(str(ce.key))
		var v = ce.val
		var on: bool = (is_equal_approx(float(cur), float(v)) if (cur is float or cur is int) and (v is float or v is int) else cur == v)
		(ce.c as Cell).sel = on
		(ce.c as Cell).queue_redraw()
	_dirty_slider = true
	_opacity.value = float(first.get("opacity", S.scene.style.get("opacity"))) if not first.is_empty() else float(S.scene.style.get("opacity"))
	_dirty_slider = false
	layout()


## Case dessinée : icône d'outil, pastille de couleur, échantillon de style.
class Cell extends Control:
	signal pressed
	var kind := "icon"
	var a = ""
	var b = ""
	var sel := false
	var dim := false
	var _hot := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func _notification(what: int) -> void:
		if what == NOTIFICATION_MOUSE_ENTER:
			_hot = true
			queue_redraw()
		elif what == NOTIFICATION_MOUSE_EXIT:
			_hot = false
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pressed.emit()

	static func _p(r: Rect2, x: float, y: float) -> Vector2:
		var s := minf(r.size.x, r.size.y)
		return r.get_center() - Vector2(s, s) * 0.5 + Vector2(x, y) * s

	func _draw() -> void:
		var T_ = preload("res://ui/theme.gd")
		var r := Rect2(Vector2.ZERO, size)
		var acc: Color = T_.OK
		if kind == "swatch":
			var rr := r.grow(-6)
			var col := Geom.ncol(str(a))
			if str(a) == "transparent":
				draw_rect(rr, Color(1, 1, 1, 0.06))
				draw_line(rr.position + Vector2(0, rr.size.y), rr.position + Vector2(rr.size.x, 0), Color(T_.BAD, 0.8), 2.0)
			else:
				draw_rect(rr, col)
			draw_rect(rr, Color(1, 1, 1, 0.25), false, 1.0)
			if sel:
				draw_rect(r.grow(-2), acc, false, 3.0)
			elif _hot:
				draw_rect(r.grow(-2), Color(1, 1, 1, 0.35), false, 2.0)
			return
		var bgc := Color(0, 0, 0, 0)
		if sel:
			bgc = Color(acc, 0.22)
		elif _hot:
			bgc = Color(1, 1, 1, 0.07)
		if bgc.a > 0.0:
			draw_rect(r.grow(-2), bgc)
		if sel:
			draw_rect(r.grow(-2), Color(acc, 0.8), false, 2.0)
		var c: Color = acc if sel else T_.TEXT
		if dim:
			c = Color(T_.DIM, 0.4)
		var ir := r.grow(-8)
		match kind:
			"icon":
				icon(self, str(a), ir, c)
				if str(b) != "":
					draw_string(get_theme_default_font(), Vector2(r.size.x - 11, r.size.y - 5), str(b), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(T_.DIM, 0.9))
			"text":
				draw_string(get_theme_default_font(), Vector2(0, r.size.y * 0.5 + 5), str(a), HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 14, c)
			"linew":
				draw_line(_p(ir, 0.15, 0.5), _p(ir, 0.85, 0.5), c, float(a) + 0.5)
			"lines":
				var pts := PackedVector2Array([_p(ir, 0.1, 0.5), _p(ir, 0.9, 0.5)])
				if str(a) == "plein":
					draw_line(pts[0], pts[1], c, 2.0)
				else:
					draw_multiline(Geom.dash(pts, 6.0 if str(a) == "tirets" else 1.0, 5.0 if str(a) == "tirets" else 4.0), c, 2.0)
			"fill":
				var br := ir.grow(-3)
				match str(a):
					"plein":
						draw_rect(br, Color(c, 0.8))
					"hachure", "croise":
						var x := br.position.x - br.size.y
						while x < br.end.x:
							var p0 := Vector2(maxf(x, br.position.x), br.end.y - maxf(br.position.x - x, 0.0))
							var p1 := Vector2(minf(x + br.size.y, br.end.x), br.end.y - minf(x + br.size.y, br.end.x) + x)
							draw_line(p0, p1, Color(c, 0.8), 1.5)
							if str(a) == "croise":
								draw_line(Vector2(p0.x, br.position.y + (br.end.y - p0.y)), Vector2(p1.x, br.position.y + (br.end.y - p1.y)), Color(c, 0.8), 1.5)
							x += 7.0
				draw_rect(br, c, false, 1.5)
			"rough":
				var n := 10
				var pp := PackedVector2Array()
				for i in n + 1:
					var t := float(i) / n
					pp.append(_p(ir, 0.1 + 0.8 * t, 0.5 + sin(t * 9.0) * 0.07 * float(a) * 2.0 + (0.05 * float(a) if i % 2 == 0 else -0.05 * float(a))))
				draw_polyline(pp, c, 2.0, true)
			"edge":
				var br2 := ir.grow(-3)
				if str(a) == "sharp":
					draw_rect(br2, c, false, 2.0)
				else:
					var rad := 6.0
					var pts2 := PackedVector2Array()
					var cs := [br2.position + Vector2(rad, rad), Vector2(br2.end.x - rad, br2.position.y + rad), br2.end - Vector2(rad, rad), Vector2(br2.position.x + rad, br2.end.y - rad)]
					for ci in 4:
						for k in 5:
							var ang := PI + (ci + float(k) / 4.0) * PI * 0.5
							pts2.append((cs[ci] as Vector2) + Vector2(cos(ang), sin(ang)) * rad)
					pts2.append(pts2[0])
					draw_polyline(pts2, c, 2.0, true)
			"head":
				var tip := _p(ir, 0.78, 0.5)
				draw_line(_p(ir, 0.1, 0.5), tip, c, 2.0)
				match str(a):
					"arrow":
						draw_polyline(PackedVector2Array([_p(ir, 0.55, 0.3), tip, _p(ir, 0.55, 0.7)]), c, 2.0)
					"triangle":
						draw_colored_polygon(PackedVector2Array([tip, _p(ir, 0.55, 0.3), _p(ir, 0.55, 0.7)]), c)
					"bar":
						draw_line(_p(ir, 0.78, 0.3), _p(ir, 0.78, 0.7), c, 2.0)
					"dot":
						draw_circle(_p(ir, 0.72, 0.5), 4.0, c)
			"atype":
				match str(a):
					"sharp":
						draw_line(_p(ir, 0.12, 0.78), _p(ir, 0.88, 0.22), c, 2.0)
					"round":
						var cv := PackedVector2Array()
						for i in 13:
							cv.append(Geom.bez(_p(ir, 0.12, 0.78), _p(ir, 0.5, 0.78), _p(ir, 0.5, 0.22), _p(ir, 0.88, 0.22), i / 12.0))
						draw_polyline(cv, c, 2.0, true)
					"elbow":
						draw_polyline(PackedVector2Array([_p(ir, 0.12, 0.78), _p(ir, 0.5, 0.78), _p(ir, 0.5, 0.22), _p(ir, 0.88, 0.22)]), c, 2.0)

	static func icon(ci: CanvasItem, n: String, r: Rect2, c: Color) -> void:
		var w := 2.0
		match n:
			"select":
				var pl := PackedVector2Array([_p(r, 0.3, 0.18), _p(r, 0.3, 0.8), _p(r, 0.45, 0.66), _p(r, 0.56, 0.86), _p(r, 0.66, 0.81), _p(r, 0.55, 0.62), _p(r, 0.74, 0.62), _p(r, 0.3, 0.18)])
				ci.draw_polyline(pl, c, w, true)
			"hand":
				for xs in [[0.34, 0.3], [0.45, 0.2], [0.56, 0.22], [0.67, 0.32]]:
					ci.draw_line(_p(r, xs[0], 0.55), _p(r, xs[0], xs[1]), c, w)
				ci.draw_polyline(PackedVector2Array([_p(r, 0.34, 0.55), _p(r, 0.24, 0.45), _p(r, 0.3, 0.7), _p(r, 0.45, 0.84), _p(r, 0.62, 0.84), _p(r, 0.72, 0.7), _p(r, 0.67, 0.55)]), c, w, true)
			"rectangle":
				ci.draw_rect(Rect2(_p(r, 0.2, 0.28), _p(r, 0.8, 0.72) - _p(r, 0.2, 0.28)), c, false, w)
			"diamond":
				ci.draw_polyline(PackedVector2Array([_p(r, 0.5, 0.15), _p(r, 0.85, 0.5), _p(r, 0.5, 0.85), _p(r, 0.15, 0.5), _p(r, 0.5, 0.15)]), c, w, true)
			"ellipse":
				var pe := PackedVector2Array()
				for i in 25:
					pe.append(_p(r, 0.5 + cos(TAU * i / 24.0) * 0.32, 0.5 + sin(TAU * i / 24.0) * 0.26))
				ci.draw_polyline(pe, c, w, true)
			"arrow":
				ci.draw_line(_p(r, 0.2, 0.8), _p(r, 0.8, 0.2), c, w, true)
				ci.draw_polyline(PackedVector2Array([_p(r, 0.5, 0.2), _p(r, 0.8, 0.2), _p(r, 0.8, 0.5)]), c, w, true)
			"line":
				ci.draw_line(_p(r, 0.2, 0.75), _p(r, 0.8, 0.25), c, w, true)
			"freedraw":
				ci.draw_line(_p(r, 0.62, 0.3), _p(r, 0.3, 0.62), c, 4.0, true)
				ci.draw_polyline(PackedVector2Array([_p(r, 0.3, 0.62), _p(r, 0.24, 0.78), _p(r, 0.4, 0.72)]), c, w, true)
				ci.draw_line(_p(r, 0.7, 0.22), _p(r, 0.78, 0.3), c, 3.0)
			"text":
				ci.draw_line(_p(r, 0.25, 0.25), _p(r, 0.75, 0.25), c, w)
				ci.draw_line(_p(r, 0.5, 0.25), _p(r, 0.5, 0.78), c, w)
				ci.draw_line(_p(r, 0.4, 0.78), _p(r, 0.6, 0.78), c, w)
			"image":
				ci.draw_rect(Rect2(_p(r, 0.15, 0.22), _p(r, 0.85, 0.78) - _p(r, 0.15, 0.22)), c, false, w)
				ci.draw_circle(_p(r, 0.35, 0.42), 3.0, c)
				ci.draw_polyline(PackedVector2Array([_p(r, 0.18, 0.76), _p(r, 0.45, 0.52), _p(r, 0.6, 0.66), _p(r, 0.72, 0.5), _p(r, 0.84, 0.64)]), c, w, true)
			"eraser":
				ci.draw_polyline(PackedVector2Array([_p(r, 0.2, 0.62), _p(r, 0.5, 0.22), _p(r, 0.82, 0.46), _p(r, 0.54, 0.84), _p(r, 0.2, 0.62)]), c, w, true)
				ci.draw_line(_p(r, 0.36, 0.42), _p(r, 0.67, 0.65), c, w)
			"lock":
				ci.draw_rect(Rect2(_p(r, 0.28, 0.48), _p(r, 0.72, 0.82) - _p(r, 0.28, 0.48)), c, false, w)
				ci.draw_arc(_p(r, 0.5, 0.48), r.size.x * 0.2, PI, TAU, 12, c, w, true)
			"unlock":
				ci.draw_rect(Rect2(_p(r, 0.28, 0.48), _p(r, 0.72, 0.82) - _p(r, 0.28, 0.48)), c, false, w)
				ci.draw_arc(_p(r, 0.5, 0.48), r.size.x * 0.2, PI, TAU * 0.86, 12, c, w, true)
			"frame":
				for t in [0.35, 0.65]:
					ci.draw_line(_p(r, t, 0.15), _p(r, t, 0.85), c, w)
					ci.draw_line(_p(r, 0.15, t), _p(r, 0.85, t), c, w)
			"undo", "redo":
				var sg := 1.0 if n == "undo" else -1.0
				var pu := PackedVector2Array()
				for i in 9:
					var an: float = PI * (1.05 + 0.95 * float(i) / 8.0)
					pu.append(_p(r, 0.5 + cos(an) * 0.27 * sg, 0.62 + sin(an) * 0.3))
				ci.draw_polyline(pu, c, w, true)
				var e0 := pu[0]
				ci.draw_polyline(PackedVector2Array([e0 + Vector2(-5, -5), e0, e0 + Vector2(5, -5)]), c, w, true)
			"plus":
				ci.draw_line(_p(r, 0.25, 0.5), _p(r, 0.75, 0.5), c, w)
				ci.draw_line(_p(r, 0.5, 0.25), _p(r, 0.5, 0.75), c, w)
			"minus":
				ci.draw_line(_p(r, 0.25, 0.5), _p(r, 0.75, 0.5), c, w)
			"dup":
				ci.draw_rect(Rect2(_p(r, 0.2, 0.3), _p(r, 0.62, 0.8) - _p(r, 0.2, 0.3)), c, false, w)
				ci.draw_rect(Rect2(_p(r, 0.38, 0.2), _p(r, 0.8, 0.7) - _p(r, 0.38, 0.2)), Color(c, 0.6), false, w)
			"trash":
				ci.draw_rect(Rect2(_p(r, 0.3, 0.35), _p(r, 0.7, 0.85) - _p(r, 0.3, 0.35)), c, false, w)
				ci.draw_line(_p(r, 0.22, 0.28), _p(r, 0.78, 0.28), c, w)
				ci.draw_line(_p(r, 0.42, 0.18), _p(r, 0.58, 0.18), c, w)
			"group":
				ci.draw_rect(Rect2(_p(r, 0.2, 0.2), _p(r, 0.8, 0.8) - _p(r, 0.2, 0.2)), Color(c, 0.6), false, 1.0)
				ci.draw_rect(Rect2(_p(r, 0.3, 0.3), _p(r, 0.5, 0.5) - _p(r, 0.3, 0.3)), c, false, w)
				ci.draw_rect(Rect2(_p(r, 0.5, 0.5), _p(r, 0.7, 0.7) - _p(r, 0.5, 0.5)), c, false, w)
			"z_front", "z_forward":
				ci.draw_polyline(PackedVector2Array([_p(r, 0.3, 0.55), _p(r, 0.5, 0.35), _p(r, 0.7, 0.55)]), c, w, true)
				ci.draw_line(_p(r, 0.5, 0.35), _p(r, 0.5, 0.8), c, w)
				if n == "z_front":
					ci.draw_line(_p(r, 0.3, 0.2), _p(r, 0.7, 0.2), c, w)
			"z_back", "z_backward":
				ci.draw_polyline(PackedVector2Array([_p(r, 0.3, 0.45), _p(r, 0.5, 0.65), _p(r, 0.7, 0.45)]), c, w, true)
				ci.draw_line(_p(r, 0.5, 0.65), _p(r, 0.5, 0.2), c, w)
				if n == "z_back":
					ci.draw_line(_p(r, 0.3, 0.8), _p(r, 0.7, 0.8), c, w)
