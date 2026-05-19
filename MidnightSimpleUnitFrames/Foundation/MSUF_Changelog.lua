-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.4 Beta 3",
    previousVersion = "5.4 Beta 2",
    rangeLabel = "5.4 Beta 2 -> 5.4 Beta 3",
    entries = {
        {
            version = "5.4 Beta 3",
            date = "2026-05-19",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Added status icon Advanced tabs for Unit Frame and Group Frame status indicators, including extended offsets, layer controls, reset, test mode, and preview actions.",
                        "Added status icon pack discovery from addon Icons folders and bundled the UX Pro status icon pack under MidnightSimpleUnitFrames\\Icons\\UXPro.",
                        "Added support for external Interface\\Icons replacement packs by resolving accessible spell and aura FileDataIDs back to icon paths before rendering.",
                        "Fixed Group Frame status icon menu clipping around the Placement layer controls.",
                        "Improved status icon texture handling across aura previews, aura rendering, healer buffs, spell indicators, focus kick icons, and dropdown previews so replacement packs are used consistently.",
                        "Improved Group Frame heal prediction and absorb test mode so Bars test rendering updates overlay bars without unnecessary live prediction reads while out of combat.",
                        "Refactored low-risk runtime paths for aura commits, target-swap visuals, gameplay apply scheduling, crosshair target callbacks, and boss castbar event registration.",
                    },
                },
            },
        },
        {
            version = "5.4 Beta 2",
            date = "2026-05-19",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Added per-indicator icon pack selection for Unit Frame and Group Frame status indicators.",
                        "Added Group Frame options to hide name text while units are dead or offline.",
                        "Moved heal prediction controls into the Bars pages so Unit Frame and Group Frame bar configuration is grouped consistently.",
                        "Added a global Bar Outline Color for Unit Frames and Group Frames while keeping aggro, purge, dispel, and other indicator colors independent.",
                        "Improved Unit Frame bar outlines so detached, active, and pixel-snapped outline borders render consistently.",
                        "Improved Group Frame bar outline rendering so preview and live frames use the same outside-outline behavior as Unit Frames.",
                        "Fixed Unit Frame range alpha background bleed when layered alpha state changes.",
                        "Fixed Sated aura threshold filters so aura rule changes stay fresh.",
                        "Fixed a Group Frame preview upvalue warning.",
                    },
                },
            },
        },
        {
            version = "5.4 Beta",
            date = "2026-05-18",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Added persistent Menu2 memory so accordion/card open states, pinned previews, dashboard panels, page selectors, scopes, color selectors, and profile import/export choices survive menu rebuilds and reopening.",
                        "Improved Auras2 performance by caching dispel metadata, tracking structural aura changes with epochs, and avoiding repeated filter/sort work when aura structure and configuration are unchanged.",
                        "Reduced Auras2 event/render overhead when the feature or all unit aura modules are disabled, including harder cleanup of inactive containers and private aura state.",
                        "Improved range-fade stability and cost by repairing unchanged layered alpha less often while still clearing stale fade state when range becomes unknown.",
                        "Expanded Menu2 search coverage for toggle-style questions such as enable, disable, show, hide, turn on, and turn off.",
                    },
                },
            },
        },
        {
            version = "5.32",
            date = "2026-05-18",
            sections = {
                {
                    title = "Patch Release",
                    bullets = {
                        "Fixed a group-frame Spell Indicators crash when linked aura rules, such as Restoration Druid Symbiotic Relationship, checked the scan ownership cache before it was in local scope.",
                        "Bundled the 5.31 and 5.3 release notes with this hotfix so the in-game changelog keeps the full recent release context.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
