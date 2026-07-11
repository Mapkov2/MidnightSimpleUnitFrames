-- Assistant Castbars detail enum and alias data.
-- Loaded before MSUF_AssistantRegistry_Castbars_Details.lua.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.CastbarsRegistry = A.CastbarsRegistry or {}

A.CastbarsRegistry.DetailData = {
    CASTBAR_ICON_POSITION_VALUES = { "LEFT", "RIGHT", "INSIDE_LEFT", "INSIDE_RIGHT" },
    CASTBAR_TEXT_POSITION_VALUES = { "LEFT", "CENTER", "RIGHT", "ABOVE", "BELOW" },
    CASTBAR_TEXT_ALIGN_VALUES = { "LEFT", "CENTER", "RIGHT" },
    CASTBAR_TRUNCATE_VALUES = { "AUTO", "CLIP", "NONE" },
    CASTBAR_ICON_BORDER_VALUES = { "NONE", "DARK", "CASTBAR" },
    CASTBAR_TIME_FORMAT_VALUES = { "CURRENT", "ELAPSED", "ELAPSED_MAX", "CURRENT_MAX" },

    CASTBAR_ICON_POSITION_ALIASES = {
        left = "LEFT",
        links = "LEFT",
        right = "RIGHT",
        rechts = "RIGHT",
        ["inside left"] = "INSIDE_LEFT",
        ["inside-left"] = "INSIDE_LEFT",
        ["inside right"] = "INSIDE_RIGHT",
        ["inside-right"] = "INSIDE_RIGHT",
    },

    CASTBAR_TEXT_POSITION_ALIASES = {
        left = "LEFT",
        links = "LEFT",
        center = "CENTER",
        centre = "CENTER",
        mitte = "CENTER",
        right = "RIGHT",
        rechts = "RIGHT",
        above = "ABOVE",
        oben = "ABOVE",
        below = "BELOW",
        unten = "BELOW",
    },

    CASTBAR_TEXT_ALIGN_ALIASES = {
        left = "LEFT",
        links = "LEFT",
        center = "CENTER",
        centre = "CENTER",
        mitte = "CENTER",
        right = "RIGHT",
        rechts = "RIGHT",
    },

    CASTBAR_TRUNCATE_ALIASES = {
        auto = "AUTO",
        ["auto fit"] = "AUTO",
        automatic = "AUTO",
        automatisch = "AUTO",
        clip = "CLIP",
        clipped = "CLIP",
        ["fixed clip"] = "CLIP",
        ["manual width"] = "CLIP",
        none = "NONE",
        off = "NONE",
        aus = "NONE",
        ["no limit"] = "NONE",
        ["no width limit"] = "NONE",
        unlimited = "NONE",
    },

    CASTBAR_ICON_BORDER_ALIASES = {
        none = "NONE",
        off = "NONE",
        aus = "NONE",
        ["no border"] = "NONE",
        dark = "DARK",
        ["dark border"] = "DARK",
        black = "DARK",
        castbar = "CASTBAR",
        ["castbar border"] = "CASTBAR",
    },

    CASTBAR_TIME_FORMAT_ALIASES = {
        current = "CURRENT",
        remaining = "CURRENT",
        rest = "CURRENT",
        verbleibend = "CURRENT",
        elapsed = "ELAPSED",
        vergangen = "ELAPSED",
        ["elapsed total"] = "ELAPSED_MAX",
        ["elapsed max"] = "ELAPSED_MAX",
        ["elapsed / total"] = "ELAPSED_MAX",
        ["remaining total"] = "CURRENT_MAX",
        ["remaining max"] = "CURRENT_MAX",
        ["remaining / total"] = "CURRENT_MAX",
        total = "CURRENT_MAX",
    },
}
