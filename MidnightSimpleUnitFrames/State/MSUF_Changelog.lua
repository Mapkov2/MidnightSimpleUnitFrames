-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-alpha5",
    previousVersion = "6.0-alpha4",
    rangeLabel = "6.0-alpha4 -> 6.0-alpha5",
    entries = {
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
        {
            version = "6.0 Alpha 2",
            date = "2026-06-27",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "New Aura Container System: MSUF now uses WoW 12.1's native AuraContainer and AuraButton system for live aura display instead of the older custom aura scanner/render path from Alpha 1.",
                        "Buffs, debuffs, and important defensive/external auras are handled as separate native aura lanes, so aura updates should feel smoother and more reliable during target swaps, group changes, and combat.",
                        "Unit frames, party frames, raid frames, and mythic raid frames now share the same Auras3 foundation, with Blizzard doing the heavy aura tracking and MSUF focusing on layout and styling.",
                        "Aura containers allocate only the configured number of icons, which keeps the system predictable and avoids unnecessary preloading spikes.",
                    },
                },
                {
                    title = "Aura Settings And Filtering",
                    bullets = {
                        "Added clearer aura controls for unit frames and group frames, including separate styling for buffs and debuffs.",
                        "Added native group aura filter choices such as raid buffs, raid debuffs, dispellable debuffs, crowd control, external defensives, and big defensives.",
                        "Added optional debuff type visuals: off, colored border, or colored border with a type symbol.",
                        "Cooldown swipe, cooldown text, stack count, tooltip behavior, size, spacing, growth direction, and text placement can now be adjusted per aura lane.",
                        "Existing legacy blacklist data is kept, but exact SpellID-style filtering is limited in this alpha because the new native AuraContainer path exposes Blizzard filter strings rather than MSUF's old custom predicate system.",
                    },
                },
                {
                    title = "Menu And Assistant Improvements",
                    bullets = {
                        "The Auras page was rebuilt around scope and lane workflows, making it easier to edit Shared, Player, Target, Focus, Boss, Party, and Raid aura behavior.",
                        "The Assistant gained much broader coverage for auras, group auras, castbars, class resources, unit frames, profiles, dashboard actions, and troubleshooting.",
                        "Search and dashboard routing now expose more setup tasks directly, so common configuration areas are easier to find.",
                        "Many large Assistant registry files were split into smaller pieces to reduce load risk and make future changes easier to maintain.",
                    },
                },
                {
                    title = "Unit Frames, Castbars, And Class Resources",
                    bullets = {
                        "Unit frame refresh paths received more targeted updates for visuals, text, alpha, range fade, status indicators, and aura-related state.",
                        "Castbar runtime code received cleanup across player, target, focus, boss, channel ticks, empower casts, focus kick, and Interrupt Ready paths.",
                        "Class resource handling received follow-up fixes around Player HP integration, preview behavior, alternate mana, and balance druid state.",
                        "Group frame visuals, status handling, spell indicators, and preview paths received additional Alpha 2 cleanup.",
                    },
                },
                {
                    title = "Performance And Stability",
                    bullets = {
                        "Removed much of the Alpha 1 custom aura scan/diff/render work from the live display path.",
                        "Aura refreshes now lean on Blizzard's native incremental aura updates, while MSUF coalesces expensive layout/configuration changes.",
                        "Target and focus aura swaps are refreshed more deliberately so stale aura displays are less likely after changing targets.",
                        "Several runtime paths were simplified so errors surface during alpha testing instead of being hidden by broad fallback wrappers.",
                        "Added local smoke and quality checks for Assistant parsing, group status runtime behavior, namespace safety, spell indicator data, and general addon quality gates.",
                    },
                },
                {
                    title = "Alpha Testing Notes",
                    bullets = {
                        "This is still an alpha build. Export important profiles before testing.",
                        "Please test auras on player, target, focus, boss, party, raid, and mythic raid frames.",
                        "Please test target switching, focus switching, entering/leaving groups, raid conversion, combat lockdown, dispel visuals, stack counts, cooldown text, and tooltip behavior.",
                        "If an old aura blacklist or exact spell filter no longer behaves like Alpha 1, report it with the spell name, SpellID, unit frame, and aura lane.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
