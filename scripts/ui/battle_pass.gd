extends Control
## Battle pass : 40 paliers, piste gratuite + premium, défis quotidiens et hebdomadaires.

var _track: HBoxContainer
var _scroll: ScrollContainer
var _header: VBoxContainer
var _challenges: VBoxContainer
var _fx: Control                 # effets de récupération (RewardFx)
var _cells := {}                 # "palier:piste" -> case de récompense
var _neons_label: Label
var _shown_neons := -1


func _ready() -> void:
	Ui.screen_base(self, "res://assets/backgrounds/zone_holo.png", 0.78)
	Audio.play_music("boutique")
	Profile.refresh_challenges()
	var root := Ui.vbox(14)
	add_child(Ui.margin(root, 36))
	root.add_child(Ui.title(Db.battlepass.name))
	var d := Ui.label(Db.battlepass.desc, 19, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	root.add_child(d)

	_header = Ui.vbox(8)
	root.add_child(_header)

	_scroll = ScrollContainer.new()
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(0, 420)
	root.add_child(_scroll)
	_track = Ui.hbox(10)
	_scroll.add_child(_track)

	var low := Ui.hbox(20)
	low.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(low)
	var cp := Ui.panel(16)
	cp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	low.add_child(cp)
	_challenges = Ui.vbox(6)
	cp.add_child(_challenges)

	var bar := Ui.hbox(16)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(bar)
	bar.add_child(Ui.button("Retour", func(): Game.goto("main_menu"), 240))
	bar.add_child(Ui.button("Tout récupérer", _claim_all, 280))
	_fx = load("res://scripts/ui/reward_fx.gd").new()
	add_child(_fx)
	_refresh()
	await get_tree().process_frame
	_scroll.scroll_horizontal = max(0, (Profile.bp_tier() - 3) * 170)


func _refresh() -> void:
	for c in _header.get_children():
		c.queue_free()
	var tier = Profile.bp_tier()
	var maxt: int = Db.battlepass.tiers.size()
	var h := Ui.hbox(20)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(Ui.label("Palier %d / %d" % [tier, maxt], 30, Ui.C_GOLD))
	var pb := ProgressBar.new()
	pb.custom_minimum_size = Vector2(500, 26)
	pb.max_value = 1.0
	pb.step = 0.001
	pb.value = Profile.bp_progress() if tier < maxt else 1.0
	pb.show_percentage = false
	pb.add_theme_stylebox_override("fill", Ui.box(Ui.C_ACCENT, Color(0, 0, 0, 0), 0, 8))
	h.add_child(pb)
	h.add_child(Ui.label("%d / %d XP" % [int(Profile.data.battlepass.xp) % int(Db.battlepass.xp_per_tier), Db.battlepass.xp_per_tier], 20))
	h.add_child(Ui.spacer(0, 30))
	h.add_child(Ui.icon("res://assets/sprites/ui/neons.png", 34))
	var neons := int(Profile.data.neons)
	_neons_label = Ui.label(str(_shown_neons if _shown_neons >= 0 else neons), 24, Ui.C_ACCENT)
	h.add_child(_neons_label)
	if _shown_neons >= 0 and _shown_neons != neons:   # le compteur défile jusqu'à la nouvelle valeur
		var lab := _neons_label
		var tw := lab.create_tween()
		tw.tween_method(func(x): lab.text = str(int(x)), float(_shown_neons), float(neons), 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		lab.pivot_offset = Vector2(20, 14)
		tw.parallel().tween_property(lab, "scale", Vector2(1.3, 1.3), 0.15)
		tw.tween_property(lab, "scale", Vector2.ONE, 0.2)
	_shown_neons = neons
	_header.add_child(h)
	var h2 := Ui.hbox(16)
	h2.alignment = BoxContainer.ALIGNMENT_CENTER
	if Profile.data.battlepass.premium:
		h2.add_child(Ui.label("★ PASS PREMIUM ACTIVÉ ★", 24, Ui.C_GOLD))
	else:
		h2.add_child(Ui.button("Activer le pass premium (%d néons)" % Db.battlepass.premium_price_neons, _buy_premium, 0, 22))
	h2.add_child(Ui.button("Acheter un palier (%d néons)" % Db.battlepass.tier_skip_neons, _buy_tier, 0, 22))
	h2.add_child(Ui.label("Fin de saison : %s" % Db.battlepass.ends, 18, Ui.C_MUTED))
	_header.add_child(h2)

	for c in _track.get_children():
		c.queue_free()
	_cells.clear()
	for t in Db.battlepass.tiers:
		_track.add_child(_tier_column(t))
	_refresh_challenges()


func _tier_column(t: Dictionary) -> Control:
	var tier: int = t.tier
	var reached = tier <= Profile.bp_tier()
	var v := Ui.vbox(6)
	v.custom_minimum_size = Vector2(160, 0)
	var lbl := Ui.label("Palier %d" % tier, 20, Ui.C_GOLD if reached else Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	v.add_child(lbl)
	v.add_child(_reward_cell(tier, "free", t.free))
	v.add_child(_reward_cell(tier, "premium", t.premium))
	return v


func _reward_cell(tier: int, track: String, reward: Dictionary) -> Control:
	var premium := track == "premium"
	var claimed: bool = tier in Profile.data.battlepass["claimed_" + track]
	var border := Ui.C_GOLD if premium else Ui.C_BORDER.darkened(0.3)
	var claimable := Profile.bp_claimable(tier, track)
	if claimable:
		border = Ui.C_GOLD.lightened(0.2)
	var p := Ui.panel(8, Color("#2a1c4a", 0.95) if premium else Color(Ui.C_PANEL_2, 0.95), border)
	p.custom_minimum_size = Vector2(160, 180)
	_cells["%d:%s" % [tier, track]] = p
	var v := Ui.vbox(4)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(v)
	v.add_child(Ui.label("PREMIUM" if premium else "GRATUIT", 14, Ui.C_GOLD if premium else Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	var ic := Ui.icon(Profile.reward_icon(reward), 72)
	if reward.type == "color":
		ic.modulate = Ui.color_of_cosmetic(reward.id)
	if claimed:
		ic.modulate.a = 0.35
	v.add_child(ic)
	if claimable:   # la récompense « respire » et la case scintille pour attirer l'œil
		ic.pivot_offset = Vector2(36, 36)
		var tw := ic.create_tween().set_loops()
		tw.tween_property(ic, "scale", Vector2(1.14, 1.14), 0.45).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ic, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_SINE)
		var glow := p.create_tween().set_loops()
		glow.tween_property(p, "self_modulate", Color(1.35, 1.25, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
		glow.tween_property(p, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)
	var l := Ui.label(Profile.reward_text(reward), 15, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(140, 0)
	v.add_child(l)
	if claimed:
		v.add_child(Ui.label("✔ Récupéré", 15, Ui.C_GOOD, HORIZONTAL_ALIGNMENT_CENTER))
	elif claimable:
		v.add_child(Ui.button("Récupérer", _claim.bind(tier, track), 0, 16))
	elif premium and not Profile.data.battlepass.premium:
		v.add_child(Ui.label("🔒 Premium", 15, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	return p


func _refresh_challenges() -> void:
	for c in _challenges.get_children():
		c.queue_free()
	var h := Ui.hbox(40)
	_challenges.add_child(h)
	for kind in ["daily", "weekly"]:
		var col := Ui.vbox(6)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(Ui.label("Défis quotidiens" if kind == "daily" else "Défis hebdomadaires", 24, Ui.C_BORDER))
		for c in Profile.data.challenges[kind]:
			var def = Profile.challenge_def(c.id)
			if def.is_empty():
				continue
			var row := Ui.hbox(10)
			var txt = String(def.text).replace("{n}", str(int(def.n)))
			row.add_child(Ui.label(("✔ " if c.done else "• ") + txt, 18, Ui.C_GOOD if c.done else Ui.C_TEXT))
			row.add_child(Ui.spacer())
			row.add_child(Ui.label("%d/%d" % [int(c.progress), int(def.n)], 18, Ui.C_MUTED))
			row.add_child(Ui.label("+%d XP" % def.xp, 18, Ui.C_GOLD))
			col.add_child(row)
		h.add_child(col)


func _cell_pos(tier: int, track: String) -> Vector2:
	var c = _cells.get("%d:%s" % [tier, track])
	if c and is_instance_valid(c):
		var r: Rect2 = c.get_global_rect()
		var sr: Rect2 = _scroll.get_global_rect()
		return Vector2(clamp(r.get_center().x, sr.position.x + 40, sr.end.x - 40), r.get_center().y)
	return get_global_rect().get_center()


func _claim(tier: int, track: String) -> void:
	if _fx.is_busy():
		return
	var from := _cell_pos(tier, track)
	var r = Profile.bp_claim(tier, track)
	if not r.is_empty():
		_refresh()
		await _fx.reveal_one(r, from)


func _claim_all() -> void:
	if _fx.is_busy():
		return
	var items := []
	for t in range(1, Profile.bp_tier() + 1):
		for track in ["free", "premium"]:
			if Profile.bp_claimable(t, track):
				items.append({"tier": t, "track": track, "from": _cell_pos(t, track)})
	if items.is_empty():
		Ui.toast("Rien à récupérer pour l'instant. Allez jouer !")
		return
	for it in items:
		it.reward = Profile.bp_claim(it.tier, it.track)
	_refresh()
	await _fx.reveal_many(items)


func _buy_premium() -> void:
	if Profile.bp_buy_premium():
		Audio.play("palier")
		Ui.flash(Color(Ui.C_GOLD, 0.4))
		Ui.toast("Pass premium activé ! Mamie RAM est fière de vous.", Ui.C_GOLD)
		_refresh()
	else:
		Audio.play("erreur")
		Ui.toast("Pas assez de néons. Les néons s'obtiennent via la piste gratuite et les défis.", Ui.C_BAD, 3.5)


func _buy_tier() -> void:
	if Profile.bp_buy_tier():
		Audio.play("achat")
		_refresh()
	else:
		Audio.play("erreur")
		Ui.toast("Impossible : pas assez de néons ou pass déjà terminé.", Ui.C_BAD)
