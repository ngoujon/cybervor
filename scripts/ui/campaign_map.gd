extends Control
## Carte de la campagne : 5 zones, 4 missions chacune.

var _zone_idx := 0
var _zone_panel: VBoxContainer
var _bg: TextureRect
var _mission_box: VBoxContainer
var _zone_tabs: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var base := ColorRect.new()
	base.color = Ui.C_BG
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(base)
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_bg)
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.02, 0.08, 0.5)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	Audio.play_music("carte")

	var root := Ui.vbox(16)
	add_child(Ui.margin(root, 40))
	root.add_child(Ui.title("Campagne : Opération Mise à Jour"))
	var dh := Ui.hbox(10)
	dh.alignment = BoxContainer.ALIGNMENT_CENTER
	dh.add_child(Ui.label("Difficulté :", 20))
	var dopt := OptionButton.new()
	for d in Db.DIFFICULTIES:
		dopt.add_item(d.name)
	dopt.select(Settings.difficulty)
	var ddesc := Ui.label(Db.DIFFICULTIES[Settings.difficulty].desc, 18, Ui.C_MUTED)
	dopt.item_selected.connect(func(i):
		Settings.difficulty = i
		Settings.save_settings()
		ddesc.text = Db.DIFFICULTIES[i].desc)
	dh.add_child(dopt)
	dh.add_child(ddesc)
	root.add_child(dh)
	_zone_tabs = Ui.hbox(10)
	_zone_tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(_zone_tabs)

	var body := Ui.hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var zp := Ui.panel(22)
	zp.custom_minimum_size = Vector2(620, 0)
	body.add_child(zp)
	_zone_panel = Ui.vbox(10)
	zp.add_child(_zone_panel)
	body.add_child(Ui.spacer())
	var mp := Ui.panel(22)
	mp.custom_minimum_size = Vector2(760, 0)
	body.add_child(mp)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	mp.add_child(scroll)
	_mission_box = Ui.vbox(12)
	_mission_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_mission_box)

	var back := Ui.button("Retour", func(): Game.goto("main_menu"), 260)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(back)

	# Zone par défaut : la première non terminée
	for i in Db.campaign.zones.size():
		var z: Dictionary = Db.campaign.zones[i]
		if Profile.mission_unlocked(z.missions[0].id):
			_zone_idx = i
	_show_zone(_zone_idx)


func _show_zone(idx: int) -> void:
	_zone_idx = idx
	for c in _zone_tabs.get_children():
		c.queue_free()
	for i in Db.campaign.zones.size():
		var z: Dictionary = Db.campaign.zones[i]
		var unlocked = Profile.mission_unlocked(z.missions[0].id)
		var b := Ui.button("%d. %s" % [i + 1, z.name] if unlocked else "%d. ???" % (i + 1), _show_zone.bind(i), 0, 20)
		b.disabled = not unlocked
		b.toggle_mode = true
		b.button_pressed = i == idx
		_zone_tabs.add_child(b)

	var z: Dictionary = Db.campaign.zones[idx]
	_bg.texture = Db.tex(z.background)
	for c in _zone_panel.get_children():
		c.queue_free()
	_zone_panel.add_child(Ui.title(z.name, 40, Color(z.tint)))
	var img := Ui.icon(z.background, 300)
	img.custom_minimum_size = Vector2(560, 300)
	img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_zone_panel.add_child(img)
	var d := Ui.label(z.desc, 20, Ui.C_MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_zone_panel.add_child(d)
	var done := 0
	for m in z.missions:
		if Profile.mission_completed(m.id):
			done += 1
	_zone_panel.add_child(Ui.label("Progression : %d / %d missions" % [done, z.missions.size()], 22, Ui.C_GOLD))

	for c in _mission_box.get_children():
		c.queue_free()
	for i in z.missions.size():
		_mission_box.add_child(_mission_row(z, z.missions[i], i))


func _mission_row(z: Dictionary, m: Dictionary, i: int) -> Control:
	var unlocked = Profile.mission_unlocked(m.id)
	var completed = Profile.mission_completed(m.id)
	var p := Ui.panel(14, Color(Ui.C_PANEL_2, 0.9), Ui.C_GOLD if m.has("boss") else Ui.C_BORDER.darkened(0.4))
	var h := Ui.hbox(14)
	p.add_child(h)
	var icon_path: String = Db.enemies[m.boss].sprite if m.has("boss") else Db.enemies[m.pool[0][0]].sprite
	var ic := Ui.icon(icon_path, 84)
	if not unlocked:
		ic.modulate = Color(0.1, 0.1, 0.15)
	h.add_child(ic)
	var v := Ui.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var name_txt: String = ("Mission %d : %s" % [i + 1, m.name]) if unlocked else "Mission %d : ???" % (i + 1)
	v.add_child(Ui.label(name_txt, 24, Ui.C_GOLD if m.has("boss") else Ui.C_TEXT))
	var info = "%d vagues — difficulté %s" % [m.waves, "★".repeat(clamp(int(round(m.difficulty * 2)), 1, 6))]
	if m.has("boss"):
		info += " — BOSS : " + Db.enemies[m.boss].name
	v.add_child(Ui.label(info, 18, Ui.C_MUTED))
	if completed:
		v.add_child(Ui.label("✔ Terminée", 18, Ui.C_GOOD))
	var b := Ui.button("Jouer" if not completed else "Rejouer", _launch.bind(m.id), 160)
	b.disabled = not unlocked
	h.add_child(b)
	return p


func _launch(mission_id: String) -> void:
	Net.start_solo("campaign")
	Net.lobby.mission = mission_id
	Net.lobby.difficulty = Settings.difficulty
	Game.goto("character_select", {"then": "solo_start"})
