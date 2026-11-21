extends Control
## Base commune des pages : en-tête fixe (retour, titre, actions) + contenu défilant centré.
## Les pages surchargent build() ; rebuild() reconstruit le contenu après un changement de données.

const Ctx := preload("res://core/ctx.gd")
const Catalog := preload("res://core/catalog.gd")
const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")

var ctx: Ctx
var router: Control
var args := {}
var page_id := ""
var max_w := T.MAX_WIDTH
var _outer: VBoxContainer
var page_title := ""  # titre de fenêtre (vide = accueil)
var has_back := true
var head: HBoxContainer
var head_title: Label
var head_right: HBoxContainer
var body: VBoxContainer
var scroll: ScrollContainer
var _center: CenterContainer


func _ready() -> void:
	var outer := VBoxContainer.new()
	_outer = outer
	outer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("separation", 10)
	add_child(outer)
	var hm := MarginContainer.new()
	hm.add_theme_constant_override("margin_left", 18)
	hm.add_theme_constant_override("margin_right", 18)
	hm.add_theme_constant_override("margin_top", 16)
	outer.add_child(hm)
	var hc := CenterContainer.new()
	hm.add_child(hc)
	head = HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	hc.add_child(head)
	if has_back:
		var b := W.IconBtn.new("back", 44)
		b.tooltip_text = "Retour"
		b.pressed.connect(func(): router.back())
		head.add_child(b)
	head_title = W.label("", 20, T.TEXT, head)
	head_title.autowrap_mode = TextServer.AUTOWRAP_OFF
	head_title.clip_text = true
	head_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if has_back else HORIZONTAL_ALIGNMENT_LEFT
	head_right = HBoxContainer.new()
	head_right.add_theme_constant_override("separation", 10)
	head.add_child(head_right)

	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(scroll)
	var sm := MarginContainer.new()
	sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sm.add_theme_constant_override("margin_left", 18)
	sm.add_theme_constant_override("margin_right", 18)
	sm.add_theme_constant_override("margin_top", 6)
	sm.add_theme_constant_override("margin_bottom", 28)
	scroll.add_child(sm)
	_center = CenterContainer.new()
	_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sm.add_child(_center)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	_center.add_child(body)
	get_viewport().size_changed.connect(_fit_width)
	resized.connect(_fit_width)
	_fit_width()
	head_title.text = page_title
	build()


func _fit_width() -> void:
	if body == null:
		return
	var w := clampf(size.x - 36.0 if size.x > 0.0 else get_viewport_rect().size.x - 36.0, 300.0, max_w)
	body.custom_minimum_size.x = w
	head.custom_minimum_size.x = w


func set_title(t: String) -> void:
	page_title = t
	if head_title != null:
		head_title.text = t


## Vide le contenu (suppression immédiate pour éviter les doublons) puis le reconstruit.
func rebuild() -> void:
	for c in head_right.get_children():
		head_right.remove_child(c)
		c.queue_free()
	for c in body.get_children():
		body.remove_child(c)
		c.queue_free()
	build()


## Changement de charte (univers) : reconstruit la page avec les nouvelles couleurs.
func retheme() -> void:
	if body != null:
		rebuild()


## Connecte un signal une seule fois (les pages se reconstruisent sans empiler les connexions).
func link(sig: Signal, cb: Callable) -> void:
	if not sig.is_connected(cb):
		sig.connect(cb)


## À surcharger : remplit `body`.
func build() -> void:
	pass


## Appelée quand on revient sur cette page (retour de navigation).
func on_show() -> void:
	pass


## Retour : renvoie true si la page l'a consommé.
func on_back() -> bool:
	return false


## Texte et couleur de la pastille d'état d'une app.
func status_pill(a: Dictionary) -> Array:
	if ctx.installer.is_queued(a.name):
		return ["Installation…" if ctx.installer.current.get("name", "") == a.name else "En attente", T.OK]
	match ctx.app_status(a):
		"soon":
			return ["Bientôt", T.DIM]
		"ok":
			return ["Installée", T.OK]
		"update":
			return ["Mise à jour", T.WARN]
	return [Catalog.tag(a), T.DIM]


## Icône d'une app (image du repo ou lettre colorée) ; pastille si mise à jour disponible.
func app_icon(a: Dictionary, px: int, halo: bool) -> W.AppIcon:
	var ic := W.AppIcon.new()
	ic.custom_minimum_size = Vector2(px, px)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.tex = a.get("icon")
	ic.letter = str(a.name).substr(0, 1).to_upper()
	ic.tint = Color.from_hsv(float(str(a.name).hash() % 360) / 360.0, 0.55, 0.9)
	ic.halo = halo
	if ctx.app_status(a) == "update":
		ic.badge = T.WARN
	return ic
