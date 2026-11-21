extends Node
## Test headless sans réseau : GL_TEST=1 flatpak run --env=GL_TEST=1 org.godotengine.Godot --headless --path . 
## Charge chaque page avec un catalogue factice, simule navigation, états et installation. Affiche « OK » ou les échecs.

const Ctx := preload("res://core/ctx.gd")
const Router := preload("res://ui/router.gd")
const Store := preload("res://core/store.gd")
const Catalog := preload("res://core/catalog.gd")

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


func run(host: Node) -> void:
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
	check(home._avatar.badge, "badge sur l'avatar")
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
	pr.body.get_child(0).edit.text = "Testeur"
	pr.body.get_child(0).commit()
	check(ctx.store.pseudo == "Testeur" and ctx.store.avatar == 2, "profil enregistré")
	router.back()
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
	check(ctx.store.welcomed and router.current().get_script() == Router.PAGES["home"], "fin de bienvenue -> accueil")

	# --- transitions animées (sans instant) : pas d'erreur
	router.instant = false
	router.push("settings")
	await get_tree().create_timer(0.4).timeout
	router.back()
	await get_tree().create_timer(0.4).timeout
	check(router.stack.size() == 1, "transitions")

	if fails.is_empty():
		print("OK")
		get_tree().quit(0)
	else:
		print("ECHECS : ", ", ".join(fails))
		get_tree().quit(1)
