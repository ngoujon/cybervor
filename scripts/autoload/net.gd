extends Node
## Couche réseau : solo (peer hors ligne), hôte (serveur d'écoute), client, serveur dédié.
## Modèle autoritaire : le serveur (id 1) simule la partie. Les clients envoient leurs entrées
## (position) et reçoivent des instantanés compressés.

signal lobby_changed
signal connected
signal connection_failed(reason: String)
signal disconnected(reason: String)
signal chat_received(from_name: String, text: String)

const DEFAULT_PORT := 7777
const MAX_PLAYERS := 4
const PROTOCOL := "cybervor-1"

var peers: Dictionary = {}          # id -> infos joueur
var lobby: Dictionary = {"mode": "coop", "mission": "z1_m1", "endless_zone": "z1", "difficulty": 1, "team_size": 1, "ai_level": 1}
var leader_id := 1
var dedicated := false
var max_players := MAX_PLAYERS
var in_game := false
var port := DEFAULT_PORT
var _bot_counter := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_server() -> bool:
	return multiplayer.is_server()


func my_id() -> int:
	return multiplayer.get_unique_id()


func is_online() -> bool:
	return not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer) and multiplayer.multiplayer_peer != null


func is_leader() -> bool:
	return my_id() == leader_id


func local_info() -> Dictionary:
	return {
		"name": Settings.player_name,
		"player_id": Profile.data.player_id,
		"character": Profile.data.character,
		"skills": Profile.skill_stats(),
		"cosmetics": Profile.cosmetics_payload(),
		"ready": false,
		"bot": false,
		"protocol": PROTOCOL,
	}


# ------------------------------------------------------------------ démarrage
func start_solo(mode := "campaign") -> void:
	close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peers = {1: local_info()}
	leader_id = 1
	lobby.mode = mode


func host(port := DEFAULT_PORT, max_p := MAX_PLAYERS) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err = peer.create_server(port, max_p)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	max_players = max_p
	self.port = port
	peers = {1: local_info()}
	leader_id = 1
	lobby_changed.emit()
	return OK


func join(address: String, port := DEFAULT_PORT) -> Error:
	close()
	var peer := ENetMultiplayerPeer.new()
	var err = peer.create_client(address, port)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	return OK


func start_dedicated(port := DEFAULT_PORT, max_p := MAX_PLAYERS, mode := "coop") -> Error:
	close()
	dedicated = true
	var peer := ENetMultiplayerPeer.new()
	var err = peer.create_server(port, max_p)
	if err != OK:
		return err
	peer.host.compress(ENetConnection.COMPRESS_RANGE_CODER)
	multiplayer.multiplayer_peer = peer
	max_players = max_p
	self.port = port
	peers = {}
	leader_id = 0
	lobby.mode = mode
	print("[Serveur] Cybervor dédié en écoute sur le port %d (%s, %d joueurs max)" % [port, mode, max_p])
	return OK


func close() -> void:
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	peers = {}
	in_game = false


# ------------------------------------------------------------------ événements
func _on_peer_connected(id: int) -> void:
	if is_server() and in_game:
		# Partie en cours : on refuse poliment les nouveaux venus.
		_kick.rpc_id(id, "Une partie est déjà en cours sur ce serveur.")


func _on_peer_disconnected(id: int) -> void:
	if not is_server():
		return
	peers.erase(id)
	if id == leader_id:
		var ids := human_ids()
		leader_id = ids[0] if ids.size() > 0 else (1 if not dedicated else 0)
	if not in_game:
		fill_teams()
	_broadcast_lobby()
	if dedicated and human_ids().is_empty() and in_game:
		print("[Serveur] Plus aucun joueur, retour au salon.")
		Game.server_abort_to_lobby()


func _on_connected() -> void:
	_register.rpc_id(1, local_info())
	connected.emit()


func _on_connection_failed() -> void:
	close()
	connection_failed.emit("Connexion impossible. Vérifiez l'adresse et le port.")


func _on_server_disconnected() -> void:
	close()
	disconnected.emit("Le serveur s'est déconnecté.")


@rpc("any_peer", "reliable")
func _register(info: Dictionary) -> void:
	if not is_server():
		return
	var id = multiplayer.get_remote_sender_id()
	if info.get("protocol", "") != PROTOCOL:
		_kick.rpc_id(id, "Version du jeu incompatible avec le serveur.")
		return
	if human_ids().size() >= max_players:
		_kick.rpc_id(id, "Le serveur est plein.")
		return
	info.ready = false
	info.bot = false
	peers[id] = info
	if leader_id == 0:
		leader_id = id
	fill_teams()
	if dedicated:
		print("[Serveur] %s a rejoint (%d)" % [info.get("name", "?"), id])
	_broadcast_lobby()


@rpc("authority", "reliable")
func _kick(reason: String) -> void:
	close()
	disconnected.emit(reason)


func _broadcast_lobby() -> void:
	if is_online() and not multiplayer.get_peers().is_empty():
		_sync_lobby.rpc(peers, lobby, leader_id)
	lobby_changed.emit()


@rpc("authority", "reliable")
func _sync_lobby(p: Dictionary, l: Dictionary, leader: int) -> void:
	peers = p
	lobby = l
	leader_id = leader
	lobby_changed.emit()


## Le client met à jour ses infos (personnage, prêt…).
func update_my_info(changes: Dictionary) -> void:
	if is_server():
		_apply_info(my_id(), changes)
	else:
		_request_info.rpc_id(1, changes)


@rpc("any_peer", "reliable")
func _request_info(changes: Dictionary) -> void:
	if is_server():
		_apply_info(multiplayer.get_remote_sender_id(), changes)


func _apply_info(id: int, changes: Dictionary) -> void:
	if not peers.has(id):
		return
	for k in changes:
		if k in ["name", "character", "skills", "cosmetics", "ready"]:
			peers[id][k] = changes[k]
	if changes.has("team") and lobby.mode == "pvp":
		var t: int = clamp(int(changes.team), 0, 1)
		var humans_in_team := 0
		for pid in human_ids():
			if pid != id and int(peers[pid].get("team", 0)) == t:
				humans_in_team += 1
		if humans_in_team < int(lobby.team_size):
			peers[id].team = t
			fill_teams()
	_broadcast_lobby()


## Le chef du salon modifie les réglages (mode, mission, bots).
func set_lobby(changes: Dictionary) -> void:
	if is_server():
		_apply_lobby(my_id(), changes)
	else:
		_request_lobby.rpc_id(1, changes)


@rpc("any_peer", "reliable")
func _request_lobby(changes: Dictionary) -> void:
	if is_server():
		_apply_lobby(multiplayer.get_remote_sender_id(), changes)


func _apply_lobby(id: int, changes: Dictionary) -> void:
	if id != leader_id and not (id == 1 and not dedicated):
		return
	for k in changes:
		lobby[k] = changes[k]
	fill_teams()
	_broadcast_lobby()


## PvP : répartit les humains dans les 2 équipes puis complète chaque équipe avec des IA
## jusqu'au format choisi (1v1 … 4v4). Hors PvP, retire toutes les IA.
func fill_teams() -> void:
	for id in peers.keys():
		if peers[id].get("bot", false):
			peers.erase(id)
	if lobby.get("mode", "") != "pvp":
		return
	var humans := human_ids()
	var size: int = clamp(int(lobby.get("team_size", 1)), 1, 4)
	size = max(size, int(ceil(humans.size() / 2.0)))
	lobby.team_size = size
	var counts := [0, 0]
	for id in humans:
		var t: int = int(peers[id].get("team", -1))
		if t < 0 or t > 1 or counts[t] >= size:
			t = 0 if counts[0] <= counts[1] else 1
		peers[id].team = t
		counts[t] += 1
	var chars: Array = Db.characters.keys()
	var names := ["Bot-Bernard", "Bot-Josiane", "Bot-Kevin", "Bot-Gertrude", "Bot-Jean-Mich", "Bot-Huguette", "Bot-Brandon", "Bot-Micheline"]
	var n := 0
	for t in 2:
		while counts[t] < size:
			var c: String = chars[(n * 3 + 1 + t) % chars.size()]
			peers[1000 + n] = {"name": names[n % names.size()], "character": c, "skills": {}, "team": t,
				"cosmetics": {"hat": "", "color": "", "title": ""}, "ready": true, "bot": true}
			counts[t] += 1
			n += 1


func human_ids() -> Array:
	var out := []
	for id in peers:
		if not peers[id].get("bot", false):
			out.append(id)
	out.sort()
	return out


func request_start() -> void:
	if is_server():
		_try_start(my_id())
	else:
		_request_start.rpc_id(1)


@rpc("any_peer", "reliable")
func _request_start() -> void:
	if is_server():
		_try_start(multiplayer.get_remote_sender_id())


func _try_start(id: int) -> void:
	if id != leader_id and not (id == 1 and not dedicated):
		return
	if lobby.mode == "pvp":
		fill_teams()
	in_game = true
	Game.server_start_session(lobby.duplicate(true))


# ------------------------------------------------------------------ discussion
func send_chat(text: String) -> void:
	text = text.strip_edges().left(200)
	if text == "":
		return
	if is_server():
		_relay_chat(my_id(), text)
	else:
		_chat_to_server.rpc_id(1, text)


@rpc("any_peer", "reliable")
func _chat_to_server(text: String) -> void:
	if is_server():
		_relay_chat(multiplayer.get_remote_sender_id(), text.left(200))


func _relay_chat(id: int, text: String) -> void:
	var n: String = peers.get(id, {}).get("name", "???")
	if is_online():
		_chat.rpc(n, text)
	else:
		_chat(n, text)


func send_chat_system(text: String) -> void:
	if is_online():
		_chat.rpc("Système", text)
	else:
		_chat("Système", text)


@rpc("authority", "reliable", "call_local")
func _chat(from_name: String, text: String) -> void:
	chat_received.emit(from_name, text)
