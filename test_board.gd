extends RefCounted
## Tests du plan (moteur de scène façon Excalidraw) : création, sélection, déplacement, redimensionnement, rotation,
## flèches liées, historique, presse-papiers, groupes, migration v1, sauvegarde, performance. Appelé par test_run.gd.

const Geom := preload("res://ui/draw/geom.gd")
const Scene := preload("res://ui/draw/scene.gd")

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

	# --- nettoyage
	sc.clear()
	b._clear_nodes()
	b._dirty = false
	DirAccess.remove_absolute(b._plan_file())
