# Changelog

## Unreleased - EQoL-Inspired Unit Frame / Group Frame Additions

### Aura Filtering

- Shared Global Ignore List now applies to boss frames.
- Boss aura menu now edits the shared ignore categories directly.
- Boss/native aura rendering now respects shared ignore settings consistently.
- Aura ignore hash cache is now per-table and weak-keyed to avoid stale global cache state.
- Group aura blacklist now supports `HEALER_HOTS`.

### Group Frame Spell Indicators

- Missing spell indicators now work in live group frames, not only in preview.
- Missing number indicators now show `0` in live frames.

### External Defensive Auras

- Added External DR percent text for defensive external auras.
- DR percent text is event-driven like EQoL:
  - reads `aura.points[1]`
  - no tick manager
  - no `OnUpdate`
  - no duration/expiration percentage calculation
- Added External DR preview text with sample `75%`.
- Added External DR controls:
  - show/hide DR percent
  - font size
  - anchor
  - X/Y offset

### Group Border

- Added optional border around the whole group frame block.
- Added Group Border controls:
  - enable/disable
  - thickness
  - padding
  - color
- Added Group Border copy/export support.
- Fixed live Group Border positioning with proper UI scale handling.
- Group Border now ignores stale/hidden frames and only uses real visible live units.
- Group Border is now previewed in:
  - multi-frame group preview
  - options mock preview

### Validation

- `luac -p` passed for all addon Lua files.
- `git diff --check` passed; only existing CRLF warnings were reported.
