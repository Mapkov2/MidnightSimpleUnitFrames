-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "6.0 Preview 2",
    previousVersion = "6.0 Preview 1",
    rangeLabel = "6.0 Preview 1 -> 6.0 Preview 2",
    entries = {
        {
            version = "6.0 Preview 2",
            date = "2026-06-01",
            sections = {
                {
                    title = "Preview Channel",
                    bullets = {
                        "Local preview package for the second 6.0 Menu2/Edit Mode test build.",
                        "Version metadata is prepared as 6.0-preview2 for local install testing.",
                        "This remains a preview-only build and is not a stable public release.",
                    },
                },
                {
                    title = "Menu2 Architecture",
                    bullets = {
                        "Split the large Unit Frame page into focused lazy-loaded sections for text, range fade, alpha, and frame visuals.",
                        "Split group-frame preview rendering, handles, rounded masks, text focus, zoom, pan, and specs into dedicated Menu2 modules.",
                        "Added shared Menu2 theme tokens and control gates so dense settings pages can share consistent enabled, disabled, locked, and preview-only states.",
                        "Added group specs and advanced aura specs modules so repeated dropdown, texture, and aura option data is maintained in one place.",
                        "Reworked Menu2 XML load order for the new page, preview, search, and theme modules.",
                    },
                },
                {
                    title = "Search And Guidance",
                    bullets = {
                        "Rebuilt Menu2 search around smaller keyword, alias, routing, and FAQ catalog modules.",
                        "Added FAQ search coverage for common setup, layout, unit, group, aura, visibility, and troubleshooting questions.",
                        "Reduced the large generated search data surface by moving reusable query text and routing behavior into focused files.",
                    },
                },
                {
                    title = "Preview And Interaction",
                    bullets = {
                        "Added reusable zoom and pan helpers for unit and group previews.",
                        "Moved unit-preview runtime and rendering work out of the view shell so preview refreshes are easier to reason about.",
                        "Added dedicated group-preview handle rendering and text-focus helpers for clearer direct manipulation.",
                        "Improved live preview/status rendering for selected unit-frame and group-frame controls.",
                    },
                },
                {
                    title = "Edit Mode",
                    bullets = {
                        "Split Edit Mode popup scale, castbar, and aura popup behavior into dedicated modules.",
                        "Reworked the tooltip edit popup to use the Menu2 visual style, larger action layout, draggable placement, and shared popup scaling.",
                        "Refined Edit Mode HUD, focus, layout, and mover behavior around the slimmer popup model.",
                        "Kept edit popups closer to the same visual and interaction language as Menu2.",
                    },
                },
                {
                    title = "Runtime And Defaults",
                    bullets = {
                        "Added the unit-frame range-fade runtime element and defaulted range fade settings for supported unit frames.",
                        "Removed old dispel overlay/state load paths that no longer match the paused 6.0 aura backend.",
                        "Removed the old Auras3 group-filtering runtime path while keeping the remaining menu/model surfaces.",
                        "Cleaned group indicator, status, visual, spell-registry, metadata, and preview paths around the current 6.0 runtime shape.",
                        "Updated unit-frame alpha, border, prediction, text, metadata, config, and dispatch paths for the new range/visual split.",
                    },
                },
                {
                    title = "Visual Assets And Docs",
                    bullets = {
                        "Added Menu2 HIG and checkbox preview mockups under docs/.",
                        "Added checkbox edge/fill media assets used by the updated Menu2 checkbox treatment.",
                        "Refreshed the minimap icon asset for the preview package.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed range-fade defaults so existing profiles receive the expected per-unit fallback values.",
                        "Fixed tooltip edit popup placement and resizing behavior for the new Edit Mode popup style.",
                        "Fixed Menu2 preview module boundaries so rendering helpers can be reused without rebuilding full page shells.",
                        "Fixed stale load references to removed aura and dispel runtime files.",
                    },
                },
            },
        },
        {
            version = "6.0 Preview 1",
            date = "2026-05-31",
            sections = {
                {
                    title = "Preview Channel",
                    bullets = {
                        "Local preview package for 6.0 Menu2/Edit Mode testing.",
                        "This build is not a public release and is not published to GitHub, CurseForge, or Wago.",
                        "Version metadata is prepared as 6.0-preview1 for local install testing.",
                    },
                },
                {
                    title = "Menu2 Design System",
                    bullets = {
                        "Added a shared Menu2/Edit Mode visual language for buttons, pills, steppers, sliders, section headers, popups, and inspector surfaces.",
                        "Added shared material tokens for shell, rail, host, card, popup, focus, guide, and warning layers.",
                        "Added calmer glass-style popup and card materials with controlled gradients, softer borders, and more consistent depth.",
                        "Added subtle gradient treatment to high-value controls and active states while keeping inactive surfaces quiet.",
                        "Unified widget spacing, compact control sizing, hitboxes, hover states, disabled states, and active-state rendering.",
                        "Reworked checkbox/toggle visuals so they read cleaner against the dark Menu2 surface and do not overpower labels.",
                        "Reduced strong border noise across dense settings pages and moved emphasis to active, hovered, and focused controls.",
                        "Removed redundant left-nav explanatory tooltips; retained tooltips only where they explain hidden, dangerous, or non-obvious behavior.",
                    },
                },
                {
                    title = "Menu2 Focus, Motion, And Feedback",
                    bullets = {
                        "Added a reusable dropdown focus veil so open dropdowns keep attention on the active choice while the rest of the menu subtly recedes.",
                        "Added smoother dropdown fade behavior and fixed close-state flicker from the global dropdown focus handling.",
                        "Added a shared motion layer for short, purposeful transitions: dropdown fade, accordion open/close, popup fade/scale, control hover, and command feedback.",
                        "Added Menu2 header inline feedback for commands, avoiding unnecessary chat spam and interruptive popups.",
                        "Added inline feedback for page reset, group reset, copy actions, copy category selection, profile export/import, edit-mode toggles, layout preset changes, undo, redo, session reset, and combat-locked actions.",
                        "Added command failure feedback for captured Menu2 actions.",
                        "Added safer menu-state migration so old auto-opened text sections from earlier Edit Mode focus requests do not keep reopening.",
                    },
                },
                {
                    title = "Progressive Disclosure",
                    bullets = {
                        "Reworked large Unit Frame and Group Frame sections so common controls appear first and advanced geometry or detail controls stay behind collapsible sections.",
                        "Reduced closed-section clutter by hiding most badges unless the section is open or the badge is decision-critical.",
                        "Reworked Group Frame layout setup around intent-first presets: 5-Player, Raid Grid, and Compact Raid.",
                        "Moved Group Frame layout intent into the top scope bar and removed the redundant extra Layout Intent section.",
                        "Renamed advanced layout details to Geometry so users choose the intent first and tune exact size/spacing only when needed.",
                        "Kept status summaries near active/open sections instead of showing every setting as a permanent pill.",
                    },
                },
                {
                    title = "Menu2 Preview And Direct Manipulation",
                    bullets = {
                        "Connected Menu2 controls to preview/edit focus for unit frame text, power bars, castbars, frame layout, and group-frame layers.",
                        "Hovering relevant Menu2 controls can now highlight the matching preview element instead of forcing users to guess which setting affects which visual part.",
                        "Selecting or editing text slots keeps the preview focus aligned with Name, HP Text, Power Text, left/center/right slots, and related position controls.",
                        "Slider and stepper changes refresh the preview immediately where the runtime supports live preview updates.",
                        "Copy and reset actions now provide visible confirmation in the Menu2 status bar.",
                        "Fixed Menu2 focus requests so browsing pages while Edit Mode is active no longer forces the Text section open unless the user explicitly targeted text from Edit Mode.",
                    },
                },
                {
                    title = "Edit Mode UX",
                    bullets = {
                        "Reconnected Edit Mode with Unit Frame and Group Frame previews so dummy previews and real edit handles use the same selection and positioning state.",
                        "Restored group-frame dummy previews for party, raid, and mythic raid scopes, including behavior when the player is in a real raid group.",
                        "Reworked Edit Mode popups into the Menu2 visual style with shared popup materials, steppers, pills, copy-to actions, reset placement, and close buttons.",
                        "Added a compact inspector-style popup for active frames with X/Y/Width/Height steppers and cleaner actions.",
                        "Added Copy To support for position and size in the Edit Mode popup.",
                        "Kept detached powerbar editing available in the Edit Mode popup while removing redundant Name/HP/Power text editing from the popup.",
                        "Added popup parity between unit frames and group frames so both use the same visual language and interaction model.",
                        "Reworked tooltip edit preview handling so tooltip positioning can be adjusted through a small popup instead of relying only on old drag text.",
                        "Removed loud selection highlighting from Edit Mode and replaced it with calmer focus/dimming behavior where appropriate.",
                        "Kept snap highlight behavior but removed/trimmed unstable snap-guide positioning that caused jitter or visual misalignment.",
                        "Stabilized the Edit Mode inspector so it no longer jumps around while the user is working.",
                    },
                },
                {
                    title = "Group Frame Menu And Preview",
                    bullets = {
                        "Reworked Group Frame top controls to reduce redundancy between scope selection, layout intent, and geometry details.",
                        "Added clearer scope switching feedback for Party, Raid, and Mythic Raid without adding explanatory tooltips.",
                        "Improved Group Frame preview/dummy anchoring so preview blocks match live frame positioning more closely.",
                        "Fixed raid-frame anchor positioning issues where the raid dummy preview could align differently from the live frame anchor.",
                        "Added preview/live parity work for raid and party layouts, including correct behavior while already inside a real raid group.",
                        "Kept group-frame layout presets separate from advanced geometry so users can choose a desired result first and tune details later.",
                        "Cleaned closed Group Frame section headers so they show title and important state only, reducing badge clutter.",
                    },
                },
                {
                    title = "Unit Frame Menu",
                    bullets = {
                        "Reworked Unit Frame top actions for consistent Copy To and Edit Mode behavior.",
                        "Added unit-frame copy feedback for selected target and category changes.",
                        "Added Edit Mode on/off feedback from unit-frame pages.",
                        "Improved live text-slot preview focus for Name, HP, and Power text controls.",
                        "Fixed mismatches between the blue dummy overlay and the real unit-frame preview for selected preview elements.",
                        "Removed range-fade controls from per-unit transparency pages after the 6.0 runtime cleanup moved away from that per-unit UI path.",
                    },
                },
                {
                    title = "Performance And Runtime Tweaks",
                    bullets = {
                        "Continued reducing hot-path work in the 6.0 Unit Frame Core by moving more behavior into compiled specs and targeted dirty masks.",
                        "Reduced disabled-feature overhead so inactive text, visual, indicator, aura, range, and status systems avoid unnecessary event and refresh work.",
                        "Trimmed repeated frame updates in text, prediction, health, power, status, group, and castbar preview paths.",
                        "Split large unit-frame runtime responsibilities into smaller element modules to keep hot updates focused and easier to maintain.",
                        "Removed unused bundled runtime libraries from the packaged addon path where the rewritten 6.0 runtime no longer depends on them.",
                        "Reduced group-frame preview/live refresh amplification by using scope-aware refreshes and preserving dirty-mask intent through public shims.",
                        "Reduced menu rebuild churn by preserving persistent menu state and closing auto-focused sections only when focus was not explicitly requested.",
                        "Added wider use of direct references and guarded calls instead of repeated global/table lookups on frequent paths.",
                        "Improved combat-lock feedback and deferred apply handling so blocked actions return quickly and explain the state inline.",
                        "Kept preview-only work out of live runtime paths where possible, especially for group-frame and unit-frame edit previews.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed dropdown focus animation closing with a dark/light/dark flicker.",
                        "Fixed group-frame raid preview positioning where the dummy preview anchor did not match the live raid-frame anchor.",
                        "Fixed Text sections reopening automatically while navigating Menu2 during Edit Mode.",
                        "Fixed Edit Mode snap-guide instability that caused visible shaking during drag.",
                        "Fixed Edit Mode popup layout and removed old popup paths that no longer matched the Menu2 style.",
                        "Fixed copy/reset/edit actions that previously changed state without clear UI confirmation.",
                    },
                },
            },
        },
        {
            version = "6.0 Alpha 4",
            date = "2026-05-29",
            sections = {
                {
                    title = "Runtime Kernel",
                    bullets = {
                        "Added compiled per-frame hot-event states for health, power, connection, aura, and prediction/absorb dispatch.",
                        "Stored direct update function references for hot and generic event lists, reducing repeated element table and update-key lookups during frame events.",
                        "Added a generic hot-event tail so future elements registered to hot events still run without requiring switch edits.",
                        "Reused unit identity/state reads within a single dispatch token to avoid duplicate UnitExists/UnitIsConnected/UnitIsPlayer style calls when multiple elements handle the same event.",
                        "Fixed combined unit/unitless event owner tracking so both registrations stay unitless-capable through unregister/rebuild paths.",
                    },
                },
            },
        },
        {
            version = "6.0 Alpha 3",
            date = "2026-05-29",
            sections = {
                {
                    title = "Aura Backend Pause",
                    bullets = {
                        "Removed the live 6.0 Auras3 runtime while Blizzard's Midnight aura refactor is still in flux.",
                        "Removed custom unit-frame aura rendering, group aura cache snapshots, group custom aura lanes, Blizzard/private aura anchoring, and aura cooldown text runtime management.",
                        "Kept Auras3 profile data, menu surfaces, edit-mode handles, and unit/group preview configuration so user settings can survive until a new supported backend is ready.",
                        "Group aura-dependent spell indicators, custom corner aura indicators, dispel overlays, and dispel aura borders no longer register live aura runtime work while the backend is disabled.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
