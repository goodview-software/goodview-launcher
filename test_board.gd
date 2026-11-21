extends RefCounted
## Tests du plan (moteur de scène façon Excalidraw) : création, sélection, déplacement, redimensionnement, rotation,
## flèches liées, historique, presse-papiers, groupes, migration v1, sauvegarde, performance. Appelé par test_run.gd.

const Geom := preload("res://ui/draw/geom.gd")
const Scene := preload("res://ui/draw/scene.gd")
const Chat := preload("res://ui/draw/chat.gd")
const Render := preload("res://ui/draw/render.gd")
const Surface := preload("res://ui/draw/surface.gd")

var t  # le test_run (check, frames, router)
var b  # la page Plan
var sc
var S
var tl


func mb(pressed: bool, shift := false, alt := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.shift_pressed = shift
	e.alt_pressed = alt
	return e


func mm(shift := false, alt := false) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.shift_pressed = shift
	e.alt_pressed = alt
	return e


## Geste complet souris : appui en a, déplacements, relâchement en c (coordonnées du canevas).
func drag(a: Vector2, c: Vector2, shift := false, alt := false) -> void:
	tl.press(a, mb(true, shift, alt))
	for i in 4:
		tl.motion(a.lerp(c, (i + 1) / 4.0), mm(shift, alt))
	tl.release(c, mb(false, shift, alt))


func add(type: String, x: float, y: float, w: float, h: float) -> Dictionary:
	var el: Dictionary = sc.make(type, x, y)
	el.w = w
	el.h = h
	sc.add(el)
	sc.commit()
	return el


func run(test, host_page) -> void:
	t = test
	b = host_page
	# plan temporaire : ne jamais toucher aux vrais plans de l'utilisateur
	b.plans = [{"id": "ptest_tmp", "name": "Test"}]
	b.plan_id = "ptest_tmp"
	b._dirty = false
	b._clear_nodes()
	DirAccess.remove_absolute(b._plan_file())
	b._load()
	sc = b.scene
	S = b.canvas
	tl = S.tools
	await t.frames(2)
	S.set_view(Vector2.ZERO, 1.0)
	S.size = Vector2(1000, 700)
	t.check(sc.els.is_empty() and sc.can_undo() == false, "plan : scène vide au départ")

	# --- création de chaque type
	var types := ["rectangle", "diamond", "ellipse", "arrow", "line", "freedraw", "text", "frame"]
	for ty in types:
		var el: Dictionary = sc.make(ty, 40.0 + sc.els.size() * 10, 40)
		el.w = 80.0
		el.h = 60.0
		if ty in ["arrow", "line", "freedraw"]:
			Geom.set_world_pts(el, PackedVector2Array([Vector2(el.x, el.y), Vector2(el.x + 80, el.y + 60), Vector2(el.x + 120, el.y + 20)]))
		if ty == "text":
			el.text = "Bonjour"
			Geom.fit_text(el)
		sc.add(el)
		var c := Geom.build(sc, el)
		t.check(not c.is_empty(), "type %s : cache construit" % ty)
	sc.commit()
	var z: Dictionary = b._add_zone("note", "Zone test", Vector2(600, 300))
	t.check(b.nodes.has(z.id) and b.zones().size() == 1 and sc.get_el(z.id).type == "zone", "zone : élément + nœud hébergé")
	var img: Dictionary = sc.make("image", 300, 400)
	img.w = 100.0
	img.h = 80.0
	sc.add(img)
	sc.commit()
	t.check(sc.els.size() == types.size() + 2, "création : %d éléments" % sc.els.size())
	S.partition()
	t.check(S.vis_back.size() + S.vis_front.size() > 0, "culling : éléments visibles répartis")
	await t.frames(2)
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	t.check(sc.els.is_empty() and b.nodes.is_empty(), "clear : scène et zones vidées")

	# --- déplacement, annulation
	var r1 := add("rectangle", 100, 100, 100, 100)
	sc.reset_history()
	tl.set_tool("select")
	drag(Vector2(100, 150), Vector2(160, 180))
	t.check(sc.sel.has(r1.id), "clic : sélectionne")
	t.check(absf(float(r1.x) - 160.0) < 8.0 and absf(float(r1.y) - 130.0) < 8.0, "déplacement : (%.0f, %.0f)" % [r1.x, r1.y])
	var moved_x: float = r1.x
	t.check(sc.can_undo(), "déplacement : historique")
	tl.undo()
	t.check(absf(float(r1.x) - 100.0) < 0.01, "annuler : retour à x=100")
	tl.redo()
	t.check(absf(float(r1.x) - moved_x) < 0.01, "rétablir : x=%.0f" % moved_x)
	sc.clear_sel()

	# --- marquee
	var r2 := add("ellipse", 400, 100, 60, 60)
	tl.set_tool("select")
	drag(Vector2(80, 80), Vector2(480, 270))
	t.check(sc.sel.has(r1.id) and sc.sel.has(r2.id), "marquee : sélectionne les deux")
	drag(Vector2(700, 600), Vector2(720, 620))
	t.check(sc.sel.is_empty(), "clic dans le vide : désélectionne")

	# --- redimensionnement par poignée
	sc.select([r2.id])
	var w0: float = r2.w
	var fr: Dictionary = tl.sel_frame()
	var se := Vector2.ZERO
	for hd in fr.handles:
		if hd.name == "se":
			se = hd.pos
	t.check(se != Vector2.ZERO, "poignée se présente")
	drag(se, se + Vector2(40, 30))
	t.check(float(r2.w) > w0 + 30.0 and float(r2.h) > 60.0 + 20.0, "redimensionnement : %.0fx%.0f" % [r2.w, r2.h])
	# --- rotation
	fr = tl.sel_frame()
	var rot := Vector2.ZERO
	for hd in fr.handles:
		if hd.name == "rot":
			rot = hd.pos
	t.check(rot != Vector2.ZERO, "poignée de rotation présente")
	var c2 = S.w2c(Geom.center(r2))
	drag(rot, c2 + Vector2(120, 0))
	t.check(absf(float(r2.angle)) > 0.5, "rotation : %.2f rad" % float(r2.angle))
	tl.undo()
	t.check(absf(float(r2.angle)) < 0.01, "rotation annulée")
	sc.clear_sel()

	# --- flèche liée qui suit sa cible
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	var ra := add("rectangle", 100, 300, 100, 80)
	var rb := add("rectangle", 500, 300, 100, 80)
	tl.set_tool("arrow")
	drag(Vector2(150, 340), Vector2(550, 340))
	var arr: Dictionary = {}
	for e in sc.els:
		if e.type == "arrow":
			arr = e
	t.check(not arr.is_empty() and arr.start == ra.id and arr.end == rb.id, "flèche : liée aux deux formes")
	t.check(tl.tool == "select", "outil : retour à Sélection après tracé")
	var wp0 := Geom.world_pts(arr)
	var end0: Vector2 = wp0[wp0.size() - 1]
	sc.select([rb.id])
	tl.nudge(Vector2(0, 100))
	var wp1 := Geom.world_pts(arr)
	t.check(absf(wp1[wp1.size() - 1].y - end0.y) > 30.0 or absf(wp1[wp1.size() - 1].x - end0.x) > 5.0, "flèche liée suit la cible déplacée")
	tl.undo()
	t.check(absf(float(rb.y) - 300.0) < 0.01, "undo du déplacement de la cible")
	var arr_n := 0
	for e in sc.els:
		if e.type == "arrow":
			arr_n += 1
	t.check(arr_n == 1, "undo : la flèche est toujours là")

	# --- copier / coller / groupes / ordre / suppression
	sc.select([ra.id, rb.id])
	var n0: int = sc.els.size()
	tl.copy()
	tl.paste()
	t.check(sc.els.size() == n0 + 2, "copier-coller : +2 éléments")
	tl.undo()
	t.check(sc.els.size() == n0, "coller annulé")
	sc.select([ra.id, rb.id])
	tl.group_sel()
	sc.clear_sel()
	sc.select([ra.id])
	t.check(sc.sel.has(rb.id), "groupe : la sélection s'étend")
	tl.ungroup_sel()
	sc.clear_sel()
	sc.select([ra.id])
	t.check(not sc.sel.has(rb.id), "dégroupé")
	var i0: int = sc.els.find(ra)
	tl.order("front")
	t.check(sc.els.back() == ra and sc.els.find(ra) != i0, "ordre : premier plan")
	tl.undo()
	t.check(sc.els.find(ra) == i0, "ordre annulé")
	tl.delete_sel()
	t.check(sc.get_el(ra.id).is_empty(), "suppression")
	tl.undo()
	t.check(not sc.get_el(ra.id).is_empty(), "suppression annulée")

	# --- texte direct sur le canevas
	S.edit_new_text(Vector2(300, 500))
	S.ed.text = "Salut"
	S.edit_commit()
	var found := false
	for e in sc.els:
		if e.type == "text" and e.text == "Salut" and float(e.w) > 5.0:
			found = true
	t.check(found, "texte : créé par l'éditeur direct")

	# --- zones : fils, contexte IA, annuler/rétablir
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	var za: Dictionary = b._add_zone("ideas", "Idées", Vector2(50, 50))
	var zb: Dictionary = b._add_zone("decision", "Choix", Vector2(600, 50))
	za.msgs = [{"role": "user", "content": "voyage"}, {"role": "assistant", "content": "Lisbonne"}]
	tl.set_tool("arrow")
	drag(S.w2c(Geom.center(za)), S.w2c(Geom.center(zb)))
	var lk: Array = b.links()
	t.check(lk.size() == 1 and lk[0].from == za.id and lk[0].to == zb.id and lk[0].type == "feed", "fil : flèche liée zone→zone, type nourrit")
	t.check("Lisbonne" in b.incoming_context(str(zb.id)), "fil : le contexte IA reste calculé")
	b.cycle_link(sc.get_el(str(lk[0].arrow)))
	t.check(b.links()[0].type == "critique", "fil : l'étiquette change le type")
	var zx: float = zb.x
	sc.select([zb.id])
	tl.nudge(Vector2(40, 0))
	t.check(absf(float(zb.x) - zx - 40.0) < 0.01 and absf(b.nodes[zb.id].position.x - float(zb.x)) < 0.01, "zone : déplacée avec son nœud")
	tl.undo()
	t.check(absf(float(zb.x) - zx) < 0.01 and absf(b.nodes[zb.id].position.x - zx) < 0.01, "zone : déplacement annulé (nœud resynchronisé)")
	za.title = "Titre modifié"
	sc.select([zb.id])
	tl.delete_sel()
	t.check(b.zones().size() == 1 and b.links().is_empty() and not b.nodes.has(zb.id), "zone supprimée avec son fil")
	tl.undo()
	t.check(b.zones().size() == 2 and b.nodes.has(zb.id) and b.links().size() == 1, "annuler : zone et fil reviennent")
	t.check(za.title == "Titre modifié" and za.msgs.size() == 2, "annuler ne touche pas au contenu du chat")

	# --- sauvegarde / rechargement
	b._save()
	var n_el: int = sc.els.size()
	b._clear_nodes()
	b._load()
	t.check(sc.els.size() == n_el and b.zones().size() == 2 and b.nodes.size() == 2 and b.links().size() == 1, "sauvegarde v2 : rechargée à l'identique")
	var raw = JSON.parse_string(FileAccess.get_file_as_string(b._plan_file()))
	t.check(raw is Dictionary and raw.has("elements") and int(raw.v) == 2, "fichier : clé elements, v2")

	# --- migration d'un ancien plan (zones, cadres, fils, formes)
	var old := {"zones": [
			{"id": "z1", "x": 10.0, "y": 20.0, "w": 340.0, "h": 280.0, "title": "A", "ai": 0, "kind": "problem", "mode": "etapes", "msgs": [{"role": "user", "content": "q"}], "summary": "", "closed": false},
			{"id": "z2", "x": 500.0, "y": 20.0, "w": 320.0, "h": 260.0, "title": "B", "ai": 1, "kind": "note", "mode": "libre", "msgs": [], "summary": "", "closed": true}],
		"links": [{"from": "z1", "to": "z2", "type": "merge"}],
		"frames": [{"id": "f1", "x": 0.0, "y": 0.0, "w": 900.0, "h": 400.0, "title": "Thème", "color": "ff8fb1"}],
		"shapes": [{"id": "s1", "type": "rect", "x": 50.0, "y": 400.0, "w": 100.0, "h": 60.0, "color": "ff6b6b", "width": 1, "fill": true},
			{"id": "s2", "type": "arrow", "x": 200.0, "y": 450.0, "w": 100.0, "h": -30.0, "color": "4de1b4", "width": 1, "fill": false},
			{"id": "s3", "type": "pencil", "x": 10.0, "y": 500.0, "w": 0.0, "h": 0.0, "color": "f4f4f5", "width": 0, "pts": [[0, 0], [10, 5], [20, 0]]},
			{"id": "s4", "type": "text", "x": 300.0, "y": 500.0, "w": 0.0, "h": 0.0, "color": "fbbf24", "width": 1, "text": "Note"}],
		"pan": [30.0, 40.0], "zoom": 0.8}
	b._clear_nodes()
	sc.load_dict(old, func(ai: int) -> String: return "4de1b4")
	var cnt := {}
	for e in sc.els:
		cnt[e.type] = int(cnt.get(e.type, 0)) + 1
	t.check(cnt.get("zone", 0) == 2 and cnt.get("frame", 0) == 1 and cnt.get("rectangle", 0) == 1 and cnt.get("arrow", 0) == 2 and cnt.get("freedraw", 0) == 1 and cnt.get("text", 0) == 1, "migration v1 : tous les éléments repris %s" % str(cnt))
	var z1: Dictionary = sc.get_el("z1")
	t.check(z1.msgs.size() == 1 and b.nodes.has("z1") and b.nodes.has("z2"), "migration : zones et chats intacts")
	var l1: Array = b.links()
	t.check(l1.size() == 1 and l1[0].type == "merge" and l1[0].from == "z1" and l1[0].to == "z2", "migration : fil -> flèche liée typée")
	t.check(sc.get_el("z2").closed == true, "migration : zone clôturée conservée")

	# --- dessin : exécute tous les chemins de rendu (styles, types, sélection, vue éloignée, surcouche, barres)
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	var dn := [0, 0, 0]
	S.draw.connect(func(): dn[0] += 1)
	S.front.draw.connect(func(): dn[1] += 1)
	S.overlay.draw.connect(func(): dn[2] += 1)
	var zA: Dictionary = b._add_zone("note", "A", Vector2(20, 20))
	var zB: Dictionary = b._add_zone("ideas", "B", Vector2(500, 20))
	var k := 0
	for ty3 in ["rectangle", "diamond", "ellipse"]:
		for fs3 in ["hachure", "croise", "plein", "aucun"]:
			var e5 := add(ty3, 40.0 + k * 30, 400.0 + (k % 4) * 90, 120, 70)
			e5.bg = "60a5fa"
			e5.fillStyle = fs3
			e5.strokeStyle = ["plein", "tirets", "points"][k % 3]
			e5.roughness = k % 3
			e5.roundness = "sharp" if k % 2 == 0 else "round"
			e5.angle = 0.3 * (k % 2)
			e5.label = "lab%d" % k
			sc.mark(e5)
			k += 1
	for at in ["sharp", "round", "elbow"]:
		var ar: Dictionary = sc.make("arrow", 700, 100.0 + k * 10)
		ar.arrowType = at
		ar.startHead = ["none", "arrow", "triangle", "bar", "dot"][k % 5]
		ar.endHead = ["dot", "bar", "triangle", "arrow", "none"][k % 5]
		ar.label = "fl"
		Geom.set_world_pts(ar, PackedVector2Array([Vector2(700, 100 + k * 10), Vector2(900, 160 + k * 10)]))
		sc.add(ar)
		Geom.refresh_arrow(sc, ar)
		k += 1
	var fr2: Dictionary = sc.make("frame", 0, 0)
	fr2.w = 900.0
	fr2.h = 380.0
	sc.add(fr2, 0)
	var im2: Dictionary = sc.make("image", 950, 300)
	im2.w = 100.0
	im2.h = 70.0
	sc.add(im2)
	var tx: Dictionary = sc.make("text", 950, 50)
	tx.text = "ligne 1\nligne 2"
	tx.angle = 0.4
	Geom.fit_text(tx)
	sc.add(tx)
	var la: Dictionary = sc.make("arrow", 0, 0)
	la.start = zA.id
	la.end = zB.id
	la.points = [[0.0, 0.0], [10.0, 10.0]]
	sc.add(la)
	tl._finish_arrow(la)
	sc.commit()
	t.check(str(la.link) == "feed" and b.links().size() == 1, "fil créé par _finish_arrow")
	for zoom_v in [1.0, 0.3, 2.5]:
		S.set_view(Vector2(30, 30), zoom_v)
		sc.select([])
		for e6 in sc.els:
			sc.sel = {e6.id: true}
			tl.hover = str(e6.id)
			await t.frames(1)
		sc.select(sc.els.map(func(e7): return e7.id))
		tl.bind_hover = str(zA.id)
		tl.guides = [[Vector2(0, 0), Vector2(100, 100)]]
		tl.erase_set = {str(tx.id): true}
		await t.frames(2)
		tl.erase_set = {}
		tl.guides = []
		tl.bind_hover = ""
	for tool_n in ["hand", "rectangle", "arrow", "freedraw", "text", "eraser", "frame", "select"]:
		tl.set_tool(tool_n)
		tl.update_cursor(Vector2(100, 100))
		await t.frames(1)
	tl.mode = "marquee"
	tl.marquee = Rect2(10, 10, 200, 100)
	await t.frames(1)
	tl.mode = ""
	S.grid_on = true
	await t.frames(1)
	S.grid_on = false
	S.size = Vector2(400, 600)
	await t.frames(2)
	S.size = Vector2(1000, 700)
	t.check(dn[0] > 0 and dn[1] > 0 and dn[2] > 0, "rendu : couches dessinées (%s)" % str(dn))
	S.set_view(Vector2.ZERO, 1.0)
	sc.clear()
	b._clear_nodes()
	sc.reset_history()

	# --- performance : 1000 éléments
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var t0 := Time.get_ticks_usec()
	for i in 1000:
		var ty2 = ["rectangle", "ellipse", "diamond", "text", "freedraw"][i % 5]
		var el2: Dictionary = sc.make(ty2, rng.randf_range(0, 4000), rng.randf_range(0, 3000))
		el2.w = 60.0
		el2.h = 40.0
		el2.bg = "ff6b6b" if i % 3 == 0 else "transparent"
		if ty2 == "text":
			el2.text = "t%d" % i
			Geom.fit_text(el2)
		if ty2 == "freedraw":
			Geom.set_world_pts(el2, PackedVector2Array([Vector2(el2.x, el2.y), Vector2(el2.x + 30, el2.y + 10), Vector2(el2.x + 50, el2.y)]))
		sc.add(el2)
	var t_add := (Time.get_ticks_usec() - t0) / 1000.0
	sc.commit()
	S.set_view(Vector2.ZERO, 0.25)
	var t1 := Time.get_ticks_usec()
	S.partition()
	for el3 in S.vis_back:
		Geom.build(sc, el3)
	var t_build := (Time.get_ticks_usec() - t1) / 1000.0
	var t2 := Time.get_ticks_usec()
	S._part_key = []
	S.partition()
	for el4 in S.vis_back:
		Geom.build(sc, el4)  # caches chauds
	var t_warm := (Time.get_ticks_usec() - t2) / 1000.0
	var t3 := Time.get_ticks_usec()
	for i in 50:
		tl.top_hit(Vector2(rng.randf_range(0, 4000), rng.randf_range(0, 3000)))
	var t_hit := (Time.get_ticks_usec() - t3) / 50000.0
	var t4 := Time.get_ticks_usec()
	var all: Array = []
	for el5 in sc.els:
		all.append(el5.id)
	sc.select(all)
	var t_sel := (Time.get_ticks_usec() - t4) / 1000.0
	var t5 := Time.get_ticks_usec()
	for el6 in sc.els:
		sc.mark(el6)
	sc.commit()
	var t_commit := (Time.get_ticks_usec() - t5) / 1000.0
	print("PERF 1000 éléments : ajout %.0f ms, 1re passe %.0f ms, passe chaude %.1f ms, hit-test %.2f ms, sélection %.0f ms, commit %.0f ms" % [t_add, t_build, t_warm, t_hit, t_sel, t_commit])
	t.check(t_warm < 60.0 and t_hit < 15.0 and t_build < 1500.0, "perf : 1000 éléments (chaud %.1f ms, hit %.2f ms)" % [t_warm, t_hit])
	await t.frames(3)

	# --- export PNG (ne doit pas planter ; supprime le fichier s'il est produit)
	var path: String = await S.export_png(false)
	if path != "":
		DirAccess.remove_absolute(path)

	# --- raccourcis clavier
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	S.get_viewport().gui_release_focus()
	var k1 := add("rectangle", 10, 10, 50, 50)
	var k2 := add("ellipse", 200, 10, 50, 50)
	t.check(tl.key(_key(KEY_R)) and tl.tool == "rectangle", "clavier : R = rectangle")
	t.check(tl.key(_key(0, KEY_5)) and tl.tool == "arrow", "clavier : 5 = flèche")
	t.check(tl.key(_key(KEY_ESCAPE)) and tl.tool == "select", "clavier : Échap = sélection")
	t.check(tl.key(_key(KEY_A, 0, true)) and sc.sel.size() == 2, "clavier : Ctrl+A")
	t.check(tl.key(_key(KEY_RIGHT, 0, false, true)) and absf(float(k1.x) - 20.0) < 0.01, "clavier : Maj+flèche = 10 px")
	t.check(tl.key(_key(KEY_DELETE)) and sc.els.is_empty(), "clavier : Suppr")
	t.check(tl.key(_key(KEY_Z, 0, true)) and sc.els.size() == 2, "clavier : Ctrl+Z")
	t.check(tl.key(_key(KEY_Z, 0, true, true)) and sc.els.is_empty(), "clavier : Ctrl+Maj+Z")
	t.check(tl.key(_key(KEY_Z, 0, true)) and tl.key(_key(KEY_Q)) and tl.locked, "clavier : Q = verrou")
	tl.toggle_lock()
	var kz := _key(KEY_G, 0, true)
	k1 = sc.els[0]
	k2 = sc.els[1]
	sc.select([k1.id, k2.id])
	t.check(tl.key(kz) and str(k1.group) != "" and k1.group == k2.group, "clavier : Ctrl+G groupe")

	# --- chat en nœuds (arbre de messages)
	await _chat_tests()

	# --- seuil de lisibilité (vignettes) et joystick
	await _lod_joystick_tests()

	# --- nettoyage
	sc.clear()
	b._clear_nodes()
	b._dirty = false
	DirAccess.remove_absolute(b._plan_file())


func _key(code: int, phys := 0, ctrl := false, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code as Key
	e.physical_keycode = phys as Key
	e.pressed = true
	e.ctrl_pressed = ctrl
	e.shift_pressed = shift
	return e


func _msgs_overlap(list: Array) -> bool:
	for i in list.size():
		for j in range(i + 1, list.size()):
			if Geom.rect(list[i]).intersects(Geom.rect(list[j])):
				return true
	return false


func _chat_tests() -> void:
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	S.set_view(Vector2.ZERO, 1.0)
	S.size = Vector2(1000, 700)
	if b.ctx.models.is_empty():
		b.ctx.models = [{"name": "llama3.1:8b", "size": 1.0}]
	t.check(Surface.LOD <= 0.25 and Surface.LOD >= 0.15, "seuil des vignettes abaissé (%.2f)" % Surface.LOD)

	# 1. j'écris : nœud utilisateur + nœud IA enfant qui répond en streaming ; une demande = une étape Ctrl+Z
	var a1: Dictionary = await b.chat_say("Bonjour, qui es-tu ?", "", 0)
	var u1: Dictionary = Chat.parent_of(sc, a1)
	t.check(sc.msgs().size() == 2 and str(u1.role) == "user" and str(a1.role) == "assistant" and a1.parent == u1.id and str(u1.parent) == "", "chat : racine utilisateur + réponse enfant")
	t.check("Bonjour" in str(a1.text) and bool(a1.done) and not b.chat_busy(str(a1.id)) and str(u1.text) == "Bonjour, qui es-tu ?", "chat : réponse reçue en streaming dans le nœud (%s)" % str(a1.text).left(20))
	t.check(float(a1.y) >= float(u1.y) + float(u1.h) and absf(float(a1.x) - float(u1.x)) < 1.0, "chat : l'enfant est placé sous son parent")
	t.check(sc.sel.has(a1.id) and sc.sel.size() == 1, "chat : le nœud de l'IA est sélectionné")
	t.check(sc.can_undo(), "chat : annulable")
	tl.undo()
	t.check(sc.msgs().is_empty(), "chat : UN Ctrl+Z retire la question et la réponse")
	tl.redo()
	t.check(sc.msgs().size() == 2 and "Bonjour" in str(sc.get_el(str(a1.id)).text), "chat : Ctrl+Maj+Z les rétablit avec le texte")
	a1 = sc.get_el(str(a1.id))
	u1 = sc.get_el(str(u1.id))

	# 2. je réponds depuis le nœud de l'IA ; 3. branche : second message depuis le même nœud
	var a2: Dictionary = await b.chat_say("Et toi ?", str(a1.id), 0)
	var u2: Dictionary = Chat.parent_of(sc, a2)
	var a3: Dictionary = await b.chat_say("Autre piste", str(a1.id), 0)
	var u3: Dictionary = Chat.parent_of(sc, a3)
	t.check(u2.parent == a1.id and u3.parent == a1.id and sc.kids(str(a1.id)).size() == 2, "arbre : deux branches depuis le même nœud")
	t.check(Chat.path(sc, str(a2.id)).size() == 4 and Chat.path(sc, str(a3.id)).size() == 4, "arbre : chemin racine -> nœud (4 nœuds)")
	t.check(float(u3.x) > float(u2.x) + float(u2.w) - 1.0, "arbre : la branche suivante est à droite de la précédente")
	t.check(not _msgs_overlap(sc.msgs()), "arbre : aucun nœud ne se chevauche (%d nœuds)" % sc.msgs().size())

	# 4. contexte envoyé au modèle = ancêtres seulement (fonction pure)
	var h: Array = Chat.history(sc, str(u3.id), "SYS", 0, b._ai_name)
	var joined := ""
	for m in h:
		joined += str(m.content) + "|"
	t.check(h.size() == 4 and h[0].role == "system" and h[1].role == "user" and h[2].role == "assistant" and h[3].role == "user" and h[3].content == "Autre piste", "historique : système + ancêtres (%d messages)" % h.size())
	t.check(not ("Et toi" in joined), "historique : la branche voisine n'est pas envoyée")
	a1["ai"] = 1
	var h2: Array = Chat.history(sc, str(u3.id), "SYS", 0, b._ai_name)
	t.check(h2[2].role == "user" and str(h2[2].content).begins_with("[" + b._ai_name(1) + "]"), "historique : l'autre assistant est étiqueté")
	a1["ai"] = 0
	var h3: Array = Chat.history(sc, str(a2.id), "SYS", 0, b._ai_name, 2)
	t.check(h3.size() == 3, "historique : plafonné aux N derniers messages")

	# 5. régénérer = nouveau frère
	var a4: Dictionary = await b.chat_regen(str(a1.id))
	t.check(a4.parent == u1.id and sc.kids(str(u1.id)).size() == 2 and "Bonjour" in str(a4.text) and not _msgs_overlap(sc.msgs()), "régénérer : nouvelle réponse frère, sans chevauchement")

	# 6. chemin en relief : ancêtres + descendants gardés, le reste de l'arbre estompé
	sc.select([a3.id])
	var fo: Dictionary = Chat.focus(sc)
	t.check(fo.on and fo.anc.has(u1.id) and fo.anc.has(a1.id) and fo.anc.has(u3.id) and fo.anc.has(a3.id) and not fo.anc.has(u2.id), "mise en évidence : chemin racine -> nœud")
	t.check(fo.tree.has(a4.id) and not fo.keep.has(a4.id) and fo.keep.has(a3.id), "mise en évidence : le reste de l'arbre est estompé")
	sc.clear_sel()
	t.check(not Chat.focus(sc).on, "mise en évidence : rien sélectionné, rien estompé")

	# 7. déplacement à la main d'un nœud
	var mx: float = u2.x
	tl.set_tool("select")
	drag(S.w2c(Geom.center(u2)), S.w2c(Geom.center(u2)) + Vector2(0, 260))
	t.check(sc.sel.has(u2.id) and float(u2.y) > 100.0 and absf(float(u2.x) - mx) < 30.0, "nœud déplaçable à la main")
	tl.undo()

	# 8. rangement automatique : on mélange tout, puis on range sans chevauchement, enfants sous leur parent
	var seed_rng := RandomNumberGenerator.new()
	seed_rng.seed = 3
	for m in sc.msgs():
		m.x = seed_rng.randf_range(0, 300)
		m.y = seed_rng.randf_range(0, 300)
		sc.mark(m)
	var moved: Array = Chat.tidy(sc, str(u1.id))
	var below := true
	for m in sc.msgs():
		var pm: Dictionary = Chat.parent_of(sc, m)
		if not pm.is_empty() and float(m.y) < float(pm.y) + float(pm.h):
			below = false
	t.check(not moved.is_empty() and not _msgs_overlap(sc.msgs()) and below, "rangement : aucun chevauchement, enfants sous leur parent")
	sc.commit()

	# 9. copier / coller une sous-branche : parent recréé dans la copie
	var n_before: int = sc.msgs().size()
	sc.select([a1.id, u3.id, a3.id])
	tl.copy()
	tl.paste()
	var pasted: Array = sc.msgs().filter(func(m): return not [u1.id, a1.id, u2.id, a2.id, u3.id, a3.id, a4.id].has(m.id))
	t.check(sc.msgs().size() == n_before + 3 and pasted.size() == 3, "copier-coller : 3 nœuds copiés")
	var roots_p: Array = pasted.filter(func(m): return Chat.parent_of(sc, m).is_empty())
	t.check(roots_p.size() == 1 and str(roots_p[0].text) == str(a1.text), "copie : le nœud de tête devient une racine, les autres gardent leur parent copié")
	tl.undo()
	t.check(sc.msgs().size() == n_before, "coller annulé")

	# 10. suppression : un nœud emporte toute sa sous-branche, un seul Ctrl+Z la rend
	var total: int = sc.msgs().size()
	sc.select([a1.id])
	tl.delete_sel()
	t.check(not sc.by_id.has(a1.id) and not sc.by_id.has(a3.id) and not sc.by_id.has(u2.id) and sc.by_id.has(u1.id) and sc.by_id.has(a4.id), "suppression : la sous-branche part avec le nœud, le reste demeure")
	tl.undo()
	t.check(sc.msgs().size() == total and sc.by_id.has(a3.id) and Chat.parent_of(sc, sc.get_el(str(a3.id))).id == u3.id, "suppression : UN Ctrl+Z rend toute la branche")

	# 11. sauvegarde / rechargement (clé elements, v2)
	b._save()
	var texts := {}
	for m in sc.msgs():
		texts[m.id] = [str(m.text), str(m.parent), str(m.role)]
	b._clear_nodes()
	b._load()
	var same: bool = sc.msgs().size() == texts.size()
	for m in sc.msgs():
		if not texts.has(m.id) or texts[m.id] != [str(m.text), str(m.parent), str(m.role)] or not bool(m.done):
			same = false
	var raw = JSON.parse_string(FileAccess.get_file_as_string(b._plan_file()))
	var in_raw := 0
	for e in raw.elements:
		if e.type == "msg":
			in_raw += 1
	t.check(same and in_raw == texts.size() and int(raw.v) == 2, "sauvegarde v2 : %d nœuds de chat rechargés à l'identique" % texts.size())
	u1 = sc.get_el(str(u1.id))
	a1 = sc.get_el(str(a1.id))
	a3 = sc.get_el(str(a3.id))
	u3 = sc.get_el(str(u3.id))

	# 12. recherche et export Markdown (arbre indenté)
	b._apply_search("autre piste")
	t.check(sc.search_q == "autre piste" and Chat.matches(u3, sc.search_q) and not Chat.matches(u1, sc.search_q), "recherche : seuls les nœuds correspondants restent nets")
	sc.clear_sel()
	b.search_e.text = "autre piste"
	b._goto_first_match()
	t.check(sc.sel.has(u3.id), "recherche : Entrée sélectionne le premier nœud trouvé")
	b._apply_search("")
	var md: PackedStringArray = Chat.markdown(sc, b._ai_name)
	var mdt := "\n".join(md)
	t.check("## Conversations" in mdt and "- **Toi** : Bonjour, qui es-tu ?" in mdt and ("  - **" + b._ai_name(0) + "** :") in mdt and "    - **Toi** : Autre piste" in mdt, "export Markdown : arbre indenté")

	# 13. hauteur du nœud suivant le texte, largeur redimensionnable
	var lm: Dictionary = Chat.make_msg(sc, "assistant", "court", "", 0)
	var h_short: float = Chat.layout(sc, lm).h
	lm.text = "# Titre\n\n- puce un\n- puce deux\n\n```\ncode()\n```\n\n" + "Un long paragraphe de texte qui doit passer à la ligne plusieurs fois. ".repeat(12)
	sc.cache.erase(lm.id)
	var lay: Dictionary = Chat.layout(sc, lm)
	t.check(float(lay.h) > h_short + 120.0 and lay.lines.size() > 10 and lay.boxes.size() >= 1 and float(lm.h) == float(lay.h), "mise en page : Markdown léger, la hauteur suit le texte (%.0f -> %.0f)" % [h_short, lay.h])
	lm.w = 560.0
	sc.cache.erase(lm.id)
	t.check(Chat.layout(sc, lm).h < float(lay.h), "mise en page : plus large = moins haut")

	# 14. rendu (tous les niveaux de zoom, avec chemin en relief et recherche)
	var dn := [0]
	S.draw.connect(func(): dn[0] += 1)
	S.fit_all()
	for zv in [1.0, 0.5, 0.3, 0.22, 0.12]:
		S.set_view(Vector2(30, 30), zv)
		sc.select([a3.id])
		sc.search_q = "bonjour" if zv < 0.3 else ""
		await t.frames(2)
	sc.search_q = ""
	t.check(dn[0] > 0, "rendu : nœuds de chat dessinés à tous les zooms")
	S.set_view(Vector2.ZERO, 1.0)

	# 15. barre de saisie : deux modes, cible = nœud sélectionné ; boutons rapides sous le nœud
	var asst = b.assist
	t.check(asst.mode == "chat", "barre : Discuter par défaut")
	sc.select([a3.id])
	S.sel_changed.emit()
	await t.frames(2)
	t.check(asst.target_id() == str(a3.id) and b.chat_bar.visible and Rect2(Vector2.ZERO, S.size).encloses(Rect2(b.chat_bar.position, b.chat_bar.size)), "boutons rapides : visibles sous le nœud sélectionné")
	t.check(b.chat_bar.b_regen.visible and b.chat_bar.b_fork.visible and b.chat_bar.b_reply.visible and not b.chat_bar.b_stop.visible, "boutons rapides : Répondre, Branche ici, Régénérer")
	b.chat_reply(str(a3.id), true)
	t.check(asst.visible and asst.mode == "chat" and asst.fork and asst.target_id() == str(a3.id), "Branche ici : barre ouverte sur ce nœud")
	asst.set_mode("graph")
	t.check(asst.mode == "graph" and not asst.who.visible and asst.b_graph.button_pressed, "barre : bascule vers Éditer le graphe")
	asst.open("chat")
	t.check(asst.mode == "chat" and asst.who.visible and asst.b_chat.button_pressed and asst.model_l.text != "", "barre : retour à Discuter, sélecteur d'assistant et modèle affichés")
	var ek := _key(KEY_ENTER, 0, true)
	asst.input.gui_input.emit(ek)
	t.check(asst.mode == "graph", "barre : Ctrl+Entrée dans le champ bascule de mode")
	asst.set_mode("chat")
	S.get_viewport().gui_release_focus()
	t.check(tl.key(_key(KEY_ENTER, 0, true)) and asst.mode == "graph", "clavier : Ctrl+Entrée = éditer le graphe")
	asst.close()
	t.check(tl.key(_key(KEY_ENTER)) and asst.mode == "chat" and asst.visible, "clavier : Entrée = discuter")
	var nb: int = sc.msgs().size()
	sc.clear_sel()
	asst.who.select(2)
	await asst.ask("Salut à tous")
	await t.wait_for(func(): return b.reqs.is_empty())
	var fresh: Array = sc.msgs().filter(func(m): return str(m.text) == "Salut à tous")
	t.check(sc.msgs().size() == nb + 2 and fresh.size() == 1 and Chat.parent_of(sc, fresh[0]).is_empty() and int(fresh[0].ai) == 2, "barre : sans sélection, nouvelle conversation (racine) avec l'assistant choisi")
	var ans: Array = sc.kids(str(fresh[0].id))
	t.check(ans.size() == 1 and int(ans[0].ai) == 2 and "Bonjour" in str(ans[0].text) and bool(ans[0].done), "barre : l'assistant choisi répond dans un nœud enfant")
	asst.close()
	# le graphe ne touche pas aux nœuds de chat
	const GT := preload("res://ui/draw/graph_tools.gd")
	GT.run(sc, "supprimer", {"ids": ["tout"]}, Vector2.ZERO, [])
	var del_res: String = GT.run(sc, "supprimer", {"ids": [str(fresh[0].id)]}, Vector2.ZERO, [])
	t.check(sc.msgs().size() == nb + 2 and "Refusé" in del_res, "assistant du graphe : les nœuds de chat sont protégés")

	# 16. perf : 300 nœuds de chat
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	var prev_id := ""
	var t0 := Time.get_ticks_usec()
	for i in 300:
		var par := "" if i % 6 == 0 else prev_id
		var nm: Dictionary = Chat.add_msg(sc, "assistant" if i % 2 == 1 else "user", ("Texte de test numéro %d. " % i).repeat(18), par, 0, false, Vector2(i * 7 % 400, 0))
		prev_id = str(nm.id)
	var t_add := (Time.get_ticks_usec() - t0) / 1000.0
	var rs: Array = Chat.roots(sc)
	for r in rs:
		Chat.tidy(sc, str(r.id))
	S.set_view(Vector2.ZERO, 0.3)
	var t1 := Time.get_ticks_usec()
	S._part_key = []
	S.partition()
	for el in sc.msgs():
		sc.cache.erase(el.id)
	for el in S.vis_back:
		Chat.layout(sc, el)
	var t_lay := (Time.get_ticks_usec() - t1) / 1000.0
	var t2 := Time.get_ticks_usec()
	S._part_key = []
	S.partition()
	for el in S.vis_back:
		Chat.layout(sc, el)
	var t_warm := (Time.get_ticks_usec() - t2) / 1000.0
	var nodes_vis: int = S.vis_back.size() + S.vis_front.size()
	print("PERF 300 nœuds de chat : ajout %.0f ms, mise en page des %d visibles %.0f ms, passe chaude %.1f ms" % [t_add, nodes_vis, t_lay, t_warm])
	t.check(t_warm < 30.0 and t_lay < 1500.0 and t_add < 6000.0, "perf : 300 nœuds de chat (chaud %.1f ms)" % t_warm)
	await t.frames(3)
	sc.clear()
	b._clear_nodes()
	sc.reset_history()


func _lod_joystick_tests() -> void:
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
	var z: Dictionary = b._add_zone("note", "Z", Vector2(100, 100))
	# seuil : les zones restent de vrais nœuds jusqu'à 20 %, vignettes en dessous
	S.set_view(Vector2.ZERO, 0.34)
	t.check(not S.lod and S.world.visible, "zoom 34 % : zones en vrai (plus de vignette)")
	S.set_view(Vector2.ZERO, 0.21)
	t.check(not S.lod and S.world.visible, "zoom 21 % : zones en vrai")
	S.set_view(Vector2.ZERO, 0.15)
	t.check(S.lod and not S.world.visible, "zoom 15 % : vignettes")
	S.set_view(Vector2.ZERO, 0.3)
	t.check(not S.lod and S.world.visible, "retour à 30 % : zones revenues")
	# textes lisibles : jamais tracés sous HIDE_FS, agrandis jusqu'à MIN_FS sinon
	t.check(Render.MIN_FS >= 6.0 and Render.HIDE_FS < Render.MIN_FS, "textes : taille minimale à l'écran %.0f px" % Render.MIN_FS)
	var tx: Dictionary = sc.make("text", 400, 100)
	tx.text = "Lisible"
	tx.fontSize = 20.0
	Geom.fit_text(tx)
	sc.add(tx)
	for zv in [0.3, 0.2, 0.12]:
		S.set_view(Vector2.ZERO, zv)
		await t.frames(1)
	sc.remove([tx.id])
	S.set_view(Vector2.ZERO, 1.0)

	# joystick
	var bars: Control = b.bars
	var joy: Control = bars.joy
	await t.frames(2)
	bars.layout()
	t.check(joy.visible and joy.size.x >= 64.0 and joy.size.y >= 64.0, "joystick : visible, %.0f px" % joy.size.x)
	t.check(not Rect2(joy.position, joy.size).intersects(Rect2(bars.zoombar.position, bars.zoombar.size)) and not Rect2(joy.position, joy.size).intersects(Rect2(bars.panel.position, bars.panel.size)), "joystick : ne recouvre ni le zoom ni les propriétés")
	t.check(Rect2(Vector2.ZERO, S.size).encloses(Rect2(joy.position, joy.size)) and S.block_rect == Rect2(joy.position, joy.size), "joystick : dans le canevas, touchers exclus du pincement")
	S.set_view(Vector2(100, 100), 1.0)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = joy.size * 0.5 + Vector2(45, 0)
	joy._gui_input(ev)
	t.check(joy.active and joy.vec.x > 0.8 and absf(joy.vec.y) < 0.01, "joystick : appui à droite")
	for i in 30:
		joy.step(1.0 / 60.0)
	var dx: float = 100.0 - S.pan.x
	t.check(dx > 20.0 and absf(S.pan.y - 100.0) < 0.5, "joystick à droite : la vue défile vers la droite (%.0f px)" % dx)
	# vitesse proportionnelle à l'écart
	joy.release()
	for i in 200:
		joy.step(1.0 / 60.0)
	S.set_view(Vector2(100, 100), 1.0)
	joy.vel = Vector2.ZERO
	joy.active = true
	joy.aim(joy.size * 0.5 + Vector2(17, 0))
	for i in 30:
		joy.step(1.0 / 60.0)
	var d_small: float = 100.0 - S.pan.x
	t.check(d_small > 0.5 and d_small < dx * 0.6, "joystick : vitesse proportionnelle à l'écart (%.0f px < %.0f px)" % [d_small, dx])
	# haut / bas
	joy.release()
	for i in 200:
		joy.step(1.0 / 60.0)
	S.set_view(Vector2(100, 100), 1.0)
	joy.active = true
	joy.aim(joy.size * 0.5 + Vector2(0, -45))
	for i in 30:
		joy.step(1.0 / 60.0)
	t.check(S.pan.y > 120.0 and absf(S.pan.x - 100.0) < 0.5, "joystick vers le haut : la vue monte")
	# relâchement : inertie douce puis retour au centre, arrêt du traitement
	var ev2 := InputEventMouseButton.new()
	ev2.button_index = MOUSE_BUTTON_LEFT
	ev2.pressed = false
	joy._idx = -1
	joy._gui_input(ev2)
	t.check(not joy.active and joy.vec == Vector2.ZERO and joy.vel.length() > 1.0, "joystick : relâché, il reste de l'inertie")
	var pan_rel: Vector2 = S.pan
	for i in 3:
		joy.step(1.0 / 60.0)
	t.check(S.pan.y > pan_rel.y, "joystick : l'inertie continue un instant")
	for i in 240:
		joy.step(1.0 / 60.0)
	t.check(joy.vel == Vector2.ZERO and joy.knob == Vector2.ZERO and not joy.is_processing(), "joystick : revenu au centre, plus de traitement")
	# le canevas reste utilisable : molette et glisser
	var p0: Vector2 = S.pan
	var we := InputEventMouseButton.new()
	we.button_index = MOUSE_BUTTON_WHEEL_DOWN
	we.pressed = true
	t.check(S.wheel(we) and S.pan.y < p0.y, "canevas : la molette défile toujours")
	var tev := InputEventScreenTouch.new()
	tev.index = 0
	tev.pressed = true
	tev.position = S.get_global_rect().position + joy.position + Vector2(10, 10)
	S.touch_event(tev)
	t.check(S._touches.is_empty(), "tactile : un doigt sur le joystick ne compte pas pour le pincement")
	S.set_view(Vector2.ZERO, 1.0)
	sc.clear()
	b._clear_nodes()
	sc.reset_history()
