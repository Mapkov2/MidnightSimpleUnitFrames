# Midnight Simple UnitFrames (MSUF)

Lightweight, minimal **unit frames + castbars + auras + group frames** for World of Warcraft. Built for clean visuals, deep configurability, and performance-first event-driven updates.

---

## Unit Frames
**Player · Target · Focus · Pet · Target-of-Target · Boss**

- Per-frame sizing, positioning, and bar texture via full Edit Mode integration
- **Health bar color modes** — Dark, Class Color, Unified, or HP-based Gradient (runs fully C-side)
- Absorb bar, heal-absorb overlay, and smooth fill animation via native Blizzard interpolation
- **Alpha system** — three layer modes (Foreground/Background, HP Bar, Full Frame) with separate in/out-of-combat sliders, HP color preservation at any transparency, and optional portrait/text exclusion
- **11 HP and power text modes** — Current, Percent, Current/Max, and all reverse-order variants
- Portrait modes: 2D, 3D model, class icon — with shape, border, and background options
- **Highlight borders** — Aggro, Dispel, Purge, Boss Target; per-unit independent overrides; configurable priority order
- **Dispel glow** — animated LibCustomGlow overlay in Pixel, AutoCast, or Proc style
- **Dispel colors** — single color or per debuff type (Magic, Curse, Disease, Poison, Bleed)
- **Interrupt indicator** — overlay on the castbar when a target's spell is kickable, with threshold and color control
- **Status indicators** — AFK/DND/Dead/Ghost text, combat icon, resting icon, rez icon — all with configurable anchors, layers, and pulse animation
- **Elite/rare icons** — gold for elites/world bosses, silver for rares
- **Role/leader icons** — 11 icon set styles (Diamonds, GlassPanels, Midnight, NeonOutline, and more)
- **Range fade** — configurable alpha, per-class friendly spell detection, optional portrait fade
- NPC color modes: reaction-based or type-based (Boss, Miniboss, Caster, Melee, Regular)
- Optional rounded corners

## Castbars
**Player · Target · Focus · Boss**

- Configurable size, position, font, texture, icon placement, and time display per castbar
- Interruptible / non-interruptible / interrupt feedback colors independently set
- Shield overlay for non-interruptible casts
- Secret-safe and compatible with modern Blizzard timing APIs

## Auras 2.0
**Player · Target · Focus · Boss**

- Filters: mine only, boss auras, dispellable, stealable, spell ID whitelist/blacklist
- Configurable rows, growth direction, icon size, spacing, and stacking rules
- Cooldown text with bucket-based color thresholds
- Dispellable/stealable highlighting and buff reminder system

## Group Frames
**Party · Raid · Mythic Raid**

- Per-frame HP bar, power bar, name text, role/leader icons, and status indicators
- **Blizzard-native aura renderer by default** — group frame auras run through Blizzard's C-side engine with zero Lua overhead per update; supports buffs, debuffs, dispellable, externals, and private auras — all independently toggleable
- **Spell indicators** — configurable spell overlays per group member with a built-in curated data set for common raid and PvP spells
- **Corner indicators** — up to 4 corners per frame (aggro, debuff type, dispellable, and more)
- **Healer buff tracker** — dedicated tracker with a built-in in-game editor
- **GF Effects** — HP gradient, missing HP overlay, absorb bar, and glow effects
- Native private aura support, Masque-compatible icons, full Edit Mode integration

## Colors
12 collapsible sections covering every color in the addon — class bar colors, NPC type colors, castbar colors, dispel colors per debuff type, power bar colors, class power colors, aura threshold colors, portrait colors, gameplay highlight colors, and more.

## Additional
- **Class Power** — configurable class resource bar with per-resource colors
- **Spec Profiles** — auto-switch profiles on spec change
- **Import / Export** — full profile sharing via copy-paste strings
- **LibSharedMedia** — all textures and fonts LSM-registered
- **Masque** — aura icon skinning on unit frames and group frames
- **Search** — searchable options panels
