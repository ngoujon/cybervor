extends Control
## Paramètres : audio (volumes par bus + sourdine), vidéo, jeu, réseau.
## Utilisable comme écran plein (menu) ou en superposition (pause) via `overlay = true`.

signal closed

var overlay := false
var _url: LineEdit
var _net_status: Label
var _tabs: TabContainer


## Manette : LB / RB pour changer d'onglet (sauf pendant la saisie d'un raccourci).
func _input(event: InputEvent) -> void:
	if _tabs == null or not (event is InputEventJoypadButton) or not event.pressed:
		return
	var ct = _tabs.get_current_tab_control()
	if ct and ct.has_method("capturing") and ct.capturing():
		return
	var d := 0
	if event.button_index == JOY_BUTTON_LEFT_SHOULDER:
		d = -1
	elif event.button_index == JOY_BUTTON_RIGHT_SHOULDER:
		d = 1
	if d != 0:
		_tabs.current_tab = posmod(_tabs.current_tab + d, _tabs.get_tab_count())
		get_viewport().set_input_as_handled()


func _ready() -> void:
	theme = Ui.theme
	if overlay:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.7)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(dim)
	else:
		Ui.screen_base(self, "res://assets/backgrounds/titre.png", 0.8)
		Audio.play_music("menu")
	var root := Ui.vbox(16)
	add_child(Ui.margin(root, 60))
	root.add_child(Ui.title("Paramètres"))
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 24)
	root.add_child(tabs)
	tabs.add_child(_audio_tab())
	tabs.add_child(_video_tab())
	tabs.add_child(_game_tab())
	tabs.add_child(load("res://scripts/ui/controls_tab.gd").new())
	tabs.add_child(_network_tab())
	_tabs = tabs
	var back := Ui.button("Enregistrer et revenir", _close, 380, 26)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(back)


func _page(title: String) -> VBoxContainer:
	var v := Ui.vbox(18)
	v.name = title
	return v


func _audio_tab() -> Control:
	var v := _page("Audio")
	v.add_child(Ui.label("Réglez chaque canal audio. La musique et les effets ont été générés avec ComfyUI.", 18, Ui.C_MUTED))
	for bus in Settings.AUDIO_BUSES:
		var row := Ui.hbox(16)
		var l := Ui.label(Settings.BUS_LABELS[bus], 24)
		l.custom_minimum_size = Vector2(280, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.01
		s.value = Settings.audio[bus]
		s.custom_minimum_size = Vector2(560, 32)
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(s)
		var pct := Ui.label("%d %%" % int(Settings.audio[bus] * 100), 22, Ui.C_GOLD)
		pct.custom_minimum_size = Vector2(90, 0)
		row.add_child(pct)
		var m := CheckBox.new()
		m.text = "Muet"
		m.button_pressed = Settings.mute[bus]
		m.add_theme_font_size_override("font_size", 20)
		row.add_child(m)
		s.value_changed.connect(func(val):
			Settings.set_volume(bus, val)
			pct.text = "%d %%" % int(val * 100))
		s.drag_ended.connect(func(_c): _preview(bus))
		m.toggled.connect(func(on): Settings.set_mute(bus, on))
		v.add_child(row)
	var mu := CheckBox.new()
	mu.text = "Couper le son quand la fenêtre n'est pas active"
	mu.button_pressed = Settings.mute_unfocused
	mu.toggled.connect(func(on): Settings.mute_unfocused = on)
	mu.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(mu)
	return v


func _preview(bus: String) -> void:
	match bus:
		"Effets":
			Audio.play("laser")
		"Interface":
			Audio.play("clic")
		"Dialogues":
			Audio.play_dialogue_blip()
		"Master":
			Audio.play("ramasse")


func _video_tab() -> Control:
	var v := _page("Vidéo")
	v.add_child(_check("Plein écran", Settings.fullscreen, func(on):
		Settings.fullscreen = on
		Settings.apply()))
	v.add_child(_check("Synchronisation verticale (V-Sync)", Settings.vsync, func(on):
		Settings.vsync = on
		Settings.apply()))
	v.add_child(_check("Afficher les FPS", Settings.show_fps, func(on): Settings.show_fps = on))
	var row := Ui.hbox(16)
	row.add_child(Ui.label("Tremblements de l'écran", 22))
	var s := HSlider.new()
	s.min_value = 0
	s.max_value = 1.5
	s.step = 0.05
	s.value = Settings.screen_shake
	s.custom_minimum_size = Vector2(400, 32)
	s.value_changed.connect(func(val): Settings.screen_shake = val)
	row.add_child(s)
	v.add_child(row)
	return v


func _game_tab() -> Control:
	var v := _page("Jeu")
	v.add_child(Ui.label("Pseudo, héros et apparence : cliquez sur votre profil en haut à droite du menu principal.", 18, Ui.C_MUTED))
	v.add_child(_check("Afficher les chiffres de dégâts", Settings.damage_numbers, func(on): Settings.damage_numbers = on))
	v.add_child(_check("Lancer automatiquement les sorts actifs dès qu'ils sont prêts", Settings.auto_cast, func(on): Settings.auto_cast = on))
	var r2 := Ui.hbox(16)
	r2.add_child(Ui.label("Vitesse du texte des dialogues", 22))
	var s := HSlider.new()
	s.min_value = 0.5
	s.max_value = 3.0
	s.step = 0.25
	s.value = Settings.text_speed
	s.custom_minimum_size = Vector2(400, 32)
	s.value_changed.connect(func(val): Settings.text_speed = val)
	r2.add_child(s)
	v.add_child(r2)
	v.add_child(Ui.label("Raccourcis de l'esquive et des sorts (clavier, souris, manette) : onglet « Commandes ».", 18, Ui.C_MUTED))
	return v


func _network_tab() -> Control:
	var v := _page("Réseau")
	v.add_child(Ui.label("Serveur méta (battle pass, profils, serveurs en ligne). Laissez vide pour jouer hors ligne.", 18, Ui.C_MUTED))
	var row := Ui.hbox(16)
	_url = LineEdit.new()
	_url.placeholder_text = "https://cybervor.exemple.fr"
	_url.text = Backend.base_url
	_url.custom_minimum_size = Vector2(620, 0)
	row.add_child(_url)
	row.add_child(Ui.button("Se connecter", func():
		Backend.set_url(_url.text)
		_net_status.text = "Connexion…", 0, 20))
	v.add_child(row)
	_net_status = Ui.label("Statut : " + ("en ligne" if Backend.online else "hors ligne"), 20, Ui.C_GOLD)
	v.add_child(_net_status)
	Backend.status_changed.connect(func(on):
		if is_instance_valid(_net_status):
			_net_status.text = "Statut : " + ("en ligne ✔" if on else "hors ligne (serveur injoignable)"))
	v.add_child(Ui.label("Identifiant joueur : " + Profile.data.player_id, 16, Ui.C_MUTED))
	return v


func _check(text: String, value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.add_theme_font_size_override("font_size", 22)
	c.toggled.connect(cb)
	c.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return c


func _close() -> void:
	Settings.save_settings()
	Settings.apply()
	if overlay:
		closed.emit()
		queue_free()
	else:
		Game.goto("main_menu")
