extends Control
## Chargement : un vrai cube 3D (SubViewport) roule lentement (comme un escargot) du bord gauche jusqu'au
## centre de l'écran, de 0 à 100 %. `value` (0..1) pilote la position ; `auto` = progression simulée.
const T := preload("res://ui/theme.gd")
const SIZE := 56.0

var value := 0.0: set = _set_value
var auto := true
var _t := 0.0
var _svc: SubViewportContainer
var _vp: SubViewport
var _cube: MeshInstance3D
var _cam: Camera3D


func _init() -> void:
	custom_minimum_size = Vector2(0, 240)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_svc)
	_vp = SubViewport.new()
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_svc.add_child(_vp)
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.position = Vector3(0, 0, 600)
	_vp.add_child(_cam)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	_vp.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = T.TEXT
	env.ambient_light_energy = 0.45
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cube = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * SIZE
	_cube.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = T.OK
	m.roughness = 0.45
	_cube.material_override = m
	_vp.add_child(_cube)
	resized.connect(_layout)


func _set_value(v: float) -> void:
	value = clampf(v, 0.0, 1.0)
	_layout()
	queue_redraw()


## Termine l'animation : le cube atteint le centre, 100 %.
func finish() -> void:
	auto = false
	value = 1.0


func _x0() -> float:
	return SIZE


func _ground() -> float:
	return size.y * 0.55


func _layout() -> void:
	if _cam == null or size.x < 1.0:
		return
	_cam.size = size.y
	var x := lerpf(_x0(), size.x * 0.5, value)
	_cube.position = Vector3(x - size.x * 0.5, size.y * 0.5 - _ground(), 0)
	# roule : une rotation proportionnelle au chemin parcouru + petite inclinaison pour voir la 3D
	var roll := -(x - _x0()) / (SIZE * 0.5)
	_cube.basis = Basis.from_euler(Vector3(0.5 + sin(_t * 0.8) * 0.1, 0.6, 0)) * Basis(Vector3.BACK, roll)


func _process(dt: float) -> void:
	_t += dt
	if auto:
		value = minf(0.99, 1.0 - exp(-_t / 2.5))
	else:
		_layout()
	queue_redraw()


func _draw() -> void:
	var gy := _ground() + SIZE * 0.5 + 8.0
	var xe := size.x * 0.5
	var x := lerpf(_x0(), xe, value)
	draw_line(Vector2(_x0(), gy), Vector2(xe, gy), Color(T.DIM, 0.35), 3.0)
	draw_line(Vector2(_x0(), gy), Vector2(x, gy), T.OK, 3.0)
	var f := ThemeDB.fallback_font
	draw_string(f, Vector2(0, size.y - 12), "%d %%" % int(round(value * 100.0)), HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, T.TEXT)
