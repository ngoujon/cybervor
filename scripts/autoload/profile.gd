extends Node
## Profil du joueur : niveau de compte, compétences, campagne, battle pass, défis, cosmétiques.
## Sauvegardé localement (user://profil.json) et synchronisable avec l'API méta (voir Backend).

signal changed
signal level_up(new_level: int)
signal bp_tier_up(new_tier: int)

const PATH := "user://profil.json"
const VERSION := 2   # 2 : sauvegarde cloud (updated_at, fusion) — les profils v1 sont repris tels quels
const BACKUP_V1 := "user://profil.v1.sauvegarde.json"
const BACKUP_SYNC := "user://profil.avant-synchro.json"

var data: Dictionary = {}


func _ready() -> void:
	if OS.has_feature("dedicated_server") or "--server" in OS.get_cmdline_user_args():
		sandbox = true   # un serveur de jeu n'écrit jamais de sauvegarde
	load_profile()
	refresh_challenges()


func _default() -> Dictionary:
	return {
		"version": VERSION,
		"player_id": "",
		"level": 1, "xp": 0, "skill_points_earned": 1,
		"puces": 200, "neons": 0,
		"skills": {},
		"campaign": {"completed": [], "best_endless": 0},
		"character": "patatron",
		"cosmetics": {"hats": [], "colors": [], "titles": [], "hat": "", "color": "", "title": ""},
		"battlepass": {"season": int(Db.battlepass.get("season", 1)), "xp": 0, "premium": false, "claimed_free": [], "claimed_premium": []},
		"challenges": {"daily_key": "", "daily": [], "weekly_key": "", "weekly": []},
		"lifetime": {},
		"updated_at": 0,
	}


func load_profile() -> void:
	data = _default()
	if FileAccess.file_exists(PATH):
		var f = FileAccess.open(PATH, FileAccess.READ)
		var raw := f.get_as_text()
		var parsed = JSON.parse_string(raw)
		if typeof(parsed) == TYPE_DICTIONARY:
			# Première version du jeu : copie intacte de l'ancienne sauvegarde avant toute migration.
			if int(parsed.get("version", 1)) < VERSION and not sandbox and not FileAccess.file_exists(BACKUP_V1):
				var b := FileAccess.open(BACKUP_V1, FileAccess.WRITE)
				if b:
					b.store_string(raw)
			_merge(data, ints(parsed))
			data.version = VERSION
		else:
			# Fichier illisible (coupure pendant l'écriture…) : on le garde de côté plutôt que de l'écraser.
			if not sandbox:
				DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path("user://profil.illisible.json"))
			if FileAccess.file_exists(BACKUP_SYNC):
				var bk = JSON.parse_string(FileAccess.get_file_as_string(BACKUP_SYNC))
				if bk is Dictionary:
					_merge(data, ints(bk))
	if data.player_id == "":
		data.player_id = _uuid()
	# Nouvelle saison : on remet à zéro la progression du battle pass.
	if int(data.battlepass.season) != int(Db.battlepass.get("season", 1)):
		data.battlepass = _default().battlepass


## Les nombres relus depuis du JSON sont des flottants : on remet les entiers en int (« 569.0 » -> 569).
static func ints(v):
	if v is float and v == floor(v) and abs(v) < 1e15:
		return int(v)
	if v is Array:
		return v.map(func(x): return ints(x))
	if v is Dictionary:
		var o := {}
		for k in v:
			o[k] = ints(v[k])
		return o
	return v


func _merge(base: Dictionary, over: Dictionary) -> void:
	for k in over:
		if base.has(k) and typeof(base[k]) == TYPE_DICTIONARY and typeof(over[k]) == TYPE_DICTIONARY:
			_merge(base[k], over[k])
		else:
			base[k] = over[k]


var sandbox := false   # outils de test (captures, bande-annonce, tests auto) : rien n'est écrit sur le disque
var edits := 0         # incrémenté à chaque sauvegarde (la synchro cloud détecte les modifications en vol)


func save() -> void:
	if sandbox:
		return
	data.updated_at = int(Time.get_unix_time_from_system())
	edits += 1
	_write()
	changed.emit()
	Backend.queue_sync()


func _write() -> void:
	var tmp := PATH + ".tmp"
	var f = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(PATH))


var _backed_up := false


## Remplace le profil local par la version fusionnée renvoyée par le cloud (sans relancer de synchro).
func apply_cloud(merged: Dictionary) -> void:
	if not sandbox and not _backed_up and FileAccess.file_exists(PATH):
		_backed_up = true   # une copie par session, avant la première fusion
		DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(BACKUP_SYNC))
	var pid := String(data.player_id)
	data = _default()
	_merge(data, ints(merged))
	data.player_id = pid
	if int(data.battlepass.season) != int(Db.battlepass.get("season", 1)):
		data.battlepass = _default().battlepass
	if not sandbox:
		_write()
	refresh_challenges()
	changed.emit()


func _uuid() -> String:
	var s := ""
	for i in 16:
		s += "%02x" % (randi() % 256)
	return s


# ------------------------------------------------------------------ niveau de compte
func xp_for_level(lvl: int) -> int:
	return 400 + 150 * lvl


func add_account_xp(amount: int) -> int:
	var gained := 0
	data.xp += amount
	while data.xp >= xp_for_level(data.level):
		data.xp -= xp_for_level(data.level)
		data.level += 1
		data.skill_points_earned += 1
		data.neons += 25
		gained += 1
		level_up.emit(data.level)
	return gained


# ------------------------------------------------------------------ compétences
func skill_rank(id: String) -> int:
	return int(data.skills.get(id, 0))


func spent_points() -> int:
	var total := 0
	for id in data.skills:
		var n = Db.skill_node(id)
		total += int(n.get("cost", 1)) * int(data.skills[id])
	return total


func available_points() -> int:
	return int(data.skill_points_earned) - spent_points()


func skill_unlockable(id: String) -> bool:
	var n = Db.skill_node(id)
	if n.is_empty():
		return false
	if skill_rank(id) >= int(n.max):
		return false
	if available_points() < int(n.cost):
		return false
	return skill_requirements_met(id)


func skill_requirements_met(id: String) -> bool:
	var n = Db.skill_node(id)
	var reqs: Array = n.get("req", [])
	if reqs.is_empty():
		return true
	var any: bool = n.get("req_any", false)
	var met := 0
	for r in reqs:
		if skill_rank(r) > 0:
			met += 1
	return met > 0 if any else met == reqs.size()


func unlock_skill(id: String) -> bool:
	if not skill_unlockable(id):
		return false
	data.skills[id] = skill_rank(id) + 1
	save()
	return true


func respec_cost() -> int:
	return 100 + spent_points() * 10


func respec() -> bool:
	if data.puces < respec_cost():
		return false
	data.puces -= respec_cost()
	data.skills = {}
	save()
	return true


## Bonus de statistiques cumulés de l'arbre de compétences, appliqués au début de chaque partie.
func skill_stats() -> Dictionary:
	var out := {}
	for id in data.skills:
		var n = Db.skill_node(id)
		var rank = int(data.skills[id])
		for k in n.get("stats", {}):
			out[k] = out.get(k, 0) + n.stats[k] * rank
	return out


# ------------------------------------------------------------------ campagne & personnages
func mission_completed(id: String) -> bool:
	return id in data.campaign.completed


func mission_unlocked(id: String) -> bool:
	var all = Db.all_missions()
	for i in all.size():
		if all[i].id == id:
			return i == 0 or mission_completed(all[i - 1].id)
	return false


func complete_mission(id: String) -> bool:
	if mission_completed(id):
		return false
	data.campaign.completed.append(id)
	return true


func character_unlocked(id: String) -> bool:
	var req: String = Db.characters.get(id, {}).get("unlock", "")
	return req == "" or mission_completed(req)


# ------------------------------------------------------------------ cosmétiques
func owns(kind: String, id: String) -> bool:
	return id in data.cosmetics.get(kind, [])


func equip(slot: String, id: String) -> void:
	data.cosmetics[slot] = id
	save()


func cosmetics_payload() -> Dictionary:
	return {"hat": data.cosmetics.hat, "color": data.cosmetics.color, "title": data.cosmetics.title}


# ------------------------------------------------------------------ battle pass
func bp_tier() -> int:
	return int(data.battlepass.xp) / int(Db.battlepass.xp_per_tier)


func bp_progress() -> float:
	var per = int(Db.battlepass.xp_per_tier)
	return float(int(data.battlepass.xp) % per) / per


func add_bp_xp(amount: int) -> void:
	var before := bp_tier()
	var max_xp = int(Db.battlepass.xp_per_tier) * Db.battlepass.tiers.size()
	data.battlepass.xp = min(int(data.battlepass.xp) + amount, max_xp)
	var after := bp_tier()
	if after > before:
		bp_tier_up.emit(after)


func bp_claimable(tier: int, track: String) -> bool:
	if tier > bp_tier():
		return false
	if track == "premium" and not data.battlepass.premium:
		return false
	return not (tier in data.battlepass["claimed_" + track])


func bp_claim(tier: int, track: String) -> Dictionary:
	if not bp_claimable(tier, track):
		return {}
	var reward: Dictionary = Db.battlepass.tiers[tier - 1][track]
	data.battlepass["claimed_" + track].append(tier)
	grant(reward)
	save()
	return reward


func bp_claim_all() -> int:
	var n := 0
	for t in range(1, bp_tier() + 1):
		for track in ["free", "premium"]:
			if bp_claimable(t, track):
				var reward: Dictionary = Db.battlepass.tiers[t - 1][track]
				data.battlepass["claimed_" + track].append(t)
				grant(reward)
				n += 1
	if n > 0:
		save()
	return n


func bp_buy_premium() -> bool:
	var price = int(Db.battlepass.premium_price_neons)
	if data.battlepass.premium or data.neons < price:
		return false
	data.neons -= price
	data.battlepass.premium = true
	save()
	return true


func bp_buy_tier() -> bool:
	var price = int(Db.battlepass.tier_skip_neons)
	if data.neons < price or bp_tier() >= Db.battlepass.tiers.size():
		return false
	data.neons -= price
	add_bp_xp(int(Db.battlepass.xp_per_tier))
	save()
	return true


func grant(reward: Dictionary) -> void:
	match reward.get("type", ""):
		"puces":
			data.puces += int(reward.amount)
		"neons":
			data.neons += int(reward.amount)
		"skill_point":
			data.skill_points_earned += int(reward.amount)
		"hat":
			if not owns("hats", reward.id):
				data.cosmetics.hats.append(reward.id)
		"color":
			if not owns("colors", reward.id):
				data.cosmetics.colors.append(reward.id)
		"title":
			if not owns("titles", reward.id):
				data.cosmetics.titles.append(reward.id)


func reward_text(reward: Dictionary) -> String:
	match reward.get("type", ""):
		"puces":
			return "%d puces" % reward.amount
		"neons":
			return "%d néons" % reward.amount
		"skill_point":
			return "%d point%s de compétence" % [reward.amount, "s" if reward.amount > 1 else ""]
		"hat":
			return "Chapeau : " + Db.battlepass.hats.get(reward.id, {}).get("name", reward.id)
		"color":
			return "Couleur : " + Db.battlepass.colors.get(reward.id, {}).get("name", reward.id)
		"title":
			return "Titre : « %s »" % Db.battlepass.titles.get(reward.id, reward.id)
	return "?"


func reward_icon(reward: Dictionary) -> String:
	match reward.get("type", ""):
		"puces":
			return "res://assets/sprites/ui/puces.png"
		"neons":
			return "res://assets/sprites/ui/neons.png"
		"skill_point":
			return "res://assets/sprites/ui/point_competence.png"
		"hat":
			return Db.battlepass.hats.get(reward.id, {}).get("sprite", "")
		"color":
			return "res://assets/sprites/characters/patatron.png"
		"title":
			return "res://assets/sprites/ui/titre.png"
	return ""


# ------------------------------------------------------------------ défis
func _date_key() -> String:
	var d = Time.get_date_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]


func _week_key() -> String:
	var unix = int(Time.get_unix_time_from_system())
	return "S%d" % ((unix / 86400 + 3) / 7)   # semaine commençant le lundi


func refresh_challenges() -> void:
	var dk := _date_key()
	if data.challenges.daily_key != dk:
		data.challenges.daily_key = dk
		data.challenges.daily = _pick_challenges(Db.battlepass.challenges.daily, 3, dk.hash())
	var wk := _week_key()
	if data.challenges.weekly_key != wk:
		data.challenges.weekly_key = wk
		data.challenges.weekly = _pick_challenges(Db.battlepass.challenges.weekly, 3, wk.hash())


func _pick_challenges(pool: Array, n: int, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var copy := pool.duplicate()
	var out := []
	for i in min(n, copy.size()):
		var c: Dictionary = copy.pop_at(rng.randi() % copy.size())
		out.append({"id": c.id, "progress": 0, "done": false})
	return out


func challenge_def(id: String) -> Dictionary:
	for kind in ["daily", "weekly"]:
		for c in Db.battlepass.challenges[kind]:
			if c.id == id:
				return c
	return {}


## Enregistre une statistique de jeu (éliminations, vagues…) pour les défis et les statistiques à vie.
func track(stat: String, amount: int = 1) -> Array:
	refresh_challenges()
	data.lifetime[stat] = int(data.lifetime.get(stat, 0)) + amount
	var completed := []
	for kind in ["daily", "weekly"]:
		for c in data.challenges[kind]:
			var def = challenge_def(c.id)
			if def.is_empty() or c.done or def.stat != stat:
				continue
			c.progress = min(int(c.progress) + amount, int(def.n))
			if c.progress >= int(def.n):
				c.done = true
				add_bp_xp(int(def.xp))
				completed.append(def)
	return completed


## Applique les récompenses de fin de partie et renvoie un résumé pour l'écran de résultats.
func apply_run_rewards(r: Dictionary) -> Dictionary:
	var bp = Db.battlepass.xp_sources
	var bp_xp = int(r.get("waves", 0)) * int(bp.wave) + int(r.get("kills", 0)) * int(bp.kill) + int(r.get("bosses", 0)) * int(bp.boss)
	if r.get("victory", false):
		bp_xp += int(bp.victory)
	var first_clear := false
	if r.get("victory", false) and r.get("mission", "") != "":
		first_clear = complete_mission(r.mission)
		if first_clear:
			bp_xp += int(bp.mission_first_clear)
		track("missions")
	bp_xp += int(r.get("pvp_rounds", 0)) * int(bp.pvp_round_win)
	if r.get("pvp_win", false):
		bp_xp += int(bp.pvp_match_win)
	if r.get("coop", false):
		bp_xp = int(bp_xp * (1.0 + float(bp.coop_bonus_pct) / 100.0))
	var mult: float = float(r.get("reward_mult", 1.0))
	bp_xp = int(bp_xp * mult)
	var account_xp := int(bp_xp * 0.8) + 50
	var puces = int(r.get("waves", 0)) * 12 + int(r.get("bosses", 0)) * 80 + (150 if r.get("victory", false) else 0) + int(r.get("kills", 0)) / 10
	puces = int(puces * mult)
	var tier_before := bp_tier()
	add_bp_xp(bp_xp)
	var levels := add_account_xp(account_xp)
	data.puces += puces
	var done := []
	for stat in ["kills", "waves", "data", "bosses", "purchases", "levels", "pvp_rounds"]:
		if int(r.get(stat, 0)) > 0:
			done.append_array(track(stat, int(r[stat])))
	if r.get("coop", false):
		done.append_array(track("coop_games"))
	if r.get("pvp_win", false):
		done.append_array(track("pvp_wins"))
	if r.get("mode", "") == "endless":
		data.campaign.best_endless = max(int(data.campaign.best_endless), int(r.get("waves", 0)))
	save()
	return {"bp_xp": bp_xp, "account_xp": account_xp, "puces": puces, "levels": levels,
		"tiers": bp_tier() - tier_before, "challenges": done, "first_clear": first_clear}
