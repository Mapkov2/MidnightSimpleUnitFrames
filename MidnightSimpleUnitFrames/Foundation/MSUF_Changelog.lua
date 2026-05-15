-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.1 Beta 4",
    previousVersion = "5.1 Beta 3",
    rangeLabel = "5.1 Beta 3 -> 5.1 Beta 4",
    entries = {
        {
            version = "5.1 Beta 4",
            date = "2026-05-15",
            sections = {
                {
                    title = "Performance",
                    bullets = {
                        "Dispel / purge outline event gating: Aura outline updates now only register and queue when the current player can actually friendly-dispel or purge. Friendly dispel and purge capability are cached per player class/race and refreshed on login.",
                        "Dispel / purge aura filtering: Incremental UNIT_AURA updates now skip queue work when the changed aura data cannot affect the active friendly-dispel or purge outline state.",
                        "Group Frame cache build: Blizzard aura type flags are resolved in one pass and stored in the per-frame cache, avoiding repeated renderer/type checks during frame cache rebuilds.",
                        "Group Frame highlight cache: Highlight border values and colors are pre-resolved from group and general settings during cache build instead of re-running fallback lookups in hot paths.",
                        "Group Frame status text cache: AFK, DND, dead, and ghost visibility flags are now cached per frame and reused by status text updates.",
                        "Aura2 reminders: Reminder scans now ignore disabled or irrelevant provider classes before aura lookup work, and prefer cached player aura data before falling back to direct API scans.",
                        "Hover highlight hide hook: Unitframe highlight cleanup avoids redundant Hide() calls when the highlight is already hidden.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed Clique / Blizzard click-casting registration for Group Frames. Frames are registered after tooltip OnEnter / OnLeave scripts are installed so Clique can wrap the final handlers.",
                        "Fixed preview Group Frames being added to the click-casting registry.",
                        "Fixed detached power bar outline mode. Detached power bars now use a dedicated outline path and no longer depend on the normal embedded power bar border logic.",
                        "Fixed the dashboard MSUF UI scale Apply button so the scale is applied live immediately.",
                        "Fixed global MSUF scale collection so Group Frames are only included when their own scale mode is manual or auto.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Dashboard Wago Profiles now shows the bundled changelog from the previous release to the current build in a readable in-game release notes panel, including beta builds.",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "CurseForge publishing now uses BigWigsMods/packager directly from the release workflow.",
                        "Release channel resolution now maps alpha/beta/prerelease tags to the correct Wago stability and CurseForge release type.",
                        "CurseForge API secrets can be provided as either CF_API_KEY or CURSEFORGE.",
                        "Release zips now use the full addon name (MidnightSimpleUnitFrames<version>.zip) instead of the short MSUF-<version>.zip name.",
                    },
                },
                {
                    title = "Documentation",
                    bullets = {
                        "Added docs/PERFY_WORKFLOW.md with the current Perfy trace workflow, validation rules, and known instrumentation pitfalls for future performance passes.",
                    },
                },
            },
        },
        {
            version = "5.1 Beta 3",
            date = "2026-05-14",
            sections = {
                {
                    title = "Performance (Stage 1 micro-optimizations)",
                    bullets = {
                        "UFCore_FlushTask: Core._flushSettingsCacheSerial is now set each flush tick, activating the per-flush-cycle fast path in UFCore_GetSettingsCache. Previously the fast path was dead code (serial never set), so every GetSettingsCache() call re-ran 4 table-ref comparisons.",
                        "Health color gradient hot path: enableHealthGradient is now snapped into file-scope locals during UFCore_RefreshSettingsCache. _HealthValueFast and Elements.Health.Update read one precomputed boolean instead of calling a per-frame DB/cache resolver.",
                        "GF.QueueGroupBorderRefresh: Pre-built stable closures per kind (created once on first call). Switched primary dispatch to MSUF_ScheduleOnce (key-based dedup). Eliminates one new closure allocation + GF._groupBorderRefreshQueued table write per GROUP_ROSTER_UPDATE burst call.",
                        "Health color gradient checks: UFCore_RefreshFrameInvariantFlags and UFCore_RefreshHealthBarColorFast also use the file-scope snapshot, so all UFCore gradient-color gates avoid per-frame DB resolution.",
                        "TargetUnitInFriendlySpellsRange: InCombatLockdown() hoisted to function entry; eliminates the redundant not InCombatLockdown or nil-check pattern at both usage sites.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "MSUF_Alpha.lua - secret-value arithmetic crash (3111x spam): GetAlpha() and GetStatusBarColor() return secret values when WoW execution is tainted. The alpha diff functions (_AlphaNearlyEqual, MSUF_Alpha_SetFlat, MSUF_Alpha_ApplyLayered) and four EditMode minimum-alpha comparisons all performed arithmetic/comparison on these values, crashing with \"attempt to perform arithmetic on a secret number value\". All sites now use issecretvalue guards before arithmetic; on secret input the functions fall through to SetAlpha (safe conservative re-apply) rather than attempting comparison.",
                    },
                },
                {
                    title = "New Features",
                    bullets = {
                        "Group Frame aura renderer split: Blizzard/native or MSUF custom.",
                        "Per-type Blizzard routing for buffs, debuffs, dispels, defensives, and private auras.",
                        "Blizzard aura controls: icon size, limits, organization, cooldown text, strata, frame level, and private-aura layer fix.",
                        "Group Frame aura preview with custom layers plus locked Blizzard/native layer.",
                        "Custom defensive aura group controls for placement, size, growth, spacing, cooldown, and stacks.",
                        "Page-level reset support across menus.",
                        "Release tooling for GitHub, Wago, CurseForge, package builds, and manual publishing.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Disabled Group Frames now stop their MSUF feature work and hand control back to Blizzard frames.",
                        "Menu and Edit Mode actions are combat-gated with a clear combat-lock message.",
                        "Blizzard aura containers skip unnecessary rebuilds during cheap aura updates.",
                        "Group Frame aura, healer buff, group number, effects, and render paths were tightened for lower overhead.",
                        "Range fade and target range checks are more performant.",
                        "Aura2 reminder/range refresh behavior does less idle work.",
                        "Group Frame preview better matches custom aura text, cooldown, stack, dispel, private, and Blizzard aura paths.",
                        "Group Frame preview font rendering improved.",
                        "Locale coverage updated for all 5.1 Beta 1 Group Aura / Blizzard Renderer strings.",
                        "CurseForge release flow now uses auto-packaging with fixed package roots.",
                        "Release publishing workflow hardened.",
                    },
                },
                {
                    title = "Removed",
                    bullets = {
                        "Removed experimental external DR % before Beta 1.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed Scheduler sparse queue errors (table index is nil).",
                        "Fixed Group Frame raid marker taint from secret-value comparisons.",
                        "Fixed disabled Group Frames still running feature updates.",
                        "Fixed protected menu/edit operations being possible in combat.",
                        "Fixed Blizzard/native aura preview implying draggable custom placement.",
                        "Fixed Group Frame menu/Edit Mode preview hiding real raid/mythic raid frames after closing.",
                        "Fixed Group Frame range fade being skipped by runtime gating.",
                        "Fixed health color gradient toggle also enabling the HP bar overlay gradient.",
                        "Fixed Group Frame border/highlight preview behavior.",
                        "Fixed Absorb Bar Test Mode.",
                        "Fixed permanent buff toggle behavior.",
                        "Fixed release package metadata/workflow issues.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
