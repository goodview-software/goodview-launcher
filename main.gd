extends Control
## Goodview Launcher : amorçage uniquement. Le reste vit dans core/ (données, réseau), ui/ (composants, routeur)
## et pages/ (une page par fichier). Variable d'environnement GL_TEST=1 : lance test_run.gd (headless, sans réseau).

const Ctx := preload("res://core/ctx.gd")
const Router := preload("res://ui/router.gd")
const T := preload("res://ui/theme.gd")
const Tk := preload("res://kit/tokens.gd")
const Pixelize := preload("res://kit/pixelize.gd")
const APP_TITLE := "Goodview Launcher"

var ctx: Ctx
var router: Router
var _save_timer: Timer


func _ready() -> void:
	Tk.set_pixel(true)  # skin pixel art commun aux apps Goodview
	theme = T.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if OS.get_environment("GL_TEST") == "1" and ResourceLoader.exists("res://test_run.gd"):
		var runner: Node = load("res://test_run.gd").new()
		add_child(runner)
		runner.run(self)
		return
	get_window().title = APP_TITLE
	get_window().min_size = Vector2i(360, 520)
	ctx = Ctx.new()
	add_child(ctx)
	ctx.setup()
	router = Router.new()
	router.ctx = ctx
	ctx.router = router
	add_child(router)
	router.page_changed.connect(_on_page)
	_restore_window()
	get_window().content_scale_factor = float(ctx.store.get_s("ui", "scale", 1.0))
	router.push(("board" if ctx.start_page() == "chat" else ctx.start_page()) if ctx.store.welcomed else "welcome")
	ctx.start()
	Pixelize.install(self)
	if OS.get_environment("GL_PAGE") != "":  # débogage : ouvre directement une page d'onglet
		router.go_tab(OS.get_environment("GL_PAGE"))


func _on_page(page_title: String) -> void:
	get_window().title = APP_TITLE if page_title == "" else "%s · %s" % [APP_TITLE, page_title]


func _unhandled_input(e: InputEvent) -> void:
	if router == null:
		return
	if e is InputEventKey and e.pressed and e.ctrl_pressed and e.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD, KEY_MINUS, KEY_KP_SUBTRACT]:
		var up: bool = e.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]
		var z := clampf(snappedf(get_window().content_scale_factor + (0.25 if up else -0.25), 0.25), 1.0, 2.5)
		get_window().content_scale_factor = z
		ctx.store.set_s("ui", "scale", z)
		get_viewport().set_input_as_handled()
		return
	if e.is_action_pressed("ui_cancel") or (e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_XBUTTON1):
		if router.back():
			get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:  # bouton Retour d'Android
			if router != null:
				router.back()
		NOTIFICATION_WM_CLOSE_REQUEST:
			_save_window()


# ------------------------------------------------------------------ Taille / position de la fenêtre

func _restore_window() -> void:
	if not OS.has_feature("pc") or DisplayServer.get_name() == "headless":
		return
	var s: Variant = ctx.store.get_s("window", "size", null)
	var p: Variant = ctx.store.get_s("window", "pos", null)
	var w := get_window()
	if s is Vector2i:
		w.size = Vector2i(maxi(s.x, 360), maxi(s.y, 520))
	if p is Vector2i:
		# on ne restaure la position que si elle reste sur un écran
		var ok := false
		for i in DisplayServer.get_screen_count():
			var r := DisplayServer.screen_get_usable_rect(i)
			if r.grow(-40).has_point(p + Vector2i(60, 30)):
				ok = true
		if ok:
			w.position = p
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.8
	_save_timer.timeout.connect(_save_window)
	add_child(_save_timer)
	w.size_changed.connect(func(): _save_timer.start())


func _save_window() -> void:
	var w := get_window()
	if ctx == null or not OS.has_feature("pc") or DisplayServer.get_name() == "headless" or w.mode != Window.MODE_WINDOWED:
		return
	ctx.store.cfg.set_value("window", "size", w.size)
	ctx.store.cfg.set_value("window", "pos", w.position)
	ctx.store.save_cfg()
