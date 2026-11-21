extends SceneTree
func _init():
	for p in OS.get_cmdline_user_args():
		var s = load(p)
		print(p, " -> ", s != null)
	quit()
