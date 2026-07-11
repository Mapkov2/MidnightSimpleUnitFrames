-- Static guided-setup text for the Assistant diagnostics registry.
-- Kept separate from diagnostic logic so the workflow file stays reviewable.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.DiagnosticsRegistryData or {}
A.DiagnosticsRegistryData = Data

Data.GUIDED_SETUP_STEPS = {
    {
        key = "frame_size",
        title = "Main Frame Size",
        page = "uf_player",
        goal = "Start with readable Player and Target frames before tuning details.",
        body = "A solid baseline is Player width 275 and height 40, then Target can copy the same size.",
        examples = {
            "make player width 275",
            "make player height 40",
            "copy player layout to target",
        },
    },
    {
        key = "placement",
        title = "Player and Target Placement",
        page = "uf_player",
        goal = "Put the main frames where your eyes naturally rest in combat.",
        body = "Edit Mode is best for broad placement. Small nudges are easier to control than one big jump.",
        examples = {
            "start edit mode",
            "move player 20 left",
            "move target 20 right",
        },
    },
    {
        key = "castbars",
        title = "Cast Bars",
        page = "opt_castbar",
        goal = "Make important casts obvious without crowding the center.",
        body = "Target cast bar is usually the first one to verify. After that, add Player, Focus, or Boss cast bars only if you need them.",
        examples = {
            "show target castbar",
            "move target castbar 20 down",
            "set castbar height to 28",
        },
    },
    {
        key = "text",
        title = "Text Visibility",
        page = "uf_player",
        goal = "Keep the text you actually read and remove repeated noise.",
        body = "Clean layouts usually keep names and one clear health value, then reduce redundant power or HP text.",
        examples = {
            "hide player power text",
            "show target name",
            "set global font size 14",
        },
    },
    {
        key = "power",
        title = "Power Bars and Resources",
        page = "opt_bars",
        goal = "Make resource information clear without mistaking it for class resources.",
        body = "Power Bar options are on unit and group frames. Class Resources use their own global options.",
        examples = {
            "set target power bar height to 8",
            "detach target power bar",
            "turn on class resources",
        },
    },
    {
        key = "group_frames",
        title = "Group Frames",
        page = "gf_layout",
        goal = "Build Party and Raid after the main frames feel stable.",
        body = "Group frames need dense but readable sizing. Start with Party/Raid visibility, then tune width, text, and indicators.",
        examples = {
            "show party group frames",
            "make raid width 80",
            "turn off ready check symbol for all group frames",
        },
    },
    {
        key = "boss_frames",
        title = "Boss Frames and Final Check",
        page = "uf_boss",
        goal = "Finish with encounter information and a quick diagnostic pass.",
        body = "Boss frames and Boss cast bars should be readable without covering your main layout.",
        examples = {
            "show boss frame",
            "show boss castbar",
            "diagnose boss frames",
        },
    },
}

Data.GUIDED_SETUP_GUIDES = {
    main = {
        label = "MSUF layout setup",
        steps = Data.GUIDED_SETUP_STEPS,
    },
}
