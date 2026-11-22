extends "res://kit/ui/k_card.gd"
## Carte d'app de la grille : une ligne sobre (icône, nom, accroche, état).
## Toute la carte est cliquable (survol / pression uniformes, composant KCard interactif).

signal fav_toggled

const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")


func _init() -> void:
	super()
	interactive = true
	pad = Tokens.S4
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Remplit la carte : une ligne (icône, nom + accroche, état). Étoile seulement pour un favori.
func setup(icon: Control, title: String, tagline: String, status: Array, fav: bool, show_star := true) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", Tokens.S3)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	icon.custom_minimum_size = Vector2(56, 56)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := KS.vbox(h, 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var nm := KS.label(v, title, Tokens.FS_LG, null, 600, true)
	nm.max_lines_visible = 2
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.set_meta("k_ellipsis", true)
	var tl := KS.label(v, tagline, Tokens.FS_SM, Tokens.text_muted, 400, true)
	tl.max_lines_visible = 2
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.set_meta("k_ellipsis", true)
	var pr := HBoxContainer.new()
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(pr)
	if fav and show_star:
		var st := W.IconBtn.new("star_on", 36)
		st.col = T.WARN
		st.tooltip_text = "Retirer des favoris"
		st.pressed.connect(func(): fav_toggled.emit())
		pr.add_child(st)
	W.pill(pr, status[0], status[1])


## Carte fantôme pour l'état de chargement.
class Ghost extends "res://kit/ui/k_card.gd":
	func _init(_i := 0) -> void:
		super()
		pad = Tokens.S4
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := KS.vbox(self, Tokens.S3)
		var ic: Control = load("res://kit/ui/k_skeleton.gd").new()
		ic.custom_minimum_size = Vector2(80, 80)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		ic.radius = Tokens.R_LG
		v.add_child(ic)
		for h in [16, 12]:
			var s: Control = load("res://kit/ui/k_skeleton.gd").new()
			s.custom_minimum_size = Vector2(0, h)
			v.add_child(s)
		var bt: Control = load("res://kit/ui/k_skeleton.gd").new()
		bt.custom_minimum_size = Vector2(0, 40)
		bt.radius = Tokens.R_MD
		v.add_child(bt)
