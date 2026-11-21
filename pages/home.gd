extends "res://pages/page.gd"
## Apps : panneau sobre (titre, nombre, tout mettre à jour, recherche, tri, vérifier, état du catalogue)
## + grille d'apps à 2 colonnes. Écran large : panneau à gauche, grille à droite ; écran étroit : une colonne.

const AppCard := preload("res://ui/app_card.gd")
const U := preload("res://ui/universe.gd")
const SORTS := [["recent", "Récents"], ["az", "A–Z"], ["updates", "Mises à jour"]]
const SEARCH_MIN := 6  # la recherche apparaît au-delà de ce nombre d'apps
const WIDE_MIN := 900.0  # largeur de page à partir de laquelle le panneau passe à gauche

var _chk: W.IconBtn
var _chk_btn: W.Btn
var _banner: VBoxContainer
var _count: Label
var _sub: Label
var _actions: VBoxContainer
var _search: Control
var _seg: W.Seg
var _list: VBoxContainer
var _prog: Control
var _prog_lbl: Label
var query := ""
var sort_mode := "recent"
var force_wide := -1  # -1 auto, 0 une colonne, 1 deux colonnes (tests)
var _wide := false


func _init() -> void:
	has_back = false
	max_w = 1120.0


func set_wide(_v: bool) -> void:
	pass  # la mise en page suit la largeur (KSplit / KAdaptiveGrid)


func build() -> void:
	set_title("Goodview")
	sort_mode = str(ctx.store.get_s("ui", "sort", "recent"))
	var gear := W.IconBtn.new("gear", 44)
	gear.tooltip_text = "Paramètres"
	gear.pressed.connect(func(): router.push("settings"))
	head_right.add_child(gear)

	var lay: Container = K.Split.new()
	lay.side_first = true
	lay.side_width = 290
	lay.wide_at = 760
	body.add_child(lay)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", Tk.S3)
	lay.add_child(side)
	var tr := HBoxContainer.new()
	tr.add_theme_constant_override("separation", Tk.S3)
	side.add_child(tr)
	var tcol := VBoxContainer.new()
	tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tcol.add_theme_constant_override("separation", 0)
	tr.add_child(tcol)
	W.label("Apps", 30, T.TEXT, tcol)
	_count = W.label("", 14, T.DIM, tcol)
	_chk = W.IconBtn.new("refresh", 44)
	_chk.tooltip_text = "Vérifier les mises à jour"
	_chk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_chk.pressed.connect(_on_check)
	tr.add_child(_chk)
	_sub = W.label("", 13, T.DIM, side)
	_banner = VBoxContainer.new()
	side.add_child(_banner)
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", Tk.S2)
	side.add_child(_actions)
	_search = K.InputField.new()
	_search.label_text = "Rechercher"
	_search.icon = "search"
	_search.text_changed.connect(func(t: String):
		query = t.strip_edges().to_lower()
		_render_list())
	side.add_child(_search)
	_seg = W.Seg.new(SORTS, sort_mode)
	_seg.changed.connect(func(id: String):
		sort_mode = id
		ctx.store.set_s("ui", "sort", id)
		_render_list())
	side.add_child(_seg)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 0)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lay.add_child(_list)
	_search.ready.connect(func(): _search.set_text(query))

	link(ctx.catalog.changed, _render)
	link(ctx.installer.changed, _render)
	link(ctx.installer.progress, _on_progress)
	link(ctx.updater.changed, _render)
	link(ctx.profile_changed, _render)
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
	if not is_inside_tree() or _list == null or not is_instance_valid(_list):
		return
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
	p.add_theme_stylebox_override("panel", T.style(Color(T.OK, 0.12), Tk.R_XL, Tk.S4))
	_banner.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", Tk.S2)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", Tk.S3)
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
		b.pressed.connect(func():
			if u.state == "ready":
				u.restart()
			else:
				u.download())
		h.add_child(b)
	if u.state == "downloading":
		var pb: Control = K.Progress.new()
		pb.value = u.ratio
		v.add_child(pb)
	elif u.notes != "":
		W.label(u.notes.left(260) + ("…" if u.notes.length() > 260 else ""), 13, T.DIM, v)


func _render_status() -> void:
	var cat := ctx.catalog
	var n := cat.apps.size()
	_count.text = "Chargement…" if cat.state == "loading" and n == 0 else "%d app%s" % [n, "s" if n > 1 else ""]
	_sub.text = ""
	_sub.add_theme_color_override("font_color", T.DIM)
	if cat.state == "loading" and n == 0:
		return
	if not cat.online:
		if cat.rate_reset > Time.get_unix_time_from_system():
			_sub.text = "Limite GitHub · réessaie dans %d min" % maxi(1, int(ceil((cat.rate_reset - Time.get_unix_time_from_system()) / 60.0)))
		else:
			_sub.text = ("Hors ligne · vérifié " + ctx.ago(cat.last_check)) if cat.last_check > 0.0 else "Hors ligne"
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
		h.add_theme_constant_override("separation", Tk.S3)
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
		_prog = K.Progress.new()
		_prog.value = ins.ratio
		c.add_child(_prog)
		return
	var ups := ctx.updates()
	if ups.size() > 0:
		var b := W.Btn.new("Tout mettre à jour (%d)" % ups.size(), "primary")
		b.pressed.connect(func():
			for a in ctx.updates():
				ins.enqueue(a))
		_actions.add_child(b)


func _on_progress(r: float) -> void:
	if _prog != null and is_instance_valid(_prog):
		_prog.value = r
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
	if _list == null or not is_instance_valid(_list):
		return
	_clear(_list)
	_list.add_child(_assistant_grid())
	var cat := ctx.catalog
	var n := cat.apps.size()
	_seg.visible = n > 1
	_search.visible = n > SEARCH_MIN
	if n <= SEARCH_MIN and query != "":
		query = ""
	_seg.select(sort_mode)
	if n == 0:
		match cat.state:
			"loading":
				var g := _grid()
				for i in 4:
					g.add_child(AppCard.Ghost.new(i))
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
	var g2 := _grid()
	for a in apps:
		g2.add_child(_card(a))


## Autocollant (image fixe, non animée) + second autocollant avec le nom en dessous.
class Sticker extends Control:
	var variant := 0
	var label := ""

	func _init(v := 0, nm := "") -> void:
		variant = v
		label = nm
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(0, 124)

	func _sticker(rect: Rect2, rot: float, fill: Color) -> void:
		var c := rect.get_center()
		draw_set_transform(c, rot, Vector2.ONE)
		var r := Rect2(-rect.size * 0.5, rect.size)
		draw_rect(Rect2(r.position + Vector2(3, 4), r.size), Color(0, 0, 0, 0.4))
		draw_rect(r.grow(3), Color("f4f1e8"))
		draw_rect(r, fill)

	func _draw() -> void:
		var col: Color = U.color(variant)
		var cx := floorf(size.x * 0.5)
		var pic := Rect2(cx - 40, 6, 80, 80)
		_sticker(pic, -0.06, T.BG.lerp(col, 0.35))
		var c := pic.get_center()
		draw_set_transform(c, -0.06, Vector2.ONE)
		var row: int = W.Orb.ANIMS["idle"][0] + variant * 5
		draw_texture_rect_region(W.Orb.SHEET, Rect2(-32, -32, 64, 64), Rect2(0, row * 32, 32, 32))
		var nm := Rect2(cx - 46, 96, 92, 20)
		_sticker(nm, 0.04, Color("f4f1e8"))
		draw_set_transform(nm.get_center(), 0.04, Vector2.ONE)
		var font := get_theme_default_font()
		draw_string(font, Vector2(-44, 4), label.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, 88, 12, Color("1a1d24"))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Sous-apps intégrées : Assistant IA (plan 2D de zones) et Chat rapide (conversation classique).
func _assistant_grid() -> Control:
	var g: Container = K.Grid.new()
	g.min_card_width = 220
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var c := AppCard.new()
	c.btn_text = "Ouvrir"
	c.setup(Sticker.new(ctx.active, "Assistant IA"), "", "Un plan 2D : des zones pour discuter avec l'IA, reliées par des fils.", ["Intégré", T.OK], false, false)
	c.pressed.connect(func(): router.push("board"))
	g.add_child(c)
	var c2 := AppCard.new()
	c2.btn_text = "Ouvrir"
	c2.setup(Sticker.new((ctx.active + 3) % U.count(), "Chat rapide"), "", "Une conversation directe avec %s et 7 autres assistants locaux." % U.get_u(ctx.active).name, ["Intégré", T.OK], false, false)
	c2.pressed.connect(func(): router.go_tab("chat"))
	g.add_child(c2)
	return g


func _grid() -> Container:
	var g: Container = K.Grid.new()
	g.min_card_width = 220
	g.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_child(g)
	return g


func _state_view(anim: String, title: String, msg: String, retry: bool) -> void:
	var sv := W.StateView.new(anim, ctx.active, title, msg, "Réessayer" if retry else "", 170)
	sv.action.connect(func(): ctx.catalog.refresh())
	_list.add_child(sv)


func _card(a: Dictionary) -> Control:
	var c := AppCard.new()
	c.setup(app_icon(a, 88, false), Catalog.title(a), Catalog.tagline(a), status_pill(a), ctx.store.is_fav(a.name))
	c.pressed.connect(func(): router.push("app", {"name": a.name}))
	c.fav_toggled.connect(func():
		ctx.store.toggle_fav(a.name)
		_render_list())
	return c
