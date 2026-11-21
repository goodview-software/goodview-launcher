extends Container
## Grille adaptative : colonnes = floor(largeur / min_card_width), gouttières tokenisées, cartes de hauteur égale par ligne.
const Tokens := preload("res://kit/tokens.gd")
var min_card_width := 280: set = _smw
var gap := Tokens.S4
var max_columns := 6
var columns := 1
var _last_h := -1.0

func _smw(v: int) -> void:
	min_card_width = v
	queue_sort()

func cols_for(w: float) -> int:
	return clampi(int(floor((w + gap) / (min_card_width + gap))), 1, max_columns)

func _kids() -> Array:
	var l: Array = []
	for c in get_children():
		if c is Control and c.visible:
			l.append(c)
	return l

func _layout_h(w: float) -> float:
	var kids := _kids()
	if kids.is_empty():
		return 0.0
	var n := cols_for(w)
	var cw := (w - gap * (n - 1)) / n
	var y := 0.0
	var i := 0
	while i < kids.size():
		var rh := 0.0
		for j in range(i, mini(i + n, kids.size())):
			rh = maxf(rh, (kids[j] as Control).get_combined_minimum_size().y)
		y += rh + gap
		i += n
	return y - gap

func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		var kids := _kids()
		columns = cols_for(size.x)
		var cw := (size.x - gap * (columns - 1)) / columns
		var y := 0.0
		var i := 0
		while i < kids.size():
			var rh := 0.0
			for j in range(i, mini(i + columns, kids.size())):
				rh = maxf(rh, (kids[j] as Control).get_combined_minimum_size().y)
			for j in range(i, mini(i + columns, kids.size())):
				fit_child_in_rect(kids[j], Rect2((j - i) * (cw + gap), y, cw, rh))
			y += rh + gap
			i += columns
		var h := maxf(y - gap, 0.0)
		if absf(h - _last_h) > 0.5:
			_last_h = h
			update_minimum_size()

func _get_minimum_size() -> Vector2:
	var w := size.x if size.x > 0 else float(min_card_width)
	var mw := 0.0
	for c in _kids():
		mw = maxf(mw, 0.0)
	return Vector2(0, _layout_h(w))
