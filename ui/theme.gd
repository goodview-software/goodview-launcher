extends RefCounted
## Charte graphique : couleurs, styles partagés et thème global de l'application.

const U := preload("res://ui/universe.gd")
# Couleurs de l'univers actif : variables statiques mises à jour par apply() (les widgets les relisent au dessin).
static var BG := Color("0e1116")
static var CARD := Color("171b22")
static var CARD_HI := Color("1e242d")
static var FIELD := Color("232a34")
static var FIELD_HI := Color("2c3541")
static var OK := Color("4de1b4")  # accent de l'univers actif
static var universe := 0
const TEXT := Color("e8ecf1")
const DIM := Color("8892a0")
const WARN := Color("ffb454")
const BAD := Color("ff6b6b")
static var ON_ACCENT := Color("0e1116")
const MAX_WIDTH := 640.0


## Applique la charte de l'univers i (0..7). Renvoie true si elle a changé.
static func apply(i: int) -> bool:
	i = clampi(i, 0, U.count() - 1)
	var changed := i != universe
	universe = i
	var u := U.get_u(i)
	BG = Color(str(u.bg))
	CARD = Color(str(u.card))
	CARD_HI = Color(str(u.card_hi))
	FIELD = Color(str(u.field))
	FIELD_HI = FIELD.lightened(0.08)
	OK = Color(str(u.accent))
	ON_ACCENT = BG
	return changed


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
	for st in ["panel", "hover"]:
		th.set_stylebox(st, "PopupMenu", style(CARD_HI, 12, 8))
	th.set_color("font_color", "PopupMenu", TEXT)
	th.set_color("font_hover_color", "PopupMenu", ON_ACCENT)
	th.set_stylebox("hover", "PopupMenu", style(OK, 8, 6))
	th.set_stylebox("panel", "TooltipPanel", style(CARD_HI, 8, 8))
	th.set_stylebox("normal", "TextEdit", style(FIELD, 16, 12))
	th.set_stylebox("focus", "TextEdit", style(FIELD, 16, 12))
	th.set_stylebox("read_only", "TextEdit", style(FIELD, 16, 12))
	th.set_color("font_color", "TextEdit", TEXT)
	th.set_color("caret_color", "TextEdit", OK)
	th.set_color("font_placeholder_color", "TextEdit", DIM)
	th.set_color("selection_color", "TextEdit", Color(OK, 0.3))
	th.set_color("selection_color", "RichTextLabel", Color(OK, 0.3))
	th.set_color("default_color", "RichTextLabel", TEXT)
	var sl := style(FIELD_HI, 4, 0)
	sl.content_margin_top = 4
	sl.content_margin_bottom = 4
	th.set_stylebox("slider", "HSlider", sl)
	var sa := style(OK, 4, 0)
	sa.content_margin_top = 4
	sa.content_margin_bottom = 4
	th.set_stylebox("grabber_area", "HSlider", sa)
	th.set_stylebox("grabber_area_highlight", "HSlider", sa)
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
