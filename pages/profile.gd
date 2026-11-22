extends "res://pages/page.gd"
## Profil (onglet) : pseudo + mascotte, partagés avec toutes les apps Goodview via ~/.config/goodview/profile.json.

const Editor := preload("res://ui/profile_editor.gd")


func _init() -> void:
	page_title = "Profil"
	has_back = false


func build() -> void:
	head_title.text = "Profil"
	var gear := W.IconBtn.new("gear", 44)
	gear.tooltip_text = "Paramètres"
	gear.pressed.connect(func(): router.push("settings"))
	head_right.add_child(gear)
	var ed := Editor.new()
	ed.ctx = ctx
	body.add_child(ed)


func on_back() -> bool:
	for c in body.get_children():
		if c.has_method("commit"):
			c.commit()
	return false
