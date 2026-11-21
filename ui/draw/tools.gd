extends "res://ui/draw/core.gd"
## Outils du plan : actions (supprimer, copier/coller, dupliquer, ordre, groupes, styles), menu contextuel et raccourcis
## clavier calqués sur Excalidraw. Hérite du noyau d'interaction (core.gd).

# ------------------------------------------------------------------ actions

func delete_sel() -> void:
	var ids: Array = []
	for el in sc.selected():
		if not el.locked:
			ids.append(el.id)
	if ids.is_empty():
		return
	sc.remove(Chat.with_branches(sc, ids))  # supprimer un nœud de chat emporte toute sa sous-branche (un seul Ctrl+Z la rend)
	sc.commit()
	S.host.links_changed()
	S.sel_changed.emit()


func select_all() -> void:
	var ids: Array = []
	for el in sc.els:
		if not el.locked:
			ids.append(el.id)
	sc.select(ids)
	S.sel_changed.emit()


func _add_clones(arr: Array) -> void:
	var ids: Array = []
	for c in arr:
		sc.add(c)
		ids.append(c.id)
	sc.refresh_arrows(sc.sel)
	sc.sel = {}
	for id in ids:
		sc.sel[id] = true
	S.host.sync_zones(sc.sel)
	S.host.sync_order()
	S.host.links_changed()
	sc.commit()
	sc.touch()
	S.sel_changed.emit()


func duplicate_sel() -> void:
	var src = sc.selected()
	if src.is_empty():
		return
	_add_clones(sc.clone(src, Vector2(20, 20)))


func copy(cut := false) -> void:
	var src = sc.selected()
	if src.is_empty():
		return
	_clip = []
	for el in src:
		_clip.append(el.duplicate(true))
	if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		DisplayServer.clipboard_set(PREFIX + JSON.stringify(_clip))
	if cut:
		delete_sel()


func paste() -> void:
	var txt := DisplayServer.clipboard_get() if DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD) else ""
	var arr: Array = []
	if txt.begins_with(PREFIX):
		var v = JSON.parse_string(txt.substr(PREFIX.length()))
		if v is Array:
			arr = v
	elif txt == "" and not _clip.is_empty():
		arr = _clip
	var cp: Vector2 = S.get_local_mouse_position()
	var target: Vector2 = S.c2w(cp) if Rect2(Vector2.ZERO, S.size).has_point(cp) else S.c2w(S.size * 0.5)
	if arr.is_empty():
		if DisplayServer.has_method("clipboard_has_image") and DisplayServer.clipboard_has_image():
			S.host.add_image_from_image(DisplayServer.clipboard_get_image(), target)
		elif txt.strip_edges() != "":
			var n: Dictionary = sc.make("text", target.x, target.y)
			n.text = txt.strip_edges()
			Geom.fit_text(n)
			_add_clones([n])
		return
	var b := Rect2()
	var first := true
	for el in arr:
		var r := Geom.aabb(el)
		b = r if first else b.merge(r)
		first = false
	var cl: Array = sc.clone(arr, target - b.get_center())
	_add_clones(cl)


func nudge(d: Vector2) -> void:
	var els = sc.selected()
	if els.is_empty():
		return
	var moving := {}
	for el in els:
		if not el.locked:
			moving[el.id] = true
	for id in moving.keys():
		var a: Dictionary = sc.get_el(id)
		if a.type == "arrow" or a.type == "line":
			for k in ["start", "end"]:
				if str(a.get(k, "")) != "" and not moving.has(str(a[k])):
					a[k] = ""
	for id in moving:
		var el: Dictionary = sc.get_el(id)
		el.x = float(el.x) + d.x
		el.y = float(el.y) + d.y
		sc.mark(el)
	sc.refresh_arrows(moving)
	S.host.sync_zones(moving)
	sc.commit()
	sc.touch()


func order(mode_: String) -> void:
	var ids: Array = sc.sel.keys()
	if ids.is_empty():
		return
	sc.reorder(ids, mode_)
	S.host.sync_order()
	sc.commit()


func group_sel() -> void:
	sc.group(sc.sel.keys())
	sc.commit()


func ungroup_sel() -> void:
	sc.ungroup(sc.sel.keys())
	sc.commit()


func toggle_lock_sel() -> void:
	var els = sc.selected()
	if els.is_empty():
		return
	var v: bool = not bool(els[0].locked)
	for el in els:
		el.locked = v
		sc.mark(el)
	sc.commit()
	sc.touch()
	S.sel_changed.emit()


func undo() -> void:
	S.edit_commit()
	if sc.undo():
		_after_history()


func redo() -> void:
	S.edit_commit()
	if sc.redo():
		_after_history()


func _after_history() -> void:
	S.host.sync_zones({})
	S.host.sync_order()
	S.host.links_changed()
	S.sel_changed.emit()


# ------------------------------------------------------------------ styles

const FONT_KEYS := ["fontSize"]


func style_of(k: String):
	var els = sc.selected()
	if not els.is_empty() and els[0].has(k):
		return els[0][k]
	return sc.style.get(k)


func set_style(k: String, v, commit := true) -> void:
	sc.style[k] = v
	var changed := false
	for el in sc.selected():
		if el.type in ["zone"] and k != "opacity":
			continue
		if k in ["startHead", "endHead", "arrowType"] and el.type != "arrow":
			continue
		if k == "roundness" and not (el.type in ["rectangle", "image"]):
			continue
		el[k] = v
		if k == "fontSize" and el.type == "text":
			Geom.fit_text(el)
		sc.mark(el)
		changed = true
		if k == "arrowType":
			Geom.refresh_arrow(sc, el)
	if changed:
		if commit:
			sc.commit()
		sc.touch()
		S.host.sync_zones(sc.sel)


func copy_style() -> void:
	var els = sc.selected()
	if els.size() == 1:
		_style_clip = {}
		for k in sc.STYLE_KEYS:
			if els[0].has(k):
				_style_clip[k] = els[0][k]


func paste_style() -> void:
	if _style_clip.is_empty():
		return
	for el in sc.selected():
		if el.type == "zone":
			continue
		for k in _style_clip:
			el[k] = _style_clip[k]
		sc.mark(el)
	sc.commit()
	sc.touch()


# ------------------------------------------------------------------ menu contextuel

func _context(cp: Vector2) -> void:
	if mode != "" or S.pinching:
		return
	var wp: Vector2 = S.c2w(cp)
	var el := top_hit(wp, true)
	if not el.is_empty() and not sc.sel.has(el.id):
		sc.select([el.id])
		S.sel_changed.emit()
	elif el.is_empty():
		sc.clear_sel()
		S.sel_changed.emit()
	var lh := label_hit(wp)
	_menu_hit = str(lh.id) if not lh.is_empty() else ""
	if _menu == null:
		_menu = PopupMenu.new()
		_menu.id_pressed.connect(_menu_pick)
		S.add_child(_menu)
	_menu.clear()
	var has = not sc.sel.is_empty()
	_menu.add_item("Coller", 1)
	if has and sc.selected().size() == 1 and sc.selected()[0].type == "msg":
		_menu.add_item("Répondre à ce message", 16)
		_menu.add_item("Ranger la conversation", 17)
		_menu.add_separator()
	if has:
		_menu.add_item("Copier", 2)
		_menu.add_item("Couper", 3)
		_menu.add_item("Dupliquer", 4)
		_menu.add_separator()
		_menu.add_item("Premier plan", 5)
		_menu.add_item("Avancer", 6)
		_menu.add_item("Reculer", 7)
		_menu.add_item("Arrière-plan", 8)
		_menu.add_separator()
		_menu.add_item("Grouper", 9)
		_menu.add_item("Dégrouper", 10)
		_menu.add_item("Verrouiller / déverrouiller", 11)
		_menu.add_separator()
		_menu.add_item("Supprimer", 12)
	if _menu_hit != "":
		_menu.add_item("Supprimer ce fil", 13)
	_menu.add_separator()
	_menu.add_item("Tout sélectionner", 14)
	_menu.add_item("Grille", 15)
	_menu.popup(Rect2i(Vector2i(S.get_screen_position() + cp), Vector2i.ZERO))


func _menu_pick(i: int) -> void:
	match i:
		1: paste()
		2: copy()
		3: copy(true)
		4: duplicate_sel()
		5: order("front")
		6: order("forward")
		7: order("backward")
		8: order("back")
		9: group_sel()
		10: ungroup_sel()
		11: toggle_lock_sel()
		12: delete_sel()
		13:
			sc.remove([_menu_hit])
			sc.commit()
			S.host.links_changed()
		14: select_all()
		15: toggle_grid()
		16: S.host.chat_reply(str(sc.selected()[0].id) if sc.selected().size() == 1 else "")
		17: S.host.chat_tidy()


func toggle_grid() -> void:
	S.grid_on = not S.grid_on
	S.tool_changed.emit()
	S.redraw()


# ------------------------------------------------------------------ clavier

func key(e: InputEventKey) -> bool:
	if S.is_editing():
		return false
	var focus = S.get_viewport().gui_get_focus_owner()
	if focus != null and (focus is LineEdit or focus is TextEdit):
		return false
	if e.keycode == KEY_SPACE:
		_space = e.pressed
		update_cursor(S.get_local_mouse_position())
		return true
	if not e.pressed:
		return false
	var ctrl: bool = e.ctrl_pressed or e.meta_pressed
	var k: int = e.keycode
	if (k == KEY_ENTER or k == KEY_KP_ENTER) and (ctrl or e.shift_pressed) and mode == "":
		S.host.open_assist("graph")  # Ctrl+Entrée / Maj+Entrée : assistant d'édition du graphe
		return true
	var pk: int = e.physical_keycode
	if ctrl:
		match k:
			KEY_A:
				select_all()
			KEY_C:
				if e.alt_pressed:
					copy_style()
				else:
					copy()
			KEY_X:
				copy(true)
			KEY_V:
				if e.alt_pressed:
					paste_style()
				else:
					paste()
			KEY_D:
				duplicate_sel()
			KEY_G:
				if e.shift_pressed:
					ungroup_sel()
				else:
					group_sel()
			KEY_Z:
				if e.shift_pressed:
					redo()
				else:
					undo()
			KEY_Y:
				redo()
			KEY_BRACKETRIGHT:
				order("front" if e.shift_pressed else "forward")
			KEY_BRACKETLEFT:
				order("back" if e.shift_pressed else "backward")
			KEY_APOSTROPHE, KEY_QUOTEDBL:
				toggle_grid()
			KEY_L:
				if e.shift_pressed:
					toggle_lock_sel()
				else:
					return false
			KEY_E:
				if e.shift_pressed:
					S.host.export_png()
				else:
					return false
			KEY_0:
				S.zoom_to(1.0)
			KEY_EQUAL, KEY_PLUS:
				S.zoom_at(S.size * 0.5, 1.25)
			KEY_MINUS:
				S.zoom_at(S.size * 0.5, 0.8)
			_:
				return false
		return true
	if e.alt_pressed:
		return false
	if DIGITS.has(pk):
		if e.shift_pressed and pk == KEY_1:
			S.fit_all()
		elif e.shift_pressed and pk == KEY_2:
			S.fit_selection()
		elif not e.shift_pressed:
			set_tool(str(DIGITS[pk]))
		else:
			return false
		return true
	match k:
		KEY_ESCAPE:
			if mode == "poly":
				_finish_draw()
			elif mode != "":
				cancel()
			elif tool != "select":
				set_tool("select")
			else:
				sc.clear_sel()
				S.sel_changed.emit()
		KEY_ENTER, KEY_KP_ENTER:
			if mode == "poly":
				_finish_draw()
			else:
				S.host.open_assist("chat")  # Entrée = discuter en créant des nœuds (Ctrl/Maj+Entrée : éditer le graphe ; F2 : éditer le texte)
		KEY_F2:
			if true:
				var els = sc.selected()
				if els.size() == 1:
					match str(els[0].type):
						"text":
							S.edit_el(els[0], "text")
						"rectangle", "diamond", "ellipse":
							S.edit_el(els[0], "label")
						"arrow", "line":
							if str(els[0].get("link", "")) == "":
								S.edit_el(els[0], "label")
						"frame":
							S.edit_el(els[0], "name")
		KEY_DELETE, KEY_BACKSPACE:
			delete_sel()
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
			var st := 10.0 if e.shift_pressed else 1.0
			if S.grid_on:
				st = 20.0
			nudge(Vector2(-st if k == KEY_LEFT else (st if k == KEY_RIGHT else 0.0), -st if k == KEY_UP else (st if k == KEY_DOWN else 0.0)))
		KEY_Q:
			toggle_lock()
		_:
			if KEYS.has(k):
				set_tool(str(KEYS[k]))
			else:
				return false
	return true
