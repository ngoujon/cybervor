extends Node2D
## Effets visuels éphémères, déclenchés par les événements du serveur (identiques sur tous les pairs).

var world: Node
var fx: Array = []          # {kind, t, dur, ...}
var parts: Array = []       # particules {pos, vel, t, dur, color, size}
var font: Font
var headless := false

const KILL_COLORS := [Color("#5ff7ff"), Color("#ff5fd2"), Color("#ffd166"), Color("#9dff6b")]


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"
	font = Ui.font_bold
	z_index = 500


func handle(ev: Array) -> void:
	if headless:
		return
	match ev[0]:
		"D":
			if not Settings.damage_numbers:
				return
			var col: Color = Color.hex(ev[5]) if ev[5] != 0 else (Color("#ffd166") if ev[4] else Color.WHITE)
			fx.append({"kind": "num", "t": 0.0, "dur": 0.7, "pos": Vector2(ev[1] + randf_range(-10, 10), ev[2]), "text": str(ev[3]), "col": col, "big": ev[4]})
		"T":
			fx.append({"kind": "num", "t": 0.0, "dur": 1.1, "pos": Vector2(ev[1], ev[2]), "text": ev[3], "col": Color.hex(ev[4]), "big": true})
		"K":
			var pos := Vector2(ev[1], ev[2])
			var n := 14 if ev[4] else 7
			for i in n:
				parts.append({"pos": pos, "vel": Vector2.from_angle(randf() * TAU) * randf_range(80, 260 if ev[4] else 180), "t": 0.0,
					"dur": randf_range(0.3, 0.6), "color": KILL_COLORS[randi() % KILL_COLORS.size()], "size": randf_range(3, 7 if ev[4] else 5)})
			fx.append({"kind": "ring", "t": 0.0, "dur": 0.25, "pos": pos, "r": 40.0 if ev[4] else 24.0, "col": Color(1, 1, 1, 0.7)})
			Audio.play_at("mort_gros" if ev[4] else "mort_ennemi", pos, -4 if ev[4] else -9)
		"E":
			fx.append({"kind": "boom", "t": 0.0, "dur": 0.35, "pos": Vector2(ev[1], ev[2]), "r": ev[3], "col": Color.hex(ev[4])})
			for i in 10:
				parts.append({"pos": Vector2(ev[1], ev[2]), "vel": Vector2.from_angle(randf() * TAU) * randf_range(100, 300), "t": 0.0,
					"dur": randf_range(0.3, 0.5), "color": Color("#ffb347"), "size": randf_range(4, 8)})
		"S":
			fx.append({"kind": "slash", "t": 0.0, "dur": 0.18, "pos": Vector2(ev[1], ev[2]), "a": ev[3], "r": ev[4], "arc": ev[5], "col": Color.hex(ev[6])})
		"C":
			fx.append({"kind": "chain", "t": 0.0, "dur": 0.2, "pts": ev[1], "col": Color.hex(ev[2]), "seed": randi()})
		"F":
			fx.append({"kind": "flame", "t": 0.0, "dur": 0.22, "pos": Vector2(ev[1], ev[2]), "a": ev[3], "r": ev[4], "arc": ev[5]})
		"H":
			fx.append({"kind": "ring", "t": 0.0, "dur": 0.6, "pos": Vector2(ev[1], ev[2]), "r": ev[3], "col": Color("#06ffa5")})
		"B":
			fx.append({"kind": "ring", "t": 0.0, "dur": 0.35, "pos": Vector2(ev[1], ev[2]), "r": 50.0, "col": Color("#c77dff")})
		"A":
			Audio.play_at(ev[1], Vector2(ev[2], ev[3]), -7)
		"PH":
			world.on_player_hurt_visual(ev[1], ev[2])
		"SH":
			world.add_shake(ev[1])
		"SC":   # sort lancé : recharge (affichée par le HUD du lanceur)
			if int(ev[1]) == Net.my_id():
				world.my_cd[int(ev[2])] = [world.server_time + float(ev[3]), float(ev[3])]
		"Z":    # zone persistante (sorts de zone, traînée de flammes)
			fx.append({"kind": "zone", "t": 0.0, "dur": float(ev[4]), "pos": Vector2(ev[1], ev[2]), "r": float(ev[3]), "col": Color.hex(ev[5]), "follow": int(ev[6]), "seed": randf() * TAU})
		"L":    # rayon laser (sorts « laser », frappe orbitale)
			fx.append({"kind": "beam", "t": 0.0, "dur": 0.35, "a": Vector2(ev[1], ev[2]), "b": Vector2(ev[3], ev[4]), "w": float(ev[5]), "col": Color.hex(ev[6])})
			for i in 8:
				parts.append({"pos": Vector2(ev[3], ev[4]), "vel": Vector2.from_angle(randf() * TAU) * randf_range(80, 260), "t": 0.0,
					"dur": randf_range(0.2, 0.4), "color": Color.hex(ev[6]), "size": randf_range(3, 6)})
		"W":    # impact annoncé (pluie de projectiles) : cercle d'avertissement
			fx.append({"kind": "warn", "t": 0.0, "dur": float(ev[4]), "pos": Vector2(ev[1], ev[2]), "r": float(ev[3]), "col": Color.hex(ev[5])})
		"AU":   # aura de bonus temporaire autour d'un joueur
			fx.append({"kind": "aura", "t": 0.0, "dur": float(ev[3]), "pid": int(ev[1]), "col": Color.hex(ev[2])})
		"DG":   # esquive
			var from := Vector2(ev[3], ev[4])
			var to := Vector2(ev[5], ev[6])
			var dcol := Color.hex(ev[7])
			world.on_dodge_visual(int(ev[1]), ev[2], from, to, dcol)
			fx.append({"kind": "ring", "t": 0.0, "dur": 0.3, "pos": from, "r": 46.0, "col": dcol})
			if ev[2] == "blink":
				fx.append({"kind": "ring", "t": 0.0, "dur": 0.35, "pos": to, "r": 60.0, "col": Color.WHITE})
			for i in 10:
				parts.append({"pos": from, "vel": Vector2.from_angle(randf() * TAU) * randf_range(60, 200), "t": 0.0,
					"dur": randf_range(0.25, 0.45), "color": dcol, "size": randf_range(3, 6)})
			Audio.play_at("dash", from, -6)
		"LV":
			var p := Vector2(ev[1], ev[2])
			fx.append({"kind": "ring", "t": 0.0, "dur": 0.6, "pos": p, "r": 90.0, "col": Color("#ffd166")})
			fx.append({"kind": "num", "t": 0.0, "dur": 1.2, "pos": p + Vector2(0, -70), "text": "NIVEAU +1 !", "col": Color("#ffd166"), "big": true})


func _process(delta: float) -> void:
	if headless:
		return
	for f in fx:
		f.t += delta
	fx = fx.filter(func(f): return f.t < f.dur)
	for p in parts:
		p.t += delta
		p.pos += p.vel * delta
		p.vel *= 0.92
	parts = parts.filter(func(p): return p.t < p.dur)
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var k: float = 1.0 - p.t / p.dur
		draw_circle(p.pos, p.size * k + 1, Color(p.color, k))
	for f in fx:
		var k: float = f.t / f.dur
		match f.kind:
			"num":
				var pos: Vector2 = f.pos + Vector2(0, -40 * k)
				var size := 30 if f.big else 22
				var col: Color = f.col
				col.a = 1.0 - max(0.0, k - 0.6) / 0.4
				var w = font.get_string_size(f.text, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
				draw_string_outline(font, pos - Vector2(w / 2, 0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 6, Color(0, 0, 0, col.a))
				draw_string(font, pos - Vector2(w / 2, 0), f.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
			"ring":
				draw_arc(f.pos, f.r * (0.4 + 0.6 * k), 0, TAU, 32, Color(f.col, 1.0 - k), 4)
			"boom":
				var r: float = f.r * (0.3 + 0.7 * sqrt(k))
				draw_circle(f.pos, r, Color(f.col, 0.45 * (1.0 - k)))
				draw_circle(f.pos, r * 0.6, Color(1, 1, 0.8, 0.6 * (1.0 - k)))
				draw_arc(f.pos, r, 0, TAU, 40, Color(0, 0, 0, 0.6 * (1.0 - k)), 4)
			"slash":
				var a0: float = f.a - f.arc / 2
				var a1: float = f.a + f.arc / 2
				var sweep: float = lerp(a0, a1, min(1.0, k * 1.6))
				draw_arc(f.pos, f.r * 0.8, a0, sweep, 20, Color(0, 0, 0, 0.5 * (1.0 - k)), 22)
				draw_arc(f.pos, f.r * 0.8, a0, sweep, 20, Color(f.col, 0.9 * (1.0 - k)), 14)
				draw_arc(f.pos, f.r * 0.8, a0, sweep, 20, Color(1, 1, 1, 0.8 * (1.0 - k)), 4)
			"chain":
				var pts: PackedFloat32Array = f.pts
				var rng := RandomNumberGenerator.new()
				rng.seed = f.seed + int(f.t * 30)
				for i in range(0, pts.size() - 2, 2):
					var a := Vector2(pts[i], pts[i + 1])
					var b := Vector2(pts[i + 2], pts[i + 3])
					var line := PackedVector2Array([a])
					for s in range(1, 6):
						var m = a.lerp(b, s / 6.0) + Vector2(rng.randf_range(-12, 12), rng.randf_range(-12, 12))
						line.append(m)
					line.append(b)
					draw_polyline(line, Color(f.col, 0.5 * (1.0 - k)), 9)
					draw_polyline(line, Color(1, 1, 1, 1.0 - k), 3)
			"zone":
				var zp: Vector2 = f.pos
				if f.follow != 0 and world.player_nodes.has(f.follow):
					zp = world.player_nodes[f.follow].position
				var fade: float = min(1.0, f.t / 0.2) * min(1.0, (f.dur - f.t) / 0.3)
				var pulse: float = 0.5 + 0.5 * sin(f.t * 6.0)
				draw_circle(zp, f.r, Color(f.col, 0.16 * fade))
				draw_arc(zp, f.r, 0, TAU, 48, Color(f.col, 0.75 * fade), 4)
				for i in 3:
					var rr: float = f.r * fmod(f.t * 0.6 + i / 3.0, 1.0)
					draw_arc(zp, rr, 0, TAU, 32, Color(f.col, 0.35 * fade * (1.0 - rr / f.r)), 3)
				for i in 6:
					var a: float = f.seed + f.t * 1.4 + TAU * i / 6.0
					draw_circle(zp + Vector2.from_angle(a) * f.r * (0.55 + 0.25 * pulse), 6, Color(f.col, 0.6 * fade))
			"beam":
				var fade: float = 1.0 - k
				var w: float = f.w * (1.0 + 0.5 * (1.0 - fade))
				draw_line(f.a, f.b, Color(f.col, 0.25 * fade), w * 2.6)
				draw_line(f.a, f.b, Color(f.col, 0.8 * fade), w)
				draw_line(f.a, f.b, Color(1, 1, 1, 0.95 * fade), max(2.0, w * 0.35))
				draw_circle(f.a, w * 0.9, Color(1, 1, 1, 0.8 * fade))
			"warn":
				var kk: float = clamp(f.t / f.dur, 0.0, 1.0)
				draw_circle(f.pos, f.r * kk, Color(f.col, 0.18 + 0.12 * kk))
				draw_arc(f.pos, f.r, 0, TAU, 32, Color(f.col, 0.85), 3)
				draw_line(f.pos + Vector2(-12, 0), f.pos + Vector2(12, 0), Color(f.col, 0.9), 3)
				draw_line(f.pos + Vector2(0, -12), f.pos + Vector2(0, 12), Color(f.col, 0.9), 3)
			"aura":
				if world.player_nodes.has(f.pid):
					var ap: Vector2 = world.player_nodes[f.pid].position + Vector2(0, -20)
					var fa: float = min(1.0, (f.dur - f.t) / 0.4)
					for i in 2:
						var ar: float = 52.0 + 8.0 * sin(f.t * 5.0 + i * PI)
						draw_arc(ap, ar, f.t * 2.0 + i * PI, f.t * 2.0 + i * PI + PI * 1.3, 24, Color(f.col, 0.75 * fa), 4)
			"flame":
				for i in 6:
					var aa: float = f.a + randf_range(-f.arc / 2, f.arc / 2)
					var d: float = randf_range(0.3, 1.0) * f.r
					var c := Color(1.0, randf_range(0.4, 0.8), 0.1, 0.55 * (1.0 - k))
					draw_circle(f.pos + Vector2.from_angle(aa) * d, randf_range(8, 18) * (0.5 + d / f.r), c)
