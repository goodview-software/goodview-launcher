extends RefCounted
## Composants visuels réutilisables : mêmes états de survol / pression partout.

const T := preload("res://ui/theme.gd")
const Ico := preload("res://ui/icons.gd")


# ------------------------------------------------------------------ Helpers de construction

static func label(text: String, size: int, color: Color, parent: Control = null) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	# dans une ligne (HBox) un texte qui passe à la ligne se réduit à 1 lettre de large : on le garde sur une ligne
	l.autowrap_mode = TextServer.AUTOWRAP_OFF if parent is HBoxContainer else TextServer.AUTOWRAP_WORD_SMART
	if parent != null:
		parent.add_child(l)
	return l


## Pastille de texte colorée.
static func pill(parent: Control, text: String, color: Color) -> Label:
	var p := PanelContainer.new()
	var sb := T.style(Color(color, 0.14), 14, 4)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var l := label(text, 13, color, p)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Carte (fond #171b22, sans bordure) ; renvoie le conteneur vertical intérieur.
static func card(parent: Control, pad := 18) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", T.style(T.CARD, 22, pad))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	return v


static func spacer(parent: Control) -> Control:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(s)
	return s


## Ligne de réglage : titre + sous-titre à gauche ; renvoie la ligne pour y ajouter le contrôle à droite.
static func setting_row(parent: Control, title: String, sub := "") -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	parent.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 2)
	h.add_child(v)
	label(title, 17, T.TEXT, v)
	if sub != "":
		label(sub, 13, T.DIM, v)
	return h


static func hsep(parent: Control) -> void:
	var sep := ColorRect.new()
	sep.color = Color(1, 1, 1, 0.06)
	sep.custom_minimum_size = Vector2(0, 1)
	parent.add_child(sep)


# ------------------------------------------------------------------ Base interactive

## Zone cliquable : survol, pression et relâchement identiques pour tous les widgets.
class Tap extends Control:
	signal pressed
	var hot := false
	var down := false
	var enabled := true:
		set(v):
			enabled = v
			modulate.a = 1.0 if v else 0.4
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW

	func _init() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _set_hot(true))
		mouse_exited.connect(func(): _set_hot(false))

	func _set_hot(v: bool) -> void:
		hot = v
		if not v:
			down = false
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if not enabled or not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			down = true
		else:
			var inside := Rect2(Vector2.ZERO, size).has_point(e.position)
			var was := down
			down = false
			if was and inside:
				pressed.emit()
		queue_redraw()
		accept_event()


# ------------------------------------------------------------------ Boutons

class IconBtn extends Tap:
	var kind := "refresh":
		set(v):
			kind = v
			queue_redraw()
	var col := Color("e8ecf1"):
		set(v):
			col = v
			queue_redraw()
	var spin := false:
		set(v):
			spin = v
			angle = 0.0
			set_process(v)
			queue_redraw()
	var badge := false:
		set(v):
			badge = v
			queue_redraw()
	var angle := 0.0

	func _init(k := "refresh", px := 44) -> void:
		super()
		kind = k
		custom_minimum_size = Vector2(px, px)
		set_process(false)

	func _process(d: float) -> void:
		angle += d * 6.0
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, Color(1, 1, 1, 0.16 if down else (0.11 if hot else 0.05)))
		draw_set_transform(c, angle if spin else 0.0)
		var k := minf(size.x, size.y) / 46.0 * 0.78 * (0.92 if down else 1.0)
		Ico.draw_kind(self, kind, Vector2.ZERO, k, col)
		draw_set_transform(Vector2.ZERO)
		if badge:
			draw_circle(c + Vector2(r * 0.68, -r * 0.68), r * 0.26, T.BG)
			draw_circle(c + Vector2(r * 0.68, -r * 0.68), r * 0.18, T.WARN)


## Bouton texte : "primary" (accent), "soft" (neutre), "danger", "ghost" (sans fond).
class Btn extends Button:
	var kind := "soft"

	func _init(txt := "", k := "soft") -> void:
		text = txt
		kind = k
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		focus_mode = Control.FOCUS_NONE
		custom_minimum_size = Vector2(0, 50)
		add_theme_font_size_override("font_size", 17)
		_apply()

	func _apply() -> void:
		var base := T.FIELD
		var hi := T.FIELD_HI
		var fg := T.TEXT
		match kind:
			"primary":
				base = T.OK
				hi = T.OK.lightened(0.15)
				fg = T.ON_ACCENT
			"danger":
				base = Color(T.BAD, 0.18)
				hi = Color(T.BAD, 0.3)
				fg = T.BAD
			"ghost":
				base = Color(1, 1, 1, 0.0)
				hi = Color(1, 1, 1, 0.07)
				fg = T.DIM
		var rad := int(custom_minimum_size.y / 2.0)
		for st in ["normal", "hover", "pressed", "focus", "disabled"]:
			var col := hi if st == "hover" else (base.darkened(0.15) if st == "pressed" else base)
			if st == "disabled":
				col = T.FIELD if kind == "primary" else Color(base, base.a * 0.5)
			var sb := T.style(col, rad, 12)
			sb.content_margin_left = 22
			sb.content_margin_right = 22
			add_theme_stylebox_override(st, sb)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			add_theme_color_override(c, fg)
		add_theme_color_override("font_disabled_color", T.DIM)

	func set_kind(k: String) -> void:
		kind = k
		_apply()


class Toggle extends Tap:
	signal toggled(on: bool)
	var on := false
	var t := 0.0

	func _init() -> void:
		super()
		custom_minimum_size = Vector2(58, 34)
		pressed.connect(func():
			on = not on
			toggled.emit(on))

	func set_on(v: bool) -> void:  # sans émettre de signal
		on = v
		t = 1.0 if v else 0.0
		queue_redraw()

	func _process(d: float) -> void:
		var nt := move_toward(t, 1.0 if on else 0.0, d * 9.0)
		if nt != t or hot:
			t = nt
			queue_redraw()

	func _draw() -> void:
		var h := size.y
		var bg := T.FIELD_HI.lerp(T.OK, t) if hot else T.FIELD.lerp(T.OK, t)
		draw_rect(Rect2(h / 2, 0, size.x - h, h), bg, true)
		draw_circle(Vector2(h / 2, h / 2), h / 2, bg)
		draw_circle(Vector2(size.x - h / 2, h / 2), h / 2, bg)
		var kx := lerpf(h / 2, size.x - h / 2, t)
		draw_circle(Vector2(kx, h / 2 + 1.0), h / 2 - 3, Color(0, 0, 0, 0.25))
		draw_circle(Vector2(kx, h / 2), h / 2 - (5 if down else 4), Color.WHITE)


## Sélecteur segmenté : options [[id, libellé], ...].
class Seg extends Control:
	signal changed(id: String)
	var opts: Array = []
	var cur := ""

	func _init(o: Array, c: String) -> void:
		opts = o
		cur = c
		custom_minimum_size = Vector2(opts.size() * 96, 38)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func select(id: String) -> void:
		cur = id
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			var i := clampi(int(e.position.x / (size.x / opts.size())), 0, opts.size() - 1)
			if opts[i][0] != cur:
				cur = opts[i][0]
				changed.emit(cur)
				queue_redraw()
			accept_event()

	func _draw() -> void:
		var h := size.y
		Ico.box(self, Rect2(Vector2.ZERO, size), h / 2.0, T.FIELD)
		var w := size.x / opts.size()
		var font := get_theme_default_font()
		for i in opts.size():
			var on: bool = opts[i][0] == cur
			if on:
				Ico.box(self, Rect2(i * w + 3, 3, w - 6, h - 6), (h - 6) / 2.0, T.FIELD_HI)
			var txt: String = opts[i][1]
			var fs := 14
			var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(i * w + (w - tw) / 2.0, h / 2.0 + fs * 0.36), txt,
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, T.TEXT if on else T.DIM)


# ------------------------------------------------------------------ Mascotte, icônes d'app, avatars

class Orb extends Control:
	const SHEET := preload("res://mascot/goody.png")
	const ANIMS := {"idle": [0, 4], "happy": [1, 4], "wait": [2, 4], "off": [3, 4], "sad": [4, 4]}
	const FPS := {"idle": 3.0, "happy": 6.0, "wait": 3.0, "off": 1.5, "sad": 2.0}
	const COLORS := {"wait": Color("ffb454"), "idle": Color("4de1b4"), "happy": Color("4de1b4"),
			"off": Color("5b6573"), "sad": Color("ff6b6b")}
	var color := Color("5b6573")
	var variant := 0
	var level := 0.0
	var pulse := 0.0
	var t := 0.0
	var anim := "off":
		set(v):
			if v != anim:
				anim = v
				t = 0.0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		pulse = fposmod(pulse + d, TAU)
		t += d * FPS[anim] * (1.0 + level * 1.5)
		color = color.lerp(COLORS[anim], 0.1)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.26
		for i in 4:
			var rr := r + 8.0 * (i + 1) + level * 14.0 + sin(pulse + i) * 2.0
			draw_circle(c, rr, Color(color, 0.11 - i * 0.025))
		draw_circle(c, r, Color(color, 0.16))
		var row: int = ANIMS[anim][0] + variant * 5
		var n: int = ANIMS[anim][1]
		var sc := maxi(1, int(size.y * 0.72 / 32.0))
		var px := 32 * sc
		var pos := (c - Vector2(px, px) / 2.0).round()
		draw_texture_rect_region(SHEET, Rect2(pos, Vector2(px, px)), Rect2((int(t) % n) * 32, row * 32, 32, 32))


## Icône d'app : carré arrondi + image (ou lettre colorée), halo et pastille d'état optionnels.
class AppIcon extends Control:
	var tex: Texture2D
	var letter := "?"
	var tint := Color("4de1b4")
	var halo := false
	var badge := Color(0, 0, 0, 0)
	var pulse := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		if halo:
			pulse = fposmod(pulse + d, TAU)
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var s := minf(size.x, size.y)
		var side := s * (0.62 if halo else 1.0)
		if halo:
			for i in 4:
				draw_circle(c, side * 0.5 + 10.0 * (i + 1) + sin(pulse + i) * 2.0, Color(tint, 0.10 - i * 0.022))
		var r := Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side))
		Ico.box(self, r, side * 0.24, Color("232a34") if tex != null else tint.darkened(0.35))
		if tex != null:
			var m := side * 0.12
			draw_texture_rect(tex, Rect2(r.position + Vector2(m, m), r.size - Vector2(m, m) * 2.0), false)
		else:
			var fs := int(side * 0.5)
			draw_string(ThemeDB.fallback_font, Vector2(r.position.x, c.y + fs * 0.36), letter,
					HORIZONTAL_ALIGNMENT_CENTER, side, fs, Color.WHITE)
		if badge.a > 0.0:
			var bp := r.position + Vector2(side, 0) - Vector2(side * 0.08, -side * 0.08)
			draw_circle(bp, side * 0.14, T.BG)
			draw_circle(bp, side * 0.1, badge)


## Avatar rond d'une variante de mascotte ; cliquable (sélecteur) ou décoratif.
class Avatar extends Tap:
	const SHEET := preload("res://mascot/variants.png")
	const BODIES := [Color("4de1b4"), Color("ff8fb1"), Color("6aa8ff"), Color("ffa24d"), Color("b58bff"),
			Color("ffd84d"), Color("ff6b6b"), Color("c9d1da")]
	var variant := 0:
		set(v):
			variant = v
			queue_redraw()
	var selected := false:
		set(v):
			selected = v
			queue_redraw()
	var badge := false:
		set(v):
			badge = v
			queue_redraw()

	func _init(clickable := false) -> void:
		super()
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if not clickable:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if down:
			r *= 0.95
		draw_circle(c, r, (BODIES[variant] as Color).darkened(0.62 - (0.1 if hot else 0.0)))
		var s := maxi(int(r * 2.0 * 0.86 / 32.0) * 32, 32)
		draw_texture_rect_region(SHEET, Rect2((c - Vector2(s, s) / 2.0).round(), Vector2(s, s)), Rect2(variant * 32, 0, 32, 32))
		draw_arc(c, r - 1.5, 0.0, TAU, 48, T.OK if selected else Color(1, 1, 1, 0.12), 3.0 if selected else 1.5, true)
		if badge:
			draw_circle(c + Vector2(r * 0.72, -r * 0.72), r * 0.27, T.BAD)


# ------------------------------------------------------------------ Ligne de liste

## Ligne cliquable (accueil) : fond au survol, plus marqué à la pression.
class Row extends PanelContainer:
	signal pressed
	var sb := T.style(Color(0, 0, 0, 0), 16, 12)
	var hot := false
	var down := false

	func _init() -> void:
		add_theme_stylebox_override("panel", sb)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _paint(true, down))
		mouse_exited.connect(func(): _paint(false, false))

	func _paint(h: bool, d: bool) -> void:
		hot = h
		down = d
		sb.bg_color = Color(1, 1, 1, 0.09 if d else (0.05 if h else 0.0))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_paint(hot, true)
			else:
				var fire := down and Rect2(Vector2.ZERO, size).has_point(e.position)
				_paint(hot, false)
				if fire:
					pressed.emit()
			accept_event()


# ------------------------------------------------------------------ États (chargement / vide / hors-ligne / erreur)

## Mascotte + titre + message + bouton d'action optionnel.
class StateView extends VBoxContainer:
	signal action
	var orb: Orb

	func _lbl(text: String, size_: int, color: Color, parent: Control) -> Label:
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", size_)
		l.add_theme_color_override("font_color", color)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(l)
		return l

	func _init(anim: String, variant: int, title: String, msg := "", btn := "", orb_h := 150) -> void:
		add_theme_constant_override("separation", 10)
		alignment = BoxContainer.ALIGNMENT_CENTER
		orb = Orb.new()
		orb.anim = anim
		orb.variant = variant
		orb.custom_minimum_size = Vector2(0, orb_h)
		add_child(orb)
		var t := _lbl(title, 21, T.TEXT, self)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if msg != "":
			var m := _lbl(msg, 14, T.DIM, self)
			m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if btn != "":
			var b := Btn.new(btn, "soft")
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func(): action.emit())
			add_child(b)


## Lignes fantômes qui pulsent pendant le chargement.
class Skeleton extends Control:
	var t := 0.0
	var rows := 4

	func _init(n := 4) -> void:
		rows = n
		custom_minimum_size = Vector2(0, n * 80 + 16)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		t += d * 3.0
		queue_redraw()

	func _draw() -> void:
		Ico.box(self, Rect2(Vector2.ZERO, size), 24, T.CARD)
		for i in rows:
			var a := 0.05 + 0.03 * sin(t - i * 0.7)
			var y := 8.0 + i * 80.0 + 12.0
			Ico.box(self, Rect2(20, y, 56, 56), 14, Color(1, 1, 1, a))
			Ico.box(self, Rect2(92, y + 8, 150, 14), 7, Color(1, 1, 1, a))
			Ico.box(self, Rect2(92, y + 32, 230, 11), 5, Color(1, 1, 1, a * 0.7))


## Notification discrète en bas de l'écran (remplace les boîtes de dialogue).
class Toast extends PanelContainer:
	var lbl: Label
	var tw: Tween

	func _lbl(text: String, size_: int, color: Color, parent: Control) -> Label:
		var l := Label.new()
		l.text = text
		l.add_theme_font_size_override("font_size", size_)
		l.add_theme_color_override("font_color", color)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(l)
		return l

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		modulate.a = 0.0
		lbl = _lbl("", 15, T.TEXT, self)
		lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		grow_horizontal = Control.GROW_DIRECTION_BOTH
		grow_vertical = Control.GROW_DIRECTION_BEGIN
		offset_bottom = -26

	func show_msg(text: String, kind := "info") -> void:
		var col := T.TEXT
		match kind:
			"ok":
				col = T.OK
			"error":
				col = T.BAD
		var sb := T.style(Color("262d38"), 22, 12)
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		add_theme_stylebox_override("panel", sb)
		lbl.text = text
		lbl.add_theme_color_override("font_color", col)
		if tw != null:
			tw.kill()
		tw = create_tween()
		tw.tween_property(self, "modulate:a", 1.0, 0.18)
		tw.tween_interval(2.8)
		tw.tween_property(self, "modulate:a", 0.0, 0.3)

