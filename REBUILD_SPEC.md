# Open Theft Auto — Exhaustive Feature Inventory / Rebuild Spec

Everything in this repo, distilled for a from-scratch rebuild. Source: Godot 4.7, pure
GDScript (~19,400 lines under `scripts/`), no build step. All world geometry is
procedural except 9 licensed glTF assets (cars, aircraft, shuttle, spacecraft, 5 human
rigs). Movement/collision is **pure kinematic AABB** (custom `collides_at` test, no
physics bodies) — the only Godot-physics object in the game is the Moon's trimesh
collider for the buggy/spacecraft.

---

## 1. Tech foundation

- **Engine:** Godot 4.7 (standard, not .NET). Main scene `scenes/main.tscn` = Node3D + `game.gd`.
- **Window:** 1920×1080 viewport, exclusive fullscreen, stretch `canvas_items`, aspect `expand`. Mobile: 0.65 render scale, MSAA off; desktop MSAA ×2. Android export supported (touch HUD).
- **Autoload singletons (order matters):** `GameState`, `Forbes`, `Ventures`, `InputConfig`, `AudioFX`, `Gamepad`, `StockMarket`, `Garage`, `RaceManager`, `SaveGame`.
- **Frame step:** `dt = min(0.05, delta)`. Game clock: `time_min += dt*0.5`, wraps 1440 (full day ≈ 48 real min, starts at noon = 720).
- **All UI is procedural GDScript Control trees** — no .tscn UI, no Theme resource; consistent palette (off-white `#e8e6e0`, steel `#8c9bab`, gold `#c2a05a`, money green `#84a85f`, danger `#c8534a`, panel bg ~`rgb(.075,.085,.10)`).
- Test harness: `tests/world_collision_audit.gd` — headless boot, asserts every road centreline walkable, shorelines wade-able, deep water blocked, causeway open, no oversized colliders. Prints `WORLD_COLLISION_AUDIT_OK buildings=N`.
- Landing page: `site/index.html` (static marketing page, deployed to Vercel).
- Naming quirk shipped in product: boot screen says "GTA VI / FREE HARBOR · 3D · 2026"; project + site say "Open Theft Auto".

---

## 2. Procedural world (`world.gd`, 3,981 lines)

### Scale constants
| Constant | Value |
|---|---|
| BLOCK | 32 m |
| GRID | 13 blocks/axis (14 roads/axis) |
| ROAD_W | 15 m |
| WORLD (city core) | 416 m square (half 208) |
| Wilderness outer ring | half 458 |
| LAND_HALF (coastline) | 838 (code comment says 806 — trust arithmetic) |
| MOON_Y | 4,000 m above city |

### City
- Road grid: 14 N-S strips + 14 E-W (E-W gapped over river, carried by bridges). Layered heights 0–0.13 to prevent z-fighting; textured asphalt + footpath (sidewalk = road+14 wide).
- **Districts** per block by radius: `d<60` downtown (1–3 towers, w/d 6–14, h 45–110, blue-grey palette), `d<122` commercial (2–3 blocks, h 10–40, LA stucco creams), else residential villas. Fixed park blocks (6,5),(5,9),(4,7). Fixed landmark blocks: exchange (6,6), dealership (6,7), Stark lab (5,6), realtor (7,6), hospital (5,7), Angel Ventures (7,7).
- **Building grammar:** plinth base, brick/stucco shader facades (world-space UV), corner piers, floor bands, roof slab + water tank or solar panel, door + canopy; ≥28 m glazed podium; ≥18 m curtain-wall mullions (MultiMesh). Windows: 0.8×1.4 quads, 82% spawn, single emissive **MultiMesh** (one draw call), energy animated day→night.
- **Villas:** lawn 18×16, driveway, stucco body, gable tiled roof, framed windows, porch, attached garage, fenced recessed pool, perimeter fence, shrubs.
- **Parks:** lawn, circular pond (animated water shader), cross paths, 11 trees.
- **River:** x = −64, half-width 8; recessed bed, water plane, rocks/reeds/nav markers; 14 bridges (deck h 4.2, 16 m ramps, pylons, railings) — `surface_height` lifts entities onto decks.
- **Docks:** 5 piers (walkable rects over water, deck y 0.55), boat boarding points.
- Suburbs ring: up to 72 procedural houses (rotated lots, chimneys, mailboxes, hedges, 58% garages). Outer landscape: ~220 trees/rocks. 44 beach palms + 110 city trees. 45 drifting cloud clusters (y 55–90).
- Street lamps: checkerboard over intersections (~72), emissive bulb + OmniLight (range 18), lit at night.

### Landmarks (each with an interaction kiosk: pedestal + emissive monitor + Label3D prompt)
- **Free Harbor Exchange** — brick tower h 66, emissive bands, sign, 2 Forbes banners. Hidden **glass trading-floor penthouse** at y 66.4 (revealed on entry; altitude-gated collision so ground still works below) with desks, 14 glowing monitors, lounge, EXIT pad.
- **Free Harbor Autos** — glass showroom, 4 display cars (2 on interior lifts).
- **Stark Industries** — glass showroom + tower h 52, arc-reactor disc, suit-delivery dais with light beam, 4 display suits (Mark III / Mark VI / War Machine / Hulkbuster, Hulkbuster ×1.55).
- **Free Harbor Realty** — stucco office, sign; second "City Planning" kiosk for the island megaproject.
- **Free Harbor General Hospital** — clinic, emissive red cross, donate kiosk.
- **Angel Ventures HQ** — podium + hexagonal glass tower h 60, gold rings/crown/spire/beacon, 1 Forbes banner.
- **FORBES banners:** SubViewport (640×840) renders a fully `_draw()`n Forbes board — masthead, "THE WORLD'S RICHEST", LIVE tag, top-5 rows with deterministic drawn bust portraits (hashed from name; player gets shades + gold ring), refreshed on `Forbes.updated`.

### Safehouses (from PropertyCatalog, each a 2×2-block estate)
Lawn 52×52, 2-storey glass-white mansion, 3-door garage wing, gated perimeter wall, hedges/palms, name sign; pool from index ≥1, rooftop helipad from index ≥2. Grandeur scales with price.

### Airport island (south-east bay, causeway from city)
- Grass airfield `x 30–235, z 227–777`. Runway A 500×16 (airliner), Runway B 420×10 — centreline dashes, threshold bars, edge lights, grass overrun.
- Walkable terminal (30×44×16 lobby, glass front, 14 m entrances, pillars, skylight, gold roof sign), control tower, hangar, apron, helipad (r 11), red pulsing beacon on 50 m pole, taxi guide line.

### President's estate island (own bay island, causeway to airport)
Manicured grounds `x −135–18, z 252–470`; walled perimeter with east gate, columned mansion + 2 wings + flagpoles, 6-bay garage, helipad, ornamental lake, fountain plaza.

### Hidden space facility (wilderness, `(300, −650)` — no marker ever)
Fenced compound 180×150 (gate on south side, "RESTRICTED AREA" board, dirt approach track), rocket pad + service gantry (h 48) + 3 fuel tanks + "FREE HARBOR SPACE" sign, enterable maintenance hangar (workbenches, tool cabinets, engine cradle), spacecraft **PAD B** (painted landing ring, amber beacons), **He-3 buyer depot** (kiosk + storage spheres), control tower with radar dish, corner floodlights. One-time cryptic toast at t>240 s: "Strange lights reported far to the north, past the wilderness..."

### The Moon (built at y 4000, visible only when near)
- Heightfield: FastNoiseLite (seed 1969) hills + **40 procedural crater bowls** (r 8–34, raised rims), flattened around pad/base, curls down past playable r 340 to horizon r 620 (small-body curve).
- SurfaceTool mesh (grid step 16) + trimesh StaticBody (the game's only physics collider). Player walks on analytic `moon_height`.
- Props: 34 rocks, emissive Earth sphere (r 74) in sky, landing pad + flag, 9-gate glowing buggy course, **moon base** (2 domes, tube, airlock, solar arrays, comms dish, sign), **He-3 extractor** (drill tower, spheres, hopper, green vents), 700-star MultiMesh dome.
- **Space vista:** real Earth sphere (r 2600, continents + cloud shell) and vista Moon sphere fade in by altitude for the orbit view; sea plane hidden from orbit.

### New Harbor Island megaproject (`(1180, 40)`, 380×320)
Cost **$500B** at City Planning kiosk (double-press E within 6 s to sign). Pre-built in 3 hidden stages toggled by `island_stage`: 1 construction (pilings, cranes, barge) → 2 cable-stay bridge → 3 finished district (marina hotel tower h 74, casino + gold dome, shops, lighthouse, palms, sign). Builds in real time (~5 min); walkable + solid only at stage 3.

### Collision contract
`collides_at(x, z, r=0.5, altitude)` — spatial hash (24 m cells) over AABB list `{x,z,w,d,h}` (+ optional yaw/round); altitude gating frees fliers above rooftops; whitelisted walkable zones (docks, causeways, airfield, estate, facility, island); water blocks: river channel below bridge height, deep sea, world edge = coastline. `surface_height` lifts onto bridges/docks/trading floor. `find_safe_spawn()` spiral search.

---

## 3. Player, camera, combat

### On foot
- Walk 4.5, sprint 8.0 m/s; accel `move_toward(…, 50*dt)`; yaw lerp `dt*14`; no jump. Moon: 2.9 / 4.6 m/s with floaty bob. Collision radius ~0.4.
- Player model: rigged glTF "Peter" (clothed), weapon prop bone-attached to right hand.
- Passive regen +4 HP/s when wanted = 0. `restock_respawn` (R): alive = full HP + ammo; dead = respawn.
- **Death:** all liquid cash → 0 (bank + assets survive); if killed by a Forbes rival's guard, that rival inherits the cash. Respawn at active safehouse (else safe spot), wanted cleared, HP full.

### Camera
- Third-person chase, dist 6.5; mouse sens 0.0025 (0.0011 aiming); pitch clamp [−0.2, 1.2]. In vehicles auto-swings behind heading (`lerp_angle dt*6`).
- FOV 70 hip / 32 ADS / 10 sniper; ground vehicles widen up to +14 with speed; spacecraft hyper +38.
- First-person ADS (hold aim): eye height +1.62, body hidden. **Sniper scope:** animated 0.35 s smoothstep zoom 70→10 driving a fading vignette scope overlay (mask circle, mil-dot reticle, red centre dot).
- Toggleable driver/first-person vehicle camera per vehicle (offsets per type; vehicle mesh hidden).
- Camera shake accumulator, decay 2.2/s.
- **Gamepad aim-assist:** on-foot + aiming + firearm only — magnet cone ~17°, range 75 m, pull scales with closeness (max 0.5), player stick can override.

### Weapons (`WeaponDB.LIST`, hotkeys 1–9, cycle Q/Tab/Z or L1/R1)
| # | Name | Ammo | Dmg | Rate s | Range | Spread | Pellets | Notes |
|---|---|---|---|---|---|---|---|---|
| 0 | FISTS | ∞ | 10 | 0.32 | 2.4 | – | 1 | melee |
| 1 | KNIFE | ∞ | 32 | 0.42 | 2.8 | – | 1 | melee |
| 2 | PISTOL | ∞ | 22 | 0.26 | 80 | 0.012 | 1 | also all NPC/cop fire |
| 3 | REVOLVER | 36 | 58 | 0.50 | 90 | 0.006 | 1 | |
| 4 | SMG | 300 | 13 | 0.055 | 68 | 0.04 | 1 | |
| 5 | RIFLE | 120 | 40 | 0.20 | 130 | 0.018 | 1 | |
| 6 | SHOTGUN | 48 | 13 | 0.62 | 42 | 0.17 | 8 | |
| 7 | SNIPER | 20 | 95 | 1.0 | 220 | 0.001 | 1 | scope |
| 8 | RPG | 8 | 130 | 1.3 | 160 | 0.015 | 1 | explosive |

- Bullets = spheres @120 m/s, life = range/speed, spawn +1.5 above feet, direction = camera fwd + spread. Recoil rumble scales with damage.
- Hits vs torso point (`dist² < 1.0`) → damage + wanted +0.4 + blood; near-miss vehicles take dmg×0.3; explosive rounds detonate on any impact (radius 5.5, falloff 0.35–1.0, vehicles ×0.4).
- Dedicated melee action (C / right paddle): FISTS cone strike, half-angle 0.6 rad, 0.4 s cooldown, any loadout.
- Enemy bullets: driven vehicle first (dmg×0.5), then torso (dist<1.3); armour absorbs 70%; Iron Man suit invulnerable (sparks).
- Vehicle explosion: player ≤8 m takes up to 60, NPCs up to 80. Run-over: speed>3 → `speed*240*dt` dmg + wanted.
- Tank cannon: 1.4 s cd, explosive 120 dmg, range 220, +1.5 wanted per shot.
- Particles: blood, sparks, fire, 60-particle explosions; money pickups spin/bob, collect ≤1.5 m.

---

## 4. Vehicles

**Common:** enter ≤4 m (planes 5+r); motorcade not commandeerable; HP → burning (2 s) → explode; pit lane self-repair +26 HP/s below 8 m/s; bikes keep rider visible (astride pose).

### Catalog (dealership; max_speed m/s, HUD km/h = ×3.6)
City Cab $35k/18 · Vapid Stride $60k/23 · Granger XL SUV $180k/26 · Buffalo GT $480k/40 · Comet Coupe $850k/46 · Banshee $1.4M/54 · Adder $2.6M/66 · Vacca Veloce $4.5M/78 · **Formula 1 $8M/111** · Vortex Bike $140k/58 · Rhino Tank $6M/13.

- **Cars:** accel `0.6×max_speed` (boost ×1.7 = sprint), drag 0.6 (handbrake 4), grip falls with speed, handbrake drift, cosmetic lean/squat, front-wheel visual steer, collision = sparks + hp − speed×0.3 + bounce −0.3×. Procedural box meshes per style (sedan/coupe/sports/suv/hyper/bike/tank); F1 = real McLaren MCL35M glTF (scale 32, ride height 0.13). Tank = hull + tracks + turret + cannon. Bike = 2 wheels/frame/tank/fairing.
- **Traffic:** 54 ambient cars on the grid.
- **Boats:** speedboat 26, jetski 34, **submarine** 18 (dive 0–3.2 m, underwater blue-green fog when submerged); spawn at every dock; wake spray; exit only at docks.
- **Boeing 787** (glTF; airliner ×1.8 on runway A, small ×1.0 on B): manual throttle lever (holds set point), takeoff speed 14 m/s (below → sinks/stall), pitch ±0.55 on arrow keys, banked turns, max speed 62, ceiling 240; **animated landing gear** (1.2 s, toggle in flight; belly landing = −45 HP crash); bail out at y>4 → plane destroyed + parachute.
- **UH-60 Black Hawk** (glTF, airport helipad): vertical takeoff, hover on release, max 46, ceiling 240, cyclic only airborne, spinning main/tail rotors, bail + parachute.
- **Parachute:** descent 9 m/s, steer 7 m/s; auto-deploys on bail-out or high-altitude vehicle death.

### Space Shuttle (3 separable glTF meshes: orbiter, tank, twin SRBs; ~48 m stack)
State machine: ascent → space_climb → space → moon_descent → moon_landed → moon → moon_ascent → reentry → splashdown.
- Vertical rail ascent; **SRB separation at 520 m** (tumbling, gravity −18); dark sky at 1500 m; **tank separation on reaching space**; at 3000 m teleport to Moon approach (y MOON_Y+280), scripted −26 m/s descent, touchdown on moon terrain.
- Return: board on Moon, climb; at MOON_Y+900 teleport to Earth re-entry (y 2400) — heat-shield fire, buffet, wind ramp — **splashdown** at y≤34 (spray, walk to nearest dock, fresh shuttle respawns at pad).
- Layered exhaust plume (blue-white tight jet in vacuum, smoke in atmosphere); rocket rumble/ignition audio.

### Fighter spacecraft (glTF, facility hangar PAD B)
Phases: landed → **hover** (scripted rise to 8 m over 2 s) → **spool** (2.2 s tremble) → **hyper** (850 m/s vertical burn, min 3 s; to space at 1700 m Earth / 300 m Moon) → **space free-flight** (full pitch/yaw/thrust, no drag, cruise 160) → **manual hover-descent** (sink limit 14 + agl×0.28, auto-level, touch down anywhere — no autoland).
- Interact in space = instant Earth↔Moon hop. HUD nav panel: body/phase/altitude, Earth/Moon distance mapped onto real 384,400 km, He-3 cargo readout.

### Moon buggy
Parked near lander: max 24, HP 200, low-gravity bounce, tilts to terrain slope, 9-gate glowing course.

### He-3 economy loop
Load **120 kg** at Moon extractor (120 s refill cooldown, refills in real time), sell at Earth facility depot at the **live HE3 stock ticker price** × kg.

---

## 5. Iron Man suit

| Tier | Name | Price | fly_v/fly_h | Repulsor dmg/cd | Missiles dmg/cd |
|---|---|---|---|---|---|
| 1 | Mark III | free (spawns near player) | 14/22 | 18 / 0.18 | – |
| 2 | Mark VI | $1.8M | 17/26 | 28 / 0.13 | 68 / 0.85 |
| 3 | War Machine | $15M | 22/34 | 42 / 0.10 | 100 / 0.5 |
| 4 | Hulkbuster | $1.8B | 18/26 (slower) | 75 / 0.09 | 170 / 0.45 |

- Rigged `ironman.glb` (scale 40; Hulkbuster ×1.5). Purchased suits delivered to the lit Stark pad.
- **Assembly:** step onto parked suit (≤2.2 m; must move >3.6 m away to re-arm) — plates fly on feet-to-head, 0.1 s stagger, 0.5 s grow, sparks.
- **Summon (V):** plates streak across the map to you (0.05 stagger, 0.8 s flight, trails); on the Moon they drop from +40.
- Flight: vertical accel 46/s to ±fly_v, ceiling ground+220; horizontal fly_h airborne (7.0 grounded), sprint ×1.7; boot jets while airborne. **Bulletproof + explosion-proof.**
- Repulsor (hold fire): range 95, speed 170. Missiles (alt-fire, tier 2+): range 165, speed 82, explosive. F powers down (steps clear of solids).

---

## 6. NPCs, police, VIPs, President

- **Pedestrians:** 54 spawned, topped to 40 min; HP 35, carry $5–30; wander 2.5 m/s, flee gunfire; death drops cash, +2.0 wanted; despawn >200 m. Character mix: tinted Quaternius rigs ×3, photo-scanned "Nathan" ×2 (baked mocap walk clip), suit VIPs, guards. Procedural walk cycle for all rigs (measured arm-down angles per importer bind pose, cached bone lookups); seated pose in vehicles.
- **Wanted (0–5 stars):** `_raise_wanted(amt)` → wanted += amt×0.15, happiness −amt×0.08; decays 0.18/s after 4 s calm. Escalation: 1★ cops (HP 80, 5 m/s, pistol <60 m every 0.7 s, sirens), 3★ **SWAT** (HP 180, 6.6 m/s, 0.45 s fire) + **SWAT vans** (drop 3, every 17 s, max 4), 4★ **police helicopter** (spawns y 62, tracks at 30 m/s holding +36, strafes <95 m). Cop spawn timer max(4, 10−wanted×1.4). Cops give up 90 m (<2★) / 180 m. Killing a public figure = instant 5★.
- **Asset seizure at high heat:** wanted ≥3.5 → **trading account frozen**; ≥4.5 → seizure pulse every 18 s: tow an owned car to impound → raid safehouse (up to 0.5% net worth) → claw cash. Impound recovery fee = half sticker price at the dealership.
- **Rich VIPs:** 4 roaming, HP 70, escorted by 3 guards (HP 95, ring 4 m, fire <55 m); kill reward randomly $10k / $50k / $100k / $1M as a drop; +3.0 wanted, −1.5 happiness; whole detail aggros.
- **Forbes rivals in-world:** all 8 tycoons hold court at landmark turfs — HP 240, **5 guards HP 140**, floating live net-worth nametag. Kill one → **their entire fortune transfers to you**, instant 5★, −8 happiness; dead rivals stay dead (persisted). Their guards' kills route your dropped cash back to that rival.
- **President motorcade endgame:** limo (HP 280) + 3 escort SUVs + President (HP 240) + 6 guards (HP 120); convoy 17 m/s runs estate ↔ airport on a timer (first at 75 s, then 110–180 s). Shooting = hostile detail + 5★. **Kill the President → CITY OWNED:** +$5B, wanted permanently stood down, armour cap ×1000 (100k, held full), **$200,000/s passive income**, victory banner, and you get a presidential detail: 4 friendly bodyguards (gun down threats ≤48 m) + 4 escort SUVs that form a convoy around your car.

### Wealth milestones (each fires once; deferred until on foot on Earth)
$1k → 3 celebrants/+2 respect · $100k → 3/+4 · $1M → 4/+6 · $100M → 5/+10 · $1B → 5/+15 · $10B → 6/+20 · $1T → 6/+30. Celebrants spawn off-screen, run in, cheer 6–10 s (bouncy hop), wander off; purely cosmetic; queued one at a time, no timeout.

---

## 7. Economy & simulation autoloads

### GameState
money, bank_balance (insured, survives death), wanted, time_min, weapon_idx/ammo dict, respect (0–100, starts 5), happiness (0–100, starts 50), total_donated, milestones_hit, island_stage/progress, he3_cargo.

### Stock market (tick 1.6 s, runs even paused; history 90 samples)
9 tickers `{price, vol, drift, event-prob, rally_bias}`: VIN 128 · MBT 74 · PSW 39 · BNM 52 · LFE 88 · FLY 16 (negative drift) · BWC 6.5 (crypto, wildest) · RAS 1.2 · **HE3 35,000** (the He-3 sale price feed). Model: log mean-reversion to a decaying anchor + gaussian noise + event runs (rally/crash regimes, 5–35 ticks, overextension damping), price clamps 0.02–500M. Fractional-share buys by dollar amount; sells floored to prevent minting; cost-basis tracking.

### Angel Ventures (resolve tick 5 s)
5 open deals from name/sector generator (16 prefixes × 14 suffixes, 10 sectors w/ emoji, Indian founder name pools, 5 pitch-thesis templates); ask $2M–$250M, equity 5–25%, valuation = ask/equity, traction strings, risk low/med/high. **Min ticket $100k.** **Negotiate:** lowball <25% of ask risks founder walking (35%); ≥70% → equity bonus up to +10 pts (cap 40%). Per-tick per holding: fail prob (6%→1% by stage, ×1.5 high/×0.6 low risk), exit prob from Series B (payout = current value, verb IPO at Pre-IPO, **+respect 2+stage**), raise prob (~14–20%, value ×1.25–4.5 by risk), else drift −2%..+3%. Stages: Seed → A → B → C → Pre-IPO. Realised P/L tracked.

### FORBES — RICHEST (tick 4 s)
8 rivals: Otto Bergmann $950B (aggressive) · Eleanor Vance $620B · Kazuo Tanaka $410B · Rex Calloway $340B (aggressive) · Priya Nandakumar $95B · Simone Delacroix $58B · Marcus Whitfield $22B · Ines Okafor $5.4B. Geometric growth (aggressive drift 0.26%/tick vs 0.09%, vol 1.5% vs 0.7%), clamp $1B–$5T. Aggressive rivals: 5%/tick **mega-deal** (×1.06–1.20) with "ahead of you again" taunt toast (45 s cooldown). Player worth = cash + bank + stocks + ventures. **First #1 → "You are the richest person alive," +15 respect, one-time.** Live top-5 (+you) rendered on downtown banner boards. Kill/inherit + death-cash-absorption hooks.

### Reputation
Respect & happiness 0–100, shown as 5-pip meters. Sources: donations (log curve `log(1+amt/1000)×1.8 × headroom`, diminishing to the 100 cap, tiered thank-you messages $10k→$10M), venture exits, Forbes #1, milestones; crime/wanted drains happiness.

### Garage
Owned vehicle indices, impound list (+ half-price recovery), suit tier (only climbs, always wear best), properties, active_property = respawn home (first purchase auto-home).

### Grand Prix (RaceManager)
Entry **$100k** non-refundable + optional bet; lap choices 3/5/8; countdown 4 s; player on pole + **5 AI racers** (rail-follow the baked centreline, skill 88+4i, slow for corners, offset lanes); rank by monotonic on-track progress (no infield cutting). Payout ×10/×4/×2/0. Lap detection: mid-track arming + n/10 line + 6 s cooldown; last/best lap; **drift score** (60/s escalating on-track while drifting).

### F1 circuit (`track.gd`)
Catmull-Rom loop through the wilderness, 21 control nodes, width 16 (+6 corner widening), baked every 6 m. Sand runoff, dashed centreline, chequered start/finish band, red/white corner curbs, armco, streetlights, **neon-lit tunnel sector**, start gantry, 8 pit garages + pit lane, 2 grandstands, **paddock hall** (glowing race-entry disc), winner's podium, plus a "Vinewood Hills" billionaire estate (helipad, infinity pool, guest houses).

---

## 8. Save system

`user://open_theft_auto_save.json`; autosave every 10 s (started && !paused) + on window close; NEW GAME deletes. Saves: money, bank, weapon idx, finite ammo, owned/impounded vehicles, suit tier, properties + home, stock holdings **and full market prices/regimes** (Continue doesn't reprice), respect/happiness/donated, venture portfolio + realised P/L, milestones, island stage/progress, He-3 cargo, **Forbes rival worths + alive flags** + reached-#1 flag. Load clamps everything; restores by symbol/name matching. Controls saved separately (`user://controls.json`).

---

## 9. Input (`input_config.gd` + `gamepad.gd`)

- All actions registered as `g_*` in InputMap, **fully rebindable** (keyboard+mouse slot and gamepad slot per action), persisted JSON, conflict-clearing on rebind, reset-to-defaults. Defaults: WASD move, Shift sprint, Space aim/handbrake, LMB fire, RMB alt-fire, C melee, ↑/↓ fly, F enter/exit, E interact, V summon suit, P phone, Q/Tab/Z weapons, 1–9 direct, R restock/respawn, G race terminal, B landing gear, X camera view, M mute, Esc pause.
- Pad: sticks move/look, R2/L2 accel-brake or fire/aim, □ interact+handbrake (intentionally yoked pair), △ enter/exit, ○ summon, ✕ boost/confirm, L1/R1 weapons & shop amount steppers, paddles sprint/melee (fallback ✕/R3), Share phone, Options pause, D-pad ↑ restock, ↓ race. `ui_accept` auto-bound to ✕ so all menus confirm on pad. Last-device tracking picks the controls tab.
- Gamepad autoload: deadzones 0.18 stick / 0.06 trigger (rescaled), PlayStation detection by name, **layered rumble** (continuous engine channel + decaying one-shot pulses, re-issued at 0.15 s).

---

## 10. Audio (`audio_fx.gd` — almost fully synthesized, 22,050 Hz mono WAV)

20-player round-robin pool + dedicated loop players (ambient, radio, rocket, wind, spacecraft, jet). Synth primitives: tone (sine/square/saw + exp decay), noise, drone, chiptune melody. **Per-gun layered gunshot synth** (noise snap + pitch crack + sine body + tail) with distinct params for pistol/revolver/SMG/rifle/shotgun; sniper uses a sampled shot + synthesized sub-boom tail; RPG launch whoosh; generic sampled gunshot fallback. Loops: rocket ignition/rumble, wind, spacecraft hum, jet turbine (throttle-pitched), city ambient drone, chiptune radio. One-shots: repulsor sweep, missile, hit, 2-note coin, explosion, siren, engine revs, thruster, splash, metal crash, landing-gear whirr. Global mute toggle.

---

## 11. UI screens

- **Boot:** big title, CONTINUE/NEW GAME (save-aware) or PRESS START, full controls legend, gamepad focus seeded.
- **HUD:** money, 5-star wanted widget, REP/MOOD pip meters, waypoint text (President when motorcade out, else AIRPORT + distance + 8-way compass), clock, HP/armour bars, weapon + ammo, **semicircular speedometer** (needle, redline last 18%, digital km/h) for ground vehicles / ALT for aircraft, **228 px minimap** (water/land/beach/river/grid/islands/causeways, landmark dots, pulsing President blip, player arrow, 1080 m span), race panel (position/lap/time/best/drift), spacecraft nav panel, **stacked toasts** (max 5, newest at bottom, emoji icon extraction, good/bad accent inference, fade in/hold/out), sniper scope overlay, **WASTED** death screen, **CITY OWNED** victory banner (8 s fade).
- **Pause menu:** PAUSED → Resume / Controls / Exit (saves). Controls screen: scrollable grouped action list with keycap chips (kb + pad per action), press-to-capture rebinding with pulsing prompt, reset-to-defaults, fixed-controls legend, and a **live drawn DualSense diagram** (body silhouette, all buttons, leader-line labels that re-resolve current bindings in teal, "(unassigned)" states).
- **Phone (P):** Call sports car / Call F1 · Fast travel: Airport, Exchange, Launch pad · Full heal+ammo · **Bribe cops $50,000** (wanted→0).
- **Touch HUD (mobile only):** dynamic left-half joystick (radius 110, sprint at >0.85 magnitude), right-half drag look, FIRE/E/F/V circle buttons, hidden under overlays.
- **Terminals** (all: pause, E/Esc/○ close, gamepad focus ring via UiNav, L1/R1 amount steppers, magnitude-scaled dollar steps, quick-fill chips):
  - **Exchange:** cash/portfolio header, **insured bank deposit/withdraw**, frozen-account banner (wanted ≥3.5), per-stock rows with sector badge, live sparkline, price/change/holdings, buy/sell; detail view with full-width chart (open-price baseline, high/low, P/L); buy-by-dollars vs sell-by-shares order ticket (chips $100/$1k/$10k/MAX or 25/50/75/100%).
  - **Dealership:** 4-col car cards with rendered PNG thumbnails, BUY/SPAWN/RECOVER-from-impound states.
  - **Realtor:** 4 property cards, BUY / SET HOME / YOUR HOME states.
  - **Stark:** suit table (capabilities column), EQUIPPED/OWNED/BUY, delivery-pad hint.
  - **Race:** 3/5/8 laps picker, bet field + chips, payout table, total-to-enter validation.
  - **Hospital:** respect/happiness/total-donated stats, live "+X respect +Y happiness" preview, diminishing-returns curve, tiered thank-yous.
  - **Angel Ventures:** 3-pane — deal-flow cards (risk-coloured), founder pitch (thesis, valuation/raising/equity/traction boxes, **NEGOTIATE** button, ticket + result preview, INVEST), portfolio pane (stage-dot bars ●●●○○, P/L, closed history).

---

## 12. Day/night & atmosphere

Sun rotates with game clock; energy/colour warm→cool; opposing moon light; fog and sky colours interpolate; night turns on window emission ×1.2, lamp glow ×2.5, 72 street OmniLights, head/taillights, pulsing runway beacon, signs. Space sky = flat near-black + fog off + altitude-gated planet vistas. Drifting clouds. Underwater fog when submarine dives.

---

## 13. Third-party assets (all fitted in code; everything else procedural)

McLaren MCL35M (CC-BY) · Quaternius Universal Base Characters (CC0) · "Indian Man in suit" VIP (CC-BY) · "Man Dressed In Suit" guards (CC-BY) · Renderpeople "Nathan" w/ mocap walk (CC-BY) · Spider-Man "Peter" player model (CC-BY) · Boeing 787 (CC-BY) · UH-60M Black Hawk (CC-BY) · Space Shuttle w/ boosters (Sketchfab Standard) · Class-3 fighter spaceship "Hodbin" (Sketchfab Standard) · CC0 gunshot samples. MIT-licensed project.
