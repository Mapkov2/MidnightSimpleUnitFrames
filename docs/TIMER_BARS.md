# Timer bars

The Castbar page includes **Other timer bars** for Breath, Fatigue, Feign Death,
Battle Start and Group Countdown. Every timer starts disabled. Enabled bars use
the Player castbar's texture, background, border, artwork, font and text layout.
Each timer has its own color, position and optional size, and may name its own
bar and background texture (SharedMedia); an empty choice follows the castbar
and stores no override.

Each timer also has its own text settings, mirroring the castbar's Spell Text
and Time Text controls: position preset, size and X/Y offsets for the timer
label and for the time text, a font for the time text, and the time format
(Remaining, Elapsed, Elapsed / Total, Remaining / Total, in whole seconds and
`m:ss` from one minute). An empty position, a size of 0 and an empty font
follow the Player castbar; the offsets apply once a text has its own position,
and the time offsets sit on the castbar's 2 px edge padding. Low-time warning is optional and does not warn while a
mirror timer refills.

All timers live in the single **Other timer bars** section. Each timer has a
tab (`W.SegmentTabs`, like the Bars page's absorb tabs) holding its Enable
switch and settings; the tabs and the timer chooser of the Castbar preview
share one selection (`M.castbarTimerSelection`, menu state only). Clicking a
tab switches the menu preview to that timer and turns on **Preview timer
bars**, so the enabled bars appear at their saved screen positions; a disabled
timer has no live bar and shows in the menu preview only. An exact search link
shows the tab its control sits on.

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
  castbar renderer and owns the independent sample and drag behavior. A timer's
  own text settings reach that renderer through a view of the profile
  (`TextSource`): the view answers the Player castbar's text keys
  (`castbarPlayerSpellNamePosition`, `castbarPlayerTimeFont` and their siblings)
  with the timer's choices and reads every other key from the profile, so the
  castbar renderer itself is unchanged and the Player castbar's keys are never
  written. The time format is painted by the timer (`Bars.Paint`).
- `Pages/MSUF_Menu2_TimerBars.lua` adds controls and the independent preview
  chooser to the existing Castbar page.
- Idle cost: only the events of enabled timers are registered (mirror events
  for Breath, Fatigue and Feign Death; `START_TIMER` and `STOP_TIMER_OF_TYPE`
  for Battle Start; those two plus the player countdown pair for Group
  Countdown), with `PLAYER_ENTERING_WORLD` while any timer is enabled and
  `PLAYER_REGEN_DISABLED` only during preview or Edit Mode. With every timer
  disabled the driver holds no event after the first world entry.
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

Offline regressions cover the runtime lifecycle, per-timer event registration,
own textures, own text settings, refill, pause/resume, expiry, native restoration, secret
rejection, independent preview, menu controls, timer selection and drag
persistence. Live-client visuals, combat/taint and real swimming,
Feign Death and battleground/countdown events still require in-game acceptance.
