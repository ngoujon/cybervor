extends Control
## Entre deux vagues : choix d'améliorations de niveau (statistiques), puis boutique et inventaire.
## En boutique : armes passives (drones qui tirent seuls), objets, et armes actives / passives propres au héros
## qui donnent des sorts (les actifs vont dans la barre de raccourcis, 5 emplacements).

const SpellHud := preload("res://scripts/world/spell_hud.gd")

var world: Node
var _root: VBoxContainer
var _last: Dictionary = {}


func _ready() -> void:
	theme = Ui.theme
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.02, 0.09, 0.86)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_root = Ui.vbox(14)
	add_child(Ui.margin(_root, 36))
	visibility_changed.connect(func():
		if visible and not world.my_private.is_empty():
			refresh(world.my_private))


func refresh(d: Dictionary) -> void:
	_last = d
	for c in _root.get_children():
		c.queue_free()
	if int(d.get("pending", 0)) > 0 and not d.get("choices", []).is_empty():
		_build_upgrades(d)
	else:
		_build_shop(d)


# ------------------------------------------------------------------ améliorations
func _build_upgrades(d: Dictionary) -> void:
	_root.add_child(Ui.title("NIVEAU SUPÉRIEUR !", 64, Ui.C_GOLD))
	_root.add_child(Ui.label("Choisissez une amélioration (%d restante%s)" % [d.pending, "s" if d.pending > 1 else ""], 26, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
	_root.add_child(Ui.spacer(30))
	var row := Ui.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(row)
	var choices: Array = d.choices
	for i in choices.size():
		var c: Dictionary = choices[i]
		var col: Color = Db.RARITY_COLORS[c.rarity]
		var b := Button.new()
		b.custom_minimum_size = Vector2(300, 300)
		b.add_theme_stylebox_override("normal", Ui.box(Color(Ui.C_PANEL_2, 0.95), col, 4, 20))
		b.add_theme_stylebox_override("hover", Ui.box(Color(Ui.C_PANEL_2.lightened(0.15), 0.95), Ui.C_GOLD, 5, 20))
		b.add_theme_stylebox_override("pressed", Ui.box(col.darkened(0.5), Ui.C_GOLD, 5, 20))
		Ui.wire_sfx(b)
		var v := Ui.vbox(10)
		v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		v.alignment = BoxContainer.ALIGNMENT_CENTER
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(v)
		for l in [Ui.label(Db.RARITY_NAMES[c.rarity], 20, col, HORIZONTAL_ALIGNMENT_CENTER),
				Ui.title("+%s%s" % [Db._num(c.value), Db.stats[c.stat].suffix], 56, col),
				Ui.label(Db.stat_name(c.stat), 26, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER),
				Ui.label("Actuel : %s" % Db._num(d.stats.get(c.stat, 0)), 18, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			v.add_child(l)
		b.pressed.connect(func():
			Audio.play("niveau")
			world.request("upgrade", i))
		row.add_child(b)
		if i == 0:
			b.call_deferred("grab_focus")


func _build_shop(d: Dictionary) -> void:
	var head := Ui.hbox(20)
	_root.add_child(head)
	head.add_child(Ui.title("Boutique" if not world.pvp else "Boutique de l'arène", 52, Ui.C_BORDER))
	head.add_child(Ui.spacer())
	head.add_child(Ui.icon("res://assets/sprites/pickups/data.png", 44))
	head.add_child(Ui.label("%d données" % d.data, 34, Ui.C_BORDER))

	var body := Ui.hbox(24)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root.add_child(body)

	# Offres et inventaire : zone défilante, pour que le bouton « Prêt » reste toujours visible en bas
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left_scroll.follow_focus = true
	body.add_child(left_scroll)
	var left := Ui.vbox(12)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(left)
	var offers := Ui.hbox(14)
	left.add_child(offers)
	var shop: Array = d.get("shop", [])
	for i in shop.size():
		offers.add_child(_offer_card(shop[i], i, int(d.data)))
	var rr := Ui.hbox(14)
	left.add_child(rr)
	var reroll_txt := "Relancer (gratuit)" if int(d.reroll) == 0 else "Relancer (%d)" % d.reroll
	var rb := Ui.button(reroll_txt, func(): world.request("reroll"), 280, 22)
	rb.disabled = int(d.data) < int(d.reroll)
	rr.add_child(rb)
	rr.add_child(Ui.label("Armes identiques de même rang : fusion. Racheter un sort le fait monter de rang (★).", 17, Ui.C_MUTED))

	# Sorts : barre de raccourcis (actifs) et passifs
	_build_spell_bar(left, d)

	# Inventaire armes
	left.add_child(Ui.label("Drones d'armes — tir automatique (%d / 6)" % d.weapons.size(), 26, Ui.C_BORDER))
	var wr := Ui.hbox(10)
	left.add_child(wr)
	for i in d.weapons.size():
		wr.add_child(_weapon_slot(d.weapons, i, int(d.get("sell_weapons", [])[i]) if i < d.get("sell_weapons", []).size() else 0))

	# Objets
	left.add_child(Ui.label("Objets", 26, Ui.C_BORDER))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	left.add_child(flow)
	var items: Dictionary = d.get("items", {})
	if items.is_empty():
		flow.add_child(Ui.label("Aucun objet pour l'instant.", 18, Ui.C_MUTED))
	for item_id in items:
		var it: Dictionary = Db.items[item_id]
		var p := Ui.panel(4, Color(Ui.C_PANEL, 0.9), Db.RARITY_COLORS[it.rarity])
		var h := Ui.hbox(2)
		p.add_child(h)
		var ic := Ui.icon(it.icon, 52)
		h.add_child(ic)
		if int(items[item_id]) > 1:
			h.add_child(Ui.label("x%d" % items[item_id], 18, Ui.C_GOLD))
		p.tooltip_text = "%s\n%s\n%s" % [it.name, Db.format_stats(it.stats), it.desc]
		flow.add_child(p)

	# Statistiques
	var sp := Ui.panel(14)
	sp.custom_minimum_size = Vector2(400, 0)
	body.add_child(sp)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sp.add_child(sc)
	var sv := Ui.vbox(2)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(sv)
	sv.add_child(Ui.label("Statistiques — niveau %d" % d.level, 22, Ui.C_GOLD))
	var stats: Dictionary = d.get("stats", {})
	for k in Db.stats:
		var val: float = stats.get(k, 0.0)
		if Db.stats[k].upgrade.is_empty() and val == 0:
			continue
		var row := Ui.hbox(6)
		row.add_child(Ui.label(Db.stat_name(k), 17))
		row.add_child(Ui.spacer())
		var col = Ui.C_TEXT if val == Db.stats[k].base else (Ui.C_GOOD if val > Db.stats[k].base else Ui.C_BAD)
		row.add_child(Ui.label(Db._num(val) + Db.stats[k].suffix, 17, col))
		sv.add_child(row)

	# Bas : prêt
	var bot := Ui.hbox(20)
	bot.alignment = BoxContainer.ALIGNMENT_CENTER
	_root.add_child(bot)
	var waiting: Array = d.get("waiting", [])
	if d.get("ready", false):
		bot.add_child(Ui.label("En attente de : " + ", ".join(waiting), 22, Ui.C_MUTED))
		bot.add_child(Ui.button("Annuler", func(): world.request("ready", false), 200))
	else:
		var go := Ui.button("Prêt ! Vague suivante" if not world.pvp else "Prêt ! Manche suivante", func(): world.request("ready", true), 420, 28)
		bot.add_child(go)
		go.call_deferred("grab_focus")
		if waiting.size() > 1:
			bot.add_child(Ui.label("Pas encore prêts : " + ", ".join(waiting), 18, Ui.C_MUTED))


## Barre de raccourcis (5 sorts actifs, réorganisables) et sorts passifs, revendables.
func _build_spell_bar(parent: Control, d: Dictionary) -> void:
	var spells: Dictionary = d.get("spells", {})
	var actives: Array = d.get("actives", [])
	var max_a := int(Db.spells.get("max_actives", 5))
	parent.add_child(Ui.label("Barre de raccourcis — sorts actifs (%d / %d)" % [actives.size(), max_a], 26, Ui.C_BORDER))
	var bar := Ui.hbox(10)
	parent.add_child(bar)
	for i in max_a:
		var p := Ui.panel(6, Color(Ui.C_PANEL, 0.9), Color(Db.spells.spells[actives[i]].color) if i < actives.size() else Color(Ui.C_MUTED, 0.4))
		p.custom_minimum_size = Vector2(150, 0)
		var v := Ui.vbox(3)
		p.add_child(v)
		var key := Settings.hud_label("spell_%d" % (i + 1))
		if i >= actives.size():
			v.add_child(Ui.label("[%s]" % key, 16, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
			v.add_child(Ui.label("Libre\nachetez une\narme active", 14, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
			bar.add_child(p)
			continue
		var sid: String = actives[i]
		var def: Dictionary = Db.spells.spells[sid]
		var rank := int(spells.get(sid, 1))
		var top := Ui.hbox(4)
		v.add_child(top)
		top.add_child(Ui.label("[%s]" % key, 16, Ui.C_GOLD))
		top.add_child(Ui.spacer())
		var dti := SpellHud.dmg_type(sid)
		if not dti.is_empty():
			top.add_child(Ui.label(dti[0].left(4) + ".", 13, Color(dti[1])))
		top.add_child(Ui.label("★%d" % rank, 16, Color(def.color)))
		var ic := Ui.icon(def.icon, 64)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(ic)
		v.add_child(Ui.label(def.name.left(16), 14, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER))
		var h := Ui.hbox(4)
		h.alignment = BoxContainer.ALIGNMENT_CENTER
		v.add_child(h)
		var lb := Ui.button("◀", func(): world.request("swap_spell", [i, i - 1]), 0, 14)
		lb.disabled = i == 0
		lb.tooltip_text = "Décaler vers la gauche"
		h.add_child(lb)
		var rb := Ui.button("▶", func(): world.request("swap_spell", [i, i + 1]), 0, 14)
		rb.disabled = i >= actives.size() - 1
		rb.tooltip_text = "Décaler vers la droite"
		h.add_child(rb)
		var gain := int(d.get("sell_spells", {}).get(sid, 0))
		var sb := Ui.button("Vendre +%d" % gain, func(): world.request("sell_spell", sid), 0, 14)
		sb.tooltip_text = "Revendre ce sort : +%d données (libère l'emplacement)" % gain
		h.add_child(sb)
		p.tooltip_text = "%s — rang %d\n%s" % [def.name, rank, SpellHud.describe(sid, rank)]
		bar.add_child(p)
	var passives := spells.keys().filter(func(s): return Db.spells.spells[s].type == "passive")
	if passives.is_empty():
		return
	var pr := Ui.hbox(8)
	parent.add_child(pr)
	pr.add_child(Ui.label("Passifs :", 20, Ui.C_BORDER))
	for sid in passives:
		var def: Dictionary = Db.spells.spells[sid]
		var b := Button.new()
		b.icon = Db.tex(def.icon)
		b.expand_icon = true
		b.custom_minimum_size = Vector2(56, 56)
		b.text = ""
		b.tooltip_text = "%s — rang %d\n%s\n(cliquer pour revendre : +%d données)" % [def.name, int(spells[sid]), SpellHud.describe(sid, int(spells[sid])),
			int(d.get("sell_spells", {}).get(sid, 0))]
		b.pressed.connect(func(): world.request("sell_spell", sid))
		pr.add_child(b)


func _spell_offer_card(o: Dictionary, i: int, data: int) -> Control:
	var def: Dictionary = Db.spells.spells[o.id]
	var active: bool = def.type == "active"
	var col := Color(def.color)
	var p := Ui.panel(14, Color(Ui.C_PANEL_2, 0.95), col)
	p.custom_minimum_size = Vector2(290, 400)
	var v := Ui.vbox(6)
	p.add_child(v)
	var rank := int(o.rank)
	var kind_txt := ("Objet actif" if def.get("generic", false) else ("Arme active" if active else "Arme passive")) + (" — amélioration ★%d → ★%d" % [rank - 1, rank] if rank > 1 else " — nouveau")
	v.add_child(Ui.label(kind_txt, 16, col, HORIZONTAL_ALIGNMENT_CENTER))
	var dt := SpellHud.dmg_type(o.id)
	if not dt.is_empty():
		var badge := Ui.panel(4, Color(Color(dt[1]), 0.18), Color(dt[1]))
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		badge.add_child(Ui.label(("Dégâts " if dt[0] != "Soutien" else "") + dt[0], 16, Color(dt[1]), HORIZONTAL_ALIGNMENT_CENTER))
		badge.tooltip_text = ("Profite de la statistique « %s »." % Db.stat_name(dt[2])) if dt[2] != "" else "Sort utilitaire (soin, bouclier, renforts, bonus)."
		v.add_child(badge)
	var ic := Ui.icon(def.icon, 96)
	if o.sold:
		ic.modulate.a = 0.3
	v.add_child(ic)
	var nm := Ui.label(def.name + "  " + "★".repeat(rank), 22, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	var il := Ui.label(SpellHud.describe(o.id, rank), 16, Ui.C_GOOD)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	il.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(il)
	v.add_child(Ui.label("Se lance vers le curseur (barre de raccourcis)" if active else "Effet permanent", 14, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	if o.sold:
		v.add_child(Ui.label("VENDU", 22, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		if o.get("promo", false):
			v.add_child(Ui.label("PROMO ! %d → %d" % [int(o.was), int(o.price)], 18, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		var full: bool = active and rank == 1 and _last.get("actives", []).size() >= int(Db.spells.get("max_actives", 5))
		var b := Ui.button("Barre pleine" if full else "Acheter — %d" % o.price, func(): world.request("buy", i), 0, 20)
		b.disabled = data < int(o.price) or full
		if full:
			b.tooltip_text = "Revendez un sort actif pour libérer un emplacement."
		v.add_child(b)
	return p


func _offer_card(o: Dictionary, i: int, data: int) -> Control:
	if o.kind == "spell":
		return _spell_offer_card(o, i, data)
	var is_weapon: bool = o.kind == "weapon"
	var def: Dictionary = Db.weapons[o.id] if is_weapon else Db.items[o.id]
	var rarity: int = o.tier if is_weapon else int(def.rarity)
	var col: Color = Db.RARITY_COLORS[rarity]
	var p := Ui.panel(14, Color(Ui.C_PANEL_2, 0.95), col)
	p.custom_minimum_size = Vector2(290, 400)
	var v := Ui.vbox(6)
	p.add_child(v)
	v.add_child(Ui.label(("Arme " + Db.TIER_NAMES[o.tier]) if is_weapon else Db.RARITY_NAMES[rarity], 16, col, HORIZONTAL_ALIGNMENT_CENTER))
	var ic := Ui.icon(def.icon, 96)
	if o.sold:
		ic.modulate.a = 0.3
	v.add_child(ic)
	var nm := Ui.label(def.name, 22, Ui.C_TEXT, HORIZONTAL_ALIGNMENT_CENTER)
	nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(nm)
	var info := ""
	if is_weapon:
		var classes := {"melee": "Mêlée", "ranged": "Distance", "tech": "Techno"}
		info = "%s — Dégâts %d — Cadence %.2fs\nPortée %d" % [classes[def["class"]], def.damage[o.tier], def.cooldown[o.tier], def.range]
	else:
		info = Db.format_stats(def.stats)
	var il := Ui.label(info, 16, Ui.C_GOOD)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	il.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(il)
	var dl := Ui.label(def.desc, 15, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(dl)
	if o.sold:
		v.add_child(Ui.label("VENDU", 22, Ui.C_MUTED, HORIZONTAL_ALIGNMENT_CENTER))
	else:
		if o.get("promo", false):
			v.add_child(Ui.label("PROMO ! %d → %d" % [int(o.was), int(o.price)], 18, Ui.C_GOLD, HORIZONTAL_ALIGNMENT_CENTER))
		var b := Ui.button("Acheter — %d" % o.price, func(): world.request("buy", i), 0, 20)
		b.disabled = data < int(o.price)
		v.add_child(b)
	return p


func _weapon_slot(weapons: Array, i: int, gain := 0) -> Control:
	var w: Array = weapons[i]
	var def: Dictionary = Db.weapons[w[0]]
	var p := Ui.panel(8, Color(Ui.C_PANEL, 0.9), Db.RARITY_COLORS[w[1]])
	var v := Ui.vbox(4)
	p.add_child(v)
	v.add_child(Ui.icon(def.icon, 60))
	v.add_child(Ui.label("%s %s" % [def.name.left(12), Db.TIER_NAMES[w[1]]], 14, Db.RARITY_COLORS[w[1]], HORIZONTAL_ALIGNMENT_CENTER))
	var h := Ui.hbox(4)
	v.add_child(h)
	var can_merge := false
	for j in weapons.size():
		if j != i and weapons[j][0] == w[0] and weapons[j][1] == w[1] and w[1] < 3:
			can_merge = true
	if can_merge:
		h.add_child(Ui.button("Fusion", func(): world.request("merge", i), 0, 14))
	if weapons.size() > 1:
		var sb := Ui.button("Vendre +%d" % gain, func(): world.request("sell", i), 0, 14)
		sb.tooltip_text = "Revendre cette arme : +%d données" % gain
		h.add_child(sb)
	p.tooltip_text = "%s (%s)\n%s" % [def.name, Db.TIER_NAMES[w[1]], def.desc]
	return p
