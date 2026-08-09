<div align="center">
  <img src="MidnightSimpleUnitFrames/Media/MSUF_EditModeIcon.png" width="150" alt="Midnight Simple Unit Frames logo">

  <h1>Midnight Simple Unit Frames</h1>

  <p>
    Clean, highly configurable unit frames, group frames, castbars and auras for World of Warcraft Retail.
  </p>

  <p>
    <a href="https://www.curseforge.com/wow/addons/midnightsimpleunitframes"><img src="https://img.shields.io/badge/CurseForge-Download-F16436?style=for-the-badge&logo=curseforge&logoColor=white" alt="Download MSUF on CurseForge"></a>
    <a href="https://addons.wago.io/addons/midnightsimpleunitframes"><img src="https://img.shields.io/badge/Wago-Download-EE3DE0?style=for-the-badge" alt="Download MSUF on Wago Addons"></a>
    <a href="https://discord.gg/2Gf9b2Wprz"><img src="https://img.shields.io/badge/Discord-Community-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Join the MSUF Discord"></a>
  </p>

  <p>
    <img src="https://img.shields.io/badge/Version-6.0%20RC18-38C7F0?style=flat-square" alt="MSUF version 6.0 RC18">
    <img src="https://img.shields.io/badge/WoW-Retail%2012.1-148EFF?style=flat-square&logo=worldofwarcraft&logoColor=white" alt="World of Warcraft Retail 12.1">
    <img src="https://img.shields.io/github/last-commit/Mapkov2/MidnightSimpleUnitFrames?style=flat-square&logo=github" alt="Latest GitHub commit">
  </p>
</div>

> [!IMPORTANT]
> **6.0 RC18 is a prerelease build.** Release candidates continue to use the **Beta** channel on addon platforms until the final 6.0 release.

## What is MSUF?

Midnight Simple Unit Frames (MSUF) is a complete, customizable replacement for Blizzard's unit and group frames. It brings player, target, focus, focus-target, boss, party and raid frames together with castbars, auras and class resources in one consistent interface.

MSUF is made for players who want clear combat information, extensive visual control and a lightweight event-driven runtime. The full configuration UI and the optional Assistant load only when requested.

> **Signature per-frame Fill Direction:** MSUF lets each Unit Frame fill its Health and Power bars horizontally from left to right or right to left, or vertically from bottom to top or top to bottom. This per-frame combination of vertical and mirrored bar layouts is a level of control not currently offered by other unit-frame addons.

## Basic features

- Custom Player, Target, Focus, Focus Target, Pet, Target-of-Target and Boss frames
- Party, Raid and Mythic Raid group frames
- Configurable health, power, absorb and heal-absorb displays
- Per-frame horizontal and vertical Health/Power fill directions in all four directions
- Player, Target, Focus and Boss castbars
- Buffs, debuffs, defensive auras, private auras and spell indicators
- 2D and class-icon portraits with multiple shapes and placements
- Custom name, health, power, status and castbar text
- Class colors, reaction colors, custom colors, gradients, fonts and textures
- Aggro, dispel, purge, range, role, leader, raid-marker and status indicators
- Class Power displays for class resources
- Full Edit Mode positioning, previews, snapping and layer controls
- Profiles, specialization switching and profile import/export
- Searchable options, guided setup and recovery tools
- Optional Masque, LibSharedMedia and Clique integration

## Feature highlights

| Area | Highlights |
| --- | --- |
| **Unit Frames** | Player, Target, Focus, Focus Target, Pet, Target-of-Target and Boss frames with configurable health, power, text, portraits, colors, textures, layers and status indicators. Every frame can fill its Health and Power bars horizontally or vertically in either direction. |
| **Group Frames** | Party, Raid and Mythic Raid layouts with role/status indicators, range fading, spell indicators, healer tools and native private-aura support. |
| **Auras 3** | Blizzard-native 12.1 aura containers, custom spell matching, per-lane filters, icon shapes, cooldown text, growth/layout controls and portrait tracking. |
| **Castbars** | Player, Target, Focus and Boss castbars with interrupt feedback, channel support, configurable text/icons, rounded styling and secret-safe timing paths. |
| **Edit Mode** | Live frame positioning, draggable elements, previews, snapping, layer controls and direct navigation to the matching setting. |
| **Profiles** | Specialization-aware profiles, copy tools and robust import/export including migration from legacy 5.x profiles. |

## More included

- Configurable Class Power displays, including an optional Guardian Druid Ironfur tracker
- SharedMedia textures and fonts, Masque support and Clique compatibility
- Searchable, load-on-demand options with guided setup and recovery tools
- Optional load-on-demand MSUF Assistant for local feature help and safe setting changes
- Twelve included locales: English, German, French, Spanish, Italian, Portuguese, Russian, Korean and Simplified/Traditional Chinese
- Performance-oriented event routing designed to stay quiet when features are disabled

## Install and open

1. Install MSUF through [CurseForge](https://www.curseforge.com/wow/addons/midnightsimpleunitframes) or [Wago Addons](https://addons.wago.io/addons/midnightsimpleunitframes).
2. For a manual installation, keep all three packaged folders together in `World of Warcraft/_retail_/Interface/AddOns`:
   - `MidnightSimpleUnitFrames`
   - `MidnightSimpleUnitFrames_Options`
   - `MidnightSimpleUnitFrames_Assistant`
3. Reload the game and type `/msuf` to open the configuration menu.

The Core addon runs normally without opening Options or the Assistant. Both companions are loaded on demand.

## Compatibility

| | |
| --- | --- |
| **Game** | World of Warcraft Retail |
| **Interface versions** | 12.0.7 and 12.1.0 |
| **Current source version** | 6.0 RC18 |
| **Main command** | `/msuf` |
| **Optional integrations** | Masque, LibSharedMedia, Clique and WagoAnalytics |

## Developer APIs

Only APIs documented in this section are stable integration contracts.
Arbitrary `MSUF_*` globals, frame registries, runtime namespaces and saved
variables are implementation details.

`MSUF.API.Nicknames` V1 lets another addon provide display names for MSUF unit
and group frames without frame hooks. It is event-driven: there is no polling,
ticker or idle `OnUpdate`; providers and nickname refreshes never run in combat.
Changes reported in combat are coalesced and applied once after
`PLAYER_REGEN_ENABLED`.

```lua
local OWNER = "YourAddon"
local PRIORITY = 50
local MSUF = _G.MSUF
local API = MSUF and MSUF.API and MSUF.API.Nicknames

local function ResolveNickname(unit, nativeName, fullName)
    local nickname = YourAddon:GetNickname(unit)
    return nickname ~= nativeName and nickname or nil
end

local function SetNicknameProviderEnabled(enabled)
    if not (API and API.GetVersion() >= 1) then return end
    if enabled then
        API.RegisterProvider(OWNER, ResolveNickname, PRIORITY)
    else
        API.UnregisterProvider(OWNER)
    end
end

local function NotifyNicknamesChanged()
    if API and API.IsProviderRegistered(OWNER) then
        API.NotifyChanged(OWNER)
    end
end
```

Add `## OptionalDeps: MidnightSimpleUnitFrames` when MSUF should load before the
provider. `RegisterProvider(owner, resolver, priority)` accepts an optional
numeric priority; higher priorities run first. Use
`UnregisterProvider(owner)` when the integration is disabled. Call the enable
function once after loading the provider's persisted state, and call the change
notification only when its nickname data changes.

### Edit Mode provider integration

`MSUF_EditModeAPI` V1 lets another addon expose its own movable frames inside
MSUF Edit Mode. The provider keeps ownership of frame creation, saved positions,
profiles, anchors and protected-frame operations; MSUF supplies the mover,
selection, grid/snap, arrow nudge, Undo/Redo and Save/Discard shell.

Feature-detect and register after adding the same optional dependency:

```lua
local EditMode = _G.MSUF_EditModeAPI
if not EditMode or EditMode.GetVersion() < 1 then return end

local ok, reason = EditMode.RegisterElements("YourAddon", {
    {
        id = "main",
        label = "Your Addon Frames",
        group = "Your Addon",
        order = 100,

        getFrame = function()
            return YourAddon.GetMovableContainer()
        end,

        getPosition = function()
            local point, relativeToName, relativePoint, x, y = YourAddon.GetPosition()
            return {
                point = point,
                relativeToName = relativeToName,
                relativePoint = relativePoint,
                offsetX = x,
                offsetY = y,
            }
        end,

        setPosition = function(position, changeReason)
            return YourAddon.SetPosition(position, changeReason)
        end,

        -- Optional links/actions shown by the MSUF-owned popup.
        openSettings = YourAddon.OpenSettings,
        resetPosition = YourAddon.ResetPosition,
    },
})

if not ok then
    print("YourAddon: MSUF Edit Mode registration failed: " .. tostring(reason))
end
```

Each `id` is stable within its owner and represents one independently movable
frame or container. A provider may instead implement the advanced transaction
callbacks `captureState`, `restoreState`, and `movePosition` when a simple
position table is insufficient.

Notify MSUF only after an event changes availability or geometry:

```lua
MSUF_EditModeAPI.RefreshElement("YourAddon", "main")
-- or refresh every registered element owned by the addon:
MSUF_EditModeAPI.RefreshOwner("YourAddon")
```

These are cold event notifications, not per-frame APIs. Registration installs
no polling, ticker, global hook, or idle `OnUpdate`. Configuration writes are
rejected during combat, and providers must enforce their own protected-frame
rules inside callbacks. Dynamic teardown uses
`UnregisterElement("YourAddon", "main")` or `UnregisterOwner("YourAddon")`.

## Support development

If MSUF improves your UI, you can support continued development through any of the links below. These are the same official links shown inside the MSUF Dashboard.

<p align="center">
  <a href="https://www.patreon.com/cw/MidnightSimpleUnitframes"><img src="MidnightSimpleUnitFrames/Media/Masks/Patreon.png" height="42" alt="Support MSUF on Patreon" title="Patreon"></a>&nbsp;&nbsp;&nbsp;
  <a href="https://www.paypal.com/ncp/payment/H3N2P87S53KBQ"><img src="MidnightSimpleUnitFrames/Media/Masks/PayPal.png" height="42" alt="Support MSUF with PayPal" title="PayPal"></a>&nbsp;&nbsp;&nbsp;
  <a href="https://ko-fi.com/midnightsimpleunitframes"><img src="MidnightSimpleUnitFrames/Media/Masks/Ko-Fi.png" height="42" alt="Support MSUF on Ko-fi" title="Ko-fi"></a>
</p>

<p align="center">
  <a href="https://www.patreon.com/cw/MidnightSimpleUnitframes">Patreon</a> ·
  <a href="https://www.paypal.com/ncp/payment/H3N2P87S53KBQ">PayPal</a> ·
  <a href="https://ko-fi.com/midnightsimpleunitframes">Ko-fi</a>
</p>

## Community and feedback

<p align="center">
  <a href="https://discord.gg/2Gf9b2Wprz"><img src="MidnightSimpleUnitFrames/Media/Masks/Discord.png" height="42" alt="Join the MSUF Discord" title="Discord"></a>&nbsp;&nbsp;&nbsp;
  <a href="https://github.com/Mapkov2/MidnightSimpleUnitFrames"><img src="MidnightSimpleUnitFrames/Media/Masks/GitHub.png" height="42" alt="View the MSUF source on GitHub" title="GitHub"></a>
</p>

- Ask questions, share profiles and report gameplay issues on the [MSUF Discord](https://discord.gg/2Gf9b2Wprz).
- Report reproducible bugs through [GitHub Issues](https://github.com/Mapkov2/MidnightSimpleUnitFrames/issues).
- Browse and share community profiles through [Wago](https://wago.io/search/imports/wow/msuf).

When reporting a bug, please include your MSUF version, WoW client version, affected frame and exact reproduction steps.

---

<div align="center">
  Made for players who want powerful frames without a heavy runtime.
</div>
