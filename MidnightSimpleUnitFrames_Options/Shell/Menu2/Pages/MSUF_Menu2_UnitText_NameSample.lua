-- The page supplies sample inputs; runtime text state owns formatting and the sink.
local _, MSUF = ...
local M = MSUF.MSUF2
local Sample = {}
M.UnitNameSample = Sample

local HAS_CHARACTER_SURNAMES = MSUF.Client.HasCharacterSurnames == true

function Sample.Name()
    if HAS_CHARACTER_SURNAMES then
        local parts = M.EnsureDB().general.characterNameParts
        if parts == "FIRST" then return "Alexandriana" end
        if parts == "SURNAME" then return "Brightwhisper" end
        return "Alexandriana Brightwhisper"
    end
    return "Alexandriana"
end

local function State(value)
    local state = value._msufNameSample
    if not state then
        local color = M.Theme.colors.text
        state = { nameText = value, _msufTextRuntime = {},
            MSUFSpec = { textColor = { r = color[1], g = color[2], b = color[3], a = color[4] or 1 } } }
        value._msufNameSample = state
    end
    return state
end

-- Both examples use the runtime painter and its UTF-8 formatter.
function Sample.PaintFormat(value, name, mode, maxChars, showDots, side)
    local state = State(value)
    local rt = state._msufTextRuntime
    rt.nameFormat = MSUF.UFText.ResolveNameFormat(mode)
    rt.nameFormatMax, rt.nameLegacyShortenMax = maxChars, maxChars
    rt.nameFormatter = rt.nameFormat and MSUF.UFText.NameFormatter or MSUF.UFText.TruncateName
    rt.nameShortenSide, rt.nameLegacyShortenDots = side, showDots
    rt.nameLegacyTruncation = rt.nameFormat ~= nil or maxChars > 0
    MSUF.UFText.PaintSampleName(state, name)
end

function Sample.Paint(value, unit, name, groupAllowed)
    local state = State(value)
    local db = M.EnsureDB()
    MSUF.UF.Config.ResolveNameShortening(db, db.general, db[unit], unit, state._msufTextRuntime)
    local mode = state._msufTextRuntime.nameFormat
    if mode then
        local rt = state._msufTextRuntime
        name = MSUF.UFText.FormatName(state, name, mode, rt.nameShortenMax, rt.nameShortenDots, rt.nameShortenSide)
    end
    state._msufTextRuntime.nameFormat = nil
    state._msufTextRuntime.nameLegacyTruncation = false
    local owner = M.UnitPage
    if groupAllowed and owner.ReadStatusBool(unit, "showRaidGroupInName", false) then
        local group = MSUF.UFStatusRuntime.RaidGroupText(owner.ReadText(unit, "raidGroupNameStyle", "PAREN"), 2)
        name = name .. " " .. group
    end
    MSUF.UFText.PaintSampleName(state, name)
end
