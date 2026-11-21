extends RefCounted
## Charte graphique : couleurs, styles partagés et thème global de l'application.

const U := preload("res://ui/universe.gd")
const Tk := preload("res://kit/tokens.gd")
const ThemeBuilder := preload("res://kit/theme_builder.gd")
# Couleurs de l'univers actif : variables statiques mises à jour par apply() (les widgets les relisent au dessin).
static var BG := Color("0e1116")
static var CARD := Color("171b22")
static var CARD_HI := Color("1e242d")
static var FIELD := Color("232a34")
static var FIELD_HI := Color("2c3541")
static var OK := Color("4de1b4")  # accent de l'univers actif
static var universe := 0
static var TEXT := Color("e8ecf1")
static var DIM := Color("98a2b0")
static var WARN := Color("fbbf24")
static var BAD := Color("f87171")
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
	Tk.apply(OK, {"bg": BG, "card": CARD, "card_hi": CARD_HI, "field": Color(str(u.field))})
	ON_ACCENT = Tk.on_accent
	TEXT = Tk.text
	DIM = Tk.text_muted
	WARN = Tk.warn
	BAD = Tk.danger
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
	return ThemeBuilder.build()
