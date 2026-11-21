extends PanelContainer
## Barre de saisie flottante en bas du tableau (Entrée pour l'ouvrir, Échap pour la fermer), deux modes :
##  - « Discuter » (défaut) : le message devient un nœud (réponse au nœud sélectionné, sinon nouvelle conversation) et l'IA
##    répond dans un nœud enfant (board.chat_say) ;
##  - « Éditer le graphe » : on lui parle (« fais un schéma de… », « mets le deuxième nœud en rouge »), il agit sur la
##    scène avec les outils de graph_tools.gd. Tout ce qu'il fait pendant une demande forme UNE seule étape d'historique.

const U := preload("res://ui/universe.gd")
const T := preload("res://ui/theme.gd")
const MD := preload("res://ui/markdown.gd")
const Ollama := preload("res://core/ollama.gd")
const Orchestra := preload("res://core/orchestra.gd")
const GraphTools := preload("res://ui/draw/graph_tools.gd")
const Chat := preload("res://ui/draw/chat.gd")
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
var mode := "chat"  # "chat" : discuter en nœuds ; "graph" : éditer le graphe
var fork := false  # prochaine réponse = nouvelle branche (« Branche ici »)
var force_root := false  # le prochain message démarre une nouvelle conversation même si un nœud est sélectionné
var who: OptionButton
var b_chat: Button
var b_graph: Button
var target_b: Button
var model_l: Label
var _syncing := false


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
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	v.add_child(top)
	var grp := ButtonGroup.new()
	b_chat = Button.new()
	b_chat.text = "Discuter"
	b_chat.tooltip_text = "Ton message devient un nœud ; l'IA répond dans un nœud enfant (Entrée)"
	b_chat.toggle_mode = true
	b_chat.button_group = grp
	b_chat.pressed.connect(func(): set_mode("chat"))
	top.add_child(b_chat)
	b_graph = Button.new()
	b_graph.text = "Éditer le graphe"
	b_graph.tooltip_text = "L'IA crée et modifie des schémas (Ctrl+Entrée)"
	b_graph.toggle_mode = true
	b_graph.button_group = grp
	b_graph.pressed.connect(func(): set_mode("graph"))
	top.add_child(b_graph)
	who = OptionButton.new()
	who.tooltip_text = "Assistant qui répond"
	for i in U.count():
		who.add_item(str(U.get_u(i).name), i)
	var act = board.ctx.get("active")
	who.selected = clampi(int(act) if act != null else 0, 0, U.count() - 1)
	who.item_selected.connect(func(_i: int): _sync_target())
	top.add_child(who)
	model_l = Label.new()
	model_l.add_theme_font_size_override("font_size", 11)
	model_l.add_theme_color_override("font_color", T.DIM)
	model_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	model_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(model_l)
	target_b = Button.new()
	target_b.flat = true
	target_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	target_b.add_theme_font_size_override("font_size", 12)
	target_b.tooltip_text = "Cliquer : alterner entre répondre au nœud sélectionné et démarrer une nouvelle conversation"
	target_b.pressed.connect(func():
		force_root = not force_root
		_sync_target())
	target_b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	target_b.custom_minimum_size = Vector2(0, 0)
	v.add_child(target_b)
	var row := HBoxContainer.new()
	v.add_child(row)
	input = LineEdit.new()
	input.placeholder_text = "Écris un message…  (Entrée : envoyer · Échap : fermer)"
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
	if board.canvas.has_signal("sel_changed"):
		board.canvas.sel_changed.connect(_sync_target)
	set_mode("chat")


## Bascule « Discuter » / « Éditer le graphe ».
func set_mode(m: String) -> void:
	mode = "graph" if m == "graph" else "chat"
	_syncing = true
	b_chat.button_pressed = mode == "chat"
	b_graph.button_pressed = mode == "graph"
	_syncing = false
	who.visible = mode == "chat"
	target_b.visible = mode == "chat"
	reply.visible = mode == "graph" and reply.text != ""
	input.placeholder_text = "Écris un message…  (Entrée : envoyer · Échap : fermer)" if mode == "chat" else "Éditer le graphe : « fais un schéma de… », « mets en rouge… »  (Entrée : envoyer · Échap : fermer)"
	_sync_target()
	reposition()


## Nœud auquel le prochain message répond : le nœud de chat sélectionné, sinon "" (nouvelle conversation).
func target_id() -> String:
	if force_root:
		return ""
	var sel: Array = board.scene.selected()
	if sel.size() == 1 and Chat.is_msg(sel[0]):
		return str(sel[0].id)
	return ""


func _sync_target() -> void:
	if target_b == null:
		return
	if mode == "chat":
		var tid := target_id()
		var el: Dictionary = board.scene.get_el(tid) if tid != "" else {}
		if el.is_empty():
			target_b.text = "✚ Nouvelle conversation (sélectionne un nœud pour lui répondre)" if not force_root else "✚ Nouvelle conversation (cliquer : répondre au nœud sélectionné)"
		else:
			var t := Chat.title_of(el)
			target_b.text = "%s « %s » (cliquer : nouvelle conversation)" % ["⑂ Nouvelle branche depuis" if fork else "↳ Réponse à", t if t != "" else "…"]
	var m := ""
	if mode == "chat":
		m = str(board.ctx.model_for(who.selected))
	else:
		m = _model()
	model_l.text = "modèle : " + (m if m != "" else "aucun")
	reposition()


func open(m := "") -> void:
	if m != "":
		set_mode(m)
	fork = false
	visible = true
	_sync_target()
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
	if mode == "chat":
		if text == "":
			return
		input.text = ""
		var parent := target_id()
		var fk := fork
		fork = false
		force_root = false
		board.chat_say(text, parent, who.selected, fk)  # sans attendre : la barre reste libre pour la suite
		_sync_target()
		return
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
