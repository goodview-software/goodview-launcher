extends "res://pages/page.gd"
## Accueil : bannière de mise à jour du launcher, mascotte, « Tout mettre à jour », recherche / tri, liste des apps.

const SORTS := [["recent", "Récents"], ["az", "A–Z"], ["updates", "Mises à jour"]]
const SEARCH_MIN := 6  # la recherche apparaît au-delà de ce nombre d'apps

var _chk: W.IconBtn
var _avatar: W.Avatar
var _banner: VBoxContainer
var _orb_box: VBoxContainer
var _orb: W.Orb
var _status: Label
var _sub: Label
var _actions: VBoxContainer
var _toolbar: HFlowContainer
var _search: LineEdit
var _seg: W.Seg
var _list: VBoxContainer
var _prog: ProgressBar
var _prog_lbl: Label
var query := ""
var sort_mode := "recent"


func _init() -> void:
	has_back = false


func build() -> void:
	set_title("Goodview")
	sort_mode = str(ctx.store.get_s("ui", "sort", "recent"))
	# en-tête : vérifier, paramètres, profil
	_chk = W.IconBtn.new("refresh", 44)
	_chk.tooltip_text = "Vérifier les mises à jour"
	_chk.pressed.connect(_on_check)
	head_right.add_child(_chk)
	var gear := W.IconBtn.new("gear", 44)
	gear.tooltip_text = "Paramètres"
	gear.pressed.connect(func(): router.push("settings"))
	head_right.add_child(gear)
	_avatar = W.Avatar.new(true)
	_avatar.custom_minimum_size = Vector2(44, 44)
	_avatar.tooltip_text = "Profil"
	_avatar.pressed.connect(func(): router.push("profile"))
	head_right.add_child(_avatar)

	body.add_theme_constant_override("separation", 14)
	_banner = VBoxContainer.new()
	body.add_child(_banner)
	_orb_box = VBoxContainer.new()
	_orb_box.add_theme_constant_override("separation", 6)
	body.add_child(_orb_box)
	_orb = W.Orb.new()
	_orb.custom_minimum_size = Vector2(0, 190)
	_orb_box.add_child(_orb)
	_status = W.label("", 22, T.TEXT, _orb_box)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = W.label("", 13, T.DIM, _orb_box)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 10)
	body.add_child(_actions)
	_toolbar = HFlowContainer.new()
	_toolbar.add_theme_constant_override("h_separation", 10)
	_toolbar.add_theme_constant_override("v_separation", 10)
	body.add_child(_toolbar)
	_search = LineEdit.new()
	_search.placeholder_text = "Rechercher"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(220, 40)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(t: String):
		query = t.strip_edges().to_lower()
		_render_list())
	_toolbar.add_child(_search)
	_seg = W.Seg.new(SORTS, sort_mode)
	_seg.custom_minimum_size = Vector2(SORTS.size() * 104, 40)
	_seg.changed.connect(func(id: String):
		sort_mode = id
		ctx.store.set_s("ui", "sort", id)
		_render_list())
	_toolbar.add_child(_seg)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	body.add_child(_list)

	ctx.catalog.changed.connect(_render)
	ctx.installer.changed.connect(_render)
	ctx.installer.progress.connect(_on_progress)
	ctx.updater.changed.connect(_render)
	ctx.profile_changed.connect(_render)
	_render()


func on_show() -> void:
	_render()


func _on_check() -> void:
	if ctx.catalog.state in ["offline", "error"] or ctx.catalog.apps.is_empty():
		ctx.catalog.refresh()
		return
	var ok: bool = await ctx.updater.check_now()
	if not ok:
		ctx.notify("Vérification impossible : " + ctx.catalog.error_msg, "error")
	elif ctx.has_updates():
		ctx.notify("Des mises à jour sont disponibles", "ok")
	else:
		ctx.notify("Tout est à jour", "ok")


# ------------------------------------------------------------------ Rendu

func _render() -> void:
	if not is_inside_tree() or _list == null:
		return
	_avatar.variant = ctx.store.avatar
	_avatar.badge = ctx.has_updates()
	_chk.spin = ctx.catalog.checking or ctx.catalog.busy or ctx.updater.state == "checking"
	_render_banner()
	_render_status()
	_render_actions()
	_render_list()


func _clear(box: Control) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## Bannière de mise à jour du launcher (.pck).
func _render_banner() -> void:
	_clear(_banner)
	var u := ctx.updater
	if not u.available():
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", T.style(Color(T.OK, 0.12), 22, 16))
	_banner.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	v.add_child(h)
	var txt := "Goodview Launcher %s disponible" % u.info.get("version", "")
	var btn := "Mettre à jour"
	match u.state:
		"newbin":
			btn = "Télécharger"
		"downloading":
			txt = "Téléchargement du launcher… %d %%" % int(u.ratio * 100.0)
			btn = ""
		"ready":
			txt = "Mise à jour prête"
			btn = "Redémarrer"
	var l := W.label(txt, 16, T.TEXT, h)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if btn != "":
		var b := W.Btn.new(btn, "primary")
		b.custom_minimum_size = Vector2(0, 42)
		b.pressed.connect(func():
			if u.state == "ready":
				u.restart()
			else:
				u.download())
		h.add_child(b)
	if u.state == "downloading":
		var pb := ProgressBar.new()
		pb.show_percentage = false
		pb.custom_minimum_size = Vector2(0, 8)
		pb.value = u.ratio * 100.0
		v.add_child(pb)
	elif u.notes != "":
		W.label(u.notes.left(260) + ("…" if u.notes.length() > 260 else ""), 13, T.DIM, v)


func _render_status() -> void:
	var cat := ctx.catalog
	var n := cat.apps.size()
	var showing := n > 0 or cat.state == "loading"
	_orb_box.visible = showing
	_orb.variant = ctx.store.avatar
	_sub.text = ""
	_sub.add_theme_color_override("font_color", T.DIM)
	if cat.state == "loading" and n == 0:
		_orb.anim = "wait"
		_status.text = "Chargement du catalogue…"
		return
	var upd := ctx.updates().size()
	if upd > 0:
		_orb.anim = "happy"
		_status.text = "%d mise%s à jour" % [upd, "s" if upd > 1 else ""]
	else:
		_orb.anim = "idle"
		_status.text = "%d app%s" % [n, "s" if n > 1 else ""]
	if not cat.online:
		_orb.anim = "sad" if upd == 0 else "happy"
		if cat.rate_reset > Time.get_unix_time_from_system():
			_sub.text = "Limite GitHub · réessaie dans %d min" % maxi(1, int(ceil((cat.rate_reset - Time.get_unix_time_from_system()) / 60.0)))
		else:
			_sub.text = "Hors ligne · vérifié " + ctx.ago(cat.last_check) if cat.last_check > 0.0 else "Hors ligne"
		_sub.add_theme_color_override("font_color", T.WARN)
	elif cat.last_check > 0.0:
		_sub.text = "Vérifié " + ctx.ago(cat.last_check)


func _render_actions() -> void:
	_clear(_actions)
	_prog = null
	_prog_lbl = null
	var ins := ctx.installer
	if ins.is_busy() and not ins.current.is_empty():
		var c := W.card(_actions, 14)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		c.add_child(h)
		var txt := "Installation de %s" % Catalog.title(ins.current)
		if ins.total_jobs > 1:
			txt += " · %d/%d" % [mini(ins.done_jobs + 1, ins.total_jobs), ins.total_jobs]
		var l := W.label(txt, 16, T.TEXT, h)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_prog_lbl = W.label("", 14, T.DIM, h)
		var x := W.IconBtn.new("close", 36)
		x.tooltip_text = "Annuler"
		x.pressed.connect(ins.cancel)
		h.add_child(x)
		_prog = ProgressBar.new()
		_prog.show_percentage = false
		_prog.custom_minimum_size = Vector2(0, 8)
		_prog.value = ins.ratio * 100.0
		c.add_child(_prog)
		return
	var ups := ctx.updates()
	if ups.size() > 0:
		var b := W.Btn.new("Tout mettre à jour (%d)" % ups.size(), "primary")
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(func():
			for a in ctx.updates():
				ins.enqueue(a))
		_actions.add_child(b)


func _on_progress(r: float) -> void:
	if _prog != null and is_instance_valid(_prog):
		_prog.value = r * 100.0
		_prog_lbl.text = "%d %%" % int(r * 100.0)


func _visible_apps() -> Array:
	var out: Array = ctx.catalog.apps.filter(func(a):
		if query == "":
			return true
		return (Catalog.title(a) + " " + Catalog.tagline(a) + " " + str(a.name)).to_lower().contains(query))
	out.sort_custom(_before)
	return out


func _before(a: Dictionary, b: Dictionary) -> bool:
	var fa := ctx.store.is_fav(a.name)
	var fb := ctx.store.is_fav(b.name)
	if fa != fb:
		return fa
	if sort_mode == "updates":
		var ua := ctx.app_status(a) == "update"
		var ub := ctx.app_status(b) == "update"
		if ua != ub:
			return ua
	if sort_mode == "recent":
		var pa := Catalog.published(a)
		var pb := Catalog.published(b)
		if pa != pb:
			return pa > pb
	return Catalog.title(a).to_lower() < Catalog.title(b).to_lower()


func _render_list() -> void:
	if _list == null:
		return
	_clear(_list)
	var cat := ctx.catalog
	var n := cat.apps.size()
	_toolbar.visible = n > 1
	_search.visible = n > SEARCH_MIN
	if n <= SEARCH_MIN and query != "":
		query = ""
	_seg.select(sort_mode)
	if n == 0:
		match cat.state:
			"loading":
				_list.add_child(W.Skeleton.new(4))
			"offline":
				_state_view("sad", "Hors ligne", "Vérifie ta connexion Internet, puis réessaie.", true)
			"error":
				_state_view("sad", "Oups", cat.error_msg, true)
			_:
				_state_view("off", "Aucune app pour l'instant", "Les apps Goodview publiées apparaîtront ici.", true)
		return
	var apps := _visible_apps()
	if apps.is_empty():
		_state_view("off", "Aucun résultat", "Essaie un autre mot.", false)
		return
	var group := PanelContainer.new()
	group.add_theme_stylebox_override("panel", T.style(T.CARD, 24, 8))
	_list.add_child(group)
	var lb := VBoxContainer.new()
	lb.add_theme_constant_override("separation", 0)
	group.add_child(lb)
	for i in apps.size():
		if i > 0:
			W.hsep(lb)
		lb.add_child(_row(apps[i]))


func _state_view(anim: String, title: String, msg: String, retry: bool) -> void:
	var sv := W.StateView.new(anim, ctx.store.avatar, title, msg, "Réessayer" if retry else "", 170)
	sv.action.connect(func(): ctx.catalog.refresh())
	_list.add_child(sv)


func _row(a: Dictionary) -> Control:
	var row := W.Row.new()
	row.pressed.connect(func(): router.push("app", {"name": a.name}))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	h.add_child(app_icon(a, 56, false))
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	W.label(Catalog.title(a), 18, T.TEXT, v).mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := W.label(Catalog.tagline(a), 13, T.DIM, v)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.clip_text = true
	var s := status_pill(a)
	var pb := HBoxContainer.new()
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(pb)
	W.pill(pb, s[0], s[1])
	var fav := ctx.store.is_fav(a.name)
	var st := W.IconBtn.new("star_on" if fav else "star", 36)
	st.col = T.WARN if fav else T.DIM
	st.tooltip_text = "Retirer des favoris" if fav else "Ajouter aux favoris"
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	st.pressed.connect(func():
		ctx.store.toggle_fav(a.name)
		_render_list())
	h.add_child(st)
	var ch := Control.new()
	ch.custom_minimum_size = Vector2(18, 22)
	ch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ch.draw.connect(func(): W.Ico.draw_kind(ch, "chevron", ch.size / 2.0, 0.5, T.DIM))
	h.add_child(ch)
	return row
