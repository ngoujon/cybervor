extends Node
## Base de données du jeu : charge les définitions JSON de res://data/.

var characters: Dictionary = {}
var weapons: Dictionary = {}
var items: Dictionary = {}
var stats: Dictionary = {}
var enemies: Dictionary = {}
var campaign: Dictionary = {}
var skills: Dictionary = {}
var battlepass: Dictionary = {}
var spells: Dictionary = {}       # sorts actifs / passifs et esquives par héros

var enemy_ids: Array = []          # index <-> id pour la synchro réseau compacte
var _textures: Dictionary = {}

const RARITY_NAMES := ["Commun", "Rare", "Épique", "Légendaire"]
const RARITY_COLORS := [Color("#d9d9d9"), Color("#4cc9f0"), Color("#c77dff"), Color("#ffb703")]
const TIER_NAMES := ["I", "II", "III", "IV"]
## Niveaux de difficulté (ennemis) et niveaux de l'IA adverse (PvP).
const DIFFICULTIES := [
	{"name": "Facile", "hp": 0.7, "dmg": 0.6, "spawn": 0.75, "reward": 0.75, "desc": "Pour découvrir le jeu (ou se détendre après le boulot)."},
	{"name": "Normal", "hp": 1.0, "dmg": 1.0, "spawn": 1.0, "reward": 1.0, "desc": "L'expérience prévue par Mamie RAM."},
	{"name": "Difficile", "hp": 1.35, "dmg": 1.3, "spawn": 1.25, "reward": 1.35, "desc": "Les bugs ont fait de la musculation."},
	{"name": "Cauchemar", "hp": 1.8, "dmg": 1.6, "spawn": 1.5, "reward": 1.8, "desc": "Mise à jour obligatoire à 3 h du matin. Bonne chance."},
]
## Niveaux de l'IA en arène : bonus de stats et qualité d'esquive / de visée.
const AI_LEVELS := [
	{"name": "IA Débutante", "hp": 0.8, "damage": -25, "dodge_skill": 0.35, "aim": 0.6},
	{"name": "IA Normale", "hp": 1.0, "damage": 0, "dodge_skill": 0.7, "aim": 0.85},
	{"name": "IA Experte", "hp": 1.25, "damage": 15, "dodge_skill": 1.0, "aim": 1.0},
	{"name": "IA Impitoyable", "hp": 1.6, "damage": 35, "dodge_skill": 1.3, "aim": 1.0},
]
const TEAM_NAMES := ["Équipe Néon", "Équipe Virus"]
const TEAM_COLORS := [Color("#5ff7ff"), Color("#ff4d6d")]


func _ready() -> void:
	characters = _load("characters")
	weapons = _load("weapons")
	items = _load("items")
	stats = _load("stats")
	stats.erase("_doc")
	enemies = _load("enemies")
	campaign = _load("campaign")
	skills = _load("skills")
	battlepass = _load("battlepass")
	spells = _load("spells")
	enemy_ids = enemies.keys()
	enemy_ids.sort()


func _load(name: String) -> Dictionary:
	var path := "res://data/%s.json" % name
	var f = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Impossible de lire " + path)
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("JSON invalide : " + path)
		return {}
	return data


func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _textures.has(path):
		return _textures[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_textures[path] = t
	return t


func enemy_index(id: String) -> int:
	return enemy_ids.find(id)


func zone(zone_id: String) -> Dictionary:
	for z in campaign.zones:
		if z.id == zone_id:
			return z
	return {}


func mission(mission_id: String) -> Dictionary:
	for z in campaign.zones:
		for m in z.missions:
			if m.id == mission_id:
				return m
	return {}


func zone_of_mission(mission_id: String) -> Dictionary:
	for z in campaign.zones:
		for m in z.missions:
			if m.id == mission_id:
				return z
	return {}


func all_missions() -> Array:
	var out := []
	for z in campaign.zones:
		for m in z.missions:
			out.append(m)
	return out


func skill_node(node_id: String) -> Dictionary:
	for t in skills.trees:
		for n in t.nodes:
			if n.id == node_id:
				return n
	return {}


func stat_name(key: String) -> String:
	return stats.get(key, {}).get("name", key)


func format_stats(st: Dictionary) -> String:
	var parts := []
	for k in st:
		var v = st[k]
		var sfx: String = stats.get(k, {}).get("suffix", "")
		var sign := "+" if v >= 0 else ""
		parts.append("%s%s%s %s" % [sign, _num(v), sfx, stat_name(k)])
	return "\n".join(parts)


func _num(v) -> String:
	if is_equal_approx(float(v), round(float(v))):
		return str(int(v))
	return "%.1f" % v
