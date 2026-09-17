-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "EABAC9951706E9C483501710F22C2662C0DBBB6B6672F819E9022F24B5A9C7D5",
    currentVersion = "6.5-beta2",
    historyFromVersion = "6.5-alpha16",
    previousVersion = "6.5-alpha18",
    rangeLabel = "6.5-alpha18 -> 6.5-beta2",
    entries = {
        {
            version = "6.5-beta2",
            date = "2026-09-18",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "WoW Forever hour-0 support: Mainline family, camelot detection, Interface 16001, no arena, and the Classic Glass menu only on Forever.",
                        "Detects WoW Forever from the Blizzard_Game Camelot marker and keeps Family and Flavor Mainline.",
                        "/msuf clientinfo prints the client facts needed for Forever bug reports.",
                        "Factory profiles inflate deflate(CBOR) before DeserializeCBOR so Forever can create and import profiles.",
                        "TBC and Mists keep five Arena slots. Forever reports arena as unsupported.",
                        "The Classic Glass menu skin and \"MSUF (Forever Version)\" title show only on Forever.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Missing imported fonts fall back instead of aborting UI construction.",
                        "Profile import validates and stages the string before it creates or switches a profile.",
                        "Era dispel scans keep HARMFUL|RAID.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha18",
            date = "2026-09-13",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed options-menu and Edit Mode startup failures caused by fonts reporting incomplete values during client startup. Font readiness no longer aborts UI construction, and pending applications remain uncached until they are ready.",
                        "MSUF starts and applies profiles without optional integration addons installed. Classic clients no longer require unavailable EllesmereUI or Blizzard Edit Mode adapters.",
                        "Consolidated shared Defaults, ClassPower, aura-menu and preview helpers across Classic clients while preserving their class resources, pet happiness and Arena support.",
                        "Removed redundant protected calls and no-op substitutes so native Lua errors remain visible to BugSack/BugGrabber.",
                        "Corrected shared-helper load order and refreshed menu search indexes for Vanilla, TBC, Mists and Mainline.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha17",
            date = "2026-09-11",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Includes Retail 6.20. The Mainline manifests report 6.20; the Vanilla, TBC and Mists clients carry this alpha.",
                        "Every clickable surface in the options menu answers hover with the same accent outline the section headers use: unit tabs, pills, buttons, dropdowns and the section \"...\" menus.",
                        "Each settings section keeps exactly one on/off switch, on its header. The duplicate copy inside the section body is gone.",
                        "Every menu string is translated in all twelve locales. German, both Spanish variants, French, Italian, Korean, Brazilian Portuguese, Russian and both Chinese variants no longer fall back to English.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "With Rounded Frames on, health backgrounds no longer change opacity at random during instanced combat. The missing-health optimisation stacked a second native mask on the texture the rounded surface already masks; rounded frames keep the value-driven fill and every other frame keeps the cheaper mask.",
                        "The preview's Layers dropdown stays inside its panel and inside the preview. Entering combat view re-flowed its chips across the full preview width behind a narrow panel; the dropdown now owns its width and widens only as far as it needs to stay off the bottom edge.",
                        "The Assistant switches a fade feature on when you set its fade value. \"Set name fade in to 0.25\" used to write the number while Name Text Mouseover stayed off, so nothing visibly changed; the owner now switches on in the same transaction, on every unit frame, and undo reverts both.",
                    },
                },
            },
        },
        {
            version = "6.5-alpha16",
            date = "2026-09-10",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Every settings section now carries its on/off switch, a one-line summary and a \"...\" menu on its header, so a feature can be turned on or off without expanding it and a single section can be reset or copied on its own.",
                        "Options menus read brighter: taller section headers with an accent border when open or hovered, a higher floor for the smallest fonts, and a clearly visible active page in the navigation.",
                        "Switching a frame or a group scope off now dims only its setting sections. The frame picker, the unit selector and the preview stay usable, and Frame Basics is labelled as disabled.",
                        "Unit and Party/Raid pages open with a title naming the frame or scope they edit and an Enable switch for it.",
                        "Previews open on the neutral Studio background instead of the Silvermoon scene, and the Guides layer starts hidden.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "The interrupt-ready indicator counts every interrupt you actually have instead of a single spell, while each client keeps its own era-correct interrupt list.",
                        "With the Castbar border indicator style the ready colour no longer reverts to the normal border colour when the border is rebuilt or recoloured.",
                        "A Guides layer that was switched off no longer comes back lit every time a preview is rebuilt.",
                        "Zoning into a new area rebuilds raid headers once instead of twice, so group frames stop stalling right after a loading screen.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
