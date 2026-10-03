extends Control
## Effets de récupération des récompenses (battle pass) : la récompense jaillit de sa case,
## se révèle au centre (rayons tournants, étincelles), puis retourne dans sa case.
## Un clic accélère / passe les révélations en cours.

signal finished

const GOLD := Color("#ffd166")
const CYAN := Color("#5ff7ff")
const PINK := Color("#ff5fd2")

var _parts: Array = []        # {p, v, life, max, col, size}
var _rays_alpha := 0.0
var _rays_rot := 0.0
var _rays_col := GOLD
var _skip := false
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 50


func _gui_input(event: InputEvent) -> void:
	if _busy and event is InputEventMouseButton and event.pressed:
		_skip = true
		accept_event()


func _process(delta: float) -> void:
	_rays_rot += delta * 0.6
	for p in _parts:
		p.life -= delta
		p.v *= 0.94
		p.v.y += 260.0 * delta
		p.p += p.v * delta
	_parts = _parts.filter(func(p): return p.life > 0)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	if _rays_alpha > 0.01:
		for i in 16:
			var a := _rays_rot + i * TAU / 16.0
			var w := 0.09
			var r := 900.0
			var pts := PackedVector2Array([c, c + Vector2.from_angle(a - w) * r, c + Vector2.from_angle(a + w) * r])
			draw_colored_polygon(pts, Color(_rays_col, _rays_alpha * (0.22 if i % 2 == 0 else 0.1)))
		draw_circle(c, 210, Color(_rays_col, _rays_alpha * 0.18))
	for p in _parts:
		var k: float = p.life / p.max
		var s: float = p.size * (0.4 + k)
		var col: Color = Color(p.col, k)
		draw_colored_polygon(PackedVector2Array([p.p + Vector2(0, -s), p.p + Vector2(s * 0.6, 0), p.p + Vector2(0, s), p.p + Vector2(-s * 0.6, 0)]), col)


## Gerbe d'étincelles en `pos` (coordonnées locales).
func burst(pos: Vector2, n := 28, colors := [GOLD, CYAN, PINK, Color.WHITE], speed := 520.0) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2.from_angle(a) * randf_range(speed * 0.35, speed)
		_parts.append({"p": pos, "v": v, "life": randf_range(0.5, 1.1), "max": 1.1, "col": colors[i % colors.size()], "size": randf_range(5.0, 11.0)})


func _rarity_color(reward: Dictionary) -> Color:
	match reward.get("type", ""):
		"hat", "title", "color":
			return PINK
		"neons", "skill_point":
			return CYAN
	return GOLD


func _subtitle(reward: Dictionary) -> String:
	match reward.get("type", ""):
		"hat":
			return "NOUVEAU CHAPEAU !"
		"color":
			return "NOUVELLE COULEUR !"
		"title":
			return "NOUVEAU TITRE !"
		"skill_point":
			return "POINT DE COMPÉTENCE !"
	return "RÉCOMPENSE !"


## Révèle une récompense partie de `from` (position globale). `quick` : version courte (« Tout récupérer »).
func reveal(reward: Dictionary, from: Vector2, quick := false) -> void:
	_busy = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := _rarity_color(reward)
	var cosmetic: bool = reward.get("type", "") in ["hat", "color", "title"]
	var hold := 0.35 if quick else (1.25 if cosmetic else 0.85)
	if _skip:
		hold = 0.0
	var local_from := from - global_position
	var center := size / 2.0

	var card := PanelContainer.new()
	card.theme = Ui.theme
	card.add_theme_stylebox_override("panel", Ui.box(Color("#1d1042", 0.97), col, 4, 18))
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v := Ui.vbox(6)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(v)
	var sub := Ui.label(_subtitle(reward), 20, col, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(sub)
	var ic := Ui.icon(Profile.reward_icon(reward), 150)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if reward.get("type", "") == "color":
		ic.modulate = Ui.color_of_cosmetic(reward.id)
	v.add_child(ic)
	var txt := Ui.label(Profile.reward_text(reward), 28, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(txt)
	card.custom_minimum_size = Vector2(380, 290)
	add_child(card)
	card.size = card.custom_minimum_size
	card.pivot_offset = card.size / 2.0
	card.position = local_from - card.size / 2.0
	card.scale = Vector2(0.15, 0.15)
	card.modulate.a = 0.0
	_rays_col = col

	Audio.play("palier" if (cosmetic or not quick) else "ramasse")
	burst(local_from, 14, [col, Color.WHITE], 300.0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(card, "position", center - card.size / 2.0, 0.32 if not _skip else 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "scale", Vector2.ONE * (1.12 if cosmetic else 1.0), 0.32 if not _skip else 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "modulate:a", 1.0, 0.15)
	tw.tween_method(func(a): _rays_alpha = a, _rays_alpha, 1.0, 0.3)
	await tw.finished
	burst(center, 40 if cosmetic else 26)
	if cosmetic and not _skip:
		Ui.flash(Color(col, 0.25), 0.3)
	# petite respiration de l'icône pendant l'affichage
	ic.pivot_offset = Vector2(75, 75)
	var pulse := create_tween().set_loops()
	pulse.tween_property(ic, "scale", Vector2(1.08, 1.08), 0.25)
	pulse.tween_property(ic, "scale", Vector2.ONE, 0.25)
	var t := 0.0
	while t < hold and not _skip:
		await get_tree().process_frame
		t += get_process_delta_time()
	pulse.kill()
	# retour dans la case
	var back := create_tween().set_parallel(true)
	back.tween_property(card, "position", local_from - card.size / 2.0, 0.26).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	back.tween_property(card, "scale", Vector2(0.15, 0.15), 0.26).set_ease(Tween.EASE_IN)
	back.tween_property(card, "modulate:a", 0.0, 0.26).set_delay(0.08)
	back.tween_method(func(a): _rays_alpha = a, 1.0, 0.0, 0.3)
	await back.finished
	burst(local_from, 12, [col, Color.WHITE], 260.0)
	card.queue_free()


## Révèle plusieurs récompenses à la suite. Au-delà de `max_shown`, un récapitulatif remplace le reste.
func reveal_many(items: Array, max_shown := 5) -> void:
	_skip = false
	for i in items.size():
		if i >= max_shown or _skip:
			break
		await reveal(items[i].reward, items[i].from, true)
	var rest: int = items.size() - mini(items.size(), max_shown)
	if _skip:
		rest = items.size()
	if rest > 0:
		await _summary(items.size())
	_done()


func reveal_one(reward: Dictionary, from: Vector2) -> void:
	_skip = false
	await reveal(reward, from)
	_done()


func _summary(n: int) -> void:
	_skip = false
	var lab := Ui.title("%d récompenses récupérées !" % n, 56, GOLD)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lab)
	lab.position = size / 2.0 - Vector2(500, 40)
	lab.custom_minimum_size = Vector2(1000, 0)
	lab.pivot_offset = Vector2(500, 40)
	lab.scale = Vector2(0.3, 0.3)
	burst(size / 2.0, 60)
	Audio.play("palier")
	var tw := create_tween()
	tw.tween_method(func(a): _rays_alpha = a, 0.0, 1.0, 0.2)
	tw.parallel().tween_property(lab, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.9)
	tw.tween_property(lab, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_method(func(a): _rays_alpha = a, 1.0, 0.0, 0.3)
	await tw.finished
	lab.queue_free()


func _done() -> void:
	_busy = false
	_skip = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit()


func is_busy() -> bool:
	return _busy
