import os
os.chdir('/data/ronins_edge/game')
def sub(p, old, new):
    s=open(p).read()
    if new in s: return
    assert old in s, (p, old[:70])
    s=s.replace(old,new,1)
    open(p,'w').write(s)
p='shaders/sky.gdshader'
sub(p,'''		// under a closing deck the clear sky that still shows is grey and dim
		float oc_sky = smoothstep(0.55, 0.95, cloud_cover);
		col = mix(col, vec3(dot(col, vec3(0.2126, 0.7152, 0.0722))) * mix(0.62, 0.38, cloud_storm), oc_sky * 0.9);
''','''		// Under a closing deck the air is lit by the grey light coming through
		// the cloud, not by the sun, so the sunlit clear-sky horizon glow must
		// go: an overcast sky is darkest at the horizon (CIE overcast, ~1/3 of
		// the zenith) and its haze is the colour of the cloud base. Greying the
		// clear sky kept its bright band under every storm.
		float oc_sky = smoothstep(0.55, 0.95, cloud_cover);
		float lc = dot(mix(amb_hor, amb_top, 0.55), vec3(0.2126, 0.7152, 0.0722)) * 0.55 * (1.0 - 0.45 * cloud_storm);
		vec3 over = vec3(lc) * mix(0.62, 1.0, clamp(d.y * 2.5, 0.0, 1.0));
		col = mix(col, over, oc_sky * 0.9);
''')
sub(p,'''					col += tv * limb * edge * vis * 10.0 * clamp(sky_exposure / 26.0, 1.0, 5.0) * (1.0 - art_mix);''','''					// a deck thick enough to hide the sky hides the disc completely
					float dv = vis * vis * (1.0 - cloud_storm);
					col += tv * limb * edge * dv * 10.0 * clamp(sky_exposure / 26.0, 1.0, 5.0) * (1.0 - art_mix);''')
p='world/Terrain.gd'
sub(p,'''	mass.frequency = 1.0 / 3400.0''','''	mass.frequency = 1.0 / 5200.0''')
sub(p,'''	ridge.fractal_octaves = 6
	ridge.fractal_lacunarity = 2.05
	ridge.fractal_weighted_strength = 0.55
	ridge.frequency = 1.0 / 1500.0
	ridge.domain_warp_enabled = true
	ridge.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	ridge.domain_warp_amplitude = 260.0
	ridge.domain_warp_frequency = 1.0 / 1900.0''','''	ridge.fractal_octaves = 5
	ridge.fractal_lacunarity = 2.1
	ridge.fractal_gain = 0.45
	ridge.fractal_weighted_strength = 0.6
	ridge.frequency = 1.0 / 2600.0
	ridge.domain_warp_enabled = true
	ridge.domain_warp_type = FastNoiseLite.DOMAIN_WARP_SIMPLEX
	ridge.domain_warp_amplitude = 380.0
	ridge.domain_warp_frequency = 1.0 / 3200.0''')
sub(p,'''	hills.frequency = 1.0 / 520.0
	var crag''','''	hills.frequency = 1.0 / 700.0
	var crag''')
sub(p,'''	crag.frequency = 1.0 / 230.0''','''	crag.frequency = 1.0 / 320.0''')
sub(p,'''				var foot := 30.0 + 170.0 * hl + 80.0 * rr * rr
				var hi := 150.0 + (600.0 + 800.0 * ms) * pow(rr, 1.6) + 90.0 * hl
				var far := smoothstep(300.0, 2500.0, d)
				var mh := lerpf(foot, hi, far)
				mh += (crag.get_noise_2d(x, z) * 0.5 + 0.5) * 75.0 * far * smoothstep(0.30, 0.75, rr)''','''				var foot := 25.0 + 150.0 * hl + 60.0 * rr * rr
				var hi := 120.0 + (450.0 + 650.0 * ms) * pow(rr, 1.35) + 70.0 * hl
				var far := smoothstep(500.0, 3200.0, d)
				var mh := lerpf(foot, hi, far)
				mh += (crag.get_noise_2d(x, z) * 0.5 + 0.5) * 40.0 * far * smoothstep(0.45, 0.85, rr)''')
sub(p,'''	# the crests. Layered ridgelines''','''	# the crests (slopes kept to what real ranges have - the first try
	# at 1/1500 m made needle karst). Layered ridgelines''')
p='shaders/distant_land.gdshader'
sub(p,'''uniform vec3 col_meadow : source_color = vec3(0.29, 0.38, 0.16);
uniform vec3 col_conifer : source_color = vec3(0.085, 0.140, 0.085);
uniform vec3 col_broadleaf : source_color = vec3(0.15, 0.22, 0.10);''','''// Forest seen from kilometres away is far darker than its leaves: the canopy
// shades itself. These are canopy albedos, not leaf colours.
uniform vec3 col_meadow : source_color = vec3(0.24, 0.30, 0.14);
uniform vec3 col_conifer : source_color = vec3(0.050, 0.082, 0.056);
uniform vec3 col_broadleaf : source_color = vec3(0.090, 0.130, 0.062);''')
sub(p,'''uniform float tree_line = 1080.0;
uniform float snow_line = 980.0;''','''uniform float tree_line = 900.0;
uniform float snow_line = 1010.0;''')
sub('world/DayNight.gd','''var haze_far := 6000.0''','''var haze_far := 4500.0''')
print('post_wip3 ok')
