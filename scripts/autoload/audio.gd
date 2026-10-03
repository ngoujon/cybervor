extends Node
## Gestion de la musique (fondu enchaîné) et des effets sonores (pool de lecteurs).

const MUSIC_DIR := "res://assets/music/"
const SFX_DIR := "res://assets/sfx/"
const POOL_SIZE := 24
const UI_SFX := ["clic", "survol", "erreur", "achat", "vente", "reroll", "palier", "niveau"]

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _current_music := ""
var _pool: Array[AudioStreamPlayer] = []
var _pool_2d: Array[AudioStreamPlayer2D] = []
var _streams: Dictionary = {}
var _last_play: Dictionary = {}
var _headless := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_headless = DisplayServer.get_name() == "headless"
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.bus = "Effets"
		add_child(p)
		_pool.append(p)
	for i in POOL_SIZE:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "Effets"
		p2.max_distance = 1800
		p2.attenuation = 1.5
		add_child(p2)
		_pool_2d.append(p2)


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Musique"
	p.volume_db = -80
	add_child(p)
	return p


func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
	_streams[path] = s
	return s


func play_music(name: String, fade := 1.2, loop := true) -> void:
	if _headless or name == _current_music:
		return
	_current_music = name
	var stream := _stream(MUSIC_DIR + name + ".ogg")
	var old := _music_a if _music_a.playing else _music_b
	var nxt := _music_b if old == _music_a else _music_a
	if stream:
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = loop
		nxt.stream = stream
		nxt.volume_db = -40
		nxt.play()
		var tw := create_tween()
		tw.tween_property(nxt, "volume_db", 0.0, fade)
	if old.playing:
		var tw2 := create_tween()
		tw2.tween_property(old, "volume_db", -60.0, fade)
		tw2.tween_callback(old.stop)


func stop_music(fade := 1.0) -> void:
	_current_music = ""
	for p in [_music_a, _music_b]:
		if p.playing:
			var tw := create_tween()
			tw.tween_property(p, "volume_db", -60.0, fade)
			tw.tween_callback(p.stop)


func current_music() -> String:
	return _current_music


## Joue un effet sonore. Anti-spam : un même son ne peut pas être joué plus de ~25 fois/s.
func play(name: String, volume_db := 0.0, pitch_var := 0.08) -> void:
	if _headless or name == "":
		return
	var now = Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 40:
		return
	_last_play[name] = now
	var stream := _stream(SFX_DIR + name + ".wav")
	if stream == null:
		return
	var p := _free_player(_pool)
	p.bus = "Interface" if name in UI_SFX else "Effets"
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_at(name: String, pos: Vector2, volume_db := 0.0, pitch_var := 0.1) -> void:
	if _headless or name == "":
		return
	var now = Time.get_ticks_msec()
	if now - int(_last_play.get(name, -1000)) < 45:
		return
	_last_play[name] = now
	var stream := _stream(SFX_DIR + name + ".wav")
	if stream == null:
		return
	var p := _free_player(_pool_2d)
	p.stream = stream
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_dialogue_blip() -> void:
	if _headless:
		return
	var stream = _stream(SFX_DIR + "dialogue.wav")
	if stream == null:
		return
	var p := _free_player(_pool)
	p.bus = "Dialogues"
	p.stream = stream
	p.volume_db = -6
	p.pitch_scale = randf_range(0.9, 1.25)
	p.play()


func _free_player(pool: Array) -> Node:
	for p in pool:
		if not p.playing:
			return p
	return pool[randi() % pool.size()]
