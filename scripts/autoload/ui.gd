extends Node
## Thème visuel global et fabriques de widgets (style néon / dessin illustré).

const C_BG := Color("#0d0b1e")
const C_PANEL := Color("#1b1640")
const C_PANEL_2 := Color("#251e55")
const C_BORDER := Color("#5ff7ff")
const C_ACCENT := Color("#ff5fd2")
const C_GOLD := Color("#ffd166")
const C_TEXT := Color("#f4f1ff")
const C_MUTED := Color("#a59fd0")
const C_GOOD := Color("#06ffa5")
const C_BAD := Color("#ff4d6d")

var theme: Theme
var font: Font
var font_bold: Font
var _overlay: CanvasLayer
var _toasts: VBoxContainer
var _fps: Label
var _fade: ColorRect


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_theme()
	get_tree().root.theme = theme
	_build_overlay()
	call_deferred("_ensure_bar")
	_setup_cursors()


func _process(_d: float) -> void:
	_fps.visible = Settings.show_fps
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()


func _build_theme() -> void:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray(["Fredoka One", "Fredoka", "Bahnschrift", "Segoe UI", "Arial Rounded MT Bold", "Arial"])
	sf.font_weight = 600
	sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font = sf
	var sfb := SystemFont.new()
	sfb.font_names = PackedStringArray(["Fredoka One", "Bahnschrift", "Segoe UI Black", "Arial Black", "Arial"])
	sfb.font_weight = 800
	font_bold = sfb

	theme = Theme.new()
	theme.default_font = font
	theme.default_font_size = 22

	var btn_n := _box(C_PANEL_2, C_BORDER.darkened(0.35), 3, 14)
	var btn_h := _box(C_PANEL_2.lightened(0.12), C_BORDER, 3, 14)
	btn_h.shadow_color = Color(C_BORDER, 0.35)
	btn_h.shadow_size = 8
	var btn_p := _box(C_ACCENT.darkened(0.3), C_ACCENT, 3, 14)
	var btn_d := _box(Color("#1a1830"), Color("#3a3560"), 3, 14)
	var btn_f := _box(Color(0, 0, 0, 0), C_GOLD, 3, 14)
	btn_f.draw_center = false
	for t in ["Button", "OptionButton", "MenuButton"]:
		theme.set_stylebox("normal", t, btn_n)
		theme.set_stylebox("hover", t, btn_h)
		theme.set_stylebox("pressed", t, btn_p)
		theme.set_stylebox("disabled", t, btn_d)
		theme.set_stylebox("focus", t, btn_f)
		theme.set_color("font_color", t, C_TEXT)
		theme.set_color("font_hover_color", t, Color.WHITE)
		theme.set_color("font_pressed_color", t, Color.WHITE)
		theme.set_color("font_disabled_color", t, Color("#6d6893"))
		theme.set_color("font_outline_color", t, Color(0, 0, 0, 0.8))
		theme.set_constant("outline_size", t, 4)
		theme.set_font("font", t, font_bold)

	var clear := StyleBoxEmpty.new()
	for st in ["normal", "pressed", "hover", "hover_pressed", "disabled", "focus"]:
		theme.set_stylebox(st, "CheckBox", clear)
	theme.set_color("font_color", "CheckBox", C_TEXT)
	theme.set_color("font_pressed_color", "CheckBox", C_GOLD)
	theme.set_color("font_hover_color", "CheckBox", Color.WHITE)
	theme.set_color("font_hover_pressed_color", "CheckBox", C_GOLD)

	var panel := _box(Color(C_PANEL, 0.94), C_BORDER.darkened(0.2), 3, 18)
	panel.shadow_color = Color(0, 0, 0, 0.5)
	panel.shadow_size = 10
	panel.set_content_margin_all(18)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)
	var tip := _box(Color("#120f2b"), C_GOLD, 2, 10)
	tip.set_content_margin_all(10)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", C_TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 18)

	theme.set_color("font_color", "Label", C_TEXT)
	theme.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.85))
	theme.set_constant("outline_size", "Label", 4)
	theme.set_color("default_color", "RichTextLabel", C_TEXT)
	theme.set_color("font_outline_color", "RichTextLabel", Color(0, 0, 0, 0.85))
	theme.set_constant("outline_size", "RichTextLabel", 3)
	theme.set_font("bold_font", "RichTextLabel", font_bold)

	var le := _box(Color("#100d26"), C_BORDER.darkened(0.4), 2, 10)
	le.set_content_margin_all(10)
	theme.set_stylebox("normal", "LineEdit", le)
	theme.set_stylebox("focus", "LineEdit", _box(Color("#100d26"), C_BORDER, 2, 10))
	theme.set_color("font_color", "LineEdit", C_TEXT)

	var pb_bg := _box(Color("#0b0920"), Color("#000000"), 2, 8)
	var pb_fg := _box(C_GOOD, Color(0, 0, 0, 0), 0, 8)
	theme.set_stylebox("background", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fg)
	theme.set_color("font_color", "ProgressBar", C_TEXT)

	var sl := _box(Color("#0b0920"), C_BORDER.darkened(0.5), 2, 6)
	sl.content_margin_top = 6
	sl.content_margin_bottom = 6
	theme.set_stylebox("slider", "HSlider", sl)
	var sla := _box(C_BORDER.darkened(0.2), Color(0, 0, 0, 0), 0, 6)
	theme.set_stylebox("grabber_area", "HSlider", sla)
	theme.set_stylebox("grabber_area_highlight", "HSlider", _box(C_BORDER, Color(0, 0, 0, 0), 0, 6))
	theme.set_icon("grabber", "HSlider", _circle_tex(22, C_TEXT))
	theme.set_icon("grabber_highlight", "HSlider", _circle_tex(24, C_GOLD))

	var sc_bg := _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 0, 6)
	theme.set_stylebox("scroll", "VScrollBar", sc_bg)
	theme.set_stylebox("grabber", "VScrollBar", _box(C_BORDER.darkened(0.3), Color(0, 0, 0, 0), 0, 6))
	theme.set_stylebox("grabber_highlight", "VScrollBar", _box(C_BORDER, Color(0, 0, 0, 0), 0, 6))
	theme.set_stylebox("scroll", "HScrollBar", sc_bg)
	theme.set_stylebox("grabber", "HScrollBar", _box(C_BORDER.darkened(0.3), Color(0, 0, 0, 0), 0, 6))

	var pm := _box(Color("#151133"), C_BORDER, 2, 8)
	pm.set_content_margin_all(6)
	theme.set_stylebox("panel", "PopupMenu", pm)
	theme.set_stylebox("hover", "PopupMenu", _box(C_PANEL_2.lightened(0.15), Color(0, 0, 0, 0), 0, 6))
	theme.set_color("font_color", "PopupMenu", C_TEXT)

	var tab_sel := _box(C_PANEL_2.lightened(0.1), C_BORDER, 3, 12)
	var tab_un := _box(Color("#151133"), C_BORDER.darkened(0.5), 2, 12)
	theme.set_stylebox("tab_selected", "TabContainer", tab_sel)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_un)
	theme.set_stylebox("tab_hovered", "TabContainer", tab_sel)
	theme.set_stylebox("panel", "TabContainer", panel)
	theme.set_font("font", "TabContainer", font_bold)


func _box(bg: Color, border: Color, bw: int, radius: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	s.anti_aliasing = true
	return s


func _circle_tex(size: int, color: Color) -> Texture2D:
	var img = Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) / 2.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d < size / 2.0 - 1:
				img.set_pixel(x, y, color if d < size / 2.0 - 4 else Color.BLACK)
	return ImageTexture.create_from_image(img)


func box(bg: Color, border: Color = Color(0, 0, 0, 0), bw := 2, radius := 12) -> StyleBoxFlat:
	return _box(bg, border, bw, radius)


# ------------------------------------------------------------------ superposition globale
func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(_fade)
	_toasts = VBoxContainer.new()
	place(_toasts, Control.PRESET_CENTER_TOP, Vector2(-300, 90))
	_toasts.custom_minimum_size = Vector2(600, 0)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 8)
	_overlay.add_child(_toasts)
	_fps = Label.new()
	_fps.position = Vector2(10, 6)
	_fps.add_theme_font_size_override("font_size", 16)
	_overlay.add_child(_fps)


func toast(text: String, color: Color = C_BORDER, duration := 2.6) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(Color(C_PANEL, 0.95), color, 3, 14))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l = label(text, 22, Color.WHITE)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	_toasts.add_child(p)
	p.modulate.a = 0
	var tw = p.create_tween()
	tw.tween_property(p, "modulate:a", 1.0, 0.2)
	tw.tween_interval(duration)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)


func flash(color := Color(1, 1, 1, 0.5), time := 0.25) -> void:
	_fade.color = color
	var tw = _fade.create_tween()
	tw.tween_property(_fade, "color:a", 0.0, time)


# ------------------------------------------------------------------ fabriques
func button(text: String, cb: Callable = Callable(), min_w := 0, font_size := 24) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_size_override("font_size", font_size)
	if min_w > 0:
		b.custom_minimum_size = Vector2(min_w, 0)
	if cb.is_valid():
		b.pressed.connect(cb)
	wire_sfx(b)
	return b


func wire_sfx(b: BaseButton) -> void:
	b.mouse_entered.connect(func(): if not b.disabled: Audio.play("survol", -10, 0.05))
	b.pressed.connect(func(): Audio.play("clic", -4, 0.04))


func label(text: String, size := 22, color: Color = C_TEXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = align
	return l


func title(text: String, size := 54, color: Color = C_BORDER) -> Label:
	var l := label(text, size, color, HORIZONTAL_ALIGNMENT_CENTER)
	l.add_theme_font_override("font", font_bold)
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color("#120a2e"))
	return l


func rich(bbcode: String, size := 20) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bbcode
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	return r


func panel(margin := 18, bg: Color = Color(C_PANEL, 0.94), border: Color = C_BORDER.darkened(0.2)) -> PanelContainer:
	var p := PanelContainer.new()
	var s := _box(bg, border, 3, 18)
	s.set_content_margin_all(margin)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 8
	p.add_theme_stylebox_override("panel", s)
	return p


func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


func icon(path: String, size := 64) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Db.tex(path)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(size, size)
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return t


func spacer(h := 0, w := 0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, h)
	if h == 0 and w == 0:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return c


## Fond illustré plein écran assombri + couche de contenu centrée.
func screen_base(root: Control, bg_path := "res://assets/backgrounds/titre.png", dim := 0.55) -> void:
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var t = Db.tex(bg_path)
	if t:
		var tr := TextureRect.new()
		tr.texture = t
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		root.add_child(tr)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.08, dim)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)


func margin(node: Control, m := 40) -> MarginContainer:
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		mc.add_theme_constant_override("margin_" + side, m)
	mc.add_child(node)
	return mc


func color_of_cosmetic(id: String) -> Color:
	if id == "":
		return Color.WHITE
	var c: Dictionary = Db.battlepass.colors.get(id, {})
	if c.is_empty():
		return Color.WHITE
	if c.color == "rainbow":
		return Color.from_hsv(fmod(Time.get_ticks_msec() / 2000.0, 1.0), 0.45, 1.0)
	var col := Color(c.color)
	col.a = c.get("alpha", 1.0)
	return col.lerp(Color.WHITE, 0.25)


## Ancre un contrôle selon un préréglage puis le décale (croît vers la droite et le bas).
func place(c: Control, preset: int, off: Vector2) -> void:
	c.set_anchors_preset(preset)
	c.offset_left = off.x
	c.offset_top = off.y
	c.offset_right = off.x
	c.offset_bottom = off.y


# ------------------------------------------------------------------ social et retours (partout)
const SocialPanel := preload("res://scripts/ui/social_panel.gd")
var _social_layer: CanvasLayer
var _social: Control


## Ouvre le panneau social : "amis" ou "messages".
func open_social(tab := "amis") -> void:
	if DisplayServer.get_name() == "headless":
		return
	if tab == "retour":
		open_feedback()
		return
	if _social_layer == null:
		_social_layer = CanvasLayer.new()
		_social_layer.layer = 90
		add_child(_social_layer)
	if is_instance_valid(_social):
		_social.queue_free()
	_social = SocialPanel.new()
	_social.start_tab = tab
	_social_layer.add_child(_social)
	push_modal(_social)


func social_open() -> bool:
	return is_instance_valid(_social)


const FeedbackPanel := preload("res://scripts/ui/feedback_panel.gd")
var _feedback: Control
var _guide: Control


## Guide du jeu (règles, dégâts, armes, objets…) avec recherche. Raccourci : F3.
func open_guide() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _social_layer == null:
		_social_layer = CanvasLayer.new()
		_social_layer.layer = 90
		add_child(_social_layer)
	if is_instance_valid(_guide) and not _guide.is_queued_for_deletion():
		_guide.queue_free()
		return
	_guide = load("res://scripts/ui/guide_panel.gd").new()
	_social_layer.add_child(_guide)
	push_modal(_guide)


## Fenêtre « Bugs & suggestions » (liste publique, recherche, signalement) — séparée du panneau social.
func open_feedback() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _social_layer == null:
		_social_layer = CanvasLayer.new()
		_social_layer.layer = 90
		add_child(_social_layer)
	if is_instance_valid(_feedback):
		_feedback.queue_free()
	_feedback = FeedbackPanel.new()
	_social_layer.add_child(_feedback)
	push_modal(_feedback)


const ProfilePanel := preload("res://scripts/ui/profile_panel.gd")


## Fenêtre « Mon profil » (pseudo, héros, statistiques, personnalisation). tab : 0 = profil, 1 = personnalisation.
func open_profile(tab := 0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _social_layer == null:
		_social_layer = CanvasLayer.new()
		_social_layer.layer = 90
		add_child(_social_layer)
	var pp := ProfilePanel.new()
	pp.start_tab = tab
	_social_layer.add_child(pp)
	push_modal(pp)


func feedback_open() -> bool:
	return is_instance_valid(_feedback) and not _feedback.is_queued_for_deletion()


func _input(event: InputEvent) -> void:
	_pad_focus(event)
	if _is_escape(event):
		get_viewport().set_input_as_handled()
		if not close_top_modal():
			open_menu()
		return
	if event.is_action_pressed("ui_cancel") and close_top_modal():   # bouton B de la manette
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			get_viewport().set_input_as_handled()
			open_feedback()
		elif event.keycode == KEY_F2:
			get_viewport().set_input_as_handled()
			open_social("amis")
		elif event.keycode == KEY_F3:
			get_viewport().set_input_as_handled()
			open_guide()


## Informations techniques jointes aux rapports de bug.
func tech_context() -> Dictionary:
	var ctx := {
		"version": ProjectSettings.get_setting("application/config/version"),
		"ecran": Game.current_screen,
		"os": OS.get_name() + " " + OS.get_version(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"fps": Engine.get_frames_per_second(),
		"langue": OS.get_locale(),
		"personnage": Profile.data.get("character", ""),
		"niveau_compte": Profile.data.get("level", 1),
		"en_ligne": Net.is_online(),
	}
	var w = get_tree().current_scene
	if w and w.name == "World":
		ctx["mode"] = w.mode
		ctx["mission"] = w.mission.get("id", "")
		ctx["vague"] = w.wave
		ctx["etat"] = w.state
	return ctx


# ------------------------------------------------------------------ barre d'accès rapide (menus)
var _bar: HBoxContainer
var _bar_social: Button


func _ensure_bar() -> void:
	if _bar or DisplayServer.get_name() == "headless":
		return
	var layer := CanvasLayer.new()
	layer.layer = 80
	add_child(layer)
	var holder := Control.new()
	holder.theme = theme
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(holder)
	_bar = hbox(8)
	place(_bar, Control.PRESET_TOP_LEFT, Vector2(16, 12))
	holder.add_child(_bar)
	_bar_social = button("Social", func(): open_social("amis"), 0, 18)
	_bar_social.tooltip_text = "Amis et messages (F2)"
	_bar.add_child(_bar_social)
	var fb := button("Signaler", func(): open_feedback(), 0, 18)
	fb.tooltip_text = "Signaler un bug ou proposer une suggestion (F1)"
	_bar.add_child(fb)
	var st := button("⚙ Paramètres", open_settings, 0, 18)
	_bar.add_child(st)
	_bar.add_child(button("⏻ Quitter le jeu", confirm_quit, 0, 18))
	Game.screen_changed.connect(_on_screen)
	Backend.social_updated.connect(func(_i): _update_bar())


func _on_screen(screen: String) -> void:
	close_all_modals()
	set_game_cursor(false)
	if _bar:
		_bar.visible = not screen in ["world", "update"]
		_update_bar()


func _update_bar() -> void:
	if _bar_social:
		var n := Backend.unread_total()
		_bar_social.text = "Social" + (" (%d)" % n if n > 0 else "")


func open_settings() -> void:
	if _social_layer == null:
		_social_layer = CanvasLayer.new()
		_social_layer.layer = 90
		add_child(_social_layer)
	var s = load("res://scripts/ui/settings_menu.gd").new()
	s.overlay = true
	s.process_mode = Node.PROCESS_MODE_ALWAYS
	_social_layer.add_child(s)
	push_modal(s, s._close)


## Demande confirmation puis quitte le jeu.
func confirm_quit() -> void:
	confirm("Quitter Cybervor ?", "Le Noyau en profitera pour lancer sa mise à jour. Vous êtes sûr ?", "Quitter", func():
		Settings.save_settings()
		Profile.save()
		get_tree().quit(), "Rester")


## Fenêtre de confirmation modale (Échap = annuler). Renvoie la fenêtre.
func confirm(title_text: String, text: String, ok_text: String, on_ok: Callable, cancel_text := "Annuler", on_cancel := Callable()) -> Control:
	if _social_layer == null:
		_social_layer = CanvasLayer.new()
		_social_layer.layer = 90
		add_child(_social_layer)
	var root := Control.new()
	root.theme = theme
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	var p := panel(28)
	place(p, Control.PRESET_CENTER, Vector2(-330, -140))
	p.custom_minimum_size = Vector2(660, 0)
	root.add_child(p)
	var v := vbox(16)
	p.add_child(v)
	v.add_child(title(title_text, 40))
	var l := label(text, 20, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(600, 0)
	v.add_child(l)
	var h := hbox(16)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(h)
	var cancel := func():
		root.queue_free()
		if on_cancel.is_valid():
			on_cancel.call()
	var stay := button(cancel_text, cancel, 220, 22)
	h.add_child(stay)
	h.add_child(button(ok_text, func():
		root.queue_free()
		on_ok.call(), 220, 22))
	_social_layer.add_child(root)
	push_modal(root, cancel)
	stay.call_deferred("grab_focus")
	return root


# ------------------------------------------------------------------ modales et touche Échap
## Échap ferme la modale ouverte la plus récente ; s'il n'y en a aucune, il ouvre le menu
## (menu pause en jeu, menu rapide ailleurs). Toute fenêtre modale s'enregistre avec push_modal().
const GameMenu := preload("res://scripts/ui/game_menu.gd")
var _modals: Array = []   # [{node, close}]


func push_modal(node: Node, close := Callable()) -> void:
	_modals.append({"node": node, "close": close})
	node.tree_exiting.connect(func(): _modals = _modals.filter(func(m): return m.node != node), CONNECT_ONE_SHOT)


func modal_open() -> bool:
	_modals = _modals.filter(func(m): return is_instance_valid(m.node) and not m.node.is_queued_for_deletion())
	return not _modals.is_empty()


func close_all_modals() -> void:
	for m in _modals:
		if is_instance_valid(m.node) and m.node.get_parent() and m.node.get_parent().get_parent() == self:
			m.node.queue_free()   # seulement les fenêtres globales (Ui) ; celles d'un écran partent avec lui
	_modals.clear()


func close_top_modal() -> bool:
	if not modal_open():
		return false
	var m: Dictionary = _modals.pop_back()
	if m.close.is_valid():
		m.close.call()
	else:
		m.node.queue_free()
	Audio.play("clic")
	return true


func _is_escape(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE
	return event.is_action_pressed("pause")   # bouton Start de la manette


func open_menu() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var w = get_tree().current_scene
	if Game.current_screen == "world" and w and w.has_method("open_pause_menu"):
		w.open_pause_menu()
		return
	if _social_layer == null:
		_social_layer = CanvasLayer.new()
		_social_layer.layer = 90
		add_child(_social_layer)
	var gm := GameMenu.new()
	_social_layer.add_child(gm)
	push_modal(gm)


# ------------------------------------------------------------------ curseurs de souris néon
## Flèche dans les menus, main sur tout ce qui est cliquable, barre dans les champs de texte,
## viseur pendant les vagues (assets/ui/curseurs, dessinés par tools/make_cursors.py).
const CURSOR_DIR := "res://assets/ui/curseurs/"
var _game_cursor := false


func _setup_cursors() -> void:
	if DisplayServer.get_name() == "headless":
		return
	Input.set_custom_mouse_cursor(load(CURSOR_DIR + "fleche.png"), Input.CURSOR_ARROW, Vector2(3, 3))
	Input.set_custom_mouse_cursor(load(CURSOR_DIR + "main.png"), Input.CURSOR_POINTING_HAND, Vector2(15, 3))
	Input.set_custom_mouse_cursor(load(CURSOR_DIR + "texte.png"), Input.CURSOR_IBEAM, Vector2(24, 24))
	# tous les boutons (et onglets, listes déroulantes…) affichent la main au survol
	get_tree().node_added.connect(func(n: Node):
		if n is BaseButton or n is TabBar or n is Slider:
			n.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND)


## Viseur pendant les vagues, flèche le reste du temps (boutique, menus, pause, fenêtres ouvertes).
var _want_game_cursor := false


func set_game_cursor(on: bool) -> void:
	_want_game_cursor = on
	_apply_cursor()


func _apply_cursor() -> void:
	var on := _want_game_cursor and not get_tree().paused and _modals.is_empty()
	if on == _game_cursor or DisplayServer.get_name() == "headless":
		return
	_game_cursor = on
	if on:
		Input.set_custom_mouse_cursor(load(CURSOR_DIR + "viseur.png"), Input.CURSOR_ARROW, Vector2(24, 24))
	else:
		Input.set_custom_mouse_cursor(load(CURSOR_DIR + "fleche.png"), Input.CURSOR_ARROW, Vector2(3, 3))


func _physics_process(_d: float) -> void:
	if _want_game_cursor or _game_cursor:
		_apply_cursor()


# ------------------------------------------------------------------ manette : navigation dans les menus
## Si l'on touche la manette alors qu'aucun élément n'a le focus, le premier bouton de la fenêtre
## active (modale la plus récente, sinon l'écran) le prend : tous les menus restent jouables à la manette.
func _pad_focus(event: InputEvent) -> void:
	var pad_nav: bool = (event is InputEventJoypadButton and event.pressed) \
		or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5 and event.axis <= JOY_AXIS_LEFT_Y)
	if not pad_nav or get_viewport().gui_get_focus_owner() != null:
		return
	if Game.current_screen == "world" and not get_tree().paused and _modals.is_empty():
		var w = get_tree().current_scene
		if w == null or w.get("state") == "wave":
			return   # en pleine vague, la manette sert à jouer
	var root: Node = null
	if modal_open():
		root = _modals.back().node
	else:
		root = get_tree().current_scene
	if root == null:
		return
	for b in root.find_children("*", "BaseButton", true, false):
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			get_viewport().set_input_as_handled()
			return
