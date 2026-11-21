extends "res://pages/page.gd"
## Bienvenue (premier lancement) : 2 écrans — accueil, puis pseudo + mascotte.

const Editor := preload("res://ui/profile_editor.gd")

var step := 0
var _box: VBoxContainer
var _editor: Editor


func _init() -> void:
	has_back = false
	page_title = ""


func build() -> void:
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 18)
	body.add_child(_box)
	_show_step(0, true)


func _show_step(n: int, instant := false) -> void:
	step = n
	if not instant and not router.instant:
		var tw := create_tween()
		tw.tween_property(_box, "modulate:a", 0.0, 0.12)
		await tw.finished
	for c in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	if n == 0:
		_step_hello()
	else:
		_step_profile()
	if not instant and not router.instant:
		var tw2 := create_tween()
		tw2.tween_property(_box, "modulate:a", 1.0, 0.2)


func _step_hello() -> void:
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 24)
	_box.add_child(gap)
	var sv := W.StateView.new("happy", ctx.store.avatar, "Bienvenue sur Goodview", "Toutes tes apps Goodview, au même endroit.", "", 240)
	_box.add_child(sv)
	var b := W.Btn.new("Commencer", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(260, 56)
	b.pressed.connect(func(): _show_step(1))
	_box.add_child(b)


func _step_profile() -> void:
	var t := W.label("Qui es-tu ?", 26, T.TEXT, _box)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_editor = Editor.new()
	_editor.ctx = ctx
	_box.add_child(_editor)
	var b := W.Btn.new("Terminer", "primary")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size = Vector2(260, 56)
	b.pressed.connect(finish)
	_box.add_child(b)


## Enregistre le profil et ouvre l'accueil.
func finish() -> void:
	if _editor != null:
		_editor.commit()
	ctx.store.welcomed = true
	ctx.store.save_cfg()
	router.reset("home")


func on_back() -> bool:
	if step == 1:
		_show_step(0)
		return true
	return true  # pas de retour depuis la bienvenue
