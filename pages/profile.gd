extends "res://pages/page.gd"
## Profil : pseudo + mascotte (partagés avec toutes les apps Goodview via ~/.config/goodview/profile.json).

const Editor := preload("res://ui/profile_editor.gd")


func _init() -> void:
	page_title = "Profil"


func build() -> void:
	var ed := Editor.new()
	ed.ctx = ctx
	body.add_child(ed)
	var c := W.card(body)
	var l := W.label("Ton pseudo et ta mascotte sont partagés avec toutes les apps Goodview.", 14, T.DIM, c)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func on_back() -> bool:
	for c in body.get_children():
		if c.has_method("commit"):
			c.commit()
	return false
