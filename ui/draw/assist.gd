extends PanelContainer
## Assistant du graphe : barre flottante en bas du tableau (Entrée pour l'ouvrir, Échap pour la fermer).
## On lui parle (« fais un schéma de… », « mets le deuxième nœud en rouge »), il agit sur la scène avec les outils de
## graph_tools.gd. Tout ce qu'il fait pendant une demande forme UNE seule étape d'historique : Ctrl+Z l'annule d'un coup.

const U := preload("res://ui/universe.gd")
const T := preload("res://ui/theme.gd")
const MD := preload("res://ui/markdown.gd")
const Ollama := preload("res://core/ollama.gd")
const Orchestra := preload("res://core/orchestra.gd")
const GraphTools := preload("res://ui/draw/graph_tools.gd")
const MAX_ROUNDS := 5
const MAX_HISTORY := 8
const WIDTH := 640.0

var board: Node
var reply: RichTextLabel
var input: LineEdit
var send_b: Button
var busy := false
var req: Ollama.Req
var trace: Array = []  # [{name, args, res}] des outils appelés (tests / diagnostic)
var last_error := ""
var history: Array = []  # [{role, content}] (texte seulement)


func setup(b: Node) -> void:
	board = b
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = T.CARD
	st.border_color = T.OK
	st.set_border_width_all(2)
	st.set_content_margin_all(8)
	add_theme_stylebox_override("panel", st)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	add_child(v)
	reply = RichTextLabel.new()
	reply.bbcode_enabled = true
	reply.fit_content = false
	reply.scroll_following = true
	reply.selection_enabled = true
	reply.custom_minimum_size = Vector2(0, 0)
	reply.visible = false
	v.add_child(reply)
	var row := HBoxContainer.new()
	v.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = "Assistant du graphe : « fais un schéma de… », « mets en rouge… »  (Entrée : envoyer · Échap : fermer)"
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.text_submitted.connect(ask)
	input.gui_input.connect(func(e: InputEvent):
		if e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
			if busy and req != null:
				req.cancel()
			else:
				close()
			accept_event())
	row.add_child(input)
	send_b = Button.new()
	send_b.text = "➤"
	send_b.pressed.connect(func(): ask(input.text))
	row.add_child(send_b)
	var xb := Button.new()
	xb.text = "✕"
	xb.pressed.connect(close)
	row.add_child(xb)
	board.canvas.resized.connect(reposition)


func open() -> void:
	visible = true
	reposition()
	input.grab_focus()


func close() -> void:
	visible = false
	input.release_focus()


func reposition() -> void:
	if board == null or board.canvas == null:
		return
	var cs: Vector2 = board.canvas.size
	var w := minf(WIDTH, cs.x - 24.0)
	reply.custom_minimum_size.y = 0.0 if not reply.visible else minf(150.0, maxf(40.0, cs.y * 0.28))
	size = Vector2(w, 0)
	position = Vector2(floorf((cs.x - w) * 0.5), cs.y - size.y - 14.0)


func _process(_dt: float) -> void:
	if visible:
		position.y = board.canvas.size.y - size.y - 14.0


func _model() -> String:
	var ctx: Node = board.ctx
	var m: String = ctx.model_for(0)
	if m != "" and Ollama.supports_tools(m):
		return m
	for i in range(ctx.models.size() - 1, -1, -1):  # le plus gros modèle compatible outils
		var n := str(ctx.models[i].name)
		if Ollama.supports_tools(n) and not ctx.model_is_vision(n) and not U.is_broken(n):
			return n
	return ""


func _say(bb: String) -> void:
	reply.visible = true
	reply.text = bb
	reposition()


func ask(text: String) -> void:
	text = text.strip_edges()
	if busy or text == "":
		return
	var sc = board.scene
	var model := _model()
	if model == "":
		_say("[color=#f87171]Aucun modèle compatible avec les outils (essaie qwen3 ou llama3.1 dans Ollama).[/color]")
		return
	busy = true
	input.text = ""
	input.editable = false
	var sel: Array = sc.selected().map(func(e): return str(e.id))
	var user_msg := text + ("\n(Éléments sélectionnés : %s)" % ", ".join(sel) if not sel.is_empty() else "")
	var sys := U.system_prompt(0, false) + "\nTu es l'assistant du tableau de graphes (type Excalidraw). Tu crées et modifies des schémas avec tes outils : "
	sys += "pour tout schéma ou organigramme, utilise creer_diagramme avec seulement le texte des nœuds et les liens (la mise en page est automatique, ne parle jamais de coordonnées). "
	sys += "Pour AJOUTER à un schéma existant, n'utilise JAMAIS creer_diagramme (il crée un schéma neuf et duplique tout) : utilise ajouter_etape, ajouter_texte ou relier. "
	sys += "Pour schématiser la réflexion, les étapes de raisonnement ou le contenu du plan, appelle d'abord lire_zones puis creer_diagramme (un nœud par zone ou par idée clé, 10 nœuds maximum, 5 mots maximum par nœud). "
	sys += "Ne dis JAMAIS que tu as fait quelque chose sans l'avoir fait avec un outil. "
	sys += "Appelle lister_elements avant de modifier, relier ou supprimer afin de connaître les ids. Ne supprime QUE ce qui est explicitement demandé, jamais autre chose en remplacement : si la demande vise une zone de chat (impossible pour toi), explique-le sans rien supprimer. Pour « effacer tout », utilise supprimer avec ids [\"tout\"] puis vérifie qu'il ne reste rien. Textes de nœuds courts. Après avoir agi, réponds en une ou deux phrases."
	var msgs: Array = [{"role": "system", "content": sys}]
	msgs.append_array(history.slice(maxi(0, history.size() - MAX_HISTORY)))
	msgs.append({"role": "user", "content": user_msg})
	var shown := "[color=#98a2b0]Toi : %s[/color]\n" % MD.esc(text)
	_say(shown + "[color=#98a2b0]…[/color]")
	trace.clear()
	last_error = ""
	var created: Array = []
	var center: Vector2 = board.canvas.c2w(board.canvas.size * 0.5)
	var final := ""
	var nudged := false
	for round_i in MAX_ROUNDS + 1:
		req = board.ctx.ollama.chat(model, msgs, {"temperature": 0.3, "num_predict": 3000}, GraphTools.schema() if round_i < MAX_ROUNDS else [])
		var acc := ["", ""]  # texte, done_reason
		var calls: Array = []
		req.line.connect(func(l: Dictionary):
			if l.get("done", false):
				acc[1] = str(l.get("done_reason", ""))
			var m: Dictionary = l.get("message", {})
			var c := str(m.get("content", ""))
			if c != "":
				acc[0] += c
				_say(shown + MD.to_bbcode(Ollama.strip_think(acc[0]), T.OK.to_html(false)))
			for tc in m.get("tool_calls", []):
				calls.append(tc))
		var r: Array = await req.finished
		if not is_instance_valid(self):
			return
		var txt := Ollama.strip_think(acc[0])
		if not r[0]:
			if str(r[1]) != "cancel":
				shown += "[color=#f87171]Erreur : %s[/color]\n" % MD.esc(Ollama.friendly(str(r[1]), str(r[2]), model))
			else:
				shown += "[color=#98a2b0](arrêté)[/color]\n"
			break
		if calls.is_empty():
			# JSON de l'outil écrit dans le texte (ou coupé net par la limite de longueur) : on récupère les nœuds/liens complets
			var salv := _salvage(txt)
			if not salv.is_empty():
				calls = [{"function": {"name": "creer_diagramme", "arguments": salv}}]
				txt = ""
				shown += "[color=#fbbf24](réponse du modèle %s : schéma récupéré)[/color]\n" % ("coupée" if acc[1] == "length" else "mal formée")
			elif acc[1] == "length" and not nudged:
				nudged = true
				msgs.append({"role": "assistant", "content": txt})
				msgs.append({"role": "user", "content": "Ta réponse a été coupée (trop longue). Recommence avec un schéma plus petit : 8 nœuds maximum, 4 mots par nœud."})
				shown += "[color=#fbbf24](réponse coupée : nouvel essai plus court)[/color]\n"
				continue
			elif trace.is_empty() and not nudged and _claims_done(txt):
				nudged = true
				msgs.append({"role": "assistant", "content": txt})
				msgs.append({"role": "user", "content": "Tu n'as appelé aucun outil : rien n'a été modifié sur le tableau. Appelle maintenant l'outil adapté (lister_elements si tu ne connais pas les ids)."})
				continue
		if calls.is_empty():
			final = txt
			shown += MD.to_bbcode(txt, T.OK.to_html(false))
			break
		msgs.append({"role": "assistant", "content": txt, "tool_calls": Orchestra.clean_calls(calls)})
		if txt.strip_edges() != "":
			shown += MD.to_bbcode(txt, T.OK.to_html(false)) + "\n"
		for tc in calls:
			var f: Dictionary = tc.get("function", {})
			var nm := str(f.get("name", ""))
			var args = f.get("arguments", {})
			if args is String:
				args = JSON.parse_string(args)
			if not (args is Dictionary):
				args = {}
			var res := GraphTools.run(sc, nm, args, center, created)
			trace.append({"name": nm, "args": args, "res": res})
			shown += "[color=#98a2b0]🔧 %s → %s[/color]\n" % [nm, MD.esc(res.left(80))]
			msgs.append({"role": "tool", "content": res, "tool_name": nm})
		_say(shown)
		board.canvas.redraw()
	# une seule étape d'historique pour toute la demande : Ctrl+Z annule tout ce que l'IA vient de faire
	if sc.commit():
		board.canvas.redraw()
		board._touch()
	if not created.is_empty():
		sc.select(created)
		board.canvas.sel_changed.emit()
		board.canvas.fit_selection()
	history.append({"role": "user", "content": text})
	history.append({"role": "assistant", "content": final if final != "" else "(fait)"})
	_say(shown)
	busy = false
	req = null
	input.editable = true
	input.grab_focus()


## « Voilà, c'est supprimé » sans appel d'outil : le modèle prétend avoir agi.
func _claims_done(t: String) -> bool:
	return RegEx.create_from_string("(?i)(supprim|cré|ajout|modifi|effac|reli|colori|renomm|déplac)(é|ée|és|ées)\\b|c'est fait|voilà").search(t) != null


## Récupère nœuds et liens complets dans un JSON d'outil écrit en texte (même coupé avant la fin).
func _salvage(txt: String) -> Dictionary:
	if '"noeuds"' not in txt and not ('"texte"' in txt and '"de"' in txt):
		return {}
	var nodes: Array = []
	var links: Array = []
	for m in RegEx.create_from_string("\\{[^{}]*\\}").search_all(txt):
		var o = JSON.parse_string(m.get_string())
		if o is Dictionary:
			if o.has("de") and o.has("vers"):
				links.append(o)
			elif o.has("texte"):
				nodes.append(o)
	if nodes.is_empty():
		return {}
	var disp := "arbre"
	var dm := RegEx.create_from_string("\"disposition\"\\s*:\\s*\"(arbre|ligne|grille)\"").search(txt)
	if dm != null:
		disp = dm.get_string(1)
	return {"noeuds": nodes, "liens": links, "disposition": disp}
