extends "res://pages/page.gd"
## Plan 2D : on pose des zones (rectangles) ; dans chacune on parle avec un assistant. « Clôturer » fige la zone et
## en tire une synthèse ; on tire un fil (●) d'une zone vers une autre pour la nourrir de cette synthèse.
## Données : zones {id,x,y,w,h,title,ai,msgs[{role,content}],summary,closed} + liens {from,to}, sauvées dans user://board.json.

const U := preload("res://ui/universe.gd")
const MD := preload("res://ui/markdown.gd")
const Ollama := preload("res://core/ollama.gd")
const FILE := "user://board.json"
const PORT_R := 9.0
const PORT_DX := 14.0
const MAX_HISTORY := 14
const CTX_CAP := 1500

var zones: Array = []
var links: Array = []
var nodes := {}  # id -> Zone
var pan := Vector2(24, 24)
var canvas: Control
var world: Control
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
	var add := W.Btn.new("+ Zone", "primary")
	add.size_name = "sm"
	add.pressed.connect(func(): _add_zone())
	head_right.add_child(add)
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
	canvas.add_child(world)
	_load()
	if zones.is_empty():
		_add_zone("De quoi allons-nous parler aujourd'hui ?")
	for d in zones:
		_spawn(d)
	_refresh_all()


func _process(dt: float) -> void:
	if _dirty:
		_save_t += dt
		if _save_t > 0.8:
			_save()


func _exit_tree() -> void:
	for id in reqs:
		(reqs[id] as Ollama.Req).cancel()
	if _dirty:
		_save()


func _add_zone(title := "Nouvelle zone") -> void:
	var c := canvas.size * 0.5 - pan - Vector2(160, 110) if canvas != null and canvas.size.x > 10 else Vector2(40, 40)
	c += Vector2(randf_range(-30, 30), randf_range(-30, 30))
	var d := {"id": "z%d%03d" % [Time.get_ticks_msec(), randi() % 1000], "x": c.x, "y": c.y, "w": 320.0, "h": 260.0,
			"title": title, "ai": int(ctx.active), "msgs": [], "summary": "", "closed": false}
	zones.append(d)
	if canvas != null and world != null:
		_spawn(d)
		_refresh_all()
		_touch()


func _spawn(d: Dictionary) -> void:
	var z := Zone.new()
	z.board = self
	z.d = d
	world.add_child(z)
	nodes[d.id] = z
	z.build_ui()
	z.refresh()


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


func _refresh_all() -> void:
	for id in nodes:
		(nodes[id] as Zone).refresh()
	if canvas != null:
		canvas.queue_redraw()


# ------------------------------------------------------------------ Liens

func add_link(a: String, b: String) -> void:
	if a == b or a == "" or b == "":
		return
	for l in links:
		if l.from == a and l.to == b:
			return
	links.append({"from": a, "to": b})
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
		(reqs[id] as Ollama.Req).cancel()
		reqs.erase(id)
	zones = zones.filter(func(d): return d.id != id)
	links = links.filter(func(l): return l.from != id and l.to != id)
	if nodes.has(id):
		(nodes[id] as Zone).queue_free()
		nodes.erase(id)
	_refresh_all()
	_touch()


## Texte reçu par une zone depuis ses zones sources (synthèse si clôturée, sinon fin de la discussion).
func incoming_context(id: String) -> String:
	var parts: PackedStringArray = []
	for l in links:
		if l.to != id:
			continue
		var s := _zone(str(l.from))
		if s.is_empty():
			continue
		var body := str(s.summary).strip_edges()
		if not (s.closed and body != ""):
			var tr: PackedStringArray = []
			for m in s.msgs:
				tr.append("%s : %s" % ["Utilisateur" if m.role == "user" else "Assistant", str(m.content)])
			body = "\n".join(tr)
			body = body.right(CTX_CAP) if body.length() > CTX_CAP else body
		if body != "":
			parts.append("[Zone « %s »]\n%s" % [str(s.title), body])
	return "\n\n".join(parts)


# ------------------------------------------------------------------ Discussion

func _system(d: Dictionary) -> String:
	var s := U.system_prompt(int(d.ai), false)
	s += "\nTu travailles dans une zone d'un plan de réflexion (titre : « %s »). Sois concis." % str(d.title)
	var c := incoming_context(str(d.id))
	if c != "":
		s += "\nContexte venant des zones liées à celle-ci (à utiliser comme base de travail) :\n" + c
	return s


func _model(d: Dictionary) -> String:
	return ctx.model_for(int(d.ai))


func send(id: String, text: String) -> void:
	var d := _zone(id)
	text = text.strip_edges()
	if d.is_empty() or text == "" or reqs.has(id) or d.closed:
		return
	d.msgs.append({"role": "user", "content": text})
	d.msgs.append({"role": "assistant", "content": ""})
	_stream(d, _history(d, d.msgs.size() - 1), func(t: String): d.msgs[d.msgs.size() - 1].content = t)


func close_zone(id: String) -> void:
	var d := _zone(id)
	if d.is_empty() or reqs.has(id):
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


func _history(d: Dictionary, upto: int) -> Array:
	var h: Array = [{"role": "system", "content": _system(d)}]
	var from := maxi(0, upto - MAX_HISTORY)
	for i in range(from, upto):
		h.append({"role": d.msgs[i].role, "content": d.msgs[i].content})
	return h


func _stream(d: Dictionary, msgs: Array, setter: Callable) -> void:
	var id := str(d.id)
	var model := _model(d)
	if model == "":
		setter.call("(Aucun modèle Ollama disponible : installe-en un depuis l'Assistant IA.)")
		_finish(id)
		return
	var req: Ollama.Req = ctx.ollama.chat(model, msgs, {"temperature": float(U.get_u(int(d.ai)).temp), "num_predict": 700})
	reqs[id] = req
	var acc := [""]
	_refresh_all()
	req.line.connect(func(l: Dictionary):
		var c := str(l.get("message", {}).get("content", ""))
		if c != "" and is_instance_valid(self):
			acc[0] += c
			setter.call(Ollama.strip_think(acc[0]) if "<think>" in acc[0] else acc[0])
			if nodes.has(id):
				(nodes[id] as Zone).render())
	req.finished.connect(func(ok: bool, kind: String, msg: String):
		if not is_instance_valid(self):
			return
		if not ok and kind != "cancel":
			setter.call(str(acc[0]) + "\n(Erreur : %s)" % Ollama.friendly(kind, msg, model))
		_finish(id))


func _finish(id: String) -> void:
	reqs.erase(id)
	if nodes.has(id):
		(nodes[id] as Zone).refresh()
	_touch()


# ------------------------------------------------------------------ Sauvegarde

func _save() -> void:
	_dirty = false
	_save_t = 0.0
	var f := FileAccess.open(FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"zones": zones, "links": links, "pan": [pan.x, pan.y]}))


func _load() -> void:
	if not FileAccess.file_exists(FILE):
		return
	var v = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	if v is Dictionary:
		zones = v.get("zones", [])
		links = v.get("links", [])
		var p = v.get("pan", [24, 24])
		pan = Vector2(float(p[0]), float(p[1]))
		if world != null:
			world.position = pan
		for d in zones:
			d["closed"] = bool(d.get("closed", false))
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
		return board.pan + Vector2(float(d.x) + float(d.w) + PORT_DX, float(d.y) + float(d.h) * 0.5)

	func _curve(a: Vector2, b: Vector2) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 29:
			pts.append(bez(a, a + Vector2(90, 0), b - Vector2(90, 0), b, i / 28.0))
		return pts

	func _draw() -> void:
		if board == null:
			return
		var T = board.T
		var gs := 24.0
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
			var pts := _curve(port_pos(a), board.pan + Vector2(float(b.x) - 4.0, float(b.y) + float(b.h) * 0.5))
			var solid: bool = a.closed
			for k in pts.size() - 1:
				if solid or k % 2 == 0:
					draw_line(pts[k], pts[k + 1], Color(col, 0.95 if solid else 0.55), 3.0)
			var e := pts[pts.size() - 1]
			draw_colored_polygon(PackedVector2Array([e, e + Vector2(-12, -7), e + Vector2(-12, 7)]), col)
			var m := pts[14]
			draw_circle(m, 8, T.CARD_HI)
			draw_arc(m, 8, 0, TAU, 16, col, 2.0)
			draw_line(m + Vector2(-3, -3), m + Vector2(3, 3), T.TEXT, 2.0)
			draw_line(m + Vector2(-3, 3), m + Vector2(3, -3), T.TEXT, 2.0)
		for d in board.zones:
			var col2: Color = board.U.color(int(d.ai))
			var p := port_pos(d)
			var zr: float = float(d.x) + float(d.w)
			draw_line(board.pan + Vector2(zr, float(d.y) + float(d.h) * 0.5), p, col2, 3.0)
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
				"Glisse le rond ● d'une zone vers une autre pour la nourrir de sa synthèse. Fond : déplacer le plan.",
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, 12, board.T.DIM)

	func _gui_input(e: InputEvent) -> void:
		if board == null:
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
					var pts := _curve(port_pos(a), board.pan + Vector2(float(b.x) - 4.0, float(b.y) + float(b.h) * 0.5))
					if pts[14].distance_to(e.position) < 10.0:
						board.remove_link(i)
						return
				panning = true
			else:
				if board.drag_from != "":
					board.add_link(board.drag_from, board.zone_at(e.position - board.pan, board.drag_from))
					board.drag_from = ""
					queue_redraw()
				if panning:
					panning = false
					board._touch()
		elif e is InputEventMouseMotion:
			if board.drag_from != "":
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
	var input_row: HBoxContainer
	var input: LineEdit
	var mode := ""

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
		info = Label.new()
		info.add_theme_font_size_override("font_size", 11)
		info.add_theme_color_override("font_color", board.T.DIM)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.mouse_filter = Control.MOUSE_FILTER_PASS
		v.add_child(info)
		logv = RichTextLabel.new()
		logv.bbcode_enabled = true
		logv.scroll_following = true
		logv.selection_enabled = true
		logv.size_flags_vertical = Control.SIZE_EXPAND_FILL
		logv.custom_minimum_size.y = 60
		v.add_child(logv)
		input_row = HBoxContainer.new()
		v.add_child(input_row)
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
		var src: PackedStringArray = []
		for l in board.links:
			if l.to == d.id:
				var s: Dictionary = board._zone(str(l.from))
				if not s.is_empty():
					src.append(str(s.title))
		info.visible = not src.is_empty()
		info.text = "↤ nourrie par : " + ", ".join(src) if not src.is_empty() else ""
		render()
		queue_redraw()

	func render() -> void:
		var accent: String = board.U.color(int(d.ai)).to_html(false)
		var out: PackedStringArray = []
		for m in d.msgs:
			if m.role == "user":
				out.append("[color=#98a2b0]Toi :[/color] " + board.MD.esc(str(m.content)))
			else:
				out.append(board.MD.to_bbcode(str(m.content), accent))
		if d.closed:
			out.append("[color=#%s][b]— Synthèse —[/b][/color]\n%s" % [accent, board.MD.to_bbcode(str(d.summary), accent)])
		logv.text = "\n\n".join(out)

	func _draw() -> void:
		var col: Color = board.U.color(int(d.ai))
		for i in 3:
			draw_rect(Rect2(size.x - 6 - i * 4, size.y - 6, 2, 2), Color(col, 0.8))
			draw_rect(Rect2(size.x - 6, size.y - 6 - i * 4, 2, 2), Color(col, 0.8))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				move_to_front()
				if e.position.x > size.x - 22 and e.position.y > size.y - 22:
					mode = "resize"
				elif e.position.y < 40:
					mode = "drag"
				else:
					mode = ""
			else:
				if mode != "":
					board._touch()
				mode = ""
		elif e is InputEventMouseMotion and mode != "":
			if mode == "drag":
				position += e.relative
				d.x = position.x
				d.y = position.y
			else:
				size = (size + e.relative).max(custom_minimum_size)
				d.w = size.x
				d.h = size.y
			board.canvas.queue_redraw()
			queue_redraw()
