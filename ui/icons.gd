extends RefCounted
## Icônes dessinées (traits arrondis) : un seul langage visuel pour toute l'application.


static func box(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(int(rad))
	sb.anti_aliasing_size = 1.0
	ci.draw_style_box(sb, r)


## Dessine l'icône `kind` centrée en `c`, à l'échelle `k` (1 = rayon ~16 px).
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
		"gear":
			ci.draw_arc(c, 6.0 * k, 0.0, TAU, 24, col, w, true)
			ci.draw_arc(c, 11.0 * k, 0.0, TAU, 32, col, w, true)
			for i in 8:
				var d := Vector2.from_angle(i * TAU / 8.0)
				ci.draw_line(c + d * 11.0 * k, c + d * 16.0 * k, col, w * 1.4, true)
		"star", "star_on":
			var pts := PackedVector2Array()
			for i in 10:
				var r := 16.0 if i % 2 == 0 else 7.0
				pts.append(c + Vector2.from_angle(-PI / 2.0 + i * PI / 5.0) * r * k)
			if kind == "star_on":
				ci.draw_colored_polygon(pts, col)
			pts.append(pts[0])
			ci.draw_polyline(pts, col, w * 0.7, true)
		"info":
			ci.draw_arc(c, 15.0 * k, 0.0, TAU, 32, col, w, true)
			ci.draw_line(c + Vector2(0, -1) * k, c + Vector2(0, 8) * k, col, w, true)
			ci.draw_circle(c + Vector2(0, -7) * k, 2.2 * k, col)
		"search":
			ci.draw_arc(c + Vector2(-3, -3) * k, 10.0 * k, 0.0, TAU, 28, col, w, true)
			ci.draw_line(c + Vector2(5, 5) * k, c + Vector2(15, 15) * k, col, w, true)
		"close":
			ci.draw_line(c + Vector2(-9, -9) * k, c + Vector2(9, 9) * k, col, w, true)
			ci.draw_line(c + Vector2(9, -9) * k, c + Vector2(-9, 9) * k, col, w, true)
		"folder":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-16, 12) * k, c + Vector2(-16, -12) * k,
					c + Vector2(-5, -12) * k, c + Vector2(-1, -7) * k, c + Vector2(16, -7) * k,
					c + Vector2(16, 12) * k, c + Vector2(-16, 12) * k]), col, w, true)
		"link":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-5, -13) * k, c + Vector2(-14, -13) * k,
					c + Vector2(-14, 14) * k, c + Vector2(13, 14) * k, c + Vector2(13, 5) * k]), col, w, true)
			ci.draw_line(c + Vector2(-3, 4) * k, c + Vector2(14, -13) * k, col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(4, -14) * k, c + Vector2(14, -14) * k,
					c + Vector2(14, -4) * k]), col, w, true)
		"alert":
			ci.draw_polyline(PackedVector2Array([c + Vector2(0, -16) * k, c + Vector2(16, 13) * k,
					c + Vector2(-16, 13) * k, c + Vector2(0, -16) * k]), col, w, true)
			ci.draw_line(c + Vector2(0, -5) * k, c + Vector2(0, 3) * k, col, w, true)
			ci.draw_circle(c + Vector2(0, 8) * k, 1.8 * k, col)
		"wifi_off":
			var o := c + Vector2(0, 10) * k
			for r in [7.0, 14.0, 21.0]:
				ci.draw_arc(o, r * k, -PI * 0.82, -PI * 0.18, 16, col, w, true)
			ci.draw_circle(o, 2.0 * k, col)
			ci.draw_line(c + Vector2(-15, -15) * k, c + Vector2(15, 15) * k, col, w, true)
		"sort":
			ci.draw_line(c + Vector2(-14, -9) * k, c + Vector2(14, -9) * k, col, w, true)
			ci.draw_line(c + Vector2(-14, 0) * k, c + Vector2(8, 0) * k, col, w, true)
			ci.draw_line(c + Vector2(-14, 9) * k, c + Vector2(2, 9) * k, col, w, true)
		"apps":
			for p in [Vector2(-8, -8), Vector2(8, -8), Vector2(-8, 8), Vector2(8, 8)]:
				ci.draw_rect(Rect2(c + p * k - Vector2(5, 5) * k, Vector2(10, 10) * k), col, false, w * 0.9)
		"chat":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-14, 8) * k, c + Vector2(-14, -10) * k, c + Vector2(-10, -14) * k,
					c + Vector2(10, -14) * k, c + Vector2(14, -10) * k, c + Vector2(14, 6) * k, c + Vector2(10, 10) * k,
					c + Vector2(-5, 10) * k, c + Vector2(-14, 16) * k, c + Vector2(-14, 8) * k]), col, w, true)
		"user":
			ci.draw_arc(c + Vector2(0, -6) * k, 7.0 * k, 0.0, TAU, 24, col, w, true)
			ci.draw_arc(c + Vector2(0, 17) * k, 15.0 * k, PI * 1.12, PI * 1.88, 20, col, w, true)
		"send":
			ci.draw_line(c + Vector2(0, 13) * k, c + Vector2(0, -12) * k, col, w * 1.15, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-9, -3) * k, c + Vector2(0, -13) * k, c + Vector2(9, -3) * k]), col, w * 1.15, true)
		"stop":
			ci.draw_rect(Rect2(c - Vector2(9, 9) * k, Vector2(18, 18) * k), col, true)
		"paperclip":
			ci.draw_polyline(PackedVector2Array([c + Vector2(6, -8) * k, c + Vector2(6, 8) * k, c + Vector2(3, 13) * k,
					c + Vector2(-4, 13) * k, c + Vector2(-8, 8) * k, c + Vector2(-8, -10) * k, c + Vector2(-4, -15) * k,
					c + Vector2(3, -15) * k, c + Vector2(6, -11) * k]), col, w * 0.9, true)
		"menu":
			for y in [-9, 0, 9]:
				ci.draw_line(c + Vector2(-13, y) * k, c + Vector2(13, y) * k, col, w, true)
		"copy":
			ci.draw_rect(Rect2(c + Vector2(-6, -15) * k, Vector2(20, 22) * k), col, false, w * 0.85)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-10, -8) * k, c + Vector2(-14, -8) * k, c + Vector2(-14, 15) * k,
					c + Vector2(6, 15) * k, c + Vector2(6, 11) * k]), col, w * 0.85, true)
		"edit":
			ci.draw_line(c + Vector2(-12, 13) * k, c + Vector2(10, -9) * k, col, w * 1.4, true)
			ci.draw_line(c + Vector2(-13, 14) * k, c + Vector2(-9, 13) * k, col, w, true)
			ci.draw_line(c + Vector2(-13, 14) * k, c + Vector2(-12, 10) * k, col, w, true)
		"plus":
			ci.draw_line(c + Vector2(-12, 0) * k, c + Vector2(12, 0) * k, col, w, true)
			ci.draw_line(c + Vector2(0, -12) * k, c + Vector2(0, 12) * k, col, w, true)
		"pin", "pin_on":
			ci.draw_circle(c + Vector2(0, -7) * k, 7.0 * k, col) if kind == "pin_on" else ci.draw_arc(c + Vector2(0, -7) * k, 7.0 * k, 0.0, TAU, 20, col, w, true)
			ci.draw_line(c + Vector2(0, -1) * k, c + Vector2(0, 15) * k, col, w, true)
		"export":
			ci.draw_line(c + Vector2(0, 8) * k, c + Vector2(0, -15) * k, col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-8, -7) * k, c + Vector2(0, -16) * k, c + Vector2(8, -7) * k]), col, w, true)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-13, 2) * k, c + Vector2(-13, 16) * k, c + Vector2(13, 16) * k, c + Vector2(13, 2) * k]), col, w, true)
		"sliders":
			for i in 3:
				var y := (-9 + i * 9) * k
				ci.draw_line(c + Vector2(-14 * k, y), c + Vector2(14 * k, y), col, w * 0.8, true)
				ci.draw_circle(c + Vector2((-6 + i * 6) * k, y), 3.6 * k, col)
		"image":
			ci.draw_rect(Rect2(c + Vector2(-15, -12) * k, Vector2(30, 24) * k), col, false, w * 0.85)
			ci.draw_circle(c + Vector2(-6, -4) * k, 2.6 * k, col)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-15, 10) * k, c + Vector2(-5, 2) * k, c + Vector2(2, 8) * k, c + Vector2(8, 2) * k, c + Vector2(15, 9) * k]), col, w * 0.8, true)
		"bulb":
			ci.draw_arc(c + Vector2(0, -4) * k, 9.0 * k, 0.0, TAU, 24, col, w, true)
			ci.draw_line(c + Vector2(-4, 10) * k, c + Vector2(4, 10) * k, col, w, true)
			ci.draw_line(c + Vector2(-3, 15) * k, c + Vector2(3, 15) * k, col, w, true)
