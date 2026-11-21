extends "res://pages/page.gd"
## Fiche d'une app : installer / mettre à jour / lancer, notes de version, QR APK, raccourci, désinstallation.

const QR := preload("res://qr.gd")

var app_name := ""
var _confirm := false
var _prog: ProgressBar
var _prog_lbl: Label
var _main: VBoxContainer  # colonne principale
var _side: VBoxContainer  # colonne d'informations (= _main en écran étroit)
var _col: VBoxContainer  # conteneur courant des sections
var _wide := false
var force_wide := -1
var _connected := false
const MONTHS := ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."]

var _hist := {}  # app -> liste des releases (évite de re-interroger GitHub à chaque reconstruction)
var _shots := {}  # chemin -> texture (évite de retélécharger à chaque reconstruction)


func _init() -> void:
	max_w = 1040.0


func is_wide() -> bool:
	if force_wide >= 0:
		return force_wide == 1
	var w := size.x if size.x > 0.0 else get_viewport_rect().size.x
	return w >= 900.0


func _fit_width() -> void:
	super()
	if body != null and is_inside_tree() and not a_empty() and is_wide() != _wide:
		rebuild()


func a_empty() -> bool:
	return ctx.catalog.find(app_name).is_empty()


func build() -> void:
	app_name = str(args.get("name", ""))
	var a := ctx.catalog.find(app_name)
	head_title.text = ""
	if not _connected:
		_connect()
	if a.is_empty():
		set_title("App introuvable")
		var sv := W.StateView.new("sad", ctx.active, "App introuvable", "Elle a peut-être été retirée du catalogue.", "Retour", 170)
		sv.action.connect(func(): router.back())
		body.add_child(sv)
		return
	set_title(Catalog.title(a))
	_content(a)


func _connect() -> void:
	_connected = true
	link(ctx.catalog.changed, _refresh)
	link(ctx.installer.changed, _refresh)
	link(ctx.installer.progress, _on_progress)


func _refresh() -> void:
	if is_inside_tree() and body != null:
		rebuild()


func _on_progress(r: float) -> void:
	if _prog != null and is_instance_valid(_prog):
		_prog.value = r * 100.0
		_prog_lbl.text = "%d %%" % int(r * 100.0)


func _content(a: Dictionary) -> void:
	var status := ctx.app_status(a)
	var tag := Catalog.tag(a)
	var inst: Dictionary = ctx.store.installed.get(a.name, {})
	var queued := ctx.installer.is_queued(app_name)
	_wide = is_wide()
	var lay: BoxContainer = HBoxContainer.new() if _wide else VBoxContainer.new()
	lay.add_theme_constant_override("separation", 24 if _wide else 16)
	body.add_child(lay)
	_main = VBoxContainer.new()
	_main.add_theme_constant_override("separation", 16)
	_main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(_main)
	if _wide:
		_side = VBoxContainer.new()
		_side.add_theme_constant_override("separation", 16)
		_side.custom_minimum_size = Vector2(340, 0)
		_side.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		lay.add_child(_side)
	else:
		_side = _main
	_col = _main

	# --- En-tête : icône nette, nom, accroche, pastilles
	var hd := HBoxContainer.new()
	hd.add_theme_constant_override("separation", 16 if _wide else 12)
	_main.add_child(hd)
	var px := 112 if _wide else 88
	var ic := app_icon(a, px, false)
	ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if status == "ok":
		ic.badge = T.OK
	hd.add_child(ic)
	var hv := VBoxContainer.new()
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hv.add_theme_constant_override("separation", 4)
	hd.add_child(hv)
	var t := W.label(Catalog.title(a), 28, T.TEXT, hv)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var tg := W.label(Catalog.tagline(a), 15, T.DIM, hv)
	tg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 8)
	hv.add_child(chips)
	var s := status_pill(a)
	W.pill(chips, s[0], s[1])
	if tag != "" and s[0] != tag:
		W.pill(chips, tag, T.DIM)

	# --- Actions : une seule rangée (bouton principal + favori, GitHub, partager) ; ou progression
	if queued:
		var pc := W.card(_main)
		var ph := HBoxContainer.new()
		ph.add_theme_constant_override("separation", 12)
		pc.add_child(ph)
		var cur: bool = ctx.installer.current.get("name", "") == app_name
		var pl := W.label("Téléchargement…" if cur else "En attente…", 15, T.TEXT, ph)
		pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_prog_lbl = W.label("", 14, T.DIM, ph)
		_prog_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var x := W.IconBtn.new("close", 44)
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
			ec.add_theme_stylebox_override("panel", T.style(Color(T.BAD, 0.12), 24, 16))
			_main.add_child(ec)
			var er := HBoxContainer.new()
			er.add_theme_constant_override("separation", 12)
			ec.add_child(er)
			var ei := W.IconBtn.new("alert", 44)
			ei.col = T.BAD
			ei.mouse_filter = Control.MOUSE_FILTER_IGNORE
			er.add_child(ei)
			var el := W.label(str(ctx.installer.errors[app_name]), 15, T.TEXT, er)
			el.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			el.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			el.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var ar := HBoxContainer.new()
		ar.add_theme_constant_override("separation", 8)
		_main.add_child(ar)
		var mb := _main_button(a, status)
		mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ar.add_child(mb)
		var fav := ctx.store.is_fav(app_name)
		var st := W.IconBtn.new("star_on" if fav else "star", 44)
		st.col = T.WARN if fav else T.TEXT
		st.tooltip_text = "Retirer des favoris" if fav else "Ajouter aux favoris"
		st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		st.pressed.connect(func():
			ctx.store.toggle_fav(app_name)
			rebuild())
		ar.add_child(st)
		var gh := W.IconBtn.new("github", 44)
		gh.tooltip_text = "Ouvrir sur GitHub"
		gh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		gh.pressed.connect(func(): OS.shell_open("https://github.com/%s/%s" % [a.org, a.name]))
		ar.add_child(gh)
		var sh := W.IconBtn.new("link", 44)
		sh.tooltip_text = "Copier le lien"
		sh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sh.pressed.connect(func():
			DisplayServer.clipboard_set("https://github.com/%s/%s" % [a.org, a.name])
			ctx.notify("Lien copié", "ok"))
		ar.add_child(sh)

	_stats(a)

	# notes de version visibles avant de mettre à jour
	if status == "update":
		var nc := W.card(_main)
		W.label("Mise à jour : %s → %s" % [inst.get("tag", "?"), tag], 18, T.WARN, nc)
		var notes := Catalog.clean_notes(str(a.release.get("body", "")))
		W.label(notes if notes != "" else "Pas de notes de version.", 15, T.DIM, nc)

	_col = _main
	_screenshots(a)
	_about(a)
	_notes(a, status)
	_history(a)
	_col = _side
	_info(a, inst)
	_apk_card(a)
	_manage_card(a, status, inst)


func _manage_card(a: Dictionary, status: String, inst: Dictionary) -> void:
	# gérer l'app
	var card := W.card(_col)
	W.label("Gérer", 18, T.TEXT, card)
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
	st1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	st1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st1.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if not inst.is_empty():
		var r2 := HBoxContainer.new()
		r2.add_theme_constant_override("separation", 14)
		card.add_child(r2)
		var i2 := W.IconBtn.new("desktop", 44)
		i2.col = T.OK if inst.get("desk", false) else T.TEXT
		r2.add_child(i2)
		var sl := W.label("Raccourci bureau", 15, T.DIM, r2)
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


static func _date(iso: String) -> String:
	if iso.length() < 10:
		return "—"
	return "%d %s %s" % [iso.substr(8, 2).to_int(), MONTHS[clampi(iso.substr(5, 2).to_int() - 1, 0, 11)], iso.substr(0, 4)]


func _section(title: String, right := "") -> VBoxContainer:
	var c := W.card(_col)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	c.add_child(h)
	var t := W.label(title, 18, T.TEXT, h)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if right != "":
		var r := W.label(right, 13, T.DIM, h)
		r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return c


func _kv(parent: Control, key: String, value: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	parent.add_child(h)
	var k := W.label(key, 15, T.DIM, h)
	k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var v := W.label(value, 15, T.TEXT, h)
	v.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## Bandeau de chiffres clés : version · taille · date · plateformes.
func _stats(a: Dictionary) -> void:
	var tag := Catalog.tag(a)
	if tag == "":
		return
	var plats := PackedStringArray()
	if not a.asset.is_empty():
		plats.append("Linux")
	if not Catalog.pick_apk(a.release).is_empty():
		plats.append("Android")
	var cells: Array = [
		[tag, "Version"],
		[ctx.fmt_size(float(a.asset.get("size", 0))) if not a.asset.is_empty() else "—", "Taille"],
		[_date(Catalog.published(a)).left(-5) if Catalog.published(a).length() >= 10 else "—", "Publiée"],
		[" · ".join(plats) if not plats.is_empty() else "—", "Plateformes"],
	]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", T.style(T.CARD, 24, 12))
	_main.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	for i in cells.size():
		if i > 0:
			var sep := ColorRect.new()
			sep.color = Color(1, 1, 1, 0.07)
			sep.custom_minimum_size = Vector2(1, 0)
			row.add_child(sep)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.size_flags_stretch_ratio = 1.0
		v.custom_minimum_size = Vector2(40, 0)
		v.add_theme_constant_override("separation", 2)
		row.add_child(v)
		var val := W.label(str(cells[i][0]), 15, T.TEXT, v)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var cap := W.label(str(cells[i][1]), 12, T.DIM, v)
		cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.autowrap_mode = TextServer.AUTOWRAP_OFF


func _about(a: Dictionary) -> void:
	var desc := str(a.manifest.get("description", ""))
	if desc == "":
		return
	var c := _section("À propos")
	W.label(desc, 15, T.DIM, c)


func _notes(a: Dictionary, status: String) -> void:
	var notes := Catalog.clean_notes(str(a.release.get("body", "")))
	if notes == "" or status == "update":
		return
	var c := _section("Nouveautés", "%s · %s" % [Catalog.tag(a), _date(Catalog.published(a))])
	W.label(notes, 15, T.DIM, c)


func _info(a: Dictionary, inst: Dictionary) -> void:
	var tag := Catalog.tag(a)
	var c := _section("Informations")
	_kv(c, "Dépôt", "%s/%s" % [a.org, a.name])
	if tag != "":
		_kv(c, "Dernière version", tag)
	if not inst.is_empty():
		_kv(c, "Version installée", str(inst.get("tag", "?")))
	if not a.asset.is_empty():
		_kv(c, "Taille du téléchargement", ctx.fmt_size(float(a.asset.get("size", 0))))
	var dl := 0
	for x in a.release.get("assets", []):
		dl += int(x.get("download_count", 0))
	if dl > 0:
		_kv(c, "Téléchargements", str(dl))
	var lic := str(a.repo.get("license", ""))
	if lic != "" and lic != "NOASSERTION":
		_kv(c, "Licence", lic)
	if int(a.repo.get("stars", 0)) > 0:
		_kv(c, "Étoiles", str(int(a.repo.stars)))
	var pushed := str(a.repo.get("pushed_at", ""))
	if pushed != "":
		_kv(c, "Code mis à jour", _date(pushed))


## Historique des versions (dernières releases), chargé une fois par app.
func _history(a: Dictionary) -> void:
	var c := _section("Versions")
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	c.add_child(box)
	if _hist.has(a.name):
		_fill_history(a, c, box, _hist[a.name])
		return
	var sk := W.Skeleton.new()
	sk.custom_minimum_size = Vector2(0, 44)
	box.add_child(sk)
	var r: Array = await ctx.catalog.get_json("%s/repos/%s/%s/releases?per_page=6" % [Catalog.API, a.org, a.name])
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	if r[0] != 200 or not (r[1] is Array):
		c.get_parent().queue_free()
		return
	var list: Array = []
	for rel in r[1]:
		list.append({"tag": str(rel.get("tag_name", "")), "date": str(rel.get("published_at", "")),
				"body": str(rel.get("body", ""))})
	_hist[a.name] = list
	_fill_history(a, c, box, list)


func _fill_history(a: Dictionary, c: Control, box: VBoxContainer, list: Array) -> void:
	for ch in box.get_children():
		ch.queue_free()
	if list.size() < 2:
		c.get_parent().queue_free()  # une seule version : rien à historiser
		return
	var inst_tag := str(ctx.store.installed.get(a.name, {}).get("tag", ""))
	for i in list.size():
		var e: Dictionary = list[i]
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		box.add_child(h)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", 1)
		h.add_child(left)
		var tl := W.label(e.tag, 15, T.TEXT, left)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var first := Catalog.clean_notes(e.body, 80).split("\n")[0]
		if first != "":
			var nl := W.label(first, 13, T.DIM, left)
			nl.autowrap_mode = TextServer.AUTOWRAP_OFF
			nl.clip_text = true
		var rv := VBoxContainer.new()
		rv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rv.alignment = BoxContainer.ALIGNMENT_CENTER
		h.add_child(rv)
		var d := W.label(_date(e.date), 13, T.DIM, rv)
		d.autowrap_mode = TextServer.AUTOWRAP_OFF
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if e.tag == inst_tag:
			W.pill(rv, "installée", T.OK)
		elif i == 0:
			W.pill(rv, "dernière", T.DIM)


func _main_button(a: Dictionary, status: String) -> Control:
	var b := W.Btn.new("", "primary")
	b.custom_minimum_size = Vector2(0, 52)
	b.add_theme_font_size_override("font_size", 17)
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
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	var qc := W.card(_col)
	W.label("Téléphone", 18, T.TEXT, qc)
	var qr_url := str(apk.browser_download_url)
	var qt: Texture2D = QR.texture(qr_url, 6)
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 16)
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
		tr.custom_minimum_size = Vector2(144, 144)
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
	var shc := _section("Aperçu")
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 250)
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shc.add_child(sc)
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
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if tex.get_height() < 200 else CanvasItem.TEXTURE_FILTER_LINEAR
		tr.custom_minimum_size = Vector2(240.0 * tex.get_width() / maxf(1.0, tex.get_height()), 240)
		row.add_child(tr)
