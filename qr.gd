extends RefCounted
## Encodeur QR code minimal (mode octets, correction d'erreur L, versions 1 à 10 : jusqu'à 271 octets).
## QR.encode("texte") -> {"size": n, "modules": PackedByteArray (1 = noir)} ; QR.texture(texte, échelle) -> ImageTexture.

# par version : [octets de correction par bloc, nb blocs groupe 1, données groupe 1, nb blocs groupe 2, données groupe 2]
const EC_L := [[], [7, 1, 19, 0, 0], [10, 1, 34, 0, 0], [15, 1, 55, 0, 0], [20, 1, 80, 0, 0], [26, 1, 108, 0, 0],
		[18, 2, 68, 0, 0], [20, 2, 78, 0, 0], [24, 2, 97, 0, 0], [30, 2, 116, 0, 0], [18, 2, 68, 2, 69]]
const ALIGN := [[], [], [6, 18], [6, 22], [6, 26], [6, 30], [6, 34], [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50]]

static var _exp := PackedInt32Array()
static var _log := PackedInt32Array()


static func _gf_init() -> void:
	if _exp.size() > 0:
		return
	_exp.resize(512)
	_log.resize(256)
	var x := 1
	for i in 255:
		_exp[i] = x
		_log[x] = i
		x <<= 1
		if x & 0x100:
			x ^= 0x11d
	for i in range(255, 512):
		_exp[i] = _exp[i - 255]


static func _mul(a: int, b: int) -> int:
	return 0 if a == 0 or b == 0 else _exp[_log[a] + _log[b]]


static func _rs(data: PackedInt32Array, ec: int) -> PackedInt32Array:
	var gen := PackedInt32Array([1])
	for i in ec:
		var ng := PackedInt32Array()
		ng.resize(gen.size() + 1)
		for j in gen.size():
			ng[j] ^= gen[j]
			ng[j + 1] ^= _mul(gen[j], _exp[i])
		gen = ng
	var res := PackedInt32Array()
	res.resize(ec)
	for b in data:
		var f: int = b ^ res[0]
		res.remove_at(0)
		res.append(0)
		if f != 0:
			for j in ec:
				res[j] ^= _mul(gen[j + 1], f)
	return res


static func _mask_bit(mask: int, i: int, j: int) -> bool:  # i = ligne, j = colonne
	match mask:
		0: return (i + j) % 2 == 0
		1: return i % 2 == 0
		2: return j % 3 == 0
		3: return (i + j) % 3 == 0
		4: return (i / 2 + j / 3) % 2 == 0
		5: return (i * j) % 2 + (i * j) % 3 == 0
		6: return ((i * j) % 2 + (i * j) % 3) % 2 == 0
	return ((i + j) % 2 + (i * j) % 3) % 2 == 0


static func encode(text: String, force_mask := -1) -> Dictionary:
	_gf_init()
	var bytes := text.to_utf8_buffer()
	var ver := 0
	for v in range(1, 11):
		var e: Array = EC_L[v]
		var cap: int = e[1] * e[2] + e[3] * e[4]
		if 4 + (8 if v < 10 else 16) + bytes.size() * 8 <= cap * 8:
			ver = v
			break
	if ver == 0:
		return {}
	var e: Array = EC_L[ver]
	var cap: int = e[1] * e[2] + e[3] * e[4]
	# --- bits de données
	var bits: Array = []
	var put := func(val: int, n: int) -> void:
		for i in range(n - 1, -1, -1):
			bits.append((val >> i) & 1)
	put.call(4, 4)
	put.call(bytes.size(), 8 if ver < 10 else 16)
	for b in bytes:
		put.call(b, 8)
	put.call(0, mini(4, cap * 8 - bits.size()))
	while bits.size() % 8 != 0:
		bits.append(0)
	var cw := PackedInt32Array()
	for i in range(0, bits.size(), 8):
		var v := 0
		for k in 8:
			v = (v << 1) | bits[i + k]
		cw.append(v)
	var pad := [0xEC, 0x11]
	var pi := 0
	while cw.size() < cap:
		cw.append(pad[pi % 2])
		pi += 1
	# --- blocs + correction d'erreur + entrelacement
	var blocks: Array = []
	var ecs: Array = []
	var pos := 0
	for g in 2:
		var cnt: int = e[1 + g * 2]
		var len: int = e[2 + g * 2]
		for k in cnt:
			var blk := cw.slice(pos, pos + len)
			pos += len
			blocks.append(blk)
			ecs.append(_rs(blk, e[0]))
	var final := PackedInt32Array()
	var maxlen := 0
	for b in blocks:
		maxlen = maxi(maxlen, b.size())
	for i in maxlen:
		for b in blocks:
			if i < b.size():
				final.append(b[i])
	for i in e[0]:
		for b in ecs:
			final.append(b[i])
	var dbits: Array = []
	for c in final:
		for k in range(7, -1, -1):
			dbits.append((c >> k) & 1)
	# --- matrice
	var n := 17 + 4 * ver
	var m := PackedByteArray()
	m.resize(n * n)
	var fn := PackedByteArray()
	fn.resize(n * n)
	var setf := func(x: int, y: int, v: int) -> void:
		if x >= 0 and y >= 0 and x < n and y < n:
			m[y * n + x] = v
			fn[y * n + x] = 1
	for c in [[0, 0], [n - 7, 0], [0, n - 7]]:
		for dy in range(-1, 8):
			for dx in range(-1, 8):
				var dark := dx >= 0 and dx <= 6 and dy >= 0 and dy <= 6 and (dx == 0 or dx == 6 or dy == 0 or dy == 6 or (dx >= 2 and dx <= 4 and dy >= 2 and dy <= 4))
				setf.call(c[0] + dx, c[1] + dy, 1 if dark else 0)
	for i in 9:  # zones du format (réservées)
		setf.call(8, i, 0)
		setf.call(i, 8, 0)
	for i in 8:
		setf.call(n - 1 - i, 8, 0)
		setf.call(8, n - 1 - i, 0)
	for i in range(8, n - 8):
		setf.call(i, 6, 1 if i % 2 == 0 else 0)
		setf.call(6, i, 1 if i % 2 == 0 else 0)
	var al: Array = ALIGN[ver]
	for cy in al:
		for cx in al:
			if (cx == 6 and cy == 6) or (cx == 6 and cy == al[-1]) or (cx == al[-1] and cy == 6):
				continue
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					setf.call(cx + dx, cy + dy, 0 if maxi(absi(dx), absi(dy)) == 1 else 1)
	setf.call(8, n - 8, 1)
	if ver >= 7:
		var rem := ver
		for i in 12:
			rem = (rem << 1) ^ ((rem >> 11) * 0x1F25)
		var vb := (ver << 12) | rem
		for i in 18:
			var bit := (vb >> i) & 1
			setf.call(n - 11 + i % 3, i / 3, bit)
			setf.call(i / 3, n - 11 + i % 3, bit)
	# --- placement des données en zigzag
	var idx := 0
	var up := true
	var x := n - 1
	while x > 0:
		if x == 6:
			x -= 1
		for i in n:
			var y := (n - 1 - i) if up else i
			for dx in 2:
				var xx := x - dx
				if fn[y * n + xx] == 0:
					m[y * n + xx] = dbits[idx] if idx < dbits.size() else 0
					idx += 1
		up = not up
		x -= 2
	# --- masque (le meilleur, ou imposé)
	var best := PackedByteArray()
	var best_pen := 1 << 30
	var best_mask := 0
	for mask in 8:
		if force_mask >= 0 and mask != force_mask:
			continue
		var t := m.duplicate()
		for y in n:
			for xx in n:
				if fn[y * n + xx] == 0 and _mask_bit(mask, y, xx):
					t[y * n + xx] ^= 1
		var data := (1 << 3) | mask  # niveau L = 01
		var rem := data
		for i in 10:
			rem = (rem << 1) ^ ((rem >> 9) * 0x537)
		var fb := ((data << 10) | rem) ^ 0x5412
		var sf := func(xx: int, yy: int, i: int) -> void:
			t[yy * n + xx] = (fb >> i) & 1
		for i in 6:
			sf.call(8, i, i)
		sf.call(8, 7, 6)
		sf.call(8, 8, 7)
		sf.call(7, 8, 8)
		for i in range(9, 15):
			sf.call(14 - i, 8, i)
		for i in 8:
			sf.call(n - 1 - i, 8, i)
		for i in range(8, 15):
			sf.call(8, n - 15 + i, i)
		var pen := _penalty(t, n) if force_mask < 0 else 0
		if pen < best_pen:
			best_pen = pen
			best = t
			best_mask = mask
	return {"size": n, "modules": best, "version": ver, "mask": best_mask}


static func _penalty(t: PackedByteArray, n: int) -> int:
	var pen := 0
	var dark := 0
	for y in n:
		var run := 1
		for x in n:
			dark += t[y * n + x]
			if x > 0 and t[y * n + x] == t[y * n + x - 1]:
				run += 1
				if run == 5:
					pen += 3
				elif run > 5:
					pen += 1
			else:
				run = 1
	for x in n:
		var run := 1
		for y in range(1, n):
			if t[y * n + x] == t[(y - 1) * n + x]:
				run += 1
				if run == 5:
					pen += 3
				elif run > 5:
					pen += 1
			else:
				run = 1
	for y in n - 1:
		for x in n - 1:
			var v := t[y * n + x]
			if v == t[y * n + x + 1] and v == t[(y + 1) * n + x] and v == t[(y + 1) * n + x + 1]:
				pen += 3
	var pat1 := [1, 0, 1, 1, 1, 0, 1, 0, 0, 0, 0]
	var pat2 := [0, 0, 0, 0, 1, 0, 1, 1, 1, 0, 1]
	for y in n:
		for x in n - 10:
			var a := true
			var b := true
			for k in 11:
				var v := t[y * n + x + k]
				a = a and v == pat1[k]
				b = b and v == pat2[k]
			if a or b:
				pen += 40
	for x in n:
		for y in n - 10:
			var a := true
			var b := true
			for k in 11:
				var v := t[(y + k) * n + x]
				a = a and v == pat1[k]
				b = b and v == pat2[k]
			if a or b:
				pen += 40
	pen += (absi(dark * 20 - n * n * 10) + n * n - 1) / (n * n) * 10 - 10 if absi(dark * 20 - n * n * 10) > 0 else 0
	return pen


## Texture prête à afficher : modules noirs sur fond blanc, bordure (zone calme) de 3 modules.
static func texture(text: String, scale := 6) -> ImageTexture:
	var q := encode(text)
	if q.is_empty():
		return null
	var n: int = q.size
	var b := 3
	var im := Image.create((n + 2 * b) * scale, (n + 2 * b) * scale, false, Image.FORMAT_RGB8)
	im.fill(Color.WHITE)
	var mods: PackedByteArray = q.modules
	for y in n:
		for x in n:
			if mods[y * n + x] == 1:
				im.fill_rect(Rect2i((x + b) * scale, (y + b) * scale, scale, scale), Color.BLACK)
	return ImageTexture.create_from_image(im)
