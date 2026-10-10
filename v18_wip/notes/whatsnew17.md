
---

# v0.17 — A real sky, clouds that cast shadows, and mountains that look like mountains

## Sky
- **Physical atmosphere.** The sky is computed from how sunlight scatters in
  air: Rayleigh (the blue), Mie (the white glare around the sun and the pale
  horizon) and ozone absorption (the deep blue of twilight), with a cheap
  multiple-scattering term. The same model runs on the CPU and lights the world,
  so the ambient light, the water and the fog colour match the sky you see. The
  blue zenith, white horizon, orange low sun and the blue hour come from the
  physics instead of hand-picked gradients. The old gradients are only blended
  in for deep twilight and night, where single scattering goes black.
- Sky brightness per hour is matched to the old keyframes, so the exposure of the
  world does not jump.
- Haze follows the weather: mist, rain and fog make the sky whiter and milkier.
- **Sun disc** with limb darkening, reddened near the horizon, hidden behind thick
  cloud.
- **Night:** stars, a moon with phases and dark maria, a halo round the moon and a
  faint Milky Way.
- **Overcast** skies are darkest at the horizon, as real ones are. Before, a bright
  clear-sky band showed under every storm.

## Clouds
- A cumulus deck at 1.6 km with light marched towards the sun: bright tops, grey
  bases, silver linings on edges in front of the sun, cauliflower billows. Past
  about 60% cover it closes into a stratus sheet. Cirrus streaks at 8 km.
- Clouds are fixed to the world and drift with the weather. If you ride under
  one, it passes overhead.
- **Cloud shadows.** The same cloud field casts moving shadows on the terrain,
  grass, trees and the distant mountains, from 110 m out (High and Ultra).
- Distant clouds lose detail instead of breaking up into stripes.
- Fix: the clouds no longer jump when the weather changes. Their drift was time ×
  wind speed, so every change in speed moved the whole sky at once. It is now
  added up frame by frame.

## Distance: haze and mountains
- **Bug fix: the distance fog never worked.** In Godot's depth-fog mode
  `fog_density` is the *maximum* amount of fog. Since v0.14 it had been left at
  Godot's default of 0.01, so the fog peaked at 1%. The only haze was the
  volumetric fog (High and Ultra), which adds the same ~35% to everything beyond
  about 130 m: a hill 200 m away was as hazy as a peak 4 km away, and on Low and
  Medium there was no haze at all. The depth fog is now real aerial perspective:
  almost clear across the map, then 20–60% on the far ranges depending on the
  hour and the weather, coloured mostly by the sky behind it. Each ridge is
  paler than the one in front, and the far ones fade into the real horizon. Fog,
  mist and rain pull it closer. The volumetric fog is 40% thinner and now only
  does the light shafts near the camera.
- **The mountain ring was rebuilt.** It has about 4× the resolution (1,024
  bearings × 60 rings instead of 384 × 21) and reaches 4.7 km beyond the map edge
  instead of 3.8 km. Its shape now comes from ridged noise with a domain warp:
  sharp crests, smoother valley floors and crags on the summits. Forested
  foothills sit near the map and a high rocky range further out. Before, the
  peaks were smooth cones.
- **Its surface is painted from a detail relief:** gullies and spurs bend the
  lighting, at a level of detail matched to the pixel so nothing shimmers.
  Conifer and broadleaf forest grow in patches, with rock on steep faces and
  above the tree line, faint strata, scree in the gullies, snow on the highest
  summits, darker hollows and cloud shadows.
- The camera's draw distance went from 6.5 km to 8 km to fit the larger ring.

## Film look
- New post layer: a vignette, fine film grain (24 fps, like film) and a gentle
  grade with cool shadows and warm highlights. Low: off. Medium: vignette and
  grade. High: adds grain. Ultra: adds a slight depth of field on the far
  distance. **Film grain / vignette** in the pause menu turns it off.
- **Ultra** quality can now be chosen in the pause menu.
