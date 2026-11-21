extends "res://pages/page.gd"
## Réglages du chat : modèles installés + téléchargement (/api/pull), température, contexte, URL d'Ollama,
## consignes système, liste des 8 assistants.

const U := preload("res://ui/universe.gd")
const Ollama := preload("res://core/ollama.gd")
const SUGGESTED := ["llama3.2:3b", "gemma3:4b", "qwen3:8b", "qwen2.5-coder:7b"]

var _models_box: VBoxContainer
var _pull_edit: Control
var _pull_bar: ProgressBar
var _pull_lbl: Label
var _pull_btn: W.Btn


func _init() -> void:
	page_title = "Réglages du chat"


func build() -> void:
	set_title("Réglages du chat")
	# --- Modèles
	var c1 := W.card(body)
	W.label("Modèles", 18, T.TEXT, c1)
	_models_box = VBoxContainer.new()
	_models_box.add_theme_constant_override("separation", 4)
	c1.add_child(_models_box)
	_fill_models()
	W.hsep(c1)
	W.label("Télécharger un modèle", 15, T.DIM, c1)
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 8)
	c1.add_child(hr)
	_pull_edit = K.InputField.new()
	_pull_edit.label_text = "Modèle (ex. llama3.2:3b)"
	_pull_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pull_edit.text_submitted.connect(func(_t): start_pull(_pull_edit.text))
	hr.add_child(_pull_edit)
	_pull_btn = W.Btn.new("", "primary")
	_pull_btn.pressed.connect(func(): start_pull(_pull_edit.text))
	hr.add_child(_pull_btn)
	var dl := W.IconBtn.new("download", 46)
	dl.tooltip_text = "Télécharger"
	dl.pressed.connect(func(): start_pull(_pull_edit.text))
	hr.add_child(dl)
	_pull_btn.visible = false
	var fl := HFlowContainer.new()
	fl.add_theme_constant_override("h_separation", 4)
	fl.add_theme_constant_override("v_separation", 4)
	c1.add_child(fl)
	for s in SUGGESTED:
		var b := W.Btn.new(s, "soft")
		b.custom_minimum_size = Vector2(0, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			_pull_edit.text = s)
		fl.add_child(b)
	_pull_bar = ProgressBar.new()
	_pull_bar.show_percentage = false
	_pull_bar.custom_minimum_size = Vector2(0, 8)
	c1.add_child(_pull_bar)
	_pull_lbl = W.label("", 13, T.DIM, c1)
	_sync_pull()

	# --- Génération
	var c2 := W.card(body)
	W.label("Génération", 18, T.TEXT, c2)
	var temp_set := bool(ctx.store.get_s("chat", "temp_set", false))
	var r1 := W.setting_row(c2, "Température", "Auto = réglage propre à chaque assistant")
	var tl := W.label("", 15, T.OK, r1)
	tl.autowrap_mode = TextServer.AUTOWRAP_OFF
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sl := HSlider.new()
	sl.min_value = 0.0
	sl.max_value = 2.0
	sl.step = 0.05
	sl.value = float(ctx.store.get_s("chat", "temp", 0.7))
	sl.custom_minimum_size = Vector2(0, 26)
	tl.text = "%.2f" % sl.value if temp_set else "auto"
	sl.value_changed.connect(func(v: float):
		ctx.store.cfg.set_value("chat", "temp", v)
		ctx.store.cfg.set_value("chat", "temp_set", true)
		ctx.store.save_cfg()
		tl.text = "%.2f" % v)
	c2.add_child(sl)
	var ab := W.Btn.new("Auto", "ghost")
	ab.custom_minimum_size = Vector2(0, 36)
	ab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	ab.pressed.connect(func():
		ctx.store.set_s("chat", "temp_set", false)
		tl.text = "auto")
	c2.add_child(ab)
	W.hsep(c2)
	var r2 := W.setting_row(c2, "Contexte (tokens)", "")
	var opts := [[2048, "2k"], [4096, "4k"], [8192, "8k"], [16384, "16k"]]
	var cur := int(ctx.store.get_s("chat", "num_ctx", 4096))
	var seg := W.Seg.new(opts.map(func(o): return [str(o[0]), o[1]]), str(cur))
	seg.custom_minimum_size = Vector2(240, 38)
	seg.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	seg.changed.connect(func(id: String): ctx.store.set_s("chat", "num_ctx", int(id)))
	r2.add_child(seg)
	W.hsep(c2)
	W.label("URL d'Ollama (reste sur ce PC)", 15, T.DIM, c2)
	var ue: Control = K.InputField.new()
	ue.label_text = "URL"
	ue.text = ctx.ollama.base_url
	var commit_url := func():
		var u: String = ue.text.strip_edges()
		if u == "":
			u = Ollama.DEFAULT_URL
		ctx.ollama.base_url = u
		ctx.store.set_s("chat", "url", u)
	ue.text_submitted.connect(func(_t): commit_url.call())
	ue.blurred.connect(func(): commit_url.call())
	c2.add_child(ue)

	# --- Consignes
	var c3 := W.card(body)
	W.label("Consignes supplémentaires", 18, T.TEXT, c3)
	W.label("Ajoutées au prompt de chaque assistant. Vide = prompt par défaut de l'assistant (sa personnalité).", 13, T.DIM, c3)
	var te := TextEdit.new()
	te.text = str(ctx.store.get_s("chat", "system", ""))
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.custom_minimum_size = Vector2(0, 110)
	te.text_changed.connect(func(): ctx.store.set_s("chat", "system", te.text))
	c3.add_child(te)

	# --- Assistants
	var c4 := W.card(body)
	W.label("Assistants", 18, T.TEXT, c4)
	for i in U.count():
		var u := U.get_u(i)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		c4.add_child(h)
		var av := W.Avatar.new()
		av.variant = i
		av.custom_minimum_size = Vector2(40, 40)
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(av)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		v.add_theme_constant_override("separation", 0)
		h.add_child(v)
		W.label("%s%s" % [u.name, "  · chef d'orchestre" if u.role == "general" else ""], 16, Color(str(u.accent)), v)
		W.label(str(u.specialty), 12, T.DIM, v)
		var m := ctx.model_for(i)
		var pl := HBoxContainer.new()
		v.add_child(pl)
		W.pill(pl, m if m != "" else "aucun modèle", T.OK if m != "" else T.DIM).set_meta("k_dup_ok", true)  # affectation assistant -> modèle (pas un doublon)


func _fill_models() -> void:
	for c in _models_box.get_children():
		_models_box.remove_child(c)
		c.queue_free()
	if ctx.models.is_empty():
		W.label("Aucun modèle détecté (Ollama est-il lancé ?)", 14, T.DIM, _models_box)
		return
	for m in ctx.models:
		var h := HBoxContainer.new()
		_models_box.add_child(h)
		var l := W.label(m.name, 15, T.TEXT, h)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if U.is_broken(m.name):
			W.pill(h, "incompatible", T.BAD)
		elif ctx.model_is_vision(m.name):
			W.pill(h, "vision", T.OK)
		W.label(Ollama.fmt_size(m.size), 13, T.DIM, h)


## Lance /api/pull en streaming (progression partagée : survit à la fermeture de la page).
func start_pull(model: String) -> void:
	var name := model.strip_edges()
	if name == "":
		return
	if not ctx.pull.is_empty() and ctx.pull.get("req") != null and not ctx.pull.get("done", true):
		ctx.notify("Un téléchargement est déjà en cours")
		return
	var req := ctx.ollama.pull(name)
	var st := {"model": name, "ratio": 0.0, "status": "Connexion…", "req": req, "done": false, "error": ""}
	ctx.pull = st
	req.line.connect(func(d: Dictionary):
		if d.has("error"):
			st.error = str(d.error)
		st.status = str(d.get("status", ""))
		if float(d.get("total", 0)) > 0.0:
			st.ratio = float(d.get("completed", 0)) / float(d.total))
	req.finished.connect(func(ok: bool, kind: String, msg: String):
		st.done = true
		if not ok:
			st.error = msg if st.error == "" else st.error
		if ok and st.error == "":
			st.ratio = 1.0
			st.status = "Terminé"
			ctx.notify("%s : téléchargé" % name, "ok")
			_reload_models()
		elif kind != "cancel":
			ctx.notify("Téléchargement impossible : " + str(st.error), "error"))


func _reload_models() -> void:
	var res: Array = await ctx.ollama.collect(ctx.ollama.tags())
	if res[0] and not res[3].is_empty():
		var ms: Array = []
		for m in res[3][0].get("models", []):
			ms.append({"name": str(m.get("name", "")), "size": float(m.get("size", 0))})
		ms.sort_custom(func(a, b): return a.size < b.size)
		ctx.models = ms
		ctx.prefetch_caps()
	if is_inside_tree() and _models_box != null and is_instance_valid(_models_box):
		_fill_models()


func _sync_pull() -> void:
	var st: Dictionary = ctx.pull
	_pull_bar.visible = not st.is_empty()
	_pull_lbl.visible = not st.is_empty()
	if st.is_empty():
		return
	_pull_bar.value = float(st.ratio) * 100.0
	_pull_lbl.text = ("%s : %s" % [st.model, st.error]) if st.error != "" else "%s · %s %d %%" % [st.model, st.status, int(float(st.ratio) * 100.0)]
	_pull_lbl.add_theme_color_override("font_color", T.BAD if st.error != "" else T.DIM)


func _process(_d: float) -> void:
	if _pull_bar != null and not ctx.pull.is_empty() and not ctx.pull.get("done", true):
		_sync_pull()
