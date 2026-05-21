-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.4 Beta 9",
    previousVersion = "5.4 Beta 8",
    rangeLabel = "5.4 Beta 8 -> 5.4 Beta 9",
    entries = {
        {
            version = "5.4 Beta 9",
            date = "2026-05-21",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Fixed Group Frame center HP text drifting when the displayed health value changes by anchoring the centered text to a stable full-width text area.",
                        "Fixed Group Frame font outline changes not applying when the font face and size stayed the same.",
                        "Fixed stale Group Frame dispel/debuff visuals after frame retire or reuse so old disease/debuff state no longer hides shields until ReloadUI.",
                    },
                },
            },
        },
        {
            version = "5.4 Beta 8",
            date = "2026-05-20",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Improved Menu2 search so the search box also works as an \"ask\" field for location-style questions such as where to move frames, change fonts, or adjust inline text colors.",
                        "Added generic English and German question handling for menu search, with better ranking for direct controls and sections instead of sending broad \"where/how\" queries to FAQ-style results.",
                        "Reduced menu search idle work by cancelling background indexing when leaving the Search page and rebuilding registry search records only when needed.",
                        "Improved Menu2 performance by avoiding redundant title, subtitle, navigation, status-bar, and search-result refresh work when the visible values did not change.",
                        "Added the first-use Search / Ask intro popover and updated the search placeholder to make natural-language menu search discoverable.",
                        "Fixed Advanced Gameplay menu clipping at smaller widths and scaled UI layouts by stacking Combat Timer, Combat Enter/Leave, Class-specific, and Combat Crosshair controls when space is tight.",
                        "Improved compact widget layout for sliders, switches, toggles, and edit boxes so controls clamp cleanly instead of overlapping or spilling outside their sections.",
                        "Fixed Group Frame preview note clipping by sizing the preview intro area dynamically for translated and wrapped text.",
                        "Added live party and raid previews while editing Group Frame bar settings, without taking over the normal Edit Mode group preview state.",
                        "Added configurable Target-of-Target inline text color modes: Auto, ToT Name Color, Target Name Color, NPC / Type Color, and Default Font Color.",
                        "Updated Target preview rendering and runtime inline text color resolution so the new ToT inline color modes match class, target-name, NPC reaction, NPC type, and default font color behavior.",
                        "Added German menu labels for the new inline color options.",
                    },
                },
            },
        },
        {
            version = "5.4 Beta 7",
            date = "2026-05-20",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Rebuilt Unit Frame and Group Frame dispel visual priority around one visible Highlight Priority order, keeping Dispel, Aggro, Purge, Boss Target, Target, and Focus as the user-facing priority lanes.",
                        "Collapsed legacy Magic, Curse, Disease, Poison, and Bleed custom sorting into the single Dispel visual lane so older profiles no longer keep hidden debuff-type priority state.",
                        "Force-migrated old Unit Frame and Group Frame overlay/debuff priority settings across saved profiles, including stale overlay priority toggles and ordering tables.",
                        "Kept Dispel Border and Dispel Overlay independently enabled and configured while sharing the same resolved debuff winner, so border-only, overlay-only, and combined setups use one consistent priority result.",
                        "Fixed renderer-independent Group Frame dispel highlights so MSUF can still scan and draw priority visuals when Blizzard owns aura icons, while custom aura rendering uses the same priority path.",
                        "Added shared strata/frame-level helpers and separate effect layers for highlight borders, dispel overlays, and debuff stripes so active visual lanes stack predictably.",
                        "Improved live combat refresh for dispel visuals by tracking priority-relevant aura changes, aura cache versions, Bleed enum/fallback resolution, and coalesced refresh queues.",
                        "Reduced redundant Unit Frame and Group Frame border/overlay work by avoiding duplicate scans when trigger, priority, and cache signatures match.",
                        "Simplified the UnitFrame and GroupFrame Dispel Overlay menus by removing separate overlay priority controls while keeping trigger, style, health-only, opacity, and independent enable toggles.",
                        "Updated the Group Frames > Health & Text navigation tooltip so it points users to health colors, bars, power bar, text, Dispel Overlay, Debuff Stripe, and Range Fade.",
                    },
                },
            },
        },
        {
            version = "5.4 Beta 6",
            date = "2026-05-20",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Reworked Unit Frame and Group Frame dispel priority resolution so Magic, Curse, Disease, Poison, Bleed, generic dispel, aggro, purge, and boss-target lanes stay independent instead of collapsing to the first matching type.",
                        "Kept Dispel Border and Dispel Overlay as separate visual lanes with their own trigger, priority, color, and refresh state so live option changes no longer reuse a stale border winner for the overlay.",
                        "Added settings-serial, aura-version, priority-signature, color-revision, and unit-guid cache guards around dispel scans so repeated refreshes are cheaper without keeping stale aura colors or stale priority winners.",
                        "Improved Any Debuff and Any Dispel Type handling so typed color mode and typed priority order can still select the correct highest-priority debuff, including Bleed.",
                        "Added Bleed support to the group-frame dispel color curve for the currently observed Bleed ids.",
                        "Improved Dispel Overlay behavior when Blizzard/native aura rendering is enabled: Blizzard can still own the aura icon/border path while MSUF keeps the health-bar overlay active.",
                        "Reduced redundant glow, overlay, color, reverse-fill, and status-bar updates for Unit Frame and Group Frame dispel visuals while keeping secret-value handling safe.",
                        "Improved aura delta handling for added, updated, and removed debuffs so priority-based dispel visuals rescan only when the tracked winner or priority-relevant data can change.",
                        "Added Perfy workflow documentation for temporary instrumented test zips, including the rule that MSUF_PerfyHook.lua stays out of normal beta releases.",
                        "Note: the Dispel system is still work in progress and will continue to be tuned in upcoming beta builds.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
