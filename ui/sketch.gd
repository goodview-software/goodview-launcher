extends RefCounted
## Couche de dessin « façon Excalidraw » du Plan IA : formes tremblées, flèches collées aux zones,
## annuler/rétablir. Les formes vivent dans board.sketch.shapes (coordonnées monde) et sont
## sauvegardées sous la clé "shapes" du plan.

const T := preload("res://ui/theme.gd")
const TOOLS := ["select", "hand", "rect", "ellipse", "diamond", "arrow", "line", "pencil", "text", "eraser"]
const TOOL_TIPS := {"select": "Sélection", "hand": "Main (déplacer la vue)", "rect": "Rectangle", "ellipse": "Ellipse",
		"diamond": "Losange", "arrow": "Flèche (se colle aux zones)", "line": "Ligne", "pencil": "Crayon",
		"text": "Texte", "eraser": "Gomme"}
const COLORS := ["f4f4f5", "ff6b6b", "fbbf24", "4de1b4", "60a5fa", "a78bfa", "ff8fb1", "9ca3af"]
const WIDTHS := [2.0, 4.0, 7.0]
const FONTS := [16, 22, 32]
const MAX_UNDO := 60
const BOXES := ["rect", "ellipse", "diamond"]

var board: Node
var shapes: Array = []
var tool := "select"
var color := "f4f4f5"
var wi := 0  # index d'épaisseur
var fill := false
var sel := ""
var dragging := false
var layer: Layer
var overlay: Overlay
var bar: Bar
var _undo: Array = []
var _redo: Array = []
var _mode := ""  # move / end_a / end_b / resize
var _last := Vector2.ZERO
var _moved := false
var draft: Dictionary = {}
var _edit: LineEdit
var _edit_id := ""


func _init(b: Node) -> void:
	board = b


func attach(canvas: Control, world: Control) -> void:
	layer = Layer.new()
	layer.sk = self
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	world.add_child(layer)
	overlay = Overlay.new()
	overlay.sk = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(overlay)
	bar = Bar.new()
	bar.sk = self
	canvas.add_child(bar)
	bar.build()
	canvas.resized.connect(bar.relayout)
	bar.relayout()


# ------------------------------------------------------------------ Données

func new_id() -> String:
	return "s%d%03d" % [Time.get_ticks_msec(), randi() % 1000]


func get_shape(id: String) -> Dictionary:
	for s in shapes:
		if s.id == id:
			return s
	return {}


func load_shapes(v) -> void:
	shapes = []
	_undo.clear()
	_redo.clear()
	sel = ""
	if v is Array:
		for s in v:
			if s is Dictionary and s.has("id") and TOOLS.has(str(s.get("type", ""))):
				s["x"] = float(s.get("x", 0))
				s["y"] = float(s.get("y", 0))
				s["w"] = float(s.get("w", 0))
				s["h"] = float(s.get("h", 0))
				s["color"] = str(s.get("color", "f4f4f5"))
				s["width"] = clampi(int(s.get("width", 0)), 0, 2)
				s["fill"] = bool(s.get("fill", false))
				shapes.append(s)
	redraw()


func to_save() -> Array:
	sync()
	return shapes


func clear() -> void:
	shapes = []
	_undo.clear()
	_redo.clear()
	sel = ""
	draft = {}
	redraw()


func redraw() -> void:
	if layer != null:
		layer.queue_redraw()


func has_bound() -> bool:
	for s in shapes:
		if s.get("from", "") != "" or s.get("to", "") != "":
			return true
	return false


## Recolle les extrémités liées aux zones (met à jour x,y,w,h).
func sync() -> void:
	for s in shapes:
		if s.type == "arrow" or s.type == "line":
			var e := ends(s)
			s.x = e[0].x
			s.y = e[0].y
			s.w = e[1].x - e[0].x
			s.h = e[1].y - e[0].y


func _zrect(id: String) -> Rect2:
	var z: Dictionary = board._zone(id)
	if z.is_empty():
		return Rect2()
	return Rect2(float(z.x), float(z.y), float(z.w), float(z.h))


static func _clip(r: Rect2, p: Vector2) -> Vector2:
	var c := r.get_center()
	var dv := p - c
	if dv.length() < 0.01:
		return c
	var hw := r.size.x * 0.5
	var hh := r.size.y * 0.5
	var t := minf(hw / maxf(absf(dv.x), 0.001), hh / maxf(absf(dv.y), 0.001))
	if t >= 1.0:
		return p  # le point est déjà dans la zone
	return c + dv * t + dv.normalized() * 5.0


func ends(s: Dictionary) -> Array:
	var a := Vector2(float(s.x), float(s.y))
	var b := a + Vector2(float(s.w), float(s.h))
	var ra := _zrect(str(s.get("from", ""))) if str(s.get("from", "")) != "" else Rect2()
	var rb := _zrect(str(s.get("to", ""))) if str(s.get("to", "")) != "" else Rect2()
	var ca := ra.get_center() if ra.size != Vector2.ZERO else a
	var cb := rb.get_center() if rb.size != Vector2.ZERO else b
	var na := _clip(ra, cb) if ra.size != Vector2.ZERO else a
	var nb := _clip(rb, ca) if rb.size != Vector2.ZERO else b
	return [na, nb]


## Rectangle englobant (monde).
func bounds(s: Dictionary) -> Rect2:
	match str(s.type):
		"text":
			var f := layer.get_theme_default_font()
			var fs: int = FONTS[int(s.width)]
			return Rect2(float(s.x), float(s.y), f.get_string_size(str(s.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, fs * 1.3)
		"arrow", "line":
			var e := ends(s)
			return Rect2(e[0], Vector2.ZERO).expand(e[1])
		_:
			return Rect2(float(s.x), float(s.y), float(s.w), float(s.h)).abs()


func outline(s: Dictionary) -> PackedVector2Array:
	var r := Rect2(float(s.x), float(s.y), float(s.w), float(s.h)).abs()
	match str(s.type):
		"rect":
			return PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		"diamond":
			var c := r.get_center()
			return PackedVector2Array([Vector2(c.x, r.position.y), Vector2(r.end.x, c.y), Vector2(c.x, r.end.y), Vector2(r.position.x, c.y)])
		"ellipse":
			var pts := PackedVector2Array()
			var c2 := r.get_center()
			for i in 32:
				var a := TAU * i / 32.0
				pts.append(c2 + Vector2(cos(a) * r.size.x * 0.5, sin(a) * r.size.y * 0.5))
			return pts
	return PackedVector2Array()


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


func hit(s: Dictionary, p: Vector2, tol: float) -> bool:
	match str(s.type):
		"text":
			return bounds(s).grow(tol * 0.5).has_point(p)
		"arrow", "line":
			var e := ends(s)
			return _seg_dist(p, e[0], e[1]) <= tol
		"pencil":
			var pts: Array = s.get("pts", [])
			var o := Vector2(float(s.x), float(s.y))
			for i in pts.size() - 1:
				if _seg_dist(p, o + Vector2(pts[i][0], pts[i][1]), o + Vector2(pts[i + 1][0], pts[i + 1][1])) <= tol:
					return true
			return pts.size() == 1 and p.distance_to(o + Vector2(pts[0][0], pts[0][1])) <= tol
		_:
			var poly := outline(s)
			if bool(s.fill) and Geometry2D.is_point_in_polygon(p, poly):
				return true
			for i in poly.size():
				if _seg_dist(p, poly[i], poly[(i + 1) % poly.size()]) <= tol:
					return true
	return false


func top_hit(p: Vector2) -> Dictionary:
	var tol: float = 10.0 / board.zoom
	for i in range(shapes.size() - 1, -1, -1):
		if hit(shapes[i], p, tol):
			return shapes[i]
	return {}


# ------------------------------------------------------------------ Annuler / rétablir

func push_undo() -> void:
	sync()
	_undo.append(JSON.stringify(shapes))
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()
	_redo.clear()


func _restore(js: String) -> void:
	var v = JSON.parse_string(js)
	shapes = v if v is Array else []
	if get_shape(sel).is_empty():
		sel = ""
	board._touch()
	redraw()


func undo() -> void:
	if _undo.is_empty():
		return
	sync()
	_redo.append(JSON.stringify(shapes))
	_restore(_undo.pop_back())


func redo() -> void:
	if _redo.is_empty():
		return
	sync()
	_undo.append(JSON.stringify(shapes))
	_restore(_redo.pop_back())


func delete_selected() -> void:
	if sel == "":
		return
	push_undo()
	shapes = shapes.filter(func(s): return s.id != sel)
	sel = ""
	board._touch()
	redraw()


func duplicate_selected() -> void:
	var s := get_shape(sel)
	if s.is_empty():
		return
	push_undo()
	var c: Dictionary = s.duplicate(true)
	c.id = new_id()
	c.x = float(c.x) + 24.0
	c.y = float(c.y) + 24.0
	c.erase("from")
	c.erase("to")
	shapes.append(c)
	sel = c.id
	board._touch()
	redraw()


func set_tool(t: String) -> void:
	_commit_edit()
	tool = t
	draft = {}
	dragging = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if t == "select" else Control.MOUSE_FILTER_STOP
	overlay.mouse_default_cursor_shape = Control.CURSOR_DRAG if t == "hand" else Control.CURSOR_CROSS
	if t != "select":
		sel = ""
	if bar != null:
		bar.refresh()
	redraw()


func apply_style() -> void:
	var s := get_shape(sel)
	if not s.is_empty():
		push_undo()
		s.color = color
		s.width = wi
		s.fill = fill
		board._touch()
		redraw()
	if bar != null:
		bar.refresh()


## Touches clavier (retourne true si traitée).
func key(e: InputEventKey) -> bool:
	var fo := board.get_viewport().gui_get_focus_owner()
	if fo is LineEdit or fo is TextEdit:
		return false
	var ctrl: bool = e.ctrl_pressed or e.meta_pressed
	match e.keycode:
		KEY_DELETE:
			if sel != "":
				delete_selected()
				return true
		KEY_ESCAPE:
			if tool != "select":
				set_tool("select")
				return true
			if sel != "":
				sel = ""
				redraw()
				return true
		KEY_Z:
			if ctrl:
				if e.shift_pressed:
					redo()
				else:
					undo()
				return true
		KEY_Y:
			if ctrl:
				redo()
				return true
		KEY_D:
			if ctrl and sel != "":
				duplicate_selected()
				return true
	return false


# ------------------------------------------------------------------ Souris : outil Sélection (appelée par Canvas)

func handle_at(p: Vector2, s: Dictionary) -> String:
	# poignées de la forme sélectionnée (position en pixels canevas)
	var r := 16.0
	if s.type == "arrow" or s.type == "line":
		var e := ends(s)
		if board.w2c(e[0]).distance_to(p) < r:
			return "end_a"
		if board.w2c(e[1]).distance_to(p) < r:
			return "end_b"
	elif BOXES.has(str(s.type)):
		var b := bounds(s)
		if board.w2c(b.end).distance_to(p) < r:
			return "resize"
	return ""


func sel_press(cp: Vector2, dbl: bool) -> bool:
	if tool != "select":
		return false
	var wp: Vector2 = board.c2w(cp)
	var cur := get_shape(sel)
	if not cur.is_empty():
		var h := handle_at(cp, cur)
		if h != "":
			_begin(h, wp)
			return true
	var s := top_hit(wp)
	if s.is_empty():
		if sel != "":
			sel = ""
			redraw()
			bar.refresh()
		return false
	sel = str(s.id)
	if dbl and s.type == "text":
		edit_text(Vector2(float(s.x), float(s.y)), sel)
		return true
	color = str(s.color)
	wi = int(s.width)
	fill = bool(s.fill)
	bar.refresh()
	_begin("move", wp)
	return true


func _begin(m: String, wp: Vector2) -> void:
	_mode = m
	_last = wp
	_moved = false
	dragging = true
	redraw()


func sel_motion(cp: Vector2) -> void:
	var s := get_shape(sel)
	if s.is_empty():
		return
	var wp: Vector2 = board.c2w(cp)
	if not _moved:
		push_undo()
		_moved = true
	var dv := wp - _last
	_last = wp
	match _mode:
		"move":
			s.x = float(s.x) + dv.x
			s.y = float(s.y) + dv.y
			s.erase("from")
			s.erase("to")
		"end_a":
			s.x = float(s.x) + dv.x
			s.y = float(s.y) + dv.y
			s.w = float(s.w) - dv.x
			s.h = float(s.h) - dv.y
			s.erase("from")
		"end_b":
			s.w = float(s.w) + dv.x
			s.h = float(s.h) + dv.y
			s.erase("to")
		"resize":
			var b := bounds(s)
			s.x = b.position.x
			s.y = b.position.y
			s.w = maxf(wp.x - b.position.x, 8.0)
			s.h = maxf(wp.y - b.position.y, 8.0)
	redraw()


func sel_release(cp: Vector2) -> void:
	dragging = false
	var s := get_shape(sel)
	if not s.is_empty() and _moved:
		if _mode == "end_a" or _mode == "end_b":
			_bind_end(s, _mode == "end_a", board.c2w(cp))
		board._touch()
	_mode = ""
	redraw()


func _bind_end(s: Dictionary, is_a: bool, wp: Vector2) -> void:
	if s.type != "arrow" and s.type != "line":
		return
	var z: String = board.zone_at(wp)
	if z != "":
		s["from" if is_a else "to"] = z
	else:
		s.erase("from" if is_a else "to")


# ------------------------------------------------------------------ Souris : outils de dessin (appelée par Overlay)

func tool_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb: InputEventMouseButton = e
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				board.zoom_at(mb.position, 1.12 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12)
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			overlay.panning = mb.pressed
			return
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		if mb.pressed:
			_tool_press(mb.position)
		else:
			_tool_release(mb.position)
	elif e is InputEventMouseMotion:
		var mm: InputEventMouseMotion = e
		if overlay.panning or (tool == "hand" and overlay.down):
			board.pan += mm.relative
			board.world.position = board.pan
			board.canvas.queue_redraw()
		elif overlay.down:
			_tool_motion(mm.position)


func _tool_press(cp: Vector2) -> void:
	_commit_edit()
	var wp: Vector2 = board.c2w(cp)
	overlay.down = true
	match tool:
		"hand":
			pass
		"text":
			overlay.down = false
			edit_text(wp, "")
		"eraser":
			_erased = false
			_erase_at(wp)
		"pencil":
			draft = {"id": new_id(), "type": "pencil", "x": wp.x, "y": wp.y, "w": 0.0, "h": 0.0, "pts": [[0.0, 0.0]],
					"color": color, "width": wi, "fill": false}
		_:
			draft = {"id": new_id(), "type": tool, "x": wp.x, "y": wp.y, "w": 0.0, "h": 0.0,
					"color": color, "width": wi, "fill": fill and BOXES.has(tool)}
	redraw()


var _erased := false


func _erase_at(wp: Vector2) -> void:
	var tol: float = 8.0 / board.zoom
	for i in range(shapes.size() - 1, -1, -1):
		if hit(shapes[i], wp, tol):
			if not _erased:
				push_undo()
				_erased = true
			shapes.remove_at(i)
			break
	redraw()


func _tool_motion(cp: Vector2) -> void:
	var wp: Vector2 = board.c2w(cp)
	if tool == "eraser":
		_erase_at(wp)
		return
	if draft.is_empty():
		return
	if tool == "pencil":
		var pts: Array = draft.pts
		var rel := wp - Vector2(float(draft.x), float(draft.y))
		var lastp := Vector2(pts[pts.size() - 1][0], pts[pts.size() - 1][1])
		if rel.distance_to(lastp) > 2.5 / board.zoom:
			pts.append([rel.x, rel.y])
	else:
		draft.w = wp.x - float(draft.x)
		draft.h = wp.y - float(draft.y)
	redraw()


func _tool_release(cp: Vector2) -> void:
	overlay.down = false
	if draft.is_empty():
		_erased = false
		return
	var d := draft
	draft = {}
	var wp: Vector2 = board.c2w(cp)
	var keep := true
	if d.type == "pencil":
		var pts: Array = d.pts
		var mn := Vector2(INF, INF)
		for p in pts:
			mn = mn.min(Vector2(p[0], p[1]))
		if pts.size() < 2:
			pts.append([1.0, 1.0])
		for p in pts:
			p[0] = float(p[0]) - mn.x
			p[1] = float(p[1]) - mn.y
		d.x = float(d.x) + mn.x
		d.y = float(d.y) + mn.y
	else:
		keep = Vector2(float(d.w), float(d.h)).length() * board.zoom > 6.0
		if keep and BOXES.has(str(d.type)):
			var r := Rect2(float(d.x), float(d.y), float(d.w), float(d.h)).abs()
			d.x = r.position.x
			d.y = r.position.y
			d.w = r.size.x
			d.h = r.size.y
	if keep:
		push_undo()
		if d.type == "arrow" or d.type == "line":
			_bind_end(d, true, Vector2(float(d.x), float(d.y)))
			_bind_end(d, false, wp)
		shapes.append(d)
		board._touch()
		if tool != "pencil":
			set_tool("select")
			sel = str(d.id)
	redraw()


# ------------------------------------------------------------------ Texte

func edit_text(wp: Vector2, id: String) -> void:
	_commit_edit()
	_edit_id = id
	_edit = LineEdit.new()
	_edit.custom_minimum_size = Vector2(220, 44)
	_edit.placeholder_text = "Texte…"
	var cur := get_shape(id)
	if not cur.is_empty():
		_edit.text = str(cur.get("text", ""))
	_edit.set_meta("pos", wp)
	_edit.position = board.w2c(wp) - Vector2(0, 8)
	board.canvas.add_child(_edit)
	_edit.grab_focus()
	_edit.text_submitted.connect(func(_t: String): _commit_edit())
	_edit.focus_exited.connect(_commit_edit)
	_edit.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_cancel_edit())


func _cancel_edit() -> void:
	if _edit != null:
		var e := _edit
		_edit = null
		e.queue_free()


func _commit_edit() -> void:
	if _edit == null:
		return
	var e := _edit
	_edit = null
	var txt := e.text.strip_edges()
	var wp: Vector2 = e.get_meta("pos")
	e.queue_free()
	var cur := get_shape(_edit_id)
	if cur.is_empty():
		if txt == "":
			return
		push_undo()
		shapes.append({"id": new_id(), "type": "text", "x": wp.x, "y": wp.y, "w": 0.0, "h": 0.0, "text": txt,
				"color": color, "width": wi, "fill": false})
	else:
		push_undo()
		if txt == "":
			shapes = shapes.filter(func(s): return s.id != _edit_id)
			sel = ""
		else:
			cur.text = txt
	board._touch()
	redraw()


# ------------------------------------------------------------------ Rendu (dans le monde, sous les zones)

class Layer extends Control:
	var sk

	func _draw() -> void:
		if sk == null:
			return
		sk.sync()
		for s in sk.shapes:
			_shape(s)
		if not sk.draft.is_empty():
			_shape(sk.draft)
		var cur: Dictionary = sk.get_shape(sk.sel)
		if not cur.is_empty():
			_selection(cur)

	func _minw(s: Dictionary) -> float:
		return maxf(float(sk.WIDTHS[int(s.width)]), 1.6 / sk.board.zoom)

	static func _jit(seed_: int, i: int, amp: float) -> Vector2:
		var h1 := hash(Vector2i(seed_ & 0xffff, i)) & 0xffff
		var h2 := hash(Vector2i((seed_ >> 8) & 0xffff, i + 7919)) & 0xffff
		return Vector2(h1 / 65535.0 - 0.5, h2 / 65535.0 - 0.5) * 2.0 * amp

	## Points de base subdivisés puis tremblés (déterministe par id).
	func _wobble(base: PackedVector2Array, closed: bool, seed_: int, amp: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		var n := base.size()
		var cnt := n if closed else n - 1
		for i in cnt:
			var a := base[i]
			var b := base[(i + 1) % n]
			var steps := maxi(1, int(a.distance_to(b) / 45.0))
			for k in steps:
				pts.append(a.lerp(b, float(k) / steps))
		if not closed:
			pts.append(base[n - 1])
		var out := PackedVector2Array()
		for i in pts.size():
			out.append(pts[i] + _jit(seed_, i, amp))
		if closed and out.size() > 0:
			out.append(out[0])
		return out

	func _shape(s: Dictionary) -> void:
		var col := Color(str(s.color))
		var w := _minw(s)
		var seed_: int = str(s.id).hash()
		var amp := 1.0 + w * 0.25
		match str(s.type):
			"rect", "ellipse", "diamond":
				var poly: PackedVector2Array = sk.outline(s)
				if poly.size() < 3:
					return
				if bool(s.fill):
					_hatch(poly, col, w)
				for pass_ in 2:
					draw_polyline(_wobble(poly, true, seed_ + pass_ * 977, amp), Color(col, 1.0 if pass_ == 0 else 0.55), w, true)
			"line", "arrow":
				var e: Array = sk.ends(s)
				var base := PackedVector2Array([e[0], e[1]])
				for pass_ in 2:
					draw_polyline(_wobble(base, false, seed_ + pass_ * 977, amp), Color(col, 1.0 if pass_ == 0 else 0.55), w, true)
				if s.type == "arrow":
					var dir: Vector2 = (e[1] - e[0]).normalized()
					var hl := 12.0 + w * 3.0
					for sg in [-1.0, 1.0]:
						draw_line(e[1], e[1] - dir.rotated(sg * 0.45) * hl, col, w, true)
			"pencil":
				var o := Vector2(float(s.x), float(s.y))
				var pp := PackedVector2Array()
				for p in s.pts:
					pp.append(o + Vector2(p[0], p[1]))
				if pp.size() >= 2:
					draw_polyline(pp, col, w, true)
			"text":
				var f := get_theme_default_font()
				var fs: int = sk.FONTS[int(s.width)]
				draw_string(f, Vector2(float(s.x), float(s.y) + fs), str(s.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	## Hachures à 45° dans un polygone convexe.
	func _hatch(poly: PackedVector2Array, col: Color, w: float) -> void:
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for p in poly:
			mn = mn.min(p)
			mx = mx.max(p)
		var step := 9.0 + w
		var c := mn.x + mn.y
		while c < mx.x + mx.y:
			var xs: Array = []
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				var da := a.x + a.y - c
				var db := b.x + b.y - c
				if (da <= 0.0 and db >= 0.0) or (da >= 0.0 and db <= 0.0):
					var den := db - da
					var t := 0.5 if absf(den) < 0.0001 else -da / den
					xs.append(a.lerp(b, t))
			if xs.size() >= 2:
				var p1: Vector2 = xs[0]
				var p2: Vector2 = xs[0]
				for q in xs:
					if q.x < p1.x:
						p1 = q
					if q.x > p2.x:
						p2 = q
				draw_line(p1, p2, Color(col, 0.45), maxf(1.2, w * 0.4), true)
			c += step

	func _selection(s: Dictionary) -> void:
		var z: float = sk.board.zoom
		var col: Color = sk.T.OK
		var b: Rect2 = sk.bounds(s).grow(6.0 / z)
		var step := 6.0 / z
		var x := b.position.x
		while x < b.end.x:
			var x2 := minf(x + step, b.end.x)
			draw_line(Vector2(x, b.position.y), Vector2(x2, b.position.y), col, 1.5 / z)
			draw_line(Vector2(x, b.end.y), Vector2(x2, b.end.y), col, 1.5 / z)
			x += step * 2.0
		var y := b.position.y
		while y < b.end.y:
			var y2 := minf(y + step, b.end.y)
			draw_line(Vector2(b.position.x, y), Vector2(b.position.x, y2), col, 1.5 / z)
			draw_line(Vector2(b.end.x, y), Vector2(b.end.x, y2), col, 1.5 / z)
			y += step * 2.0
		var hp: Array = []
		if s.type == "arrow" or s.type == "line":
			hp = sk.ends(s)
		elif sk.BOXES.has(str(s.type)):
			hp = [sk.bounds(s).end]
		for p in hp:
			draw_circle(p, 7.0 / z, sk.T.BG)
			draw_arc(p, 7.0 / z, 0, TAU, 16, col, 2.0 / z)


class Overlay extends Control:
	var sk
	var down := false
	var panning := false

	func _gui_input(e: InputEvent) -> void:
		if sk != null:
			sk.tool_input(e)
			accept_event()


# ------------------------------------------------------------------ Barre d'outils flottante

class Bar extends PanelContainer:
	var sk
	var toggle: Button
	var body: HFlowContainer
	var btns := {}
	var swatches: Array = []
	var wbtns: Array = []
	var fill_b: Button
	var open := true

	func build() -> void:
		position = Vector2(10, 52)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(sk.T.CARD, 0.94)
		sb.set_corner_radius_all(6)
		sb.set_content_margin_all(4)
		sb.border_color = sk.T.FIELD_HI
		sb.set_border_width_all(2)
		add_theme_stylebox_override("panel", sb)
		var v := VBoxContainer.new()
		add_child(v)
		toggle = _btn("Dessin ▾", "")
		toggle.custom_minimum_size = Vector2(110, 44)
		toggle.pressed.connect(func():
			open = not open
			body.visible = open
			toggle.text = "Dessin ▾" if open else "Dessin ▸"
			relayout())
		v.add_child(toggle)
		body = HFlowContainer.new()
		body.add_theme_constant_override("h_separation", 4)
		body.add_theme_constant_override("v_separation", 4)
		v.add_child(body)
		for t in sk.TOOLS:
			var b := _btn("", "tool")
			b.set_meta("icon", t)
			b.tooltip_text = sk.TOOL_TIPS[t]
			b.pressed.connect(func(): sk.set_tool(t))
			body.add_child(b)
			btns[t] = b
		for c in sk.COLORS:
			var b2 := _btn("", "color")
			b2.set_meta("col", c)
			b2.tooltip_text = "Couleur"
			b2.pressed.connect(func():
				sk.color = c
				sk.apply_style())
			body.add_child(b2)
			swatches.append(b2)
		for i in 3:
			var b3 := _btn("", "width")
			b3.set_meta("wi", i)
			b3.tooltip_text = "Épaisseur"
			b3.pressed.connect(func():
				sk.wi = i
				sk.apply_style())
			body.add_child(b3)
			wbtns.append(b3)
		fill_b = _btn("", "fill")
		fill_b.tooltip_text = "Remplissage hachuré"
		fill_b.pressed.connect(func():
			sk.fill = not sk.fill
			sk.apply_style())
		body.add_child(fill_b)
		var un := _btn("↶", "")
		un.tooltip_text = "Annuler (Ctrl+Z)"
		un.pressed.connect(func(): sk.undo())
		body.add_child(un)
		var re := _btn("↷", "")
		re.tooltip_text = "Rétablir (Ctrl+Y)"
		re.pressed.connect(func(): sk.redo())
		body.add_child(re)
		var dl := _btn("Suppr", "")
		dl.tooltip_text = "Supprimer la sélection"
		dl.pressed.connect(func(): sk.delete_selected())
		body.add_child(dl)
		var dp := _btn("Dupl.", "")
		dp.tooltip_text = "Dupliquer (Ctrl+D)"
		dp.pressed.connect(func(): sk.duplicate_selected())
		body.add_child(dp)
		refresh()

	func _btn(txt: String, kind: String) -> Button:
		var b := Button.new()
		b.text = txt
		b.custom_minimum_size = Vector2(44, 44)
		b.focus_mode = Control.FOCUS_NONE
		b.set_meta("kind", kind)
		b.draw.connect(_icon.bind(b))
		return b

	func relayout() -> void:
		if sk == null or sk.board.canvas == null:
			return
		var w := minf(sk.board.canvas.size.x - 20.0, 600.0)
		custom_minimum_size.x = maxf(w, 120.0)
		size = Vector2(custom_minimum_size.x, 0)

	func refresh() -> void:
		for t in btns:
			(btns[t] as Button).queue_redraw()
		for b in swatches:
			b.queue_redraw()
		for b in wbtns:
			b.queue_redraw()
		fill_b.queue_redraw()

	func _icon(b: Button) -> void:
		var kind := str(b.get_meta("kind"))
		var r := Vector2(b.size)
		var c := r * 0.5
		var on := false
		var col: Color = sk.T.TEXT
		match kind:
			"tool":
				on = sk.tool == str(b.get_meta("icon"))
			"color":
				on = sk.color == str(b.get_meta("col"))
			"width":
				on = sk.wi == int(b.get_meta("wi"))
			"fill":
				on = sk.fill
		if on:
			b.draw_rect(Rect2(Vector2.ZERO, r), Color(sk.T.OK, 0.28))
			b.draw_rect(Rect2(Vector2.ZERO, r), sk.T.OK, false, 2.0)
		match kind:
			"color":
				b.draw_circle(c, 13.0, Color(str(b.get_meta("col"))))
			"width":
				b.draw_line(Vector2(10, c.y), Vector2(r.x - 10, c.y), col, float(sk.WIDTHS[int(b.get_meta("wi"))]))
			"fill":
				b.draw_rect(Rect2(c - Vector2(12, 12), Vector2(24, 24)), col, false, 2.0)
				for i in range(-2, 3):
					b.draw_line(c + Vector2(-12 + i * 6, 12), c + Vector2(12 + i * 6, -12), Color(col, 0.7), 1.5)
			"tool":
				_tool_icon(b, str(b.get_meta("icon")), c, col)

	func _tool_icon(b: Button, t: String, c: Vector2, col: Color) -> void:
		match t:
			"select":
				b.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -12), c + Vector2(-8, 10), c + Vector2(-3, 5), c + Vector2(2, 13), c + Vector2(5, 11), c + Vector2(0, 3), c + Vector2(7, 3)]), col)
			"hand":
				b.draw_arc(c + Vector2(0, 2), 10.0, PI, TAU, 12, col, 2.0)
				for i in 4:
					b.draw_line(c + Vector2(-9 + i * 6, 2), c + Vector2(-9 + i * 6, -10), col, 2.0)
				b.draw_line(c + Vector2(-9, 2), c + Vector2(-9, 10), col, 2.0)
				b.draw_line(c + Vector2(9, 2), c + Vector2(9, 10), col, 2.0)
				b.draw_line(c + Vector2(-9, 10), c + Vector2(9, 10), col, 2.0)
			"rect":
				b.draw_rect(Rect2(c - Vector2(12, 9), Vector2(24, 18)), col, false, 2.0)
			"ellipse":
				b.draw_arc(c, 11.0, 0, TAU, 24, col, 2.0)
			"diamond":
				b.draw_polyline(PackedVector2Array([c + Vector2(0, -12), c + Vector2(12, 0), c + Vector2(0, 12), c + Vector2(-12, 0), c + Vector2(0, -12)]), col, 2.0)
			"arrow":
				b.draw_line(c + Vector2(-12, 10), c + Vector2(11, -10), col, 2.0)
				b.draw_line(c + Vector2(11, -10), c + Vector2(2, -9), col, 2.0)
				b.draw_line(c + Vector2(11, -10), c + Vector2(10, -1), col, 2.0)
			"line":
				b.draw_line(c + Vector2(-12, 10), c + Vector2(12, -10), col, 2.0)
			"pencil":
				b.draw_polyline(PackedVector2Array([c + Vector2(-12, 6), c + Vector2(-6, -6), c + Vector2(0, 4), c + Vector2(6, -8), c + Vector2(12, 2)]), col, 2.0)
			"text":
				b.draw_line(c + Vector2(-9, -10), c + Vector2(9, -10), col, 3.0)
				b.draw_line(c + Vector2(0, -10), c + Vector2(0, 11), col, 3.0)
			"eraser":
				b.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, 4), c + Vector2(-2, -8), c + Vector2(12, -2), c + Vector2(2, 10)]), Color(col, 0.55))
				b.draw_polyline(PackedVector2Array([c + Vector2(-12, 4), c + Vector2(-2, -8), c + Vector2(12, -2), c + Vector2(2, 10), c + Vector2(-12, 4)]), col, 2.0)
