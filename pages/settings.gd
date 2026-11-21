extends "res://pages/page.gd"
## Paramètres : vérification automatique, dossier d'installation, cache.

var _confirm_cache := false
var _last_lbl: Label
var _cache_lbl: Label


func _init() -> void:
	page_title = "Paramètres"


func build() -> void:
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
	var pe := LineEdit.new()
	pe.text = ctx.store.apps_dir()
	pe.add_theme_font_size_override("font_size", 14)
	c2.add_child(pe)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	c2.add_child(pr)
	var open := W.Btn.new("Ouvrir le dossier", "soft")
	open.custom_minimum_size = Vector2(0, 44)
	open.pressed.connect(_open_dir)
	pr.add_child(open)
	var def := W.Btn.new("Par défaut", "ghost")
	def.custom_minimum_size = Vector2(0, 44)
	def.pressed.connect(func():
		ctx.store.set_s("install", "dir", "")
		pe.text = ctx.store.apps_dir()
		ctx.notify("Dossier par défaut rétabli"))
	pr.add_child(def)
	var apply := func():
		var p := pe.text.strip_edges()
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
	pe.focus_exited.connect(func(): apply.call())

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
	var c4 := W.card(body, 8)
	var row := W.Row.new()
	row.pressed.connect(func(): router.push("about"))
	c4.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
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
