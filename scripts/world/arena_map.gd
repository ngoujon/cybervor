class_name ArenaMap
extends RefCounted
## Forme de l'arène et obstacles, générés à partir de la graine de la partie (identiques sur le serveur et
## chez les clients). Le contour est une « côte » organique (lobes, baies, presqu'îles) tracée autour du
## centre : chaque point de l'arène voit le centre en ligne droite, donc la zone est toujours d'un seul tenant.
## Au-delà du contour et dans les failles au sol, c'est le vide : les projectiles passent par-dessus, les
## corps (joueurs, ennemis, butin) glissent le long des bords.
## Règle de liberté de mouvement : il reste toujours au moins GAP pixels entre deux failles, ou entre une
## faille et le bord, pour que même un boss puisse passer.

const GAP := 270.0
const SHAPES := ["nebuleuse", "baies", "haricot", "atoll", "fragment", "recif"]
const N := 128               # sommets du contour (angles réguliers autour du centre)

static var force_shape := ""   # captures de test uniquement

var bounds: Rect2
var shape := "nebuleuse"
var center := Vector2.ZERO
var outline := PackedVector2Array()   # contour praticable, sommet i à l'angle TAU * i / N
var _in_n := PackedVector2Array()     # normale vers l'intérieur de l'arête i (sommet i -> i + 1)
var blocks: Array = []      # failles : {poly: PackedVector2Array, aabb: Rect2, c: Vector2, kind: "faille"}
var _clear: Array = []      # zones à garder libres : [centre, rayon]


func _init(arena: Rect2, seed_value: int, opts := {}) -> void:
	bounds = arena
	center = arena.get_center()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 7919 + 13
	var pvp: bool = opts.get("pvp", false)
	shape = opts.get("shape", SHAPES[rng.randi() % SHAPES.size()])
	if force_shape != "":
		shape = force_shape
	for c in opts.get("clear", []):
		_clear.append(c)
	_build_outline(rng, pvp)
	_place_pits(rng, int(opts.get("pits", rng.randi_range(4, 7))), pvp)
	# garantie finale : si une faille isole un recoin trop étroit pour un boss, on la retire
	while not blocks.is_empty() and not _reachable_everywhere(96.0):
		blocks.pop_back()
		if pvp and not blocks.is_empty():
			blocks.pop_back()   # les failles vont par paires symétriques
	_build_grid()


# ------------------------------------------------------------------ génération du contour
## Rayon du contour : une ellipse qui remplit l'arène, déformée par des ondulations (lobes), creusée de
## baies et gonflée de presqu'îles selon la famille de forme. En PvP, le contour est symétrique gauche/droite.
func _build_outline(rng: RandomNumberGenerator, mirror: bool) -> void:
	var waves: Array = []     # [k, amplitude, phase]
	var dents: Array = []     # [angle, profondeur (+ creuse, - gonfle), largeur]
	var w := func(kmin: int, kmax: int, amin: float, amax: float, n: int) -> void:
		for i in n:
			waves.append([rng.randi_range(kmin, kmax), rng.randf_range(amin, amax), rng.randf() * TAU])
	var d := func(n: int, dmin: float, dmax: float, wmin: float, wmax: float) -> void:
		for i in n:
			dents.append([rng.randf() * TAU, rng.randf_range(dmin, dmax), rng.randf_range(wmin, wmax)])
	match shape:
		"nebuleuse":   # gros lobes arrondis
			w.call(3, 5, 0.1, 0.17, 2)
			w.call(6, 9, 0.02, 0.04, 2)
		"baies":       # côte creusée de baies profondes
			w.call(2, 4, 0.03, 0.07, 2)
			d.call(rng.randi_range(2, 4), 0.28, 0.45, 0.18, 0.3)
		"haricot":     # forme allongée pincée d'un côté
			w.call(2, 2, 0.1, 0.16, 1)
			d.call(1, 0.3, 0.42, 0.35, 0.55)
			w.call(5, 8, 0.02, 0.04, 2)
		"atoll":       # rivage très découpé
			w.call(7, 13, 0.03, 0.06, 3)
			w.call(3, 4, 0.04, 0.08, 1)
		"fragment":    # asymétrique : un côté rongé, une presqu'île de l'autre
			w.call(1, 2, 0.08, 0.14, 1)
			d.call(2, 0.2, 0.34, 0.25, 0.4)
			d.call(1, -0.18, -0.12, 0.2, 0.3)
		"recif":       # nombreuses petites anses
			w.call(4, 6, 0.04, 0.07, 1)
			d.call(rng.randi_range(5, 7), 0.16, 0.26, 0.09, 0.15)
		_:             # « douce » : presque ronde (première mission)
			w.call(2, 4, 0.03, 0.06, 2)
	# un boss doit pouvoir aller partout : sinon, on adoucit les découpes jusqu'à ce que ce soit le cas
	for attempt in 6:
		_compute_outline(waves, dents, mirror, 1.0 - attempt * 0.17)
		if _reachable_everywhere(96.0):
			return


func _compute_outline(waves: Array, dents: Array, mirror: bool, amp: float) -> void:
	var hw := bounds.size.x * 0.5
	var hh := bounds.size.y * 0.5
	var r_min: float = min(hw, hh) * 0.55
	var radii := PackedFloat32Array()
	radii.resize(N)
	for i in N:
		var th := TAU * i / N
		var ev := th
		if mirror and cos(th) < 0.0:
			ev = PI - th          # symétrie gauche/droite
		var f := 1.0
		for wv in waves:
			f += amp * float(wv[1]) * cos(int(wv[0]) * ev + float(wv[2]))
		for dt in dents:
			var da := wrapf(ev - float(dt[0]), -PI, PI)
			f -= amp * float(dt[1]) * exp(-pow(da / float(dt[2]), 2.0))
		var base := 1.0 / sqrt(pow(cos(th) / hw, 2.0) + pow(sin(th) / hh, 2.0))
		radii[i] = base * 0.86 * f
	# zones à garder dans l'arène (départs, apparition du boss)
	for z in _clear:
		var off: Vector2 = z[0] - center
		var dist := off.length()
		if dist < 1.0:
			for i in N:
				radii[i] = max(radii[i], float(z[1]) + 60.0)
			continue
		var span := atan2(float(z[1]), dist) + 0.12
		for i in N:
			if absf(wrapf(TAU * i / N - off.angle(), -PI, PI)) < span:
				radii[i] = max(radii[i], dist + float(z[1]) * 0.8)
	# lissage, puis bornes : jamais trop étroit, jamais hors du rectangle de l'arène
	for pass_i in 3:
		var sm := radii.duplicate()
		for i in N:
			sm[i] = radii[(i + N - 1) % N] * 0.25 + radii[i] * 0.5 + radii[(i + 1) % N] * 0.25
		radii = sm
	outline.resize(N)
	for i in N:
		var dir := Vector2.from_angle(TAU * i / N)
		var r_max := _ray_to_bounds(dir) - 6.0
		outline[i] = center + dir * clampf(radii[i], r_min, r_max)
	_in_n.resize(N)
	for i in N:
		var a := outline[i]
		var b := outline[(i + 1) % N]
		var n := (b - a).orthogonal().normalized()
		if n.dot(center - a) < 0:
			n = -n
		_in_n[i] = n


## Toutes les zones où tient un corps de rayon `margin` communiquent entre elles (grille de 40 px).
func _reachable_everywhere(margin: float) -> bool:
	var step := 40.0
	var gx := int(bounds.size.x / step)
	var gy := int(bounds.size.y / step)
	var free := {}
	for x in gx:
		for y in gy:
			var q := bounds.position + Vector2(x + 0.5, y + 0.5) * step
			if is_free(q, margin):
				free[Vector2i(x, y)] = true
	if free.is_empty():
		return false
	var start: Vector2i = free.keys()[0]
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for dd in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nq: Vector2i = c + dd
			if free.has(nq) and not seen.has(nq):
				seen[nq] = true
				todo.append(nq)
	return seen.size() == free.size()


func _ray_to_bounds(dir: Vector2) -> float:
	var hw := bounds.size.x * 0.5
	var hh := bounds.size.y * 0.5
	var tx := INF if absf(dir.x) < 0.0001 else hw / absf(dir.x)
	var ty := INF if absf(dir.y) < 0.0001 else hh / absf(dir.y)
	return min(tx, ty)


## Arête du contour traversée par le rayon centre -> p.
func _edge_of(p: Vector2) -> int:
	var a := wrapf((p - center).angle(), 0.0, TAU)
	return int(a / (TAU / N)) % N


## Distance signée au contour : positive à l'intérieur de l'arène, négative dans le vide.
func outline_distance(p: Vector2) -> float:
	var i := _edge_of(p)
	var inside := (p - outline[i]).dot(_in_n[i]) >= 0.0
	var best := INF
	for j in [i - 2, i - 1, i, i + 1, i + 2]:
		var k: int = (j + N) % N
		best = min(best, Geometry2D.get_closest_point_to_segment(p, outline[k], outline[(k + 1) % N]).distance_to(p))
	return best if inside else -best


func _push_outline(p: Vector2, margin: float) -> Vector2:
	var i := _edge_of(p)
	if (p - outline[i]).dot(_in_n[i]) < 0.0:
		p = Geometry2D.get_closest_point_to_segment(p, outline[i], outline[(i + 1) % N]) + _in_n[i] * (margin + 0.5)
	for j in [i - 1, i, i + 1]:
		var k: int = (j + N) % N
		var q := Geometry2D.get_closest_point_to_segment(p, outline[k], outline[(k + 1) % N])
		var dd := q.distance_to(p)
		if dd < margin:
			var away: Vector2 = (p - q) / dd if dd > 0.001 else _in_n[k]
			if away.dot(_in_n[k]) < 0.0:
				away = _in_n[k]
			p = q + away * (margin + 0.5)
	return p


## Failles au sol : formes convexes irrégulières, espacées d'au moins GAP les unes des autres et des bords.
func _place_pits(rng: RandomNumberGenerator, count: int, mirror: bool) -> void:
	var placed := 0
	var tries := 0
	while placed < count and tries < 300:
		tries += 1
		var r := rng.randf_range(70.0, 140.0)
		var half := bounds.grow(-(GAP * 0.6 + r))
		if half.size.x <= 0 or half.size.y <= 0:
			break
		var c := Vector2(rng.randf_range(half.position.x, half.end.x), rng.randf_range(half.position.y, half.end.y))
		if mirror:
			c.x = rng.randf_range(bounds.get_center().x + 120 + r, half.end.x)
		var poly := _random_convex(rng, c, r)
		var cand := [poly]
		if mirror:
			var m := PackedVector2Array()
			for i in range(poly.size() - 1, -1, -1):
				m.append(Vector2(2.0 * bounds.get_center().x - poly[i].x, poly[i].y))
			cand.append(m)
		var ok := true
		for p in cand:
			if not _fits(p):
				ok = false
				break
		if not ok:
			continue
		for p in cand:
			_add(p, "faille")
		placed += cand.size()


func _random_convex(rng: RandomNumberGenerator, c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var elong := rng.randf_range(1.0, 1.7)
	var rot := rng.randf() * TAU
	var n := rng.randi_range(11, 15)
	for i in n:
		var a := TAU * i / n + rng.randf_range(-0.12, 0.12)
		var v := Vector2(cos(a) * r * elong, sin(a) * r / elong * 1.15) * rng.randf_range(0.88, 1.0)
		pts.append(c + v.rotated(rot))
	var hull := Geometry2D.convex_hull(pts)
	hull.remove_at(hull.size() - 1)   # convex_hull referme le polygone
	return hull


func _fits(poly: PackedVector2Array) -> bool:
	for p in poly:
		if outline_distance(p) < GAP:
			return false
	for z in _clear:
		if _poly_distance(poly, z[0]) < float(z[1]):
			return false
	for b in blocks:
		for p in poly:
			if _poly_distance(b.poly, p) < GAP:
				return false
		for p in b.poly:
			if _poly_distance(poly, p) < GAP:
				return false
	return true


func _add(poly: PackedVector2Array, kind: String) -> void:
	if Geometry2D.is_polygon_clockwise(poly):
		poly.reverse()
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var aabb := Rect2(poly[0], Vector2.ZERO)
	for p in poly:
		aabb = aabb.expand(p)
	blocks.append({"poly": poly, "aabb": aabb, "c": c, "kind": kind})


# ------------------------------------------------------------------ requêtes
## Ramène un point dans la zone praticable (dans le contour, hors des failles), à `margin` pixels des bords.
func resolve(p: Vector2, margin := 0.0) -> Vector2:
	p = _clamp_bounds(p, margin)
	for it in 3:
		var moved := false
		var o := _push_outline(p, margin)
		if o != p:
			p = o
			moved = true
		for b in blocks:
			if not b.aabb.grow(margin).has_point(p):
				continue
			var q := _push_out(b, p, margin)
			if q != p:
				p = q
				moved = true
		p = _clamp_bounds(p, margin)
		if not moved:
			break
	return p


func is_free(p: Vector2, margin := 0.0) -> bool:
	if not bounds.grow(-margin).has_point(p) or outline_distance(p) < margin:
		return false
	for b in blocks:
		if b.aabb.grow(margin).has_point(p) and (Geometry2D.is_point_in_polygon(p, b.poly) or _poly_distance(b.poly, p) < margin):
			return false
	return true


func random_free_point(rng: RandomNumberGenerator, margin := 60.0) -> Vector2:
	for i in 40:
		var p := Vector2(rng.randf_range(bounds.position.x + margin, bounds.end.x - margin), rng.randf_range(bounds.position.y + margin, bounds.end.y - margin))
		if is_free(p, margin):
			return p
	return resolve(bounds.get_center(), margin)


## Contournement : si la direction mène droit dans un obstacle proche, on la fait glisser le long de son bord.
## `reach` : distance de la cible (on ne contourne pas un obstacle situé derrière elle).
func steer(pos: Vector2, dir: Vector2, radius: float, look := 70.0, reach := INF) -> Vector2:
	if dir == Vector2.ZERO:
		return dir
	look = clampf(reach - radius, 0.0, look)
	var ahead := pos + dir * (radius + look)
	if look > 0.0 and outline_distance(ahead) < radius:
		# le bord de l'arène approche : on le longe
		var n_o: Vector2 = _in_n[_edge_of(ahead)]
		var t_o := n_o.orthogonal()
		if t_o.dot(dir) < 0:
			t_o = -t_o
		return (t_o + n_o * 0.25).normalized()
	for b in blocks:
		if not b.aabb.grow(radius + look).has_point(pos):
			continue
		var inside := Geometry2D.is_point_in_polygon(ahead, b.poly)
		var cp := _closest(b.poly, ahead)
		if not inside and cp.distance_to(ahead) > radius:
			continue
		var n: Vector2 = (pos - _closest(b.poly, pos)).normalized()
		if n == Vector2.ZERO:
			n = (pos - b.c).normalized()
		# on contourne du côté où la direction penche déjà (stable d'une image à l'autre)
		var tangent := n.orthogonal()
		var lean: float = tangent.dot(dir)
		if absf(lean) < 0.05:
			lean = tangent.dot(pos - b.c)
		if lean < 0:
			tangent = -tangent
		return (tangent * 1.0 + n * 0.25).normalized()
	return dir


# ------------------------------------------------------------------ navigation (champ de distances par cible)
const CELL := 50.0
var _gw := 0
var _gh := 0
var _walk := PackedByteArray()
var _fields := {}            # cellule cible -> PackedInt32Array des distances
var _field_order: Array = []


func _build_grid() -> void:
	_gw = int(ceil(bounds.size.x / CELL))
	_gh = int(ceil(bounds.size.y / CELL))
	_walk.resize(_gw * _gh)
	for y in _gh:
		for x in _gw:
			_walk[y * _gw + x] = 1 if is_free(_cell_center(x, y), 42.0) else 0


func _cell_center(x: int, y: int) -> Vector2:
	return bounds.position + Vector2(x + 0.5, y + 0.5) * CELL


func _cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int((p.x - bounds.position.x) / CELL), 0, _gw - 1), clampi(int((p.y - bounds.position.y) / CELL), 0, _gh - 1))


## Distances (pas de 2 en ligne droite, 3 en diagonale) depuis la cellule cible, sur la grille praticable.
func _field(target: Vector2i) -> PackedInt32Array:
	var key := target.y * _gw + target.x
	if _fields.has(key):
		return _fields[key]
	var dist := PackedInt32Array()
	dist.resize(_gw * _gh)
	dist.fill(1 << 30)
	var buckets := {0: [key]}
	dist[key] = 0
	var cur := 0
	var left := 1
	while left > 0:
		var bucket: Array = buckets.get(cur, [])
		buckets.erase(cur)
		left -= bucket.size()
		for idx in bucket:
			if dist[idx] != cur:
				continue
			var x: int = idx % _gw
			var y: int = idx / _gw
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx < 0 or ny < 0 or nx >= _gw or ny >= _gh:
					continue
				var ni := ny * _gw + nx
				if _walk[ni] == 0:
					continue
				var diag: bool = d.x != 0 and d.y != 0
				if diag and (_walk[y * _gw + nx] == 0 or _walk[ny * _gw + x] == 0):
					continue
				var nd: int = cur + (3 if diag else 2)
				if nd < dist[ni]:
					dist[ni] = nd
					if not buckets.has(nd):
						buckets[nd] = []
					buckets[nd].append(ni)
					left += 1
		cur += 1
	_fields[key] = dist
	_field_order.append(key)
	if _field_order.size() > 96:
		_fields.erase(_field_order.pop_front())
	return dist


## Déplacement vers une cible : ligne droite avec contournement local, ou chemin de la grille autour du vide.
func pursue(pos: Vector2, target: Vector2, dir: Vector2, radius: float) -> Vector2:
	var c := chase_dir(pos, target, dir)
	if c != dir:
		return c
	var st := steer(pos, dir, radius, 70.0, pos.distance_to(target))
	if st != dir:
		# un bord gêne la ligne droite : le chemin de la grille dit de quel côté passer
		var f := chase_dir(pos, target, dir, true)
		if f != dir:
			return f
	return st


## Direction de poursuite : tout droit si rien ne gêne, sinon on suit le chemin le plus court autour du vide.
## `dir` est la direction voulue (avec ses effets : zigzag…), on la fait tourner vers le chemin.
func chase_dir(pos: Vector2, target: Vector2, dir: Vector2, force_path := false) -> Vector2:
	if dir == Vector2.ZERO:
		return dir
	var tc := _cell_of(target)
	var pc := _cell_of(pos)
	if _walk[tc.y * _gw + tc.x] == 0 or tc == pc:
		return dir
	var dist := _field(tc)
	var here: int = dist[pc.y * _gw + pc.x]
	var ax: int = absi(pc.x - tc.x)
	var ay: int = absi(pc.y - tc.y)
	if not force_path and here < 1 << 30 and here <= 3 * mini(ax, ay) + 2 * (maxi(ax, ay) - mini(ax, ay)):
		return dir        # rien ne gêne : ligne droite
	var best := here
	var best_c := pc
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = pc.x + dx
			var ny: int = pc.y + dy
			if nx < 0 or ny < 0 or nx >= _gw or ny >= _gh:
				continue
			var v: int = dist[ny * _gw + nx]
			if v < best:
				best = v
				best_c = Vector2i(nx, ny)
	if best_c == pc:
		return dir
	var want := (_cell_center(best_c.x, best_c.y) - pos).normalized()
	var to_t := (target - pos).normalized()
	return dir.rotated(to_t.angle_to(want))


func _clamp_bounds(p: Vector2, margin: float) -> Vector2:
	return Vector2(clamp(p.x, bounds.position.x + margin, bounds.end.x - margin), clamp(p.y, bounds.position.y + margin, bounds.end.y - margin))


func _push_out(b: Dictionary, p: Vector2, margin: float) -> Vector2:
	var poly: PackedVector2Array = b.poly
	var inside := Geometry2D.is_point_in_polygon(p, poly)
	var best_d := INF
	var cp := p
	var normal := Vector2.ZERO
	for i in poly.size():
		var a := poly[i]
		var c := poly[(i + 1) % poly.size()]
		var q := Geometry2D.get_closest_point_to_segment(p, a, c)
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			cp = q
			var n := (c - a).orthogonal().normalized()
			if n.dot((a + c) / 2.0 - b.c) < 0:
				n = -n
			normal = n
	if inside:
		return cp + normal * (margin + 0.5)
	var dist := sqrt(best_d)
	if dist >= margin:
		return p
	var away := (p - cp) / dist if dist > 0.001 else normal
	return cp + away * (margin + 0.5)


func _closest(poly: PackedVector2Array, p: Vector2) -> Vector2:
	var best_d := INF
	var cp := p
	for i in poly.size():
		var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
		var d := q.distance_squared_to(p)
		if d < best_d:
			best_d = d
			cp = q
	return cp


func _poly_distance(poly: PackedVector2Array, p: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(p, poly):
		return 0.0
	return _closest(poly, p).distance_to(p)
