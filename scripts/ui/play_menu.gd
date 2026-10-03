extends Control
## Écran « Multijoueur » : créer une partie sur le serveur ou rejoindre une partie ouverte
## et entraînement contre l'IA (survie, arène PvP). La campagne solo est sur l'accueil.

var _ip: LineEdit
var _port: SpinBox
var _status: Label
var _zone_opt: OptionButton
var _format: OptionButton
var _ai: OptionButton
var _diff: OptionButton
var _servers_box: VBoxContainer


func _ready() -> void:
	Ui.screen_base(self, "res://assets/backgrounds/titre.png", 0.7)
	Audio.play_music("menu")
	var root := Ui.vbox(24)
	add_child(Ui.margin(root, 50))
	root.add_child(Ui.title("Multijoueur"))

	var cols := Ui.hbox(30)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	# --- Multijoueur : un seul serveur, chaque joueur peut y créer sa partie et les autres la rejoignent
	var multi := _column(cols, "En ligne & entre amis")
	if Backend.enabled():
		multi.add_child(Ui.label("Créer une partie", 22, Ui.C_BORDER))
		var cr := Ui.hbox(8)
		var coop_b := Ui.button("Coopération", _create.bind("coop"), 0, 22)
		coop_b.tooltip_text = "Campagne ou survie à plusieurs : cristaux partagés."
		coop_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cr.add_child(coop_b)
		var pvp_b := Ui.button("Arène PvP", _create.bind("pvp"), 0, 22)
		pvp_b.tooltip_text = "Équipes contre équipes (les places vides sont tenues par l'IA)."
		pvp_b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cr.add_child(pvp_b)
		multi.add_child(cr)
		multi.add_child(Ui.label("Votre partie apparaît dans la liste ci-dessous : vos amis n'ont plus qu'à la rejoindre.", 16, Ui.C_MUTED))
		multi.add_child(Ui.spacer(10))
		var hr := Ui.hbox(8)
		hr.add_child(Ui.label("Parties ouvertes", 22, Ui.C_BORDER))
		hr.add_child(Ui.spacer())
		hr.add_child(Ui.button("↻", Backend.fetch_servers, 44, 18))
		multi.add_child(hr)
		var sc := ScrollContainer.new()
		sc.custom_minimum_size = Vector2(0, 230)
		sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		multi.add_child(sc)
		_servers_box = Ui.vbox(6)
		_servers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(_servers_box)
		_servers_box.add_child(Ui.label("Recherche…", 17, Ui.C_MUTED))
		Backend.servers_received.connect(_on_servers)
		Backend.fetch_servers()
		var t := Timer.new()
		t.wait_time = 5.0
		t.autostart = true
		t.timeout.connect(Backend.fetch_servers)
		add_child(t)
	else:
		multi.add_child(Ui.label("Aucun serveur en ligne configuré.", 17, Ui.C_MUTED))
	# Réseau local / adresse directe (repliable)
	multi.add_child(Ui.spacer(8))
	var lan := Ui.vbox(8)
	lan.visible = not Backend.enabled()
	var lan_t := Ui.button(("▾ " if lan.visible else "▸ ") + "Réseau local ou adresse directe", Callable(), 0, 17)
	lan_t.flat = true
	lan_t.pressed.connect(func():
		lan.visible = not lan.visible
		lan_t.text = ("▾ " if lan.visible else "▸ ") + "Réseau local ou adresse directe")
	multi.add_child(lan_t)
	multi.add_child(lan)
	lan.add_child(Ui.button("Héberger sur mon PC", _host, 0, 20))
	var ipr := Ui.hbox(8)
	_ip = LineEdit.new()
	_ip.placeholder_text = "Adresse IP ou nom d'hôte"
	_ip.text = Settings.last_ip
	_ip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ipr.add_child(_ip)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = Settings.last_port
	ipr.add_child(_port)
	lan.add_child(ipr)
	lan.add_child(Ui.button("Rejoindre cette adresse", _join, 0, 20))

	# --- Entraînement contre l'IA
	var solo := _column(cols, "Contre l'IA")
	var dr := Ui.hbox(8)
	dr.add_child(Ui.label("Difficulté :", 20))
	_diff = _option(Db.DIFFICULTIES.map(func(d): return d.name), Settings.difficulty)
	_diff.item_selected.connect(func(i):
		Settings.difficulty = i
		Settings.save_settings())
	_diff.tooltip_text = "
".join(Db.DIFFICULTIES.map(func(d): return "%s : %s (récompenses x%.2f)" % [d.name, d.desc, d.reward]))
	dr.add_child(_diff)
	solo.add_child(dr)
	solo.add_child(Ui.spacer(10))
	var zr := Ui.hbox(8)
	zr.add_child(Ui.label("Zone :", 20))
	_zone_opt = OptionButton.new()
	for z in Db.campaign.zones:
		_zone_opt.add_item(z.name)
	_zone_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zr.add_child(_zone_opt)
	solo.add_child(zr)
	solo.add_child(Ui.button("Survie infinie", _start_endless, 0, 26))
	solo.add_child(Ui.label("Record : vague %d" % int(Profile.data.campaign.best_endless), 17, Ui.C_GOLD))
	solo.add_child(Ui.spacer(14))
	var br := Ui.hbox(8)
	br.add_child(Ui.label("Arène :", 20))
	_format = _option(["1 contre 1", "2 contre 2", "3 contre 3", "4 contre 4"], Settings.team_size - 1)
	br.add_child(_format)
	_ai = _option(Db.AI_LEVELS.map(func(a): return a.name), Settings.ai_level)
	br.add_child(_ai)
	solo.add_child(br)
	solo.add_child(Ui.button("Arène PvP contre l'IA", _start_pvp_bots, 0, 26))
	solo.add_child(Ui.label("Vos alliés et adversaires sont pilotés par l'IA.", 17, Ui.C_MUTED))

	_status = Ui.label("", 20, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(_status)
	var back := Ui.button("Retour", func(): Game.goto("main_menu"), 260)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_child(back)

	Net.connected.connect(_on_connected)
	Net.connection_failed.connect(func(r): _status.text = r)
	Net.disconnected.connect(func(r): _status.text = r)


func _column(parent: Control, title: String) -> VBoxContainer:
	var p := Ui.panel(24)
	p.custom_minimum_size = Vector2(560, 0)
	parent.add_child(p)
	var v := Ui.vbox(10)
	p.add_child(v)
	v.add_child(Ui.title(title, 38, Ui.C_ACCENT))
	return v


func _start_endless() -> void:
	Net.start_solo("endless")
	Net.lobby.difficulty = Settings.difficulty
	Net.lobby.endless_zone = Db.campaign.zones[_zone_opt.selected].id
	Game.goto("character_select", {"then": "solo_start"})


func _start_pvp_bots() -> void:
	Net.start_solo("pvp")
	Net.lobby.mode = "pvp"
	Settings.team_size = _format.selected + 1
	Settings.ai_level = _ai.selected
	Settings.save_settings()
	Net.lobby.team_size = Settings.team_size
	Net.lobby.ai_level = Settings.ai_level
	Net.peers[1].team = 0
	Net.fill_teams()
	Game.goto("character_select", {"then": "solo_start"})


func _host() -> void:
	var err = Net.host(int(_port.value))
	if err != OK:
		_status.text = "Impossible d'héberger sur le port %d (erreur %d)." % [int(_port.value), err]
		Audio.play("erreur")
		return
	Settings.last_port = int(_port.value)
	Settings.save_settings()
	Game.goto("lobby")


func _join() -> void:
	var ip = _ip.text.strip_edges()
	if ip == "":
		_status.text = "Entrez une adresse."
		return
	Settings.last_ip = ip
	Settings.last_port = int(_port.value)
	Settings.save_settings()
	_status.text = "Connexion à %s:%d…" % [ip, int(_port.value)]
	var err = Net.join(ip, int(_port.value))
	if err != OK:
		_status.text = "Échec de la connexion (erreur %d)." % err


func _on_connected() -> void:
	Game.goto("lobby")


func _on_servers(list: Array) -> void:
	if not is_instance_valid(_servers_box):
		return
	for c in _servers_box.get_children():
		c.queue_free()
	# les parties en attente d'abord, puis les plus remplies
	list.sort_custom(func(x, y):
		if bool(x.get("in_game", false)) != bool(y.get("in_game", false)):
			return not x.get("in_game", false)
		return int(x.get("players", 0)) > int(y.get("players", 0)))
	if list.is_empty():
		_servers_box.add_child(Ui.label("Aucune partie ouverte : créez la vôtre !", 17, Ui.C_MUTED))
		return
	for s in list:
		var row := Ui.panel(8, Color(0.05, 0.03, 0.12, 0.6), Color(Ui.C_ACCENT if s.get("mode") == "pvp" else Ui.C_BORDER, 0.5))
		var h := Ui.hbox(8)
		row.add_child(h)
		var info := Ui.vbox(0)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		info.add_child(Ui.label(String(s.get("name", "Partie")), 18))
		var full: bool = int(s.get("players", 0)) >= int(s.get("max", 4))
		var state := "en cours" if s.get("in_game", false) else ("complète" if full else "en attente de joueurs")
		info.add_child(Ui.label("%s · %d/%d joueurs · %s" % ["Arène PvP" if s.get("mode") == "pvp" else "Coopération",
			int(s.get("players", 0)), int(s.get("max", 4)), state], 15, Ui.C_MUTED))
		var sv := String(s.get("version", ""))
		if sv != "" and sv != Updater.current:
			# partie d'une autre version : on propose la mise à jour plutôt qu'une connexion vouée à l'échec
			var newer := Updater.is_newer(sv, Updater.current)
			var u := Ui.button("Mettre à jour" if newer else "Ancienne version", _update_now, 0, 18)
			u.disabled = not newer
			u.tooltip_text = "Cette partie utilise la version %s (vous avez la %s)." % [sv, Updater.current]
			h.add_child(u)
		else:
			var b := Ui.button("Rejoindre", _connect_to.bind(String(s.get("host", "")), int(s.get("port", Net.DEFAULT_PORT))), 0, 18)
			b.disabled = s.get("in_game", false) or full
			h.add_child(b)
		_servers_box.add_child(row)


func _create(mode: String) -> void:
	_status.text = "Création de votre partie…"
	var res: Dictionary = await Backend.create_room(mode)
	if not is_inside_tree():
		return
	if res.has("_error") or not res.has("port"):
		_status.text = String(res.get("detail", "Impossible de créer la partie."))
		Audio.play("erreur")
		if "mise à jour" in _status.text and Updater.enabled():
			Ui.confirm("Mise à jour nécessaire", _status.text, "Mettre à jour", _update_now, "Plus tard")
		return
	_status.text = "Partie « %s » créée, connexion…" % res.get("name", "")
	await get_tree().create_timer(1.5).timeout   # le temps que l'instance démarre
	if is_inside_tree():
		_connect_to(String(res.host), int(res.port))


func _update_now() -> void:
	if not Updater.enabled():
		OS.shell_open(Backend.base_url + "/#telecharger")
		return
	Game.goto("update")


func _connect_to(host: String, port: int) -> void:
	_status.text = "Connexion à la partie…"
	var err = Net.join(host, port)
	if err != OK:
		_status.text = "Échec de la connexion (erreur %d)." % err


func _quick(mode: String) -> void:
	_status.text = "Recherche d'une partie %s…" % ("coop" if mode == "coop" else "PvP")
	var res: Dictionary = await Backend.matchmake(mode)
	if res.is_empty():
		_create(mode)
		return
	_connect_to(res.host, res.port)


func _option(items: Array, selected: int) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.select(clamp(selected, 0, items.size() - 1))
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return o
