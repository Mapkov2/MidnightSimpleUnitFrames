-- Assistant GroupFrames layout setting registry.
-- Loaded before MSUF_AssistantRegistry_GroupFramesSettings.lua; the main domain passes helpers in.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.GroupFramesRegistry = A.GroupFramesRegistry or {}

function A.GroupFramesRegistry.RegisterLayoutSettings(ctx, scope, defaults)
    if type(ctx) ~= "table" or type(scope) ~= "string" then return end
    defaults = type(defaults) == "table" and defaults or {}

    local AddAliasesForUnit = ctx.AddAliasesForUnit
    local RegisterGroupBoolean = ctx.RegisterGroupBoolean
    local RegisterGroupNumber = ctx.RegisterGroupNumber

    if type(AddAliasesForUnit) ~= "function" then return end
    if type(RegisterGroupBoolean) ~= "function" or type(RegisterGroupNumber) ~= "function" then return end

    local widthDefault = defaults.width or 80
    local heightDefault = defaults.height or 32
    local maxColumnsDefault = defaults.maxColumns or 8
    local powerHeightDefault = defaults.powerHeight or 4

    local aliases = {}
    AddAliasesForUnit(aliases, scope, "width", "breite")
    AddAliasesForUnit(aliases, scope, "frame width", "frame breite")
    RegisterGroupNumber(scope, "width", "width", "Width", widthDefault, 40, 300, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "height", "hoehe")
    AddAliasesForUnit(aliases, scope, "frame height", "frame hoehe")
    RegisterGroupNumber(scope, "height", "height", "Height", heightDefault, 16, 120, 1, "rebuild", aliases)

    aliases = {}
    -- No bare "frame" alias here. AddAliasesForUnit expands it into "party
    -- frame", "raid frame", "frame party" and so on, which name the FRAME, not
    -- its horizontal offset -- so every sentence that merely mentioned the
    -- frame exact-alias matched X Position and was answered with "what value do
    -- you want me to use for Party X Position?". The remaining aliases all name
    -- the control itself.
    AddAliasesForUnit(aliases, scope, "frame position", "frame position")
    AddAliasesForUnit(aliases, scope, "x position", "x position")
    AddAliasesForUnit(aliases, scope, "x offset", "x versatz")
    AddAliasesForUnit(aliases, scope, "frame x", "frame x")
    AddAliasesForUnit(aliases, scope, "frame x offset", "frame x versatz")
    AddAliasesForUnit(aliases, scope, "horizontal position", "horizontale position")
    RegisterGroupNumber(scope, "offsetX", "offsetX", "X Position", 0, -4096, 4096, 1, "rebuild", aliases)

    aliases = {}
    -- Same as X Position above: a bare "frame" alias names the frame, not its
    -- vertical offset.
    AddAliasesForUnit(aliases, scope, "frame position", "frame position")
    AddAliasesForUnit(aliases, scope, "y position", "y position")
    AddAliasesForUnit(aliases, scope, "y offset", "y versatz")
    AddAliasesForUnit(aliases, scope, "frame y", "frame y")
    AddAliasesForUnit(aliases, scope, "frame y offset", "frame y versatz")
    AddAliasesForUnit(aliases, scope, "vertical position", "vertikale position")
    RegisterGroupNumber(scope, "offsetY", "offsetY", "Y Position", 0, -4096, 4096, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "spacing", "abstand")
    AddAliasesForUnit(aliases, scope, "frame spacing", "frame abstand")
    AddAliasesForUnit(aliases, scope, "space between frames")
    AddAliasesForUnit(aliases, scope, "gap between frames")
    AddAliasesForUnit(aliases, scope, "closer together")
    AddAliasesForUnit(aliases, scope, "farther apart")
    AddAliasesForUnit(aliases, scope, "more space between frames")
    AddAliasesForUnit(aliases, scope, "less space between frames")
    RegisterGroupNumber(scope, "spacing", "spacing", "Spacing", 1, 0, 20, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "units per column", "einheiten pro spalte")
    AddAliasesForUnit(aliases, scope, "members per column", "spieler pro spalte")
    AddAliasesForUnit(aliases, scope, "players per column")
    AddAliasesForUnit(aliases, scope, "frames per column")
    RegisterGroupNumber(scope, "unitsPerColumn", "unitsPerColumn", "Units Per Column", 5, 1, 40, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "max columns", "max spalten")
    AddAliasesForUnit(aliases, scope, "columns", "spalten")
    AddAliasesForUnit(aliases, scope, "frames in columns")
    AddAliasesForUnit(aliases, scope, "number of columns")
    RegisterGroupNumber(scope, "maxColumns", "maxColumns", "Max Columns", maxColumnsDefault, 1, 8, 1, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "preserve raid groups", "raid gruppen beibehalten")
    AddAliasesForUnit(aliases, scope, "keep raid groups")
    AddAliasesForUnit(aliases, scope, "keep raid groups together")
    RegisterGroupBoolean(scope, "preserveRaidGroups", "preserveRaidGroups", "Preserve Raid Groups", false, "rebuild", aliases)

    aliases = {}
    AddAliasesForUnit(aliases, scope, "power height", "power hoehe")
    AddAliasesForUnit(aliases, scope, "power bar height", "power balken hoehe")
    RegisterGroupNumber(scope, "powerHeight", "powerHeight", "Power Bar Height", powerHeightDefault, 0, 30, 1, "rebuild", aliases)
end
