extends Node
## Résolution du combat (serveur uniquement) : armes, drones, dégâts, morts, explosions.

const PK := preload("res://scripts/world/projectile_system.gd")
const PlayerNode := preload("res://scripts/world/player.gd")
const FROM_DRONE := ["projectile", "rocket", "boomerang", "chain", "cone", "mine"]   # tirs partant du drone porteur

var world: Node
var time := 0.0


func update(dt: float) -> void:
	time += dt
	for pid in world.run:
		var rp = world.run[pid]
		if not rp.alive:
			continue
		var pos: Vector2 = world.player_pos(pid)
		if pos == Vector2.INF:
			continue
		rp.invuln = max(0.0, rp.invuln - dt)
		rp.dash_cd = max(0.0, rp.dash_cd - dt)
		# régénération
		if rp.stats.hp_regen > 0 and rp.hp < rp.max_hp():
			rp.regen_acc += rp.stats.hp_regen * 0.12 * dt
			if rp.regen_acc >= 1.0:
				rp.regen_acc -= 1.0
				rp.hp = min(rp.max_hp(), rp.hp + 1.0)
		var carried: Array = []   # armes portées par un drone (toutes sauf les orbes)
		for wj in rp.weapons.size():
			if Db.weapons[rp.weapons[wj].id].kind != "orbit":
				carried.append(wj)
		for wi in rp.weapons.size():
			var w: Dictionary = rp.weapons[wi]
			var def: Dictionary = Db.weapons[w.id]
			if def.kind == "orbit":
				_orbit(rp, pid, pos, w, def, wi)
				continue
			w.cd -= dt
			if w.cd > 0:
				continue
			var rng: float = rp.weapon_range(w)
			var tgt = _find_target(pid, pos, rng if def.kind != "mine" else 99999.0)
			if tgt.is_empty() and def.kind != "mine":
				w.cd = 0.1
				continue
			w.cd = rp.weapon_cooldown(w)
			var muzzle := pos
			if def.kind in FROM_DRONE:
				muzzle = pos + PlayerNode.drone_offset(carried.find(wi), carried.size(), world.server_time)
			_fire(rp, pid, muzzle, w, def, tgt.get("pos", pos))
		_drones(rp, pid, pos, dt)


# ------------------------------------------------------------------ ciblage
func _find_target(pid: int, pos: Vector2, rng: float) -> Dictionary:
	var e = world.enemies.nearest(pos, rng)
	var best := {}
	var bd := rng * rng
	if e:
		best = {"pos": e.pos, "enemy": e}
		bd = e.pos.distance_squared_to(pos)
	if world.pvp:
		for t in world.alive_targets():
			if not world.is_foe(pid, t[0]):
				continue
			var d: float = pos.distance_squared_to(t[1])
			if d < bd:
				bd = d
				best = {"pos": t[1], "player": t[0]}
	return best


func _roll(rp, base: float) -> Array:
	var crit: bool = randf() * 100.0 < rp.stats.crit
	var dmg = base * (2.0 + rp.stats.crit_dmg / 100.0) if crit else base
	return [dmg, crit]


# ------------------------------------------------------------------ tir
func _fire(rp, pid: int, pos: Vector2, w: Dictionary, def: Dictionary, tpos: Vector2) -> void:
	var base: float = rp.weapon_damage(w)
	var dir := (tpos - pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var color := Color(def.color)
	var knock: float = def.get("knockback", 0) + rp.stats.knockback
	var rng: float = rp.weapon_range(w)
	match def.kind:
		"projectile", "rocket", "boomerang":
			var count: int = int(def.get("count", 1)) + int(rp.stats.projectiles)
			var spread: float = float(def.get("spread", 0))
			if count > 1 and spread == 0:
				spread = 12.0
			var spd: float = def.speed
			for i in count:
				var a = dir.angle()
				if count > 1:
					a += deg_to_rad(spread) * (float(i) / (count - 1) - 0.5)
				if def.kind == "projectile" and spread > 0 and count == 1:
					a += deg_to_rad(randf_range(-spread, spread) * 0.5)
				var r := _roll(rp, base)
				var kind := PK.Kind.BULLET
				var life := rng / spd * 1.15
				if def.kind == "rocket":
					kind = PK.Kind.ROCKET
				elif def.kind == "boomerang":
					kind = PK.Kind.BOOMERANG
					life = rng / spd * 2.2
				elif int(def.get("pierce", 0)) >= 99:
					kind = PK.Kind.RAIL
				world.projectiles.spawn(kind, pos + dir * 14, Vector2.from_angle(a) * spd, life, float(def.get("radius", 6)), color, pid, r[0],
					{"crit": r[1], "pierce": int(def.get("pierce", 0)) + int(rp.stats.pierce), "aoe": float(def.get("aoe", 0)), "knock": knock, "weapon": w.id})
		"mine":
			var r2 := _roll(rp, base)
			var mpos: Vector2 = world.clamp_to_arena(pos + Vector2.from_angle(randf() * TAU) * randf_range(20, rng * 0.5), 20)
			world.projectiles.spawn(PK.Kind.MINE, mpos, Vector2.ZERO, 12.0, 14, color, pid, r2[0], {"crit": r2[1], "aoe": float(def.aoe), "arm": 0.5})
		"slash":
			var arc = deg_to_rad(float(def.arc))
			var r3 := _roll(rp, base)
			_area_hit(pid, pos, rng, dir, arc, r3[0], r3[1], dir, knock, w.id)
			world.ev_u(["S", int(pos.x), int(pos.y), dir.angle(), rng, arc, color.to_rgba32()])
		"slam":
			var center = pos + dir * min(pos.distance_to(tpos), rng * 0.7)
			var r4 := _roll(rp, base)
			_area_hit(pid, center, float(def.aoe), Vector2.ZERO, TAU, r4[0], r4[1], Vector2.ZERO, knock, w.id)
			world.ev_u(["E", int(center.x), int(center.y), float(def.aoe), color.to_rgba32()])
			shake(4)
		"chain":
			var jumps: int = int(def.chain) + int(rp.stats.get("chain", 0))
			var pts = [pos.x, pos.y]
			var hit := {}
			var cur := tpos
			var r5 := _roll(rp, base)
			var tgt := _find_target(pid, pos, rng)
			for j in jumps + 1:
				if tgt.is_empty():
					break
				cur = tgt.pos
				pts.append_array([cur.x, cur.y])
				if tgt.has("enemy"):
					hit[tgt.enemy.id] = true
					damage_enemy(tgt.enemy, r5[0] * pow(0.85, j), r5[1], pid, Vector2.ZERO, 0, Color(), w.id)
				else:
					hit[-int(tgt.player)] = true
					hit_player(tgt.player, r5[0] * pow(0.85, j), cur, pid)
				tgt = _next_chain(pid, cur, float(def.chain_range), hit)
			world.ev_u(["C", PackedFloat32Array(pts), color.to_rgba32()])
		"cone":
			var arc2 = deg_to_rad(float(def.arc))
			var r6 := _roll(rp, base)
			_area_hit(pid, pos, rng, dir, arc2, r6[0], r6[1], dir, 15, w.id, float(def.get("burn", 0)))
			world.ev_u(["F", int(pos.x), int(pos.y), dir.angle(), rng, arc2])
	var sfx: String = def.get("sfx", "")
	if sfx != "":
		var every: int = int(def.get("sfx_every", 1))
		if every <= 1 or randi() % every == 0:
			world.ev_u(["A", sfx, int(pos.x), int(pos.y)])


func _next_chain(pid: int, from: Vector2, rng: float, hit: Dictionary) -> Dictionary:
	var best := {}
	var bd := rng * rng
	for e in world.enemies.query(from, rng):
		if hit.has(e.id):
			continue
		var d: float = e.pos.distance_squared_to(from)
		if d < bd:
			bd = d
			best = {"pos": e.pos, "enemy": e}
	if world.pvp:
		for t in world.alive_targets():
			if not world.is_foe(pid, t[0]) or hit.has(-int(t[0])):
				continue
			var d2: float = from.distance_squared_to(t[1])
			if d2 < bd:
				bd = d2
				best = {"pos": t[1], "player": t[0]}
	return best


## Dégâts de zone (cercle ou secteur) sur ennemis (et joueurs adverses en PvP).
func _area_hit(pid: int, center: Vector2, radius: float, dir: Vector2, arc: float, dmg: float, crit: bool, kdir: Vector2, knock: float, weapon: String, burn := 0.0) -> void:
	for e in world.enemies.query(center, radius):
		var to: Vector2 = e.pos - center
		if arc < TAU - 0.01 and to.length() > e.radius and abs(dir.angle_to(to)) > arc / 2:
			continue
		var kd = kdir if kdir != Vector2.ZERO else to.normalized()
		damage_enemy(e, dmg, crit, pid, kd, knock, Color(), weapon)
		if burn > 0 and e.alive:
			_apply_burn(e, dmg * burn * 0.5, pid)
	if world.pvp:
		for t in world.alive_targets():
			if not world.is_foe(pid, t[0]):
				continue
			var to2: Vector2 = t[1] - center
			if to2.length() > radius + 22:
				continue
			if arc < TAU - 0.01 and abs(dir.angle_to(to2)) > arc / 2:
				continue
			hit_player(t[0], dmg, center, pid)


func _apply_burn(e, dps: float, pid: int) -> void:
	e.burn = 3.0
	e.burn_dps = max(e.burn_dps if e.burn > 0 else 0.0, dps)
	e.burn_src = pid


func _orbit(rp, pid: int, pos: Vector2, w: Dictionary, def: Dictionary, wi: int) -> void:
	var n: int = int(def.count) + int(def.count_per_tier) * int(w.tier) + int(rp.stats.projectiles)
	var radius: float = float(def.range) + rp.stats.range * 0.3
	var hit_cd: float = rp.weapon_cooldown(w)
	for i in n:
		var a := time * 2.6 + TAU * i / n + wi
		var op := pos + Vector2.from_angle(a) * radius
		for e in world.enemies.query(op, 18.0):
			var key := pid * 10 + wi
			if time - float(e.orbit_hits.get(key, -99.0)) < hit_cd:
				continue
			e.orbit_hits[key] = time
			var r = _roll(rp, rp.weapon_damage(w))
			damage_enemy(e, r[0], r[1], pid, (e.pos - pos).normalized(), 40, Color(), w.id)
		if world.pvp:
			for t in world.alive_targets():
				if world.is_foe(pid, t[0]) and op.distance_squared_to(t[1]) < 40 * 40:
					var key2 := "o%d_%d" % [pid, wi]
					var rp2 = world.run[t[0]]
					if time - float(rp2.get_meta(key2, -99.0)) >= hit_cd:
						rp2.set_meta(key2, time)
						hit_player(t[0], rp.weapon_damage(w), op, pid)


func _drones(rp, pid: int, pos: Vector2, dt: float) -> void:
	var n = int(rp.stats.get("drones", 0))
	if n <= 0:
		return
	rp.drone_cd -= dt
	if rp.drone_cd > 0:
		return
	rp.drone_cd = 1.1 / max(0.3, 1.0 + rp.stats.attack_speed / 100.0)
	for i in n:
		var dp := pos + Vector2.from_angle(time * 1.5 + TAU * i / n) * 70
		var tgt := _find_target(pid, dp, 420)
		if tgt.is_empty():
			return
		var dmg: float = (4.0 + rp.stats.tech * 1.0 + rp.level * 0.25) * (1.0 + rp.stats.damage / 100.0)
		var r := _roll(rp, dmg)
		world.projectiles.spawn(PK.Kind.DRONE, dp, (tgt.pos - dp).normalized() * 800, 0.6, 4, Color("#9dff6b"), pid, r[0], {"crit": r[1]})


# ------------------------------------------------------------------ dégâts aux ennemis
func damage_enemy(e, dmg: float, crit: bool, owner: int, kdir: Vector2, knock: float, color := Color(), weapon := "") -> void:
	if not e.alive or e.spawning > 0 or e.hidden:
		return
	var rp = world.run.get(owner)
	if rp and e.boss:
		dmg *= 1.0 + rp.stats.get("boss_damage", 0.0) / 100.0
	e.hp -= dmg
	e.flash = 0.08
	if knock > 0 and not e.boss:
		var resist: float = e.def.get("knockback_resist", 0.0)
		e.knock += kdir * knock * 6.0 * (1.0 - resist)
	if rp:
		rp.damage_dealt += int(dmg)
		if rp.stats.life_steal > 0 and randf() * 100.0 < rp.stats.life_steal and rp.alive:
			rp.hp = min(rp.max_hp(), rp.hp + 1.0)
		if rp.stats.get("burn_chance", 0) > 0 and weapon != "" and randf() * 100.0 < rp.stats.burn_chance:
			_apply_burn(e, 2.0 + rp.stats.tech * 0.8, owner)
	world.ev_u(["D", int(e.pos.x), int(e.pos.y - e.radius), int(ceil(dmg)), crit, color.to_rgba32() if color != Color() else 0])
	if e.hp <= 0:
		kill_enemy(e, owner)


func kill_enemy(e, owner: int) -> void:
	if not e.alive:
		return
	world.enemies.remove(e)
	var def: Dictionary = e.def
	var big: bool = e.boss or e.elite or def.size >= 100
	world.ev_u(["K", int(e.pos.x), int(e.pos.y), e.tidx, big])
	if e.no_drop:
		return
	var rp = world.run.get(owner)
	if rp:
		rp.kills += 1
	world.on_enemy_killed(e, owner)
	# butin
	var drops: int = int(def.drop) * (3 if e.elite else 1)
	var value := 1
	if drops > 12:
		value = int(ceil(drops / 12.0))
		drops = 12
	for i in drops:
		world.pickups.spawn_pickup("data", e.pos + Vector2.from_angle(randf() * TAU) * randf_range(0, 18 + drops * 3), value)
	var luck := 0.0
	if rp:
		luck = rp.stats.luck
	if randf() < 0.018 * (1.0 + luck / 100.0):
		world.pickups.spawn_pickup("soin", e.pos, 1)
	if e.elite or (e.boss and not world.pvp):
		world.pickups.spawn_pickup("coffre", e.pos + Vector2(0, 20), 1)
	# division
	if def.has("split"):
		for i in int(def.split_count):
			world.spawn_enemy(def.split, e.pos + Vector2.from_angle(TAU * i / def.split_count) * 26, false, 0.15)
	# explosion à l'élimination
	if rp and rp.stats.get("explode_on_kill", 0) > 0 and randf() * 100.0 < rp.stats.explode_on_kill:
		explode(e.pos, 80, (6.0 + world.wave * 1.5) * (1.0 + rp.stats.damage / 100.0), owner, false)


## Explosion d'un joueur (roquettes, mines, puce explosive).
func explode(pos: Vector2, radius: float, dmg: float, owner: int, crit: bool) -> void:
	world.ev_u(["E", int(pos.x), int(pos.y), radius, Color("#ff9f1c").to_rgba32()])
	world.ev_u(["A", "explosion", int(pos.x), int(pos.y)])
	for e in world.enemies.query(pos, radius):
		damage_enemy(e, dmg, crit, owner, (e.pos - pos).normalized(), 60)
	if world.pvp:
		for t in world.alive_targets():
			if world.is_foe(owner, t[0]) and pos.distance_squared_to(t[1]) < pow(radius + 20, 2):
				hit_player(t[0], dmg, pos, owner)
	shake(5)


## Explosion d'un ennemi (kamikaze) : touche les joueurs.
func enemy_explosion(pos: Vector2, radius: float, dmg: float) -> void:
	world.ev_u(["E", int(pos.x), int(pos.y), radius, Color("#ff4d4d").to_rgba32()])
	world.ev_u(["A", "explosion", int(pos.x), int(pos.y)])
	for t in world.alive_targets():
		if pos.distance_squared_to(t[1]) < pow(radius + 20, 2):
			hit_player(t[0], dmg, pos, 0)
	shake(6)


func enemy_contact(e, pid: int) -> void:
	if hit_player(pid, e.damage, e.pos, 0):
		var rp = world.run[pid]
		if rp.stats.get("thorns", 0) > 0:
			damage_enemy(e, rp.stats.thorns, false, pid, (e.pos - world.player_pos(pid)).normalized(), 30)


# ------------------------------------------------------------------ dégâts aux joueurs
func hit_player(pid: int, dmg: float, src: Vector2, attacker: int) -> bool:
	var rp = world.run.get(pid)
	if rp == null or not rp.alive or rp.invuln > 0 or world.state != "wave":
		return false
	var ppos: Vector2 = world.player_pos(pid)
	if randf() * 100.0 < rp.stats.dodge:
		rp.invuln = 0.15
		world.ev_u(["T", int(ppos.x), int(ppos.y - 50), "Esquive !", Color("#5ff7ff").to_rgba32()])
		return false
	if rp.shield_left > 0:
		rp.shield_left -= 1
		rp.invuln = 0.4
		world.ev_u(["T", int(ppos.x), int(ppos.y - 50), "Bloqué !", Color("#4cc9f0").to_rgba32()])
		return false
	var armor: float = rp.stats.armor
	var mult = 1.0 / (1.0 + armor / 15.0) if armor >= 0 else 1.0 + abs(armor) / 15.0
	var final: float = max(1.0, round(dmg * mult))
	rp.hp -= final
	rp.invuln = 0.25 if world.pvp else 0.5
	var arp = world.run.get(attacker)
	if arp:
		arp.damage_dealt += int(final)
	world.ev_u(["PH", pid, int(final)])
	world.ev_u(["D", int(ppos.x), int(ppos.y - 40), int(final), false, Color("#ff4d6d").to_rgba32()])
	if rp.hp <= 0:
		if rp.revives_left > 0:
			rp.revives_left -= 1
			rp.hp = rp.max_hp() * 0.5
			rp.invuln = 2.0
			world.ev_u(["T", int(ppos.x), int(ppos.y - 60), "Sauvegarde automatique restaurée !", Color("#06ffa5").to_rgba32()])
			world.ev_u(["A", "soin", int(ppos.x), int(ppos.y)])
		else:
			rp.hp = 0
			rp.alive = false
			world.on_player_died(pid, attacker)
	return true


func shake(amount: float) -> void:
	world.ev_u(["SH", amount])
