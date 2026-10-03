extends Node
## Navigation entre écrans et cycle de vie d'une session de jeu.

signal screen_changed(name: String)

const SCREENS := {
	"main_menu": "res://scripts/ui/main_menu.gd",
	"play": "res://scripts/ui/play_menu.gd",
	"character_select": "res://scripts/ui/character_select.gd",
	"campaign": "res://scripts/ui/campaign_map.gd",
	"lobby": "res://scripts/ui/lobby.gd",
	"skills": "res://scripts/ui/skill_tree.gd",
	"battlepass": "res://scripts/ui/battle_pass.gd",
	"settings": "res://scripts/ui/settings_menu.gd",
	"results": "res://scripts/ui/results.gd",
	"cosmetics": "res://scripts/ui/cosmetics.gd",
	"world": "res://scripts/world/world.gd",
	"server": "res://scripts/server_idle.gd",
	"update": "res://scripts/ui/update_screen.gd",
}

var session: Dictionary = {}
var last_results: Dictionary = {}
var params: Dictionary = {}
var autotest := false
var trailer: Dictionary = {}   # bande-annonce : {start_wave, weapons, buff} (vitesse réelle, joueur piloté par l'IA)
var hold_intermission := false   # captures : laisse la boutique ouverte en test auto
var current_screen := ""


func goto(screen: String, p: Dictionary = {}) -> void:
	params = p
	current_screen = screen
	var tree := get_tree()
	var old = tree.current_scene
	var node: Node = load(SCREENS[screen]).new()
	node.name = "World" if screen == "world" else screen.to_pascal_case()
	if old:
		old.name = "_old_scene"
		old.queue_free()
	tree.root.add_child(node)
	tree.current_scene = node
	tree.paused = false
	screen_changed.emit(screen)


# ------------------------------------------------------------------ session
## Côté serveur : lance la partie pour tous les participants du salon.
func server_start_session(cfg: Dictionary) -> void:
	cfg.players = Net.peers.duplicate(true)
	cfg.seed = randi()
	if Net.is_online():
		_begin.rpc(cfg)
	else:
		_begin(cfg)


@rpc("authority", "reliable", "call_local")
func _begin(cfg: Dictionary) -> void:
	session = cfg
	Net.in_game = true
	goto("world")


## Fin de partie : le monde appelle ceci sur chaque pair avec le résumé de partie.
func finish_session(results: Dictionary) -> void:
	last_results = results
	Net.in_game = false
	if Net.dedicated:
		goto("server")
		return
	goto("results")


## Après l'écran de résultats.
func leave_results() -> void:
	if Net.is_online():
		for id in Net.peers:
			Net.peers[id].ready = false
		goto("lobby")
	elif session.get("mode", "") == "campaign":
		goto("campaign")
	else:
		goto("main_menu")


func server_abort_to_lobby() -> void:
	Net.in_game = false
	if Net.is_online():
		_abort.rpc()
	else:
		_abort()


@rpc("authority", "reliable", "call_local")
func _abort() -> void:
	Net.in_game = false
	if Net.dedicated:
		goto("server")
	elif Net.is_online():
		goto("lobby")
	else:
		goto("main_menu")


func quit_to_menu() -> void:
	Net.close()
	goto("main_menu")
