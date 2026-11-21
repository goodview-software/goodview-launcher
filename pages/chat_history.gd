extends "res://pages/page.gd"
## Conversations : groupées (Épinglées / Aujourd'hui / Hier / Cette semaine / Plus ancien), recherche plein texte,
## filtre par assistant, renommer, épingler, exporter en Markdown, supprimer (annulable).

const Chats := preload("res://core/chats.gd")
const U := preload("res://ui/universe.gd")

var query := ""
var filter_ai := -1
var renaming := ""
var _list: VBoxContainer
var _filters: Control


func _init() -> void:
	page_title = "Conversations"


func build() -> void:
	set_title("Conversations")
	var nb := W.IconBtn.new("plus", 44)
	nb.tooltip_text = "Nouvelle conversation"
	nb.pressed.connect(func():
		ctx.pending_chat = "new"
		router.back())
	head_right.add_child(nb)
	var se: Control = K.InputField.new()
	se.label_text = "Rechercher dans les conversations"
	se.icon = "search"
	se.text = query
	se.text_changed.connect(func(t: String):
		query = t.strip_edges()
		_render())
	body.add_child(se)
	_filters = K.Row.new()
	_filters.gap = Tk.S1
	body.add_child(_filters)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	body.add_child(_list)
	_render()


func set_filter(i: int) -> void:
	filter_ai = -1 if filter_ai == i else i
	_render()


func _render() -> void:
	for c in _filters.get_children():
		_filters.remove_child(c)
		c.queue_free()
	for i in U.count():
		var av := W.Avatar.new(true)
		av.variant = i
		av.selected = i == filter_ai
		av.custom_minimum_size = Vector2(44, 44)
		av.tooltip_text = "Filtrer : " + str(U.get_u(i).name)
		av.pressed.connect(func(): set_filter(i))
		_filters.add_child(av)
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var es := Chats.search(ctx.chats.index, query, filter_ai)
	if es.is_empty():
		var sv := W.StateView.new("off", ctx.active, "Aucune conversation", "", "", 130)
		_list.add_child(sv)
		return
	for g in Chats.group(es, Time.get_unix_time_from_system()):
		W.label(g[0], 13, T.DIM, _list)
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", T.style(T.CARD,22, 4))
		_list.add_child(card)
		var v := VBoxContainer.new()
		card.add_child(v)
		for k in g[1].size():
			if k > 0:
				W.hsep(v)
			v.add_child(_row(g[1][k]))


func _row(e: Dictionary) -> Control:
	var row := W.Row.new()
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	var av := W.Avatar.new()
	av.variant = int(e.assistant)
	av.custom_minimum_size = Vector2(40, 40)
	av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(av)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	if renaming == e.id:
		var le := LineEdit.new()
		le.text = Chats.display_title(e)
		le.custom_minimum_size = Vector2(0, 38)
		le.text_submitted.connect(func(t: String):
			_rename(e.id, t))
		le.focus_exited.connect(func(): _rename(e.id, le.text))
		v.add_child(le)
		le.grab_focus.call_deferred()
	else:
		var tl := W.label(Chats.display_title(e), 16, T.TEXT, v)
		tl.autowrap_mode = TextServer.AUTOWRAP_OFF
		tl.clip_text = true
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sub := W.label("%s · %s" % [U.get_u(int(e.assistant)).name, ctx.ago(float(e.updated))], 12, T.DIM, v)
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.pressed.connect(func(): open(e.id))
	for d in [[("pin_on" if e.pinned else "pin"), "Épingler", func(): _pin(e)], ["edit", "Renommer", func():
				renaming = e.id
				_render()], ["export", "Exporter en Markdown", func(): _export(e.id)], ["trash", "Supprimer", func(): _delete(e.id)]]:
		var b := W.IconBtn.new(d[0], 32)
		b.tooltip_text = d[1]
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(d[2])
		h.add_child(b)
	return row


func open(id: String) -> void:
	ctx.pending_chat = id
	router.back()


func _rename(id: String, t: String) -> void:
	if renaming != id:
		return
	renaming = ""
	var nt := t.strip_edges()
	if nt != "":
		ctx.chats.patch(id, {"title": nt, "titled": true})
	_render()


func _pin(e: Dictionary) -> void:
	ctx.chats.patch(e.id, {"pinned": not e.pinned})
	_render()


func _export(id: String) -> void:
	var p := ctx.chats.export_md(ctx.chats.load_chat(id))
	ctx.notify("Exporté : " + p.get_file() if p != "" else "Export impossible", "ok" if p != "" else "error")


func _delete(id: String) -> void:
	var c := ctx.chats.delete(id)
	var cp = router.tabs.get("chat")
	if cp != null and is_instance_valid(cp):
		cp.forget(id)
	_render()
	if not c.is_empty():
		ctx.notify("Conversation supprimée", "info", "Annuler", func():
			ctx.chats.save(c)
			if is_inside_tree():
				_render())
