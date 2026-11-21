extends Control
## Petit joystick virtuel (en bas à gauche du tableau) : on le déplace à la souris ou au doigt, la vue défile en continu
## dans cette direction, à une vitesse proportionnelle à l'écart (inertie douce) ; au relâchement il revient au centre.
## Dessiné en pixel-art (carré chanfreiné, flèches en gradins) avec les couleurs du thème.

const T := preload("res://ui/theme.gd")
const SIZE := 96.0
const MAX_SPEED := 1100.0  # pixels d'écran par seconde, manche à fond
const DEAD := 0.1

var S  # surface (pan_by)
var vec := Vector2.ZERO  # position demandée, longueur <= 1 (y vers le haut = négatif)
var knob := Vector2.ZERO  # position affichée (suit vec en douceur)
var vel := Vector2.ZERO  # vitesse de défilement lissée (px/s)
var active := false
var _idx := -2


func setup(surface) -> void:
	S = surface
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	tooltip_text = "Joystick : glisse pour déplacer la vue (plus tu t'écartes, plus ça va vite)"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(false)


func _gui_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
		if e.pressed:
			_grab(-1, e.position)
		elif _idx == -1:
			release()
		accept_event()
	elif e is InputEventMouseMotion and active and _idx == -1:
		aim(e.position)
		accept_event()
	elif e is InputEventScreenTouch and not Input.is_emulating_mouse_from_touch():
		if e.pressed:
			_grab(e.index, e.position)
		elif _idx == e.index:
			release()
		accept_event()
	elif e is InputEventScreenDrag and active and _idx == e.index and not Input.is_emulating_mouse_from_touch():
		aim(e.position)
		accept_event()


func _grab(idx: int, p: Vector2) -> void:
	active = true
	_idx = idx
	aim(p)
	set_process(true)


## Pointe le joystick vers une position locale (coordonnées du contrôle).
func aim(p: Vector2) -> void:
	var r := SIZE * 0.5 - 14.0
	var v := (p - size * 0.5) / r
	if v.length() > 1.0:
		v = v.normalized()
	vec = v
	set_process(true)


func release() -> void:
	active = false
	_idx = -2
	vec = Vector2.ZERO
	set_process(true)


## Vitesse cible (px/s) pour une position du manche : proportionnelle à l'écart, courbe douce près du centre.
static func speed_for(v: Vector2) -> Vector2:
	var l := v.length()
	if l < DEAD:
		return Vector2.ZERO
	var k := (l - DEAD) / (1.0 - DEAD)
	return v / l * pow(k, 1.4) * MAX_SPEED


## Un pas de simulation (appelé par _process ; les tests l'appellent directement).
func step(dt: float) -> void:
	vel = vel.lerp(speed_for(vec), 1.0 - exp(-dt * 9.0))
	knob = knob.lerp(vec, 1.0 - exp(-dt * (22.0 if active else 14.0)))
	if vel.length() > 0.5 and S != null:
		S.pan_by(-vel * dt)  # manche à droite : la vue va à droite, le contenu défile à gauche
	if not active and vel.length() < 1.0 and knob.length() < 0.01:
		vel = Vector2.ZERO
		knob = Vector2.ZERO
		set_process(false)
	queue_redraw()


func _process(dt: float) -> void:
	step(minf(dt, 0.1))


static func _oct(r: Rect2, c: float) -> PackedVector2Array:
	var a := r.position
	var b := r.end
	return PackedVector2Array([Vector2(a.x + c, a.y), Vector2(b.x - c, a.y), Vector2(b.x, a.y + c), Vector2(b.x, b.y - c),
			Vector2(b.x - c, b.y), Vector2(a.x + c, b.y), Vector2(a.x, b.y - c), Vector2(a.x, a.y + c)])


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	var base := _oct(r, 14.0)
	draw_colored_polygon(base, Color(T.CARD, 0.94))
	var edge := base.duplicate()
	edge.append(base[0])
	draw_polyline(edge, Color(T.OK, 0.55 if active else 0.25), 2.0, false)
	var c := size * 0.5
	# flèches en gradins aux quatre points cardinaux, éclairées dans la direction visée
	for d in [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]:
		var lit := clampf(vec.dot(d) * 1.6, 0.0, 1.0)
		var col := T.DIM.lerp(T.OK, lit)
		for i in 4:
			var along := SIZE * 0.5 - 17.0 + i * 3.0
			var half := float(3 - i) * 2.0 + 1.0
			var pc: Vector2 = c + d * along
			var sz := Vector2(3.0, half * 2.0) if d.x != 0.0 else Vector2(half * 2.0, 3.0)
			draw_rect(Rect2(pc - sz * 0.5, sz), col)
	var kp := c + knob * (SIZE * 0.5 - 14.0)
	var kr := Rect2(kp - Vector2(15, 15), Vector2(30, 30))
	var kb := _oct(kr, 6.0)
	draw_colored_polygon(kb, T.OK.darkened(0.45) if not active else T.OK.darkened(0.2))
	var kin := _oct(kr.grow(-4), 4.0)
	draw_colored_polygon(kin, T.OK if active else T.OK.darkened(0.1))
	var ke := kb.duplicate()
	ke.append(kb[0])
	draw_polyline(ke, T.OK.darkened(0.6), 2.0, false)
