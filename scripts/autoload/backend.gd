extends Node
## Client de l'API méta (profils, battle pass, liste des serveurs, matchmaking).
## Fonctionne hors ligne par défaut : tant qu'aucune URL n'est configurée, tout reste local.
## Configuration : res://config/online.cfg (valeurs par défaut du build) ou Paramètres > Réseau.

signal status_changed(online: bool)
signal servers_received(list: Array)
signal social_updated(info: Dictionary)   # {unread: [...], friend_requests: n}

const CONFIG_PATH := "res://config/online.cfg"
const API_PREFIX := "/api/v1"

var base_url := ""
var default_game_host := ""
var default_game_port := 7777
var token := ""
var online := false

var _sync_timer: Timer
var _busy := false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		base_url = cfg.get_value("meta", "url", "")
		default_game_host = cfg.get_value("jeu", "hote", "")
		default_game_port = cfg.get_value("jeu", "port", 7777)
	if Settings.server_url != "":
		base_url = Settings.server_url
	if OS.get_environment("CYBERVOR_CLIENT_META") != "":   # développement : API méta locale
		base_url = OS.get_environment("CYBERVOR_CLIENT_META")
	_sync_timer = Timer.new()
	_sync_timer.one_shot = true
	_sync_timer.wait_time = 3.0
	_sync_timer.timeout.connect(sync_profile)
	_load_sync_state()
	add_child(_sync_timer)
	if enabled():
		call_deferred("login")


func enabled() -> bool:
	return base_url != "" and not is_game_server()


## Serveur de jeu (export dédié ou lancé avec --server) : jamais de compte joueur, de profil ni de synchro cloud.
static func is_game_server() -> bool:
	return OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args()


func set_url(url: String) -> void:
	base_url = url.strip_edges().trim_suffix("/")
	Settings.server_url = base_url
	Settings.save_settings()
	if enabled():
		login()


func login() -> void:
	var res = await _request(HTTPClient.METHOD_POST, "/auth/guest", {"player_id": Profile.data.player_id, "name": Settings.player_name})
	if res is Dictionary and res.has("token"):
		token = res.token
		online = true
		var server_name := String(res.get("name", Settings.player_name))
		if server_name != "" and server_name != Settings.player_name:
			Ui.toast("Le pseudo « %s » est déjà pris : vous jouez sous « %s » (modifiable dans votre profil)." % [Settings.player_name, server_name], Ui.C_GOLD, 5.0)
			Settings.player_name = server_name
			Settings.save_settings()
		await sync_profile()
		_start_social_poll()
		if OS.get_environment("CYBERVOR_TEST_RESTORE") != "" and not _test_restored:   # test : récupération par code
			_test_restored = true
			print("[CLOUD] test : récupération ", JSON.stringify(await restore_save(OS.get_environment("CYBERVOR_TEST_RESTORE"))))
		flush_feedback()
	else:
		online = false
		_retry_login_later()
	status_changed.emit(online)


## Hors ligne : on retente la connexion régulièrement ; la progression faite entre-temps
## est alors fusionnée avec la sauvegarde cloud.
var _retry: Timer


func _retry_login_later() -> void:
	if _retry == null:
		_retry = Timer.new()
		_retry.one_shot = true
		_retry.timeout.connect(func():
			if not online and enabled():
				login())
		add_child(_retry)
	_retry.start(45.0)


func queue_sync() -> void:
	if online and _sync_timer:
		_sync_timer.start()


# ------------------------------------------------------------------ sauvegarde cloud
## Le profil local est fusionné avec celui du cloud (POST /profile/sync) : missions, déblocages et records
## s'additionnent, les monnaies gardent les gains faits hors ligne ET ailleurs, les choix les plus récents
## l'emportent. « base » = dernière version reçue du cloud ; « push_id » rend un renvoi sans danger.
const SYNC_PATH := "user://profil_sync.json"

signal cloud_status_changed(state: String)   # "ok", "pending", "offline", "syncing"

var cloud_state := "offline"
var last_cloud_sync := 0
var _sync_base: Dictionary = {}
var _push_id := ""
var _syncing := false
var _resync := false
var _fresh := false
var _test_restored := false   # sauvegarde restaurée : on récupère le cloud tel quel


func _load_sync_state() -> void:
	if FileAccess.file_exists(SYNC_PATH):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SYNC_PATH))
		if parsed is Dictionary:
			_sync_base = parsed.get("base", {}) if parsed.get("base") is Dictionary else {}
			_push_id = String(parsed.get("push_id", ""))
			last_cloud_sync = int(parsed.get("last", 0))
			if String(parsed.get("player_id", "")) != String(Profile.data.player_id):
				_sync_base = {}   # autre joueur (sauvegarde restaurée) : on repart sans base
				_push_id = ""


func _save_sync_state() -> void:
	if Profile.sandbox:
		return
	var f := FileAccess.open(SYNC_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"player_id": Profile.data.player_id, "base": _sync_base, "push_id": _push_id, "last": last_cloud_sync}))


func _set_cloud(state: String) -> void:
	cloud_state = state
	cloud_status_changed.emit(state)


## Vrai si des progrès locaux n'ont pas encore été envoyés au cloud.
func cloud_pending() -> bool:
	return _push_id != "" or int(Profile.data.get("updated_at", 0)) > last_cloud_sync


func sync_profile() -> void:
	if not online or Profile.sandbox:
		_set_cloud("pending" if cloud_pending() else "offline")
		return
	if _syncing:
		_resync = true
		return
	_syncing = true
	_set_cloud("syncing")
	var sent: Dictionary = {} if _fresh else Profile.data.duplicate(true)
	var edits_before := Profile.edits
	if _push_id == "":
		_push_id = Profile._uuid()
		_save_sync_state()   # mémorisé avant l'envoi : un renvoi après coupure réutilise le même identifiant
	var res = await _request(HTTPClient.METHOD_POST, "/profile/sync",
		{"profile": sent, "base": _sync_base if not _sync_base.is_empty() else null, "push_id": _push_id})
	_syncing = false
	if res is Dictionary and res.get("profile") is Dictionary and not res.has("_error"):
		var merged: Dictionary = _ints(res.profile)
		if Profile.edits == edits_before:
			Profile.apply_cloud(merged)
			_sync_base = merged
		else:
			# le joueur a progressé pendant l'envoi : on garde le local, le cloud a déjà intégré « sent »
			_sync_base = sent
			_resync = true
		_push_id = ""
		_fresh = false
		last_cloud_sync = int(merged.get("updated_at", 0))
		_save_sync_state()
		_set_cloud("ok")
		print("[CLOUD] synchronisé : %d missions, %d puces" % [Profile.data.campaign.completed.size(), int(Profile.data.puces)])
	else:
		_set_cloud("pending")
		if not online:
			_retry_login_later()
		elif _sync_timer:
			_sync_timer.start(30.0)
	if _resync:
		_resync = false
		queue_sync()


## Restaure une sauvegarde cloud sur ce PC à partir du code de sauvegarde.
func restore_save(code: String) -> Dictionary:
	if not enabled():
		return {"_error": 0, "detail": "Serveur en ligne non configuré."}
	var res = await _request(HTTPClient.METHOD_POST, "/auth/restore", {"code": code})
	if not (res is Dictionary) or res.has("_error"):
		return res if res is Dictionary else {"_error": 0, "detail": "Réponse invalide."}
	# Profil local remis à zéro : la sauvegarde cloud prime entièrement.
	var pid := String(res.player_id)
	Profile.data = Profile._default()
	Profile.data.player_id = pid
	Profile._write()
	_sync_base = {}
	_push_id = ""
	last_cloud_sync = 0
	_fresh = true
	_save_sync_state()
	Settings.player_name = String(res.get("name", Settings.player_name))
	Settings.save_settings()
	online = false
	await login()
	return {"ok": true, "name": Settings.player_name}


## Code de sauvegarde à noter pour retrouver sa progression sur un autre PC.
func save_code() -> String:
	var pid := String(Profile.data.player_id).to_upper()
	var parts := []
	for i in range(0, pid.length(), 4):
		parts.append(pid.substr(i, 4))
	return "-".join(parts)


func _ints(v):
	return Profile.ints(v)


func report_run(summary: Dictionary) -> void:
	if online:
		_request(HTTPClient.METHOD_POST, "/runs", summary)


func fetch_servers() -> void:
	if not enabled():
		servers_received.emit([])
		return
	var res = await _request(HTTPClient.METHOD_GET, "/servers")
	servers_received.emit(res.get("servers", []) if res is Dictionary else [])


## Demande au serveur méta une partie (matchmaking). Renvoie {host, port} ou {} si indisponible.
func matchmake(mode: String) -> Dictionary:
	if not enabled():
		return {}
	var res = await _request(HTTPClient.METHOD_POST, "/matchmaking", {"mode": mode, "player_id": Profile.data.player_id, "version": Updater.current})
	return res if res is Dictionary and res.has("host") else {}


## Crée une partie sur le serveur : une instance dédiée est lancée pour l'occasion.
## Renvoie {host, port, name…} ou {"_error", "detail"}.
func create_room(mode: String, room_name := "") -> Dictionary:
	if not enabled():
		return {"_error": 0, "detail": "Serveur en ligne non configuré."}
	if not online:
		return {"_error": 0, "detail": "Connexion au serveur impossible pour le moment."}
	var res = await _request(HTTPClient.METHOD_POST, "/rooms", {"mode": mode, "name": room_name, "max": Net.MAX_PLAYERS, "version": Updater.current})
	return res if res is Dictionary else {"_error": 0, "detail": "Réponse invalide."}


func _request(method: int, path: String, body = null):
	var http := HTTPRequest.new()
	http.timeout = 8.0
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var payload := "" if body == null else JSON.stringify(body)
	var err = http.request(base_url + API_PREFIX + path, headers, method, payload)
	if err != OK:
		http.queue_free()
		return {"_error": 0, "detail": "Requête impossible."}
	var result: Array = await http.request_completed
	http.queue_free()
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	if result[0] != HTTPRequest.RESULT_SUCCESS or result[1] >= 400:
		if result[1] == 401:
			online = false
			status_changed.emit(false)
		var detail := "Serveur injoignable." if result[0] != HTTPRequest.RESULT_SUCCESS else "Erreur %d" % result[1]
		var parsed = JSON.parse_string(text) if text != "" else null
		if parsed is Dictionary and parsed.has("detail") and parsed.detail is String:
			detail = parsed.detail
		return {"_error": result[1], "detail": detail}
	return JSON.parse_string(text) if text != "" else {}


# ------------------------------------------------------------------ serveur dédié
## Le serveur de jeu dédié s'annonce auprès de l'API méta (liste des serveurs, matchmaking).
## Variables d'environnement : CYBERVOR_META_URL, CYBERVOR_SERVER_SECRET, CYBERVOR_PUBLIC_HOST,
## CYBERVOR_SERVER_NAME, CYBERVOR_SERVER_ID.
var _hb_port := 7777


func start_heartbeat(port: int) -> void:
	var url := OS.get_environment("CYBERVOR_META_URL")
	if url == "":
		print("[Serveur] CYBERVOR_META_URL non défini : pas d'annonce auprès de l'API méta.")
		return
	base_url = url.trim_suffix("/")
	_hb_port = port
	var t := Timer.new()
	t.wait_time = 15.0
	t.autostart = true
	t.timeout.connect(_heartbeat)
	add_child(t)
	_heartbeat()


func _heartbeat() -> void:
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var body := {
		"id": OS.get_environment("CYBERVOR_SERVER_ID") if OS.get_environment("CYBERVOR_SERVER_ID") != "" else "srv-%d" % _hb_port,
		"name": OS.get_environment("CYBERVOR_SERVER_NAME") if OS.get_environment("CYBERVOR_SERVER_NAME") != "" else "Cybervor %d" % _hb_port,
		"host": OS.get_environment("CYBERVOR_PUBLIC_HOST"),
		"port": _hb_port,
		"mode": Net.lobby.mode,
		"players": Net.human_ids().size(),
		"max": Net.max_players,
		"in_game": Net.in_game,
		"protocol": Net.PROTOCOL,
		"owner": OS.get_environment("CYBERVOR_ROOM_OWNER"),
		"room": OS.get_environment("CYBERVOR_ROOM_OWNER") != "",
		"version": Updater.current,
	}
	var headers := PackedStringArray(["Content-Type: application/json", "X-Server-Secret: " + OS.get_environment("CYBERVOR_SERVER_SECRET")])
	http.request_completed.connect(func(_r, code, _h, _b):
		if code >= 400 or code == 0:
			printerr("[Serveur] Heartbeat refusé par l'API méta (HTTP %d)" % code)
		http.queue_free())
	http.request(base_url + API_PREFIX + "/servers/heartbeat", headers, HTTPClient.METHOD_POST, JSON.stringify(body))



## Partie créée par un joueur (lancée par server/game/rooms.py) : l'instance s'arrête d'elle-même
## si personne ne la rejoint dans les 2 minutes, ou dès qu'elle reste vide 60 secondes.
const ROOM_FIRST_JOIN := 120.0
const ROOM_EMPTY := 60.0


var _room_empty_since := 0.0
var _room_seen_player := false


func watch_room() -> void:
	var t := Timer.new()
	t.wait_time = 5.0
	t.autostart = true
	add_child(t)
	t.timeout.connect(_check_room)


func _check_room() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if not Net.human_ids().is_empty():
		_room_seen_player = true
		_room_empty_since = now
		return
	var limit := ROOM_EMPTY if _room_seen_player else ROOM_FIRST_JOIN
	if OS.get_environment("CYBERVOR_ROOM_EMPTY") != "":   # tests
		limit = float(OS.get_environment("CYBERVOR_ROOM_EMPTY"))
	if now - _room_empty_since >= limit:
		print("[Serveur] Partie vide : arrêt de l'instance.")
		get_tree().quit(0)


# ------------------------------------------------------------------ social : amis & messagerie
const FEEDBACK_DIR := "user://retours"

var my_code := ""
var social: Dictionary = {"unread": [], "friend_requests": 0}
var _poll: Timer
var _last_seen_msg := 0


func _start_social_poll() -> void:
	if _poll == null:
		_poll = Timer.new()
		_poll.wait_time = 20.0
		_poll.autostart = true
		_poll.timeout.connect(poll_social)
		add_child(_poll)
	poll_social()


func poll_social() -> void:
	if not online:
		return
	var res = await _request(HTTPClient.METHOD_GET, "/messages/unread")
	if not (res is Dictionary) or res.has("_error"):
		return
	var newest := _last_seen_msg
	for u in res.get("unread", []):
		if int(u.last) > _last_seen_msg:
			newest = max(newest, int(u.last))
			Ui.toast("Nouveau message de %s (F2 pour répondre)" % u.name, Ui.C_ACCENT, 3.5)
			Audio.play("ramasse")
	if int(res.get("friend_requests", 0)) > int(social.get("friend_requests", 0)):
		Ui.toast("Nouvelle demande d'ami ! (F2)", Ui.C_GOLD, 3.5)
	_last_seen_msg = newest
	social = res
	social_updated.emit(res)


func unread_total() -> int:
	var n := int(social.get("friend_requests", 0))
	for u in social.get("unread", []):
		n += int(u.n)
	return n


func friends() -> Dictionary:
	var res = await _request(HTTPClient.METHOD_GET, "/friends")
	if res is Dictionary and res.has("my_code"):
		my_code = res.my_code
	return res if res is Dictionary else {"_error": 0, "detail": "?"}


## Demande d'ami par code ami (« K7Q2-9XMB »), par pseudo, ou par identifiant (salon).
func add_friend(code: String, player_id := "", name := "") -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/friends/request", {"code": code, "player_id": player_id, "name": name})


## « K7Q2-9XMB » est un code ami ; tout le reste est traité comme un pseudo.
func add_friend_auto(text: String) -> Dictionary:
	var t := text.strip_edges()
	var re := RegEx.create_from_string("^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$")
	if re.search(t):
		return await add_friend(t.to_upper())
	return await add_friend("", "", t)


## Change le pseudo (unique côté serveur). Hors ligne : changement local uniquement.
func change_name(new_name: String) -> Dictionary:
	new_name = " ".join(new_name.strip_edges().split(" ", false))
	if new_name.length() < 3 or new_name.length() > 20:
		return {"_error": 422, "detail": "Le pseudo doit faire entre 3 et 20 caractères."}
	if online:
		var res: Dictionary = await _request(HTTPClient.METHOD_POST, "/me/name", {"name": new_name})
		if res.has("_error"):
			return res
		new_name = res.get("name", new_name)
	Settings.player_name = new_name
	Settings.save_settings()
	Profile.changed.emit()
	return {"name": new_name}


func accept_friend(player_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/friends/accept", {"player_id": player_id})


func remove_friend(player_id: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/friends/remove", {"player_id": player_id})


func messages(with_player: String, since := 0) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/messages?with_player=%s&since=%d" % [with_player.uri_encode(), since])


func send_message(to: String, text: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/messages", {"to": to, "text": text})


# ------------------------------------------------------------------ retours : bugs & suggestions
## Envoie un rapport de bug ou une suggestion. Hors ligne, il est mis en attente et envoyé plus tard.
func send_feedback(kind: String, text: String, context: Dictionary, title := "") -> String:
	var body := {"kind": kind, "title": title, "text": text, "context": context}
	if enabled():
		var res = await _request(HTTPClient.METHOD_POST, "/feedback", body)
		if res is Dictionary and not res.has("_error"):
			return "sent"
	DirAccess.make_dir_recursive_absolute(FEEDBACK_DIR)
	var f := FileAccess.open("%s/%d_%d.json" % [FEEDBACK_DIR, Time.get_unix_time_from_system(), randi() % 10000], FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(body, "\t"))
	return "queued"


func flush_feedback() -> void:
	if not enabled() or not DirAccess.dir_exists_absolute(FEEDBACK_DIR):
		return
	for name in DirAccess.get_files_at(FEEDBACK_DIR):
		var path := FEEDBACK_DIR + "/" + name
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			continue
		var body = JSON.parse_string(f.get_as_text())
		f = null
		if not (body is Dictionary):
			DirAccess.remove_absolute(path)
			continue
		var res = await _request(HTTPClient.METHOD_POST, "/feedback", body)
		if res is Dictionary and not res.has("_error"):
			DirAccess.remove_absolute(path)


func pending_feedback_count() -> int:
	return DirAccess.get_files_at(FEEDBACK_DIR).size() if DirAccess.dir_exists_absolute(FEEDBACK_DIR) else 0


# ------------------------------------------------------------------ retours communautaires (liste publique)
func feedback_list(query := "", kind := "", sort := "votes") -> Dictionary:
	if not enabled():
		return {"_error": 0, "detail": "Hors ligne"}
	return await _request(HTTPClient.METHOD_GET, "/feedback?q=%s&kind=%s&sort=%s&limit=60" % [query.uri_encode(), kind, sort])


func feedback_get(fid: int) -> Dictionary:
	return await _request(HTTPClient.METHOD_GET, "/feedback/%d" % fid)


func feedback_comment(fid: int, text: String) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/feedback/%d/comments" % fid, {"text": text})


func feedback_vote(fid: int) -> Dictionary:
	return await _request(HTTPClient.METHOD_POST, "/feedback/%d/vote" % fid)
