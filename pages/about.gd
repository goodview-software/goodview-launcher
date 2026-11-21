extends "res://pages/page.gd"
## À propos : version, mise à jour du launcher, liens.

const LINKS := [
	["github", "Organisation Goodview", "https://github.com/goodview-software"],
	["github", "Code du launcher", "https://github.com/goodview-software/goodview-launcher"],
	["link", "Notes de version", "https://github.com/goodview-software/goodview-launcher/releases"],
]

var _upd_box: VBoxContainer


func _init() -> void:
	page_title = "À propos"


func build() -> void:
	var sv := W.StateView.new("idle", ctx.active, "Goodview Launcher", "Version " + ctx.VERSION, "", 170)
	body.add_child(sv)
	_upd_box = VBoxContainer.new()
	_upd_box.add_theme_constant_override("separation", 12)
	body.add_child(_upd_box)
	link(ctx.updater.changed, _render_update)
	_render_update()
	var c := W.card(body, 8)
	for i in LINKS.size():
		if i > 0:
			W.hsep(c)
		var row := W.Row.new()
		var url: String = LINKS[i][2]
		row.pressed.connect(func(): OS.shell_open(url))
		c.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(h)
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(30, 30)
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kind: String = LINKS[i][0]
		ic.draw.connect(func(): W.Ico.draw_kind(ic, kind, ic.size / 2.0, 0.7, T.TEXT))
		h.add_child(ic)
		var l := W.label(LINKS[i][1], 17, T.TEXT, h)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ch := Control.new()
		ch.custom_minimum_size = Vector2(22, 22)
		ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ch.draw.connect(func(): W.Ico.draw_kind(ch, "chevron", ch.size / 2.0, 0.5, T.DIM))
		h.add_child(ch)
	var f := W.label("Mascotte Goody · fait avec Godot %s" % Engine.get_version_info().string, 13, T.DIM, body)
	f.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _exit_tree() -> void:
	if ctx != null and ctx.updater.changed.is_connected(_render_update):
		ctx.updater.changed.disconnect(_render_update)


func _render_update() -> void:
	for c in _upd_box.get_children():
		_upd_box.remove_child(c)
		c.queue_free()
	var u := ctx.updater
	var card := W.card(_upd_box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	card.add_child(line)
	var txt := "Vérification…"
	var btn := ""
	match u.state:
		"uptodate":
			txt = "Le launcher est à jour"
		"available":
			txt = "Version %s disponible" % u.info.get("version", "")
			btn = "Mettre à jour"
		"newbin":
			txt = "Version %s disponible (nouveau programme)" % u.info.get("version", "")
			btn = "Télécharger"
		"downloading":
			txt = "Téléchargement… %d %%" % int(u.ratio * 100.0)
		"ready":
			txt = "Mise à jour prête"
			btn = "Redémarrer"
		"error":
			txt = u.error_msg
			btn = "Réessayer"
		"idle":
			txt = "Mises à jour non vérifiées"
			btn = "Vérifier"
	var l := W.label(txt, 16, T.TEXT, line)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if btn != "":
		var b := W.Btn.new(btn, "primary" if u.state in ["available", "ready", "newbin"] else "soft")
		b.custom_minimum_size = Vector2(0, 44)
		b.pressed.connect(_on_update_button)
		line.add_child(b)
	if u.notes != "" and u.available():
		W.label(u.notes, 14, T.DIM, card)


func _on_update_button() -> void:
	var u := ctx.updater
	match u.state:
		"available", "newbin":
			u.download()
		"ready":
			u.restart()
		_:
			u.check_launcher()
