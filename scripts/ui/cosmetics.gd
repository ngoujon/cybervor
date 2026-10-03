extends Control
## Personnalisation : chapeaux, couleurs et titres débloqués via le battle pass.

var _preview_char: TextureRect
var _preview_hat: TextureRect
var _preview_title: Label
var _lists: VBoxContainer
var embedded := false   # intégré dans la fenêtre Profil (pas de fond, de titre ni de bouton Retour)


func _ready() -> void:
	var root := Ui.vbox(16)
	if embedded:
		name = "Personnalisation"
		add_child(root)
		root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	else:
		Ui.screen_base(self, "res://assets/backgrounds/zone_serres.png", 0.78)
		Audio.play_music("boutique")
		add_child(Ui.margin(root, 40))
		root.add_child(Ui.title("Personnalisation"))
	var body := Ui.hbox(30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var pp := Ui.panel(24)
	pp.custom_minimum_size = Vector2(440 if embedded else 480, 0)
	body.add_child(pp)
	var pv := Ui.vbox(10)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pp.add_child(pv)
	var stage := Control.new()
	stage.custom_minimum_size = Vector2(420, 420)
	pv.add_child(stage)
	_preview_char = Ui.icon(Db.characters[Profile.data.character].sprite, 300)
	_preview_char.position = Vector2(60, 100)
	_preview_char.size = Vector2(300, 300)
	stage.add_child(_preview_char)
	_preview_hat = Ui.icon("", 150)
	_preview_hat.position = Vector2(135, 20)
	_preview_hat.size = Vector2(150, 150)
	stage.add_child(_preview_hat)
	_preview_title = Ui.label("", 24, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	pv.add_child(_preview_title)

	var lp := Ui.panel(20)
	lp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(lp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.add_child(scroll)
	_lists = Ui.vbox(14)
	_lists.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_lists)

	if not embedded:
		var back := Ui.button("Retour", func(): Game.goto("main_menu"), 260)
		back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		root.add_child(back)
	_refresh()


func _process(_d: float) -> void:
	if _preview_char:
		_preview_char.modulate = Ui.color_of_cosmetic(Profile.data.cosmetics.color)


func _refresh() -> void:
	var cos: Dictionary = Profile.data.cosmetics
	_preview_hat.texture = Db.tex(Db.battlepass.hats.get(cos.hat, {}).get("sprite", "")) if cos.hat != "" else null
	_preview_title.text = ("« %s »" % Db.battlepass.titles[cos.title]) if cos.title != "" else "(aucun titre)"
	for c in _lists.get_children():
		c.queue_free()
	_section("Chapeaux", "hats", "hat", Db.battlepass.hats)
	_section("Couleurs", "colors", "color", Db.battlepass.colors)
	_section("Titres", "titles", "title", Db.battlepass.titles)
	_lists.add_child(Ui.label("Débloquez d'autres cosmétiques dans la piste premium du battle pass.", 18, Ui.C_MUTED))


func _section(title: String, kind: String, slot: String, catalog: Dictionary) -> void:
	_lists.add_child(Ui.label(title, 28, Ui.C_BORDER))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	_lists.add_child(flow)
	var none := Ui.button("Aucun", func():
		Profile.equip(slot, "")
		_refresh(), 0, 18)
	none.toggle_mode = true
	none.button_pressed = Profile.data.cosmetics[slot] == ""
	flow.add_child(none)
	for id in catalog:
		var owned = Profile.owns(kind, id)
		var label_txt: String = catalog[id] if kind == "titles" else catalog[id].name
		var b := Ui.button(label_txt if owned else "🔒 " + label_txt, func():
			Profile.equip(slot, id)
			_refresh(), 0, 18)
		b.toggle_mode = true
		b.button_pressed = Profile.data.cosmetics[slot] == id
		b.disabled = not owned
		if kind == "hats":
			b.icon = Db.tex(catalog[id].sprite)
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 40)
		elif kind == "colors" and owned:
			b.add_theme_color_override("font_color", Ui.color_of_cosmetic(id))
		flow.add_child(b)
