-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "E2F7771811A7DC1ACF0E70BA3AD7E581106A1D34CCC9B582A37590BB58466676",
    currentVersion = "6.50",
    historyFromVersion = "6.5-beta17",
    previousVersion = "6.5-beta17",
    rangeLabel = "6.5-beta17 -> 6.50",
    entries = {
        {
            version = "6.50",
            date = "2026-10-09",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "MSUF 6.50 completes the 6.5 line. It brings 102 new features and changes, 103 bug fixes and 20 performance improvements, including Arena Frames, Pet Target, Slanted Frames and Cosmetic Texture Layers. On WoW 12.1.5 the login greeting sums this up; turn it off under Global > Misc > Show welcome message.",
                            link = {
                                pageKey = "opt_misc",
                                query = "show welcome message",
                                label = "Show welcome message",
                                sectionId = "misc_startup",
                                controlId = "menu2.opt.misc.global.setting.show.welcome.message",
                                settingKey = "general.showWelcomeMessage",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Every client runs version 6.50: Midnight, WoW Forever, Classic Era, TBC and Mists.",
                    },
                },
            },
        },
        {
            version = "6.5-beta19",
            date = "2026-10-09",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Slanted bars take a cut direction per frame. Each unit, group and castbar scope can follow the shared direction or use its own, and the menu previews show the chosen cut. Set it under Bars > Slanted > Cut direction.",
                            link = {
                                pageKey = "opt_bars",
                                query = "cut direction",
                                label = "Cut direction",
                                sectionId = "bars_slanted",
                                controlId = "menu2.opt.bars.global.slanted.direction",
                                settingKey = "bars.slantedBarDirection",
                            },
                        },
                        {
                            text = "Interrupt readiness tracks Demonology's Axe Toss again. Spells of another specialization no longer count as a ready interrupt.",
                            link = {
                                pageKey = "opt_castbar",
                                query = "show on target castbar",
                                label = "Show on Target castbar",
                                sectionId = "castbar_interrupt_ready",
                                controlId = "menu2.opt.castbar.global.interrupt.ready.kick.ready.show.target",
                                settingKey = "general.kickReadyShowTarget",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Menu search understands natural task phrasing in English and German, such as \"make my target health numbers bigger\".",
                        "Corner indicators set to Show when missing work on Classic clients; Retail and WoW Forever show why the choice is unavailable there.",
                        "Blizzard Damage Meter appearance changes made in MSUF Edit Mode apply after a UI reload; width and height still apply at once.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Handing the player castbar back to Blizzard and changing Damage Meter settings no longer leave Blizzard frames tainted.",
                        "Entering combat with the Boss or Arena page open restores the real boss and arena auras.",
                        "Power text with maximum values and frame transparency stay error-free when the client hides those values.",
                        "The Combat Timer starts on the first second of combat, and profile switches keep aura tooltip options that MSUF did not set.",
                        "Castbar glow stays inside rounded and slanted castbars; the aura Name Overlay follows unit changes.",
                        "Party and Raid bar textures follow the Bars page after Copy To, and the Basics reset also clears an old frame shape.",
                        "WoW Forever's Gamepad UI no longer opens a hidden buff bar; Classic Era no longer offers a Focus anchor for the Combat Timer.",
                        "Guided Setup hints, aura filter labels and several terms are translated correctly in every language.",
                    },
                },
            },
        },
        {
            version = "6.5-beta18",
            date = "2026-10-09",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Frame outlines keep their configured color across shapes and styles. Texture and True Outline borders use the selected outline color on square, rounded and slanted frames, while active highlights retain their own colors. Set the shared color under Colors > Bar & Prediction Colors > Bar Outline Color.",
                            link = {
                                pageKey = "opt_colors",
                                query = "bar outline color",
                                label = "Bar Outline Color",
                                sectionId = "colors_bar_colors",
                                controlId = "menu2.opt.colors.advanced.bar.outline.color",
                                settingKey = "general.barOutlineColor",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Improved control state, page navigation, exact-search routing and translated labels across the supported clients.",
                        "Menu and Edit Mode previews follow the current resource, aura and frame settings more consistently.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Scoped outline colors enable their override even when the selected color matches the shared value. Shaped borders prepare the required normal and highlight artwork when their settings are applied.",
                        "Profile startup, switching and synchronization preserve the active profile state. Edit Mode selection and Undo/Redo remain consistent across profile transitions.",
                        "Corrected aura rendering and client capability guards, cast interruption feedback, interrupt readiness and resource updates.",
                        "Corrected unit and group frame state updates and affected menu preview lifecycles.",
                        "Castbars and the totem preview handle restricted frame-strata values through their supported fallback paths.",
                        "WoW Forever controller button prompts retain the full icon artwork and corrected sizing.",
                    },
                },
                {
                    title = "Performance",
                    bullets = {
                        "Changing the Frame Outline style refreshes the affected borders without rebuilding unrelated castbars, class resources or aura masks.",
                        "Border event updates reuse prepared artwork and retain the shared color rendering path.",
                    },
                },
            },
        },
        {
            version = "6.5-beta17",
            date = "2026-10-06",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Textured borders now follow rounded corners and slanted frame edges. True Outline and Texture styles work with Rounded Frames and Slanted Bars, including unit and group frames. Choose your style under Bars > Frame Outline; menu previews show the selected border along the same frame shape.",
                            link = {
                                pageKey = "opt_bars",
                                query = "rounded frame texture",
                                label = "Rounded frame texture",
                                sectionId = "bars_rounded",
                                controlId = "menu2.opt.bars.global.rounded.rounded.frames.enabled",
                                settingKey = "bars.roundedFramesEnabled",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Additional Resource settings use dedicated resource sections, nearby color shortcuts and previews built from the runtime's resource renderer.",
                        "Frame shapes are configured through the Bars menu and Group Layout. Removed the duplicate shape picker from each unit's Frame Basics section.",
                        "Improved integration with compatible Suite windows for profiles, fonts, anchors and menu controls.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "ConsolePort Game Menu layout changes wait until combat ends before moving or resizing protected controls.",
                        "Border style, color and thickness remain consistent between shaped frames and their menu previews.",
                    },
                },
                {
                    title = "Performance",
                    bullets = {
                        "Unrelated power events skip unnecessary resource text work.",
                        "Styled borders reuse their textures and layout; combat color updates avoid rebuilding border geometry.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
