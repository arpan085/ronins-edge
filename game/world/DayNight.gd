class_name DayNight
extends Node
## Smooth day/night cycle.
##
## Lighting is defined as keyframes on the 24 h clock and interpolated every
## frame, so dawn/golden hour/dusk arrive as gradual transitions instead of
## visible switches. Owns the sun, the moon, the sky material and the fog.

# hour -> lighting state
## Golden hour used to go almost black at ground level: at 6.2 and 19.2 the sun
## is grazing, so nearly all the light on the terrain is sky ambient, and the
## ambient energy and ground bounce were both set for a midday sky. Dawn, dusk
## and the hour either side now carry a warm bounce and about 25% more ambient,
## which is what lets a backlit field still read as green instead of silhouette.
const KEYS := [
	{"h": 0.0,  "sun": Color(0.10, 0.14, 0.26), "se": 0.0,  "moon": 0.78,
	 "top": Color(0.022, 0.034, 0.078), "hor": Color(0.060, 0.080, 0.140),
	 "gnd": Color(0.016, 0.019, 0.030), "fog": Color(0.050, 0.068, 0.120), "fd": 2.30, "amb": 0.62, "mist": 2.4, "sl": 0.0032},
	{"h": 4.6,  "sun": Color(0.16, 0.20, 0.34), "se": 0.02, "moon": 0.62,
	 "top": Color(0.058, 0.078, 0.150), "hor": Color(0.20, 0.185, 0.235),
	 "gnd": Color(0.048, 0.050, 0.062), "fog": Color(0.15, 0.16, 0.22), "fd": 2.10, "amb": 0.90, "mist": 2.8, "sl": 0.0103},
	{"h": 6.2,  "sun": Color(0.98, 0.62, 0.42), "se": 0.98, "moon": 0.30,
	 "top": Color(0.22, 0.32, 0.55), "hor": Color(0.92, 0.66, 0.50),
	 "gnd": Color(0.225, 0.185, 0.150), "fog": Color(0.70, 0.62, 0.58), "fd": 1.70, "amb": 1.34, "sl": 0.1209},
	{"h": 8.0,  "sun": Color(1.00, 0.88, 0.74), "se": 1.10, "moon": 0.0,
	 "top": Color(0.26, 0.42, 0.72), "hor": Color(0.70, 0.76, 0.80),
	 "gnd": Color(0.17, 0.17, 0.15), "fog": Color(0.70, 0.75, 0.80), "fd": 1.30, "amb": 0.95, "sl": 0.2481},
	{"h": 12.0, "sun": Color(1.00, 0.97, 0.92), "se": 1.55, "moon": 0.0,
	 "top": Color(0.28, 0.46, 0.80), "hor": Color(0.74, 0.80, 0.86),
	 "gnd": Color(0.20, 0.20, 0.18), "fog": Color(0.76, 0.81, 0.86), "fd": 0.85, "amb": 1.10, "sl": 0.3923},
	{"h": 15.5, "sun": Color(1.00, 0.93, 0.80), "se": 1.35, "moon": 0.0,
	 "top": Color(0.27, 0.44, 0.76), "hor": Color(0.78, 0.78, 0.76),
	 "gnd": Color(0.19, 0.18, 0.16), "fog": Color(0.76, 0.77, 0.78), "fd": 1.00, "amb": 1.00, "sl": 0.3012},
	{"h": 17.8, "sun": Color(1.00, 0.74, 0.44), "se": 1.18, "moon": 0.0,
	 "top": Color(0.24, 0.36, 0.66), "hor": Color(1.00, 0.70, 0.44),
	 "gnd": Color(0.230, 0.195, 0.160), "fog": Color(0.86, 0.68, 0.53), "fd": 1.25, "amb": 1.26, "sl": 0.1523},
	{"h": 19.2, "sun": Color(1.00, 0.46, 0.26), "se": 0.82, "moon": 0.22,
	 "top": Color(0.13, 0.18, 0.40), "hor": Color(0.90, 0.42, 0.28),
	 "gnd": Color(0.165, 0.130, 0.120), "fog": Color(0.60, 0.38, 0.35), "fd": 1.55, "amb": 1.16, "sl": 0.0677},
	{"h": 20.8, "sun": Color(0.30, 0.24, 0.34), "se": 0.06, "moon": 0.58,
	 "top": Color(0.050, 0.068, 0.145), "hor": Color(0.21, 0.17, 0.24),
	 "gnd": Color(0.040, 0.040, 0.052), "fog": Color(0.17, 0.165, 0.22), "fd": 1.80, "amb": 0.78, "mist": 1.6, "sl": 0.0091},
	{"h": 24.0, "sun": Color(0.10, 0.14, 0.26), "se": 0.0,  "moon": 0.78,
	 "top": Color(0.022, 0.034, 0.078), "hor": Color(0.060, 0.080, 0.140),
	 "gnd": Color(0.016, 0.019, 0.030), "fog": Color(0.050, 0.068, 0.120), "fd": 2.30, "amb": 0.62, "mist": 2.4, "sl": 0.0032},
]

var sun: DirectionalLight3D
var moon: DirectionalLight3D
var env: Environment
var sky_mat: ShaderMaterial
var water: WaterSystem
var hour := 9.0
var day_length_min := 24.0      # real minutes for a full cycle
var paused := false

# weather multipliers, applied on top of the time-of-day state
var fog_mul := 1.0
var light_mul := 1.0
var fog_tint := Color(1, 1, 1)
var base_fog_density := 0.00085
var fog_height_base := 16.0
var fog_height_dens := 0.016
var fog_clear_begin := 240.0    # metres of fully clear air in front of the camera
var fog_clear_end := 2400.0     # metres at which fog reaches full strength
## v0.17 aerial perspective: depth-fog end distance (m) at fd = 1
var haze_far := 4500.0
## Base volumetric density for the current quality tier. Perf owns the number;
## DayNight owns how it moves across the day and through the weather.
var vol_base := 0.0
## v0.17 physical sky. Mie haze multiplier (Weather raises it in mist and rain).
var turbidity := 1.25
var sky_exposure := 26.0
var art_mix := 0.0
var sky_sun_dir := Vector3(0, 1, 0)
var sky_zenith := Vector3(0.1, 0.2, 0.45)    # linear, what the sky shader draws straight up
var sky_horizon := Vector3(0.5, 0.6, 0.7)    # and along the horizon, 90 degrees from the sun
var _phys_zen := Vector3.ZERO
var _phys_hor := Vector3.ZERO
var _sky_h := -100.0
var _sky_turb := -1.0

var state := {}

func setup(s: DirectionalLight3D, m: DirectionalLight3D, e: Environment, sm: ShaderMaterial) -> void:
	sun = s; moon = m; env = e; sky_mat = sm
	apply(true)

func set_hour(h: float, snap := true) -> void:
	hour = fposmod(h, 24.0)
	if snap: apply(true)

func advance(delta: float) -> void:
	if paused: return
	hour = fposmod(hour + delta * (24.0 / maxf(day_length_min * 60.0, 1.0)), 24.0)

func _blend() -> Dictionary:
	var a: Dictionary = KEYS[0]
	var b: Dictionary = KEYS[KEYS.size() - 1]
	for i in KEYS.size() - 1:
		if hour >= float(KEYS[i]["h"]) and hour <= float(KEYS[i + 1]["h"]):
			a = KEYS[i]; b = KEYS[i + 1]; break
	var span: float = maxf(float(b["h"]) - float(a["h"]), 0.0001)
	var t: float = clampf((hour - float(a["h"])) / span, 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)      # smoothstep: no visible switching
	var out := {}
	var keys := a.keys()
	for k in b.keys():
		if not keys.has(k): keys.append(k)
	for k in keys:
		if k == "h": continue
		# optional keys (v0.15 "mist") default to 1 where a key frame omits them
		var va = a.get(k, 1.0)
		var vb = b.get(k, 1.0)
		if va is Color: out[k] = (va as Color).lerp(vb, t)
		else: out[k] = lerpf(float(va), float(vb), t)
	return out

## Sun elevation follows a real arc: below the horizon at night, highest at noon.
func _sun_basis() -> Basis:
	var day_t := (hour - 6.0) / 12.0                 # 0 at sunrise, 1 at sunset
	var elev := sin(day_t * PI) * deg_to_rad(72.0) - deg_to_rad(6.0)
	var azim := deg_to_rad(-110.0 + (hour / 24.0) * 300.0)
	return Basis.from_euler(Vector3(-elev - PI * 0.5 + PI * 0.5, azim, 0.0))

func apply(_snap := false) -> void:
	state = _blend()
	if sun != null:
		var day_t := (hour - 6.0) / 12.0
		var elev := sin(clampf(day_t, 0.0, 1.0) * PI) * 72.0 - 6.0
		var azim := -110.0 + (hour / 24.0) * 300.0
		sun.rotation = Vector3(deg_to_rad(-maxf(elev, -12.0)), deg_to_rad(azim), 0.0)
		sun.light_color = state["sun"]
		sun.light_energy = maxf(0.0, float(state["se"]) * light_mul)
		sun.visible = float(state["se"]) * light_mul > 0.005
		# long shadows at golden hour come free from the low sun angle
		sun.shadow_enabled = sun.visible
		# Shafts want a low sun. Raking light through the canopy at dawn and
		# dusk gets up to 3x the scattering a noon sun does.
		sun.light_volumetric_fog_energy = clampf(
			3.0 - clampf(elev, 0.0, 60.0) / 30.0, 1.0, 3.0)
	if moon != null:
		moon.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(40.0 + hour * 6.0), 0.0)
		moon.light_energy = float(state["moon"]) * light_mul
		moon.visible = moon.light_energy > 0.005
	if sky_mat != null:
		var se: float = float(state["se"])
		var nightf := clampf(1.0 - se * 2.4, 0.0, 1.0)
		# v0.17: the sky is an atmosphere now (shaders/sky.gdshader). The sun it
		# scatters follows the light down to a degree below the horizon and then
		# sinks slowly through twilight, so dusk is a long blue-and-orange hour
		# rather than a switch. The exposure divides the brightness this hour has
		# always had by what the model produces, which is what keeps the ambient
		# light (it comes from the sky) where every scene was balanced.
		var e_sky := sky_elevation()
		var azr := deg_to_rad(-110.0 + (hour / 24.0) * 300.0)
		var er := deg_to_rad(e_sky)
		sky_sun_dir = Vector3(sin(azr) * cos(er), sin(er), cos(azr) * cos(er))
		art_mix = maxf(0.80 * _ss(2.0, -4.0, e_sky), nightf)
		sky_exposure = clampf(float(state.get("sl", 0.1)) / Atmosphere.hemisphere_lum(e_sky), 1.0, 2500.0)
		if absf(hour - _sky_h) > 0.002 or absf(turbidity - _sky_turb) > 0.02:
			_sky_h = hour
			_sky_turb = turbidity
			_phys_zen = Atmosphere.inscatter(Vector3.UP, sky_sun_dir, turbidity, 8)
			var side := Vector3(-sky_sun_dir.z, 0.0, sky_sun_dir.x)
			if side.length() < 0.01: side = Vector3.RIGHT
			_phys_hor = Atmosphere.inscatter((side.normalized() + Vector3(0, 0.08, 0)).normalized(),
				sky_sun_dir, turbidity, 8)
		var top_l := (state["top"] as Color).srgb_to_linear()
		var hor_l := (state["hor"] as Color).srgb_to_linear()
		sky_zenith = Vector3(top_l.r, top_l.g, top_l.b).lerp(_phys_zen * sky_exposure, 1.0 - art_mix)
		sky_horizon = Vector3(hor_l.r, hor_l.g, hor_l.b).lerp(_phys_hor * sky_exposure, 1.0 - art_mix)
		sky_mat.set_shader_parameter("top_color", state["top"])
		sky_mat.set_shader_parameter("horizon_color", state["hor"])
		sky_mat.set_shader_parameter("ground_color", state["gnd"])
		sky_mat.set_shader_parameter("sun_color", state["sun"])
		sky_mat.set_shader_parameter("sun_energy", clampf(se, 0.0, 2.0))
		sky_mat.set_shader_parameter("night", nightf)
		sky_mat.set_shader_parameter("sky_sun_dir", sky_sun_dir)
		RenderingServer.global_shader_parameter_set("cloud_sun", sky_sun_dir)
		sky_mat.set_shader_parameter("sky_exposure", sky_exposure)
		sky_mat.set_shader_parameter("art_mix", art_mix)
		sky_mat.set_shader_parameter("turbidity", turbidity)
		sky_mat.set_shader_parameter("amb_top", sky_zenith)
		sky_mat.set_shader_parameter("amb_hor", sky_horizon)
		sky_mat.set_shader_parameter("moon_energy", float(state["moon"]))
		if moon != null:
			sky_mat.set_shader_parameter("moon_dir", Basis.from_euler(moon.rotation).z)
	if water != null:
		# Water reflects the sky it is under. A hardcoded blue meant every
		# river stayed the same colour at sunset as at noon.
		# v0.17: from the physical sky, 60/40 with the old keyframes
		var wh := _to_srgb(sky_horizon)
		var wz := _to_srgb(sky_zenith)
		water.set_sky_color((state["hor"] as Color).lerp(wh, 0.6), (state["top"] as Color).lerp(wz, 0.6))
	if env != null:
		env.ambient_light_energy = float(state["amb"]) * light_mul
		env.fog_light_color = (state["fog"] as Color) * fog_tint
		# Depth fog, not exponential+height fog. The old height fog had a fixed
		# 14 m ceiling at density 0.41; the river valley floor sits at ~12 m, so
		# every low-lying view was 60-100% fog and the whole world read as a
		# flat grey sheet. Depth fog keeps the near field clear and only hazes
		# the distance, which is what "atmospheric" actually looks like.
		env.fog_mode = Environment.FOG_MODE_DEPTH
		var fd: float = float(state["fd"]) * pow(fog_mul, 1.55) / 1.35
		fd = maxf(fd, 0.25)
		# v0.17: in depth mode fog_density is the fog's MAXIMUM amount, and it
		# was never set - Godot's default 0.01 - so since v0.14 this depth fog
		# topped out at 1% and the only haze anywhere was the volumetric slab
		# (High/Ultra), the same ~35% at 150 m as at 4 km. Now it is real
		# aerial perspective: an S-curve from ~0 at the camera, a few % across
		# the map, 20-60% on the mountain ring depending on the hour, so each
		# ridge is paler than the one in front of it; fog, mist and rain pull
		# the far end in and raise the ceiling until the distance is gone.
		env.fog_depth_begin = 0.0
		env.fog_depth_end = haze_far / fd
		env.fog_depth_curve = 0.75
		var thick := clampf((fog_mul - 1.0) / 2.0, 0.0, 1.0)
		env.fog_density = 0.78 + 0.20 * thick
		# the sky makes its own haze now; only real fog should veil it
		env.fog_sky_affect = 0.15 + 0.5 * clampf((fog_mul - 1.0) / 3.0, 0.0, 1.0)
		env.fog_sun_scatter = clampf(float(state["se"]) * 0.22, 0.0, 0.5)
		# A thin mist still pools in the valleys, but at 1/30th of the old
		# density and with the ceiling above the river so it reads as mist
		# rather than as a grey wall.
		env.fog_height = fog_height_base
		# v0.15: and at night it thickens into ground mist
		env.fog_height_density = clampf(fog_height_dens * fog_mul * float(state.get("mist", 1.0)), 0.0, 0.3)
		if vol_base > 0.0:
			env.volumetric_fog_enabled = true
			# thickest at dawn, dusk and in bad weather; thinnest at midday
			# v0.17: thinner - it is for the shafts near the camera now; the
			# depth fog above does the distance
			env.volumetric_fog_density = clampf(
				vol_base * 0.6 * clampf(fd * 0.85, 0.40, 2.4), 0.0, 0.12)
			env.volumetric_fog_albedo = ((state["fog"] as Color) * fog_tint).lerp(
				Color(1, 1, 1), 0.35)
		else:
			env.volumetric_fog_enabled = false

## Elevation (degrees) of the sun the sky scatters. Equal to the light's while
## it is above -1 degree; after that it sinks slowly to -4.5 by full night (and
## rises the same way before dawn), because the light's own path parks at -6
## through the whole night and a physical sky at -6 is already black.
func sky_elevation() -> float:
	var day_t := (hour - 6.0) / 12.0
	var el := sin(clampf(day_t, 0.0, 1.0) * PI) * 72.0 - 6.0
	if el >= -1.0 and day_t >= 0.0 and day_t <= 1.0:
		return el
	if hour >= 12.0:
		return -1.0 - 3.5 * _ss(17.735, 20.8, hour)
	return -1.0 - 3.5 * (1.0 - _ss(4.6, 6.265, hour))

static func _ss(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

static func _to_srgb(v: Vector3) -> Color:
	var c := Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))
	return c.linear_to_srgb()

func is_night() -> bool:
	return hour < 5.6 or hour > 19.6

func light_level() -> float:
	return clampf(float(state.get("se", 1.0)) + float(state.get("moon", 0.0)), 0.0, 2.0)

## v0.16 0..1, how much there is to see by: the sun, plus a little moonlight.
## Soldiers' sight range scales with it (a dark night roughly halves it).
func daylight() -> float:
	return clampf(float(state.get("se", 1.0)) + 0.3 * float(state.get("moon", 0.0)), 0.0, 1.0)
