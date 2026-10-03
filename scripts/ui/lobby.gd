extends Control
## Salon multijoueur : joueurs, choix du mode / mission, discussion, lancement.

var _players_box: VBoxContainer
var _settings_box: VBoxContainer
var _chat_log: RichTextLabel
var _chat_input: LineEdit
var _ready_btn: Button
var _start_btn: Button
var _info: Label


func _ready() -> void:
	Ui.screen_base(self, "res://assets/backgrounds/pvp.png" if Net.lobby.mode == "pvp" else "res://assets/backgrounds/titre.png", 0.72)
	Audio.play_music("menu")
	var root := Ui.vbox(16)
	add_child(Ui.margin(root, 40))
	root.add_child(Ui.title("Salon multijoueur"))
	_info = Ui.label("", 18, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_info)

	var body := Ui.hbox(20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	var pp := Ui.panel(18)
	pp.custom_minimum_size = Vector2(640, 0)
	body.add_child(pp)
	var pv := Ui.vbox(10)
	pp.add_child(pv)
	pv.add_child(Ui.label("Joueurs", 28, Ui.C_BORDER))
	_players_box = Ui.vbox(8)
	pv.add_child(_players_box)

	var sp := Ui.panel(18)
	sp.custom_minimum_size = Vector2(520, 0)
	body.add_child(sp)
	_settings_box = Ui.vbox(10)
	sp.add_child(_settings_box)

	var cp := Ui.panel(18)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(cp)
	var cv := Ui.vbox(8)
	cp.add_child(cv)
	cv.add_child(Ui.label("Discussion", 28, Ui.C_BORDER))
	_chat_log = RichTextLabel.new()
	_chat_log.bbcode_enabled = true
	_chat_log.scroll_following = true
	_chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chat_log.add_theme_font_size_override("normal_font_size", 18)
	cv.add_child(_chat_log)
	_chat_input = LineEdit.new()
	_chat_input.placeholder_text = "Écrire un message… (Entrée)"
	_chat_input.text_submitted.connect(func(t):
		Net.send_chat(t)
		_chat_input.clear())
	cv.add_child(_chat_input)

	var bar := Ui.hbox(16)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bar)
	bar.add_child(Ui.button("Quitter le salon", _leave, 260))
	bar.add_child(Ui.button("Changer de héros", func(): Game.goto("character_select", {"then": "lobby"}), 280))
	_ready_btn = Ui.button("Prêt !", _toggle_ready, 220, 26)
	_ready_btn.toggle_mode = true
	bar.add_child(_ready_btn)
	_start_btn = Ui.button("Lancer la partie", func(): Net.request_start(), 300, 28)
	bar.add_child(_start_btn)

	Net.lobby_changed.connect(_refresh)
	Net.chat_received.connect(_on_chat)
	Net.disconnected.connect(_on_disconnected)
	# Synchronise nos infos (personnage / compétences / cosmétiques) avec le serveur.
	var me = Net.local_info()
	Net.update_my_info({"character": me.character, "skills": me.skills, "cosmetics": me.cosmetics, "name": me.name, "ready": false})
	_refresh()
	_on_chat("Système", "Bienvenue ! Choisissez votre héros, puis cliquez sur « Prêt ! ».")


func _refresh() -> void:
	if not is_instance_valid(_players_box):
		return
	var leader = Net.is_leader() or (Net.is_server() and not Net.dedicated)
	if Net.is_server() and not Net.dedicated:
		_info.text = "Vous hébergez sur le port %d — IP locales : %s" % [Net.port, ", ".join(_local_ips())]
	else:
		_info.text = "Connecté au serveur." + ("  Vous êtes le chef du salon." if Net.is_leader() else "")

	for c in _players_box.get_children():
		c.queue_free()
	var ids = Net.peers.keys()
	ids.sort()
	var all_ready := true
	for id in ids:
		var p: Dictionary = Net.peers[id]
		if not p.get("ready", false) and not p.get("bot", false):
			all_ready = false
		var row := Ui.panel(10, Color(Ui.C_PANEL_2, 0.9), Ui.C_GOLD if id == Net.leader_id else Ui.C_BORDER.darkened(0.5))
		var h := Ui.hbox(12)
		row.add_child(h)
		var ch: Dictionary = Db.characters.get(p.get("character", "patatron"), Db.characters.patatron)
		var ic := Ui.icon(ch.sprite, 64)
		ic.modulate = Ui.color_of_cosmetic(p.get("cosmetics", {}).get("color", ""))
		h.add_child(ic)
		var v := Ui.vbox(2)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nm: String = p.get("name", "?")
		if id == Net.my_id():
			nm += " (vous)"
		if id == Net.leader_id:
			nm += "  ♛"
		v.add_child(Ui.label(nm, 22))
		var sub: String = ch.name
		if Net.lobby.mode == "pvp":
			var t: int = int(p.get("team", 0))
			sub += "  —  " + Db.TEAM_NAMES[t]
			if p.get("bot", false):
				sub += " (" + Db.AI_LEVELS[int(Net.lobby.get("ai_level", 1))].name + ")"
		v.add_child(Ui.label(sub, 17, Db.TEAM_COLORS[int(p.get("team", 0))] if Net.lobby.mode == "pvp" else Ui.C_MUTED))
		h.add_child(v)
		if Backend.online and id != Net.my_id() and not p.get("bot", false) and p.get("player_id", "") != "":
			var pid_str: String = p.player_id
			var fb := Ui.button("+ Ami", func():
				var res: Dictionary = await Backend.add_friend("", pid_str)
				Ui.toast(res.detail if res.has("_error") else "Demande d'ami envoyée à %s !" % nm, Ui.C_BAD if res.has("_error") else Ui.C_GOOD), 0, 16)
			h.add_child(fb)
		var rdy: bool = p.get("ready", false) or p.get("bot", false)
		h.add_child(Ui.label("PRÊT" if rdy else "…", 22, Ui.C_GOOD if rdy else Ui.C_MUTED))
		_players_box.add_child(row)

	if Net.peers.has(Net.my_id()):
		_ready_btn.set_pressed_no_signal(Net.peers[Net.my_id()].get("ready", false))
	_start_btn.visible = leader
	_start_btn.disabled = not all_ready
	_build_settings(leader)


func _build_settings(leader: bool) -> void:
	for c in _settings_box.get_children():
		c.queue_free()
	_settings_box.add_child(Ui.label("Réglages de la partie", 28, Ui.C_BORDER))
	var modes = [["coop", "Campagne coop"], ["endless", "Survie infinie coop"], ["pvp", "Arène PvP"]]
	var mo := OptionButton.new()
	for i in modes.size():
		mo.add_item(modes[i][1])
		if modes[i][0] == Net.lobby.mode or (Net.lobby.mode == "campaign" and modes[i][0] == "coop"):
			mo.select(i)
	mo.disabled = not leader
	mo.item_selected.connect(func(i): Net.set_lobby({"mode": modes[i][0]}))
	_settings_box.add_child(mo)

	match Net.lobby.mode:
		"coop", "campaign":
			_settings_box.add_child(Ui.label("Mission", 20, Ui.C_MUTED))
			var mi := OptionButton.new()
			var all = Db.all_missions()
			var idx := 0
			for m in all:
				if Profile.mission_unlocked(m.id) or not leader:
					mi.add_item("%s — %s" % [Db.zone_of_mission(m.id).name, m.name])
					mi.set_item_metadata(mi.item_count - 1, m.id)
					if m.id == Net.lobby.mission:
						idx = mi.item_count - 1
			if mi.item_count > 0:
				mi.select(idx)
			mi.disabled = not leader
			mi.item_selected.connect(func(i): Net.set_lobby({"mission": mi.get_item_metadata(i)}))
			_settings_box.add_child(mi)
			var m = Db.mission(Net.lobby.mission)
			if not m.is_empty():
				_settings_box.add_child(Ui.label("%d vagues%s" % [m.waves, (" — Boss : " + Db.enemies[m.boss].name) if m.has("boss") else ""], 18, Ui.C_GOLD))
		"endless":
			_settings_box.add_child(Ui.label("Zone", 20, Ui.C_MUTED))
			var zo := OptionButton.new()
			for i in Db.campaign.zones.size():
				zo.add_item(Db.campaign.zones[i].name)
				if Db.campaign.zones[i].id == Net.lobby.endless_zone:
					zo.select(i)
			zo.disabled = not leader
			zo.item_selected.connect(func(i): Net.set_lobby({"endless_zone": Db.campaign.zones[i].id}))
			_settings_box.add_child(zo)
		"pvp":
			_settings_box.add_child(Ui.label("Premier à 3 manches gagnées. Les places libres
sont occupées par des IA (alliées ou adverses).", 18, Ui.C_MUTED))
			var fh := Ui.hbox(8)
			fh.add_child(Ui.label("Format :", 20))
			var fo := OptionButton.new()
			for i in 4:
				fo.add_item("%d contre %d" % [i + 1, i + 1])
			fo.select(int(Net.lobby.get("team_size", 1)) - 1)
			fo.disabled = not leader
			fo.item_selected.connect(func(i): Net.set_lobby({"team_size": i + 1}))
			fh.add_child(fo)
			_settings_box.add_child(fh)
			var ah := Ui.hbox(8)
			ah.add_child(Ui.label("Niveau de l'IA :", 20))
			var ao := OptionButton.new()
			for a in Db.AI_LEVELS:
				ao.add_item(a.name)
			ao.select(int(Net.lobby.get("ai_level", 1)))
			ao.disabled = not leader
			ao.item_selected.connect(func(i): Net.set_lobby({"ai_level": i}))
			ah.add_child(ao)
			_settings_box.add_child(ah)
			var my_team: int = int(Net.peers.get(Net.my_id(), {}).get("team", 0))
			_settings_box.add_child(Ui.button("Rejoindre l'%s" % Db.TEAM_NAMES[1 - my_team], func(): Net.update_my_info({"team": 1 - my_team}), 0, 20))
	if Net.lobby.mode != "pvp":
		var dh := Ui.hbox(8)
		dh.add_child(Ui.label("Difficulté :", 20))
		var dopt := OptionButton.new()
		for d in Db.DIFFICULTIES:
			dopt.add_item(d.name)
		dopt.select(int(Net.lobby.get("difficulty", 1)))
		dopt.disabled = not leader
		dopt.item_selected.connect(func(i): Net.set_lobby({"difficulty": i}))
		dh.add_child(dopt)
		_settings_box.add_child(dh)
	if not leader:
		_settings_box.add_child(Ui.label("Seul le chef du salon peut modifier ces réglages.", 16, Ui.C_MUTED))


func _toggle_ready() -> void:
	Net.update_my_info({"ready": _ready_btn.button_pressed})


func _on_chat(from_name: String, text: String) -> void:
	if is_instance_valid(_chat_log):
		var col := "#ffd166" if from_name == "Système" else "#5ff7ff"
		_chat_log.append_text("[color=%s]%s :[/color] %s\n" % [col, from_name, text.replace("[", "(")])


func _on_disconnected(reason: String) -> void:
	Ui.toast(reason, Ui.C_BAD, 4)
	Game.goto("play")


func _leave() -> void:
	Net.close()
	Game.goto("play")


func _local_ips() -> Array:
	var out := []
	for ip in IP.get_local_addresses():
		if ip.count(".") == 3 and not ip.begins_with("127.") and not ip.begins_with("169.254"):
			out.append(ip)
	return out.slice(0, 3)
