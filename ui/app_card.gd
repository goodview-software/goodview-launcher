extends PanelContainer
## Carte d'app de la grille : grande icône, nom, accroche, pastille d'état, étoile favori, bouton « Voir l'app ».
## Toute la carte est cliquable (survol / pression uniformes).

signal pressed
signal fav_toggled

const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")

var sb := T.style(T.CARD, 26, 16)
var hot := false
var down := false


func _init() -> void:
	add_theme_stylebox_override("panel", sb)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func(): _paint(true, down))
	mouse_exited.connect(func(): _paint(false, false))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _paint(h: bool, d: bool) -> void:
	hot = h
	down = d
	sb.bg_color = T.CARD_HI.lightened(0.04) if d else (T.CARD_HI if h else T.CARD)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_paint(hot, true)
		else:
			var fire := down and Rect2(Vector2.ZERO, size).has_point(e.position)
			_paint(hot, false)
			if fire:
				pressed.emit()
		accept_event()


## Remplit la carte. icon : Control (AppIcon) déjà créé ; status : [texte, couleur].
func setup(icon: Control, title: String, tagline: String, status: Array, fav: bool) -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(36, 36)
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	W.spacer(top)
	var st := W.IconBtn.new("star_on" if fav else "star", 36)
	st.col = T.WARN if fav else Color(T.DIM, 0.6)
	st.tooltip_text = "Retirer des favoris" if fav else "Ajouter aux favoris"
	st.pressed.connect(func(): fav_toggled.emit())
	top.add_child(st)
	icon.custom_minimum_size = Vector2(0, 88)
	icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(icon)
	var nm := W.label(title, 19, T.TEXT, v)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.autowrap_mode = TextServer.AUTOWRAP_OFF
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tl := W.label(tagline, 13, T.DIM, v)
	tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tl.max_lines_visible = 2
	tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tl.custom_minimum_size = Vector2(0, 36)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pr := HBoxContainer.new()
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pr)
	W.pill(pr, status[0], status[1])
	var b := W.Btn.new("Voir l'app", "primary")
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(func(): pressed.emit())
	v.add_child(b)


## Carte fantôme pour l'état de chargement.
class Ghost extends Control:
	var t := 0.0

	func _init(i := 0) -> void:
		t = i * 0.6
		custom_minimum_size = Vector2(0, 300)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		t += d * 3.0
		queue_redraw()

	func _draw() -> void:
		var a := 0.05 + 0.03 * sin(t)
		W.Ico.box(self, Rect2(Vector2.ZERO, size), 26, T.CARD)
		var cx := size.x / 2.0
		W.Ico.box(self, Rect2(cx - 40, 56, 80, 80), 20, Color(1, 1, 1, a))
		W.Ico.box(self, Rect2(cx - 50, 156, 100, 14), 7, Color(1, 1, 1, a))
		W.Ico.box(self, Rect2(cx - 70, 182, 140, 10), 5, Color(1, 1, 1, a * 0.7))
		W.Ico.box(self, Rect2(16, size.y - 58, size.x - 32, 42), 21, Color(1, 1, 1, a * 0.8))
