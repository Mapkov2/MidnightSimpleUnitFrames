-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "F3CAFE784ADCC07531E81C3CA93F1796797D1C866DFDAF27727B845ECDCE1ACF",
    currentVersion = "6.5-beta3",
    historyFromVersion = "6.5-alpha17",
    previousVersion = "6.5-beta2",
    rangeLabel = "6.5-beta2 -> 6.5-beta3",
    entries = {
        {
            version = "6.5-beta3",
            date = "2026-09-18",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "New factory default profile on every client. First login, \"Reset profile\" and \"New profile\" all start from it.",
                        "Factory castbars fill left to right. Existing profiles keep their direction.",
                        "The factory cleanse border detects \"Dispellable by group\" instead of every debuff with a dispel type.",
                        "Factory target buffs and debuffs sit on the same line; player and target aura positions follow the new profile.",
                        "WoW Forever: hunter pet happiness shows on the pet frame.",
                        "WoW Forever: Fonts page option to show the full character name, the first name or the surname.",
                        "WoW Forever: group frames offer Party and Raid only.",
                        "MSUF versions are now per game client. WoW Forever and the Classic clients report 6.5; Midnight keeps its own Retail version. /msuf clientinfo prints the running version.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "First login and \"Reset profile\" received the code defaults instead of the factory profile. Both start from the factory profile again, including Focus Target.",
                        "The class resource bar in the Unit Frames preview and the Class Resources preview sits where the live bar sits. It was drawn the bar height plus 6 px too high.",
                        "WoW Forever: the menu preview backgrounds (Silvermoon and the stone scenes) no longer stay black. Other clients fall back the same way when a scene fails to load.",
                        "The addon version is read once at load instead of on every version display, version check and analytics pass.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
