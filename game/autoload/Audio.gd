extends Node
## Audio manager: pooled 3D/2D sound effects with recorded variants, per-zone
## music with crossfades (combat and boss themes on top), and a layered
## soundscape (wind, birds by day, crickets at night, rain, streams) driven by
## the weather, the clock and where the player stands.
##
## Every recording is CC0 (see CREDITS.md). Variants live in
## res://assets/audio/sfx/<name>_<n>.ogg and are found at startup.

const SFX_DIR := "res://assets/audio/sfx/"
const AMB_DIR := "res://assets/audio/amb/"
const MUSIC_DIR := "res://assets/audio/music/"
## old call names -> sound sets
const ALIAS := {
	"swing": "swing_light", "impact": "hit_blade", "deflect": "clash", "ui": "ui_click",
	"footstep": "footstep_dirt", "enemy_attack": "swing_light", "footstep_sand": "footstep_dirt",
	"footstep_snow": "footstep_mud", "footstep_road": "footstep_rock", "footstep_stone": "footstep_rock",
	"hoof_grass": "hoof_dirt", "hoof_mud": "hoof_dirt", "hoof_rock": "hoof_hard", "hoof_road": "hoof_hard",
	"hoof_stone": "hoof_hard", "hoof_wood": "hoof_hard", "hoof_water": "footstep_water",
	# v0.16
	"assassinate": "deathblow", "mikiri": "clash", "drink": "heal",
}
## per-set level (dB) so callers only express relative loudness
const LEVEL := {
	"swing_light": -3.0, "swing_heavy": -2.0, "hit_blade": -1.0, "hit_blunt": -2.0, "clash": -1.0,
	"block": -3.0, "posture_break": -1.0, "deathblow": 0.0, "bodyfall": -4.0,
	"footstep_grass": -9.0, "footstep_dirt": -10.0, "footstep_rock": -10.0, "footstep_wood": -9.0,
	"footstep_mud": -9.0, "footstep_water": -8.0, "cloth": -8.0, "land": -6.0,
	"hoof_dirt": -5.0, "hoof_hard": -7.0, "horse_neigh": -4.0, "horse_snort": -6.0,
	"ui_click": -8.0, "ui_select": -8.0, "ui_confirm": -6.0, "ui_back": -8.0,
	"smoke": -3.0, "quest": -4.0, "heal": -8.0, "discover": -6.0, "taiko": -3.0, "drum": -4.0,
	"bow": -5.0, "arrow_hit": -5.0, "telegraph": -6.0, "draw": -4.0, "sheathe": -5.0,
	# v0.15 wildlife, hunting, map, night
	"deer_alarm": -5.0, "fox_bark": -7.0, "boar_grunt": -4.0, "boar_squeal": -4.0,
	"wolf_howl": -3.0, "wolf_growl": -3.0, "wolf_yelp": -5.0, "harvest": -6.0,
	"map_open": -9.0, "owl": -9.0,
	# v0.23 sets: prologue, title, horse
	"whoosh_big": -4.0, "boom": -3.0, "sword_ring": -7.0, "brush": -6.0, "temple_bell": -8.0,
	"conch": -6.0, "horse_breath": -9.0, "fire_whoosh": -7.0, "riser": -6.0,
}
## sets heard from far off: [max distance m, unit size] for the 3D voice
const FAR := {"wolf_howl": [450.0, 45.0], "owl": [170.0, 24.0], "deer_alarm": [120.0, 12.0],
	"fox_bark": [110.0, 11.0]}
## sets that must not be pitched far from the recording
const NO_BIG_PITCH := ["horse_neigh", "horse_snort", "quest", "discover", "ui_confirm",
	"temple_bell", "sword_ring", "conch", "horse_breath", "boom", "riser"]
const MUSIC := {
	"menu": "menu", "shrine": "shrine", "forest": "forest", "bamboo": "bamboo", "village": "village",
	"farmland": "farmland", "grassland": "grassland", "lake": "lake", "ruins": "ruins",
	"castle": "castle", "mountain": "mountain", "combat": "combat", "combat2": "combat2", "boss": "boss",
}
const AMB_LAYERS := ["wind", "wind_strong", "birds", "night", "rain", "stream"]
## v0.23 per-track gain (dB) hook. tools/audio_audit_v23.py measured every zone
## track at -18.6 LUFS integrated (all within 0.3 dB) and the prologue score is
## mastered to the same level, so no track needs a trim today.
const MUSIC_GAIN := {}

var _sets := {}                 ## name -> Array[AudioStream]
var _sfx3d: Array[AudioStreamPlayer3D] = []
var _sfx2d: Array[AudioStreamPlayer] = []
var _music: Array[AudioStreamPlayer] = []
var _music_active := 0
var _amb := {}                  ## layer -> AudioStreamPlayer
var _amb_db := {}               ## layer -> current dB
var _cache := {}
var _last_played := {}
var _last_variant := {}
var _combat := false
var _boss := false
var _current_track := ""
var _amb_t := 0.0
var _owl_t := 20.0
var _ambient: AudioStreamPlayer  ## kept for old callers (the wind layer)
## v0.23 score: a one-shot cue (the prologue) owns the music until stop_score()
var _score := ""
var _pending_track := ""
var _duck: AudioEffectAmplify
var _duck_db := 0.0
var _duck_want := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_scan()
	for i in 20:
		var p := AudioStreamPlayer3D.new()
		p.bus = "SFX"; p.max_distance = 60.0; p.unit_size = 7.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.attenuation_filter_cutoff_hz = 9000.0
		p.attenuation_filter_db = -12.0
		add_child(p); _sfx3d.append(p)
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p); _sfx2d.append(p)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		add_child(p); _music.append(p)
	for layer in AMB_LAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambience"
		var s := _load(AMB_DIR + layer + ".ogg")
		if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
		p.stream = s
		p.volume_db = -80.0
		add_child(p)
		_amb[layer] = p
		_amb_db[layer] = -80.0
	_ambient = _amb["wind"]
	_set_layer("wind", -20.0, true)

## Find every <name>_<n>.ogg once (in exported builds only the .import files
## are listed, so strip that suffix).
func _scan() -> void:
	var d := DirAccess.open(SFX_DIR)
	if d == null: return
	var seen := {}
	for f in d.get_files():
		var fn := String(f)
		if fn.ends_with(".import"): fn = fn.substr(0, fn.length() - 7)
		if not fn.ends_with(".ogg") or seen.has(fn): continue
		seen[fn] = true
		var base := fn.get_basename()
		var cut := base.rfind("_")
		if cut <= 0: continue
		var name := base.substr(0, cut)
		if not _sets.has(name): _sets[name] = []
		_sets[name].append(SFX_DIR + fn)

func _setup_buses() -> void:
	for b in ["Music", "SFX", "Ambience"]:
		if AudioServer.get_bus_index(b) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, b)
			AudioServer.set_bus_send(idx, "Master")
	# a little room on the effects so hits do not sound pasted on
	var sfx := AudioServer.get_bus_index("SFX")
	if sfx >= 0 and AudioServer.get_bus_effect_count(sfx) == 0:
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.35; rv.damping = 0.6; rv.wet = 0.08; rv.dry = 1.0; rv.spread = 0.8
		AudioServer.add_bus_effect(sfx, rv)
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -0.5; lim.threshold_db = -3.0
		AudioServer.add_bus_effect(sfx, lim)
	# v0.22 mix: the music ducks a little under loud hits (sidechained to the
	# effects bus) so clashes cut through, and the master bus is glued by a
	# gentle compressor and caught by a limiter, so a big fight with music,
	# rain and ten swords never clips or turns harsh.
	var mus := AudioServer.get_bus_index("Music")
	if mus >= 0 and AudioServer.get_bus_effect_count(mus) == 0:
		var duck := AudioEffectCompressor.new()
		duck.sidechain = &"SFX"
		duck.threshold = -22.0; duck.ratio = 2.5
		duck.attack_us = 15000.0; duck.release_ms = 420.0
		AudioServer.add_bus_effect(mus, duck)
		_duck = AudioEffectAmplify.new()
		_duck.volume_db = 0.0
		AudioServer.add_bus_effect(mus, _duck)
	if AudioServer.get_bus_effect_count(0) == 0:
		var glue := AudioEffectCompressor.new()
		glue.threshold = -14.0; glue.ratio = 2.0
		glue.attack_us = 12000.0; glue.release_ms = 220.0
		AudioServer.add_bus_effect(0, glue)
		var ml := AudioEffectLimiter.new()
		ml.ceiling_db = -0.8; ml.threshold_db = -2.0
		AudioServer.add_bus_effect(0, ml)
	apply_volumes()

func apply_volumes() -> void:
	# The pause menu writes "music" / "sfx". v0.13 read "music_vol" / "sfx_vol",
	# keys nothing ever set, so the sliders changed nothing and the music
	# played on at the default level whatever you did.
	_set_bus_volume("Master", float(Game.settings.get("master", 1.0)))
	_set_bus_volume("Music", float(Game.settings.get("music", 0.7)))
	_set_bus_volume("SFX", float(Game.settings.get("sfx", 0.9)))
	_set_bus_volume("Ambience", float(Game.settings.get("ambience", 0.8)))

## v0.15: slider position -> bus gain on a perceptual curve.
## The old mapping was linear_to_db(v): 10% is only -20 dB, which a listener
## hears as roughly a third to a half of full volume, so the bottom of the
## slider did almost nothing until the last notch muted it outright -- "10%
## sounds like 50%, then 0". Gain = v^2 puts 50% at -12 dB (a bit under half
## as loud), 25% at -24 dB and 10% at -40 dB (quiet but clearly there), so the
## whole travel of the slider is usable.
static func slider_db(v: float) -> float:
	if v <= 0.001: return -80.0
	return 40.0 * (log(v) / log(10.0))

func _set_bus_volume(bus: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1: return
	AudioServer.set_bus_volume_db(idx, slider_db(linear))
	AudioServer.set_bus_mute(idx, linear <= 0.001)

func _load(path: String) -> AudioStream:
	if _cache.has(path): return _cache[path]
	if not ResourceLoader.exists(path): return null
	var s = load(path)
	_cache[path] = s
	return s

func has_sound(name: String) -> bool:
	return _sets.has(str(ALIAS.get(name, name)))

## Play one variant of a sound set. pos = null plays it flat (UI, music stings).
func play_sfx(name: String, pos = null, pitch: float = 1.0, vol_db: float = 0.0) -> void:
	if not _sets.has(name): name = str(ALIAS.get(name, name))
	if not _sets.has(name): return
	var variants: Array = _sets[name]
	# never the same variant twice in a row
	var k := randi() % variants.size()
	if variants.size() > 1 and _last_variant.get(name, -1) == k: k = (k + 1) % variants.size()
	_last_variant[name] = k
	var stream := _load(variants[k])
	if stream == null: return
	var now := Time.get_ticks_msec()
	if _last_played.has(name) and now - int(_last_played[name]) < 30 and pos == null:
		return
	_last_played[name] = now
	var lo := 0.9 if NO_BIG_PITCH.has(name) else 0.72
	var hi := 1.1 if NO_BIG_PITCH.has(name) else 1.4
	var p_scale := clampf(pitch * randf_range(0.97, 1.03), lo, hi)
	var db := vol_db + float(LEVEL.get(name, -4.0))
	if pos != null:
		var best: AudioStreamPlayer3D = null
		for p in _sfx3d:
			if not p.playing: best = p; break
		if best == null:
			# steal the oldest-sounding (furthest along) voice
			var far := -1.0
			for p in _sfx3d:
				var t := p.get_playback_position()
				if t > far: far = t; best = p
		best.stream = stream; best.global_position = pos
		best.pitch_scale = p_scale; best.volume_db = db
		var far: Array = FAR.get(name, [60.0, 7.0])
		best.max_distance = float(far[0]); best.unit_size = float(far[1])
		best.play()
	else:
		for p in _sfx2d:
			if not p.playing:
				p.stream = stream; p.pitch_scale = p_scale
				p.volume_db = db; p.play(); return

func play_ui(kind: String = "click") -> void:
	play_sfx("ui_" + kind, null, 1.0, 0.0)

# ---------------------------------------------------------------- music
func _music_stream(key: String) -> AudioStream:
	var s := _load(MUSIC_DIR + str(MUSIC.get(key, "shrine")) + ".ogg")
	if s is AudioStreamOggVorbis: (s as AudioStreamOggVorbis).loop = true
	return s

## v0.23 play a one-shot cue on the music bus (no loop); zone changes are
## remembered and resumed by stop_score().
func play_score(key: String) -> void:
	var s = _load(MUSIC_DIR + key + ".ogg")
	if s == null: return
	if s is AudioStreamOggVorbis:
		s = (s as AudioStreamOggVorbis).duplicate()
		(s as AudioStreamOggVorbis).loop = false
	if _score == "": _pending_track = _current_track
	_score = key
	_current_track = "score:" + key
	_crossfade(s, 0.4, float(MUSIC_GAIN.get(key, 0.0)))

func stop_score(fade := 3.0) -> void:
	if _score == "": return
	_score = ""
	var key := _pending_track
	if key == "" or key == "menu" or key.begins_with("score:"): key = Game.zone
	var stream := _music_stream(key)
	_current_track = key
	if stream != null: _crossfade(stream, fade, float(MUSIC_GAIN.get(key, 0.0)))

func score_playing() -> bool:
	return _score != ""

## v0.23 story dialogue: the music steps back 5 dB while someone speaks.
func duck_dialogue(on: bool) -> void:
	_duck_want = -5.0 if on else 0.0

func play_music(track_key: String) -> void:
	if _score != "":
		_pending_track = track_key
		return
	if (_combat or _boss) and track_key != "menu": return
	if _current_track == track_key: return
	var stream := _music_stream(track_key)
	if stream == null: return
	_current_track = track_key
	_crossfade(stream, 2.4, float(MUSIC_GAIN.get(track_key, 0.0)))

func set_combat(on: bool) -> void:
	if _combat == on: return
	_combat = on
	if _boss or _score != "": return
	var key := ("combat" if randf() < 0.6 else "combat2") if on else Game.zone
	var stream := _music_stream(key)
	if stream == null: return
	_current_track = key
	_crossfade(stream, 0.9 if on else 3.0, float(MUSIC_GAIN.get(key, 0.0)))
	if on: play_sfx("drum", null, 1.0, -2.0)

func set_boss(on: bool) -> void:
	if _boss == on: return
	_boss = on
	if _score != "": return
	var key := "boss" if on else ("combat" if _combat else Game.zone)
	var stream := _music_stream(key)
	if stream == null: return
	_current_track = key
	_crossfade(stream, 1.2, float(MUSIC_GAIN.get(key, 0.0)))

func _crossfade(stream: AudioStream, dur: float = 1.6, gain_db: float = 0.0) -> void:
	var outgoing := _music[_music_active]
	_music_active = 1 - _music_active
	var incoming := _music[_music_active]
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(incoming, "volume_db", gain_db, dur)
	if outgoing.playing:
		tw.tween_property(outgoing, "volume_db", -40.0, dur)
		tw.chain().tween_callback(outgoing.stop)

# ---------------------------------------------------------------- soundscape
func _set_layer(layer: String, db: float, instant := false) -> void:
	var p: AudioStreamPlayer = _amb.get(layer)
	if p == null or p.stream == null: return
	var cur: float = _amb_db[layer]
	var v := db if instant else move_toward(cur, db, 3.0)   # <= 3 dB per update (0.25 s)
	_amb_db[layer] = v
	p.volume_db = v
	if v <= -59.0:
		if p.playing: p.stop()
	elif not p.playing:
		p.play(randf() * 20.0)

func _process(delta: float) -> void:
	if _duck != null and absf(_duck_db - _duck_want) > 0.01:
		_duck_db = move_toward(_duck_db, _duck_want, delta * 10.0)
		_duck.volume_db = _duck_db
	_amb_t += delta
	if _amb_t < 0.25: return
	_amb_t = 0.0
	var w = Game.world_ref
	if w == null or not is_instance_valid(w) or not ("weather" in w) or w.weather == null:
		# menus: a quiet breeze only
		for l in AMB_LAYERS: _set_layer(l, -24.0 if l == "wind" else -80.0)
		return
	var wx = w.weather
	var hour := 12.0
	if "daynight" in w and w.daynight != null: hour = float(w.daynight.hour)
	var rain := clampf(float(wx.rain), 0.0, 1.0)
	var wind := clampf(float(wx.wind), 0.0, 2.5)
	var day := clampf(minf((hour - 4.8) / 1.5, (19.6 - hour) / 1.5), 0.0, 1.0)
	var night := clampf(minf((hour - 19.0) / 1.2, 1.0) if hour > 12.0 else (4.6 - hour) / 1.2, 0.0, 1.0)
	var alt := 0.0
	var water := 0.0
	var pl = Game.player_ref
	if pl != null and is_instance_valid(pl):
		alt = clampf((float(pl.global_position.y) - 70.0) / 50.0, 0.0, 1.0)
		if w.has_method("water_proximity"): water = float(w.water_proximity(pl.global_position))
	_set_layer("wind", lerpf(-26.0, -13.0, clampf(wind / 1.4, 0.0, 1.0)) + alt * 4.0)
	_set_layer("wind_strong", -80.0 if wind < 0.8 and alt < 0.3 else lerpf(-34.0, -12.0, clampf(maxf((wind - 0.8) / 1.4, alt), 0.0, 1.0)))
	_set_layer("birds", -80.0 if day * (1.0 - rain) * (1.0 - alt) < 0.05 else lerpf(-40.0, -15.0, day * (1.0 - rain) * (1.0 - alt * 0.7)))
	_set_layer("night", -80.0 if night * (1.0 - rain) < 0.05 else lerpf(-40.0, -17.0, night * (1.0 - rain)))
	# v0.15: the odd owl somewhere out in the dark
	_owl_t -= 0.25
	if night > 0.6 and rain < 0.4 and alt < 0.6 and _owl_t <= 0.0 and pl != null and is_instance_valid(pl):
		_owl_t = randf_range(22.0, 55.0)
		var a := randf() * TAU
		var r := randf_range(35.0, 90.0)
		var op: Vector3 = pl.global_position + Vector3(sin(a) * r, randf_range(6.0, 14.0), cos(a) * r)
		play_sfx("owl", op, randf_range(0.94, 1.04), 0.0)
	_set_layer("rain", -80.0 if rain < 0.03 else lerpf(-32.0, -8.0, rain))
	_set_layer("stream", -80.0 if water < 0.03 else lerpf(-36.0, -9.0, water))

func haptic(kind: String) -> void:
	if not bool(Game.settings.get("haptics", true)): return
	match kind:
		"deflect": Input.vibrate_handheld(60, 0.7)
		"hit": Input.vibrate_handheld(40, 0.4)
		"heavy": Input.vibrate_handheld(90, 0.9)
		"deathblow": Input.vibrate_handheld(200, 1.0)
		"stance": Input.vibrate_handheld(25, 0.25)
		_: Input.vibrate_handheld(30, 0.3)
