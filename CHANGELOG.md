# Midnight Simple Unit Frames Changelog

## 6.0-Beta1 - 2026-07-01

### Kurz gesagt
- 6.0-Beta1 ist der echte 5.60 -> 6.0 Beta-Schnitt: alle Alpha-Aenderungen 1 bis 8 plus die Beta-Stabilisierung sind enthalten.
- Umfang seit 5.60: 222 Commits, 726 geaenderte Dateien, 212631 neue und 147999 entfernte Zeilen; davon 533 neue und 133 entfernte Dateien.
- Ziel ist WoW 12.1. 5.60 bleibt die letzte 5.x-Basis fuer den alten 12.0.x-Pfad.

### Die grossen Unterschiede zu 5.60
- Auras: Auras2 ist raus, Auras3 ist drin. MSUF nutzt jetzt Blizzards 12.1 AuraContainer/AuraButton-System statt eigener Aura-Scanner und Renderer.
- Aura-Bedienung: Buffs, Debuffs, Shared-vs-Custom Styles, Cooldowntext, Stacks, Reverse Swipe, Duration Bars, native Filter und Dispel-Visuals sind pro Scope sauber editierbar.
- Castbars: Player, Target, Focus, Boss, Focus Kick und Interrupt Ready laufen im Hauptaddon, inklusive Channels, Empower, Spark, Glow, Latenz, Icons und Live-Previews.
- Unit Frames: Health, Power, Text, Alpha, Prediction Bars, Load Conditions, Status, Borders, Range Fade und Dispatch laufen ueber die neue 6.x Engine.
- Group Frames: Party, Raid und Mythic Raid wurden neu aufgebaut, inklusive secure Headers, Blizzard-Fallback, Previews, Status-/Spell-Indikatoren, Health Fade, Offline/Dead Looks, Rollenfiltern, Dispel/Highlight-Overlays und Range.
- Assistant: aus Suche/FAQ wurde ein echter Einstellungs-Assistent mit Kommandos, Followups, Diagnose, Undo, Profilaktionen, Seiten-Routing und breiter Abdeckung fuer Auren, Gruppen, Castbars, Class Resources und Unitframes.
- Menu2: neues Shell/UI-System mit Dashboard, Nav Rail, Fenstersteuerung, Seiten-Previews, Zoom/Pan, Anchor Picker, Bug Report Flow und Ingame-Changelog.
- Profile: MSUF4 Export/Import, Legacy MSUF2/MSUF3 Fallbacks, 5.60 -> 6.0 Migration, Font-/Texture-Fallbacks und Normalisierung alter Alpha-Profile.
- Integrationen und Optik: NSRT Nicknames, Third-Party Anchors, Skiron Cooldown Anchors, neue Class-Resource Shapes, PvP Flags, native Dispel-Sensoren und neue runde Frame-Medien.

### Beta1 nach Alpha8
- Aura Duration Bars und native Dispel Sensors sind jetzt in Runtime, Preview, Defaults, Menu und Assistant angebunden.
- Assistant und Parser verstehen mehr Followups, Aura-Kommandos, Group-Frame-Status, Bar-/Overlay-Optionen, Load Conditions und konkrete Korrekturaktionen.
- Neue Load Conditions und Rollenfilter decken mehr Housing-/Visibility-Faelle ab; Aggro-Border koennen gezielter nach Rollen angezeigt werden.
- Castbar-Fixes fuer Width Mode, Text, Interrupt Ready und Refresh-Verhalten; Class-Bar Quick Setup setzt Player Power wieder korrekt.
- Menu-Previews, Keyboard-Handling, Group Layout und Group Status wurden fuer Beta stabilisiert.
- Font-Anwendung, lokale Dev-Dateien, Bytecode-Reste und Release-Vorbereitung wurden bereinigt.

### Alpha-Verlauf kompakt
- Alpha 1: erster oeffentlicher 6.x Kern mit neuer Menu2 UI, Previews, integrierten Castbars, Class Resources, Group-Frame-Arbeit, Profil-Import/Export und erstem Auras3-Pfad.
- Alpha 2: Umstieg auf Blizzards native 12.1 AuraContainer, neue Aura-Filter, bessere Aura-Performance, Castbar-/Class-Power-/Group-Frame-Cleanup und Smoke Checks.
- Alpha 3: Aura-Farben nach Timer, mehr Assistant-Kontext, bessere Geometry-Followups und weitere Castbar-/Aura-Notizen.
- Alpha 4: Shared Aura Style vs. per-unit Text-Overrides, Cooldowntext-Anker, bessere Aura-Previews, Followups und Boss-Preview-Refresh.
- Alpha 5: Reverse Cooldown Swipe, klarere Shared/Custom Aura-Steuerung und wichtige Castbar-Fixes fuer Channels, Empower und Player-Castbar-Suppression.
- Alpha 6: Party Targeted Spell Indicators, NSRT Nicknames, MSUF4 Profilstrings, bessere Legacy-Imports, Ingame-Changelog und mehr Assistant-Abdeckung.
- Alpha 7: Edit-Mode Logo-Intro und CurseForge-only Alpha-Release-Pfad.
- Alpha 8: Aura-Dragging, Menu-Performance, Combat-Performance und mehr Group-/Bar-Control-Abdeckung im Assistant.
- Beta1: Stabilisierung der Alpha-Linie fuer einen echten 5.60 -> 6.0 Beta-Test.

### Testfokus fuer Beta
- Vor dem Test wichtige 5.60 Profile exportieren.
- Nach Import alter Profile Player, Target, Focus, Boss, Party, Raid, Mythic Raid, Target of Target und Focus Target pruefen.
- Auren auf WoW 12.1 testen: Target-/Focus-Wechsel, Party/Raid-Konvertierung, Dispel-Debuffs, Duration Bars, Cooldowntext, Stacktext und Group Aura Filter.
- Party Targeted Spell Indicators in 5er Content mit aktivierten Enemy Nameplates testen.
- Profile, Font-/Texture-Fallbacks, NSRT Nicknames, externe Anchors, Castbar Ownership, Edit Mode und /reload nach Combat testen.


## 6.0-alpha8 - 2026-06-30

### Highlights
- Added draggable Auras3 edit handles so aura lanes can be moved more directly in Edit Mode.
- Improved Menu2 and combat hot-path performance before the Beta cut.
- Expanded Assistant coverage for group-frame and bar controls.
- Prepared the MSUF_6.0A8 package as the last alpha before Beta1.

### Auras, Menu, And Performance
- Improved aura movement, aura edit-mode state, target/focus aura refresh, and range fade related refresh behavior.
- Reduced menu preview rebuild work and tightened several Menu2 window/page refresh paths.
- Improved combat performance across runtime update paths that were too noisy during alpha testing.
- Updated group bar/page controls and related Assistant routing so more group-frame settings can be found and changed naturally.

## 6.0-alpha7 - 2026-06-30

### Highlights
- Added the MSUF Edit Mode Logo Wake intro using the high-resolution MSUF logo asset.
- Added a CurseForge-only release path so Alpha 7 can be published without also uploading to Wago.

### Edit Mode
- Updated the logo intro so the logo fades in smoothly, gets a brief cyan wake glow, then lets the ring trace run once and close.
- Kept the intro animation scoped to the Edit Mode opening sequence; its `OnUpdate` is removed again when the intro stops.

### Release And Notes
- Release name: MSUF_6.0A7.
- Bumped VERSION and addon metadata to 6.0-alpha7.
- This tag is intentionally an alpha build; use `6.0-alpha7` as the publish tag.
- Alpha 7 is intended for CurseForge-only publishing.

### Alpha Testing Notes
- This is an alpha build for the 6.0 branch. Export important profiles before testing.
- Please test opening and leaving Edit Mode repeatedly and verify the logo intro does not continue running after Edit Mode closes.
- Please test opening Edit Mode shortly before/after combat to confirm no combat overhead or lingering animation state.

## 6.0-alpha6 - 2026-06-29

### Highlights
- Added party targeted spell indicators that can show enemy nameplate casts on the targeted party frame, with icon stack, placement, timer text, and time-based text color controls.
- Added optional Northern Sky Raid Tools nickname integration for unit-frame display names.
- Improved profile import/export and migration handling, including the new MSUF4 compact profile format and better fallback decoding for older MSUF2/MSUF3 profile strings.
- Added the bundled in-game changelog prompt so users can open release notes from the dashboard after updating.

### Group Frames And Indicators
- Added party-only targeted spell tracking for enemy casts, including cast/channel pickup, retarget verification, cooldown text, and per-party-frame icon placement.
- Added Targeted Spells controls to Group Indicators with enable mode, icon size/count/layer, anchor/growth, offsets, cooldown text, and timer color thresholds.
- Updated group-frame defaults and configuration so targeted spell settings are carried by the party profile scope.
- Improved group preview rendering for targeted spell/status indicator placement and native preview refreshes.

### Profiles, Imports, And Defaults
- Added MSUF4 profile export strings while keeping import compatibility for MSUF3 and legacy MSUF2 variants.
- Improved compact profile decoding by trying Blizzard decompression, direct CBOR, and LibDeflate-backed fallbacks where available.
- Added profile translation and normalization for older 6.0 alpha profile layouts, including aura geometry, text/name shortening aliases, status indicator fields, and group-frame scope fields.
- Hardened profile runtime apply calls so one apply error is captured instead of breaking the whole profile operation.

### Menu, Assistant, And Integrations
- Added NSRT nickname resolver support with combat-safe refresh behavior and cache updates when NSRT nickname data changes.
- Expanded Assistant parsing and registry coverage for aura style/filter commands, group aura lane geometry, targeted spell controls, global bar settings, and base global options.
- Improved dashboard and nav-rail behavior, including hover scale defaults and typewriter/changelog handling.
- Clarified Global Bars texture inheritance: unit scopes keep Shared textures while group-frame scopes can override textures and gradients.
- Temporarily disabled dispel/purge border controls for 12.1 PTR until native AuraContainer exposes the needed detection path again.

### Fonts, Text, And Visuals
- Improved font path probing and safe font fallback resolution for missing or unavailable fonts.
- Updated text layout/status paths to handle layer frames, status fonts, name shortening, and profile-translated text fields more consistently.
- Refined castbar, class power, aura popup, group preview, and Edit Mode HUD rendering details.
- Updated superellipse media assets used by the rounded frame visuals.

### Release And Notes
- Release name: MSUF_6.0A6.
- Bumped VERSION and addon metadata to 6.0-alpha6.
- Regenerated the in-game dashboard changelog data for Alpha 6.
- Hardened the release workflow and Wago upload step so alpha metadata, alpha tags, and A-style alpha release names cannot be uploaded to Wago as stable/release.
- This tag is intentionally an alpha build; use `6.0-alpha6` as the publish tag so Wago receives `stability = alpha`, CurseForge receives an alpha release type, and GitHub marks the release as prerelease.

### Alpha Testing Notes
- This is an alpha build for the 6.0 branch. Export important profiles before testing.
- Please test Targeted Spells in 5-player party content with enemy nameplates enabled, especially casts that retarget or channel.
- Please test importing older Alpha 2 through Alpha 5 profile strings, especially profiles with custom aura positions, fonts, textures, and group-frame text settings.
- Please test NSRT nickname display with NSRT global nicknames enabled and disabled.

## 6.0-alpha5 - 2026-06-28

### Highlights
- Added reverse cooldown swipe options for aura icons, including defaults, profile export normalization, previews, and Assistant/menu registry coverage.
- Improved Aura Style and Aura Filters menu scope handling with clearer shared-vs-custom override controls for unit frames and group frames.
- Fixed castbar channel and empowered preview/runtime behavior after the Alpha 4 castbar pass.
- Fixed castbar previews so player/target/focus/boss preview refreshes and Blizzard player castbar suppression behave more reliably.

### Aura Menu And Assistant
- Added cooldown swipe direction controls for unit and group aura lanes.
- Updated shared aura previews to distinguish normal and reverse swipe samples instead of grouping them only by icon size.
- Added shared/custom override bars for aura style and filter pages so inherited settings are easier to see and reset.
- Expanded Assistant coverage for aura style/filter settings and group aura lane controls.

### Castbars
- Hardened castbar preview refreshes and removed fragile preview driver state.
- Fixed channel and empowered castbar preview updates, including stage blink handling and safer color/option lookups.
- Stopped writing addon-owned suppression fields onto Blizzard castbar frames; MSUF now suppresses Blizzard player castbar events directly when MSUF owns the player castbar.
- Removed unsafe SetOnUpdateMode calls from castbar runtime paths.

### Release And Notes
- Release name: MSUF_6.0A5.
- Bumped VERSION and addon metadata to 6.0-alpha5.
- Regenerated the in-game dashboard changelog data for Alpha 5.
- This tag is intentionally an alpha build; the release workflow maps alpha tags to Wago alpha stability, CurseForge alpha release type, and GitHub prerelease.

### Alpha Testing Notes
- This is an alpha build for the 6.0 branch. Export important profiles before testing.
- Please test aura cooldown swipe direction on player, target, focus, boss, party, and raid frames.
- Please test normal casts, channels, empowered casts, castbar previews, and switching between Blizzard and MSUF player castbar ownership.

## 6.0-alpha4 - 2026-06-27

### Highlights
- Release name: MSUF_6.0A4.
- Aura style editing now separates shared layout inheritance from per-unit text style overrides, so individual frames can adjust aura text without cloning all aura layout data.
- Unit, group, and shared aura previews now show cooldown and stack text placement more accurately, including per-lane cooldown anchors.
- Assistant followups and aura registries now cover more natural language commands for aura lanes, unit aura settings, and text-area adjustments.
- Boss frame previews refresh more reliably outside encounters, including when reopening the unit-frame page.

### Aura Style And Preview
- Added cooldown text anchor support for shared, buff, and debuff aura lanes in the Auras3 model, edit-mode preview path, live unit-frame compiler, and Auras menu controls.
- Added sparse visual override normalization so inherited aura layout keys are not treated as per-unit style overrides unless the scope actually customizes text or style behavior.
- Rebuilt unit and group aura style controls into focused preview, text feature, stack-count, cooldown text, and behavior sections.
- Shared aura previews now group frame samples by actual configured icon size and label the affected frame group instead of showing one generic preview.
- Added scope-aware cooldown timer formatting so Shared, unit, and group aura styles can choose below how many remaining seconds decimal text is shown; live aura text still uses Blizzard's C-side DurationTextBinding/NumericRuleFormatter path.
- Group aura style controls now expose cooldown and stack text anchors, offsets, dynamic scaling, tooltip, sorting, and player-aura preference in collapsible sections.

### Assistant And Menu
- Improved followup parsing for bare exact-number edits such as "set to 12" and for applying the previous HP/name/power text adjustment to another text area.
- Expanded aura assistant registry coverage for cooldown text anchors, lane style values, use-shared-style behavior, and unit aura lane commands.
- Added larger change/reload guidance for assistant-driven changes that may need a UI reload.
- Refined assistant context handling from the previous local commit, including no-match resolution, geometry followups, edit-mode previews, and registry exact aliases.
- Updated the Boss frame preview copy and refresh logic so previewed boss frames are not left hidden after menu navigation.

### Release And Notes
- Bumped addon metadata from 6.0-alpha3 to 6.0-alpha4 and VERSION from 6.0-alpha2 to 6.0-alpha4.
- Regenerated the in-game changelog data from this changelog for the A4 package.
- Kept the existing release automation path compatible with alpha publishing by using the 6.0-alpha4 publish tag and MSUF_6.0A4 as the release name.

## 6.0 Alpha 3 - 2026-06-27

### Highlights
- Added timer-based aura color work after Alpha 2.
- Improved assistant context, geometry followups, exact alias handling, edit-mode controls, and preview routing.
- Updated castbar, aura, and assistant release notes after the Alpha 3 packaging pass.

### Notes
- Alpha 3 was an interim alpha build on the 6.0 branch before the A4 aura style and assistant followup pass.

## 6.0 Alpha 2 - 2026-06-27

### Highlights
- New Aura Container System: MSUF now uses WoW 12.1's native AuraContainer and AuraButton system for live aura display instead of the older custom aura scanner/render path from Alpha 1.
- Buffs, debuffs, and important defensive/external auras are handled as separate native aura lanes, so aura updates should feel smoother and more reliable during target swaps, group changes, and combat.
- Unit frames, party frames, raid frames, and mythic raid frames now share the same Auras3 foundation, with Blizzard doing the heavy aura tracking and MSUF focusing on layout and styling.
- Aura containers allocate only the configured number of icons, which keeps the system predictable and avoids unnecessary preloading spikes.

### Aura Settings And Filtering
- Added clearer aura controls for unit frames and group frames, including separate styling for buffs and debuffs.
- Added native group aura filter choices such as raid buffs, raid debuffs, dispellable debuffs, crowd control, external defensives, and big defensives.
- Added optional debuff type visuals: off, colored border, or colored border with a type symbol.
- Cooldown swipe, cooldown text, stack count, tooltip behavior, size, spacing, growth direction, and text placement can now be adjusted per aura lane.
- Existing legacy blacklist data is kept, but exact SpellID-style filtering is limited in this alpha because the new native AuraContainer path exposes Blizzard filter strings rather than MSUF's old custom predicate system.

### Menu And Assistant Improvements
- The Auras page was rebuilt around scope and lane workflows, making it easier to edit Shared, Player, Target, Focus, Boss, Party, and Raid aura behavior.
- The Assistant gained much broader coverage for auras, group auras, castbars, class resources, unit frames, profiles, dashboard actions, and troubleshooting.
- Search and dashboard routing now expose more setup tasks directly, so common configuration areas are easier to find.
- Many large Assistant registry files were split into smaller pieces to reduce load risk and make future changes easier to maintain.

### Unit Frames, Castbars, And Class Resources
- Unit frame refresh paths received more targeted updates for visuals, text, alpha, range fade, status indicators, and aura-related state.
- Castbar runtime code received cleanup across player, target, focus, boss, channel ticks, empower casts, focus kick, and Interrupt Ready paths.
- Class resource handling received follow-up fixes around Player HP integration, preview behavior, alternate mana, and balance druid state.
- Group frame visuals, status handling, spell indicators, and preview paths received additional Alpha 2 cleanup.

### Performance And Stability
- Removed much of the Alpha 1 custom aura scan/diff/render work from the live display path.
- Aura refreshes now lean on Blizzard's native incremental aura updates, while MSUF coalesces expensive layout/configuration changes.
- Target and focus aura swaps are refreshed more deliberately so stale aura displays are less likely after changing targets.
- Several runtime paths were simplified so errors surface during alpha testing instead of being hidden by broad fallback wrappers.
- Added local smoke and quality checks for Assistant parsing, group status runtime behavior, namespace safety, spell indicator data, and general addon quality gates.

### Alpha Testing Notes
- This is still an alpha build. Export important profiles before testing.
- Please test auras on player, target, focus, boss, party, raid, and mythic raid frames.
- Please test target switching, focus switching, entering/leaving groups, raid conversion, combat lockdown, dispel visuals, stack counts, cooldown text, and tooltip behavior.
- If an old aura blacklist or exact spell filter no longer behaves like Alpha 1, report it with the spell name, SpellID, unit frame, and aura lane.

## 6.0 Alpha 1 - 2026-06-24

### Alpha 1 Baseline
- First public 6.0 alpha package for the rewritten MSUF 6.x core.
- Introduced the rebuilt Menu2 configuration UI, expanded previews, integrated castbars, class resource updates, group-frame runtime work, profile import/export work, and the first Auras3 alpha path.
- This build is the comparison baseline used for the Alpha 2 notes above.
