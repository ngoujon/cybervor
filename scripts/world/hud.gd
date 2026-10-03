extends CanvasLayer
## Interface en jeu : PV, XP, données, vague, chrono, coéquipiers, boss, armes, score PvP.

var world: Node
var _hp_bar: ProgressBar
var _hp_label: Label
var _xp_bar: ProgressBar
var _lvl_label: Label
var _data_label: Label
var _wave_label: Label
var _timer_label: Label
var _team_box: VBoxContainer
var _boss_panel: PanelContainer
var _boss_bar: ProgressBar
var _boss_name: Label
var _weapons_box: HBoxContainer
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _hurt: ColorRect
var _score: Label
var _hint: Label
var _root: Control
var spell_hud: Control
var _chat_box: VBoxContainer
var _chat_log: RichTextLabel
var _chat_edit: LineEdit
var _chat_fade := 0.0


func _ready() -> void:
	layer = 10
	if DisplayServer.get_name() == "headless":
		return
	_root = Control.new()
	_root.theme = Ui.theme
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_hurt = ColorRect.new()
	_hurt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hurt.color = Color(1, 0, 0.2, 0)
	_hurt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hurt)

	# Bloc joueur (haut gauche)
	var p := Ui.panel(14)
	Ui.place(p, Control.PRESET_TOP_LEFT, Vector2(20, 20))
	p.custom_minimum_size = Vector2(430, 0)
	_root.add_child(p)
	var v := Ui.vbox(6)
	p.add_child(v)
	var hb := Control.new()
	hb.custom_minimum_size = Vector2(400, 34)
	v.add_child(hb)
	_hp_bar = ProgressBar.new()
	_hp_bar.show_percentage = false
	_hp_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_bar.add_theme_stylebox_override("fill", Ui.box(Color("#ff4d6d"), Color(0, 0, 0, 0), 0, 8))
	hb.add_child(_hp_bar)
	_hp_label = Ui.label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	_hp_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(_hp_label)
	var xr := Ui.hbox(8)
	v.add_child(xr)
	_lvl_label = Ui.label("Niv. 1", 20, Ui.C_GOLD)
	_lvl_label.custom_minimum_size = Vector2(80, 0)
	xr.add_child(_lvl_label)
	_xp_bar = ProgressBar.new()
	_xp_bar.show_percentage = false
	_xp_bar.max_value = 1.0
	_xp_bar.step = 0.001
	_xp_bar.custom_minimum_size = Vector2(300, 14)
	_xp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_xp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	xr.add_child(_xp_bar)
	var dr := Ui.hbox(8)
	v.add_child(dr)
	dr.add_child(Ui.icon("res://assets/sprites/pickups/data.png", 30))
	_data_label = Ui.label("0", 24, Ui.C_BORDER)
	dr.add_child(_data_label)

	# Vague / chrono (haut centre)
	var top := Ui.vbox(0)
	Ui.place(top, Control.PRESET_CENTER_TOP, Vector2(-200, 14))
	top.custom_minimum_size = Vector2(400, 0)
	_root.add_child(top)
	_wave_label = Ui.label("", 28, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_wave_label)
	_timer_label = Ui.title("", 60, Color.WHITE)
	top.add_child(_timer_label)
	_score = Ui.label("", 22, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_score)

	# Coéquipiers (haut droite)
	_team_box = Ui.vbox(6)
	Ui.place(_team_box, Control.PRESET_TOP_RIGHT, Vector2(-320, 20))
	_team_box.custom_minimum_size = Vector2(300, 0)
	_root.add_child(_team_box)

	# Armes (bas gauche)
	_weapons_box = Ui.hbox(6)
	Ui.place(_weapons_box, Control.PRESET_BOTTOM_LEFT, Vector2(20, -90))
	_root.add_child(_weapons_box)

	# Boss (bas centre)
	_boss_panel = Ui.panel(10, Color(0.1, 0.02, 0.05, 0.9), Ui.C_ACCENT)
	Ui.place(_boss_panel, Control.PRESET_CENTER_BOTTOM, Vector2(-450, -205))
	_boss_panel.custom_minimum_size = Vector2(900, 0)
	_boss_panel.visible = false
	_root.add_child(_boss_panel)
	var bv := Ui.vbox(4)
	_boss_panel.add_child(bv)
	_boss_name = Ui.label("", 24, Ui.C_ACCENT, HORIZONTAL_ALIGNMENT_CENTER)
	bv.add_child(_boss_name)
	_boss_bar = ProgressBar.new()
	_boss_bar.max_value = 1.0
	_boss_bar.step = 0.001
	_boss_bar.show_percentage = false
	_boss_bar.custom_minimum_size = Vector2(860, 22)
	_boss_bar.add_theme_stylebox_override("fill", Ui.box(Ui.C_ACCENT, Color(0, 0, 0, 0), 0, 8))
	bv.add_child(_boss_bar)

	spell_hud = load("res://scripts/world/spell_hud.gd").new()
	spell_hud.world = world
	_root.add_child(spell_hud)

	_hint = Ui.label("", 16, Ui.C_MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.custom_minimum_size = Vector2(760, 0)
	Ui.place(_hint, Control.PRESET_BOTTOM_RIGHT, Vector2(-790, -36))
	_update_hint()
	Settings.binds_changed.connect(_update_hint)
	Settings.input_device_changed.connect(func(_p): _update_hint())
	_root.add_child(_hint)

	# Bannière centrale
	_banner = Ui.vbox(0)
	Ui.place(_banner, Control.PRESET_CENTER, Vector2(-500, -220))
	_banner.custom_minimum_size = Vector2(1000, 0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.modulate.a = 0
	_root.add_child(_banner)
	_banner_title = Ui.title("", 86)
	_banner.add_child(_banner_title)
	_banner_sub = Ui.label("", 28, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.add_child(_banner_sub)
	_build_chat()


func _update_hint() -> void:
	if not is_instance_valid(_hint):
		return
	var keys := range(1, 6).map(func(i): return Settings.hud_label("spell_%d" % i))
	_hint.text = "%s : pause · %s : esquive · sorts : %s%s" % ["Start" if Settings.using_pad else "Échap", Settings.hud_label("dash"),
		" ".join(keys), " · Entrée : discuter" if Net.is_online() else ""]


# ------------------------------------------------------------------ chat en jeu (multijoueur)
func _build_chat() -> void:
	if not Net.is_online():
		return
	_update_hint()
	_chat_box = Ui.vbox(4)
	_chat_box.custom_minimum_size = Vector2(520, 0)
	Ui.place(_chat_box, Control.PRESET_BOTTOM_LEFT, Vector2(24, -300))
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chat_box)
	_chat_log = Ui.rich("", 18)
	_chat_log.custom_minimum_size = Vector2(520, 200)
	_chat_log.scroll_following = true
	_chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_box.add_child(_chat_log)
	_chat_edit = LineEdit.new()
	_chat_edit.placeholder_text = "Message à l'équipe… (Entrée pour envoyer, Échap pour annuler)"
	_chat_edit.max_length = 200
	_chat_edit.add_theme_font_size_override("font_size", 18)
	_chat_edit.visible = false
	_chat_edit.text_submitted.connect(_on_chat_submit)
	_chat_box.add_child(_chat_edit)
	Net.chat_received.connect(_on_chat)


func _on_chat(from_name: String, text: String) -> void:
	if _chat_log == null:
		return
	var col := Ui.C_MUTED if from_name == "Système" else Ui.C_ACCENT
	_chat_log.append_text("[color=#%s]%s :[/color] %s
" % [col.to_html(false), from_name.replace("[", "("), text.replace("[", "(")])
	_chat_fade = 8.0
	_chat_box.modulate.a = 1.0


func _on_chat_submit(text: String) -> void:
	text = text.strip_edges()
	if text != "":
		Net.send_chat(text)
	_close_chat()


func _close_chat() -> void:
	_chat_edit.text = ""
	_chat_edit.release_focus()
	_chat_edit.visible = false
	_chat_fade = 6.0


func chat_focused() -> bool:
	return _chat_edit != null and _chat_edit.has_focus()


func _input(event: InputEvent) -> void:
	if _chat_edit == null or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _chat_edit.has_focus():
		if event.keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
	elif event.keycode in [KEY_ENTER, KEY_KP_ENTER] and get_viewport().gui_get_focus_owner() == null and not Ui.modal_open():
		_chat_edit.visible = true
		_chat_box.modulate.a = 1.0
		_chat_edit.grab_focus.call_deferred()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _chat_box and not chat_focused():
		_chat_fade -= delta
		_chat_box.modulate.a = clamp(_chat_fade / 2.0, 0.35, 1.0)
	if world == null or _hp_bar == null:
		return
	_hurt.color.a = max(0.0, _hurt.color.a - delta * 1.5)
	var me: Dictionary = world.snapshot_players.get(Net.my_id(), {})
	if not me.is_empty():
		_hp_bar.max_value = me.max_hp
		_hp_bar.value = me.hp
		_hp_label.text = "%d / %d" % [ceil(me.hp), me.max_hp] if me.alive else "HORS SERVICE"
		_lvl_label.text = "Niv. %d" % me.level
		_xp_bar.value = me.xp
		_data_label.text = str(me.data)
	match world.state:
		"wave":
			if world.pvp:
				_wave_label.text = "Manche %d" % world.wave
			elif world.max_waves > 0:
				_wave_label.text = "Vague %d / %d" % [world.wave, world.max_waves]
			else:
				_wave_label.text = "Vague %d (survie)" % world.wave
			var boss_wave: bool = world.mode == "campaign" and world.wave == world.max_waves and world.mission.has("boss")
			boss_wave = boss_wave or (world.mode == "endless" and world.wave % 5 == 0)
			if boss_wave:
				_timer_label.text = "BOSS"
			else:
				_timer_label.text = str(int(ceil(max(0.0, world.wave_duration - world.wave_time))))
		"intermission":
			_wave_label.text = "Entre deux vagues" if not world.pvp else "Entre deux manches"
			_timer_label.text = ""
		"intro":
			_wave_label.text = world.mission.get("name", "")
			_timer_label.text = ""
		_:
			_timer_label.text = ""
	if world.pvp:
		var my_team: int = world.team_of(Net.my_id())
		var fmt: int = int(world.cfg.get("team_size", 1))
		_score.text = "%s %d  —  %d %s   (%dv%d, premier à %d)  •  Vous : %s" % [Db.TEAM_NAMES[0], int(world.pvp_scores.get(0, 0)),
			int(world.pvp_scores.get(1, 0)), Db.TEAM_NAMES[1], fmt, fmt, world.PVP_WIN_ROUNDS, Db.TEAM_NAMES[my_team]]
		_score.add_theme_color_override("font_color", Db.TEAM_COLORS[my_team])
	var boss: Dictionary = world.enemies.boss_view()
	_boss_panel.visible = not boss.is_empty() and world.state == "wave"
	if _boss_panel.visible:
		_boss_name.text = boss.name
		_boss_bar.value = boss.hp
	_refresh_team()


func _refresh_team() -> void:
	var ids: Array = world.player_nodes.keys()
	ids.sort()
	ids.erase(Net.my_id())
	while _team_box.get_child_count() < ids.size():
		var row := Ui.panel(8)
		var h := Ui.vbox(2)
		row.add_child(h)
		h.add_child(Ui.label("", 18))
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(260, 10)
		bar.add_theme_stylebox_override("fill", Ui.box(Color("#06ffa5"), Color(0, 0, 0, 0), 0, 6))
		h.add_child(bar)
		_team_box.add_child(row)
	while _team_box.get_child_count() > ids.size():
		var c := _team_box.get_child(_team_box.get_child_count() - 1)
		_team_box.remove_child(c)
		c.queue_free()
	for i in ids.size():
		var pid: int = ids[i]
		var info: Dictionary = world.snapshot_players.get(pid, {})
		var box := _team_box.get_child(i).get_child(0)
		var nm: String = world.player_nodes[pid].display_name
		if world.pvp:
			nm += "  [allié]" if not world.is_foe(Net.my_id(), pid) else "  [adversaire]"
		(box.get_child(0) as Label).text = nm + ("" if info.get("alive", true) else "  (hors service)")
		var bar: ProgressBar = box.get_child(1)
		bar.max_value = info.get("max_hp", 1)
		bar.value = info.get("hp", 0)


func refresh_loadout() -> void:
	if _weapons_box == null:
		return
	if spell_hud:
		spell_hud.refresh()
	for c in _weapons_box.get_children():
		c.queue_free()
	var st: Dictionary = world.public.get(Net.my_id(), {})
	for w in st.get("weapons", []):
		var def: Dictionary = Db.weapons.get(w[0], {})
		var p := Ui.panel(4, Color(Ui.C_PANEL, 0.85), Db.RARITY_COLORS[w[1]])
		var ic := Ui.icon(def.get("icon", ""), 48)
		ic.tooltip_text = "%s %s" % [def.get("name", ""), Db.TIER_NAMES[w[1]]]
		p.add_child(ic)
		_weapons_box.add_child(p)


func on_state(s: String) -> void:
	Ui.set_game_cursor(s == "wave")
	if _hint:
		_hint.visible = s == "wave"
	if _root:
		for c in _root.get_children():
			if c != _banner and c != _chat_box:
				c.visible = s != "intermission" or c == _hurt


func banner(title: String, sub: String, color: Color) -> void:
	if _banner == null:
		return
	_banner_title.text = title
	_banner_title.add_theme_color_override("font_color", color)
	_banner_sub.text = sub
	var tw = _banner.create_tween()
	_banner.modulate.a = 0
	_banner.scale = Vector2(0.8, 0.8)
	_banner.pivot_offset = _banner.size / 2
	tw.tween_property(_banner, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK)
	tw.tween_interval(1.6)
	tw.tween_property(_banner, "modulate:a", 0.0, 0.5)


func hurt() -> void:
	if _hurt:
		_hurt.color.a = 0.28
