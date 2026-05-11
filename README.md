# MCHUD — Minecraft style HUD for Garry's Mod (LJE)

A Minecraft inspired HUD that runs through **lj-expand (LJE)** instead of the
standard GMod addon system. You get the MC heart row, hotbar, XP bar, armor,
hunger, bubbles, and crosshair — visible only on your client.

> **What's the point?** It's just for fun. Your friends can see "this guy is
> playing Garry's Mod with a Minecraft HUD" if they take a screenshot of your
> screen, but the server doesn't know anything is happening on your end. No
> server interaction, no anti-cheat trip (on most servers — see safety notes).

---

## Requirements

- **Garry's Mod** (64-bit)
- **lj-expand** installed and working (https://github.com/lj-expand/lj-expand)
- **ljeutil** installed in your `.lje_scripts` folder
  (https://github.com/Eyoko1/lje-util)
- **The MCHUD texture pack** (2 PNG files — see below)

---

## Installation

### 1. Install ljeutil (if not already)

```
cd %USERPROFILE%\.lje_scripts
git clone https://github.com/Eyoko1/lje-util ljeutil
```

The folder name **must** match `ljeutil` (no `lje-util` with a dash).

### 2. Install MCHUD

```
cd %USERPROFILE%\.lje_scripts
git clone https://github.com/YOURNAME/mchud
```

Or download the ZIP and extract so the structure is:

```
%USERPROFILE%\.lje_scripts\mchud\
  ├── info.toml
  ├── preinit.lua
  ├── main.lua
  └── README.md
```

### 3. Install the texture pack

> **Why isn't this automatic?** I deliberately don't auto-download textures.
> Anti-cheat systems on bigger servers monitor file writes to
> `garrysmod/materials/` — that's a classic dropper-malware behavior pattern
> and will get you banned faster than the HUD itself. Install once, manually,
> done.

You need two PNG files at:

```
<Steam>\steamapps\common\GarrysMod\garrysmod\materials\mc_hud\icons.png
<Steam>\steamapps\common\GarrysMod\garrysmod\materials\mc_hud\widgets.png
```

These come from Minecraft's official assets. Common sources:

- The original v8 GMod-only port shipped them in an addon — if you have that
  addon installed, the files are already there
- Search "minecraft icons.png widgets.png" on a texture archive site
- Or extract from a Minecraft `assets/minecraft/textures/gui/` folder

Once installed, launch GMod with LJE — the HUD will appear automatically.
If the textures aren't found, MCHUD logs a warning to the LJE console and
draws nothing (no crash).

---

## Configuration

Open `main.lua` and look at the top:

```lua
local DEBUG = true   -- set to false for "quiet" public release
```

Set this to `false` once you confirm everything works. It silences the
`[MCHUD]` console messages so you don't spam the LJE console during play.

---

## Safety notes (please read before sharing)

### What MCHUD does NOT do

- ❌ **Does not touch DLib's hook table.** It bypasses DLib by capturing the
  native `hook` table at preinit time. DLib still works, MCHUD still works,
  no one steps on anyone.
- ❌ **Does not detour engine functions.** No `surface.SetMaterial` wrapping,
  no `render.SetScissorRect` overrides. All bait removed.
- ❌ **Does not download files at runtime.**
- ❌ **Does not register fake console commands.**
- ❌ **Does not iterate other addons' hooks** to find/remove things.

### What MCHUD does that's still detectable

- ✅ Reads `lp:Frags()`, `lp:WaterLevel()`, `lp:GetWeapons()` — completely
  normal client-side reads, no signal value
- ✅ Hides the stock HL2 HUD via `HUDShouldDraw` — also normal, every HUD
  addon does this
- ✅ Captures 1-9 keys + scroll wheel via `PlayerBindPress` /
  `InputMouseApply` — same pattern as MCHUD's predecessor and any other
  weapon-switch addon

The only thing that is "louder than nothing" is the `HUDShouldDraw` filter
list. If a server explicitly enforces "don't hide my HUD elements", they
could detect that. In practice nobody does this.

### When NOT to use MCHUD

- ❌ **Servers with strict CAC or custom anti-cheat**: even though MCHUD
  itself is clean, LJE's mere presence in the process is detectable by
  some kernel-mode anti-cheats. Don't gamble.
- ❌ **Competitive/ranked servers**: anything that looks like an addon you
  didn't get from Workshop is suspicious to admins reviewing screenshots.
  Even if the script is innocent, **explaining why your HUD looks like
  Minecraft isn't worth it.**
- ✅ **Sandbox / DarkRP / TTT casual / single-player**: have fun.

---

## Troubleshooting

### "Pink/black checkerboards where the icons should be"

The texture pack isn't installed. Check
`garrysmod/materials/mc_hud/icons.png` exists.

### "I can't see the XP bar fill (just the dark background)"

This was the v8 bug. v1.0 should fix it because we draw via
`hook.pre("ljeutil/render", ...)` instead of `HUDPaint`. If you still see
it, check that ljeutil is actually loaded (`lje console` should show
`[ljeutil] loaded` at startup).

### "The hotbar shows weapons but pressing 1-9 still opens the HL2 selector"

Some gamemodes override `PlayerBindPress`. MCHUD returns `true` to
suppress the default handling, but if a higher-priority hook runs first
and consumes the bind, ours never fires. Try `bind 1 "lastinv"` etc. as
a workaround on those gamemodes.

### "Death overlay never goes away"

Click `+kill` in console once. It's a v1.0 limitation — there's no
clickable button yet (vgui in LJE is fragile).

---

## Roadmap

- [ ] Death screen with pure-draw clickable buttons
- [ ] Total master on/off toggle (one keybind to disable everything)
- [ ] Optional in-water actual damage simulation (off by default)
- [ ] Local XP persistence via `lje.data` so kills don't reset on map change

---

## Credits

- Original GMod-only HUD: yourname / community
- LJE: yogwoggf — https://github.com/lj-expand/lj-expand
- ljeutil: Eyoko1 — https://github.com/Eyoko1/lje-util
- gilbhax (rendering pattern reference): yogwoggf — https://github.com/lj-expand/gilbhax
- Minecraft textures: © Mojang AB

## License

Do whatever you want with this code. Don't sell it. Don't blame me if it
gets you banned.
