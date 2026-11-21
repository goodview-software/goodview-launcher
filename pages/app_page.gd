extends "res://pages/page.gd"
## Fiche d'une app : installer / mettre à jour / lancer, notes de version, QR APK, raccourci, désinstallation.

const QR := preload("res://qr.gd")

var app_name := ""
var _confirm := false
var _prog: ProgressBar
var _prog_lbl: Label
var _star: W.IconBtn
var _connected := false
var _shots := {}  # chemin -> texture (évite de retélécharger à chaque reconstruction)


func build() -> void:
	app_name = str(args.get("name", ""))
	var a := ctx.catalog.find(app_name)
	head_title.text = ""
	if not _connected:
		_connect()
	if a.is_empty():
		set_title("App introuvable")
		var sv := W.StateView.new("sad", ctx.store.avatar, "App introuvable", "Elle a peut-être été retirée du catalogue.", "Retour", 170)
		sv.action.connect(func(): router.back())
		body.add_child(sv)
		return
	set_title(Catalog.title(a))
	_header_buttons(a)
	_content(a)


func _connect() -> void:
	_connected = true
	ctx.catalog.changed.connect(_refresh)
	ctx.installer.changed.connect(_refresh)
	ctx.installer.progress.connect(_on_progress)


func _refresh() -> void:
	if is_inside_tree() and body != null:
		rebuild()


func _on_progress(r: float) -> void:
	if _prog != null and is_instance_valid(_prog):
		_prog.value = r * 100.0
		_prog_lbl.text = "%d %%" % int(r * 100.0)


func _header_buttons(a: Dictionary) -> void:
	for c in head_right.get_children():
		head_right.remove_child(c)
		c.queue_free()
	var fav := ctx.store.is_fav(app_name)
	_star = W.IconBtn.new("star_on" if fav else "star", 44)
	_star.col = T.WARN if fav else T.TEXT
	_star.tooltip_text = "Retirer des favoris" if fav else "Ajouter aux favoris"
	_star.pressed.connect(func():
		ctx.store.toggle_fav(app_name)
		_header_buttons(a))
	head_right.add_child(_star)
	var gh := W.IconBtn.new("github", 44)
	gh.tooltip_text = "Ouvrir sur GitHub"
	gh.pressed.connect(func(): OS.shell_open("https://github.com/%s/%s" % [a.org, a.name]))
	head_right.add_child(gh)


func _content(a: Dictionary) -> void:
	var status := ctx.app_status(a)
	var tag := Catalog.tag(a)
	var inst: Dictionary = ctx.store.installed.get(a.name, {})
	var queued := ctx.installer.is_queued(app_name)

	var ic := app_icon(a, 200, true)
	if status == "ok":
		ic.badge = T.OK
	body.add_child(ic)
	var t := W.label(Catalog.title(a), 28, T.TEXT, body)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tg := W.label(Catalog.tagline(a), 15, T.DIM, body)
	tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var chips := HBoxContainer.new()
	chips.alignment = BoxContainer.ALIGNMENT_CENTER
	chips.add_theme_constant_override("separation", 8)
	body.add_child(chips)
	if tag != "":
		W.pill(chips, tag, T.DIM)
	if not a.asset.is_empty():
		W.pill(chips, ctx.fmt_size(float(a.asset.get("size", 0))), T.DIM)
	var s := status_pill(a)
	if s[0] != tag:
		W.pill(chips, s[0], s[1])

	# notes de version visibles avant de mettre à jour
	if status == "update":
		var nc := W.card(body)
		W.label("Mise à jour : %s → %s" % [inst.get("tag", "?"), tag], 18, T.WARN, nc)
		var notes := Catalog.clean_notes(str(a.release.get("body", "")))
		W.label(notes if notes != "" else "Pas de notes de version.", 15, T.DIM, nc)

	# action principale (ou progression avec annulation)
	if queued:
		var pc := W.card(body)
		var ph := HBoxContainer.new()
		ph.add_theme_constant_override("separation", 12)
		pc.add_child(ph)
		var cur: bool = ctx.installer.current.get("name", "") == app_name
		var pl := W.label("Téléchargement…" if cur else "En attente…", 16, T.TEXT, ph)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_prog_lbl = W.label("", 14, T.DIM, ph)
		var x := W.IconBtn.new("close", 36)
		x.tooltip_text = "Annuler"
		x.pressed.connect(ctx.installer.cancel)
		ph.add_child(x)
		_prog = ProgressBar.new()
		_prog.show_percentage = false
		_prog.custom_minimum_size = Vector2(0, 8)
		_prog.value = ctx.installer.ratio * 100.0 if cur else 0.0
		pc.add_child(_prog)
	else:
		_prog = null
		if ctx.installer.errors.has(app_name):
			var ec := PanelContainer.new()
			ec.add_theme_stylebox_override("panel", T.style(Color(T.BAD, 0.12), 22, 16))
			body.add_child(ec)
			var er := HBoxContainer.new()
			er.add_theme_constant_override("separation", 12)
			ec.add_child(er)
			var ei := Control.new()
			ei.custom_minimum_size = Vector2(30, 30)
			ei.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ei.draw.connect(func(): W.Ico.draw_kind(ei, "alert", ei.size / 2.0, 0.7, T.BAD))
			er.add_child(ei)
			var el := W.label(str(ctx.installer.errors[app_name]), 15, T.TEXT, er)
			el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		body.add_child(_main_button(a, status))

	_apk_card(a)

	# réglages de l'app installée
	var card := W.card(body)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 14)
	card.add_child(r1)
	var i1 := W.IconBtn.new("refresh", 44)
	i1.tooltip_text = "Vérifier les mises à jour de cette app"
	i1.spin = ctx.catalog.checking
	i1.pressed.connect(func():
		if not await ctx.catalog.check_one(a):
			ctx.notify("Vérification impossible : " + ctx.catalog.error_msg, "error"))
	r1.add_child(i1)
	var st1 := W.label(_check_text(a, status), 15, T.DIM, r1)
	st1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not inst.is_empty():
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 14)
		card.add_child(r2)
		var i2 := W.IconBtn.new("desktop", 44)
		i2.col = T.OK if inst.get("desk", false) else T.TEXT
		r2.add_child(i2)
		var sl := W.label("Raccourci sur le bureau", 15, T.DIM, r2)
		sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var tg2 := W.Toggle.new()
		tg2.set_on(inst.get("desk", false))
		tg2.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		tg2.toggled.connect(func(on: bool):
			if not ctx.installer.set_shortcut(a, on):
				ctx.notify("Impossible de créer le raccourci.", "error")
				tg2.set_on(false)
				on = false
			i2.col = T.OK if on else T.TEXT)
		r2.add_child(tg2)
		card.add_child(_uninstall_row(a))

	_screenshots(a)
	var desc := str(a.manifest.get("description", ""))
	if desc != "":
		var dc := W.card(body)
		W.label("À propos", 18, T.TEXT, dc)
		W.label(desc, 15, T.DIM, dc)
	var notes2 := Catalog.clean_notes(str(a.release.get("body", "")))
	if notes2 != "" and status != "update":
		var nc2 := W.card(body)
		W.label("Nouveautés · " + tag, 18, T.TEXT, nc2)
		W.label(notes2, 15, T.DIM, nc2)


func _main_button(a: Dictionary, status: String) -> Button:
	var b := W.Btn.new("", "primary")
	b.custom_minimum_size = Vector2(260, 58)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 19)
	b.set_kind("primary")
	var failed: bool = ctx.installer.errors.has(app_name)
	match status:
		"soon":
			b.text = "Pas encore publiée"
			b.disabled = true
		"nolinux":
			b.text = "Pas de version Linux"
			b.disabled = true
		"none":
			b.text = "Réessayer" if failed else "Installer"
		"update":
			b.text = "Réessayer" if failed else "Mettre à jour"
		_:
			b.text = "Lancer"
	b.pressed.connect(func():
		if status == "ok":
			var err := ctx.installer.launch(app_name)
			ctx.notify(err if err != "" else "%s se lance…" % Catalog.title(a), "error" if err != "" else "ok")
		else:
			ctx.installer.enqueue(a))
	return b


func _uninstall_row(a: Dictionary) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	if not _confirm:
		var i3 := W.IconBtn.new("trash", 44)
		i3.col = T.BAD
		i3.tooltip_text = "Désinstaller"
		i3.pressed.connect(func():
			_confirm = true
			rebuild()
			get_tree().create_timer(4.0).timeout.connect(func():
				if is_instance_valid(self) and _confirm:
					_confirm = false
					rebuild()))
		h.add_child(i3)
		var l := W.label("Désinstaller", 15, T.DIM, h)
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		var ok := W.Btn.new("Confirmer la désinstallation", "danger")
		ok.custom_minimum_size = Vector2(0, 44)
		ok.pressed.connect(func():
			_confirm = false
			ctx.installer.uninstall(a)
			ctx.notify("%s désinstallée" % Catalog.title(a)))
		h.add_child(ok)
		var no := W.Btn.new("Annuler", "ghost")
		no.custom_minimum_size = Vector2(0, 44)
		no.pressed.connect(func():
			_confirm = false
			rebuild())
		h.add_child(no)
	return h


func _check_text(a: Dictionary, status: String) -> String:
	var inst: Dictionary = ctx.store.installed.get(a.name, {})
	match status:
		"soon":
			return "Aucune version publiée"
		"ok":
			return "À jour · " + Catalog.tag(a)
		"update":
			return "%s → %s" % [inst.get("tag", "?"), Catalog.tag(a)]
	return "Dernière version : " + Catalog.tag(a)


func _apk_card(a: Dictionary) -> void:
	var apk := Catalog.pick_apk(a.release)
	if apk.is_empty():
		return
	var qc := W.card(body)
	var qr_url := str(apk.browser_download_url)
	var qt: Texture2D = QR.texture(qr_url, 6)
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 18)
	qc.add_child(qh)
	if qt != null:
		var fr := PanelContainer.new()
		fr.add_theme_stylebox_override("panel", T.style(Color.WHITE, 16, 6))
		fr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		qh.add_child(fr)
		var tr := TextureRect.new()
		tr.texture = qt
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(170, 170)
		tr.tooltip_text = "Scanne avec ton téléphone"
		fr.add_child(tr)
	var qv := VBoxContainer.new()
	qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qv.alignment = BoxContainer.ALIGNMENT_CENTER
	qv.add_theme_constant_override("separation", 12)
	qh.add_child(qv)
	var ph := W.IconBtn.new("phone", 64)
	ph.tooltip_text = "Télécharger l'APK (Android)"
	ph.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ph.pressed.connect(func(): OS.shell_open(qr_url))
	qv.add_child(ph)
	var pr := HBoxContainer.new()
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	qv.add_child(pr)
	W.pill(pr, "APK · " + ctx.fmt_size(float(apk.get("size", 0))), T.DIM)


func _screenshots(a: Dictionary) -> void:
	var shots: Array = a.manifest.get("screenshots", [])
	if shots.is_empty():
		return
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 250)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(sc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	sc.add_child(row)
	for sh in shots:
		var tex: Texture2D = _shots.get(sh)
		if tex == null:
			var r: Array = await ctx.catalog.get_bytes("%s/%s/%s/HEAD/%s" % [Catalog.RAW, a.org, a.name, str(sh)])
			if r[0] != 200:
				continue
			tex = ctx.catalog.make_tex(r[1], str(sh).ends_with(".svg"))
			if tex == null:
				continue
			_shots[sh] = tex
		if not is_instance_valid(row) or not row.is_inside_tree():
			continue
		var tr := TextureRect.new()
		tr.texture = tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(250.0 * tex.get_width() / maxf(1.0, tex.get_height()), 240)
		row.add_child(tr)
