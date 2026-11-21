extends RefCounted
## Icônes Lucide (SVG, trait currentColor) rastérisées nettes et mises en cache ; teinte par modulate.
## Icon.make("house", 20, color) -> nœud KIcon.  Icon.texture("house", 20) -> ImageTexture blanche.

const BASE := "res://kit/icons/"
const SIZES := [16, 20, 24, 32]
const KIcon := preload("res://kit/ui/k_icon.gd")
static var _cache := {}
static var _svg := {}

static func has(name: String) -> bool:
	return FileAccess.file_exists(BASE + name + ".svg")

static func _source(name: String) -> String:
	if not _svg.has(name):
		var p := BASE + name + ".svg"
		_svg[name] = FileAccess.get_file_as_string(p).replace("currentColor", "#ffffff") if FileAccess.file_exists(p) else ""
	return _svg[name]

static func texture(name: String, px := 20) -> Texture2D:
	var key := "%s@%d" % [name, px]
	if _cache.has(key):
		return _cache[key]
	var src := _source(name)
	var tex: Texture2D = null
	if src != "":
		var img := Image.new()
		var scale := float(px) / 24.0 * 2.0  # rendu en 2x pour la netteté
		if img.load_svg_from_buffer(src.to_utf8_buffer(), scale) == OK:
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex

static func make(name: String, px := 20, color: Variant = null) -> Control:
	var n := KIcon.new()
	n.icon_name = name
	n.px = px
	if color != null:
		n.color = color
	return n
