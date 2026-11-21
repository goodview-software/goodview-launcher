extends RefCounted
## Pièces jointes du chat : fichiers texte/code (insérés dans le contexte, tronqués au-delà d'une limite)
## et images (JPEG réduit, en base64, pour les modèles vision).

const MAX_TEXT := 40000  # caractères conservés par fichier
const MAX_FILES := 8
const MAX_IMG := 1280  # px (plus grand côté)
const TEXT_EXTS := ["txt", "md", "markdown", "csv", "tsv", "json", "gd", "py", "js", "ts", "html", "css", "xml", "yml", "yaml", "toml",
		"ini", "cfg", "log", "sh", "c", "h", "cpp", "hpp", "cs", "java", "rs", "go", "php", "sql", "tscn", "tres", "godot", "shader",
		"gdshader", "c", "lua", "bat", "conf", "env", "rb", "kt", "swift", "tex", "rst", "srt", "lrc", "enf", "et", "layout"]
const IMG_EXTS := ["png", "jpg", "jpeg", "webp", "bmp", "gif"]


## Lit un fichier. Renvoie {name, kind: "text"|"image"|"bad", text, truncated, chars, b64, tex, error}.
static func read(path: String) -> Dictionary:
	var name := path.get_file()
	var ext := path.get_extension().to_lower()
	var r := {"name": name, "kind": "bad", "text": "", "truncated": false, "chars": 0, "b64": "", "tex": null, "error": ""}
	if not FileAccess.file_exists(path):
		r.error = "Fichier introuvable"
		return r
	if ext in IMG_EXTS:
		var img := Image.load_from_file(path)
		if img == null or img.is_empty():
			r.error = "Image illisible"
			return r
		if maxi(img.get_width(), img.get_height()) > MAX_IMG:
			var k := float(MAX_IMG) / maxi(img.get_width(), img.get_height())
			img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_BILINEAR)
		if img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGB8)
		r.b64 = Marshalls.raw_to_base64(img.save_jpg_to_buffer(0.85))
		r.tex = thumb(img)
		r.kind = "image"
		return r
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		r.error = "Lecture impossible"
		return r
	var bytes := f.get_buffer(mini(f.get_length(), MAX_TEXT * 4 + 8))
	f.close()
	if bytes.has(0):
		r.error = "Format non pris en charge"
		return r
	var txt := bytes.get_string_from_utf8()
	if txt.length() > MAX_TEXT:
		txt = txt.left(MAX_TEXT)
		r.truncated = true
	elif FileAccess.get_size(path) > bytes.size():
		r.truncated = true
	r.text = txt
	r.chars = txt.length()
	r.kind = "text"
	return r



static func thumb(img: Image) -> ImageTexture:
	var t := img.duplicate() as Image
	var k := 160.0 / maxi(t.get_width(), t.get_height())
	if k < 1.0:
		t.resize(maxi(1, int(t.get_width() * k)), maxi(1, int(t.get_height() * k)), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(t)


## Vignette depuis une image base64 (conversation restaurée).
static func tex_from_b64(b64: String) -> Texture2D:
	var img := Image.new()
	if img.load_jpg_from_buffer(Marshalls.base64_to_raw(b64)) != OK:
		return null
	return thumb(img)
