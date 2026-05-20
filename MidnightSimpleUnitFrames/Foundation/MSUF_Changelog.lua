-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.4 Beta 7",
    previousVersion = "5.4 Beta 6",
    rangeLabel = "5.4 Beta 6 -> 5.4 Beta 7",
    entries = {
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
        {
            version = "5.4 Beta 5",
            date = "2026-05-19",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Refactored the Group Frame effects runtime into clear internal modules instead of keeping text, aura effects, range/threat, events, cleanup, highlights, status/offline handling, frame cache, and tooltip/mouseover behavior in one large file.",
                        "Refactored Auras2 into clearer cache, collection, icon, layout, Masque, cooldown-text, render, reminder, event, and edit-mode responsibilities instead of concentrating aura state, icon reuse, filtering, layout, and rendering in the core/render files.",
                        "Added Auras2/MSUF_A2_Cache.lua for aura cache ownership, full scans, delta updates, invalidation, and aura table pooling.",
                        "Added Auras2/MSUF_A2_Collect.lua for zero-allocation helpful/harmful aura collection paths and sorted/unsorted list preparation.",
                        "Added Auras2/MSUF_A2_Icons.lua for icon pool ownership, acquire/release behavior, stack/timer/pandemic application, and icon cleanup.",
                        "Added Auras2/MSUF_A2_Layout.lua for aura icon positioning, row/column layout, and hide-unused behavior.",
                        "Kept Auras2/MSUF_A2_Masque.lua and Auras2/MSUF_A2_CooldownText.lua as dedicated render subsystems so Masque skinning and cooldown text updates stay out of the main aura render orchestration.",
                        "Refactored Auras2/MSUF_A2_Render.lua around render orchestration, shared buff/debuff commit handling, icon commit/layout boundaries, and preview/runtime separation.",
                        "Refactored Core/MSUF_UnitframeCore.lua by moving Target-of-Target inline widget logic into Core/MSUF_UFCore_ToTInline.lua, while keeping public runtime behavior and wrappers compatible.",
                        "Refactored the main frame backbone by moving preview/test-mode frame behavior into Core/MSUF_FramePreview.lua, keeping MidnightSimpleUnitFrames.lua focused more on public orchestration and real runtime frame setup.",
                        "Refactored Gameplay support by moving Blizzard Totem Preview handling into Features/MSUF_Gameplay_TotemPreview.lua, while keeping one public ns.MSUF_RequestGameplayApply path and apply coalescing.",
                        "Refactored ClassPower specialty logic by moving alternate mana handling into ClassPower/MSUF_CP_AltMana.lua and Balance Druid prediction into ClassPower/MSUF_CP_BalanceDruid.lua, leaving the controller closer to orchestration.",
                        "Refactored Boss Castbar preview handling into MidnightSimpleUnitFrames_Castbars/Modules/BossCastbars_Preview.lua, separating edit-mode/fake-cast preview behavior from runtime boss cast handling.",
                        "Reduced GroupFrames/MSUF_GF_Effects.lua to the Health, Power, overlay, and visual-dispatch orchestration path, making the remaining hot-path code easier to review and safer to profile.",
                        "Added GroupFrames/MSUF_GF_Text.lua for compiled text-slot handling, text dirty queues, and text retire cleanup.",
                        "Added GroupFrames/MSUF_GF_AuraEffects.lua for UNIT_AURA dispatch, dispel scanning, dispel overlay/glow, debuff stripe handling, and aura-effect refresh state.",
                        "Added GroupFrames/MSUF_GF_RangeThreat.lua for range fade, layered alpha handling, threat state, and the related lightweight event dispatch.",
                        "Added GroupFrames/MSUF_GF_Events.lua for unit-event masks, global event registration, event lifecycle, and roster/target/focus event routing.",
                        "Added GroupFrames/MSUF_GF_Highlight.lua for highlight configuration resolution, border styling, quick border updates, and target indicator rendering.",
                        "Added GroupFrames/MSUF_GF_StatusOffline.lua for AFK, DND, Dead, Ghost, and delayed offline-hide state handling.",
                        "Added GroupFrames/MSUF_GF_FrameCache.lua for cold-path per-frame configuration caching, event-bit calculation, and cache invalidation triggers.",
                        "Added GroupFrames/MSUF_GF_TooltipMouseover.lua for mouseover highlight styling, tooltip throttling, and Group Frame init hooks.",
                        "Added GroupFrames/MSUF_GF_Cleanup.lua so retired or hidden Group Frames release tooltip, text, aura, range, and offline-hide state through one cleanup entry point.",
                        "Preserved existing Group Frame public APIs and diagnostic wrappers, including update, aura, highlight, status, target, overlay, and frame-cache entry points.",
                        "Fixed a Group Frame target indicator risk by moving its secret-safe UnitIsUnit boolean normalization into the new highlight module instead of relying on a missing local helper.",
                        "Kept the Group Frame aura hot path conservative: no extra aura scans, no extra UnitAura or C_UnitAuras calls, no broader unit-event registration, and no new timer or OnUpdate loop.",
                        "Kept the frame-cache split on the cold apply/refresh path so cache construction is easier to maintain without adding work to frequent Health, Power, Aura, or Range events.",
                        "Updated the TOC load order so highlight, status, aura-effect, and range/threat helpers bind before the hot-path effects orchestrator, while the cold frame cache still loads after the shared effects exports it needs.",
                        "Verified the refactor with luac -p across project-owned Lua files and git diff --check.",
                    },
                },
            },
        },
        {
            version = "5.4 Beta 3",
            date = "2026-05-19",
            sections = {
                {
                    title = "Beta Release",
                    bullets = {
                        "Added status icon Advanced tabs for Unit Frame and Group Frame status indicators, including extended offsets, layer controls, reset, test mode, and preview actions.",
                        "Added status icon pack discovery from addon Icons folders and bundled the UX Pro status icon pack under MidnightSimpleUnitFrames\\Icons\\UXPro.",
                        "Added support for external Interface\\Icons replacement packs by resolving accessible spell and aura FileDataIDs back to icon paths before rendering.",
                        "Fixed Group Frame status icon menu clipping around the Placement layer controls.",
                        "Improved status icon texture handling across aura previews, aura rendering, healer buffs, spell indicators, focus kick icons, and dropdown previews so replacement packs are used consistently.",
                        "Improved Group Frame heal prediction and absorb test mode so Bars test rendering updates overlay bars without unnecessary live prediction reads while out of combat.",
                        "Refactored low-risk runtime paths for aura commits, target-swap visuals, gameplay apply scheduling, crosshair target callbacks, and boss castbar event registration.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
