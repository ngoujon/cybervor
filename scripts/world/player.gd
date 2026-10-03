extends Node2D
## Personnage d'un joueur. Le pair propriétaire le déplace ; les autres interpolent.
## Les PV, armes, etc. sont fournis par le serveur.

const RADIUS := 26.0
const TIER_COLORS := [Color("#d9d9d9"), Color("#4cc9f0"), Color("#c77dff"), Color("#ff4d6d")]
const DRONE_RADIUS := 64.0
const DRONE_SPIN := 1.1


## Position (relative au héros) du drone qui porte l'arme n° i sur n. Même formule côté serveur
## (les tirs partent du drone) et côté client (affichage).
static func drone_offset(i: int, n: int, t: float) -> Vector2:
	var a: float = t * DRONE_SPIN + TAU * i / maxi(n, 1)
	return Vector2(cos(a) * DRONE_RADIUS, sin(a) * DRONE_RADIUS * 0.75 - 26.0)

var world: Node
var pid := 0
var is_local := false
var server_controlled := false    # bots (et joueur en test auto)
var display_name := ""
var character := "patatron"
var cosmetics := {}

var hp := 20.0
var max_hp := 20.0
var alive := true
var speed := 310.0
var has_dash := false
var drones := 0
var weapons: Array = []           # [[id, tier]]

var target_pos := Vector2.ZERO
var velocity := Vector2.ZERO
var facing := 1.0
var hurt_flash := 0.0
var dash_time := 0.0
var dash_cd := 0.0
var dash_dir := Vector2.ZERO
var dash_pending := false
var dash_speed := 1000.0
var dodge_kind := ""         # esquive en cours (rendu) : dash, blink, jump, phase, rocket, grapple
var dodge_t := 0.0
var dodge_dur := 0.0
var dodge_col := Color.WHITE
var _ghosts: Array = []      # images rémanentes {pos, t}
var _cast_acc := 0.0
var _walk := 0.0
var _send_acc := 0.0

var _body: Sprite2D
var _hat: Sprite2D
var _name: Label
var _weapon_sprites: Array = []
var _drone_tex: Texture2D
var _carrier_tex: Texture2D   # drone porteur d'arme
var _headless := false


func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	target_pos = position
	if _headless:
		return
	_body = Sprite2D.new()
	var ch: Dictionary = Db.characters.get(character, Db.characters.patatron)
	_body.texture = Db.tex(ch.sprite)
	if _body.texture:
		_body.scale = Vector2.ONE * (96.0 / _body.texture.get_width())
	_body.position = Vector2(0, -24)
	add_child(_body)
	var hat_id: String = cosmetics.get("hat", "")
	if hat_id != "":
		_hat = Sprite2D.new()
		_hat.texture = Db.tex(Db.battlepass.hats.get(hat_id, {}).get("sprite", ""))
		if _hat.texture:
			_hat.scale = Vector2.ONE * (52.0 / _hat.texture.get_width())
		_hat.position = Vector2(0, -78)
		add_child(_hat)
	var name_col: Color = Ui.C_BORDER if is_local else Ui.C_TEXT
	if world.pvp:
		name_col = Db.TEAM_COLORS[world.team_of(pid)]
	_name = Ui.label(display_name, 18, name_col, HORIZONTAL_ALIGNMENT_CENTER)
	_name.position = Vector2(-100, -118)
	_name.custom_minimum_size = Vector2(200, 0)
	_name.visible = not is_local
	add_child(_name)
	_drone_tex = Db.tex("res://assets/sprites/items/mini_drone.png")
	_carrier_tex = Db.tex("res://assets/sprites/ui/drone_arme.png")
	if _carrier_tex == null:
		_carrier_tex = _drone_tex


func set_loadout(state: Dictionary) -> void:
	weapons = state.get("weapons", [])
	has_dash = true
	drones = state.get("drones", 0)
	if _headless:
		return
	for s in _weapon_sprites:
		s.queue_free()
	_weapon_sprites.clear()
	for w in weapons:
		var def: Dictionary = Db.weapons.get(w[0], {})
		if def.is_empty() or def.kind == "orbit":
			continue
		var s := Sprite2D.new()   # le drone porteur
		s.texture = _carrier_tex
		if s.texture:
			s.scale = Vector2.ONE * (46.0 / s.texture.get_width())
		s.set_meta("tier", w[1])
		var gun := Sprite2D.new()   # l'arme, accrochée sous le drone
		gun.texture = Db.tex(def.icon)
		if gun.texture:
			gun.scale = Vector2.ONE * (34.0 / gun.texture.get_width()) / max(s.scale.x, 0.001)
		gun.position = Vector2(0, 0.42 * (s.texture.get_height() if s.texture else 40.0))
		s.add_child(gun)
		add_child(s)
		_weapon_sprites.append(s)


func _physics_process(delta: float) -> void:
	dash_cd = max(0.0, dash_cd - delta)
	if is_local and not server_controlled:
		_local_move(delta)
	elif server_controlled and Net.is_server():
		pass   # déplacé par l'IA du monde (bots)
	else:
		if position.distance_squared_to(target_pos) > 160000:
			position = target_pos
		else:
			position = position.lerp(target_pos, min(1.0, delta * 15.0))


func _local_move(delta: float) -> void:
	if not alive or world.state != "wave":
		velocity = Vector2.ZERO
		return
	var input = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var typing := get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit
	if typing:
		input = Vector2.ZERO
	if dash_time > 0:
		dash_time -= delta
		velocity = dash_dir * dash_speed
	else:
		velocity = input * speed
		if not typing and dash_cd <= 0 and Input.is_action_just_pressed("dash"):
			start_dodge(input if input != Vector2.ZERO else Vector2(facing, 0))
	if not typing:
		_spell_input(delta)
	position = world.clamp_to_arena(position + velocity * delta, RADIUS)
	_send_acc += delta
	if _send_acc >= 1.0 / 30.0:
		_send_acc = 0.0
		world.send_input(position, dash_pending)
		dash_pending = false


func move_by_ai(dir: Vector2, delta: float) -> void:
	if dash_time > 0:
		dash_time -= delta
		velocity = dash_dir * dash_speed
	else:
		velocity = dir * speed
	position = world.clamp_to_arena(position + velocity * delta, RADIUS)
	target_pos = position


# ------------------------------------------------------------------ esquive (Espace) et sorts (1 à 5)
func dodge_def() -> Dictionary:
	return Db.spells.dodges.get(character, Db.spells.dodges.patatron)


func dodge_cooldown() -> float:
	return float(dodge_def().cd) * pow(0.7, world.stat_of(pid, "dash"))


## Déclenche l'esquive propre au héros. Appelée par le joueur local ou par l'IA (serveur).
func start_dodge(dir: Vector2) -> void:
	if not alive or world.state != "wave" or dash_cd > 0:
		return
	var def := dodge_def()
	dir = dir.normalized()
	var from := position
	var dist := float(def.dist)
	dash_cd = dodge_cooldown()
	dash_dir = dir
	if def.kind == "blink":
		position = world.clamp_to_arena(position + dir * dist, RADIUS)
		target_pos = position
		dash_time = 0.0
	else:
		dash_time = float(def.time)
		dash_speed = dist / float(def.time)
	world.send_dodge(pid, from, position if def.kind == "blink" else from + dir * dist)
	if is_local:
		Audio.play("dash", -4)


func _spell_input(delta: float) -> void:
	for i in 5:
		if Input.is_action_just_pressed("spell_%d" % (i + 1)):
			world.request_cast(i, aim_point())
	if Settings.auto_cast:
		_cast_acc += delta
		if _cast_acc >= 0.3:
			_cast_acc = 0.0
			var actives: Array = world.public.get(pid, {}).get("actives", [])
			for i in actives.size():
				if world.spell_ready(i):
					world.request_cast(i, Vector2.INF)   # lancement automatique : visée de l'ennemi le plus proche
					break


## Point visé par les sorts actifs : le curseur de la souris ; à la manette, la direction du stick droit
## (sinon Vector2.INF : le serveur vise l'ennemi le plus proche).
const AIM_STICK_RANGE := 420.0


func aim_point() -> Vector2:
	if Settings.using_pad:
		var stick := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down") if InputMap.has_action("aim_left") \
			else Vector2(Input.get_joy_axis(0, JOY_AXIS_RIGHT_X), Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y))
		if stick.length() > 0.3:
			return position + stick.normalized() * AIM_STICK_RANGE
		return Vector2.INF
	return get_global_mouse_position()


## Rendu de l'esquive (tous les pairs, via l'événement serveur « DG »).
func dodge_visual(kind: String, from: Vector2, to: Vector2, col: Color) -> void:
	dodge_kind = kind
	dodge_col = col
	dodge_t = 0.0
	dodge_dur = float(dodge_def().get("time", 0.25)) if kind != "blink" else 0.3
	if kind == "blink":
		_ghosts.append({"pos": from - position, "t": 0.0, "abs": from})


func _process(delta: float) -> void:
	if _headless:
		return
	hurt_flash = max(0.0, hurt_flash - delta)
	var self_driven := (is_local and not server_controlled) or (server_controlled and Net.is_server())
	var moving: bool = velocity.length_squared() > 100 if self_driven else position.distance_squared_to(target_pos) > 4
	var vx: float = velocity.x if self_driven else target_pos.x - position.x
	if abs(vx) > 0.5:
		facing = sign(vx)
	if moving:
		_walk += delta * 14.0
	else:
		_walk = lerp(_walk, round(_walk / PI) * PI, min(1.0, delta * 8.0))
	var bob = abs(sin(_walk)) * 0.08
	var base_scale := 96.0 / _body.texture.get_width() if _body.texture else 1.0
	_body.scale = Vector2(base_scale * (1.0 + bob * 0.4) * facing, base_scale * (1.0 - bob * 0.3 + sin(Time.get_ticks_msec() / 300.0) * 0.015))
	_body.rotation = sin(_walk) * 0.08 if moving else 0.0
	var col := Ui.color_of_cosmetic(cosmetics.get("color", ""))
	if not alive:
		col = Color(0.6, 0.6, 1.0, 0.35)
	elif hurt_flash > 0:
		col = Color(2.0, 0.6, 0.6)
	elif dodge_kind == "phase" and dodge_t < dodge_dur:
		col = Color(1.4, 1.0, 2.0, 0.35)
	elif dodge_t < dodge_dur:
		col = Color(1.5, 1.5, 1.8, 0.85)
	_body.modulate = col
	# esquive : arc de saut et images rémanentes
	var jump := 0.0
	if dodge_t < dodge_dur:
		dodge_t += delta
		if dodge_kind == "jump":
			jump = sin(PI * clamp(dodge_t / dodge_dur, 0.0, 1.0)) * 70.0
		if dodge_kind != "blink" and _ghosts.size() < 12 and int(dodge_t * 60) % 2 == 0:
			_ghosts.append({"abs": position, "t": 0.0})
	for g in _ghosts:
		g.t += delta
	_ghosts = _ghosts.filter(func(g): return g.t < 0.3)
	_body.position = Vector2(0, -24 - jump)
	if _hat:
		_hat.position = Vector2(4 * facing, -78 - bob * 60 - jump)
		_hat.modulate = Color(1, 1, 1, col.a)
		_hat.flip_h = facing < 0
	# drones porteurs d'armes en orbite (les tirs partent d'eux)
	var n = _weapon_sprites.size()
	var tnow = Time.get_ticks_msec() / 1000.0
	for i in n:
		var s: Sprite2D = _weapon_sprites[i]
		s.position = drone_offset(i, n, world.server_time) + Vector2(0, sin(tnow * 5.0 + i) * 3)
		s.z_index = 1 if s.position.y > -26 else -1   # devant / derrière le héros selon l'orbite
		s.rotation = sin(tnow * 3.0 + i) * 0.08
		s.modulate.a = 0.4 if not alive else 1.0
	z_index = int(position.y / 10.0)
	queue_redraw()


func _draw() -> void:
	# images rémanentes de l'esquive
	if _body and _body.texture:
		for g in _ghosts:
			var gp: Vector2 = g.abs - position
			var ts: Vector2 = _body.texture.get_size() * _body.scale.abs()
			draw_texture_rect(_body.texture, Rect2(gp + Vector2(0, -24) - ts / 2, ts), false, Color(dodge_col, 0.45 * (1.0 - g.t / 0.3)))
	var jumping := dodge_kind == "jump" and dodge_t < dodge_dur
	var shadow_k := 1.0 - 0.45 * sin(PI * clamp(dodge_t / max(dodge_dur, 0.01), 0.0, 1.0)) if jumping else 1.0
	draw_set_transform(Vector2(0, 14), 0, Vector2(shadow_k, 0.4 * shadow_k))
	draw_circle(Vector2.ZERO, 34, Color(0, 0, 0, 0.3))
	if world.pvp:
		draw_arc(Vector2.ZERO, 38, 0, TAU, 32, Color(Db.TEAM_COLORS[world.team_of(pid)], 0.8), 5)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	for s in _weapon_sprites:
		var tier: int = s.get_meta("tier", 0)
		# halo de rang + petite flamme de réacteur sous le drone
		if tier > 0:
			draw_circle(s.position, 26, Color(TIER_COLORS[tier], 0.3))
		draw_circle(s.position + Vector2(0, 24), 5 + sin(Time.get_ticks_msec() / 60.0 + s.position.x) * 1.5, Color(0.4, 0.9, 1.0, 0.55))
	if not alive:
		return
	# orbes orbitaux et drones (même formule que le serveur)
	var t: float = world.server_time
	for wi in weapons.size():
		var w: Array = weapons[wi]
		var def: Dictionary = Db.weapons.get(w[0], {})
		if def.get("kind", "") != "orbit":
			continue
		var cnt: int = int(def.count) + int(def.count_per_tier) * int(w[1]) + int(world.stat_of(pid, "projectiles"))
		var radius: float = float(def.range) + world.stat_of(pid, "range") * 0.3
		for i in cnt:
			var a := t * 2.6 + TAU * i / cnt + wi
			var p := Vector2.from_angle(a) * radius
			draw_circle(p, 17, Color(Color(def.color), 0.35))
			draw_circle(p, 11, Color(def.color))
			draw_circle(p, 5, Color.WHITE)
	if drones > 0 and _drone_tex:
		for i in drones:
			var dp := Vector2.from_angle(t * 1.5 + TAU * i / drones) * 70 + Vector2(0, -20)
			draw_texture_rect(_drone_tex, Rect2(dp - Vector2(18, 18), Vector2(36, 36)), false)
	# barre de vie (alliés / adversaires)
	if not is_local:
		var w2 := 70.0
		draw_rect(Rect2(-w2 / 2, 26, w2, 9), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(-w2 / 2 + 1, 27, (w2 - 2) * clamp(hp / max(max_hp, 1.0), 0.0, 1.0), 7), Color("#ff4d6d") if world.is_foe(Net.my_id(), pid) else Color("#06ffa5"))
