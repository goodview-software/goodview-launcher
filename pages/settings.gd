extends "res://pages/page.gd"

const QR := preload("res://qr.gd")
const APK_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest/download/GoodviewLauncher.apk"
## Paramètres : vérification automatique, dossier d'installation, cache.

var _confirm_cache := false
var _last_lbl: Label
var _cache_lbl: Label


func _init() -> void:
	page_title = "Paramètres"


func build() -> void:
	# --- Démarrage et assistants
	var c0 := W.card(body)
	W.label("Assistants", 18, T.TEXT, c0)
	var r0 := W.setting_row(c0, "Page de démarrage", "")
	var sg := W.Seg.new([["chat", "Chat"], ["home", "Apps"]], ctx.start_page())
	sg.custom_minimum_size = Vector2(190, 38)
	sg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sg.changed.connect(func(id: String): ctx.store.set_s("ui", "start", id))
	r0.add_child(sg)
	W.hsep(c0)
	var r00 := W.setting_row(c0, "Les assistants peuvent s'appeler", "Goody et les experts se posent des questions entre eux")
	var tg0 := W.Toggle.new()
	tg0.set_on(ctx.orchestra.allow)
	tg0.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tg0.toggled.connect(func(on: bool):
		ctx.orchestra.allow = on
		ctx.store.set_s("chat", "delegate", on))
	r00.add_child(tg0)
	W.hsep(c0)
	var r01 := W.setting_row(c0, "Réglages du chat", "Ollama, modèles, température, prompt")
	var b01 := W.IconBtn.new("sliders", 44)
	b01.pressed.connect(func(): router.push("chat_settings"))
	r01.add_child(b01)

	# --- Mises à jour
	var c1 := W.card(body)
	W.label("Mises à jour", 18, T.TEXT, c1)
	var r1 := W.setting_row(c1, "Vérification automatique", "Au démarrage puis toutes les 30 minutes")
	var tg := W.Toggle.new()
	tg.set_on(ctx.updater.auto_enabled())
	tg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tg.toggled.connect(func(on: bool):
		ctx.store.set_s("updates", "auto", on)
		ctx.updater.apply_settings())
	r1.add_child(tg)
	W.hsep(c1)
	var r2 := W.setting_row(c1, "Vérifier maintenant", "")
	_last_lbl = r2.get_child(0).get_child(0)
	_refresh_last()
	var chk := W.Btn.new("Vérifier", "soft")
	chk.custom_minimum_size = Vector2(0, 44)
	chk.pressed.connect(func():
		chk.disabled = true
		await ctx.updater.check_now()
		if is_instance_valid(chk):
			chk.disabled = false
			_refresh_last()
		ctx.notify("À jour" if not ctx.has_updates() else "Des mises à jour sont disponibles", "ok"))
	r2.add_child(chk)

	# --- Installation
	var c2 := W.card(body)
	W.label("Installation", 18, T.TEXT, c2)
	W.label("Dossier des apps (appliqué aux prochaines installations)", 13, T.DIM, c2)
	var pe: Control = K.InputField.new()
	pe.label_text = "Dossier"
	pe.text = ctx.store.apps_dir()
	c2.add_child(pe)
	var pr: Control = K.Row.new()
	c2.add_child(pr)
	var open := W.Btn.new("Ouvrir le dossier", "soft")
	open.pressed.connect(_open_dir)
	pr.add_child(open)
	var def := W.Btn.new("Par défaut", "ghost")
	def.pressed.connect(func():
		ctx.store.set_s("install", "dir", "")
		pe.text = ctx.store.apps_dir()
		ctx.notify("Dossier par défaut rétabli"))
	pr.add_child(def)
	var apply := func():
		var p: String = pe.text.strip_edges()
		if p == ctx.store.apps_dir():
			return
		if p == "" or DirAccess.make_dir_recursive_absolute(p) == OK:
			ctx.store.set_s("install", "dir", p)
			pe.text = ctx.store.apps_dir()
			ctx.notify("Dossier d'installation enregistré", "ok")
		else:
			pe.text = ctx.store.apps_dir()
			ctx.notify("Dossier inaccessible", "error")
	pe.text_submitted.connect(func(_t: String): apply.call())
	pe.blurred.connect(func(): apply.call())

	# --- Cache
	var c3 := W.card(body)
	W.label("Cache", 18, T.TEXT, c3)
	var r3 := W.setting_row(c3, "Catalogue et icônes", "")
	_cache_lbl = r3.get_child(0).get_child(0)
	_refresh_cache()
	var clr := W.Btn.new("Confirmer ?" if _confirm_cache else "Vider", "danger" if _confirm_cache else "soft")
	clr.custom_minimum_size = Vector2(0, 44)
	clr.pressed.connect(func():
		if not _confirm_cache:
			_confirm_cache = true
			clr.text = "Confirmer ?"
			clr.set_kind("danger")
			get_tree().create_timer(3.0).timeout.connect(func():
				if is_instance_valid(clr) and _confirm_cache:
					_confirm_cache = false
					clr.text = "Vider"
					clr.set_kind("soft"))
			return
		_confirm_cache = false
		ctx.store.clear_cache()
		clr.text = "Vider"
		clr.set_kind("soft")
		_refresh_cache()
		ctx.notify("Cache vidé", "ok"))
	r3.add_child(clr)

	# --- À propos
	# --- Launcher sur téléphone : QR code de l'APK
	var cq := W.card(body)
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 16)
	cq.add_child(qh)
	var qt: Texture2D = QR.texture(APK_URL, 6)
	if qt != null:
		var fr := PanelContainer.new()
		fr.add_theme_stylebox_override("panel", T.style(Color.WHITE, 16, 8))
		fr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		qh.add_child(fr)
		var tr := TextureRect.new()
		tr.texture = qt
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(160, 160)
		tr.tooltip_text = "Scanne avec ton téléphone"
		fr.add_child(tr)
	var qv := VBoxContainer.new()
	qv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	qv.add_theme_constant_override("separation", 12)
	qh.add_child(qv)
	W.label("Launcher sur téléphone", 18, T.TEXT, qv)
	W.label("Scanne le code pour installer l'APK Android.", 14, T.DIM, qv)
	var phb := W.Btn.new("Télécharger l'APK", "primary")
	phb.icon = "android"
	phb.tooltip_text = "Ouvrir le lien de l'APK"
	phb.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	phb.pressed.connect(func(): OS.shell_open(APK_URL))
	qv.add_child(phb)

	var c4 := W.card(body, 8)
	var row := W.Row.new()
	row.pressed.connect(func(): router.push("about"))
	c4.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var ic := Control.new()
	ic.custom_minimum_size = Vector2(30, 30)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.draw.connect(func(): W.Ico.draw_kind(ic, "info", ic.size / 2.0, 0.7, T.TEXT))
	h.add_child(ic)
	var l := W.label("À propos · v" + ctx.VERSION, 17, T.TEXT, h)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ch := Control.new()
	ch.custom_minimum_size = Vector2(22, 22)
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.draw.connect(func(): W.Ico.draw_kind(ch, "chevron", ch.size / 2.0, 0.5, T.DIM))
	h.add_child(ch)


func _refresh_last() -> void:
	_last_lbl.text = "Dernière vérification : " + ctx.ago(ctx.catalog.last_check)


func _refresh_cache() -> void:
	_cache_lbl.text = "Cache : " + ctx.fmt_size(ctx.store.cache_size())


func _open_dir() -> void:
	var d := ctx.store.apps_dir()
	DirAccess.make_dir_recursive_absolute(d)
	if ctx.store.real:
		OS.shell_open(d)
