-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.31",
    previousVersion = "5.3",
    rangeLabel = "5.3 -> 5.31",
    entries = {
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
        {
            version = "5.3",
            date = "2026-05-18",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Focus Target as a new unit frame with its own settings, Edit Mode mover, Menu2 preview, copy targets, text options, status icons, and secure runtime refresh.",
                        "Added Rounded Frames through Global Style > Bars > Rounded Texture, with separate controls for unit frames, group frames, power bars, and mouseover highlights.",
                        "Reworked Dispel Border / Glow so it can be useful for every class, including classes without a defensive dispel.",
                        "Continued the Menu2 redesign with cleaner cards, better navigation, stronger search coverage, and clearer profile/menu workflows.",
                    },
                },
                {
                    title = "Focus Target",
                    bullets = {
                        "Added a dedicated Focus Target frame that appears when Focus is enabled and your focus has a target.",
                        "Integrated Focus Target into unit-frame defaults, secure show/hide state, live refreshes, Edit Mode, preview rendering, copy/apply actions, import/export handling, alpha controls, text settings, portraits, and indicators.",
                        "Kept Focus Target lightweight by default: it has health/name support like other unit frames, while power is off by default and castbars/auras remain out of scope for this frame.",
                        "Added Focus Target help/search text and menu safeguards so the frame clearly explains when Focus must be enabled first.",
                    },
                },
                {
                    title = "Rounded Frames",
                    bullets = {
                        "Added rounded mask media and runtime support for unit frames, group frames, health bars, power bars, detached power bars, absorbs, overlays, highlights, and preview samples.",
                        "Added a master Rounded Texture switch plus per-surface toggles for Unit frames, Group frames, Power bars, and Mouseover highlights.",
                        "Integrated rounded edges with active borders, mouseover highlights, dispel highlights, aggro/target/focus highlights, group-frame overlays, and layer ordering so rounded frames no longer fall back to square highlight visuals.",
                        "Added preview, search coverage, localization, reload guidance, and safe rebuild behavior for rounded frame texture changes.",
                        "Rounded Frames stay disabled by default and avoid their runtime path while disabled.",
                    },
                },
                {
                    title = "Dispel Border / Glow",
                    bullets = {
                        "Added Dispel Border detection modes: Dispellable by me, Any dispel-type debuff, and Any debuff.",
                        "Dispel Border / Glow can now support all classes: healers can keep class-aware dispel detection, while non-dispel classes can still highlight debuff types or any debuff without losing the debuff list.",
                        "Added MSUF Dispel Border / Glow for Blizzard aura mode, so Blizzard can keep rendering aura icons while MSUF still draws the configured dispel border and glow.",
                        "Added scope-aware group-frame behavior for dispel colors, glow options, scan state, and highlight priority, so party/raid scopes can keep the correct visual rules.",
                        "Improved dispel color resolution, secret-safe aura scanning, debuff filtering, and highlight cache behavior for Magic, Curse, Poison, Disease, and generic debuff states.",
                    },
                },
                {
                    title = "Menu2",
                    bullets = {
                        "Expanded the card-based layout across unit frames, group frames, auras, indicators, bars, colors, gameplay, profiles, class power, and advanced pages.",
                        "Improved the dashboard preview, collapsed text badges, clipping behavior, input readability, submenu colors, scroll behavior, dynamic strata handling, and card enable states.",
                        "Added a larger search module with better guidance for auras, name shortening, rounded frames, Focus Target, Unit Auras, Blizzard aura modes, and profile workflows.",
                        "Refined switches, range fade controls, profile UX, FAQ text, and warnings around Blizzard-managed buffs/debuffs.",
                    },
                },
                {
                    title = "Other Improvements",
                    bullets = {
                        "Added heal prediction anchor modes.",
                        "Added more status icon anchor options.",
                        "Added player aggro border support.",
                        "Added a global Preserve HP color sync option for unit-frame Bar Background Tint and improved Dark Mode missing-health background handling.",
                        "Added raid group number display next to unit names.",
                        "Improved Unit Auras debuff filters, including Include dispellable debuffs and the Magic, Curse, Poison, and Disease toggles.",
                        "Defaulted tooltips back to Blizzard-controlled behavior for better compatibility.",
                    },
                },
                {
                    title = "Performance and Stability",
                    bullets = {
                        "Improved bar background rendering, text update paths, interrupt-ready handling, range fade alpha repair, and castbar width-source layout checks.",
                        "Reduced unnecessary group-frame header rescans and repeated group health color/alpha work.",
                        "Hardened backend namespace compatibility and imported media handling.",
                        "Fixed detached unit-frame outline borders, player aura helpful classification, group HP reverse order, aura tooltip hover sizing, menu preview refreshes, dashboard support clipping, and layer ordering consistency.",
                    },
                },
                {
                    title = "Localization",
                    bullets = {
                        "Completed direct locale coverage for enUS, enGB, deDE, frFR, esES, esMX, itIT, koKR, ptBR, ruRU, zhCN, and zhTW.",
                        "Moved locale coverage into real locale files and updated runtime localization coverage for the 5.3 feature set.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
