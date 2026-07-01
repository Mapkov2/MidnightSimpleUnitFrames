-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0-Beta1",
    previousVersion = "5.60",
    rangeLabel = "5.60 -> 6.0-Beta1",
    entries = {
        {
            version = "6.0-Beta1",
            date = "2026-07-01",
            sections = {
                {
                    title = "Short Version",
                    bullets = {
                        "6.0-Beta1 is the real upgrade path from 5.60 to 6.0, not a small follow-up patch.",
                        "It is built for WoW 12.1. If you are still using 5.60, export your profiles before trying this beta.",
                        "All Alpha 1-8 changes are included here, plus the final Beta1 fixes and polish.",
                        "The addon should still feel like MSUF, but a lot underneath it has been replaced so it can work properly on the 12.1 client.",
                    },
                },
                {
                    title = "What You Will Notice First",
                    bullets = {
                        "Auras are the biggest change. Buffs and debuffs now use the WoW 12.1 native aura system instead of the old 5.60 aura renderer.",
                        "Group frames should feel more complete and more consistent, especially in parties and raids.",
                        "Class resources and Player power bars have more visual styles, better previews, and more layout control.",
                        "The settings menu is more useful. The new Assistant can find settings, apply many changes, handle followups, run checks, and undo changes it made.",
                        "Castbars are now part of the main 6.0 setup instead of feeling like a separate older layer.",
                        "Profile import/export is more forgiving, especially when older strings, missing fonts, missing textures, or alpha profiles are involved.",
                    },
                },
                {
                    title = "New Compared To 5.60",
                    bullets = {
                        "Auras3 replaces Auras2 for live aura display on WoW 12.1.",
                        "Aura duration bars can now be shown under buff and debuff icons.",
                        "Aura cooldown swipe direction can be normal or reversed.",
                        "Aura lanes can be moved more directly in Edit Mode.",
                        "Buff and debuff lanes have clearer Shared/Custom style controls, cooldown text placement, stack text placement, native filters, and preview support.",
                        "Native dispel detection is wired into the new aura path.",
                        "Party Targeted Spell Indicators can show enemy nameplate casts on the party member being targeted.",
                        "MSUF4 profile strings are now supported, while older MSUF2/MSUF3 strings are still handled as fallback imports.",
                        "Northern Sky Raid Tools nicknames can be used for unit-frame names.",
                        "External anchor support was added, including Skiron cooldown anchors.",
                        "New class-resource and power-bar shapes were added: circle, diamond, hex, round, crystal, and orb-style options.",
                        "Class Resources now has shape presets such as Classic Bar, Clean Dots, Gems, Hex Pips, and Compact.",
                        "The detached Player Power bar can now follow class-resource styling or use its own bar, round, crystal, or orb style.",
                        "An optional extra Player HP bar can be shown near class resources or Player Power, with its own text, size, color, texture, and shape options.",
                        "The in-game changelog can be opened from MSUF after updating.",
                    },
                },
                {
                    title = "Reworked From 5.60",
                    bullets = {
                        "Unit frames were rebuilt for 6.0: health, power, text, alpha, range fade, status icons, prediction bars, borders, and load conditions now use the new engine.",
                        "Group frames were rebuilt instead of patched on top of the old 5.60 group system. Party, Raid, and Mythic Raid now share the same newer frame logic.",
                        "Castbars existed in 5.60, but 6.0 integrates Player, Target, Focus, Boss, Focus Kick, and Interrupt Ready into the main addon flow with better previews and cleaner ownership.",
                        "Class Resources were expanded with better class/spec previews, shape media, smoother resource presentation, detached power-bar controls, and the optional Player HP bridge.",
                        "Menu2 was already present in 5.60, but 6.0 turns it into a fuller settings shell with navigation, previews, search, Assistant support, bug report tools, and better window handling.",
                        "Edit Mode moved from the old EditMode2 path to the new 6.0 Edit Mode, including aura handles, cast/aura popups, popup scaling, and the new logo intro.",
                        "Gameplay helpers were reorganized and hardened around combat, reloads, target sound, totem preview, and related helper settings.",
                    },
                },
                {
                    title = "Auras In Plain English",
                    bullets = {
                        "5.60 displayed auras with MSUF's own older scanner and renderer. 6.0 lets Blizzard's 12.1 aura system do the live tracking and lets MSUF control how those auras look.",
                        "This should make target swaps, focus swaps, group updates, and combat aura updates more reliable on the new client.",
                        "You get more visible controls for each aura lane: size, spacing, growth direction, cooldown text, stack text, duration bars, filters, and tooltip behavior.",
                        "Existing blacklist data is kept, but old Auras2 filtering may not match perfectly because the new system uses Blizzard's native 12.1 filter strings.",
                    },
                },
                {
                    title = "Group Frames",
                    bullets = {
                        "Party, Raid, and Mythic Raid are now handled by the same 6.0 group-frame system.",
                        "Party Targeted Spell Indicators are the main new gameplay feature here: in dungeon content, a party frame can show when an enemy cast is aimed at that player.",
                        "Group auras now use the new Auras3 path, including native dispel support and better preview behavior.",
                        "Status indicators, spell indicators, range fade, health fade, offline/dead visuals, role filters, threat/aggro visuals, and text handling were cleaned up into one more predictable setup.",
                        "Beta1 also adds more visibility/load conditions, including housing cases, and more control over which roles show aggro borders.",
                    },
                },
                {
                    title = "Class Resources And Power Bars",
                    bullets = {
                        "Class resources are no longer just the old rectangular class bar style. You can use bar, dot, gem, hex, compact, round, crystal, and orb-like looks depending on the resource or attached power bar.",
                        "The Class Resources page now has better previews for real class/spec cases such as runes, combo points, soul shards, essence, holy power, chi, insanity, maelstrom, stagger, and similar resource styles.",
                        "Shape presets make it faster to switch between classic bars, clean dots, gem-style pips, hex pips, and compact resource displays.",
                        "Detached Player Power can sync with class resources or use its own style, size, texture, outline, text, and placement.",
                        "The optional Player HP bar can sit above or below class resources or Player Power, and can follow the Player Power style if you want a matched resource cluster.",
                        "Power-bar and class-resource previews were improved so changes are easier to judge before leaving the settings menu.",
                    },
                },
                {
                    title = "Profiles And Migration",
                    bullets = {
                        "6.0 tries to migrate 5.60 profiles automatically, but this is a major version jump. Export first.",
                        "Old profile strings, missing media, older alpha data, and some external imports should recover better instead of failing the whole import.",
                        "MSUF4 is the new profile string format for 6.0.",
                        "Older MSUF2/MSUF3 profile strings are still attempted through fallback import paths.",
                        "Imported profiles can be applied to the current profile or brought in as a new profile, depending on the workflow.",
                    },
                },
                {
                    title = "From Alpha 1 To Beta1",
                    bullets = {
                        "Alpha 1 opened the 6.0 branch with the new foundation, previews, castbar work, class-resource work, profile import/export, group-frame work, and the first Auras3 version.",
                        "Alpha 2 moved live aura display to Blizzard's native 12.1 AuraContainer system.",
                        "Alpha 3 improved aura timer colors, Assistant context, geometry followups, castbar controls, class-resource previews, and preview routing.",
                        "Alpha 4 improved Shared aura styling, per-unit aura text overrides, cooldown text anchors, aura previews, and boss preview refresh.",
                        "Alpha 5 added reverse cooldown swipe and fixed important castbar preview/runtime issues.",
                        "Alpha 6 added Party Targeted Spell Indicators, NSRT nicknames, MSUF4 profile strings, class-resource shapes, stronger import handling, and the in-game changelog.",
                        "Alpha 7 added the Edit Mode logo intro and prepared the CurseForge-only alpha release path.",
                        "Alpha 8 added aura dragging, menu performance work, combat performance work, and more Assistant coverage for group and bar settings.",
                        "Beta1 stabilizes all of that for wider 5.60 -> 6.0 testing.",
                    },
                },
                {
                    title = "Beta1 Polish",
                    bullets = {
                        "Aura duration bars and native dispel sensors are now connected through live frames, previews, defaults, menus, and the Assistant.",
                        "The Assistant understands more aura, group-frame, bar, overlay, load-condition, and followup requests.",
                        "Castbar width mode, castbar text, Interrupt Ready refresh, and class-bar quick setup issues were fixed.",
                        "Group-frame layout, group status refresh, menu keyboard handling, unit-frame prediction updates, and font checks were tightened up.",
                        "Local development files, stale bytecode output, and release packaging were cleaned up for the beta build.",
                    },
                },
                {
                    title = "What To Test First",
                    bullets = {
                        "Import or copy a 5.60 profile, then check Player, Target, Focus, Boss, Target of Target, Focus Target, Party, Raid, and Mythic Raid.",
                        "Test auras on WoW 12.1: target swaps, focus swaps, party/raid conversion, dispellable debuffs, duration bars, cooldown text, stack text, aura dragging, and filters.",
                        "Test Party Targeted Spell Indicators in 5-player content with enemy nameplates enabled.",
                        "Test Class Resources on several classes/specs, especially shape presets, detached Player Power, the optional Player HP bar, and preview switching.",
                        "Test castbars for normal casts, channels, empower casts, Boss casts, Focus Kick, Interrupt Ready, and Blizzard/MSUF player castbar ownership.",
                        "Test profile strings, missing font/texture fallback, NSRT nicknames, external anchors, Edit Mode, and /reload after combat.",
                    },
                },
            },
        },
        {
            version = "6.0-alpha8",
            date = "2026-06-30",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added draggable Auras3 edit handles so aura lanes can be moved more directly in Edit Mode.",
                        "Improved Menu2 and combat hot-path performance before the Beta cut.",
                        "Expanded Assistant coverage for group-frame and bar controls.",
                        "Prepared the MSUF_6.0A8 package as the last alpha before Beta1.",
                    },
                },
                {
                    title = "Auras, Menu, And Performance",
                    bullets = {
                        "Improved aura movement, aura edit-mode state, target/focus aura refresh, and range fade related refresh behavior.",
                        "Reduced menu preview rebuild work and tightened several Menu2 window/page refresh paths.",
                        "Improved combat performance across runtime update paths that were too noisy during alpha testing.",
                        "Updated group bar/page controls and related Assistant routing so more group-frame settings can be found and changed naturally.",
                    },
                },
            },
        },
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
        {
            version = "6.0 Alpha 1",
            date = "2026-06-24",
            sections = {
                {
                    title = "Alpha 1 Baseline",
                    bullets = {
                        "First public 6.0 alpha package for the rewritten MSUF 6.x core.",
                        "Introduced the rebuilt Menu2 configuration UI, expanded previews, integrated castbars, class resource updates, group-frame runtime work, profile import/export work, and the first Auras3 alpha path.",
                        "This build is the comparison baseline used for the Alpha 2 notes above.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
