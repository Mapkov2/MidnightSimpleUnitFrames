# Timer bars

The Castbar page includes **Other timer bars** for Breath, Fatigue, Feign Death,
Battle Start and Group Countdown. Every timer starts disabled. Enabled bars use
the Player castbar's texture, background, border, artwork, font and text layout.
Each timer has its own color, position and optional size. Low-time warning is
optional and does not warn while a mirror timer refills.

Select **Timer Bars** in the Castbar preview, then choose a timer. This sample
uses a separate frame and the same painter as the runtime; it works with every
live timer disabled. **Preview timer bars** shows enabled bars in their saved
screen positions. MSUF Edit Mode also shows those samples and permits dragging
each one independently. Leaving preview or entering combat ends dragging.

The optional native-bar suppression changes the corresponding mirror frame's
alpha or hides the unprotected TimerTracker bar child. Previous state is kept
in a side table and restored on release. Native parents, scripts,
event registration, sounds and golden countdown numbers remain owned by
Blizzard. By default the custom countdown gives way at Blizzard's 11-second
battleground and 31-second group-countdown transition points; each countdown
can keep its custom bar during the numbers instead.

## Runtime and profile ownership

- `Castbars/MSUF_TimerBars.lua` owns the event subscriptions, public-value
  checks, active state and profile settings under `general.castbarTimers`.
  This key follows the existing castbar ownership rule for partial profile
  import/export and synchronization. Missing settings read as disabled without
  manufacturing profile overrides.
- `Castbars/MSUF_TimerBarVisuals.lua` delegates appearance to the shared player
  castbar renderer and owns the independent sample and drag behavior.
- `Pages/MSUF_Menu2_TimerBars.lua` adds controls and the independent preview
  chooser to the existing Castbar page.
- A 50 ms update runs only while an enabled, unpaused timer is active. Disabled,
  stopped and paused timers have no update script. Mirror timers are recovered
  after entering the world; available native countdown snapshots are recovered
  when enabling a bar. World transitions clear the battleground countdown.

## Verified Blizzard source, 2026-11-10

The source mirror is [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source).
The inspected client snapshots are:

| Client branch | Commit |
| --- | --- |
| `live` | `297d7aaaa736f346b3e036f38ee088eaf7f8c07f` |
| `forever` | `9dc84f0d3bbae1768ac3405b3716000bd93eda06` |
| `classic_era` | `4192ac60067fc55566182291bc67c85dd9b6794d` |
| `classic_anniversary` | `68e0a2ec559d9761dfc4e7f864c3944f9d758a49` |
| `classic` | `e5d9b3a22c3f0f6f41ebac0e454f4969594261cf` |

`Blizzard_MirrorTimer/Mainline/MirrorTimer.lua` and its XML/TOC establish the
Mainline/Forever mirror event, progress and Edit Mode paths. The Classic
clients load `Blizzard_FrameXML/Classic/MirrorTimer.lua` through their matching
FrameXML TOCs. All five clients load `Blizzard_FrameXML/Timer.lua`, which owns
the countdown events, timer-list snapshots and transition markers. `DEATH` and
`FEIGNDEATH` share the custom Feign Death slot and retain the native event label.

Offline regressions cover the runtime lifecycle, refill, pause/resume, expiry,
native restoration, secret rejection, independent preview, menu controls and
drag persistence. Live-client visuals, combat/taint and real swimming,
Feign Death and battleground/countdown events still require in-game acceptance.
