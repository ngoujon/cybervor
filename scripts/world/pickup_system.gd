extends Node2D
## Objets au sol : données (monnaie + XP), batteries de soin, coffres (objet gratuit).

const TYPES := ["data", "soin", "coffre"]
const TEX := {
	"data": "res://assets/sprites/pickups/data.png",
	"soin": "res://assets/sprites/pickups/soin.png",
	"coffre": "res://assets/sprites/pickups/coffre.png",
}
const SIZE := {"data": 30.0, "soin": 40.0, "coffre": 58.0}


class Pickup:
	var id := 0
	var type := "data"
	var pos := Vector2.ZERO
	var value := 1
	var magnet := 0
	var speed := 0.0
	var alive := true
	var fly_to := Vector2.INF
	var fly_t := 0.0
	var phase := 0.0


var world: Node
var list: Array = []
var by_id: Dictionary = {}
var next_id := 1
var headless := false
var _tex := {}
var _time := 0.0


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	for k in TEX:
		_tex[k] = Db.tex(TEX[k])


func clear_all() -> void:
	list.clear()
	by_id.clear()


func spawn_pickup(type: String, pos: Vector2, value: int) -> void:
	var p := Pickup.new()
	p.id = next_id
	next_id += 1
	p.type = type
	p.pos = world.clamp_to_arena(pos, 10)
	p.value = value
	p.phase = randf() * TAU
	list.append(p)
	by_id[p.id] = p
	world.ev_r(["U", p.id, TYPES.find(type), int(p.pos.x), int(p.pos.y)])


func server_update(dt: float) -> void:
	var targets: Array = world.alive_targets()
	if targets.is_empty():
		return
	for p in list:
		if not p.alive:
			continue
		if p.magnet == 0:
			for t in targets:
				var rp = world.run[t[0]]
				var r: float = rp.pickup_range() if p.type == "data" else 60.0
				if p.pos.distance_squared_to(t[1]) < r * r:
					p.magnet = t[0]
					p.speed = 250.0
					break
		if p.magnet != 0:
			var tp: Vector2 = world.player_pos(p.magnet)
			if tp == Vector2.INF or not world.run[p.magnet].alive:
				p.magnet = 0
				continue
			p.speed += 1800.0 * dt
			p.pos = p.pos.move_toward(tp, p.speed * dt)
			if p.pos.distance_squared_to(tp) < 26 * 26:
				_collect(p, p.magnet)
	list = list.filter(func(x): return x.alive)


func _collect(p: Pickup, pid: int) -> void:
	p.alive = false
	by_id.erase(p.id)
	world.ev_r(["u", p.id, pid])
	world.on_pickup(p.type, p.value, pid)


## Fin de vague : tout ce qui reste est aspiré vers les joueurs vivants.
func vacuum() -> void:
	var targets: Array = world.alive_targets()
	if targets.is_empty():
		targets = []
		for pid in world.run:
			targets.append([pid, world.player_pos(pid)])
	if targets.is_empty():
		return
	for p in list:
		if not p.alive or p.type == "soin":
			continue
		var best = targets[0]
		var bd := INF
		for t in targets:
			var d: float = p.pos.distance_squared_to(t[1])
			if d < bd:
				bd = d
				best = t
		_collect(p, best[0])
	for p in list:
		if p.alive:
			p.alive = false
			world.ev_r(["u", p.id, 0])
	list.clear()
	by_id.clear()


# ------------------------------------------------------------------ client
func client_event(ev: Array) -> void:
	match ev[0]:
		"U":
			var p := Pickup.new()
			p.id = ev[1]
			p.type = TYPES[ev[2]]
			p.pos = Vector2(ev[3], ev[4])
			p.phase = randf() * TAU
			list.append(p)
			by_id[p.id] = p
		"u":
			var p = by_id.get(ev[1])
			if p:
				by_id.erase(ev[1])
				var tp: Vector2 = world.player_pos(ev[2]) if ev[2] != 0 else Vector2.INF
				if tp == Vector2.INF:
					p.alive = false
				else:
					p.fly_to = tp
					p.fly_t = 0.15


func client_update(dt: float) -> void:
	for p in list:
		if p.fly_to != Vector2.INF:
			p.fly_t -= dt
			p.pos = p.pos.lerp(p.fly_to, min(1.0, dt * 18.0))
			if p.fly_t <= 0:
				p.alive = false
	list = list.filter(func(x): return x.alive)


func _process(delta: float) -> void:
	_time += delta
	if not headless:
		queue_redraw()


func _draw() -> void:
	for p in list:
		var t: Texture2D = _tex.get(p.type)
		var s: float = SIZE[p.type]
		var bob = sin(_time * 4.0 + p.phase) * 3.0
		if p.type == "data":
			draw_circle(p.pos, s * 0.5, Color(0.37, 0.97, 1.0, 0.15 + 0.1 * sin(_time * 6.0 + p.phase)))
		elif p.type == "coffre":
			draw_circle(p.pos, s * 0.7, Color(1.0, 0.82, 0.4, 0.2 + 0.1 * sin(_time * 5.0)))
		if t:
			draw_texture_rect(t, Rect2(p.pos - Vector2(s, s) / 2 + Vector2(0, bob), Vector2(s, s)), false)
		else:
			draw_circle(p.pos, s / 3, Color.CYAN)
