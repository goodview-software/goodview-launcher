extends RefCounted
## Modèle de scène du plan : liste ordonnée d'éléments (l'ordre = z-order), sélection, historique global
## (annuler/rétablir), sérialisation v2 (clé "elements") et migration de l'ancien format (zones/cadres/fils/formes).

const Geom := preload("res://ui/draw/geom.gd")
const HIST_MAX := 120
## Une zone garde dans l'historique seulement sa géométrie : le contenu du chat n'est jamais annulé.
const ZONE_HIST := ["id", "type", "x", "y", "w", "h", "angle", "locked", "group", "opacity"]
const TYPES := ["rectangle", "diamond", "ellipse", "arrow", "line", "freedraw", "text", "image", "frame", "zone", "msg"]
const STYLE_KEYS := ["stroke", "bg", "fillStyle", "strokeWidth", "strokeStyle", "roughness", "opacity", "roundness"]
const DEFAULT_STYLE := {"stroke": "e8ecf1", "bg": "transparent", "fillStyle": "hachure", "strokeWidth": 2.0, "strokeStyle": "plein",
		"roughness": 1, "opacity": 100, "roundness": "round", "fontSize": 20, "arrowType": "sharp", "startHead": "none", "endHead": "arrow"}

signal changed
signal reset
signal zone_added(el)
signal zone_removed(id)
signal msg_removed(id)
signal order_changed

var els: Array = []
var by_id := {}
var sel := {}
var rev := 0
var cache := {}
var grave := {}
var search_q := ""  # recherche en cours (les nœuds msg qui ne correspondent pas sont estompés)
var focus_key: Array = []  # cache de la mise en évidence du chemin (chat.gd)
var focus_val := {}
var style := DEFAULT_STYLE.duplicate()
var on_clone: Callable = Callable()  # (ancien id, nouvel id, élément) : copie des fichiers liés (image d'une zone)
var _struct := 0
var _zones: Array = []
var _arrows: Array = []
var _msgs: Array = []
var _kids := {}
var _list_struct := -1
var _hist: Array = []
var _hi := -1
var _dirty := {}


func uid(prefix := "e") -> String:
	var id := "%s%d%04d" % [prefix, Time.get_ticks_msec(), randi() % 10000]
	while by_id.has(id):
		id += "x"
	return id


func get_el(id: String) -> Dictionary:
	return by_id.get(id, {})


func make(type: String, x: float, y: float, st := {}) -> Dictionary:
	var el := {"id": uid("e"), "type": type, "x": x, "y": y, "w": 0.0, "h": 0.0, "angle": 0.0, "locked": false, "group": ""}
	var src: Dictionary = style if st.is_empty() else st
	for k in STYLE_KEYS:
		el[k] = src.get(k, DEFAULT_STYLE[k])
	match type:
		"text":
			el.text = ""
			el.fontSize = src.get("fontSize", 20)
			el.fillStyle = "aucun"
		"arrow", "line", "freedraw":
			el.points = [[0.0, 0.0]]
			el.fillStyle = "aucun"
			if type != "freedraw":
				el.start = ""
				el.end = ""
				el.label = ""
				el.fontSize = 16
			if type == "arrow":
				el.arrowType = src.get("arrowType", "sharp")
				el.startHead = src.get("startHead", "none")
				el.endHead = src.get("endHead", "arrow")
				el.link = ""
		"rectangle", "diamond", "ellipse":
			el.label = ""
			el.fontSize = src.get("fontSize", 20)
		"frame":
			el.name = "Cadre"
			el.stroke = "4de1b4"
		"image":
			el.file = ""
	return el


# ------------------------------------------------------------------ structure

func zones() -> Array:
	_lists()
	return _zones


func arrows() -> Array:
	_lists()
	return _arrows


## Nœuds de chat (type « msg »), dans l'ordre des calques.
func msgs() -> Array:
	_lists()
	return _msgs


## Enfants (nœuds msg) d'un nœud de chat.
func kids(id: String) -> Array:
	_lists()
	return _kids.get(id, [])


func struct_id() -> int:
	return _struct


func _lists() -> void:
	if _list_struct == _struct:
		return
	_list_struct = _struct
	_zones = []
	_arrows = []
	_msgs = []
	_kids = {}
	for el in els:
		if el.type == "zone":
			_zones.append(el)
		elif el.type == "arrow":
			_arrows.append(el)
		elif el.type == "msg":
			_msgs.append(el)
			var pid := str(el.get("parent", ""))
			if pid != "":
				if not _kids.has(pid):
					_kids[pid] = []
				_kids[pid].append(el)


func _struct_changed() -> void:
	_struct += 1
	rev += 1


func add(el: Dictionary, at := -1) -> Dictionary:
	if at < 0 or at >= els.size():
		els.append(el)
	else:
		els.insert(at, el)
	by_id[el.id] = el
	_dirty[el.id] = true
	_struct_changed()
	if el.type == "zone":
		zone_added.emit(el)
	changed.emit()
	return el


## Retire des éléments (les flèches de fil liées à une zone supprimée partent avec ; les autres se détachent).
func remove(ids: Array) -> void:
	var gone := {}
	for id in ids:
		if by_id.has(id):
			gone[id] = true
	for a in arrows():
		if gone.has(a.id):
			continue
		var cut := false
		if gone.has(str(a.get("start", ""))):
			a.start = ""
			cut = true
		if gone.has(str(a.get("end", ""))):
			a.end = ""
			cut = true
		if cut:
			if str(a.get("link", "")) != "":
				gone[a.id] = true
			else:
				mark(a)
	var keep: Array = []
	for el in els:
		if gone.has(el.id):
			if el.type == "zone":
				grave[el.id] = el
				zone_removed.emit(el.id)
			by_id.erase(el.id)
			cache.erase(el.id)
			sel.erase(el.id)
			_dirty[el.id] = true
		else:
			keep.append(el)
	els = keep
	_struct_changed()
	changed.emit()


func mark(el_or_id) -> void:
	var id: String = str(el_or_id.id) if el_or_id is Dictionary else str(el_or_id)
	cache.erase(id)
	_dirty[id] = true
	rev += 1


func touch() -> void:
	rev += 1
	changed.emit()


func mark_links() -> void:
	for a in arrows():
		if str(a.get("link", "")) != "":
			cache.erase(a.id)


## Recalcule les flèches liées à l'un des éléments donnés (ou toutes si vide).
func refresh_arrows(ids := {}) -> void:
	for a in arrows():
		if ids.is_empty() or ids.has(a.id) or ids.has(str(a.get("start", ""))) or ids.has(str(a.get("end", ""))):
			if str(a.get("start", "")) != "" or str(a.get("end", "")) != "" or ids.is_empty():
				Geom.refresh_arrow(self, a)
				mark(a)


func bounds_of(ids) -> Rect2:
	var r := Rect2()
	var first := true
	for id in ids:
		var el: Dictionary = by_id.get(id, {})
		if el.is_empty():
			continue
		var b := Geom.aabb(el)
		r = b if first else r.merge(b)
		first = false
	return r


func selected() -> Array:
	var out: Array = []
	for el in els:
		if sel.has(el.id):
			out.append(el)
	return out


func select(ids: Array, add_to := false) -> void:
	if not add_to:
		sel = {}
	for id in expand_groups(ids):
		if by_id.has(id):
			sel[id] = true
	changed.emit()


func clear_sel() -> void:
	if not sel.is_empty():
		sel = {}
		changed.emit()


func expand_groups(ids) -> Array:
	var groups := {}
	for id in ids:
		var el: Dictionary = by_id.get(id, {})
		if not el.is_empty() and str(el.get("group", "")) != "":
			groups[el.group] = true
	var out: Array = []
	for id in ids:
		out.append(id)
	if not groups.is_empty():
		for el in els:
			if groups.has(str(el.get("group", ""))) and not out.has(el.id):
				out.append(el.id)
	return out


func group(ids: Array) -> void:
	if ids.size() < 2:
		return
	var g := uid("g")
	for id in ids:
		if by_id.has(id):
			by_id[id].group = g
			mark(id)
	changed.emit()


func ungroup(ids: Array) -> void:
	for id in ids:
		if by_id.has(id) and str(by_id[id].get("group", "")) != "":
			by_id[id].group = ""
			mark(id)
	changed.emit()


## Ordre des calques : "front", "back", "forward", "backward".
func reorder(ids: Array, mode: String) -> void:
	var s := {}
	for id in ids:
		s[id] = true
	var n := els.size()
	if mode == "front" or mode == "back":
		var a: Array = []
		var b: Array = []
		for el in els:
			(a if s.has(el.id) else b).append(el)
		els = (b + a) if mode == "front" else (a + b)
	elif mode == "forward":
		for i in range(n - 2, -1, -1):
			if s.has(els[i].id) and not s.has(els[i + 1].id):
				var t = els[i]
				els[i] = els[i + 1]
				els[i + 1] = t
	elif mode == "backward":
		for i in range(1, n):
			if s.has(els[i].id) and not s.has(els[i - 1].id):
				var t2 = els[i]
				els[i] = els[i - 1]
				els[i - 1] = t2
	for id in ids:
		_dirty[id] = true
	for el in els:
		_dirty[el.id] = true  # l'ordre fait partie de l'état
	_struct_changed()
	order_changed.emit()
	changed.emit()


## Copie profonde d'éléments (nouveaux ids, groupes et liaisons recréés dans la copie). Retourne les nouveaux éléments.
func clone(src: Array, off := Vector2.ZERO) -> Array:
	var map := {}
	var gmap := {}
	var out: Array = []
	for el in src:
		var c: Dictionary = (el as Dictionary).duplicate(true)
		c.id = uid("z" if el.type == "zone" else ("m" if el.type == "msg" else "e"))
		map[el.id] = c.id
		c.x = float(c.x) + off.x
		c.y = float(c.y) + off.y
		var g := str(c.get("group", ""))
		if g != "":
			if not gmap.has(g):
				gmap[g] = uid("g")
			c.group = gmap[g]
		out.append(c)
	for c in out:
		if c.type == "msg":
			c.parent = str(map.get(str(c.get("parent", "")), ""))  # copie d'une sous-branche : le parent copié suit, sinon nouvelle racine
			c.done = true
			c.model = ""
		if c.type == "arrow" or c.type == "line":
			for k in ["start", "end"]:
				var t := str(c.get(k, ""))
				c[k] = str(map[t]) if map.has(t) else ""
			if str(c.get("link", "")) != "" and (str(c.start) == "" or str(c.end) == ""):
				c.link = ""
	for i in out.size():
		if on_clone.is_valid():
			on_clone.call(str(src[i].id), str(out[i].id), out[i])
	return out


# ------------------------------------------------------------------ historique

func _ser(el: Dictionary) -> String:
	if el.type == "zone":
		var d := {}
		for k in ZONE_HIST:
			d[k] = el.get(k)
		return JSON.stringify(d)
	return JSON.stringify(el)


## Enregistre l'état courant comme étape d'historique (rien si rien n'a changé).
func commit() -> bool:
	var prev: Dictionary = _hist[_hi] if _hi >= 0 else {"o": PackedStringArray(), "d": {}}
	var o := PackedStringArray()
	var d := {}
	var diff: bool = false
	for el in els:
		var id: String = el.id
		o.append(id)
		if prev.d.has(id) and not _dirty.has(id):
			d[id] = prev.d[id]
		else:
			d[id] = _ser(el)
			if not prev.d.has(id) or prev.d[id] != d[id]:
				diff = true
	_dirty.clear()
	if not diff and o == prev.o and _hi >= 0:  # (sans état de base, un plan vide ne pourrait jamais être « annulé » jusqu'au vide)
		return false
	if _hi < _hist.size() - 1:
		_hist.resize(_hi + 1)
	_hist.append({"o": o, "d": d})
	_hi += 1
	if _hist.size() > HIST_MAX:
		_hist.pop_front()
		_hi -= 1
	return true


func reset_history() -> void:
	_hist = []
	_hi = -1
	_dirty.clear()
	commit()


func can_undo() -> bool:
	return _hi > 0


func can_redo() -> bool:
	return _hi < _hist.size() - 1


func undo() -> bool:
	if not can_undo():
		return false
	_hi -= 1
	_restore(_hist[_hi])
	return true


func redo() -> bool:
	if not can_redo():
		return false
	_hi += 1
	_restore(_hist[_hi])
	return true


func _restore(st: Dictionary) -> void:
	var keep := {}
	var new_els: Array = []
	for id in st.o:
		var src = JSON.parse_string(str(st.d[id]))
		if not (src is Dictionary):
			continue
		var live: Dictionary = by_id.get(id, {})
		var revive := false
		if live.is_empty():
			live = grave.get(id, {})
			revive = not live.is_empty()
			if live.is_empty():
				live = src
				revive = true
			else:
				grave.erase(id)
		if live is Dictionary and not live.is_empty() and live != src:
			if live.type != "zone":
				live.clear()
			for k in src:
				live[k] = src[k]
		keep[id] = true
		new_els.append(live)
		if revive and live.type == "zone":
			by_id[id] = live
			zone_added.emit(live)
	for el in els:
		if not keep.has(el.id) and el.type == "zone":
			grave[el.id] = el
			zone_removed.emit(el.id)
		elif not keep.has(el.id) and el.type == "msg":
			msg_removed.emit(el.id)
	els = new_els
	by_id = {}
	for el in els:
		by_id[el.id] = el
	var ns := {}
	for id in sel:
		if by_id.has(id):
			ns[id] = true
	sel = ns
	cache.clear()
	_dirty.clear()
	_struct_changed()
	refresh_arrows()
	order_changed.emit()
	reset.emit()
	changed.emit()


# ------------------------------------------------------------------ sauvegarde / migration

func to_dict() -> Dictionary:
	return {"v": 2, "elements": els}


func clear() -> void:
	for el in els:
		if el.type == "zone":
			zone_removed.emit(el.id)
		elif el.type == "msg":
			msg_removed.emit(el.id)
	els = []
	by_id = {}
	sel = {}
	cache.clear()
	grave.clear()
	_struct_changed()
	reset.emit()


## Charge un plan (v2 : "elements" ; sinon ancien format migré). color_of : Callable(ai:int) -> String hex.
func load_dict(v: Dictionary, color_of := Callable()) -> void:
	clear()
	var list: Array = []
	if v.has("elements"):
		list = v.get("elements", [])
	else:
		list = migrate(v, color_of)
	for el in list:
		if el is Dictionary and el.has("id") and TYPES.has(str(el.get("type", ""))):
			_sanitize(el)
			els.append(el)
			by_id[el.id] = el
	_struct_changed()
	refresh_arrows()
	for el in els:
		if el.type == "zone":
			zone_added.emit(el)
	reset_history()
	reset.emit()
	changed.emit()


func _sanitize(el: Dictionary) -> void:
	for k in ["x", "y", "w", "h", "angle"]:
		el[k] = float(el.get(k, 0.0))
	el["locked"] = bool(el.get("locked", false))
	el["group"] = str(el.get("group", ""))
	el["opacity"] = clampf(float(el.get("opacity", 100)), 0.0, 100.0)
	if el.type != "zone" and el.type != "msg":
		for k in STYLE_KEYS:
			if not el.has(k):
				el[k] = DEFAULT_STYLE[k]
	if el.type == "msg":
		el["role"] = "assistant" if str(el.get("role", "user")) == "assistant" else "user"
		el["text"] = str(el.get("text", ""))
		el["parent"] = str(el.get("parent", ""))
		el["img"] = str(el.get("img", ""))
		el["ai"] = int(el.get("ai", 0))
		el["model"] = str(el.get("model", ""))
		el["kind"] = "note"
		el["w"] = maxf(float(el.w), 220.0)
		el["h"] = maxf(float(el.h), 68.0)
		el["angle"] = 0.0
		if not bool(el.get("done", true)):  # réponse interrompue (fermeture pendant l'écriture)
			el["done"] = true
			if str(el.text).strip_edges() == "":
				el["text"] = "(réponse interrompue)"
		el["done"] = true
	if el.type == "text":
		el["text"] = str(el.get("text", ""))
		el["fontSize"] = float(el.get("fontSize", 20))
		if float(el.w) < 1.0:
			Geom.fit_text(el)
	if el.type in Geom.LINEAR and not (el.get("points", null) is Array):
		el["points"] = [[0.0, 0.0], [float(el.w), float(el.h)]]
	if el.type == "arrow" or el.type == "line":
		el["start"] = str(el.get("start", ""))
		el["end"] = str(el.get("end", ""))
		el["label"] = str(el.get("label", ""))
	if el.type == "arrow":
		el["link"] = str(el.get("link", ""))
		el["arrowType"] = str(el.get("arrowType", "sharp"))
		el["startHead"] = str(el.get("startHead", "none"))
		el["endHead"] = str(el.get("endHead", "arrow"))


func migrate(v: Dictionary, color_of := Callable()) -> Array:
	var out: Array = []
	for f in v.get("frames", []):
		var c := str(f.get("color", "4de1b4"))
		out.append({"id": str(f.id), "type": "frame", "x": f.x, "y": f.y, "w": f.w, "h": f.h, "name": str(f.get("title", "Cadre")), "stroke": c})
	var wfont := [16, 22, 32]
	var ww := [1.0, 2.0, 4.0]
	var late: Array = []
	for s in v.get("shapes", []):
		if not (s is Dictionary):
			continue
		var t := str(s.get("type", ""))
		var el := {"id": str(s.get("id", uid("e"))), "x": float(s.get("x", 0)), "y": float(s.get("y", 0)), "w": float(s.get("w", 0)), "h": float(s.get("h", 0)),
				"stroke": str(s.get("color", "f4f4f5")), "strokeWidth": ww[clampi(int(s.get("width", 1)), 0, 2)]}
		match t:
			"rect", "ellipse", "diamond":
				el.type = "rectangle" if t == "rect" else t
				if bool(s.get("fill", false)):
					el.bg = el.stroke
					el.fillStyle = "plein"
				if float(el.w) < 0.0:
					el.x = float(el.x) + float(el.w)
					el.w = -float(el.w)
				if float(el.h) < 0.0:
					el.y = float(el.y) + float(el.h)
					el.h = -float(el.h)
				out.append(el)
			"text":
				el.type = "text"
				el.text = str(s.get("text", ""))
				el.fontSize = wfont[clampi(int(s.get("width", 1)), 0, 2)]
				Geom.fit_text(el)
				out.append(el)
			"pencil":
				el.type = "freedraw"
				var pts: Array = []
				var wp := PackedVector2Array()
				for p in s.get("pts", []):
					wp.append(Vector2(float(el.x) + float(p[0]), float(el.y) + float(p[1])))
				if wp.size() >= 1:
					Geom.set_world_pts(el, wp)
					out.append(el)
			"arrow", "line":
				el.type = t
				el.start = str(s.get("from", ""))
				el.end = str(s.get("to", ""))
				var a := Vector2(float(el.x), float(el.y))
				el.points = [[0.0, 0.0], [float(el.w), float(el.h)]]
				Geom.set_world_pts(el, PackedVector2Array([a, a + Vector2(float(s.get("w", 0)), float(s.get("h", 0)))]))
				late.append(el)
	for d in v.get("zones", []):
		d["type"] = "zone"
		out.append(d)
	for l in v.get("links", []):
		var za := str(l.get("from", ""))
		var zb := str(l.get("to", ""))
		var col := "4de1b4"
		for d in v.get("zones", []):
			if str(d.id) == za and color_of.is_valid():
				col = str(color_of.call(int(d.get("ai", 0))))
		out.append({"id": uid("l"), "type": "arrow", "x": 0.0, "y": 0.0, "w": 0.0, "h": 0.0, "stroke": col, "strokeWidth": 3.0, "arrowType": "round",
				"start": za, "end": zb, "link": str(l.get("type", "feed")), "endHead": "triangle", "points": [[0.0, 0.0], [10.0, 10.0]]})
	out.append_array(late)
	return out
