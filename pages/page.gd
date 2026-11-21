extends "res://kit/layout/k_page.gd"
## Base commune des pages : en-tête fixe (retour, titre, actions) + contenu défilant centré.
## Les pages surchargent build() ; rebuild() reconstruit le contenu après un changement de données.

const Ctx := preload("res://core/ctx.gd")
const Catalog := preload("res://core/catalog.gd")
const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")
const K := preload("res://kit/k.gd")
const Tk := preload("res://kit/tokens.gd")

var ctx: Ctx
var router: Control
var args := {}
var page_id := ""
var max_w := 960.0
var caps := {}
var extra_containers: Array = []
var page_title := ""  # titre de fenêtre (vide = accueil)


func _ready() -> void:
	build_shell()
	back_pressed.connect(func(): router.back())
	_fit_width()
	head_title.text = page_title
	build()


func _fit_width() -> void:
	caps = {"xs": 100000, "sm": 100000, "md": minf(720.0, max_w), "lg": max_w, "xl": max_w}
	_hc.max_widths = caps
	_bc.max_widths = caps
	for c in extra_containers:
		if is_instance_valid(c):
			c.max_widths = caps


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
