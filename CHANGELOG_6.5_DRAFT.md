# MSUF 6.5 Full Changelog Draft

All documented 6.5 beta changes through **Beta 17, released on 6 October 2026**, together with the foundational 6.5 additions. Client-specific features are available where supported.

## Highlights

- **Arena Frames:** dedicated opponent frames with their own castbars, auras, settings and Edit Mode movers, including preparation, stealth and trinket states. Midnight supports three opponents; TBC and Mists support five.
- **Pet Target:** a separate frame for your pet's target, with independent styling, settings, preview and placement.
- **Pet Auras:** configurable buff and debuff lanes directly on the Pet frame, plus client-supported Pet XP and Pet Happiness.
- **Slanted Frames:** angular shapes for supported Unit and Group Frames, Power bars, castbars and Class Resources. True Outline and Texture borders now follow both Slanted and Rounded edges.
- **Cosmetic Texture Layering:** decorate each Unit Frame with up to three independent texture layers. Choose textures or supported Blizzard artwork and adjust placement, size, opacity, colors, crop and mirroring, with matching previews.
- **Unified client support:** one source for Midnight, Classic Era, TBC, Mists and WoW Forever, with client-appropriate settings and runtime behavior.

## Features & Changes

### Group layouts and organisation

- **Name strips:** give group names a separate strip above the health bar, with adjustable height, color and opacity.
- **Member target frames:** display group members' targets in a separate block, with independent position and dimensions and an option to include your own target.
- **Group Pet frames:** use a separate pet block with its own position, dimensions, columns, text size and pet-count limit.
- **Healer mana rows:** show a separate mana row for members with the assigned Healer role, with independent placement, size, amount text and text color.
- **Allied boss frames:** display dedicated friendly-boss frames on clients with boss units, optionally restricted to players with the assigned Healer role.
- **Raid-size layouts:** choose manual or group-size scaling and separate width, height, growth, scale and optional position for 1–10, 11–20, 21–25 and 26+ players. Base dimensions remain the fallback.
- **Scale related visuals:** indicators, aura icons and tracked buffs can independently scale with frame dimensions. Hidden groups can be excluded from the size calculation.
- **Class priority sorting:** drag classes into a preferred order within the configured group and role order. Eligible raid role layouts can sort names alphabetically within roles.
- **Raid-wide role sorting:** the unified line includes sorting tanks, healers and damage dealers across the whole raid, including supported preserved-group layouts.
- **Small-raid organisation:** use Party layout for raids of up to five players, center solo layouts, collapse empty preserved groups and hide groups 5–8 in supported Mythic raids.
- **Header switches:** Name strip, Member targets, Pet frames, Allied boss frames, Healer mana bars and Forever Buff coverage can be toggled while their accordion is closed.
- **Healer mana colors:** text color lives under Colors > Group > Healer mana bars and remains available through the section's three-dot shortcut. Existing values are retained, and edits follow the shared Party, Raid and Mythic Raid color behavior.
- **Threat percentage:** Classic Era, TBC and Forever can show Threat % on supported Target, Focus, Boss, Party and Raid frames; 100% means you have aggro. Group values use your current target. Placement, size, background and low/medium/high colors are adjustable. Party starts enabled in the supplied defaults; Raid is opt-in.
- **Group level text:** Party and Raid can show optional level text with difficulty coloring; it starts disabled.

### Unit frames and status information

- **Pet Target:** a complete independent Unit Frame with its own controls, defaults, preview and placement.
- **Pet information:** configurable buffs and debuffs, client-gated XP and Pet Happiness. Forever uses Blizzard's three happiness atlases when available.
- **Difficulty-colored levels:** configurable red, orange, white, green and gray bands identify relative difficulty, including unknown levels. Existing per-frame level colors are retained where already selected.
- **Round level badge:** an optional gold-rimmed badge follows the level indicator's position, size and layer, using native artwork or a bundled fallback.
- **Tagged mobs:** optionally gray names and applicable health-bar colors for mobs tagged by another player.
- **Classic load conditions:** expose No target and Out of combat and no target where supported.
- **Forever names:** choose full character name, first name or surname through the Fonts page where the name is readable.
- **Incoming-heal prediction:** supported Classic clients can opt into prediction from all healers; player-only prediction remains the default.
- **Health and prediction appearance:** the unified line includes independent Full bar or Missing health only backgrounds, configurable color sources and Keep Absorbs + Prediction Visible.
- **Text visibility:** the unified line retains independent Name, Health and Power mouseover visibility with fade timing, and injured-only Unit Frame visibility.

### Shapes, borders, portraits and artwork

- **Slanted scopes:** configure Unit Frames, Group Frames, Power bars, castbars, Class Resources and mouseover surfaces with matching previews.
- **Rounded fallback:** turning off Slanted restores the active Rounded fallback without discarding saved frame styles, including imported profiles.
- **Styled shaped borders:** True Outline and Texture borders follow rounded corners and slanted edges on Unit and Group Frames, with matching style, color and thickness in previews. Configure them under Bars > Frame Outline.
- **Frame-shape controls:** configure shapes through Bars and Group Layout. The duplicate shape picker in each unit's Frame Basics section has been removed.
- **Cosmetic Texture Layers:** up to three decoration slots per Unit Frame, with independent textures, geometry, opacity and layering. Crop, mirror, class-color and health-gradient options support decorative accents, with optional target/combat conditions and matching previews.
- **Portrait dragons:** Blizzard-style portraits offer elite, rare and boss decorations, with additional placement, size and layering choices.
- **Portrait connector and rim:** add the bottom-right gold connector and suppress a duplicate standalone rim when complete Blizzard frame artwork already includes one.
- **Portrait adjustments:** zoom, left-to-right flip, inset-shadow strength and corner direction, with matching per-unit previews.
- **Temporary portrait preview:** preview classification artwork on the live portrait; closing the section or entering combat restores the real unit classification.
- **Native atlas Texture Layers:** use Blizzard atlases with matching runtime and preview crops and an ordinary texture fallback when the atlas is unavailable.
- **Native status artwork:** leader, assistant and combat indicators use matching native art where available and texture fallbacks on older clients.
- **Menu appearances:** Classic Glass, Midnight and Midnight Dark are available across supported clients.

### Class Resources and Additional Resources

- **Independent Edit Mode movers:** move Class Resources and detached Player Power together or separately. Inactive resources, including Druid Combo Points outside Cat Form, retain an editable mover.
- **Detached Power geometry:** independent width, height and position controls; Energy bars anchored to Combo Points continue to follow them.
- **Full Player-frame width:** Class Resources using Player frame width span the full frame.
- **Resource workspace:** direct resource selection, scoped controls, Copy To, Quick Setup and reset actions in one shared workspace.
- **Dedicated helper controls:** Additional Resources have their own sections, color shortcuts and runtime-rendered previews.
- **Marks and thresholds:** place absolute or percentage marks on Player Power, Class Resource or Alternative Mana; restrict by power type, choose width and color, and change color above or below a threshold.
- **Mana spend preview:** show upcoming mana costs. Supported clients also provide regeneration-pause and mana-return helpers.
- **Midnight resource helpers:** Ignore Pain duration and Arcane window timing, with shared geometry and separate colors.
- **Arcane timing modes:** seconds, global cooldowns or both, with adjustable countdown visibility, warning timing and phase colors.
- **Out-of-combat hiding:** optionally hide Player Power together with Class Resource when Hide out of combat is enabled. Edit Mode keeps both visible for placement.
- **Explicit Mana and Alternative Mana:** client-specific resource selection, placement and text settings remain available alongside the main class resource.
- **Additional resource colors:** helper colors are available under Colors > Additional resource colors.

### Auras and castbars

- **Pet aura lanes:** configure Pet buffs and debuffs independently on the Pet page.
- **Rank-aware Classic matching:** Era, TBC and Mists can match readable aura names when spell ranks or cast IDs differ from the visible aura ID. Their generated alias catalogs are no longer loaded or packaged.
- **Forever aura aliases:** rebuilt the localized spell-name catalog from all eleven build-70009 locale exports and revalidated the curated aura IDs.
- **Aura workspaces:** the unified line includes scope-specific ordering and filtering, the curated MSUF Highlights Group Buff filter, custom-priority containers and combat collection in the blacklist workspace.
- **Native Mainline tooltip options:** aura caster names and spell IDs follow client availability.
- **Independent GCD bar:** supported clients can position it separately, with size, opacity, time and spell display, idle-background and combat-only options.
- **Final channel tick:** add a final-tick accent to supported spell-specific Player castbar markers.
- **Classic channel data:** Era and Forever use rank-specific channel information, with up to fifteen ticks where supported. TBC and Mists retain their existing tables.
- **Arena castbar configuration:** icon, spell-name and cast-time options apply to supported opponent frames, including all five TBC and Mists slots.
- **Focus Kick:** the unified line includes the option to retain the Focus castbar beside the compact interrupt icon.

### WoW Forever Swing Timers and buff coverage

- **Main Hand, Off Hand and Ranged timers:** separate appearance and text controls, fill direction, elapsed or remaining time, custom labels and saved placement.
- **Swing helpers:** an off-hand lane inside the main-hand bar, queued-attack cues and reach warnings.
- **Swing preview and transfer:** embedded menu preview, drag placement and category-based Copy To. Disabling the module restores Blizzard's previous swing-bar visibility.
- **Group buff coverage:** check selected Mark of the Wild, Thorns, Arcane Intellect, Paladin blessings, Fortitude and Divine Spirit buffs against available group providers.
- **Buff reminder rules:** optional glow, tank-only Thorns and mana-user rules for Intellect and Spirit.
- **Restricted-state visibility:** coverage icons hide in restricted states by default. The optional combat-display mode retains known coverage where fresh aura data is unavailable.

### Profiles and transfer

- **Profile variants:** override selected settings and layouts for specializations, locations or a hotkey while retaining the base profile. Variants have recording controls, conditions, priority, field selection and import/export.
- **Selected Unit Frame export and import:** transfer supported Player, Target, Target of Target, Pet, Focus, Focus Target, Boss and Arena selections. Each selection carries its own settings, auras and castbar.
- **Scoped imports:** apply selected frames to the current or a new profile while preserving other frames and shared settings. Inherited appearance follows the receiving profile.
- **Selection validation:** empty selections, unsupported frames and settings outside the selected scope are rejected. Full-profile and category transfers retain their formats.
- **Client-aware defaults:** fresh installs, new profiles and resets use the factory layout, with revised power bars, separate Alternative Mana placement, compact raid geometry and updated text/aura positions.
- **Factory visual settings:** updated Slug font rendering, Focus/Target-of-Target placement and Pet transparency. Factory castbars fill left to right, the cleanse border uses Dispellable by group, and Target buffs/debuffs share one line. Existing profiles retain their chosen settings.
- **Forever factory layout:** a dedicated client layout with revised Unit Frame defaults and 80% health-fill opacity.
- **Section Copy To:** includes supported portrait connector, rim, level badge, atlas, text mouseover, clickable portrait, chunked fill and prediction-opacity settings. Unavailable destinations are marked or filtered.
- **Supported profile formats:** the unified line retains MSUF 6.x profiles and their supported Wago envelope. Pre-6.0 conversion and its import controls were retired during the alpha series.

### Menu, search and controller controls

- Section headers provide their feature switch, summary and three-dot actions for reset and Copy To.
- Disabled frame scopes dim their settings while keeping frame selection and previews usable.
- Clearer navigation, section labels, help text and explanations for unavailable controls; menu clicks and hover use consistent accent styling.
- Search follows client capabilities and preserves field edits.
- Updated menu and Edit Mode labels, prompts, tooltips, status text, history, chat messages and placeholders across all twelve supported locales.
- Typed HEX colors commit on Enter through the shared color-picker apply path.
- Blizzard Micro Menu and Bags controls expose horizontal and vertical orientation where the client provides it.
- Forever controller controls cover D-pad focus, confirm/cancel, dropdowns, anchors, search and switching MSUF windows.
- The on-screen keyboard supports text and exact numeric entry. Controller actions include slider adjustment, preview and Edit Mode nudges, and supported Undo/Redo.
- Localized button hints, focus highlights and haptic feedback accompany supported controller actions. Navigation releases input in combat and while Blizzard panels own it.

### Client Support & Packaging

- **Supported client paths:** Midnight 12.0.7/12.1.0/12.1.5, Classic Era 1.15.9, TBC 2.5.6, Mists 5.5.4 and WoW Forever 1.60.1 through the Mainline manifest and Interface 16001.
- The package contains the **core addon and load-on-demand Options addon**.
- The in-game Assistant is retired and no longer shipped. Its saved chat data is removed once and excluded from profile transfers. For a manual update, remove any old `MidnightSimpleUnitFrames_Assistant` folder from `Interface/AddOns`.
- WoW Forever is detected through its client marker, including the dedicated project identifier present in build 70170. Unknown clients retain a guarded fallback.
- Version reporting follows the running client. The Midnight beta manifests retain their Retail version; Classic and Forever use the 6.5 beta release version. `/msuf clientinfo` reports the detected client and addon version for bug reports.
- Menus and search hide unavailable controls, including unsupported Arena Frames, Empowered Casts, pet information and Cooldown Manager anchors. Forever group choices are limited to Party and Raid.
- Retail 12.1.5 uses the supported native aura, scheduling and pixel-rounding paths; older Mainline versions retain their compatible fallbacks.
- Mainline core and Options appear in the MSUF category in the AddOn list; version labels follow the current game type.
- Added Forever game-version targeting and Wago publishing support to the release pipeline, with expanded startup, menu-index, locale and package validation.
- The Forever menu title follows the detected client. Classic Glass, initially Forever-specific, is available alongside Midnight and Midnight Dark across supported clients.

## Bug Fixes

### Group frames and secure layouts

- Fixed group layout changes at combat entry, preserved layout capacity and role ordering for members joining during combat, and returned previewed groups to their live headers.
- Fixed small-raid Party layouts, class-priority identity reads, filters, extra-block names and housing visibility, including consistent dead/offline backgrounds.
- Newly created group and Pet buttons retain click handling and pixel alignment in combat.
- Member target frames refresh when compound unit tokens receive no native unit event.
- Healer mana rows and allied boss frames repaint when a unit token is reassigned; healer mana text receives its font before its first update.
- Raid Manager expanded state survives settings reapplication. Hidden mode leaves its toggles click-through; Forever's gamepad-opened manager stays visible with its panel and closes with it.
- Classic and Forever members without an assigned role retain their power bar when enabled for any role, while explicit role filters still apply.
- Fixed roster-slot aura rebinding, preserved subgroup geometry, configured columns, role sorting and world-entry refreshes in the unified client line.
- Fixed disappearing Forever Party, Raid and Priority frames during secure group setup. Updated initialization follows Blizzard's repaired load order.
- Saved negative-heal-absorb overrides remain consistent across group layouts and logins. Group sorting, previews and Edit Mode use the same layout settings.

### Auras and indicators

- **Removed the baked-in Blizzard icon border (#159):** runtime icons, reminders and menu/Edit Mode previews share a minimum crop while preserving stronger configured zoom.
- Classic aura lanes honor all nine anchors, the menu layer range, Player-first sorting and the correct Pet overrides.
- Combat-only filters refresh at the combat transition; AUTO dispel symbols follow the frame's strata.
- Custom auras compile on supported Classic Arena Frames. Classic Edit Mode retains click forwarding and avoids rewiring sealed native aura buttons.
- Fixed aura refreshes after profile switches, resets, imports, specialization changes and roster-slot changes.
- Fixed Friendly, Enemy and Both conditions on Classic cleanse borders, permanent-aura rules, faction updates and sorting agreement between lanes and custom containers.
- Era dispel scans retain the HARMFUL|RAID filter. Untouched sparse factory aura layouts from Alpha 18 through Beta 3 are repaired while customized aura owners are preserved.
- Filtered-out auras can reappear. Failed or interrupted full refreshes recover instead of leaving later updates stuck or half-merged.
- Shaped dispel borders use the actual debuff color. Missing Classic atlases use bundled symbol artwork, and disabled symbols clear immediately.
- Classic menus hide unsupported Pandemic-only options and show correct client-specific search entries.
- Aura icons allow clicks through to their unit frame.
- Rounded highlight borders retain their thickness and state; group highlight detection remains available when aura icons are disabled.

### Class Resources, power and status

- Class Resource settings apply after saved profiles load and stay synchronized with variants and page resets.
- Fixed explicit Mana selection and Alternative Mana overlap; classes without a mana pool no longer inherit an unusable Alternative Mana bar.
- Class resources refresh after death and resurrection. Mists Monk Chi updates after settings changes.
- Resource maxima trigger required layout changes; Stagger colors, Ironfur and aura-count visibility repaint correctly.
- Mists Burning Embers use the unmodified maximum; Affliction shards use the supported spell gate. Midnight Affliction/Demonology prediction receives cast events.
- Mists Death Knight runes use their rune-type colors unless an explicit override is selected. Combo Points and aura-based resources refresh correctly.
- Eclipse respects its text mode and removes auras that end early. Player Power regains its color after Eclipse.
- Alternative Mana returns after Edit Mode, and disabling the secondary Player HP module hides its bar.
- Resource marks use the displayed resource's range, remain above pips and handle restricted power percentages through the supported native path.
- Hidden Class Resources and detached Power keep their Edit Mode movers; attached bars retain their maintained anchor while the visible resource is inactive.
- AFK timers resume after combat, and death state updates on direct health ticks.
- Unit tooltips display available AFK/DND flags. Inline target-of-target text follows the visible edge of the name glyphs.
- Native managed class-resource bars retain Blizzard lifecycle handling while their visuals are concealed. Totem takeover restores only the frame-position flag owned by MSUF.

### Castbars and Arena Frames

- Arena bars honor Show icon, Spell name and Cast time, with corrected time-text positioning in runtime and previews.
- Castbar movers follow bars after they move, and font updates preserve cast-target class colors.
- Interrupt feedback follows the displayed cast, including late interruption events and successive rapid interrupts.
- The Interrupt Ready indicator considers all available interrupts with client-appropriate spell lists. Classic has a cooldown fallback, and the ready border retains its color after rebuilding.
- Castbar fill direction and countdown mode work together.
- TBC and Mists width matching and portrait previews include all five Arena opponents. Their castbars retain a native event frame when the shared event bus declines a subscription, and all three text regions clear their font cache after a font change.
- Arena power text refreshes when a slot binds to a different opponent, including Solo Shuffle rounds.
- Arena and Boss bars share consistent frame lifecycle handling, restore native text when needed and refresh outlines and cooldown state.
- Native managed castbars retain Blizzard lifecycle handling while MSUF conceals their visuals.
- Restricted cast, duration, swing, aura, health and power values follow supported native formatting and rendering paths.

### Shapes, portraits and prediction

- Rounded borders and masks retain the selected shape; imported Slanted styles use the current Rounded fallback when Slanted is disabled.
- Styled shaped borders and previews retain matching style, color and thickness.
- Fixed portrait rim/mask alignment, direction, zoom, foreground opacity and layering after native refreshes. Atlas artwork retains its full image and flip direction.
- Status badges and level numbers remain within native overlay limits for imported high layer values. Disabling Level also removes its fallback badge ring.
- Missing-health backgrounds no longer show a fully reversed bar at full health; rounded health backgrounds retain their intended opacity in instanced combat.
- Global font and texture changes preserve frame opacity and update affected text. Protected prediction values retain their over-absorb glow.
- Unit frames recover after instance or housing visibility changes, resume event routes and refresh stance text. Portrait variants update without a reload.
- Previews retain their layer choices, fit dropdown chips inside their panels and keep Class Resource geometry aligned with the live bar.
- Fixed black Forever preview backgrounds, with scene fallbacks on other clients. Classic previews render power gradients and the Class Resource text layer; Mists Boss previews include the boss-target marker.
- Font previews and the related default-setting inconsistencies are corrected.

### Profiles, imports and resets

- Malformed imports are staged and validated before profile creation or switching and cannot overwrite the active profile.
- Oversized compressed imports are rejected before inflation. Forever factory profiles decode their compressed CBOR format correctly.
- Missing imported fonts fall back safely, and imports validate fonts through the font registry. Incomplete startup font values no longer abort the menu or Edit Mode.
- First login and profile resets apply the factory profile instead of code defaults, including Focus Target.
- `/msuf reset` restores factory dimensions, positions, layout and text visibility. `/msuf profile <name>` saves the current settings.
- Imports preserve dispel-migration stamps and supported numeric spell IDs; variants retain the resource-extra keys needed to represent removals.
- A Blizzard Edit Mode snapshot is imported only when its import option is selected.
- Selected-frame aura imports avoid full-profile resets and repair defaults on a private copy before applying the selected settings.
- Profile deletion reassigns characters to Default or the alphabetically first remaining profile, rather than depending on table order.
- Profile names remain as typed. Scale history, dropdown alignment and page refreshes remain consistent across profile changes. Copy To preserves supported font, texture, gradient and status settings.
- Page resets retain Undo. Edit Mode Cancel and Undo cannot write an earlier profile's edits into a newly selected profile; history remains bounded for large profiles.
- New/reset Forever profiles follow the intended disabled global-scale default while preserving explicitly enabled settings, including changes made immediately after reset.

### Menu, search, Edit Mode and integrations

- Fixed exact-search targets, Unicode normalization, field-edit preservation and refreshes of visible pages without rebuilding unaffected pages.
- Fixed Class Resource card containment, left-aligned titles, spacing and preview fit on narrow windows, plus Group Anchor/class-priority wrapped text and Portrait/Healer mana spacing.
- Section switch labels toggle their feature; disabled frame scopes keep navigation and previews usable.
- Edit Mode Cancel discards unfinished text edits before restoration. Supported drag positions survive combat interruptions, and history commits defer safely through combat entry.
- Configuration and focus-preview keyboard input stop at combat entry. ConsolePort Game Menu movement and resizing wait until combat ends.
- Fixed preview lifecycle and animation behavior, including resource movement staying within Edit Mode and shared runtime/preview geometry.
- Cooldown Manager anchors are offered and applied only when supported; imported unsupported anchors fall back to the normal global anchor.
- Hiding Blizzard's TargetFrame also stops the hidden Forever ComboFrame from updating.
- Fixed repeated Forever welcome/tour prompts and analytics initialization writing to the wrong global.
- Corrected malformed Classic AddOn-list title colors that displayed a stray letter. Pet Happiness is labeled correctly on every supported client.
- Unknown clients no longer offer unsupported Arena Frames; the guarded Mainline diagnostic requests `/msuf clientinfo` where needed.

## Performance

- Hidden Unit Frames suspend their event routes until shown again.
- Unrelated power events skip resource-text work; thresholds share a resource read, and Mists rune types refresh on their native event.
- Aura sorting runs only when the selected sort mode and changed timing require it. Icon layout and shaped dispel geometry are reapplied only when their inputs change.
- Aura containers are reused after retirement. Compatible group-aura previews share compiled configuration across rows.
- Styled borders reuse textures and layout. Combat color updates avoid rebuilding border geometry.
- Closed menu sections defer controls and decoration. Repeated header layout and owned-button skin work reuse existing state.
- Cold search indexes build in short menu-task slices; exact searches retain synchronous results and prepare required lazy sections.
- Options, aura workspaces and search reuse existing page state. Color previews avoid duplicate render requests and preserve staged construction.
- Aura-resource and cast-expiry paths avoid per-event closures; shared aura countdown drivers stop when idle.
- Arena castbar geometry is checked per style change, and the Mists trinket fallback stays off unrelated combat logs.
- Completed pixel-layout setup is reused. Zoning avoids duplicate raid-header rebuilds.
- Native Mainline scheduling coalesces keyed delayed work where supported; older clients keep compatible event-driven timer fallbacks.
- Health gradients, backgrounds, protected text, prediction and aura-name fallback paths include the shared runtime's sample reuse, cached writers and bounded refresh work.
- Version information is read once at load instead of on each display or analytics pass.
- Shared client, defaults, aura, castbar and group owners reduce duplicated implementations while retaining client-specific behavior.
- Opening Options from the Game Menu shares the keybind's deferred first-load boundary, reducing first-open script-time pressure.
- Shared target-based Combo Point handling covers Classic and Forever; client defaults, Class Resources and previews use consolidated owners.
- Preview animation, factory-profile decoding and search avoid repeated work.
