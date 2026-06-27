# Midnight Simple Unit Frames Changelog

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
