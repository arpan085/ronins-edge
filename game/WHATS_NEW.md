# Ronin's Edge — cinematic / open-world pass

Everything in this document was verified by rendering the real game
(`main/Main.tscn`) through the harnesses in `tests/` and looking at the output.
The test machine has no GPU — Godot runs on llvmpipe, a software rasteriser, at
0.5–9 seconds per frame — so **no frame-rate number in this project is a real
frame-rate number** and none is claimed. What the measurements below report is
what the renderer itself counts: draw calls, primitives, and instance/object
counts, plus the *relative* cost between quality tiers on identical scenes.

Characters, rigs and animations were deliberately left alone.

---

## 1. The bug that was hiding the entire world

`Terrain._chunk_mesh()` emitted its triangles as `[[a, c2, b], [b, c2, d]]`.
That gives a **+Y** cross product for `(v1-v0) x (v2-v0)`. Godot's front face is
the side that cross product points *away* from, so an up-facing surface needs
**-Y**. Every terrain chunk in the game was back-face culled.

What was actually on screen was the inside of the fogged sky dome. That is why
the "ground" was a flat untextured sheet whose colour tracked the time-of-day fog
colour exactly, and why nothing about the terrain shader ever seemed to matter.

Proof, before the fix: painting the terrain unshaded green changed nothing under
`cull_back`; switching the same material to `cull_disabled` filled the whole
lower half of the frame. That probe is kept as `tests/Probe.tscn`.

Fixed to `[[a, b, c2], [b, d, c2]]`. `WaterSystem._quad` had the same inverted
winding and is also fixed — cosmetic only there, because `water.gdshader` is
`cull_disabled` and was drawing anyway.

## 2. Fog

Height fog was configured with a fixed 14 m ceiling at density 0.41. The river
valley floor sits at about 12 m, so every low-lying view was 60–100% fog: the
world was grey regardless of weather or time of day.

Replaced with depth fog in `DayNight.apply()`:

* `fog_mode = FOG_MODE_DEPTH`, 240 m of clear air, full fog at 2400 m, curve 1.55
* weather compresses that range as `fog_mul^1.55 / 1.35`, so storms close in
* valley mist survives as a thin layer: `fog_height = 16`, density 0.016 —
  about a thirtieth of the old value, and with its ceiling above the river
* `Perf.apply_quality()` no longer writes `fog_density`; it was overwriting the
  time-of-day curve every time quality changed

## 3. Terrain surface

`shaders/terrain.gdshader`:

* **Tints are base colours, not multipliers.** The old code multiplied the
  sampled texel by the tint, so a 0.30 texel times a 0.34 tint produced a 0.10
  albedo — darker than wet asphalt. The texture now modulates luminance around
  the tint (`detail_contrast = 0.62`).
* Two-octave sampling (a second tap at 0.37x) to hide the ~1.6 m tile repeat.
* A high-frequency detail normal in the first 22 m, which is what stops the
  ground directly under the camera from reading as paper.
* Moisture remapped `clamp(bi.g * 1.90 - 0.10)`. The biome moisture channel has
  a median of 0.502, and the old `* 1.25` left most ground on the dry end of the
  ramp, so fields read as straw.
* Splat weights biased towards grass — `pow(sp.r, 0.70) * 1.45`, rock `* 0.72` —
  because the generator writes a thin grass layer nearly everywhere and taking
  it linearly washed the world brown.
* Grass/dry/dirt/rock tints re-authored greener and less saturated.

## 4. Sky

New `shaders/sky.gdshader` (`shader_type sky`) replaces
`ProceduralSkyMaterial`, which can only draw a colour ramp — which is why every
shot had an empty sky.

* a low cumulus deck with a domain-warped FBM, thresholded by a `cover` uniform
  (`mix(0.66, 0.26, cover)`) so low cover keeps isolated puffs and high cover
  closes the deck
* a high cirrus deck on a faster drift
* density-gradient shading: bright tops, dark bases, and a silver lining where
  the sun sits behind a cloud edge
* sun disc and glow, a storm slate tint, and twinkling stars at night
* both decks project onto a flat plane with `y` clamped at 0.055 and fade out
  below 0.20 up, or the projection smears at the horizon
* `octaves` is a uniform (3 on Low, 6 on Ultra)

Driven from `DayNight.apply()` (colours, sun energy, night factor, cloud tint
tracking the sun) and `Weather._apply()` (cover, storm, drift speed).
Verified standalone with `tests/SkyOnly.tscn`: clear, broken, dusk, storm and
starfield all render as intended.

## 5. Grass

`world/Foliage.gd` now streams **four** rings instead of three:

| ring | cell | range | LOD | blades / 24 m² |
| --- | --- | --- | --- | --- |
| 0 | 12 m | 0–34 m | 0 | 1520 |
| 1 | 24 m | 30–96 m | 0 | 780 |
| 2 | 48 m | 92–215 m | 1 | 265 |
| 3 | 96 m | 210–380 m | 2 | 78 |

* density **floor** per surface read from `terrain.surface_at()` — grass 0.62,
  mud 0.34, dirt ×0.5 (min 0.10), rock ×0.30. The generator's density map drops
  to zero over large stretches, which left bald patches with no transition.
* per-chunk cap raised 2600 → 5400, build budget 6 → 10 chunks/frame
* wider biome mixes for village, farmland and rocky, which were single-category

`shaders/grass.gdshader`:

* camera-proximity duck: blades shrink from 3.2 m to 1.0 m in front of the
  camera instead of standing at eye level and blocking the view
* roots take the ground colour (`ground_blend = 0.55`) so clumps sit in the
  terrain instead of floating on it

## 6. Trees

`MeshLib._blob()` — the canopy primitive — was a bare 8-face octahedron with
flat per-face normals, and those normals point *inward*, so canopies were both
faceted and lit from the wrong side. It now:

* subdivides the octahedron 2 / 1 / 0 times by LOD
* projects onto an ellipsoid with a stable per-direction lump, so shared
  vertices agree and the surface is smooth
* flattens the underside into a dome rather than a sphere
* uses smooth outward normals and bakes vertical AO into the vertex colour

`world/TreeSystem.gd` gained per-tier **placement** density (previously only the
draw range changed), using a stable hash of world position so the same trunks
survive every rebuild and the forest does not reshuffle when quality changes.
`set_quality()` rebuilds from a cached list.

## 7. Camera

`player/PlayerCamera.gd` rewritten:

* split follow damping — horizontal 13, vertical 6.5 — so slopes and stairs stop
  bobbing the frame
* velocity look-ahead up to 1.35 m, cut to 35% while locked on
* speed-driven FOV, arm length and bank, with a fast attack and a slow release
  (`_toward()`), so accelerating feels different from decelerating
* critically damped landing dip (`land_dip()`) and idle breathing
* directional `impulse()` separate from undirected `shake()`
* far plane 900 m → 2600 m; 900 m was clipping the mountains and the terrain's
  own far LOD ring

## 8. Movement

`player/Player.gd`:

* sprint spools up over 0.9 s and decays in 0.45 s instead of snapping
* turn rate scales with speed: 13 rad/s standing, 5.2 rad/s at full sprint
* surface speed costs — mud 0.68, shallow water 0.52, rock 0.94
* slope penalty 0.42 uphill, 0.16 refund downhill, sampled 1.6 m ahead
* heavy-landing recovery caps speed at 45% briefly
* surface-aware footstep pitch and level, with dust/clipping puffs above 3 m/s

## 9. Impact

`fx/HitFx.gd` now has one tiered `impact()` call covering sparks, shake,
directional camera push, an expanding ring flash and hitstop, with five explicit
tiers by damage (graze / light / solid / heavy / finisher) instead of every call
site guessing. `EnemyBase` freezes at the top of `_physics_process` for the
returned hitstop duration. `surface_puff()` adds per-surface debris colours.

## 10. Ambient life

New `world/Ambience.gd`: drifting leaves under canopy, pollen over open ground
in daylight, dust on arid ground and in wind, fireflies at night near water or
under trees in calm weather, canopy drips while it rains, and circling birds
(0 / 3 / 6 / 9 by tier). Everything is condition-gated on biome, weather and
time of day, follows the player, and scales with the tier's particle budget.

## 11. Quality tiers

Four tiers plus autodetection, replacing three fixed presets:

| | Low | Medium | High | Ultra |
| --- | --- | --- | --- | --- |
| Render scale | 0.68 | 0.85 | 1.00 | 1.00 |
| Shadow map | 1024 | 2048 | 4096 | 8192 |
| Shadow distance | 70 m | 120 m | 200 m | 300 m |
| Foliage density | 0.30x | 0.58x | 1.00x | 1.45x |
| Tree placement | 0.45x | 0.72x | 1.00x | 1.00x |
| Tree draw range | 0.55x | 0.80x | 1.00x | 1.25x |
| Sky octaves | 3 | 4 | 5 | 6 |
| SSAO | off | off | on | on |

`Perf.autodetect()` picks the starting tier from `OS.get_name()`, the reported
video adapter and the CPU count: Android/iOS and software renderers start on
Low, integrated Intel on Medium, everything else on High. Adaptive quality then
samples frame time and steps render scale down to 0.62 or back up — three
samples over budget before it sheds, six under before it restores — so it never
oscillates mid-fight.

### What the tiers actually cost

Measured with `tests/PerfTiers.tscn` on the test box (adapter
`llvmpipe (LLVM 15.0.7, 256 bits)`, 2 CPUs), same vantage, same time of day,
same weather. Frame times are omitted on purpose: a software rasteriser's
milliseconds say nothing about a real GPU.

| grassland vantage | Low | Medium | High | Ultra |
| --- | --- | --- | --- | --- |
| grass instances | 10,530 | 41,847 | 128,278 | 284,962 |
| trees placed (world) | 6,057 | 9,769 | 13,514 | 13,514 |
| draw calls | 817 | 811 | 918 | 1,040 |
| primitives | 1.01 M | 1.59 M | 2.38 M | 3.12 M |
| render scale | 0.68 | 0.85 | 1.00 | 1.00 |
| shadow distance | 70 m | 120 m | 200 m | 300 m |

The tree counts are 0.448x / 0.723x / 1.0x of the full set, which matches the
0.45 / 0.72 / 1.00 placement multipliers. Ultra places the full set and spends
its budget on draw range and shadows instead.

## 12. Other fixes

* `World.warp_to()` now spirals outward through `_free_spot()` (rings at 3, 6,
  10, 15, 22 m, eight directions each) until a 0.45 m capsule fits. Landmark
  buildings sit exactly on their zone markers, so warping to the castle
  checkpoint dropped the player inside the keep.
* `ui/HUD.gd` minimap actually draws. It assumed a 481-sample heightmap over a
  480 m world; the real terrain is 769 samples over 1536 m, so it read the
  height array on the wrong stride — and it tested `Terrain.loaded`, which is
  only set in `_ready()` and never runs on a detached node, so the texture was
  never built at all. Now baked at 256² with relief shading and river overlay.
* Tonemap white 6.0 → 3.0 (6.0 crushed the midtones), saturation 1.04 → 1.12,
  contrast 1.03 → 1.06, glow 0.35 → 0.28, SSAO radius/intensity/power tuned.
* Dawn, golden hour and dusk ambient light raised; moonlight raised. The ground
  was unreadably dark either side of the day.
* `Audio.SFX_FALLBACK` maps the new surface footstep names onto the generic clip
  so they are not silent until real recordings exist.
* Respawn no longer drops the player under water. Zone markers are authored on
  the map centre and the lake marker sits at y=0 with the water line at 6 m, so
  dying anywhere after touching that checkpoint put the player inside the lake
  with the camera in the water volume. Checkpoints are now walked to dry land
  when registered, the initial spawn is guarded the same way, and `respawn()`
  goes through `warp_to()`.

## 13. Verification harnesses

| harness | what it does |
| --- | --- |
| `tests/EnvShots.tscn` | boots Main.tscn, walks 10 zone/time/weather scenarios, screenshots each, writes `metrics_<tag>.csv`. `only=` filters scenarios. |
| `tests/PerfTiers.tscn` | walks quality tiers at four vantages, writes `perf_tiers.csv`. `tiers=`, `spots=`, `settle=`. |
| `tests/SkyOnly.tscn` | sky preview with no world load, for fast shader iteration |
| `tests/Probe.tscn` | the culling probe used to find the terrain bug |
| `tests/Playtest.tscn` | scripted pilot through the real game: explore, engage, fight, recover |

---

# v0.7 — Collision & physicality pass

Four genuine bugs, all found by measuring rather than by looking.

## 1. Terrain collision was a metre out of line (critical)

`Terrain._build_collision()` centred the `HeightMapShape3D` at
`size/2 - cell/2` = **767 m**. A heightmap of `grid` samples at `cell` spacing
spans `(grid-1)*cell`, so the correct centre is `(grid-1)*cell/2` = **768 m**.
The whole collision surface was therefore shifted one metre diagonally against
the terrain you can see. On flat ground nobody notices; on a slope the error is
`slope x 1 m`, so the floor you stand on sat **up to 1.5 m below the hillside**
and the camera showed half the body buried in the mountain.

Measured with 900 downward rays against `sample_height()`:

| | mean error | worst | straight-line profile (24 m) |
|---|---|---|---|
| before | -0.038 m | **-1.496 m** | -0.48 -> -0.90 m, never zero |
| after | **+0.001 m** | +0.146 m | +0.00 m at every sample |

The +0.15 m residual is the difference between bilinear height sampling and the
shape's triangulation. It is inherent and harmless.

## 2. Nothing in the world had collision

A census of the running game found **2 static bodies in the entire 1.5 km
world**: the terrain, and one hand-placed box on the castle keep. Props and
trees are drawn with `MultiMesh`, which carries no collision, so every house,
wall, torii, watchtower, boulder and tree trunk was walk-through.

New `world/SolidBodies.gd` fixes this with two strategies, because the counts
differ by two orders of magnitude:

* **Structures** (houses, walls, fences, stalls, towers, gates, bridges, wells,
  lanterns, shrine, keep) get permanent shapes -- **146** of them. Sizes are
  taken from the real GLB bounds, not guessed. Torii and the castle gate are
  split into flanks so you can still walk through the opening; bridges get a
  walkable deck plus rails.
* **Boulders and trees** stream. **15,151** items live in a 48 m spatial hash;
  a pool of 240 shapes is recycled onto whatever is within 46 m of the player,
  refreshed every 6 m of movement. Collision never scales with the quality
  preset -- walking through a tree is a bug, not a graphics setting.

All shapes hang off two `StaticBody3D`s. Godot's broadphase indexes per shape,
so this is cheaper than 15,000 bodies and keeps the scene tree small.

Verified in the running game: **12/12** sampled trees and **12/12** sampled
boulders block a shape query after streaming; houses, walls, fences, stalls,
towers, lanterns, shrine and keep all block at 8/8 of sampled instances.

A 12-beat scripted playtest through the real `Main.tscn` now reports
**max sink 0.000 m and 0 penetrating frames out of 2,201 grounded samples**.
The player also picked up `floor_snap_length = 0.5`, `floor_block_on_wall` and
`floor_constant_speed`, so the capsule stops leaving the ground on convex
edges; enemies got the same treatment.

## 3. Rivers were floating tiles, and used the wrong mask channel

Two bugs stacked on top of each other in `WaterSystem._build_rivers()`.

**Geometry.** Each channel cell was drawn as a *square* at a single
*centre-sampled* height, and seven of every eight "stream" cells were punched
out to save fill. The result was detached pale sheets hovering over hillsides
all over the map. Confirmed by `tests/Isolate.tscn`, which re-renders one spot
with each subsystem hidden: hiding the water node made them vanish.

Now one quad per cell, exactly covering the cell, with **all four corners
sampled on the terrain**, so neighbouring cells share corner heights and the
channel is one continuous surface that follows the ground.

**Mask channels.** The river mask's two channels were read the wrong way round.
Measured on the real 769x769 image, both are binary: **R covers 10.1% of the
map, A covers 2.4%**. R is the broad valley-bottom/damp mask; A is the carved
channel. The code treated R as the river and A as a minor stream, so a water
surface was being laid over a tenth of the world -- and once the geometry was
made continuous, that showed up as a flood. Now A always gets a surface, and R
only where the ground is within 1.2 m of the water table; everywhere else the
damp is left to the terrain shader's moisture term.

Channel cells are also sampled at 2 m instead of 4 m, because a quad only
conforms to the ground at its corners: on a 1:3 slope a 4 m cell could sit
0.66 m above the terrain in the middle, which is enough to hover. Surface rise
above the bed dropped from 0.40 m to 0.14 m, and the reported channel depth
went from 0.65 to 1.8 -- at 0.65 the shader's shoreline foam dominated and
rivers rendered as white ribbons rather than water. The lake mesh got the same conforming
treatment: 4 m blocks instead of 8 m, and a block is only drawn once 3 of its
4 corners are actually under water, instead of 1. Total water surface is now
about 6% of the map instead of ~20%.

Ambient leaf, pollen, dust, firefly and drip particles also picked up a
32x32 radial alpha mote instead of being untextured unshaded quads, which is
why they showed up in world shots as flat coloured rectangles.

## 4. Wildlife were untextured cubes in a corner

`_build_wildlife()` made each animal a single `BoxMesh` floating 0.5 m above
the ground, and seeded all six inside a 400 m square -- left over from when
the map was 480 m across. On the 1,536 m map they clustered as brown cubes in
one corner.

New `world/Wildlife.gd`: deer, foxes and cranes built from primitives with
legs, barrel, neck, head and ears/bill; ground-snapped every frame; oriented
to travel direction with a gait bob and a slope lean; they refuse water and
cliffs, bolt when the player gets close, and are re-seeded around the player
when they wander past 240 m. Count scales 3/5/8/11 by quality tier.

## 5. Locomotion secondary motion

The animation complaint turned out not to be a code bug. Measuring per-bone
rotation across one stride in the authored clips:

| clip | thigh | upperarm | chest | spine | head |
|---|---|---|---|---|---|
| `Walk_F` | 40 deg | 30 deg | **2 deg** | **2 deg** | **2 deg** |
| `Jog_F` | 58 deg | 56 deg | 5 deg | 4 deg | 3 deg |
| `Sprint_F` | 60 deg | 84 deg | 8 deg | 7 deg | 5 deg |

The legs and arms are fine; the torso barely participates and the head is
welded to the chest. That rigidity is what reads as cheap.

New `anim/LocoPolish.gd`, a `SkeletonModifier3D` that adds the missing counter
motion on top of whatever the blend tree produced: pelvis yaw and roll with
the stride, spine and chest counter-rotation against the arm swing, a shoulder
line that leans into turns, head stabilisation, a vertical bob at twice stride
frequency, forward lean from speed and acceleration, bank from turn rate, and
extra arm swing at speed. It ramps to 1.3x at full sprint and fades to nothing
at idle, where the idle clips carry their own sway.

Stride phase is read back **from the thigh bones**, not integrated from a
clock, so it stays locked to the clips through every blend, time-scale change
and state transition. Nothing can drift out of sync. It runs through `AnimLOD`
at influence 1.0 / 0.85 / 0 / 0 by distance tier.

## What this pass did not fix

The character mesh is a low-poly blocked-out figure: slab torso, box limbs, no
hands, no face. Secondary motion makes it move better; it cannot make it look
like a modern AAA character. That needs new art, not new code.

## New harnesses

* `tests/CollAudit.tscn` — terrain alignment rays, static-body census, per-kind
  prop solidity, streamed-collision verification.
* `tests/CollShots.tscn` — walks the player into a building, a tree and a
  hillside and photographs where the body stops, printing the ground delta.
* `tests/Isolate.tscn` — re-renders one spot with each subsystem hidden in
  turn, which is how the water bug was pinned down.

---

# v0.8 — Character rebuild

The previous section admitted the real problem: secondary motion was polishing
a blockout. The figure was 3,596 triangles of bevelled boxes, 8-segment cones
and 12-segment spheres — a slab torso with no waist, one box per hand with a
box thumb, and a face made of three flat plates glued to a sphere. This pass
replaces the mesh.

## Smooth-surface primitives

New `v3/shape.py`. Everything structural is now built from cross-sections
rather than stacked solids:

| builder | what it makes | used for |
| --- | --- | --- |
| `ring(n, rx, ry, p, …)` | one closed superellipse section, with separate front and back depth | every loft below |
| `loft(sections, …)` | skins a list of sections; a one-point section becomes a pole | torso, limbs, skull, hakama, tabi |
| `lathe(profile, …)` | revolves a profile, optionally squashed on one axis | hats, collars, cuffs, hip ring |
| `tube(path, radii, …)` | sweeps a section down a curve with parallel-transport frames | fingers, cords, lacing, brow, horns |
| `_plate(rows, yaw)` | a flat, gently domed armour lame swung around the body axis | sode, kusazuri |

The superellipse exponent is what lets one primitive be a round limb at `p=2`,
a flat-fronted chest plate at `p=3.2` and a near-rectangular strap at `p=6`.

## Proportions

The rig was re-cut, not just re-skinned.

| | before | after |
| --- | --- | --- |
| height | 1.74 m | 1.785 m |
| head height | 0.26 m (6.7 heads) | 0.24 m (7.4 heads) |
| shoulder span | 0.33 m | 0.43 m |
| hand | one box + a box thumb | palm, opposed thumb, four two-knuckle fingers |
| triangles (Kaito) | 3,596 | 9,438 |

Clips are pure bone rotations plus a root translation, so every one of the 60
animations survived the re-cut untouched. Hips, legs and feet were left where
they were on purpose — the foot IK and stride tables are calibrated to them.

## Face bones that actually move

`jaw`, `eye.L/R` and `brow.L/R` were in the rig's `NO_AUTO` set, so the little
boxes representing them were weighted to `head` and **every facial animation
track was inert**. The eyes, brows and jaw are now separate meshes bound only
to their own bone, so those tracks drive geometry for the first time.

## Things that had to be fixed twice

Worth recording, because each one was only obvious once rendered:

* **Sode and kusazuri as swept tubes.** Whichever way the squash axes fell, the
  lames came out as black sausages. Replaced with `_plate`, which builds the
  lame flat in local space and then swings it around the body axis.
* **A hat the size of a parasol.** The first kasa was 0.71 m across and sat
  above the skull rather than on it, so it read as a UFO and put the whole
  face in shadow. Now 0.50 m, steeper, resting on the head, with chin cords.
* **The saya through the stomach.** The scabbard mesh was centred on its bone,
  so 0.4 m of lacquered rod projected out of the character's front. It now
  starts at the hip and sweeps back.
* **A melted mask.** Cheekbone and eyelid sweeps glued onto the skull left hard
  intersection seams that read as smears. The face is now a smooth skull plus a
  nose, a brow ridge, ears, a lash line and a mouth line.
* **A bowl cut.** The wig flared out from eyebrow height and swallowed the
  forehead. It now tucks inside the skull below the hairline and the crown
  sections sit back, so the pate reads shaved — the sakayaki a samurai wore.
* **A glowing ice cube.** The clan mon was a 45-degree box floating proud of the
  chest. It is now a flat inlaid disc.

## Collision

Player and enemy capsules were re-fitted to the taller figure: 0.34 m radius,
1.78 m tall, centred at 0.89 m. Regression on the real world is unchanged —
2,205 ground samples, **max sink 0.000 m, 0 penetrating frames**, 146 permanent
structure shapes and 15,151 streamed items.

## Harness

`tests/CharShots.tscn` renders a character sheet — front, three-quarter, side,
back, head, hands, torso and legs — on a neutral stage at 760×1000. Pass
`kind=ashigaru` to shoot a different character. It is the only reliable way to
judge this work; in-world screenshots are too small to show anything.

---

# v0.9 — Materials, lighting and the reference pass

Driven by a set of reference frames: a ronin walking through deep wind-blown
susuki grass at golden hour, a solid vermillion torii, one wide flat-topped
pine. Green grass rather than the reference's gold, but the same light, the
same motion, the same weight in the objects.

Everything below was found by rendering the real game and looking at it. The
useful ones are the bugs, because every one of them had been shipping.

## The seven bugs

**1. Rivers rendered as chains of white stepping stones.**
Not a shader bug. The drainage mask stores rivers as one-pixel lines and
plenty of them run diagonally, so one axis-aligned quad per lit pixel gives
squares that touch only at their corners. Measured: 14,172 lit pixels forming
5,009 separate fragments, 3,788 of them a single pixel. A plus-shaped dilation
makes every run 4-connected and about three cells wide.

**2. Most of those rivers should not have existed.**
The same mask is a capillary network — thousands of tributary stubs scattered
across dry meadows. The R channel turned out not to be a "damp valley" mask at
all (a comment in the code claimed it covered 10% of the map; it covers 0.95%,
and every R pixel is also a channel pixel). It marks the high-accumulation
stems, which makes it a free river-order signal. Components that do not reach
at least 8 trunk pixels are dropped: 896 components become **146 real river
systems**, with zero isolated specks.

**3. Water depth was baked in metres and read as quarters of a metre.**
`_quad` packs depth over a 0–4 m span into an 8-bit vertex colour; the shader
treated the packed value as metres. A 0.4 m bank therefore arrived as 0.1 and
sat at the very top of the foam ramp, so every shallow stream rendered as
**solid white foam**. Both sides now share a `DEPTH_RANGE` constant and the
shader works in metres throughout.

**4. The water shader composited the scene by hand.**
It sampled `SCREEN_TEXTURE`, mixed the water colour over it, and shipped the
result opaque. `DEPTH_TEXTURE` reads zero on this project's fallback renderer
and the screen texture is no better, so the result was a sheet of near-white.
Hardware alpha blending does the same compositing with no texture read at all
and gets sorting right for free. The screen sample is now only a refraction
nudge, taken only when it is usable.

**5. The water's ripple normal map was `metal_n.png`.**
A brushed-metal normal on a lake. There was no water normal map in the project.
`water_n.png` is now generated as tiling, wind-stretched capillary ripples and
sampled at three scales drifting at different speeds and angles.

**6. Every cloth surface in the game was lavender.**
`make_mat(..., ctex="cloth_n.png")` — a normal map wired into the colour slot.
Nobody had noticed because no large cloth surface faced the camera. Rebuilding
the farmhouse put three big shoji panels on the front of it and the bug became
the most visible thing in the village.

**7. Grass blades were zero-width above 62% of their height.**
The taper was `sin(PI * min(t*1.6, 1))`, which reaches zero at t = 0.625 and
stays there. The top third of every blade was a degenerate strip.

## Wind

Motion was two sine waves, which always reads as a regular corrugation because
that is what it is. It is now a **travelling gust field**: two octaves of value
noise sampled at `world_xz - wind_dir * TIME`, so gust cells drift downwind at
`gust_speed` while staying locked to the world. A gust front crosses the meadow
as a visible band and takes the trees on the far side a moment later — trees
sample the identical field at the identical scale.

The bend is now a **rotation about the blade's root** (Rodrigues, angle scaled
by the vertex bend weight), not a shear. Rotation preserves length, so a blade
in a 60° gust arcs over instead of stretching into a parallelogram. Wind
direction is taken into the instance's own frame with two dot products against
the normalised model-matrix columns, which inverts a yaw-plus-scale basis
exactly and costs nothing.

Even "clear" weather now carries a working breeze (0.45 → 0.62 wind, 0.20 →
0.38 gust). A still field is the one thing this landscape cannot be.

## Grass

| | before | after |
|---|---|---|
| blade shape | 2–4 straight segments, leaning | 3–6 segments on a **circular arc**, length-preserving |
| blade facing | every blade's width on +X — a clump was parallel cards | width perpendicular to each blade's own lean |
| seed heads | none | **susuki plumes**: three fine spikelets per head, `COLOR.b` flagged, tinted and whipped separately |
| colour | one green ±16% brightness | per-clump **hue** drift in R, G and B separately |
| grassland mix | medium/short | short/medium/**tall**, selected by a smooth 26 m spatial field so the field lays down in banks |
| far ring | 78 clumps per 24 m², to 380 m | 145, to 430 m |
| ground floor | dirt 0.10 | dirt 0.32, grass 0.78, mud 0.46 |

The clump scale was also capped for the tall kinds. A 1.35 random scale stacked
on a 1.35 density bonus and a 1.25 vertical stretch was producing 4 m blades
that swallowed the camera.

## Lighting

- **Golden hour was going black at ground level.** At 6.2 h and 19.2 h the sun
  grazes, so nearly all the light on the terrain is sky ambient — and the
  ambient energy and ground bounce were both set for a midday sky. Dawn, dusk
  and the hours either side now carry a warm bounce and ~25% more ambient.
- **Bloom.** 0.28 intensity at a 1.1 threshold barely registered, because
  almost nothing in the scene is above 1.1 except the sun disc. Now 0.58 at
  0.92 with a 2.4 HDR scale, screen blend.
- **Auto exposure** (`CameraAttributesPractical`, 40–320 sensitivity, 0.40
  speed). A real camera re-meters walking from a sunlit meadow into a cedar
  wood. The range is narrow so it corrects the scene rather than flattening
  the difference between noon and dusk.
- **Ambient occlusion** tightened from a 1.6 m radius at 1.5 intensity to
  0.95 m at 2.4. Contact darkening is what grounds a blade of grass in the
  soil it grows out of, and that lives in the first half metre.
- **Water reflects the live sky**, horizon colour and zenith colour picked
  along the reflected ray, pushed by DayNight. Rays reflected below the
  horizon take a bank colour, because with no screen-space reflections the
  honest answer for what is down there is land, not sky. Fresnel is capped at
  0.66 so the surface keeps some of its own colour at every angle.
- **Sub-surface scattering, clearcoat, anisotropy and rim** applied to rig
  materials at load (`anim/MatPolish.gd`) — everything glTF cannot carry.

## Objects

- **Torii.** The two things that make one readable at 200 m are the *sori* —
  the upward sweep of the top beam — and the inward lean of the pillars. It
  had neither: three straight boxes on two vertical posts, which reads as a
  rugby goal painted red. Now a 9-segment fanned kasagi with a real sori, a
  dark crowning beam over a vermillion shimaki, leaning tapered pillars, nuki
  through the posts with kusabi wedges, gakuzuka, stone footings and a hung
  plaque. 1,668 tris.
- **Farmhouse.** A minka is mostly roof. Now a 7-course hipped-gable roof with
  a concave eave flare oversailing the walls by 0.95 m, carried on visible
  corner posts with the wall plane set back in shadow behind them, plus sill
  and head rails, three shoji bays, an engawa veranda on its own short posts,
  ridge ornaments and exposed rafter tails. 1,936 tris.
- **Pine.** Was concentric half-round blobs on a straight pole — a Christmas
  tree. A Japanese black pine is a leaning, kinked trunk carrying a few broad
  wind-pruned plates that sit off to one side of it, so the read is
  horizontal. Now three overlapping lobe clusters per plate, widest at the
  top, each hung off a visible bough. The distant LODs were collapsing to a
  bare octahedron — a literal diamond — and now keep a mass.
- **Distant mountains.** Were 46 pairs of flat triangles in one flat grey.
  Now two ranges, a 7-segment jagged ridge line per peak, vertex-coloured
  from forested foot through rock to snow cap, with the far range hazed
  toward the sky.

## Measured

| shot | draws | primitives | grass instances |
|---|---|---|---|
| windfield (17.4 h) | 948 | 4,113,552 | 188,526 |
| village (17.4 h) | 1,048 | 2,363,880 | 211,641 |

River census: **146 systems**, lake 4,509 quads. Collision regression
unchanged at 2,205 samples, max sink 0.000 m, 0 penetrating frames.

---

# v0.10 — The ronin

Everything in this pass came from the same question: what is actually on the
screen? Every entry below is a bug that had been shipping, and most of them
were found by measuring the scene rather than looking at it.

## The eight bugs

**1. Every generated normal map in the game was flat.**
`norm_from_height` multiplied the raw central difference of a 0–1 height field
by `strength`. Across 512 px those gradients are about 0.004, so `nx` came out
near 0.01 and every normal pointed straight up. Measured channel deviation:
cloth 0.003, terrain 0.002, leather 0.004, stone 0.005, bark 0.007, brushed
metal 0.00002. The handful of maps that did show relief — tatami, roof tile,
wood — only worked because their height fields were built from hard steps
rather than smooth noise, which is not a decision anybody made. The gradient
is now normalised against its own RMS, so `strength` means a real surface
slope regardless of how spiky the source is, and the differences wrap so
tiling has no seam. Same deviation after: cloth 0.084, terrain 0.041, leather
0.063, stone 0.060, bark 0.094 — and the maps that already worked land within
10% of where they were.

**2. Every character normal map was tiling 4× to 10× too large.**
The character build tiles textures with a Blender Mapping node. glTF has no
way to express one, so the exporter writes the raw UVs and silently drops the
scale — and `smart_project` packs the entire body into a single 0–1 square, so
one 512 px texture was stretched over a whole 1.8 m ronin. `MatPolish` now
restores the `uv_scale` the build asked for (cloth 6, armour 4, lacing 10,
leather 5, kasa 5, blade 2). Together with bug 1 this is why the cloth looked
like painted vinyl.

**3. The visual terrain and its collider disagreed by up to 6.42 m.**
`HeightMapShape3D` splits every cell on its 00–11 diagonal. The chunk mesh was
splitting 10–01, and `sample_height` was bilinear — a curved surface over a
pair of flat triangles. So the ground you saw, the ground you stood on and the
ground the game asked about were three different surfaces. Measured over the
real heightmap: mesh vs collider mean 0.014 m, p99 0.147 m, **max 6.42 m**.
Both now follow the collider's own triangulation. Re-measured with 8,000
raycasts against the live collider: **max error 0.00008 m, mean 0.00002 m**.
This is what was putting the ronin's feet through the ground on slopes.

**4. 2.4% of the map is water and 7.1% of it was being drawn as water.**
Every channel in the drainage mask is exactly one pixel wide (p95 of the
distance transform: 1.00 cells), so the plus-dilation that made rivers
4-connected was also inflating 914 hairline tributary stubs into full rivers.
Dilating the R *trunk* channel instead keeps the real rivers wide and lets the
capillaries disappear: **147 systems, 2.43% of the map**, and ~0% at the two
camera positions that previously had a pale sheet lying across the grassland.

**5. Grass was being shaved bald along dry gullies.**
Suppression tested the full channel mask while the water surface is built from
the trunk channel, so every unrendered tributary still scratched a bare line
through the meadow. New `Terrain.river_surface_at()` tests what is actually
drawn, including the dilation's neighbours.

**6. Auto exposure was destroying every golden-hour frame.**
`CameraAttributesPractical` meters average frame luminance. A grassland at
golden hour is mostly dark grass under a bright sky, so the meter read the
frame as underexposed and pushed exposure up until the whole sun side was
white paper. Proved by re-rendering one identical frame with metering off and
nothing else changed. Removed. Glow moved from screen blend at 0.58/0.13 over
a 0.92 threshold to **additive at 0.42/0.05 over 1.45**, and tonemap white
3.0 → 4.0.

**7. Distant pines were signposts.**
Every tree LOD built its foliage from `_blob`, an octahedron — six silhouette
vertices, which at distance reads as a stack of flat hexagonal discs on a
pole. New `_canopy()` scatters two-triangle foliage sprays through an
ellipsoid, biased outward, each pointing away from the centre and drooping.
Pine plates, cedar tiers, maple and sakura crowns and saplings all use it.
The card bend weight has to stay above 0.62 because `COLOR.r` doubles as the
bark/leaf selector in `tree.gdshader`; a card in the bark band renders as a
floating plank of wood.

**8. The saya was empty in every frame the game has ever drawn.**
`Sheathe` and `Unsheathe` clips were in the rig and had never been played.
Nothing was bound to them, and nothing could be: there was no input for it.

## Carrying the sword

`anim/SwordCarry.gd` is a `SkeletonModifier3D` that rewrites one bone. The
katana is skinned to `weapon.R`, a child of `hand.R`, so it goes wherever the
hand goes — permanently drawn, in every idle and every walk. Splitting the
mesh out of the GLB would mean rebuilding the character; overriding one bone
does not. When sheathed, `weapon.R`'s global pose is set to the scabbard
bone's pose times a fixed offset, so the hand animates freely underneath and
the sword stays at the hip.

The offset was measured, not eyeballed. In `weapon.R`'s bone space the katana
runs from a pommel at y −0.082 to a tip at (y 0.907, z −0.408): an axis 24°
off +Y, which is exactly the `extra_rot` the build applies when it mounts the
sword in the hand. In the scabbard bone's space the saya is a straight tube on
+Y from −0.10 (the mouth, at the front of the hip) to +0.70. So the seating
rotation is +24° about X — which lands the blade on the saya's axis to within
a rounding error — and the translation is whatever puts the tsuba at the
mouth. The saya was then lengthened from 0.80 m to 0.86 m, because the blade
is 0.908 m and the last 4 cm of tip was sitting past the kojiri.

Drawing is the same override fading 1 → 0 across `Unsheathe`, so the blade
travels out of the saya and into the grip. **Attacking while sheathed does not
teleport the sword into the hand** — it queues the attack behind a draw, so
the first strike of a fight is a genuine iai draw-cut. The blade goes away
again 3.2 s after the last threat.

Only the ronin gets the modifier. Every rig has a `scabbard` bone, but the
levy troops carry a pouch on it, the archer a quiver and the captain a
sashimono banner; parking a katana in any of those would look like a bug.

## Jumping

`Jump_Up`, `Jump_Air` and `Jump_Land` were also in the rig with no input
bound. Now:

- **Space** to jump, with 0.12 s of coyote time so a jump at the lip of a
  ledge still fires.
- **Variable height** — releasing early cuts the rise to 62%.
- **Air control** at 55% authority: you can steer a leap, not restart it.
- **A sprint leap is not a standing hop.** Speed already in the legs converts
  into 20% more height and a forward impulse, so a run-up buys you the gap.
- **Hard landings** above 11 m/s cost a recovery beat and kick up dust.
- Walking off a ledge drops you into the same air state instead of skating
  down the cliff face.

## Controls

16 actions are now rebindable from **Pause → Controls**: the four moves,
sprint, jump, dodge, slash, heavy, spirit strike, guard, draw/sheathe,
lock-on, stance, interact and pause. Each one keeps its fixed alternates
(arrow keys, mouse buttons) and shows the bound key; picking a key that is
already taken clears it from the other action. Defaults: WASD, Shift sprint,
Space jump, Ctrl dodge, J/LMB slash, K heavy, R spirit strike, L/RMB guard,
X draw, Tab lock-on, Q stance, F interact.

## A solid world

Houses, walls and wells were already solid. Rocks were solid; everything else
scattered across the world was scenery you walked through. Loose debris is now
streamed through the same body pool as the structures: **1,632 rocks, 1,288
small stones, 420 fallen logs and 353 stumps**, plus crates, barrels and
baskets in the villages. Branches, ferns, flowers and mushrooms stay
walk-through on purpose — tripping on a fern is not immersion.

## Ground cover

Half of each biome's grass mix was tall or medium, and a 1 m clump only covers
about 0.1 m², so the floor between clumps was visible dirt. Every mix now
carries a short entry (grassland 30%, farmland 34%, rocky 34%, village 34%),
and `short` was rebuilt from 7 thin upright blades into a splayed 10-blade
rosette that actually covers ground. Tier-0 clumps cast shadows at high
quality, which is what stops near grass from looking pasted on.

Shrubs were five smooth blobs and read as rocks. They are now 6 woody stems
with 7 leaf cards each.

## Sky

The horizon was one colour all the way round, which is never true. It now
grades azimuthally: warm toward the sun, a cooler blue-grey away from it,
weighted by how low the sun is so the effect vanishes at noon and at night.

## Measured

Environment, `tests/EnvShots.tscn` at the village vantage, 17.5 h clear, High
quality:

| | v0.9 | v0.10 |
|---|---|---|
| draw calls | 1,048 | 1,263 |
| primitives | 2,363,880 | 4,406,668 |
| grass instances | 211,641 | 186,477 |
| grass chunks | — | 180 |

Ground probe at the same spot — a 25×25 grid on 2.5 m spacing, sampled off the
real terrain rather than guessed from the PNG: `surf={dirt:99, grass:523,
rock:3}`, mean density 0.422, **0 of 625 samples below the water table, 19 on
a river** (3.0%, against 12.9% before the trunk-channel fix).

Terrain agreement, `tests/TriProbe.tscn`, 8,000 raycasts against the live
collider: **max 0.00008 m, mean 0.00002 m**.

Normal map channel deviation before → after: cloth 0.003 → 0.095, terrain
0.002 → 0.041, leather 0.004 → 0.063, stone 0.005 → 0.060, bark 0.007 →
0.094, mud 0.026 → 0.067, snow 0.025 → 0.053. The three maps that already
worked moved less than 15%.

Frame times are still omitted on purpose. This machine renders through
llvmpipe at 2–21 seconds per frame; its milliseconds say nothing about a
phone. High quality also needs more than the 4 GB this sandbox has, so the
high-quality passes had to be run one vantage at a time.

## New harnesses

- `tests/TriProbe.tscn` — raycasts the live heightmap collider against
  `sample_height` and the chunk mesh and reports the worst disagreement.
- `tests/SayaProbe.tscn` — extracts per-bone vertex AABBs from the character
  GLB in bind space. This is where the katana and saya measurements above
  come from.
- `tests/TanProbe.tscn` — reports whether an imported mesh has tangents and
  whether its material has a normal map, because a normal map without
  tangents is a silent no-op.
- `tests/EnvShots.tscn` gained `sweep=1` (re-render the identical frame under
  a list of tonemap/glow settings, ~10 s each instead of a 5 minute run),
  `probe=1` (sample the terrain under the camera), `iso=1` (hide one
  subsystem at a time), and writes its metrics to `user://metrics_<tag>.csv`
  after every shot rather than at exit — Godot block-buffers stdout when it
  is not a terminal, so a run that dies at the end used to lose everything it
  measured.
- `tests/CharShots.tscn` gained `carry=sweep`, which renders a list of
  candidate sheathe offsets at hip and side framings with index 0 forced to
  the drawn pose as a reference.


# v0.11 — The ronin's face, and what was under it

v0.10 fixed how the ronin was lit. This pass asks what is actually *built*.
Close-ups rendered with one material hidden at a time showed that most of what
looked like a lighting problem was a modelling or rigging fault, so every entry
below was found by taking the character apart, not by looking at it.

`tests/CharShots.gd` grew the switches that made that possible:
`hide=<material fragment>` (make a material invisible), `only=7_torso,9_hip`
(render just those shots), `rest` / `bind` (no animation / force the bind pose),
`nolod` (mesh LOD off), `noshadow`, and `clip=Heavy at=0.25,0.55,0.85`, which
freezes the animation tree and photographs the named clip at each time, with
the camera following the hips. One A/B run answers "which surface is this" in
fifteen seconds; one pose run answers "what does it do when it moves".

Two Blender-side tools came out of the same work. `tools/stretch.py` poses a
shipped GLB at `Clip@seconds` (or, with `--all`, every clip at 25, 55 and 85% of
its length) and lists every edge that is over 30 cm long (`--min=` changes that)
and more than 3x its rest length -- a sheet of cloth reaching from a shoulder to
an ankle is a handful of such edges. And every build now ends with
`rig.audit_weights`, which prints how many vertices take real weight from a bone
more than 12 cm away, by material.

## The eleven bugs

**1. There was no mouth.**
The lower face was a separate `jaw` object floating ~20 mm proud of the skull,
and the mouth line sat 13 mm *inside* it, so the lips were buried in every frame
the game has drawn. The lower face is part of the skull loft now (chin rows down
to z 1.522), the lips are real geometry, and the jaw bone is painted onto the
head with `rig.paint_bone` (`_jaw_weight` in `build.py`) because nearest-bone
binding cannot find a jaw inside a head.

**2. The eyes were buried.**
The eyeball sat 1–2 mm inside the skull loft, so what read as "eyes" was a pair
of dark lash tubes stuck on a blank face. New `shape.bump()` is a sculpt brush
for loft sections; it carves a 12.5 mm socket around `EYE` and adds the brow
ridge (+3.8 mm), cheekbones (+4.4 mm), temples (−4.2 mm), mouth corners, jaw
angle, philtrum and chin ball.

**3. The iris and pupil were flattened spheres buried inside the sclera.**
They are flattened caps seated on the front of the eyeball now, so they show
and catch the light.

**4. The eyebrows floated about 9 mm off the face.** They sit on the brow ridge.

**5. Three of the four shin binding cords were inside the leg.**
A fixed 0.063 m ring on a calf that tapers 0.082 → 0.057. The cords follow the
taper.

**6. The hakama legs overlapped the centreline by 72 mm.**
The two trouser columns interpenetrated at their widest row. They meet at the
centreline now, with five hanging folds each (`shape.drape`) and a different
phase per leg so they stop being mirror images. The shin wraps have folds too.

**7. The hair was a closed shell inside the head.**
Hidden geometry is still in the shadow map. The ring stack hidden behind the
forehead was shadowing the face from the inside as a stack of dark chevrons. It
is an open band just proud of the skin now, running down to a V-shaped hairline
at the nape (`HAIR_HALF` / `HAIR_FADE` in `body.py`).

**8. The kasa was 3–6 mm thick and shadowed itself.**
A sheet of paper with a shadow map. It is a hollow dished lathe with real
thickness now, and the sode and kusazuri plates are bowed (`_plate(..., bow=)`)
instead of flat slabs hanging off the shoulders like cardboard wings.

**9. The torso was four shells skinned by distance, and they slid through each
other.**
Found after everything else, with the A/B switches: in the bind pose the belly
was clean, in the first idle frame blue kimono tongues and a grey patch of obi
came through the cuirass. The under-kimono, obi, cuirass and lacing are
concentric shells 5–13 mm apart, and `rig.bind` weighted each vertex by its true
distance to the nearest bone. A shell 13 mm further out got different weights
from the one inside it — the arm bones reach a long way in — so the moment the
spine bent, the shells moved by different amounts and the softest one won. The
torso is now bound with `axial=(1.30, 1.40, 0.15)`: vertices are squashed
toward the body axis before distances are measured, so weight is a function of
*height* and every shell at the same height moves as one. (Side effect, and a
good one: the flanks no longer get dragged around by the arms.)

**10. The trousers were skinned to the hand.**
Found with a pose, not a still. `clip=Heavy` showed a sheet of blue cloth running
from the raised wrist to the knee. `tools/stretch.py` counted **245** stretched
edges across 15 sampled poses (Heavy, Light1-3, Roll, Sprint, Deflect, Jump,
Unsheathe and more) -- all of them in the hakama, all between rest heights 0.63
and 0.70 m, one end weighted to `thigh` and the other **51-59% to `hand`**. The
hanging hand is 20 mm from the outer wall of the trouser leg and the thigh bone
is 100 mm away, and `rig.bind` weights by nearest bone, so every arm swing
carried the trouser with it. It has been in the character since the v0.8
rebuild. The limbs mesh is a bag of separate pieces (arm tube, cuff, palm, each
finger, two hakama columns, shin wraps, cords, tabi), so `rig.limb_sets` gives
each piece, by connected component, to the limb whose bone is nearest its
centroid, and `bind(..., limbs=True)` only lets it use that limb's bones (plus
chest for the sleeve, hips for the leg). With the hand out of the picture the
top rim of each hakama column left the pelvis with the thigh and showed as a
flat-topped tube beside the hip armour, so `waist=(0.78, 0.93)` blends the
trousers into `hips` toward the waist, where a hakama is tied, and each column
gained one row (`body.build_limbs`) that gathers in toward the body centre and up
under the hip ring, so the open top of the trouser is inside the torso shells
instead of five centimetres outside them. Result: **245 -> 0** stretched edges on
Kaito's 15 hand-picked poses. A final sweep over every clip of all four kinds at 25, 55
and 85% of its length (471 poses, `tools/stretch.py --all --min=0.15`) found **18,456**
stretched edges in the build from just before this fix -- in 407 of the 471 poses,
in 56 of Kaito's 60 clips, every idle and every jog among them, longest 0.57 m -- and **0** in
the build that ships.

**11. The kasa took 13% of the chest's motion.**
`rig.audit_weights` showed the hat brim, 0.25 m out and 0.3 m above the
shoulders, taking up to 13% of `upperchest`. A hat is rigid on the head, so
everything from the brow line up is painted fully onto `head`
(`_hat_weight` in `build.py`, through `rig.paint_bone`).

## The forehead chevrons were not geometry

After the hair was fixed, the face still wore evenly spaced dark chevrons at
0.7 m and again at 2.9 m. Hiding the hair, hiding the hat, turning shadows off
and turning SSS off each changed the picture; shadow bias, filter and quality
did not. The cause is Godot's screen-space subsurface scattering: the blur
rejects a neighbour only when its depth differs by more than
`subsurface_scattering_depth_scale` (default **0.01**), and the brows, lashes and
hair edge stand 4–6 mm off the skin — inside that tolerance — so the blur
dragged their black onto the shadowed forehead as ghost copies. `project.godot`
now sets `depth_scale` 0.001, `quality` 3 and `scale` 0.04, with the skin rule at
`sss 0.26`. At the game camera's 4.6 m the ghosting was invisible, which is why
it went unnoticed; it is obvious in any close-up.

## Baked detail

`rig.bake_ao` writes ambient occlusion and hem grime into a vertex colour layer
(two ray lengths multiplied: 5 cm for cavities, 34 cm for contact shadow, so a
hat brim over the shoulders is seen). It casts against the whole joined body, so
occlusion crosses part boundaries. A `tint(co, material)` hook multiplies the
layer per vertex, which is how lips, cheeks and the nose tip get their own colour
(`body.face_tint`) without a second material or another draw call. The layer
ships as `COLOR_0`; the glTF exporter flag name moved between Blender versions,
so `build.py` probes the operator. `MatPolish` turns
`vertex_color_use_as_albedo` on — Godot's importer leaves it off, so before this
the bake would have been dead data.

## Looking from behind

A third-person camera shows the back of the head and the nape all game long.
That view was a bare glossy egg under a black cap and a plain white neck tube.
There is a hairline now, a pale juban collar standing above the kimono collar,
a matte hair material (rough 0.40 → 0.58, aniso 0.72 → 0.45), and the skin was
moved from a porcelain 0.76/0.585/0.455 to 0.54/0.375/0.265 because the lit half
of every face was clipping to white under the key light.

## Measured

| | kaito | ashigaru | archer | captain |
|---|---|---|---|---|
| triangles | 13,258 | 12,934 | 13,542 | 13,900 |
| vertices | 7,108 | 6,940 | 7,268 | 7,453 |
| bones | 38 | 38 | 38 | 38 |
| clips | 60 | 29 | 35 | 33 |
| poses swept (every clip at 25/55/85%) | 180 | 87 | 105 | 99 |
| stretched edges > 15 cm, before -> after the trouser fix | 7,036 -> 0 | 3,495 -> 0 | 3,813 -> 0 | 4,112 -> 0 |

Godot import is clean on every install (no script, parse or shader errors), and
so is a fresh unzip into an empty folder, which is the path you take. That fresh
import is what caught two untyped variables in the old `tests/Diag.gd`
diagnostic, which the incremental imports never re-parsed; fixed. All 57 scripts
now load with 0 errors. The one remaining line in every launch log was
`Error opening file 'res://icon.svg'`: `project.godot` named an icon that had
never been added. There is one now.

A headless run of the scripted pilot (`godot --headless --path game
res://tests/Playtest.tscn`: spawn, walk, jump, draw, sprint, lock-on, attack,
block, dodge, heavy strike, withdraw -- 15 beats through the real `Main.tscn`)
now finishes in about a minute, because `_shoot` skips the screenshot when there
is no renderer. On the shipped build: 7,104 frames, 3 enemies spawned and
engaged, 2,688 grounded samples with max sink 0.000 m and 0 penetrating
frames, 0 script errors. The `mesh_get_surface_count` lines in that log come
from Godot's dummy renderer, which keeps no meshes; rendered runs do not print
them. With a renderer the same scene takes about 18 s per frame on this
machine, so a rendered full playthrough was not completed (its first two beats
were).
The counts are 96 triangles / 48 vertices above the values this pass reached
before the trouser fix (13,162 / 7,060 for Kaito and so on): that is the one new
waist-gather row on each hakama column, and nothing else changed the geometry.

## What this does not fix

The head is about 14% larger than a real head at this height, the ears are
crude, the hands are small, and the hair is a smooth shell with no strands (the
character UVs are a single smart-project island, so a strand map would not
tile). The sheathed sword hangs close to horizontal at the hip in some poses, and
the captain's kabuto covers the upper face. Nothing here gets procedural
geometry to the fidelity of a sculpted, hand-textured character; it gets it from
"a mannequin with a nose" to a face, a hairline and a body whose layers stay
where they are put.

# v0.12 — New ronin, four weapons and a horse

## What changed
- **New player character**: Quaternius Universal Base Character with outfit and hair
  (all CC0, see `CREDITS.md`), on a 121-clip animation library (Quaternius
  Universal Animation Library 1 & 2 plus KayKit clips retargeted to the same rig).
- **PlayerRig**: weapon sockets (hand, hip, back), draw/sheathe with hand IK, an
  upper-body pose layer so you can guard or attack while moving, rider leg fit.
- **Four weapons**: katana, nodachi, yari and fists. Each has light combos, a heavy,
  a sprint attack; fists get a jab–cross–hook combo and kick. Dodges: backstep,
  sidestep, roll. Sword trails are rebuilt (smooth, attached to the blade).
- **Horse**: H calls it, E mounts. W canters, Shift gallops, S brakes, Space jumps,
  cut from the saddle, trample, riding camera.
- **Fast travel**: Pause → Fast Travel to any zone you have visited; the horse comes with you.
- **Controls**: two keys per action, rebind in Pause → Controls.

## Bugs found and fixed
- Ground-slope factor ate ~22% of move speed.
- Pausing dropped skeleton modifiers (skeleton now always processes).
- Sword trail ignored vertex colour, faded the wrong way and sampled per frame.
- Weapons carried on the back sat at hip/feet height (nodachi scabbard dragged on
  the ground, yari butt underground).
- Hit windows opened 4–7 frames before the blade actually swung; realigned to the
  measured blade-speed peaks.
- Fist block used a shield pose; now a boxing high guard. Combos reset on weapon switch.
- Zone names/hints missing for the five newer zones (banner showed "farmland —").

## Tests
- `tests/PlayerQA` (headless): 105 passed, 0 failed. `tests/TestRunner`: 62 passed, 0 failed.
- All scripts compile. `tests/PlayerLab` / `RideLab` render single moves for checking.

## Known limits
- Verified with software rendering and headless runs only — no GPU playtest here.
- Enemies still use the old rig and animation driver.
- Blocks are one-handed; nodachi two-handed guard rests the left hand on the blade;
  the yari flips briefly during draw; rider hands sit a bit high.

---

# v0.13 — Sound, a real river, a better horse and more ways to fight

## Music and sound
- **New soundtrack** (14 CC0 tracks from OpenGameArt, listed in `CREDITS.md`): one
  piece per province, two combat themes, a boss theme and a title theme. Tracks cross-fade on zone changes; combat cuts in
  with a drum hit; a Captain in the fight switches to the boss theme, and his fall
  gets a taiko stinger.
- **All sound effects replaced** with CC0 recordings (Kenney packs and Freesound
  uploads found through Freesound's CC0 licence filter): blade swings, clashes,
  blocks, hits, body falls, footsteps per surface, cloth, draw / sheathe, bow,
  UI clicks, discovery and quest stingers. `autoload/Audio.gd` plays several takes
  per sound (never the same take twice in a row) at per-sound levels.
- **Ambience** follows the place: wind, birds, the river (louder the nearer you
  are), waterfalls with their own roar, fireflies by the water at night.

## The river
- `tools/make_river.py` carves one main river from a mountain spring down to the
  lake: about 1.1 km, falls and a cascade, shallow fords, deeper pools, muddy
  banks. Water is a ribbon that follows the channel, with flowing foam,
  whitewater where it runs fast and churn under each fall.
- Waterfalls are curved sheets with streaks, mist and a foam pool where they land.
- **Swimming**: deep water (lake, river pools) is now swum instead of walked on the
  bottom. Your weapon is sheathed, the body floats, hold Sprint for a fast stroke
  (costs stamina). Fords slow you down by depth. Enemies stop at the edge of deep
  water; the horse slows in fords and refuses deep water.

## The ground
- New terrain material built from photographed CC0 ground sets (Poly Haven): grass,
  forest floor, packed earth, rock, mud and river bed, blended by their height maps
  so stones and roots poke through, with anti-tiling, large-scale variation, rock
  on steep slopes and wet banks along the river. Quality settings scale it down.

## Character and combat
- **Stamina**: dodges, rolls, jumps, attacks and sprinting use stamina; it refills
  quickly when you stop. Empty = winded for a moment (no sprint).
- **More moves**: the katana has a fourth light cut (a diagonal cut before the
  finisher); the yari gets a third, sweeping swing.
- **Riposte**: a perfect deflect opens a short window ("RIPOSTE" on screen); attack
  in it for a fast cut that does heavy posture damage.
- **Plunging cut**: attack while in the air with a blade drawn. The blade comes down
  as you land and hits all around you.

## The horse
- New horse model (smoothed, re-textured, with mane and tail).
- Walk, trot, canter and gallop, each played at the speed the hooves really move,
  so the horse no longer skates. Hoof sounds are timed to each hoof touching down.
- The horse has its own stamina: a gallop lasts about 15 s, then it drops to a
  canter until it gets its wind back.

## Interface
- New HUD: radar map (baked from the world: biomes, contours, roads, river,
  buildings), health with a damage ghost, stamina, posture, focus, horse stamina,
  zone banners, quest tracker with an objective marker, new death screen, and new
  fonts (Noto Sans, Shippori Mincho; SIL OFL).
- Pause menu buttons respond to the mouse again.

## Tests
- `tests/PlayerQA` (headless, real keyboard/mouse input): 129 checks including the
  new riposte, plunging cut and swimming checks — 0 failed.
- `tests/TestRunner`: 62 passed, 0 failed. All 67 scripts compile.
- `tests/RiverShots` renders the river, falls and ground from fixed viewpoints and
  measures each frame (water coverage and colour, layer mix, ground colour).

## Known limits
- Checked with software rendering and headless runs only — **no GPU playtest**,
  so frame rate on your machine is unknown. If it is slow, use Low quality.
- Screenshots were measured by script, not looked at by a person.
- Music and sounds were picked by their descriptions and checked for level and
  length, not listened to in context.
- Swimming has no diving or drowning; enemies do not swim.

# v0.14 — Story mode, new trees and a tidier world

## Story mode
- **Prologue.** New Game opens with a short letterboxed cinematic — the castle on
  its plateau, the keep, Hanamura, the forest road and the Sakura Shrine — under
  five narrative cards, ending behind Kaito at the foot of the shrine steps.
  Enter, Space or a click shows the next card; Esc or the Skip button skips it.
- **Six chapters.** The six quests are now chapters. Each opens with a title card
  (Japanese and English) and has a few spoken lines when it starts, when you reach
  its place and when it is done, shown in a subtitle box. Enter (or a tap on the
  box) moves on; during play Space and E still jump and interact.
- The story owns the quest order: walking into a zone no longer starts its quest,
  so exactly one chapter is active (several could stack up before).
- **Epilogue** when Kuroda falls, then free roam. Continue re-shows the title card
  of the chapter in progress.
- While a cinematic plays the player cannot be hurt, enemies ignore him, and the
  HUD and objective beacon are hidden.
- A new game starts at the foot of the torii steps below the Sakura Shrine, facing
  up them (it used to start on a hilltop 470 m away).
- **Fix: Kuroda now waits in the castle courtyard.** His spawn point was a stale
  coordinate from an older map, a kilometre away in the north-west hills, so the
  final duel could never be found.

## Trees
- Every family is rebuilt: branching trunks and limbs with photographed bark
  (Poly Haven, CC0) and crowns made of textured leaf-cluster cards from a
  generated atlas (`tools/make_foliage_atlas.py`), shaded as one soft volume. The
  v0.13 trees were flat-coloured triangle sprays on six-sided poles.
- New level-of-detail system: trees are grouped in 192 m and 64 m chunks that the
  engine swaps between three detail levels. Each tree is drawn exactly once (no
  doubled canopies, no holes), the three levels share one silhouette so the swap
  does not pop, and there is no per-frame script work. `game/tools/tree_tris.gd`
  prints triangle counts per family and level.
- It is spring: two maples in three are fresh green, the rest a deep red-leaf
  cultivar (the old fire-engine red read as confetti). Cherry petals have real
  petal shapes and only fall where there are cherry trees.

## The world
- **Distant land**: a real ring of hills and mountains 2–4 km out, painted by
  height and slope and hazed by the fog. v0.13 used flat cut-outs that could be
  seen edge-on.
- **Map edge**: the world generator's erosion wrapped around the map, leaving a
  20–45 m wall or trench along every border — the brown striped band visible from
  high ground. The outer 24 m now blend into the land, and invisible walls 4 m
  inside the border keep the player, horse and enemies in. Waterfalls that sat on
  the old wall are gone.
- **Tidier placement** (`tools/tidy_world.py`): removed 67 trees growing through
  houses, walls, the castle gate, torii and lanterns; 22 trees standing on roads;
  the forest inside the castle walls (76 trees — a few ornamental pines and
  cherries stay); 70 rocks, logs and branches inside buildings, on roads or in the
  bailey; and duplicate copies of the keep, shrine hall and first torii that
  flickered against each other at range.
- Rocks and stones use a photographed mossy-rock material (Poly Haven, CC0); logs,
  stumps, branches, crates and wild flowers got real materials (they were plain
  white).
- Grass is brighter, matching the meadow ground; shorter, with far fewer seed
  heads; forest undergrowth is narrower; and the wind sway is slower (0.27 Hz, not
  0.84 Hz — the field used to shiver).
- Fog: the valley mist is 1/30 of its old density and volumetric fog about a third
  — it hid the far half of every view and tinted it green.

## Character
- Running looks less cartoonish: body sway, bob, lean and arm swing are about two
  thirds of v0.13, and leaning into turns is capped at about 6° (was 11.5°).

## Tests
- `tests/StoryShots` plays the prologue or epilogue and photographs it at given
  times, or, in stills mode, frames named shots (`stills=castle:0,village:1`).
- In log mode (`-- log`, headless) StoryShots runs the story without rendering
  and prints its state: the prologue ends at 41.5 s and chapter 1 opens with its
  title card and first lines; Skip at 4 s goes straight there; the epilogue plays
  its four cards and ends in free roam at 32 s.
- `tests/PlayerQA`: 129 checks, 0 failed. `tests/TestRunner`: 62 passed, 0 failed.
  All 72 scripts compile.

## Fixes
- Changing graphics quality filled the Output panel with thousands of "Can't find
  visibility parent" errors: tree chunks were removed in the wrong order.
- Foot IK logged "The axis Vector3 … must be normalized" after a landing on flat
  ground; HUD toasts and the weapon sockets logged warnings. A headless test run
  now prints about 350 lines instead of 27,600 (what is left is the headless
  renderer's own "Parameter "m" is null" noise).

## Known limits
- Checked with software rendering and headless runs only — **no GPU playtest**.
  The prologue shots were framed from still renders; the camera moves were not
  watched at full frame rate.
- Dialogue is text only (no voice acting). Genjo, Elder Ume and Kuroda speak in
  the subtitle box; only Kuroda stands in the world.

---

# v0.15 — Real grass, wildlife and hunting, healing, a darker night

## Grass
- **New grass.** Each plant is two or three crossed cards carrying a whole clump of
  thin, photo-scanned blades (Poly Haven scans, CC0, packed into one atlas by
  `tools/make_grass_atlas.py`). v0.14 built wide ribbon blades on the CPU.
- **No more pop-in.** v0.14 loaded grass in chunks, ten every 0.2 s in scan order,
  so it visibly grew in around you, and a quality change threw it all away. Now
  three rings of tiles around the camera all draw one shared MultiMesh and the GPU
  turns each grid point into a plant from the terrain's own maps (height, biome,
  density, splat, river). Moving a tile is one transform write, so the whole field
  is there the moment you look at it. Rings hand over plant by plant across a
  band (each plant has its own fade distance) instead of swapping chunks.
  Grass reaches 160 m on Low, 240 m on Medium, 320 m on High and 400 m on Ultra.
- The grass takes the same moisture tint and colour variation as the ground under
  it, so the far ring melts into the terrain instead of ending on a line. The
  ground's grass layer is shaded as if it were in the blades' shade.
- Wind is slow travelling gusts with a capped bend: a breeze leans a meadow a few
  degrees, a storm lays it over by about 40°, and blades never fold in half.
- Ferns, shrubs, sasa (bamboo grass) and mushrooms use the same GPU placement,
  each with its own chance per biome. Placement is hashed from world position, so
  a spot always grows the same plants.

## Trees
- **Forests no longer appear as you ride toward them.** The far cards took over at
  260 m and the far field ended at 760 m. They now start at 400 m and are never
  culled by distance (the world is 1.5 km across).
- **No more black, blocky canopies at a distance.** v0.14 boosted leaf alpha
  without limit as textures shrank, so far crowns became solid squares. The leaf
  texture now stops shrinking at a level that keeps the clusters' outline, with a
  capped boost. Far crowns stay broken and leafy, and cards seen edge-on fade
  away instead of showing as streaks.

## Health
Three ways to get health back (v0.14 had none):
- **Natural recovery.** After 7 s out of combat without being hit, health comes
  back at 2.5 per second.
- **The gourd (B).** Three drinks per fill, each restoring 45 health over 1.2 s
  with a soft green-gold glow. The HUD shows a small gourd with one pip per drink.
- **Refills.** Rest at any checkpoint or shrine you have reached (E there): full
  health, a full gourd and a save. Reaching a new checkpoint also refills it.
  Hidden caches give +25 health and +1 drink. Meat from hunted game heals too.
- Fix: "restore health" rewards only changed a stored number, not the health bar,
  so they restored nothing.

## Wildlife and hunting
- **Real animals.** Rigged, animated sika does and stags, red foxes, wild boar
  and wolves (free models, see CREDITS.md) replace v0.14's box animals. Herds
  spawn out of sight, wander, graze, look around, and warn each other.
- **Stalking.** Prey hears you by how fast you move and sees you when it faces
  you. Switch to walk (Z) and come up from behind while it grazes, and freeze when
  it looks up. Run at it and it bolts. A cut on an unaware animal does 2.5× damage.
- **Harvest.** Press E over a carcass. Doe +35 health, stag +50, boar +60, fox +15,
  wolf +20. Deer and boar also refill one gourd drink. Stags, boar and wolves give
  +1 mastery.
- **Boar.** It charges. Sidestep the rush, then cut while it skids round with its
  flank open. A deflect knocks it round. If it gores you, it barrels on past and
  veers off before turning.
- **Wolves at night.** A pack of three may pick up your trail in the wilds (never
  in villages or at shrines). They circle and dart in one at a time. A bite only
  lands in front of the jaws, so a sidestep makes it miss, and a deflect sends a
  wolf reeling. They leave at dawn.
- New sounds: deer alarm barks, fox barks, boar grunts and squeals, wolf howls,
  growls and yelps, the harvest, and the map (CC0, Freesound; see CREDITS.md).
  Howls carry about 450 m, owls about 170 m.

## Night
- **Darker and mistier.** At midnight moonlight is about a third lower, ambient
  light about a fifth lower, the sky and fog darker, the fog closes in to about
  half the distance, and low ground mist is about 2.4× as thick (2.8× before
  dawn). Dusk stays readable.
- **Hitodama.** Pale blue spirit fires from Japanese folklore drift at head height
  in forests, bamboo groves, shrines and ruins between about 21:00 and 04:00. They
  keep their distance: come within about 10 m and one gutters out, then appears
  somewhere else. From Medium quality up they faintly light the ground. They are
  atmosphere only (2 on Low to 6 on Ultra).
- Owls call out in the dark. Wolves howl far off at night even when no pack is
  near, and growl when one is close.

## Horse riding
- **Reins.** The seated clip was a car driver's, so the rider seemed to steer an
  invisible wheel. Arm IK now brings both fists down together above the pommel.
  The horse has a bridle (headstall, browband, cheekpieces, noseband, bit rings),
  and the reins are a sagging leather strap from the bit to the rider's fists.
  With no rider, they lie along the neck to the pommel.

## World map (M)
- A full-screen map over the paused game shows every province, the shrines and
  checkpoints you can rest at, caves, waterfalls, landmarks, your horse and the
  current objective. Drag or WASD to pan, wheel or Q/E to zoom, C to centre on
  yourself, and click a visited province to fast-travel. M or Esc closes it. On
  touch screens, use the MAP button.

## Settings
- **Lag when changing settings is fixed.** Every settings save re-applied graphics
  quality: each slider tick, and every weapon swap (which saves the last weapon).
  Each time it threw away all loaded grass and the forest, and respawned the
  animals. That was the lag, and why grass vanished and crept back in. Quality is
  now applied once, and only when the tier actually changes.
- **Volume sliders behave.** There are four (Master, Music, Sound effects, Nature
  / ambience), each with a % readout. The old linear-to-dB mapping made 10% sound
  like half volume before the last notch muted everything. Gain is now the square
  of the slider: 50% = −12 dB, 25% = −24 dB, 10% = −40 dB (quiet but clearly there).

## About Terrain3D
Terrain3D's ideas are built into the game's own terrain code instead of adding
the plugin:
- GPU data maps feeding the shaders,
- instancer cells moved by the CPU while placement happens on the GPU,
- a colour map tinting the foliage to match the ground.

The plugin itself was not added because:
- it is a compiled C++ GDExtension with native binaries per platform;
- it keeps terrain in its own region format;
- it would replace the terrain that every system queries (height, biome, water,
  roads, minimap, spawning).

Taking it on would mean moving the generated world into Terrain3D's format and
re-testing everything, for the same look. Water and roads keep their existing
systems; Terrain3D has no water, and its roads are painted texture layers, which
the terrain already has.

## Tests
- `tests/HuntQA` (new) plays the hunting rules against the real game: sneak up on
  and kill a doe, harvest it, spook one by running, freeze when watched, dodge a
  boar charge and cut it down, and a night wolf pack that attacks one at a time
  and leaves at dawn. 21 checks, 0 failed.
- `tools/animal_info.gd` prints each animal's measured size and clips;
  `tests/ColorProbe` measures rendered grass/ground colour; EnvShots gained grass
  and tree debug views.
- `tests/Playtest` looked for a node called "Player", but the player node is
  called "Kaito", so it picked up an enemy instead and stalled when that enemy
  despawned. It now asks the world for its player. All 15 beats run:
  0 script errors, max sink 0.000 m, 0 penetrating frames in 2,625 grounded samples.
- `tests/PlayerQA`: 129 checks, 0 failed. `tests/TestRunner`: 62 passed, 0 failed.
  All 79 scripts compile. StoryShots (log mode): the prologue hands over to chapter
  one at 42 s, the epilogue ends in free roam at 32 s.
- `tests/RideLab`: both fists sit within 5–12 mm of their rein IK targets.
- Night, lake vantage at 23:00 (EnvShots, Medium): mean frame brightness 21.3 →
  13.2 (of 255), down 38%. The 06:24 shrine dawn shot is unchanged (63.4 → 64.9).
  `EnvShots only=nightwood wisps=1` photographs the hitodama up close.

## Known limits
- Checked with software rendering and headless runs only. **No GPU playtest**, so
  no frame rates are claimed. Grass, trees, night and hitodama were judged from
  still renders.
- No new music tracks this version. The music work was the volume curve.
- Animals keep to land and do not swim. Wolves do not follow you into villages or
  shrines.

---

# v0.16 — Stealth, smarter soldiers and a technique tree

## Stealth
- **Crouch (C).** C toggles a low sneak (1.45 m/s, quieter footsteps). Sprinting,
  jumping, dodging, guarding, attacking, taking a hit, mounting or swimming stands
  you up.
- **Soldiers see you over time.** Each soldier has a clear view cone 60° either
  side, slower side vision out to 105°, and needs a clear line of sight. Instead
  of spotting you the moment you are in range, his awareness builds. How fast
  depends on distance, how much of you shows (still, walking, running, crouched; a
  rider is obvious) and the light. On a dark night their sight range is about
  half (measured: 1.15 s to spot you standing at 9 m by day, 1.98 s at midnight).
- **Cover.** Crouched in tall grass you are almost invisible: 0.13 visibility,
  against 0.62 standing still in the open. Inside a smoke cloud you cannot be
  seen at all.
- **Soldiers hear you.** How far depends on how you move: crouch-walking about
  1 m, sprinting 12 m, riding 16 m. Hits, clashes and deflects carry further. A
  noise makes a soldier turn and come to look, but noise alone never starts a
  fight.
- **Markers.** A ring over a soldier fills as he notices you. It is white while he
  is unsure, turns amber with a "?" when he comes to look, and flashes a red "!"
  when he raises the alarm. Soldiers who are off screen get an arrow at the edge.
  An eye on the HUD reads CROUCHED, HIDDEN or IN SMOKE.
- **Alarms.** A soldier who spots you shouts. His camp (within 34 m) and any other
  soldier within 14 m join the fight, and anyone within 24 m comes to look. If
  he loses sight of you for 5 s in a fight, he searches where he last saw you,
  then goes back to his post.
- **Sneak attacks.** A cut on a soldier who has not seen you deals 2.5× damage.

## Camps
- All seven provinces now have a camp, including two new ones in the bamboo grove
  and the ruins: sentries at posts facing outward, patrols walking a route through
  the camp, and archers keeping watch from the edge. 35 soldiers, Kuroda included.
- **Fix: soldiers stood in a diagonal line.** The v0.15 spawn search only looked
  inside the first 472 m of the 1.5 km map. Every province except the mountain
  fell back to a fixed point, and its soldiers stood in a diagonal line 5 m apart,
  unchecked for water or slope. Now every post is checked to be on dry, walkable
  ground, and no two soldiers stand within 1.5 m.
- **Fix: soldiers wandered off toward the corner of the map.** A soldier recorded
  his post before he was placed in the world, so his "post" was the map origin.
  Idle soldiers drifted toward it and returned there after a fight. They now keep
  to their own posts and routes.

## Smarter soldiers
- **They block.** Ashigaru block about 30% of the cuts they see coming, and
  captains block 50%. Keep hammering one and he reads the rhythm: he blocks more
  and answers with a quick counter. A blocked cut still costs him posture. Heavy
  attacks are blocked half as often. Kicks, cuts from behind, Iaijutsu
  draw-cuts and Spirit Blade Mastery always get through. Archers never block.
- **Their posture recovers.** Posture holds for 1.6 s after the last hit, then
  drains, faster when the soldier is healthy. Keep up the pressure.
- **Perilous attacks (危).** A red 危 over a soldier and a red pulse at the edge of
  the screen warn of an attack that a guard will not stop:
  - **thrust:** perfect-deflect it, dodge it, or dodge *into* it with Mikiri
    Counter;
  - **sweep:** a low cut that goes through a guard. Jump over it or dodge clear.
  The wind-up is 45% longer than a normal attack, so there is time to read it.
  The HUD names the answer (DEFLECT / MIKIRI or JUMP).
- **Rhythm.** Soldiers sometimes hold a swing a beat longer (ashigaru 15%, captains
  22%), and captains feint: the blade stops, then comes again (18%).
- **Spacing.** Soldiers waiting for their turn spread out around you instead of
  queueing in front of you.
- **Captains string cuts together.** v0.15 captains had a combo that never fired,
  because the check ran after the attack had already been released. A captain now
  follows up with a second, harder cut (and a third in his second phase). Below half
  health he guards less and uses more perilous attacks.
- **Fix: every castle captain was a boss.** The captain class flagged itself as
  the boss, so killing either ordinary captain at the castle counted as defeating
  Kuroda and could end the story. Now only Kuroda is the boss, and only his phase
  change announces itself.

## Techniques (技)
Mastery points (from quests, shrines, hidden caches and hunting) now have
something to buy. They are also earned in fights: 1 per soldier, 3 per captain,
5 for Kuroda and 1 more for each assassination. Press **U** (or Pause →
Techniques, or TECH on touch screens) to open the techniques screen over the
paused game. There are three paths of four techniques. Each path is a trunk of two
techniques that forks into two final ones, costing 1, 2, 3 and 3 points (27 for
all twelve). Learning saves the game.

| Path | Technique | Cost | Effect |
|---|---|---|---|
| Bushido 武士道 | Steady Hand | 1 | Perfect-deflect window 20% longer |
| | Unbroken | 2 | Posture recovers 30% faster; blocking costs 15% less posture |
| | Iaijutsu | 3 | The first cut drawn from the sheath: 1.8× damage, 2× posture, unblockable |
| | Mikiri Counter | 3 | Dodge into a perilous thrust: he loses half his posture, then riposte |
| Shinobi 忍術 | Silent Step | 1 | Noticed 40% more slowly, heard from half as far |
| | Assassination | 2 | One-stroke kill from behind an unaware soldier (or one blinded by smoke) |
| | Smoke Bomb | 3 | Throw smoke (Y): blinds those inside, the rest lose you |
| | Chain Assassination | 3 | Straight after an assassination, a second within 8 m |
| Spirit 霊縁 | Fox Spirit | 1 | A spirit fox that pounces on the soldier about to strike you |
| | Spirit Mending | 2 | +3 health per perfect deflect, +6 per kill near you |
| | Spirit Blade Mastery | 3 | Spirit Blade lasts 15 s (was 10), cuts through any guard, +50% posture |
| | Shadow Step | 3 | Attack right after dodging a blow: appear behind him and strike (1.6×, 8 s cooldown) |

- **Assassination.** ASSASSINATE appears when you are behind a soldier who has not
  seen you, or near one blinded by smoke. Press E (or attack while crouched) for a
  short dash and a one-stroke kill. It does not work on Kuroda or on a soldier
  already fighting you. A soldier who sees the body comes to look. If he is close
  and looking straight at it, he raises the alarm.
- **Chain Assassination.** For 1.6 s after an assassination, attack or E takes a
  second soldier up to 8 m away, even one who has just turned to shout.
- **Smoke bombs** (Y or mouse button 4). You carry three, restocked when you rest
  at a checkpoint or shrine (and when you respawn). The HUD shows them next to the
  gourd. The cloud has a 5.5 m radius and lasts 8 s. Soldiers inside are blinded
  for 4.5 s, anyone who walks in for 2.5 s, and soldiers outside within 18 m lose
  you and search.
- **The spirit fox** is a translucent blue fox that trots at your heel (and keeps
  out of the way while you ride). In a fight it pounces every 16 s on the soldier
  about to attack you, or the nearest one, who turns on it for 2.6 s.
- **Shadow Step.** Dodging through a soldier's blow opens a 0.7 s window. SHADOW
  STEP shows, and attacking puts you behind him for a heavy cut.

## Controls
- **C is now crouch.** Dodge stays on Ctrl. Saved bindings that still had C on
  dodge are moved over automatically.
- **Y** (or mouse button 4) throws a smoke bomb, and **U** opens the techniques
  screen. Touch screens get CRCH, SMKE and TECH buttons.

## Other fixes
- Hints sent as "tips" never appeared (for example "Wounded — press B to drink
  from your gourd"). They now show as a toast.
- Drinking from the gourd was silent because no sound was called "drink". It now
  plays the healing sound.
- Hit and deflect sparks were hard-edged squares. After a dust puff (a hard
  landing, a heavy blow on the ground) they also kept the puff's size, up to
  2.1 times larger. They are now soft round sparks at their own size. Found in
  the smoke bomb still, where the fox's pounce left a cloud of white squares.
- New sounds: two smoke bomb bursts (made for the game by
  `tools/make_smoke_sfx.py`, CC0).
- New font: `Kanji.ttf`, a subset of Noto Serif CJK JP Black (SIL OFL 1.1), for
  the path and technique kanji and the 危 warning.

## Tests
- `tests/AdvQA` (new): 86 checks on the real game, 0 failed. It covers the camps
  (seven, no stacking, dry ground, patrol routes, one boss), sight, crouching,
  night, cover, hearing and Silent Step, alarms, assassination, chains,
  witnesses, smoke, guarding, posture recovery, perilous thrusts and sweeps,
  Mikiri, feints, spacing, the fox, Shadow Step, Iaijutsu, Steady Hand,
  Unbroken, Mending, Blade Mastery, technique rules and saving, the techniques
  screen and mastery for kills. `ADVQA_ONLY=smoke,mikiri` runs a subset.
- `tests/TestRunner`: 68 passed, 0 failed. New checks cover saving techniques and
  smoke bombs, the tree's size and cost, and the new input actions. The detection
  check now gives awareness time to build instead of expecting an instant alert.
- `tests/PlayerQA`: 129 passed, 0 failed. `tests/HuntQA`: 21 checks, 0 failed.
  `tests/Playtest`: all 15 beats, 0 script errors, max sink 0.000 m, 0
  penetrating frames in 2,623 grounded samples. StoryShots (log mode): skipping
  the prologue at 5 s leads into chapter one's dialogue. All 87 scripts compile.
- `tests/FeatureShots16` (new) photographs stealth, an assassination, a perilous
  thrust, a smoke bomb and the techniques screen. `tests/SkillsShot` (new) draws
  the techniques screen on its own over any still in about 30 seconds. On the
  software renderer the world stills need anisotropic filtering off (an
  `override.cfg` that is not shipped): with it on, llvmpipe spent up to seven
  minutes on a single frame of terrain and grass. `tests/ClipProbe16` measures the
  new clips (Crouch_Fwd 0.84 m/s, K_Throw 1.37 s, K_1H_Stab 1.6 s).
- Two bugs were found by the new tests and fixed: an Iaijutsu or Shadow Step bonus
  could carry over to a later air or mounted swing, and a soldier blinded by smoke
  could stand just out of assassination reach. Blinded soldiers can now be
  reached from 3.6 m.

## Known limits
- Checked with software rendering and headless runs only. **No GPU playtest**.
  Detection speeds, perilous timing and technique strength are tuned from test
  measurements, not hands-on play, and may need adjusting.
- No new animations: assassinations use the existing stab clips, and the spirit
  fox is the v0.15 fox model with a spirit shader.
- Archers neither block nor use perilous attacks. Wild animals ignore smoke.

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

## Verification
- Rendered through `tests/EnvShots` (the real game, Ultra, HUD hidden with the
  new `nohud=1` option) and `tests/SkyOnly` (rewritten: the real DayNight cycle
  over a grey ball and ground, cases noon, morning, golden, sunset, dusk,
  cloudy, storm, mist, night). The village vista went from smooth pale cones to
  layered, hazed ridgelines; storm skies lost their bright horizon band.
- `tools/sky_table.gd` (new) recomputes the sky-luminance table the exposure
  uses if the atmosphere constants change.
- `tests/TestRunner`: 68 passed, 0 failed. One run in two had "enemy reaches
  ATTACK or RECOVER" fail with the soldier still circling (COMBAT_READY) after
  2.5 s; it is a timing check and passed on the re-run. `tests/AdvQA`: 86
  passed, 0 failed. All 89 scripts compile.

## Known limits
- Checked with software rendering and headless runs only. **No GPU playtest**,
  so there is no frame-rate number. The new mountain shader and the cloud
  shadows cost more per pixel; drop to Medium if High is slow.
- The clouds are a 2.5D layer, not volumetric: you cannot fly into them.
- The characters, rigs and animations are unchanged in this version.


---

# v0.18 — Real bodies, real armour: the character and anatomy pass

## The soldiers are people now
- **Same body as the ronin.** Ashigaru, archers and captains were low-poly
  procedural figures on their own 38-bone rig. They now use the ronin's
  realistic base body (65 bones) and his 121-clip animation library, through a
  new driver (`anim/UBCDriver.gd`) that keeps the old API, so the AI and the
  combat code did not change.
- **Movement.** Walk, jog and sprint are chosen from the real ground speed
  with hysteresis (no flicker between gaits), stride rate matched to speed,
  backpedal and side-steps in combat, combat stances (spear held two-handed,
  katana at the ready), and the head and neck turn to follow you.
- **Attacks you can read.** Each soldier's swing is a real library clip: the
  ashigaru's yari thrust and sweep, the captain's cuts and thrust. The wind-up
  is stretched to the AI's telegraph and the strike plays at speed, so the
  blade reaches you on the frame the hit is scored. Hits, staggers, blocks,
  knockdowns, getting up and deaths all have their own clips.
- **Archers draw the bow.** Side-on stance, left arm straight with the yumi
  standing vertical, the string drawn back to the jaw by arm IK, the arrow on
  the string, and on release the string snaps straight. The bow rides on the
  back until they aim.
- **Weapons in the right place.** The yari is carried on the back and taken in
  both hands for a fight; the captain's katana sits in its saya on the left hip
  and is drawn when he engages.

## Armour and kit, built to period
- **Jingasa** for the ashigaru: a shallow lacquered cone with the clan mon in
  gold and its chin cord.
- **Kabuto** for captains: a riveted bowl with 16 raised ribs (suji), a
  five-lame neck guard (shikoro) with lacing, a peak, **fukigaeshi** — the top
  lames turned back into wings either side of the face, each with a gilt mon —
  and a gilt crescent maedate seated in its socket above the brow.
- **Sashimono** (back banner: pole, crossbar, white flag with a red disc),
  **yumi** (1.9 m, asymmetric, gripped below centre, with bindings) and a
  **quiver** of fletched arrows.
- Each type is dressed differently from the same body: robe colours and armour
  pieces per type (the captain in darker robes with a brown obi).

## Anatomy and materials (the ronin and everyone else)
- **Joints that move like a body** (`anim/Anatomy.gd`): past ~30 degrees the
  shoulder blade rotates with a raised arm (about 1 degree per 2), the ribcage
  breathes ~14 times a minute at rest and faster and deeper after exertion, and
  the fingers close round whatever the hand holds.
- **The sword is worn properly**: otoshi-zashi at the left hip, the left hand
  resting on the saya while it is sheathed.
- **Real cloth**: the costume is mapped with scanned fabrics (linen, hessian,
  wool herringbone, crepe satin) instead of flat colour; armour lames and hair
  strands have their own generated textures; skin scatters light (subsurface)
  so faces stop looking painted.

## No two soldiers alike
- Every soldier gets his own height (plus or minus 4.5 %, captains a little
  taller), skin tone and dye lot for his robe.

## Performance
- **Distance LOD for the new bodies.** Near: everything every frame. Past
  20 m the smallest parts (eyes, rivets, cords) drop out, past 40 m the other
  small pieces. Past 32 m the
  animation steps at 12 Hz and the anatomy and look-at layers switch off; past
  55 m, or off screen, 5 Hz and small parts stop casting shadows. Hits are
  scored from the soldier's position, never from his bones, so LOD can never
  change a fight.

## Tests
- `tests/TestRunner`: 68 passed, 0 failed. The "enemy reaches ATTACK or
  RECOVER" check now watches the whole 2.5 s window instead of one instant (a
  swing-recover-ready cycle is about 2 s, so a single sample could land between
  two attacks; that was the v0.17 flake). `tests/AdvQA`: 86 passed, 0 failed.
  `tests/PlayerQA`: 129 passed, 0 failed. All 94 scripts compile.
- `tests/EnemyLab.tscn` (new): renders any soldier type in any clip or state
  from several cameras (`--vary SEED` shows the per-soldier variety).

## Known limits
- Checked with software rendering and headless runs only. **No GPU playtest**,
  so there is no frame-rate number. The new bodies cost more than the old
  low-poly ones; the LOD above is there for that, and Medium quality helps.
- Faces are the same base face on every soldier (height, skin and clothes
  vary, features do not).
- `UBC_BODIES` in `enemies/EnemyBase.gd` switches the old procedural soldiers
  back on if needed.

---

# v0.19 — Faces of their own: facial hair, and proof that the LOD pays

## Facial hair
- Soldiers now grow facial hair (`anim/FacialHair.gd`). Five styles: stubble,
  moustache, drooping moustache, goatee and full beard. Each is a soft mask
  over the face skin; the triangles under it are copied with their own bone
  weights and pushed out along the skin by a few millimetres (more under the
  chin, so a beard hangs instead of lying flat), then cut by a streaky noise
  so the edges break up into strands. The hair shares the head's skin, so it
  moves exactly with the face. Stubble is a soft blended shadow, not hairs.
- Who gets what: about a third of ashigaru and archers are clean-shaven and a
  third show stubble; the rest have moustaches, goatees or beards. Captains
  always have a moustache or beard, and about one in three has gone grey.
  Hair colour varies from black to dark brown. The style comes from the same
  per-soldier roll as his height and skin, so a repeatable seed gives the
  same faces.
- The hair casts no shadow and is not drawn past 40 m.

## The LOD, measured
- New `tests/LODPerf.tscn` spawns 36 soldiers (all three kinds) between 6 and
  90 m from a camera, ticks them the way `EnemyBase` does (half walking, half
  idle) and times whole frames with the distance LOD off and on, twice each.
  On the 2-core test machine (headless, so this is CPU work only: animation,
  anatomy and look-at layers): **14.1 ms per frame with the LOD off, 6.9 ms
  with it on**, about half. With this layout 4 soldiers are at full detail, 7
  at level 1, 10 at level 2 and 15 at level 3. In the game, soldiers that are
  off screen also drop to level 3, so a real camp saves more than this.

---

# v0.20 — Soaked: the rain reaches the people

## Wet characters
- v0.19 rain darkened the ground, the grass and the bark, but the ronin and
  the soldiers stayed bone dry in a storm. Now every character material is
  registered with what it is made of (`anim/CharWet.gd`) and follows the
  weather's wetness, with the same lag as the ground:
  - cloth and straw go darker (water fills the weave, so less light is
    scattered back) and slightly less rough;
  - skin and facial hair pick up a sheen (roughness down by up to 40 %);
  - lacquered armour gets a deeper, glossier clear coat; iron gets glossier.
- The dry values are stored, so drying out returns exactly to them, and new
  soldiers spawned in the rain start from their dry colours, then soak.
- Cost: a few dozen material updates whenever the wetness changes by 1 %,
  nothing per frame otherwise.
- New checks in `tests/TestRunner`: soak and dry-back of a material, and a
  storm soaking the characters while clear weather dries them.

---

# v0.21 — Breath in the cold

## Visible breath
- On a snowy day, a clear night or a foggy dawn every nearby character
  breathes out a small cloud of vapour (`fx/BreathFX.gd`). The puffs follow
  the anatomy layer's own breathing (14 breaths a minute at rest, up to 40
  when winded), so a fighter who has just sprinted or fought puffs fast and
  hard while a sentry breathes slowly. The vapour is left behind in the air
  as the character moves, drifts forward and a little up, grows and fades in
  under two seconds.
- How cold it is comes from the weather: full strength in snow, about half
  on a clear night, a little more in thick fog.
- Cost: two small one-shot CPU emitters per character (12 particles each),
  only for characters within about 32 m (LOD 0-1). The dead stop breathing.
- New check in `tests/TestRunner`: a soldier's breath shows in the snow and
  not at a clear noon. `tests/EnemyLab` can show it: `--cold 1 --puff 0.6`
  (breathe out, capture 0.6 s later) and `--mood cold` (winter light).

---

# v0.22 — Feet on the ground

## Characters stand on the ground
- Fixed the biggest visual bug: in almost every animation (standing, walking,
  running, sword cuts, hits, interactions) the ronin and every soldier stood
  about 17 cm too low, with the feet sunk into the ground up to the ankles.
  The v0.15 animation bake scaled the hip height by the wrong axis (the base
  character's root bone is turned 90 degrees, so it read the hips' 4 cm
  front/back offset instead of their height) and lowered every clip from the
  Universal Animation Library by 18 %. `anim/GroundFix.gd` undoes that on the
  vertical axis when the library loads, so the feet now meet the ground (idle
  0.0 cm, walk +0.4, jog +1.1, sprint 0.0 at the lowest point of the cycle).
  The body also no longer jumps up and down by 17 cm when it switches between
  those clips and the KayKit attack clips, which were baked correctly.
- `tests/GroundClips.tscn` measures every clip (121): 89 now touch the ground
  within 2 cm; the rest are jumps, rolls, deaths, swimming and riding, where
  the feet are meant to be off the ground or are handled in code.

## Feet planted on slopes and steps
- The foot IK from the old body (v0.9) now drives the new bodies too: the
  ronin and every soldier within about 14 m (LOD 0) plant both feet on
  slopes, steps and rocks, the hips drop to let the lower foot reach, and each
  sole tilts to the ground. On a 20 degree slope the uphill foot used to sink
  8 cm and the downhill foot float 8 cm; now both are within 1.5 cm.
- It fades out in the air, in rolls, in water, on horseback and when dead.

## Footsteps on the beat
- Footsteps are played when a foot actually lands (the IK reports each
  footfall) instead of on a timer, so they match the stride at every speed,
  and a sprint lands harder than a walk. Nearby soldiers now make footsteps
  too, on the right surface, quieter than yours.

## Mix
- The music ducks a little under loud hits (a compressor sidechained to the
  effects bus) so sword clashes cut through, and the master bus has a gentle
  compressor and a limiter, so a big fight with music, rain and many swords
  never clips.

## Tests
- `tests/TestRunner`: 3 new checks (feet on the ground in idle, walk, jog and
  sprint; both feet planted across a 20 degree slope; master limiter and
  music ducking). `tests/GroundProbe.tscn -- --slope 20` prints the sole gaps
  with the IK on and off. `tests/EnemyLab --nofix 1` shows the old sunk pose.

---

# v0.23 — The Night the Castle Fell

## A cinematic opening
- A new game now opens on a 68-second prologue cut to its own score:
  the province and the year over black; Asano castle burning at night, seen
  from low in the courtyard while the camera tilts up the keep; soldiers with
  torches marching out of the gate; Kuroda standing in front of the burning
  keep; Hanamura village on fire; a sword flash and "Eleven winters later";
  then dawn, and Kaito gallops up the forest road on his own horse (the real
  horse and rider in the game world, not a video), past a camera on the road,
  to the shrine hill and the title. He reins in at the Sakura Shrine and
  dismounts, and the camera cranes down behind him into the normal follow
  camera without a cut.
- Six narration cards tell the story (Lord Asano's death, Kuroda's betrayal,
  the raids, who Kaito is and why he returns).
- Hold Esc (or the Skip button) to skip: the night is cleared and Kaito is
  placed where the ride ends. Loading a saved game never plays it.
- The keep fires sit outside the walls (they were inside the model before and
  could not be seen), with flames, smoke, embers and flickering light.
- Fixed: the opening text cards ("Kiyomizu Province, 1573" and "Eleven winters
  later") were drawn under the black fade and could not be seen.
- Chapter cards now land with a taiko stroke and a temple bell.

## Kaito's own face
- Kaito no longer shares the soldiers' head. `tools/kaito_head_v23.py` builds
  `assets/char/Kaito.glb` from the base character (the soldiers keep theirs):
  - a lean face: hollow cheeks under wide, projected cheekbones, a
    medium-width jaw and a defined chin;
  - "hunter" eyes: almond-shaped, hooded by a lower, heavier brow ridge, with
    a slight lift at the outer corners;
  - thick, low, nearly straight eyebrows;
  - long, dark-brown wavy hair (about 450 hair cards with their own strand
    texture) parted near the middle, lying close over the crown and falling
    over the ears to the jaw and the nape, with a few locks across the forehead;
  - stubble, and a thin old scar across the right cheekbone.
- The topknot and headband are gone; the samurai outfit is unchanged.
- The hair is shaded with a low specular so it stays dark brown at grazing
  angles instead of shining tan.

## The horse
- The tail moves on its own: it streams up and back at the gallop and bounces
  with the stride, swings out on turns, lags like a whip when the horse sets
  off or reins in, and swishes at flies when it stands (`anim/HorseTail.gd`,
  a chain of springs on the seven tail bones, on top of the animation).
- Dust kicks up behind the hooves at the canter and gallop on dry ground
  (none in the rain, on wet ground, in water or on rock).
- After a hard run it blows: breathing builds with every second of gallop and
  is heard once it slows down, louder and faster the longer it ran, easing off
  as it recovers. On cold mornings, clear nights and in snow its nostrils
  steam with every breath (`fx/HorseFX.gd`).
- New horse breathing recordings (CC0).

## Title screen
- An animated ink-and-gold backdrop that drifts with the mouse, falling
  petals, and a timed reveal: a rising swell, a sword flash on the title, the
  seal and a taiko stroke, then "Press any key". Continue appears when there
  is a save; New Game asks before it erases one.

## Music
- The prologue score (`assets/audio/music/prologue.ogg`) is built from CC0
  recordings: a dark wind drone, shakuhachi, a war horn, a taiko performance
  that builds through the night, impacts on the cuts, ringing steel on the
  sword flash and the title, a temple bell and koto at the shrine.
  Every hit is placed on its cut (the swelling impact and the late-ringing
  steel were measured and lined up by their peaks).
- Loudness: every zone track measures -18.6 LUFS (within 0.3 dB) and the
  prologue is mastered to match (-18.9 LUFS, true peak -1.5 dBTP; it was
  -16.7 LUFS and clipped at +0.3 dBTP).

## Sound effects, tested
- `tools/audio_audit_v23.py` measures every sound in the game (169 effects,
  15 music tracks, 8 ambience loops): loudness, true peak, DC offset, silent
  lead-in, loop seams and how far the variants of one sound sit apart.
- `tools/sfx_fix_v23.py` fixed the 70 effects it flagged: DC offset removed,
  silent lead-ins trimmed (a sound now starts on its frame), and the variants
  of each sound levelled so no hit or step is suddenly louder than the others.
- New sound sets: riser, boom, sword ring, big whoosh, brush stroke, temple
  bell, war horn, horse breathing, fire whoosh, and a big fire loop.
- All 30 new recordings are CC0 (public domain) from Freesound; each licence
  was checked on its page when it was fetched (`tools/fetch_ids_v23.py`).
  See CREDITS.md.

## How this was checked
- No GPU here: stills were rendered with Godot's software renderer and the
  test suites run headless. Audio was judged by measurement (loudness, peaks,
  onsets), not by ear. Frame rate on a real GPU was not measured.
