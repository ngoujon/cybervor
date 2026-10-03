extends RefCounted
## État autoritaire (serveur) d'un joueur pendant une partie : statistiques, armes, objets,
## niveau, monnaie (« données »), améliorations en attente et boutique.

const MAX_WEAPONS := 6
const BASE_SPEED := 310.0

var id := 0
var name := ""
var character := "patatron"
var bot := false
var team := 0
var cosmetics := {}
var skill_stats := {}

var weapons: Array = []        # [{id, tier, cd}]
var items: Dictionary = {}      # id -> quantité
var upgrades: Dictionary = {}   # stat -> valeur cumulée (améliorations de niveau)
var spells: Dictionary = {}     # sort -> rang (arbre de sorts du héros, data/spells.json)
var actives: Array = []         # sorts actifs dans l'ordre des emplacements (touches 1 à 5)
var spell_cd: Dictionary = {}   # sort actif -> recharge restante
var buffs: Array = []           # bonus temporaires [{stats, t}]
var passive_t: Dictionary = {}  # minuteurs des passifs (auras, effets périodiques)
var dodge_cd := 0.0
var aim_dir := Vector2.RIGHT    # direction de visée (curseur / stick droit ; IA : cible la plus proche)
var stats: Dictionary = {}      # statistiques finales calculées

var hp := 20.0
var alive := true
var level := 1
var xp := 0.0
var data := 0
var pending_levels := 0
var upgrade_choices: Array = []
var shop: Array = []
var shop_rerolls := 0
var free_rerolls_left := 0
var shield_left := 0
var revives_left := 0
var invuln := 0.0
var dash_cd := 0.0
var regen_acc := 0.0
var ready := false
var drone_cd := 0.0

# statistiques de partie
var kills := 0
var data_collected := 0
var damage_dealt := 0
var levels_gained := 0
var purchases := 0
var pvp_rounds_won := 0
var casts := 0
var dodges := 0


func setup(info: Dictionary, pid: int) -> void:
	id = pid
	name = info.get("name", "Joueur")
	character = info.get("character", "patatron")
	if not Db.characters.has(character):
		character = "patatron"
	bot = info.get("bot", false)
	team = int(info.get("team", 0))
	cosmetics = info.get("cosmetics", {})
	skill_stats = info.get("skills", {})
	var ch: Dictionary = Db.characters[character]
	weapons = [{"id": ch.weapon, "tier": 0, "cd": 0.5}]
	recompute()
	hp = stats.max_hp
	data = int(stats.get("start_data", 0)) + 30
	revives_left = int(stats.get("revive", 0))
	shield_left = int(stats.get("shield", 0))


func recompute() -> void:
	var s := {}
	for k in Db.stats:
		s[k] = float(Db.stats[k].get("base", 0))
	var add := func(src: Dictionary, mult: float):
		for k in src:
			s[k] = float(s.get(k, 0.0)) + float(src[k]) * mult
	add.call(Db.characters[character].get("stats", {}), 1.0)
	add.call(skill_stats, 1.0)
	add.call(upgrades, 1.0)
	for sid in spells:
		var sdef: Dictionary = Db.spells.spells.get(sid, {})
		if sdef.get("type", "") != "passive":
			continue
		var rank: int = spells[sid]
		if sdef.kind == "stats":
			add.call(sdef.base.get("stats", {}), float(rank))
		if rank >= 3:
			add.call(sdef.get("rank3", {}), 1.0)
		if rank >= 5:
			add.call(sdef.get("rank5", {}), 1.0)
	for b in buffs:
		add.call(b.stats, 1.0)
	for item_id in items:
		add.call(Db.items[item_id].stats, items[item_id])
	s.max_hp = max(1.0, s.max_hp)
	s.dodge = min(s.dodge, 60.0)
	stats = s
	hp = min(hp, stats.max_hp)


func max_hp() -> float:
	return stats.max_hp


func move_speed() -> float:
	return BASE_SPEED * max(0.3, 1.0 + stats.speed / 100.0)


func pickup_range() -> float:
	return 90.0 + stats.pickup


func xp_to_next() -> float:
	return pow(level + 3, 2)


## Ajoute de l'XP, renvoie le nombre de niveaux gagnés.
func add_xp(amount: float) -> int:
	xp += amount * (1.0 + stats.xp_gain / 100.0)
	var gained := 0
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		gained += 1
		pending_levels += 1
		levels_gained += 1
		upgrades["max_hp"] = upgrades.get("max_hp", 0) + 1
	if gained > 0:
		recompute()
		hp = min(hp + gained, stats.max_hp)
	return gained


# ------------------------------------------------------------------ armes
func weapon_damage(w: Dictionary) -> float:
	var def: Dictionary = Db.weapons[w.id]
	var base: float = def.damage[w.tier]
	for k in def.get("scale", {}):
		base += float(def.scale[k]) * float(stats.get(k, 0.0))
	var mult = 1.0 + stats.damage / 100.0
	if def["class"] == "ranged":
		mult *= 1.0 + stats.get("ranged_mult", 0.0) / 100.0
	return max(1.0, base * mult)


func weapon_cooldown(w: Dictionary) -> float:
	var def: Dictionary = Db.weapons[w.id]
	var aspd: float = stats.attack_speed
	var f := 1.0 + aspd / 100.0 if aspd >= 0 else 1.0 / (1.0 - aspd / 100.0)
	return max(0.06, float(def.cooldown[w.tier]) / f)


func weapon_range(w: Dictionary) -> float:
	var def: Dictionary = Db.weapons[w.id]
	var bonus: float = stats.range
	if def["class"] == "melee":
		bonus *= 0.5
	return max(60.0, float(def.range) + bonus)


func can_add_weapon(wid: String, tier: int) -> bool:
	if weapons.size() < MAX_WEAPONS:
		return true
	for w in weapons:
		if w.id == wid and w.tier == tier and tier < 3:
			return true
	return false


## Ajoute une arme ; fusionne automatiquement si l'inventaire est plein.
func add_weapon(wid: String, tier: int) -> bool:
	if weapons.size() < MAX_WEAPONS:
		weapons.append({"id": wid, "tier": tier, "cd": 0.3})
		return true
	for w in weapons:
		if w.id == wid and w.tier == tier and tier < 3:
			w.tier += 1
			return true
	return false


func merge_weapon(idx: int) -> bool:
	if idx < 0 or idx >= weapons.size():
		return false
	var w: Dictionary = weapons[idx]
	if w.tier >= 3:
		return false
	for j in weapons.size():
		if j != idx and weapons[j].id == w.id and weapons[j].tier == w.tier:
			weapons.remove_at(j)
			w.tier += 1
			return true
	return false


func sell_weapon(idx: int) -> int:
	if idx < 0 or idx >= weapons.size() or weapons.size() <= 1:
		return 0
	var value := weapon_sell_value(idx)   # même montant que celui affiché sur le bouton
	weapons.remove_at(idx)
	data += value
	return value


func add_item(item_id: String) -> void:
	items[item_id] = int(items.get(item_id, 0)) + 1
	var before_max := max_hp()
	recompute()
	if max_hp() > before_max:
		hp += max_hp() - before_max


# ------------------------------------------------------------------ sorts (vendus en boutique, propres au héros)
func cooldown_mult() -> float:
	return 1.0 / (1.0 + max(0.0, stats.get("tech", 0.0)) * 0.01)


func dodge_cooldown() -> float:
	var def: Dictionary = Db.spells.dodges.get(character, Db.spells.dodges.patatron)
	return float(def.cd) * pow(0.7, stats.get("dash", 0.0))


## Sorts que la boutique peut proposer : nouveaux sorts de l'arbre du héros (armes actives tant qu'il reste
## un emplacement sur 5 dans la barre de raccourcis, armes passives sans limite) ou rang supérieur d'un sort possédé.
func spell_options() -> Array:
	var out := []
	for sid in Db.spells.trees.get(character, []) + Db.spells.get("generic", []):
		var def: Dictionary = Db.spells.spells[sid]
		var rank: int = spells.get(sid, 0)
		if rank >= int(def.get("max", 5)):
			continue
		if rank == 0 and def.type == "active" and actives.size() >= int(Db.spells.get("max_actives", 5)):
			continue
		out.append({"spell": sid, "rank": rank + 1})
	return out


func learn_spell(sid: String) -> void:
	var def: Dictionary = Db.spells.spells[sid]
	if not spells.has(sid) and def.type == "active":
		actives.append(sid)
		spell_cd[sid] = 0.0
	spells[sid] = spells.get(sid, 0) + 1
	recompute()


func spell_price(sid: String, rank: int, wave: int) -> int:
	var def: Dictionary = Db.spells.spells[sid]
	var base := 26.0 if def.type == "active" else 22.0
	return int(round(base * (1.0 + (rank - 1) * 0.7) * price_mult(wave)))


func spell_sell_value(sid: String) -> int:
	var value := 0
	for r in range(1, int(spells.get(sid, 0)) + 1):
		value += int(spell_price(sid, r, shop_wave) * 0.35)
	return max(1, value)


func weapon_sell_value(idx: int) -> int:
	if idx < 0 or idx >= weapons.size():
		return 0
	return max(1, int(weapon_price(weapons[idx].id, weapons[idx].tier, shop_wave) * 0.35))


func _spell_sell_values() -> Dictionary:
	var out := {}
	for s in spells:
		out[s] = spell_sell_value(s)
	return out


## Revend un sort (libère son emplacement dans la barre). Rend 35 % de ce qu'il a coûté.
func sell_spell(sid: String) -> int:
	if not spells.has(sid):
		return 0
	var value := spell_sell_value(sid)
	spells.erase(sid)
	actives.erase(sid)
	spell_cd.erase(sid)
	data += value
	var before_max := max_hp()
	recompute()
	if hp > max_hp():
		hp = max_hp()
	elif max_hp() < before_max:
		hp = min(hp, max_hp())
	return value


## Réorganise la barre de raccourcis (échange deux emplacements).
func swap_actives(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a >= actives.size() or b >= actives.size() or a == b:
		return false
	var t: String = actives[a]
	actives[a] = actives[b]
	actives[b] = t
	spell_cd[actives[a]] = 0.0
	spell_cd[actives[b]] = 0.0
	return true


# ------------------------------------------------------------------ améliorations de niveau
func roll_upgrades(rng: RandomNumberGenerator, wave: int) -> void:
	# niveau supérieur : améliorations de statistiques (les sorts s'achètent en boutique)
	var keys := []
	for k in Db.stats:
		if not Db.stats[k].upgrade.is_empty():
			keys.append(k)
	var n := 4 + int(stats.get("extra_choice", 0))
	upgrade_choices = []
	for i in n:
		if keys.is_empty():
			break
		var k: String = keys.pop_at(rng.randi() % keys.size())
		var r := roll_rarity(rng, wave)
		upgrade_choices.append({"stat": k, "rarity": r, "value": Db.stats[k].upgrade[r]})


func choose_upgrade(idx: int) -> bool:
	if pending_levels <= 0 or idx < 0 or idx >= upgrade_choices.size():
		return false
	var c: Dictionary = upgrade_choices[idx]
	if c.has("spell"):
		learn_spell(c.spell)
	else:
		upgrades[c.stat] = upgrades.get(c.stat, 0) + c.value
	var before_max := max_hp()
	recompute()
	if max_hp() > before_max:
		hp += max_hp() - before_max
	pending_levels -= 1
	upgrade_choices = []
	return true


func roll_rarity(rng: RandomNumberGenerator, wave: int) -> int:
	var luck: float = 1.0 + max(stats.get("luck", 0.0), -50.0) / 100.0
	var r := rng.randf()
	var legend: float = clamp((wave - 6) * 0.008, 0.0, 0.08) * luck
	var epic: float = clamp((wave - 2) * 0.025, 0.0, 0.25) * luck
	var rare: float = clamp(0.12 + wave * 0.04, 0.0, 0.6) * luck
	if r < legend:
		return 3
	if r < legend + epic:
		return 2
	if r < legend + epic + rare:
		return 1
	return 0


# ------------------------------------------------------------------ boutique
## Début de partie : boutiques moins chères (-35 % après la vague 1, puis normal à partir de la vague 5).
func price_mult(wave: int) -> float:
	var early: float = lerp(0.65, 1.0, clamp((wave - 1) / 4.0, 0.0, 1.0))
	return early * (1.0 + (wave - 1) * 0.12) * max(0.5, 1.0 - stats.get("shop_discount", 0.0) / 100.0)


func weapon_price(wid: String, tier: int, wave: int) -> int:
	return int(round(Db.weapons[wid].price * (1.0 + tier * 0.9) * price_mult(wave)))


func item_price(item_id: String, wave: int) -> int:
	return int(round(Db.items[item_id].price * price_mult(wave)))


var shop_wave := 1   # vague de la boutique en cours (sert aussi aux prix de revente)


func roll_shop(rng: RandomNumberGenerator, wave: int) -> void:
	shop_wave = wave
	shop = []
	var spell_slots := 2   # au plus 2 sorts par boutique, jamais le même deux fois
	for i in 4:
		var o := {}
		if spell_slots > 0 and rng.randf() < 0.45:
			o = _roll_spell_offer(rng, wave)
		if o.is_empty():
			o = _roll_offer(rng, wave)
		else:
			spell_slots -= 1
		shop.append(o)
	_ensure_affordable(rng)


## Jamais une boutique où l'on ne peut rien acheter : si aucune offre n'est abordable, l'une d'elles
## passe en promotion au prix des données disponibles (au moins 40 % de son prix).
func _ensure_affordable(rng: RandomNumberGenerator) -> void:
	if shop.is_empty() or shop.any(func(o): return not o.sold and int(o.price) <= data):
		return
	var cheapest := 0
	for i in shop.size():
		if int(shop[i].price) < int(shop[cheapest].price):
			cheapest = i
	var o: Dictionary = shop[cheapest]
	var floor_price := int(ceil(int(o.price) * 0.4))
	if data >= floor_price:
		o["was"] = int(o.price)
		o.price = max(1, data)
		o["promo"] = true


func _roll_spell_offer(rng: RandomNumberGenerator, wave: int) -> Dictionary:
	var opts := spell_options().filter(func(x): return not shop.any(func(s): return s.kind == "spell" and s.id == x.spell))
	if opts.is_empty():
		return {}
	var owned := opts.filter(func(x): return x.rank > 1)
	var pool: Array = owned if (not owned.is_empty() and rng.randf() < 0.4) else opts
	var pick: Dictionary = pool[rng.randi() % pool.size()]
	var sid: String = pick.spell
	return {"kind": "spell", "id": sid, "rank": pick.rank, "price": spell_price(sid, pick.rank, wave), "sold": false}


func _roll_offer(rng: RandomNumberGenerator, wave: int) -> Dictionary:
	var r := roll_rarity(rng, wave)
	if rng.randf() < 0.35:
		var ids = Db.weapons.keys()
		var wid: String = ids[rng.randi() % ids.size()]
		# Favorise les armes déjà possédées (pour les fusions)
		if not weapons.is_empty() and rng.randf() < 0.3:
			wid = weapons[rng.randi() % weapons.size()].id
		var tier: int = clamp(r, 0, 3)
		return {"kind": "weapon", "id": wid, "tier": tier, "price": weapon_price(wid, tier, wave), "sold": false}
	var candidates := []
	for item_id in Db.items:
		if int(Db.items[item_id].rarity) == r:
			candidates.append(item_id)
	if candidates.is_empty():
		candidates = Db.items.keys()
	var iid: String = candidates[rng.randi() % candidates.size()]
	return {"kind": "item", "id": iid, "price": item_price(iid, wave), "sold": false}


func reroll_price(wave: int) -> int:
	if free_rerolls_left > 0:
		return 0
	return max(1, int(wave * 0.75)) + shop_rerolls * max(1, wave / 2)


func buy(idx: int) -> String:
	if idx < 0 or idx >= shop.size():
		return "Offre invalide."
	var o: Dictionary = shop[idx]
	if o.sold:
		return "Déjà acheté."
	if data < o.price:
		return "Pas assez de données."
	if o.kind == "weapon":
		if not add_weapon(o.id, o.tier):
			return "Inventaire d'armes plein (6). Vendez ou fusionnez une arme."
	elif o.kind == "spell":
		var def: Dictionary = Db.spells.spells[o.id]
		if int(spells.get(o.id, 0)) >= int(def.get("max", 5)):
			return "Ce sort est déjà au rang maximum."
		if not spells.has(o.id) and def.type == "active" and actives.size() >= int(Db.spells.get("max_actives", 5)):
			return "Barre de raccourcis pleine (5 sorts actifs) : revendez un sort actif pour faire de la place."
		var before_max := max_hp()
		learn_spell(o.id)
		if max_hp() > before_max:
			hp += max_hp() - before_max
	else:
		add_item(o.id)
	data -= o.price
	o.sold = true
	purchases += 1
	return ""


# ------------------------------------------------------------------ synchronisation
func public_state() -> Dictionary:
	return {"id": id, "name": name, "character": character, "cosmetics": cosmetics,
		"weapons": weapons.map(func(w): return [w.id, w.tier]),
		"items": items, "drones": int(stats.get("drones", 0)), "spells": spells, "actives": actives,
		"buffs": buffs.size()}


func private_state(wave: int) -> Dictionary:
	return {"data": data, "level": level, "pending": pending_levels, "choices": upgrade_choices,
		"shop": shop, "reroll": reroll_price(wave), "weapons": weapons.map(func(w): return [w.id, w.tier]),
		"spells": spells, "actives": actives,
		"sell_weapons": range(weapons.size()).map(func(i): return weapon_sell_value(i)),
		"sell_spells": _spell_sell_values(),
		"items": items, "stats": stats, "hp": hp, "max_hp": max_hp(), "ready": ready}


## Bonus de l'IA adverse en arène (niveau choisi dans le salon).
func apply_ai_level(level: Dictionary) -> void:
	upgrades["damage"] = upgrades.get("damage", 0) + float(level.damage)
	recompute()
	upgrades["max_hp"] = upgrades.get("max_hp", 0) + stats.max_hp * (float(level.hp) - 1.0)
	recompute()
	hp = max_hp()
