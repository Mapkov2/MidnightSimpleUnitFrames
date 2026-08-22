# Midnight Simple Unit Frames Changelog

## 6.12-beta1 - 2026-08-22

### Highlights

- **Class Resource text can now show Current, Maximum, or Current / Maximum.** The new Resource text selector keeps Automatic as the untouched resource-specific default, while explicit modes change only the central resource value.
<!-- msuf-menu-link: {"pageKey":"classpower","sectionId":"classpower_visuals","controlId":"menu2.classpower.advanced.style.text.mode","settingKey":"bars.classPowerTextMode","prepareKind":"","prepareValue":"","query":"class resource text mode","label":"Resource text"} -->
- **Boss Range Fade can now update up to 20 times per second.** The new Boss update-rate slider keeps the adaptive standard cadence at zero or continuously checks visible Boss Frames from 1 through 20 updates per second.
<!-- msuf-menu-link: {"pageKey":"uf_boss","sectionId":"range_fade","controlId":"menu2.uf_boss.unit.range_fade.update_rate","settingKey":"boss.rangeFadeUpdateRate","prepareKind":"","prepareValue":"","query":"boss range update rate","label":"Updates per second"} -->

### Changes

- Added Automatic, Current, Maximum, and Current / Maximum formats for the central Class Resource value. Rune timers, Ebon Might duration, and the Ironfur stack counter retain their native formats.
- Class Resource previews mirror the selected text mode, and the Assistant can find and set both the resource-text format and the Boss range-update rate.
- Retired unused legacy Class Resource text-format fields from existing profiles and generated fallback metadata.

### Fixes & Performance

- One-icon aura lanes now use Blizzard's one-frame AuraSlot primitive instead of allocating a ten-frame AuraGroup pool; weapon-enchant and custom-priority lanes keep their specialized group behavior.
- Aura identity-event topology changes are batched across secure Group Frame header scans, resolved aura-name registrations survive unchanged layout refreshes, and redundant native full-aura refreshes were removed.
- Target name and health text now resolve protected PvP class tokens through Blizzard's native class-color object without comparing or caching secret-backed RGB values.
- Standard Boss Range Fade retains its adaptive 0.75/2-second checks, while a custom rate accelerates only visible Boss Frames and shares the existing timer scheduler.
- See New Features now reports the correct compact and full-history version ranges for 6.11.

## 6.11 - 2026-08-21

### Highlights

- **Expanded Buff Tracking is back for Custom 1-3 aura containers.** Every whitelisted spell keeps a fixed slot, missing buffs show as dimmed placeholders, and the same slots can securely cast spells or use bound items when clicked.
<!-- msuf-menu-link: {"pageKey":"uf_player","sectionId":"auras","controlId":"menu2.uf_player.auras.unit-workspace.container-selector","settingKey":"auras3.player.custom1.placed.reminderEnabled","prepareKind":"unitAuraWorkspace","prepareValue":"custom1_reminder","query":"buff reminder fixed slots","label":"Buff Reminder"} -->

### Changes

- Buff Reminder accepts Spell IDs, spell links, item links, and separate tracked-spell/item-action pairs. Player reminders can also track Main Hand and Off Hand temporary enchants, filter out spells the current character cannot apply, and pin shared consumables with **Always show**.
- Main Hand and Off Hand enchant reminders now show their remaining time and a shaped cooldown swipe. A configurable 5-240 minute duration keeps the swipe proportional after login or reload, while the native duration binding updates without polling.
- Reminder slots follow whitelist order, preserve their positions as auras appear or expire, and keep their secure click bindings fixed outside combat without polling or recurring aura reads.
- Localized the complete Buff Reminder setup, whitelist actions, weapon-enchant controls, status text, and tooltips across all 12 supported locales.
- The Assistant can now execute explicit multi-control requests clause by clause, including comma-separated and shared-scope commands, while continuing to fail closed for questions, planning requests, incomplete values, and ambiguous fragments.
- Menu pages, accordion sections, and Back/Forward navigation now switch immediately without transition fades or a recurring discovery pulse.

### Fixes & Performance

- Fixed Friendly Target Range Fade becoming inaccurate in instanced combat when Blizzard temporarily stops returning a fresh range result. MSUF now keeps the last authoritative result until a native range event or a real target change supplies a replacement, without adding polling, timers, or an open-world fallback path.
- Castbars reuse unchanged manager topology and boss-frame geometry validation, resolve cast activity once per update, and share the player's plain interrupt-cooldown status across same-frame Target, Focus, and Boss refreshes.
- Player-first role-sorted Party Frames now wait for a complete Arena roster before publishing their secure name list and refresh on Arena match-state and unit-name transitions; the additional listeners remain disabled in PvE.
- The Assistant no longer mistakes player-count ranges inside Group Frame scale labels (such as 1-10 Players) for a requested value when none was supplied.
- Fixed Elemental Shamans seeing Maelstrom on both resource bars. While Maelstrom owns the Class Resource row, the Player power bar now consistently displays Mana across fill, current value, maximum, percentage, text color, and event filtering; disabling that row or entering a vehicle restores the primary resource.
- Applied the same resource-ownership transition to Shadow Priest Mana/Insanity and cleared both overrides when the Class Resource module shuts down.
- Made third-party cooldown-viewer and external-frame anchoring safe when 12.1 returns protected geometry. MSUF validates foreign frames once, shares one stable proxy between Unit Frames, and freezes that proxy at the combat edge instead of repeatedly touching every consumer.
- Boss castbars now prewarm at most one hidden bar per rendered frame when an encounter starts, avoiding one large synchronous layout burst while retaining authoritative validation when a real cast begins.
- Aura-name fallback scans are coalesced to one frame and permanently retire each resolved alias until the container configuration changes, removing repeated name lookups from unrelated full aura updates.
- Aura menu search now opens the Filters tool correctly for Player Defensives and Target Dots instead of falling back to Setup.
- Rounded Unit Frames no longer read the protected parent of Blizzard-owned dispel-overlay textures; the safe owner is captured before the region becomes forbidden and reused when masks are applied.
- Group Frame previews keep their generated character names when ordinary player-unit events refresh the dummy frames outside Edit Mode.

## 6.1 - 2026-08-19

### Highlights

- The **Raid Group** indicator now has its own Size slider in Status icons, on every frame that can show it. It used to render at the frame's name font size with no way to change it; an untouched profile keeps that size, so nothing moves until you drag the slider.
<!-- msuf-menu-link: {"pageKey":"uf_player","sectionId":"status_icons","controlId":"menu2.uf_player.unit.status.selected.size","settingKey":"player.raidGroupNameSize","prepareKind":"unitStatus","prepareValue":"raidgroupname","query":"raid group size","label":"Size"} -->

### Changes

- Separated the **Augmentation Evoker** resources: Ebon Might now renders on the Player power bar, Essence is an ordinary Class Resource, and Mana moves to Alternative Mana. The Ebon Might bar takes its height, position, texture, background, border and text from the Player Power settings; only its fill colour still comes from the Ebon Might colour entry.
- Class Resource width, offsets, pixel snapping and cooldown anchoring finally apply to an Augmentation Evoker's Essence bar; it used to silently copy the power bar's width and anchor and ignore those settings.
- Turning the Player Power bar off now also turns off the Ebon Might display instead of leaving an empty bar behind.
- Ebon Might's bar and duration text follow live setting changes instead of freezing at the values they had when the native aura slot was first created.
- Added a **Power width** slider to the Class Resources > Player Power card, where Width mode "Manual" previously had no width to set. Dragging it releases *Sync width to Class Resource*, because that sync outranks an explicit width.
- Switching the **Active profile** now offers a UI reload: frames re-apply at once, but settings that are only read at load time otherwise keep the old profile's values until the next reload.
- The group preview **LAYERS** chips now apply to the preview frames drawn on screen as well as to the preview box in the menu, and Shift-click solo shows only that one element on them.
- Cooldown and stack numbers on the preview's aura icons follow the CD/Stack chip, and the chip is greyed out when no enabled aura lane prints a timer or stack count.

### Fixes & Performance

- **Power text** on the Target, Focus, Pet and Boss frames follows the unit you are actually on again. With *Colour power text by type* enabled the colour was resolved once and then kept across every target change, so a Focus or Rage target could stay on the previous target's colour, or sit on Mana blue for the rest of the session (#125). Frames with the power bar switched off were affected the most, because they had no bar to take fresh resource data from.
- Power text no longer falls back to the Mana colour when a unit reports no resource at all. It renders the configured text colour instead, which is what those slots show with colour by power type switched off.
- **Boss frames** no longer freeze at the range fade they happened to have when the pull started. Boss units have no range event of their own, so the periodic check behind *Enable Range Fade* now keeps running in combat instead of stopping at the encounter start.
- The range fade check now retires completely once nothing is left to sample. Only units MSUF has no range event for keep the timer running, so a state without such a unit costs nothing while idle instead of waking up every 0.75 to 2 seconds.
- The Assistant can see and set the **Power width** slider again. Its generated control schema had not been rebuilt since the slider landed, so the one control added this cycle was missing from everything the Assistant can reach by name.
- The Assistant can now drive the **Active auras on this frame** dropdown in the blacklist workspace. It was the only control in that section it could not see, so a live scan could be started and blocked by hand but not by request.
- Aura name resolution compiles its alias list once per container instead of rebuilding an iterator on every event, which is the hot path whenever the client falls back to a full aura update in a raid.
- The over-absorb glow decides once per render pass whether the absorb value is protected, instead of re-checking it at every branch that writes to the bar.
- Fixed a spell indicator's health-bar highlight covering the player name and the aura icons on live Group Frames, while the menu preview drew the same effect correctly underneath (#123). The effect rode along whenever its native aura container was re-levelled, so opening the settings or changing zone could flip the order either way; it now keeps the Layer it was configured with.
- Full-Frame effect previews in the Group preview and in Edit Mode now paint through the same renderer the frames use, so Glow shows its real halo instead of four flat edges and Pulse animates with its live opacity.
- Changing a spell indicator's **Display as** shape now re-gates that section right away; controls belonging to the previous shape, such as Icon Effect, could stay visible until an unrelated click refreshed the page.
- Colour changes on the Colors page now repaint the Resources strip in the preview immediately instead of leaving it on the previous colours until the tab was rebuilt.
- Fixed a raid frame block not staying where it was placed in Edit Mode: the saved position was converted between two internal formats with mismatched roster counts and drifted by up to 162 pixels, and a click that never moved could permanently lock the conversion out.
- Long castbar spell names are now shortened with a visible ellipsis that respects the bar width instead of being clipped by the renderer at an unpredictable spot (#121); a 23-character name could previously disappear completely under a 25-character limit, because the client cuts a bounded line at a glyph-dependent position.
- Turning off a castbar's cast time hands those pixels back to the spell name instead of leaving the gap reserved, so names truncate far less often.
- Fixed an Augmentation Evoker's player health bar shrinking by the extra composite height, and the power bar showing frozen Mana numbers under the Ebon Might duration text.
- If the UI starts in combat and the native aura container cannot be created, an Augmentation Evoker's power bar falls back to a normal Mana bar and retries after combat instead of showing an empty bar.
- The raid preview shows the correct group number on each preview frame instead of numbering members 1-5 within every group.
- The power colour swatch on the Global Fonts page shows an Augmentation Evoker's real power token instead of a hard-coded Essence colour.
- The castbar name shortening no longer builds a cache key string on every text write.

## 6.09 - 2026-08-17

### Highlights

- Added dynamic **Custom Priority** ordering for **Dots on target** and Custom 1-3 aura containers, keeping the configured spell order compact and stable as tracked auras appear or expire.
<!-- msuf-menu-link: {"pageKey":"uf_target","sectionId":"auras","controlId":"menu2.uf_target.auras.unit-workspace.container-selector","settingKey":"auras3.target.custom4.placed.sortMethod","prepareKind":"unitAuraWorkspace","prepareValue":"custom4_behavior","query":"dots on target custom priority","label":"Custom Priority"} -->
- Added a **combat aura scanner** to the Unitframe blacklist workspace: one click closes the menu, keeps capturing every blockable aura with its icon until combat ends, then reopens the menu with the collected list, ready to block.
<!-- msuf-menu-link: {"pageKey":"uf_target","sectionId":"auras","controlId":"menu2.uf_target.auras.unit-workspace.container-selector","settingKey":"auras3.target.debuff.blacklist.hidePermanent","prepareKind":"unitAuraWorkspace","prepareValue":"debuff_blacklist","query":"target debuff blacklist","label":"Combat scan"} -->
- Manual blacklist entries are now verified by **Spell ID** against the live unit: when your cast's ID differs from the aura's actual ID, MSUF warns and offers to block the real aura ID instead.
<!-- msuf-menu-link: {"pageKey":"uf_target","sectionId":"auras","controlId":"menu2.uf_target.auras.unit-workspace.container-selector","settingKey":"auras3.target.debuff.blacklist.hidePermanent","prepareKind":"unitAuraWorkspace","prepareValue":"debuff_blacklist","query":"target debuff blacklist","label":"Blacklist"} -->
- Added an optional **Show spell IDs in aura tooltips** toggle that keeps the native 12.1 tooltip option enabled across logins.
<!-- msuf-menu-link: {"pageKey":"opt_misc","sectionId":"misc_tooltips","controlId":"menu2.opt.misc.global.setting.tooltip.show.aura.spell.ids","settingKey":"general.tooltipShowAuraSpellIDs","query":"spell ids","label":"Aura tooltip spell IDs"} -->
- Added an optional **Boss Number** status indicator so boss frames can show their encounter index directly on the frame.
<!-- msuf-menu-link: {"pageKey":"uf_boss","sectionId":"status_icons","controlId":"menu2.uf_boss.unit.status.selected.enabled","settingKey":"boss.showBossNumberIndicator","prepareKind":"unitStatus","prepareValue":"bossNumber","query":"boss number","label":"Boss Number"} -->

### Changes

- Moved aura ordering out of Style into dedicated, scope-aware **Ordering** workspaces for Unit Frames, Group Frames, custom aura containers, and external defensives, with draggable priority rows that snap to their new slot.
- Added a live **Active auras on this frame** dropdown to the blacklist with one-click blocking, a Rescan button, and a session capture list; scans run only on click.
- Extended the **Maximum duration** filter to every aura lane on unit and group frames, including Buffs, Tracked Buffs, and External Defensives.
- Reworked pandemic-window Full-Frame effects for tracked DoTs to bind to the visible aura buttons themselves, including portrait mode.
- Replaced Aura list scrollbars with the consistent MSUF scrollbar style and exposed Ordering options directly without a redundant accordion.
- Added Blizzard's **NEW** badge to the **See New Features** button, shown until the bundled release notes have been opened.
- Added Deathstalker's Mark for Rogues and Atmospheric Exposure for Druids to the tracked target-effect presets, and corrected the Balance Druid presets for Moonfire (`164812`), Sunfire (`164815`), and Atmospheric Exposure (`430589`).

### Fixes & Performance

- Fixed the combat timer not being movable while its position was unlocked.
- Added a tooltip to the combat timer's **Lock position** toggle explaining how positioning works.
- Fixed the Combat Enter/Leave text vanishing after every combat transition while unlocked; it now stays visible as its movable handle.
- Fixed gameplay mover offsets drifting when the moved element was anchored to a scaled frame, and dragging a mover now repaints its X/Y sliders live.
- Scanning respects Blizzard's instanced-content restrictions: encounter, Mythic+, and PvP lockdowns show a clear notice pointing to the curated presets and resume automatically instead of erroring.
- Scan results state how many auras Blizzard hides as secret; hidden auras cannot be identified or blocked by any addon, so everything blockable is always captured.
- Fixed Edit Mode arrow-key nudging for Custom 1-4 aura containers, including shared boss-frame positioning.
- Fixed Spell Indicator controls from an inactive display type remaining visible after selection or preview changes.
- Kept Custom Priority ordering and blacklist scanning fully event- and click-driven: no polling, no recurring `OnUpdate` work, and nothing added to combat hotpaths.

## 6.08 - 2026-08-16

### Highlights

- Added optional profile-wide custom colors for **Magic, Curse, Disease, Poison, and Bleed** across Unit and Group Frame dispel visuals while preserving Blizzard's native defaults whenever no override is enabled.
<!-- msuf-menu-link: {"pageKey":"opt_colors","sectionId":"colors_auras","controlId":"menu2.opt.colors.advanced.auras.dispel.magic.color","settingKey":"general.dispelTypeColorOverrides.Magic","prepareKind":"","prepareValue":"","query":"magic dispel color","label":"Magic color"} -->
- Added an optional, class-colored interrupter name beside the castbar's interrupted state.
<!-- msuf-menu-link: {"pageKey":"uf_target","sectionId":"castbar","controlId":"menu2.uf_target.unit.castbar.show_interrupt_source","settingKey":"target.showInterruptSource","prepareKind":"unitCastbarTab","prepareValue":"general","query":"show interrupter name","label":"Show interrupter name"} -->
- Added configurable AFK timers to Unit and Group Frame status text.
<!-- msuf-menu-link: {"pageKey":"uf_player","sectionId":"status_icons","controlId":"menu2.uf_player.unit.status.selected.enabled","settingKey":"player.statusAFKTimerEnabled","prepareKind":"unitStatus","prepareValue":"statusAFKTimer","query":"afk timer","label":"AFK Timer"} -->
- Added an optional Player Frame **Stance** text indicator for warrior stances, paladin auras, druid forms, and other native stance-bar forms.
<!-- msuf-menu-link: {"pageKey":"uf_player","sectionId":"status_icons","controlId":"menu2.uf_player.unit.status.selected.enabled","settingKey":"player.showStanceIndicator","prepareKind":"unitStatus","prepareValue":"stance","query":"stance","label":"Stance"} -->
- Added explicit **Uniform** and **Width & height** portrait sizing modes for Unit and Group Frames while preserving existing portrait geometry during migration.
<!-- msuf-menu-link: {"pageKey":"uf_player","sectionId":"portrait","controlId":"menu2.uf_player.unit.portrait.portraitsizemode","settingKey":"player.portraitSizeMode","prepareKind":"unitPortraitTab","prepareValue":"geometry","query":"portrait size mode","label":"Size mode"} -->
- Added configurable edge softness for circular, rounded, and diamond portraits, with matching Unit Frame, Group Frame, and preview rendering.
<!-- msuf-menu-link: {"pageKey":"uf_player","sectionId":"portrait","controlId":"menu2.uf_player.unit.portrait.portraitedgesoftness","settingKey":"player.portraitEdgeSoftness","prepareKind":"unitPortraitTab","prepareValue":"border","query":"portrait edge softness","label":"Portrait edge softness"} -->

### Changes

- Added an optional **Slug** font rendering mode for clearer, more consistent text across Unit Frames, Group Frames, Castbars, Class Resources, and other MSUF text.
- Applied custom Dispel colors consistently to Unit Dispel Overlays, Group Dispel Overlays, Dispel Highlight Borders, MSUF Dispel symbols, Edit Mode, and every matching Menu preview.
- Added `:::` color shortcuts to Unit Dispel Overlay, Group Dispel Overlay, and Highlight Borders for direct access to the matching global Dispel colors.
- Kept original Blizzard and MSUF Dispel artwork for default colors; tint-neutral MSUF symbol assets are selected only for Dispel types with an active custom override.
- Replaced the toolbar's **New Task** action with a dedicated **See New Features** changelog page. Highlighted feature sentences now link directly to their exact MSUF Menu controls and subcategories.
- Localized the new Dispel colors, AFK timer, stance, portrait sizing, portrait edge-softness, and related controls across all 12 supported locales.
- Updated Assistant registrations, profile behavior, copy/reset handling, search routing, generated coverage data, and static search data for the new controls.
- Added daily GitHub synchronization from Retail `main` to the Classic repository, clearer sync-failure reporting, and required versioned Classic validation.
- Added manual release-channel recovery support to the GitHub release workflow.

### Fixes & Performance

- Updated Spell Indicator filters in place through Blizzard's public AuraSlot setter, avoiding unnecessary restricted AuraButton and container rebuilds when only a friendly/hostile filter changes.
- Fixed custom MSUF Dispel symbols becoming black or incorrectly multiplied after recoloring. Custom overrides now use tint-neutral, alpha-identical companions, while unchanged colors continue using the original assets.
- Fixed Group Frame absorb overlays ignoring the configured opacity.
- Fixed aura icon zoom scaling when a Debuff border is active, including runtime and preview rendering.
- Fixed the Castbar General tab height after adding the interrupter-name option.
- Changed Target and Focus castbar identity refreshes from deferred callbacks to direct synchronous updates.
- Cleared the castbar driver's unused `OnUpdate` script once during construction instead of repeating the native transition on target swaps.
- Fixed player Unit Frames showing the fallback blue or another incorrect health color for identity-restricted PvP targets by routing every player class through Blizzard's native secret-safe class-color pipeline.
- Fixed restricted Race and Class status text showing a unit name or blank value by using Blizzard's stable identity return directly when localized identity text is protected.
- Streamlined Unit Frame identity refreshes across bars, portraits, status text, regular text, and range fading so unchanged identity state avoids redundant work.
- Skipped player-only nickname-provider APIs for NPC units while retaining supported NPC nickname sources.
- Fixed Arena Group Frames using Raid instead of Party configuration across runtime, Blizzard-frame ownership, Edit Mode, and previews.
- Fixed exact-ID aura indicators mixing friendly and hostile filters after switching targets.
- Limited PvP indicator runtime to Arenas, Battlegrounds, and War Mode, removing unrelated faction and PvP-timer event traffic outside those modes.

## 6.07 - 2026-08-15

### Highlights

- Expanded **Texture Layers** into three independently configurable, HP-reactive decoration slots with shared gradients, threshold colors, opacity rules, target/combat conditions, presets, and runtime-faithful previews.
- Added **League of Legends-style Health and Power loss feedback** for Unit and Group Frames. Bars update immediately while a configurable trailing chunk shows recently lost Health or spent Power without polling.
- Added profile-wide controls for Blizzard's Player Buff Frame and normal Debuff icons while keeping Private Auras and Deadly Debuff warnings available.

### Changes

- Added direct Edit Mode popup controls for Custom Aura 1-4, Dots on Target, and Player Defensive Buffs, including position, size, spacing, reset, undo, Boss synchronization, and Menu focus.
- Restored Spell Indicator bars with Blizzard's native aura-duration StatusBar, configurable growth direction, smoothing, timer text, geometry, color, alpha, and layer.
- Increased the Menu Back and Forward buttons for easier navigation.

### Fixes & Performance

- Fixed Group Aura lanes and Spell Indicators remaining visible for offline, phased, distant-map, or different-instance members. Presence updates remain coalesced and event-driven.
- Fixed Unit Aura preview handles requiring a second click before their X/Y controls appeared after switching lanes. The first click now survives the settings-page rebuild.
- Fixed Target of Target identity and color events being routed through the Target frame without unit filtering. Updates now listen only to `targettarget`, and foreign unit events can no longer recolor the Target health bar.
- Fixed Texture Layer controls writing to the wrong slot and protected HP-driven alpha values being cached or compared from Lua.
- Fixed Spell Indicator icon, bar, glow, and full-frame effect ownership, opacity, cleanup, preview parity, and layer ordering.
- Fixed Level, Race, Class, and other name-relative status text drifting away from shortened or repositioned Unit Frame names.
- Fixed stale Player portraits, Unit Aura settings writing to the wrong lane, and Objective Tracker state leaking through MSUF's Edit Mode bridge.
- Fixed Class Resource preview text handles becoming trapped behind higher-layer bar visuals.

## 6.06 - 2026-08-13

### Changes

- Added a **Non-Player Auras** Debuff filter for Unit and Group Frames, including Menu, profile import, diagnostics, and Assistant support. It keeps encounter and environment Debuffs while excluding effects caused by players or player pets.

### Fixes & Performance

- Fixed an edge case where Player, Target, Boss, and other Unit Frame health text remained hidden after importing profiles with a conflicting obsolete visibility value. Current profile settings now always win, while legacy-only profiles retain their previous behavior without profile rewrites or recurring runtime work.
- Fixed the MSUF Game Menu button using mismatched dimensions and styling. It now follows the active Game Menu button template, size, font, and EllesmereUI skin without stretching.

## 6.05 - 2026-08-13

### Highlights

- Reworked Augmentation Evoker resources into one coherent Player Power surface: segmented Essence remains visible while Ebon Might uses its own native duration row. Runtime, embedded and detached layouts, rounded styling, text layers, Menu previews, search, and the Assistant now share the same geometry and ownership.

### Changes

- Added Unit Frame load conditions for **No target** and **Out of combat and no target**, including Copy To, search, diagnostics, and Assistant control.
- Added a dedicated Class Resource text layer so resource numbers, Rune times, and Ebon Might duration text can be ordered independently from the resource bar and normal Player Power text.
- Added a delayed warning with a direct settings shortcut when Unit Frames are configured to follow Essential Cooldowns but no supported Blizzard or third-party cooldown anchor is active.

### Fixes & Performance

- Fixed Spell Icon Full-Frame Effects ignoring their configured element layer. Effects now use a frame-local surface so their 0–30 layer orders correctly against bars, text, and other Unit Frame elements.
- Fixed helpful and hostile Group Aura owners retaining invalid exact-ID assignments after assistability, roster-presence, or instance transitions. Updates remain event-driven and fail closed without polling or restricted Aura reads.
- Fixed Interrupt Ready colors and Focus Kick state becoming stale when a protected cooldown completed. MSUF now uses Blizzard's native duration completion callback with a one-shot fallback and ignores unrelated cooldown events.
- Fixed Group Range Fade briefly treating members from another instance or phase as in range after portal and party-presence transitions.
- Fixed Castbars jumping when switching between Unit Frame anchoring and independent Edit Mode placement.
- Fixed later canonical Aura profile revisions being mistaken for legacy data eligible for the original Aura reset.
- Refreshed cached Menu pages when reopening MSUF, made exported profile strings immediately selectable for copying, and exposed the HEX value in the compact color picker.
- Improved Assistant handling for direct control wording, target-aware visibility requests, outline sizing, background textures, and maximum-health-loss textures.

## 6.04 - 2026-08-13

### Highlights

- Reworked Unit Frame Auras around explicit lane ownership. Every Buff and Debuff lane now owns its exact layout, filtering, text, effect, and visibility settings, while icon appearance remains global by Aura type. Existing profiles retain their visible setup, and runtime, Menu, Edit Mode, search, and the Assistant now use the same ownership model.
- Added a profile-specific option to disable Northern Sky Raid Tools nicknames on MSUF frames without changing NSRT or its settings. The integration remains enabled by default and can also be controlled through the Assistant.

### Fixes & Performance

- Reduced recurring work on frequent Health and Texture Layer events. Health prediction and text followers now skip already-pending updates, while dynamic Texture Layers refresh only affected slots, use color-only updates where possible, and reuse their runtime objects.
- Fixed the Elite Indicator missing from Unit Frame previews. Elite, Rare Elite, Rare, and Boss classifications now use their matching Blizzard icons in runtime and previews while sharing one position, size, and layer.
- Fixed identity-dependent Aura displays becoming stale after taxi transitions and helpful Group auras remaining visible when their caster identity could no longer be verified out of range. The existing range and lifecycle events now refresh them without polling.
- Fixed sorted or filtered Raid headers temporarily omitting roster members when unit-name data lagged behind the authoritative Raid roster. MSUF now waits for a complete name list and otherwise falls back to Blizzard's native roster path.
- Fixed Tracked Buffs silently inheriting the normal Buff container's sort method and direction instead of using their own ordering.
- Fixed Group Frame preview borders not repainting immediately, and fixed rounded borders overwriting active Aggro or Dispel test colors after the preview refresh.
- Kept reload-required popups above the MSUF options window and expanded Unit Frame Basics sections so their controls no longer clip.
- Improved the disabled Options-module error so it tells the user to enable MSUF Options in Blizzard's AddOns menu.

## 6.03 - 2026-08-12

### Highlights

- Track any group buff from any specialization. Group Frame Spell Icons now provide a shared All Specs workspace, so entries such as Feint can be configured once and remain active across every character specialization.

### Changes

- Multi-Spec now exposes all 40 Retail specializations. Custom Aura IDs can also be added to an individual specialization, allowing a Holy Priest configuration, for example, to track Feint (`1966`) on another group member while **Only show my casts** is disabled.
- Added a curated, class-wide Big Defensive Spell-ID filter for friendly Unit and Group Frames, with Blizzard's native classification as the restricted-data fallback. Aura classification choices are now mutually exclusive while **Only mine** and **Also include nameplate-only** remain explicit modifiers, and Menu, search, and the Assistant share the same contract.
- Added direct Assistant control and cold-path diagnostics for Unit Frame Buff and Debuff Full-Frame Effects. Menu and Assistant now share the same effect choices without polling or reading protected native Aura visibility.

### Fixes & Performance

- Fixed Target of Target and Focus Target health bars and names losing class colors when WoW protects dependent-unit class data in combat. Protected colors now flow directly through Blizzard-native color sinks without polling or persistent secret-value caches.
- Fixed Health and Power gradients missing or differing in Unit and Group previews. Embedded, detached, and rounded Power previews now reuse the same gradient composition as runtime rendering.
- Fixed Level, Race, and Class text in Unit Frame previews using the default preview font instead of the selected unit font.
- Made Cleanse Border changes request the required UI reload.
- Kept the Player Castbar provider selectable in the Bars menu.
- Fixed native Aura containers triggering a forbidden `EventRegistrations` error during Unit Frame aura setup.
- Improved the ownership handoff between MSUF and Blizzard Party/Raid frames. Provider and fallback changes now return frames reliably through Blizzard's own lifecycle and request the required UI reload.
- Fixed Clique and other click-cast providers losing their Unit Frame bindings after profile or configuration updates. MSUF now preserves provider-owned secure click attributes after the initial fallback setup.
- Isolated Group Spell Indicator preview positions from live saved positions.
- Restored continuous Devourer class-resource updates and removed obsolete partial-update ownership from the resource pipeline.
- Fixed Icicles showing an Aura icon over Class Resources or retaining incorrect stack counts. Icicles now refreshes the exact player Aura on each Aura change, while protected Icicle and Maelstrom Weapon counts fill their pips through Blizzard's native StatusBar clamping without Lua comparisons.
- Fixed Tip of the Spear showing incorrect stacks after current Survival Hunter spenders and Takedown with Twin Fangs. Stack tracking now also expires correctly without protected Aura reads.
- Fixed native Auras, Spell Indicators, and Aura-based Class Resources becoming stale or retaining incorrect durations after cinematics and entering the world. Lifecycle refreshes are now coalesced and event-driven without polling.
- Refreshed Unit Frame names immediately after anchor changes.
- Restored live Group frames correctly after preview roster handoffs.
- Honored configured Aura layers for fixed Group slots.
- Fixed the animated Resting symbol trying to use an unavailable Blizzard atlas; unsupported clients now fall back safely.
- Fixed Unit Frame Edit Mode quick actions applying stale compiled settings after size, position, reset, copy, or detached Power changes.

## 6.02 - 2026-08-11

### WoW 12.1 Release Highlights

- Split Unit Preview Buffs and Debuffs into independent layers with correct handle-to-menu routing, and expanded the frame-local Debuff blacklist presets.
- Added Blizzard-native Ebon Might duration text plus safe, independently configurable Alternative Mana width geometry across runtime, previews, search, and the Assistant.
- Made Blizzard's animated Resting symbol part of the fresh default profile while preserving existing profile choices and live Resting state.
- Reworked the upgrade-highlight tour around real Back/Forward navigation and added Assistant commands that can restart a skipped or completed tour.

### Fixes & Performance

- Fixed nickname-provider fallback refreshes so updated names reach the correct Unit and Group Frames without broad polling.
- Guarded secret Player Health values before Class Resource logic can inspect them in combat.
- Fixed Texture Layer target refreshes, rounded clipping, true-outline geometry, rounded preview edges, and Castbar preview text positions after live setting changes.

## 6.01 - 2026-08-10

### Final Beta Release Highlights

- Expanded Texture Layers with a built-in target-highlight recipe, Current Target visibility, custom-class-color following, automatic sizing, top/bottom texture cropping, and Original or Monochrome source treatment.
- Added real eight-piece outline media alongside the existing solid and stretched-texture Frame Outline styles.
- Added optional rounded rectangular Class Resources and Blizzard's animated native Resting symbol across live frames and previews.
- Refreshed the complete fresh-install visual baseline with cohesive dark bars, warm target accents, and deliberate 6.01 defaults without changing existing profiles.

### Fixes & Performance

- Fixed nickname-provider Target refreshes so only the affected Unit and Group Frames are invalidated, with combat changes still coalesced safely.
- Fixed restricted 12.1 Class Resource values hiding their text in combat; protected values now pass directly to Blizzard's native text and StatusBar sinks while preserving configured styling.
- Fixed Unit Copy To bypassing its action guard and reporting unsupported Castbar copies as successful. Pet, Target of Target, and Focus Target now skip Castbar settings explicitly while mixed copies keep every supported category.
- Fixed Castbar Spell, Time, and Target text using different layout rules in the Unit Preview than on the live runtime castbar.
- Fixed Manual Detached Power width losing authority to a synchronized width source in Edit Mode and Menu controls.
- Fixed Boss portrait refreshes missing frames that had not yet been seeded into the Edit Mode registry.
- Fixed rounded mouseover edges retaining their previous color until the next hover transition.
