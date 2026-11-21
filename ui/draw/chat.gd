extends RefCounted
## Chat en nœuds : une conversation est un ARBRE d'éléments « msg » (parent -> enfants). Ce fichier ne contient que de la
## logique pure (sans Node) : chemin racine->nœud, historique envoyé au modèle, placement et rangement des nœuds,
## mise en page du texte (Markdown léger), mise en évidence du chemin, export Markdown. Le dessin est dans render.gd.

const Geom := preload("res://ui/draw/geom.gd")
const MD := preload("res://ui/markdown.gd")
const W := 380.0
const MIN_W := 220.0
const HGAP := 48.0
const VGAP := 56.0
const FS := 15
const HEAD := 28.0
const PAD := 10.0
const MIN_PX := 6.0  # en dessous, le texte du nœud n'est plus tracé tel quel mais résumé en petits caractères lisibles
const SUM_PX := 8
const HISTORY_MAX := 14
const NO_OBST := ["arrow", "line", "freedraw", "frame"]

static var _bold: FontVariation


static func bold_font() -> Font:
	if _bold == null or _bold.base_font != Geom.f():
		_bold = FontVariation.new()
		_bold.base_font = Geom.f()
		_bold.variation_embolden = 0.6
	return _bold


# ------------------------------------------------------------------ arbre

static func is_msg(el) -> bool:
	return el is Dictionary and str(el.get("type", "")) == "msg"


static func parent_of(sc, el: Dictionary) -> Dictionary:
	var p: Dictionary = sc.get_el(str(el.get("parent", "")))
	return p if is_msg(p) else {}


## Chemin racine -> nœud (le nœud inclus), à l'abri des cycles.
static func path(sc, id: String) -> Array:
	var out: Array = []
	var cur: Dictionary = sc.get_el(id)
	var guard := 0
	while is_msg(cur) and guard < 500:
		out.push_front(cur)
		cur = parent_of(sc, cur)
		guard += 1
	return out


## Le nœud et toute sa sous-branche (ids).
static func branch(sc, id: String) -> Array:
	var out: Array = []
	var seen := {}
	var todo: Array = [id]
	while not todo.is_empty():
		var cur: String = todo.pop_back()
		if seen.has(cur) or not is_msg(sc.get_el(cur)):
			continue
		seen[cur] = true
		out.append(cur)
		for k in sc.kids(cur):
			todo.append(str(k.id))
	return out


## Ajoute à une liste d'ids les sous-branches des nœuds msg qu'elle contient.
static func with_branches(sc, ids: Array) -> Array:
	var seen := {}
	var out: Array = []
	for id in ids:
		var list: Array = branch(sc, str(id)) if is_msg(sc.get_el(str(id))) else [id]
		for x in list:
			if not seen.has(x):
				seen[x] = true
				out.append(x)
	return out


static func root_of(sc, id: String) -> Dictionary:
	var p := path(sc, id)
	return p[0] if not p.is_empty() else {}


static func roots(sc) -> Array:
	var out: Array = []
	for m in sc.msgs():
		if parent_of(sc, m).is_empty():
			out.append(m)
	out.sort_custom(func(a, b): return float(a.y) < float(b.y) if absf(float(a.y) - float(b.y)) > 30.0 else float(a.x) < float(b.x))
	return out


## Historique envoyé au modèle pour répondre à `upto_id` : le prompt système puis les messages du chemin racine -> nœud
## (les réponses d'un autre assistant sont présentées comme un message d'utilisateur étiqueté).
static func history(sc, upto_id: String, system: String, cur_ai: int, name_of := Callable(), max_n := HISTORY_MAX) -> Array:
	var chain: Array = path(sc, upto_id).filter(func(m): return str(m.get("text", "")).strip_edges() != "")
	if chain.size() > max_n:
		chain = chain.slice(chain.size() - max_n)
	var out: Array = [{"role": "system", "content": system}]
	for m in chain:
		if str(m.role) == "assistant" and int(m.get("ai", cur_ai)) != cur_ai:
			var nm := str(name_of.call(int(m.ai))) if name_of.is_valid() else "Assistant"
			out.append({"role": "user", "content": "[%s] %s" % [nm, str(m.text)]})
		else:
			out.append({"role": "user" if str(m.role) != "assistant" else "assistant", "content": str(m.text)})
	return out


static func make_msg(sc, role: String, text: String, parent_id: String, ai: int) -> Dictionary:
	return {"id": sc.uid("m"), "type": "msg", "x": 0.0, "y": 0.0, "w": W, "h": HEAD + 40.0, "angle": 0.0, "locked": false, "group": "", "opacity": 100.0,
			"role": role, "text": text, "ai": ai, "parent": parent_id, "model": "", "done": role != "assistant", "kind": "note"}


## Crée un nœud, le place (sous son parent, ou à droite de ses frères ; racine : `at`) et l'ajoute à la scène.
static func add_msg(sc, role: String, text: String, parent_id: String, ai: int, fork := false, at := Vector2(40, 40)) -> Dictionary:
	var par: Dictionary = sc.get_el(parent_id) if parent_id != "" else {}
	if not is_msg(par):
		par = {}
		parent_id = ""
	var el := make_msg(sc, role, text, parent_id, ai)
	layout(sc, el)
	var p := spot(sc, par, Vector2(float(el.w), float(el.h)), fork, at)
	el.x = p.x
	el.y = p.y
	sc.add(el)
	return el


static func subtree_rect(sc, el: Dictionary) -> Rect2:
	var r := Geom.rect(el)
	for id in branch(sc, str(el.id)):
		r = r.merge(Geom.rect(sc.get_el(str(id))))
	return r


## Position d'un nouveau nœud : sous son parent (premier enfant) ou à droite du sous-arbre de ses frères.
static func spot(sc, parent: Dictionary, size: Vector2, fork := false, at := Vector2(40, 40)) -> Vector2:
	var p := at
	if not parent.is_empty():
		var kids: Array = sc.kids(str(parent.id))
		p = Vector2(float(parent.x), float(parent.y) + float(parent.h) + VGAP)
		if not kids.is_empty():
			var right := -INF
			for k in kids:
				right = maxf(right, subtree_rect(sc, k).end.x)
			p.x = right + HGAP
			p.y = float(kids[0].y)
		elif fork:
			p.x = float(parent.x) + size.x + HGAP
	return free_spot(sc, p, size, str(parent.get("id", "")))


## Décale vers la droite jusqu'à ne plus recouvrir aucun élément (hors flèches, cadres, et `ignore`).
static func free_spot(sc, p: Vector2, size: Vector2, ignore := "") -> Vector2:
	for i in 80:
		var r := Rect2(p, size).grow(8.0)
		var hit := false
		for e in sc.els:
			if str(e.type) in NO_OBST or str(e.id) == ignore:
				continue
			var b := Geom.aabb(e)
			if r.intersects(b):
				p.x = b.end.x + HGAP
				hit = true
				break
		if not hit:
			break
	return p


## Repousse vers le bas les enfants d'un nœud qui a grandi (réponse reçue en streaming), avec toute leur sous-branche.
static func push_down(sc, el: Dictionary) -> void:
	var need := float(el.y) + float(el.h) + VGAP
	for k in sc.kids(str(el.id)):
		if float(k.y) < need - 0.5:
			var d := need - float(k.y)
			for id in branch(sc, str(k.id)):
				var m: Dictionary = sc.get_el(str(id))
				m.y = float(m.y) + d
				sc.mark(m)


## Range l'arbre qui part de root_id : enfants côte à côte sous leur parent, sans chevauchement. Retourne les ids déplacés.
static func tidy(sc, root_id: String) -> Array:
	var root: Dictionary = sc.get_el(root_id)
	if not is_msg(root):
		return []
	var moved: Array = []
	var widths := {}
	_sw(sc, root, widths, {})
	var left := float(root.x) + float(root.w) * 0.5 - float(widths[str(root.id)]) * 0.5
	_place(sc, root, left, float(root.y), widths, moved, {})
	return moved


static func _sw(sc, el: Dictionary, widths: Dictionary, seen: Dictionary) -> float:
	seen[str(el.id)] = true
	var kids: Array = sc.kids(str(el.id)).filter(func(k): return not seen.has(str(k.id)))
	var total := 0.0
	for k in kids:
		total += _sw(sc, k, widths, seen)
	total += HGAP * maxf(kids.size() - 1.0, 0.0)
	var w := maxf(float(el.w), total)
	widths[str(el.id)] = w
	return w


static func _place(sc, el: Dictionary, left: float, y: float, widths: Dictionary, moved: Array, seen: Dictionary) -> void:
	seen[str(el.id)] = true
	var sw: float = widths[str(el.id)]
	var nx := left + (sw - float(el.w)) * 0.5
	if absf(nx - float(el.x)) > 0.01 or absf(y - float(el.y)) > 0.01:
		el.x = nx
		el.y = y
		sc.mark(el)
		moved.append(el.id)
	var cx := left
	var kids: Array = sc.kids(str(el.id)).filter(func(k): return not seen.has(str(k.id)))
	var span := 0.0
	for k in kids:
		span += float(widths[str(k.id)]) + HGAP
	span -= HGAP
	if not kids.is_empty():
		cx = left + (sw - span) * 0.5
	for k in kids:
		_place(sc, k, cx, y + float(el.h) + VGAP, widths, moved, seen)
		cx += float(widths[str(k.id)]) + HGAP


# ------------------------------------------------------------------ mise en évidence du chemin

## {on, anc, keep, tree} pour la sélection : anc = chemin racine -> nœud, keep = anc + descendants, tree = tout l'arbre.
static func focus(sc) -> Dictionary:
	var key := [sc.struct_id(), sc.sel.keys()]
	if sc.focus_key == key:
		return sc.focus_val
	var out := {"on": false, "anc": {}, "keep": {}, "tree": {}}
	for el in sc.msgs():
		if sc.sel.has(el.id):
			var anc := {}
			for m in path(sc, str(el.id)):
				anc[str(m.id)] = true
			var keep: Dictionary = anc.duplicate()
			for id in branch(sc, str(el.id)):
				keep[id] = true
			var tree := {}
			for id in branch(sc, str(root_of(sc, str(el.id)).id)):
				tree[id] = true
			out = {"on": true, "anc": anc, "keep": keep, "tree": tree}
			break
	sc.focus_key = key
	sc.focus_val = out
	return out


static func matches(el: Dictionary, q: String) -> bool:
	return q in str(el.get("text", "")).to_lower()


# ------------------------------------------------------------------ mise en page du texte

static func _inline(s: String) -> String:
	s = s.replace("**", "").replace("__", "").replace("`", "")
	var r := RegEx.create_from_string("\\{\\{([^|{}]+)\\|[^{}]*\\}\\}")
	return r.sub(s, "$1", true)


## Texte brut aplati (aperçu en vue éloignée).
static func plain(text: String) -> String:
	var out: PackedStringArray = []
	for ln in text.split("\n"):
		var t := ln.strip_edges()
		if t.begins_with("```") or t == "":
			continue
		t = t.lstrip("#>").strip_edges()
		if t.begins_with("- ") or t.begins_with("* "):
			t = "• " + t.substr(2)
		out.append(_inline(t))
	return " ".join(out)


static func title_of(el: Dictionary) -> String:
	for ln in str(el.get("text", "")).split("\n"):
		var t := _inline(ln.strip_edges().lstrip("#>-* ").strip_edges())
		if t != "" and not t.begins_with("```"):
			return t.left(80)
	return ""


static func wrap_lines(t: String, width: float, fs: int, font: Font = null) -> Array:
	var f: Font = font if font != null else Geom.f()
	var out: Array = []
	var p := TextParagraph.new()
	p.add_string(t, f, fs)
	p.width = maxf(width, 20.0)
	for i in p.get_line_count():
		var r := p.get_line_range(i)
		out.append(t.substr(r.x, r.y - r.x).strip_edges(false, true))
	if out.is_empty():
		out.append(t)
	return out


## Mise en page (cache dans scene.cache, effacé par scene.mark) : lignes à tracer en coordonnées locales du nœud ;
## fixe aussi la hauteur du nœud (elle dépend du texte et de la largeur).
static func layout(sc, el: Dictionary) -> Dictionary:
	var c: Dictionary = sc.cache.get(el.id, {})
	if not c.is_empty() and c.get("sig", "") == "msg" and is_equal_approx(float(c.w), float(el.w)):
		return c
	c = _build(el)
	sc.cache[el.id] = c
	el.h = c.h
	return c


static func _build(el: Dictionary) -> Dictionary:
	var w := maxf(float(el.w), MIN_W)
	var inner := w - PAD * 2.0
	var f := Geom.f()
	var lines: Array = []  # {t, x, y, fs, k} k : 0 texte, 1 titre, 2 puce, 3 code, 4 citation
	var boxes: Array = []  # {r: Rect2, k} fond de bloc de code (0) ou barre de citation (1)
	var y := HEAD + 6.0
	var lh := f.get_height(FS) + 2.0
	var text := str(el.get("text", ""))
	for blk in MD.blocks(text):
		if blk.type == "code":
			var y0 := y
			y += 4.0
			for cl in str(blk.text).split("\n"):
				for part in wrap_lines(cl, inner - 12.0, FS - 1):
					lines.append({"t": part, "x": PAD + 6.0, "y": y, "fs": FS - 1, "k": 3})
					y += lh - 1.0
			boxes.append({"r": Rect2(PAD, y0, inner, y - y0 + 4.0), "k": 0})
			y += 8.0
			continue
		for raw in str(blk.text).split("\n"):
			var s: String = raw.strip_edges(false, true)
			var st := s.strip_edges()
			if st == "":
				y += lh * 0.45
				continue
			var kind := 0
			var x := PAD
			var width := inner
			var fs := FS
			var prefix := ""
			if st.begins_with("#"):
				kind = 1
				st = st.lstrip("#").strip_edges()
				fs = FS + 2
			elif st.begins_with("- ") or st.begins_with("* ") or st.begins_with("• "):
				kind = 2
				st = st.substr(2).strip_edges()
				prefix = "•"
				x = PAD + 16.0
				width = inner - 16.0
			elif RegEx.create_from_string("^\\d+[.)]\\s").search(st) != null:
				kind = 2
				var m := RegEx.create_from_string("^(\\d+[.)])\\s+").search(st)
				prefix = m.get_string(1)
				st = st.substr(m.get_end())
				x = PAD + 20.0
				width = inner - 20.0
			elif st.begins_with(">"):
				kind = 4
				st = st.lstrip(">").strip_edges()
				x = PAD + 10.0
				width = inner - 10.0
			var first := true
			var q0 := y
			for part in wrap_lines(_inline(st), width, fs, bold_font() if kind == 1 else null):
				if first and prefix != "":
					lines.append({"t": prefix, "x": PAD + 2.0, "y": y, "fs": fs, "k": 0})
				lines.append({"t": part, "x": x, "y": y, "fs": fs, "k": kind})
				first = false
				y += f.get_height(fs) + 2.0
			if kind == 4:
				boxes.append({"r": Rect2(PAD + 2.0, q0, 3.0, y - q0), "k": 1})
			if kind == 1:
				y += 2.0
	var h := maxf(y + PAD, HEAD + 40.0)
	var txt := plain(text)
	return {"sig": "msg", "w": float(el.w), "lines": lines, "boxes": boxes, "h": h, "plain": txt.left(500), "title": title_of(el)}


# ------------------------------------------------------------------ export

static func markdown(sc, name_of: Callable) -> PackedStringArray:
	var out: PackedStringArray = []
	var rs := roots(sc)
	if rs.is_empty():
		return out
	out.append("## Conversations")
	out.append("")
	var seen := {}
	for r in rs:
		_md(sc, r, 0, name_of, out, seen)
		out.append("")
	return out


static func _md(sc, el: Dictionary, depth: int, name_of: Callable, out: PackedStringArray, seen: Dictionary) -> void:
	if seen.has(str(el.id)):
		return
	seen[str(el.id)] = true
	var pad := "  ".repeat(depth)
	var who := "Toi" if str(el.role) == "user" else str(name_of.call(int(el.get("ai", 0))))
	var ls: PackedStringArray = str(el.get("text", "")).strip_edges().split("\n")
	out.append("%s- **%s** : %s" % [pad, who, ls[0] if not ls.is_empty() else ""])
	for i in range(1, ls.size()):
		out.append(pad + "  " + ls[i])
	for k in sc.kids(str(el.id)):
		_md(sc, k, depth + 1, name_of, out, seen)
