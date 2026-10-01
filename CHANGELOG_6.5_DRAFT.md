# MSUF 6.5 — Full Changelog Draft

This draft covers the committed unified 6.5 line through **6.5-beta11 (29 September 2026)**. Its five highlights are additions absent from committed **Retail 6.21**; the detail below also covers client ports and extensions made in the Classic repository. It follows the full 6.0 changelog's approach: lead with the changes players will notice, then explain their scope, fixes, and compatibility. Auras3, Texture Layers, Priority Frames, Dispel Symbols, four-way bar fill, and the other established 6.0 features are not presented as 6.5 additions.

## 5 Highlights

1. **Arena Frames built into MSUF.** Arena opponents get dedicated frames with their own castbars, Auras, Edit Mode movers, settings page, and preview. Match preparation, stealth, and trinket states have their own handling. Midnight provides three opponent slots; TBC and Mists provide five. Classic Era and WoW Forever do not expose Arena Frames.
2. **A frame for your pet's target.** Pet Target is now a separate Unit Frame with its own runtime, defaults, settings, preview, and Edit Mode placement on supported clients. You can place and style it independently of the Pet frame.
3. **Buffs and debuffs on the Pet frame.** The Pet frame now has configurable Aura lanes under Pet > Auras, so the pet's effects are visible and styled on the frame itself. Classic Pet XP appears when the client supplies XP data; WoW Forever hunter pets can also show their happiness.
4. **New Slanted bar shape.** Health and other rectangular bars can use the new cut, angular edge instead of a square or rounded outline. A global switch and scope choices cover Unit Frames, Group Frames, Power bars, castbars, Class Resources, and mouseover. Runtime and menu previews use the same shape choice; saved Rounded styles return when Slanted is disabled.
5. **One MSUF codebase for the supported WoW versions.** The unified package has client-specific manifests and capabilities for Midnight Mainline 12.0.7, 12.1.0, and the prepared 12.1.5 path; Classic Era 1.15.9; Burning Crusade Classic 2.5.6; Mists of Pandaria Classic 5.5.4; and WoW Forever 1.60.1. Controls and runtime paths follow the client that is actually running, including separate version reporting and a client-info command for bug reports.

## Package and Client Support

- The main addon and the load-on-demand Options each ship manifests for Mainline, Vanilla, TBC, and Mists. WoW Forever is identified within the Mainline family by its Camelot client marker and uses its own capability and factory-profile paths.
- The Mainline manifests declare 12.0.7, 12.1.0, 12.1.5, and WoW Forever's Interface 16001. The 12.1.5 code paths activate only when their native APIs are present; 12.1.0 keeps guarded Aura, timer, and layout fallbacks.
- The AddOn list reports the version for the current game type. Midnight still reports 6.20 in the beta11 manifests; Classic and WoW Forever report 6.5-beta11. `/msuf clientinfo` prints the detected client family, flavor, game mode, and addon version.
- Menus and search omit controls unsupported by the running client. WoW Forever has no Arena Frames or Evoker Empowered Cast options; Classic clients do not offer unavailable Cooldown Manager anchors.
- Fresh installs, new profiles, and full resets use client-aware factory layouts. Existing customized profiles keep their settings. WoW Forever has its own supplied layout.
- The in-game Assistant is retired and no longer ships; its saved chat history is removed once and never travels in profile exports or copies. After a manual install, delete the old `MidnightSimpleUnitFrames_Assistant` folder from `Interface/AddOns` (an app update removes it for you).

## Arena Frames

- Arena Frames have their own Unit Frame options, Aura and castbar configuration, Edit Mode movers, and previews. Arena Group Frames use Party rather than Raid settings.
- Midnight supports arena1–3. TBC and Mists support arena1–5, including all five castbars and portrait previews. Clients without Arena slots do not offer the feature.
- Opponent slots refresh their power text when reassigned between Solo Shuffle rounds. Castbar events, font changes, and trinket fallback are handled per relevant Arena state; the Mists combat-log fallback subscribes only inside an arena.
- Arena castbar geometry is validated when its style changes instead of before every cast.

## Pet Target and Pet Auras

- Pet Target can be enabled and placed separately from Pet. Its own defaults, frame settings, status and text options, preview, and Edit Mode path make it a complete Unit Frame rather than a borrowed Pet display.
- Pet buffs and debuffs have their own Aura controls on the Pet page. The Pet frame also exposes Classic Pet XP only when that client provides the data.
- WoW Forever hunter pet happiness can use the client's native three-state artwork where available. Its full-name, first-name, and surname display choice is separate from the Pet Aura lanes.

## Bar Shapes, Portraits, and Other Visual Changes

- Slanted covers frame surfaces, embedded or detached Power, castbars, Class Resources, and mouseover where those surfaces are enabled. Unit and Group previews resolve the same Slanted, Rounded, or Square result as the live frame.
- Switching the global Slanted or Rounded option does not discard a saved frame style. Imported profiles and preview rebuilds use the active fallback.
- An optional round Level badge with a gold rim follows the level indicator's size, position, and layer, with bundled artwork on clients without the native atlas.
- The Retail 6.21 portrait dragons are available in the unified client line. 6.5 adds an optional bottom-right gold connector and a separate rim choice; the live Runtime Preview does not save a false unit classification.
- Texture Layers can select native Blizzard atlases with matching runtime and preview crops, plus a texture fallback on older clients. Leader, assistant, and combat indicators use native art when available.
- The menu offers Midnight, Midnight Dark, and Classic Glass appearances on supported clients.

## Group Frames, Status, and Classic Information

- Classic Era, TBC, and WoW Forever can show Threat % on supported Target, Focus, Boss, Party, and Raid frames. Placement, size, background, and low/medium/high colors are adjustable; Party starts enabled in the supplied factory profile and Raid is optional.
- The Classic clients receive the Retail difficulty-colored Level Text behavior with editable color bands, plus the option to gray names and relevant health colors for mobs tagged by another player.
- Classic Era and WoW Forever channel ticks use rank-specific spell data, with up to fifteen markers when supported. TBC and Mists retain their previous channel table until their spell data is verified.
- Supported Classic clients can opt into incoming-heal prediction from all healers. Player-only prediction remains the default.
- Class Resources and detached Player Power have independent Edit Mode movers and geometry. Temporarily inactive resources, including a Druid resource outside its active form, retain an editable mover.

## Auras, Castbars, and 12.1.5 Preparation

- The prepared 12.1.5 Mainline path uses Blizzard-owned Pandemic animation regions, suppresses those effects in Edit Mode Aura previews, and exposes native Aura caster names in tooltips when available.
- Keyed delayed work on 12.1.5 uses the client's native timed signal map; 12.1.0 keeps its event-driven timer fallback. Supported 12.1.5 frames use native nearest-pixel rounding.
- Classic Era, TBC, and Mists Aura filters match readable names when a spell rank or cast ID differs from the visible Aura ID. WoW Forever uses a catalog derived from its client locale exports.
- A full Aura refresh can recover after interrupted or over-budget work instead of leaving later refreshes stuck. Classic Aura lanes also restore filtered icons, permanent-Aura rules, sorting, and roster-slot rebinding.
- Dispel Symbols fall back to bundled artwork when a Classic client lacks the 12.1 atlas. Client-specific menus hide effects the client cannot render.

## Profiles, Menu, Edit Mode, and Suite

- Selected Unit Frame export/import can transfer Player, Target, Target of Target, Pet, Focus, Focus Target, Boss, or Arena frames where supported. Each selection carries that frame's settings, Auras, and castbar; other frames and shared appearance stay with the receiving profile.
- Invalid selections and imports with unsupported frames or unrelated settings are rejected before applying. Full-profile and existing category transfers keep their established formats.
- MSUF Suite can participate in profile and module transfer, profile lifecycle, Undo/Redo, global-font refresh, and the Essential cooldown-row anchor when installed. Anchoring Class Resources to that row requires user acceptance and default placement.
- MSUF and Suite factory resets are separate confirmed actions. The Suite reset is shown only when its reset API is available.
- WoW Forever limits Group Frame choices to its available Party and Raid types. Classic-specific options, previews, and search routes follow the active client.

## Retail Development Since 6.0 Included in the Unified Line

These are later Retail changes brought into the 6.5 source. They extend the 6.0 baseline, but they are not the five new highlights that distinguish this repository from Retail 6.21.

### Unit and Group Frames

- Unit and Group health backgrounds offer Full bar or Missing health only fill with configurable color sources. Prediction and absorb overlays can stay visible while the underlying health bar fades.
- Unit Frames can hide at full health and appear when injured. Name, Health, and Power text can each be limited to mouseover with their own fade timing.
- Raid role sorting can order tanks, healers, and damage dealers across the whole raid. Preserved subgroups and configured columns keep their secure layout behavior.
- The Boss Preview shows incoming heals, absorbs, heal absorbs, and absorb text, so those settings can be judged without a live boss.
- Player Power can explicitly select Mana instead of Automatic where supported, and Class Resource text can show Current, Maximum, or both while keeping resource-specific formats.

### Auras and Castbars

- Buff and Debuff lanes own their layout, filters, effects, ordering, and visibility; their icon appearance remains shared by Aura type. The same ownership reaches Menu, Edit Mode, and search controls.
- The curated MSUF Highlights Group Buff filter and Custom Priority ordering for Target Dots and Custom 1–3 Aura containers are included. Existing profiles retain their chosen filters.
- The blacklist workspace can collect blockable Auras during combat for review afterward, and manual entries can distinguish a cast ID from the Aura ID actually shown.
- Non-Player Auras can filter encounter and environmental debuffs without including player or pet effects.
- Focus Kick can be shown beside the Focus castbar; interrupted-cast feedback and castbar text handling retain their later Retail fixes.

### Menu and Profile Experience

- Section headers carry their own on/off switch, current-value summary, and section action menu. Disabled frame scopes dim their settings while leaving selection and preview available.
- The compact color picker accepts a typed HEX value on Enter. The unified menus carry the twelve-locale translation pass from the Retail line.
- The supplied factory profile carries the later Retail castbar direction, group-cleanse border, and Target Aura placement; client-specific variants adapt it without overwriting customized profiles.

## Fixes and Performance

- Hidden Unit Frames suspend their event routes until shown again. Aura sorting, icon layout, and shaped Dispel Border work run only when the state relevant to them changes.
- Classic Party and Raid frames retain subgroup geometry, configured columns, role sorting, and member updates after roster or zone changes. WoW Forever group initialization follows its beta client's secure setup path.
- Classic class resources refresh after death and resurrection; Mists Monk Chi updates after settings changes. Explicit Mana selection and Alternative Mana no longer conflict with the active resource bar.
- Portrait masks, rings, zoom, opacity, and artwork layering stay aligned after native refreshes. High imported layer values no longer place status badges outside the native overlay range.
- Font and factory-profile startup failures no longer abort the menu or addon. Profile scale history, menu dropdown alignment, and Classic Aura preview layout received targeted fixes.

## Draft Boundary

This is the committed **Retail `f7e8e3f1` / Classic `8b191b72`** comparison, not the final 6.5 release text. Current uncommitted changes in both checkouts and planned features are outside it, except the Assistant retirement under Package and Client Support, which changes what a manual install must contain. The 12.1.5 path is prepared in source; this draft does not claim final live-client, combat, visual, or performance certification.
