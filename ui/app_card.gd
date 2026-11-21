extends "res://kit/ui/k_card.gd"
## Carte d'app de la grille : grande icône, nom, accroche, pastille d'état, étoile favori, bouton « Voir l'app ».
## Toute la carte est cliquable (survol / pression uniformes, composant KCard interactif).

signal fav_toggled

const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")
const Btn_ := preload("res://kit/ui/k_button.gd")


func _init() -> void:
	super()
	interactive = true
	pad = Tokens.S4
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


## Remplit la carte. icon : Control (AppIcon) déjà créé ; status : [texte, couleur].
func setup(icon: Control, title: String, tagline: String, status: Array, fav: bool) -> void:
	var v := KS.vbox(self, Tokens.S2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	KS.spacer(top)
	var st := W.IconBtn.new("star_on" if fav else "star", 44)
	st.tooltip_text = "Retirer des favoris" if fav else "Ajouter aux favoris"
	st.pressed.connect(func(): fav_toggled.emit())
	top.add_child(st)
	icon.custom_minimum_size = Vector2(0, 88)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(icon)
	var nm := KS.label(v, title, Tokens.FS_LG, null, 600, true)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var tl := KS.label(v, tagline, Tokens.FS_SM, Tokens.text_muted, 400, true)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.max_lines_visible = 2
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.set_meta("k_ellipsis", true)
	KS.spacer(v, false).size_flags_vertical = Control.SIZE_EXPAND_FILL
	var pr := HBoxContainer.new()
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pr)
	W.pill(pr, status[0], status[1])
	var b := Btn_.make("Voir l'app", "primary", "md")
	b.size_flags_horizontal = Control.SIZE_FILL
	b.pressed.connect(func(): pressed.emit())
	v.add_child(b)


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
