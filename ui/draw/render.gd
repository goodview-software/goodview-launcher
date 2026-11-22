extends RefCounted
## Rendu de la scène : un seul code de dessin, appelé par la couche arrière (sous les zones-Controls) et la couche
## avant (au-dessus), plus la surcouche de sélection. Culling au viewport, polylignes en cache (Geom.build).

const Geom := preload("res://ui/draw/geom.gd")
const T := preload("res://ui/theme.gd")
const Chat := preload("res://ui/draw/chat.gd")
const MIN_FS := 6.0  # taille minimale à l'écran d'un texte tracé (plus petit : on l'agrandit jusque-là)
const HIDE_FS := 3.0  # en dessous, le texte est illisible : remplacé par un trait

static var _dot_tex: ImageTexture
static var _grid_tex: ImageTexture


static func _tex_dots() -> ImageTexture:
	if _dot_tex == null:
		var im := Image.create(24, 24, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		for dx in 2:
			for dy in 2:
				im.set_pixel(dx, dy, Color(1, 1, 1, 0.1))
		_dot_tex = ImageTexture.create_from_image(im)
	return _dot_tex


static func _tex_grid() -> ImageTexture:
	if _grid_tex == null:
		var im := Image.create(20, 20, false, Image.FORMAT_RGBA8)
		im.fill(Color(0, 0, 0, 0))
		for i in 20:
			im.set_pixel(i, 0, Color(1, 1, 1, 0.09))
			im.set_pixel(0, i, Color(1, 1, 1, 0.09))
		_grid_tex = ImageTexture.create_from_image(im)
	return _grid_tex


static func draw_grid(ci: Control, S) -> void:
	var step := 20.0 if S.grid_on else 24.0
	var tex := _tex_grid() if S.grid_on else _tex_dots()
	var k := 1
	while step * S.zoom * k < 10.0:
		k *= 4
	var z: float = S.zoom * k
	ci.draw_set_transform(S.pan, 0.0, Vector2(z, z))
	var o: Vector2 = -S.pan / z
	var tl := Vector2(floorf(o.x / step) * step - step, floorf(o.y / step) * step - step)
	ci.draw_texture_rect(tex, Rect2(tl, ci.size / z + Vector2(step * 3, step * 3)), true)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func xform(S, el: Dictionary) -> Transform2D:
	var z: float = S.zoom
	var a := float(el.angle)
	var ax := Vector2(cos(a), sin(a)) * z
	var ay := Vector2(-sin(a), cos(a)) * z
	var c = S.w2c(Geom.center(el))
	var hw := float(el.w) * 0.5
	var hh := float(el.h) * 0.5
	return Transform2D(ax, ay, c - ax * hw - ay * hh)


static func zone_color(S, el: Dictionary) -> Color:
	return S.host.zone_color(el)


## Dessine tous les éléments visibles d'une couche (front=false : sous les zones ; true : au-dessus).
static func draw_layer(ci: Control, S, front: bool) -> void:
	S.partition()
	var list: Array = S.vis_front if front else S.vis_back
	for el in list:
		draw_el(ci, S, el)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func draw_el(ci: Control, S, el: Dictionary) -> void:
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)
	var t := str(el.type)
	var op := float(el.get("opacity", 100.0)) / 100.0
	if S.tools.erase_set.has(el.id):
		op *= 0.3
	if t == "zone":
		if S.lod:
			_zone_proxy(ci, S, el, op)
		return
	if t == "frame":
		_frame(ci, S, el, op)
		return
	if t == "msg":
		_msg(ci, S, el, op)
		return
	if t == "text":
		if S.editing_id != el.id:
			_text(ci, S, el, op)
		return
	if t == "image":
		_image(ci, S, el, op)
		return
	var lstyle := {}
	var col := Geom.ncol(str(el.stroke))
	var lname := ""
	if t == "arrow" and str(el.get("link", "")) != "":
		lstyle = S.host.link_style(el)
		col = lstyle.color
		lname = str(lstyle.name)
	col.a *= op
	var c := Geom.build(S.scene, el, lstyle)
	var z: float = S.zoom
	ci.draw_set_transform_matrix(xform(S, el))
	var sw := maxf(float(el.get("strokeWidth", 2)), 1.2 / z)
	var bgc := Geom.ncol(str(el.get("bg", "transparent")))
	if (c.fill as PackedVector2Array).size() >= 3:
		bgc.a *= op * 0.85
		ci.draw_colored_polygon(c.fill, bgc)
	elif (c.hatch as PackedVector2Array).size() >= 2:
		bgc.a *= op * 0.8
		ci.draw_multiline(c.hatch, bgc, maxf(sw * 0.6, 1.0 / z), true)
	for ln in c.lines:
		if (ln as PackedVector2Array).size() >= 2:
			ci.draw_polyline(ln, col, sw, true)
	if (c.segs as PackedVector2Array).size() >= 2:
		ci.draw_multiline(c.segs, col, sw, true)
	for fp in c.fills:
		if (fp as PackedVector2Array).size() >= 3:
			ci.draw_colored_polygon(fp, col)
	# étiquette (formes, flèches, fils)
	var lab := str(el.get("label", ""))
	if lname != "":
		lab = lname
	if lab != "":
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		if t == "arrow":
			var lr := Geom.label_rect(el, lab)
			var sr := Rect2(S.w2c(lr.position), lr.size * z)
			if lname != "":
				ci.draw_rect(sr, Color(T.CARD_HI, op))
				ci.draw_rect(sr, col, false, 2.0)
				ci.draw_string(Geom.f(), Vector2(sr.position.x, sr.position.y + sr.size.y * 0.5 + 13.0 * z * 0.36), lab, HORIZONTAL_ALIGNMENT_CENTER, sr.size.x, maxi(int(13.0 * z), 6), Color(T.TEXT, op))
			else:
				ci.draw_rect(sr, Color(T.BG, 0.85 * op))
				_centered(ci, S, el, lab, sr.get_center(), op)
		else:
			_centered(ci, S, el, lab, S.w2c(Geom.center(el)), op, true)


static func _centered(ci: Control, S, el: Dictionary, txt: String, c: Vector2, op: float, rot := false) -> void:
	var fs = float(el.get("fontSize", 16)) * S.zoom
	if fs < HIDE_FS:
		return
	fs = maxf(fs, MIN_FS)
	var sz := Geom.f().get_multiline_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs))
	var colr := Geom.ncol(str(el.stroke))
	colr.a *= op
	if rot:
		ci.draw_set_transform(c, float(el.angle), Vector2.ONE)
		c = Vector2.ZERO
	ci.draw_multiline_string(Geom.f(), c - sz * 0.5 + Vector2(0, Geom.f().get_ascent(int(fs))), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), -1, colr)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _text(ci: Control, S, el: Dictionary, op: float) -> void:
	var fs = float(el.get("fontSize", 20)) * S.zoom
	var col := Geom.ncol(str(el.stroke))
	col.a *= op
	var c: Vector2 = S.w2c(Geom.center(el))
	var sz = Vector2(float(el.w), float(el.h)) * S.zoom
	if fs < HIDE_FS:
		ci.draw_set_transform(c, float(el.angle), Vector2.ONE)
		ci.draw_rect(Rect2(-sz * 0.5, Vector2(sz.x, maxf(sz.y * 0.35, 1.5))), Color(col, col.a * 0.6))
		ci.draw_set_transform_matrix(Transform2D.IDENTITY)
		return
	fs = maxf(fs, MIN_FS)
	ci.draw_set_transform(c, float(el.angle), Vector2.ONE)
	ci.draw_multiline_string(Geom.f(), Vector2(-sz.x * 0.5, -sz.y * 0.5 + Geom.f().get_ascent(int(fs))), str(el.get("text", "")), HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs), -1, col)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _image(ci: Control, S, el: Dictionary, op: float) -> void:
	ci.draw_set_transform_matrix(xform(S, el))
	var tex: Texture2D = S.host.image_tex(el)
	var r := Rect2(0, 0, float(el.w), float(el.h))
	if tex != null:
		ci.draw_texture_rect(tex, r, false, Color(1, 1, 1, op))
	else:
		ci.draw_rect(r, Color(T.CARD_HI, op))
		ci.draw_line(Vector2.ZERO, Vector2(r.size.x, r.size.y), Color(T.DIM, op), 2.0 / S.zoom)
		ci.draw_line(Vector2(r.size.x, 0), Vector2(0, r.size.y), Color(T.DIM, op), 2.0 / S.zoom)
	ci.draw_rect(r, Color(Geom.ncol(str(el.stroke)), 0.5 * op), false, 1.5 / S.zoom)
	ci.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _frame(ci: Control, S, el: Dictionary, op: float) -> void:
	var col := Geom.ncol(str(el.get("stroke", "4de1b4")))
	var z: float = S.zoom
	var r := Rect2(S.w2c(Vector2(float(el.x), float(el.y))), Vector2(float(el.w), float(el.h)) * z)
	ci.draw_rect(r, Color(col, 0.07 * op))
	ci.draw_rect(r, Color(col, 0.6 * op), false, 2.0)
	var bh: float = Geom.frame_bar(float(el.h))
	var bar := Rect2(r.position, Vector2(r.size.x, minf(bh * z, r.size.y)))
	ci.draw_rect(bar, Color(col, 0.18 * op))
	var fs := clampi(int(minf(bar.size.y * 0.6, 28.0)), 8, 28)
	ci.draw_string(Geom.f(), bar.position + Vector2(8, bar.size.y * 0.5 + fs * 0.35), str(el.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, maxf(bar.size.x - 12.0, 8.0), fs, Color(T.TEXT, op))


## Nœud de chat : carte (en-tête coloré par l'assistant, texte en Markdown léger), flèche fine depuis son parent ;
## le chemin racine -> nœud sélectionné est en relief, le reste de l'arbre est estompé. Vue éloignée : texte résumé,
## jamais sous MIN_FS pixels à l'écran.
static func _msg(ci: Control, S, el: Dictionary, op: float) -> void:
	var sc = S.scene
	var z: float = S.zoom
	var foc: Dictionary = Chat.focus(sc)
	var in_path := false
	if foc.on:
		in_path = foc.anc.has(el.id)
		if not foc.keep.has(el.id) and foc.tree.has(el.id):
			op *= 0.5
	var q: String = sc.search_q
	if q != "" and not Chat.matches(el, q):
		op *= 0.25
	var st: Dictionary = S.host.msg_style(el)
	var col: Color = st.color
	var c: Dictionary = Chat.layout(sc, el)
	var r := Rect2(S.w2c(Vector2(float(el.x), float(el.y))), Vector2(float(el.w), float(el.h)) * z)
	var par: Dictionary = Chat.parent_of(sc, el)
	if not par.is_empty():
		_msg_edge(ci, S, par, el, foc.on and foc.anc.has(str(par.id)) and in_path, op, col)
	var ip := Chat.img_edge(sc, el)
	if ip.size() == 2:
		var isel: bool = S.tools.edge_sel == "img:" + str(el.id)
		ci.draw_dashed_line(S.w2c(ip[0]), S.w2c(ip[1]), Color(T.WARN if isel else T.OK, op), 3.0 if isel else 2.0, 8.0)
	ci.draw_rect(r, Color(T.CARD_HI if str(el.role) == "user" else T.CARD, op))
	var hh := Chat.HEAD * z
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, hh)), Color(col, 0.22 * op))
	ci.draw_rect(r, Color(col, (1.0 if in_path else 0.7) * op), false, 3.0 if in_path else 2.0)
	var f := Geom.f()
	var hpx := int(12.0 * z)
	if hpx >= 6:
		var sq := 14.0 * z
		var ar := Rect2(r.position + Vector2(8.0 * z, (Chat.HEAD * z - sq) * 0.5), Vector2(sq, sq))
		ci.draw_rect(ar, Color(col, op))
		var nm := str(st.name)
		ci.draw_string(Chat.bold_font(), Vector2(ar.end.x + 6.0 * z, r.position.y + Chat.HEAD * z * 0.5 + hpx * 0.35), nm, HORIZONTAL_ALIGNMENT_LEFT, maxf(r.size.x - 60.0 * z, 10.0), hpx, Color(T.TEXT, op))
		if not bool(el.get("done", true)):
			ci.draw_string(f, Vector2(r.end.x - 70.0 * z, r.position.y + Chat.HEAD * z * 0.5 + hpx * 0.35), "écrit…", HORIZONTAL_ALIGNMENT_RIGHT, 62.0 * z, hpx, Color(T.WARN, op))
	var tcol := Color(T.TEXT, op)
	if Chat.FS * z >= Chat.MIN_PX:
		for b in c.boxes:
			var br: Rect2 = b.r
			var sr := Rect2(r.position + br.position * z, br.size * z)
			ci.draw_rect(sr, Color(0, 0, 0, 0.28 * op) if int(b.k) == 0 else Color(col, 0.7 * op))
		for l in c.lines:
			var sy: float = r.position.y + float(l.y) * z
			if sy > ci.size.y or sy + 22.0 * z < 0.0:
				continue
			var px := int(float(l.fs) * z)
			var fnt: Font = Chat.bold_font() if int(l.k) == 1 else f
			var lc := tcol
			match int(l.k):
				1:
					lc = Color(col.lightened(0.25), op)
				3, 4:
					lc = Color(T.DIM, op)
			ci.draw_string(fnt, Vector2(r.position.x + float(l.x) * z, sy + fnt.get_ascent(px)), str(l.t), HORIZONTAL_ALIGNMENT_LEFT, -1, px, lc)
	elif r.size.x >= 44.0 and r.size.y > hh + 14.0:
		var txt: String = str(c.plain) if str(c.plain) != "" else "…"
		var lines_n := clampi(int((r.size.y - hh - 6.0) / f.get_height(Chat.SUM_PX)), 1, 14)
		ci.draw_multiline_string(f, r.position + Vector2(5.0, hh + 3.0 + f.get_ascent(Chat.SUM_PX)), txt, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 10.0, Chat.SUM_PX, lines_n, tcol)


## Flèche fine parent -> enfant (courbe de Bézier, pointe en bout), calculée d'après les positions courantes.
static func _msg_edge(ci: Control, S, par: Dictionary, el: Dictionary, hot: bool, op: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for w in Chat.edge_pts(par, el):
		pts.append(S.w2c(w))
	var sel: bool = S.tools.edge_sel == str(el.id)
	var lc := Color(T.WARN if sel else (T.OK if hot else T.DIM), (1.0 if sel else (0.95 if hot else 0.6)) * op)
	ci.draw_polyline(pts, lc, 4.0 if sel else (2.5 if hot else 1.5), true)
	var tip: Vector2 = pts[16]
	var dir: Vector2 = (tip - pts[14]).normalized()
	var perp := Vector2(-dir.y, dir.x)
	ci.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 9.0 + perp * 4.5, tip - dir * 9.0 - perp * 4.5]), lc)


static func _zone_proxy(ci: Control, S, el: Dictionary, op: float) -> void:
	var col := zone_color(S, el)
	var r := Rect2(S.w2c(Vector2(float(el.x), float(el.y))), Vector2(float(el.w), float(el.h)) * S.zoom)
	ci.draw_rect(r, Color(T.CARD, op))
	ci.draw_rect(r, Color(col, op), false, 2.0)
	var fs := clampi(int(r.size.y * 0.2), 9, 30)
	ci.draw_string(Geom.f(), r.position + Vector2(6, fs + 4), str(el.get("title", "")), HORIZONTAL_ALIGNMENT_LEFT, maxf(r.size.x - 10.0, 8.0), fs, Color(T.TEXT, op))
	if r.size.y > 40:
		ci.draw_rect(Rect2(r.position + Vector2(0, fs + 12), Vector2(r.size.x, 2)), Color(col, 0.35 * op))


# ------------------------------------------------------------------ surcouche : sélection, poignées, guides

static func _rot_rect(S, el: Dictionary, pad: float) -> PackedVector2Array:
	var r := Geom.rect(el).grow(pad)
	var c := Geom.center(el)
	var a := float(el.angle)
	var out := PackedVector2Array()
	for p in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		out.append(S.w2c(c + (p - c).rotated(a)))
	return out


## Ports des nœuds de chat (survolé / sélectionné) et fil en cours de tirage.
static func _ports(ci: Control, S) -> void:
	var tl = S.tools
	var sc = S.scene
	var ids := {}
	if tl.hover != "" and tl.mode == "":
		ids[tl.hover] = true
	for id in sc.sel:
		ids[id] = true
	for id in ids:
		var m: Dictionary = sc.get_el(str(id))
		if m.is_empty() or (m.type != "msg" and m.type != "image"):
			continue
		var r := Geom.rect(m)
		for p in ([Vector2(r.get_center().x, r.end.y)] if m.type == "image" else [Vector2(r.get_center().x, r.position.y), Vector2(r.get_center().x, r.end.y)]):
			var cp: Vector2 = S.w2c(p)
			ci.draw_circle(cp, 6.0, T.CARD)
			ci.draw_arc(cp, 6.0, 0.0, TAU, 20, T.OK, 2.0, true)
	if not tl.wire.is_empty():
		var m2: Dictionary = sc.get_el(str(tl.wire.id))
		if not m2.is_empty():
			var r2 := Geom.rect(m2)
			var a: Vector2 = S.w2c(Vector2(r2.get_center().x, r2.end.y if (tl.wire.out or m2.type == "image") else r2.position.y))
			ci.draw_line(a, S.w2c(tl.wire.pos), T.WARN, 2.5, true)
			var h: Dictionary = tl.top_hit(tl.wire.pos)
			if not h.is_empty() and h.type == "msg" and str(h.id) != str(tl.wire.id):
				_outline(ci, S, h, Color(T.WARN, 0.9), 3.0)


static func draw_overlay(ci: Control, S) -> void:
	var acc: Color = T.OK
	var sc = S.scene
	var tl = S.tools
	# survol
	if tl.hover != "" and not sc.sel.has(tl.hover) and tl.mode == "":
		var h: Dictionary = sc.get_el(tl.hover)
		if not h.is_empty():
			_outline(ci, S, h, Color(acc, 0.55), 2.0)
	if tl.bind_hover != "":
		var b: Dictionary = sc.get_el(tl.bind_hover)
		if not b.is_empty():
			var pts := _rot_rect(S, b, 5.0 / S.zoom)
			pts.append(pts[0])
			ci.draw_polyline(pts, T.WARN, 2.5, true)
	_ports(ci, S)
	for id in sc.sel:
		var el: Dictionary = sc.get_el(id)
		if not el.is_empty() and (sc.sel.size() > 1 or el.type not in Geom.LINEAR or el.type == "freedraw"):
			if sc.sel.size() > 1 or el.type == "freedraw":
				_outline(ci, S, el, Color(acc, 0.5), 1.0)
			elif el.type != "text":
				pass
	var fr: Dictionary = tl.sel_frame()
	if not fr.is_empty():
		if fr.kind == "linear":
			for hd in fr.handles:
				ci.draw_circle(hd.pos, 7.0, T.BG)
				ci.draw_arc(hd.pos, 7.0, 0, TAU, 16, acc, 2.0, true)
		else:
			var pts2: PackedVector2Array = fr.poly
			var closed := pts2.duplicate()
			closed.append(pts2[0])
			ci.draw_polyline(closed, acc, 1.5, true)
			for hd in fr.handles:
				if hd.name == "rot":
					ci.draw_line(fr.top, hd.pos, Color(acc, 0.7), 1.5, true)
					ci.draw_circle(hd.pos, 6.0, T.BG)
					ci.draw_arc(hd.pos, 6.0, 0, TAU, 16, acc, 2.0, true)
				elif hd.name == "port":
					ci.draw_line(fr.right, hd.pos, Color(acc, 0.7), 2.0, true)
					ci.draw_circle(hd.pos, 9.0, acc)
				else:
					var rr := Rect2(hd.pos - Vector2(5, 5), Vector2(10, 10))
					ci.draw_rect(rr, T.BG)
					ci.draw_rect(rr, acc, false, 2.0)
	if tl.mode == "marquee":
		var m: Rect2 = tl.marquee
		var sr := Rect2(S.w2c(m.position), m.size * S.zoom)
		ci.draw_rect(sr, Color(acc, 0.08))
		ci.draw_rect(sr, Color(acc, 0.7), false, 1.0)
	for g in tl.guides:
		ci.draw_line(S.w2c(g[0]), S.w2c(g[1]), Color("ff8fb1"), 1.0, true)


static func _outline(ci: Control, S, el: Dictionary, col: Color, w: float) -> void:
	if str(el.type) in Geom.LINEAR and str(el.type) != "freedraw":
		var wp := Geom.world_pts(el)
		var sp := PackedVector2Array()
		for p in wp:
			sp.append(S.w2c(p))
		if sp.size() >= 2:
			ci.draw_polyline(sp, col, w + 3.0, true)
		return
	var pts := _rot_rect(S, el, 2.0 / S.zoom)
	pts.append(pts[0])
	ci.draw_polyline(pts, col, w, true)
