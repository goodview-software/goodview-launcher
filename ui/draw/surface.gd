extends Control
## Surface du plan : vue (pan/zoom interpolé), couches de rendu (arrière / zones / avant / surcouche), entrées souris,
## tactile et molette, édition de texte directe sur le canevas, export PNG. Les zones de chat sont des Controls
## hébergés dans `world` (qui suit pan/zoom) ; tout le reste est dessiné par Render, sans aucun nœud par forme.

const Geom := preload("res://ui/draw/geom.gd")
const Render := preload("res://ui/draw/render.gd")
const Scene := preload("res://ui/draw/scene.gd")
const Tools := preload("res://ui/draw/tools.gd")
const T := preload("res://ui/theme.gd")
const ZMIN := 0.1
const ZMAX := 4.0
const LOD := 0.5

signal view_changed
signal tool_changed
signal sel_changed

var host: Node
var scene: Scene
var tools: Tools
var world: Control
var front: Control
var overlay: Control
var ed: TextEdit
var pan := Vector2(24, 24)
var zoom := 1.0
var t_pan := Vector2(24, 24)
var t_zoom := 1.0
var lod := false
var grid_on := false
var editing_id := ""
var vis_back: Array = []
var vis_front: Array = []
var pinching := false
var _part_key := []
var _touches := {}
var _pinch_prev := {}
var _ed_el: Dictionary = {}
var _ed_mode := ""
var _ed_new := false
var _ed_pos := Vector2.ZERO
var _committing := false


func setup(h: Node) -> void:
	host = h
	scene = Scene.new()
	tools = Tools.new(self)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	focus_mode = Control.FOCUS_CLICK
	clip_contents = true
	Geom.font = get_theme_default_font()
	world = Control.new()
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	front = Layer.new()
	front.S = self
	front.is_front = true
	front.set_anchors_preset(Control.PRESET_FULL_RECT)
	front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	front.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(front)
	overlay = Over.new()
	overlay.S = self
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	ed = TextEdit.new()
	ed.visible = false
	ed.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	ed.scroll_fit_content_height = true
	for sn in ["normal", "focus", "read_only"]:
		ed.add_theme_stylebox_override(sn, StyleBoxEmpty.new())
	ed.add_theme_color_override("selection_color", Color(T.OK, 0.35))
	ed.text_changed.connect(_ed_fit)
	ed.focus_exited.connect(func(): edit_commit())
	ed.gui_input.connect(_ed_input)
	add_child(ed)
	scene.changed.connect(redraw)
	scene.reset.connect(redraw)
	set_process(false)


func _draw() -> void:
	Render.draw_grid(self, self)
	Render.draw_layer(self, self, false)


func redraw() -> void:
	queue_redraw()
	if front != null:
		front.queue_redraw()
		overlay.queue_redraw()


# ------------------------------------------------------------------ coordonnées

func w2c(v: Vector2) -> Vector2:
	return pan + v * zoom


func c2w(v: Vector2) -> Vector2:
	return (v - pan) / zoom


func view_world() -> Rect2:
	return Rect2(-pan / zoom, size / zoom)


func tol() -> float:
	return 8.0 / zoom


## Éléments visibles répartis en couche arrière / avant (un élément au-dessus d'une zone qu'il recouvre passe devant les zones).
func partition() -> void:
	var key := [scene.rev, pan, zoom, size, lod, editing_id]
	if key == _part_key:
		return
	_part_key = key
	vis_back = []
	vis_front = []
	var view := view_world().grow(30.0 / zoom)
	var zr: Array = []
	var i := 0
	for el in scene.els:
		if el.type == "zone":
			zr.append([i, Geom.rect(el)])
		i += 1
	i = 0
	for el in scene.els:
		var ab := Geom.aabb(el)
		if el.type in Geom.LINEAR:
			ab = ab.grow(30.0)
		if not ab.intersects(view):
			i += 1
			continue
		var fr := false
		if not zr.is_empty() and el.type != "zone" and el.type != "frame":
			for z in zr:
				if z[0] >= i:
					break
				if (z[1] as Rect2).intersects(ab):
					fr = true
					break
		(vis_front if fr else vis_back).append(el)
		i += 1


# ------------------------------------------------------------------ vue

func _apply() -> void:
	world.position = pan
	world.scale = Vector2(zoom, zoom)
	Geom.zoom = zoom
	var nl := zoom < LOD
	if nl != lod:
		lod = nl
		world.visible = not nl
		if host != null:
			host.on_lod(nl)
	if ed != null and ed.visible:
		_ed_place()
	redraw()
	view_changed.emit()


func set_view(p: Vector2, z: float) -> void:
	pan = p
	zoom = clampf(z, ZMIN, ZMAX)
	t_pan = pan
	t_zoom = zoom
	_apply()


func pan_by(d: Vector2) -> void:
	pan += d
	t_pan += d
	_apply()


## Zoom centré sur un point du canevas, interpolé (sans à-coups).
func zoom_at(cpos: Vector2, factor: float, smooth := true) -> void:
	var nz := clampf(t_zoom * factor, ZMIN, ZMAX)
	if is_equal_approx(nz, t_zoom):
		return
	var wp := (cpos - t_pan) / t_zoom
	t_zoom = nz
	t_pan = cpos - wp * t_zoom
	if smooth:
		set_process(true)
	else:
		pan = t_pan
		zoom = t_zoom
		_apply()


func center_on(wp: Vector2, z: float) -> void:
	t_zoom = clampf(z, ZMIN, ZMAX)
	t_pan = size * 0.5 - wp * t_zoom
	set_process(true)


func zoom_to(z: float, smooth := true) -> void:
	zoom_at(size * 0.5, z / t_zoom, smooth)


## Cadre un rectangle du monde dans la vue.
func fit_rect(r: Rect2, max_zoom := 1.0, smooth := true) -> void:
	if size.x < 10.0 or r.size.x <= 0.0 and r.size.y <= 0.0:
		return
	r = r.grow(40.0)
	t_zoom = clampf(minf(size.x / r.size.x, size.y / r.size.y), ZMIN, max_zoom)
	t_pan = size * 0.5 - r.get_center() * t_zoom
	if smooth:
		set_process(true)
	else:
		pan = t_pan
		zoom = t_zoom
		_apply()


func fit_all() -> void:
	if scene.els.is_empty():
		return
	fit_rect(scene.bounds_of(scene.els.map(func(e): return e.id)))


func fit_selection() -> void:
	if not scene.sel.is_empty():
		fit_rect(scene.bounds_of(scene.sel.keys()), 2.0)


func _process(dt: float) -> void:
	var k := 1.0 - exp(-dt * 16.0)
	zoom = lerpf(zoom, t_zoom, k)
	pan = pan.lerp(t_pan, k)
	if absf(zoom - t_zoom) < 0.0008 * t_zoom and pan.distance_to(t_pan) < 0.4:
		zoom = t_zoom
		pan = t_pan
		set_process(false)
	_apply()


func wheel(e: InputEventMouseButton) -> bool:
	var f: float = e.factor if e.factor > 0.0 else 1.0
	var up := e.button_index == MOUSE_BUTTON_WHEEL_UP
	match e.button_index:
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if e.ctrl_pressed or e.meta_pressed:
				zoom_at(get_local_mouse_position(), pow(1.12, f if up else -f))
			elif e.shift_pressed:
				pan_by(Vector2(55.0 * f, 0) * (1.0 if up else -1.0))
			else:
				pan_by(Vector2(0, 55.0 * f) * (1.0 if up else -1.0))
			return true
		MOUSE_BUTTON_WHEEL_LEFT:
			pan_by(Vector2(55.0 * f, 0))
			return true
		MOUSE_BUTTON_WHEEL_RIGHT:
			pan_by(Vector2(-55.0 * f, 0))
			return true
	return false


# ------------------------------------------------------------------ entrées

func _gui_input(e: InputEvent) -> void:
	_route(e)


func _route(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.pressed and wheel(e):
			accept_event()
			return
		tools.event(e)
	elif e is InputEventMouseMotion:
		tools.event(e)


## Pincement / deux doigts sur écran tactile.
func touch_event(e: InputEvent) -> void:
	var off := get_global_rect().position
	if e is InputEventScreenTouch:
		if e.pressed:
			_touches[e.index] = e.position - off
			if _touches.size() == 2:
				pinching = true
				tools.cancel()
				_pinch_prev = {"d": _touch_d(), "c": _touch_c()}
		else:
			_touches.erase(e.index)
			if _touches.size() < 2:
				pinching = false
	elif e is InputEventScreenDrag and _touches.has(e.index):
		_touches[e.index] = e.position - off
		if _touches.size() == 2 and not _pinch_prev.is_empty():
			var d := _touch_d()
			var c := _touch_c()
			if float(_pinch_prev.d) > 4.0 and d > 4.0:
				zoom_at(c, d / float(_pinch_prev.d), false)
			pan_by(c - (_pinch_prev.c as Vector2))
			_pinch_prev = {"d": d, "c": c}


func _touch_d() -> float:
	var v := _touches.values()
	return (v[0] as Vector2).distance_to(v[1])


func _touch_c() -> Vector2:
	var v := _touches.values()
	return ((v[0] as Vector2) + (v[1] as Vector2)) * 0.5


func set_cursor(shape: Control.CursorShape) -> void:
	mouse_default_cursor_shape = shape
	if overlay != null:
		overlay.mouse_default_cursor_shape = shape


# ------------------------------------------------------------------ édition de texte directe

func is_editing() -> bool:
	return ed != null and ed.visible


func edit_new_text(wp: Vector2) -> void:
	edit_commit()
	_ed_el = {}
	_ed_mode = "text"
	_ed_new = true
	_ed_pos = wp
	editing_id = ""
	_ed_open("", float(scene.style.fontSize), str(scene.style.stroke))


## Édite un élément existant : "text" (texte), "label" (texte lié à une forme/flèche), "name" (nom d'un cadre).
func edit_el(el: Dictionary, mode: String) -> void:
	edit_commit()
	_ed_el = el
	_ed_mode = mode
	_ed_new = false
	editing_id = str(el.id) if mode == "text" else ""
	var fs := float(el.get("fontSize", 20))
	var txt := str(el.get("text", "")) if mode == "text" else (str(el.get("label", "")) if mode == "label" else str(el.get("name", "")))
	if mode == "name":
		fs = 18.0 / maxf(zoom, 0.1) if zoom < 1.0 else 18.0
	_ed_open(txt, fs, str(el.get("stroke", "e8ecf1")) if mode != "name" else "e8ecf1")
	if mode == "name":
		ed.select_all()
	redraw()


func _ed_open(txt: String, fs: float, col: String) -> void:
	ed.text = txt
	ed.set_meta("fs", fs)
	ed.add_theme_font_override("font", Geom.f())
	ed.add_theme_color_override("font_color", Color(col))
	ed.add_theme_color_override("caret_color", Color(col))
	ed.visible = true
	_ed_fit()
	ed.grab_focus()
	ed.set_caret_column(txt.length())
	redraw()


func _ed_fs() -> int:
	var fs := float(ed.get_meta("fs", 20.0))
	return clampi(int(fs * (zoom if _ed_mode != "name" else 1.0)), 6, 400)


func _ed_fit() -> void:
	var fs := _ed_fs()
	ed.add_theme_font_size_override("font_size", fs)
	var s := Geom.f().get_multiline_string_size(ed.text if ed.text != "" else " ", HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	ed.size = Vector2(maxf(s.x + 14.0, 40.0), s.y + 6.0)
	_ed_place()


func _ed_place() -> void:
	var p: Vector2
	if _ed_new:
		p = w2c(_ed_pos)
	elif _ed_mode == "label":
		var c := Geom.mid_of(Geom.world_pts(_ed_el)) if str(_ed_el.type) in Geom.LINEAR else Geom.center(_ed_el)
		p = w2c(c) - ed.size * 0.5
	elif _ed_mode == "name":
		p = w2c(Vector2(float(_ed_el.x), float(_ed_el.y))) + Vector2(6, 2)
	else:
		p = w2c(Vector2(float(_ed_el.x), float(_ed_el.y)))
	ed.position = p


func _ed_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed:
		if e.keycode == KEY_ESCAPE or (e.keycode == KEY_ENTER and (e.ctrl_pressed or _ed_mode == "name")) or (e.keycode == KEY_KP_ENTER and e.ctrl_pressed):
			ed.accept_event()
			edit_commit()
			grab_focus()


func edit_commit() -> void:
	if _committing or not is_editing():
		return
	_committing = true
	var t := ed.text
	var mode := _ed_mode
	var el := _ed_el
	var was_new := _ed_new
	var pos := _ed_pos
	ed.visible = false
	_ed_el = {}
	editing_id = ""
	var changed := false
	if mode == "text":
		if was_new:
			if t.strip_edges() != "":
				var n := scene.make("text", pos.x, pos.y)
				n.text = t
				Geom.fit_text(n)
				scene.add(n)
				scene.select([n.id])
				changed = true
		elif not el.is_empty():
			if t.strip_edges() == "":
				scene.remove([el.id])
			else:
				el.text = t
				Geom.fit_text(el)
				scene.mark(el)
			changed = true
	elif not el.is_empty():
		if mode == "label":
			el.label = t.strip_edges()
		else:
			el.name = t.strip_edges() if t.strip_edges() != "" else "Cadre"
		scene.mark(el)
		changed = true
	if changed:
		scene.commit()
		scene.touch()
		tools.after_create()
	_committing = false
	redraw()


# ------------------------------------------------------------------ export PNG

func export_png(only_sel: bool) -> String:
	var ids: Array = scene.sel.keys() if only_sel and not scene.sel.is_empty() else scene.els.map(func(e): return e.id)
	if ids.is_empty():
		return ""
	if DisplayServer.get_name() == "headless":
		return ""  # pas de rendu en mode headless
	var r := scene.bounds_of(ids).grow(24.0)
	var k := clampf(2.0, 0.1, 4096.0 / maxf(maxf(r.size.x, r.size.y), 1.0))
	var px := Vector2i(maxi(int(r.size.x * k), 8), maxi(int(r.size.y * k), 8))
	var vp := SubViewport.new()
	vp.size = px
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var prox := Proxy.new()
	prox.scene = scene
	prox.host = host
	prox.zoom = k
	prox.pan = -r.position * k
	prox.size = Vector2(px)
	prox.ids = {}
	if only_sel and not scene.sel.is_empty():
		prox.ids = scene.sel.duplicate()
	var view := ExportView.new()
	view.S = prox
	view.size = Vector2(px)
	vp.add_child(view)
	add_child(vp)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	if img == null or img.is_empty():
		return ""
	var dir := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if dir == "":
		dir = OS.get_environment("HOME")
	var t := Time.get_datetime_dict_from_system()
	var path := "%s/plan_%04d-%02d-%02d_%02d%02d%02d.png" % [dir, t.year, t.month, t.day, t.hour, t.minute, t.second]
	if img.save_png(path) != OK:
		return ""
	return path


## Vue figée pour l'export : mêmes fonctions de rendu, zones dessinées en vignettes.
class Proxy extends RefCounted:
	var scene
	var host
	var zoom := 1.0
	var pan := Vector2.ZERO
	var size := Vector2.ZERO
	var ids := {}
	var lod := true
	var editing_id := ""
	var grid_on := false
	var tools := {"erase_set": {}}
	var vis_back: Array = []
	var vis_front: Array = []

	func w2c(v: Vector2) -> Vector2:
		return pan + v * zoom

	func partition() -> void:
		vis_back = []
		for el in scene.els:
			if ids.is_empty() or ids.has(el.id):
				vis_back.append(el)


class ExportView extends Control:
	var S

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("0e1116"))
		Render.draw_layer(self, S, false)


class Layer extends Control:
	var S
	var is_front := false

	func _draw() -> void:
		Render.draw_layer(self, S, true)


## Surcouche : sélection, poignées, guides. N'intercepte la souris que sur une poignée (ou partout avec un outil de tracé).
class Over extends Control:
	var S

	func _draw() -> void:
		Render.draw_overlay(self, S)

	func _has_point(p: Vector2) -> bool:
		return S.tools.captures(p)

	func _gui_input(e: InputEvent) -> void:
		S._route(e)
