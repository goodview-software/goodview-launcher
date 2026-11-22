extends Control
## Chargement (pixel art, charte Goodview) : une fusée avance sur une barre segmentée de 0 à 100 %.
## Cahier des charges : style pixel du kit (KPx), couleurs = jetons du thème, animation par paliers (12 i/s),
## pourcentage en police du thème, barre centrée, s'adapte à toute largeur. `value` 0..1 ; `auto` = simulé ; `finish()` = 100 %.
## (Nom de fichier conservé : utilisé par main.gd, home.gd et les tests.)
const T := preload("res://ui/theme.gd")
const Tk := preload("res://kit/tokens.gd")
const KPx := preload("res://kit/ui/px.gd")

const UNIT := 3.0  # taille d'un pixel du sprite
const SEG := 14.0  # largeur d'un segment de la barre
const GAP := 4.0
const BAR_H := 22.0
const MAX_W := 360.0
const ROCKET := [
	"...kk...........",
	"..krkkkkkkk.....",
	".kkwwwwwwwwk....",
	"kyywwwbbbwwwk...",
	".kkwwwwwwwwk....",
	"..krkkkkkkk.....",
	"...kk...........",
]

var value := 0.0: set = _set_value
var shown := 0.0
var auto := true
var _t := 0.0
var _frame := 0
var _pal := {}


func _init() -> void:
	custom_minimum_size = Vector2(0, 240)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)


func finish() -> void:
	auto = false
	value = 1.0


func _process(dt: float) -> void:
	_t += dt
	if auto:
		value = minf(0.99, 1.0 - exp(-_t / 2.5))
	shown = lerpf(shown, value, 1.0 - exp(-7.0 * dt))
	var f := int(_t * 12.0)  # paliers : look pixel
	if f != _frame:
		_frame = f
		queue_redraw()


func _draw() -> void:
	_pal = {"k": Tk.surface0, "w": Tk.text, "b": Tk.accent, "r": T.BAD, "y": T.WARN}
	var w := minf(size.x - 2.0 * Tk.S8, MAX_W)
	var n := maxi(4, int(w / (SEG + GAP)))
	w = n * (SEG + GAP) - GAP
	var bx := roundf((size.x - w) * 0.5)
	var by := roundf(size.y * 0.5 + 6.0)
	# cadre de la barre
	KPx.panel(self, Rect2(bx - 8, by - 8, w + 16, BAR_H + 16), Tk.surface1, Tk.surface0, true, 1)
	# segments (vides puis remplis, le dernier clignote)
	var lit := shown * n
	for i in n:
		var r := Rect2(bx + i * (SEG + GAP), by, SEG, BAR_H)
		if i < int(lit):
			draw_rect(r, Tk.accent)
			draw_rect(Rect2(r.position, Vector2(SEG, 3)), Tk.accent.lightened(0.3))
			draw_rect(Rect2(r.position.x, r.end.y - 3, SEG, 3), Tk.accent.darkened(0.25))
		elif i == int(lit) and (_frame / 3) % 2 == 0 and shown < 1.0:
			draw_rect(r, Color(Tk.accent, 0.45))
		else:
			draw_rect(r, Tk.surface3)
	# fusée au bout de la partie remplie (petit rebond par paliers)
	var sz := KPx.sprite_size(ROCKET, UNIT)
	var hx := clampf(bx + shown * w, bx, bx + w) - sz.x * 0.35
	var hy := by + BAR_H * 0.5 - sz.y * 0.5 - 22.0 + float((_frame / 3) % 2) * UNIT
	var flame := (_frame % 2) * UNIT
	draw_rect(Rect2(hx - flame - UNIT, hy + sz.y * 0.5 - UNIT, UNIT, UNIT), Color(T.WARN, 0.6))
	KPx.sprite(self, ROCKET, Vector2(hx, hy), UNIT, _pal)
	# pourcentage + libellé
	var f := get_theme_default_font()
	var s := "%d %%" % int(round(shown * 100.0))
	draw_string(f, Vector2(0, by + BAR_H + 44), s, HORIZONTAL_ALIGNMENT_CENTER, size.x, Tk.TEXT_SIZES["2xl"][0], Tk.text)
	draw_string(f, Vector2(0, by - 30 - sz.y), "Goodview", HORIZONTAL_ALIGNMENT_CENTER, size.x, Tk.TEXT_SIZES["base"][0], Tk.text_muted)
