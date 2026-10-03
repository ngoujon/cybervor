extends Node2D
## Projectiles : simulés et résolus sur le serveur, reproduits visuellement chez les clients.

enum Kind { BULLET, ROCKET, BOOMERANG, MINE, ENEMY, DRONE, RAIL }


class Proj:
	var id := 0
	var kind := 0
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var life := 1.0
	var max_life := 1.0
	var radius := 6.0
	var color = Color.WHITE
	var owner := 0        # 0 = ennemis, sinon id du joueur
	var dmg := 1.0
	var crit := false
	var pierce := 0
	var hits := {}
	var aoe := 0.0
	var knock := 0.0
	var weapon := ""
	var arm := 0.0
	var returning := false
	var alive := true


var world: Node
var list: Array = []
var next_id := 1
var headless := false
var _shuriken_tex: Texture2D
var _mine_tex: Texture2D
var _time := 0.0


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	_shuriken_tex = Db.tex("res://assets/sprites/weapons/shuriken.png")
	_mine_tex = Db.tex("res://assets/sprites/weapons/mines.png")


func clear_all() -> void:
	list.clear()


# ------------------------------------------------------------------ création (serveur)
func spawn(kind: int, pos: Vector2, vel: Vector2, life: float, radius: float, color: Color, owner: int, dmg: float, extra := {}) -> Proj:
	var p := Proj.new()
	p.id = next_id
	next_id += 1
	p.kind = kind
	p.pos = pos
	p.vel = vel
	p.life = life
	p.max_life = life
	p.radius = radius
	p.color = color
	p.owner = owner
	p.dmg = dmg
	p.crit = extra.get("crit", false)
	p.pierce = extra.get("pierce", 0)
	p.aoe = extra.get("aoe", 0.0)
	p.knock = extra.get("knock", 0.0)
	p.weapon = extra.get("weapon", "")
	p.arm = extra.get("arm", 0.0)
	list.append(p)
	world.ev_u(["P", p.id, kind, int(pos.x), int(pos.y), int(vel.x), int(vel.y), life, radius, color.to_rgba32(), owner])
	return p


func spawn_enemy_bullet(pos: Vector2, vel: Vector2, dmg: float, radius: float, color: Color) -> void:
	spawn(Kind.ENEMY, pos, vel, 4.0, radius, color, 0, dmg)


func _despawn(p: Proj) -> void:
	p.alive = false
	world.ev_u(["X", p.id])


# ------------------------------------------------------------------ simulation (serveur)
func server_update(dt: float) -> void:
	var pvp: bool = world.pvp
	for p in list:
		if not p.alive:
			continue
		p.life -= dt
		if p.life <= 0:
			if p.kind == Kind.ROCKET or p.kind == Kind.MINE:
				world.combat.explode(p.pos, p.aoe, p.dmg, p.owner, p.crit)
			_despawn(p)
			continue
		_move(p, dt)
		if p.kind == Kind.ENEMY:
			for t in world.alive_targets():
				if p.pos.distance_squared_to(t[1]) < pow(p.radius + 22.0, 2):
					world.combat.hit_player(t[0], p.dmg, p.pos, 0)
					_despawn(p)
					break
			continue
		if p.kind == Kind.MINE:
			p.arm -= dt
			if p.arm > 0:
				continue
			var trig: Array = world.enemies.query(p.pos, 38.0)
			var trig_player := pvp and _player_hit(p, 30.0) != 0
			if not trig.is_empty() or trig_player:
				world.combat.explode(p.pos, p.aoe, p.dmg, p.owner, p.crit)
				_despawn(p)
			continue
		# Projectiles des joueurs contre les ennemis
		for e in world.enemies.query(p.pos, p.radius):
			if p.hits.has(e.id):
				continue
			p.hits[e.id] = true
			if p.kind == Kind.ROCKET:
				world.combat.explode(p.pos, p.aoe, p.dmg, p.owner, p.crit)
				_despawn(p)
				break
			world.combat.damage_enemy(e, p.dmg, p.crit, p.owner, p.vel.normalized(), p.knock, Color(), p.weapon)
			if p.pierce <= 0:
				_despawn(p)
				break
			p.pierce -= 1
		if p.alive and pvp:
			var pid := _player_hit(p, 22.0)
			if pid != 0 and not p.hits.has(-pid):
				p.hits[-pid] = true
				if p.kind == Kind.ROCKET:
					world.combat.explode(p.pos, p.aoe, p.dmg, p.owner, p.crit)
					_despawn(p)
				else:
					world.combat.hit_player(pid, p.dmg, p.pos, p.owner)
					if p.pierce <= 0:
						_despawn(p)
					else:
						p.pierce -= 1
		if p.alive and not world.in_arena(p.pos, -60.0) and p.kind != Kind.BOOMERANG:
			_despawn(p)
	list = list.filter(func(x): return x.alive)


func _player_hit(p: Proj, r: float) -> int:
	for t in world.alive_targets():
		if world.is_foe(p.owner, t[0]) and p.pos.distance_squared_to(t[1]) < pow(p.radius + r, 2):
			return t[0]
	return 0


func _move(p: Proj, dt: float) -> void:
	if p.kind == Kind.BOOMERANG:
		var half = p.max_life * 0.5
		if p.life < half and not p.returning:
			p.returning = true
			p.hits.clear()
		if p.returning:
			var owner_pos: Vector2 = world.player_pos(p.owner)
			if owner_pos != Vector2.INF:
				p.vel = (owner_pos - p.pos).normalized() * p.vel.length()
				if p.pos.distance_squared_to(owner_pos) < 900:
					p.life = 0
	p.pos += p.vel * dt


# ------------------------------------------------------------------ côté client
func client_event(ev: Array) -> void:
	match ev[0]:
		"P":
			var p := Proj.new()
			p.id = ev[1]
			p.kind = ev[2]
			p.pos = Vector2(ev[3], ev[4])
			p.vel = Vector2(ev[5], ev[6])
			p.life = ev[7]
			p.max_life = ev[7]
			p.radius = ev[8]
			p.color = Color.hex(ev[9])
			p.owner = ev[10]
			list.append(p)
		"X":
			for p in list:
				if p.id == ev[1]:
					p.alive = false


func client_update(dt: float) -> void:
	for p in list:
		p.life -= dt
		if p.life <= 0:
			p.alive = false
			continue
		_move(p, dt)
	list = list.filter(func(x): return x.alive)


func _process(delta: float) -> void:
	_time += delta
	if not headless:
		queue_redraw()


func _draw() -> void:
	for p in list:
		match p.kind:
			Kind.MINE:
				if _mine_tex:
					draw_texture_rect(_mine_tex, Rect2(p.pos - Vector2(18, 18), Vector2(36, 36)), false)
				if fmod(_time * 3.0 + p.id, 1.0) < 0.5:
					draw_circle(p.pos, 5, Color("#ff2244"))
			Kind.BOOMERANG:
				if _shuriken_tex:
					draw_set_transform(p.pos, _time * 18.0, Vector2.ONE)
					draw_texture_rect(_shuriken_tex, Rect2(Vector2(-p.radius - 6, -p.radius - 6), Vector2(p.radius * 2 + 12, p.radius * 2 + 12)), false)
					draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			Kind.ROCKET:
				var d = p.vel.normalized()
				draw_line(p.pos - d * 26, p.pos, Color(1, 0.7, 0.2, 0.6), 6)
				draw_circle(p.pos - d * 30, 6 + randf() * 4, Color(1, 0.5, 0.1, 0.5))
				draw_line(p.pos - d * 10, p.pos + d * 10, Color.BLACK, 12)
				draw_line(p.pos - d * 9, p.pos + d * 9, p.color, 8)
			Kind.RAIL:
				var d2 = p.vel.normalized()
				draw_line(p.pos - d2 * 90, p.pos, Color(p.color, 0.35), 14)
				draw_line(p.pos - d2 * 90, p.pos, Color.WHITE, 4)
			Kind.ENEMY:
				draw_circle(p.pos, p.radius + 4, Color(0, 0, 0, 0.6))
				draw_circle(p.pos, p.radius + 1, p.color)
				draw_circle(p.pos, p.radius * 0.45, Color(1, 1, 1, 0.9))
			_:
				var d3 = p.vel.normalized()
				draw_line(p.pos - d3 * p.radius * 2.2, p.pos, Color(p.color, 0.4), p.radius * 1.6)
				draw_circle(p.pos, p.radius + 3, Color(0, 0, 0, 0.55))
				draw_circle(p.pos, p.radius + 1, p.color)
				draw_circle(p.pos, p.radius * 0.5, Color(1, 1, 1, 0.9))
