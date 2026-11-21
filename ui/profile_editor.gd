extends VBoxContainer
## Choix du pseudo et de la mascotte (variante parmi 8). Enregistre au fil de l'eau dans le profil partagé.

signal changed

const Ctx := preload("res://core/ctx.gd")
const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")

var ctx: Ctx
var preview: W.Avatar
var pickers: Array = []
var edit: LineEdit
var avatar := 0


func _ready() -> void:
	avatar = ctx.store.avatar
	add_theme_constant_override("separation", 16)
	preview = W.Avatar.new()
	preview.custom_minimum_size = Vector2(130, 130)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(preview)
	var pick := HFlowContainer.new()
	pick.alignment = FlowContainer.ALIGNMENT_CENTER
	pick.add_theme_constant_override("h_separation", 10)
	pick.add_theme_constant_override("v_separation", 10)
	add_child(pick)
	for i in W.Avatar.BODIES.size():
		var av := W.Avatar.new(true)
		av.variant = i
		av.custom_minimum_size = Vector2(60, 60)
		av.pressed.connect(func(): _pick(i))
		pick.add_child(av)
		pickers.append(av)
	edit = LineEdit.new()
	edit.placeholder_text = "Ton pseudo"
	edit.max_length = 24
	edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit.add_theme_font_size_override("font_size", 22)
	edit.custom_minimum_size = Vector2(300, 54)
	edit.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	edit.text = ctx.store.pseudo
	edit.text_submitted.connect(func(_t: String): commit())
	edit.focus_exited.connect(commit)
	add_child(edit)
	tree_exiting.connect(commit)
	_refresh()


func _pick(i: int) -> void:
	avatar = i
	_refresh()
	commit()


func _refresh() -> void:
	preview.variant = avatar
	for i in pickers.size():
		pickers[i].selected = i == avatar


func commit() -> void:
	if ctx == null:
		return
	ctx.set_profile(edit.text, avatar)
	if edit.text.strip_edges() == "":
		edit.text = ctx.store.pseudo
	changed.emit()
