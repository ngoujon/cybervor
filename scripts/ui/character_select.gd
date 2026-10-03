extends Control
## Sélection du personnage.

var _detail: VBoxContainer
var _selected := ""
var _cards := {}


func _ready() -> void:
	Ui.screen_base(self, "res://assets/backgrounds/titre.png", 0.75)
	_selected = Profile.data.character
	if not Profile.character_unlocked(_selected):
		_selected = "patatron"
	var root := Ui.vbox(18)
	add_child(Ui.margin(root, 46))
	root.add_child(Ui.title("Choisissez votre héros"))

	var body := Ui.hbox(30)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	body.add_child(grid)
	for id in Db.characters:
		grid.add_child(_card(id))

	var dp := Ui.panel(24)
	dp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(dp)
	_detail = Ui.vbox(12)
	dp.add_child(_detail)

	var bar := Ui.hbox(20)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bar)
	bar.add_child(Ui.button("Retour", _back, 260))
	var go := Ui.button("C'est parti !", _confirm, 320, 28)
	bar.add_child(go)
	go.call_deferred("grab_focus")
	_select(_selected)


func _card(id: String) -> Control:
	var c: Dictionary = Db.characters[id]
	var unlocked = Profile.character_unlocked(id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(230, 250)
	b.toggle_mode = true
	Ui.wire_sfx(b)
	var v := Ui.vbox(4)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var ic := Ui.icon(c.sprite, 160)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not unlocked:
		ic.modulate = Color(0.1, 0.1, 0.15, 1)
	v.add_child(ic)
	var l := Ui.label(c.name if unlocked else "???", 22, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(l)
	b.add_child(v)
	b.pressed.connect(func(): _select(id))
	_cards[id] = b
	return b


func _select(id: String) -> void:
	_selected = id
	for k in _cards:
		_cards[k].button_pressed = k == id
	for ch in _detail.get_children():
		ch.queue_free()
	var c: Dictionary = Db.characters[id]
	var unlocked = Profile.character_unlocked(id)
	var top := Ui.hbox(16)
	var portrait := Ui.icon(c.sprite, 200)
	portrait.modulate = Ui.color_of_cosmetic(Profile.data.cosmetics.color) if unlocked else Color(0.1, 0.1, 0.15)
	top.add_child(portrait)
	var tv := Ui.vbox(6)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_child(Ui.title(c.name if unlocked else "Verrouillé", 44, Ui.C_ACCENT))
	var desc := Ui.label(c.desc, 20, Ui.C_MUTED)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tv.add_child(desc)
	top.add_child(tv)
	_detail.add_child(top)
	if not unlocked:
		var m = Db.mission(c.unlock)
		_detail.add_child(Ui.label("Terminez la mission « %s » pour débloquer ce héros." % m.get("name", c.unlock), 22, Ui.C_GOLD))
		return
	_detail.add_child(Ui.label("Capacité", 26, Ui.C_BORDER))
	var p := Ui.label(c.passive, 21)
	p.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail.add_child(p)
	var w: Dictionary = Db.weapons[c.weapon]
	_detail.add_child(Ui.label("Arme de départ", 26, Ui.C_BORDER))
	var wr := Ui.hbox(10)
	wr.add_child(Ui.icon(w.icon, 64))
	var wl := Ui.label("%s\n%s" % [w.name, w.desc], 19)
	wl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wr.add_child(wl)
	_detail.add_child(wr)
	var bonus = Profile.skill_stats()
	if not bonus.is_empty():
		_detail.add_child(Ui.label("Bonus des arbres de compétences actifs : %d" % bonus.size(), 18, Ui.C_GOOD))


func _confirm() -> void:
	if not Profile.character_unlocked(_selected):
		Audio.play("erreur")
		Ui.toast("Ce héros est encore verrouillé !", Ui.C_BAD)
		return
	Profile.data.character = _selected
	Profile.save()
	match Game.params.get("then", ""):
		"solo_start":
			Net.peers[1] = Net.local_info()
			Net.request_start()
		"lobby":
			Net.update_my_info({"character": _selected})
			Game.goto("lobby")
		_:
			Game.goto("main_menu")


func _back() -> void:
	match Game.params.get("then", ""):
		"lobby":
			Game.goto("lobby")
		"solo_start":
			Game.goto("campaign" if Net.lobby.mode == "campaign" else "play")
		_:
			Game.goto("main_menu")
