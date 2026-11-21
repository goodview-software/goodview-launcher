extends Control
## Goodview Launcher : catalogue des apps de l'organisation GitHub, page de présentation par app,
## installation de la dernière release (asset Linux) dans user://apps/<repo>/, mise à jour et lancement.
##
## Convention par repo (tous optionnels) :
##   icon.png | icon.svg   à la racine : icône affichée dans le catalogue
##   app.json              {"tagline": "...", "description": "...", "screenshots": ["docs/a.png", ...]}

const ORGS := ["goodview-software"]
const API := "https://api.github.com"
const RAW := "https://raw.githubusercontent.com"
const APPS_DIR := "user://apps"
const VERSION: String = preload("res://version.gd").VERSION
const UPDATE_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest/download/version.json"
const RELEASES_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest"
const STATE_FILE := "user://installed.json"
const CFG_FILE := "user://settings.cfg"
const EXCLUDED := [".github", "goodview-launcher"]

const C_BG := Color("0e1116")
const C_CARD := Color("171b22")
const C_CARD_HI := Color("1e242d")
const C_TEXT := Color("e8ecf1")
const C_DIM := Color("8892a0")
const C_OK := Color("4de1b4")

var token := ""
var installed := {}  # repo -> {tag, exe}
var apps: Array = []  # {name, org, repo, release, asset, icon, manifest}
var busy := false
var cur_app: Dictionary = {}

var col: VBoxContainer
var page_list: VBoxContainer
var list_box: VBoxContainer
var page_detail: VBoxContainer
var status: Label
var progress: ProgressBar
var token_edit: LineEdit
var pseudo := ""
var avatar_tex: Texture2D
var chip_avatar: Avatar
var chip_name: Label
var prof_avatar: Avatar
var pseudo_edit: LineEdit
var page_profile: VBoxContainer
var file_dlg: FileDialog
var upd_lbl: Label
var upd_btn: Button
var upd_info := {}
var upd_http: HTTPRequest


# ------------------------------------------------------------------ Widgets

class AppIcon extends Control:
	var tex: Texture2D
	var letter := "?"
	var tint := Color("4de1b4")

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("232a34") if tex != null else tint.darkened(0.35)
		sb.set_corner_radius_all(int(size.x * 0.22))
		sb.anti_aliasing_size = 1.2
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		if tex != null:
			var m := size.x * 0.12
			draw_texture_rect(tex, Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0), false)
		else:
			var f := ThemeDB.fallback_font
			var fs := int(size.x * 0.5)
			draw_string(f, Vector2(0, size.y / 2.0 + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color.WHITE)


class Avatar extends Control:
	var tex: Texture2D:
		set(v):
			tex = v
			queue_redraw()
	var letter := "?":
		set(v):
			letter = v
			queue_redraw()
	var badge := false:
		set(v):
			badge = v
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if tex != null:
			draw_texture_rect(tex, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
		else:
			draw_circle(c, r, Color("2fb88f"))
			var fs := int(r * 1.1)
			draw_string(ThemeDB.fallback_font, Vector2(0, c.y + fs * 0.36), letter, HORIZONTAL_ALIGNMENT_CENTER, size.x, fs, Color.WHITE)
		draw_arc(c, r - 0.8, 0.0, TAU, 48, Color(1, 1, 1, 0.14), 1.5, true)
		if badge:
			draw_circle(c + Vector2(r * 0.72, -r * 0.72), r * 0.27, Color("ff6b6b"))


# ------------------------------------------------------------------ Démarrage

func _ready() -> void:
	_load_state()
	_load_avatar()
	_build_ui()
	_refresh_account()
	_show_list()
	refresh()
	_check_update()


func _style(bg: Color, rad := 14, pad := 14) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(rad)
	sb.set_content_margin_all(pad)
	sb.anti_aliasing_size = 1.2
	return sb


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 16
	th.set_color("font_color", "Label", C_TEXT)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_disabled_color"]:
		th.set_color(c, "Button", C_TEXT if c != "font_disabled_color" else C_DIM)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := _style(Color("232a34") if st != "hover" else Color("2c3541"), 12, 12)
		if st == "focus":
			sb.bg_color = Color("232a34")
		th.set_stylebox(st, "Button", sb)
	th.set_stylebox("normal", "LineEdit", _style(Color("232a34"), 10, 10))
	th.set_stylebox("focus", "LineEdit", _style(Color("232a34"), 10, 10))
	th.set_color("font_color", "LineEdit", C_TEXT)
	var bgp := _style(Color("232a34"), 5, 0)
	var fill := _style(C_OK, 5, 0)
	th.set_stylebox("background", "ProgressBar", bgp)
	th.set_stylebox("fill", "ProgressBar", fill)
	th.set_stylebox("focus", "ScrollContainer", StyleBoxEmpty.new())
	var sg := _style(Color(1, 1, 1, 0.18), 3, 0)
	sg.content_margin_left = 6
	sg.content_margin_right = 6
	for n in ["grabber", "grabber_highlight", "grabber_pressed"]:
		th.set_stylebox(n, "VScrollBar", sg)
		th.set_stylebox(n, "HScrollBar", sg)
	var sc := StyleBoxEmpty.new()
	th.set_stylebox("scroll", "VScrollBar", sc)
	th.set_stylebox("scroll", "HScrollBar", sc)
	return th


func _label(text: String, size: int, color: Color, parent: Control) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _build_ui() -> void:
	theme = _make_theme()
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 20)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(center)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	get_viewport().size_changed.connect(_fit_width)
	_fit_width()

	var th := HBoxContainer.new()
	col.add_child(th)
	var title := _label("Goodview Software", 30, C_TEXT, th)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", _style(C_CARD, 26, 6))
	chip.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	chip.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_show_profile())
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 10)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(ch)
	chip_avatar = Avatar.new()
	chip_avatar.custom_minimum_size = Vector2(38, 38)
	chip_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.add_child(chip_avatar)
	chip_name = _label("", 16, C_TEXT, ch)
	chip_name.autowrap_mode = TextServer.AUTOWRAP_OFF
	chip_name.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_name.add_theme_constant_override("margin_right", 6)
	th.add_child(chip)

	page_list = VBoxContainer.new()
	page_list.add_theme_constant_override("separation", 12)
	col.add_child(page_list)
	list_box = VBoxContainer.new()
	list_box.add_theme_constant_override("separation", 10)
	page_list.add_child(list_box)

	page_detail = VBoxContainer.new()
	page_detail.add_theme_constant_override("separation", 16)
	col.add_child(page_detail)

	page_profile = VBoxContainer.new()
	page_profile.add_theme_constant_override("separation", 18)
	page_profile.visible = false
	col.add_child(page_profile)
	_build_profile()

	file_dlg = FileDialog.new()
	file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	file_dlg.use_native_dialog = true
	file_dlg.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	file_dlg.file_selected.connect(_set_avatar)
	add_child(file_dlg)

	progress = ProgressBar.new()
	progress.show_percentage = false
	progress.custom_minimum_size = Vector2(0, 10)
	progress.visible = false
	col.add_child(progress)
	status = _label("", 14, C_DIM, col)


func _build_profile() -> void:
	var back := Button.new()
	back.text = "‹  Catalogue"
	back.flat = true
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func():
		_commit_profile()
		_show_list())
	page_profile.add_child(back)
	var top := VBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 14)
	page_profile.add_child(top)
	prof_avatar = Avatar.new()
	prof_avatar.custom_minimum_size = Vector2(140, 140)
	prof_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	prof_avatar.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	prof_avatar.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			file_dlg.popup_centered_ratio(0.6))
	top.add_child(prof_avatar)
	var pb := Button.new()
	pb.text = "Changer l'image"
	pb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pb.pressed.connect(func(): file_dlg.popup_centered_ratio(0.6))
	top.add_child(pb)
	pseudo_edit = LineEdit.new()
	pseudo_edit.placeholder_text = "Pseudo"
	pseudo_edit.max_length = 24
	pseudo_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	pseudo_edit.add_theme_font_size_override("font_size", 22)
	pseudo_edit.custom_minimum_size = Vector2(300, 52)
	pseudo_edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pseudo_edit.text_submitted.connect(func(_t: String): _commit_profile())
	pseudo_edit.focus_exited.connect(_commit_profile)
	top.add_child(pseudo_edit)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(C_CARD, 18, 16))
	page_profile.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var vr := HBoxContainer.new()
	v.add_child(vr)
	upd_lbl = _label("v" + VERSION, 15, C_DIM, vr)
	upd_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	upd_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	upd_btn = Button.new()
	upd_btn.visible = false
	upd_btn.pressed.connect(_do_update)
	vr.add_child(upd_btn)
	token_edit = LineEdit.new()
	token_edit.placeholder_text = "Token GitHub (repos privés)"
	token_edit.secret = true
	token_edit.text = token
	token_edit.custom_minimum_size = Vector2(0, 46)
	token_edit.text_submitted.connect(func(_t: String): _commit_profile())
	token_edit.focus_exited.connect(_commit_profile)
	v.add_child(token_edit)


func _commit_profile() -> void:
	var np := pseudo_edit.text.strip_edges()
	var nt := token_edit.text.strip_edges()
	var retoken := nt != token
	if np != "":
		pseudo = np
	token = nt
	_save_state()
	_refresh_account()
	if retoken:
		refresh()


func _refresh_account() -> void:
	if pseudo == "":
		var u := OS.get_environment("USER").capitalize()
		pseudo = u if u != "" else "Invité"
	chip_name.text = pseudo
	for a in [chip_avatar, prof_avatar]:
		if a != null:
			a.tex = avatar_tex
			a.letter = pseudo.substr(0, 1).to_upper()
	if pseudo_edit != null:
		pseudo_edit.text = pseudo


func _load_avatar() -> void:
	var path := ProjectSettings.globalize_path("user://avatar.png")
	if not FileAccess.file_exists(path):
		return
	var im := Image.load_from_file(path)
	if im == null:
		return
	im.convert(Image.FORMAT_RGBA8)
	im.resize(128, 128, Image.INTERPOLATE_LANCZOS)
	for y in 128:
		for x in 128:
			if Vector2(x - 63.5, y - 63.5).length() > 64.0:
				im.set_pixel(x, y, Color(0, 0, 0, 0))
	avatar_tex = ImageTexture.create_from_image(im)


func _set_avatar(path: String) -> void:
	var im := Image.load_from_file(path)
	if im == null:
		status.text = "Image illisible."
		return
	var side := mini(im.get_width(), im.get_height())
	im = im.get_region(Rect2i((im.get_width() - side) / 2, (im.get_height() - side) / 2, side, side))
	im.resize(256, 256, Image.INTERPOLATE_LANCZOS)
	im.save_png(ProjectSettings.globalize_path("user://avatar.png"))
	_load_avatar()
	_refresh_account()


func _show_profile() -> void:
	cur_app = {}
	page_list.visible = false
	page_detail.visible = false
	page_profile.visible = true
	_refresh_account()


func _fit_width() -> void:
	if col != null:
		col.custom_minimum_size.x = clampf(get_viewport_rect().size.x - 44.0, 300.0, 780.0)


func _show_list() -> void:
	cur_app = {}
	page_list.visible = true
	page_detail.visible = false
	page_profile.visible = false
	_render_list()


# ------------------------------------------------------------------ Catalogue

func _render_list() -> void:
	for c in list_box.get_children():
		c.queue_free()
	for a in apps:
		list_box.add_child(_card(a))


func _card(a: Dictionary) -> Control:
	var p := PanelContainer.new()
	var sb := _style(C_CARD, 18, 14)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	p.mouse_entered.connect(func(): sb.bg_color = C_CARD_HI)
	p.mouse_exited.connect(func(): sb.bg_color = C_CARD)
	p.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_show_detail(a))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	h.add_child(_icon(a, 72))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 3)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_label(_title(a), 20, C_TEXT, v)
	_label(_tagline(a), 14, C_DIM, v)
	var st := _label(_state_text(a), 13, C_OK if _is_installed(a) else C_DIM, v)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for c in v.get_children():
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _icon(a: Dictionary, px: int) -> AppIcon:
	var ic := AppIcon.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.tex = a.get("icon")
	ic.letter = str(a.name).substr(0, 1).to_upper()
	ic.tint = Color.from_hsv(float(str(a.name).hash() % 360) / 360.0, 0.55, 0.9)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return ic


func _title(a: Dictionary) -> String:
	return str(a.manifest.get("name", str(a.name).replace("-", " ").capitalize()))


func _tagline(a: Dictionary) -> String:
	var t = a.manifest.get("tagline", a.repo.get("description", ""))
	return str(t) if t != null else ""


func _tag(a: Dictionary) -> String:
	return str(a.release.get("tag_name", ""))


func _is_installed(a: Dictionary) -> bool:
	return installed.has(a.name)


func _state_text(a: Dictionary) -> String:
	var tag := _tag(a)
	if tag == "":
		return "Bientôt disponible"
	if not _is_installed(a):
		return tag
	if installed[a.name].tag == tag:
		return "Installée · à jour"
	return "Mise à jour disponible · %s" % tag


# ------------------------------------------------------------------ Page de présentation

func _show_detail(a: Dictionary) -> void:
	cur_app = a
	page_list.visible = false
	page_profile.visible = false
	page_detail.visible = true
	_render_detail()
	DisplayServer.window_set_title(_title(a) + " · Goodview Launcher")


func _render_detail() -> void:
	var a := cur_app
	for c in page_detail.get_children():
		c.queue_free()
	var back := Button.new()
	back.text = "‹  Catalogue"
	back.flat = true
	back.alignment = HORIZONTAL_ALIGNMENT_LEFT
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func():
		DisplayServer.window_set_title("Goodview Launcher")
		_show_list())
	page_detail.add_child(back)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 20)
	page_detail.add_child(head)
	head.add_child(_icon(a, 120))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 6)
	head.add_child(v)
	_label(_title(a), 32, C_TEXT, v)
	_label(_tagline(a), 16, C_DIM, v)
	var meta := PackedStringArray()
	if _tag(a) != "":
		meta.append(_tag(a))
	if not a.asset.is_empty():
		meta.append("%.0f Mo" % (float(a.asset.get("size", 0)) / 1048576.0))
	var d := str(a.release.get("published_at", "")).substr(0, 10)
	if d != "":
		meta.append(d)
	_label("  ·  ".join(meta), 13, C_DIM, v)

	# actions
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 10)
	page_detail.add_child(act)
	var tag := _tag(a)
	var inst: Dictionary = installed.get(a.name, {})
	var main := Button.new()
	main.custom_minimum_size = Vector2(190, 52)
	for st in ["normal", "hover", "pressed", "focus"]:
		var sb := _style(C_OK if st != "hover" else C_OK.lightened(0.15), 14, 12)
		main.add_theme_stylebox_override(st, sb)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		main.add_theme_color_override(c, Color("0e1116"))
	main.add_theme_font_size_override("font_size", 18)
	if tag == "":
		main.text = "Pas encore publiée"
		main.disabled = true
		main.add_theme_stylebox_override("disabled", _style(Color("232a34"), 14, 12))
	elif inst.is_empty():
		main.text = "Installer"
	elif inst.tag != tag:
		main.text = "Mettre à jour"
	else:
		main.text = "Lancer"
	if tag != "" and a.asset.is_empty() and (inst.is_empty() or inst.tag != tag):
		main.text = "Pas de version Linux"
		main.disabled = true
		main.add_theme_stylebox_override("disabled", _style(Color("232a34"), 14, 12))
	main.pressed.connect(func():
		if main.text == "Lancer":
			_launch(a.name)
		else:
			install(a))
	act.add_child(main)
	if not inst.is_empty():
		var rm := Button.new()
		rm.text = "Désinstaller"
		rm.custom_minimum_size = Vector2(0, 52)
		rm.pressed.connect(func(): _uninstall(a))
		act.add_child(rm)
	var gh := Button.new()
	gh.text = "GitHub"
	gh.custom_minimum_size = Vector2(0, 52)
	gh.pressed.connect(func(): OS.shell_open("https://github.com/%s/%s" % [a.org, a.name]))
	act.add_child(gh)

	# captures d'écran
	var shots: Array = a.manifest.get("screenshots", [])
	if shots.size() > 0:
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 250)
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		page_detail.add_child(sc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		sc.add_child(row)
		_load_shots(a, shots, row)

	# description
	var desc := str(a.manifest.get("description", ""))
	if desc == "":
		desc = _tagline(a)
	if desc != "":
		_section("À propos", desc)
	var notes := str(a.release.get("body", "")).strip_edges()
	if notes != "":
		_section("Nouveautés · " + tag, notes.left(900))


func _section(title: String, body: String) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _style(C_CARD, 18, 18))
	page_detail.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	_label(title, 18, C_TEXT, v)
	_label(body, 15, C_DIM, v)


func _load_shots(a: Dictionary, shots: Array, row: HBoxContainer) -> void:
	for s in shots:
		var r: Array = await _get_bytes("%s/%s/%s/HEAD/%s" % [RAW, a.org, a.name, str(s)])
		if r[0] != 200 or not is_instance_valid(row):
			continue
		var t := _tex(r[1], str(s).ends_with(".svg"))
		if t == null:
			continue
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(250.0 * t.get_width() / maxf(1.0, t.get_height()), 240)
		row.add_child(tr)


# ------------------------------------------------------------------ Réseau

func _headers(binary := false) -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: goodview-launcher"])
	h.append("Accept: application/octet-stream" if binary else "Accept: application/vnd.github+json")
	if token != "":
		h.append("Authorization: Bearer " + token)
	return h


func _get_bytes(url: String) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	add_child(req)
	if req.request(url, _headers()) != OK:
		req.queue_free()
		return [0, PackedByteArray()]
	var res: Array = await req.request_completed
	req.queue_free()
	return [res[1], res[3]]


func _get_json(url: String) -> Variant:
	var r: Array = await _get_bytes(url)
	if r[0] != 200:
		return null
	return JSON.parse_string((r[1] as PackedByteArray).get_string_from_utf8())


func _tex(bytes: PackedByteArray, svg := false) -> Texture2D:
	var im := Image.new()
	var err := im.load_svg_from_buffer(bytes, 2.0) if svg else im.load_png_from_buffer(bytes)
	if err != OK and not svg:
		err = im.load_jpg_from_buffer(bytes)
	return ImageTexture.create_from_image(im) if err == OK else null


func refresh() -> void:
	if busy:
		return
	busy = true
	apps.clear()
	_render_list()
	status.text = "Chargement du catalogue…"
	var failed := 0
	for org in ORGS:
		var repos = await _get_json("%s/orgs/%s/repos?per_page=100&type=%s" % [API, org, "all" if token != "" else "public"])
		if repos == null or not repos is Array:
			failed += 1
			continue
		for repo in repos:
			if repo.name in EXCLUDED or repo.get("archived", false):
				continue
			var rel = await _get_json("%s/repos/%s/%s/releases/latest" % [API, org, repo.name])
			var a := {"name": repo.name, "org": org, "repo": repo, "release": rel if rel is Dictionary else {},
					"asset": {}, "icon": null, "manifest": {}}
			a.asset = _pick_asset(a.release)
			var m: Array = await _get_bytes("%s/%s/%s/HEAD/app.json" % [RAW, org, repo.name])
			if m[0] == 200:
				var j = JSON.parse_string((m[1] as PackedByteArray).get_string_from_utf8())
				if j is Dictionary:
					a.manifest = j
			for f in ["icon.png", "icon.svg"]:
				var ic: Array = await _get_bytes("%s/%s/%s/HEAD/%s" % [RAW, org, repo.name, f])
				if ic[0] == 200:
					a.icon = _tex(ic[1], f.ends_with(".svg"))
					if a.icon != null:
						break
			apps.append(a)
			if cur_app.is_empty():
				list_box.add_child(_card(a))
	if failed == ORGS.size():
		status.text = "Impossible de lire le catalogue (réseau ou token ?)."
	else:
		status.text = "" if apps.size() > 0 else "Aucune application publiée pour l'instant."
	busy = false


# ------------------------------------------------------------------ Installation

func _pick_asset(release: Dictionary) -> Dictionary:
	var best := {}
	for a in release.get("assets", []):
		var n: String = a.name.to_lower()
		if n.ends_with(".apk") or n.ends_with(".pck") or n.ends_with(".json"):
			continue
		if n.contains("linux") or n.ends_with(".x86_64") or n.ends_with(".appimage"):
			return a
		if best.is_empty() and not (n.contains("windows") or n.contains("macos") or n.ends_with(".exe")):
			best = a
	return best


func install(a: Dictionary) -> void:
	if busy:
		return
	busy = true
	var name: String = a.name
	var asset: Dictionary = a.asset
	var dir := ProjectSettings.globalize_path(APPS_DIR + "/" + name)
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir)
	var file: String = dir + "/" + str(asset.name)
	var req := HTTPRequest.new()
	req.download_file = file
	req.max_redirects = 8
	add_child(req)
	var url: String = asset.url if token != "" else asset.browser_download_url
	req.request(url, _headers(true) if token != "" else PackedStringArray(["User-Agent: goodview-launcher"]))
	progress.visible = true
	progress.value = 0
	status.text = "Téléchargement…"
	while true:
		var total := req.get_body_size()
		if total > 0:
			progress.value = 100.0 * req.get_downloaded_bytes() / total
		await get_tree().process_frame
		if req.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			break
	req.queue_free()
	progress.visible = false
	if not FileAccess.file_exists(file) or FileAccess.get_file_as_bytes(file).size() < 100:
		status.text = "Échec du téléchargement."
		busy = false
		return
	var exe := _unpack(file, dir)
	if exe == "":
		status.text = "Aucun exécutable trouvé dans " + str(asset.name)
		busy = false
		return
	installed[name] = {"tag": _tag(a), "exe": exe}
	_save_state()
	status.text = "Installée ✔"
	busy = false
	_render_detail()


func _unpack(file: String, dir: String) -> String:
	var n := file.get_file().to_lower()
	if n.ends_with(".zip"):
		var z := ZIPReader.new()
		if z.open(file) != OK:
			return ""
		for p in z.get_files():
			if p.ends_with("/"):
				DirAccess.make_dir_recursive_absolute(dir + "/" + p)
				continue
			DirAccess.make_dir_recursive_absolute((dir + "/" + p).get_base_dir())
			var f := FileAccess.open(dir + "/" + p, FileAccess.WRITE)
			f.store_buffer(z.read_file(p))
			f.close()
		z.close()
		DirAccess.remove_absolute(file)
	elif n.ends_with(".tar.gz") or n.ends_with(".tgz"):
		OS.execute("tar", ["-xzf", file, "-C", dir])
		DirAccess.remove_absolute(file)
	OS.execute("chmod", ["-R", "u+x", dir])
	return _find_exe(dir)


func _find_exe(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for sub in d.get_directories():
		var found := _find_exe(dir + "/" + sub)
		if found != "":
			return found
	for f in d.get_files():
		var l := f.to_lower()
		if l.ends_with(".x86_64") or l.ends_with(".appimage") or l.ends_with(".sh"):
			return dir + "/" + f
	for f in d.get_files():
		if f.get_extension() == "":
			return dir + "/" + f
	return ""


func _launch(name: String) -> void:
	var exe: String = installed[name].exe
	var pid := OS.create_process(exe, [])
	status.text = "Lancée." if pid > 0 else "Impossible de lancer " + exe


func _uninstall(a: Dictionary) -> void:
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(APPS_DIR + "/" + str(a.name))])
	installed.erase(a.name)
	_save_state()
	status.text = ""
	_render_detail()


# ------------------------------------------------------------------ Persistance

func _load_state() -> void:
	if FileAccess.file_exists(STATE_FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
		if d is Dictionary:
			installed = d
	var cfg := ConfigFile.new()
	if cfg.load(CFG_FILE) == OK:
		token = cfg.get_value("github", "token", "")
		pseudo = str(cfg.get_value("profile", "pseudo", ""))


func _save_state() -> void:
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(installed))
	f.close()
	var cfg := ConfigFile.new()
	cfg.set_value("github", "token", token)
	cfg.set_value("profile", "pseudo", pseudo)
	cfg.save(CFG_FILE)


# ------------------------------------------------------------------ Mise à jour du launcher (version.json + .pck)

func _check_update() -> void:
	upd_lbl.text = "v" + VERSION
	upd_http = HTTPRequest.new()
	upd_http.timeout = 10.0
	add_child(upd_http)
	upd_http.request_completed.connect(_on_version_json, CONNECT_ONE_SHOT)
	upd_http.request(UPDATE_URL)


func _on_version_json(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var info = JSON.parse_string(body.get_string_from_utf8())
	if not (info is Dictionary) or not info.has("version"):
		return
	if not preload("res://boot.gd").newer(str(info["version"]), VERSION):
		upd_lbl.text = "✓ v" + VERSION
		return
	upd_info = info
	chip_avatar.badge = true
	var v := Engine.get_version_info()
	var same: bool = str(info.get("godot", "")) == "%d.%d.%d" % [v.major, v.minor, v.patch]
	upd_btn.visible = true
	if same and info.has("pck"):
		upd_lbl.text = "v%s disponible" % info["version"]
		upd_btn.text = "Mettre à jour"
	else:
		upd_lbl.text = "v%s disponible (nouveau programme)" % info["version"]
		upd_btn.text = "Télécharger"


func _do_update() -> void:
	if upd_btn.text == "Télécharger":
		OS.shell_open(RELEASES_URL)
		return
	if upd_btn.text == "Redémarrer":
		OS.set_restart_on_exit(true)
		get_tree().quit()
		return
	upd_btn.disabled = true
	upd_lbl.text = "Téléchargement…"
	upd_http.download_file = "user://update.tmp"
	upd_http.request_completed.connect(_on_pck, CONNECT_ONE_SHOT)
	upd_http.request(str(upd_info["pck"]))


func _on_pck(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	upd_http.download_file = ""
	upd_btn.disabled = false
	var tmp := "user://update.tmp"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 \
			or FileAccess.get_sha256(tmp) != str(upd_info.get("sha256", "")):
		DirAccess.remove_absolute(tmp)
		upd_lbl.text = "Échec du téléchargement"
		return
	DirAccess.rename_absolute(tmp, "user://update.pck")
	var c := ConfigFile.new()
	c.set_value("update", "version", str(upd_info["version"]))
	c.save("user://update.cfg")
	upd_lbl.text = "v%s installée" % upd_info["version"]
	upd_btn.text = "Redémarrer"
