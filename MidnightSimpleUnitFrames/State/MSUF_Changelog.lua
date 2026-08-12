-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    currentVersion = "6.0",
    previousVersion = "6.0-RC18",
    rangeLabel = "6.0-RC18 -> 6.0",
    entries = {
        {
            version = "6.0",
            date = "2026-08-11",
            sections = {
                {
                    title = "Final Release Changes",
                    bullets = {
                        "Rebuilt Unit Preview Aura handling with independent Buff and Debuff layers, correct lane routing from every handle, and clearer Aura-menu copy for the actual Unit/Group styling workspaces.",
                        "Expanded the Debuff blacklist presets and clarified that blacklist entries belong to the selected frame and Debuff lane.",
                        "Added native Ebon Might duration text plus safe, independently configurable Alternative Mana width geometry across runtime, previews, search, and the Assistant.",
                        "Made Blizzard's animated Resting symbol part of the fresh default profile while preserving existing profiles and live resting state.",
                        "Reworked the upgrade-highlight tour so Back/Forward history is taught first, the real navigation arrows pulse while that page is open, page actions perform their advertised action, and the Assistant can restart a skipped or completed tour from natural-language requests.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed nickname-provider refreshes and fallback resolution so updated Target names reach the correct Unit and Group Frames without broad polling.",
                        "Guarded secret Player Health values before Class Resource logic can inspect them in combat.",
                        "Fixed Texture Layer target refreshes, rounded clipping, true-outline geometry, and rounded preview edges after live setting changes.",
                        "Fixed Resting state/default normalization and Castbar preview text positions drifting from their runtime owners.",
                    },
                },
            },
        },
        {
            version = "6.01",
            date = "2026-08-10",
            sections = {
                {
                    title = "Final Beta Release Highlights",
                    bullets = {
                        "Expanded Texture Layers with a built-in target-highlight recipe, Current Target visibility, custom-class-color following, automatic sizing, top/bottom texture cropping, and Original or Monochrome source treatment.",
                        "Added real eight-piece outline media alongside the existing solid and stretched-texture Frame Outline styles.",
                        "Added optional rounded rectangular Class Resources and Blizzard's animated native Resting symbol across live frames and previews.",
                        "Refreshed the complete fresh-install visual baseline with cohesive dark bars, warm target accents, and deliberate 6.01 defaults without changing existing profiles.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed nickname-provider Target refreshes so only the affected Unit and Group Frames are invalidated, with combat changes still coalesced safely.",
                        "Fixed restricted 12.1 Class Resource values hiding their text in combat; protected values now pass directly to Blizzard's native text and StatusBar sinks while preserving configured styling.",
                        "Fixed Unit Copy To bypassing its action guard and reporting unsupported Castbar copies as successful. Pet, Target of Target, and Focus Target now skip Castbar settings explicitly while mixed copies keep every supported category.",
                        "Fixed Castbar Spell, Time, and Target text using different layout rules in the Unit Preview than on the live runtime castbar.",
                        "Fixed Manual Detached Power width losing authority to a synchronized width source in Edit Mode and Menu controls.",
                        "Fixed Boss portrait refreshes missing frames that had not yet been seeded into the Edit Mode registry.",
                        "Fixed rounded mouseover edges retaining their previous color until the next hover transition.",
                    },
                },
            },
        },
        {
            version = "6.0-RC19",
            date = "2026-08-09",
            sections = {
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Unit and Group Aura layout controls not updating their per-row availability immediately after changing a lane's growth direction.",
                        "Fixed detached power bars being unavailable or reattached in Edit Mode and Unit previews for Target of Target, Focus Target, Pet and Boss frames. Runtime, Edit Mode and Menu previews now share one unit-capability contract.",
                        "Fixed Castbar Spell Text exposing a separate Alignment setting that could conflict with its Position preset. Position now owns both the anchor and visible alignment consistently in live frames, previews, search and the Assistant.",
                    },
                },
            },
        },
        {
            version = "6.0-RC18",
            date = "2026-08-09",
            sections = {
                {
                    title = "Changes",
                    bullets = {
                        "Added a versioned nickname-provider API for Unit and Group Frames. Providers are priority ordered, cached, event-driven and deferred safely across combat; the bundled Northern Sky Raid Tools adapter now uses the same public contract.",
                        "Documented the supported Nickname and Edit Mode provider APIs for addon authors in the README.",
                    },
                },
                {
                    title = "Fixes & Performance",
                    bullets = {
                        "Fixed Boss Frame health, power, background and border geometry moving or leaving the screen after a combat reload (#77). Pixel-snapped regions now remain attached to their secure frame owner.",
                        "Fixed Boss castbar spell-name shortening being ignored at runtime and in Edit Mode previews (#78), including the renderer-only path required for secret combat values.",
                        "Fixed Edit Mode always showing the Boss castbar leading-edge spark even when the setting was disabled (#79). The animation no longer overrides the cold style owner every tick.",
                        "Fixed detached Boss castbars appearing outside the Unit Preview (#80). The preview projects the applied runtime relationship without changing the saved absolute position.",
                        "Fixed Player Defensives being re-enabled by Menu normalization after the user disabled them. Runtime, Menu preview and Edit Mode now honor the same master switch, while tracked Target DoTs keep their disabled configuration preview.",
                        "Fixed Player search routes treating the layer substring inside player as a Text section request. Portrait and other exact results no longer open an unrelated accordion or rebuild the page unnecessarily.",
                        "Fixed explicit guided-setup phrases containing topics such as profiles being consumed by text creation guidance instead of opening the native guided setup.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
