-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-alpha6",
    previousVersion = "6.0-alpha5",
    rangeLabel = "6.0-alpha5 -> 6.0-alpha6",
    entries = {
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
        {
            version = "6.0-alpha5",
            date = "2026-06-28",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added reverse cooldown swipe options for aura icons, including defaults, profile export normalization, previews, and Assistant/menu registry coverage.",
                        "Improved Aura Style and Aura Filters menu scope handling with clearer shared-vs-custom override controls for unit frames and group frames.",
                        "Fixed castbar channel and empowered preview/runtime behavior after the Alpha 4 castbar pass.",
                        "Fixed castbar previews so player/target/focus/boss preview refreshes and Blizzard player castbar suppression behave more reliably.",
                    },
                },
                {
                    title = "Aura Menu And Assistant",
                    bullets = {
                        "Added cooldown swipe direction controls for unit and group aura lanes.",
                        "Updated shared aura previews to distinguish normal and reverse swipe samples instead of grouping them only by icon size.",
                        "Added shared/custom override bars for aura style and filter pages so inherited settings are easier to see and reset.",
                        "Expanded Assistant coverage for aura style/filter settings and group aura lane controls.",
                    },
                },
                {
                    title = "Castbars",
                    bullets = {
                        "Hardened castbar preview refreshes and removed fragile preview driver state.",
                        "Fixed channel and empowered castbar preview updates, including stage blink handling and safer color/option lookups.",
                        "Stopped writing addon-owned suppression fields onto Blizzard castbar frames; MSUF now suppresses Blizzard player castbar events directly when MSUF owns the player castbar.",
                        "Removed unsafe SetOnUpdateMode calls from castbar runtime paths.",
                    },
                },
                {
                    title = "Release And Notes",
                    bullets = {
                        "Release name: MSUF_6.0A5.",
                        "Bumped VERSION and addon metadata to 6.0-alpha5.",
                        "Regenerated the in-game dashboard changelog data for Alpha 5.",
                        "This tag is intentionally an alpha build; the release workflow maps alpha tags to Wago alpha stability, CurseForge alpha release type, and GitHub prerelease.",
                    },
                },
                {
                    title = "Alpha Testing Notes",
                    bullets = {
                        "This is an alpha build for the 6.0 branch. Export important profiles before testing.",
                        "Please test aura cooldown swipe direction on player, target, focus, boss, party, and raid frames.",
                        "Please test normal casts, channels, empowered casts, castbar previews, and switching between Blizzard and MSUF player castbar ownership.",
                    },
                },
            },
        },
        {
            version = "6.0-alpha4",
            date = "2026-06-27",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Release name: MSUF_6.0A4.",
                        "Aura style editing now separates shared layout inheritance from per-unit text style overrides, so individual frames can adjust aura text without cloning all aura layout data.",
                        "Unit, group, and shared aura previews now show cooldown and stack text placement more accurately, including per-lane cooldown anchors.",
                        "Assistant followups and aura registries now cover more natural language commands for aura lanes, unit aura settings, and text-area adjustments.",
                        "Boss frame previews refresh more reliably outside encounters, including when reopening the unit-frame page.",
                    },
                },
                {
                    title = "Aura Style And Preview",
                    bullets = {
                        "Added cooldown text anchor support for shared, buff, and debuff aura lanes in the Auras3 model, edit-mode preview path, live unit-frame compiler, and Auras menu controls.",
                        "Added sparse visual override normalization so inherited aura layout keys are not treated as per-unit style overrides unless the scope actually customizes text or style behavior.",
                        "Rebuilt unit and group aura style controls into focused preview, text feature, stack-count, cooldown text, and behavior sections.",
                        "Shared aura previews now group frame samples by actual configured icon size and label the affected frame group instead of showing one generic preview.",
                        "Added scope-aware cooldown timer formatting so Shared, unit, and group aura styles can choose below how many remaining seconds decimal text is shown; live aura text still uses Blizzard's C-side DurationTextBinding/NumericRuleFormatter path.",
                        "Group aura style controls now expose cooldown and stack text anchors, offsets, dynamic scaling, tooltip, sorting, and player-aura preference in collapsible sections.",
                    },
                },
                {
                    title = "Assistant And Menu",
                    bullets = {
                        "Improved followup parsing for bare exact-number edits such as \"set to 12\" and for applying the previous HP/name/power text adjustment to another text area.",
                        "Expanded aura assistant registry coverage for cooldown text anchors, lane style values, use-shared-style behavior, and unit aura lane commands.",
                        "Added larger change/reload guidance for assistant-driven changes that may need a UI reload.",
                        "Refined assistant context handling from the previous local commit, including no-match resolution, geometry followups, edit-mode previews, and registry exact aliases.",
                        "Updated the Boss frame preview copy and refresh logic so previewed boss frames are not left hidden after menu navigation.",
                    },
                },
                {
                    title = "Release And Notes",
                    bullets = {
                        "Bumped addon metadata from 6.0-alpha3 to 6.0-alpha4 and VERSION from 6.0-alpha2 to 6.0-alpha4.",
                        "Regenerated the in-game changelog data from this changelog for the A4 package.",
                        "Kept the existing release automation path compatible with alpha publishing by using the 6.0-alpha4 publish tag and MSUF_6.0A4 as the release name.",
                    },
                },
            },
        },
        {
            version = "6.0 Alpha 3",
            date = "2026-06-27",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added timer-based aura color work after Alpha 2.",
                        "Improved assistant context, geometry followups, exact alias handling, edit-mode controls, and preview routing.",
                        "Updated castbar, aura, and assistant release notes after the Alpha 3 packaging pass.",
                    },
                },
                {
                    title = "Notes",
                    bullets = {
                        "Alpha 3 was an interim alpha build on the 6.0 branch before the A4 aura style and assistant followup pass.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
