-- Assistant exact-alias parser data.
-- Literal tokens live here so parser logic stays focused on index behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ParserData or {}
A.ParserData = Data

Data.REGISTRY_EXACT_ALIAS = {
    MAX_EXACT_ALIAS_TOKENS = 8,
    COMMON_EXACT_ALIAS_TOKENS = {
        a = true,
        an = true,
        ["and"] = true,
        change = true,
        disable = true,
        enable = true,
        ["for"] = true,
        make = true,
        move = true,
        nudge = true,
        of = true,
        off = true,
        on = true,
        set = true,
        shift = true,
        the = true,
        to = true,
        turn = true,
        player = true,
        target = true,
        focus = true,
        pet = true,
        boss = true,
        party = true,
        raid = true,
        frame = true,
        frames = true,
    },
}
