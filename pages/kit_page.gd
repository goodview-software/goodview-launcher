extends "res://pages/page.gd"
## Galerie du kit (page cachée : 5 appuis sur le titre de « À propos ») : chaque composant dans chaque état.
const Gallery := preload("res://kit/gallery.gd")


func _init() -> void:
	page_title = "Kit"
	max_w = 1040.0


func build() -> void:
	set_title("Kit Goodview")
	var g: Control = Gallery.new()
	g.embedded = true
	g.popup_host = router
	g.body = body
	body.add_child(g)
