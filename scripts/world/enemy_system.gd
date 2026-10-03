extends Node2D
## Ennemis : simulation autoritaire (serveur) + rendu (serveur et clients via instantanés).

const CELL := 96.0
const MAX_ENEMIES := 260
const F_SPAWNING := 1
const F_BOSS := 2
const F_FLASH := 4
const F_BURN := 8
const F_LEFT := 16
const F_HIDDEN := 32
const F_ELITE := 64
const F_CHARGE := 128


class Enemy:
	var id := 0
	var type := ""
	var tidx := 0
	var def: Dictionary
	var pos := Vector2.ZERO
	var knock := Vector2.ZERO
	var move_dir := Vector2.ZERO
	var hp := 1.0
	var max_hp := 1.0
	var speed := 100.0
	var damage := 1.0
	var radius := 20.0
	var ai := "chase"
	var spawning := 0.8
	var t := 0.0
	var cd := 0.0
	var cd2 := 0.0
	var state := 0
	var state_t := 0.0
	var dir := Vector2.ZERO
	var boss := false
	var elite := false
	var burn := 0.0
	var slow := 0.0      # ralentissement (sorts de zone)
	var slow_t := 0.0
	var burn_dps := 0.0
	var burn_src := 0
	var flash := 0.0
	var hidden := false
	var life := -1.0
	var pattern_i := 0
	var target_id := 0
	var retarget := 0.0
	var orbit_hits := {}
	var alive := true
	var no_drop := false
	var spiral_a := 0.0


var world: Node
var list: Array = []
var by_id: Dictionary = {}
var grid: Dictionary = {}
var next_id := 1
var headless := false

# rendu
var views: Dictionary = {}     # id -> {sprite, target, tidx, flags, hp}
var _time := 0.0


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"


# ================================================================== SERVEUR
func spawn(type: String, pos: Vector2, hp_mult := 1.0, dmg_mult := 1.0, wave := 1, elite := false, delay := 0.8) -> Enemy:
	if list.size() >= MAX_ENEMIES and not Db.enemies[type].get("boss", false):
		return null
	var def: Dictionary = Db.enemies[type]
	var e := Enemy.new()
	e.id = next_id
	next_id += 1
	e.type = type
	e.tidx = Db.enemy_index(type)
	e.def = def
	e.pos = pos
	e.ai = def.ai
	e.max_hp = (float(def.hp) + float(def.hp_wave) * (wave - 1)) * hp_mult
	e.damage = (float(def.damage) + float(def.damage_wave) * (wave - 1)) * dmg_mult
	e.speed = float(def.speed) * randf_range(0.92, 1.08)
	e.radius = float(def.radius)
	e.boss = def.get("boss", false)
	e.elite = elite
	if elite:
		e.max_hp *= 4.0
		e.damage *= 1.4
		e.radius *= 1.35
		e.speed *= 0.9
	e.hp = e.max_hp
	e.spawning = delay
	e.cd = randf_range(0.5, 1.5)
	e.cd2 = 1.0
	if def.has("lifetime"):
		e.life = float(def.lifetime)
	list.append(e)
	by_id[e.id] = e
	return e


func clear_all() -> void:
	for e in list:
		e.alive = false
	list.clear()
	by_id.clear()


func boss_alive() -> bool:
	for e in list:
		if e.boss and e.alive:
			return true
	return false


func _rebuild_grid() -> void:
	grid.clear()
	for e in list:
		if e.spawning > 0 or e.hidden:
			continue
		var c := Vector2i(floori(e.pos.x / CELL), floori(e.pos.y / CELL))
		if grid.has(c):
			grid[c].append(e)
		else:
			grid[c] = [e]


## Ennemis dont le cercle intersecte (pos, r).
func query(pos: Vector2, r: float) -> Array:
	var out := []
	var reach := r + 120.0
	var c0 := Vector2i(floori((pos.x - reach) / CELL), floori((pos.y - reach) / CELL))
	var c1 := Vector2i(floori((pos.x + reach) / CELL), floori((pos.y + reach) / CELL))
	for cx in range(c0.x, c1.x + 1):
		for cy in range(c0.y, c1.y + 1):
			var cell = grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for e in cell:
				if e.alive and e.pos.distance_squared_to(pos) <= pow(r + e.radius, 2):
					out.append(e)
	return out


func nearest(pos: Vector2, max_range: float) -> Enemy:
	var best: Enemy = null
	var bd := max_range * max_range
	for e in list:
		if not e.alive or e.spawning > 0 or e.hidden:
			continue
		var d = e.pos.distance_squared_to(pos)
		if d < bd:
			bd = d
			best = e
	return best


func server_update(dt: float) -> void:
	_rebuild_grid()
	var targets: Array = world.alive_targets()
	for e in list.duplicate():
		if not e.alive:
			continue
		if e.spawning > 0:
			e.spawning -= dt
			continue
		e.t += dt
		e.flash = max(0.0, e.flash - dt)
		if e.burn > 0:
			e.burn -= dt
			e.cd2 -= dt
			if e.cd2 <= 0:
				e.cd2 = 0.5
				world.combat.damage_enemy(e, e.burn_dps * 0.5, false, e.burn_src, Vector2.ZERO, 0, Color("#ff9f1c"))
				if not e.alive:
					continue
		if e.life > 0:
			e.life -= dt
			if e.life <= 0:
				e.no_drop = true
				world.combat.kill_enemy(e, 0)
				continue
		if e.slow_t > 0:
			e.slow_t -= dt
			_ai(e, dt * (1.0 - clamp(e.slow, 0.0, 0.8)), targets)
		else:
			e.slow = 0.0
			_ai(e, dt, targets)
		# recul
		if e.knock.length_squared() > 1:
			e.pos += e.knock * dt
			e.knock = e.knock.move_toward(Vector2.ZERO, 1400 * dt)
		e.pos = world.clamp_to_arena(e.pos, e.radius)
	_separate()
	# contact avec les joueurs
	for e in list:
		if not e.alive or e.spawning > 0 or e.hidden:
			continue
		for tgt in targets:
			if e.pos.distance_squared_to(tgt[1]) < pow(e.radius + 26.0, 2):
				world.combat.enemy_contact(e, tgt[0])


func _separate() -> void:
	for cell in grid.values():
		var n: int = cell.size()
		for i in n:
			var a: Enemy = cell[i]
			for j in range(i + 1, n):
				var b: Enemy = cell[j]
				var d := b.pos - a.pos
				var min_d := (a.radius + b.radius) * 0.85
				var l2 := d.length_squared()
				if l2 < min_d * min_d and l2 > 0.01:
					var l := sqrt(l2)
					var push := d / l * (min_d - l) * 0.5
					if not a.boss:
						a.pos -= push
					if not b.boss:
						b.pos += push


func _pick_target(e: Enemy, targets: Array, dt: float) -> Vector2:
	e.retarget -= dt
	var tpos := Vector2.INF
	if e.retarget <= 0 or e.target_id == 0:
		e.retarget = 0.6
		var bd := INF
		for t in targets:
			var d = e.pos.distance_squared_to(t[1])
			if d < bd:
				bd = d
				e.target_id = t[0]
				tpos = t[1]
	else:
		for t in targets:
			if t[0] == e.target_id:
				tpos = t[1]
		if tpos == Vector2.INF:
			e.target_id = 0
			return _pick_target(e, targets, 0.0) if not targets.is_empty() else e.pos
	return tpos if tpos != Vector2.INF else e.pos


func _ai(e: Enemy, dt: float, targets: Array) -> void:
	if targets.is_empty():
		return
	var tp := _pick_target(e, targets, dt)
	var to = tp - e.pos
	var dist = to.length()
	var dirn = to / dist if dist > 0.01 else Vector2.ZERO
	var spd = e.speed
	match e.ai:
		"chase":
			if e.def.get("wobble", 0):
				dirn = dirn.rotated(sin(e.t * 6.0 + e.id) * 0.6)
			e.move_dir = dirn
		"ranged":
			var keep: float = e.def.keep_distance
			if dist > keep + 40:
				e.move_dir = dirn
			elif dist < keep - 70:
				e.move_dir = -dirn
			else:
				e.move_dir = dirn.orthogonal() * (1 if e.id % 2 == 0 else -1) * 0.6
			e.cd -= dt
			if e.cd <= 0:
				e.cd = float(e.def.shoot_cd) * randf_range(0.85, 1.15)
				_shoot_at(e, tp, int(e.def.get("bullets", 1)), 14.0)
		"exploder":
			if e.state == 0:
				e.move_dir = dirn
				if dist < float(e.def.explode_radius) * 0.65:
					e.state = 1
					e.state_t = 0.6
			else:
				e.move_dir = Vector2.ZERO
				e.flash = 0.1
				e.state_t -= dt
				if e.state_t <= 0:
					world.combat.enemy_explosion(e.pos, float(e.def.explode_radius), e.damage)
					world.combat.kill_enemy(e, 0)
					return
		"healer":
			var keep2: float = e.def.keep_distance
			e.move_dir = dirn if dist > keep2 + 30 else (-dirn if dist < keep2 - 30 else Vector2.ZERO)
			e.cd -= dt
			if e.cd <= 0:
				e.cd = float(e.def.heal_cd)
				var healed := false
				for o in query(e.pos, float(e.def.heal_radius)):
					if o != e and o.hp < o.max_hp:
						o.hp = min(o.max_hp, o.hp + float(e.def.heal) * (1.0 + world.wave * 0.15))
						healed = true
				if healed:
					world.fx_heal_ring(e.pos, float(e.def.heal_radius))
		"dasher":
			match e.state:
				0:
					e.move_dir = dirn
					e.cd -= dt
					if e.cd <= 0 and dist < 520:
						e.state = 1
						e.state_t = 0.55
						e.dir = dirn
				1:
					e.move_dir = Vector2.ZERO
					e.flash = 0.05
					e.state_t -= dt
					if e.state_t <= 0:
						e.state = 2
						e.state_t = 0.45
				2:
					e.move_dir = e.dir
					spd = float(e.def.dash_speed)
					e.state_t -= dt
					if e.state_t <= 0:
						e.state = 0
						e.cd = float(e.def.dash_cd)
		"turret":
			e.move_dir = Vector2.ZERO
			e.cd -= dt
			if e.cd <= 0:
				e.cd = float(e.def.shoot_cd)
				var n = int(e.def.bullets)
				var off := randf() * TAU
				for i in n:
					var a = off + TAU * i / n
					world.projectiles.spawn_enemy_bullet(e.pos, Vector2.from_angle(a) * float(e.def.bullet_speed), e.damage, 10, Color("#ff6b35"))
				Audio.play_at("tir_ennemi", e.pos, -8)
		"phantom":
			e.move_dir = dirn
			e.cd -= dt
			if e.cd <= 0 and dist > 220:
				e.cd = float(e.def.blink_cd)
				world.fx_blink(e.pos)
				e.pos = tp + Vector2.from_angle(randf() * TAU) * randf_range(170, 240)
				e.spawning = 0.35
				world.fx_blink(e.pos)
		"boss":
			_boss_ai(e, dt, tp, dirn, dist, targets)
			return
	var md: Vector2 = e.move_dir
	if md != Vector2.ZERO and md.dot(dirn) > 0.3:
		md = world.map.pursue(e.pos, tp, md, e.radius)
	else:
		md = world.map.steer(e.pos, md, e.radius)
	e.pos += md * spd * dt


func _shoot_at(e: Enemy, tp: Vector2, count: int, spread_deg: float) -> void:
	var base = (tp - e.pos).angle()
	for i in count:
		var a = base + deg_to_rad(spread_deg) * (i - (count - 1) / 2.0)
		world.projectiles.spawn_enemy_bullet(e.pos, Vector2.from_angle(a) * float(e.def.get("bullet_speed", 300)), e.damage, 10, Color("#ff4d6d"))
	Audio.play_at("tir_ennemi", e.pos, -6)


func _boss_ai(e: Enemy, dt: float, tp: Vector2, dirn: Vector2, dist: float, targets: Array) -> void:
	var enraged = e.hp < e.max_hp * 0.5
	match e.state:
		0:  # déplacement + attente du prochain motif
			e.pos += world.map.pursue(e.pos, tp, dirn, e.radius) * e.speed * (1.25 if enraged else 1.0) * dt
			e.cd -= dt
			if e.cd <= 0:
				var patterns: Array = e.def.patterns
				var p: String = patterns[e.pattern_i % patterns.size()]
				e.pattern_i += 1
				_start_pattern(e, p, tp)
				e.cd = float(e.def.pattern_cd) * (0.7 if enraged else 1.0)
		1:  # préparation de charge
			e.flash = 0.05
			e.state_t -= dt
			if e.state_t <= 0:
				e.state = 2
				e.state_t = 0.9
		2:  # charge
			e.pos += e.dir * 820 * dt
			e.state_t -= dt
			if e.state_t <= 0:
				e.state = 0
		3:  # spirale
			e.state_t -= dt
			e.cd2 -= dt
			if e.cd2 <= 0:
				e.cd2 = 0.07
				e.spiral_a += 0.42
				for k in 3:
					var a = e.spiral_a + TAU * k / 3.0
					world.projectiles.spawn_enemy_bullet(e.pos, Vector2.from_angle(a) * 280, e.damage * 0.6, 11, Color("#ff5fd2"))
			if e.state_t <= 0:
				e.state = 0
		4:  # tirs visés en rafales
			e.state_t -= dt
			e.cd2 -= dt
			if e.cd2 <= 0:
				e.cd2 = 0.35
				var a0 = (tp - e.pos).angle()
				for k in 5:
					var a = a0 + deg_to_rad(12) * (k - 2)
					world.projectiles.spawn_enemy_bullet(e.pos, Vector2.from_angle(a) * 380, e.damage * 0.7, 11, Color("#ff4d6d"))
				Audio.play_at("tir_ennemi", e.pos, -4)
			if e.state_t <= 0:
				e.state = 0
		5:  # sous terre
			e.state_t -= dt
			if e.state_t <= 0:
				e.hidden = false
				e.pos = world.clamp_to_arena(tp + Vector2.from_angle(randf() * TAU) * 60, e.radius)
				_ring(e, 20, 300)
				world.combat.shake(12)
				e.state = 0
	e.pos = world.clamp_to_arena(e.pos, e.radius)


func _start_pattern(e: Enemy, p: String, tp: Vector2) -> void:
	if p.begins_with("summon:"):
		var parts = p.split(":")
		var n = int(parts[2])
		for i in n:
			var sp: Vector2 = e.pos + Vector2.from_angle(TAU * i / n) * (e.radius + 60)
			world.spawn_enemy(parts[1], world.clamp_to_arena(sp, 20), false, 0.5)
		world.fx_blink(e.pos)
		return
	match p:
		"ring":
			_ring(e, 24, 260)
		"charge":
			e.state = 1
			e.state_t = 0.7
			e.dir = (tp - e.pos).normalized()
		"spiral":
			e.state = 3
			e.state_t = 2.4
			e.cd2 = 0
		"aimed":
			e.state = 4
			e.state_t = 1.5
			e.cd2 = 0
		"burrow":
			e.state = 5
			e.state_t = 1.3
			e.hidden = true
			world.fx_blink(e.pos)


func _ring(e: Enemy, n: int, spd: float) -> void:
	var off := randf() * TAU
	for i in n:
		world.projectiles.spawn_enemy_bullet(e.pos, Vector2.from_angle(off + TAU * i / n) * spd, e.damage * 0.7, 12, Color("#ffd166"))
	Audio.play_at("tir_ennemi", e.pos, 0)


func remove(e: Enemy) -> void:
	e.alive = false
	list.erase(e)
	by_id.erase(e.id)


## Instantané compact : 3 entiers par ennemi.
func pack() -> PackedInt32Array:
	var arr := PackedInt32Array()
	arr.resize(list.size() * 3)
	var i := 0
	for e in list:
		var flags := 0
		if e.spawning > 0:
			flags |= F_SPAWNING
		if e.boss:
			flags |= F_BOSS
		if e.flash > 0:
			flags |= F_FLASH
		if e.burn > 0:
			flags |= F_BURN
		if e.move_dir.x < -0.1:
			flags |= F_LEFT
		if e.hidden:
			flags |= F_HIDDEN
		if e.elite:
			flags |= F_ELITE
		if e.state == 1 and (e.ai == "dasher" or e.ai == "boss"):
			flags |= F_CHARGE
		var hp_pct: int = clamp(int(ceil(e.hp / e.max_hp * 255.0)), 0, 255)
		arr[i] = e.id
		arr[i + 1] = (e.tidx & 0xFF) | (hp_pct << 8) | (flags << 16)
		arr[i + 2] = (int(e.pos.x) + 32768) | ((int(e.pos.y) + 32768) << 16)
		i += 3
	return arr


# ================================================================== RENDU
func sync_views_from_server() -> void:
	if headless:
		return
	var seen := {}
	for e in list:
		seen[e.id] = true
		var flags := 0
		if e.spawning > 0:
			flags |= F_SPAWNING
		if e.flash > 0:
			flags |= F_FLASH
		if e.burn > 0:
			flags |= F_BURN
		if e.move_dir.x < -0.1:
			flags |= F_LEFT
		if e.hidden:
			flags |= F_HIDDEN
		if e.elite:
			flags |= F_ELITE
		if e.boss:
			flags |= F_BOSS
		if e.state == 1 and (e.ai == "dasher" or e.ai == "boss"):
			flags |= F_CHARGE
		_update_view(e.id, e.tidx, e.pos, e.hp / e.max_hp, flags, true)
	_cleanup_views(seen)


func apply_snapshot(arr: PackedInt32Array) -> void:
	if headless:
		return
	var seen := {}
	var i := 0
	while i + 2 < arr.size():
		var id = arr[i]
		var a = arr[i + 1]
		var b = arr[i + 2]
		var pos := Vector2((b & 0xFFFF) - 32768, ((b >> 16) & 0xFFFF) - 32768)
		seen[id] = true
		_update_view(id, a & 0xFF, pos, float((a >> 8) & 0xFF) / 255.0, (a >> 16) & 0xFF, false)
		i += 3
	_cleanup_views(seen)


func _update_view(id: int, tidx: int, pos: Vector2, hp: float, flags: int, snap: bool) -> void:
	var v = views.get(id)
	if v == null:
		var type: String = Db.enemy_ids[tidx] if tidx < Db.enemy_ids.size() else "bugzy"
		var def: Dictionary = Db.enemies[type]
		var s := Sprite2D.new()
		s.texture = Db.tex(def.sprite)
		var tw: float = s.texture.get_width() if s.texture else 64.0
		var base_scale: float = float(def.size) / tw * (1.35 if flags & F_ELITE else 1.0)
		s.position = pos
		add_child(s)
		v = {"sprite": s, "target": pos, "tidx": tidx, "flags": flags, "hp": hp, "scale": base_scale, "phase": randf() * TAU, "type": type}
		views[id] = v
	v.target = pos
	v.flags = flags
	v.hp = hp
	if snap:
		v.sprite.position = pos


func _cleanup_views(seen: Dictionary) -> void:
	for id in views.keys():
		if not seen.has(id):
			views[id].sprite.queue_free()
			views.erase(id)


func _process(delta: float) -> void:
	if headless:
		return
	_time += delta
	var lerp_f: float = min(1.0, delta * 14.0)
	for id in views:
		var v: Dictionary = views[id]
		var s: Sprite2D = v.sprite
		var flags: int = v.flags
		if s.position.distance_squared_to(v.target) > 250000:
			s.position = v.target
		else:
			s.position = s.position.lerp(v.target, lerp_f)
		var spawning := flags & F_SPAWNING != 0
		s.visible = not spawning and not (flags & F_HIDDEN)
		var bob = sin(_time * 9.0 + v.phase) * 0.06
		s.scale = Vector2(v.scale * (1.0 - bob * 0.5), v.scale * (1.0 + bob))
		s.flip_h = flags & F_LEFT != 0
		if flags & F_FLASH:
			s.modulate = Color(2.2, 2.2, 2.2)
		elif flags & F_CHARGE:
			s.modulate = Color(1.8, 0.7, 0.7)
		elif flags & F_BURN:
			s.modulate = Color(1.4, 0.85, 0.55)
		elif flags & F_ELITE:
			s.modulate = Color(1.15, 1.0, 0.6)
		else:
			s.modulate = Color.WHITE
		s.z_index = int(s.position.y / 10.0)
	queue_redraw()


func _draw() -> void:
	for id in views:
		var v: Dictionary = views[id]
		var p: Vector2 = v.sprite.position
		if v.flags & F_SPAWNING:
			var a := 0.5 + 0.5 * sin(_time * 14.0)
			var c := Color(1, 0.25, 0.35, 0.5 + 0.4 * a)
			draw_line(p + Vector2(-14, -14), p + Vector2(14, 14), c, 6)
			draw_line(p + Vector2(-14, 14), p + Vector2(14, -14), c, 6)
		elif v.flags & F_ELITE and not (v.flags & F_HIDDEN):
			var w := 70.0
			var y: float = p.y - Db.enemies[v.type].size * 0.85
			draw_rect(Rect2(p.x - w / 2, y, w, 8), Color(0, 0, 0, 0.7))
			draw_rect(Rect2(p.x - w / 2 + 1, y + 1, (w - 2) * v.hp, 6), Color("#ffd166"))
		elif v.flags & F_HIDDEN:
			draw_circle(p, 60 + 10 * sin(_time * 10.0), Color(0.3, 0.2, 0.1, 0.5))


## Données du boss visible pour la barre de vie du HUD.
func boss_view() -> Dictionary:
	for id in views:
		if views[id].flags & F_BOSS:
			return {"name": Db.enemies[views[id].type].name, "hp": views[id].hp}
	return {}
