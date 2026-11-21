extends Node
## Installation / mise à jour / désinstallation des apps (file d'attente séquentielle), raccourcis bureau, lancement.

signal changed  # file ou état modifiés
signal progress(ratio: float)
signal finished(app_name: String, ok: bool, msg: String)

const Store := preload("res://core/store.gd")
const Catalog := preload("res://core/catalog.gd")

var store: Store
var queue: Array = []  # apps en attente
var current: Dictionary = {}  # app en cours de téléchargement
var ratio := 0.0
var done_jobs := 0
var total_jobs := 0
var errors := {}  # app_name -> dernier message d'erreur
var simulate := false  # tests : pas de réseau, installation factice
var _running := false
var _cancel := false
var _req: HTTPRequest


func is_busy() -> bool:
	return _running


func is_queued(app_name: String) -> bool:
	if current.get("name", "") == app_name:
		return true
	for a in queue:
		if a.name == app_name:
			return true
	return false


func enqueue(a: Dictionary) -> void:
	if is_queued(a.name) or a.asset.is_empty():
		return
	errors.erase(a.name)
	queue.append(a)
	total_jobs += 1
	changed.emit()
	if not _running:
		_run()


## Annule le téléchargement en cours et vide la file.
func cancel() -> void:
	queue.clear()
	_cancel = true
	if _req != null:
		_req.cancel_request()
	changed.emit()


func _run() -> void:
	_running = true
	while not queue.is_empty():
		current = queue.pop_front()
		ratio = 0.0
		changed.emit()
		var msg := await _install(current)
		var nm: String = current.name
		if _cancel:
			finished.emit(nm, false, "Annulé")
		elif msg == "":
			done_jobs += 1
			finished.emit(nm, true, "")
		else:
			errors[nm] = msg
			finished.emit(nm, false, msg)
		_cancel = false
	current = {}
	total_jobs = 0
	done_jobs = 0
	_running = false
	changed.emit()


## Installe une app ; renvoie "" si succès, sinon un message lisible.
func _install(a: Dictionary) -> String:
	var app_name: String = a.name
	var asset: Dictionary = a.asset
	var dir := store.apps_dir() + "/" + app_name
	var tmp := dir + ".new"  # on n'écrase l'ancienne version qu'une fois le téléchargement réussi
	OS.execute("rm", ["-rf", tmp])
	if DirAccess.make_dir_recursive_absolute(tmp) != OK:
		return "Impossible de créer le dossier d'installation."
	var file: String = tmp + "/" + str(asset.name)
	if simulate:
		for i in 6:
			ratio = i / 5.0
			progress.emit(ratio)
			await get_tree().process_frame
			if _cancel:
				OS.execute("rm", ["-rf", tmp])
				return "Annulé"
		var f := FileAccess.open(tmp + "/app.x86_64", FileAccess.WRITE)
		f.store_string("#!/bin/sh\n")
		f.close()
	else:
		var res := await _download(str(asset.browser_download_url), file)
		if _cancel:
			OS.execute("rm", ["-rf", tmp])
			return "Annulé"
		if res != "":
			OS.execute("rm", ["-rf", tmp])
			return res
		if _unpack(file, tmp) == "":
			OS.execute("rm", ["-rf", tmp])
			return "Aucun exécutable trouvé dans " + str(asset.name)
	OS.execute("rm", ["-rf", dir])
	if DirAccess.rename_absolute(tmp, dir) != OK:
		return "Impossible de finaliser l'installation."
	var exe := _find_exe(dir)
	var desk: bool = store.installed.get(app_name, {}).get("desk", false)
	store.installed[app_name] = {"tag": Catalog.tag(a), "exe": exe, "desk": desk}
	store.save_installed()
	if desk:
		set_shortcut(a, true)  # recrée le raccourci (dossier réinstallé)
	return ""


## Télécharge `url` vers `file` en publiant la progression. Renvoie "" ou un message d'erreur.
func _download(url: String, file: String) -> String:
	_req = HTTPRequest.new()
	_req.download_file = file
	_req.max_redirects = 8
	_req.timeout = 60.0
	add_child(_req)
	var out := [-1, 0]
	_req.request_completed.connect(func(r: int, c: int, _h: PackedStringArray, _b: PackedByteArray): out = [r, c])
	if _req.request(url, PackedStringArray(["User-Agent: goodview-launcher"])) != OK:
		_req.queue_free()
		_req = null
		return "Téléchargement impossible (pas de connexion ?)."
	while out[0] == -1 and not _cancel:
		var total := _req.get_body_size()
		if total > 0:
			ratio = float(_req.get_downloaded_bytes()) / total
			progress.emit(ratio)
		await get_tree().process_frame
	_req.queue_free()
	_req = null
	if _cancel:
		return "Annulé"
	if out[0] != HTTPRequest.RESULT_SUCCESS:
		return "Échec du téléchargement : connexion interrompue."
	if out[1] != 200:
		return "Échec du téléchargement (HTTP %d)." % out[1]
	if not FileAccess.file_exists(file) or FileAccess.get_file_as_bytes(file).size() < 100:
		return "Fichier téléchargé invalide."
	return ""


func _unpack(file: String, dir: String) -> String:
	var n := file.get_file().to_lower()
	if n.ends_with(".zip"):
		var z := ZIPReader.new()
		if z.open(file) != OK:
			return ""
		for p in z.get_files():
			if p.ends_with("/"):
				DirAccess.make_dir_recursive_absolute(dir + "/" + p)
				continue
			DirAccess.make_dir_recursive_absolute((dir + "/" + p).get_base_dir())
			var f := FileAccess.open(dir + "/" + p, FileAccess.WRITE)
			if f == null:
				z.close()
				return ""
			f.store_buffer(z.read_file(p))
			f.close()
		z.close()
		DirAccess.remove_absolute(file)
	elif n.ends_with(".tar.gz") or n.ends_with(".tgz"):
		OS.execute("tar", ["-xzf", file, "-C", dir])
		DirAccess.remove_absolute(file)
	OS.execute("chmod", ["-R", "u+x", dir])
	return _find_exe(dir)


func _find_exe(dir: String) -> String:
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for sub in d.get_directories():
		var found := _find_exe(dir + "/" + sub)
		if found != "":
			return found
	for f in d.get_files():
		var l := f.to_lower()
		if l.ends_with(".x86_64") or l.ends_with(".appimage") or l.ends_with(".sh"):
			return dir + "/" + f
	for f in d.get_files():
		if f.get_extension() == "":
			return dir + "/" + f
	return ""


## Lance l'app installée. Renvoie "" ou un message d'erreur.
func launch(app_name: String) -> String:
	if not store.installed.has(app_name):
		return "App non installée."
	var exe: String = store.installed[app_name].exe
	if not store.real:
		return ""
	if not FileAccess.file_exists(exe):
		return "Exécutable introuvable : relance l'installation."
	return "" if OS.create_process(exe, []) > 0 else "Impossible de lancer " + exe.get_file()


func uninstall(a: Dictionary) -> void:
	set_shortcut(a, false)
	OS.execute("rm", ["-rf", store.apps_dir() + "/" + str(a.name)])
	store.installed.erase(a.name)
	store.save_installed()
	errors.erase(a.name)
	changed.emit()


func desktop_dir() -> String:
	if store.real:
		return OS.get_system_dir(OS.SYSTEM_DIR_DESKTOP)
	var d := ProjectSettings.globalize_path(store.path("desktop"))
	DirAccess.make_dir_recursive_absolute(d)
	return d


## Raccourci bureau (.desktop). Renvoie false si impossible à créer.
func set_shortcut(a: Dictionary, on: bool) -> bool:
	var app_name: String = a.name
	var path := desktop_dir() + "/" + Catalog.title(a) + ".desktop"
	if store.installed.has(app_name):
		store.installed[app_name]["desk"] = on
		store.save_installed()
	if not on:
		DirAccess.remove_absolute(path)
		return true
	if not store.installed.has(app_name):
		return false
	var exe: String = store.installed[app_name].exe
	var icon_line := ""
	if a.icon != null:
		var ip := store.apps_dir() + "/" + app_name + "/icon.png"
		(a.icon as Texture2D).get_image().save_png(ip)
		icon_line = "Icon=" + ip + "\n"
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string("[Desktop Entry]\nType=Application\nName=%s\nComment=%s\nExec=\"%s\"\nPath=%s\n%sTerminal=false\nCategories=Game;Utility;\n"
			% [Catalog.title(a), Catalog.tagline(a), exe, exe.get_base_dir(), icon_line])
	f.close()
	if store.real:
		OS.execute("chmod", ["+x", path])
		OS.execute("gio", ["set", path, "metadata::trusted", "true"])
	return true
