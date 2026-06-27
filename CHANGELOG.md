# Midnight Simple Unit Frames Changelog

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
