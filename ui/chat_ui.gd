extends RefCounted
## Composants propres au chat : points d'attente animés, tuile d'assistant, bandeau d'assistants, bouton rond.

const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")
const Ico := preload("res://ui/icons.gd")
const U := preload("res://ui/universe.gd")
const MD := preload("res://ui/markdown.gd")


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
			draw_circle(Vector2(8 + i * 15, 11 - sin(t - i * 0.8) * 2.0), 4.0, Color(T.OK, a))


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
		custom_minimum_size = Vector2(40, 58)
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
				draw_circle(c, r + 4.0 + i * 4.0, Color(col, 0.16 - i * 0.07))
		draw_circle(c, r, col.darkened(0.62 - (0.1 if hot else 0.0)))
		draw_arc(c, r - 1.0, 0.0, TAU, 32, col if selected else Color(1, 1, 1, 0.1), 2.5 if selected else 1.2, true)
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
		add_theme_constant_override("separation", 2)
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
		var r := minf(size.x, size.y) / 2.0 * (0.94 if down else 1.0)
		var base := T.OK if enabled or true else T.FIELD
		draw_circle(c, r, base.lightened(0.12) if hot else base)
		Ico.draw_kind(self, kind, c, r / 23.0 * 0.78, T.ON_ACCENT)


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
		body.add_theme_constant_override("separation", 6)
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
