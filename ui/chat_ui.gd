extends RefCounted
## Composants propres au chat : points d'attente animés, tuile d'assistant, bandeau d'assistants, bouton rond.

const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")
const Ico := preload("res://ui/icons.gd")
const U := preload("res://ui/universe.gd")
const MD := preload("res://ui/markdown.gd")
const KPx := preload("res://kit/ui/px.gd")
const KIcon := preload("res://kit/icon.gd")


## Trois points qui pulsent (avant le premier jeton).
class Dots extends Control:
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(46, 22)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		t += d * 5.0
		queue_redraw()

	func _draw() -> void:
		for i in 3:
			var a := 0.35 + 0.65 * maxf(0.0, sin(t - i * 0.8))
			draw_rect(Rect2(floorf(4 + i * 14), floorf(7 - sin(t - i * 0.8) * 2.0), 8, 8), Color(T.OK, a))


## Tuile d'un assistant : pastille ronde + mascotte animée selon son mode.
class Tile extends W.Tap:
	var ai := 0
	var selected := false:
		set(v):
			selected = v
			queue_redraw()
	var mode := "idle":
		set(v):
			if v != mode:
				mode = v
				t = 0.0
				queue_redraw()
	var t := 0.0
	var speed := 1.0
	var _last := -1

	func _init(a := 0) -> void:
		super()
		ai = a
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size = Vector2(36, 58)
		tooltip_text = "%s · %s  (Ctrl+%d)" % [U.get_u(a).name, U.get_u(a).specialty, a + 1]

	func _process(d: float) -> void:
		var fps: float = float(W.Orb.FPS.get(U.anim_for(mode), 3.0)) * speed * float(U.get_u(ai).anim.speed)
		t += d * fps
		var f := int(t) % 4
		if f != _last and (selected or mode != "idle"):
			_last = f
			queue_redraw()

	func _draw() -> void:
		var a := U.anim_for(mode)
		var col := U.color(ai)
		var c := Vector2(size.x / 2.0, 22)
		var r := 20.0 if selected else 17.0
		if selected or mode != "idle":
			for i in 2:
				var g := r + 4.0 + i * 4.0
				draw_rect(Rect2(c - Vector2(g, g), Vector2(g, g) * 2.0), Color(col, 0.16 - i * 0.07))
		KPx.panel(self, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), col.darkened(0.62 - (0.1 if hot else 0.0)), col if selected else Color("0b0e12"), false, 1)
		var f := int(t) % 4
		var bounce := -absf(sin(t * 1.3)) * 2.0 * float(U.get_u(ai).anim.bounce) if a == "talk" else 0.0
		var pos := (c - Vector2(16, 16) + Vector2(0, bounce)).round()
		if W.Orb.XANIMS.has(a):
			draw_texture_rect_region(W.Orb.XSHEET, Rect2(pos, Vector2(32, 32)), Rect2(f * 32, (ai * 4 + W.Orb.XANIMS[a]) * 32, 32, 32))
		else:
			var row: int = W.Orb.ANIMS[a][0] + ai * 5
			draw_texture_rect_region(W.Orb.SHEET, Rect2(pos, Vector2(32, 32)), Rect2(f * 32, row * 32, 32, 32))
		if selected:
			var font := get_theme_default_font()
			var nm: String = U.get_u(ai).name
			var tw := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string(font, Vector2((size.x - tw) / 2.0, 52), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


## Bandeau horizontal des 8 assistants (sélection par clic, Ctrl+1..8 gérés par la page).
class Strip extends HBoxContainer:
	signal picked(ai: int)
	var tiles: Array = []

	func _init(sel := 0) -> void:
		add_theme_constant_override("separation", 0)
		for i in U.count():
			var tl := Tile.new(i)
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tl.selected = i == sel
			tl.pressed.connect(func(): picked.emit(i))
			add_child(tl)
			tiles.append(tl)

	func select(i: int) -> void:
		for k in tiles.size():
			tiles[k].selected = k == i

	func set_mode(ai: int, mode: String, speed := 1.0) -> void:
		if ai >= 0 and ai < tiles.size():
			tiles[ai].mode = mode
			tiles[ai].speed = speed

	func reset_modes() -> void:
		for tl in tiles:
			tl.mode = "idle"
			tl.speed = 1.0

	func set_enabled(v: bool) -> void:
		for tl in tiles:
			tl.enabled = v


## Bouton rond plein (envoi / stop).
class RoundBtn extends W.Tap:
	var kind := "send":
		set(v):
			kind = v
			queue_redraw()

	func _init(k := "send", px := 46) -> void:
		super()
		kind = k
		custom_minimum_size = Vector2(px, px)

	func _draw() -> void:
		var c := size / 2.0
		var base := T.OK
		var rc := Rect2(Vector2.ZERO, size).grow(-2)
		if down:
			rc.position += Vector2(2, 2)
		KPx.panel(self, rc, base.lightened(0.12) if hot else base, Color(0, 0, 0, 0), not down)
		var u := maxf(2.0, floorf(size.y / 15.0))
		var spr: Array = KPx.ARROW_UP if kind == "send" else KPx.STOP
		var sz := KPx.sprite_size(spr, u)
		KPx.sprite(self, spr, (c - sz * 0.5).round() + (Vector2(2, 2) if down else Vector2.ZERO), u, {"#": T.ON_ACCENT})


## Carte repliable d'une délégation : « Goody demande à Bleu… » + réponse écrite en streaming.
class CardView extends PanelContainer:
	var from := 0
	var to := 0
	var open := true
	var user_toggled := false
	var head: W.Tap
	var title: Label
	var chev: Control
	var body: VBoxContainer
	var qlbl: Label
	var ans: RichTextLabel
	var done := false
	var accent := ""

	func _init(f := 0, t_ := 1, question := "") -> void:
		from = f
		to = t_
		accent = U.get_u(t_).accent
		add_theme_stylebox_override("panel", T.style(Color(U.color(t_), 0.10), 18, 12))
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		add_child(v)
		head = W.Tap.new()
		head.custom_minimum_size = Vector2(0, 30)
		v.add_child(head)
		var h := HBoxContainer.new()
		h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_theme_constant_override("separation", 8)
		head.add_child(h)
		var av := W.Avatar.new()
		av.variant = t_
		av.custom_minimum_size = Vector2(28, 28)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(av)
		title = W.label("%s demande à %s…" % [U.get_u(f).name, U.get_u(t_).name], 15, U.color(t_), h)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.clip_text = true
		title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		title.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chev = Control.new()
		chev.custom_minimum_size = Vector2(24, 24)
		chev.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chev.draw.connect(func():
			chev.draw_set_transform(chev.size / 2.0, PI / 2.0 if open else 0.0)
			Ico.draw_kind(chev, "chevron", Vector2.ZERO, 0.5, T.DIM))
		h.add_child(chev)
		head.pressed.connect(func():
			user_toggled = true
			set_open(not open))
		body = VBoxContainer.new()
		body.add_theme_constant_override("separation", 4)
		v.add_child(body)
		qlbl = W.label(question, 13, T.DIM, body)
		ans = RichTextLabel.new()
		ans.bbcode_enabled = true
		ans.fit_content = true
		ans.scroll_active = false
		ans.selection_enabled = true
		ans.add_theme_font_size_override("normal_font_size", 15)
		ans.add_theme_font_size_override("bold_font_size", 15)
		body.add_child(ans)

	func set_open(v: bool) -> void:
		open = v
		body.visible = v
		chev.queue_redraw()

	func set_answer(text: String, live: bool) -> void:
		ans.text = MD.to_bbcode(MD.esc_cursor(text, live), accent)

	func finish(text: String) -> void:
		done = true
		title.text = "%s a répondu à %s" % [U.get_u(to).name, U.get_u(from).name]
		ans.text = MD.to_bbcode(text, accent)
		if not user_toggled:
			set_open(false)


## Scène FIXE de l'assistant : sa place (il ne bouge pas quand on fait défiler) + route en perspective « rayons X » qui s'élargit vers le chat.
class Stage extends Control:
	var ai := 0
	var mode := "idle":
		set(v):
			if v != mode:
				mode = v
				t = 0.0
	var speed := 1.0
	var t := 0.0
	var flow := 0.0
	var motto := ""
	const FEET := 0.40

	func _init(a := 0) -> void:
		ai = a
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size = Vector2(0, 236)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true

	func _process(d: float) -> void:
		var a := U.anim_for(mode)
		t += d * float(W.Orb.FPS.get(a, 3.0)) * speed * float(U.get_u(ai).anim.speed)
		flow += d * (0.18 if mode == "idle" else 0.9 * speed)
		queue_redraw()

	func _draw() -> void:
		var col := U.color(ai)
		var w := size.x
		var h := size.y
		var y0 := floorf(h * FEET)
		# fond : bandes de ciel pixel
		for i in 6:
			draw_rect(Rect2(0, floorf(i * y0 / 6.0), w, ceilf(y0 / 6.0)), T.BG.lerp(col, 0.02 + 0.015 * i))
		# route : rangées de 4 px, bords droits qui s'élargissent (perspective)
		var step := 4.0
		var y := y0
		while y < h:
			var tt := (y + step * 0.5 - y0) / maxf(h - y0, 1.0)
			var hw := lerpf(26.0, w * 0.49, tt)
			var cx := w * 0.5
			var depth := 1.0 / (tt + 0.07)
			var asphalt := T.BG.darkened(0.25).lerp(col, 0.07 + 0.08 * tt)
			draw_rect(Rect2(cx - hw, y, hw * 2.0, step), asphalt)
			# rails lumineux
			draw_rect(Rect2(cx - hw, y, 4.0, step), Color(col, 0.95))
			draw_rect(Rect2(cx + hw - 4.0, y, 4.0, step), Color(col, 0.95))
			draw_rect(Rect2(cx - hw + 8.0 + tt * 14.0, y, 2.0, step), Color(col, 0.35))
			draw_rect(Rect2(cx + hw - 10.0 - tt * 14.0, y, 2.0, step), Color(col, 0.35))
			# lignes transversales « rayons X » : espacées selon la profondeur, qui avancent vers le chat
			if fposmod(depth * 1.1 - flow * 3.0, 1.0) < 0.16:
				draw_rect(Rect2(cx - hw + 4.0, y, hw * 2.0 - 8.0, step * 0.5), Color(col, 0.42))
			# tirets centraux
			if fposmod(depth * 0.9 - flow * 2.4, 1.0) < 0.5:
				var dw := lerpf(3.0, 12.0, tt)
				draw_rect(Rect2(cx - dw * 0.5, y, dw, step), Color(T.TEXT, 0.55))
			y += step
		# halo de l'horizon
		draw_rect(Rect2(0, y0 - 2.0, w, 2.0), Color(col, 0.55))
		# piédestal + mascotte (taille ×3), centrée
		var px := 96
		var cx2 := floorf(w * 0.5)
		KPx.panel(self, Rect2(cx2 - 54, y0 - 6.0, 108, 14), col.darkened(0.55), col.darkened(0.8), true, 1)
		var f := int(t) % 4
		var a := U.anim_for(mode)
		var bounce := -absf(sin(t * 1.3)) * 3.0 * float(U.get_u(ai).anim.bounce) if a == "talk" else 0.0
		var pos := (Vector2(cx2 - px * 0.5, y0 - px + 4.0 + bounce)).round()
		if W.Orb.XANIMS.has(a):
			draw_texture_rect_region(W.Orb.XSHEET, Rect2(pos, Vector2(px, px)), Rect2(f * 32, (ai * 4 + W.Orb.XANIMS[a]) * 32, 32, 32))
		else:
			var row: int = W.Orb.ANIMS[a][0] + ai * 5
			var n: int = W.Orb.ANIMS[a][1]
			draw_texture_rect_region(W.Orb.SHEET, Rect2(pos, Vector2(px, px)), Rect2((int(t) % n) * 32, row * 32, 32, 32))
		# étiquette
		var font := get_theme_default_font()
		var nm: String = str(U.get_u(ai).name).to_upper()
		draw_string(font, Vector2(cx2 + 60, y0 - 52), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, col)
		draw_string(font, Vector2(cx2 + 60, y0 - 34), str(U.get_u(ai).specialty), HORIZONTAL_ALIGNMENT_LEFT, maxf(w - cx2 - 70, 40.0), 12, T.DIM)


## Tableau pixel art (panneau d'affichage en bois) des réponses toutes faites.
class Board extends PanelContainer:
	signal picked(text: String)

	func _init(title: String, items: Array) -> void:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var m := MarginContainer.new()
		for s in ["left", "right", "bottom", "top"]:
			m.add_theme_constant_override("margin_" + s, 16)
		add_child(m)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		m.add_child(v)
		var hd := W.label(title.to_upper(), 14, Color("ffe9a8"), v)
		hd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		v.add_child(grid)
		for s in items:
			var r := W.Row.new()
			r.add_theme_stylebox_override("panel", T.style(Color("f2e6c4"), 4, 8))
			r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			r.pressed.connect(func(): picked.emit(s))
			var l := W.label(s, 14, Color("2b2118"), r)
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			grid.add_child(r)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var wood := Color("6b4a2b")
		KPx.panel(self, r, wood, wood.darkened(0.6), true, 1)
		var inner := r.grow(-8)
		draw_rect(inner, Color("23303a"))
		draw_rect(inner, Color("0b1218"), false, 2.0)
		for p in [Vector2(4, 4), Vector2(size.x - 8, 4), Vector2(4, size.y - 8), Vector2(size.x - 8, size.y - 8)]:  # clous
			draw_rect(Rect2(p, Vector2(4, 4)), Color("d9c27a"))


## Cadre « montage » pixel art autour d'une image (bois + liseré doré + clous).
class PicFrame extends MarginContainer:
	func _init(tex: Texture2D, h := 120) -> void:
		for s in ["left", "right", "top", "bottom"]:
			add_theme_constant_override("margin_" + s, 12)
		size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		var ratio := float(tex.get_width()) / maxf(float(tex.get_height()), 1.0)
		tr.custom_minimum_size = Vector2(clampf(h * ratio, 60.0, 360.0), h)
		add_child(tr)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var wood := Color("7a5533")
		KPx.panel(self, r, wood, wood.darkened(0.65), true, 1)
		draw_rect(r.grow(-8), Color("e0c36a"), false, 2.0)
		draw_rect(r.grow(-10), Color("0b0e12"), false, 2.0)
		for p in [Vector2(3, 3), Vector2(size.x - 7, 3), Vector2(3, size.y - 7), Vector2(size.x - 7, size.y - 7)]:
			draw_rect(Rect2(p, Vector2(4, 4)), Color("f5e6a8"))
