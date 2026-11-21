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
}
const SLIDE := 28.0

var ctx: Node
var stack: Array = []  # pages ouvertes, la dernière est visible
var instant := false  # true : pas d'animation (tests)
var stage: Control
var _toast: W.Toast
var _tweens := {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = T.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	stage = Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.clip_contents = true
	add_child(stage)
	_toast = W.Toast.new()
	add_child(_toast)


func current() -> Control:
	return stack.back() if not stack.is_empty() else null


func can_pop() -> bool:
	return stack.size() > 1


func toast(text: String, kind := "info") -> void:
	_toast.show_msg(text, kind)


func _make(id: String, args: Dictionary) -> Control:
	assert(PAGES.has(id), "page inconnue : " + id)
	var n: Control = PAGES[id].new()
	n.ctx = ctx
	n.args = args
	n.router = self
	n.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(n)
	return n


## Ouvre une page par-dessus la courante (le retour la ramène).
func push(id: String, args := {}) -> Control:
	var old := current()
	var n := _make(id, args)
	stack.append(n)
	_swap(n, old, 1, false)
	return n


## Remplace la page courante (pas de retour vers elle).
func replace(id: String, args := {}) -> Control:
	var old: Control = stack.pop_back() if not stack.is_empty() else null
	var n := _make(id, args)
	stack.append(n)
	_swap(n, old, 1, true)
	return n


## Repart d'une pile vide avec une seule page.
func reset(id: String, args := {}) -> Control:
	var old := current()
	for p in stack:
		if p != old:
			p.queue_free()
	stack.clear()
	var n := _make(id, args)
	stack.append(n)
	_swap(n, old, 1, true)
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
	_swap(n, old, -1, true)
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
