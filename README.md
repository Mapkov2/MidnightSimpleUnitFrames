# Midnight Simple UnitFrames (MSUF)

Lightweight, minimal **unitframes + castbars + auras** for World of Warcraft, with a strong focus on **clean visuals**, **high configurability**, and **performance-friendly, event-driven updates**.

---

## Highlights

### Unitframes
- Player / Target / Focus / Pet / Target-of-Target / Boss frames
- Per-frame sizing & positioning
- Flexible text modes (name / HP / power), font sizing, outlines
- Color systems (class colors, reaction colors, custom overrides)
- Optional indicators (e.g. leader/assist, raid marker, status text like AFK/DND/DEAD)

### Castbars
- Player / Target / Focus / Boss castbars
- Interruptibility visuals, outlines, text settings
- Edit-mode previews + live positioning
- Designed to be **secret-safe** and compatible with modern Blizzard timing APIs

### Auras 2.0
- Target / Focus / Boss auras
- Filters (mine-only, boss auras, dispellable/stealable highlighting, etc.)
- Configurable layouts (rows, growth, stacking/splitting, spacing)
- Optional cooldown text styling (bucket colors / warning thresholds)

### Profiles & Import / Export
- Profile system for quickly switching setups
- Import/Export via copy-paste strings (supports **legacy** formats and newer formats)

---

## Installation

1. Download the latest release (or clone the repo).
2. Put the folder into:
   - `World of Warcraft/_retail_/Interface/AddOns/`
3. Ensure the main folder name matches the addon folder (as shipped).
4. Restart WoW (or `/reload`) and enable **Midnight Simple UnitFrames** in the AddOns list.

---

## Usage

### Open settings
- Use the in-game settings panel (AddOns → MSUF), or the addon’s menu entry if present.

### Slash commands
- `/msuf` – open the MSUF menu / settings
- `/msuf reset` – reset frame positions/visibility to defaults
- `/msuf fullreset` – factory reset (all profiles & settings)

*(Exact command set may expand over time — the addon also prints help in-game.)*

---

## Performance Philosophy

MSUF aims to keep updates **event-driven**, coalesced, and lightweight:
- Avoid unnecessary OnUpdate loops where possible
- Coalesce bursty events (e.g. target swapping) into a single refresh pass
- Keep UI building lazy (options are built when opened)

---

## Contributing

PRs and issues are welcome.

If you report a bug, please include:
- A short description + how to reproduce
- Your WoW version/client
- Any relevant addon settings (screenshots help a lot)
- The exact Lua error message (if any)

---

## Credits

Built and maintained by the MSUF project.

Huge thanks to:
- The WoW UI / addon community
- Everyone providing testing feedback and ideas

---

## Links

- GitHub: **(your repo link here)**
- Issues: use the GitHub Issues tab
