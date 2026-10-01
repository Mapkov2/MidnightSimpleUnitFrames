-- uf_elements_quality_contracts_smoke.lua <repo root>
--
-- Small unit-frame element contracts from the 2026-09-30 element review:
--   1. The mouseover highlight debug command finds the target frame in the
--      engine's frame list. Engine frames carry MSUFUnitKey, never .unit, so
--      the old .unit lookup could not find anything.
--   2. The legacy group name truncation (migrated 5.73 Group profiles) builds
--      no closure per name update and still cuts UTF-8 names by characters,
--      from either side, with or without dots.
-- Boots the WoW Forever core (shared code) through tools/tests/client_world.lua.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local function Check(condition, message)
    if not condition then error(message, 2) end
end
local function Read(relative)
    local handle = assert(io.open(root .. "/" .. relative, "rb"), "cannot open " .. relative)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

local world = assert(loadfile(root .. "/tools/tests/client_world.lua"))().New(root, "Forever")
local env, core = world.env, world.core
env.UnitExists = function() return true end
world:Boot()
local failure = world:FirstFailure()
Check(not failure, failure and failure.message)
env.MSUF_InitProfiles(); env.MSUF_EnsureDB(true)
local UF = core.UF

-- 1. Highlight debug: the frame list fallback matches MSUFUnitKey.
local printed = {}
env.print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
end
local target = env.CreateFrame("Frame", "MSUFSmokeTargetFrame", env.UIParent)
target:SetSize(200, 40); target.MSUFUnitKey = "target"
local other = env.CreateFrame("Frame", "MSUFSmokePlayerFrame", env.UIParent)
other:SetSize(200, 40); other.MSUFUnitKey = "player"
env.MSUF_target = nil
local getFrame, frameList = UF.GetFrame, UF.frameList
UF.GetFrame, UF.frameList = function() return nil end, { other, target }
Check(type(env.MSUF_HighlightDebug) == "function", "the highlight debug command is missing")
env.MSUF_HighlightDebug()
UF.GetFrame, UF.frameList = getFrame, frameList
local found = false
for _, line in ipairs(printed) do
    if line:find("target frame = MSUFSmokeTargetFrame", 1, true) then found = true end
    Check(not line:find("no target frame found", 1, true), "the highlight debug command did not find the target frame in the frame list")
end
Check(found, "the highlight debug command did not report the target frame")

-- 2. Legacy group name truncation: no closure per call, same cuts as before.
local source = Read("MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua")
local body = source:match("\nlocal function TruncateLegacyGroupName%(name, rt%)\n(.-)\nend\n")
Check(body ~= nil, "TruncateLegacyGroupName is missing")
Check(not body:find("function", 1, true), "TruncateLegacyGroupName builds a closure on every name update")

local Text = assert(core.UFText, "the unit text module is missing")
local frame = env.CreateFrame("Frame", nil, env.UIParent)
frame.MSUFUnitKey = "party1"
frame.nameText = frame:CreateFontString(nil, "OVERLAY")
local function Cut(name, maxChars, side, dots)
    frame._msufTextRuntime = { nameLegacyTruncation = true, nameLegacyShortenMax = maxChars,
        nameShortenSide = side, nameLegacyShortenDots = dots }
    frame._msufPreviewNameText = name
    frame.nameText._msufText = nil
    Text.UpdateName(frame, "MSUF_SMOKE", "party1")
    return frame.nameText:GetText()
end
-- "Zoë" has a 2-byte "ë", "日本" 3-byte characters, the emoji 4 bytes.
Check(Cut("Ellesmeria", 4, "RIGHT", true) == "Elle..", "right cut with dots")
Check(Cut("Ellesmeria", 4, "LEFT", true) == "..eria", "left cut with dots")
Check(Cut("Ellesmeria", 4, "RIGHT", false) == "Elle", "right cut without dots")
Check(Cut("Zoëlinde", 3, "RIGHT", false) == "Zoë", "a 2-byte character counts as one")
Check(Cut("日本語の名前", 2, "RIGHT", true) == "日本..", "3-byte characters count as one")
Check(Cut("ab\240\159\152\128cd", 3, "LEFT", false) == "\240\159\152\128cd", "a 4-byte character counts as one")
Check(Cut("Short", 8, "RIGHT", true) == "Short", "a name within the cap stays whole")
print("uf_elements_quality_contracts_smoke: ok")
