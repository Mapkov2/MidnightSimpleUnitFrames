-- Additional guided-setup guide variants for Assistant diagnostics.
-- Loaded after MSUF_AssistantRegistry_Diagnostics_Data.lua so the main guide fallback exists.
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

Guides.group_frames = {
    label = "Group Frames Setup",
    steps = {
        {
            key = "group_visibility",
            title = "Party and Raid Visibility",
            page = "gf_layout",
            goal = "Decide which group frames should exist before tuning dense details.",
            body = "Start with Party and Raid visibility, then check anything that should be visible but is not.",
            examples = {
                "show party group frames",
                "show raid group frames",
                "check party frames",
            },
        },
        {
            key = "group_geometry",
            title = "Group Size and Growth",
            page = "gf_layout",
            goal = "Make group frames scan cleanly at the roster sizes you actually play.",
            body = "Tune width, scale, growth, and breakpoint scale before text and indicators.",
            examples = {
                "make raid width 80",
                "set raid scale to 90",
                "set raid frames to grow right",
            },
        },
        {
            key = "group_text",
            title = "Group Health and Text",
            page = "gf_bars",
            goal = "Keep readable health information without crowding each group cell.",
            body = "Name Party or Raid explicitly when you are not already on the group page.",
            examples = {
                "move party frame name down",
                "set party power center text to current percent",
                "set party power text size to 11",
            },
        },
        {
            key = "group_indicators",
            title = "Group Status & Indicators",
            page = "gf_indicators",
            goal = "Verify group status icons and editor selections after layout and text feel stable.",
            body = "Selection requests help with editor choices; then check visibility if an icon still looks wrong.",
            examples = {
                "turn off ready check symbol for all group frames",
                "select party leader icon indicator",
                "select bottom right corner editor slot",
            },
        },
    },
}

Guides.castbars = {
    label = "Cast Bars Setup",
    steps = {
        {
            key = "castbar_visibility",
            title = "Cast Bar Visibility",
            page = "opt_castbar",
            goal = "Make the cast bars you care about visible before adjusting detail controls.",
            body = "Target is usually the first cast bar to verify; Player, Focus, and Boss can be added as needed.",
            examples = {
                "show target cast bar",
                "show player cast bar",
                "check target cast bar",
            },
        },
        {
            key = "castbar_layout",
            title = "Cast Bar Layout",
            page = "opt_castbar",
            goal = "Place cast bars and attached icons where they do not fight the unit frames.",
            body = "Move the bar or its text/icon parts separately when only one piece is wrong.",
            examples = {
                "move target cast bar icon right 4",
                "move focus kick icon down 3",
                "set target cast bar height to 18",
            },
        },
        {
            key = "castbar_details",
            title = "Cast Bar Details",
            page = "opt_castbar",
            goal = "Keep important cast information visible and hide detail noise you do not read.",
            body = "Detailed requests target cast bar controls instead of toggling the whole cast bar.",
            examples = {
                "turn off target cast bar icon",
                "turn off target cast bar interrupt",
                "set cast bar text color red",
            },
        },
    },
}

Guides.profiles = {
    label = "Profiles Setup",
    steps = {
        {
            key = "profile_backup",
            title = "Backup Current Profile",
            page = "profiles",
            goal = "Create an export point before doing broad layout work.",
            body = "Profile exports come from MSUF's profile export when MSUF can provide it.",
            examples = {
                "export current profile",
                "select profile export kind group frames",
                "copy discord link",
            },
        },
        {
            key = "profile_create",
            title = "Create or Prepare a Profile",
            page = "profiles",
            goal = "Prepare a named profile before switching or importing.",
            body = "The Assistant can prepare profile values and will ask for confirmation before destructive profile actions.",
            examples = {
                "set profile name field to Raid Draft",
                "copy profile Raid Draft",
                "turn on profile import and create new profile",
            },
        },
        {
            key = "profile_import",
            title = "Import and Spec Routing",
            page = "profiles",
            goal = "Keep imports and automatic spec switching explicit and reversible where MSUF can take snapshots.",
            body = "Run profile checks after imports, switches, or spec assignments.",
            examples = {
                "import profile",
                "enable spec auto-switch",
                "diagnose profiles",
            },
        },
    },
}
