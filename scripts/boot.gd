extends Node
## Point d'entrée : interprète la ligne de commande (serveur dédié, test auto) puis ouvre le menu.
##   Serveur dédié : Cybervor.exe --headless -- --server --port 7777 --mode coop --max 4
##   Test auto     : Cybervor.exe --headless -- --autotest


func _ready() -> void:
	var args := _parse_args(OS.get_cmdline_user_args())
	# Outils de test : la sauvegarde et les paramètres du joueur ne sont jamais modifiés.
	for tool_arg in ["preview", "trailer", "esctest", "bindtest", "spelltest", "autotest", "check"]:
		if args.has(tool_arg):
			Profile.sandbox = true
			Settings.sandbox = true
	if args.has("server") or OS.has_feature("dedicated_server"):
		Engine.max_fps = 60
		var port = int(args.get("port", Net.DEFAULT_PORT))
		var max_p = int(args.get("max", Net.MAX_PLAYERS))
		var err = Net.start_dedicated(port, max_p, String(args.get("mode", "coop")))
		if err != OK:
			printerr("[Serveur] Impossible d'ouvrir le port %d (erreur %d)" % [port, err])
			get_tree().quit(1)
			return
		if args.has("mission"):
			Net.lobby.mission = String(args.mission)
		Backend.start_heartbeat(port)
		if args.has("room"):
			Backend.watch_room()
		Game.call_deferred("goto", "server")
		return
	if args.has("check"):
		var files := []
		_collect("res://scripts", files)
		var bad := 0
		for f in files:
			var sc = load(f)
			if sc == null or not sc.can_instantiate():
				bad += 1
				printerr("ECHEC : ", f)
		print("[CHECK] %d scripts, %d en erreur" % [files.size(), bad])
		get_tree().quit(1 if bad > 0 else 0)
		return
	if args.has("preview"):
		# Captures d'écran des menus : --preview main_menu,skills --out C:/dossier
		await get_tree().process_frame
		get_tree().current_scene = null   # le Boot survit aux changements d'écran
		var out_dir := String(args.get("out", "user://captures"))
		DirAccess.make_dir_recursive_absolute(out_dir)
		for screen in String(args.preview).split(","):
			if screen == "lobby":
				Net.host(7795)
				Net.set_lobby({"mode": "pvp", "team_size": 2})
				Game.goto("lobby")
				await get_tree().create_timer(1.5).timeout
			elif screen == "social" or screen == "retour":
				Game.goto("main_menu")
				await get_tree().create_timer(0.5).timeout
				Ui.open_social("amis" if screen == "social" else "retour")
				await get_tree().create_timer(1.5).timeout
			elif screen in ["profile", "profile_cos"]:
				Game.goto("main_menu")
				await get_tree().create_timer(1.0).timeout
				Ui.open_profile(1 if screen == "profile_cos" else 0)
				await get_tree().create_timer(1.0).timeout
			elif screen in ["feedback", "feedback_detail", "feedback_similar"]:
				Game.goto("main_menu")
				await get_tree().create_timer(1.5).timeout
				Ui.open_feedback()
				await get_tree().create_timer(1.5).timeout
				if screen == "feedback_detail":
					Ui._feedback._show_detail(1)
				elif screen == "feedback_similar":
					Ui._feedback._f_title.text = "laser qui traverse"
					Ui._feedback._load_similar()
				await get_tree().create_timer(1.5).timeout
			elif screen in ["bp_claim", "bp_claim_hat"]:
				Profile.data.battlepass.xp = int(Db.battlepass.xp_per_tier) * 12
				Profile.data.battlepass.premium = true
				Game.goto("battlepass")
				await get_tree().create_timer(0.8).timeout
				var bp = get_tree().current_scene
				var tier := 1
				var track := "free"
				if screen == "bp_claim_hat":
					for t in Db.battlepass.tiers:
						if t.premium.type == "hat":
							tier = t.tier
							track = "premium"
							break
				bp._claim(tier, track)
				await get_tree().create_timer(0.55).timeout
			elif screen == "quit":
				Game.goto("main_menu")
				await get_tree().create_timer(0.5).timeout
				Ui.confirm_quit()
				await get_tree().create_timer(1.0).timeout
			elif screen == "dialogue":
				Game.goto("campaign")
				var d = load("res://scripts/ui/dialogue_box.gd").new()
				d.lines = Db.mission("z1_m1").intro
				get_tree().current_scene.add_child(d)
				await get_tree().create_timer(4.0).timeout
			elif screen == "shop" or screen == "shop_full":
				Game.autotest = true
				Game.hold_intermission = true
				Net.start_solo("campaign")
				Net.lobby.mission = "z1_m2"
				Game.server_start_session(Net.lobby.duplicate(true))
				while not (get_tree().current_scene and get_tree().current_scene.get("state") == "intermission"):
					await get_tree().process_frame
				Engine.time_scale = 1.0
				if screen == "shop_full":   # inventaire plein : la boutique doit rester utilisable (bouton Prêt visible)
					var w = get_tree().current_scene
					var rp = w.run[Net.my_id()]
					for wid in ["tesla", "orbes", "mitrailleuse", "marteau", "lance_roquettes"]:
						rp.add_weapon(wid, 1)
					for iid in Db.items.keys().slice(0, 14):
						rp.add_item(iid)
					for sid in Db.spells.trees[rp.character] + ["gen_laser", "gen_orbitale"]:
						if Db.spells.spells[sid].type == "passive" or rp.actives.size() < 5:
							rp.learn_spell(sid)
					w._broadcast_loadout(Net.my_id())
					w._send_private(Net.my_id())
				await get_tree().create_timer(1.5).timeout
			elif screen.begins_with("guide"):
				# --preview guide ou guide_<recherche>
				Game.goto("main_menu")
				await get_tree().create_timer(1.0).timeout
				Ui.open_guide()
				await get_tree().create_timer(0.5).timeout
				if screen.begins_with("guide_"):
					Ui._guide._search.text = screen.trim_prefix("guide_")
					Ui._guide._filter()
				await get_tree().create_timer(0.6).timeout
			elif screen.begins_with("map_"):
				# vue d'ensemble d'une forme d'arène : --preview map_octogone,map_croix
				ArenaMap.force_shape = screen.trim_prefix("map_")
				Game.autotest = true
				Net.start_solo("campaign")
				Net.lobby.mission = String(args.get("mission", "z1_m4"))
				Game.server_start_session(Net.lobby.duplicate(true))
				await get_tree().create_timer(6.0).timeout
				Engine.time_scale = 1.0
				var wv = get_tree().root.find_child("World", true, false)
				for n in get_tree().root.get_children():
					if n.get("map") != null:
						wv = n
				if wv:
					wv.set_process(false)
					wv.camera.position_smoothing_enabled = false
					wv.camera.limit_left = -100000
					wv.camera.limit_top = -100000
					wv.camera.limit_right = 100000
					wv.camera.limit_bottom = 100000
					wv.camera.zoom = Vector2(0.48, 0.48)
					wv.camera.position = wv.arena.get_center()
					wv.camera.offset = Vector2.ZERO
					await get_tree().create_timer(0.5).timeout
			elif screen == "game" or screen == "pvp":
				Game.autotest = true
				Net.start_solo("campaign")
				Net.lobby.mission = String(args.get("mission", "z1_m4"))
				if screen == "pvp":
					Net.lobby.mode = "pvp"
					Net.lobby.team_size = 2
					Net.fill_teams()
				Game.server_start_session(Net.lobby.duplicate(true))
				await get_tree().create_timer(float(args.get("delay", 20.0)) * 4.0).timeout
				Engine.time_scale = 1.0
			else:
				Game.goto(screen)
				await get_tree().create_timer(1.5).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out_dir + "/" + screen + ".png")
			print("[PREVIEW] ", screen)
		get_tree().quit()
		return
	if args.has("autotest") and args.has("join"):
		Game.autotest = true
		Settings.player_name = "Testeur%d" % (randi() % 1000)
		get_tree().current_scene = null
		Net.join(String(args.join), int(args.get("port", Net.DEFAULT_PORT)))
		await Net.connected
		print("[AUTOTEST] Connecté au serveur, id ", Net.my_id())
		await get_tree().create_timer(1.0).timeout
		Net.update_my_info({"ready": true})
		var expect := int(args.get("expect", 1))
		while Net.peers.size() < expect:
			await Net.lobby_changed
		await get_tree().create_timer(1.0).timeout
		if Net.is_leader():
			print("[AUTOTEST] Chef du salon : lancement de la partie")
			Net.set_lobby({"mission": String(args.get("mission", "z1_m1"))})
			await get_tree().create_timer(0.5).timeout
			Net.request_start()
		return
	if args.has("maptest"):
		_map_test()
		get_tree().quit(0 if _esc_fail == 0 else 1)
		return
	if args.has("esctest"):
		_esc_test()
		return
	if args.has("bindtest"):
		_bind_test(String(args.get("out", "")))
		return
	if args.has("spelltest"):
		_spell_test(String(args.get("out", "")))
		return
	if args.has("trailer"):
		_trailer(args)
		return
	if args.has("autotest"):
		Game.autotest = true
		Net.start_solo("campaign")
		Net.lobby.mission = String(args.get("mission", "z1_m4"))
		if args.has("pvp"):
			Net.lobby.mode = "pvp"
			Net.lobby.team_size = int(args.get("teams", 2))
			Net.lobby.ai_level = int(args.get("ai", 1))
			Net.fill_teams()
		Game.call_deferred("server_start_session", Net.lobby.duplicate(true))
		return
	# Jeu installé : mise à jour automatique au lancement (sinon directement le menu)
	if Updater.enabled():
		Game.call_deferred("goto", "update")
	else:
		Game.call_deferred("goto", "main_menu")


# ------------------------------------------------------------------ bande-annonce
## Une séquence par lancement, enregistrée avec le Movie Maker de Godot :
##   godot --path . --write-movie seq.avi --fixed-fps 30 --resolution 1920x1080 -- --trailer fight --seconds 12
const TRAILER_FIGHT := {
	"fight": {"zone": "z2", "wave": 7, "hero": "volta", "weapons": ["tesla", "orbes", "mitrailleuse", "lance_roquettes"]},
	"fight2": {"zone": "z4", "wave": 9, "hero": "brutus", "weapons": ["marteau", "lame_plasma", "lance_flammes", "shuriken"]},
	"boss": {"zone": "z3", "wave": 5, "hero": "capitaine", "weapons": ["railgun", "pompe_plasma", "orbes", "tesla", "lance_mines"]},
}


func _trailer(args: Dictionary) -> void:
	var seg := String(args.trailer)
	var secs := float(args.get("seconds", 8.0))
	await get_tree().process_frame
	get_tree().current_scene = null
	Settings.player_name = "Turbo"
	if args.has("no_music"):
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Musique"), true)
	if seg in TRAILER_FIGHT or seg == "pvp":
		var t: Dictionary = TRAILER_FIGHT.get(seg, {"zone": "z5", "wave": 1, "hero": "glitchette", "weapons": ["mitrailleuse", "tesla", "orbes"]})
		Profile.data.character = t.hero
		Game.autotest = true
		Game.trailer = {"start_wave": t.wave, "weapons": t.weapons, "tier": 2,
			"buff": {"max_hp": 400, "hp_regen": 25, "armor": 12, "damage": 25, "attack_speed": 25, "pickup": 150, "speed": 10, "projectiles": 1}}
		Net.start_solo("endless" if seg != "pvp" else "pvp")
		Net.lobby.mode = "endless" if seg != "pvp" else "pvp"
		Net.lobby.endless_zone = t.zone
		Net.lobby.difficulty = 2
		if seg == "pvp":
			Net.lobby.team_size = 4
			Net.lobby.ai_level = 2
			Net.fill_teams()
		Game.server_start_session(Net.lobby.duplicate(true))
	elif seg == "dialogue":
		Game.goto("campaign")
		await get_tree().create_timer(0.3).timeout
		var d = load("res://scripts/ui/dialogue_box.gd").new()
		d.lines = Db.mission(String(args.get("mission", "z1_m1"))).intro
		get_tree().current_scene.add_child(d)
		_advance_dialogue(d)
	elif seg == "shop":
		Game.autotest = true
		Game.hold_intermission = true
		Game.trailer = {"start_wave": 1, "weapons": ["tesla", "orbes"], "tier": 1, "buff": {"max_hp": 400, "start_data": 300}}
		Net.start_solo("campaign")
		Net.lobby.mode = "endless"
		Net.lobby.endless_zone = "z2"
		Game.server_start_session(Net.lobby.duplicate(true))
	elif seg == "social":
		Game.goto("main_menu")
		await get_tree().create_timer(0.2).timeout
		Ui.open_feedback()
	else:
		Game.goto(seg)
	_hide_bar.call_deferred()
	var cap := String(args.get("caption", ""))
	if cap != "":
		_caption(cap, String(args.get("sub", "")), args.has("top"), float(args.get("delay", 0.0)))
	await get_tree().create_timer(secs, true, false, true).timeout
	get_tree().quit()


func _advance_dialogue(d: Node) -> void:
	while is_instance_valid(d):
		await get_tree().create_timer(3.4).timeout
		if is_instance_valid(d):
			d._next()


# ------------------------------------------------------------------ test de la touche Échap
func _press_esc() -> void:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE
	e.keycode = KEY_ESCAPE
	e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	var r := e.duplicate()
	r.pressed = false
	Input.parse_input_event(r)
	for i in 3:
		await get_tree().process_frame


func _check(ok: bool, what: String) -> void:
	print("[ESCTEST] ", "OK   " if ok else "ECHEC", " ", what)
	if not ok:
		_esc_fail += 1


var _esc_fail := 0


func _esc_test() -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Game.goto("main_menu")
	await get_tree().create_timer(0.6).timeout
	await _press_esc()
	_check(Ui.modal_open() and Ui._modals.back().node is Ui.GameMenu, "menu principal : Échap ouvre le menu")
	await _press_esc()
	_check(not Ui.modal_open(), "Échap referme le menu")
	Ui.open_social("amis")
	Ui.open_settings()
	await get_tree().process_frame
	await _press_esc()
	_check(Ui.social_open() and Ui._modals.size() == 1, "modales empilées : Échap ferme seulement la plus récente (paramètres)")
	await _press_esc()
	_check(not Ui.social_open() and not Ui.modal_open(), "Échap ferme ensuite le panneau social")
	Ui.confirm_quit()
	await get_tree().process_frame
	await _press_esc()
	_check(not Ui.modal_open(), "Échap annule la confirmation « Quitter le jeu » (le jeu tourne toujours)")
	Game.goto("skills")
	await get_tree().create_timer(0.4).timeout
	await _press_esc()
	_check(Ui.modal_open(), "autre écran (compétences) : Échap ouvre le menu")
	await _press_esc()
	# --- en partie
	Game.autotest = true
	Game.trailer = {"start_wave": 1}
	Net.start_solo("campaign")
	Net.lobby.mode = "endless"
	Game.server_start_session(Net.lobby.duplicate(true))
	await get_tree().create_timer(2.0).timeout
	await _press_esc()
	_check(get_tree().paused and Ui.modal_open(), "en jeu : Échap ouvre le menu pause (jeu en pause)")
	Ui.open_feedback()
	await get_tree().process_frame
	await _press_esc()
	_check(not Ui.feedback_open() and get_tree().paused and Ui.modal_open(), "en pause : Échap ferme d'abord la fenêtre Bugs & suggestions, la pause reste")
	await _press_esc()
	_check(not get_tree().paused and not Ui.modal_open(), "Échap ferme le menu pause et reprend la partie")
	var w = get_tree().current_scene
	Game.autotest = false
	w._show_dialogue([{"who": "mamie", "text": "Test"}, {"who": "hero", "text": "Test 2"}], true)
	Game.autotest = true
	await get_tree().process_frame
	await _press_esc()
	_check(not is_instance_valid(w._dialogue) or w._dialogue.is_queued_for_deletion(), "dialogue ouvert : Échap le passe")
	_check(not Ui.modal_open() and not get_tree().paused, "… sans ouvrir le menu pause")
	print("[ESCTEST] %s" % ("TOUT EST BON" if _esc_fail == 0 else "%d échec(s)" % _esc_fail))
	get_tree().quit(_esc_fail)


func _hide_bar() -> void:
	await get_tree().process_frame
	if Ui.get("_bar"):
		Ui._bar.visible = false


func _caption(text: String, sub: String, top := false, delay := 0.0) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 120
	get_tree().root.add_child.call_deferred(layer)
	var bg := PanelContainer.new()
	bg.theme = Ui.theme
	bg.add_theme_stylebox_override("panel", Ui.box(Color(0.03, 0.01, 0.08, 0.78), Ui.C_BORDER, 3, 14))
	bg.position = Vector2(60, 150 if top else 1080 - 260)
	bg.custom_minimum_size = Vector2(1250, 0)
	layer.add_child(bg)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	bg.add_child(box)
	var t := Label.new()
	t.text = text
	t.add_theme_font_size_override("font_size", 72)
	t.add_theme_color_override("font_color", Ui.C_BORDER)
	t.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	t.add_theme_constant_override("outline_size", 12)
	box.add_child(t)
	if sub != "":
		var l := Label.new()
		l.text = sub
		l.add_theme_font_size_override("font_size", 34)
		box.add_child(l)
	bg.modulate.a = 0.0
	var tw: Tween = bg.create_tween()
	tw.tween_interval(0.4 + delay)
	tw.tween_property(bg, "modulate:a", 1.0, 0.5)


func _parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < list.size():
		var a = list[i]
		if a.begins_with("--"):
			var key := a.substr(2)
			if "=" in key:
				var kv := key.split("=", true, 1)
				out[kv[0]] = kv[1]
			elif i + 1 < list.size() and not list[i + 1].begins_with("--"):
				out[key] = list[i + 1]
				i += 1
			else:
				out[key] = true
		i += 1
	return out


func _collect(dir: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		_collect(dir + "/" + d, out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)


func _env(key: String, default: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else default


# ------------------------------------------------------------------ test des raccourcis (--bindtest [--out dossier])
func _send(e: InputEvent) -> void:
	if not e is InputEventJoypadMotion:
		e.pressed = true
	Input.parse_input_event(e)
	await get_tree().process_frame
	await get_tree().process_frame


func _release(e: InputEvent) -> void:
	var r := e.duplicate()
	if r is InputEventJoypadMotion:
		r.axis_value = 0.0
	else:
		r.pressed = false
	Input.parse_input_event(r)
	await get_tree().process_frame


func _bind_test(out: String) -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Settings.reset_bindings()
	Game.goto("main_menu")
	await get_tree().create_timer(0.5).timeout
	Ui.open_settings()
	await get_tree().create_timer(0.3).timeout
	var tab: Node = null
	for n in get_tree().root.find_children("Commandes", "", true, false):
		tab = n
	_check(tab != null, "onglet « Commandes » présent dans les paramètres")
	var tabs: TabContainer = tab.get_parent()
	tabs.current_tab = tab.get_index()
	# 1) bouton latéral de la souris sur le sort 1
	tab._start_capture("spell_1", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_XBUTTON1
	await _send(m)
	_check(Settings.binding("spell_1")[0] == "mouse:8", "souris : bouton latéral assigné au sort 1")
	await _release(m)
	# 2) gâchette droite de la manette sur le sort 2
	tab._start_capture("spell_2", 2)
	await get_tree().process_frame
	await get_tree().process_frame
	var j := InputEventJoypadMotion.new()
	j.axis = JOY_AXIS_TRIGGER_RIGHT
	j.axis_value = 1.0
	await _send(j)
	_check(Settings.binding("spell_2")[2] == "axis:5:1" and Settings.code_label("axis:5:1") == "RT", "manette : gâchette RT assignée au sort 2")
	await _release(j)
	# 3) conflit : la touche « 3 » donnée au sort 1 est retirée du sort 3
	tab._start_capture("spell_1", 1)
	await get_tree().process_frame
	await get_tree().process_frame
	var k := InputEventKey.new()
	k.physical_keycode = KEY_3
	k.keycode = KEY_3
	await _send(k)
	await _release(k)
	_check(Settings.binding("spell_1")[1] == "key:51" and Settings.binding("spell_3")[0] == "", "conflit : la touche passe au sort 1 et quitte le sort 3")
	# 4) touche réservée (déplacement) refusée, puis Échap annule sans fermer les paramètres
	tab._start_capture("dash", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var w := InputEventKey.new()
	w.physical_keycode = KEY_W
	await _send(w)
	await _release(w)
	_check(Settings.binding("dash")[0] == "key:32" and tab.capturing(), "touche de déplacement refusée")
	await _press_esc()
	_check(not tab.capturing() and Ui.modal_open(), "Échap annule la saisie sans fermer les paramètres")
	# 5) les raccourcis fonctionnent vraiment
	await _send(m)
	_check(Input.is_action_pressed("spell_1"), "le bouton latéral de la souris déclenche bien le sort 1")
	await _release(m)
	await _send(j)
	_check(Input.is_action_pressed("spell_2"), "la gâchette RT déclenche bien le sort 2")
	await _release(j)
	var a := InputEventJoypadButton.new()
	a.button_index = JOY_BUTTON_A
	await _send(a)
	_check(Settings.using_pad and Settings.hud_label("dash") == "A", "à la manette, la barre de sorts affiche les boutons (esquive : A)")
	await _release(a)
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/commandes.png")
	Settings.reset_bindings()
	_check(Settings.binding("spell_3")[0] == "key:51", "« Tout rétablir » remet les raccourcis par défaut")
	print("[ESCTEST] ", "TOUT EST BON" if _esc_fail == 0 else "%d échec(s)" % _esc_fail)
	get_tree().quit(1 if _esc_fail else 0)


# ------------------------------------------------------------------ test des sorts achetés et visés (--spelltest [--out dossier])
func _spell_test(out: String) -> void:
	await get_tree().process_frame
	get_tree().current_scene = null
	Game.hold_intermission = true
	Game.trailer = {"start_wave": 1, "weapons": ["pistolaser"], "tier": 0, "buff": {"max_hp": 2000, "hp_regen": 100}}
	Net.start_solo("endless")
	Net.lobby.mode = "endless"
	Game.server_start_session(Net.lobby.duplicate(true))
	await get_tree().create_timer(1.0).timeout
	var w = get_tree().current_scene
	var me := Net.my_id()
	var rp = w.run[me]
	# 1) la montée de niveau ne propose plus que des statistiques
	rp.roll_upgrades(w.rng, 3)
	_check(not rp.upgrade_choices.is_empty() and rp.upgrade_choices.all(func(c): return c.has("stat")), "niveau supérieur : uniquement des statistiques")
	# 2) la boutique propose des armes actives / passives du héros
	var seen := 0
	for k in 20:
		rp.roll_shop(w.rng, 3)
		seen += rp.shop.filter(func(o): return o.kind == "spell" and o.id in Db.spells.trees[rp.character]).size()
	_check(seen > 0, "la boutique propose des sorts du héros (%d en 20 boutiques)" % seen)
	# 2b) début de partie : toujours au moins une offre abordable
	var never_stuck := true
	for k in 200:
		rp.data = 12 + k % 25
		rp.roll_shop(w.rng, 2)
		if not rp.shop.any(func(o): return int(o.price) <= rp.data):
			never_stuck = false
	_check(never_stuck, "premières boutiques : toujours au moins une offre abordable (200 tirages, 12 à 36 données)")
	# 3) achat : actif -> barre de raccourcis, rachat -> rang supérieur
	rp.data = 9999
	for sid in ["pat_germe", "pat_puree", "pat_frites", "pat_germe"]:
		rp.shop = [{"kind": "spell", "id": sid, "rank": int(rp.spells.get(sid, 0)) + 1, "price": 10, "sold": false}]
		rp.buy(0)
	_check(rp.actives == ["pat_germe", "pat_puree", "pat_frites"] and rp.spells.pat_germe == 2, "achat : sorts dans la barre, rachat = rang ★2")
	_check(rp.swap_actives(0, 1) and rp.actives[0] == "pat_puree", "réorganisation de la barre")
	var refund: int = rp.sell_spell("pat_frites")
	_check(refund > 0 and not "pat_frites" in rp.actives, "revente d'un sort (+%d données)" % refund)
	w._broadcast_loadout(me)
	# 4) en vague : le sort part vers le point visé
	while w.state != "wave":
		await get_tree().process_frame
	await get_tree().create_timer(2.0).timeout
	var pos: Vector2 = w.player_pos(me)
	var aim := pos + Vector2(-320, 180)
	w.request_cast(1, aim)   # pat_germe : essaim de nanites à l'endroit visé
	await get_tree().process_frame
	var z: Array = w.spells.zones
	_check(not z.is_empty() and z.back().pos.distance_to(w.clamp_to_bounds(aim, 10)) < 2.0, "zone posée au curseur (%s)" % (str(z.back().pos) if not z.is_empty() else "aucune"))
	var far := pos + Vector2(5000, 0)
	rp.spell_cd.clear()
	w.request_cast(1, far)
	await get_tree().process_frame
	_check(w.spells.zones.back().pos.distance_to(pos) <= 652.0, "portée maximale respectée (650)")
	# dégâts : l'obus à plasma à l'endroit visé touche les ennemis qui s'y trouvent
	var e = w.enemies.nearest(pos, 900.0)
	if e:
		var hp_before: float = e.hp
		rp.spell_cd.clear()
		w.request_cast(0, e.pos)
		await get_tree().process_frame
		_check(not is_instance_valid(e) or e.hp < hp_before or e.hp <= 0, "frappe visée : l'ennemi ciblé perd %d PV" % int(hp_before - max(e.hp, 0)))
	# 5) objets actifs communs : laser (seuls les ennemis sur la ligne) et frappe orbitale (endroit exact)
	for sid in ["gen_laser", "gen_orbitale"]:
		rp.shop = [{"kind": "spell", "id": sid, "rank": 1, "price": 10, "sold": false}]
		rp.buy(0)
	_check("gen_laser" in rp.actives and "gen_orbitale" in rp.actives, "objets actifs communs achetables par tous les héros")
	var priv: Dictionary = rp.private_state(w.wave)
	_check(priv.get("sell_spells", {}).get("gen_laser", 0) > 0 and priv.get("sell_weapons", []).size() == rp.weapons.size(),
		"la boutique connaît le gain de chaque revente (laser : +%d)" % priv.get("sell_spells", {}).get("gen_laser", 0))
	w._broadcast_loadout(me)
	pos = w.player_pos(me)
	var on_line = w.enemies.spawn("brute", pos + Vector2(300, 0), 50.0, 1.0, 1, false, 0.0)
	var off_line = w.enemies.spawn("brute", pos + Vector2(300, 160), 50.0, 1.0, 1, false, 0.0)
	await get_tree().process_frame
	var hp_on: float = on_line.hp
	var hp_off: float = off_line.hp
	rp.spell_cd.clear()
	w.request_cast(rp.actives.find("gen_laser"), pos + Vector2(600, 0))
	await get_tree().process_frame
	_check(on_line.hp < hp_on and off_line.hp == hp_off, "laser : touche l'ennemi visé (-%d PV), épargne celui hors de la ligne" % int(hp_on - on_line.hp))
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/laser.png")
	var target = w.enemies.spawn("brute", pos + Vector2(-250, -200), 50.0, 1.0, 1, false, 0.0)
	await get_tree().process_frame
	var hp_t: float = target.hp
	w.request_cast(rp.actives.find("gen_orbitale"), target.pos)
	await get_tree().create_timer(0.3).timeout
	_check(target.hp == hp_t, "frappe orbitale : annoncée, pas encore tombée")
	if out != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/frappe.png")
	await get_tree().create_timer(0.8).timeout
	_check(target.hp < hp_t, "frappe orbitale : impact à l'endroit visé (-%d PV)" % int(hp_t - target.hp))
	if out != "":
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out + "/sort_vise.png")
	# 6) infobulles : la souris posée sur un sort de la barre ou sur un passif atteint bien la case
	rp.learn_spell("pat_robuste")
	w._broadcast_loadout(me)
	w._send_private(me)
	await get_tree().create_timer(0.3).timeout
	var bar_slot: Control = null
	var passive_slot: Control = null
	for c in w.hud.spell_hud._bar.get_children():
		if c is Control and c.tooltip_text != "" and not c.tooltip_text.begins_with("Esquive") and bar_slot == null and c.get_index() > 1:
			bar_slot = c
	for c in w.hud.spell_hud._passives.get_children():
		if c is Control and c.tooltip_text != "":
			passive_slot = c
	for pair in [["sort de la barre", bar_slot], ["bonus passif", passive_slot]]:
		var slot: Control = pair[1]
		if slot == null:
			_check(false, "infobulle %s : case introuvable" % pair[0])
			continue
		var mm := InputEventMouseMotion.new()
		mm.position = slot.get_global_rect().get_center()
		mm.global_position = mm.position
		get_viewport().push_input(mm, true)
		await get_tree().process_frame
		var hov := get_viewport().gui_get_hovered_control()
		var ok := hov != null and (hov == slot or slot.is_ancestor_of(hov))
		if out != "":
			await get_tree().create_timer(1.2).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(out + "/infobulle_%d.png" % passive_slot.get_instance_id() if slot == passive_slot else out + "/infobulle_barre.png")
		_check(ok and slot.tooltip_text.length() > 10, "infobulle %s : survol reçu (%s), texte « %s »" % [pair[0], hov.name if hov else "rien", slot.tooltip_text.left(40).replace("\n", " ")])
	print("[ESCTEST] ", "TOUT EST BON" if _esc_fail == 0 else "%d échec(s)" % _esc_fail)
	get_tree().quit(1 if _esc_fail else 0)


## Cartes : sur 120 graines et pour chaque forme, la zone praticable reste d'un seul tenant même pour un boss,
## aucun point n'est piégé dans le vide, et un ennemi qui poursuit contourne les failles.
func _map_test() -> void:
	var arenas := [Rect2(-1350, -860, 2700, 1720), Rect2(-1080, -690, 2160, 1380)]
	var bad_conn := 0
	var bad_resolve := 0
	var stuck := 0
	var chases := 0
	var maps := 0
	for shape in ArenaMap.SHAPES:
		for sd in 20:
			for ai in arenas.size():
				var c: Vector2 = arenas[ai].get_center()
				var m := ArenaMap.new(arenas[ai], sd * 31 + 7, {"shape": shape, "pvp": ai == 1, "clear": [[c, 340.0]]})
				maps += 1
				# connexité sur une grille, marge d'un boss (rayon 96)
				var step := 40.0
				var free := {}
				var start := Vector2i(-1, -1)
				var gx := int(arenas[ai].size.x / step)
				var gy := int(arenas[ai].size.y / step)
				for x in gx:
					for y in gy:
						var p: Vector2 = arenas[ai].position + Vector2(x + 0.5, y + 0.5) * step
						if m.is_free(p, 96.0):
							free[Vector2i(x, y)] = true
							start = Vector2i(x, y)
				var seen := {start: true}
				var todo := [start]
				while not todo.is_empty():
					var q: Vector2i = todo.pop_back()
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						var nq: Vector2i = q + d
						if free.has(nq) and not seen.has(nq):
							seen[nq] = true
							todo.append(nq)
				if seen.size() != free.size():
					bad_conn += 1
				# tout point ramené par resolve() est praticable
				var r := RandomNumberGenerator.new()
				r.seed = sd
				for k in 200:
					var p2 := Vector2(r.randf_range(-1300, 1300), r.randf_range(-900, 900))
					if not m.is_free(m.resolve(p2, 30.0), 29.0):
						bad_resolve += 1
				# poursuite : un ennemi (rayon 32) rejoint sa cible en contournant les obstacles
				for k in 6:
					var a: Vector2 = m.random_free_point(r, 60.0)
					var b: Vector2 = m.random_free_point(r, 60.0)
					var pos := a
					var t := 0.0
					while t < 40.0 and pos.distance_to(b) > 60.0:
						var dir := (b - pos).normalized()
						pos = m.resolve(pos + m.pursue(pos, b, dir, 32.0) * 200.0 / 30.0, 32.0)
						t += 1.0 / 30.0
					chases += 1
					if pos.distance_to(b) > 60.0:
						stuck += 1
						if stuck <= 5:
							print("  bloqué : ", shape, " graine ", sd * 31 + 7, " ", a, " -> ", b, " arrêté en ", pos)
	_check(bad_conn == 0, "%d cartes : zone praticable d'un seul tenant pour un boss (%d en défaut)" % [maps, bad_conn])
	_check(bad_resolve == 0, "points ramenés hors du vide (%d en défaut)" % bad_resolve)
	_check(stuck == 0, "poursuites : %d / %d bloquées derrière un obstacle" % [stuck, chases])
	print("[MAPTEST] ", "TOUT EST BON" if _esc_fail == 0 else "%d échec(s)" % _esc_fail)
