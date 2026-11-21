extends RefCounted
## Couche de compatibilité : les pages du launcher gardent leur API (W.label, W.Btn, W.IconBtn...) mais tout est rendu par le kit
## (tokens, Inter, Lucide, composants animés). Les nouveaux écrans utilisent directement kit/k.gd.

const T := preload("res://ui/theme.gd")
const Ico := preload("res://ui/icons.gd")
const U := preload("res://ui/universe.gd")
const K := preload("res://kit/k.gd")
const Tk := preload("res://kit/tokens.gd")
const KS := preload("res://kit/ui/ks.gd")
const KIcons := preload("res://kit/icon.gd")

## Tailles héritées -> tokens de texte.
static func snap(px: int) -> int:
	if px <= 12:
		return Tk.FS_XS
	if px <= 14:
		return Tk.FS_SM
	if px <= 16:
		return Tk.FS_BASE
	if px <= 18:
		return Tk.FS_LG
	if px <= 20:
		return Tk.FS_XL
	if px <= 26:
		return Tk.FS_2XL
	return Tk.FS_3XL


# ------------------------------------------------------------------ Helpers de construction

static func label(text: String, size: int, color: Color, parent: Control = null) -> Label:
	var s := snap(size)
	var l := KS.label(null, text, s, color, 600 if s >= Tk.FS_XL else 400, not (parent is HBoxContainer))
	if parent != null:
		parent.add_child(l)
	return l


## Pastille de texte colorée.
static func pill(parent: Control, text: String, color: Color) -> Label:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", KS.box(Color(color, 0.14), Tk.R_FULL, Tk.S3, Tk.S1))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(p)
	var l := KS.label(p, text, Tk.FS_XS, Tk.ensure_contrast(color, Tk.over(Color(color, 0.14), Tk.surface1), 4.5), 600, false)
	return l


## Carte ; renvoie le conteneur vertical intérieur.
static func card(parent: Control, pad := 16) -> VBoxContainer:
	var p: PanelContainer = K.Card.new()
	p.pad = Tk.S4 if pad >= 16 else Tk.S3
	parent.add_child(p)
	var v := KS.vbox(p, Tk.S3)
	return v


static func spacer(parent: Control) -> Control:
	return KS.spacer(parent)


## Ligne de réglage : titre + sous-titre à gauche ; renvoie la ligne pour y ajouter le contrôle à droite.
static func setting_row(parent: Control, title: String, sub := "") -> HBoxContainer:
	var h := KS.hbox(parent, Tk.S3)
	var v := KS.vbox(h, Tk.S1)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	KS.label(v, title, Tk.FS_BASE, null, 500, true)
	if sub != "":
		KS.label(v, sub, Tk.FS_SM, Tk.text_muted, 400, true)
	return h


static func hsep(parent: Control) -> void:
	parent.add_child(K.Divider.new())


# ------------------------------------------------------------------ Base interactive (mascottes, avatars)

class Tap extends Control:
	signal pressed
	var hot := false
	var down := false
	var enabled := true:
		set(v):
			enabled = v
			modulate.a = 1.0 if v else 0.4
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if v else Control.CURSOR_ARROW

	func _init() -> void:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _set_hot(true))
		mouse_exited.connect(func(): _set_hot(false))

	func _set_hot(v: bool) -> void:
		hot = v
		if not v:
			down = false
		queue_redraw()

	func _gui_input(e: InputEvent) -> void:
		if not enabled or not (e is InputEventMouseButton) or e.button_index != MOUSE_BUTTON_LEFT:
			return
		if e.pressed:
			down = true
		else:
			var inside := Rect2(Vector2.ZERO, size).has_point(e.position)
			var was := down
			down = false
			if was and inside:
				pressed.emit()
		queue_redraw()
		accept_event()




# ------------------------------------------------------------------ Boutons (rendus par le kit)

const ICON_MAP := {"back": "chevron-left", "refresh": "refresh-cw", "close": "x", "copy": "copy", "edit": "pencil", "gear": "settings",
		"github": "github", "link": "external-link", "paperclip": "paperclip", "phone": "smartphone", "desktop": "monitor", "plus": "plus",
		"star": "star", "star_on": "star", "trash": "trash-2", "download": "download", "send": "arrow-up", "check": "check",
		"search": "search", "info": "info", "alert": "info", "menu": "menu", "chat": "message-circle", "user": "user", "apps": "layout-grid",
		"play": "play", "folder": "folder-open", "image": "image", "export": "upload", "wifi_off": "wifi-off", "pin": "pin", "chevron": "chevron-right"}

class IconBtn extends K.Press:
	var kind := "refresh":
		set(v):
			kind = v
			queue_redraw()
	var col: Variant = null:
		set(v):
			col = v
			queue_redraw()
	var spin := false:
		set(v):
			spin = v
			angle = 0.0
			set_process(v)
			queue_redraw()
	var badge := false:
		set(v):
			badge = v
			queue_redraw()
	var angle := 0.0
	var px := 44
	var enabled := true:
		set(v):
			enabled = v
			disabled = not v

	func _init(k := "refresh", p := 44) -> void:
		super()
		kind = k
		px = p
		custom_minimum_size = Vector2(maxi(p, Tk.TOUCH), maxi(p, Tk.TOUCH))
		set_process(false)

	func _process(d: float) -> void:
		angle = fposmod(angle + d * 6.0, TAU)
		queue_redraw()

	func k_colors() -> Array:
		return [[_fg(), Tk.surface1]]

	func _fg() -> Color:
		if col != null:
			return col
		if kind == "star_on":
			return Tk.warn
		return Tk.text_muted.lerp(Tk.text, hover)

	func _draw() -> void:
		var c := size * 0.5
		var d := minf(float(px), minf(size.x, size.y))
		draw_style_box(KS.box(Color(1, 1, 1, 0.07 * hover + 0.06 * down), Tk.R_FULL), Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)))
		draw_ring(Rect2(c - Vector2(d, d) * 0.5, Vector2(d, d)), d * 0.5)
		var a := 0.42 if disabled else 1.0
		var fg := Color(_fg(), a)
		var name: String = ICON_MAP.get(kind, "")
		if name != "" and KIcons.has(name):
			var isz := 24 if d >= 40 else 20
			if spin:
				draw_set_transform(c, angle, Vector2.ONE)
				c = Vector2.ZERO
			var t := KIcons.texture(name, isz)
			if t != null:
				draw_texture_rect(t, Rect2(c - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, fg)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			Ico.draw_kind(self, kind, c, d / 44.0 * 0.62, fg)
		if badge:
			draw_circle(size * 0.5 + Vector2(d, -d) * 0.28, 5.0, Tk.surface0)
			draw_circle(size * 0.5 + Vector2(d, -d) * 0.28, 3.5, Tk.warn)


## Bouton texte : "primary", "soft" (neutre), "danger", "ghost".
class Btn extends K.Btn:
	func _init(txt := "", k := "soft") -> void:
		super()
		text = txt
		set_kind(k)
		size_name = "lg"

	func set_kind(k: String) -> void:
		kind = {"soft": "secondary"}.get(k, k)


class Toggle extends K.Toggle:
	func _init() -> void:
		super()


## Sélecteur segmenté : options [[id, libellé], ...].
class Seg extends K.Segmented:
	var cur := "":
		get:
			return value
	func _init(o: Array, c: String) -> void:
		super()
		options = o
		value = c
		_pos = float(_idx())
	func select(id: String) -> void:
		set_value(id, false)


class Orb extends Control:
	const SHEET := preload("res://mascot/goody.png")
	const XSHEET := preload("res://mascot/goody_extra.png")  # talk / think / call / listen (ligne = variante*4 + anim)
	const ANIMS := {"idle": [0, 4], "happy": [1, 4], "wait": [2, 4], "off": [3, 4], "sad": [4, 4]}
	const XANIMS := {"talk": 0, "think": 1, "call": 2, "listen": 3}
	const FPS := {"idle": 3.0, "happy": 6.0, "wait": 3.0, "off": 1.5, "sad": 2.0, "talk": 7.0, "think": 3.0, "call": 5.0, "listen": 2.5}
	var color := Color("5b6573")
	var variant := 0
	var level := 0.0
	var pulse := 0.0
	var t := 0.0
	var speed_mult := 1.0  # lié au rythme des jetons
	var anim := "off":
		set(v):
			if v != anim:
				anim = v
				t = 0.0

	func _init() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _target() -> Color:
		match anim:
			"wait", "think":
				return T.WARN
			"off":
				return Color("5b6573")
			"sad":
				return T.BAD
		return T.OK

	func _process(d: float) -> void:
		pulse = fposmod(pulse + d, TAU)
		var u: Dictionary = U.get_u(variant)
		t += d * FPS[anim] * (1.0 + level * 1.5) * speed_mult * float(u.anim.speed)
		color = color.lerp(_target(), 0.1)
		queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) * 0.26
		for i in 4:
			var rr := r + 8.0 * (i + 1) + level * 14.0 + sin(pulse + i) * 2.0
			draw_circle(c, rr, Color(color, 0.11 - i * 0.025))
		draw_circle(c, r, Color(color, 0.16))
		var sc := maxi(1, int(size.y * 0.72 / 32.0))
		var px := 32 * sc
		var u: Dictionary = U.get_u(variant)
		var bounce := 0.0
		if anim == "talk":
			bounce = -absf(sin(t * 1.3)) * 2.0 * float(u.anim.bounce) * sc
		var pos := (c - Vector2(px, px) / 2.0 + Vector2(0, bounce)).round()
		if XANIMS.has(anim):
			draw_texture_rect_region(XSHEET, Rect2(pos, Vector2(px, px)), Rect2((int(t) % 4) * 32, (variant * 4 + XANIMS[anim]) * 32, 32, 32))
		else:
			var row: int = ANIMS[anim][0] + variant * 5
			var n: int = ANIMS[anim][1]
			draw_texture_rect_region(SHEET, Rect2(pos, Vector2(px, px)), Rect2((int(t) % n) * 32, row * 32, 32, 32))


## Icône d'app : carré arrondi + image (ou lettre colorée), halo et pastille d'état optionnels.
class AppIcon extends Control:
	var tex: Texture2D
	var letter := "?"
	var tint := Color("4de1b4")
	var halo := false
	var badge := Color(0, 0, 0, 0)
	var pulse := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(d: float) -> void:
		if halo:
			pulse = fposmod(pulse + d, TAU)
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var s := minf(size.x, size.y)
		var side := s * (0.62 if halo else 1.0)
		if halo:
			for i in 4:
				draw_circle(c, side * 0.5 + 10.0 * (i + 1) + sin(pulse + i) * 2.0, Color(tint, 0.10 - i * 0.022))
		var r := Rect2(c - Vector2(side, side) / 2.0, Vector2(side, side))
		Ico.box(self, r, side * 0.24, Color("232a34") if tex != null else tint.darkened(0.35))
		if tex != null:
			var m := side * 0.12
			draw_texture_rect(tex, Rect2(r.position + Vector2(m, m), r.size - Vector2(m, m) * 2.0), false)
		else:
			var fs := int(side * 0.5)
			draw_string(ThemeDB.fallback_font, Vector2(r.position.x, c.y + fs * 0.36), letter,
					HORIZONTAL_ALIGNMENT_CENTER, side, fs, Color.WHITE)
		if badge.a > 0.0:
			var bp := r.position + Vector2(side, 0) - Vector2(side * 0.08, -side * 0.08)
			draw_circle(bp, side * 0.14, T.BG)
			draw_circle(bp, side * 0.1, badge)


## Avatar rond d'une variante de mascotte ; cliquable (sélecteur) ou décoratif.
class Avatar extends Tap:
	const SHEET := preload("res://mascot/variants.png")
	const BODIES := [Color("4de1b4"), Color("ff8fb1"), Color("6aa8ff"), Color("ffa24d"), Color("b58bff"),
			Color("ffd84d"), Color("ff6b6b"), Color("c9d1da")]  # = accents de ui/universe.gd
	var variant := 0:
		set(v):
			variant = v
			queue_redraw()
	var selected := false:
		set(v):
			selected = v
			queue_redraw()
	var badge := false:
		set(v):
			badge = v
			queue_redraw()

	func _init(clickable := false) -> void:
		super()
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if not clickable:
			mouse_filter = Control.MOUSE_FILTER_IGNORE
			mouse_default_cursor_shape = Control.CURSOR_ARROW

	func _draw() -> void:
		var c := size / 2.0
		var r := minf(size.x, size.y) / 2.0
		if down:
			r *= 0.95
		draw_circle(c, r, (BODIES[variant] as Color).darkened(0.62 - (0.1 if hot else 0.0)))
		var s := maxi(int(r * 2.0 * 0.86 / 32.0) * 32, 32)
		draw_texture_rect_region(SHEET, Rect2((c - Vector2(s, s) / 2.0).round(), Vector2(s, s)), Rect2(variant * 32, 0, 32, 32))
		draw_arc(c, r - 1.5, 0.0, TAU, 48, T.OK if selected else Color(1, 1, 1, 0.12), 3.0 if selected else 1.5, true)
		if badge:
			draw_circle(c + Vector2(r * 0.72, -r * 0.72), r * 0.27, T.BAD)


## Ligne cliquable (accueil) : fond au survol, plus marqué à la pression.
class Row extends PanelContainer:
	signal pressed
	var sb := T.style(Color(0, 0, 0, 0), 16, 12)
	var hot := false
	var down := false

	func _init() -> void:
		add_theme_stylebox_override("panel", sb)
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func(): _paint(true, down))
		mouse_exited.connect(func(): _paint(false, false))

	func _paint(h: bool, d: bool) -> void:
		hot = h
		down = d
		sb.bg_color = Color(1, 1, 1, 0.09 if d else (0.05 if h else 0.0))

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				_paint(hot, true)
			else:
				var fire := down and Rect2(Vector2.ZERO, size).has_point(e.position)
				_paint(hot, false)
				if fire:
					pressed.emit()
			accept_event()



# ------------------------------------------------------------------ États (chargement / vide / hors-ligne / erreur)

## Mascotte + titre + message + bouton d'action optionnel.
class StateView extends VBoxContainer:
	signal action
	var orb: Orb

	func _init(anim: String, variant: int, title: String, msg := "", btn := "", orb_h := 150) -> void:
		add_theme_constant_override("separation", Tk.S3)
		alignment = BoxContainer.ALIGNMENT_CENTER
		orb = Orb.new()
		orb.anim = anim
		orb.variant = variant
		orb.custom_minimum_size = Vector2(0, orb_h)
		add_child(orb)
		var t := KS.label(self, title, Tk.FS_XL, null, 600, true)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if msg != "":
			var m := KS.label(self, msg, Tk.FS_SM, Tk.text_muted, 400, true)
			m.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if btn != "":
			var b := Btn.new(btn, "soft")
			b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			b.pressed.connect(func(): action.emit())
			add_child(b)


## Lignes fantômes qui pulsent pendant le chargement.
class Skeleton extends VBoxContainer:
	func _init(n := 4) -> void:
		add_theme_constant_override("separation", Tk.S3)
		for i in n:
			var c: PanelContainer = K.Card.new()
			add_child(c)
			var h := KS.hbox(c, Tk.S3)
			var ic: Control = K.Skeleton.new()
			ic.radius = Tk.R_MD
			ic.custom_minimum_size = Vector2(48, 48)
			h.add_child(ic)
			var v := KS.vbox(h, Tk.S2)
			v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var a: Control = K.Skeleton.new()
			a.custom_minimum_size = Vector2(0, 14)
			v.add_child(a)
			var b: Control = K.Skeleton.new()
			b.custom_minimum_size = Vector2(0, 10)
			v.add_child(b)


## Notification discrète : pile de toasts du kit (garde l'ancienne API show_msg).
class Toast extends K.Toast:
	func show_msg(text: String, kind := "info", action := "", cb := Callable()) -> void:
		push(text, {"ok": "success", "error": "danger"}.get(kind, "info"), action, cb, 5.0 if action != "" else 3.0)
