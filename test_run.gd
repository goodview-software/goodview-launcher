extends Node
## Test headless sans réseau : GL_TEST=1 flatpak run --env=GL_TEST=1 org.godotengine.Godot --headless --path . 
## Charge chaque page avec un catalogue factice, simule navigation, états et installation. Affiche « OK » ou les échecs.

const Ctx := preload("res://core/ctx.gd")
const Router := preload("res://ui/router.gd")
const Store := preload("res://core/store.gd")
const Catalog := preload("res://core/catalog.gd")
const T := preload("res://ui/theme.gd")
const U := preload("res://ui/universe.gd")
const W := preload("res://ui/widgets.gd")
const Lint := preload("res://kit/lint.gd")
const K := preload("res://kit/k.gd")

var fails: PackedStringArray = []
var ctx: Ctx
var router: Router


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
	check(ctx.installer.running() is Dictionary, "installer.running() lisible (anti-doublon au lancement)")
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
	await run_lint(host)

	if fails.is_empty():
		print("OK")
		get_tree().quit(0)
	else:
		print("ECHECS : ", ", ".join(fails))
		get_tree().quit(1)


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
	check(U.get_u(0).prompt == "" and U.system_prompt(0, false) == "", "aucun prompt de base")
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
	check(U.pick_model(2, [{"name": "llama3.1:8b", "size": 1}, {"name": "gemma3:4b", "size": 1}]) == "llama3.1:8b", "modèle préféré")
	check(U.pick_model(2, ["gemma3:4b"]) == "gemma3:4b" and U.pick_model(7, ["llama3.2-vision:latest", "qwen3:8b", "gemma3:4b"]) == "gemma3:4b", "repli de modèle")
	check(U.pick_model(0, []) == "", "aucun modèle")
	ctx.set_active(0)
	await frames(2)

	# --- barre de navigation : 2 onglets
	check(ctx.start_page() == "home", "les Apps sont la page de démarrage par défaut (l'assistant est une sous-app)")
	for id in ["profile", "home"]:
		var pg: Control = router.go_tab(id)
		await frames(2)
		check(router.current() == pg and router.nav.visible and router.nav.current == id, "onglet " + id)
		label_check(pg, "onglet " + id)
	router.go_tab("home")
	router.push("settings")
	await frames()
	check(not router.nav.visible, "barre masquée sur une page secondaire")
	router.back()
	await frames()
	check(router.nav.visible, "barre revenue")

	# --- Apps : grille adaptative avec 0, 1, 4 et 7 apps, de 360 à 1100 px
	for n in [0, 1, 4, 7]:
		for w in [360, 1100]:
			ctx.catalog.set_fake(fake_list(n))
			_host.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
			_host.size = Vector2(w, 800)
			await frames(3)
			check(home._list.get_child_count() > 0, "apps : %d apps, %d px" % [n, w])
			if n > 0:
				var g: Container = home._list.get_child(0)
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
	for p in ["about", "settings", "profile"]:
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
		for id in ["home", "profile", "settings", "about", "welcome", "app", "kit"]:
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
