-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.4 Beta 2",
    previousVersion = "5.4 Beta",
    rangeLabel = "5.4 Beta -> 5.4 Beta 2",
    entries = {
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
                        "Improved Group Frame bar outline rendering so preview and live frames use the same outside-outline behavior as Unit Frames.",
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
        {
            version = "5.31",
            date = "2026-05-18",
            sections = {
                {
                    title = "Patch Release",
                    bullets = {
                        "Fixed a critical group-frame Preserve HP color crash in Midnight when background frame colors are returned as secret numbers.",
                        "Reverted the delayed range-fade alpha repair performance optimization so layered range alpha is repaired immediately again while range state is unchanged.",
                        "Bundled the full 5.3 release notes with this patch release so the in-game changelog still includes the complete 5.3 release.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
