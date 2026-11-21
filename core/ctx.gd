extends Node
## Contexte partagé : services (store, catalogue, installateur, mises à jour), routeur et utilitaires.

signal profile_changed
signal theme_changed  # charte (univers) changée : tout l'écran se recolore
signal active_changed  # assistant actif changé

const Store := preload("res://core/store.gd")
const Catalog := preload("res://core/catalog.gd")
const Installer := preload("res://core/installer.gd")
const Updater := preload("res://core/updater.gd")
const Ollama := preload("res://core/ollama.gd")
const Chats := preload("res://core/chats.gd")
const Orchestra := preload("res://core/orchestra.gd")
const T := preload("res://ui/theme.gd")
const U := preload("res://ui/universe.gd")
const VERSION: String = preload("res://version.gd").VERSION

var store: Store
var catalog: Catalog
var installer: Installer
var updater: Updater
var router: Node  # ui/router.gd
var ollama: Ollama
var chats: Chats
var orchestra: Orchestra
var ollama_version := ""
var models: Array = []  # [{name, size}] vus par /api/tags
var active := 0  # assistant actif (= univers affiché)
var pull := {}  # téléchargement de modèle en cours {model, ratio, status, req, error}
var pending_chat := ""  # conversation à ouvrir par la page Chat


## sandbox = true : fichiers isolés dans user://gltest/, aucun réseau (tests).
func setup(sandbox := false) -> void:
	if sandbox:
		OS.execute("rm", ["-rf", ProjectSettings.globalize_path("user://gltest")])
	store = Store.new("user://gltest/" if sandbox else "user://", not sandbox)
	store.load_all()
	catalog = Catalog.new()
	catalog.store = store
	catalog.net = not sandbox
	add_child(catalog)
	installer = Installer.new()
	installer.store = store
	installer.simulate = sandbox
	add_child(installer)
	updater = Updater.new()
	updater.store = store
	updater.catalog = catalog
	updater.net = not sandbox
	add_child(updater)
	installer.finished.connect(_on_finished)
	ollama = Ollama.new()
	ollama.base_url = str(store.get_s("chat", "url", Ollama.DEFAULT_URL))
	add_child(ollama)
	chats = Chats.new(store.root + "chats/")
	chats.export_dir = ProjectSettings.globalize_path(store.root + "export") if sandbox else ""
	chats.load_index()
	orchestra = Orchestra.new()
	orchestra.ollama = ollama
	orchestra.allow = bool(store.get_s("chat", "delegate", true))
	add_child(orchestra)
	active = store.avatar
	T.apply(active)


## Démarre les services : cache affiché tout de suite, puis rafraîchissement en arrière-plan.
func start() -> void:
	var cached := catalog.load_cache()
	if not cached or updater.auto_enabled():
		catalog.refresh()
	updater.start()


func _on_finished(app_name: String, ok: bool, msg: String) -> void:
	var a := catalog.find(app_name)
	var t := Catalog.title(a) if not a.is_empty() else app_name
	if ok:
		notify("%s : installée" % t, "ok")
	elif msg != "Annulé":
		notify("%s : %s" % [t, msg], "error")
	else:
		notify("Installation annulée")


func notify(text: String, kind := "info", action := "", cb := Callable()) -> void:
	if router != null:
		router.toast(text, kind, action, cb)


func set_profile(new_pseudo: String, new_avatar: int) -> void:
	var np := new_pseudo.strip_edges()
	if np != "":
		store.pseudo = np
	var changed := store.avatar != clampi(new_avatar, 0, 7)
	store.avatar = clampi(new_avatar, 0, 7)
	store.save_all()
	if changed:
		set_active(store.avatar)
	profile_changed.emit()


## Change l'assistant actif : la charte de l'app suit (recolorisation immédiate de toutes les pages).
func set_active(i: int) -> void:
	i = clampi(i, 0, U.count() - 1)
	active = i
	if T.apply(i):
		theme_changed.emit()
	active_changed.emit()


## Vision : capacités /api/show si connues, sinon heuristique sur le nom (jamais pour les modèles cassés).
func model_is_vision(m: String) -> bool:
	if U.is_broken(m):
		return false
	if ollama.caps_cache.has(m):
		return "vision" in ollama.caps_cache[m]
	return U.is_vision(m)


## Précharge les capacités (/api/show) des modèles installés.
func prefetch_caps() -> void:
	for m in models:
		if not ollama.caps_cache.has(m.name):
			await ollama.capabilities(m.name)


## Modèle Ollama d'un assistant (préféré s'il est installé, sinon repli).
func model_for(ai: int) -> String:
	return U.pick_model(ai, models, ollama.bad_models)


## Page affichée au démarrage : "chat" (défaut) ou "home" (Apps).
func start_page() -> String:
	return "home" if str(store.get_s("ui", "start", "chat")) == "home" else "chat"


## "soon" (pas de release), "nolinux", "none" (installable), "ok" (à jour), "update"
func app_status(a: Dictionary) -> String:
	var t := Catalog.tag(a)
	if t == "":
		return "soon"
	var inst = store.installed.get(a.name)
	if inst == null:
		return "none" if not a.asset.is_empty() else "nolinux"
	return "ok" if str(inst.tag) == t else "update"


## Apps installées avec une version plus récente publiée.
func updates() -> Array:
	return catalog.apps.filter(func(a): return app_status(a) == "update" and not a.asset.is_empty())


## Y a-t-il quelque chose à mettre à jour (apps ou launcher) ? Pour les badges.
func has_updates() -> bool:
	return not updates().is_empty() or updater.available()


func ago(t: float) -> String:
	if t <= 0.0:
		return "jamais"
	var s := int(Time.get_unix_time_from_system() - t)
	if s < 60:
		return "à l'instant"
	if s < 3600:
		return "il y a %d min" % (s / 60)
	if s < 86400:
		return "il y a %d h" % (s / 3600)
	return "il y a %d j" % (s / 86400)


func fmt_size(bytes: float) -> String:
	if bytes < 1048576.0:
		return "%.0f Ko" % (bytes / 1024.0)
	return "%.1f Mo" % (bytes / 1048576.0)
