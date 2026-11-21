extends RefCounted
## Géométrie des éléments du plan : bornes, tests de clic, polylignes « dessinées à la main » (mises en cache
## par élément, en coordonnées locales), flèches liées (droites, courbes, coudées) et pointes.

static var font: Font
const BOXES := ["rectangle", "diamond", "ellipse", "text", "image", "frame", "zone"]
const SHAPES := ["rectangle", "diamond", "ellipse"]
const LINEAR := ["arrow", "line", "freedraw"]
const BINDABLE := ["rectangle", "diamond", "ellipse", "text", "image", "frame", "zone"]
const GAP := 6.0
static var zoom := 1.0


## Hauteur (monde) du bandeau de titre d'un cadre : plus épais en vue éloignée pour rester lisible.
static func frame_bar(h: float) -> float:
	return minf(maxf(30.0, 26.0 / zoom), maxf(30.0, h * 0.45))


static func f() -> Font:
	return font if font != null else ThemeDB.fallback_font


static func rect(el: Dictionary) -> Rect2:
	return Rect2(float(el.x), float(el.y), float(el.w), float(el.h))


static func center(el: Dictionary) -> Vector2:
	return Vector2(float(el.x) + float(el.w) * 0.5, float(el.y) + float(el.h) * 0.5)


## Rectangle englobant dans le monde (rotation comprise).
static func aabb(el: Dictionary) -> Rect2:
	var r := rect(el)
	var a := float(el.get("angle", 0.0))
	if a == 0.0:
		return r
	var c := r.get_center()
	var hw := r.size.x * 0.5
	var hh := r.size.y * 0.5
	var ex := absf(cos(a)) * hw + absf(sin(a)) * hh
	var ey := absf(sin(a)) * hw + absf(cos(a)) * hh
	return Rect2(c.x - ex, c.y - ey, ex * 2.0, ey * 2.0)


static func unrot(el: Dictionary, p: Vector2) -> Vector2:
	var a := float(el.get("angle", 0.0))
	if a == 0.0:
		return p
	var c := center(el)
	return c + (p - c).rotated(-a)


static func rotp(el: Dictionary, p: Vector2) -> Vector2:
	var a := float(el.get("angle", 0.0))
	if a == 0.0:
		return p
	var c := center(el)
	return c + (p - c).rotated(a)


static func world_pts(el: Dictionary) -> PackedVector2Array:
	var o := Vector2(float(el.x), float(el.y))
	var out := PackedVector2Array()
	for p in el.get("points", []):
		out.append(o + Vector2(float(p[0]), float(p[1])))
	return out


static func set_world_pts(el: Dictionary, wp: PackedVector2Array) -> void:
	if wp.is_empty():
		return
	var mn := wp[0]
	var mx := wp[0]
	for p in wp:
		mn = Vector2(minf(mn.x, p.x), minf(mn.y, p.y))
		mx = Vector2(maxf(mx.x, p.x), maxf(mx.y, p.y))
	var pts: Array = []
	for p in wp:
		pts.append([p.x - mn.x, p.y - mn.y])
	el.x = mn.x
	el.y = mn.y
	el.w = mx.x - mn.x
	el.h = mx.y - mn.y
	el.points = pts


static func measure(text: String, fs: float) -> Vector2:
	var s := f().get_multiline_string_size(text if text != "" else " ", HORIZONTAL_ALIGNMENT_LEFT, -1, int(fs))
	return Vector2(maxf(s.x, 8.0), maxf(s.y, fs * 1.2))


static func fit_text(el: Dictionary) -> void:
	var s := measure(str(el.get("text", "")), float(el.get("fontSize", 20)))
	el.w = s.x
	el.h = s.y


static func ncol(s: String) -> Color:
	if s == "" or s == "transparent":
		return Color(0, 0, 0, 0)
	return Color(s)


static func has_fill(el: Dictionary) -> bool:
	return str(el.get("bg", "transparent")) != "transparent" and str(el.get("fillStyle", "aucun")) != "aucun"


# ------------------------------------------------------------------ contours

## Contour (polygone, coordonnées locales à l'élément) d'une forme.
static func outline(el: Dictionary) -> PackedVector2Array:
	var w := float(el.w)
	var h := float(el.h)
	var out := PackedVector2Array()
	match str(el.type):
		"diamond":
			out.append(Vector2(w * 0.5, 0))
			out.append(Vector2(w, h * 0.5))
			out.append(Vector2(w * 0.5, h))
			out.append(Vector2(0, h * 0.5))
		"ellipse":
			var n := 36
			for i in n:
				var a := TAU * i / n
				out.append(Vector2(w * 0.5 + cos(a) * w * 0.5, h * 0.5 + sin(a) * h * 0.5))
		_:
			var r := 0.0
			if str(el.get("roundness", "round")) == "round" and str(el.type) in ["rectangle", "image"]:
				r = minf(minf(w, h) * 0.2, 24.0)
			if r < 1.0:
				out.append(Vector2(0, 0))
				out.append(Vector2(w, 0))
				out.append(Vector2(w, h))
				out.append(Vector2(0, h))
			else:
				var corners := [Vector2(w - r, r), Vector2(w - r, h - r), Vector2(r, h - r), Vector2(r, r)]
				for ci in 4:
					for k in 6:
						var a2: float = -PI * 0.5 + (ci + float(k) / 5.0) * PI * 0.5
						out.append(corners[ci] + Vector2(cos(a2), sin(a2)) * r)
	return out


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


static func poly_dist(p: Vector2, poly: PackedVector2Array, closed: bool) -> float:
	var best := 1e9
	var n := poly.size()
	for i in (n if closed else n - 1):
		best = minf(best, seg_dist(p, poly[i], poly[(i + 1) % n]))
	if n == 1:
		best = p.distance_to(poly[0])
	return best


## Distance d'un point (monde) au tracé de l'élément ; 0 si dedans (formes remplies).
static func hit(el: Dictionary, wp: Vector2, tol: float) -> bool:
	var t := str(el.type)
	var p := unrot(el, wp)
	var o := Vector2(float(el.x), float(el.y))
	match t:
		"text", "image", "zone":
			return rect(el).grow(tol * 0.3).has_point(p)
		"frame":
			var r := rect(el)
			if Rect2(r.position, Vector2(r.size.x, frame_bar(r.size.y))).has_point(p):
				return true
			var inner := r.grow(-tol)
			return r.grow(tol * 0.3).has_point(p) and not inner.has_point(p)
		"rectangle", "diamond", "ellipse":
			var lp := p - o
			var poly := outline(el)
			if has_fill(el) and Geometry2D.is_point_in_polygon(lp, poly):
				return true
			return poly_dist(lp, poly, true) <= tol + float(el.get("strokeWidth", 2)) * 0.5
		_:
			var pts := world_pts(el)
			if pts.is_empty():
				return false
			return poly_dist(p, pts, false) <= tol + float(el.get("strokeWidth", 2)) * 0.5


## Point du bord d'une forme vu depuis le centre vers « toward » (monde), avec un petit écart.
static func edge_point(el: Dictionary, toward: Vector2, gap := GAP) -> Vector2:
	var c := center(el)
	var tl := unrot(el, toward)
	var dv := tl - c
	var hw := maxf(float(el.w) * 0.5, 0.5)
	var hh := maxf(float(el.h) * 0.5, 0.5)
	if dv.length() < 0.01:
		return rotp(el, c + Vector2(hw + gap, 0))
	var t: float
	match str(el.type):
		"diamond":
			t = 1.0 / (absf(dv.x) / hw + absf(dv.y) / hh)
		"ellipse":
			t = 1.0 / sqrt((dv.x / hw) * (dv.x / hw) + (dv.y / hh) * (dv.y / hh))
		_:
			t = minf(hw / maxf(absf(dv.x), 0.0001), hh / maxf(absf(dv.y), 0.0001))
	var q := c + dv * t + dv.normalized() * gap
	return rotp(el, q)


static func point_inside(el: Dictionary, wp: Vector2) -> bool:
	var p := unrot(el, wp)
	var r := rect(el)
	if not r.has_point(p):
		return false
	var c := r.get_center()
	var dv := (p - c)
	var hw := maxf(r.size.x * 0.5, 0.5)
	var hh := maxf(r.size.y * 0.5, 0.5)
	match str(el.type):
		"diamond":
			return absf(dv.x) / hw + absf(dv.y) / hh <= 1.0
		"ellipse":
			return (dv.x / hw) * (dv.x / hw) + (dv.y / hh) * (dv.y / hh) <= 1.0
	return true


# ------------------------------------------------------------------ flèches liées

static func mid_of(pts: PackedVector2Array) -> Vector2:
	if pts.size() < 2:
		return pts[0] if pts.size() == 1 else Vector2.ZERO
	var total := 0.0
	for i in pts.size() - 1:
		total += pts[i].distance_to(pts[i + 1])
	var acc := 0.0
	for i in pts.size() - 1:
		var l := pts[i].distance_to(pts[i + 1])
		if acc + l >= total * 0.5 and l > 0.0:
			return pts[i].lerp(pts[i + 1], (total * 0.5 - acc) / l)
		acc += l
	return pts[pts.size() - 1]


static func bez(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return p0 * u * u * u + p1 * 3.0 * u * u * t + p2 * 3.0 * u * t * t + p3 * t * t * t


## Recalcule la géométrie d'une flèche/ligne d'après ses liaisons (start/end = id d'éléments) et son type de tracé.
static func refresh_arrow(scene, a: Dictionary) -> void:
	var wp := world_pts(a)
	if wp.size() < 2:
		return
	var s_el: Dictionary = scene.get_el(str(a.get("start", ""))) if str(a.get("start", "")) != "" else {}
	var e_el: Dictionary = scene.get_el(str(a.get("end", ""))) if str(a.get("end", "")) != "" else {}
	if s_el.is_empty():
		a["start"] = ""
	if e_el.is_empty():
		a["end"] = ""
	var kind := str(a.get("arrowType", "sharp")) if str(a.type) == "arrow" else "sharp"
	var p0 := wp[0]
	var p1 := wp[wp.size() - 1]
	var mids := PackedVector2Array()
	if wp.size() > 2 and kind == "sharp":
		mids = wp.slice(1, wp.size() - 1)
	if kind == "elbow":
		var c0 := center(s_el) if not s_el.is_empty() else p0
		var c1 := center(e_el) if not e_el.is_empty() else p1
		var horiz := absf(c1.x - c0.x) >= absf(c1.y - c0.y)
		if not s_el.is_empty():
			p0 = edge_point(s_el, Vector2(c1.x, c0.y) if horiz else Vector2(c0.x, c1.y))
		if not e_el.is_empty():
			p1 = edge_point(e_el, Vector2(c0.x, c1.y) if horiz else Vector2(c1.x, c0.y))
		if horiz:
			var mx := (p0.x + p1.x) * 0.5
			set_world_pts(a, PackedVector2Array([p0, Vector2(mx, p0.y), Vector2(mx, p1.y), p1]))
		else:
			var my := (p0.y + p1.y) * 0.5
			set_world_pts(a, PackedVector2Array([p0, Vector2(p0.x, my), Vector2(p1.x, my), p1]))
		return
	var aim1 := mids[0] if not mids.is_empty() else (center(e_el) if not e_el.is_empty() else p1)
	var aim0 := mids[mids.size() - 1] if not mids.is_empty() else (center(s_el) if not s_el.is_empty() else p0)
	if not s_el.is_empty():
		p0 = edge_point(s_el, aim1 if not mids.is_empty() else (center(e_el) if not e_el.is_empty() else p1))
	if not e_el.is_empty():
		p1 = edge_point(e_el, aim0 if not mids.is_empty() else (center(s_el) if not s_el.is_empty() else p0))
	if kind == "round":
		var d := p1 - p0
		var off := clampf(d.length() * 0.45, 30.0, 170.0)
		var c1p: Vector2
		var c2p: Vector2
		if absf(d.x) >= absf(d.y):
			c1p = p0 + Vector2(off * signf(d.x if d.x != 0.0 else 1.0), 0)
			c2p = p1 - Vector2(off * signf(d.x if d.x != 0.0 else 1.0), 0)
		else:
			c1p = p0 + Vector2(0, off * signf(d.y if d.y != 0.0 else 1.0))
			c2p = p1 - Vector2(0, off * signf(d.y if d.y != 0.0 else 1.0))
		var out := PackedVector2Array()
		for i in 25:
			out.append(bez(p0, c1p, c2p, p1, i / 24.0))
		set_world_pts(a, out)
		return
	var res := PackedVector2Array([p0])
	res.append_array(mids)
	res.append(p1)
	set_world_pts(a, res)


## Rectangle (monde) de l'étiquette d'une flèche ; vide si elle n'en a pas.
static func label_rect(el: Dictionary, txt := "") -> Rect2:
	if txt == "":
		txt = str(el.get("label", ""))
	if txt == "":
		return Rect2()
	var pts := world_pts(el)
	if pts.is_empty():
		return Rect2()
	var c := mid_of(pts)
	var sz := measure(txt, float(el.get("fontSize", 16)) if str(el.get("link", "")) == "" else 13.0)
	return Rect2(c - (sz + Vector2(14, 8)) * 0.5, sz + Vector2(14, 8))


# ------------------------------------------------------------------ polylignes tremblées (cache)

static func _noise_poly(poly: PackedVector2Array, rng: RandomNumberGenerator, amp: float, closed: bool, step: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var n := poly.size()
	for i in (n if closed else n - 1):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var steps := maxi(1, int(a.distance_to(b) / step))
		for k in steps:
			pts.append(a.lerp(b, float(k) / steps))
	if not closed:
		pts.append(poly[n - 1])
	var out := PackedVector2Array()
	var prev := Vector2.ZERO
	for p in pts:
		prev = prev * 0.45 + Vector2(rng.randf_range(-amp, amp), rng.randf_range(-amp, amp))
		out.append(p + prev)
	if closed and out.size() > 0:
		out.append(out[0].lerp(out[1] if out.size() > 1 else out[0], 0.4))
	return out


static func dash(pts: PackedVector2Array, dl: float, gl: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var on := true
	var left := dl
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var l := a.distance_to(b)
		var pos := 0.0
		while pos < l - 0.001:
			var take := minf(left, l - pos)
			if on:
				out.append(a.lerp(b, pos / l))
				out.append(a.lerp(b, (pos + take) / l))
			pos += take
			left -= take
			if left <= 0.0001:
				on = not on
				left = dl if on else gl
	return out


static func _clip_line(poly: PackedVector2Array, p0: Vector2, d: Vector2, orient: float) -> Vector2:
	var t0 := -1e9
	var t1 := 1e9
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var e := poly[(i + 1) % n] - a
		var f0 := e.cross(p0 - a) * orient
		var fd := e.cross(d) * orient
		if absf(fd) < 1e-9:
			if f0 < 0.0:
				return Vector2(1, 0)
			continue
		var t := -f0 / fd
		if fd > 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
	return Vector2(t0, t1)


static func hatch(poly: PackedVector2Array, gap: float, dir: Vector2, rng: RandomNumberGenerator, rough: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var area := 0.0
	for i in poly.size():
		area += poly[i].cross(poly[(i + 1) % poly.size()])
	var orient := 1.0 if area >= 0.0 else -1.0
	var nrm := Vector2(-dir.y, dir.x)
	var lo := 1e9
	var hi := -1e9
	for p in poly:
		var s := p.dot(nrm)
		lo = minf(lo, s)
		hi = maxf(hi, s)
	var s2 := lo + gap * 0.5
	var guard := 0
	while s2 < hi and guard < 400:
		guard += 1
		var p0 := nrm * s2
		var tt := _clip_line(poly, p0, dir, orient)
		if tt.x < tt.y:
			var j := rng.randf_range(-rough, rough) * 1.5
			out.append(p0 + dir * tt.x + dir * j)
			out.append(p0 + dir * tt.y - dir * j)
		s2 += gap
	return out


static func _head(kind: String, tip: Vector2, dir: Vector2, sw: float, lines: Array, fills: Array) -> void:
	var l := 11.0 + sw * 3.0
	var perp := Vector2(-dir.y, dir.x)
	match kind:
		"arrow":
			lines.append(PackedVector2Array([tip - dir * l + perp * l * 0.5, tip, tip - dir * l - perp * l * 0.5]))
		"triangle":
			fills.append(PackedVector2Array([tip, tip - dir * l + perp * l * 0.45, tip - dir * l - perp * l * 0.45]))
		"bar":
			lines.append(PackedVector2Array([tip + perp * l * 0.5, tip - perp * l * 0.5]))
		"dot":
			var c := tip - dir * l * 0.35
			var poly := PackedVector2Array()
			for i in 14:
				poly.append(c + Vector2(cos(TAU * i / 14.0), sin(TAU * i / 14.0)) * l * 0.35)
			fills.append(poly)


## Construit (ou renvoie) le cache de dessin de l'élément : traits, hachures, remplissages, pointes.
static func build(scene, el: Dictionary, lstyle: Dictionary = {}) -> Dictionary:
	var id := str(el.id)
	var sig := str(lstyle.get("dashed", ""))
	var c: Dictionary = scene.cache.get(id, {})
	if not c.is_empty() and c.sig == sig:
		return c
	c = {"sig": sig, "lines": [], "segs": PackedVector2Array(), "hatch": PackedVector2Array(), "fill": PackedVector2Array(), "fills": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = id.hash()
	var rough := float(el.get("roughness", 1))
	var sw := float(el.get("strokeWidth", 2))
	var style := str(el.get("strokeStyle", "plein"))
	if lstyle.has("dashed"):
		style = "tirets" if lstyle.dashed else "plein"
	var t := str(el.type)
	var lines: Array = []
	if t in SHAPES:
		var base := outline(el)
		var amp := rough * clampf(minf(float(el.w), float(el.h)) * 0.012, 0.5, 2.0)
		if has_fill(el):
			var fs := str(el.fillStyle)
			if fs == "plein":
				c.fill = base
			else:
				var gap := 7.0 + sw * 3.0
				var hs := PackedVector2Array()
				hs.append_array(hatch(base, gap, Vector2(1, -1).normalized(), rng, rough))
				if fs == "croise":
					hs.append_array(hatch(base, gap, Vector2(1, 1).normalized(), rng, rough))
				c.hatch = hs
		if rough <= 0.0:
			var closed := base.duplicate()
			closed.append(base[0])
			lines.append(closed)
		else:
			for pass_i in 2:
				lines.append(_noise_poly(base, rng, amp + 0.2, true, 38.0))
	elif t == "frame":
		var w := float(el.w)
		var h := float(el.h)
		lines.append(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h), Vector2(0, 0)]))
	elif t == "image":
		var w2 := float(el.w)
		var h2 := float(el.h)
		lines.append(PackedVector2Array([Vector2(0, 0), Vector2(w2, 0), Vector2(w2, h2), Vector2(0, h2), Vector2(0, 0)]))
	elif t in LINEAR:
		var pts: PackedVector2Array = PackedVector2Array()
		for p in el.get("points", []):
			pts.append(Vector2(float(p[0]), float(p[1])))
		if pts.size() >= 2:
			if t == "freedraw":
				lines.append(_smooth(pts))
			elif rough <= 0.0 or str(el.get("arrowType", "")) in ["round", "elbow"] and rough <= 1.0 or pts.size() > 12:
				lines.append(pts)
			else:
				for pass_i in 2:
					lines.append(_noise_poly(pts, rng, rough * 0.9 + 0.2, false, 45.0))
			if t == "arrow":
				var n := pts.size()
				var hl: Array = []
				var hf: Array = []
				var eh := str(el.get("endHead", "arrow"))
				var sh := str(el.get("startHead", "none"))
				if eh != "none":
					var d1 := (pts[n - 1] - pts[maxi(0, n - 2)]).normalized()
					_head(eh, pts[n - 1], d1, sw, hl, hf)
				if sh != "none":
					var d0 := (pts[0] - pts[1]).normalized()
					_head(sh, pts[0], d0, sw, hl, hf)
				for h3 in hl:
					lines.append(h3)
				c.fills = hf
		elif pts.size() == 1:
			c.fills = [PackedVector2Array([pts[0] + Vector2(-sw, -sw), pts[0] + Vector2(sw, -sw), pts[0] + Vector2(sw, sw), pts[0] + Vector2(-sw, sw)])]
	if style != "plein":
		var segs := PackedVector2Array()
		var dl := sw * 4.0 + 6.0 if style == "tirets" else maxf(sw * 0.4, 0.8)
		var gl := sw * 3.0 + 4.0 if style == "tirets" else sw * 2.6 + 3.0
		for ln in lines:
			segs.append_array(dash(ln, dl, gl))
		c.segs = segs
		c.lines = []
	else:
		c.lines = lines
	scene.cache[id] = c
	return c


## Lissage léger du crayon (Chaikin, un passage).
static func _smooth(p: PackedVector2Array) -> PackedVector2Array:
	if p.size() < 3 or p.size() > 600:
		return p
	var out := PackedVector2Array([p[0]])
	for i in p.size() - 1:
		out.append(p[i].lerp(p[i + 1], 0.25))
		out.append(p[i].lerp(p[i + 1], 0.75))
	out.append(p[p.size() - 1])
	return out
