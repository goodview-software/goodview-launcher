extends Node
## Test headless sans réseau : GL_TEST=1 flatpak run --env=GL_TEST=1 org.godotengine.Godot --headless --path . 
## Charge chaque page avec un catalogue factice, simule navigation, états et installation. Affiche « OK » ou les échecs.

const Ctx := preload("res://core/ctx.gd")
const Router := preload("res://ui/router.gd")
const Store := preload("res://core/store.gd")
const Catalog := preload("res://core/catalog.gd")
const T := preload("res://ui/theme.gd")
const U := preload("res://ui/universe.gd")
const Ollama := preload("res://core/ollama.gd")
const Orchestra := preload("res://core/orchestra.gd")
const Chats := preload("res://core/chats.gd")
const MD := preload("res://ui/markdown.gd")
const Attach := preload("res://core/attach.gd")
const W := preload("res://ui/widgets.gd")
const Lint := preload("res://kit/lint.gd")
const K := preload("res://kit/k.gd")

var fails: PackedStringArray = []
var ctx: Ctx
var router: Router
var server := TCPServer.new()  # faux Ollama local (aucun réseau externe)
var conns: Array = []
var handler: Callable = func(_path: String, _body: Dictionary) -> Dictionary: return {"code": 200, "lines": []}
var requests: Array = []


func check(cond: bool, msg: String) -> void:
	if not cond:
		fails.append(msg)
		printerr("ECHEC : ", msg)


func frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func fake(app_name: String, tag: String, pub: String, linux := true, apk := false) -> Dictionary:
	var assets: Array = []
	if linux:
		assets.append({"name": app_name + "-linux.zip", "size": 5000000, "browser_download_url": "http://invalid/" + app_name})
	if apk:
		assets.append({"name": app_name + ".apk", "size": 9000000, "browser_download_url": "http://invalid/" + app_name + ".apk"})
	var rel := {} if tag == "" else {"tag_name": tag, "body": "## Nouveautés\n- **a**\n- b", "published_at": pub, "assets": assets}
	return {"name": app_name, "org": "goodview-software", "repo": {"description": "Description de " + app_name},
			"release": rel, "asset": Catalog.pick_asset(rel), "icon": null, "manifest": {}}


func fake_list(n: int) -> Array:
	var l: Array = []
	for i in n:
		l.append(fake("app-%d" % i, "v1.%d" % i, "2026-01-%02dT00:00:00Z" % (i + 1), true, i == 1))
	return l


var _host: Control

func run(host: Node) -> void:
	_host = host
	get_window().size = Vector2i(1100, 720)
	ctx = Ctx.new()
	host.add_child(ctx)
	ctx.setup(true)
	router = Router.new()
	router.ctx = ctx
	router.instant = true
	ctx.router = router
	server.listen(0, "127.0.0.1")
	ctx.ollama.base_url = "http://127.0.0.1:%d" % server.get_local_port()
	host.add_child(router)
	await frames()
	check(ctx.store.real == false, "store en bac à sable")

	# --- compatibilité des formats historiques
	var old := Store.new("user://gltest/compat/", false)
	FileAccess.open(old.path("installed.json"), FileAccess.WRITE).store_string('{"pocket":{"tag":"v1","exe":"/x/y.x86_64","desk":true}}')
	var cf := ConfigFile.new()
	cf.set_value("profile", "avatar", 3)
	cf.set_value("profile", "pseudo", "Zoe")
	cf.save(old.path("settings.cfg"))
	old.load_all()
	check(old.installed.get("pocket", {}).get("tag") == "v1" and old.avatar == 3 and old.pseudo == "Zoe", "lecture des fichiers existants")
	check(old.welcomed, "pseudo existant : pas de bienvenue")

	# --- accueil : tous les états du catalogue
	var home: Control = router.push("home")
	await frames()
	for st in ["loading", "offline", "error", "ready"]:
		ctx.catalog.apps = []
		ctx.catalog.error_msg = "Limite GitHub atteinte."
		ctx.catalog.set_fake([], st)
		await frames()
		check(home._list.get_child_count() > 0, "accueil état " + st + " : contenu affiché")
	ctx.catalog.online = false
	ctx.catalog.set_fake(fake_list(3))
	await frames()
	check(ctx.catalog.state == "ready", "catalogue prêt")
	ctx.catalog.online = true

	# catalogue > 6 apps : recherche, tri, favoris, mises à jour
	var apps := fake_list(8)
	apps.append(fake("zz-soon", "", ""))
	apps.append(fake("zz-nolinux", "v1", "2026-02-01T00:00:00Z", false))
	ctx.store.installed["app-0"] = {"tag": "v0.9", "exe": "/tmp/none", "desk": false}  # mise à jour dispo
	ctx.store.installed["app-2"] = {"tag": "v1.2", "exe": "/tmp/none", "desk": false}  # à jour
	ctx.store.installed["app-3"] = {"tag": "v0.1", "exe": "/tmp/none", "desk": false}  # mise à jour dispo
	ctx.catalog.set_fake(apps)
	await frames()
	check(home._search.visible, "recherche visible au-delà de 6 apps")
	check(ctx.updates().size() == 2, "2 mises à jour détectées")
	check(ctx.has_updates(), "badge de mise à jour")
	check(router.nav.badge, "badge de mise à jour sur l'onglet Apps")
	for mode in ["recent", "az", "updates"]:
		home.sort_mode = mode
		home._render_list()
		await frames(1)
	var sorted: Array = home._visible_apps()
	check(sorted[0].name in ["app-0", "app-3"], "tri : mises à jour d'abord")
	ctx.store.toggle_fav("app-7")
	check(home._visible_apps()[0].name == "app-7", "favori en tête")
	ctx.store.toggle_fav("app-7")
	home.query = "app-5"
	home._render_list()
	check(home._visible_apps().size() == 1, "recherche filtre")
	home.query = "introuvable"
	home._render_list()
	await frames(1)
	home.query = ""
	home._render_list()

	# --- fiche d'app (installée, mise à jour, QR APK, introuvable)
	for n in ["app-0", "app-1", "app-2", "zz-soon", "zz-nolinux", "n-existe-pas"]:
		var p: Control = router.push("app", {"name": n})
		await frames()
		check(p.body.get_child_count() > 0, "fiche " + n)
		check(router.back(), "retour depuis la fiche " + n)
		await frames(1)
	check(router.stack.size() == 1, "pile de navigation")

	# --- installation : un seul, annulation, « tout mettre à jour »
	var app1 := ctx.catalog.find("app-1")
	ctx.installer.enqueue(app1)
	var guard := 0
	while ctx.installer.is_busy() and guard < 300:
		await frames(1)
		guard += 1
	check(ctx.store.installed.has("app-1") and ctx.store.installed["app-1"].tag == "v1.1", "installation simulée")
	check(FileAccess.file_exists(ctx.store.installed["app-1"].exe), "exécutable installé")
	check(ctx.installer.set_shortcut(app1, true), "raccourci bureau")
	check(ctx.installer.set_shortcut(app1, false), "raccourci retiré")
	ctx.installer.enqueue(ctx.catalog.find("app-4"))
	ctx.installer.enqueue(ctx.catalog.find("app-5"))
	await frames(2)
	ctx.installer.cancel()
	guard = 0
	while ctx.installer.is_busy() and guard < 300:
		await frames(1)
		guard += 1
	check(not ctx.store.installed.has("app-5"), "annulation : file vidée")
	for a in ctx.updates():
		ctx.installer.enqueue(a)
	guard = 0
	while ctx.installer.is_busy() and guard < 600:
		await frames(1)
		guard += 1
	check(ctx.updates().is_empty(), "tout mettre à jour (séquentiel)")
	ctx.installer.uninstall(app1)
	check(not ctx.store.installed.has("app-1"), "désinstallation")
	check(ctx.installer.launch("app-1") != "", "lancer une app non installée : erreur lisible")

	# --- autres pages
	var pr: Control = router.push("profile")
	await frames()
	pr.body.get_child(0).avatar = 2
	pr.body.get_child(0)._picked = true
	pr.body.get_child(0).edit.text = "Testeur"
	pr.body.get_child(0).commit()
	check(ctx.store.pseudo == "Testeur" and ctx.store.avatar == 2, "profil enregistré")
	router.go_tab("home")
	await frames()
	var se: Control = router.push("settings")
	await frames()
	ctx.store.set_s("updates", "auto", false)
	ctx.updater.start()
	check(not ctx.updater.auto_enabled() and ctx.updater.timer.is_stopped(), "vérification auto désactivée : timer arrêté")
	ctx.store.set_s("updates", "auto", true)
	ctx.updater.apply_settings()
	check(not ctx.updater.timer.is_stopped() and ctx.updater.timer.wait_time == 1800.0, "timer 30 min")
	ctx.store.clear_cache()
	se._refresh_cache()
	router.back()
	await frames()
	router.push("about")
	await frames()
	ctx.updater.state = "available"
	ctx.updater.info = {"version": "9.9.9"}
	ctx.updater.notes = "Notes"
	ctx.updater.changed.emit()
	await frames()
	check(home._banner.get_child_count() > 0, "bannière de mise à jour du launcher")
	router.back()
	await frames()
	ctx.updater.state = "idle"

	# --- cache catalogue : sauvegarde puis rechargement
	ctx.store.save_catalog(apps, 1234.0)
	var c := ctx.store.load_catalog()
	check(c.get("apps", []).size() == apps.size(), "cache catalogue relu")
	check(ctx.ago(0.0) == "jamais" and ctx.ago(Time.get_unix_time_from_system()) == "à l'instant", "formatage du temps")

	# --- bienvenue (2 écrans) puis accueil
	ctx.store.welcomed = false
	var w: Control = router.reset("welcome")
	await frames()
	check(w.step == 0, "bienvenue écran 1")
	w._show_step(1)
	await frames()
	check(w.step == 1, "bienvenue écran 2")
	w.finish()
	await frames()
	check(ctx.store.welcomed and router.current().get_script() == Router.PAGES["home"], "fin de bienvenue -> Apps (page par défaut)")

	# --- transitions animées (sans instant) : pas d'erreur
	router.instant = false
	router.push("settings")
	await get_tree().create_timer(0.4).timeout
	router.back()
	await get_tree().create_timer(0.4).timeout
	check(router.stack.size() == 1, "transitions")

	await run_ui()
	await run_assistants()
	await run_models()
	await run_lint(host)
	if OS.get_environment("GL_TEST_OLLAMA") == "1":
		await run_live()

	if fails.is_empty():
		print("OK")
		get_tree().quit(0)
	else:
		print("ECHECS : ", ", ".join(fails))
		get_tree().quit(1)


# ------------------------------------------------------------------ Faux serveur Ollama (127.0.0.1, port éphémère)

func _process(_dt: float) -> void:
	if server.is_listening() and server.is_connection_available():
		conns.append({"p": server.take_connection(), "buf": PackedByteArray(), "done": false, "close": 0})
	for c in conns.duplicate():
		var p: StreamPeerTCP = c.p
		p.poll()
		if c.close > 0:
			c.close -= 1
			if c.close == 0:
				p.disconnect_from_host()
				conns.erase(c)
			continue
		if p.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			conns.erase(c)
			continue
		var n := p.get_available_bytes()
		if n > 0:
			c.buf.append_array(p.get_data(n)[1])
		if c.done:
			continue
		var s: String = c.buf.get_string_from_utf8()
		var he := s.find("\r\n\r\n")
		if he < 0:
			continue
		var head := s.substr(0, he)
		var cl := 0
		for l in head.split("\r\n"):
			if l.to_lower().begins_with("content-length:"):
				cl = l.get_slice(":", 1).strip_edges().to_int()
		var raw: PackedByteArray = c.buf.slice(he + 4)
		if raw.size() < cl:
			continue
		c.done = true
		var path := head.split(" ")[1]
		var body = JSON.parse_string(raw.get_string_from_utf8()) if cl > 0 else {}
		requests.append({"path": path, "body": body})
		var res: Dictionary = handler.call(path, body if body is Dictionary else {})
		var payload := ""
		for ln in res.lines:
			var b: String = ln if ln is String else JSON.stringify(ln)
			payload += "%x\r\n%s\n\r\n" % [b.to_utf8_buffer().size() + 1, b]
		payload += "0\r\n\r\n"
		var code: int = res.code
		var out := "HTTP/1.1 %d X\r\nContent-Type: application/x-ndjson\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n%s" % [code, payload]
		p.put_data(out.to_utf8_buffer())
		c.close = 3


func msg_line(text: String, done := false) -> Dictionary:
	return {"model": "x", "message": {"role": "assistant", "content": text}, "done": done}


func tags_lines() -> Array:
	var ms: Array = []
	for n in [["llama3.2:3b", 2e9], ["gemma3:4b", 3.3e9], ["qwen2.5-coder:7b", 4.7e9], ["llama3.1:8b", 4.9e9], ["llama3.2-vision:latest", 7.8e9], ["qwen3:8b", 5.2e9]]:
		ms.append({"name": n[0], "size": n[1]})
	return [{"models": ms}]


## Réponse type du faux serveur : tags, et chat « Bonjour **monde** » en 3 jetons.
func default_handler(path: String, body: Dictionary) -> Dictionary:
	if path == "/api/tags":
		return {"code": 200, "lines": tags_lines()}
	if path == "/api/pull":
		return {"code": 200, "lines": [{"status": "pulling x", "total": 100, "completed": 50}, {"status": "pulling x", "total": 100, "completed": 100}, {"status": "success"}]}
	if path == "/api/chat":
		if body.get("model", "") == "absent":
			return {"code": 404, "lines": [{"error": "model 'absent' not found"}]}
		if body.get("stream", true) == false:
			return {"code": 200, "lines": [msg_line("Un beau titre", true)]}
		return {"code": 200, "lines": [msg_line("Bonjour "), msg_line("**monde** `x`"), msg_line("", true)]}
	return {"code": 404, "lines": []}


func wait_for(cond: Callable, max_frames := 400) -> bool:
	var g := 0
	while not cond.call() and g < max_frames:
		await frames(1)
		g += 1
	return cond.call()


# ------------------------------------------------------------------ UI : thème dynamique, nav, accueil, fiche, libellés

func label_check(page: Control, tag: String) -> void:
	var bad: PackedStringArray = []
	var stack: Array = [page]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Label and (n as Label).is_visible_in_tree() and (n as Label).text.length() >= 3:
			var l: Label = n
			var fs := l.get_theme_font_size("font_size")
			var need := minf(fs * 2.0, l.get_theme_font("font").get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.98)
			if l.size.x < need and l.size.x > 0.0:
				bad.append("«%s» %.0fpx" % [l.text.left(20), l.size.x])
	if not bad.is_empty() and OS.get_environment("GL_DBG") != "":
		print("DBG page ", page.size, " head ", page.head_title.size, page.head_title.get_parent().size, page.head_title.get_parent().get_parent().size, page.head_title.get_parent().get_parent().get_parent().size, " bp ", page.bp)
	check(bad.is_empty(), "libellés coupés (%s) : %s" % [tag, ", ".join(bad)])


func run_ui() -> void:
	# --- 8 univers : charte, thème global, signal et reconstruction des pages
	check(U.count() == 8, "8 assistants")
	var seen := {}
	for i in U.count():
		var u := U.get_u(i)
		seen[u.name] = true
		for k in ["id", "name", "role", "specialty", "accent", "bg", "card", "card_hi", "field", "motto", "model", "temp", "anim", "personality", "prompt"]:
			check(u.has(k), "assistant %d : champ %s" % [i, k])
		check(float(u.anim.speed) > 0.0 and float(u.anim.bounce) > 0.0, "assistant %d : personnalité d'animation" % i)
	check(seen.size() == 8, "noms uniques")
	check(U.get_u(0).role == "general" and U.get_u(1).role == "expert", "Goody généraliste, les autres experts")
	var changes := [0]
	ctx.theme_changed.connect(func(): changes[0] += 1)
	var home: Control = router.go_tab("home")
	await frames()
	for i in [3, 6, 1, 0, 7]:
		ctx.set_active(i)
		await frames(2)
		check(T.OK == Color(str(U.get_u(i).accent)) and T.BG == Color(str(U.get_u(i).bg)), "thème de l'univers %d appliqué" % i)
		check(router.bg.color == T.BG, "fond du routeur recoloré (%d)" % i)
	check(changes[0] == 5, "signal theme_changed émis à chaque changement")
	ctx.set_profile("Testeur", 4)
	await frames(2)
	check(T.OK == U.color(4) and ctx.active == 4, "profil : changer de mascotte recolore tout")
	var sh := U.shared_theme(4)
	check(sh.name == "Mauve" and sh.accent == "#b58bff" and sh.has("bg") and sh.has("card"), "bloc theme du profil partagé")
	check(U.pick_model(2, [{"name": "qwen2.5-coder:7b", "size": 1}, {"name": "gemma3:4b", "size": 1}]) == "qwen2.5-coder:7b", "modèle préféré")
	check(U.pick_model(2, ["gemma3:4b"]) == "gemma3:4b" and U.pick_model(7, ["llama3.2-vision:latest", "qwen3:8b", "gemma3:4b"]) == "gemma3:4b", "repli de modèle")
	check(U.pick_model(0, []) == "", "aucun modèle")
	ctx.set_active(0)
	await frames(2)

	# --- barre de navigation : 3 onglets, chat par défaut
	check(ctx.start_page() == "home", "les Apps sont la page de démarrage par défaut (l'assistant est une sous-app)")
	handler = default_handler
	for id in ["profile", "home", "chat", "home"]:
		var pg: Control = router.go_tab(id)
		await frames(2)
		check(router.current() == pg and router.nav.visible == (id != "chat") and (id == "chat" or router.nav.current == id), "onglet " + id)
		label_check(pg, "onglet " + id)
	router.go_tab("home")
	router.push("settings")
	await frames()
	check(not router.nav.visible, "barre masquée sur une page secondaire")
	router.back()
	await frames()
	check(router.nav.visible, "barre revenue")
	ctx.store.set_s("ui", "start", "chat")
	check(ctx.start_page() == "chat", "réglage de page de démarrage")
	ctx.store.set_s("ui", "start", "home")

	# --- Apps : grille adaptative avec 0, 1, 4 et 7 apps, de 360 à 1100 px
	for n in [0, 1, 4, 7]:
		for w in [360, 1100]:
			ctx.catalog.set_fake(fake_list(n))
			_host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			_host.size = Vector2(w, 800)
			await frames(3)
			check(home._list.get_child_count() > 0, "apps : %d apps, %d px" % [n, w])
			if n > 0:
				var g: Container = home._list.get_child(1)
				check(g.get_script() == K.Grid and g.get_child_count() == n, "grille adaptative (%d)" % n)
				check(g.columns == g.cols_for(g.size.x) and (w > 700 or g.columns <= 2), "colonnes adaptées à %d px : %d" % [w, g.columns])
				if w == 1100 and n >= 4:
					check(g.columns >= 3, "au moins 3 colonnes à 1100 px")
			label_check(home, "apps %d/%d" % [n, w])
	_host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ctx.catalog.set_fake([], "loading")
	await frames(2)
	check(home._list.get_child(0).get_script() == K.Grid, "chargement : cartes fantômes en grille")
	ctx.catalog.set_fake(fake_list(7))
	await frames(2)

	# --- fiche d'app : versions, APK, installée ou non, textes très longs, 360 px et 1100 px
	var long_name := "application-au-nom-vraiment-extremement-long-pour-tester-le-retour-a-la-ligne"
	var la := fake(long_name, "v1.0.0-beta.12345", "2026-03-01T00:00:00Z", true, true)
	la.manifest = {"tagline": "Une accroche interminable " + "mot ".repeat(40), "description": "Description " + "longue ".repeat(60)}
	la.repo = {"description": "Une accroche interminable " + "mot ".repeat(40), "license": "GPL-3.0-or-later", "stars": 12, "pushed_at": "2026-03-02T00:00:00Z"}
	var apps2 := fake_list(5)
	apps2.append(la)
	ctx.catalog.set_fake(apps2)
	ctx.store.installed["app-4"] = {"tag": "v1.4", "exe": "/tmp/none", "desk": true}
	for scenario in [["app-2", 0], ["app-1", 1], ["app-4", 5], [long_name, 5]]:
		for w in [360, 1100]:
			get_window().size = Vector2i(w, 760)
			await frames(3)
			var ap: Control = router.push("app", {"name": scenario[0]})
			await frames(2)
			ap._hist[scenario[0]] = _versions(scenario[1])
			ap.rebuild()
			await frames(3)
			check(ap.body.get_child_count() > 0, "fiche %s v=%d w=%d" % [str(scenario[0]).left(12), scenario[1], w])
			check(ap.body.get_child(0).get_script() == K.Split, "fiche : KSplit (%d)" % w)
			label_check(ap, "fiche %s %d" % [str(scenario[0]).left(10), w])
			router.back()
			await frames(2)
	get_window().size = Vector2i(1100, 720)
	await frames(2)
	for p in ["board", "chat_history", "chat_settings", "about", "settings", "profile"]:
		var pg2: Control = router.push(p)
		await frames(3)
		label_check(pg2, p)
		if router.stack.size() > 1:
			router.back()
		await frames(2)
	router.go_tab("home")
	ctx.catalog.set_fake(fake_list(3))
	await frames(2)


func _versions(n: int) -> Array:
	var l: Array = []
	for i in n:
		l.append({"tag": "v1.%d" % (n - i), "date": "2026-0%d-01T00:00:00Z" % (i + 1), "body": "## Nouveautés\n- version %d avec un texte plutôt long pour voir" % i})
	return l


# ------------------------------------------------------------------ Assistants : fonctions pures, streaming, délégation, historique

func run_assistants() -> void:
	# --- NDJSON (découpe incrémentale et lot)
	var sp := Ollama.split_lines('{"a":1}\n{"b":2}\n{"c"')
	check(sp.lines.size() == 2 and sp.rest == '{"c"', "NDJSON : fragment incomplet conservé")
	check(Ollama.parse_ndjson('{"a":1}\n\nnope\n{"b":2}\n').size() == 2, "NDJSON : lignes invalides ignorées")
	var pu := Ollama.parse_url("http://127.0.0.1:11434/")
	check(pu.host == "127.0.0.1" and pu.port == 11434 and not pu.tls, "URL Ollama")
	check(Ollama.wants_think_off("qwen3:8b") and not Ollama.wants_think_off("llama3.2:3b"), "think désactivé pour qwen3")
	check(Ollama.strip_think("<think>x</think>Salut") == "Salut" and Ollama.strip_think("a<think>pas fini") == "a", "balises <think> masquées")
	check(Ollama.supports_tools("llama3.1:8b") and not Ollama.supports_tools("gemma3:4b"), "modèles avec tools")
	check(not U.is_vision("llama3.2-vision:latest") and U.is_broken("llama3.2-vision") and U.is_vision("gemma3:4b") and not U.is_vision("llama3.2:3b"), "modèles vision")

	# --- Markdown -> BBCode
	var bb := MD.to_bbcode("# Titre\n**gras** *ital* `code [x]`\n- un\n1. deux\n[lien](https://a.b)", "4de1b4")
	check("[b]gras[/b]" in bb and "[i]ital[/i]" in bb and "[code]code [lb]x[rb][/code]" in bb, "Markdown : gras, italique, code")
	check("[font_size=24]" in bb and "•" in bb and "[url=https://a.b]lien[/url]" in bb, "Markdown : titre, liste, lien")
	var bl := MD.blocks("avant\n```gdscript\nvar a = 1\n```\naprès\n```\nouvert")
	check(bl.size() == 4 and bl[1].type == "code" and bl[1].lang == "gdscript" and bl[3].get("open", false), "Markdown : blocs de code (dont non fermé)")

	# --- Historique : stockage, groupement, recherche, export
	var store := Chats.new("user://gltest/chats_unit/")
	store.export_dir = ProjectSettings.globalize_path("user://gltest/export_unit")
	var now := Time.get_unix_time_from_system()
	var mk := func(title: String, age_days: float, ai: int, txt: String, pin := false) -> Dictionary:
		var c := Chats.new_chat(ai, "m")
		c.title = title
		c.pinned = pin
		c.updated = now - age_days * 86400.0
		c.id = "t%s_%d" % [title, ai]
		c.messages = [{"role": "user", "content": txt}, {"role": "assistant", "assistant": ai, "content": "réponse sur " + txt, "calls": [{"id": 1, "from": 0, "to": 2, "question": "q", "answer": "r"}]}]
		store.save(c)
		return c
	mk.call("Aujourd'hui", 0.0, 0, "alpha code godot")
	mk.call("Hier", 1.0, 2, "beta données")
	mk.call("Semaine", 4.0, 2, "gamma espagnol")
	mk.call("Ancien", 40.0, 5, "delta")
	mk.call("Epingle", 30.0, 3, "epsilon", true)
	store.load_index()
	check(store.index.size() == 5, "historique : 5 conversations persistées")
	var groups := Chats.group(store.index, now)
	var labels: Array = groups.map(func(g): return g[0])
	check(labels == ["Épinglées", "Aujourd'hui", "Hier", "Cette semaine", "Plus ancien"], "groupement : " + str(labels))
	check(Chats.search(store.index, "godot").size() == 1 and Chats.search(store.index, "réponse").size() == 5, "recherche plein texte")
	check(Chats.search(store.index, "", 2).size() == 2 and Chats.search(store.index, "beta", 2).size() == 1, "filtre par assistant")
	var c1 := store.load_chat("tHier_2")
	check(c1.messages.size() == 2 and c1.messages[1].calls.size() == 1, "conversation relue avec ses délégations")
	var md_path := store.export_md(c1)
	check(FileAccess.file_exists(md_path) and "demande à" in FileAccess.get_file_as_string(md_path), "export Markdown")
	var gone := store.delete("tHier_2")
	check(store.load_chat("tHier_2").is_empty() and store.index.size() == 4, "suppression")
	store.save(gone)
	check(not store.load_chat("tHier_2").is_empty(), "annulation de la suppression")
	var api := Chats.api_messages(c1, 0)
	check(api.size() == 2 and str(api[1].content).begins_with("(Bleu)"), "contexte : l'autre assistant est nommé")

	# --- Mentions, animations, repli <<ask>>, garde-fous
	check(U.parse_mention("@Bleu écris du code").index == 2 and U.parse_mention("@bleu").index == 2 and U.parse_mention("salut @Bleu").index == -1, "sélection par @mention")
	check(U.parse_mention("@Bleu écris du code").text == "écris du code", "texte après la mention")
	check(U.anim_for("talk") == "talk" and U.anim_for("done") == "happy" and U.anim_for("error") == "sad" and U.anim_for("zzz") == "idle", "mapping des animations")
	var pa := Orchestra.parse_ask("Je demande. <<ask:Bleu>> Écris une fonction <</ask>> merci")
	check(pa.asks.size() == 1 and pa.asks[0].name == "Bleu" and "fonction" in pa.asks[0].question and "<<" not in pa.clean, "repli texte <<ask>>")
	check(Orchestra.visible_text("abc <<ask:Bleu>> q") == "abc" and Orchestra.visible_text("abc <<a") == "abc" and Orchestra.visible_text("a < b") == "a < b", "balises masquées pendant le streaming")
	check(Orchestra.guard([0], 0, 0, 0) != "" and Orchestra.guard([0, 2], 0, 1, 0) != "" and Orchestra.guard([0], 2, 2, 0) != "" and Orchestra.guard([0], 2, 0, 4) != "" and Orchestra.guard([0], 2, 0, 0) == "" and Orchestra.guard([0], -1, 0, 0) != "", "garde-fous : auto-appel, boucle, profondeur, budget")
	var ts := Orchestra.tool_schema([0, 2])
	check(ts[0].function.name == "ask_assistant" and not ("Goody" in ts[0].function.parameters.properties.nom.enum) and "Rosie" in ts[0].function.parameters.properties.nom.enum, "outil ask_assistant sans la chaîne")

	# --- Streaming réel contre le faux serveur
	handler = default_handler
	var req := ctx.ollama.chat("llama3.2:3b", [{"role": "user", "content": "salut"}], {"temperature": 0.5}, [], true)
	var toks: Array = []
	req.line.connect(func(d): toks.append(str(d.get("message", {}).get("content", ""))))
	var r: Array = await req.finished
	check(r[0] and toks.size() == 3 and toks[0] == "Bonjour ", "streaming NDJSON par HTTPClient")
	check(requests.back().body.options.temperature == 0.5 and requests.back().body.stream == true and not requests.back().body.has("think"), "requête /api/chat")
	await ctx.ollama.collect(ctx.ollama.chat("qwen3:8b", [], {}, [], true))
	check(requests.back().body.get("think", true) == false, "qwen3 : think=false envoyé")
	var rm: Array = await ctx.ollama.collect(ctx.ollama.chat("absent", [], {}))
	check(not rm[0] and rm[1] == "model_missing", "modèle absent détecté")
	var tg: Array = await ctx.ollama.collect(ctx.ollama.tags())
	check(tg[0] and tg[3][0].models.size() == 6, "/api/tags")
	var old_url := ctx.ollama.base_url
	ctx.ollama.base_url = "http://127.0.0.1:1"
	var off: Array = await ctx.ollama.collect(ctx.ollama.tags())
	check(not off[0] and off[1] == "offline", "Ollama éteint -> offline")
	ctx.ollama.base_url = old_url

	# --- Orchestre : délégation par tool-calling puis repli texte
	handler = func(path: String, body: Dictionary) -> Dictionary:
		if path != "/api/chat":
			return default_handler.call(path, body)
		var sysmsg: String = body.messages[0].content
		var last: Dictionary = body.messages.back()
		if "Tu es Bleu" in sysmsg:
			return {"code": 200, "lines": [msg_line("func f(): pass"), msg_line("", true)]}
		if last.role == "tool":
			return {"code": 200, "lines": [msg_line("Voici : " + str(last.content)), msg_line("", true)]}
		return {"code": 200, "lines": [{"message": {"role": "assistant", "content": "", "tool_calls": [{"function": {"name": "ask_assistant", "arguments": {"nom": "Bleu", "question": "écris f"}}}]}, "done": true}]}
	var evs: Array = []
	var orch: Orchestra = ctx.orchestra
	orch.allow = true
	orch.resolve_model = func(_a: int) -> String: return "llama3.1:8b"
	orch.event.connect(func(k, d): evs.append([k, d]))
	orch.run(0, [{"role": "user", "content": "code ?"}])
	await wait_for(func(): return not orch.running)
	var kinds: Array = evs.map(func(e): return e[0])
	check("card_open" in kinds and "card_done" in kinds and kinds.back() == "done", "délégation Goody -> Bleu (tools) : " + str(kinds.size()))
	check(evs.filter(func(e): return e[0] == "done").back()[1].text.contains("func f()"), "Goody synthétise la réponse de Bleu")
	check(orch.cards.size() == 1 and orch.cards[0].answer.contains("func f()"), "réponse de Bleu conservée dans la carte")
	check(evs.any(func(e): return e[0] == "speaker" and e[1].ai == 0 and e[1].mode == "call") and evs.any(func(e): return e[0] == "speaker" and e[1].ai == 2 and e[1].mode == "listen"), "mascottes : call / listen")
	# repli texte (modèle sans tools)
	evs.clear()
	handler = func(path: String, body: Dictionary) -> Dictionary:
		if path != "/api/chat":
			return default_handler.call(path, body)
		var sysmsg2: String = body.messages[0].content
		if "Tu es Bleu" in sysmsg2:
			return {"code": 200, "lines": [msg_line("print(1)"), msg_line("", true)]}
		if body.messages.back().content.contains("Réponse de Bleu"):
			return {"code": 200, "lines": [msg_line("Synthèse finale"), msg_line("", true)]}
		return {"code": 200, "lines": [msg_line("<<ask:Bleu>> écris un print <</ask>>"), msg_line("", true)]}
	orch.resolve_model = func(_a: int) -> String: return "gemma3:4b"
	orch.run(0, [{"role": "user", "content": "code ?"}])
	await wait_for(func(): return not orch.running)
	var done_ev: Array = evs.filter(func(e): return e[0] == "done")
	check(not done_ev.is_empty() and "Synthèse finale" in done_ev[0][1].text and "<<" not in done_ev[0][1].text, "repli texte <<ask>> exécuté")
	check(not requests.filter(func(q): return q.path == "/api/chat" and q.body.get("tools") != null and q.body.model == "gemma3:4b").size() > 0, "pas de tools envoyés au modèle sans tools")
	# boucle : Bleu tente d'appeler Goody -> refusé
	evs.clear()
	handler = func(path: String, body: Dictionary) -> Dictionary:
		if path != "/api/chat":
			return default_handler.call(path, body)
		var sysmsg3: String = body.messages[0].content
		if "Tu es Bleu" in sysmsg3:
			return {"code": 200, "lines": [msg_line("<<ask:Goody>> reviens <</ask>>"), msg_line("", true)]}
		if "Réponse de" in str(body.messages.back().content):
			return {"code": 200, "lines": [msg_line("ok fini"), msg_line("", true)]}
		return {"code": 200, "lines": [msg_line("<<ask:Bleu>> vas-y <</ask>>"), msg_line("", true)]}
	orch.run(0, [{"role": "user", "content": "x"}])
	await wait_for(func(): return not orch.running)
	check(orch.calls_used == 1 and evs.any(func(e): return e[0] == "notice" and "Refusé" in e[1].text), "boucle A->B->A refusée")
	check(evs.back()[0] == "done", "la boucle se termine proprement")
	# stop global
	evs.clear()
	orch.run(0, [{"role": "user", "content": "x"}])
	await frames(1)
	orch.stop()
	await wait_for(func(): return not orch.running)
	check(evs.any(func(e): return e[0] == "stopped"), "bouton Stop global")
	orch.allow = true

	# --- Page Chat : état, envoi en streaming, Markdown, assistants, historique, pièces jointes
	handler = default_handler
	ctx.models = []
	var chp: Control = router.go_tab("chat")
	await wait_for(func(): return chp.status == "ready" and not ctx.models.is_empty())
	check(chp.status == "ready" and not ctx.models.is_empty(), "chat : modèles listés (%s, %d, %s)" % [chp.status, ctx.models.size(), ctx.ollama.base_url])
	chp.new_chat()
	check(chp.chat.assistant == 0 and chp.current_model() == "llama3.1:8b", "Goody : modèle préféré")
	check(chp.strip.tiles.size() == 8, "bandeau de 8 assistants")
	check(chp.send_text("Salut"), "envoi")
	await wait_for(func(): return not chp.generating)
	check(chp.chat.messages.size() == 2 and "Bonjour" in chp.chat.messages[1].content, "réponse streamée enregistrée")
	check(chp.refs.has(1) and chp.refs[1].segs.size() >= 1, "réponse rendue (Markdown)")
	await frames(4)
	check(not ctx.chats.load_chat(chp.chat.id).is_empty(), "conversation persistée")
	await wait_for(func(): return chp.chat.get("titled", false) and chp.chat.title == "Un beau titre")
	check(chp.chat.title == "Un beau titre", "titre automatique généré par le modèle")
	chp.switch_assistant(2)
	await frames(3)
	check(chp.chat.assistant == 2 and chp.chat.messages.back().role == "note" and "Bleu rejoint" in chp.chat.messages.back().text, "changer d'assistant : ligne « rejoint la conversation »")
	check(T.OK == U.color(2) and ctx.active == 2, "thème suit l'assistant actif")
	check(chp.current_model() == "qwen2.5-coder:7b", "Bleu : modèle code")
	check(chp.send_text("@Rosie corrige ce texte"), "envoi avec @mention")
	await wait_for(func(): return not chp.generating)
	check(chp.chat.assistant == 1 and chp.chat.messages[chp.chat.messages.size() - 2].content == "corrige ce texte", "@mention bascule l'assistant")
	await frames(2)
	# régénérer / éditer
	var n_before: int = chp.chat.messages.size()
	chp.regenerate()
	await wait_for(func(): return not chp.generating)
	check(chp.chat.messages.size() == n_before, "régénérer remplace la réponse")
	chp._edit_last(chp.chat.messages.size() - 2)
	check(chp.input.text == "corrige ce texte", "éditer le dernier message")
	# pièces jointes
	var tf := "user://gltest/pj.csv"
	FileAccess.open(tf, FileAccess.WRITE).store_string("a,b\n" + "1,2\n".repeat(20000))
	var at := Attach.read(ProjectSettings.globalize_path(tf))
	check(at.kind == "text" and at.truncated and at.chars == Attach.MAX_TEXT, "fichier texte tronqué avec avertissement")
	var img := Image.create(64, 48, false, Image.FORMAT_RGB8)
	img.fill(Color.RED)
	img.save_png("user://gltest/pj.png")
	var ai_ := Attach.read(ProjectSettings.globalize_path("user://gltest/pj.png"))
	check(ai_.kind == "image" and ai_.b64.length() > 50 and ai_.tex != null, "image en base64 + vignette")
	check(Attach.read("/nonexistent/x.txt").kind == "bad", "fichier introuvable")
	chp.switch_assistant(0)
	await frames(2)
	chp.attach_files(PackedStringArray([ProjectSettings.globalize_path("user://gltest/pj.png")]))
	check(chp.attachments.is_empty(), "image refusée si le modèle n'est pas vision")
	chp.attach_files(PackedStringArray([ProjectSettings.globalize_path(tf)]))
	check(chp.attachments.size() == 1 and chp.chips.visible, "puce de fichier joint")
	chp.switch_assistant(7)
	await frames(2)
	check(U.is_vision(chp.current_model()), "Brume : modèle vision")
	chp.attach_files(PackedStringArray([ProjectSettings.globalize_path("user://gltest/pj.png")]))
	check(chp.attachments.size() == 2, "image acceptée avec un modèle vision")
	chp.send_text("décris")
	await wait_for(func(): return not chp.generating)
	var um: Dictionary = chp.chat.messages[chp.chat.messages.size() - 2]
	check(um.images.size() == 1 and um.files.size() == 1 and requests.back().body.messages.back().has("images"), "images envoyées en base64, fichier inséré")
	# erreurs : modèle absent -> message clair
	chp.chat["model"] = "absent"
	chp.send_text("test")
	await wait_for(func(): return not chp.generating)
	await frames(2)
	check(chp.msgs.get_child_count() > 0, "erreur modèle absent affichée")
	chp.chat["model"] = ""
	# Ollama éteint -> état vide + Réessayer
	ctx.ollama.base_url = "http://127.0.0.1:1"
	chp.new_chat()
	chp.status = "init"
	chp._refresh_models()
	await wait_for(func(): return chp.status == "offline")
	check(chp.status == "offline" and chp.msgs.get_child(1) is W.StateView, "Ollama éteint : état vide avec mascotte triste")
	ctx.ollama.base_url = old_url
	chp.status = "init"
	chp._refresh_models()
	await wait_for(func(): return chp.status == "ready")
	# historique et réglages (pages)
	var hp: Control = router.push("chat_history")
	await frames(3)
	check(hp._list.get_child_count() > 0, "page Conversations")
	hp.query = "Salut"
	hp._render()
	hp.set_filter(0)
	await frames(2)
	var some: Dictionary = ctx.chats.index[0]
	hp._pin(some)
	hp._delete(some.id)
	await frames(2)
	check(ctx.chats.load_chat(some.id).is_empty(), "suppression depuis l'historique")
	router.back()
	await frames(2)
	var cs: Control = router.push("chat_settings")
	await frames(3)
	cs.start_pull("llama3.2:3b")
	await wait_for(func(): return ctx.pull.get("done", false))
	check(ctx.pull.get("ratio", 0.0) == 1.0 and ctx.pull.error == "", "téléchargement de modèle (/api/pull) avec progression")
	router.back()
	await frames(2)
	ctx.store.cfg.set_value("chat", "temp_set", false)
	router.go_tab("home")
	await frames(2)


# ------------------------------------------------------------------ Test réel Ollama (GL_TEST_OLLAMA=1)

func run_live() -> void:
	ctx.ollama.base_url = "http://127.0.0.1:11434"
	var tg: Array = await ctx.ollama.collect(ctx.ollama.tags())
	var has := false
	if tg[0] and not tg[3].is_empty():
		for m in tg[3][0].get("models", []):
			if str(m.name).begins_with("llama3.2:3b"):
				has = true
	if not has:
		print("Ollama réel : llama3.2:3b absent, test ignoré")
		return
	var req := ctx.ollama.chat("llama3.2:3b", [{"role": "user", "content": "Réponds juste par un mot : bonjour ?"}], {"temperature": 0.2, "num_predict": 24}, [], true)
	var n := [0]
	req.line.connect(func(d):
		if str(d.get("message", {}).get("content", "")) != "":
			n[0] += 1)
	var r: Array = await req.finished
	check(r[0] and n[0] >= 2, "Ollama réel : jetons reçus en streaming (%d)" % n[0])
	# délégation Goody -> Bleu avec un petit modèle
	var orch: Orchestra = ctx.orchestra
	orch.allow = true
	orch.opts = {"num_ctx": 4096, "temperature": 0.2}
	orch.resolve_model = func(_a: int) -> String: return "llama3.2:3b"
	var evs: Array = []
	orch.event.connect(func(k, d): evs.append([k, d]))
	orch.run(0, [{"role": "user", "content": "Demande à Bleu (utilise l'outil ask_assistant) d'écrire une fonction GDScript qui additionne deux entiers, puis résume sa réponse."}])
	await wait_for(func(): return not orch.running, 4000)
	var kinds: Array = evs.map(func(e): return e[0])
	check("done" in kinds or "error" in kinds, "Ollama réel : l'orchestre termine")
	check("done" in kinds, "Ollama réel : pas d'erreur (%s)" % str(evs.filter(func(e): return e[0] == "error")))
	print("Ollama réel : délégations = ", orch.cards.size(), " ; événements = ", kinds.size())


# ------------------------------------------------------------------ Lint du kit sur toutes les pages et popups (320 -> 1600 px)

func lint_report(defects: Array, what: String) -> void:
	var seen := {}
	for d in defects:
		var k := str(d)
		k = k.substr(k.find("]") + 1)
		k = k.substr(0, 110)
		if not seen.has(k):
			seen[k] = true
			if seen.size() <= int(OS.get_environment("GL_LINT_N") if OS.get_environment("GL_LINT_N") != "" else "6"):
				printerr("LINT ", str(d).left(220))
	check(defects.is_empty(), "lint %s : %d défauts (%d uniques)" % [what, defects.size(), seen.size()])


func run_lint(host: Control) -> void:
	router.instant = true
	var sizes := {0: [], 1: [fake("une-app-au-nom-vraiment-tres-long-pour-tester-les-coupures-de-texte", "v1.0.0-beta.12", "2026-01-01T00:00:00Z", true, true)], 7: fake_list(7)}
	ctx.store.installed.clear()
	ctx.store.installed["app-0"] = {"tag": "v0.9", "exe": "/tmp/none", "desk": false}
	var widths := Lint.T.WIDTHS_TEST if OS.get_environment("GL_LINT_FAST") != "1" else [360, 1100]
	for n in [0, 1, 7]:
		ctx.catalog.set_fake(sizes[n])
		for id in ["home", "chat", "profile", "settings", "about", "welcome", "board", "chat_history", "chat_settings", "app", "kit"]:
			if id == "kit" and not Router.PAGES.has("kit"):
				continue
			var args := {"name": sizes[n][0].name} if (id == "app" and n > 0) else {}
			if id == "app" and n == 0:
				continue
			if OS.get_environment("GL_LINT_ONLY") != "" and not (id in OS.get_environment("GL_LINT_ONLY").split(",")):
				continue
			if OS.get_environment("GL_LINT_N7") != "" and n != int(OS.get_environment("GL_LINT_N7")):
				continue
			var pg: Control = router.go_tab(id, args) if id in Router.TABS else router.reset(id, args)
			for sp in router.stage.get_children():
				sp.visible = sp == pg
			for tw in get_tree().get_processed_tweens():
				tw.kill()
			pg.position = Vector2.ZERO
			pg.modulate.a = 1.0
			await frames(2)
			if OS.get_environment("GL_LINT_DBG") != "":
				print("DBG ", get_tree().get_processed_tweens().size(), id, pg.position, pg.get_parent().position, pg.get_parent().get_parent().position, router.instant, host.position, host.get_global_rect())
			var d: Array = await Lint.sweep(host, host, widths, get_tree(), "%s/%d apps" % [id, n])
			lint_report(d, "page %s (%d apps)" % [id, n])
	router.reset("home")
	await frames(2)
	# popups du kit avec contenu long
	for kind in ["modal", "danger", "sheet", "menu", "toast"]:
		if OS.get_environment("GL_LINT_ONLY") != "":
			break
		var cov := [0]
		var make := func() -> Control:
			var m: Control
			match kind:
				"sheet":
					m = K.Sheet.new()
				_:
					m = K.Modal.new()
			m.set_meta("instant", true)
			m.title = "Titre assez long pour vérifier le retour à la ligne dans une modale étroite"
			m.danger = kind == "danger"
			m.add_text("Un message tout aussi long qui doit passer à la ligne sans jamais être coupé ni déborder de la carte, quelle que soit la largeur.")
			m.add_button("Annuler", "secondary", "")
			m.add_button("Supprimer définitivement", "danger" if kind == "danger" else "primary", "ok")
			return m
		var node: Control
		if kind == "menu":
			node = K.Menu.open(host, [{"id": "a", "label": "Renommer la conversation", "icon": "pencil"}, {"sep": true}, {"id": "b", "label": "Supprimer", "icon": "trash-2", "danger": true}], Rect2(host.size.x - 60, 60, 44, 44))
			node.set_meta("instant", true)
		elif kind == "toast":
			node = K.Toast.new()
			node.instant = true
			host.add_child(node)
			node.push("Une notification avec un texte assez long pour passer à la ligne", "success", "Annuler", Callable())
		else:
			node = make.call()
			node.popup(host)
		var d2: Array = await Lint.sweep(host, node, Lint.T.WIDTHS_TEST, get_tree(), "popup " + kind)
		lint_report(d2, "popup " + kind)
		node.queue_free()
		await frames(2)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await frames(2)


# ------------------------------------------------------------------ Modèle incompatible (mllama) : repli automatique + message lisible

func run_models() -> void:
	handler = func(path: String, body: Dictionary) -> Dictionary:
		if path == "/api/chat" and body.get("model", "") == "llama3.1:8b":
			return {"code": 500, "lines": [{"error": "llama-server process has terminated: error loading model: unknown model architecture: 'mllama'"}]}
		return default_handler.call(path, body)
	ctx.models = [{"name": "llama3.1:8b", "size": 1.0}, {"name": "gemma3:4b", "size": 2.0}]
	ctx.ollama.bad_models.clear()
	var evs: Array = []
	var orch: Orchestra = ctx.orchestra
	orch.allow = false
	orch.resolve_model = func(a: int) -> String: return ctx.model_for(a)
	orch.event.connect(func(k, d): evs.append([k, d]))
	check(ctx.model_for(0) == "llama3.1:8b", "avant l'échec : modèle le plus léger")
	orch.run(0, [{"role": "user", "content": "salut"}])
	await wait_for(func(): return not orch.running)
	if OS.get_environment("GL_DBG") != "":
		print("DBGM ", evs.map(func(e): return [e[0], str(e[1]).left(120)]), ctx.ollama.bad_models)
	check("llama3.1:8b" in ctx.ollama.bad_models and ctx.model_for(0) != "llama3.1:8b" and ctx.model_for(0) != "", "modèle en échec exclu, repli sur un autre modèle")
	check(evs.any(func(e): return e[0] == "notice" and "bascule sur" in str(e[1].text)), "toast discret de bascule")
	check(evs.any(func(e): return e[0] == "done" and "Bonjour" in str(e[1].text)), "la réponse arrive après le repli")
	check(not evs.any(func(e): return e[0] == "error"), "pas d'erreur visible après repli")
	var fi: String = Ollama.friendly("unsupported", "unknown model architecture: 'mllama'", "weird:7b", "0.33.1")
	check("pas pris en charge" in fi and "0.33.1" in fi and "Choisis-en un autre" in fi, "message lisible : architecture inconnue")
	check("n'est pas installé" in Ollama.friendly("model_missing", "", "x") and "mémoire" in Ollama.friendly("memory", "") and "injoignable" in Ollama.friendly("offline", ""), "messages : absent / mémoire / éteint")
	check(U.is_broken("llama3.2-vision:latest") and not U.is_vision("llama3.2-vision:latest") and U.get_u(7).model == "gemma3:4b", "Brume sur gemma3:4b, mllama écarté")
	orch.event.get_connections().map(func(c): orch.event.disconnect(c.callable))
	ctx.ollama.bad_models.clear()
	handler = default_handler
