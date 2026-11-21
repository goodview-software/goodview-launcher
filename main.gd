extends Control
## Goodview Launcher : liste les repos de l'organisation GitHub, installe la
## dernière release (asset Linux) dans user://apps/<repo>/ et lance l'app.

const ORGS := ["goodview-software"]
const API := "https://api.github.com"
const APPS_DIR := "user://apps"
const VERSION: String = preload("res://version.gd").VERSION
const UPDATE_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest/download/version.json"
const RELEASES_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest"
const STATE_FILE := "user://installed.json"
const CFG_FILE := "user://settings.cfg"
const EXCLUDED := [".github", "goodview-launcher"]  # repos non listés

var token := ""
var installed := {}  # repo -> {tag, exe}
var list_box: VBoxContainer
var status: Label
var progress: ProgressBar
var token_edit: LineEdit
var busy := false
var upd_lbl: Label
var upd_btn: Button
var upd_info := {}
var upd_http: HTTPRequest

func _ready() -> void:
	_load_state()
	_build_ui()
	refresh()
	_check_update()

# ---------- UI ----------
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 20)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var th := HBoxContainer.new()
	root.add_child(th)
	var title := Label.new()
	title.text = "Goodview Software"
	title.add_theme_font_size_override("font_size", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(title)
	upd_lbl = Label.new()
	upd_lbl.modulate = Color(1, 1, 1, 0.7)
	th.add_child(upd_lbl)
	upd_btn = Button.new()
	upd_btn.visible = false
	upd_btn.pressed.connect(_do_update)
	th.add_child(upd_btn)

	var bar := HBoxContainer.new()
	root.add_child(bar)
	token_edit = LineEdit.new()
	token_edit.placeholder_text = "Token GitHub (optionnel, pour les repos privés)"
	token_edit.secret = true
	token_edit.text = token
	token_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(token_edit)
	var b := Button.new()
	b.text = "Actualiser"
	b.pressed.connect(func():
		token = token_edit.text.strip_edges()
		_save_state()
		refresh())
	bar.add_child(b)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	scroll.add_child(list_box)

	progress = ProgressBar.new()
	progress.visible = false
	root.add_child(progress)
	status = Label.new()
	root.add_child(status)

func _add_row(repo: Dictionary, release: Dictionary) -> void:
	var name: String = repo.name
	var tag: String = release.get("tag_name", "")
	var inst: Dictionary = installed.get(name, {})
	var panel := PanelContainer.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	panel.add_child(h)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	var n := Label.new()
	n.text = name
	n.add_theme_font_size_override("font_size", 20)
	info.add_child(n)
	var d := Label.new()
	d.text = str(repo.get("description", "") if repo.get("description") != null else "")
	d.modulate = Color(1, 1, 1, 0.65)
	info.add_child(d)
	var v := Label.new()
	if tag == "":
		v.text = "Aucune release publiée"
	elif inst.is_empty():
		v.text = "Dernière version : " + tag
	elif inst.tag == tag:
		v.text = "Installée : " + tag + " (à jour)"
	else:
		v.text = "Installée : %s → disponible : %s" % [inst.tag, tag]
	info.add_child(v)

	if tag != "":
		var asset := _pick_asset(release)
		var act := Button.new()
		act.custom_minimum_size = Vector2(130, 0)
		if inst.is_empty():
			act.text = "Installer"
		elif inst.tag != tag:
			act.text = "Mettre à jour"
		else:
			act.text = "Lancer"
		if asset.is_empty() and (inst.is_empty() or inst.tag != tag):
			act.text = "Pas d'asset Linux"
			act.disabled = true
		act.pressed.connect(func():
			if act.text == "Lancer":
				_launch(name)
			else:
				install(name, release, asset))
		h.add_child(act)
		if not inst.is_empty():
			var rm := Button.new()
			rm.text = "Supprimer"
			rm.pressed.connect(func(): _uninstall(name))
			h.add_child(rm)
	list_box.add_child(panel)

# ---------- Réseau ----------
func _headers(binary := false) -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: goodview-launcher"])
	h.append("Accept: application/octet-stream" if binary else "Accept: application/vnd.github+json")
	if token != "":
		h.append("Authorization: Bearer " + token)
	return h

func _get_json(url: String) -> Variant:
	var req := HTTPRequest.new()
	add_child(req)
	if req.request(url, _headers()) != OK:
		req.queue_free()
		return null
	var res: Array = await req.request_completed
	req.queue_free()
	if res[1] != 200:
		return null
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())

func refresh() -> void:
	if busy:
		return
	busy = true
	for c in list_box.get_children():
		c.queue_free()
	status.text = "Chargement du catalogue…"
	var count := 0
	var failed := 0
	for org in ORGS:
		var path := "/orgs/%s/repos?per_page=100&type=%s" % [org, "all" if token != "" else "public"]
		var repos = await _get_json(API + path)
		if repos == null or not repos is Array:
			failed += 1
			continue
		for repo in repos:
			if repo.name in EXCLUDED or repo.get("archived", false):
				continue
			var rel = await _get_json("%s/repos/%s/%s/releases/latest" % [API, org, repo.name])
			_add_row(repo, rel if rel is Dictionary else {})
			count += 1
	if failed == ORGS.size():
		status.text = "Impossible de lire le catalogue (réseau ou token ?)."
	else:
		status.text = "%d application(s) dans le catalogue." % count if count > 0 else "Aucune application publiée pour l'instant."
	busy = false

# ---------- Installation ----------
func _pick_asset(release: Dictionary) -> Dictionary:
	var best := {}
	for a in release.get("assets", []):
		var n: String = a.name.to_lower()
		if n.ends_with(".apk"):
			continue
		if n.contains("linux") or n.ends_with(".x86_64") or n.ends_with(".appimage"):
			return a
		if best.is_empty() and not (n.contains("windows") or n.contains("macos") or n.ends_with(".exe")):
			best = a
	return best

func install(repo_name: String, release: Dictionary, asset: Dictionary) -> void:
	if busy:
		return
	busy = true
	var dir := ProjectSettings.globalize_path(APPS_DIR + "/" + repo_name)
	OS.execute("rm", ["-rf", dir])
	DirAccess.make_dir_recursive_absolute(dir)
	var file: String = dir + "/" + str(asset.name)
	var req := HTTPRequest.new()
	req.download_file = file
	req.max_redirects = 8
	add_child(req)
	var url: String = asset.url if token != "" else asset.browser_download_url
	req.request(url, _headers(true) if token != "" else PackedStringArray(["User-Agent: goodview-launcher"]))
	progress.visible = true
	progress.value = 0
	while req.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED or req.get_body_size() < 0:
		var total := req.get_body_size()
		if total > 0:
			progress.value = 100.0 * req.get_downloaded_bytes() / total
		status.text = "Téléchargement de %s…" % repo_name
		await get_tree().process_frame
		if req.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
			break
	req.queue_free()
	progress.visible = false
	if not FileAccess.file_exists(file) or FileAccess.get_file_as_bytes(file).size() < 100:
		status.text = "Échec du téléchargement de " + repo_name
		busy = false
		return
	var exe := _unpack(file, dir)
	if exe == "":
		status.text = "Aucun exécutable trouvé dans " + asset.name
		busy = false
		return
	installed[repo_name] = {"tag": release.tag_name, "exe": exe}
	_save_state()
	status.text = "%s %s installé." % [repo_name, release.tag_name]
	busy = false
	refresh()

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
	var found := ""
	var d := DirAccess.open(dir)
	if d == null:
		return ""
	for sub in d.get_directories():
		found = _find_exe(dir + "/" + sub)
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

func _launch(repo_name: String) -> void:
	var exe: String = installed[repo_name].exe
	var pid := OS.create_process(exe, [])
	status.text = "%s lancé." % repo_name if pid > 0 else "Impossible de lancer " + exe

func _uninstall(repo_name: String) -> void:
	OS.execute("rm", ["-rf", ProjectSettings.globalize_path(APPS_DIR + "/" + repo_name)])
	installed.erase(repo_name)
	_save_state()
	refresh()

# ---------- Persistance ----------
func _load_state() -> void:
	if FileAccess.file_exists(STATE_FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(STATE_FILE))
		if d is Dictionary:
			installed = d
	var cfg := ConfigFile.new()
	if cfg.load(CFG_FILE) == OK:
		token = cfg.get_value("github", "token", "")

func _save_state() -> void:
	var f := FileAccess.open(STATE_FILE, FileAccess.WRITE)
	f.store_string(JSON.stringify(installed))
	f.close()
	var cfg := ConfigFile.new()
	cfg.set_value("github", "token", token)
	cfg.save(CFG_FILE)


# ---------- Mise à jour du launcher (même principe que Sound Link : version.json + .pck) ----------
func _check_update() -> void:
	upd_lbl.text = "v" + VERSION
	upd_http = HTTPRequest.new()
	upd_http.timeout = 10.0
	add_child(upd_http)
	upd_http.request_completed.connect(_on_version_json, CONNECT_ONE_SHOT)
	upd_http.request(UPDATE_URL)

func _on_version_json(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var info = JSON.parse_string(body.get_string_from_utf8())
	if not (info is Dictionary) or not info.has("version"):
		return
	if not preload("res://boot.gd").newer(str(info["version"]), VERSION):
		upd_lbl.text = "✓ v" + VERSION
		return
	upd_info = info
	var v := Engine.get_version_info()
	var same: bool = str(info.get("godot", "")) == "%d.%d.%d" % [v.major, v.minor, v.patch]
	upd_btn.visible = true
	if same and info.has("pck"):
		upd_lbl.text = "v%s disponible" % info["version"]
		upd_btn.text = "Mettre à jour"
	else:
		upd_lbl.text = "v%s disponible (nouveau programme)" % info["version"]
		upd_btn.text = "Télécharger"

func _do_update() -> void:
	if upd_btn.text == "Télécharger":
		OS.shell_open(RELEASES_URL)
		return
	if upd_btn.text == "Redémarrer":
		OS.set_restart_on_exit(true)
		get_tree().quit()
		return
	upd_btn.disabled = true
	upd_lbl.text = "Téléchargement…"
	upd_http.download_file = "user://update.tmp"
	upd_http.request_completed.connect(_on_pck, CONNECT_ONE_SHOT)
	upd_http.request(str(upd_info["pck"]))

func _on_pck(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	upd_http.download_file = ""
	upd_btn.disabled = false
	var tmp := "user://update.tmp"
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 \
			or FileAccess.get_sha256(tmp) != str(upd_info.get("sha256", "")):
		DirAccess.remove_absolute(tmp)
		upd_lbl.text = "Échec du téléchargement"
		return
	DirAccess.rename_absolute(tmp, "user://update.pck")
	var c := ConfigFile.new()
	c.set_value("update", "version", str(upd_info["version"]))
	c.save("user://update.cfg")
	upd_lbl.text = "v%s installée" % upd_info["version"]
	upd_btn.text = "Redémarrer"
