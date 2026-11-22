extends Node
## Une seule instance par app : verrou `~/.config/goodview/hud/<id>.lock` avec battement de cœur (< 5 s = vivante).
## Usage (dans _ready de la scène principale) : `if not Single.claim(self, "mon-app"): return`
## claim() renvoie false (et quitte l'app) si une autre instance tourne déjà ; true sinon (le verrou est alors tenu).
const BEAT := 2.0
const STALE := 5.0
var _path := ""


static func _dir() -> String:
	return OS.get_environment("HOME") + "/.config/goodview/hud"


static func claim(host: Node, id: String) -> bool:
	if OS.get_environment("GL_TEST") == "1" or DisplayServer.get_name() == "headless":
		return true  # tests / export headless : pas de verrou
	var path := _dir() + "/" + id + ".lock"
	if FileAccess.file_exists(path):
		var ts := float(FileAccess.get_file_as_string(path).strip_edges())
		if Time.get_unix_time_from_system() - ts < STALE:
			host.get_tree().quit()
			return false
	var s := new()
	s._path = path
	host.add_child(s)
	s._beat()
	var t := Timer.new()
	t.wait_time = BEAT
	t.timeout.connect(s._beat)
	s.add_child(t)
	t.start()
	return true


func _beat() -> void:
	DirAccess.make_dir_recursive_absolute(_dir())
	var f := FileAccess.open(_path, FileAccess.WRITE)
	if f != null:
		f.store_string(str(Time.get_unix_time_from_system()))
		f.close()


func _exit_tree() -> void:
	if _path != "":
		DirAccess.remove_absolute(_path)
