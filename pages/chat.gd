extends "res://pages/page.gd"
## Chat (onglet central) : conversation en streaming avec les 8 assistants (Ollama local), délégations visibles,
## Markdown, pièces jointes, historique. L'état de la conversation vit dans `chat` ; les vues sont reconstruites à la demande.

const ChatUI := preload("res://ui/chat_ui.gd")
const MD := preload("res://ui/markdown.gd")
const U := preload("res://ui/universe.gd")
const Chats := preload("res://core/chats.gd")
const Ollama := preload("res://core/ollama.gd")
const Attach := preload("res://core/attach.gd")
const Orchestra := preload("res://core/orchestra.gd")

const SUGGEST := {
	"goody": ["Explique-moi comment fonctionne un signal dans Godot", "Écris-moi un plan de semaine pour apprendre l'espagnol", "Donne-moi 3 idées de mini-jeux à finir en un week-end", "Résume les avantages de Linux pour jouer"],
	"rosie": ["Corrige ce texte et améliore le style", "Traduis en espagnol : « Je cherche la gare »", "Reformule ce message de façon plus polie", "Écris une courte présentation de mon projet"],
	"bleu": ["Écris un script GDScript de déplacement 2D", "Pourquoi mon signal ne se déclenche pas ?", "Explique les différences entre _process et _physics_process", "Écris un shader simple de vague"],
	"ambre": ["Calcule la moyenne et la médiane de cette liste", "Analyse ce fichier CSV joint", "Crée un tableau comparatif de trois options", "Explique comment faire un pourcentage de variation"],
	"mauve": ["Trouve 10 noms pour un jeu de survie", "Invente un univers de jeu original", "Écris le début d'une histoire mystérieuse", "Propose un système de progression pour un jeu"],
	"soleil": ["Apprends-moi 10 mots d'espagnol pour voyager", "Conjugue « tener » au présent", "Fais-moi un mini-dialogue au restaurant", "Corrige cette phrase en espagnol"],
	"braise": ["Comment gagner des FPS sur Arma Reforger ?", "Explique la structure d'un mod Enfusion", "Optimise ma config Linux pour jouer", "Quels réglages graphiques coûtent le plus ?"],
	"brume": ["Résume ce document joint en 5 points", "Décris cette image", "Quels sont les points clés de ce texte ?", "Extrais les dates importantes du fichier"],
}

var chat: Dictionary = {}
var status := "init"  # init | offline | nomodel | ready
var generating := false
var attachments: Array = []
var strip: ChatUI.Strip
var stage: ChatUI.Stage
var model_btn: W.Btn
var input: TextEdit
var send_btn: ChatUI.RoundBtn
var chips: HFlowContainer
var ctx_lbl: Label
var msgs: VBoxContainer
var refs: Dictionary = {}  # index du message -> {box, text_box, cards, name_row, dots, segs, footer}
var live_ref: Dictionary = {}
var live_text := ""
var live_dirty := false
var live_t := 0.0
var cursor_on := true
var cursor_t := 0.0
var stick := true
var _auto_scroll := false
var _draft := ""
var _chrome: Array = []
var _comp_c: Control
var _strip_c: Control
var _tok_t := 0.0
var _tok_n := 0
var rate := 0.0  # jetons / seconde (animation)
var last_rate_info := ""
var _undo_chat: Dictionary = {}


func _init() -> void:
	page_title = "Assistant IA"
	has_back = true
	max_w = 780.0


# ------------------------------------------------------------------ Construction

func build() -> void:
	head_title.text = ""
	if chat.is_empty():
		chat = Chats.new_chat(ctx.active, "")
	# en-tête : modèle, conversations, nouvelle, réglages
	model_btn = W.Btn.new("", "ghost")
	model_btn.size_name = "sm"
	model_btn.icon = "bot"
	model_btn.pressed.connect(_open_models)
	breakpoint_changed.connect(func(_b): _update_chip())
	head_right.add_child(model_btn)
	for d in [["menu", "Conversations", func(): router.push("chat_history")],
			["plus", "Nouvelle conversation", new_chat],
			["sliders", "Réglages du chat", func(): router.push("chat_settings")]]:
		var b := W.IconBtn.new(d[0], 40)
		b.tooltip_text = d[1]
		b.pressed.connect(d[2])
		head_right.add_child(b)
	# bandeau des assistants (entre l'en-tête et la liste)
	var sm: Container = K.Container_.new()
	sm.max_widths = caps
	extra_containers.append(sm)
	_outer.add_child(sm)
	_outer.move_child(sm, 1)
	strip = ChatUI.Strip.new(chat.assistant)
	strip.picked.connect(switch_assistant)
	sm.add_child(strip)
	_strip_c = strip
	_chrome.append(sm)
	# scène fixe : la place de l'assistant (ne défile pas) + route en perspective vers le chat
	var sc: Container = K.Container_.new()
	sc.max_widths = caps
	extra_containers.append(sc)
	_outer.add_child(sc)
	_outer.move_child(sc, 2)
	stage = ChatUI.Stage.new(int(chat.assistant))
	stage.picked.connect(switch_assistant)
	sc.add_child(stage)
	_chrome.append(sc)
	# messages
	msgs = VBoxContainer.new()
	msgs.add_theme_constant_override("separation", 16)
	body.add_child(msgs)
	link(scroll.get_v_scroll_bar().value_changed, _on_scrolled)
	_build_composer()
	link(ctx.orchestra.event, _on_event)
	link(get_window().files_dropped, _on_drop)
	_update_chip()
	_render_all()
	if generating:
		strip.set_mode(chat.assistant, "talk")
		stage.mode = "talk"
	if status == "init":
		_refresh_models()


func _build_composer() -> void:
	var m: Container = K.Container_.new()
	m.max_widths = caps
	m.pad_v = Tk.S2
	extra_containers.append(m)
	_outer.add_child(m)
	_chrome.append(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	m.add_child(v)
	_comp_c = v
	chips = HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 8)
	chips.add_theme_constant_override("v_separation", 4)
	v.add_child(chips)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	v.add_child(h)
	var clip := W.IconBtn.new("paperclip", 44)
	clip.tooltip_text = "Joindre un fichier ou une image (ou glisser-déposer)"
	clip.size_flags_vertical = Control.SIZE_SHRINK_END
	clip.pressed.connect(_pick_files)
	h.add_child(clip)
	input = TextEdit.new()
	input.placeholder_text = "Écris… (@Nom pour appeler un assistant)"
	input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	input.scroll_fit_content_height = true
	input.custom_minimum_size = Vector2(0, 46)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.add_theme_font_size_override("font_size", 16)
	for st in ["normal", "focus", "read_only"]:  # champ « Minecraft » : noir, cadre gris 2 px (blanc au focus)
		var mc := StyleBoxFlat.new()
		mc.bg_color = Color(0, 0, 0, 0.85)
		mc.border_color = Color("a0a0a0") if st == "focus" else Color("5a5a5a")
		mc.set_border_width_all(2)
		mc.set_content_margin_all(10)
		mc.set_meta("px", true)
		input.add_theme_stylebox_override(st, mc)
	input.add_theme_color_override("font_color", Color.WHITE)
	input.add_theme_color_override("font_placeholder_color", Color("8a8a8a"))
	input.gui_input.connect(_on_input_key)
	input.text_changed.connect(_on_input_changed)
	input.text = _draft
	h.add_child(input)
	send_btn = ChatUI.RoundBtn.new("send", 46)
	send_btn.size_flags_vertical = Control.SIZE_SHRINK_END
	send_btn.pressed.connect(_on_send_pressed)
	h.add_child(send_btn)
	ctx_lbl = W.label("", 12, T.DIM, v)
	ctx_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_refresh_attachments()
	_update_send()
	_grow()


func rebuild() -> void:
	if input != null and is_instance_valid(input):
		_draft = input.text
	for c in _chrome:
		if is_instance_valid(c):
			if c.get_parent() != null:
				c.get_parent().remove_child(c)
			c.queue_free()
	_chrome.clear()
	refs.clear()
	live_ref = {}
	super()


func on_show() -> void:
	if ctx.pending_chat != "":
		var id := ctx.pending_chat
		ctx.pending_chat = ""
		if id == "new":
			new_chat()
		else:
			open_chat(id)
	elif not generating:
		_refresh_models()
	if input != null:
		input.grab_focus.call_deferred()


func on_back() -> bool:
	if router.stack.size() == 1:  # sous-app : retour à la grille d'apps
		router.go_tab("home")
		return true
	return false


## Aligne la scène fixe sur l'assistant courant (modes normaux au repos).
func _stage_sync() -> void:
	if stage != null and is_instance_valid(stage):
		stage.ai = int(chat.assistant)
		stage.mode = "idle"
		stage.speed = 1.0


# ------------------------------------------------------------------ Modèles / état d'Ollama

func _refresh_models() -> void:
	var req := ctx.ollama.tags()
	var res: Array = await ctx.ollama.collect(req)
	if not is_inside_tree():
		return
	if res[0] and not res[3].is_empty():
		var ms: Array = []
		for m in res[3][0].get("models", []):
			ms.append({"name": str(m.get("name", "")), "size": float(m.get("size", 0))})
		ms.sort_custom(func(a, b): return a.size < b.size)
		ctx.models = ms
		ctx.prefetch_caps()
		if ctx.ollama_version == "":
			var vr: Array = await ctx.ollama.collect(ctx.ollama.version())
			if vr[0] and not vr[3].is_empty():
				ctx.ollama_version = str(vr[3][0].get("version", ""))
		status = "ready" if not ms.is_empty() else "nomodel"
	else:
		status = "offline"
	_update_chip()
	if chat.messages.is_empty():
		_render_all()


func current_model() -> String:
	if str(chat.get("model", "")) != "":
		return chat.model
	return ctx.model_for(int(chat.assistant))


func _update_chip() -> void:
	if model_btn == null or not is_instance_valid(model_btn):
		return
	var m := current_model()
	model_btn.text = "" if bp == "xs" else (m if m != "" else "Aucun modèle")
	model_btn.tooltip_text = "Modèle utilisé par " + U.get_u(chat.assistant).name


func _open_models() -> void:
	var items: Array = [{"id": "0", "label": "Auto · %s" % ctx.model_for(chat.assistant), "icon": "sparkles"}, {"sep": true}]
	for i in ctx.models.size():
		var nm: String = ctx.models[i].name
		var bad := U.is_broken(nm)
		items.append({"id": str(i + 1), "label": "%s  (%s)%s" % [nm, Ollama.fmt_size(ctx.models[i].size), " · incompatible" if bad else ""], "icon": "check" if nm == current_model() else "bot", "disabled": bad})
	items.append({"sep": true})
	items.append({"id": "1000", "label": "Télécharger un modèle…", "icon": "download"})
	var m: Control = K.Menu.open(router, items, model_btn.get_global_rect())
	m.chosen.connect(func(id: String): _on_model_menu(int(id)))
	if router.instant:
		m.set_meta("instant", true)


func _on_model_menu(id: int) -> void:
	if id == 1000:
		router.push("chat_settings")
		return
	if id == 0:
		chat["model"] = ""
	else:
		chat["model"] = ctx.models[id - 1].name
		ctx.store.set_s("chat", "model", chat.model)
	_save()
	_update_chip()


# ------------------------------------------------------------------ Conversations

func new_chat() -> void:
	if generating:
		ctx.orchestra.stop()
	chat = Chats.new_chat(ctx.active, "")
	attachments.clear()
	_after_chat_change()
	input.text = ""
	_grow()
	_refresh_attachments()
	input.grab_focus()


func open_chat(id: String) -> void:
	var c := ctx.chats.load_chat(id)
	if c.is_empty():
		return
	if generating:
		ctx.orchestra.stop()
	chat = c
	attachments.clear()
	_after_chat_change()
	_refresh_attachments()
	ctx.set_active(int(chat.assistant))


func _after_chat_change() -> void:
	live_ref = {}
	generating = false
	stick = true
	if strip != null and is_instance_valid(strip):
		strip.select(int(chat.assistant))
		strip.reset_modes()
		_stage_sync()
	_update_chip()
	_render_all()
	_update_send()


func _save() -> void:
	if (chat.messages as Array).is_empty():
		return
	chat["updated"] = Time.get_unix_time_from_system()
	chat["model"] = chat.get("model", "")
	ctx.chats.save(chat)


func switch_assistant(i: int) -> void:
	if i == int(chat.assistant) or i < 0 or i >= U.count():
		return
	if generating:
		ctx.notify("Attends la fin de la réponse (ou Stop)")
		return
	chat["assistant"] = i
	chat["model"] = ""
	if not (chat.messages as Array).is_empty():
		chat.messages.append({"role": "note", "text": "%s rejoint la conversation" % U.get_u(i).name, "assistant": i})
		_save()
	if input != null:
		_draft = input.text
	ctx.set_active(i)  # recolore l'app (la page se reconstruit)
	if strip != null and is_instance_valid(strip):
		strip.select(i)
	_stage_sync()
	_update_chip()
	_render_all()


func _shortcut_input(e: InputEvent) -> void:
	if not is_visible_in_tree() or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	if e.ctrl_pressed and e.keycode >= KEY_1 and e.keycode <= KEY_8:
		switch_assistant(e.keycode - KEY_1)
		get_viewport().set_input_as_handled()


# ------------------------------------------------------------------ Rendu des messages

func _clear_msgs() -> void:
	for c in msgs.get_children():
		msgs.remove_child(c)
		c.queue_free()
	refs.clear()


func _render_all() -> void:
	if msgs == null or not is_instance_valid(msgs):
		return
	_clear_msgs()
	var list: Array = chat.messages
	if list.is_empty():
		_render_empty()
	else:
		for i in list.size():
			_add_view(i)
	_update_ctx()
	_scroll_end.call_deferred()


func _render_empty() -> void:
	var u := U.get_u(chat.assistant)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	msgs.add_child(gap)
	match status:
		"offline":
			var sv := W.StateView.new("sad", chat.assistant, "Ollama est éteint", "Lance Ollama sur ce PC puis réessaie.", "Réessayer", 150)
			sv.action.connect(func():
				status = "init"
				_refresh_models())
			msgs.add_child(sv)
			return
		"nomodel":
			var sv2 := W.StateView.new("off", chat.assistant, "Aucun modèle installé", "Télécharge un petit modèle pour commencer.", "Télécharger", 150)
			sv2.action.connect(func(): router.push("chat_settings"))
			msgs.add_child(sv2)
			return
	var mo := W.label("« %s »" % u.motto, 15, T.DIM, msgs)
	mo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sug: Array = SUGGEST.get(u.id, [])
	var board := ChatUI.Board.new("Réponses rapides", sug)
	board.picked.connect(func(s: String): send_text(s))
	msgs.add_child(board)


func _add_view(i: int) -> void:
	var m: Dictionary = chat.messages[i]
	match m.get("role", ""):
		"user":
			_user_view(i, m)
		"note":
			var l := W.label("•  " + str(m.text), 13, T.DIM, msgs)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		"assistant":
			_assistant_view(i, m)


func _user_view(i: int, m: Dictionary) -> void:
	var h := HBoxContainer.new()
	msgs.add_child(h)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(56, 0)
	h.add_child(sp)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	h.add_child(col)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", T.style(Color(T.OK, 0.16),22, 12))
	col.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	for b64 in m.get("images", []):
		var tex := Attach.tex_from_b64(str(b64))
		if tex != null:
			v.add_child(ChatUI.PicFrame.new(tex, 120))
	if str(m.content) != "":
		var l := W.label(str(m.content), 16, T.TEXT, v)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for f in m.get("files", []):
		var fl := HBoxContainer.new()
		v.add_child(fl)
		W.pill(fl, "%s%s" % [f.name, " (tronqué)" if f.get("truncated", false) else ""], T.OK)
	# modifier le dernier message
	if _is_last_user(i) and not generating:
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_END
		col.add_child(row)
		var e := W.IconBtn.new("edit", 32)
		e.tooltip_text = "Modifier et renvoyer"
		e.pressed.connect(func(): _edit_last(i))
		row.add_child(e)


func _is_last_user(i: int) -> bool:
	for j in range(chat.messages.size() - 1, -1, -1):
		if chat.messages[j].role == "user":
			return j == i
	return false


func _assistant_view(i: int, m: Dictionary) -> void:
	var ai := int(m.get("assistant", chat.assistant))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	msgs.add_child(h)
	var av := W.Avatar.new()
	av.variant = ai
	av.custom_minimum_size = Vector2(36, 36)
	av.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(av)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	h.add_child(col)
	var nr := HBoxContainer.new()
	nr.add_theme_constant_override("separation", 8)
	col.add_child(nr)
	W.label(U.get_u(ai).name, 14, U.color(ai), nr).autowrap_mode = TextServer.AUTOWRAP_OFF
	var dots: ChatUI.Dots = null
	var cards := VBoxContainer.new()
	cards.add_theme_constant_override("separation", 8)
	col.add_child(cards)
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", 8)
	col.add_child(tb)
	var ref := {"i": i, "ai": ai, "name_row": nr, "cards": cards, "text_box": tb, "segs": [], "dots": dots, "card_views": {}, "footer": null, "col": col}
	refs[i] = ref
	for k in m.get("calls", []):
		var cv := ChatUI.CardView.new(int(k.from), int(k.to), str(k.question))
		cards.add_child(cv)
		cv.finish(str(k.answer))
		ref.card_views[int(k.id)] = cv
	var live: bool = generating and i == chat.messages.size() - 1
	if live:
		live_ref = ref
		_set_dots(ref, str(m.content) == "")
	_set_text(ref, str(m.content), live)
	if not live:
		_footer(ref, m, i)


func _set_dots(ref: Dictionary, on: bool) -> void:
	if on and ref.dots == null:
		var d := ChatUI.Dots.new()
		ref.name_row.add_child(d)
		ref.dots = d
	elif not on and ref.dots != null:
		ref.dots.queue_free()
		ref.dots = null


func _footer(ref: Dictionary, m: Dictionary, i: int) -> void:
	if ref.footer != null:
		ref.footer.queue_free()
	var f := HBoxContainer.new()
	f.add_theme_constant_override("separation", 4)
	ref.col.add_child(f)
	ref.footer = f
	var cp := W.IconBtn.new("copy", 32)
	cp.tooltip_text = "Copier"
	cp.pressed.connect(func():
		DisplayServer.clipboard_set(str(m.content))
		ctx.notify("Copié", "ok"))
	f.add_child(cp)
	if i == chat.messages.size() - 1 and not generating and str(m.get("content", "")) != "":
		var rg := W.IconBtn.new("refresh", 32)
		rg.tooltip_text = "Régénérer"
		rg.pressed.connect(regenerate)
		f.add_child(rg)
	if str(m.get("rate", "")) != "":
		W.label(str(m.rate), 12, T.DIM, f).size_flags_vertical = Control.SIZE_SHRINK_CENTER


## Met à jour les segments (texte / code) d'une réponse sans tout reconstruire.
func _set_text(ref: Dictionary, text: String, live: bool) -> void:
	var shown := Orchestra.visible_text(Ollama.strip_think(text)) if live else text
	var bl: Array = MD.blocks(shown)
	var segs: Array = ref.segs
	if live and cursor_on:
		if bl.is_empty():
			bl = [{"type": "text", "text": ""}]
	for k in bl.size():
		var b: Dictionary = bl[k]
		var is_last: bool = k == bl.size() - 1
		var txt: String = b.text + (" ▍" if live and cursor_on and is_last else "")
		if k < segs.size() and segs[k].type != b.type:
			segs[k].node.queue_free()
			segs.remove_at(k)
		if k >= segs.size():
			var node := _make_seg(b)
			ref.text_box.add_child(node)
			segs.insert(k, {"type": b.type, "node": node})
		_fill_seg(segs[k], b, txt)
	while segs.size() > bl.size():
		var s: Dictionary = segs.pop_back()
		s.node.queue_free()


func _make_seg(b: Dictionary) -> Control:
	if b.type == "text":
		var r := RichTextLabel.new()
		r.bbcode_enabled = true
		r.fit_content = true
		r.scroll_active = false
		r.selection_enabled = true
		r.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		r.add_theme_font_size_override("normal_font_size", 16)
		r.add_theme_font_size_override("bold_font_size", 16)
		r.add_theme_font_size_override("italics_font_size", 16)
		r.add_theme_font_size_override("mono_font_size", 14)
		r.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))
		return r
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", T.style(T.CARD,14, 8))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var hd := HBoxContainer.new()
	v.add_child(hd)
	var lg := W.label(str(b.lang), 12, T.DIM, hd)
	lg.name = "lang"
	W.spacer(hd)
	var cp := W.IconBtn.new("copy", 30)
	cp.tooltip_text = "Copier le code"
	cp.name = "copy"
	hd.add_child(cp)
	var code := Label.new()
	code.name = "code"
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["monospace", "DejaVu Sans Mono", "Liberation Mono"])
	code.add_theme_font_override("font", f)
	code.add_theme_font_size_override("font_size", 14)
	code.add_theme_color_override("font_color", Color("d6dde6"))
	code.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	v.add_child(code)
	return p


func _fill_seg(seg: Dictionary, b: Dictionary, txt: String) -> void:
	var node: Control = seg.node
	if b.type == "text":
		(node as RichTextLabel).text = MD.to_bbcode(txt, T.OK.to_html(false))
	else:
		var code: Label = node.find_child("code", true, false)
		code.text = b.text + (" ▍" if txt.ends_with(" ▍") else "")
		(node.find_child("lang", true, false) as Label).text = str(b.lang)
		var cp: W.IconBtn = node.find_child("copy", true, false)
		for c in cp.pressed.get_connections():
			cp.pressed.disconnect(c.callable)
		var raw: String = b.text
		cp.pressed.connect(func():
			DisplayServer.clipboard_set(raw)
			ctx.notify("Code copié", "ok"))


# ------------------------------------------------------------------ Saisie

func _on_input_key(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and (e.keycode == KEY_ENTER or e.keycode == KEY_KP_ENTER):
		if e.shift_pressed:
			return  # saut de ligne
		input.accept_event()
		_on_send_pressed()


func _on_input_changed() -> void:
	_grow()
	_update_ctx()


func _grow() -> void:
	if input == null or not is_instance_valid(input):
		return
	var lines := input.get_total_visible_line_count()
	var h := lines * input.get_line_height() + 26
	if h > 170:
		input.scroll_fit_content_height = false
		input.custom_minimum_size.y = 170
	else:
		input.scroll_fit_content_height = true
		input.custom_minimum_size.y = 46


func _update_send() -> void:
	if send_btn == null or not is_instance_valid(send_btn):
		return
	send_btn.kind = "stop" if generating else "send"
	send_btn.tooltip_text = "Arrêter" if generating else "Envoyer"


func _on_send_pressed() -> void:
	if generating:
		ctx.orchestra.stop()
		return
	var raw := input.text
	send_text(raw)


func _update_ctx() -> void:
	if ctx_lbl == null or not is_instance_valid(ctx_lbl):
		return
	var n := 0
	for m in chat.messages:
		n += Chats.approx_tokens(str(m.get("content", ""))) + Chats.approx_tokens(" ".join(PackedStringArray((m.get("files", []) as Array).map(func(f): return str(f.get("text", ""))))))
	if input != null:
		n += Chats.approx_tokens(input.text)
	for a in attachments:
		n += Chats.approx_tokens(str(a.text))
	var cap := int(ctx.store.get_s("chat", "num_ctx", 4096))
	ctx_lbl.text = "≈ %s / %s" % [_k(n), _k(cap)]
	ctx_lbl.add_theme_color_override("font_color", T.WARN if n > cap * 0.85 else T.DIM)


func _k(n: int) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 1000 else str(n)


# ------------------------------------------------------------------ Pièces jointes

func _pick_files() -> void:
	var fp: Control = K.FilePicker.new()
	fp.files_selected.connect(attach_files)
	fp.open_in(router, OS.get_environment("HOME"))


func _on_drop(files: PackedStringArray) -> void:
	if is_visible_in_tree():
		attach_files(files)


func attach_files(paths: PackedStringArray) -> void:
	for p in paths:
		if attachments.size() >= Attach.MAX_FILES:
			ctx.notify("Maximum %d fichiers" % Attach.MAX_FILES, "error")
			break
		var a := Attach.read(p)
		if a.kind == "bad":
			ctx.notify("%s : %s" % [a.name, a.error], "error")
			continue
		if a.kind == "image" and not ctx.model_is_vision(current_model()):
			ctx.notify("Ce modèle ne lit pas les images : choisis Brume (Ctrl+8) ou un modèle vision.", "error")
			continue
		if a.truncated:
			ctx.notify("%s tronqué à %d caractères" % [a.name, Attach.MAX_TEXT])
		attachments.append(a)
	_refresh_attachments()
	_update_ctx()


func _refresh_attachments() -> void:
	if chips == null or not is_instance_valid(chips):
		return
	for c in chips.get_children():
		chips.remove_child(c)
		c.queue_free()
	chips.visible = not attachments.is_empty()
	for k in attachments.size():
		var a: Dictionary = attachments[k]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", T.style(T.FIELD,16, 4))
		chips.add_child(p)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 4)
		p.add_child(h)
		if a.tex != null:
			var tr := TextureRect.new()
			tr.texture = a.tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
			tr.custom_minimum_size = Vector2(28, 28)
			h.add_child(tr)
		var l := W.label(str(a.name) + (" (tronqué)" if a.truncated else ""), 13, T.TEXT, h)
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var x := W.IconBtn.new("close", 26)
		x.pressed.connect(func():
			attachments.remove_at(k)
			_refresh_attachments()
			_update_ctx())
		h.add_child(x)


# ------------------------------------------------------------------ Envoi / génération

## Envoie un message (gère @Nom, pièces jointes, vérifications). Renvoie true si parti.
func send_text(raw: String) -> bool:
	if generating:
		return false
	var men := U.parse_mention(raw)
	var text: String = men.text
	if men.index >= 0:
		input.text = ""
		_draft = ""
		switch_assistant(men.index)
		if text.strip_edges() == "" and attachments.is_empty():
			return false
	text = text.strip_edges()
	if text == "" and attachments.is_empty():
		return false
	var model := current_model()
	if model == "":
		ctx.notify("Aucun modèle Ollama disponible", "error")
		return false
	var m := {"role": "user", "content": text}
	var files: Array = []
	var images: Array = []
	for a in attachments:
		if a.kind == "image":
			if not ctx.model_is_vision(model):
				ctx.notify("Ce modèle ne lit pas les images : passe à Brume (Ctrl+8) ou choisis un modèle vision.", "error")
				return false
			images.append(a.b64)
		else:
			files.append({"name": a.name, "text": a.text, "truncated": a.truncated})
	if not files.is_empty():
		m["files"] = files
	if not images.is_empty():
		m["images"] = images
	chat.messages.append(m)
	if str(chat.title) == "":
		chat["title"] = (text if text != "" else str(attachments[0].name)).replace("\n", " ").left(42)
	chat["model"] = chat.get("model", "")
	attachments.clear()
	input.text = ""
	_draft = ""
	_refresh_attachments()
	_grow()
	_save()
	stick = true
	_generate()
	return true


func _generate() -> void:
	var ai := int(chat.assistant)
	generating = true
	chat.messages.append({"role": "assistant", "assistant": ai, "content": "", "calls": [], "model": current_model()})
	_save()
	_render_all()
	_update_send()
	var override: String = str(chat.get("model", ""))
	var orch: Orchestra = ctx.orchestra
	orch.ollama = ctx.ollama
	orch.allow = bool(ctx.store.get_s("chat", "delegate", true))
	orch.extra = str(ctx.store.get_s("chat", "system", ""))
	orch.opts = {"temperature": float(ctx.store.get_s("chat", "temp", 0.7)), "num_ctx": int(ctx.store.get_s("chat", "num_ctx", 4096)),
			"user_temp": bool(ctx.store.get_s("chat", "temp_set", false)), "user_temp_v": float(ctx.store.get_s("chat", "temp", 0.7))}
	orch.resolve_model = func(a: int) -> String:
		return override if override != "" and a == ai else ctx.model_for(a)
	_tok_n = 0
	_tok_t = 0.0
	rate = 0.0
	live_text = ""
	var hist := Chats.api_messages(chat, ai, chat.messages.size() - 1)
	orch.run(ai, hist)


func regenerate() -> void:
	if generating or chat.messages.is_empty():
		return
	while not chat.messages.is_empty() and chat.messages.back().role != "user":
		chat.messages.pop_back()
	_generate()


func _edit_last(i: int) -> void:
	if generating:
		return
	var m: Dictionary = chat.messages[i]
	input.text = str(m.content)
	while chat.messages.size() > i:
		chat.messages.pop_back()
	_save()
	_render_all()
	_grow()
	input.grab_focus()
	input.set_caret_line(input.get_line_count() - 1)


func send_prompt_for_test(t: String) -> void:
	send_text(t)


# ------------------------------------------------------------------ Événements de l'orchestre

func _speed() -> float:
	return clampf(rate / 12.0, 0.6, 2.2) if rate > 0.0 else 1.0


func _on_event(kind: String, d: Dictionary) -> void:
	if not is_instance_valid(strip) or not generating:
		return
	match kind:
		"speaker":
			strip.set_mode(int(d.ai), str(d.mode), _speed())
			if stage != null and is_instance_valid(stage):
				stage.ai = int(d.ai)
				stage.mode = str(d.mode)
				stage.speed = _speed()
		"token":
			_tok_n += 1
			if int(d.id) == -1:
				live_text = str(d.text)
				if not live_ref.is_empty():
					_set_dots(live_ref, false)
				live_dirty = true
			else:
				var cv: ChatUI.CardView = live_ref.get("card_views", {}).get(int(d.id))
				if cv != null:
					cv.set_answer(str(d.text), true)
					live_dirty = true
		"card_open":
			var m: Dictionary = chat.messages.back()
			m.calls.append(d.duplicate())
			if not live_ref.is_empty():
				var cv2 := ChatUI.CardView.new(int(d.from), int(d.to), str(d.question))
				live_ref.cards.add_child(cv2)
				live_ref.card_views[int(d.id)] = cv2
				_set_dots(live_ref, false)
		"card_done":
			for k in chat.messages.back().calls:
				if int(k.id) == int(d.id):
					k["answer"] = d.answer
			var cv3: ChatUI.CardView = live_ref.get("card_views", {}).get(int(d.id))
			if cv3 != null:
				cv3.finish(str(d.answer))
		"notice":
			ctx.notify(str(d.text))
		"done":
			_finish(str(d.text), float(d.rate), "")
		"stopped":
			_finish(live_text, 0.0, "")
		"error":
			_finish(live_text, 0.0, str(d.kind) + "|" + str(d.msg))


func _finish(text: String, tps: float, err: String) -> void:
	generating = false
	var m: Dictionary = chat.messages.back() if not chat.messages.is_empty() else {}
	if not m.is_empty() and m.role == "assistant":
		m["content"] = Ollama.strip_think(text).strip_edges()
		if tps > 0.0:
			m["rate"] = "%.0f tok/s" % tps
		if m.content == "" and (m.get("calls", []) as Array).is_empty():
			chat.messages.pop_back()
	live_ref = {}
	_save()
	_render_all()
	_update_send()
	if err != "":
		var parts := err.split("|", true, 1)
		_show_error(parts[0], parts[1] if parts.size() > 1 else "")
		if parts[0] == "offline":
			status = "offline"
	elif _should_title():
		_auto_title()
	if err == "":
		(func():
			await get_tree().create_timer(1.6).timeout
			if not generating and is_instance_valid(strip):
				strip.reset_modes()
				_stage_sync()).call()
	else:
		strip.reset_modes()
		_stage_sync()
	if not chat.messages.is_empty():
		_scroll_end.call_deferred()


func _show_error(kind: String, msg: String) -> void:
	var card: PanelContainer = K.Card.new()
	card.add_theme_stylebox_override("panel", T.style(Color(T.BAD, 0.12), Tk.R_LG, Tk.S4))
	card.set_meta("k_error", true)
	msgs.add_child(card)
	var v := KS.vbox(card, Tk.S3)
	var model := current_model()
	var txt := Ollama.friendly(kind, msg, model, ctx.ollama_version)
	var h := KS.hbox(v, Tk.S3)
	var ic: Control = K.Icon.make("circle-x", 20, T.BAD)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	KS.label(h, txt, Tk.FS_SM, T.TEXT, 500, true)
	var prog: Control = K.Progress.new()
	prog.visible = false
	v.add_child(prog)
	var row: Control = K.Row.new()
	v.add_child(row)
	if kind == "model_missing":
		var dl := K.Btn.make("Télécharger", "primary", "md", "download")
		dl.pressed.connect(func():
			dl.loading = true
			prog.visible = true
			prog.indeterminate = true
			var req: Ollama.Req = ctx.ollama.pull(model)
			req.line.connect(func(d: Dictionary):
				if d.has("total") and d.has("completed") and float(d.total) > 0.0:
					prog.indeterminate = false
					prog.value = float(d.completed) / float(d.total))
			var r: Array = await req.finished
			if not is_instance_valid(card):
				return
			ctx.notify("%s téléchargé" % model if r[0] else "Téléchargement impossible : " + str(r[2]), "ok" if r[0] else "error")
			if r[0]:
				card.queue_free()
				_refresh_models()
				regenerate()
			else:
				dl.loading = false)
		row.add_child(dl)
	else:
		var rb := K.Btn.make("Réessayer", "primary", "md", "refresh-cw")
		rb.pressed.connect(func():
			card.queue_free()
			regenerate())
		row.add_child(rb)
	var cb := K.Btn.make("Changer de modèle", "secondary", "md", "bot")
	cb.pressed.connect(_open_models_from.bind(cb))
	row.add_child(cb)
	_scroll_end.call_deferred()


func _open_models_from(anchor: Control) -> void:
	var items: Array = []
	for i in ctx.models.size():
		var nm: String = ctx.models[i].name
		items.append({"id": str(i + 1), "label": nm, "icon": "bot", "disabled": U.is_broken(nm)})
	items.append({"sep": true})
	items.append({"id": "1000", "label": "Télécharger un modèle…", "icon": "download"})
	var m: Control = K.Menu.open(router, items, anchor.get_global_rect())
	m.chosen.connect(func(id: String): _on_model_menu(int(id)))


func _should_title() -> bool:
	return not chat.get("titled", false) and (chat.messages as Array).size() >= 2


func _auto_title() -> void:
	chat["titled"] = true
	var id: String = chat.id
	var q := ""
	var a := ""
	for m in chat.messages:
		if m.role == "user" and q == "":
			q = str(m.content).left(300)
		elif m.role == "assistant" and a == "":
			a = str(m.content).left(300)
	var model := ctx.model_for(0)
	if model == "":
		return
	var req := ctx.ollama.chat(model, [{"role": "user", "content": "Donne un titre de 3 à 5 mots, sans guillemets ni ponctuation finale, pour cette conversation.\nQuestion : %s\nRéponse : %s\nTitre :" % [q, a]}],
			{"temperature": 0.3, "num_predict": 20}, [], false)
	var res: Array = await ctx.ollama.collect(req)
	if not res[0] or res[3].is_empty():
		return
	var t := Ollama.strip_think(str(res[3].back().get("message", {}).get("content", ""))).strip_edges().replace("\"", "").replace("«", "").replace("»", "").split("\n")[0].left(50).strip_edges()
	if t == "":
		return
	if chat.get("id", "") == id:
		chat["title"] = t
		_save()
	else:
		ctx.chats.patch(id, {"title": t, "titled": true})


# ------------------------------------------------------------------ Défilement et animation

func _on_scrolled(v: float) -> void:
	if _auto_scroll:
		return
	var bar := scroll.get_v_scroll_bar()
	stick = v >= bar.max_value - bar.page - 28.0


func _scroll_end() -> void:
	if scroll == null or not is_instance_valid(scroll):
		return
	var bar := scroll.get_v_scroll_bar()
	_auto_scroll = true
	bar.value = bar.max_value
	_auto_scroll = false


func _process(dt: float) -> void:
	if not generating:
		return
	live_t += dt
	cursor_t += dt
	_tok_t += dt
	if _tok_t >= 0.5:
		var r := float(_tok_n) / _tok_t
		rate = r if rate == 0.0 else lerpf(rate, r, 0.5)
		_tok_n = 0
		_tok_t = 0.0
		if strip != null and is_instance_valid(strip):
			for tl in strip.tiles:
				if tl.mode != "idle":
					tl.speed = _speed()
	if cursor_t >= 0.5:
		cursor_t = 0.0
		cursor_on = not cursor_on
		live_dirty = true
	if live_dirty and live_t >= 0.05 and not live_ref.is_empty():
		live_t = 0.0
		live_dirty = false
		_set_text(live_ref, live_text, true)
	if stick:
		_scroll_end()


## Appelée quand une conversation est supprimée depuis l'historique.
func forget(id: String) -> void:
	if chat.get("id", "") == id:
		if generating:
			ctx.orchestra.stop()
		chat = Chats.new_chat(ctx.active, "")
		_after_chat_change()
