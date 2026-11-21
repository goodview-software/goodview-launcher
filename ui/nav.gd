extends Control
## Barre de navigation basse : Apps | Chat (au centre, mis en avant avec la mascotte) | Profil.

signal tab(id: String)

const T := preload("res://ui/theme.gd")
const Ico := preload("res://ui/icons.gd")
const U := preload("res://ui/universe.gd")
const Orb := preload("res://ui/widgets.gd").Orb
const HEIGHT := 68.0
const TABS := [["home", "Apps", "apps"], ["chat", "Chat", "chat"], ["profile", "Profil", "user"]]

var current := "chat"
var badge := false
var variant := 0  # mascotte du bouton central
var hot := -1
var t := 0.0
var _pop := 0.0


func _init() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_STOP


func select(id: String) -> void:
	if id != current:
		current = id
		_pop = 1.0
		queue_redraw()


func _process(d: float) -> void:
	t += d * 3.0
	_pop = move_toward(_pop, 0.0, d * 4.0)
	queue_redraw()


func _slot(x: float) -> int:
	return clampi(int(x / (size.x / 3.0)), 0, 2)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion:
		hot = _slot(e.position.x)
	elif e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed:
		var i := _slot(e.position.x)
		if Rect2(Vector2.ZERO, size).has_point(e.position):
			tab.emit(TABS[i][0])
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hot = -1


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), T.CARD)
	draw_rect(Rect2(0, 0, size.x, 1), Color(1, 1, 1, 0.05))
	var font := get_theme_default_font()
	var w := size.x / 3.0
	for i in 3:
		var on: bool = TABS[i][0] == current
		var cx := w * (i + 0.5)
		var col := T.OK if on else (T.TEXT if hot == i else T.DIM)
		if i == 1:
			var c := Vector2(cx, 26.0 - 7.0 * (0.0 if not on else 1.0) - _pop * 3.0)
			var r := 27.0
			for k in 2:
				draw_circle(c, r + 4.0 + k * 5.0, Color(T.OK, (0.14 - k * 0.06) * (1.0 if on else 0.6)))
			draw_circle(c, r, T.OK if on else T.OK.darkened(0.55))
			draw_circle(c, r - 3.0, T.CARD_HI if not on else T.OK.darkened(0.62))
			var f := int(t) % 4
			draw_texture_rect_region(Orb.SHEET, Rect2((c - Vector2(16, 16) + Vector2(0, -2)).round(), Vector2(32, 32)),
					Rect2(f * 32, (0 + variant * 5) * 32, 32, 32))
		else:
			Ico.draw_kind(self, TABS[i][2], Vector2(cx, 26), 0.62 * (1.0 + (_pop * 0.15 if on else 0.0)), col)
			if i == 0 and badge:
				draw_circle(Vector2(cx + 13, 14), 5.0, T.CARD)
				draw_circle(Vector2(cx + 13, 14), 3.6, T.WARN)
		var lab: String = TABS[i][1]
		var tw := font.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		if i == 1 and on:
			pass
		draw_string(font, Vector2(cx - tw / 2.0, 58), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
