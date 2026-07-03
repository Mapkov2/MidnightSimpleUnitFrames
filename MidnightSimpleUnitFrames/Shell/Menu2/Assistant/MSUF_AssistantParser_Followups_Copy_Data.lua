-- Assistant copy-followup parser data.
-- Literal phrases live here so parser logic stays focused on workflow behavior.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Data = A.ParserData or {}
A.ParserData = Data

Data.COPY_ACTION_FOLLOWUP_TERMS = {
    "copy that", "copy it", "copy the same", "copy same",
    "do that", "do it", "do the same", "same for", "same to",
    "apply that", "apply it", "apply the same", "also to", "also for",
    "repeat that", "repeat it",
    "das auch", "mach das", "mach das gleiche", "gleiches fuer", "gleiches fur",
    "auch fuer", "auch fur", "kopiere das", "uebernehme das",
}

Data.COPY_ACTION_EXPLICIT_FOLLOWUP_TERMS = {
    "copy that", "copy it", "copy the same", "copy same",
    "kopiere das", "uebernehme das",
}
