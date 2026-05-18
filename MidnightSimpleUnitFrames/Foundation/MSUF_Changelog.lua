-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.3 Beta 6",
    previousVersion = "5.3 Beta 3",
    rangeLabel = "5.3 Beta 3 -> 5.3 Beta 6",
    entries = {
        {
            version = "5.3 Beta 6",
            date = "2026-05-18",
            sections = {
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed aura icons growing on tooltip hover by suppressing inherited button-state visuals and restoring the configured icon geometry.",
                        "Fixed a taint error in class-colored Bar Background runtime caused by comparing secret unit GUID values.",
                        "Fixed group-frame debuff filtering on pure DPS classes so the Dispellable base filter no longer collapses to an empty aura set when the player has no defensive dispel.",
                        "Fixed Unit Auras debuff filters so Include dispellable debuffs and the Magic, Curse, Poison, and Disease filter toggles are applied by the runtime.",
                        "Resolved the Group Frame effects merge conflict while keeping the scope-aware highlight-priority cache path.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added scope-aware dispel border and glow behavior for group frames.",
                        "Expanded status icon anchor options.",
                        "Included the fixes and polish commits from the 2026-05-18 07:00+ beta window in this validation build.",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "Prepared 5.3 Beta 6 as the next beta validation build for today's aura, dispel, and secret-value fixes.",
                    },
                },
            },
        },
        {
            version = "5.3 Beta 5",
            date = "2026-05-18",
            sections = {
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed Bar Background Tint in Dark Mode so a white custom tint stays applied after switching Bar mode away and back.",
                        "Fixed Preserve HP color missing-health rendering so it uses the resolved HP background track color instead of falling back to the old dark preserve color.",
                        "Fixed live color refresh so preserve missing-health layers resync immediately after color and Bar mode changes.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added a global Preserve HP color sync toggle under Global Style > Colors > Bar Background Tint for unit frames.",
                        "Clarified the Colors page, unit transparency hint, search FAQ, and warning text for white missing-health backgrounds in Dark Mode.",
                        "Kept the preview and group-frame preserve backgrounds aligned with the same HP track color pipeline.",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "Prepared 5.3 Beta 5 as the next beta validation build for the Dark Mode background tint fix.",
                    },
                },
            },
        },
        {
            version = "5.3 Beta 4",
            date = "2026-05-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Focus Target frame support across unit settings, edit mode, menu previews, copy targets, text options, icons, and runtime refreshes.",
                        "Further cleaned up Menu2 with refined cards, navigation, search, switch states, dashboard behavior, and input readability.",
                        "Added Rounded Frames with per-surface controls for unit frames, group frames, bars, highlights, overlays, absorbs, and indicators.",
                        "Prepared 5.3 Beta 4 as the release-ready beta validation build. This is not the stable 5.3 release.",
                    },
                },
                {
                    title = "Performance",
                    bullets = {
                        "Optimized range fade alpha repair.",
                        "Reduced redundant HP text rendering when fast-path inputs have not changed.",
                        "Reduced repeated group-frame health color and alpha work when the visual state is unchanged.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed unit preview refresh upvalues.",
                        "Fixed dashboard support clipping.",
                        "Fixed menu clipping and improved input readability.",
                        "Fixed collapsed Menu2 text badge visibility.",
                        "Fixed group HP reverse order runtime behavior.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Added heal prediction anchor modes.",
                        "Polished Menu2 navigation submenu colors.",
                        "Completed runtime locale coverage for the 5.3 beta line.",
                    },
                },
                {
                    title = "Release / Tooling",
                    bullets = {
                        "Kept 5.3 on the beta channel for Beta 4 release-ready validation.",
                        "Updated Perfy workflow notes for current repo-based instrumentation.",
                    },
                },
            },
        },
        {
            version = "5.3 Beta 3",
            date = "2026-05-17",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added Focus Target frame support across unit settings, edit mode, menu previews, copy targets, text options, icons, and runtime refreshes.",
                        "Restored the Menu2 dashboard preview and scroll behavior to the stable 5.3 Beta 2 layout.",
                    },
                },
                {
                    title = "Bugfixes",
                    bullets = {
                        "Fixed Menu2 text badges so they hide while cards are collapsed.",
                        "Restored the Menu2 dashboard preview and scroll behavior to the 5.3 Beta 2 layout.",
                    },
                },
                {
                    title = "Changes / Improvements",
                    bullets = {
                        "Clarified unit frame alpha controls and matched them to the group frame layout.",
                        "Bundled all 5.3 Beta changelog entries in the dashboard changelog.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
