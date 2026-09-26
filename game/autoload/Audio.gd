extends Node
## Audio manager: pooled SFX, music zones with crossfade, ambience, haptics.

const SFX := {
	"swing": ["res://assets/audio/swing.wav", "res://assets/audio/swing2.wav"],
	"impact": ["res://assets/audio/impact.wav", "res://assets/audio/impact2.wav"],
	"deflect": ["res://assets/audio/deflect.wav"],
	"posture_break": ["res://assets/audio/posture_break.wav"],
	"footstep": ["res://assets/audio/footstep.wav", "res://assets/audio/footstep2.wav"],
	"enemy_attack": ["res://assets/audio/enemy_attack.wav"],
	"deathblow": ["res://assets/audio/deathblow.wav"],
	"ui": ["res://assets/audio/ui_click.wav"],
	"quest": ["res://assets/audio/quest.wav"],
	"heal": ["res://assets/audio/heal.wav"],
}
const MUSIC := {
	"shrine": "res://assets/audio/music_shrine.wav",
	"forest": "res://assets/audio/music_explore.wav",
	"village": "res://assets/audio/music_explore.wav",
	"castle": "res://assets/audio/music_castle.wav",
	"mountain": "res://assets/audio/music_castle.wav",
	"combat": "res://assets/audio/music_combat.wav",
	"menu": "res://assets/audio/music_shrine.wav",
}

var _sfx3d: Array[AudioStreamPlayer3D] = []
var _sfx2d: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _ambient: AudioStreamPlayer
var _cache := {}
var _last_played := {}
var _combat := false
var _current_track := ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	for i in 14:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"; p.max_distance = 45.0; p.unit_size = 6.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(p); _sfx3d.append(p)
	for i in 6:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p); _sfx2d.append(p)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p); _music.append(p)
	_ambient = AudioStreamPlayer.new()
	_ambient.bus = "Ambience"
	_ambient.stream = _load("res://assets/audio/ambient_wind.wav")
	if _ambient.stream is AudioStreamWAV:
		(_ambient.stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_ambient.volume_db = -20.0
	add_child(_ambient)
	_ambient.play()

func _setup_buses() -> void:
	for b in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(b) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	apply_volumes()

func apply_volumes() -> void:
	_set_bus_volume("Music", float(Game.settings.get("music", 0.7)))
	_set_bus_volume("SFX", float(Game.settings.get("sfx", 0.9)))
	_set_bus_volume("Ambience", float(Game.settings.get("sfx", 0.9)) * 0.7)

func _set_bus_volume(bus: String, linear: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i < 0: return
	AudioServer.set_bus_mute(i, linear <= 0.001)
	AudioServer.set_bus_volume_db(i, linear_to_db(clampf(linear, 0.0001, 1.0)))

func _load(path: String) -> AudioStream:
	if _cache.has(path): return _cache[path]
	if not ResourceLoader.exists(path): return null
	var s := load(path)
	_cache[path] = s
	return s

func play_sfx(name: String, pos = null, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not SFX.has(name): return
	var variants: Array = SFX[name]
	var path: String = variants[randi() % variants.size()]
	var stream := _load(path)
	if stream == null: return
	# throttle identical sounds in the same frame-ish window
	var now := Time.get_ticks_msec()
	if _last_played.has(name) and now - int(_last_played[name]) < 25 and pos == null:
		return
	_last_played[name] = now
	if pos != null:
		for p in _sfx3d:
			if not p.playing:
				p.stream = stream; p.global_position = pos
				p.pitch_scale = clampf(pitch, 0.4, 2.2); p.volume_db = vol_db
				p.play(); return
		_sfx3d[0].stream = stream; _sfx3d[0].global_position = pos; _sfx3d[0].play()
	else:
		for p in _sfx2d:
			if not p.playing:
				p.stream = stream; p.pitch_scale = clampf(pitch, 0.4, 2.2)
				p.volume_db = vol_db; p.play(); return

func play_ui() -> void:
	play_sfx("ui", null, 1.0, -4.0)

func play_music(track_key: String) -> void:
	if _combat and track_key != "menu": return
	if _current_track == track_key: return
	var path: String = MUSIC.get(track_key, MUSIC["shrine"])
	var stream := _load(path)
	if stream == null: return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_current_track = track_key
	_crossfade(stream)

func set_combat(on: bool) -> void:
	if _combat == on: return
	_combat = on
	var key := "combat" if on else Game.zone
	var stream := _load(MUSIC.get(key, MUSIC["shrine"]))
	if stream == null: return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_current_track = key
	_crossfade(stream, 0.8 if on else 1.4)

func _crossfade(stream: AudioStream, dur: float = 1.6) -> void:
	var outgoing := _music[_music_active]
	_music_active = 1 - _music_active
	var incoming := _music[_music_active]
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(incoming, "volume_db", 0.0, dur)
	if outgoing.playing:
		tw.tween_property(outgoing, "volume_db", -40.0, dur)
		tw.chain().tween_callback(outgoing.stop)

func haptic(kind: String) -> void:
	if not bool(Game.settings.get("haptics", true)): return
	match kind:
		"deflect": Input.vibrate_handheld(60, 0.7)
		"hit": Input.vibrate_handheld(40, 0.4)
		"heavy": Input.vibrate_handheld(90, 0.9)
		"deathblow": Input.vibrate_handheld(200, 1.0)
		"stance": Input.vibrate_handheld(25, 0.25)
		_: Input.vibrate_handheld(30, 0.3)
