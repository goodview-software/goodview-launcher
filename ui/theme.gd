extends RefCounted
## Charte graphique : couleurs, styles partagés et thème global de l'application.

const BG := Color("0e1116")
const CARD := Color("171b22")
const CARD_HI := Color("1e242d")
const FIELD := Color("232a34")
const FIELD_HI := Color("2c3541")
const TEXT := Color("e8ecf1")
const DIM := Color("8892a0")
const OK := Color("4de1b4")
const WARN := Color("ffb454")
const BAD := Color("ff6b6b")
const ON_ACCENT := Color("0e1116")
const MAX_WIDTH := 640.0


## Boîte arrondie sans bordure.
static func style(bg: Color, rad := 14, pad := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(rad)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing_size = 1.2
	return sb


static func make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	th.set_color("font_color", "Label", TEXT)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		th.set_color(c, "Button", TEXT)
	th.set_color("font_disabled_color", "Button", DIM)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := style(FIELD_HI if st == "hover" else FIELD, 26, 12)
		sb.content_margin_left = 20
		sb.content_margin_right = 20
		th.set_stylebox(st, "Button", sb)
	for st in ["normal", "focus", "read_only"]:
		th.set_stylebox(st, "LineEdit", style(FIELD, 14, 12))
	th.set_color("font_color", "LineEdit", TEXT)
	th.set_color("font_placeholder_color", "LineEdit", DIM)
	th.set_color("caret_color", "LineEdit", OK)
	th.set_stylebox("background", "ProgressBar", style(FIELD, 5, 0))
	th.set_stylebox("fill", "ProgressBar", style(OK, 5, 0))
	th.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	var sg := style(Color(1, 1, 1, 0.18), 3, 0)
	sg.content_margin_left = 6
	sg.content_margin_right = 6
	for n in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(n, "VScrollBar", sg)
		th.set_stylebox(n, "HScrollBar", sg)
	th.set_stylebox("scroll", "VScrollBar", StyleBoxEmpty.new())
	th.set_stylebox("scroll", "HScrollBar", StyleBoxEmpty.new())
	return th
