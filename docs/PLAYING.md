[Back to README](../README.md)

# Playing

1. Click "Load a WAD" and pick a `.wad` file. Use one you legally own, or the
   freely redistributable shareware `doom1.wad`. Optionally add PWADs (see
   [Loading PWADs and DeHackEd patches](#loading-pwads-and-dehacked-patches-mods)
   below).
2. Optionally edit the key bindings (see
   [Default controls](#default-controls) below) and the mouse sensitivity or
   invert setting.
3. Optionally pick a pixel filter and aspect ratio. You can also change these
   while playing.
4. Click "Start DOOM".
5. Click the game once to capture the mouse. From then on the mouse looks
   around and both mouse buttons shoot. Esc releases the mouse (and opens
   Doom's menu).
6. Quitting from Doom's own menu (Options, Quit Game) returns to this setup
   screen. Your WAD selections and settings stay as they were, and Start
   boots a fresh game. The short pause with a sound right after confirming
   the quit is Doom's classic quit jingle, not a hang.

## Default controls

Mouse (after clicking the game once to capture it):

1. Move mouse: turn, and look up and down
2. Left or right mouse button: shoot
3. Esc: release the mouse (also opens Doom's menu)

Keyboard defaults are WASD with strafing on A and D, since the mouse covers
turning:

1. Move Forward: `KeyW`
2. Move Backward: `KeyS`
3. Strafe Left: `KeyA`
4. Strafe Right: `KeyD`
5. Turn Left: `ArrowLeft`
6. Turn Right: `ArrowRight`
7. Fire: `KeyF`
8. Use or Open (doors and switches): `KeyE`

The key binding fields use JavaScript `KeyboardEvent.code` names, for example
`KeyW`, `ArrowUp`, `Space`, or `ControlLeft`. Internally the page remaps each
physical key onto a key the engine understands: `F` onto Left Ctrl (Doom's
Fire), `E` onto Space (Doom's Use), and `A`/`D` onto Comma/Period (Doom's
classic strafe keys, which the engine patch wires up for the browser). So `E`
really does trigger Use, not Fire, and `A`/`D` really do strafe.

Doom's own Options, Customize Controls menu also works in game and persists to
the in-memory config file for the session. The page level remap decides which
physical key is reported to the engine. The in-game menu decides what a (real
or remapped) key does. Combine both if you need finer control than the page UI
offers.

## Mouse look

Clicking the game captures the mouse with the browser's pointer lock, the
same mechanism every browser shooter uses. While captured, horizontal motion
turns and vertical motion looks up and down, GZDoom style. Esc always
releases the mouse; that is a browser rule no page can override, and it
conveniently doubles as opening Doom's own menu. Click the game again to
recapture.

Horizontal (turning) and vertical (looking) sensitivity are separate
settings, each with seven steps (Extra low, Low, Normal, High, Higher, Very
high, Extra high). The defaults are Sens X High and Sens Y Low, which suits
mouse-look play: quick turning with restrained vertical aim. Both can be set
on the setup screen or changed live from the bar at the top of the screen.
"Invert mouse look" on the setup screen flips the vertical axis.

"Raw input (disable mouse acceleration)" is on by default: it asks the
browser for unaccelerated mouse motion (the pointer lock unadjustedMovement
option), so a flick of the wrist moves the view the same amount no matter
how fast the flick was. Most desktop browsers support it; if yours refuses,
the game quietly falls back to normal accelerated motion and logs a note in
the console. The setting takes effect the next time you capture the mouse,
so if you toggle it mid-game, press Esc and click back in.

Two honest limitations of bolting vertical look onto the 1993 renderer with
y-shearing (the same technique Heretic and Hexen used): the view pitch is
clamped to a comfortable range rather than a full 90 degrees up and down, and
the sky texture can look stretched or tiled when looking far up. Both are
normal for this technique.

## Display: scaling and pixel filters

The game canvas is scaled to fill the browser window. A small control bar
sits at the top of the screen while you play. It is nearly invisible during
play so it never distracts; move the mouse over it and it comes back to full
strength. It offers:

1. Pixel filter:
   - "Crisp (original pixels)" uses nearest-neighbour scaling. This keeps the
     classic large, sharp Doom pixels. This is closest to the original look.
   - "Smooth" uses the browser's built-in bilinear smoothing, which blends the
     pixels for a softer image.
   - "hq2x", "xBR", and "DCCI" are GPU upscalers (WebGL shaders) with
     edge-aware interpolation, the same family of filters emulators use,
     each in 2x, 4x, and 8x variants (the filter applied one, two, or
     three times over). 8x pays off mainly on large or high-DPI displays,
     where it replaces the browser's final blur-up with filter-built
     detail; on a laptop screen 4x usually looks the same. The engine
     always renders the classic 320x200 picture internally, so the shaders
     recover that true image through the engine's integer enlargement and
     upscale it properly; earlier versions filtered the already-fattened
     pixels, which visibly did almost nothing. hq2x rounds pixel-art
     edges, xBR keeps sharper diagonals, DCCI is a smooth directional
     cubic look. If your browser has no usable WebGL, these fall back to
     Smooth automatically.
2. Aspect:
   - "4:3 (original look)" matches how Doom was shown on period monitors.
   - "Square pixels" displays the buffer without stretching.
3. Sens X and Sens Y: horizontal (turning) and vertical (looking) mouse
   sensitivity, seven steps each from Extra low to Extra high. Defaults are
   Sens X High and Sens Y Low (fast turning, gentle vertical aim).
4. FPS: shows or hides a performance readout in the top right corner, with
   two numbers sampled once a second from counters inside the engine:
   - "FPS" is how often the engine renders, which the browser drives.
   - "game: N/35" is game-logic speed in tics per second. 35 is full speed.
     Fewer means the map is too heavy to simulate in real time and the game
     is running in slow motion; the page itself stays responsive (see
     [Performance notes](ENGINE-PATCHES.md#performance-notes)).
5. Fullscreen: a button that toggles true fullscreen.

You can also set all of these on the setup screen before you start. Changing
a control takes effect immediately, so you can compare presets live. While
the mouse is captured by the game, press Esc first to free it, adjust the
bar, then click the game to recapture.

### Why the on-screen size scales at runtime but the rendering does not

The vanilla renderer always draws the game at 320x200, and that cannot
change while the game runs, so the page scales the finished frame to fill
the window using CSS, and the pixel filters decide how that scaling looks.
The GPU filters work from the same true 320x200 image.

## Loading PWADs and DeHackEd patches (mods)

Next to the main WAD picker there is an optional picker for PWADs, add-on
WAD files with extra maps or content. You can select several; they load on
top of the main WAD in selection order using the engine's `-file` option.
Two vanilla-engine caveats:

1. PWADs need a full IWAD (registered, retail, Freedoom, and so on). The
   shareware `doom1.wad` refuses add-on files by design; the setup screen
   catches that combination before starting.
2. Plain `-file` loading cannot fold a PWAD's replacement sprites and
   flats into the game; that is a vanilla WAD-loader fact. For total
   conversions that replace graphics, tick "total conversion (merge)"
   next to the PWAD picker: it uses the restored `-merge` loader instead,
   which handles them properly. Plain map and level PWADs are fine either
   way.

DeHackEd is fully supported. DeHackEd patches (.deh files) are how classic
mods change monster behavior, weapon stats, and game text. The build
restores the parser from Chocolate Doom (doomgeneric had deleted it while
keeping all the integration code), which enables all of the following:

1. A .deh file picker next to the PWAD picker. Patches apply in selection
   order via the engine's `-deh` option.
2. PWADs that carry a DEHACKED lump have it applied automatically.
3. The HACX 1.2 standalone IWAD works: the engine recognizes `hacx.wad`
   and loads its built-in DEHACKED lump by itself.
4. Freedoom's built-in DEHACKED lump now applies, so its texts are correct.
5. The ORIGINAL 1996 `chex.wad` IWAD, if you supply it yourself, works
   when you also add its required patch through the picker with the exact
   filename `chex.deh` (files keep their names for this reason). The Chex
   Quest Trilogy button needs none of this; it ships its own patch.
6. Load order matches classic behavior: the IWAD's own patch first, then
   your .deh files, then PWAD DEHACKED lumps.

A malformed patch stops the engine with a parse error, which the page shows
in its red error box including the offending line.

## One-click free games

If you answer yes to the freeware pack when running `install.sh`, the setup
screen shows a row of buttons that load a game in one click, with no files to
hunt down. The games are downloaded next to the build (never into any
repository) and packed as data the page loads locally, so this still works
over `file://` with no server. Each game only occupies memory while you are
actually playing it.

- Doom Shareware, Freedoom Phase 1, Freedoom Phase 2, and HACX 1.2 load
  directly as their own IWADs.
- The Chex Quest Trilogy button is Chex Quest 3: Vanilla Edition (Melodic
  Spaceship, 2024), a self-contained backport of all three Chex Quests to
  this exact engine class, loaded as its own IWAD with the plain-DeHackEd
  patch its readme prescribes for Chocolate-class engines. The title
  screen says Chex Quest 3 because that is the game it is built from; the
  EPISODES are the individual quests (Episode 1 is Chex Quest, Episode 2
  is Chex Quest 2, Episode 3 is Chex Quest 3's campaign), picked from the
  New Game menu. Chex Quest was
  a freeware cereal promotion, and Chex Quest 3 was made officially free by
  General Mills in 2019; the backport's readme is installed in the pack
  folder.
- Harmony loads as a total conversion over Freedoom Phase 2 the same way.
- WolfenDoom: First Encounter (Laz Rojas' faithful recreation of the
  Wolfenstein 3D demo episode) loads as a total conversion over Freedoom
  Phase 2. It is a fan work using id's own Wolfenstein designs, distributed
  with the author's stated permission; his readme is installed in the pack
  folder, as his distribution terms ask.
- STRAIN (1997, Alpha Dog Alliance) loads as a total conversion over
  Freedoom Phase 2, with its extensive DeHackEd patch applied. Its
  distribution terms permit free electronic distribution provided the text
  file and the entire package are included unmodified, so the pack stores
  the complete original archive untouched alongside the loader files.

Loading a free game replaces anything you picked by hand above. If a button
reports the game is missing, re-run `install.sh` and answer yes to the
freeware pack (it only downloads what is not already there).

(The ORIGINAL Chex Quest 3 release is a ZDoom-engine game, Hexen map
format and all, which a vanilla engine cannot run. That is exactly why the
pack ships the Vanilla Edition backport above instead of the original.)

Merging total conversions is possible because the build also restores the
engine's `-merge` support (see
[What is patched in the engine source](ENGINE-PATCHES.md#what-is-patched-in-the-engine-source)),
which folds a PWAD's sprites and flats into the IWAD the way the classic
deutex tool did. This is what lets Harmony, WolfenDoom, and STRAIN look
right rather than showing Freedoom graphics. The same loader is available
for your own files: tick "total conversion (merge)" next to the PWAD
picker.

A few famous total conversions are linked from the setup screen as reading
material but deliberately NOT offered as downloads: Aliens TC (1994),
Batman Doom (1999, ACE Team), and Star Wars for Doom II (1998). All run on
this engine class, but all are based on film and comics properties, so
their licensing is murkier than the officially freeware pack above. The
page links where to read up (Doom Wiki articles, and the Doomworld archive
page for Star Wars) so players can research and decide for themselves; if
obtained, they load through the PWAD picker with the total-conversion box
ticked (Batman Doom also wants its .deh file).

One format caveat that neither limit removal nor DeHackEd changes: this
engine only understands VANILLA map behavior. Many modern community WADs
(including most slaughter megawads such as Cleanout) are built in the Boom
format and need a Boom-compatible port. On this engine, Boom-only switch
and walk triggers silently do nothing (breaking progression), and stepping
into a sector with a Boom-only sector type stops the game with
"P_PlayerInSpecialSector: unknown special". Pick WADs whose readme says
vanilla, limit-removing, or complevel 2/3; "Boom" or "complevel 9" WADs are
out of scope for this engine.
