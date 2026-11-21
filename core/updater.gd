extends Node
## Mises à jour : vérification périodique des apps (Timer 30 min) + mise à jour du launcher lui-même
## (version.json + .pck chargé par boot.gd au prochain démarrage).

signal changed

const Store := preload("res://core/store.gd")
const Catalog := preload("res://core/catalog.gd")
const Boot := preload("res://boot.gd")
const VERSION: String = preload("res://version.gd").VERSION
const UPDATE_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest/download/version.json"
const RELEASES_URL := "https://github.com/goodview-software/goodview-launcher/releases/latest"
const NOTES_URL := "https://api.github.com/repos/goodview-software/goodview-launcher/releases/latest"
const INTERVAL := 1800.0  # 30 min
const TMP := "user://update.tmp"

var store: Store
var catalog: Catalog
var net := true
## "idle", "checking", "uptodate", "available" (pck), "newbin" (nouveau programme),
## "downloading", "ready" (redémarrer), "error"
var state := "idle"
var info := {}
var notes := ""
var ratio := 0.0
var error_msg := ""
var timer: Timer


func start() -> void:
	timer = Timer.new()
	timer.wait_time = INTERVAL
	timer.one_shot = false
	timer.timeout.connect(_tick)
	add_child(timer)
	apply_settings()
	if auto_enabled():
		check_launcher()


func auto_enabled() -> bool:
	return bool(store.get_s("updates", "auto", true))


## À appeler quand le réglage de vérification automatique change.
func apply_settings() -> void:
	if timer == null:
		return
	if auto_enabled():
		timer.start()
	else:
		timer.stop()


func _tick() -> void:
	if auto_enabled():
		check_now()


## Vérifie les apps puis le launcher (déclenché par le Timer ou à la main).
func check_now() -> bool:
	var ok := await catalog.check_releases()
	await check_launcher()
	return ok


func available() -> bool:
	return state in ["available", "newbin", "downloading", "ready"]


func check_launcher() -> void:
	if state in ["downloading", "ready"]:
		return
	if not net:
		return
	state = "checking"
	changed.emit()
	var r: Array = await catalog.get_bytes(UPDATE_URL, 10.0)
	var j = JSON.parse_string((r[1] as PackedByteArray).get_string_from_utf8()) if r[0] == 200 else null
	if r[0] != 200 or not (j is Dictionary) or not j.has("version"):
		state = "error" if r[0] != 0 else "idle"
		error_msg = "Vérification impossible."
		changed.emit()
		return
	if not Boot.newer(str(j["version"]), VERSION):
		state = "uptodate"
		changed.emit()
		return
	info = j
	var v := Engine.get_version_info()
	var same: bool = str(j.get("godot", "")) == "%d.%d.%d" % [v.major, v.minor, v.patch]
	state = "available" if same and j.has("pck") else "newbin"
	changed.emit()
	# notes de version (facultatives)
	var n: Array = await catalog.get_json(NOTES_URL)
	if n[1] is Dictionary:
		notes = Catalog.clean_notes(str(n[1].get("body", "")), 700)
		changed.emit()


func download() -> void:
	if state == "newbin":
		OS.shell_open(RELEASES_URL)
		return
	if state != "available":
		return
	state = "downloading"
	ratio = 0.0
	changed.emit()
	var req := HTTPRequest.new()
	req.download_file = TMP
	req.max_redirects = 8
	req.timeout = 60.0
	add_child(req)
	var out := [-1, 0]
	req.request_completed.connect(func(r: int, c: int, _h: PackedStringArray, _b: PackedByteArray):
		out[0] = r
		out[1] = c)
	if req.request(str(info["pck"]), PackedStringArray(["User-Agent: goodview-launcher"])) != OK:
		out = [1, 0]
	while out[0] == -1:
		var total := req.get_body_size()
		if total > 0:
			ratio = float(req.get_downloaded_bytes()) / total
			changed.emit()
		await get_tree().process_frame
	req.queue_free()
	if out[0] != HTTPRequest.RESULT_SUCCESS or out[1] != 200 \
			or FileAccess.get_sha256(TMP) != str(info.get("sha256", "")):
		DirAccess.remove_absolute(TMP)
		state = "available"
		error_msg = "Échec du téléchargement."
		changed.emit()
		return
	DirAccess.rename_absolute(TMP, "user://update.pck")
	var c := ConfigFile.new()
	c.set_value("update", "version", str(info["version"]))
	c.save("user://update.cfg")
	state = "ready"
	changed.emit()


func restart() -> void:
	OS.set_restart_on_exit(true)
	get_tree().quit()
