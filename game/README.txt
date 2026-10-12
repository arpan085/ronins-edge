RONIN'S EDGE  v0.22  -  how to run it
=====================================

1. Install Godot 4.3 (the standard build, NOT the .NET one):
   https://godotengine.org/download/archive/4.3-stable/
   Other versions (4.2, 4.4+) are not tested with this project.

2. Put the project in a NEW, EMPTY folder. Either way works:

   A) Unzip the download (right-click > Extract All). In Godot's Project
      Manager click Import and choose  project.godot  inside the unzipped
      RoninsEdge folder.

   B) Or skip unzipping: in the Project Manager click Import, pick the .zip
      file itself, set "Project Installation Path" to an EMPTY folder, then
      click Import & Edit.

   Do not unzip over an older copy of the game.

3. FIRST OPEN ONLY: Godot imports about 520 assets. This takes a few minutes
   and shows a progress bar; wait until it finishes before pressing Play.

4. Press F5 (Play). Title screen -> New Game. A short prologue plays first
   (Enter or a click = next card, Esc = skip), then chapter one begins.

Controls (defaults - rebind any of them, two keys each, in Pause -> Controls)
  Move            W A S D / arrow keys     Sprint (hold)       Shift
  Walk / run      Z (toggle)               Jump                Space
  Dodge           Ctrl  (no direction = quick backstep; locked on = sidestep)
  Crouch          C (toggle; sneak, hide in tall grass)
  Light attack    Left mouse / J           Heavy attack        Right mouse / K
  Kick            V                        Punch combo         G
  Guard/deflect   Q or L (hold; tap just before a hit to deflect)
  Draw / sheathe  X                        Weapons             1 katana  2 nodachi
                                                               3 yari    4 fists
  Cycle weapons   mouse wheel or [ ]       Lock on             Tab / middle mouse
  Spirit Blade    R (needs focus)          Change stance       T
  Interact        E or F (talk, mount horse, deathblow, assassinate)
  Smoke bomb      Y / mouse button 4 (needs the Smoke Bomb technique)
  Techniques      U  (spend mastery points; also Pause -> Techniques)
  Call horse      H                        Pause               Esc or P
  Drink (heal)    B  (gourd of medicine)   World map           M  (pan: drag / WASD, zoom: wheel / Q E,
                                                                  C = centre, click a visited province to travel)
  Fast travel     Pause -> Fast Travel (to provinces you have visited; the horse comes too)
  Story           Enter = next line of dialogue (or tap the box); in the prologue and
                  epilogue Enter / Space / click = next card, Esc or Skip = skip it

On horseback: W canters, hold Shift to gallop, S brakes, Space jumps,
attack buttons cut with the katana from the saddle, E dismounts.
The horse tires: after about 15 s of gallop it drops to a canter for a while.

Health (v0.15)
  Out of combat, health slowly comes back by itself. B drinks from the gourd
  (three drinks per fill). Refill it by resting at a checkpoint or shrine you
  have reached (E there), with hidden caches, or with the meat of hunted game.

Hunting (v0.15)
  Deer, foxes and boar live in the wilds. Prey hears you by your speed and sees
  you when it faces you: switch to walk (Z) and come up from behind while it
  grazes; freeze when it looks up. A cut on an unaware animal does 2.5x damage.
  Press E over a carcass to harvest it (heals, deer and boar refill the gourd).
  Boar charge: sidestep the rush, then cut while it skids round.
  At night a wolf pack may pick up your trail outside villages and shrines; they
  dart in one at a time, can be deflected, and leave at dawn.

Stealth (v0.16)
  Soldiers notice you gradually: a ring over a soldier fills as he sees or hears
  you (amber ? = he comes to look, red ! = alarm; his camp joins in). Crouch (C)
  to move quietly; crouched in tall grass you are almost invisible, and at night
  they see about half as far. A cut on a soldier who has not seen you does 2.5x
  damage. With the Assassination technique, E behind an unaware soldier kills
  him in one stroke.

Techniques (v0.16)
  Quests, shrines, caches, hunting and now kills give mastery points. Press U to
  spend them on three paths of four techniques (Bushido: deflect, posture,
  Iaijutsu, Mikiri Counter; Shinobi: Silent Step, Assassination, Smoke Bomb,
  Chain Assassination; Spirit: fox, mending, Spirit Blade Mastery, Shadow Step).
  Arrows / WASD + Enter, or click, to learn.

Combat tips (v0.13, v0.16)
  Stamina (bar under health) is spent by attacks, dodges, jumps and sprinting.
  Guard just before a hit = perfect deflect; attack right after it to RIPOSTE.
  A red 危 over a soldier = perilous attack, a guard will not stop it:
  thrust -> perfect deflect or dodge (Mikiri Counter: dodge INTO it);
  sweep -> jump over it. Soldiers block too: kick, use heavy attacks, or get
  behind them.
  Attack in the air (blade drawn) = plunging cut on landing.
  Deep water is swum: hold Shift for a fast stroke (uses stamina).

Needs a GPU with Vulkan support (the project uses the Forward+ renderer).
If the game runs slowly, set quality to Low in the Pause menu.
Graphics (v0.17): quality Low / Medium / High / Ultra in the Pause menu.
  Cloud shadows need High or Ultra; Ultra adds a soft far depth of field.
  "Film grain / vignette" in the Pause menu turns the film look off.

Characters (v0.18): the soldiers now share the ronin's realistic body and
  animation library: ashigaru with jingasa and yari, archers who really draw
  the yumi, captains in a kabuto. Every soldier is a little different.
Faces (v0.19): moustaches, beards and stubble, so the soldiers no longer
  share one face up close. Captains always wear one; some have gone grey.
Rain (v0.20): people get wet too. Clothes darken, skin, hair and armour
  pick up a sheen, and everyone dries off slowly when the rain stops.
Cold (v0.21): on snowy days, clear nights and foggy dawns you can see
  everyone's breath, faster and heavier after a fight.
Ground (v0.22): feet stand on the ground and stay planted on slopes and
  steps; footsteps land with each step.

What is new in this version: see WHATS_NEW.md (section "v0.22").
Asset credits: see CREDITS.md (CC0 assets; the fonts are SIL OFL 1.1; the
wolf model is CC-BY 4.0 by CoinCoin).
