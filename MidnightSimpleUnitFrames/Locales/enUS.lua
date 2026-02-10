local L = LibStub("AceLocale-3.0"):NewLocale("MidnightSimpleUnitFrames", "enUS", true)
if not L then return end



--SlashMenu
L["Main Menu"] = true
L["Quick tools & UI scale (same content as /msuf options)."] = true

L["Profile: "] = true
L["   •   Edit Mode: "] = true
L["Quick Actions"] = true
L["Toggle Edit Mode"] = true
L["Enter MSUF Edit Mode to drag frames and adjust positions."] = true
L["Reset Frame Positions"] = true
L["Resets MSUF frame positions + visibility to defaults (active profile)."] = true
L["Profile"] = true
L["Active profile:"] = true
L["Open Profiles"] = true
L["Show"] = true
L["Hide"] = true
L["Hidden. Click Show to reveal slash commands + power tools."] = true
L["Scale & Layout"] = true
L["Presets"] = true
L["Load preset"] = true
L["Applies the selected preset to your current active profile. This overwrites settings (export first if unsure)."] = true
L["Global UI Scale"] = true
L["Applies MSUF's global scale preset for 1080p-like setups and reloads your UI. Auto restores Blizzard scaling on reload."] = true
L["Applies MSUF's global scale preset for 1440p-like setups and reloads your UI. Auto restores Blizzard scaling on reload."] = true
L["Stops enforcing MSUF global scale and restores your previous Blizzard UI scale."] = true
L["Increase UI Scale"]  = true
L["Decrease UI Scale"]  = true
L["UI Scale (Global)"] = true
L["Scales the entire WoW UI (UIParent). 100% = 1.0, 10% = 0.10. This sets the preset to Custom."] = true
L["Current: ..."] = true
L["Current: %.3f"] = true
L["UI Scale (Global)"] = true
L["Reset"] = true
L["Reset UI Scale"] = true
L["Resets the global UI scale back to 100% (1.0) and marks it as Custom preset."] = true
L["Scaling OFF"] = true
L["Disable ALL MSUF scaling"] = true
L["Turns off all scaling MSUF applies (global UI scale + MSUF-only scale), then reloads your UI. Blizzard handles scaling."] = true
L["Overwrites your current active profile settings."] = true





L["Dashboard"] = true
L["Unit Frames"] = true
L["Player"] = true
L["Target"] = true
L["Target of Target"] = true
L["Focus"] = true
L["Boss Frames"] = true
L["Pet"] = true
L["Frame Basics"] = true
L["Enable this frame"] = true
L["Show name"] = true
L["Show HP text"] = true
L["Show power text"] = true
L["Reverse fill (HP/Power)"] = true
L["Portrait Off"]   = true
L["2D Portrait Left"] = true
L["2D Portrait Right"] = true
L["3D Portrait Left"] = true
L["3D Portrait Right"] = true

L["Player Alpha"]   = true
L["Target Alpha"]    = true
L["Target of Target Alpha"] = true
L["Focus Alpha"]     = true
L["Boss Alpha"]      = true
L["Pet Alpha"]       = true
L["Sync both"]       = true
L["Keep text + portrait visible"] = true
L["Alpha sliders affect"] = true
L["Foreground"]      = true
L["Background"]      = true
L["Alpha in combat"] = true
L["Alpha out of combat"] = true

L["Castbar"] = true
L["Inline Text"] = true
L["Show ToT text in Target frame"] = true
L["Enable player castbar"] = true
L["Enable target castbar"] = true
L["Enable focus castbar"] = true
L["Enable boss castbars"] = true
L["Show player cast time"] = true
L["Show target cast time"] = true
L["Show focus cast time"] = true
L["Show boss cast time" ] = true
L["Icon"] = true
L["Text"] = true
L["Show interrupt"] = true
L["Indicator"] = true
L["Show leader/assist icon"] = true
L["Show raid marker icon"] = true
L["Show level"] = true
L["Anchor"] = true
L["Size"] = true
L["Resets current indicator"] = true
L["Resets X/Y, Anchor and Size back to defaults."] = true

L["Boss spacing"] = true

L["Status icons"] = true
L["Combat"] = true
L["Rested (player only)"] = true
L["Incoming Rez"] = true
L["Anchor"] = true
L["Size"] = true
L["Icon"] = true
L["Test mode"] = true
L["Status icons test mode"] = true
L["Use Midnight style icons"] = true
L["Combat"] = true
L["Rez"] = true
L["Rested"] = true


L["Options"] = true

L["Bars"] = true
L["Bar appearance"] = true
L["Absorb display"] = true
L["Absorb Display"] = true
L["Absorb off"] = true
L["Absorb bar"] = true
L["Absorb bar + text"] = true
L["Absorb text only"] = true
L["Absorb bar anchoring"] = true
L["Anchor to healthbar edge (default)"] = true
L["Anchor to inside padding (prevents clipping)"] = true
L["Absorb bar texture (SharedMedia)"] = true
L["Test absorb textures"] = true
L["Bar texture (SharedMedia)"] = true
L["Gradient Options"] = true
L["Border & Text Options"] = true
L["Enable HP bar gradient"] = true
L["Enable power bar gradient"] = true
L["Gradient strength"] = true
L["Enable HP bar gradient"] = true
L["Enable power bar gradient"] = true
L["Gradient strength"] = true
L["Outline thickness"] = true
L["Power Bar Settings"] = true
L["Show power bar on target frame"] = true
L["Show power bar on boss frames"] = true
L["Show power bar on player frames"] = true
L["Show power bar on focus"] = true
L["Power bar height"] = true
L["Embed power bar into health bar"] = true
L["Show power bar border"] = true
L["Border thickness"] = true
L["Textmode HP / Power"] = true
L["Text Separators"] = true
L["Health (HP)"] = true
L["Power"] = true
L["Selected: Player"] = true
L["Click a MSUF unitframe (Player/Target/Focus/ToT/Pet/Boss) to choose which unit these spacer settings apply to."] = true
L["Works only when the corresponding text mode is set to 'Full value + %' (or '% + Full value')."] = true
L["HP Spacer on/off"] = true
L["HP Spacer (X)"] = true
L["Power Spacer on/off"] = true
L["Power Spacer (X)"] = true


L["Fonts"] = true
L["Font Settings"] = true
L["Font color & style"] = true
L["Global font"] = true
L["Text sizes"] = true
L["Global defaults. Frames inherit unless overridden in Unitframes > Text."] = true
L["Name"]   = true
L["HP"]     = true
L["Power"]  = true
L["Castbar"] = true

L["Text style"] = true
L["Use bold text (THICKOUTLINE)"] = true
L["Disable black outline around text"] = true
L["Add text shadow (backdrop)"] = true
L["Name colors"] = true
L["Color player names by class"] = true
L["Color NPC/boss names using NPC colors"] = true
L["Color power text by power type"] = true
L["Name display"] = true
L["Shorten unit names (except Player)"] = true
L["Truncation style"] = true
L["Keep start (show first letters)"] = true
L["Keep end (show last letters)"] = true
L["Max name length"] = true
L["Reserved space"] = true

L["Reset overrides"] = true
L["Clears per-unit Name/Health/Power and per-castbar Cast Name/Time font size overrides so everything inherits the global defaults again."] = true




L["Auras 2.0"] = true
L["Midnight Simple Unit Frames - Auras 2.0"] = true
L["Auras 2.0: Target / Focus / Boss 1-5.\nDefaults show ALL buffs & debuffs. This menu controls a shared layout for these units."] = true
L["MSUF Edit Mode"] = true
L["Exit MSUF Edit Mode"] = true
L["MSUF Edit Mode"] = true
L["MSUF: Can't toggle Edit Mode in combat."] = true
L["MSUF Edit Mode"] = true
L["Toggle MSUF Edit Mode (only affects Midnight Simple Unit Frames)."] = true
L["Auras 2.0"] = true
L["Enable Auras 2.0"] = true
L["Master toggle. When off, no auras are shown for Target/Focus/Boss."] = true
L["Enable filters"] = true
L["Edit filters:"] = true
L["|cff9aa0a6No overrides active.|r"] = true
L["Master for all filtering for the selected profile (Shared or a per-unit override). When off, no filtering/highlight is applied."] = true
L["Enable Masque skinning"] = true
L["Skins Auras 2.0 icons with Masque (if installed).\n\nWarning: Highlight borders may look odd with some Masque skins."] = true
L["Masque is not loaded/ready. Enable/load the Masque addon, then /reload."] = true
L["Override shared filters"] = true
L["When off, this unit uses Shared filter settings. When on, it uses its own copy of the filters."] = true
L["Override shared caps"] = true
L["When off, this unit uses Shared caps (Max Buffs/Debuffs, Icons per row). When on, it uses its own caps."]    = true
L["Reset overrides"] = true
L["Turns off Override shared filters and caps for all units and reverts them to Shared."] = true
L["Preview in Edit Mode"] = true
L["When enabled, placeholder auras can be shown while MSUF Edit Mode is active."] = true
L["Units"] = true
L["Player"] = true
L["Target"] = true
L["Focus"] = true
L["Boss 1-5"] = true
L["Display"] = true
L["Show Buffs"] = true
L["Show Debuffs"]   = true
L["Highlight own buffs"] = true
L["Highlights your own buffs with a border color (visual only; does not filter)."] = true
L["Highlight own debuffs"] = true
L["Highlights your own debuffs with a border color (visual only; does not filter)."] = true
L["Show cooldown swipe"] = true
L["Swipe darkens on loss"] = true
L["When enabled, the cooldown swipe represents elapsed time (darkens as time is lost).\n\nTurn this OFF to keep the default cooldown-style swipe."] = true
L["Show stack count"] = true
L['Shows stack/application counts (e.g. "2") on aura icons. Disable to hide stack numbers.'] = true
L["Show cooldown text"] = true
L["Shows the countdown numbers on aura icons. Disable to hide cooldown numbers (swipe can remain enabled)."] = true
L["Show tooltip"] = true
L["Hide permanent buffs"] = true
L['Hides buffs with no duration. Debuffs are never hidden by this option.\n\nNote: Target/Focus APIs may still show permanent buffs during combat due to API limitations.'] = true
L["Only my buffs"]  = true
L["Only my debuffs"] = true
L["Max Buffs"] = true
L["Max Debuffs"] = true
L["Block spacing"] = true
L["Controls how far Buff and Debuff blocks are pushed away from the unitframe when using split anchors."] = true
L["Requires Layout: Separate rows."] = true
L["Icons per row"] = true
L["Wrap rows"] = true
L["Stack Anchor"] = true
L["Buff Anchor"] = true
L["Debuff Anchor"] = true
L["Growth"] = true
L['Timer colors'] = true
L['Color aura timers by remaining time'] = true
L['When enabled, aura cooldown text uses Safe / Warning / Urgent colors based on remaining time.\nWhen disabled, aura cooldown text always uses the Safe color.'] = true
L['Safe (seconds)'] = true
L['Warning (<=)'] = true
L['Urgent (<=)'] = true
L["Advanced"] = true
L["Include"] = true
L["Include boss buffs"] = true
L["Include boss debuffs"] = true
L["Always include dispellable debuffs"] = true
L["Additive: this will NOT hide your normal debuffs."] = true
L["Only show boss auras"] = true
L["Hard filter: when enabled (and filters are enabled), only auras flagged as boss auras will be shown."] = true
L["Private Auras"] = true
L["Enabled"] = true
L["Master switch for anchoring Blizzard Private Auras to MSUF."] = true
L["Show (Player)"] = true
L["Re-anchors Blizzard Private Auras to MSUF (no spell lists)."] = true
L["Show (Focus)"] = true
L["Re-anchors Blizzard Private Auras to MSUF Focus."] = true
L["Show (Boss)"] = true
L["Re-anchors Blizzard Private Auras to MSUF Boss frames."] = true
L["Preview"] = true
L["Visual only: adds a purple border + corner marker on private aura slots."] = true
L["Debuff types"] = true
L["Magic"]  = true
L["Curse"]  = true
L["Poison"] = true
L["Disease"] = true
L["Enrage"]  = true
L['Use "Enable filters" in the Auras 2.0 box as the master switch.\n\nInclude toggles are additive (they never hide your normal auras).\nHighlight toggles only change border colors.\n\nDebuff types: if you select ANY type, debuffs are limited to the selected types.'] = true
L["Max slots (Player)"] = true
L["Max slots (Focus/Boss)"] = true







L["Castbar"] = true
L["Focus Kick"] = true
L["Focus Kick Icon"] = true
L["Behavior"] = true
L["Style"] = true
L["Empowered casts"] = true
L["Shake on interrupt"] = true
L["Shake intensity"] = true
L["Always use fill direction for all casts"] = true
L["Castbar fill direction"] = true
L["Right to left (default)"] = true
L["Left to right"] = true
L["Show channel tick lines (5)"] = true
L["Show GCD bar for instant casts"] = true
L["GCD bar: show time text"] = true
L["GCD bar: show spell name + icon"] = true
L["Castbar texture"] = true
L["Castbar background texture"] = true
L["Show castbar glow effect"] = true
L["Show latency indicator"] = true
L["Name shortening"] = true
L["Max name length"] = true
L["Reserved space"] = true
L["Add color to stages (Empowered casts)"] = true
L["Add stage blink (Empowered casts)"] = true
L["Stage blink time (sec)"] = true
L["Disable MSUF unit info panel tooltips"] = true
L["MSUF unit info panel position"] = true
L["Blizzard frames"] = true
L["Disable Blizzard unitframes"] = true
L["Fully Hide Blizzard PlayerFrame - Turn off for resource bar compatibility"] = true
L["Show MSUF minimap icon"] = true
L["Play sound on Target/Target Lost"]   = true
L["Enable Target Range Fade"]   = true
L["Enable Focus Range Fade"]   = true
L["Enable Boss Range Fade"]   = true
L["Status indicators"] = true
L["Show Dead"]   = true
L["Show Ghost"]   = true







L["Miscellaneous"] = true
L["Updates"] = true
L["Unit info panel"] = true
L["Indicators"] = true
L["Perf..."] = true
L["Balanced..."] = true
L["Accurate..."] = true
L["Unit update interval: %.2f s"] = true
L["Castbar update interval: %.2f s"] = true
L["UFCore flush budget: %.1f ms"] = true
L["UFCore urgent cap: %d"] = true
L["Disable MSUF unit info panel tooltips"] = true
L["MSUF unit info panel position"] = true






L["Colors"] = true
L["Midnight Simple Unit Frames - Colors"] = true
L["Configure global colors such as the global font color, per-class bar colors, and NPC reaction colors."] = true
L["Global font color"] = true
L["Use font palette"] = true
L["Class bar colors"] = true
L["Choose an override bar color per class."] = true
L["Reset all class colors"] = true
L["Bar background tint"] = true
L["Tint applied to the bar background in *all* bar modes. (Dark Mode uses this tint too.)"] = true
L["Reset to black"] = true
L["Match HP"] = true
L["Bar appearance"] = true
L["Bar mode"] = true    
L["Dark Mode (dark black bars)"] = true
L["Class Color Mode (color HP bars)"] = true
L["Unified Color Mode (one color for all frames)"] = true
L["Unified bar color"] = true
L["Reset to default"] = true
L["Dark mode bar color"] = true

L["Extra Color Options"] = true
L["Friendly NPC Color"] = true
L["Neutral NPC Color"] = true
L["Enemy NPC Color"] = true
L["Dead NPC Color"] = true
L["Pet Frame Color"] = true
L["Absorb Bar Color"] = true
L["Heal-Absorb Bar Color"] = true
L["Power Bar Background Color"] = true
L["Reset Extra Color"] = true
L["Castbar colors"] = true
L["Configure colors for interruptible, non-interruptible and interrupt feedback castbars."] = true
L["Interruptible cast color"] = true
L["Non-interruptible cast color"] = true
L["Interrupt color (all castbars)"] = true
L["Castbar text color"] = true
L["Castbar border color"] = true
L["Player castbar override"] = true
L["Optional: forces the Player castbar to use Class or Custom color during normal casts. Interrupt feedback still uses 'Interrupt color (all castbars)'."] = true
L["Enable Player override"] = true
L["Mode:"] = true
L["Class color"] = true
L["Custom color"] = true
L["Color:"] = true
L["Reset castbar colors"] = true
L["Mouseover highlight"] = true
L["Configure the mouseover highlight border that appears when you hover MSUF unitframes."] = true
L["Enable mouseover highlight"] = true
L["Mouseover highlight color"] = true
L["Gameplay"] = true
L["Configure colors used by Gameplay overlays (Combat Timer, Combat Enter/Leave text, Crosshair range)."] = true
L["Combat timer text color"] = true
L["Turned Off in Gameplay"] = true
L["Combat Enter text color"] = true
L["Turned Off in Gameplay"] = true
L["Combat Leave text color"] = true
L["Crosshair in-range color"] = true
L["Turned Off in Gameplay"] = true
L["Crosshair out-of-range color"] = true
L["Totem tracker text color"] = true
L["Turned Off in Gameplay"] = true
L["Reset"] = true
L["Power bar colors"] = true
L["Configure custom colors for power resources used by MSUF power bars."] = true
L["Reset"] = true
L["Auras"] = true
L["Configure colors used by Auras 2.0 (own highlight borders, advanced filter borders) and stack count text."] = true
L["Own buff highlight color"] = true
L["Own debuff highlight color"] = true
L["Stack count text color"] = true
L["Reset"] = true
L["Cooldown text: Safe"] = true
L["Cooldown text: Warning"] = true
L["Cooldown text: Urgent"] = true
L["Reset"] = true






L["Gameplay"] = true
L["Modules"] = true
L["Optional MSUF modules and UI styling (MSUF only)."] = true
L["Style"] = true
L["Enable MSUF Style"] = true
L["Disabling may require /reload to fully remove existing styling."] = true
L["Rounded unitframes"] = true
L["Round MSUF unitframes by masking HP/Power/Absorb bars and backgrounds with the superellipse mask."] = true
L["Profiles"] = true

---------EditMode------

L["Editing: %s (X: %d, Y: %d)"] = true
L["Sizing: %s (W: %d, H: %d)"] = true
L["MODE: SIZE"] = true
L["MODE: POSITION"] = true
L["Positioning"] = true
L["Overlay"] = true
L["Frames"] = true
L["Custom anchor frame name (/fstack)"] = true
L["Anchor Cooldownmanager"] = true
L["Current: "] = true
L["Edit Mode Background"] = true
L["Grid Size (px)"] = true
L["Arrows: OFF"] = true
L["Arrows: ON"] = true
L["Edit Unit:"] = true
L["Aura Preview"] = true
L["Boss Preview"] = true
L["Cancel Changes"] = true
L["Reset Frame"] = true
L["Exit MSUF Edit Mode"] = true

