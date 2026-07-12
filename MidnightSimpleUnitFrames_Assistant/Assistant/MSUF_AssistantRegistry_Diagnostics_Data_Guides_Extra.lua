-- Additional guided-setup guide variants for Assistant diagnostics.
-- Loaded after MSUF_AssistantRegistry_Diagnostics_Data_Guides.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.DiagnosticsRegistryData or {}
A.DiagnosticsRegistryData = Data

local Guides = Data.GUIDED_SETUP_GUIDES or {}
Data.GUIDED_SETUP_GUIDES = Guides

Guides.class_resources = {
    label = "Class Resources Setup",
    steps = {
        {
            key = "class_resource_baseline",
            title = "Enable and Place Resources",
            page = "classpower",
            goal = "Make class resources visible without confusing them with normal power bars.",
            body = "Class Resources use global options; unit Power Bar options are separate.",
            examples = {
                "quick setup class resources",
                "turn on class resources",
                "move class resource down 5",
            },
        },
        {
            key = "class_resource_shape",
            title = "Shape and Readability",
            page = "classpower",
            goal = "Tune width mode, opacity, and prediction once placement is stable.",
            body = "Page-local requests work on the Class Resources page, but explicit wording also works from Dashboard.",
            examples = {
                "set width mode to custom",
                "set background opacity to 40",
                "turn off prediction",
            },
        },
        {
            key = "class_resource_extras",
            title = "Class-Specific Extras",
            page = "classpower",
            goal = "Handle optional overlays such as Alternative Mana after the main resource is readable.",
            body = "Run checks when the Class Resource page looks enabled but the display does not match.",
            examples = {
                "set alt mana height to 12",
                "diagnose class resources",
                "open class resources",
            },
        },
    },
}

Guides.gameplay = {
    label = "Gameplay Helpers Setup",
    steps = {
        {
            key = "combat_timer",
            title = "Combat Timer",
            page = "gameplay",
            goal = "Place the combat timer where it gives timing context without blocking frames.",
            body = "The Gameplay page supports short page-local requests while it is active.",
            examples = {
                "turn on timer",
                "move timer down 5",
                "set timer anchor to target",
            },
        },
        {
            key = "combat_state_text",
            title = "Combat State Text",
            page = "gameplay",
            goal = "Use combat enter/leave text only if the extra signal helps you react.",
            body = "Text, size, duration, and movement are separate controls.",
            examples = {
                "turn on combat enter leave text",
                "set combat enter text to Pulling",
                "set combat state duration to 2.5",
            },
        },
        {
            key = "gameplay_frames",
            title = "Totem and Crosshair",
            page = "gameplay",
            goal = "Enable only the gameplay frames that match your class or role.",
            body = "When MSUF has no control for something, I say so clearly.",
            examples = {
                "turn on totem frame",
                "turn on combat crosshair",
            },
        },
    },
}

Guides.appearance = {
    label = "Bars and Fonts setup",
    steps = {
        {
            key = "bars_baseline",
            title = "Bars Baseline",
            page = "opt_bars",
            goal = "Set textures, outlines, and bar readability before per-frame overrides.",
            body = "Global options apply broadly; saying only one target enables its target-specific overrides.",
            examples = {
                "set bars texture to Smooth",
                "set global bar outline thickness to 2",
                "set only player bar outline thickness to 3",
            },
        },
        {
            key = "fonts_baseline",
            title = "Fonts Baseline",
            page = "opt_fonts",
            goal = "Make text readable first, then tune section-specific font overrides only where needed.",
            body = "Rendering, baseline, outline, and name-shortening controls use Global Fonts options.",
            examples = {
                "set font baseline to 2",
                "set global font size 14",
                "set target font outline only to THICKOUTLINE",
            },
        },
        {
            key = "colors_baseline",
            title = "Colors and Follow-Ups",
            page = "opt_colors",
            goal = "Use exact color requests and follow-ups for consistent non-aura colors.",
            body = "Color pickers support named colors, RGB values, hex values, and same-for follow-ups.",
            examples = {
                "set player border color to rgb 255 128 0",
                "same for target",
                "change party health bar color to blue",
            },
        },
    },
}

Guides.auras = {
    label = "Auras Setup",
    steps = {
        {
            key = "aura_visibility",
            title = "Aura Visibility and Lanes",
            page = "uf_target",
            goal = "Choose which Buff and Debuff lanes each unit should show.",
            body = "Start with Target and Player lane visibility before tuning filters or icon details.",
            examples = {
                "show target buffs",
                "show target debuffs",
                "check target auras",
            },
        },
        {
            key = "aura_layout",
            title = "Aura Icon Layout",
            page = "auras3_styling",
            goal = "Set icon size, count, growth, and spacing so important effects scan cleanly.",
            body = "Name the unit and Buff or Debuff lane when the same control exists in several places.",
            examples = {
                "set target buff icon size to 30",
                "set target debuff icon count to 8",
                "make target buffs grow right",
            },
        },
        {
            key = "aura_filters",
            title = "Aura Filters and Priorities",
            page = "auras3_filters",
            goal = "Show useful effects without hiding mechanics you need to react to.",
            body = "First name the frame and Buff or Debuff lane. Blizzard filter tokens choose broad groups; Hide Permanent handles auras with no timer; exact SpellID and group-category lists hide specific auras where Blizzard permits identity filtering. Unit filters inherit from Shared unless that unit uses its own rules.",
            examples = {
                "do not show player buffs with no timer",
                "show only my target buffs",
                "why is one raid debuff missing",
            },
        },
        {
            key = "aura_text",
            title = "Aura Cooldown and Stack Text",
            page = "auras3_styling",
            goal = "Keep timers and stacks readable without covering the icon.",
            body = "Cooldown text, swipe, duration bars, stack text, colors, and thresholds only change presentation. They do not filter an aura; use Hide Permanent when 'no timer' means no duration.",
            examples = {
                "set target buff cooldown text size to 12",
                "set target debuff stack text size to 11",
                "open aura style",
            },
        },
    },
}

Guides.colors = {
    label = "Colors Setup",
    steps = {
        {
            key = "health_colors",
            title = "Health and Reaction Colors",
            page = "opt_colors",
            goal = "Decide whether health follows class, reaction, NPC type, or custom colors.",
            body = "I can also explain a live frame color and distinguish a health fill from a highlight or debuff border.",
            examples = {
                "explain target health color",
                "set party health bar color to blue",
                "open colors",
            },
        },
        {
            key = "bar_text_colors",
            title = "Bar and Text Colors",
            page = "opt_colors",
            goal = "Keep bars and text readable against their backgrounds.",
            body = "Use named colors, hex, or RGB; explicit frame names prevent cross-scope guesses.",
            examples = {
                "set cast bar text color to white",
                "set player power text color to blue",
                "set target border color to rgb 255 128 0",
            },
        },
        {
            key = "highlight_colors",
            title = "Highlights, Dispels, and Auras",
            page = "opt_colors",
            goal = "Make priority states visually different from normal health colors.",
            body = "Ask what a live color means before changing it; the answer uses current unit and debuff state when available.",
            examples = {
                "what does the orange target border mean",
                "open group status and indicators",
                "open aura style",
            },
        },
    },
}

Guides.full_tour = {
    label = "Complete MSUF Tour",
    steps = {
        {
            key = "tour_dashboard_profiles",
            title = "Dashboard and Profiles",
            page = "home",
            goal = "Know where to check status, back up a profile, and recover before broad edits.",
            body = "The Dashboard is the starting point; Profiles owns import, export, copying, and specialization routing.",
            examples = { "show msuf status", "export current profile", "open profiles" },
        },
        {
            key = "tour_main_units",
            title = "Player and Target Frames",
            page = "uf_player",
            goal = "Understand the primary unit-frame controls for layout, text, portraits, bars, and status indicators.",
            body = "Player and Target have the richest per-frame controls; other unit frames follow the same model.",
            examples = { "open player", "open target", "what can i change here" },
        },
        {
            key = "tour_other_units",
            title = "Focus, Pet, Secondary, and Boss Frames",
            page = "uf_focus",
            goal = "Visit Focus, Pet, Target of Target, Focus Target, and Boss without mistaking one scope for another.",
            body = "Name the exact frame when a control exists in several unit pages.",
            examples = { "open focus", "open pet", "open boss frames" },
        },
        {
            key = "tour_castbars",
            title = "Cast Bars",
            page = "opt_castbar",
            goal = "Configure Player, Target, Focus, and Boss cast information and subcomponents.",
            body = "Icon, spell-name text, and time controls each depend on their own visibility toggle.",
            examples = { "open cast bars", "why is target cast bar hidden", "related settings for target cast bar icon size" },
        },
        {
            key = "tour_groups",
            title = "Group Layout, Health, and Indicators",
            page = "gf_layout",
            goal = "Cover Party, Raid, and Mythic Raid layout plus their text and status systems.",
            body = "Group Layout, Group Health & Text, and Group Status & Indicators are separate pages.",
            examples = { "open group layout", "open group health and text", "open group status and indicators" },
        },
        {
            key = "tour_auras",
            title = "Unit and Group Auras",
            page = "uf_target",
            goal = "Understand Aura lanes, layout, filters, inheritance, and Group Auras.",
            body = "Unit Auras and Group Auras use different pages but share the same visibility-first setup principle.",
            examples = { "open auras", "open aura filters", "open group auras" },
        },
        {
            key = "tour_bars_resources",
            title = "Global Bars and Class Resources",
            page = "opt_bars",
            goal = "Separate global bar appearance, normal Power Bars, detached bars, and class-specific resources.",
            body = "Class Resources has its own page and should not be confused with a unit Power Bar.",
            examples = { "open bars", "open class resources", "explain target power bar" },
        },
        {
            key = "tour_appearance",
            title = "Colors and Fonts",
            page = "opt_colors",
            goal = "Apply a readable global visual baseline, then use scope overrides only where needed.",
            body = "Colors and Fonts connect to many frame-specific settings through shared values and overrides.",
            examples = { "open colors", "open fonts", "related settings for target font outline" },
        },
        {
            key = "tour_helpers_modules",
            title = "Gameplay, Modules, and Miscellaneous",
            page = "gameplay",
            goal = "Finish with optional gameplay helpers, style modules, tooltips, and integration choices.",
            body = "These pages contain optional systems; enable only the ones that support your play and UI goals.",
            examples = { "open gameplay", "open modules", "open miscellaneous" },
        },
        {
            key = "tour_finish",
            title = "Edit Mode and Diagnostics",
            page = "home",
            goal = "Know how to move frames, run checks, inspect support details, and undo Assistant changes.",
            body = "Use Edit Mode for broad placement and diagnostics when enabled settings still do not appear.",
            examples = { "start edit mode", "run checks", "assistant support text" },
        },
    },
}
