-- Tagged-mob graying smoke.
--
--   lua tools/tests/tap_denied_gray_smoke.lua <repo root>
--
-- The first player to hit a mob owns its loot and experience; Blizzard's target
-- frame grays it for everyone else (not player controlled and UnitIsTapDenied).
-- Every Classic client and WoW Forever have tagging, Midnight needs no MSUF
-- handling. The client fact SupportsTapDenied decides everything: the compiled
-- flag, the "tapped" NPC kind on the bar, the gray name and the Colors-page
-- controls exist where tagging exists and stay absent on Midnight.
local root = assert(arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local core = root .. "/MidnightSimpleUnitFrames/"
local options = root .. "/MidnightSimpleUnitFrames_Options/"

local function Check(condition, message)
    if not condition then error(message, 2) end
    return condition
end

local function Read(path)
    local handle = assert(io.open(path, "rb"), "cannot open " .. path)
    local text = handle:read("*a"):gsub("\r\n", "\n")
    handle:close()
    return text
end

---------------------------------------------------------------------------
-- Client fact
---------------------------------------------------------------------------
local function LoadClient(isForever)
    _G.WOW_PROJECT_MAINLINE, _G.WOW_PROJECT_ID = 1, 1
    _G.C_AddOns = { GetAddOnMetadata = function() return nil end }
    _G.GetBuildInfo = function() return "test", "test", "test", isForever and 16001 or 120105 end
    _G.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    _G.GameEvent = isForever and { RegisterCamelotEvents = function() end } or nil
    _G.MSUF, _G.MSUF_NS = nil, nil
    local namespace = {}
    assert(loadfile(core .. "Game/Shared/Initialize.lua"))("MidnightSimpleUnitFrames", namespace)
    return namespace.Client
end

Check(LoadClient(true).SupportsTapDenied == true, "Forever must support tagged-mob graying")
Check(LoadClient(false).SupportsTapDenied == false, "Midnight must not compile tagged-mob graying")
local initialize = Read(core .. "Game/Shared/Initialize.lua")
Check(initialize:find("Client.SupportsTapDenied = isVanilla or isMists or isTBC or isForever", 1, true),
    "every Classic client and Forever must carry the fact")

---------------------------------------------------------------------------
-- Compiled flag: both Config copies (Mainline and the Classic shadow)
---------------------------------------------------------------------------
for _, relative in ipairs({ "UnitFrames/Engine/MSUF_UF_Config.lua", "Game/Classic/UnitFrames/MSUF_UF_Config.lua" }) do
    local config = Read(core .. relative)
    Check(config:find("tapped = { 0.50, 0.50, 0.50 },", 1, true), relative .. ": tapped default color missing")
    Check(config:find("MSUF.Client.SupportsTapDenied == true", 1, true), relative .. ": flag is not gated on the client fact")
    Check(config:find('unitKey ~= "player" and unitKey ~= "pet"', 1, true), relative .. ": player and pet must never compile the flag")
    Check(config:find('ApplyNpcTypeFlags(text, general, "npcTypeColorText", unit)', 1, true)
        and config:find('ApplyNpcTypeFlags(health, general, "npcTypeColorBar", out.key)', 1, true),
        relative .. ": unit key is not forwarded to the flag compile")
end

---------------------------------------------------------------------------
-- Runtime: cached reader, bar kind, name override
---------------------------------------------------------------------------
local SECRET = { secret = true }
_G.issecretvalue = function(value) return value == SECRET end
local tapDenied, playerControlled, tapReads = false, false, 0
_G.UnitIsTapDenied = function() tapReads = tapReads + 1; return tapDenied end
_G.UnitPlayerControlled = function() return playerControlled end
_G.UnitReaction = function() return 2 end
_G.UnitIsDeadOrGhost = function() return false end

local unitState = {}
local UF = {
    Layers = {},
    Clamp01 = function(value, fallback) return tonumber(value) or fallback end,
    RegisterElement = function() end,
    FreshUnitState = function() return unitState end,
    IsUnitToken = function(unit) return type(unit) == "string" end,
    ReadUnitExistsCached = function() return true, true end,
    ReadUnitIsPlayerCached = function() return false, true end,
    ReadUnitClassCached = function() return nil, nil end,
    ReadConnectedCached = function() return true, true end,
    ReadDeadCached = function() return false, true end,
}
local MSUF = { UF = UF, ExportPublic = function(name, value) _G[name] = value end }
_G.MSUF_NS = MSUF
assert(loadfile(core .. "UnitFrames/Engine/MSUF_UF_Shared.lua"))("TapDeniedSmoke", MSUF)
assert(loadfile(core .. "UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua"))("TapDeniedSmoke", MSUF)
local C = assert(MSUF.UFBarTextCommon, "bars common export table not found")
local UnitTapDenied = assert(C.UnitTapDenied, "UnitTapDenied is not exported")
local UnitNPCKind, NPCColor = assert(C.UnitNPCKind), assert(C.NPCColor)

local frame = { MSUFUnitKey = "target", configKey = "target" }
local function Spec(enabled)
    return { key = "target", health = { tapDeniedGray = enabled, npcColorMode = "reaction" },
        text = { tapDeniedGray = enabled, npcColorMode = "reaction" } }
end
local function Reset() for key in pairs(unitState) do unitState[key] = nil end; tapReads = 0 end

Reset(); tapDenied, playerControlled = true, false
Check(UnitTapDenied(frame, "target") == true, "a tagged mob must read as tap denied")
Check(UnitTapDenied(frame, "target") == true and tapReads == 1, "the tag state must be read once per dispatch state")
Reset(); playerControlled = true
Check(UnitTapDenied(frame, "target") == false, "a player-controlled unit is never grayed")
Reset(); playerControlled, tapDenied = false, SECRET
Check(UnitTapDenied(frame, "target") == false, "a secret tag state must not gray the unit")
Reset(); tapDenied, playerControlled = true, SECRET
Check(UnitTapDenied(frame, "target") == false, "a secret control state must not gray the unit")

Reset(); tapDenied, playerControlled = true, false
Check(UnitNPCKind(frame, "target", Spec(true)) == "tapped", "a tagged mob must take the tapped bar kind")
Check(UnitNPCKind(frame, "target", Spec(true), true) == "tapped", "the name path must see the same kind")
local r, g, b = NPCColor("tapped")
Check(r == 0.5 and g == 0.5 and b == 0.5, "tapped must default to neutral gray")
Reset()
Check(UnitNPCKind(frame, "target", Spec(false)) == "enemy", "the toggle off must keep the reaction kind")
Check(tapReads == 0, "the toggle off must not read the tag state at all")
Reset(); tapDenied = false
Check(UnitNPCKind(frame, "target", Spec(true)) == "enemy", "an untagged hostile mob keeps its reaction kind")

---------------------------------------------------------------------------
-- Name override and event route (source contracts; the text runtime needs the
-- full frame harness to execute)
---------------------------------------------------------------------------
local textCommon = Read(core .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua")
local overrideAt = textCommon:find("if text.tapDeniedGray == true and UnitTapDenied and UnitTapDenied(frame, unit) then", 1, true)
local customAt = textCommon:find("local override = text.nameColor", 1, true)
Check(overrideAt and customAt and overrideAt < customAt, "the gray name must outrank the custom name color")
local textRuntime = Read(core .. "UnitFrames/Engine/Elements/MSUF_UF_Text_Runtime.lua")
Check(textRuntime:find("if text.tapDeniedGray == true then\n    return true\n  end", 1, true),
    "a graying name must subscribe to the UNIT_FACTION color route")

---------------------------------------------------------------------------
-- Menu: gated on the fact so Midnight keeps Retail's page
---------------------------------------------------------------------------
local colors = Read(options .. "Shell/Menu2/Pages/MSUF_Menu2_AdvancedColors.lua")
local gateAt = colors:find("if MSUF.Client and MSUF.Client.SupportsTapDenied == true then", 1, true)
local swatchAt = colors:find('"Tagged by others"', 1, true)
local toggleAt = colors:find('"Gray out mobs tagged by others"', 1, true)
Check(gateAt and swatchAt and toggleAt and gateAt < swatchAt and gateAt < toggleAt,
    "the Colors-page controls must sit behind the client fact")
Check(colors:find("g.tapDeniedGray = nil", 1, true), "Reset Unitframe Colors must clear the toggle")

print("PASS tap denied gray: client fact, compiled flag, cached reader, bar kind, name override, menu gate")
