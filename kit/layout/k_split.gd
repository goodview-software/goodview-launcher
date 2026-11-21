extends Container
## 2 colonnes (principale + latérale) à partir de lg (1024 px), 1 colonne en dessous. Deux enfants.
const Tokens := preload("res://kit/tokens.gd")
var side_width := 340
var gap := Tokens.S6
var wide_at := 880  # largeur propre minimale pour 2 colonnes (= lg une fois les marges du KContainer retirées)
var side_first := false
var _last_h := -1.0

func _kids() -> Array:
	var l: Array = []
	for c in get_children():
		if c is Control and c.visible:
			l.append(c)
	return l

func _plan(w: float) -> Dictionary:
	var k := _kids()
	var wide := w >= wide_at
	return {"wide": wide, "k": k}

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var p := _plan(size.x)
		var k: Array = p.k
		if k.size() == 0:
			return
		if p.wide and k.size() > 1:
			var main_c: Control = k[1] if side_first else k[0]
			var side_c: Control = k[0] if side_first else k[1]
			var mw := size.x - side_width - gap
			var h := maxf(main_c.get_combined_minimum_size().y, side_c.get_combined_minimum_size().y)
			var hh := maxf(h, 0.0)
			if side_first:
				fit_child_in_rect(side_c, Rect2(0, 0, side_width, hh))
				fit_child_in_rect(main_c, Rect2(side_width + gap, 0, mw, hh))
			else:
				fit_child_in_rect(main_c, Rect2(0, 0, mw, hh))
				fit_child_in_rect(side_c, Rect2(mw + gap, 0, side_width, hh))
			_set_h(hh)
		else:
			var y := 0.0
			for c in k:
				var h2: float = (c as Control).get_combined_minimum_size().y
				fit_child_in_rect(c, Rect2(0, y, size.x, h2))
				y += h2 + gap
			_set_h(y - gap)

func _set_h(h: float) -> void:
	if absf(h - _last_h) > 0.5:
		_last_h = h
		update_minimum_size()

func _get_minimum_size() -> Vector2:
	return Vector2(0, maxf(_last_h, 0.0))
