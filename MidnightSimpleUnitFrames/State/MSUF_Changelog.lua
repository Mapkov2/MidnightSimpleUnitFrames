-- Auto-generated from CHANGELOG.md by tools/update-addon-changelog.ps1.
-- Edit CHANGELOG.md, then regenerate this file before packaging.
local _, ns = ...
ns = ns or {}
local ExportPublic = ns.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local data = {
    sourceSha256 = "0A32727C35FD19D395C69911B8787A9A412BF2BA57E3562AC231F65F1687EB05",
    currentVersion = "6.5-beta17",
    historyFromVersion = "6.5-beta14",
    previousVersion = "6.5-beta16",
    rangeLabel = "6.5-beta16 -> 6.5-beta17",
    entries = {
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
        {
            version = "6.5-beta16",
            date = "2026-10-06",
            sections = {
                {
                    title = "WoW Forever controller support",
                    bullets = {
                        "Expanded controller support for MSUF and compatible Suite windows. Use the D-pad to navigate controls, confirm or cancel actions, open dropdowns, choose anchors, search settings and switch windows through Forever's Gamepad UI.",
                        "Enter text and exact numeric values with the on-screen keyboard, adjust sliders, nudge previews and Edit Mode elements, and undo or redo supported changes. Localized button hints, a focus highlight and haptic feedback guide supported actions.",
                        "Controller navigation releases input during combat and while Blizzard panels own navigation.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Class Resources use a shared workspace with direct resource selection, scoped settings, Copy To, Quick Setup and reset actions. Controls remain inside their cards on narrow windows.",
                        "Forever Swing Timers include an embedded menu preview, separate Main Hand, Off Hand and Ranged settings, and category-based Copy To.",
                        "Improved Blizzard-style portrait masks, corner direction and per-unit preview alignment.",
                    },
                },
                {
                    title = "Performance",
                    bullets = {
                        "Closed menu sections defer their controls and decoration until needed. Repeated header layout and owned-button skin work reuse existing state.",
                        "Cold search indexes build in short menu-task slices while exact searches retain synchronous results and prepare the required lazy sections.",
                        "Group aura previews share their compatible configuration instead of compiling it once per row. Color previews avoid duplicate render requests and preserve staged construction.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Group layouts retain space and role ordering for members joining during combat. Housing visibility, extra-block names and dead/offline backgrounds refresh consistently.",
                        "Resource marks use the range of their displayed resource. Profile names remain as typed, and Copy To retains supported font, texture, gradient and status settings.",
                        "Corrected exact-search targets, preview lifecycle behavior, menu spacing and translations across all supported locales.",
                    },
                },
            },
        },
        {
            version = "6.5-beta15",
            date = "2026-10-03",
            sections = {
                {
                    title = "Fixes",
                    bullets = {
                        "Aura icons no longer show the border baked into Blizzard's icon artwork (#159). Runtime icons, reminders and menu/Edit Mode previews share the same minimum crop while retaining stronger configured zoom.",
                        "Classic aura lanes honor all nine anchors, the menu's layer range and Player-first sorting. Combat-only filters refresh at the combat transition, AUTO dispel symbols follow the frame's strata, and Pet overrides apply to Pet settings.",
                        "Custom auras compile on supported Classic arena frames. Edit Mode keeps click forwarding on Classic aura lanes and avoids rewiring sealed native aura buttons.",
                        "Group frames defer layout changes at combat entry and return previewed groups to their live headers. Newly created group and pet buttons retain their click handling and pixel alignment in combat.",
                        "Healer mana rows and allied boss frames repaint when a unit token changes hands. Group filters, class-priority identity reads and saved negative-heal-absorb overrides remain consistent across layouts and logins.",
                        "The Raid Manager retains its expanded state when settings are reapplied; Hidden mode leaves its toggles click-through.",
                        "Arena castbars honor Show icon, Spell name and Cast time settings and use the corrected time-text offset in runtime and previews. Castbar movers follow the bar after it moves, and font refreshes retain cast-target class colors.",
                        "Interrupt feedback follows the displayed cast, including late interrupt events. Restricted cast, duration, swing, aura, health and power values follow the supported native formatting and rendering paths without Lua comparisons.",
                        "Class Resource settings apply after saved profiles load and stay synchronized with profile variants and page resets. Growing resource maxima trigger the required layout refresh; relayouts, Stagger colors, Ironfur and aura-count visibility repaint correctly.",
                        "Mists Burning Embers use the unmodified resource maximum, and Affliction shards use the supported spell gate. Eclipse respects its text mode and drops auras that end early. On Midnight, Affliction/Demonology shard prediction receives cast events.",
                        "Alternative Mana returns after Edit Mode, Player Power regains its color after Eclipse, and disabling the secondary Player HP module hides its bar. AFK timers resume after combat; death state also updates on direct health ticks.",
                        "Rounded borders and masks retain their selected shape. Inline target-of-target text follows the name's visible glyph edge, and protected prediction values retain their over-absorb glow.",
                        "/msuf reset restores factory frame sizes, positions, layout and text visibility, and /msuf profile <name> saves the current settings. Profile imports preserve dispel-migration stamps, variants retain removed resource-extra keys, and oversized compressed imports are rejected before inflation.",
                        "New and reset Forever profiles leave global UI scaling disabled, matching the other clients. Explicitly enabled scaling in existing profiles is retained, including settings made immediately after a reset.",
                        "Native managed cast and class-resource bars keep Blizzard's lifecycle handling while MSUF conceals their visuals. Totem takeover restores only the frame-position flag owned by MSUF.",
                        "Options, aura workspaces and search results reuse their existing page state instead of repeatedly creating page trees. Configuration and focus-preview keyboard input stop at combat entry; Edit Mode history commits defer safely through that transition.",
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Aura containers are reused after retirement. Class Resource thresholds share one resource read, Mists rune types refresh on their native event, and affected aura-resource and cast-expiry paths avoid per-event closures.",
                        "Updated translations for menu and Edit Mode labels, history, prompts, status text, tooltips and chat messages across all twelve supported locales.",
                        "This package contains the core and Options addons. The retired in-game Assistant is no longer shipped; when updating manually, remove any old MidnightSimpleUnitFrames_Assistant folder from Interface/AddOns.",
                    },
                },
                {
                    title = "Compatibility",
                    bullets = {
                        "Recognizes the marker-qualified Forever client in build 70170, including its dedicated project identifier. Unknown clients continue to use the guarded fallback.",
                    },
                },
            },
        },
        {
            version = "6.5-beta14",
            date = "2026-10-02",
            sections = {
                {
                    title = "Highlights",
                    bullets = {
                        {
                            text = "Toggle additional group features directly from their accordion headers. Name strip, Member targets, Pet frames, Allied boss frames, Healer mana bars and Forever Buff coverage keep their master switch available while the section is closed.",
                            link = {
                                pageKey = "gf_layout",
                                query = "enable",
                                label = "Enable",
                                sectionId = "healer_mana",
                                controlId = "menu2.gf_layout.group.field.healermanaenabled",
                                settingKey = "gf_raid.healerManaEnabled",
                                prepareKind = "groupScope",
                                prepareValue = "raid",
                            },
                        },
                    },
                },
                {
                    title = "Changes",
                    bullets = {
                        "Healer mana Text color is now under Colors > Group > Healer mana bars and remains accessible through the section's three-dot color menu. Existing saved values are retained; color edits follow the shared Party, Raid and Mythic Raid group-color behavior.",
                        "Updated menu and Edit Mode translations across all twelve supported locales.",
                        "Classic aura rendering, group configuration and castbar frame pools have clearer shared ownership while retaining their existing controls.",
                    },
                },
                {
                    title = "Fixes",
                    bullets = {
                        "Group headers handle combat transitions, roster changes and small raids more consistently. Group layout, class priority, indicators and previews refresh through their shared owners.",
                        "Classic aura filters, icon rendering and event updates remain consistent across profile and specialization changes.",
                        "Arena and boss castbars share frame lifecycle handling, restore native text when needed and keep outline and cooldown state current.",
                        "Mists Death Knight runes follow their rune type colors when no explicit rune color override is selected. Combo points and aura-based class resources update their displayed values correctly.",
                        "Profile normalization retains supported numeric spell IDs, profile changes refresh visible menu pages, and Undo history stays bounded for large profiles.",
                        "Global font and texture changes retain frame opacity and refresh the affected text. Unit tooltips display available AFK and DND flags, and portrait atlas artwork keeps its full image and flip direction.",
                        "Edit Mode Cancel discards unfinished text edits before restoring settings. Combat interruptions preserve supported drag positions, and movement history uses translated labels.",
                        "Menu search normalizes Unicode input, retains edits and avoids rebuilding unaffected pages. Menu previews reuse their presentation state.",
                        "Group Anchor and class priority sections size their wrapped text correctly. Portrait controls and the Healer mana section use the corrected spacing.",
                        "Opening Options from the Game Menu shares the deferred cold-load boundary with the keybind, reducing first-open script-time pressure.",
                    },
                },
            },
        },
    },
}

ns.MSUF_Changelog = data
ExportPublic("MSUF_Changelog", data)
