extends Control
## Routeur de pages : pile de navigation, transitions douces (fondu + glissement), notifications.

signal page_changed(page_title: String)

const T := preload("res://ui/theme.gd")
const W := preload("res://ui/widgets.gd")
const PAGES := {
	"home": preload("res://pages/home.gd"),
	"app": preload("res://pages/app_page.gd"),
	"profile": preload("res://pages/profile.gd"),
	"settings": preload("res://pages/settings.gd"),
	"about": preload("res://pages/about.gd"),
	"welcome": preload("res://pages/welcome.gd"),
	"chat": preload("res://pages/chat.gd"),
	"chat_history": preload("res://pages/chat_history.gd"),
	"chat_settings": preload("res://pages/chat_settings.gd"),
	"kit": preload("res://pages/kit_page.gd"),
}
const TABS := ["home", "chat", "profile"]  # pages racines conservées en mémoire (le chat est une sous-app : pas dans la barre)
const NAV_TABS := ["home", "profile"]  # onglets de la barre basse
const Nav := preload("res://ui/nav.gd")
const SLIDE := 28.0

var ctx: Node
var stack: Array = []  # pages ouvertes, la dernière est visible
var instant := false  # true : pas d'animation (tests)
var stage: Control
var _toast: W.Toast
var _tweens := {}
var tabs := {}  # id -> page d'onglet (persistante)
var nav: Nav
var bg: ColorRect
var _fade: Tween


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = T.make_theme()
	bg = ColorRect.new()
	bg.color = T.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	stage = Control.new()
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.clip_contents = true
	add_child(stage)
	nav = Nav.new()
	nav.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	nav.offset_top = -Nav.HEIGHT
	nav.visible = false
	nav.tab.connect(func(id: String): go_tab(id))
	add_child(nav)
	_toast = W.Toast.new()
	add_child(_toast)
	if ctx != null:
		nav.variant = ctx.active
		ctx.theme_changed.connect(_on_theme)
		ctx.active_changed.connect(func(): nav.variant = ctx.active)
		ctx.catalog.changed.connect(_update_nav)
		ctx.updater.changed.connect(_update_nav)


func current() -> Control:
	return stack.back() if not stack.is_empty() else null


func can_pop() -> bool:
	return stack.size() > 1


func toast(text: String, kind := "info", action := "", cb := Callable()) -> void:
	_toast.show_msg(text, kind, action, cb)


func is_tab(p: Control) -> bool:
	return p != null and tabs.values().has(p)


## Recolore toute l'app : nouveau thème Godot, fond, pages reconstruites, fondu doux.
func _on_theme() -> void:
	theme = T.make_theme()
	bg.color = T.BG
	for p in stage.get_children():
		if p.has_method("retheme"):
			p.retheme()
	nav.queue_redraw()
	if not instant:
		if _fade != null and _fade.is_valid():
			_fade.kill()
		stage.modulate.a = 0.35
		_fade = create_tween()
		_fade.tween_property(stage, "modulate:a", 1.0, 0.35)


func _update_nav() -> void:
	var c := current()
	var show: bool = c != null and c.get("page_id") in NAV_TABS and stack.size() == 1
	nav.visible = show
	stage.offset_bottom = -Nav.HEIGHT if show else 0.0
	if show:
		nav.select(c.page_id)
	if ctx != null:
		nav.badge = ctx.has_updates()


## Change d'onglet (les pages d'onglet restent en mémoire : le chat en cours n'est pas interrompu).
func go_tab(id: String, args := {}) -> Control:
	var old := current()
	var tgt: Control = tabs.get(id)
	if tgt != null and not is_instance_valid(tgt):
		tgt = null
	if old != null and old == tgt:
		return old
	var n := tgt if tgt != null else _make(id, args)
	tabs[id] = n
	for p in stack:
		if p != old and p != n and not is_tab(p):
			p.queue_free()
		elif p != old and p != n:
			p.visible = false
	stack = [n]
	_swap(n, old, 1, old != null and not is_tab(old))
	if tgt != null:
		n.on_show()
	return n


func _make(id: String, args: Dictionary) -> Control:
	assert(PAGES.has(id), "page inconnue : " + id)
	var n: Control = PAGES[id].new()
	n.ctx = ctx
	n.args = args
	n.router = self
	n.page_id = id
	n.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.add_child(n)
	return n


## Ouvre une page par-dessus la courante (le retour la ramène).
func push(id: String, args := {}) -> Control:
	if id in TABS:
		return go_tab(id, args)
	var old := current()
	var n := _make(id, args)
	stack.append(n)
	_swap(n, old, 1, false)
	return n


## Remplace la page courante (pas de retour vers elle).
func replace(id: String, args := {}) -> Control:
	var old: Control = stack.pop_back() if not stack.is_empty() else null
	if id in TABS:
		stack.append(old)
		return go_tab(id, args)
	var n := _make(id, args)
	stack.append(n)
	_swap(n, old, 1, not is_tab(old))
	return n


## Repart d'une pile vide avec une seule page.
func reset(id: String, args := {}) -> Control:
	if id in TABS:
		return go_tab(id, args)
	var old := current()
	for p in stack:
		if p != old and not is_tab(p):
			p.queue_free()
	stack.clear()
	var n := _make(id, args)
	stack.append(n)
	_swap(n, old, 1, old != null and not is_tab(old))
	return n


## Retour : la page peut le consommer (on_back) ; renvoie false si on est déjà à la racine.
func back() -> bool:
	var cur := current()
	if cur != null and cur.on_back():
		return true
	return pop()


func pop() -> bool:
	if stack.size() < 2:
		return false
	var old: Control = stack.pop_back()
	var n: Control = stack.back()
	_swap(n, old, -1, not is_tab(old))
	n.on_show()
	return true


func _swap(incoming: Control, outgoing: Control, dir: int, free_out: bool) -> void:
	_kill(incoming)
	incoming.visible = true
	if instant or outgoing == null:
		incoming.modulate.a = 1.0
		incoming.position.x = 0.0
		if outgoing != null:
			_retire(outgoing, free_out)
	else:
		incoming.modulate.a = 0.0
		incoming.position.x = dir * SLIDE
		var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(incoming, "modulate:a", 1.0, 0.24)
		tw.tween_property(incoming, "position:x", 0.0, 0.26)
		_tweens[incoming] = tw
		_kill(outgoing)
		var tw2 := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw2.tween_property(outgoing, "modulate:a", 0.0, 0.14)
		tw2.tween_property(outgoing, "position:x", -dir * SLIDE * 0.5, 0.14)
		tw2.finished.connect(func():
			if is_instance_valid(outgoing):
				_retire(outgoing, free_out))
		_tweens[outgoing] = tw2
	_update_nav()
	page_changed.emit(incoming.page_title)


func _kill(n: Control) -> void:
	if _tweens.has(n):
		var tw: Tween = _tweens[n]
		if tw != null and tw.is_valid():
			tw.kill()
		_tweens.erase(n)


func _retire(n: Control, free_it: bool) -> void:
	_kill(n)
	if free_it:
		n.queue_free()
	else:
		n.visible = false
