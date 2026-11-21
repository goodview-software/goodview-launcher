extends SceneTree
const Lint := preload("res://kit/lint.gd")
const K := preload("res://kit/k.gd")
func _init():
	var host := Control.new()
	root.add_child(host)
	host.theme = K.theme()
	var bg := ColorRect.new()
	bg.color = K.Tokens.surface0
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(bg)
	var g = load("res://kit/gallery.gd").new()
	host.add_child(g)
	var out: Array = await Lint.sweep(host, host, [320, 360, 480, 768, 1100, 1600], self, "galerie")
	var seen := {}
	for l in out:
		var k = str(l).substr(str(l).find("]") + 1)
		if not seen.has(k):
			seen[k] = true
			print(str(l).left(200))
	print("DEFAUTS ", out.size(), " uniques ", seen.size())
	quit()
