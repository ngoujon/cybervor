extends Control
## Boîte de dialogue à la manière d'un visual novel (portrait, nom, texte machine à écrire).
## Mode bloquant (clic / Espace pour avancer) ou automatique (bulles pendant le combat).

signal finished

var lines: Array = []
var hero_id := "patatron"
var hero_name := ""
var auto := false

var _idx := -1
var _shown := 0.0
var _portrait: TextureRect
var _name: Label
var _text: RichTextLabel
var _hint: Label
var _auto_timer := 0.0
var _blip_acc := 0.0


func _ready() -> void:
	if not auto:
		Ui.push_modal(self, skip)
	theme = Ui.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP if not auto else Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not auto:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.35)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	var p := Ui.panel(22, Color(Ui.C_PANEL, 0.96), Ui.C_BORDER)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if auto:
		Ui.place(p, Control.PRESET_CENTER_TOP, Vector2(-520, 120))
		p.custom_minimum_size = Vector2(1040, 150)
	else:
		Ui.place(p, Control.PRESET_CENTER_BOTTOM, Vector2(-760, -330))
		p.custom_minimum_size = Vector2(1520, 270)
	add_child(p)
	var h := Ui.hbox(24)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	_portrait = Ui.icon("", 120 if auto else 220)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(_portrait)
	var v := Ui.vbox(8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	_name = Ui.label("", 30 if not auto else 24, Ui.C_GOLD)
	v.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = false
	_text.fit_content = true
	_text.scroll_active = false
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("normal_font_size", 28 if not auto else 22)
	v.add_child(_text)
	if not auto:
		_hint = Ui.label("Clic / Espace : continuer   •   Échap : passer", 16, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_RIGHT)
		v.add_child(Ui.spacer())
		v.add_child(_hint)
	_next()


func _speaker(who: String) -> Dictionary:
	if who == "hero":
		var c: Dictionary = Db.characters.get(hero_id, Db.characters.patatron)
		return {"name": hero_name if hero_name != "" else c.name, "portrait": c.sprite, "color": "#5ff7ff"}
	return Db.campaign.speakers.get(who, {"name": who, "portrait": "", "color": "#ffffff"})


func _next() -> void:
	_idx += 1
	if _idx >= lines.size():
		finished.emit()
		queue_free()
		return
	var line: Dictionary = lines[_idx]
	var sp = _speaker(line.who)
	_name.text = sp.name
	_name.add_theme_color_override("font_color", Color(sp.color))
	_portrait.texture = Db.tex(sp.portrait)
	_portrait.flip_h = line.who == "hero"
	_text.text = line.text
	_text.visible_characters = 0
	_shown = 0.0
	_auto_timer = 0.0
	var tw = _portrait.create_tween()
	_portrait.scale = Vector2(0.9, 0.9)
	_portrait.pivot_offset = _portrait.custom_minimum_size / 2
	tw.tween_property(_portrait, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)


func _process(delta: float) -> void:
	if _idx < 0 or _idx >= lines.size():
		return
	var total = _text.get_total_character_count()
	if _shown < total:
		_shown += delta * 45.0 * Settings.text_speed
		_text.visible_characters = int(_shown)
		_blip_acc += delta
		if _blip_acc > 0.07:
			_blip_acc = 0.0
			Audio.play_dialogue_blip()
	elif auto:
		_auto_timer += delta
		if _auto_timer > 1.6 + total * 0.03:
			_next()


func _input(event: InputEvent) -> void:
	if auto:
		return
	var advance = (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT) \
		or event.is_action_pressed("ui_accept") or event.is_action_pressed("dash")
	if advance:
		get_viewport().set_input_as_handled()
		if _shown < _text.get_total_character_count():
			_shown = _text.get_total_character_count()
			_text.visible_characters = -1
		else:
			_next()



## Passe tout le dialogue (Échap).
func skip() -> void:
	_idx = lines.size()
	_next()
