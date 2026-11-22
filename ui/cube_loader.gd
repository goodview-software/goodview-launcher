extends Control
## Chargement : un cube roule lentement (comme un escargot) du bord gauche jusqu'au centre de l'écran,
## de 0 à 100 %. `value` (0..1) pilote la position ; `auto` = progression simulée (jamais 100 % avant finish()).
const T := preload("res://ui/theme.gd")
const SIZE := 44.0
const EDGES_FACES := [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [2, 3, 7, 6], [1, 2, 6, 5], [0, 3, 7, 4]]

var value := 0.0: set = _set_value
var auto := true
var _t := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, 220)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	queue_redraw()


## Termine l'animation : le cube atteint le centre, 100 %.
func finish() -> void:
	auto = false
	value = 1.0


func _process(dt: float) -> void:
	_t += dt
	if auto:
		value = minf(0.99, 1.0 - exp(-_t / 2.5))
	else:
		queue_redraw()


func _draw() -> void:
	var w := size.x
	var gy := size.y * 0.62
	var x0 := SIZE
	var x := lerpf(x0, w * 0.5, value)
	# piste
	draw_line(Vector2(x0, gy + SIZE * 0.5 + 6), Vector2(w * 0.5, gy + SIZE * 0.5 + 6), Color(T.DIM, 0.35), 2.0)
	draw_line(Vector2(x0, gy + SIZE * 0.5 + 6), Vector2(x, gy + SIZE * 0.5 + 6), T.OK, 2.0)
	# le cube tourne en proportion du chemin parcouru + tourne sur lui-même doucement
	var ay := (x - x0) / SIZE * 0.9 + _t * 0.6
	var ax := 0.55 + sin(_t * 0.8) * 0.15
	var pts: Array[Vector3] = []
	for i in 8:
		var v := Vector3(-1 if (i & 1) == 0 else 1, -1 if (i & 2) == 0 else 1, -1 if (i & 4) == 0 else 1) * (SIZE * 0.5)
		pts.append(v.rotated(Vector3.UP, ay).rotated(Vector3.RIGHT, ax))
	# sommets dans l'ordre des faces ci-dessus : remap bits -> indices (0..7 comme coins du cube)
	var order := [0, 1, 3, 2, 4, 5, 7, 6]
	var faces: Array = []
	for f in EDGES_FACES:
		var q: Array = []
		var zs := 0.0
		for k in f:
			var p: Vector3 = pts[order[k]]
			q.append(p)
			zs += p.z
		faces.append([zs, q])
	faces.sort_custom(func(a, b): return a[0] > b[0])  # fond d'abord
	var c := Vector2(x, gy - SIZE * 0.1)
	for i in faces.size():
		var poly := PackedVector2Array()
		for p in faces[i][1]:
			poly.append(c + Vector2(p.x, p.y))
		var shade := 0.55 + 0.45 * float(i) / float(faces.size() - 1)
		draw_colored_polygon(poly, Color(T.OK.r * shade, T.OK.g * shade, T.OK.b * shade, 0.95))
		poly.append(poly[0])
		draw_polyline(poly, T.ON_ACCENT, 1.5)
	var f := ThemeDB.fallback_font
	var s := "%d %%" % int(round(value * 100.0))
	draw_string(f, Vector2(0, size.y - 8), s, HORIZONTAL_ALIGNMENT_CENTER, w, 20, T.TEXT)
