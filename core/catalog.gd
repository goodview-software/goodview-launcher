extends Node
## Catalogue des apps de l'organisation GitHub : cache local affiché tout de suite, puis rafraîchi en arrière-plan.
##
## Convention par repo (tous optionnels) :
##   icon.png | icon.svg   à la racine : icône
##   app.json              {"name", "tagline", "description", "screenshots": ["docs/a.png", ...]}
##
## app = {name, org, repo: {description}, release: {tag_name, body, published_at, assets}, asset, icon, manifest}

signal changed  # liste, état ou version publiée modifiés

const Store := preload("res://core/store.gd")
const ORGS := ["goodview-software"]
const API := "https://api.github.com"
const RAW := "https://raw.githubusercontent.com"
const EXCLUDED := [".github", "goodview-launcher"]

var store: Store
var net := true  # false : aucun accès réseau (tests)
var apps: Array = []
## "loading" (rien à afficher), "ready", "offline", "error"
var state := "loading"
var error_msg := ""
var online := true  # dernier accès réussi ?
var from_cache := false  # les données affichées viennent du cache
var busy := false
var checking := false
var last_check := 0.0  # horodatage Unix de la dernière vérification réussie


# ------------------------------------------------------------------ Accès aux données d'une app

static func title(a: Dictionary) -> String:
	return str(a.manifest.get("name", str(a.name).replace("-", " ").capitalize()))


## Catégories de la boutique (id, libellé). Une app choisit la sienne via app.json {"category": "jeux"} ou un topic GitHub.
const CATEGORIES := [["pocket", "Pocket"], ["outils", "Outils"], ["jeux", "Jeux"]]


static func category(a: Dictionary) -> String:
	var ids: Array = CATEGORIES.map(func(c): return c[0])
	var m := str(a.manifest.get("category", "")).to_lower()
	if m in ids:
		return m
	for t in a.repo.get("topics", []):
		if str(t).to_lower() in ids:
			return str(t).to_lower()
	return "pocket" if str(a.name).begins_with("pocket-") else "outils"


static func category_label(id: String) -> String:
	for c in CATEGORIES:
		if c[0] == id:
			return c[1]
	return id.capitalize()


static func tagline(a: Dictionary) -> String:
	var t = a.manifest.get("tagline", a.repo.get("description", ""))
	return str(t) if t != null else ""


static func tag(a: Dictionary) -> String:
	return str(a.release.get("tag_name", ""))


static func published(a: Dictionary) -> String:
	return str(a.release.get("published_at", ""))


## Asset Linux de la release (ni APK, ni .pck, ni .json, ni Windows/macOS).
static func pick_asset(release: Dictionary) -> Dictionary:
	var best := {}
	for x in release.get("assets", []):
		var n: String = str(x.name).to_lower()
		if n.ends_with(".apk") or n.ends_with(".pck") or n.ends_with(".json"):
			continue
		if n.contains("linux") or n.ends_with(".x86_64") or n.ends_with(".appimage"):
			return x
		if best.is_empty() and not (n.contains("windows") or n.contains("macos") or n.ends_with(".exe")):
			best = x
	return best


static func pick_apk(release: Dictionary) -> Dictionary:
	for x in release.get("assets", []):
		if str(x.name).to_lower().ends_with(".apk"):
			return x
	return {}


## Notes de version sans balisage Markdown lourd.
static func clean_notes(s: String, limit := 900) -> String:
	var out: PackedStringArray = []
	for line in s.replace("\r", "").split("\n"):
		var l := line.strip_edges()
		while l.begins_with("#"):
			l = l.substr(1)
		l = l.strip_edges().replace("**", "").replace("`", "")
		if l.begins_with("- ") or l.begins_with("* "):
			l = "• " + l.substr(2)
		out.append(l)
	var r := "\n".join(out).strip_edges()
	return r.left(limit) + ("…" if r.length() > limit else "")


func find(app_name: String) -> Dictionary:
	for a in apps:
		if a.name == app_name:
			return a
	return {}


# ------------------------------------------------------------------ Réseau

func _headers() -> PackedStringArray:
	return PackedStringArray(["User-Agent: goodview-launcher", "Accept: application/vnd.github+json"])


var rate_reset := 0.0  # horodatage Unix de la remise à zéro de la limite GitHub (0 = inconnue)
var _etags := {}  # url -> {"etag": ..., "body": ...} : une réponse 304 ne compte pas dans la limite GitHub


## [code HTTP (0 = échec réseau), octets, en-têtes]
func get_bytes(url: String, timeout := 15.0, extra := PackedStringArray()) -> Array:
	if not net:
		return [0, PackedByteArray(), PackedStringArray()]
	var req := HTTPRequest.new()
	req.timeout = timeout
	add_child(req)
	if req.request(url, _headers() + extra) != OK:
		req.queue_free()
		return [0, PackedByteArray(), PackedStringArray()]
	var res: Array = await req.request_completed
	req.queue_free()
	return [res[1] if res[0] == HTTPRequest.RESULT_SUCCESS else 0, res[3], res[2]]


static func _header(h: PackedStringArray, key: String) -> String:
	for line in h:
		if line.to_lower().begins_with(key.to_lower() + ":"):
			return line.substr(key.length() + 1).strip_edges()
	return ""


func _load_etags() -> void:
	if _etags.is_empty() and FileAccess.file_exists("user://etags.json"):
		var d = JSON.parse_string(FileAccess.get_file_as_string("user://etags.json"))
		if d is Dictionary:
			_etags = d


func _save_etags() -> void:
	var f := FileAccess.open("user://etags.json", FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(_etags))
		f.close()


## [code, données JSON ou null] ; requêtes conditionnelles (ETag) pour ménager la limite de l'API GitHub.
func get_json(url: String) -> Array:
	_load_etags()
	var extra := PackedStringArray()
	if _etags.has(url):
		extra.append("If-None-Match: " + str(_etags[url].etag))
	var r: Array = await get_bytes(url, 15.0, extra)
	if r[0] == 304 and _etags.has(url):
		return [200, JSON.parse_string(str(_etags[url].body))]
	if r[0] == 403 or r[0] == 429:
		var rs := _header(r[2], "x-ratelimit-reset")
		rate_reset = rs.to_float() if rs != "" else Time.get_unix_time_from_system() + 900.0
		return [r[0], null]
	if r[0] != 200:
		return [r[0], null]
	var txt: String = (r[1] as PackedByteArray).get_string_from_utf8()
	var et := _header(r[2], "etag")
	if et != "" and txt.length() < 200000:
		_etags[url] = {"etag": et, "body": txt}
		_save_etags()
	return [200, JSON.parse_string(txt)]


func make_tex(bytes: PackedByteArray, svg := false) -> Texture2D:
	var im := Image.new()
	var err := im.load_svg_from_buffer(bytes, 2.0) if svg else im.load_png_from_buffer(bytes)
	if err != OK and not svg:
		err = im.load_jpg_from_buffer(bytes)
	return ImageTexture.create_from_image(im) if err == OK else null


static func _trim_release(rel: Dictionary) -> Dictionary:
	var assets: Array = []
	for x in rel.get("assets", []):
		assets.append({"name": x.get("name", ""), "size": x.get("size", 0),
				"browser_download_url": x.get("browser_download_url", ""), "download_count": x.get("download_count", 0)})
	return {"tag_name": rel.get("tag_name", ""), "body": rel.get("body", ""),
			"published_at": rel.get("published_at", ""), "assets": assets}


## Met à jour la release d'une app. Renvoie false en cas d'échec réseau (l'ancienne valeur est conservée).
func fetch_release(a: Dictionary) -> bool:
	var r: Array = await get_json("%s/repos/%s/%s/releases/latest" % [API, a.org, a.name])
	if r[0] == 404:
		a.release = {}
		a.asset = {}
		return true
	if r[0] != 200 or not (r[1] is Dictionary):
		_note_failure(int(r[0]))
		return false
	a.release = _trim_release(r[1])
	a.asset = pick_asset(a.release)
	return true


func _note_failure(code: int) -> void:
	online = code != 0
	if code == 403 or code == 429:
		var mins := maxi(1, int(ceil((rate_reset - Time.get_unix_time_from_system()) / 60.0)))
		error_msg = "Limite GitHub atteinte, réessaie dans %d min." % mins
	elif code == 0:
		error_msg = "Impossible de joindre GitHub."
	else:
		error_msg = "GitHub a répondu une erreur (%d)." % code


# ------------------------------------------------------------------ Cache / chargement

## Charge le cache disque. Renvoie true s'il y avait quelque chose à afficher.
func load_cache() -> bool:
	var c := store.load_catalog()
	if c.is_empty():
		return false
	apps = c.apps
	last_check = c.time
	state = "ready"
	from_cache = true
	changed.emit()
	return true


## Injecte un catalogue factice (tests).
func set_fake(list: Array, st := "ready") -> void:
	apps = list
	state = st
	from_cache = false
	busy = false
	changed.emit()


func refresh() -> void:
	if busy:
		return
	busy = true
	if apps.is_empty():
		state = "loading"
	changed.emit()
	var failed := 0
	var fails_code := 0
	var seen: Array = []
	for org in ORGS:
		var r: Array = await get_json("%s/orgs/%s/repos?per_page=100&type=public" % [API, org])
		if not (r[1] is Array):
			failed += 1
			fails_code = int(r[0])
			continue
		for repo in r[1]:
			if repo.name in EXCLUDED or repo.get("archived", false):
				continue
			seen.append(repo.name)
			var a := find(repo.name)
			var is_new := a.is_empty()
			if is_new:
				a = {"name": repo.name, "org": org, "repo": {}, "release": {}, "asset": {}, "icon": null, "manifest": {}}
			var lic = repo.get("license")
			a.repo = {"description": repo.get("description", ""), "stars": repo.get("stargazers_count", 0),
					"pushed_at": repo.get("pushed_at", ""), "topics": repo.get("topics", []),
					"license": str(lic.get("spdx_id", "")) if lic is Dictionary else ""}
			await fetch_release(a)
			var m: Array = await get_bytes("%s/%s/%s/HEAD/app.json" % [RAW, org, repo.name])
			if m[0] == 200:
				var j = JSON.parse_string((m[1] as PackedByteArray).get_string_from_utf8())
				if j is Dictionary:
					a.manifest = j
			if a.icon == null:
				await _fetch_icon(a)
			if is_new:
				apps.append(a)
				state = "ready"
				changed.emit()
	busy = false
	if failed == ORGS.size():
		_note_failure(fails_code)
		from_cache = not apps.is_empty()
		state = "ready" if from_cache else ("error" if fails_code in [403, 429] or fails_code > 0 else "offline")
	else:
		online = true
		from_cache = false
		state = "ready"
		apps = apps.filter(func(a): return a.name in seen)
		last_check = Time.get_unix_time_from_system()
		store.save_catalog(apps, last_check)
	changed.emit()


func _fetch_icon(a: Dictionary) -> void:
	for f in ["icon.png", "icon.svg"]:
		var ic: Array = await get_bytes("%s/%s/%s/HEAD/%s" % [RAW, a.org, a.name, f])
		if ic[0] == 200:
			a.icon = make_tex(ic[1], f.ends_with(".svg"))
			if a.icon != null:
				store.save_icon(a.name, (a.icon as Texture2D).get_image())
				return


## Revérifie uniquement les versions publiées (léger). Renvoie true si tout a répondu.
func check_releases() -> bool:
	if checking or busy:
		return false
	checking = true
	changed.emit()
	var ok := true
	for a in apps:
		if not await fetch_release(a):
			ok = false
			break
	checking = false
	if ok:
		online = true
		last_check = Time.get_unix_time_from_system()
		store.save_catalog(apps, last_check)
	changed.emit()
	return ok


func check_one(a: Dictionary) -> bool:
	if checking:
		return false
	checking = true
	changed.emit()
	var ok := await fetch_release(a)
	checking = false
	if ok:
		store.save_catalog(apps, last_check)
	changed.emit()
	return ok
