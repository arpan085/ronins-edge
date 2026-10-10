# v0.17 plan — realism pass ("MORE ADD", "MAKE IT EVEN BETTER BEST GRAPHICS REAL")
Base: /data/ronins_edge/game = v0.16 restored from published play zip (session 017d9ee7...) after 2nd reset (Oct 9).
!! Back up WIP to session files often (reset restores /data to an OLD snapshot).
Render: sudo dnf install xorg-x11-server-Xvfb mesa-vulkan-drivers; /data/renv.sh; game/override.cfg aniso=0 only for renders.

## Physical sky calibration (numpy model, done)
Single scattering Rayleigh+Mie+ozone, Schuler Chapman approx for light optical depth, view march quadratic steps.
Params: H0 0.3 km, RG 6360, RT 6420, BR (5.802,13.558,33.1)e-3/km, BMs 3.996e-3, BMe 4.44e-3, ozone (0.65,1.881,0.085)e-3 x2.5,
HR 8, HM 1.2, Mie g 0.8, TMAX 100 km, turbidity 1.4 default, ms proxy k=0.2 (Tms = trans at 4 km, elev+0.06), steps 12.
Sky sun elevation e_sky: = light formula when >= -1 deg; evening -1 -> -4.5 smoothstep(17.735, 20.8); morning mirror (4.6 -> 6.265).
Exposure sx = sl(hour)/phys_lum(e_sky).  phys_lum table (cos-weighted upper-hemisphere luminance):
EL  [-5,-4,-3,-2,-1.5,-1,-0.5,0,1,2,3,4,6,8,10,13,16,20,25,30,40,50,60,75,90]
LUM [4.968e-05,0.0001332,0.0003706,0.0006372,0.0007879,0.0009556,0.001156,0.001676,0.002827,0.003684,0.004525,0.005338,0.006771,0.00794,0.008892,0.01001,0.01086,0.01172,0.01251,0.01309,0.0139,0.01444,0.01482,0.01516,0.01526]
sl keys (old irradiance x0.9): 0:0.0032 4.6:0.0103 6.2:0.1209 8:0.2481 12:0.3923 15.5:0.3012 17.8:0.1523 19.2:0.0677 20.8:0.0091 24:0.0032
Art layer weight w = max(0.80*smoothstep(2.0,-4.0,e_sky), night); ozone x1.5 (x4 made low sun magenta); knee >1 -> 3; fwidth LOD clouds
Clouds: 2.5D cumulus shell 1.6 km + cirrus 8 km, light taps toward sun, lit by T_sun(h)*sx*cloud_k(~0.085), ambient amb_top/amb_hor from GDScript port.
Half-res pass computes sky+clouds (ALPHA = sky visibility); full-res pass adds sun disc/moon/stars * vis. Cubemap pass cheap.

## Then
2 aerial perspective tune; 3 distant mountains (res, erosion, strata, snow); 4 post (grain/vignette/grade layer, far DOF Ultra, TAA Ultra?);
5 cloud shadows (maybe); 6 docs/tests/pack/Notion (v0.17 block, rename v0.16 block, setup paragraph, roadmap 3h).
WIP backup session file v17_wip1.tgz 67b57cd7-26db-403a-a768-a8a89cde7ea7 (sky done-ish)

## 3rd reset (Oct 9 ~18:25 UTC): /data back to v0.15 snapshot again
Restore: unzip v16 play 017d9ee7 -> /data/r16/play, dev a1de80c7 -> /data/r16/dev; cp -a r16/play/RoninsEdge/. ronins_edge/game/;
tar xzf v17_wipN.tgz game (in /data/ronins_edge); dnf install Xvfb mesa-vulkan-drivers vulkan-loader libX*; renv.sh; override.cfg aniso=0; --headless --import.
Post-wip2 edits (now in wip3): sky cumulus oc/imax restore; Terrain distant range rewrite (patch/terrain_range.py); distant_land.gdshader
rewrite (patch/); DayNight depth fog = real aerial perspective (fog_density was never set -> Godot default 0.01 -> depth fog max 1%!):
begin 0, end haze_far(6000)/fd, curve 0.75, density 0.78+0.2*thick, sky_affect 0.15+0.5*..; volumetric x0.6; World aerial 0.75 density 0.78
sky_affect 0.15; camera far 8000 (PlayerCamera, Story, RiverShots).
Baseline b16 shots lost -> use session file b16_sheet.jpg 7871c28e-5735-4c71-8e79-503aadfdc36e (village, mountain / forest, windfield; 720x405 tiles).
a2_village.jpg (retuned ring, good: layered hazy ridges) = 3f371e90-93c2-4087-a9be-cc0d8153d880; sky sheet built at /data/v17/out/v17_sky_sheet.jpg from e9eef222 + 118b8171; README v0.17 done
tests: TestRunner 68/0 (1 flaky run 67/1 COMBAT_READY timing), AdvQA 86/0; WHATS_NEW v0.17 appended; packing RoninsEdge_v17
