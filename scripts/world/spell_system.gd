extends Node
## Sorts actifs / passifs et esquives (serveur uniquement). Données : data/spells.json.
##  - actifs : achetés en boutique, lancés par le joueur vers le curseur (ou le stick droit), avec recharge ;
##    puissants (dégâts multipliés et croissants avec les vagues) pour valoir leur temps de recharge ;
##  - passifs : statistiques (via RunPlayer.recompute), auras et effets périodiques ;
##  - esquive (Espace) : propre à chaque héros, toujours invulnérable, avec un effet (dégâts, bonus…).

const PK := preload("res://scripts/world/projectile_system.gd")

var world: Node
var time := 0.0
var zones: Array = []      # {pos, r, dps, t, dur, owner, follow, pull, slow, col, tick}
var delayed: Array = []    # {at, fn: Callable}


func update(dt: float) -> void:
	time += dt
	for pid in world.run:
		var rp = world.run[pid]
		for sid in rp.spell_cd:
			rp.spell_cd[sid] = max(0.0, rp.spell_cd[sid] - dt)
		rp.dodge_cd = max(0.0, rp.dodge_cd - dt)
		_update_buffs(pid, rp, dt)
		if not rp.alive:
			continue
		_passives(pid, rp, dt)
	_update_zones(dt)
	var now := time
	var due := delayed.filter(func(d): return d.at <= now)
	delayed = delayed.filter(func(d): return d.at > now)
	for d in due:
		d.fn.call()


## Fin de vague : on nettoie les zones et effets en cours (les recharges sont conservées).
func clear_all() -> void:
	zones.clear()
	delayed.clear()
	for pid in world.run:
		var rp = world.run[pid]
		if not rp.buffs.is_empty():
			rp.buffs.clear()
			rp.recompute()
			world._broadcast_loadout(pid)


# ------------------------------------------------------------------ valeurs
static func value(def: Dictionary, key: String, rank: int, fallback = 0.0):
	var b = def.get("base", {}).get(key, fallback)
	var u = def.get("up", {}).get(key, 0.0)
	if b is Dictionary:
		var o := {}
		for k in b:
			o[k] = float(b[k]) + float(u.get(k, 0.0) if u is Dictionary else 0.0) * (rank - 1)
		return o
	if b is String:
		return b
	return float(b) + float(u) * (rank - 1)


func _power(rp) -> float:
	return (1.0 + rp.stats.damage / 100.0) * (1.0 + rp.stats.tech * 0.025)


## Les actifs suivent la difficulté des vagues (les PV des ennemis augmentent à chaque vague).
const ACTIVE_WAVE_SCALE := 0.12
const MAX_AIM_RANGE := 650.0


## Type de dégâts d'un actif (Mêlée / Distance / Techno) : +4 % par point de la statistique correspondante.
const DMG_TYPE_SCALE := 0.04


func _active_power(rp, def: Dictionary = {}) -> float:
	var st: String = def.get("dmg_type", "tech")
	var cls: float = float(rp.stats.get(st, 0.0)) if st in ["melee", "ranged", "tech"] else 0.0
	return (1.0 + rp.stats.damage / 100.0) * max(0.25, 1.0 + cls * DMG_TYPE_SCALE) * (1.0 + ACTIVE_WAVE_SCALE * max(0, world.wave - 1))


func _color(def: Dictionary) -> Color:
	return Color(def.get("color", "#ffffff"))


# ------------------------------------------------------------------ actifs
## Lance l'actif de l'emplacement `slot` (0..4) vers `aim`. Renvoie true si le sort est parti.
func cast(pid: int, slot: int, aim := Vector2.INF) -> bool:
	var rp = world.run.get(pid)
	if rp == null or not rp.alive or world.state != "wave" or slot < 0 or slot >= rp.actives.size():
		return false
	var sid: String = rp.actives[slot]
	if rp.spell_cd.get(sid, 0.0) > 0.0:
		return false
	var def: Dictionary = Db.spells.spells[sid]
	var rank: int = rp.spells.get(sid, 1)
	var pos: Vector2 = world.player_pos(pid)
	if pos == Vector2.INF:
		return false
	var cd: float = max(1.0, value(def, "cd", rank, 8.0)) * rp.cooldown_mult()
	rp.spell_cd[sid] = cd
	rp.casts += 1
	_effect(pid, rp, def, rank, pos, _resolve_aim(pid, pos, aim))
	world.ev_u(["SC", pid, slot, cd])
	world.ev_u(["T", int(pos.x), int(pos.y - 70), def.name, _color(def).to_rgba32()])
	return true


## Point visé, limité à la portée maximale. Sans point précis (manette sans stick, lancement automatique) :
## dans la direction de visée du joueur (curseur / stick), à mi-portée.
func _resolve_aim(pid: int, pos: Vector2, aim: Vector2) -> Vector2:
	if aim == Vector2.INF or not aim.is_finite():
		var rp = world.run.get(pid)
		var d0: Vector2 = rp.aim_dir if rp else Vector2.RIGHT
		return world.clamp_to_bounds(pos + d0 * 300.0, 10)
	var d := aim - pos
	if d.length() > MAX_AIM_RANGE:
		aim = pos + d.normalized() * MAX_AIM_RANGE
	return world.clamp_to_bounds(aim, 10)


func _effect(pid: int, rp, def: Dictionary, rank: int, pos: Vector2, aim: Vector2) -> void:
	var col := _color(def)
	var pw := _active_power(rp, def)
	match def.kind:
		"nova":   # frappe : explosion à l'endroit visé
			var r: float = value(def, "radius", rank, 150.0)
			world.ev_u(["C", PackedFloat32Array([pos.x, pos.y - 30, aim.x, aim.y]), col.to_rgba32()])
			_nova(pid, aim, r, value(def, "dmg", rank) * pw, value(def, "knock", rank, 40.0), col)
		"bolt":
			_bolt(pid, rp, def, rank, pos, pw, aim)
		"chain":   # premier éclair sur l'ennemi le plus proche du point visé
			_chain(pid, pos, value(def, "dmg", rank) * pw, int(value(def, "jumps", rank, 3.0)), value(def, "range", rank, 220.0), col, aim)
		"zone":
			var at: String = value(def, "at", rank, "target")
			var zpos := pos
			if at == "target":
				zpos = aim
			_zone(pid, zpos, value(def, "radius", rank, 130.0), value(def, "dps", rank) * pw, value(def, "dur", rank, 3.0),
				value(def, "pull", rank, 0.0), value(def, "slow", rank, 0.0), col, pid if at == "follow" else 0)
		"buff":
			_buff(pid, rp, value(def, "stats", rank, {}), value(def, "dur", rank, 5.0), col)
		"heal":
			var heal: float = rp.max_hp() * value(def, "pct", rank, 20.0) / 100.0
			rp.hp = min(rp.max_hp(), rp.hp + heal)
			rp.shield_left += int(value(def, "shield", rank, 0.0))
			world.ev_u(["H", int(pos.x), int(pos.y), 110.0])
			world.ev_u(["T", int(pos.x), int(pos.y - 40), "+%d PV" % int(heal), Color("#06ffa5").to_rgba32()])
			world.ev_u(["A", "soin", int(pos.x), int(pos.y)])
		"summon":
			_buff(pid, rp, {"drones": value(def, "drones", rank, 2.0)}, value(def, "dur", rank, 8.0), col)
		"laser":   # rayon instantané vers le curseur : tout ce qui est sur la ligne est touché (visée précise)
			var dir: Vector2 = (aim - pos).normalized()
			if dir == Vector2.ZERO:
				dir = Vector2.RIGHT
			var a: Vector2 = pos + dir * 24.0
			var b: Vector2 = pos + dir * value(def, "length", rank, 800.0)
			var width: float = value(def, "width", rank, 16.0)
			_line_hit(pid, a, b, width * 0.5, value(def, "dmg", rank) * pw, col, value(def, "slow", rank, 0.0))
			world.ev_u(["L", int(a.x), int(a.y), int(b.x), int(b.y), width, col.to_rgba32()])
			world.ev_u(["A", "laser", int(pos.x), int(pos.y)])
			world.combat.shake(3)
		"strike":   # frappe annoncée à l'endroit exact visé, petit rayon, énormes dégâts
			var r2: float = value(def, "radius", rank, 65.0)
			var delay: float = value(def, "delay", rank, 0.8)
			var dmg2: float = value(def, "dmg", rank) * pw
			world.ev_u(["W", int(aim.x), int(aim.y), r2, delay, col.to_rgba32()])
			var owner := pid
			delayed.append({"at": time + delay, "fn": func():
				if world.state != "wave":
					return
				world.combat.explode(aim, r2, dmg2, owner, false)
				world.ev_u(["L", int(aim.x), int(aim.y - 900), int(aim.x), int(aim.y), r2 * 0.8, col.to_rgba32()])
				world.combat.shake(8)})
		"barrage":   # pluie d'explosions autour du point visé
			_barrage(pid, aim, value(def, "dmg", rank) * pw, value(def, "radius", rank, 80.0), int(value(def, "count", rank, 5.0)), value(def, "dur", rank, 1.5), col, true)


func _nova(pid: int, pos: Vector2, radius: float, dmg: float, knock: float, col: Color) -> void:
	var crit: bool = randf() * 100.0 < world.run[pid].stats.crit
	if crit:
		dmg *= 2.0 + world.run[pid].stats.crit_dmg / 100.0
	world.combat._area_hit(pid, pos, radius, Vector2.ZERO, TAU, dmg, crit, Vector2.ZERO, knock, "sort")
	world.ev_u(["E", int(pos.x), int(pos.y), radius, col.to_rgba32()])
	world.ev_u(["A", "explosion", int(pos.x), int(pos.y)])
	world.combat.shake(4)


func _bolt(pid: int, rp, def: Dictionary, rank: int, pos: Vector2, pw: float, aim := Vector2.INF) -> void:
	var count := int(value(def, "count", rank, 3.0))
	var spd: float = value(def, "speed", rank, 850.0)
	var aoe: float = value(def, "aoe", rank, 0.0)
	var spread: float = deg_to_rad(value(def, "spread", rank, 30.0))
	if aim == Vector2.INF:
		aim = world.combat._find_target(pid, pos, 900.0).get("pos", pos + Vector2(1, 0))
	var dir: Vector2 = (aim - pos).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var col := _color(def)
	for i in count:
		var a := dir.angle()
		if count > 1:
			a += spread * (float(i) / (count - 1) - 0.5)
		var r: Array = world.combat._roll(rp, value(def, "dmg", rank) * pw)
		world.projectiles.spawn(PK.Kind.ROCKET if aoe > 0 else PK.Kind.BULLET, pos + dir * 30, Vector2.from_angle(a) * spd, 1.1, 9.0, col, pid, r[0],
			{"crit": r[1], "pierce": int(value(def, "pierce", rank, 0.0)), "aoe": aoe, "knock": 20.0, "weapon": "sort"})
	world.ev_u(["A", "roquette" if aoe > 0 else "laser", int(pos.x), int(pos.y)])


func _chain(pid: int, pos: Vector2, dmg: float, jumps: int, rng: float, col: Color, aim := Vector2.INF) -> void:
	var tgt: Dictionary = world.combat._find_target(pid, aim if aim != Vector2.INF else pos, rng * 1.8)
	var pts := [pos.x, pos.y]
	var hit := {}
	for j in jumps + 1:
		if tgt.is_empty():
			break
		var cur: Vector2 = tgt.pos
		pts.append_array([cur.x, cur.y])
		if tgt.has("enemy"):
			hit[tgt.enemy.id] = true
			world.combat.damage_enemy(tgt.enemy, dmg * pow(0.9, j), false, pid, Vector2.ZERO, 0, Color(), "sort")
		else:
			hit[-int(tgt.player)] = true
			world.combat.hit_player(tgt.player, dmg * pow(0.9, j), cur, pid)
		tgt = world.combat._next_chain(pid, cur, rng, hit)
	if pts.size() > 2:
		world.ev_u(["C", PackedFloat32Array(pts), col.to_rgba32()])
		world.ev_u(["A", "tesla", int(pos.x), int(pos.y)])


func _zone(pid: int, pos: Vector2, r: float, dps: float, dur: float, pull: float, slow: float, col: Color, follow := 0) -> void:
	zones.append({"pos": pos, "r": r, "dps": dps, "t": 0.0, "dur": dur, "owner": pid, "follow": follow, "pull": pull, "slow": slow, "col": col, "tick": 0.0})
	world.ev_u(["Z", int(pos.x), int(pos.y), r, dur, col.to_rgba32(), follow])


func _update_zones(dt: float) -> void:
	for z in zones:
		z.t += dt
		if z.follow != 0:
			var fp: Vector2 = world.player_pos(z.follow)
			if fp != Vector2.INF:
				z.pos = fp
		for e in world.enemies.query(z.pos, z.r):
			if z.pull > 0 and not e.boss:
				e.knock += (z.pos - e.pos).normalized() * z.pull * dt * 6.0
			if z.slow > 0:
				e.slow = max(e.slow, z.slow)
				e.slow_t = 0.3
		z.tick -= dt
		if z.tick <= 0:
			z.tick = 0.25
			world.combat._area_hit(z.owner, z.pos, z.r, Vector2.ZERO, TAU, z.dps * 0.25, false, Vector2.ZERO, 0, "sort")
	zones = zones.filter(func(z): return z.t < z.dur)


func _buff(pid: int, rp, st: Dictionary, dur: float, col: Color) -> void:
	rp.buffs.append({"stats": st, "t": dur})
	var before: float = rp.max_hp()
	rp.recompute()
	if rp.max_hp() > before:
		rp.hp += rp.max_hp() - before
	world._broadcast_loadout(pid)
	world.ev_u(["AU", pid, col.to_rgba32(), dur])
	world.ev_u(["A", "niveau", int(world.player_pos(pid).x), int(world.player_pos(pid).y)])


func _update_buffs(pid: int, rp, dt: float) -> void:
	if rp.buffs.is_empty():
		return
	var changed := false
	for b in rp.buffs:
		b.t -= dt
		if b.t <= 0:
			changed = true
	if changed:
		rp.buffs = rp.buffs.filter(func(b): return b.t > 0)
		rp.recompute()
		rp.hp = min(rp.hp, rp.max_hp())
		world._broadcast_loadout(pid)


func _barrage(pid: int, pos: Vector2, dmg: float, radius: float, count: int, dur: float, col: Color, aimed := false) -> void:
	var targets: Array = world.enemies.query(pos, 180.0 if aimed else 650.0)
	for i in count:
		var p: Vector2
		if aimed and (targets.is_empty() or i % 2 == 1):
			p = pos + Vector2.from_angle(randf() * TAU) * randf_range(0, 150)
		elif not targets.is_empty():
			p = targets[randi() % targets.size()].pos + Vector2(randf_range(-30, 30), randf_range(-30, 30))
		else:
			p = pos + Vector2.from_angle(randf() * TAU) * randf_range(80, 320)
		p = world.clamp_to_arena(p, 10)
		var delay = 0.35 + dur * float(i) / max(1, count)
		world.ev_u(["W", int(p.x), int(p.y), radius, delay, col.to_rgba32()])
		var owner := pid
		delayed.append({"at": time + delay, "fn": func():
			if world.state != "wave":
				return
			world.combat.explode(p, radius, dmg, owner, false)})


# ------------------------------------------------------------------ passifs
func _passives(pid: int, rp, dt: float) -> void:
	var pos: Vector2 = world.player_pos(pid)
	if pos == Vector2.INF:
		return
	for sid in rp.spells:
		var def: Dictionary = Db.spells.spells[sid]
		if def.type != "passive":
			continue
		var rank: int = rp.spells[sid]
		match def.kind:
			"aura":
				var key: String = "aura_" + sid
				rp.passive_t[key] = rp.passive_t.get(key, 0.0) - dt
				if rp.passive_t[key] <= 0:
					rp.passive_t[key] = 0.5
					var dmg: float = value(def, "dps", rank) * 0.5 * _power(rp)
					world.combat._area_hit(pid, pos, value(def, "radius", rank, 100.0), Vector2.ZERO, TAU, dmg, false, Vector2.ZERO, 0, "sort")
			"periodic":
				var key2: String = "per_" + sid
				rp.passive_t[key2] = rp.passive_t.get(key2, 0.0) - dt
				if rp.passive_t[key2] <= 0:
					rp.passive_t[key2] = max(1.0, value(def, "every", rank, 5.0))
					var sub: Dictionary = def.duplicate(true)
					sub.kind = def.base.get("effect", "nova")
					if sub.kind == "nova":
						_nova(pid, pos, value(def, "radius", rank, 130.0), value(def, "dmg", rank) * _power(rp), value(def, "knock", rank, 20.0), _color(def))
					else:
						if world.combat._find_target(pid, pos, 700.0).is_empty():
							rp.passive_t[key2] = 0.5
							continue
						_bolt(pid, rp, sub, rank, pos, _power(rp))


# ------------------------------------------------------------------ esquive (Espace)
## Esquive déclenchée : `from` = position avant, `to` = position visée / atteinte (blink).
func dodge(pid: int, from: Vector2, to: Vector2) -> bool:
	var rp = world.run.get(pid)
	if rp == null or not rp.alive or world.state != "wave" or rp.dodge_cd > 0.15:
		return false
	var def: Dictionary = Db.spells.dodges.get(rp.character, Db.spells.dodges.patatron)
	rp.dodge_cd = rp.dodge_cooldown()
	rp.dodges += 1
	rp.invuln = max(rp.invuln, float(def.iframes))
	var col := Color(def.color)
	var pw := _power(rp)
	world.ev_u(["DG", pid, def.kind, int(from.x), int(from.y), int(to.x), int(to.y), col.to_rgba32()])
	match def.kind:
		"dash", "grapple":
			if def.has("buff"):
				_buff(pid, rp, def.buff, float(def.buff_dur), col)
		"blink":
			var dmg: float = float(def.dmg) * pw
			for p in [from, to]:
				world.combat._area_hit(pid, p, float(def.radius), Vector2.ZERO, TAU, dmg, false, Vector2.ZERO, 30, "sort")
				world.ev_u(["E", int(p.x), int(p.y), float(def.radius), col.to_rgba32()])
			world.ev_u(["C", PackedFloat32Array([from.x, from.y, to.x, to.y]), col.to_rgba32()])
		"jump":
			var owner := pid
			delayed.append({"at": time + float(def.time), "fn": func():
				var lp: Vector2 = world.player_pos(owner)
				if lp == Vector2.INF or world.state != "wave":
					return
				world.combat._area_hit(owner, lp, float(def.radius), Vector2.ZERO, TAU, float(def.dmg) * pw, false, Vector2.ZERO, float(def.knock), "sort")
				world.ev_u(["E", int(lp.x), int(lp.y), float(def.radius), col.to_rgba32()])
				world.ev_u(["A", "explosion", int(lp.x), int(lp.y)])
				world.combat.shake(7)})
		"phase":
			var owner2 := pid
			delayed.append({"at": time + float(def.time), "fn": func():
				var end: Vector2 = world.player_pos(owner2)
				if end == Vector2.INF:
					return
				_line_hit(owner2, from, end, float(def.width), float(def.dmg) * pw, col)})
		"rocket":
			var owner3 := pid
			for i in 4:
				delayed.append({"at": time + float(def.time) * (i / 3.0), "fn": func():
					var p2: Vector2 = world.player_pos(owner3)
					if p2 != Vector2.INF and world.state == "wave":
						_zone(owner3, p2, float(def.radius), float(def.dps) * pw, float(def.trail), 0.0, 0.0, col)})
	return true


func _line_hit(pid: int, a: Vector2, b: Vector2, width: float, dmg: float, col: Color, slow := 0.0) -> void:
	var mid := (a + b) / 2.0
	for e in world.enemies.query(mid, a.distance_to(b) / 2.0 + width):
		var cp := Geometry2D.get_closest_point_to_segment(e.pos, a, b)
		if cp.distance_to(e.pos) <= width + e.radius:
			if slow > 0:
				e.slow = max(e.slow, slow)
				e.slow_t = 2.5
			world.combat.damage_enemy(e, dmg, false, pid, (b - a).normalized(), 30, Color(), "sort")
	if world.pvp:
		for t in world.alive_targets():
			if world.is_foe(pid, t[0]) and Geometry2D.get_closest_point_to_segment(t[1], a, b).distance_to(t[1]) <= width + 20:
				world.combat.hit_player(t[0], dmg, t[1], pid)


# ------------------------------------------------------------------ IA (bots et lancement automatique)
## Lance automatiquement les actifs prêts quand des ennemis sont à portée.
func auto_cast(pid: int) -> void:
	var rp = world.run.get(pid)
	if rp == null or not rp.alive:
		return
	var pos: Vector2 = world.player_pos(pid)
	if world.combat._find_target(pid, pos, 420.0).is_empty():
		return
	for slot in rp.actives.size():
		var sid: String = rp.actives[slot]
		if rp.spell_cd.get(sid, 0.0) <= 0.0:
			var def: Dictionary = Db.spells.spells[sid]
			if def.kind == "heal" and rp.hp > rp.max_hp() * 0.6:
				continue
			cast(pid, slot, Vector2.INF)
			return
