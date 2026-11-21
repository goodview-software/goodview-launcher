extends Control
## Goodview Launcher : catalogue des apps de l'organisation GitHub, fiche de présentation par app,
## installation de la dernière release Linux dans user://apps/<repo>/, mise à jour, raccourci bureau, lancement.
##
## Convention par repo (tous optionnels) :
##   icon.png | icon.svg   à la racine : icône
##   app.json              {"name", "tagline", "description", "screenshots": ["docs/a.png", ...]}

const ORGS := ["goodview-software"]
const API := "https://api.github.com"
const RAW := "https://raw.githubusercontent.com"
const APPS_DIR := "user://apps"
const VERSION: String = preload("res://version.gd").VERSION
const UPDATE_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest/download/version.json"
const RELEASES_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest"
const STATE_FILE := "user://installed.json"
const CFG_FILE := "user://settings.cfg"
const EXCLUDED := [".github", "goodview-launcher"]

const QR := preload("res://qr.gd")
const C_BG := Color("0e1116")
const C_CARD := Color("171b22")
const C_CARD_HI := Color("1e242d")
const C_TEXT := Color("e8ecf1")
const C_DIM := Color("8892a0")
const C_OK := Color("4de1b4")
const C_WARN := Color("ffb454")


# ------------------------------------------------------------------ Widgets dessinés (même langage que Pocket Speaker)

class Orb extends Control:
	const SHEET := preload("res://mascot/goody.png")
	const ANIMS := {"idle": [0, 4], "happy": [1, 4], "wait": [2, 4], "off": [3, 4], "sad": [4, 4]}
	const FPS := {"idle": 3.0, "happy": 6.0, "wait": 3.0, "off": 1.5, "sad": 2.0}
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

	func _process(d: float) -> void:
		pulse = fposmod(pulse + d, TAU)
		t += d * FPS[anim] * (1.0 + level * 1.5)
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


class Ico:
	static func box(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.set_corner_radius_all(int(rad))
		sb.anti_aliasing_size = 1.0
		ci.draw_style_box(sb, r)

	static func draw_kind(ci: CanvasItem, kind: String, c: Vector2, k: float, col: Color) -> void:
		var w := 3.2 * k
		match kind:
			"refresh":
				var a1 := PI * 1.45
				ci.draw_arc(c, 14.0 * k, -PI * 0.15, a1, 28, col, w, true)
				var p := c + Vector2(cos(a1), sin(a1)) * 14.0 * k
				var tn := Vector2(-sin(a1), cos(a1))
				var nm := Vector2(cos(a1), sin(a1))
				ci.draw_colored_polygon(PackedVector2Array([p + tn * 9.0 * k, p + nm * 7.0 * k, p - nm * 7.0 * k]), col)
			"trash":
				ci.draw_line(c + Vector2(-14, -11) * k, c + Vector2(14, -11) * k, col, w, true)
				ci.draw_polyline(PackedVector2Array([c + Vector2(-5, -11) * k, c + Vector2(-5, -16) * k,
						c + Vector2(5, -16) * k, c + Vector2(5, -11) * k]), col, w, true)
				ci.draw_polyline(PackedVector2Array([c + Vector2(-10, -6) * k, c + Vector2(-8, 16) * k,
						c + Vector2(8, 16) * k, c + Vector2(10, -6) * k]), col, w, true)
			"play":
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-9, -15) * k, c + Vector2(16, 0) * k,
						c + Vector2(-9, 15) * k]), col)
			"download":
				ci.draw_line(c + Vector2(0, -16) * k, c + Vector2(0, 6) * k, col, w, true)
				ci.draw_polyline(PackedVector2Array([c + Vector2(-9, -2) * k, c + Vector2(0, 8) * k,
						c + Vector2(9, -2) * k]), col, w, true)
				ci.draw_polyline(PackedVector2Array([c + Vector2(-14, 12) * k, c + Vector2(-14, 18) * k,
						c + Vector2(14, 18) * k, c + Vector2(14, 12) * k]), col, w, true)
			"desktop":
				ci.draw_rect(Rect2(c + Vector2(-18, -15) * k, Vector2(36, 24) * k), col, false, w)
				ci.draw_line(c + Vector2(0, 9) * k, c + Vector2(0, 17) * k, col, w, true)
				ci.draw_line(c + Vector2(-8, 17) * k, c + Vector2(8, 17) * k, col, w, true)
			"phone":
				ci.draw_rect(Rect2(c + Vector2(-11, -19) * k, Vector2(22, 38) * k), col, false, w)
				ci.draw_line(c + Vector2(-3, 13) * k, c + Vector2(3, 13) * k, col, w, true)
			"check":
				ci.draw_polyline(PackedVector2Array([c + Vector2(-12, 0) * k, c + Vector2(-4, 9) * k,
						c + Vector2(13, -9) * k]), col, 4.0 * k, true)
			"chevron":
				ci.draw_polyline(PackedVector2Array([c + Vector2(-5, -10) * k, c + Vector2(5, 0) * k,
						c + Vector2(-5, 10) * k]), col, 3.6 * k, true)
			"back":
				ci.draw_polyline(PackedVector2Array([c + Vector2(5, -11) * k, c + Vector2(-6, 0) * k,
						c + Vector2(5, 11) * k]), col, 3.8 * k, true)
			"github":
				ci.draw_arc(c, 15.0 * k, 0.0, TAU, 32, col, w, true)
				ci.draw_polyline(PackedVector2Array([c + Vector2(-6, -4) * k, c + Vector2(-10, 0) * k,
						c + Vector2(-6, 4) * k]), col, w, true)
				ci.draw_polyline(PackedVector2Array([c + Vector2(6, -4) * k, c + Vector2(10, 0) * k,
						c + Vector2(6, 4) * k]), col, w, true)


class IconBtn extends Control:
	signal pressed
	var kind := "refresh"
	var col := Color("e8ecf1"):
		set(v):
			col = v
			queue_redraw()
	var spin := false:
		set(v):
			spin = v
			angle = 0.0
			queue_redraw()
	var hot := false
	var angle := 0.0

	func _init(k := "refresh", px := 44) -> void:
		kind = k
		custom_minimum_size = Vector2(px, px)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func():
			hot = true
			queue_redraw())
		mouse_exited.connect(func():
			hot = false
			queue_redraw())

	func _process(d: float) -> void:
		if spin:
			angle += d * 6.0
			queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			pressed.emit()
			accept_event()

	func _draw() -> void:
		var c := size / 2.0
		draw_circle(c, minf(size.x, size.y) / 2.0, Color(1, 1, 1, 0.12 if hot else 0.06))
		draw_set_transform(c, angle if spin else 0.0)
		Ico.draw_kind(self, kind, Vector2.ZERO, minf(size.x, size.y) / 46.0 * 0.78, col)
		draw_set_transform(Vector2.ZERO)


class Toggle extends Control:
	signal toggled(on: bool)
	var on := false
	var t := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(58, 34)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	func set_on(v: bool) -> void:  # sans émettre de signal
		on = v

	func _process(d: float) -> void:
		t = move_toward(t, 1.0 if on else 0.0, d * 9.0)
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on = not on
			toggled.emit(on)
			accept_event()

	func _draw() -> void:
		var h := size.y
		var bg := Color("2a313c").lerp(Color("4de1b4"), t)
		draw_rect(Rect2(h / 2, 0, size.x - h, h), bg, true)
		draw_circle(Vector2(h / 2, h / 2), h / 2, bg)
		draw_circle(Vector2(size.x - h / 2, h / 2), h / 2, bg)
		draw_circle(Vector2(lerpf(h / 2, size.x - h / 2, t), h / 2 + 1.0), h / 2 - 3, Color(0, 0, 0, 0.25))
		draw_circle(Vector2(lerpf(h / 2, size.x - h / 2, t), h / 2), h / 2 - 4, Color.WHITE)


## Icône d'app : carré arrondi + image (ou lettre colorée), avec halo doux et pastille d'état optionnels.
class AppIcon extends Control:
	var tex: Texture2D
	var letter := "?"
	var tint := Color("4de1b4")
	var halo := false
	var badge := Color(0, 0, 0, 0)
	var pulse := 0.0

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
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("232a34") if tex != null else tint.darkened(0.35)
		sb.set_corner_radius_all(int(side * 0.24))
		sb.anti_aliasing_size = 1.2
		var r := Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side))
		draw_style_box(sb, r)
		if tex != null:
			var m := side * 0.12
			draw_texture_rect(tex, Rect2(r.position + Vector2(m, m), r.size - Vector2(m, m) * 2.0), false)
		else:
			var fs := int(side * 0.5)
			draw_string(ThemeDB.fallback_font, Vector2(r.position.x, c.y + fs * 0.36), letter,
					HORIZONTAL_ALIGNMENT_CENTER, side, fs, Color.WHITE)
		if badge.a > 0.0:
			var bp := r.position + Vector2(side, 0) - Vector2(side * 0.08, -side * 0.08)
			draw_circle(bp, side * 0.14, Color("0e1116"))
			draw_circle(bp, side * 0.1, badge)


class Avatar extends Control:
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

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		draw_circle(c, r, (BODIES[variant] as Color).darkened(0.62))
		var s := int(r * 2.0 * 0.86 / 32.0) * 32
		s = maxi(s, 32)
		draw_texture_rect_region(SHEET, Rect2((c - Vector2(s, s) / 2.0).round(), Vector2(s, s)), Rect2(variant * 32, 0, 32, 32))
		draw_arc(c, r - 1.5, 0.0, TAU, 48, Color("4de1b4") if selected else Color(1, 1, 1, 0.12), 3.0 if selected else 1.5, true)
		if badge:
			draw_circle(c + Vector2(r * 0.72, -r * 0.72), r * 0.27, Color("ff6b6b"))


# ------------------------------------------------------------------ État

var pseudo := ""
var avatar_id := 0
var installed := {}  # repo -> {tag, exe, desk}
var apps: Array = []  # {name, org, repo, release, asset, icon, manifest}
var busy := false
var checking := false
var cur_app: Dictionary = {}

var col: VBoxContainer
var orb: Orb
var home_status: Label
var page_home: VBoxContainer
var list_box: VBoxContainer
var page_detail: VBoxContainer
var page_profile: VBoxContainer
var status: Label
var progress: ProgressBar
var chip_avatar: Avatar
var chip_name: Label
var chk_btn: IconBtn
var prof_avatar: Avatar
var pseudo_edit: LineEdit
var pickers: Array = []
var upd_lbl: Label
var upd_btn: Button
var upd_info := {}
var upd_http: HTTPRequest
var home_anim := "wait"


func _ready() -> void:
	_load_state()
	_write_shared_profile()  # le profil partagé reflète toujours le choix du launcher
	_build_ui()
	_refresh_account()
	_show_home()
	refresh()
	_check_update()


func _process(_d: float) -> void:
	orb.anim = home_anim
	orb.variant = avatar_id
	orb.color = orb.color.lerp({"wait": C_WARN, "idle": C_OK, "happy": C_OK, "off": Color("5b6573"),
			"sad": Color("ff6b6b")}[home_anim], 0.1)


# ------------------------------------------------------------------ Thème

func _style(bg: Color, rad := 14, pad := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(rad)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing_size = 1.2
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	th.set_color("font_color", "Label", C_TEXT)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(c, "Button", C_TEXT)
	th.set_color("font_disabled_color", "Button", C_DIM)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := _style(Color("232a34") if st != "hover" else Color("2c3541"), 26, 12)
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		th.set_stylebox(st, "Button", sb)
	for st in ["normal", "focus"]:
		th.set_stylebox(st, "LineEdit", _style(Color("232a34"), 14, 12))
	th.set_color("font_color", "LineEdit", C_TEXT)
	th.set_stylebox("background", "ProgressBar", _style(Color("232a34"), 5, 0))
	th.set_stylebox("fill", "ProgressBar", _style(C_OK, 5, 0))
	th.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	var sg := _style(Color(1, 1, 1, 0.18), 3, 0)
	sg.content_margin_left = 6
	sg.content_margin_right = 6
	for n in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(n, "VScrollBar", sg)
		th.set_stylebox(n, "HScrollBar", sg)
	th.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	th.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	return th


func _label(text: String, size: int, color: Color, parent: Control) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _pill(parent: Control, text: String, color: Color) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(Color(color, 0.14), 14, 4))
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_left = 12
	(p.get_theme_stylebox("panel") as StyleBoxFlat).content_margin_right = 12
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	var l := _label(text, 13, color, p)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _card(parent: Control, pad := 18) -> VBoxContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(C_CARD, 22, pad))
	parent.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	return v


# ------------------------------------------------------------------ Interface

func _build_ui() -> void:
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 18)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 24)
	scroll.add_child(margin)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(center)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	center.add_child(col)
	get_viewport().size_changed.connect(_fit_width)
	_fit_width()

	# en-tête : vérifier les mises à jour + compte
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	col.add_child(head)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	chk_btn = IconBtn.new("refresh", 44)
	chk_btn.tooltip_text = "Vérifier les mises à jour"
	chk_btn.pressed.connect(check_all)
	chk_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(chk_btn)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _style(C_CARD, 26, 5))
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_show_profile())
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(ch)
	chip_avatar = Avatar.new()
	chip_avatar.custom_minimum_size = Vector2(36, 36)
	chip_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(chip_avatar)
	chip_name = _label("", 16, C_TEXT, ch)
	chip_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(chip)

	# accueil : mascotte + liste groupée
	page_home = VBoxContainer.new()
	page_home.add_theme_constant_override("separation", 14)
	col.add_child(page_home)
	orb = Orb.new()
	orb.custom_minimum_size = Vector2(0, 210)
	page_home.add_child(orb)
	home_status = _label("", 22, C_TEXT, page_home)
	home_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var group := PanelContainer.new()
	group.add_theme_stylebox_override("panel", _style(C_CARD, 24, 8))
	page_home.add_child(group)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 0)
	group.add_child(list_box)

	page_detail = VBoxContainer.new()
	page_detail.add_theme_constant_override("separation", 16)
	col.add_child(page_detail)
	page_profile = VBoxContainer.new()
	page_profile.add_theme_constant_override("separation", 18)
	col.add_child(page_profile)
	_build_profile()

	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 10)
	progress.visible = false
	col.add_child(progress)
	status = _label("", 14, C_DIM, col)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _fit_width() -> void:
	if col != null:
		col.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 36.0, 300.0, 640.0)


func _show_home() -> void:
	cur_app = {}
	page_home.visible = true
	page_detail.visible = false
	page_profile.visible = false
	chk_btn.visible = true
	_render_list()


func _show_profile() -> void:
	cur_app = {}
	page_home.visible = false
	page_detail.visible = false
	page_profile.visible = true
	chk_btn.visible = false
	_refresh_account()


func _show_detail(a: Dictionary) -> void:
	cur_app = a
	page_home.visible = false
	page_profile.visible = false
	page_detail.visible = true
	chk_btn.visible = false
	_render_detail()


# ------------------------------------------------------------------ Accueil

func _render_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	for i in apps.size():
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color(1, 1, 1, 0.06)
			sep.custom_minimum_size = Vector2(0, 1)
			list_box.add_child(sep)
		list_box.add_child(_row(apps[i]))


func _row(a: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sb := _style(Color(0, 0, 0, 0), 16, 12)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func(): sb.bg_color = Color(1, 1, 1, 0.05))
	p.mouse_exited.connect(func(): sb.bg_color = Color(0, 0, 0, 0))
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(a))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(_icon(a, 56, false))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_label(_title(a), 18, C_TEXT, v).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := _label(_tagline(a), 13, C_DIM, v)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.clip_text = true
	var s := _state(a)
	var pill_box := HBoxContainer.new()
	pill_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pill_box)
	_pill(pill_box, s[0], s[1])
	var ch := Control.new()
	ch.custom_minimum_size = Vector2(22, 22)
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.draw.connect(func(): Ico.draw_kind(ch, "chevron", ch.size / 2.0, 0.5, C_DIM))
	h.add_child(ch)
	return p


func _icon(a: Dictionary, px: int, halo: bool) -> AppIcon:
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.tex = a.get("icon")
	ic.letter = str(a.name).substr(0, 1).to_upper()
	ic.tint = Color.from_hsv(float(str(a.name).hash() % 360) / 360.0, 0.55, 0.9)
	ic.halo = halo
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func _title(a: Dictionary) -> String:
	return str(a.manifest.get("name", str(a.name).replace("-", " ").capitalize()))


func _tagline(a: Dictionary) -> String:
	var t = a.manifest.get("tagline", a.repo.get("description", ""))
	return str(t) if t != null else ""


func _tag(a: Dictionary) -> String:
	return str(a.release.get("tag_name", ""))


## [texte, couleur] de la pastille d'état
func _state(a: Dictionary) -> Array:
	var tag := _tag(a)
	if tag == "":
		return ["Bientôt", C_DIM]
	if not installed.has(a.name):
		return [tag, C_DIM]
	if installed[a.name].tag == tag:
		return ["Installée", C_OK]
	return ["Mise à jour", C_WARN]


func _update_home_state() -> void:
	if apps.is_empty():
		home_anim = "off"
		home_status.text = "Aucune app"
		return
	var upd := 0
	var inst := 0
	for a in apps:
		if installed.has(a.name):
			inst += 1
			if installed[a.name].tag != _tag(a):
				upd += 1
	if upd > 0:
		home_anim = "happy"
		home_status.text = "%d mise%s à jour" % [upd, "s" if upd > 1 else ""]
	else:
		home_anim = "idle"
		home_status.text = "%d app%s" % [apps.size(), "s" if apps.size() > 1 else ""]


# ------------------------------------------------------------------ Fiche d'app

func _render_detail() -> void:
	var a := cur_app
	for c in page_detail.get_children():
		c.queue_free()
	var tag := _tag(a)
	var inst: Dictionary = installed.get(a.name, {})

	var top := HBoxContainer.new()
	page_detail.add_child(top)
	var back := IconBtn.new("back", 44)
	back.tooltip_text = "Catalogue"
	back.pressed.connect(_show_home)
	top.add_child(back)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var gh := IconBtn.new("github", 44)
	gh.tooltip_text = "Ouvrir sur GitHub"
	gh.pressed.connect(func(): OS.shell_open("https://github.com/%s/%s" % [a.org, a.name]))
	top.add_child(gh)

	var ic := _icon(a, 210, true)
	ic.tint = Color.from_hsv(float(str(a.name).hash() % 360) / 360.0, 0.5, 0.95)
	var s := _state(a)
	if installed.has(a.name):
		ic.badge = s[1]
	page_detail.add_child(ic)

	var t := _label(_title(a), 28, C_TEXT, page_detail)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tg := _label(_tagline(a), 15, C_DIM, page_detail)
	tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 8)
	page_detail.add_child(chips)
	if tag != "":
		_pill(chips, tag, C_DIM)
	if not a.asset.is_empty():
		_pill(chips, "%.0f Mo" % (float(a.asset.get("size", 0)) / 1048576.0), C_DIM)
	if s[0] != tag:
		_pill(chips, s[0], s[1])

	# action principale
	var main := Button.new()
	main.custom_minimum_size = Vector2(0, 58)
	main.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	main.custom_minimum_size.x = 260
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _style(C_OK if st != "hover" else C_OK.lightened(0.15), 29, 12)
		main.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		main.add_theme_color_override(c, Color("0e1116"))
	main.add_theme_font_size_override("font_size", 19)
	var can: bool = tag != "" and not a.asset.is_empty()
	if tag == "":
		main.text = "Pas encore publiée"
	elif not can and (inst.is_empty() or inst.tag != tag):
		main.text = "Pas de version Linux"
	elif inst.is_empty():
		main.text = "Installer"
	elif inst.tag != tag:
		main.text = "Mettre à jour"
	else:
		main.text = "Lancer"
	if not can and (inst.is_empty() or inst.tag != tag):
		main.disabled = true
		main.add_theme_stylebox_override("disabled", _style(Color("232a34"), 29, 12))
	main.pressed.connect(func():
		if main.text == "Lancer":
			_launch(a.name)
		else:
			install(a))
	page_detail.add_child(main)

	# QR code : télécharger l'APK avec le téléphone
	var apk := _pick_apk(a.release)
	if not apk.is_empty():
		var qc := _card(page_detail)
		var qr_url := str(apk.browser_download_url)
		var qt: Texture2D = QR.texture(qr_url, 6)
		var qh := HBoxContainer.new()
		qh.add_theme_constant_override("separation", 18)
		qc.add_child(qh)
		if qt != null:
			var fr := PanelContainer.new()
			fr.add_theme_stylebox_override("panel", _style(Color.WHITE, 16, 6))
			fr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			qh.add_child(fr)
			var tr := TextureRect.new()
			tr.texture = qt
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.custom_minimum_size = Vector2(170, 170)
			tr.tooltip_text = "Scanne avec ton téléphone"
			fr.add_child(tr)
		var qv := VBoxContainer.new()
		qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		qv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		qv.alignment = BoxContainer.ALIGNMENT_CENTER
		qv.add_theme_constant_override("separation", 12)
		qh.add_child(qv)
		var ph := IconBtn.new("phone", 64)
		ph.tooltip_text = "Télécharger l'APK (Android)"
		ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ph.pressed.connect(func(): OS.shell_open(qr_url))
		qv.add_child(ph)
		var pr := HBoxContainer.new()
		pr.alignment = BoxContainer.ALIGNMENT_CENTER
		qv.add_child(pr)
		_pill(pr, "APK · %.0f Mo" % (float(apk.get("size", 0)) / 1048576.0), C_DIM)

	# réglages en icônes (comme Pocket Speaker)
	var card := _card(page_detail)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 14)
	card.add_child(r1)
	var i1 := IconBtn.new("refresh", 44)
	i1.tooltip_text = "Vérifier les mises à jour de cette app"
	i1.pressed.connect(func(): check_one(a))
	r1.add_child(i1)
	var st1 := _label(_check_text(a), 15, C_DIM, r1)
	st1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not inst.is_empty():
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 14)
		card.add_child(r2)
		var i2 := IconBtn.new("desktop", 44)
		i2.tooltip_text = "Raccourci sur le bureau"
		i2.col = C_OK if inst.get("desk", false) else C_TEXT
		r2.add_child(i2)
		var sp2 := Control.new()
		sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(sp2)
		var tg2 := Toggle.new()
		tg2.set_on(inst.get("desk", false))
		tg2.tooltip_text = "Raccourci sur le bureau"
		tg2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tg2.toggled.connect(func(on: bool):
			_set_shortcut(a, on)
			i2.col = C_OK if on else C_TEXT)
		r2.add_child(tg2)
		var r3 := HBoxContainer.new()
		r3.add_theme_constant_override("separation", 14)
		card.add_child(r3)
		var i3 := IconBtn.new("trash", 44)
		i3.tooltip_text = "Désinstaller"
		i3.col = Color("ff6b6b")
		i3.pressed.connect(func(): _uninstall(a))
		r3.add_child(i3)

	# captures d'écran
	var shots: Array = a.manifest.get("screenshots", [])
	if shots.size() > 0:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 250)
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page_detail.add_child(sc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		sc.add_child(row)
		_load_shots(a, shots, row)

	var desc := str(a.manifest.get("description", ""))
	if desc != "":
		_section("À propos", desc)
	var notes := str(a.release.get("body", "")).strip_edges()
	if notes != "":
		_section("Nouveautés · " + tag, notes.left(900))


func _pick_apk(release: Dictionary) -> Dictionary:
	for x in release.get("assets", []):
		if str(x.name).to_lower().ends_with(".apk"):
			return x
	return {}


func _check_text(a: Dictionary) -> String:
	var inst: Dictionary = installed.get(a.name, {})
	if _tag(a) == "":
		return "Aucune version publiée"
	if inst.is_empty():
		return "Dernière version : " + _tag(a)
	if inst.tag == _tag(a):
		return "À jour"
	return "%s → %s" % [inst.tag, _tag(a)]


func _section(title: String, body: String) -> void:
	var v := _card(page_detail)
	_label(title, 18, C_TEXT, v)
	_label(body, 15, C_DIM, v)


func _load_shots(a: Dictionary, shots: Array, row: HBoxContainer) -> void:
	for s in shots:
		var r: Array = await _get_bytes("%s/%s/%s/HEAD/%s" % [RAW, a.org, a.name, str(s)])
		if r[0] != 200 or not is_instance_valid(row):
			continue
		var t := _tex(r[1], str(s).ends_with(".svg"))
		if t == null:
			continue
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(250.0 * t.get_width() / maxf(1.0, t.get_height()), 240)
		row.add_child(tr)


# ------------------------------------------------------------------ Profil

func _build_profile() -> void:
	var top := HBoxContainer.new()
	page_profile.add_child(top)
	var back := IconBtn.new("back", 44)
	back.pressed.connect(func():
		_commit_profile()
		_show_home())
	top.add_child(back)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	page_profile.add_child(box)
	prof_avatar = Avatar.new()
	prof_avatar.custom_minimum_size = Vector2(140, 140)
	prof_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(prof_avatar)
	var pick := HFlowContainer.new()
	pick.alignment = FlowContainer.ALIGNMENT_CENTER
	pick.add_theme_constant_override("h_separation", 10)
	pick.add_theme_constant_override("v_separation", 10)
	box.add_child(pick)
	for i in Avatar.BODIES.size():
		var av := Avatar.new()
		av.variant = i
		av.custom_minimum_size = Vector2(64, 64)
		av.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		av.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				avatar_id = i
				_save_state()
				_refresh_account())
		pick.add_child(av)
		pickers.append(av)
	pseudo_edit = LineEdit.new()
	pseudo_edit.placeholder_text = "Pseudo"
	pseudo_edit.max_length = 24
	pseudo_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	pseudo_edit.add_theme_font_size_override("font_size", 22)
	pseudo_edit.custom_minimum_size = Vector2(300, 54)
	pseudo_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pseudo_edit.text_submitted.connect(func(_t: String): _commit_profile())
	pseudo_edit.focus_exited.connect(_commit_profile)
	box.add_child(pseudo_edit)

	var card := _card(page_profile)
	var vr := HBoxContainer.new()
	card.add_child(vr)
	upd_lbl = _label("v" + VERSION, 15, C_DIM, vr)
	upd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upd_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	upd_btn = Button.new()
	upd_btn.visible = false
	upd_btn.pressed.connect(_do_update)
	vr.add_child(upd_btn)


func _commit_profile() -> void:
	var np := pseudo_edit.text.strip_edges()
	if np != "":
		pseudo = np
	_save_state()
	_refresh_account()


func _refresh_account() -> void:
	if pseudo == "":
		var u := OS.get_environment("USER").capitalize()
		pseudo = u if u != "" else "Invité"
	chip_name.text = pseudo
	for a in [chip_avatar, prof_avatar]:
		if a != null:
			a.variant = avatar_id
	for i in pickers.size():
		pickers[i].selected = i == avatar_id
	if pseudo_edit != null:
		pseudo_edit.text = pseudo


# ------------------------------------------------------------------ Réseau

func _headers(binary := false) -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: goodview-launcher"])
	h.append("Accept: application/octet-stream" if binary else "Accept: application/vnd.github+json")
	return h


func _get_bytes(url: String) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	if req.request(url, _headers()) != OK:
		req.queue_free()
		return [0, PackedByteArray()]
	var res: Array = await req.request_completed
	req.queue_free()
	return [res[1], res[3]]


func _get_json(url: String) -> Variant:
	var r: Array = await _get_bytes(url)
	if r[0] != 200:
		return null
	return JSON.parse_string((r[1] as PackedByteArray).get_string_from_utf8())


func _tex(bytes: PackedByteArray, svg := false) -> Texture2D:
	var im := Image.new()
	var err := im.load_svg_from_buffer(bytes, 2.0) if svg else im.load_png_from_buffer(bytes)
	if err != OK and not svg:
		err = im.load_jpg_from_buffer(bytes)
	return ImageTexture.create_from_image(im) if err == OK else null


func _fetch_release(a: Dictionary) -> void:
	var rel = await _get_json("%s/repos/%s/%s/releases/latest" % [API, a.org, a.name])
	a.release = rel if rel is Dictionary else {}
	a.asset = _pick_asset(a.release)


func refresh() -> void:
	if busy:
		return
	busy = true
	apps.clear()
	_render_list()
	home_anim = "wait"
	home_status.text = ""
	var failed := 0
	for org in ORGS:
		var repos = await _get_json("%s/orgs/%s/repos?per_page=100&type=%s" % [API, org, "public"])
		if repos == null or not repos is Array:
			failed += 1
			continue
		for repo in repos:
			if repo.name in EXCLUDED or repo.get("archived", false):
				continue
			var a := {"name": repo.name, "org": org, "repo": repo, "release": {}, "asset": {}, "icon": null, "manifest": {}}
			await _fetch_release(a)
			var m: Array = await _get_bytes("%s/%s/%s/HEAD/app.json" % [RAW, org, repo.name])
			if m[0] == 200:
				var j = JSON.parse_string((m[1] as PackedByteArray).get_string_from_utf8())
				if j is Dictionary:
					a.manifest = j
			for f in ["icon.png", "icon.svg"]:
				var ic: Array = await _get_bytes("%s/%s/%s/HEAD/%s" % [RAW, org, repo.name, f])
				if ic[0] == 200:
					a.icon = _tex(ic[1], f.ends_with(".svg"))
					if a.icon != null:
						break
			apps.append(a)
			if page_home.visible:
				_render_list()
	busy = false
	if failed == ORGS.size():
		home_anim = "sad"
		home_status.text = "Hors ligne"
	else:
		_update_home_state()


func check_all() -> void:
	if checking or busy:
		return
	checking = true
	chk_btn.spin = true
	home_anim = "wait"
	for a in apps:
		await _fetch_release(a)
	checking = false
	chk_btn.spin = false
	_update_home_state()
	_render_list()


func check_one(a: Dictionary) -> void:
	if checking:
		return
	checking = true
	await _fetch_release(a)
	checking = false
	if cur_app == a:
		_render_detail()


# ------------------------------------------------------------------ Installation

func _pick_asset(release: Dictionary) -> Dictionary:
	var best := {}
	for a in release.get("assets", []):
		var n: String = a.name.to_lower()
		if n.ends_with(".apk") or n.ends_with(".pck") or n.ends_with(".json"):
			continue
		if n.contains("linux") or n.ends_with(".x86_64") or n.ends_with(".appimage"):
			return a
		if best.is_empty() and not (n.contains("windows") or n.contains("macos") or n.ends_with(".exe")):
			best = a
	return best


func install(a: Dictionary) -> void:
	if busy:
		return
	busy = true
	var name: String = a.name
	var asset: Dictionary = a.asset
	var dir := ProjectSettings.globalize_path(APPS_DIR + "/" + name)
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir)
	var file: String = dir + "/" + str(asset.name)
	var req := HTTPRequest.new()
	req.download_file = file
	req.max_redirects = 8
	add_child(req)
	req.request(str(asset.browser_download_url), PackedStringArray(["User-Agent: goodview-launcher"]))
	progress.visible = true
	progress.value = 0
	status.text = ""
	while true:
		var total := req.get_body_size()
		if total > 0:
			progress.value = 100.0 * req.get_downloaded_bytes() / total
		await get_tree().process_frame
		if req.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			break
	req.queue_free()
	progress.visible = false
	if not FileAccess.file_exists(file) or FileAccess.get_file_as_bytes(file).size() < 100:
		status.text = "Échec du téléchargement."
		busy = false
		return
	var exe := _unpack(file, dir)
	if exe == "":
		status.text = "Aucun exécutable trouvé dans " + str(asset.name)
		busy = false
		return
	var desk: bool = installed.get(name, {}).get("desk", false)
	installed[name] = {"tag": _tag(a), "exe": exe, "desk": desk}
	_save_state()
	busy = false
	if desk:
		_set_shortcut(a, true)  # recrée le raccourci (dossier réinstallé)
	_update_home_state()
	_render_detail()


func _unpack(file: String, dir: String) -> String:
	var n := file.get_file().to_lower()
	if n.ends_with(".zip"):
		var z := ZIPReader.new()
		if z.open(file) != OK:
			return ""
		for p in z.get_files():
			if p.ends_with("/"):
				DirAccess.make_dir_recursive_absolute(dir + "/" + p)
				continue
			DirAccess.make_dir_recursive_absolute((dir + "/" + p).get_base_dir())
			var f := FileAccess.open(dir + "/" + p, FileAccess.WRITE)
			f.store_buffer(z.read_file(p))
			f.close()
		z.close()
		DirAccess.remove_absolute(file)
	elif n.ends_with(".tar.gz") or n.ends_with(".tgz"):
		OS.execute("tar", ["-xzf", file, "-C", dir])
		DirAccess.remove_absolute(file)
	OS.execute("chmod", ["-R", "u+x", dir])
	return _find_exe(dir)


func _find_exe(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for sub in d.get_directories():
		var found := _find_exe(dir + "/" + sub)
		if found != "":
			return found
	for f in d.get_files():
		var l := f.to_lower()
		if l.ends_with(".x86_64") or l.ends_with(".appimage") or l.ends_with(".sh"):
			return dir + "/" + f
	for f in d.get_files():
		if f.get_extension() == "":
			return dir + "/" + f
	return ""


func _launch(name: String) -> void:
	var exe: String = installed[name].exe
	var pid := OS.create_process(exe, [])
	status.text = "" if pid > 0 else "Impossible de lancer " + exe


func _uninstall(a: Dictionary) -> void:
	_set_shortcut(a, false)
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(APPS_DIR + "/" + str(a.name))])
	installed.erase(a.name)
	_save_state()
	_update_home_state()
	_render_detail()


## Raccourci bureau (.desktop) pour une app installée.
func _set_shortcut(a: Dictionary, on: bool) -> void:
	var name: String = a.name
	var path := OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP) + "/" + _title(a) + ".desktop"
	if installed.has(name):
		installed[name]["desk"] = on
		_save_state()
	if not on:
		DirAccess.remove_absolute(path)
		return
	if not installed.has(name):
		return
	var exe: String = installed[name].exe
	var icon_line := ""
	if a.icon != null:
		var ip := ProjectSettings.globalize_path(APPS_DIR + "/" + name + "/icon.png")
		(a.icon as Texture2D).get_image().save_png(ip)
		icon_line = "Icon=" + ip + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		status.text = "Impossible de créer le raccourci."
		return
	f.store_string("[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec=\"%s\"\nPath=%s\n%sTerminal=false\nCategories=Game;Utility;\n"
			% [_title(a), _tagline(a), exe, exe.get_base_dir(), icon_line])
	f.close()
	OS.execute("chmod", ["+x", path])
	OS.execute("gio", ["set", path, "metadata::trusted", "true"])


# ------------------------------------------------------------------ Persistance

func _load_state() -> void:
	if FileAccess.file_exists(STATE_FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
		if d is Dictionary:
			installed = d
	var cfg := ConfigFile.new()
	if cfg.load(CFG_FILE) == OK:
		avatar_id = clampi(int(cfg.get_value("profile", "avatar", 0)), 0, 7)
		pseudo = str(cfg.get_value("profile", "pseudo", ""))


## Profil partagé avec toutes les apps Goodview (mascotte + pseudo) : ~/.config/goodview/profile.json
func _write_shared_profile() -> void:
	var dir := OS.get_environment("HOME") + "/.config/goodview"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/profile.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"pseudo": pseudo, "mascot": avatar_id}))
		f.close()


func _save_state() -> void:
	_write_shared_profile()
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(installed))
	f.close()
	var cfg := ConfigFile.new()
	cfg.set_value("profile", "avatar", avatar_id)
	cfg.set_value("profile", "pseudo", pseudo)
	cfg.save(CFG_FILE)


# ------------------------------------------------------------------ Mise à jour du launcher (version.json + .pck)

func _check_update() -> void:
	upd_http = HTTPRequest.new()
	upd_http.timeout = 10.0
	add_child(upd_http)
	upd_http.request_completed.connect(_on_version_json, CONNECT_ONE_SHOT)
	upd_http.request(UPDATE_URL)


func _on_version_json(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var info = JSON.parse_string(body.get_string_from_utf8())
	if not (info is Dictionary) or not info.has("version"):
		return
	if not preload("res://boot.gd").newer(str(info["version"]), VERSION):
		upd_lbl.text = "✓ v" + VERSION
		return
	upd_info = info
	chip_avatar.badge = true
	var v := Engine.get_version_info()
	var same: bool = str(info.get("godot", "")) == "%d.%d.%d" % [v.major, v.minor, v.patch]
	upd_btn.visible = true
	if same and info.has("pck"):
		upd_lbl.text = "v%s disponible" % info["version"]
		upd_btn.text = "Mettre à jour"
	else:
		upd_lbl.text = "v%s disponible (nouveau programme)" % info["version"]
		upd_btn.text = "Télécharger"


func _do_update() -> void:
	if upd_btn.text == "Télécharger":
		OS.shell_open(RELEASES_URL)
		return
	if upd_btn.text == "Redémarrer":
		OS.set_restart_on_exit(true)
		get_tree().quit()
		return
	upd_btn.disabled = true
	upd_lbl.text = "Téléchargement…"
	upd_http.download_file = "user://update.tmp"
	upd_http.request_completed.connect(_on_pck, CONNECT_ONE_SHOT)
	upd_http.request(str(upd_info["pck"]))


func _on_pck(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	upd_http.download_file = ""
	upd_btn.disabled = false
	var tmp := "user://update.tmp"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 \
			or FileAccess.get_sha256(tmp) != str(upd_info.get("sha256", "")):
		DirAccess.remove_absolute(tmp)
		upd_lbl.text = "Échec du téléchargement"
		return
	DirAccess.rename_absolute(tmp, "user://update.pck")
	var c := ConfigFile.new()
	c.set_value("update", "version", str(upd_info["version"]))
	c.save("user://update.cfg")
	upd_lbl.text = "v%s installée" % upd_info["version"]
	upd_btn.text = "Redémarrer"
