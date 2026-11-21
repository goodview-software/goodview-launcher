extends RefCounted
## Persistance locale. Formats historiques conservés :
##   installed.json  {repo: {tag, exe, desk}}
##   settings.cfg    [profile] avatar, pseudo   (+ nouvelles sections [app] [ui] [updates] [window] [install])
##   ~/.config/goodview/profile.json  {pseudo, mascot}  lu par les autres apps
## Le cache du catalogue vit dans catalog.json + cache/icons/.

const U := preload("res://ui/universe.gd")
var root := "user://"
var real := true  # false = bac à sable (tests) : aucun fichier hors de `root`
var installed := {}  # repo -> {tag, exe, desk}
var pseudo := ""
var avatar := 0
var welcomed := false
var cfg := ConfigFile.new()


func _init(r := "user://", is_real := true) -> void:
	root = r
	real = is_real
	if not real:
		DirAccess.make_dir_recursive_absolute(root)


func path(file: String) -> String:
	return root + file


func load_all() -> void:
	if FileAccess.file_exists(path("installed.json")):
		var d = JSON.parse_string(FileAccess.get_file_as_string(path("installed.json")))
		if d is Dictionary:
			installed = d
	if cfg.load(path("settings.cfg")) == OK:
		avatar = clampi(int(cfg.get_value("profile", "avatar", 0)), 0, 7)
		pseudo = str(cfg.get_value("profile", "pseudo", ""))
	# les installations existantes (pseudo déjà choisi) ne repassent pas par la bienvenue
	welcomed = bool(cfg.get_value("app", "welcomed", pseudo != ""))
	if pseudo == "":
		var u := OS.get_environment("USER").capitalize()
		pseudo = u if u != "" else "Invité"
	save_all()


func save_all() -> void:
	save_installed()
	save_cfg()
	write_shared_profile()


func save_installed() -> void:
	var f := FileAccess.open(path("installed.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(installed))
		f.close()


func save_cfg() -> void:
	cfg.set_value("profile", "avatar", avatar)
	cfg.set_value("profile", "pseudo", pseudo)
	cfg.set_value("app", "welcomed", welcomed)
	cfg.save(path("settings.cfg"))


## Profil partagé avec toutes les apps Goodview : ~/.config/goodview/profile.json
func write_shared_profile() -> void:
	if not real:
		return
	var dir := OS.get_environment("HOME") + "/.config/goodview"
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir + "/profile.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"pseudo": pseudo, "mascot": avatar, "theme": U.shared_theme(avatar)}))
		f.close()


func get_s(section: String, key: String, def: Variant) -> Variant:
	return cfg.get_value(section, key, def)


func set_s(section: String, key: String, value: Variant) -> void:
	cfg.set_value(section, key, value)
	save_cfg()


# ------------------------------------------------------------------ Favoris, tri

func is_fav(app_name: String) -> bool:
	return app_name in (get_s("ui", "favs", []) as Array)


func toggle_fav(app_name: String) -> void:
	var f: Array = (get_s("ui", "favs", []) as Array).duplicate()
	if app_name in f:
		f.erase(app_name)
	else:
		f.append(app_name)
	set_s("ui", "favs", f)


# ------------------------------------------------------------------ Dossier d'installation

## Dossier absolu des apps (réglage [install] dir, sinon <données>/apps).
func apps_dir() -> String:
	var custom := str(get_s("install", "dir", "")).strip_edges()
	if custom != "":
		return custom
	return ProjectSettings.globalize_path(path("apps"))


# ------------------------------------------------------------------ Cache du catalogue

func save_catalog(apps: Array, last_check: float) -> void:
	var out: Array = []
	for a in apps:
		var c: Dictionary = (a as Dictionary).duplicate()
		c.erase("icon")
		out.append(c)
	var f := FileAccess.open(path("catalog.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"v": 1, "time": last_check, "apps": out}))
		f.close()


## Renvoie {apps: Array, time: float} ou {} si pas de cache exploitable.
func load_catalog() -> Dictionary:
	if not FileAccess.file_exists(path("catalog.json")):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(path("catalog.json")))
	if not (d is Dictionary) or not (d.get("apps") is Array):
		return {}
	for a in d.apps:
		a["icon"] = load_icon(str(a.get("name", "")))
	return {"apps": d.apps, "time": float(d.get("time", 0.0))}


func icon_path(app_name: String) -> String:
	return path("cache/icons/%s.png" % app_name.validate_filename())


func save_icon(app_name: String, img: Image) -> void:
	DirAccess.make_dir_recursive_absolute(path("cache/icons"))
	img.save_png(icon_path(app_name))


func load_icon(app_name: String) -> Texture2D:
	var p := icon_path(app_name)
	if not FileAccess.file_exists(p):
		return null
	var im := Image.load_from_file(p)
	return ImageTexture.create_from_image(im) if im != null else null


func cache_size() -> int:
	var total := 0
	var f := path("catalog.json")
	if FileAccess.file_exists(f):
		total += FileAccess.get_file_as_bytes(f).size()
	var d := DirAccess.open(path("cache/icons"))
	if d != null:
		for n in d.get_files():
			total += FileAccess.get_file_as_bytes(path("cache/icons/" + n)).size()
	return total


func clear_cache() -> void:
	DirAccess.remove_absolute(path("catalog.json"))
	var d := DirAccess.open(path("cache/icons"))
	if d != null:
		for n in d.get_files():
			DirAccess.remove_absolute(path("cache/icons/" + n))
