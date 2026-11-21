extends PanelContainer
## Boutons rapides sous le nœud de chat sélectionné : Répondre, Branche ici, Régénérer (nouveau frère), Ranger, Stop.

const T := preload("res://ui/theme.gd")
const Chat := preload("res://ui/draw/chat.gd")

var board: Node
var b_reply: Button
var b_fork: Button
var b_regen: Button
var b_tidy: Button
var b_stop: Button


func setup(b: Node) -> void:
	board = b
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = T.CARD
	st.border_color = Color(1, 1, 1, 0.14)
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	st.set_content_margin_all(4)
	add_theme_stylebox_override("panel", st)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	add_child(h)
	b_reply = _btn(h, "↩ Répondre", "Répondre à ce message : il devient le parent du tien (Entrée)", func(): board.chat_reply(_id()))
	b_fork = _btn(h, "⑂ Branche ici", "Nouvelle branche depuis ce nœud, à côté des réponses existantes", func(): board.chat_reply(_id(), true))
	b_regen = _btn(h, "↻ Régénérer", "Nouvelle réponse de l'IA (nouveau nœud frère)", func(): board.chat_regen(_id()))
	b_tidy = _btn(h, "⇅ Ranger", "Range la conversation : enfants côte à côte, sans chevauchement", func(): board.chat_tidy())
	b_stop = _btn(h, "■ Stop", "Arrête la réponse en cours", func(): board.chat_stop(_id()))


func _btn(parent: Control, txt: String, tip: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 12)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _id() -> String:
	var sel: Array = board.scene.selected()
	return str(sel[0].id) if sel.size() == 1 and Chat.is_msg(sel[0]) else ""


func _process(_dt: float) -> void:
	var cv: Control = board.canvas
	var id := _id()
	if id == "" or cv.is_editing():
		visible = false
		return
	var el: Dictionary = board.scene.get_el(id)
	var busy: bool = board.chat_busy(id)
	b_stop.visible = busy
	b_regen.visible = not busy
	b_regen.text = "↻ Régénérer" if str(el.role) == "assistant" else "↻ Faire répondre"
	b_regen.disabled = str(el.role) == "assistant" and Chat.parent_of(board.scene, el).is_empty()
	size = get_combined_minimum_size()
	var r := Rect2(cv.w2c(Vector2(float(el.x), float(el.y))), Vector2(float(el.w), float(el.h)) * cv.zoom)
	var view := Rect2(Vector2.ZERO, cv.size)
	if not r.intersects(view):
		visible = false
		return
	var x := clampf(r.get_center().x - size.x * 0.5, 8.0, maxf(cv.size.x - size.x - 8.0, 8.0))
	var y := r.end.y + 8.0
	if y + size.y > cv.size.y - 70.0:  # trop bas (barre de saisie) : au-dessus du nœud
		y = r.position.y - size.y - 8.0
	position = Vector2(x, clampf(y, 64.0, maxf(cv.size.y - size.y - 8.0, 64.0)))
	visible = true
