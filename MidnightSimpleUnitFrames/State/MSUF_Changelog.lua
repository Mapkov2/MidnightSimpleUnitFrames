-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-alpha7",
    previousVersion = "6.0-alpha6",
    rangeLabel = "6.0-alpha6 -> 6.0-alpha7",
    entries = {
        {
            version = "6.0-alpha7",
            date = "2026-06-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added the MSUF Edit Mode Logo Wake intro using the high-resolution MSUF logo asset.",
                        "Added a CurseForge-only release path so Alpha 7 can be published without also uploading to Wago.",
                    },
                },
                {
                    title = "Edit Mode",
                    bullets = {
                        "Updated the logo intro so the logo fades in smoothly, gets a brief cyan wake glow, then lets the ring trace run once and close.",
                        "Kept the intro animation scoped to the Edit Mode opening sequence; its OnUpdate is removed again when the intro stops.",
                    },
                },
                {
                    title = "Release And Notes",
                    bullets = {
                        "Release name: MSUF_6.0A7.",
                        "Bumped VERSION and addon metadata to 6.0-alpha7.",
                        "This tag is intentionally an alpha build; use 6.0-alpha7 as the publish tag.",
                        "Alpha 7 is intended for CurseForge-only publishing.",
                    },
                },
                {
                    title = "Alpha Testing Notes",
                    bullets = {
                        "This is an alpha build for the 6.0 branch. Export important profiles before testing.",
                        "Please test opening and leaving Edit Mode repeatedly and verify the logo intro does not continue running after Edit Mode closes.",
                        "Please test opening Edit Mode shortly before/after combat to confirm no combat overhead or lingering animation state.",
                    },
                },
            },
        },
        {
            version = "6.0-alpha6",
            date = "2026-06-29",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added party targeted spell indicators that can show enemy nameplate casts on the targeted party frame, with icon stack, placement, timer text, and time-based text color controls.",
                        "Added optional Northern Sky Raid Tools nickname integration for unit-frame display names.",
                        "Improved profile import/export and migration handling, including the new MSUF4 compact profile format and better fallback decoding for older MSUF2/MSUF3 profile strings.",
                        "Added the bundled in-game changelog prompt so users can open release notes from the dashboard after updating.",
                    },
                },
                {
                    title = "Group Frames And Indicators",
                    bullets = {
                        "Added party-only targeted spell tracking for enemy casts, including cast/channel pickup, retarget verification, cooldown text, and per-party-frame icon placement.",
                        "Added Targeted Spells controls to Group Indicators with enable mode, icon size/count/layer, anchor/growth, offsets, cooldown text, and timer color thresholds.",
                        "Updated group-frame defaults and configuration so targeted spell settings are carried by the party profile scope.",
                        "Improved group preview rendering for targeted spell/status indicator placement and native preview refreshes.",
                    },
                },
                {
                    title = "Profiles, Imports, And Defaults",
                    bullets = {
                        "Added MSUF4 profile export strings while keeping import compatibility for MSUF3 and legacy MSUF2 variants.",
                        "Improved compact profile decoding by trying Blizzard decompression, direct CBOR, and LibDeflate-backed fallbacks where available.",
                        "Added profile translation and normalization for older 6.0 alpha profile layouts, including aura geometry, text/name shortening aliases, status indicator fields, and group-frame scope fields.",
                        "Hardened profile runtime apply calls so one apply error is captured instead of breaking the whole profile operation.",
                    },
                },
                {
                    title = "Menu, Assistant, And Integrations",
                    bullets = {
                        "Added NSRT nickname resolver support with combat-safe refresh behavior and cache updates when NSRT nickname data changes.",
                        "Expanded Assistant parsing and registry coverage for aura style/filter commands, group aura lane geometry, targeted spell controls, global bar settings, and base global options.",
                        "Improved dashboard and nav-rail behavior, including hover scale defaults and typewriter/changelog handling.",
                        "Clarified Global Bars texture inheritance: unit scopes keep Shared textures while group-frame scopes can override textures and gradients.",
                        "Temporarily disabled dispel/purge border controls for 12.1 PTR until native AuraContainer exposes the needed detection path again.",
                    },
                },
                {
                    title = "Fonts, Text, And Visuals",
                    bullets = {
                        "Improved font path probing and safe font fallback resolution for missing or unavailable fonts.",
                        "Updated text layout/status paths to handle layer frames, status fonts, name shortening, and profile-translated text fields more consistently.",
                        "Refined castbar, class power, aura popup, group preview, and Edit Mode HUD rendering details.",
                        "Updated superellipse media assets used by the rounded frame visuals.",
                    },
                },
                {
                    title = "Release And Notes",
                    bullets = {
                        "Release name: MSUF_6.0A6.",
                        "Bumped VERSION and addon metadata to 6.0-alpha6.",
                        "Regenerated the in-game dashboard changelog data for Alpha 6.",
                        "Hardened the release workflow and Wago upload step so alpha metadata, alpha tags, and A-style alpha release names cannot be uploaded to Wago as stable/release.",
                        "This tag is intentionally an alpha build; use 6.0-alpha6 as the publish tag so Wago receives stability = alpha, CurseForge receives an alpha release type, and GitHub marks the release as prerelease.",
                    },
                },
                {
                    title = "Alpha Testing Notes",
                    bullets = {
                        "This is an alpha build for the 6.0 branch. Export important profiles before testing.",
                        "Please test Targeted Spells in 5-player party content with enemy nameplates enabled, especially casts that retarget or channel.",
                        "Please test importing older Alpha 2 through Alpha 5 profile strings, especially profiles with custom aura positions, fonts, textures, and group-frame text settings.",
                        "Please test NSRT nickname display with NSRT global nicknames enabled and disabled.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
