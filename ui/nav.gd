extends "res://kit/ui/k_navbar.gd"
## Barre de navigation basse PIXEL ART du launcher (kit/ui/k_navbar.gd) : Apps | Profil. L'assistant IA est une sous-app (carte dans Apps).

signal tab(id: String)

const TABS := [["home", "Apps", "layout-grid"], ["profile", "Profil", "user"]]

var badge := false: set = _set_badge
var variant := 0  # (compat) mascotte de l'assistant actif


func _init() -> void:
	super()
	setup(TABS.map(func(t): return {"id": t[0], "label": t[1], "icon": t[2]}), "home")
	selected.connect(func(id: String): tab.emit(id))


func select(id: String) -> void:
	current = id


func _set_badge(v: bool) -> void:
	badge = v
	set_badge("home", v)
