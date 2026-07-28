-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}

local data = {
    currentVersion = "5.77b",
    previousVersion = "5.77",
    rangeLabel = "5.77 -> 5.77b",
    entries = {
        {
            version = "5.77b",
            date = "2026-07-28",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Fixed channeled spells filling the Castbar like a regular cast instead of draining; channels now start full and empty out from the same edge the cast direction sets, so the bar runs the opposite way unless \"Always use fill direction for all casts\" is enabled. Affects Player, Target, Focus, and Boss Castbars.",
                    },
                },
            },
        },
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
    },
}

ns.MSUF_Changelog = data
_G.MSUF_Changelog = data
