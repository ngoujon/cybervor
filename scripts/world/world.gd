extends Node2D
## Arène de jeu. Le serveur simule (vagues, ennemis, combat, boutique) et diffuse des
## instantanés + événements ; tous les pairs (serveur compris) affichent le même monde.

const RunPlayer := preload("res://scripts/world/run_player.gd")
const PlayerNode := preload("res://scripts/world/player.gd")
const EnemySystem := preload("res://scripts/world/enemy_system.gd")
const ProjectileSystem := preload("res://scripts/world/projectile_system.gd")
const PickupSystem := preload("res://scripts/world/pickup_system.gd")
const FxLayer := preload("res://scripts/world/fx_layer.gd")
const Combat := preload("res://scripts/world/combat.gd")
const SpellSystem := preload("res://scripts/world/spell_system.gd")
const Hud := preload("res://scripts/world/hud.gd")
const IntermissionUi := preload("res://scripts/world/intermission_ui.gd")
const PauseMenu := preload("res://scripts/world/pause_menu.gd")
const DialogueBox := preload("res://scripts/ui/dialogue_box.gd")

const SNAP_RATE := 20.0
const PVP_WIN_ROUNDS := 3
const PVP_ROUND_TIME := 75.0
const INTERMISSION_TIMEOUT := 120.0

var cfg: Dictionary
var mode := "campaign"
var pvp := false
var mission: Dictionary = {}
var zone: Dictionary = {}
var arena := Rect2(-1350, -860, 2700, 1720)
var map: ArenaMap                   # forme de l'arène et failles (même graine partout)
var map_layer: Node2D

var state := "loading"
var wave := 0
var max_waves := 0
var wave_time := 0.0
var wave_duration := 30.0
var server_time := 0.0
var is_server := false
var headless := false

var run: Dictionary = {}            # serveur : pid -> RunPlayer
var player_nodes: Dictionary = {}   # pid -> Player
var public: Dictionary = {}         # pid -> état public (armes, stats visibles)
var snapshot_players: Dictionary = {}   # pid -> dernières infos HUD
var my_private: Dictionary = {}
var rng := RandomNumberGenerator.new()

var enemies: Node2D
var projectiles: Node2D
var pickups: Node2D
var fx: Node2D
var combat: Node
var spells: Node                     # sorts et esquives (serveur)
var my_cd: Dictionary = {}           # client : emplacement -> [fin (server_time), durée] des sorts du joueur local
var camera: Camera2D
var hud: CanvasLayer
var ui_layer: CanvasLayer
var intermission: Control
var _dialogue: Control

var _ev_u: Array = []
var _ev_r: Array = []
var _snap_acc := 0.0
var _loaded := {}
var _dialogue_done := {}
var _wait_timer := 0.0
var _spawn_acc := 0.0
var _boss_spawn_at := -1.0
var _elites_this_wave := 0
var _targets_cache: Array = []
var _shake := 0.0
var pvp_scores: Dictionary = {}
var bosses_killed := 0
var team_data := 0
var _ended := false
var _endless_boss_cycle = ["boss_serveur", "boss_reine", "boss_taupe", "boss_hydre", "boss_noyau"]


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	is_server = Net.is_server()
	cfg = Game.session
	mode = cfg.get("mode", "campaign")
	if mode == "coop":
		mode = "campaign"
	pvp = mode == "pvp"
	rng.seed = int(cfg.get("seed", 1))
	if mode == "campaign":
		mission = Db.mission(cfg.get("mission", "z1_m1"))
		if mission.is_empty():
			mission = Db.all_missions()[0]
		zone = Db.zone_of_mission(mission.id)
		max_waves = int(mission.waves)
	elif mode == "endless":
		zone = Db.zone(cfg.get("endless_zone", "z1"))
		if zone.is_empty():
			zone = Db.campaign.zones[0]
		max_waves = 0
	else:
		zone = Db.campaign.zones[1]
		arena = Rect2(-1080, -690, 2160, 1380)
		max_waves = 0
	_build_map()
	_build_scene()
	_spawn_players()
	if is_server:
		pvp_scores = {0: 0, 1: 0}
		_loaded[1] = true
		set_physics_process(true)
	else:
		_client_loaded.rpc_id(1)
	if Game.autotest:
		Engine.time_scale = 1.0 if not Game.trailer.is_empty() else 4.0
	multiplayer.peer_disconnected.connect(_on_peer_left)
	Net.disconnected.connect(_on_server_lost)


func _on_peer_left(pid: int) -> void:
	if not is_server or not run.has(pid):
		return
	var rp = run[pid]
	rp.alive = false
	rp.ready = true
	ev_r(["T", int(player_pos(pid).x), int(player_pos(pid).y - 60), "%s s'est déconnecté." % rp.name, Color("#a59fd0").to_rgba32()])
	run.erase(pid)
	var node = player_nodes.get(pid)
	if node:
		node.queue_free()
		player_nodes.erase(pid)
	if run.is_empty() or human_ids().is_empty():
		Game.server_abort_to_lobby()


func _on_server_lost(reason: String) -> void:
	Ui.toast(reason, Ui.C_BAD, 4)
	Game.goto("main_menu")


# ================================================================== construction
func _build_map() -> void:
	var c := arena.get_center()
	var opts := {"pvp": pvp, "clear": [[c, 340.0], [c + Vector2(0, -arena.size.y * 0.3), 230.0]]}
	if pvp:
		opts["pits"] = 4
		for sx in [-1.0, 1.0]:
			opts.clear.append([c + Vector2(sx * arena.size.x * 0.36, 0), 300.0])
	elif mode == "campaign" and mission.get("id", "") == "z1_m1":
		opts["shape"] = "douce"   # première mission : contour doux, peu d'obstacles
		opts["pits"] = 2
	map = ArenaMap.new(arena, int(cfg.get("seed", 1)), opts)
	if Game.autotest or headless:
		var sig := 0.0
		for b in map.blocks:
			for v in b.poly:
				sig += v.x * 0.37 + v.y * 0.61
		print("[CARTE] %s, %d obstacles, empreinte %.3f" % [map.shape, map.blocks.size(), sig])


func _build_scene() -> void:
	var ground := Sprite2D.new()
	ground.texture = Db.tex(zone.get("ground", ""))
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.modulate = Color(0.82, 0.82, 0.86)
	ground.region_enabled = true
	ground.centered = false
	var big := arena.grow(900)
	ground.region_rect = Rect2(Vector2.ZERO, big.size)
	ground.position = big.position
	ground.z_index = -100
	add_child(ground)
	if not headless:
		map_layer = Node2D.new()
		map_layer.z_index = -95
		map_layer.draw.connect(_draw_map)
		add_child(map_layer)

	pickups = PickupSystem.new()
	pickups.world = self
	pickups.z_index = -10
	add_child(pickups)
	enemies = EnemySystem.new()
	enemies.world = self
	add_child(enemies)
	projectiles = ProjectileSystem.new()
	projectiles.world = self
	projectiles.z_index = 400
	add_child(projectiles)
	fx = FxLayer.new()
	fx.world = self
	add_child(fx)
	combat = Combat.new()
	combat.world = self
	add_child(combat)
	spells = SpellSystem.new()
	spells.world = self
	add_child(spells)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	camera.limit_left = int(arena.position.x - 260)
	camera.limit_top = int(arena.position.y - 260)
	camera.limit_right = int(arena.end.x + 260)
	camera.limit_bottom = int(arena.end.y + 260)
	add_child(camera)
	camera.make_current()

	hud = Hud.new()
	hud.world = self
	add_child(hud)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 20
	add_child(ui_layer)
	intermission = IntermissionUi.new()
	intermission.world = self
	intermission.visible = false
	ui_layer.add_child(intermission)


func _draw() -> void:
	if map == null:
		draw_rect(arena, Color(Ui.C_BORDER, 0.9), false, 6)


## Contour et failles : du vide sombre bordé d'un liseré lumineux qui pulse doucement.
func _draw_map() -> void:
	var tint := Color(zone.get("tint", "#5ff7ff"))
	var pulse := 0.75 + 0.25 * sin(Time.get_ticks_msec() / 600.0)
	var o: PackedVector2Array = map.outline
	var void_col := Color(0.02, 0.01, 0.06, 0.97)
	for i in o.size():
		var a: Vector2 = o[i]
		var b: Vector2 = o[(i + 1) % o.size()]
		var fa: Vector2 = map.center + (a - map.center).normalized() * 6000.0
		var fb: Vector2 = map.center + (b - map.center).normalized() * 6000.0
		map_layer.draw_colored_polygon(PackedVector2Array([a, fa, fb, b]), void_col)
	var ring := o.duplicate()
	ring.append(o[0])
	map_layer.draw_polyline(ring, Color(tint, 0.16 * pulse), 26)
	map_layer.draw_polyline(ring, Color(0, 0, 0, 0.85), 14)
	map_layer.draw_polyline(ring, Color(Ui.C_BORDER.lerp(tint, 0.3), 0.95), 5)
	for b in map.blocks:
		var poly: PackedVector2Array = b.poly
		var closed := poly.duplicate()
		closed.append(poly[0])
		# faille : halo, fond, profondeur (contours rétrécis de plus en plus sombres)
		map_layer.draw_polyline(closed, Color(tint, 0.18 * pulse), 22)
		map_layer.draw_colored_polygon(poly, Color(0.01, 0.0, 0.035, 0.97))
		for k in 3:
			var inner := Geometry2D.offset_polygon(poly, -10.0 - k * 14.0)
			if inner.is_empty():
				break
			var ip: PackedVector2Array = inner[0]
			ip.append(ip[0])
			map_layer.draw_polyline(ip, Color(tint, (0.22 - k * 0.07) * pulse), 2)
		map_layer.draw_polyline(closed, Color(0, 0, 0, 0.9), 8)
		map_layer.draw_polyline(closed, Color(tint, 0.9 * pulse), 3)


func _spawn_players() -> void:
	var players: Dictionary = cfg.get("players", {})
	var ids = players.keys()
	ids.sort()
	var i := 0
	for pid in ids:
		var info: Dictionary = players[pid]
		var p := PlayerNode.new()
		p.world = self
		p.pid = pid
		p.name = "P%d" % pid
		p.display_name = info.get("name", "?")
		p.character = info.get("character", "patatron")
		p.cosmetics = info.get("cosmetics", {})
		p.is_local = pid == Net.my_id()
		p.server_controlled = info.get("bot", false) or (p.is_local and Game.autotest)
		p.position = _start_pos(i, ids.size(), pid)
		add_child(p)
		player_nodes[pid] = p
		if is_server:
			var rp := RunPlayer.new()
			rp.setup(info, pid)
			if rp.bot and pvp:
				rp.apply_ai_level(Db.AI_LEVELS[clamp(int(cfg.get("ai_level", 1)), 0, Db.AI_LEVELS.size() - 1)])
			if not Game.trailer.is_empty():
				for wid in Game.trailer.get("weapons", []):
					rp.add_weapon(wid, int(Game.trailer.get("tier", 1)))
				rp.upgrades = Game.trailer.get("buff", {}).duplicate()
				rp.recompute()
				rp.hp = rp.max_hp()
			run[pid] = rp
			p.speed = rp.move_speed()
			p.max_hp = rp.max_hp()
			p.hp = rp.hp
		i += 1
	var me = player_nodes.get(Net.my_id())
	if me:
		camera.position = me.position


func _start_pos(i: int, n: int, pid := 0) -> Vector2:
	if pvp:
		# Équipe 0 à gauche, équipe 1 à droite, membres répartis verticalement.
		var t := team_of(pid)
		var mates := []
		for id in _sorted_ids():
			if team_of(id) == t:
				mates.append(id)
		var k := mates.find(pid)
		var y: float = arena.get_center().y + (k - (mates.size() - 1) / 2.0) * 170.0
		var x: float = arena.get_center().x + (-1.0 if t == 0 else 1.0) * arena.size.x * 0.36
		return map.resolve(Vector2(x, y), PlayerNode.RADIUS) if map else Vector2(x, y)
	if n <= 1:
		return arena.get_center()
	var r: float = min(arena.size.x, arena.size.y) * (0.36 if pvp else 0.12)
	return arena.get_center() + Vector2.from_angle(TAU * i / n + PI / 4) * r


# ================================================================== utilitaires
func _sorted_ids() -> Array:
	var ids: Array = cfg.get("players", {}).keys()
	ids.sort()
	return ids


func team_of(pid: int) -> int:
	if is_server and run.has(pid):
		return run[pid].team
	return int(cfg.get("players", {}).get(pid, {}).get("team", 0))


## Vrai si a et b sont adversaires (PvP par équipes). Hors PvP, les joueurs sont alliés.
func is_foe(a: int, b: int) -> bool:
	return pvp and a != b and team_of(a) != team_of(b)


func difficulty() -> Dictionary:
	return Db.DIFFICULTIES[clamp(int(cfg.get("difficulty", 1)), 0, Db.DIFFICULTIES.size() - 1)]


## Ramène un point dans la zone praticable : dans l'arène et hors du vide (coins découpés, failles).
func clamp_to_arena(p: Vector2, margin := 0.0) -> Vector2:
	if map:
		return map.resolve(p, margin)
	return clamp_to_bounds(p, margin)


## Seulement le rectangle de l'arène (visée des sorts : on peut viser au-dessus d'une faille).
func clamp_to_bounds(p: Vector2, margin := 0.0) -> Vector2:
	return Vector2(clamp(p.x, arena.position.x + margin, arena.end.x - margin), clamp(p.y, arena.position.y + margin, arena.end.y - margin))


func in_arena(p: Vector2, margin := 0.0) -> bool:
	return arena.grow(-margin).has_point(p)


func player_pos(pid: int) -> Vector2:
	var p = player_nodes.get(pid)
	if p == null:
		return Vector2.INF
	if is_server and not (p.is_local or p.server_controlled):
		return p.target_pos
	return p.position


func alive_targets() -> Array:
	return _targets_cache


func _refresh_targets() -> void:
	_targets_cache = []
	for pid in run:
		if run[pid].alive:
			_targets_cache.append([pid, player_pos(pid)])


func stat_of(pid: int, key: String) -> float:
	if is_server and run.has(pid):
		return run[pid].stats.get(key, 0.0)
	return public.get(pid, {}).get("vis", {}).get(key, 0.0)


func human_ids() -> Array:
	var out := []
	var players: Dictionary = cfg.get("players", {})
	for pid in players:
		if players[pid].get("bot", false):
			continue
		if pid == Net.my_id() or Net.peers.has(pid):
			out.append(pid)
	return out


func ev_u(e: Array) -> void:
	_ev_u.append(e)


func ev_r(e: Array) -> void:
	_ev_r.append(e)


func add_shake(a: float) -> void:
	_shake = min(_shake + a * Settings.screen_shake, 30.0)


func spawn_enemy(type: String, pos: Vector2, elite := false, delay := 0.8):
	var n: int = max(1, run.size())
	var diff: float = float(mission.get("difficulty", 1.0)) if mode == "campaign" else (0.6 if pvp else 1.0 + wave * 0.06)
	var d := difficulty()
	var hp_mult: float = diff * (1.0 + 0.45 * (n - 1)) * float(d.hp)
	if Db.enemies[type].get("boss", false):
		hp_mult = diff * (1.0 + 0.7 * (n - 1)) * float(d.hp)
	return enemies.spawn(type, pos, hp_mult, sqrt(diff) * float(d.dmg), wave, elite, delay)


# ================================================================== boucle serveur
func _physics_process(delta: float) -> void:
	if not is_server:
		server_time += delta
		projectiles.client_update(delta)
		pickups.client_update(delta)
		return
	match state:
		"loading":
			_wait_timer += delta
			var all := true
			for pid in human_ids():
				if not _loaded.has(pid):
					all = false
			if all or _wait_timer > 15.0:
				_begin_run()
		"intro":
			_wait_timer += delta
			if _wait_timer > 120.0 or _all_humans_in(_dialogue_done):
				_start_wave(int(Game.trailer.get("start_wave", 1)))
		"wave":
			server_time += delta
			wave_time += delta
			_refresh_targets()
			_bots_ai(delta)
			combat.update(delta)
			spells.update(delta)
			_refresh_targets()
			enemies.server_update(delta)
			projectiles.server_update(delta)
			pickups.server_update(delta)
			_director(delta)
			_check_wave_end()
		"intermission":
			_wait_timer += delta
			_bots_intermission()
			if _all_ready() or (Net.is_online() and _wait_timer > INTERMISSION_TIMEOUT):
				_start_wave(wave + 1)
	enemies.sync_views_from_server()
	_flush(delta)


func _all_humans_in(d: Dictionary) -> bool:
	for pid in human_ids():
		if not d.has(pid):
			return false
	return true


func _all_ready() -> bool:
	for pid in run:
		if not run[pid].ready:
			return false
	return true


func _flush(delta: float) -> void:
	if not _ev_r.is_empty():
		var r = _ev_r
		_ev_r = []
		_events_r_local(r)
		if Net.is_online():
			_events_r.rpc(r)
	if not _ev_u.is_empty():
		var u = _ev_u
		_ev_u = []
		_events_u_local(u)
		if Net.is_online():
			_events_u.rpc(u)
	_snap_acc += delta
	if _snap_acc >= 1.0 / SNAP_RATE:
		_snap_acc = 0.0
		var players := []
		for pid in run:
			var rp = run[pid]
			var pp := player_pos(pid)
			players.append([pid, int(pp.x), int(pp.y), rp.hp, rp.max_hp(), rp.alive, rp.level, rp.xp / rp.xp_to_next(), rp.data, rp.move_speed()])
			var node = player_nodes.get(pid)
			if node:
				node.hp = rp.hp
				node.max_hp = rp.max_hp()
				node.alive = rp.alive
				node.speed = rp.move_speed()
		_apply_players(players)
		if Net.is_online():
			_snap.rpc(server_time, wave_time, players, enemies.pack())


# ================================================================== réseau : clients -> serveur
@rpc("any_peer", "reliable")
func _client_loaded() -> void:
	_loaded[multiplayer.get_remote_sender_id()] = true


@rpc("any_peer", "unreliable_ordered")
func _input_state(pos: Vector2, _dash: bool, aim := Vector2.RIGHT) -> void:
	var pid = multiplayer.get_remote_sender_id()
	var node = player_nodes.get(pid)
	var rp = run.get(pid)
	if node == null or rp == null:
		return
	node.target_pos = clamp_to_arena(pos, PlayerNode.RADIUS)
	if aim.is_finite() and aim.length() > 0.1:
		rp.aim_dir = aim.normalized()


func send_input(pos: Vector2, dash: bool, aim := Vector2.RIGHT) -> void:
	if not is_server:
		_input_state.rpc_id(1, pos, dash, aim)
	elif run.has(Net.my_id()) and aim.length() > 0.1:
		run[Net.my_id()].aim_dir = aim.normalized()


# ------------------------------------------------------------------ sorts et esquive (client -> serveur)
## Esquive (Espace) : `from` = position de départ, `to` = arrivée visée.
func send_dodge(pid: int, from: Vector2, to: Vector2) -> void:
	if is_server:
		spells.dodge(pid, from, clamp_to_arena(to, PlayerNode.RADIUS))
	else:
		_dodge_req.rpc_id(1, from, to)


@rpc("any_peer", "reliable")
func _dodge_req(from: Vector2, to: Vector2) -> void:
	var pid := multiplayer.get_remote_sender_id()
	var node = player_nodes.get(pid)
	if node == null or not run.has(pid):
		return
	if from.distance_to(node.target_pos) > 250:   # garde-fou : on part de la dernière position connue
		from = node.target_pos
	var dist: float = float(Db.spells.dodges.get(run[pid].character, {}).get("dist", 260))
	if from.distance_to(to) > dist + 60:
		to = from + (to - from).normalized() * dist
	spells.dodge(pid, from, clamp_to_arena(to, PlayerNode.RADIUS))


## Lance l'actif de l'emplacement `slot` (0 à 4).
## Lance un sort actif vers `aim` (position visée dans le monde ; Vector2.INF = ennemi le plus proche).
func request_cast(slot: int, aim := Vector2.INF) -> void:
	if is_server:
		spells.cast(Net.my_id(), slot, aim)
	else:
		_cast_req.rpc_id(1, slot, aim)


@rpc("any_peer", "reliable")
func _cast_req(slot: int, aim: Vector2 = Vector2.INF) -> void:
	spells.cast(multiplayer.get_remote_sender_id(), slot, aim)


func spell_ready(slot: int) -> bool:
	return server_time >= float(my_cd.get(slot, [0.0, 0.0])[0])


## Effet visuel d'esquive pour tous les pairs (saut, blink, traînée…).
func on_dodge_visual(pid: int, kind: String, from: Vector2, to: Vector2, col: Color) -> void:
	var node = player_nodes.get(pid)
	if node:
		node.dodge_visual(kind, from, to, col)


## Requête d'un joueur (boutique, améliorations, prêt, dialogue terminé).
func request(action: String, arg = 0) -> void:
	if is_server:
		_handle_request(Net.my_id(), action, arg)
	else:
		_req.rpc_id(1, action, arg)


@rpc("any_peer", "reliable")
func _req(action: String, arg) -> void:
	_handle_request(multiplayer.get_remote_sender_id(), action, arg)


func _handle_request(pid: int, action: String, arg) -> void:
	if action == "dialogue_done":
		_dialogue_done[pid] = true
		return
	var rp = run.get(pid)
	if rp == null or state != "intermission":
		return
	var err := ""
	var loadout_changed := false
	match action:
		"upgrade":
			if rp.choose_upgrade(int(arg)):
				if rp.pending_levels > 0:
					rp.roll_upgrades(rng, wave)
				loadout_changed = true
		"buy":
			err = rp.buy(int(arg))
			loadout_changed = err == ""
			if err == "":
				_send_fx_to(pid, "achat")
		"reroll":
			var price: int = rp.reroll_price(wave)
			if rp.data >= price:
				rp.data -= price
				if rp.free_rerolls_left > 0:
					rp.free_rerolls_left -= 1
				else:
					rp.shop_rerolls += 1
				rp.roll_shop(rng, wave)
				_send_fx_to(pid, "reroll")
			else:
				err = "Pas assez de données pour relancer."
		"sell_spell":
			var gain: int = rp.sell_spell(String(arg))
			if gain > 0:
				loadout_changed = true
				_send_fx_to(pid, "vente")
				_toast_to(pid, "Sort revendu : +%d données" % gain)
			else:
				err = "Sort introuvable."
		"swap_spell":
			if arg is Array and arg.size() == 2 and rp.swap_actives(int(arg[0]), int(arg[1])):
				loadout_changed = true
		"sell":
			var wgain: int = rp.sell_weapon(int(arg))
			if wgain > 0:
				loadout_changed = true
				_send_fx_to(pid, "vente")
				_toast_to(pid, "Arme revendue : +%d données" % wgain)
			else:
				err = "Impossible de vendre votre dernière arme."
		"merge":
			if rp.merge_weapon(int(arg)):
				loadout_changed = true
				_send_fx_to(pid, "niveau")
			else:
				err = "Il faut deux armes identiques de même rang (max IV)."
		"ready":
			rp.ready = bool(arg) and rp.pending_levels == 0
	if loadout_changed:
		_broadcast_loadout(pid)
	_send_private(pid, err)


func _toast_to(pid: int, text: String) -> void:
	if pid == Net.my_id():
		Ui.toast(text, Ui.C_GOLD)
	elif Net.is_online() and not run[pid].bot:
		_toast_rpc.rpc_id(pid, text)


@rpc("authority", "reliable")
func _toast_rpc(text: String) -> void:
	Ui.toast(text, Ui.C_GOLD)


func _send_fx_to(pid: int, sfx: String) -> void:
	if pid == Net.my_id():
		Audio.play(sfx)
	elif Net.is_online() and not run[pid].bot:
		_play_sfx.rpc_id(pid, sfx)


@rpc("authority", "reliable")
func _play_sfx(sfx: String) -> void:
	Audio.play(sfx)


# ================================================================== réseau : serveur -> clients
func _bcast_call(method: String, args: Array) -> void:
	callv(method, args)
	if Net.is_online():
		callv("rpc", [StringName(method)] + args)


@rpc("authority", "reliable")
func _events_r(arr: Array) -> void:
	_events_r_local(arr)


func _events_r_local(arr: Array) -> void:
	for e in arr:
		match e[0]:
			"U", "u":
				if not is_server:
					pickups.client_event(e)
			"CLR":
				if not is_server:
					projectiles.list.clear()
			"TP":
				var node = player_nodes.get(e[1])
				if node:
					node.position = Vector2(e[2], e[3])
					node.target_pos = node.position
			_:
				fx.handle(e)


@rpc("authority", "unreliable_ordered")
func _events_u(arr: Array) -> void:
	_events_u_local(arr)


func _events_u_local(arr: Array) -> void:
	for e in arr:
		if e[0] == "P" or e[0] == "X":
			if not is_server:
				projectiles.client_event(e)
		else:
			fx.handle(e)


@rpc("authority", "unreliable_ordered")
func _snap(t: float, wt: float, players: Array, enemy_data: PackedInt32Array) -> void:
	if abs(server_time - t) > 0.25:
		server_time = t
	else:
		server_time = lerp(server_time, t, 0.1)
	wave_time = wt
	_apply_players(players)
	enemies.apply_snapshot(enemy_data)


func _apply_players(players: Array) -> void:
	for p in players:
		var pid: int = p[0]
		snapshot_players[pid] = {"hp": p[3], "max_hp": p[4], "alive": p[5], "level": p[6], "xp": p[7], "data": p[8]}
		var node = player_nodes.get(pid)
		if node == null:
			continue
		if not is_server:
			node.hp = p[3]
			node.max_hp = p[4]
			node.alive = p[5]
			node.speed = p[9]
			if not node.is_local:
				node.target_pos = Vector2(p[1], p[2])


func _broadcast_loadout(pid: int) -> void:
	var st: Dictionary = run[pid].public_state()
	st["vis"] = {"projectiles": run[pid].stats.projectiles, "range": run[pid].stats.range, "dash": run[pid].stats.get("dash", 0)}
	_bcast_call("_loadout", [pid, st])


@rpc("authority", "reliable")
func _loadout(pid: int, st: Dictionary) -> void:
	public[pid] = st
	var node = player_nodes.get(pid)
	if node:
		node.set_loadout(st)
	if hud:
		hud.refresh_loadout()


func _send_private(pid: int, err := "") -> void:
	var rp = run.get(pid)
	if rp == null or rp.bot:
		return
	var data: Dictionary = rp.private_state(wave)
	data["error"] = err
	data["waiting"] = _waiting_names()
	if pid == Net.my_id():
		_private(data)
	elif Net.is_online():
		_private.rpc_id(pid, data)
	# mettre à jour la liste d'attente des autres joueurs
	if action_ready_changed(rp):
		for other in run:
			if other != pid and not run[other].bot:
				var d2: Dictionary = run[other].private_state(wave)
				d2["error"] = ""
				d2["waiting"] = _waiting_names()
				if other == Net.my_id():
					_private(d2)
				elif Net.is_online():
					_private.rpc_id(other, d2)


func action_ready_changed(_rp) -> bool:
	return run.size() > 1


func _waiting_names() -> Array:
	var out := []
	for pid in run:
		if not run[pid].ready:
			out.append(run[pid].name)
	return out


@rpc("authority", "reliable")
func _private(data: Dictionary) -> void:
	my_private = data
	if Game.autotest and not is_server and state == "intermission" and not data.get("ready", false):
		if int(data.get("pending", 0)) > 0 and not data.get("choices", []).is_empty():
			request("upgrade", 0)
		else:
			request("ready", true)
	if intermission.visible:
		intermission.refresh(data)
	if data.get("error", "") != "":
		Audio.play("erreur")
		Ui.toast(data.error, Ui.C_BAD)


@rpc("authority", "reliable")
func _set_state(s: String, w: int, mw: int, dur: float, extra: Dictionary) -> void:
	state = s
	wave = w
	max_waves = mw
	wave_duration = dur
	wave_time = 0.0
	if s == "wave":
		intermission.visible = false
		Audio.play("vague_debut", -3)
		if extra.get("boss_wave", false):
			hud.banner("VAGUE FINALE", "Un boss approche…", Ui.C_ACCENT)
		elif pvp:
			hud.banner("MANCHE %d" % w, "Que le meilleur gagne !", Ui.C_GOLD)
		else:
			hud.banner("VAGUE %d" % w, "", Ui.C_BORDER)
		_music_for_wave(extra.get("boss_wave", false))
		if extra.has("teleport"):
			pass
	elif s == "intermission":
		Audio.play("vague_fin", -3)
		Audio.play_music("boutique")
		intermission.visible = not headless and (not Game.autotest or Game.hold_intermission)
		if extra.has("round_winner"):
			hud.banner("MANCHE GAGNÉE PAR", extra.round_winner, Ui.C_GOLD)
		if extra.has("scores"):
			pvp_scores = extra.scores
	hud.on_state(s)


func _music_for_wave(boss_wave: bool) -> void:
	if pvp:
		Audio.play_music("pvp")
	elif not boss_wave:
		Audio.play_music(zone.get("music", "zone1"))


@rpc("authority", "reliable")
func _show_dialogue(lines: Array, blocking: bool) -> void:
	if headless or Game.autotest:
		if blocking:
			request("dialogue_done")
		return
	if is_instance_valid(_dialogue):
		_dialogue.queue_free()
	var d := DialogueBox.new()
	d.lines = lines
	d.auto = not blocking
	var me: Dictionary = cfg.players.get(Net.my_id(), {})
	d.hero_id = me.get("character", "patatron")
	d.hero_name = Db.characters.get(d.hero_id, {}).get("name", "")
	ui_layer.add_child(d)
	_dialogue = d
	if blocking:
		d.finished.connect(func(): request("dialogue_done"))


@rpc("authority", "reliable")
func _boss_music() -> void:
	Audio.play_music("boss", 0.6)
	Audio.play("boss")
	add_shake(14)


@rpc("authority", "reliable")
func _run_finished(results: Dictionary) -> void:
	_ended = true
	state = "ended"
	var win: bool = results.get("victory", false) or results.get("pvp_win", false)
	hud.banner("VICTOIRE !" if win else ("FIN DU MATCH" if pvp else "DÉFAITE…"), "", Ui.C_GOOD if win else Ui.C_ACCENT)
	if Game.autotest:
		print("[AUTOTEST] Fin de partie : ", JSON.stringify(results))
		Engine.time_scale = 1.0
		get_tree().quit(0 if results.get("waves", 0) > 0 else 1)
		return
	await get_tree().create_timer(2.5).timeout
	Game.finish_session(results)


# ================================================================== déroulement (serveur)
func _begin_run() -> void:
	for pid in run:
		_broadcast_loadout(pid)
	if mode == "campaign" and mission.has("intro") and not Net.dedicated:
		state = "intro"
		_wait_timer = 0.0
		_bcast_call("_set_state", ["intro", 0, max_waves, 0.0, {}])
		_bcast_call("_show_dialogue", [mission.intro, true])
		for pid in run:
			if run[pid].bot:
				_dialogue_done[pid] = true
	else:
		_start_wave(int(Game.trailer.get("start_wave", 1)))


func _start_wave(n: int) -> void:
	wave = n
	wave_time = 0.0
	_spawn_acc = 0.0
	_elites_this_wave = 0
	_boss_spawn_at = -1.0
	var boss_wave := false
	if pvp:
		wave_duration = PVP_ROUND_TIME
	else:
		wave_duration = min(20.0 + 5.0 * (n - 1), 60.0)
		if mode == "campaign" and n == max_waves and mission.has("boss"):
			boss_wave = true
		if mode == "endless" and n % 5 == 0:
			boss_wave = true
	if boss_wave:
		_boss_spawn_at = 2.5
	var ids = run.keys()
	ids.sort()
	for i in ids.size():
		var rp = run[ids[i]]
		rp.ready = false
		rp.shield_left = int(rp.stats.get("shield", 0))
		rp.invuln = 1.0
		if pvp or not rp.alive:
			rp.alive = true
		rp.hp = rp.max_hp()
		for w in rp.weapons:
			w.cd = 0.4
		if pvp:
			var sp = _start_pos(i, ids.size(), ids[i])
			ev_r(["TP", ids[i], int(sp.x), int(sp.y)])
			player_nodes[ids[i]].position = sp
			player_nodes[ids[i]].target_pos = sp
	state = "wave"
	_bcast_call("_set_state", ["wave", wave, max_waves, wave_duration, {"boss_wave": boss_wave}])


func _director(delta: float) -> void:
	if _boss_spawn_at > 0 and wave_time >= _boss_spawn_at:
		_boss_spawn_at = -1.0
		_spawn_boss()
	var n: int = max(1, run.size())
	if pvp:
		_spawn_acc += delta
		if _spawn_acc > 2.2 and enemies.list.size() < 30:
			_spawn_acc = 0.0
			for i in 2:
				spawn_enemy(["bugzy", "spammer"][rng.randi() % 2], _random_spawn_pos())
		return
	_spawn_acc += delta
	var interval: float = max(0.35, 1.55 - wave * 0.075) / (1.0 + 0.4 * (n - 1)) / float(difficulty().spawn)
	if enemies.boss_alive():
		interval *= 1.8
	if _spawn_acc < interval:
		return
	_spawn_acc = 0.0
	var group := 1 + int(wave / 3.0) + rng.randi() % 2
	var pool := _pool()
	var center := _random_spawn_pos()
	for i in group:
		var type := _pick_weighted(pool)
		var elite := wave >= 5 and _elites_this_wave < 1 + wave / 6 and rng.randf() < 0.012 * wave
		if elite:
			_elites_this_wave += 1
		spawn_enemy(type, clamp_to_arena(center + Vector2(rng.randf_range(-70, 70), rng.randf_range(-70, 70)), 30), elite)


func _pool() -> Array:
	var out := []
	if mode == "campaign":
		for p in mission.pool:
			if wave >= int(p[2]):
				out.append([p[0], float(p[1])])
	else:
		var unlocks = [["bugzy", 10, 1], ["spammer", 6, 1], ["kamikaze", 4, 2], ["sniper", 4, 3], ["brute", 3, 4], ["trojan", 3, 5],
			["dasher", 4, 6], ["phantom", 4, 7], ["healer", 2, 8], ["turret", 2, 9]]
		for u in unlocks:
			if wave >= u[2]:
				out.append([u[0], float(u[1])])
	return out


func _pick_weighted(pool: Array) -> String:
	var total := 0.0
	for p in pool:
		total += p[1]
	var r := rng.randf() * total
	for p in pool:
		r -= p[1]
		if r <= 0:
			return p[0]
	return pool[0][0]


func _random_spawn_pos() -> Vector2:
	for attempt in 12:
		var p := map.random_free_point(rng, 90.0)
		var ok := true
		for t in _targets_cache:
			if p.distance_squared_to(t[1]) < 380 * 380:
				ok = false
				break
		if ok:
			return p
	return map.random_free_point(rng, 90.0)


func _spawn_boss() -> void:
	var boss_id: String
	if mode == "campaign":
		boss_id = mission.boss
		if mission.has("boss_intro"):
			_bcast_call("_show_dialogue", [mission.boss_intro, false])
	else:
		boss_id = _endless_boss_cycle[(wave / 5 - 1) % _endless_boss_cycle.size()]
	var pos = arena.get_center() + Vector2(0, -arena.size.y * 0.3)
	spawn_enemy(boss_id, pos, false, 1.5)
	_bcast_call("_boss_music", [])


func _check_wave_end() -> void:
	# défaite / fin de manche
	var alive := 0
	for pid in run:
		if run[pid].alive:
			alive += 1
	if pvp:
		var teams_alive := {}
		for pid in run:
			if run[pid].alive:
				teams_alive[run[pid].team] = true
		if teams_alive.size() <= 1:
			_end_pvp_round()
		elif wave_time >= wave_duration:
			_end_pvp_round()
		return
	if alive == 0:
		_end_run(false)
		return
	var boss_wave = (mode == "campaign" and wave == max_waves and mission.has("boss")) or (mode == "endless" and wave % 5 == 0)
	if boss_wave:
		if _boss_spawn_at < 0 and not enemies.boss_alive() and wave_time > 5.0:
			_end_wave()
	elif wave_time >= wave_duration:
		_end_wave()


func _clear_field() -> void:
	spells.clear_all()
	for e in enemies.list.duplicate():
		e.no_drop = true
		combat.kill_enemy(e, 0)
	projectiles.clear_all()
	ev_r(["CLR"])


func _end_wave() -> void:
	_clear_field()
	pickups.vacuum()
	for pid in run:
		var rp = run[pid]
		rp.data += int(rp.stats.get("harvest", 0))
		rp.data_collected += int(rp.stats.get("harvest", 0))
	if mode == "campaign" and wave >= max_waves:
		_end_run(true)
		return
	_enter_intermission({})


func _enter_intermission(extra: Dictionary) -> void:
	state = "intermission"
	_wait_timer = 0.0
	for pid in run:
		var rp = run[pid]
		rp.ready = false
		rp.free_rerolls_left = int(rp.stats.get("free_reroll", 0))
		rp.shop_rerolls = 0
		if rp.pending_levels > 0:
			rp.roll_upgrades(rng, wave)
		rp.roll_shop(rng, wave + 1)
	_bcast_call("_set_state", ["intermission", wave, max_waves, 0.0, extra])
	for pid in run:
		_send_private(pid)


func _end_pvp_round() -> void:
	# Équipe gagnante : la seule encore debout, sinon (temps écoulé) la meilleure moyenne de PV.
	var ratio := {0: 0.0, 1: 0.0}
	var count := {0: 0, 1: 0}
	for pid in run:
		var rp = run[pid]
		count[rp.team] += 1
		if rp.alive:
			ratio[rp.team] += rp.hp / rp.max_hp()
	var r0: float = ratio[0] / max(1, count[0])
	var r1: float = ratio[1] / max(1, count[1])
	var winner := -1
	if r0 > r1:
		winner = 0
	elif r1 > r0:
		winner = 1
	var winner_name := "personne (égalité)"
	if winner >= 0:
		pvp_scores[winner] = int(pvp_scores.get(winner, 0)) + 1
		winner_name = Db.TEAM_NAMES[winner]
		for pid in run:
			if run[pid].team == winner:
				run[pid].pvp_rounds_won += 1
	_clear_field()
	pickups.vacuum()
	if winner >= 0 and pvp_scores[winner] >= PVP_WIN_ROUNDS:
		_end_run(false, winner)
		return
	_enter_intermission({"round_winner": winner_name, "scores": pvp_scores.duplicate()})


func _end_run(victory: bool, pvp_winner := -1) -> void:
	if state == "ended":
		return
	state = "ended"
	_clear_field()
	var coop := human_ids().size() > 1
	var waves_survived := wave if victory or pvp else wave - 1
	for pid in run:
		var rp = run[pid]
		if rp.bot:
			continue
		var res := {
			"mode": mode, "mission": mission.get("id", ""), "zone": zone.get("id", ""),
			"victory": victory, "waves": max(0, waves_survived), "kills": rp.kills, "bosses": bosses_killed,
			"data": rp.data_collected, "levels": rp.levels_gained, "damage_dealt": rp.damage_dealt, "spells": rp.spells, "casts": rp.casts, "dodges": rp.dodges,
			"purchases": rp.purchases, "coop": coop, "pvp_rounds": rp.pvp_rounds_won,
			"pvp_win": pvp and pvp_winner == rp.team, "pvp_winner_name": Db.TEAM_NAMES[pvp_winner] if pvp_winner >= 0 else "",
			"difficulty": int(cfg.get("difficulty", 1)), "reward_mult": 1.0 if pvp else float(difficulty().reward),
			"team_size": int(cfg.get("team_size", 1)), "ai_level": int(cfg.get("ai_level", 1)),
			"character": rp.character, "player_id": cfg.players.get(pid, {}).get("player_id", ""),
		}
		if pid == Net.my_id():
			_run_finished(res)
		elif Net.is_online():
			_run_finished.rpc_id(pid, res)
	if Net.dedicated:
		await get_tree().create_timer(3.0).timeout
		Game.finish_session({})


# ================================================================== événements de jeu (serveur)
func on_enemy_killed(e, _owner: int) -> void:
	if e.boss:
		bosses_killed += 1
		ev_r(["T", int(e.pos.x), int(e.pos.y - 100), "BOSS VAINCU !", Color("#ffd166").to_rgba32()])
		combat.shake(20)


func on_pickup(type: String, value: int, pid: int) -> void:
	var rp = run.get(pid)
	if rp == null:
		return
	match type:
		"data":
			# Coop / campagne : les cristaux sont partagés (chacun reçoit la valeur, avec son propre bonus
			# de gain de données). PvP : seul le joueur qui ramasse en profite.
			var receivers: Array = [pid] if pvp else run.keys()
			for r in receivers:
				var rr = run[r]
				var gain = int(round(value * (1.0 + rr.stats.get("data_gain", 0.0) / 100.0)))
				rr.data += gain
				rr.data_collected += gain
				if r == pid:
					team_data += gain
			ev_u(["A", "ramasse", int(player_pos(pid).x), int(player_pos(pid).y)])
			for r in receivers:
				var gained: int = run[r].add_xp(value)
				if gained > 0:
					var pp := player_pos(r)
					ev_u(["LV", int(pp.x), int(pp.y)])
					ev_u(["A", "niveau", int(pp.x), int(pp.y)])
		"soin":
			rp.hp = min(rp.max_hp(), rp.hp + 5 + rp.max_hp() * 0.1)
			ev_u(["A", "soin", int(player_pos(pid).x), int(player_pos(pid).y)])
			ev_u(["H", int(player_pos(pid).x), int(player_pos(pid).y), 50.0])
		"coffre":
			var r = rp.roll_rarity(rng, wave + 3)
			var cands := []
			for iid in Db.items:
				if int(Db.items[iid].rarity) == r:
					cands.append(iid)
			if cands.is_empty():
				cands = Db.items.keys()
			var item: String = cands[rng.randi() % cands.size()]
			rp.add_item(item)
			_broadcast_loadout(pid)
			var pp2 := player_pos(pid)
			ev_r(["T", int(pp2.x), int(pp2.y - 80), "Coffre : " + Db.items[item].name, Db.RARITY_COLORS[r].to_rgba32()])
			ev_u(["A", "achat", int(pp2.x), int(pp2.y)])


func on_player_died(pid: int, attacker: int) -> void:
	var pp := player_pos(pid)
	ev_r(["T", int(pp.x), int(pp.y - 60), "%s est hors service !" % run[pid].name, Color("#ff4d6d").to_rgba32()])
	ev_u(["A", "mort_joueur", int(pp.x), int(pp.y)])
	if pvp and run.has(attacker):
		ev_r(["T", int(pp.x), int(pp.y - 100), "Éliminé par " + run[attacker].name, Color("#ffd166").to_rgba32()])


func on_player_hurt_visual(pid: int, _amount: int) -> void:
	var node = player_nodes.get(pid)
	if node:
		node.hurt_flash = 0.25
	if pid == Net.my_id():
		Audio.play("degat_joueur", -2)
		add_shake(6)
		hud.hurt()


func fx_heal_ring(pos: Vector2, r: float) -> void:
	ev_u(["H", int(pos.x), int(pos.y), r])


func fx_blink(pos: Vector2) -> void:
	ev_u(["B", int(pos.x), int(pos.y)])


# ================================================================== bots
func _bots_ai(delta: float) -> void:
	for pid in run:
		var node = player_nodes[pid]
		if not node.server_controlled or not run[pid].alive:
			continue
		var pos: Vector2 = node.position
		var dir := Vector2.ZERO
		var danger := false
		for e in enemies.query(pos, 280):
			var away: Vector2 = pos - e.pos
			var d: float = max(away.length(), 1.0)
			dir += away / d * (280.0 - d) / 280.0 * (2.0 if e.boss else 1.0)
			if d < 160:
				danger = true
		var skill: float = 1.0
		if pvp and run[pid].bot:
			skill = float(Db.AI_LEVELS[clamp(int(cfg.get("ai_level", 1)), 0, 3)].dodge_skill)
		for p in projectiles.list:
			var hostile: bool = p.kind == ProjectileSystem.Kind.ENEMY or (p.owner != 0 and is_foe(pid, p.owner))
			if hostile and p.pos.distance_squared_to(pos) < 130 * 130:
				# s'écarter perpendiculairement à la trajectoire
				var side: Vector2 = p.vel.normalized().orthogonal()
				if side.dot(pos - p.pos) < 0:
					side = -side
				dir += side * 0.9 * skill
				danger = true
		if pvp:
			var ideal: float = 300.0
			if not run[pid].weapons.is_empty():
				ideal = clamp(run[pid].weapon_range(run[pid].weapons[0]) * 0.75, 110.0, 420.0)
			for t in _targets_cache:
				if t[0] == pid:
					continue
				var to: Vector2 = t[1] - pos
				var dist = to.length()
				if not is_foe(pid, t[0]):
					if dist > 380:
						dir += to.normalized() * 0.3   # rester groupé avec ses alliés
					continue
				if dist < ideal - 60:
					dir -= to.normalized() * skill
				elif dist > ideal + 80:
					dir += to.normalized() * 0.7
				else:
					dir += to.normalized().orthogonal() * 0.5 * (1 if pid % 2 == 0 else -1)
		if not danger:
			var best_d := 500.0 * 500.0
			var best := Vector2.INF
			for pk in pickups.list:
				var d2: float = pk.pos.distance_squared_to(pos)
				if d2 < best_d:
					best_d = d2
					best = pk.pos
			if best != Vector2.INF:
				dir += (best - pos).normalized() * 0.8
		# éviter les bords
		var c := arena.get_center()
		var edge := Vector2(
			(pos.x - c.x) / (arena.size.x / 2.0),
			(pos.y - c.y) / (arena.size.y / 2.0))
		if abs(edge.x) > 0.75 or abs(edge.y) > 0.75:
			dir += (c - pos).normalized() * 1.2
		dir += Vector2.from_angle(server_time * 0.7 + pid) * 0.15
		var mdir: Vector2 = dir.normalized() if dir.length() > 0.05 else Vector2.ZERO
		if danger and run[pid].dodge_cd <= 0 and rng.randf() < 0.04 * skill and mdir != Vector2.ZERO:
			node.start_dodge(mdir)
		mdir = map.steer(pos, mdir, PlayerNode.RADIUS)
		# l'IA n'a pas de curseur : elle vise la cible la plus proche (sinon sa direction de marche)
		var tgt: Dictionary = combat._find_target(pid, pos, 750.0)
		if not tgt.is_empty() and tgt.pos != pos:
			run[pid].aim_dir = (tgt.pos - pos).normalized()
		elif mdir != Vector2.ZERO:
			run[pid].aim_dir = mdir
		node.move_by_ai(mdir, delta)
		spells.auto_cast(pid)


func _bots_intermission() -> void:
	for pid in run:
		var rp = run[pid]
		var node = player_nodes[pid]
		if rp.ready or not node.server_controlled or (Game.hold_intermission and pid == Net.my_id()):
			continue
		while rp.pending_levels > 0:
			if rp.upgrade_choices.is_empty():
				rp.roll_upgrades(rng, wave)
			rp.choose_upgrade(rng.randi() % rp.upgrade_choices.size())
			if rp.pending_levels > 0:
				rp.roll_upgrades(rng, wave)
		for i in rp.shop.size():
			var o: Dictionary = rp.shop[i]
			if not o.sold and rp.data >= o.price and rng.randf() < 0.7:
				rp.buy(i)
		for i in rp.weapons.size():
			if rp.merge_weapon(i):
				break
		_broadcast_loadout(pid)
		rp.ready = true
		if not rp.bot:
			_send_private(pid)


# ================================================================== rendu / caméra / pause
func _process(delta: float) -> void:
	if headless:
		return
	var me = player_nodes.get(Net.my_id())
	var follow: Vector2 = me.position if me else arena.get_center()
	if me and not me.alive and not pvp:
		for pid in player_nodes:
			if snapshot_players.get(pid, {}).get("alive", false):
				follow = player_nodes[pid].position
				break
	camera.position = follow
	_shake = max(0.0, _shake - delta * 40.0)
	camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	queue_redraw()
	if map_layer:
		map_layer.queue_redraw()


## Appelé par Ui quand Échap est pressé sans modale ouverte.
func open_pause_menu() -> void:
	if state == "ended" or _ended:
		return
	var pm := PauseMenu.new()
	pm.world = self
	ui_layer.add_child(pm)


func quit_run() -> void:
	if Net.is_online() and is_server and not Net.dedicated:
		Game.server_abort_to_lobby()
		Net.close()
		Game.goto("main_menu")
	elif Net.is_online():
		Net.close()
		Game.goto("main_menu")
	else:
		Game.goto("campaign" if mode == "campaign" else "main_menu")
