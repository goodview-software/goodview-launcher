extends Window
## HUD pixel art (PC), même principe que Pocket Chat : bandeau en haut à droite de l'écran avec la fusée (ouvre le launcher)
## et les apps installées (clic = lancer), dépliable en liste. Sans bordure, transparent, toujours au-dessus, sans prise de focus.
const KPx := preload("res://kit/ui/px.gd")
const SPRITE := [
	".......kk.......", "......kwwk......", ".....kwwwwk.....", ".....kwwwwk.....",
	"....kwwbbwwk....", "....kwbbbbwk....", "....kwbbbbwk....", "....kwwbbwwk....",
	"....kwwwwwwk....", "...krkwwwwkrk...", "..krrkwwwwkrrk..", "..krrkkkkkkrrk..",
	"...kk.kyyk.kk...", "......kyyk......", ".......yy.......", ".......y........",
]
const PAL := {"k": Color("1b1b2f"), "w": Color("f2f2f7"), "b": Color("4aa3ff"), "r": Color("e5484d"), "y": Color("ffc83d")}
const ACC := Color("6c6cff")
const MARGIN := 12
const BOX := 44
const ROW_H := 46
const PANEL_W := 280
const MAX_STRIP := 5

const SLOT_ID := "goodview-launcher"
const SLOT_ORDER := ["pocket-chat", "pocket-speaker", "goodview-launcher"]  # de droite à gauche
var _slot_t := 0.0


## Décalage (px) à gauche des HUD des autres apps Goodview actives ; publie aussi notre largeur (battement de cœur).
func _slot_offset(w: int) -> int:
	_slot_t = 0.0
	var now := Time.get_unix_time_from_system()
	var dir := OS.get_environment("HOME") + "/.config/goodview/hud"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/" + SLOT_ID + ".txt", FileAccess.WRITE)
	if f != null:
		f.store_string("%d %d" % [int(now), w])
		f.close()
	var off := 0
	for id in SLOT_ORDER:
		if id == SLOT_ID:
			break
		var p: String = dir + "/" + id + ".txt"
		if FileAccess.file_exists(p):
			var parts := FileAccess.get_file_as_string(p).split(" ")
			if parts.size() == 2 and now - float(parts[0]) < 5.0:
				off += int(parts[1]) + 6
	return off


func _exit_tree() -> void:
	DirAccess.remove_absolute(OS.get_environment("HOME") + "/.config/goodview/hud/" + SLOT_ID + ".txt")

var ctx: Object
var font: Font
var cv: Control
var expanded := false
var hits: Array = []   # [Rect2, String] : "toggle", "open" ou nom d'app
var hover := -1
var entries: Array = []  # [{name, icon, update}]
var _sig := ""


func _ready() -> void:
	title = "Goodview HUD"
	borderless = true
	always_on_top = true
	transparent = true
	transparent_bg = true
	unfocusable = true
	transient = false
	force_native = true
	exclusive = false
	wrap_controls = false
	cv = Control.new()
	cv.set_anchors_preset(Control.PRESET_FULL_RECT)
	cv.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cv.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cv.draw.connect(_draw_ui)
	cv.gui_input.connect(_input_ui)
	cv.mouse_exited.connect(func(): hover = -1)
	add_child(cv)
	var t := Timer.new()
	t.wait_time = 1.5
	t.autostart = true
	t.timeout.connect(func():
		_collect()
		_slot_t += 1.5
		if _slot_t > 1.5:
			_relayout())
	add_child(t)
	_collect()
	visible = true


func _collect() -> void:
	if ctx == null:
		return
	var l: Array = []
	var upd: Array = ctx.updates().map(func(a): return str(a.name))
	var run: Dictionary = ctx.installer.running()
	for n in ctx.store.installed:
		var a: Dictionary = ctx.catalog.find(n)
		l.append({"name": str(n), "icon": a.get("icon") if not a.is_empty() else null, "update": str(n) in upd,
				"running": run.has(str(n)), "title": str(run.get(str(n), ""))})
	for n in run:
		if not ctx.store.installed.has(n):  # ouverte hors launcher (sources, « dev »)
			l.append({"name": str(n), "icon": null, "update": false, "running": true, "title": str(run[n])})
	entries = l
	var sig := str(l.map(func(e): return "%s%s%s%s" % [e.name, e.update, e.icon != null, e.running])) + str(expanded) + str(ctx.has_updates())
	if sig != _sig:
		_sig = sig
		_relayout()
	cv.queue_redraw()


func _strip_w() -> int:
	var n := mini(entries.size(), MAX_STRIP) + 1
	var extra := 1 if entries.size() > MAX_STRIP else 0
	return 16 + n * (BOX + 6) + extra * 30 + 34


func _relayout() -> void:
	var w := maxi(PANEL_W if expanded else 0, _strip_w())
	var h := 60
	if expanded:
		h += 8 + 14 + entries.size() * ROW_H + ROW_H
	var r := DisplayServer.screen_get_usable_rect(DisplayServer.get_primary_screen())
	size = Vector2i(w, h)
	position = Vector2i(r.end.x - w - MARGIN - _slot_offset(w), r.position.y + MARGIN)
	cv.queue_redraw()


# ------------------------------------------------------------------ Dessin

func _txt(p: Vector2, s: String, sz: int, col: Color, w := -1.0) -> void:
	font.draw_string(cv, p, s, HORIZONTAL_ALIGNMENT_LEFT, w, sz, col)


func _rocket(r: Rect2) -> void:
	KPx.panel(cv, r, Color("2a2a45"), Color("0b0e12"), false, 1)
	var k := floorf((r.size.x - 8.0) / 16.0)
	var o := r.get_center() - Vector2(8, 8) * k
	for y in SPRITE.size():
		var row: String = SPRITE[y]
		for x in row.length():
			if row[x] != ".":
				cv.draw_rect(Rect2((o + Vector2(x, y) * k).round(), Vector2(k, k)), PAL[row[x]])


func _app(r: Rect2, e: Dictionary) -> void:
	KPx.panel(cv, r, Color("232a34"), Color("0b0e12"), false, 1)
	if e.icon != null:
		cv.draw_texture_rect(e.icon, r.grow(-5), false)
	else:
		_txt(r.position + Vector2(r.size.x * 0.3, r.size.y * 0.68), str(e.name).left(1).to_upper(), 20, Color("e8ecf1"))
	if e.running:
		cv.draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 5), Color("0b0e12"))
		cv.draw_rect(Rect2(r.position.x + 1, r.end.y, r.size.x - 2, 3), Color("4de1b4"))
	if e.update:
		cv.draw_rect(Rect2(r.end.x - 8, r.position.y - 4, 12, 12).grow(2), Color.BLACK)
		cv.draw_rect(Rect2(r.end.x - 8, r.position.y - 4, 12, 12), PAL["y"])


func _draw_ui() -> void:
	hits.clear()
	if font == null:
		return
	var W := float(size.x)
	KPx.panel(cv, Rect2(0, 0, W, 56), Color("171b22"), Color("0b0e12"), true, 2)
	var x := 12.0
	var rr := Rect2(x, 6, BOX - 4, BOX - 4)
	_rocket(rr)
	if ctx.updater.available():
		cv.draw_rect(Rect2(rr.end.x - 6, rr.position.y - 4, 12, 12), PAL["y"])
	hits.append([Rect2(x, 4, BOX, 48), "open"])
	x += BOX + 6
	var shown := mini(entries.size(), MAX_STRIP)
	for i in shown:
		_app(Rect2(x, 6, BOX - 4, BOX - 4), entries[i])
		hits.append([Rect2(x, 4, BOX, 48), str(entries[i].name)])
		x += BOX + 6
	if entries.size() > shown:
		_txt(Vector2(x + 2, 34), "+%d" % (entries.size() - shown), 16, Color("8892a0"))
	var tg := Rect2(W - 34, 8, 26, 40)
	cv.draw_rect(tg, Color("232a34") if hover != hits.size() else Color("2f3947"))
	var cc := tg.get_center()
	var dir := -1.0 if expanded else 1.0
	for k in 4:
		cv.draw_rect(Rect2(cc.x - 8 + k * 2, cc.y - 4 * dir + k * 2 * dir - 1, 16 - k * 4, 3), ACC)
	hits.append([Rect2(W - 38, 0, 38, 56), "toggle"])
	if expanded:
		var y := 64.0
		var ph := 14.0 + entries.size() * ROW_H + ROW_H
		KPx.panel(cv, Rect2(0, y, W, ph), Color("171b22"), Color("0b0e12"), true, 2)
		var ry := y + 10.0
		for e in entries:
			var row := Rect2(8, ry, W - 16, ROW_H - 2)
			if hover == hits.size():
				cv.draw_rect(row, Color("232a34"))
			_app(Rect2(14, ry + 3, 38, 38), e)
			_txt(Vector2(62, ry + 28), str(e.name), 17, Color("e8ecf1"), W - 62 - 50)
			if e.running:
				_txt(Vector2(W - 74, ry + 28), "OUVERT", 14, Color("4de1b4"))
			elif e.update:
				_txt(Vector2(W - 54, ry + 28), "MAJ", 14, PAL["y"])
			hits.append([row, str(e.name)])
			ry += ROW_H
		var orr := Rect2(8, ry + 2, W - 16, ROW_H - 6)
		cv.draw_rect(orr, ACC if hover == hits.size() else Color("4a4ab8"))
		_txt(Vector2(orr.position.x + 14, orr.position.y + 26), "OUVRIR LE LAUNCHER", 15, Color.WHITE)
		hits.append([orr, "open"])


# ------------------------------------------------------------------ Entrées souris

func _input_ui(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		var h := -1
		for i in hits.size():
			if (hits[i][0] as Rect2).has_point(e.position):
				h = i
				break
		if h != hover:
			hover = h
			cv.queue_redraw()
	elif e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
		for hh in hits:
			if (hh[0] as Rect2).has_point(e.position):
				_act(str(hh[1]))
				return


func _act(id: String) -> void:
	match id:
		"toggle":
			expanded = not expanded
			_relayout()
		"open":
			var w := get_tree().root
			w.show()
			if w.mode == Window.MODE_MINIMIZED:
				w.mode = Window.MODE_WINDOWED
			w.grab_focus()
		_:
			for e in entries:
				if e.name == id and e.running:
					ctx.installer.focus(str(e.title))
					return
			ctx.installer.launch(id)
