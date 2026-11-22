extends Control
## Chargement moderne : anneau de progression lumineux (0 → 100 %) avec une comète qui tourne,
## pourcentage au centre. `value` (0..1) ; `auto` = progression simulée ; `finish()` = 100 %.
## (Nom de fichier conservé : utilisé par main.gd, home.gd et les tests.)
const T := preload("res://ui/theme.gd")
const RADIUS := 54.0
const WIDTH := 7.0

var value := 0.0: set = _set_value
var shown := 0.0  # valeur lissée affichée
var auto := true
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 240)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)


## Termine l'animation : 100 %.
func finish() -> void:
	auto = false
	value = 1.0


func _process(dt: float) -> void:
	_t += dt
	if auto:
		value = minf(0.99, 1.0 - exp(-_t / 2.5))
	shown = lerpf(shown, value, 1.0 - exp(-8.0 * dt))
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5 - Vector2(0, 10)
	var top := -PI * 0.5
	# halo doux derrière l'anneau
	for i in 6:
		draw_circle(c, RADIUS + 26.0 - i * 4.0, Color(T.OK, 0.015 + 0.01 * shown))
	# piste
	draw_arc(c, RADIUS, 0.0, TAU, 96, Color(T.DIM, 0.18), WIDTH, true)
	# anneau fin extérieur qui tourne (pointillé)
	var spin := _t * 1.2
	for i in 4:
		var a0 := spin + i * TAU / 4.0
		draw_arc(c, RADIUS + 16.0, a0, a0 + 0.35, 12, Color(T.OK, 0.35), 2.0, true)
	# progression : dégradé d'opacité du début vers la tête
	var end := top + TAU * shown
	var n := maxi(1, int(shown * 90.0))
	for i in n:
		var a0 := top + TAU * shown * float(i) / n
		var a1 := top + TAU * shown * float(i + 1) / n + 0.02
		var k := float(i + 1) / n
		draw_arc(c, RADIUS, a0, a1, 3, Color(T.OK, 0.25 + 0.75 * k), WIDTH, true)
	# tête lumineuse
	var head := c + Vector2.from_angle(end) * RADIUS
	var pulse := 1.0 + 0.15 * sin(_t * 6.0)
	for i in 5:
		draw_circle(head, (WIDTH * 0.5 + 2.0 + i * 3.5) * pulse, Color(T.OK, 0.22 - i * 0.04))
	draw_circle(head, WIDTH * 0.5 + 1.0, T.TEXT)
	# pourcentage
	var f := ThemeDB.fallback_font
	var s := "%d" % int(round(shown * 100.0))
	draw_string(f, c + Vector2(-60, 11), s, HORIZONTAL_ALIGNMENT_CENTER, 120, 32, T.TEXT)
	draw_string(f, c + Vector2(-60, 32), "%", HORIZONTAL_ALIGNMENT_CENTER, 120, 14, T.DIM)
