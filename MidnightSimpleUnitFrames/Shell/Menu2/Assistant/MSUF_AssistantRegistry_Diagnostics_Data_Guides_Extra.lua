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
            title = "Totem, First Dance, and Crosshair",
            page = "gameplay",
            goal = "Enable only the gameplay frames that match your class or role.",
            body = "When MSUF has no control for something, I say so clearly.",
            examples = {
                "turn on totem frame",
                "turn on first dance",
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
