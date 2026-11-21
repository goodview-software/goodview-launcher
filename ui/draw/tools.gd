extends RefCounted
## Interaction du plan, calquée sur Excalidraw : outils, sélection, déplacement / redimensionnement / rotation,
## aimantation, flèches liées, presse-papiers, groupes, ordre, raccourcis clavier.

const Geom := preload("res://ui/draw/geom.gd")
const PREFIX := "gvplan:"
const DRAW := ["rectangle", "diamond", "ellipse", "arrow", "line", "freedraw", "frame"]
const KEYS := {KEY_V: "select", KEY_H: "hand", KEY_R: "rectangle", KEY_D: "diamond", KEY_O: "ellipse", KEY_A: "arrow", KEY_L: "line",
		KEY_P: "freedraw", KEY_T: "text", KEY_E: "eraser", KEY_F: "frame"}
const DIGITS := {KEY_1: "select", KEY_2: "rectangle", KEY_3: "diamond", KEY_4: "ellipse", KEY_5: "arrow", KEY_6: "line", KEY_7: "freedraw",
		KEY_8: "text", KEY_9: "image", KEY_0: "eraser"}
const CURSORS := {"nw": Control.CURSOR_FDIAGSIZE, "se": Control.CURSOR_FDIAGSIZE, "ne": Control.CURSOR_BDIAGSIZE, "sw": Control.CURSOR_BDIAGSIZE,
		"n": Control.CURSOR_VSIZE, "s": Control.CURSOR_VSIZE, "e": Control.CURSOR_HSIZE, "w": Control.CURSOR_HSIZE}

var S  # surface
var sc  # scène
var tool := "select"
var locked := false
var mode := ""  # "", pan, marquee, move, resize, rotate, endpoint, draw, poly, erase, label
var hover := ""
var bind_hover := ""
var guides: Array = []
var marquee := Rect2()
var erase_set := {}
var _p0 := Vector2.ZERO
var _c0 := Vector2.ZERO
var _last := Vector2.ZERO
var _orig := {}
var _ob := Rect2()
var _moved := false
var _draft := {}
var _dpts := PackedVector2Array()
var _handle := ""
var _space := false
var _dup_done := false
var _click_sel := ""
var _label_arrow := ""
var _grab_angle := 0.0
var _clip: Array = []
var _style_clip := {}
var _menu: PopupMenu
var _menu_hit := ""


func _init(s) -> void:
	S = s
	sc = s.scene


# ------------------------------------------------------------------ outils

func set_tool(t: String) -> void:
	S.edit_commit()
	cancel()
	if t == "image":
		S.host.add_image_dialog()
		return
	tool = t
	if t != "select" and t != "hand":
		sc.clear_sel()
	hover = ""
	update_cursor(S.get_local_mouse_position())
	S.tool_changed.emit()
	S.redraw()


func after_create() -> void:
	if not locked and tool != "select":
		tool = "select"
		S.tool_changed.emit()
	update_cursor(S.get_local_mouse_position())
	S.sel_changed.emit()


func toggle_lock() -> void:
	locked = not locked
	S.tool_changed.emit()


## Abandonne le geste en cours (pincement, Échap) : restaure l'état d'avant.
func cancel() -> void:
	if mode in ["move", "resize", "rotate"]:
		_restore_orig()
	if mode in ["draw", "poly"] and not _draft.is_empty():
		sc.remove([_draft.id])
	_draft = {}
	mode = ""
	marquee = Rect2()
	guides = []
	bind_hover = ""
	erase_set = {}
	S.redraw()


func busy() -> bool:
	return mode != ""


func captures(p: Vector2) -> bool:
	if S.pinching:
		return false
	if tool != "select" or _space or mode != "":
		return true
	return handle_at(p) != ""


# ------------------------------------------------------------------ recherche d'éléments

func top_hit(wp: Vector2, locked_too := false) -> Dictionary:
	var tol: float = S.tol()
	for i in range(sc.els.size() - 1, -1, -1):
		var el: Dictionary = sc.els[i]
		if el.locked and not locked_too:
			continue
		var ab := Geom.aabb(el).grow(tol + 20.0)
		if not ab.has_point(wp):
			continue
		if Geom.hit(el, wp, tol):
			return el
	return {}


func label_hit(wp: Vector2) -> Dictionary:
	for a in sc.arrows():
		if str(a.get("link", "")) != "":
			var lr := Geom.label_rect(a, str(S.host.link_style(a).name))
			if lr.has_point(wp):
				return a
	return {}


func bind_target(wp: Vector2, except := "") -> String:
	var tol: float = 10.0 / S.zoom
	for i in range(sc.els.size() - 1, -1, -1):
		var el: Dictionary = sc.els[i]
		if el.id == except or el.locked or not (el.type in Geom.BINDABLE):
			continue
		if not Geom.aabb(el).grow(tol).has_point(wp):
			continue
		if el.type == "frame":
			if Geom.hit(el, wp, tol) and not Geom.rect(el).grow(-tol * 2.0).has_point(wp):
				return str(el.id)
			continue
		if Geom.point_inside(el, wp) or Geom.hit(el, wp, tol):
			return str(el.id)
	return ""


# ------------------------------------------------------------------ cadre de sélection et poignées

func _rotatable(els: Array) -> bool:
	for el in els:
		if el.type in ["zone", "frame", "arrow", "line"]:
			return false
	return true


func sel_frame() -> Dictionary:
	var els: Array = sc.selected()
	if els.is_empty() or mode in ["marquee", "pan"]:
		return {}
	var z: float = S.zoom
	if els.size() == 1 and els[0].type in ["arrow", "line"]:
		var wp := Geom.world_pts(els[0])
		if wp.size() < 2 or els[0].locked:
			return {}
		return {"kind": "linear", "handles": [{"name": "ep0", "pos": S.w2c(wp[0])}, {"name": "ep1", "pos": S.w2c(wp[wp.size() - 1])}]}
	var r: Rect2
	var a := 0.0
	if els.size() == 1:
		r = Geom.rect(els[0])
		a = float(els[0].angle)
	else:
		r = sc.bounds_of(sc.sel.keys())
	var pad := 6.0 / z
	r = r.grow(pad)
	var c := r.get_center()
	var poly := PackedVector2Array()
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		poly.append(S.w2c(c + (p - c).rotated(a)))
	var out := {"kind": "box", "poly": poly, "handles": [], "r": r, "angle": a}
	var all_locked := true
	for el in els:
		if not el.locked:
			all_locked = false
	if all_locked:
		return out
	var hs: Array = out.handles
	var wide := r.size.x * z > 44.0
	var tall := r.size.y * z > 44.0
	var defs := [["nw", Vector2(0, 0)], ["ne", Vector2(1, 0)], ["se", Vector2(1, 1)], ["sw", Vector2(0, 1)]]
	if wide:
		defs.append(["n", Vector2(0.5, 0)])
		defs.append(["s", Vector2(0.5, 1)])
	if tall:
		defs.append(["w", Vector2(0, 0.5)])
		defs.append(["e", Vector2(1, 0.5)])
	for d in defs:
		var lp: Vector2 = r.position + r.size * (d[1] as Vector2)
		hs.append({"name": d[0], "pos": S.w2c(c + (lp - c).rotated(a))})
	var up := Vector2(0, -1).rotated(a)
	var top = S.w2c(c + (Vector2(0, -r.size.y * 0.5)).rotated(a))
	out["top"] = top
	out["right"] = S.w2c(c + Vector2(r.size.x * 0.5, 0).rotated(a))
	if _rotatable(els):
		hs.append({"name": "rot", "pos": top + up * 26.0})
	if els.size() == 1 and els[0].type == "zone":
		hs.append({"name": "port", "pos": (out.right as Vector2) + Vector2(26, 0)})
	return out


func handle_at(cp: Vector2) -> String:
	if S.scene.sel.is_empty():
		return ""
	var fr := sel_frame()
	if fr.is_empty():
		return ""
	var best := ""
	var bd := 13.0
	for hd in fr.handles:
		var d: float = (hd.pos as Vector2).distance_to(cp)
		if d <= bd:
			bd = d
			best = str(hd.name)
	return best


func update_cursor(cp: Vector2) -> void:
	var c := Control.CURSOR_ARROW
	if _space or tool == "hand":
		c = Control.CURSOR_DRAG
	elif tool == "text":
		c = Control.CURSOR_IBEAM
	elif tool != "select":
		c = Control.CURSOR_CROSS
	elif mode in ["move", "resize", "rotate", "endpoint"]:
		c = Control.CURSOR_MOVE
	elif mode == "":
		var h := handle_at(cp)
		if h != "":
			c = CURSORS.get(h, Control.CURSOR_MOVE if h.begins_with("ep") else Control.CURSOR_CROSS)
		elif hover != "":
			c = Control.CURSOR_MOVE
	S.set_cursor(c)


# ------------------------------------------------------------------ événements souris

func event(e: InputEvent) -> void:
	if S.pinching:
		return
	var cp: Vector2 = S.get_local_mouse_position()
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				press(cp, e)
			else:
				release(cp, e)
		elif e.button_index == MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				S.edit_commit()
				mode = "pan"
				_c0 = cp
				_last = cp
				S.set_cursor(Control.CURSOR_DRAG)
			elif mode == "pan":
				mode = ""
				update_cursor(cp)
		elif e.button_index == MOUSE_BUTTON_RIGHT and e.pressed:
			_context(cp)
	elif e is InputEventMouseMotion:
		motion(cp, e)


func press(cp: Vector2, e: InputEventMouseButton) -> void:
	S.edit_commit()
	S.get_viewport().gui_release_focus()
	S.grab_focus()
	_c0 = cp
	_last = cp
	_p0 = S.c2w(cp)
	_moved = false
	_click_sel = ""
	_label_arrow = ""
	if mode == "poly":
		_poly_press(e)
		return
	if _space or tool == "hand":
		mode = "pan"
		S.set_cursor(Control.CURSOR_DRAG)
		return
	match tool:
		"select":
			_press_select(cp, e)
		"eraser":
			mode = "erase"
			erase_set = {}
			_erase_at(_p0)
		"text":
			S.edit_new_text(_snap_pt(_p0))
		_:
			_press_draw(e)


func motion(cp: Vector2, e: InputEventMouseMotion) -> void:
	var wp: Vector2 = S.c2w(cp)
	match mode:
		"":
			if tool == "select":
				var h := top_hit(wp)
				var nh := str(h.id) if not h.is_empty() else ""
				if nh != hover:
					hover = nh
					S.overlay.queue_redraw()
			elif hover != "":
				hover = ""
				S.overlay.queue_redraw()
			update_cursor(cp)
		"pan":
			S.pan_by(cp - _last)
		"marquee":
			marquee = Rect2(_p0, Vector2.ZERO).expand(wp)
			var ids: Array = []
			for el in sc.els:
				if marquee.encloses(Geom.aabb(el)):
					ids.append(el.id)
			if e.shift_pressed:
				for id in _orig:
					ids.append(id)
			sc.sel = {}
			for id in sc.expand_groups(ids):
				sc.sel[id] = true
			S.sel_changed.emit()
			S.redraw()
		"move":
			if not _moved and cp.distance_to(_c0) < 3.0:
				return
			_moved = true
			_do_move(wp, e)
		"resize":
			_do_resize(wp, e)
		"rotate":
			_do_rotate(wp, e)
		"endpoint":
			_do_endpoint(wp, e)
		"draw":
			_do_draw(wp, e)
		"poly":
			_poly_motion(wp, e)
		"erase":
			_erase_at(wp)
		"label":
			if cp.distance_to(_c0) > 4.0:
				mode = ""
	_last = cp


func release(cp: Vector2, e: InputEventMouseButton) -> void:
	match mode:
		"pan":
			mode = ""
			update_cursor(cp)
			S.host.touch()
		"marquee":
			mode = ""
			marquee = Rect2()
			S.sel_changed.emit()
			S.redraw()
		"move":
			mode = ""
			guides = []
			if _moved:
				_end_move()
			elif _click_sel != "":
				sc.select([_click_sel])
				S.sel_changed.emit()
			S.redraw()
		"resize", "rotate":
			mode = ""
			_orig = {}
			sc.refresh_arrows(sc.sel)
			sc.commit()
			sc.touch()
			S.sel_changed.emit()
		"endpoint":
			mode = ""
			bind_hover = ""
			var el: Dictionary = sc.get_el(str(sc.sel.keys()[0])) if not sc.sel.is_empty() else {}
			if not el.is_empty():
				_finish_arrow(el)
			sc.commit()
			sc.touch()
		"draw":
			_release_draw(cp, e)
		"erase":
			mode = ""
			if not erase_set.is_empty():
				sc.remove(erase_set.keys())
				sc.commit()
			erase_set = {}
			S.redraw()
		"label":
			mode = ""
			var a: Dictionary = sc.get_el(_label_arrow)
			if not a.is_empty():
				S.host.cycle_link(a)
	update_cursor(cp)


# ------------------------------------------------------------------ sélection

func _press_select(cp: Vector2, e: InputEventMouseButton) -> void:
	var hh := handle_at(cp)
	if hh != "":
		_begin_handle(hh)
		return
	var lh := label_hit(_p0)
	if not lh.is_empty() and not e.double_click:
		_label_arrow = str(lh.id)
		mode = "label"
		sc.select([lh.id])
		return
	var el := top_hit(_p0)
	if e.double_click:
		_dbl(el)
		return
	if not el.is_empty():
		var ids: Array = sc.expand_groups([el.id])
		if e.shift_pressed:
			if sc.sel.has(el.id):
				for id in ids:
					sc.sel.erase(id)
			else:
				for id in ids:
					sc.sel[id] = true
			S.sel_changed.emit()
			S.redraw()
			if not sc.sel.has(el.id):
				return
		elif not sc.sel.has(el.id):
			sc.select(ids)
			S.sel_changed.emit()
		elif sc.sel.size() > 1:
			_click_sel = str(el.id)
		_begin_move()
	else:
		if not e.shift_pressed:
			sc.clear_sel()
			S.sel_changed.emit()
		_orig = sc.sel.duplicate()
		mode = "marquee"
		marquee = Rect2(_p0, Vector2.ZERO)


func _dbl(el: Dictionary) -> void:
	if el.is_empty():
		S.edit_new_text(_snap_pt(_p0))
		return
	match str(el.type):
		"text":
			sc.select([el.id])
			S.edit_el(el, "text")
		"rectangle", "diamond", "ellipse":
			sc.select([el.id])
			S.edit_el(el, "label")
		"arrow", "line":
			if str(el.get("link", "")) == "":
				sc.select([el.id])
				S.edit_el(el, "label")
		"frame":
			S.edit_el(el, "name")
		"zone":
			if S.lod:
				S.host.focus_zone(str(el.id))


func select_only(id: String) -> void:
	if not sc.sel.has(id):
		sc.select([id])
		S.sel_changed.emit()


func _begin_move() -> void:
	_snapshot()
	var moving := {}
	for id in sc.sel:
		moving[id] = true
	# un cadre emporte les éléments qu'il contient
	for el in sc.selected():
		if el.type == "frame":
			var r := Geom.rect(el)
			for o in sc.els:
				if not moving.has(o.id) and o.type != "frame" and not o.locked and r.has_point(Geom.center(o)):
					_orig[o.id] = _snap_of(o)
	for el in sc.selected():
		if el.locked:
			_orig.erase(el.id)
	# une flèche déplacée sans sa cible se détache
	for id in _orig.keys():
		var a: Dictionary = sc.get_el(id)
		if a.type == "arrow" or a.type == "line":
			for k in ["start", "end"]:
				if str(a.get(k, "")) != "" and not _orig.has(str(a[k])):
					a[k] = ""
					if str(a.get("link", "")) != "":
						a["link"] = ""
	var b := Rect2()
	var first := true
	for id in _orig:
		var el2: Dictionary = sc.get_el(id)
		b = Geom.aabb(el2) if first else b.merge(Geom.aabb(el2))
		first = false
	_ob = b
	_dup_done = false
	mode = "move"


func _snap_of(el: Dictionary) -> Dictionary:
	var d := {"x": el.x, "y": el.y, "w": el.w, "h": el.h, "angle": el.angle}
	if el.has("points"):
		d["points"] = (el.points as Array).duplicate(true)
	if el.has("fontSize"):
		d["fontSize"] = el.fontSize
	return d


func _snapshot() -> void:
	_orig = {}
	for el in sc.selected():
		_orig[el.id] = _snap_of(el)


func _restore_orig() -> void:
	for id in _orig:
		var el: Dictionary = sc.get_el(id)
		if el.is_empty():
			continue
		var o: Dictionary = _orig[id]
		for k in o:
			el[k] = o[k].duplicate(true) if o[k] is Array else o[k]
		sc.mark(el)
	sc.refresh_arrows(_orig)
	S.host.sync_zones(_orig)
	_orig = {}


func _do_move(wp: Vector2, e: InputEventMouseMotion) -> void:
	var d := wp - _p0
	if e.shift_pressed:
		if absf(d.x) > absf(d.y):
			d.y = 0.0
		else:
			d.x = 0.0
	if e.alt_pressed and not _dup_done:
		_dup_done = true
		var src = sc.selected()
		var cl: Array = sc.clone(src)
		var ids: Array = []
		for c in cl:
			sc.add(c)
			ids.append(c.id)
		sc.sel = {}
		for id in ids:
			sc.sel[id] = true
		_orig = {}
		_snapshot()
		S.sel_changed.emit()
	d = _snap_move(d, _ob, _orig, e.ctrl_pressed)
	for id in _orig:
		var el: Dictionary = sc.get_el(id)
		var o: Dictionary = _orig[id]
		el.x = float(o.x) + d.x
		el.y = float(o.y) + d.y
		sc.mark(el)
	sc.refresh_arrows(_orig)
	S.host.sync_zones(_orig)
	sc.touch()


func _end_move() -> void:
	_orig = {}
	sc.commit()
	S.host.touch()
	S.sel_changed.emit()


func _snap_pt(p: Vector2) -> Vector2:
	if S.grid_on:
		return Vector2(roundf(p.x / 20.0) * 20.0, roundf(p.y / 20.0) * 20.0)
	return p


func _snap_move(d: Vector2, bx: Rect2, excl: Dictionary, off: bool) -> Vector2:
	guides = []
	if off:
		return d
	if S.grid_on:
		return Vector2(roundf((bx.position.x + d.x) / 20.0) * 20.0 - bx.position.x, roundf((bx.position.y + d.y) / 20.0) * 20.0 - bx.position.y)
	var thr: float = 6.0 / S.zoom
	var mx := [bx.position.x + d.x, bx.get_center().x + d.x, bx.end.x + d.x]
	var my := [bx.position.y + d.y, bx.get_center().y + d.y, bx.end.y + d.y]
	var vw: Rect2 = S.view_world()
	var cand: Array = []
	for el in sc.els:
		if excl.has(el.id):
			continue
		var b := Geom.aabb(el)
		if b.intersects(vw):
			cand.append(b)
	var bdx := INF
	var bdy := INF
	for b in cand:
		for t in [b.position.x, b.get_center().x, b.end.x]:
			for a in mx:
				var df: float = t - a
				if absf(df) <= thr and absf(df) < absf(bdx):
					bdx = df
		for t2 in [b.position.y, b.get_center().y, b.end.y]:
			for a2 in my:
				var df2: float = t2 - a2
				if absf(df2) <= thr and absf(df2) < absf(bdy):
					bdy = df2
	if bdx != INF:
		d.x += bdx
	if bdy != INF:
		d.y += bdy
	var nb := Rect2(bx.position + d, bx.size)
	for b in cand:
		for t in [b.position.x, b.get_center().x, b.end.x]:
			for a in [nb.position.x, nb.get_center().x, nb.end.x]:
				if absf(t - a) < 0.5 and guides.size() < 8:
					guides.append([Vector2(a, minf(b.position.y, nb.position.y)), Vector2(a, maxf(b.end.y, nb.end.y))])
		for t2 in [b.position.y, b.get_center().y, b.end.y]:
			for a2 in [nb.position.y, nb.get_center().y, nb.end.y]:
				if absf(t2 - a2) < 0.5 and guides.size() < 8:
					guides.append([Vector2(minf(b.position.x, nb.position.x), a2), Vector2(maxf(b.end.x, nb.end.x), a2)])
	return d


# ------------------------------------------------------------------ poignées : redimensionner / tourner / extrémités

func _begin_handle(h: String) -> void:
	_handle = h
	if h == "port":
		var z: Dictionary = sc.selected()[0]
		sc.clear_sel()
		_start_arrow_from(z)
		return
	if h.begins_with("ep"):
		_snapshot()
		mode = "endpoint"
		return
	_snapshot()
	var els = sc.selected()
	if els.size() == 1:
		_ob = Geom.rect(els[0])
	else:
		_ob = sc.bounds_of(sc.sel.keys())
	if h == "rot":
		mode = "rotate"
		var c := _ob.get_center()
		var a0 := atan2(_p0.y - c.y, _p0.x - c.x) + PI * 0.5
		_grab_angle = a0 - (float(els[0].angle) if els.size() == 1 else 0.0)
	else:
		mode = "resize"


func _min_size(el: Dictionary) -> Vector2:
	match str(el.type):
		"zone":
			return Vector2(250, 190)
		"frame":
			return Vector2(120, 80)
	return Vector2(4, 4)


func _do_resize(wp: Vector2, e: InputEventMouseMotion) -> void:
	wp = _snap_pt(wp) if not e.ctrl_pressed else wp
	var els = sc.selected()
	if els.is_empty():
		return
	var single = els.size() == 1
	var o0: Dictionary = _orig[els[0].id]
	var a := float(o0.angle) if single else 0.0
	var c0 := _ob.get_center()
	var hw := _ob.size.x * 0.5
	var hh := _ob.size.y * 0.5
	var pl := (wp - c0).rotated(-a)
	var hx := 0
	var hy := 0
	if _handle.contains("e"):
		hx = 1
	elif _handle.contains("w"):
		hx = -1
	if _handle.contains("s"):
		hy = 1
	elif _handle.contains("n"):
		hy = -1
	var ms := Vector2(4, 4)
	for el in els:
		ms = ms.max(_min_size(el) if single else Vector2(4, 4))
	var nw := hw * 2.0
	var nh := hh * 2.0
	var ncx := 0.0
	var ncy := 0.0
	if hx != 0:
		if e.alt_pressed:
			nw = maxf(absf(pl.x) * 2.0, ms.x)
		else:
			nw = maxf(hx * pl.x + hw, ms.x)
			ncx = hx * (nw * 0.5 - hw)
	if hy != 0:
		if e.alt_pressed:
			nh = maxf(absf(pl.y) * 2.0, ms.y)
		else:
			nh = maxf(hy * pl.y + hh, ms.y)
			ncy = hy * (nh * 0.5 - hh)
	var keep: bool = e.shift_pressed or (single and els[0].type in ["text", "image"])
	if keep and hx != 0 and hy != 0 and hw > 0.0 and hh > 0.0:
		var s := maxf(nw / (hw * 2.0), nh / (hh * 2.0))
		nw = hw * 2.0 * s
		nh = hh * 2.0 * s
		if not e.alt_pressed:
			ncx = hx * (nw * 0.5 - hw)
			ncy = hy * (nh * 0.5 - hh)
	var cw := c0 + Vector2(ncx, ncy).rotated(a)
	var nb := Rect2(cw - Vector2(nw, nh) * 0.5, Vector2(nw, nh))
	var sx := nw / maxf(hw * 2.0, 0.001)
	var sy := nh / maxf(hh * 2.0, 0.001)
	for el in els:
		if el.locked:
			continue
		var o: Dictionary = _orig[el.id]
		if single:
			el.x = nb.position.x
			el.y = nb.position.y
			el.w = nb.size.x
			el.h = nb.size.y
		else:
			el.x = nb.position.x + (float(o.x) - _ob.position.x) * sx
			el.y = nb.position.y + (float(o.y) - _ob.position.y) * sy
			el.w = maxf(float(o.w) * sx, 1.0)
			el.h = maxf(float(o.h) * sy, 1.0)
		if o.has("points"):
			var np: Array = []
			var ow := maxf(float(o.w), 0.001)
			var oh := maxf(float(o.h), 0.001)
			for p in o.points:
				np.append([float(p[0]) * (float(el.w) / ow), float(p[1]) * (float(el.h) / oh)])
			el.points = np
		if el.type == "text":
			el.fontSize = maxf(8.0, float(o.fontSize) * (sy if not single else nh / maxf(float(o.h), 0.001)))
			var cx2 := Vector2(float(el.x), float(el.y))
			Geom.fit_text(el)
			el.x = cx2.x
			el.y = cx2.y
		sc.mark(el)
	sc.refresh_arrows(sc.sel)
	S.host.sync_zones(sc.sel)
	sc.touch()


func _do_rotate(wp: Vector2, e: InputEventMouseMotion) -> void:
	var els = sc.selected()
	var c := _ob.get_center()
	var ang := atan2(wp.y - c.y, wp.x - c.x) + PI * 0.5 - _grab_angle
	if e.shift_pressed:
		ang = roundf(ang / deg_to_rad(15.0)) * deg_to_rad(15.0)
	if els.size() == 1:
		els[0].angle = fposmod(ang, TAU)
		sc.mark(els[0])
	else:
		for el in els:
			var o: Dictionary = _orig[el.id]
			var oc := Vector2(float(o.x) + float(o.w) * 0.5, float(o.y) + float(o.h) * 0.5)
			var nc := c + (oc - c).rotated(ang)
			el.x = nc.x - float(el.w) * 0.5
			el.y = nc.y - float(el.h) * 0.5
			el.angle = fposmod(float(o.angle) + ang, TAU)
			sc.mark(el)
	sc.refresh_arrows(sc.sel)
	sc.touch()


func _do_endpoint(wp: Vector2, e: InputEventMouseMotion) -> void:
	var el: Dictionary = sc.selected()[0]
	var wpts := Geom.world_pts(el)
	var idx := 0 if _handle == "ep0" else wpts.size() - 1
	var other := wpts[wpts.size() - 1 - idx if wpts.size() == 2 else (1 if idx == 0 else wpts.size() - 2)]
	var p := _snap_pt(wp)
	if e.shift_pressed:
		var dv := p - other
		var ang := roundf(dv.angle() / deg_to_rad(15.0)) * deg_to_rad(15.0)
		p = other + Vector2.from_angle(ang) * dv.length()
	var tgt := ""
	if el.type == "arrow" and not e.ctrl_pressed:
		tgt = bind_target(wp, str(el.id))
	el["start" if idx == 0 else "end"] = tgt
	bind_hover = tgt
	wpts[idx] = p
	Geom.set_world_pts(el, wpts)
	Geom.refresh_arrow(sc, el)
	sc.mark(el)
	sc.touch()


# ------------------------------------------------------------------ tracés

func _press_draw(e: InputEventMouseButton) -> void:
	var p := _snap_pt(_p0)
	var t := tool
	var el: Dictionary = sc.make(t, p.x, p.y)
	if t == "frame":
		el.stroke = str(S.host.next_frame_color())
	if t == "arrow" or t == "line":
		el.points = [[0.0, 0.0], [0.0, 0.0]]
		_dpts = PackedVector2Array([p, p])
		if t == "arrow":
			el.start = bind_target(_p0)
	elif t == "freedraw":
		el.points = [[0.0, 0.0], [0.1, 0.0]]
		_dpts = PackedVector2Array([p, p + Vector2(0.1, 0)])
	sc.sel = {}
	sc.add(el)
	_draft = el
	mode = "draw"
	S.sel_changed.emit()


func _do_draw(wp: Vector2, e: InputEventMouseMotion) -> void:
	var el := _draft
	var p := _snap_pt(wp)
	var t := str(el.type)
	if t == "arrow" or t == "line":
		var anchor := _dpts[_dpts.size() - 2]
		if e.shift_pressed:
			var dv := p - anchor
			var ang := roundf(dv.angle() / deg_to_rad(15.0)) * deg_to_rad(15.0)
			p = anchor + Vector2.from_angle(ang) * dv.length()
		_dpts[_dpts.size() - 1] = p
		_apply_dpts(el, wp, e.ctrl_pressed)
	elif t == "freedraw":
		if _dpts[_dpts.size() - 1].distance_to(wp) > 1.6 / S.zoom:
			_dpts.append(wp)
			Geom.set_world_pts(el, _dpts)
			sc.mark(el)
			sc.touch()
	else:
		var a := _snap_pt(_p0)
		var d := p - a
		if e.shift_pressed:
			var m := maxf(absf(d.x), absf(d.y))
			d = Vector2(signf(d.x) * m, signf(d.y) * m)
		var r := Rect2(a, Vector2.ZERO).expand(a + d)
		if e.alt_pressed:
			r = Rect2(a - d.abs(), d.abs() * 2.0)
		el.x = r.position.x
		el.y = r.position.y
		el.w = r.size.x
		el.h = r.size.y
		sc.mark(el)
		sc.touch()


func _apply_dpts(el: Dictionary, wp: Vector2, nobind: bool) -> void:
	if el.type == "arrow":
		var tgt := "" if nobind else bind_target(wp, str(el.id))
		el.end = tgt
		bind_hover = tgt
	Geom.set_world_pts(el, _dpts)
	if el.type == "arrow":
		Geom.refresh_arrow(sc, el)
	sc.mark(el)
	sc.touch()


func _release_draw(cp: Vector2, e: InputEventMouseButton) -> void:
	var el := _draft
	if el.is_empty():
		mode = ""
		return
	var t := str(el.type)
	if t == "arrow" or t == "line":
		if cp.distance_to(_c0) < 5.0:
			mode = "poly"  # clic simple : tracé point par point (Entrée / double-clic / Échap pour finir)
			return
		_finish_draw()
		return
	mode = ""
	if t == "freedraw":
		Geom.set_world_pts(el, _dpts)
		sc.mark(el)
	elif float(el.w) < 4.0 and float(el.h) < 4.0:
		sc.remove([el.id])
		_draft = {}
		S.redraw()
		return
	_draft = {}
	sc.select([el.id])
	sc.commit()
	sc.touch()
	after_create()


func _finish_draw() -> void:
	var el := _draft
	mode = ""
	bind_hover = ""
	_draft = {}
	var pts := PackedVector2Array()
	for p in _dpts:
		if pts.is_empty() or pts[pts.size() - 1].distance_to(p) > 2.0 / S.zoom:
			pts.append(p)
	if pts.size() < 2:
		sc.remove([el.id])
		S.redraw()
		return
	Geom.set_world_pts(el, pts)
	if el.type == "arrow":
		Geom.refresh_arrow(sc, el)
		_finish_arrow(el)
	sc.mark(el)
	sc.select([el.id])
	sc.commit()
	sc.touch()
	after_create()


func _poly_press(e: InputEventMouseButton) -> void:
	var p := _snap_pt(_p0)
	if e.double_click or p.distance_to(_dpts[_dpts.size() - 2]) < 4.0 / S.zoom:
		_dpts[_dpts.size() - 1] = p
		_finish_draw()
		return
	_dpts[_dpts.size() - 1] = p
	_dpts.append(p)
	_apply_dpts(_draft, _p0, false)


func _poly_motion(wp: Vector2, e: InputEventMouseMotion) -> void:
	var p := _snap_pt(wp)
	var anchor := _dpts[_dpts.size() - 2]
	if e.shift_pressed:
		var dv := p - anchor
		var ang := roundf(dv.angle() / deg_to_rad(15.0)) * deg_to_rad(15.0)
		p = anchor + Vector2.from_angle(ang) * dv.length()
	_dpts[_dpts.size() - 1] = p
	_apply_dpts(_draft, wp, e.ctrl_pressed)


func _start_arrow_from(z: Dictionary) -> void:
	tool = "arrow"
	var p := Geom.center(z)
	var el: Dictionary = sc.make("arrow", p.x, p.y)
	el.points = [[0.0, 0.0], [0.0, 0.0]]
	el.start = str(z.id)
	_dpts = PackedVector2Array([_p0, _p0])
	sc.add(el)
	_draft = el
	mode = "draw"
	S.tool_changed.emit()


## Une flèche liée à deux zones devient un fil (nourrit par défaut) ; sinon elle redevient une flèche simple.
func _finish_arrow(el: Dictionary) -> void:
	if el.type != "arrow":
		return
	var a: Dictionary = sc.get_el(str(el.get("start", "")))
	var b: Dictionary = sc.get_el(str(el.get("end", "")))
	var is_link: bool = not a.is_empty() and not b.is_empty() and a.type == "zone" and b.type == "zone" and a.id != b.id
	if is_link and str(el.get("link", "")) == "":
		el.link = "feed"
		el.arrowType = "round"
		el.endHead = "triangle"
		el.strokeWidth = 3.0
		Geom.refresh_arrow(sc, el)
	elif not is_link and str(el.get("link", "")) != "":
		el.link = ""
	sc.mark(el)
	S.host.links_changed()


func _erase_at(wp: Vector2) -> void:
	var tol: float = 6.0 / S.zoom
	for i in range(sc.els.size() - 1, -1, -1):
		var el: Dictionary = sc.els[i]
		if el.locked or el.type == "zone" or el.type == "frame" or erase_set.has(el.id):
			continue
		if Geom.aabb(el).grow(tol).has_point(wp) and Geom.hit(el, wp, tol):
			erase_set[el.id] = true
	S.redraw()


# ------------------------------------------------------------------ actions

func delete_sel() -> void:
	var ids: Array = []
	for el in sc.selected():
		if not el.locked:
			ids.append(el.id)
	if ids.is_empty():
		return
	sc.remove(ids)
	sc.commit()
	S.host.links_changed()
	S.sel_changed.emit()


func select_all() -> void:
	var ids: Array = []
	for el in sc.els:
		if not el.locked:
			ids.append(el.id)
	sc.select(ids)
	S.sel_changed.emit()


func _add_clones(arr: Array) -> void:
	var ids: Array = []
	for c in arr:
		sc.add(c)
		ids.append(c.id)
	sc.refresh_arrows(sc.sel)
	sc.sel = {}
	for id in ids:
		sc.sel[id] = true
	S.host.sync_zones(sc.sel)
	S.host.sync_order()
	S.host.links_changed()
	sc.commit()
	sc.touch()
	S.sel_changed.emit()


func duplicate_sel() -> void:
	var src = sc.selected()
	if src.is_empty():
		return
	_add_clones(sc.clone(src, Vector2(20, 20)))


func copy(cut := false) -> void:
	var src = sc.selected()
	if src.is_empty():
		return
	_clip = []
	for el in src:
		_clip.append(el.duplicate(true))
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(PREFIX + JSON.stringify(_clip))
	if cut:
		delete_sel()


func paste() -> void:
	var txt := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
	var arr: Array = []
	if txt.begins_with(PREFIX):
		var v = JSON.parse_string(txt.substr(PREFIX.length()))
		if v is Array:
			arr = v
	elif txt == "" and not _clip.is_empty():
		arr = _clip
	var cp: Vector2 = S.get_local_mouse_position()
	var target: Vector2 = S.c2w(cp) if Rect2(Vector2.ZERO, S.size).has_point(cp) else S.c2w(S.size * 0.5)
	if arr.is_empty():
		if DisplayServer.has_method("clipboard_has_image") and DisplayServer.clipboard_has_image():
			S.host.add_image_from_image(DisplayServer.clipboard_get_image(), target)
		elif txt.strip_edges() != "":
			var n: Dictionary = sc.make("text", target.x, target.y)
			n.text = txt.strip_edges()
			Geom.fit_text(n)
			_add_clones([n])
		return
	var b := Rect2()
	var first := true
	for el in arr:
		var r := Geom.aabb(el)
		b = r if first else b.merge(r)
		first = false
	var cl: Array = sc.clone(arr, target - b.get_center())
	_add_clones(cl)


func nudge(d: Vector2) -> void:
	var els = sc.selected()
	if els.is_empty():
		return
	var moving := {}
	for el in els:
		if not el.locked:
			moving[el.id] = true
	for id in moving.keys():
		var a: Dictionary = sc.get_el(id)
		if a.type == "arrow" or a.type == "line":
			for k in ["start", "end"]:
				if str(a.get(k, "")) != "" and not moving.has(str(a[k])):
					a[k] = ""
	for id in moving:
		var el: Dictionary = sc.get_el(id)
		el.x = float(el.x) + d.x
		el.y = float(el.y) + d.y
		sc.mark(el)
	sc.refresh_arrows(moving)
	S.host.sync_zones(moving)
	sc.commit()
	sc.touch()


func order(mode_: String) -> void:
	var ids: Array = sc.sel.keys()
	if ids.is_empty():
		return
	sc.reorder(ids, mode_)
	S.host.sync_order()
	sc.commit()


func group_sel() -> void:
	sc.group(sc.sel.keys())
	sc.commit()


func ungroup_sel() -> void:
	sc.ungroup(sc.sel.keys())
	sc.commit()


func toggle_lock_sel() -> void:
	var els = sc.selected()
	if els.is_empty():
		return
	var v: bool = not bool(els[0].locked)
	for el in els:
		el.locked = v
		sc.mark(el)
	sc.commit()
	sc.touch()
	S.sel_changed.emit()


func undo() -> void:
	S.edit_commit()
	if sc.undo():
		_after_history()


func redo() -> void:
	S.edit_commit()
	if sc.redo():
		_after_history()


func _after_history() -> void:
	S.host.sync_zones({})
	S.host.sync_order()
	S.host.links_changed()
	S.sel_changed.emit()


# ------------------------------------------------------------------ styles

const FONT_KEYS := ["fontSize"]


func style_of(k: String):
	var els = sc.selected()
	if not els.is_empty() and els[0].has(k):
		return els[0][k]
	return sc.style.get(k)


func set_style(k: String, v, commit := true) -> void:
	sc.style[k] = v
	var changed := false
	for el in sc.selected():
		if el.type in ["zone"] and k != "opacity":
			continue
		if k in ["startHead", "endHead", "arrowType"] and el.type != "arrow":
			continue
		if k == "roundness" and not (el.type in ["rectangle", "image"]):
			continue
		el[k] = v
		if k == "fontSize" and el.type == "text":
			Geom.fit_text(el)
		sc.mark(el)
		changed = true
		if k == "arrowType":
			Geom.refresh_arrow(sc, el)
	if changed:
		if commit:
			sc.commit()
		sc.touch()
		S.host.sync_zones(sc.sel)


func copy_style() -> void:
	var els = sc.selected()
	if els.size() == 1:
		_style_clip = {}
		for k in sc.STYLE_KEYS:
			if els[0].has(k):
				_style_clip[k] = els[0][k]


func paste_style() -> void:
	if _style_clip.is_empty():
		return
	for el in sc.selected():
		if el.type == "zone":
			continue
		for k in _style_clip:
			el[k] = _style_clip[k]
		sc.mark(el)
	sc.commit()
	sc.touch()


# ------------------------------------------------------------------ menu contextuel

func _context(cp: Vector2) -> void:
	if mode != "" or S.pinching:
		return
	var wp: Vector2 = S.c2w(cp)
	var el := top_hit(wp, true)
	if not el.is_empty() and not sc.sel.has(el.id):
		sc.select([el.id])
		S.sel_changed.emit()
	elif el.is_empty():
		sc.clear_sel()
		S.sel_changed.emit()
	var lh := label_hit(wp)
	_menu_hit = str(lh.id) if not lh.is_empty() else ""
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.id_pressed.connect(_menu_pick)
		S.add_child(_menu)
	_menu.clear()
	var has = not sc.sel.is_empty()
	_menu.add_item("Coller", 1)
	if has:
		_menu.add_item("Copier", 2)
		_menu.add_item("Couper", 3)
		_menu.add_item("Dupliquer", 4)
		_menu.add_separator()
		_menu.add_item("Premier plan", 5)
		_menu.add_item("Avancer", 6)
		_menu.add_item("Reculer", 7)
		_menu.add_item("Arrière-plan", 8)
		_menu.add_separator()
		_menu.add_item("Grouper", 9)
		_menu.add_item("Dégrouper", 10)
		_menu.add_item("Verrouiller / déverrouiller", 11)
		_menu.add_separator()
		_menu.add_item("Supprimer", 12)
	if _menu_hit != "":
		_menu.add_item("Supprimer ce fil", 13)
	_menu.add_separator()
	_menu.add_item("Tout sélectionner", 14)
	_menu.add_item("Grille", 15)
	_menu.popup(Rect2i(Vector2i(S.get_screen_position() + cp), Vector2i.ZERO))


func _menu_pick(i: int) -> void:
	match i:
		1: paste()
		2: copy()
		3: copy(true)
		4: duplicate_sel()
		5: order("front")
		6: order("forward")
		7: order("backward")
		8: order("back")
		9: group_sel()
		10: ungroup_sel()
		11: toggle_lock_sel()
		12: delete_sel()
		13:
			sc.remove([_menu_hit])
			sc.commit()
			S.host.links_changed()
		14: select_all()
		15: toggle_grid()


func toggle_grid() -> void:
	S.grid_on = not S.grid_on
	S.tool_changed.emit()
	S.redraw()


# ------------------------------------------------------------------ clavier

func key(e: InputEventKey) -> bool:
	if S.is_editing():
		return false
	var focus = S.get_viewport().gui_get_focus_owner()
	if focus != null and (focus is LineEdit or focus is TextEdit):
		return false
	if e.keycode == KEY_SPACE:
		_space = e.pressed
		update_cursor(S.get_local_mouse_position())
		return true
	if not e.pressed:
		return false
	var ctrl: bool = e.ctrl_pressed or e.meta_pressed
	var k: int = e.keycode
	var pk: int = e.physical_keycode
	if ctrl:
		match k:
			KEY_A:
				select_all()
			KEY_C:
				if e.alt_pressed:
					copy_style()
				else:
					copy()
			KEY_X:
				copy(true)
			KEY_V:
				if e.alt_pressed:
					paste_style()
				else:
					paste()
			KEY_D:
				duplicate_sel()
			KEY_G:
				if e.shift_pressed:
					ungroup_sel()
				else:
					group_sel()
			KEY_Z:
				if e.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_BRACKETRIGHT:
				order("front" if e.shift_pressed else "forward")
			KEY_BRACKETLEFT:
				order("back" if e.shift_pressed else "backward")
			KEY_APOSTROPHE, KEY_QUOTEDBL:
				toggle_grid()
			KEY_L:
				if e.shift_pressed:
					toggle_lock_sel()
				else:
					return false
			KEY_E:
				if e.shift_pressed:
					S.host.export_png()
				else:
					return false
			KEY_0:
				S.zoom_to(1.0)
			KEY_EQUAL, KEY_PLUS:
				S.zoom_at(S.size * 0.5, 1.25)
			KEY_MINUS:
				S.zoom_at(S.size * 0.5, 0.8)
			_:
				return false
		return true
	if e.alt_pressed:
		return false
	if DIGITS.has(pk):
		if e.shift_pressed and pk == KEY_1:
			S.fit_all()
		elif e.shift_pressed and pk == KEY_2:
			S.fit_selection()
		elif not e.shift_pressed:
			set_tool(str(DIGITS[pk]))
		else:
			return false
		return true
	match k:
		KEY_ESCAPE:
			if mode == "poly":
				_finish_draw()
			elif mode != "":
				cancel()
			elif tool != "select":
				set_tool("select")
			else:
				sc.clear_sel()
				S.sel_changed.emit()
		KEY_ENTER, KEY_KP_ENTER:
			if mode == "poly":
				_finish_draw()
			else:
				var els = sc.selected()
				if els.size() == 1:
					match str(els[0].type):
						"text":
							S.edit_el(els[0], "text")
						"rectangle", "diamond", "ellipse":
							S.edit_el(els[0], "label")
						"arrow", "line":
							if str(els[0].get("link", "")) == "":
								S.edit_el(els[0], "label")
						"frame":
							S.edit_el(els[0], "name")
		KEY_DELETE, KEY_BACKSPACE:
			delete_sel()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var st := 10.0 if e.shift_pressed else 1.0
			if S.grid_on:
				st = 20.0
			nudge(Vector2(-st if k == KEY_LEFT else (st if k == KEY_RIGHT else 0.0), -st if k == KEY_UP else (st if k == KEY_DOWN else 0.0)))
		KEY_Q:
			toggle_lock()
		_:
			if KEYS.has(k):
				set_tool(str(KEYS[k]))
			else:
				return false
	return true
