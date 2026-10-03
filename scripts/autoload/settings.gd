extends Node
## Paramètres utilisateur (audio, vidéo, jeu, réseau), sauvegardés dans user://parametres.cfg.

signal changed
signal binds_changed
signal input_device_changed(pad: bool)

const PATH := "user://parametres.cfg"
const AUDIO_BUSES := ["Master", "Musique", "Effets", "Interface", "Dialogues"]
const BUS_LABELS := {"Master": "Volume général", "Musique": "Musique", "Effets": "Effets sonores", "Interface": "Interface", "Dialogues": "Dialogues"}

var audio := {"Master": 0.8, "Musique": 0.7, "Effets": 0.8, "Interface": 0.7, "Dialogues": 0.8}
var mute := {"Master": false, "Musique": false, "Effets": false, "Interface": false, "Dialogues": false}
var mute_unfocused := true
var fullscreen := false
var vsync := true
var screen_shake := 1.0
var damage_numbers := true
var show_fps := false
var player_name := ""
var last_ip := "127.0.0.1"
var last_port := 7777
var server_url := ""        # URL de l'API méta (battle pass, profils) — fournie plus tard
var text_speed := 1.0
var difficulty := 1      # index dans Db.DIFFICULTIES
var ai_level := 1        # index dans Db.AI_LEVELS
var team_size := 1       # arène : 1 = 1v1 … 4 = 4v4
var auto_cast := false   # lance automatiquement les sorts actifs dès qu'ils sont prêts


func _ready() -> void:
	_setup_inputs()
	load_settings()
	apply_binds()
	apply()


## Commandes : touches physiques (ZQSD sur AZERTY = WASD sur QWERTY), flèches et manette.
func _setup_inputs() -> void:
	var map := {
		"move_left": [KEY_A, KEY_LEFT, JOY_AXIS_LEFT_X, -1.0, JOY_BUTTON_DPAD_LEFT],
		"move_right": [KEY_D, KEY_RIGHT, JOY_AXIS_LEFT_X, 1.0, JOY_BUTTON_DPAD_RIGHT],
		"move_up": [KEY_W, KEY_UP, JOY_AXIS_LEFT_Y, -1.0, JOY_BUTTON_DPAD_UP],
		"move_down": [KEY_S, KEY_DOWN, JOY_AXIS_LEFT_Y, 1.0, JOY_BUTTON_DPAD_DOWN],
	}
	for action in map:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		var cfg: Array = map[action]
		var k := InputEventKey.new()
		k.physical_keycode = cfg[0]
		InputMap.action_add_event(action, k)
		var k2 := InputEventKey.new()
		k2.physical_keycode = cfg[1]
		InputMap.action_add_event(action, k2)
		var j := InputEventJoypadMotion.new()
		j.axis = cfg[2]
		j.axis_value = cfg[3]
		InputMap.action_add_event(action, j)
		var jb := InputEventJoypadButton.new()
		jb.button_index = cfg[4]
		InputMap.action_add_event(action, jb)
	# esquive et sorts actifs : configurables (voir binds / apply_binds)
	for act in BINDABLE:
		if not InputMap.has_action(act):
			InputMap.add_action(act, 0.5)
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var esc := InputEventKey.new()
		esc.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", esc)
		var start := InputEventJoypadButton.new()
		start.button_index = JOY_BUTTON_START
		InputMap.action_add_event("pause", start)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and mute_unfocused:
		_set_bus_mute("Master", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_bus_mute("Master", mute["Master"])


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		player_name = _default_name()
		return
	for b in AUDIO_BUSES:
		audio[b] = cfg.get_value("audio", b, audio[b])
		mute[b] = cfg.get_value("audio", b + "_muet", mute[b])
	mute_unfocused = cfg.get_value("audio", "muet_hors_focus", mute_unfocused)
	fullscreen = cfg.get_value("video", "plein_ecran", fullscreen)
	vsync = cfg.get_value("video", "vsync", vsync)
	screen_shake = cfg.get_value("jeu", "tremblement", screen_shake)
	damage_numbers = cfg.get_value("jeu", "chiffres_degats", damage_numbers)
	show_fps = cfg.get_value("jeu", "afficher_fps", show_fps)
	text_speed = cfg.get_value("jeu", "vitesse_texte", text_speed)
	difficulty = cfg.get_value("jeu", "difficulte", difficulty)
	ai_level = cfg.get_value("jeu", "niveau_ia", ai_level)
	team_size = cfg.get_value("jeu", "taille_equipe", team_size)
	auto_cast = cfg.get_value("jeu", "sorts_auto", auto_cast)
	player_name = cfg.get_value("reseau", "pseudo", _default_name())
	last_ip = cfg.get_value("reseau", "derniere_ip", last_ip)
	last_port = cfg.get_value("reseau", "dernier_port", last_port)
	server_url = cfg.get_value("reseau", "url_serveur", server_url)
	for act in BINDABLE:
		var v = cfg.get_value("touches", act, [])
		if v is Array and v.size() == 3:
			binds[act] = v


var sandbox := false   # outils de test : paramètres non enregistrés


func save_settings() -> void:
	if sandbox:
		return
	var cfg := ConfigFile.new()
	for b in AUDIO_BUSES:
		cfg.set_value("audio", b, audio[b])
		cfg.set_value("audio", b + "_muet", mute[b])
	cfg.set_value("audio", "muet_hors_focus", mute_unfocused)
	cfg.set_value("video", "plein_ecran", fullscreen)
	cfg.set_value("video", "vsync", vsync)
	cfg.set_value("jeu", "tremblement", screen_shake)
	cfg.set_value("jeu", "chiffres_degats", damage_numbers)
	cfg.set_value("jeu", "afficher_fps", show_fps)
	cfg.set_value("jeu", "vitesse_texte", text_speed)
	cfg.set_value("jeu", "difficulte", difficulty)
	cfg.set_value("jeu", "niveau_ia", ai_level)
	cfg.set_value("jeu", "taille_equipe", team_size)
	cfg.set_value("jeu", "sorts_auto", auto_cast)
	cfg.set_value("reseau", "pseudo", player_name)
	cfg.set_value("reseau", "derniere_ip", last_ip)
	cfg.set_value("reseau", "dernier_port", last_port)
	cfg.set_value("reseau", "url_serveur", server_url)
	for act in BINDABLE:
		cfg.set_value("touches", act, binding(act))
	cfg.save(PATH)


func apply() -> void:
	for b in AUDIO_BUSES:
		var idx = AudioServer.get_bus_index(b)
		if idx < 0:
			continue
		var v: float = clamp(audio[b], 0.0, 1.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(max(v, 0.0001)))
		AudioServer.set_bus_mute(idx, mute[b] or v <= 0.001)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	changed.emit()


func set_volume(bus: String, value: float) -> void:
	audio[bus] = value
	apply()


func set_mute(bus: String, value: bool) -> void:
	mute[bus] = value
	apply()


func _set_bus_mute(bus: String, value: bool) -> void:
	var idx = AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_mute(idx, value)


func _default_name() -> String:
	var names = ["Neon", "Octet", "Pixel", "Bidule", "Gigaoctet", "Brioche", "Turbo", "Cookie"]
	return "%s%d" % [names[randi() % names.size()], randi() % 900 + 100]


# ------------------------------------------------------------------ raccourcis configurables
## Esquive et sorts actifs : 3 emplacements par action — [principal, secondaire] (clavier ou souris) et manette.
## Codage : "key:<touche physique>", "mouse:<bouton>", "joy:<bouton>", "axis:<axe>:<sens>" ("" = aucun).
const BINDABLE := ["dash", "spell_1", "spell_2", "spell_3", "spell_4", "spell_5"]
const BIND_NAMES := {"dash": "Esquive", "spell_1": "Sort actif 1", "spell_2": "Sort actif 2", "spell_3": "Sort actif 3",
	"spell_4": "Sort actif 4", "spell_5": "Sort actif 5"}
const DEFAULT_BINDS := {
	"dash": ["key:32", "key:4194325", "joy:0"],           # Espace, Maj, A
	"spell_1": ["key:49", "key:4194439", "joy:2"],        # 1, pavé 1, X
	"spell_2": ["key:50", "key:4194440", "joy:3"],        # 2, pavé 2, Y
	"spell_3": ["key:51", "key:4194441", "joy:1"],        # 3, pavé 3, B
	"spell_4": ["key:52", "key:4194442", "joy:9"],        # 4, pavé 4, LB
	"spell_5": ["key:53", "key:4194443", "joy:10"],       # 5, pavé 5, RB
}
## Réservés : déplacements (ZQSD/WASD, flèches, croix directionnelle, stick gauche), Échap et Start (menu).
const RESERVED := ["key:65", "key:68", "key:83", "key:87", "key:4194319", "key:4194321", "key:4194320", "key:4194322",
	"key:4194305", "joy:11", "joy:12", "joy:13", "joy:14", "joy:6", "axis:0:-1", "axis:0:1", "axis:1:-1", "axis:1:1"]

var binds := {}          # action -> [principal, secondaire, manette]
var using_pad := false   # dernier périphérique utilisé : la manette (libellés des touches en jeu)


func binding(act: String) -> Array:
	return binds.get(act, DEFAULT_BINDS[act]).duplicate()


func apply_binds() -> void:
	for act in BINDABLE:
		InputMap.action_erase_events(act)
		for code in binding(act):
			var e := str_to_event(code)
			if e:
				InputMap.action_add_event(act, e)
	binds_changed.emit()


## Assigne un raccourci. Renvoie le nom de l'action qui l'utilisait (il lui est retiré), ou "".
func set_binding(act: String, slot: int, code: String) -> String:
	var taken_by := ""
	if code != "":
		for other in BINDABLE:
			var b := binding(other)
			for i in 3:
				if b[i] == code and not (other == act and i == slot):
					b[i] = ""
					binds[other] = b
					taken_by = other
	var mine := binding(act)
	mine[slot] = code
	binds[act] = mine
	apply_binds()
	return taken_by


func reset_bindings(act := "") -> void:
	if act == "":
		binds.clear()
	else:
		binds.erase(act)
	apply_binds()


static func event_to_str(e: InputEvent) -> String:
	if e is InputEventKey:
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return "key:%d" % k
	if e is InputEventMouseButton:
		return "mouse:%d" % e.button_index
	if e is InputEventJoypadButton:
		return "joy:%d" % e.button_index
	if e is InputEventJoypadMotion and absf(e.axis_value) > 0.6:
		return "axis:%d:%d" % [e.axis, 1 if e.axis_value > 0 else -1]
	return ""


static func str_to_event(code: String) -> InputEvent:
	var p := code.split(":")
	match p[0]:
		"key":
			var k := InputEventKey.new()
			k.physical_keycode = int(p[1])
			return k
		"mouse":
			var m := InputEventMouseButton.new()
			m.button_index = int(p[1])
			return m
		"joy":
			var j := InputEventJoypadButton.new()
			j.button_index = int(p[1])
			return j
		"axis":
			var a := InputEventJoypadMotion.new()
			a.axis = int(p[1])
			a.axis_value = float(p[2])
			return a
	return null


const MOUSE_NAMES := {1: "Clic gauche", 2: "Clic droit", 3: "Clic molette", 4: "Molette ↑", 5: "Molette ↓",
	8: "Souris 4", 9: "Souris 5"}
const PAD_NAMES := {0: "A", 1: "B", 2: "X", 3: "Y", 4: "Select", 5: "Guide", 6: "Start", 7: "L3", 8: "R3",
	9: "LB", 10: "RB", 11: "Croix ↑", 12: "Croix ↓", 13: "Croix ←", 14: "Croix →"}


## Libellé lisible d'un raccourci (touches selon la disposition du clavier : Z sur AZERTY…).
static func code_label(code: String) -> String:
	if code == "":
		return "—"
	var p := code.split(":")
	match p[0]:
		"key":
			if int(p[1]) >= KEY_KP_MULTIPLY and int(p[1]) <= KEY_KP_9:   # pavé numérique (indépendant du verr. num.)
				return "Pavé " + OS.get_keycode_string(int(p[1])).trim_prefix("Kp ")
			var kc := DisplayServer.keyboard_get_keycode_from_physical(int(p[1]))
			var t := OS.get_keycode_string(kc if kc != 0 else int(p[1]))
			return {"Space": "Espace", "Shift": "Maj", "Ctrl": "Ctrl", "Tab": "Tab", "Enter": "Entrée", "Backspace": "Retour"}.get(t, t)
		"mouse":
			return MOUSE_NAMES.get(int(p[1]), "Souris %s" % p[1])
		"joy":
			return PAD_NAMES.get(int(p[1]), "Bouton %s" % p[1])
		"axis":
			match int(p[1]):
				4: return "LT"
				5: return "RT"
				2: return "Stick droit " + ("→" if int(p[2]) > 0 else "←")
				3: return "Stick droit " + ("↓" if int(p[2]) > 0 else "↑")
			return "Axe %s" % p[1]
	return code


## Libellé à afficher en jeu pour une action : bouton manette si l'on joue à la manette, sinon la touche principale.
func hud_label(act: String) -> String:
	var b := binding(act)
	if using_pad and b[2] != "":
		return code_label(b[2])
	return code_label(b[0] if b[0] != "" else b[1])


func _input(event: InputEvent) -> void:
	var pad := using_pad
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		pad = false
	if pad != using_pad:
		using_pad = pad
		input_device_changed.emit(pad)
