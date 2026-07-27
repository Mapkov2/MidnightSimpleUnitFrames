-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.77",
    previousVersion = "5.76",
    rangeLabel = "5.76 -> 5.77",
    entries = {
        {
            version = "5.77",
            date = "2026-07-28",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed Unit Frame portraits randomly showing stale or corrupted images (such as a piece of the game world) on Player and Target frames; portraits now refresh automatically after loading screens, cinematics, and model changes such as shapeshifts.",
                        "Fixed the \"Always use fill direction for all casts\" Castbar toggle having no effect on channeled casts; channels now fill in the configured direction exactly like regular casts, with the spark and latency zone following the moving edge of the bar.",
                    },
                },
            },
        },
        {
            version = "5.76",
            date = "2026-07-20",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added independent X/Y positioning for Castbar icons and duration text in Edit Mode for Player, Target, Focus, and Boss frames.",
                        "Added spell-specific Player channel tick markers with talent- and duration-aware layouts, custom-position support, and a five-marker fallback for unsupported spells.",
                        "Added a 100-200% zoom control for 2D Unit Frame portraits with matching live and preview rendering.",
                        "Added 11 bundled bar textures: Arcane Pulse, Aurora Silk, Deep Current, Dragon Scale, Ember Weave, Forged Steel, Frosted Quartz, Lucent, Lunar Mist, Obsidian Glass, and Runic Circuit.",
                        "Added an adjustable 0-5 second interrupt display duration for Player, Target, Focus, and Boss Castbars.",
                    },
                },
                {
                    title = "Import & Stability",
                    bullets = {
                        "Improved UUF imports to preserve right-side Castbar icons, non-default spell and duration text positions, additional HP-percentage tags, and combined name-and-level labels.",
                        "Fixed power-bar separator borders that could remain hidden until Edit Mode was opened.",
                        "Preserved the Player Castbar across active profile and UUF imports, including profiles that previously relied on Blizzard's Player Castbar fallback.",
                        "Stabilized ArcUI Essential Cooldown anchors across form and specialization changes, delayed addon loading, and protected combat transitions.",
                        "Fixed overlapping controls in the Portrait Border and Raid Grid sections of the options menu.",
                        "Kept channel marker updates event-driven with no recurring background polling.",
                    },
                },
            },
        },
        {
            version = "5.75",
            date = "2026-07-20",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        "Added spell-specific Player channel tick markers with talent- and duration-aware layouts, custom-position support, and a five-marker fallback for unsupported spells.",
                        "Added a 100-200% zoom control for 2D Unit Frame portraits with matching live and preview rendering.",
                        "Added 11 bundled bar textures: Arcane Pulse, Aurora Silk, Deep Current, Dragon Scale, Ember Weave, Forged Steel, Frosted Quartz, Lucent, Lunar Mist, Obsidian Glass, and Runic Circuit.",
                        "Added an adjustable 0-5 second interrupt display duration for Player, Target, Focus, and Boss Castbars.",
                    },
                },
                {
                    title = "Fixes & Stability",
                    bullets = {
                        "Preserved the Player Castbar across active profile and UUF imports, including profiles that previously relied on Blizzard's Player Castbar fallback.",
                        "Stabilized ArcUI Essential Cooldown anchors across form and specialization changes, delayed addon loading, and protected combat transitions.",
                        "Fixed overlapping controls in the Portrait Border and Raid Grid sections of the options menu.",
                        "Kept channel marker updates event-driven with no recurring background polling.",
                    },
                },
            },
        },
        {
            version = "5.74",
            date = "2026-07-19",
            sections = {
                {
                    title = "Highlight",
                    bullets = {
                        "Rebuilt Castbar outlines for crisp, pixel-perfect borders at every UI scale across live Castbars, previews, and Boss Castbars.",
                    },
                },
                {
                    title = "Improvements & Fixes",
                    bullets = {
                        "Added independent Castbar icon-outline thickness using the configured Castbar border color.",
                        "Expanded Auto Width to Player, Target, Focus, and Boss Castbars with exact Unit Frame or Cooldown Manager matching and adjustable offsets.",
                        "Fixed imported profiles with legacy UI_Parent anchors causing an endless full Unit Frame reanchor loop, extreme idle CPU usage, and severe FPS loss; affected profiles are repaired automatically, and the reanchor scheduler now recovers cleanly from unexpected bridge errors.",
                        "Expanded Skyriding aura filtering to include Thrill of the Skies and both Flight Style auras, with per-Boss Unit Aura ignore-list overrides available again.",
                        "Preserved character-specific keybindings by no longer replaying account-wide stored bindings automatically.",
                        "Reopened the options menu on its last active page and corrected custom scrollbar dragging without idle polling.",
                    },
                },
            },
        },
        {
            version = "5.73",
            date = "2026-07-18",
            sections = {
                {
                    title = "Highlight",
                    bullets = {
                        "Import UnhaltedUnitFrames 12.1 profiles directly into MSUF with the load-on-demand UUF importer.",
                        "Added full support for Coolinator and Skiron CDM",
                    },
                },
                {
                    title = "Minor Bug Fixes",
                    bullets = {
                        "Fixed imported UUF profiles losing independent health-fill and missing-health transparency in live frames and previews.",
                        "Fixed aura icon size controls not staying synchronized between the menu and Edit Mode.",
                        "Fixed edge case Blizzard Cooldown Manager anchors shifting unit frames after instance and zone transitions.",
                        "Fixed visible Group Frame power bars shifting name text vertically in live frames and previews.",
                        "Fixed split health text updates relying on secret-string comparisons.",
                        "Fixed dragging third-party anchored unit frames and synchronizing cooldown-sized power bars.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
