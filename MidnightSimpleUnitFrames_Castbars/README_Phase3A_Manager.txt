Phase 3A (v2) — Castbar Manager scaffold (NO behavior change)

What this patch does:
- Adds Castbars/MSUF_CastbarManager.lua
  * Shared scheduler/pump with cold-idle (no OnUpdate when empty).
  * Does NOT drive any castbar unless some other module explicitly calls:
      _G.MSUF_CB_Register(frame)

- Updates MidnightSimpleUnitFrames_Castbars.toc to load the manager file.

What this patch does NOT do (by design):
- No rewiring of player/target/focus/boss castbars.
- No time text changes, no interrupt feedback changes, no color changes.

Next step (Phase 3B):
- Move ONE unit (target) to use MSUF_CB_Register/Unregister, but keep Driver/Apply behavior identical.
