extends SceneTree
## Test RÉEL (appelle Ollama, ~1 minute) du chat en nœuds : message -> nœud utilisateur + nœud IA qui se remplit en streaming,
## puis réponse depuis ce nœud (le modèle reçoit le chemin racine -> nœud) :
##   flatpak run org.godotengine.Godot --headless --path . -s res://test_chat_real.gd

const Ollama := preload("res://core/ollama.gd")
const Scene := preload("res://ui/draw/scene.gd")
const Chat := preload("res://ui/draw/chat.gd")
const MODEL := "qwen3:14b"

var fails: PackedStringArray = []
var passes := 0


func check(cond: bool, msg: String) -> void:
	if cond:
		passes += 1
		print("  ok   ", msg)
	else:
		fails.append(msg)
		print("  ECHEC ", msg)


## Même boucle que board._chat_answer (sans la page) : remplit le nœud pendant le streaming.
func answer(ol, sc, a: Dictionary, upto: String) -> int:
	var msgs: Array = Chat.history(sc, upto, "Tu réponds en français, en quelques mots.", 0)
	var acc := [""]
	var chunks := [0]
	var req = ol.chat(MODEL, msgs, {"temperature": 0.2, "num_predict": 80})
	req.line.connect(func(l: Dictionary):
		var c := str(l.get("message", {}).get("content", ""))
		if c != "":
			acc[0] += c
			chunks[0] += 1
			a["text"] = Ollama.strip_think(acc[0])
			sc.mark(a)
			Chat.layout(sc, a))
	var r: Array = await req.finished
	a["done"] = true
	if not r[0]:
		print("  erreur Ollama : ", r[1], " ", r[2])
	return chunks[0]


func _initialize() -> void:
	var ol := Ollama.new()
	root.add_child(ol)
	var sc = Scene.new()
	sc.reset_history()
	var u1 := Chat.add_msg(sc, "user", "Dis seulement le mot « pomme », rien d'autre.", "", 0)
	var a1 := Chat.add_msg(sc, "assistant", "", str(u1.id), 0)
	a1["done"] = false
	var h0: float = a1.h
	var n := await answer(ol, sc, a1, str(u1.id))
	check(n >= 1 and str(a1.text).strip_edges() != "", "réponse reçue dans le nœud (%d morceaux) : « %s »" % [n, str(a1.text).left(60)])
	check(bool(a1.done) and float(a1.h) >= h0, "nœud terminé, hauteur à jour (%.0f)" % float(a1.h))
	var u2 := Chat.add_msg(sc, "user", "Maintenant répète le mot que tu viens de dire, en MAJUSCULES.", str(a1.id), 0)
	var a2 := Chat.add_msg(sc, "assistant", "", str(u2.id), 0)
	a2["done"] = false
	await answer(ol, sc, a2, str(u2.id))
	print("  réponse 2 : ", str(a2.text).left(80))
	check("POMME" in str(a2.text).to_upper() and "pomme" in str(a1.text).to_lower(), "la réponse depuis le nœud tient compte du chemin (le mot précédent)")
	check(Chat.path(sc, str(a2.id)).size() == 4, "arbre : chemin de 4 nœuds")
	print("\nRÉSULTAT : %d ok, %d échec(s)" % [passes, fails.size()])
	quit(1 if not fails.is_empty() else 0)
