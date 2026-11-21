extends SceneTree
## Test d'intégration RÉEL de l'assistant du graphe (appelle Ollama, plusieurs minutes) :
##   flatpak run org.godotengine.Godot --headless --path . -s res://test_assist.gd
## Rejoue des demandes en français sur une vraie scène et vérifie les effets (création, édition, suppression, annulation).

const Ollama := preload("res://core/ollama.gd")
const Scene := preload("res://ui/draw/scene.gd")
const Assist := preload("res://ui/draw/assist.gd")
const MODEL := "qwen3:14b"

var fails: PackedStringArray = []
var passes := 0


class FakeCtx extends Node:
	var ollama
	var models: Array = [{"name": "qwen3:14b", "size": 9.0e9}]
	func model_for(_i: int) -> String:
		return "qwen3:14b"
	func model_is_vision(_m: String) -> bool:
		return false


class FakeCanvas extends Control:
	signal sel_changed
	func c2w(v: Vector2) -> Vector2:
		return v
	func redraw() -> void:
		pass
	func fit_selection() -> void:
		pass


class FakeBoard extends Node:
	var ctx
	var scene
	var canvas
	func _touch() -> void:
		pass


func ask(asst, text: String) -> void:
	await asst.ask(text)
	print("  > ", text)
	for t in asst.trace:
		print("    outil ", t.name, " ", JSON.stringify(t.args).left(200), " => ", str(t.res).left(100))
	if asst.trace.is_empty():
		print("    (aucun outil) ", str(asst.history[asst.history.size() - 1].content).left(160) if not asst.history.is_empty() else "")


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  ok   ", msg)
	else:
		fails.append(msg)
		print("  ECHEC ", msg)


func shapes(sc) -> Array:
	return sc.els.filter(func(e): return e.type in ["rectangle", "ellipse", "diamond"])


func arrows(sc) -> Array:
	return sc.els.filter(func(e): return e.type == "arrow")


func label(e: Dictionary) -> String:
	return str(e.get("label", e.get("text", ""))).replace("\n", " ")


func _initialize() -> void:
	await _run()
	print("\nRÉSULTAT : %d ok, %d échec(s)" % [passes, fails.size()])
	for f in fails:
		print(" - ", f)
	quit(1 if not fails.is_empty() else 0)


func _run() -> void:
	var ctx := FakeCtx.new()
	ctx.ollama = Ollama.new()
	root.add_child(ctx)
	root.add_child(ctx.ollama)
	var sc = Scene.new()
	sc.reset_history()
	var cv := FakeCanvas.new()
	cv.size = Vector2(1000, 700)
	root.add_child(cv)
	var board := FakeBoard.new()
	board.ctx = ctx
	board.scene = sc
	board.canvas = cv
	root.add_child(board)
	var asst = Assist.new()
	cv.add_child(asst)
	asst.setup(board)
	asst.set_mode("graph")
	asst.open()

	print("— 1. Créer un schéma")
	await ask(asst, "Fais un schéma des étapes pour choisir la couleur d'une police d'écriture")
	var n1 := shapes(sc).size()
	check(n1 >= 3, "au moins 3 nœuds créés (%d)" % n1)
	check(arrows(sc).size() >= 2, "au moins 2 flèches (%d)" % arrows(sc).size())
	var bound := true
	for a in arrows(sc):
		if sc.get_el(str(a.start)).is_empty() or sc.get_el(str(a.end)).is_empty():
			bound = false
	check(bound, "toutes les flèches sont liées à des nœuds")
	var overlap := false
	var sh := shapes(sc)
	for i in sh.size():
		for j in range(i + 1, sh.size()):
			if Rect2(float(sh[i].x), float(sh[i].y), float(sh[i].w), float(sh[i].h)).intersects(Rect2(float(sh[j].x), float(sh[j].y), float(sh[j].w), float(sh[j].h))):
				overlap = true
	check(not overlap, "aucun nœud ne se chevauche")
	var total1: int = sc.els.size()
	check(sc.can_undo(), "la demande est annulable")
	sc.undo()
	check(sc.els.size() == 0, "UN Ctrl+Z annule tout le schéma (%d restants)" % sc.els.size())
	sc.redo()
	check(sc.els.size() == total1, "Ctrl+Y le rétablit")

	print("— 2. Modifier une couleur")
	await ask(asst, "Mets le premier nœud en rouge")
	var red: Array = sc.els.filter(func(e): return str(e.get("stroke", "")) == "f87171")
	check(red.size() >= 1, "un élément est devenu rouge (%d)" % red.size())
	check(red.size() <= 2, "pas toute la scène en rouge (%d)" % red.size())

	print("— 3. Ajouter une étape et la relier (mémoire de la conversation)")
	var s_before := shapes(sc).size()
	var a_before := arrows(sc).size()
	await ask(asst, "Ajoute une étape « Livrer la maquette » après la dernière étape et relie-la")
	var found := false
	for e in shapes(sc):
		if "livrer" in label(e).to_lower():
			found = true
	check(found, "la nouvelle étape existe")
	check(shapes(sc).size() == s_before + 1, "exactement une forme ajoutée (%d → %d)" % [s_before, shapes(sc).size()])
	check(arrows(sc).size() >= a_before + 1, "une flèche ajoutée (%d → %d)" % [a_before, arrows(sc).size()])

	print("— 4. Supprimer")
	var s2 := shapes(sc).size()
	await ask(asst, "Supprime l'étape « Livrer la maquette »")
	var still := false
	for e in shapes(sc):
		if "livrer" in label(e).to_lower():
			still = true
	check(not still, "l'étape a disparu")
	check(shapes(sc).size() == s2 - 1, "une seule forme supprimée (%d → %d)" % [s2, shapes(sc).size()])
	for a in arrows(sc):
		check(not sc.get_el(str(a.start)).is_empty() and not sc.get_el(str(a.end)).is_empty(), "aucune flèche orpheline")
		break

	print("— 5. Question sans action")
	var before_total: int = sc.els.size()
	await ask(asst, "Quels types d'éléments peux-tu créer ?")
	check(sc.els.size() == before_total, "aucun élément créé pour une simple question")

	print("— 6. Cible inexistante : pas de plantage")
	await ask(asst, "Relie « Zorglub » à « Machin »")
	check(not asst.busy, "l'assistant est de nouveau disponible")
	check(sc.els.size() >= before_total - 1, "scène intacte")

	print("— 7. Autre disposition et formes")
	var t0: int = sc.els.size()
	await ask(asst, "Fais un petit organigramme en ligne : Début, Décision (en losange), Fin")
	check(sc.els.size() > t0, "nouveau schéma ajouté")
	var diamonds: Array = sc.els.filter(func(e): return e.type == "diamond")
	check(diamonds.size() >= 1, "un losange pour la décision")
	var tx0: int = sc.els.size()
	sc.undo()
	check(sc.els.size() == t0, "annulable en une étape (%d → %d)" % [tx0, sc.els.size()])

	print("— 7b. Fond de couleur, puis effacer tout")
	await ask(asst, "Mets le fond du premier nœud en jaune")
	var yellow: Array = sc.els.filter(func(e): return str(e.get("bg", "")) == "fbbf24")
	check(yellow.size() >= 1, "un nœud a un fond jaune (%d)" % yellow.size())
	await ask(asst, "Efface tout le schéma")
	check(shapes(sc).size() == 0 and arrows(sc).size() == 0, "tout est effacé (%d formes, %d flèches)" % [shapes(sc).size(), arrows(sc).size()])
	sc.undo()
	check(shapes(sc).size() >= 1, "Ctrl+Z restaure tout en une étape (%d formes)" % shapes(sc).size())

	print("— 7c. Récupération d'un JSON coupé net (hors modèle)")
	var cut := '{"name":"creer_diagramme","arguments":{"noeuds":[{"id":"1","texte":"Poser le problème"},{"id":"2","texte":"Explorer des pistes"},{"id":"3","texte":"Comparer"},{"id":"4","texte":"Déci'
	check(asst._salvage(cut).get("noeuds", []).size() == 3, "3 nœuds complets récupérés d'un JSON tronqué")
	var cut2 := '"noeuds":[{"texte":"A"},{"texte":"B"}],"liens":[{"de":"A","vers":"B"},{"de":"B","ve'
	var sv: Dictionary = asst._salvage(cut2)
	check(sv.get("noeuds", []).size() == 2 and sv.get("liens", []).size() == 1, "nœuds et liens complets récupérés (liens tronqués ignorés)")
	check(asst._claims_done("L'étape a été supprimée."), "détecte « a été supprimée »")
	check(not asst._claims_done("Je peux créer des formes et des flèches."), "« je peux créer » n'est pas une action")

	print("— 7d. Schéma de la réflexion à partir des zones (cas réel signalé)")
	sc.clear()
	sc.reset_history()
	var zl: Array = []
	for t in [["Le problème", "Choisir une police lisible", true], ["Idées", "3 pistes : sans-serif, serif, monospace", false], ["Pour/contre", "Sans-serif plus lisible à l'écran", true], ["Décision", "On retient une sans-serif", true]]:
		var zz: Dictionary = {"id": sc.uid("z"), "type": "zone", "x": float(zl.size()) * 380.0, "y": 0.0, "w": 320.0, "h": 260.0, "angle": 0.0, "locked": false, "group": "", "opacity": 100.0, "title": t[0], "kind": "note", "mode": "libre", "msgs": [{"role": "user", "content": "q"}, {"role": "assistant", "content": t[1]}], "summary": t[1] if t[2] else "", "closed": t[2], "img": "", "ai": 0}
		sc.add(zz)
		zl.append(zz)
	for i in 3:
		var la: Dictionary = sc.make("arrow", 0.0, 0.0)
		la.points = [[0.0, 0.0], [10.0, 10.0]]
		la.start = zl[i].id
		la.end = zl[i + 1].id
		la.link = "feed"
		sc.add(la)
	sc.commit()
	var n0: int = sc.els.size()
	await ask(asst, "Génère-moi un schéma qui montre toutes les étapes de réflexion")
	check(shapes(sc).size() >= 4, "au moins 4 nœuds pour les étapes de réflexion (%d)" % shapes(sc).size())
	var used_zones := false
	for t in asst.trace:
		if t.name == "lire_zones":
			used_zones = true
	check(used_zones, "l'assistant a lu les zones du plan")
	check(sc.els.size() > n0, "le schéma a été ajouté")
	check(not asst.busy, "pas de blocage")

	print("— 8. Les zones de chat sont protégées")
	var z: Dictionary = {"id": sc.uid("z"), "type": "zone", "x": 0.0, "y": 0.0, "w": 300.0, "h": 200.0, "angle": 0.0, "locked": false, "group": "", "opacity": 100.0, "title": "MaZone", "kind": "note", "mode": "libre", "msgs": [], "summary": "", "closed": false, "img": "", "ai": 0}
	sc.add(z)
	sc.commit()
	var keep: int = sc.els.size()
	await ask(asst, "Supprime la zone MaZone")
	check(not sc.get_el(str(z.id)).is_empty(), "la zone de chat existe toujours")
	check(sc.els.size() == keep, "rien d'autre n'a été supprimé (%d → %d)" % [keep, sc.els.size()])
