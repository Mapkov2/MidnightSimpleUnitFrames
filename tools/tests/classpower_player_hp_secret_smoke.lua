-- classpower_player_hp_secret_smoke.lua <repoRoot>
--
-- The optional second Player HP bar (ClassPower/MSUF_CP_PlayerHP.lua) while
-- Midnight keeps player health secret (UnitHealth, UnitHealthMax and
-- UnitHealthPercent are SecretReturns, Blizzard UnitDocumentation.lua):
--   * mirroring the player frame's text copies a FontString whose GetText()
--     returns a secret string: it goes straight to SetText, never compared;
--   * its own text shows the percent through the C sink
--     (SetFormattedText with UnitHealthPercent(..., ScaleTo100)) instead of
--     going blank.
-- Secrets come from tools/tests/classpower_secrets.lua (type() answers
-- "number"/"string", comparisons raise, a line hook records == / ~= / not on a
-- secret local).
--
-- Plain Lua 5.1, repo root as arg 1.

local repo = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local PLAYER_HP = repo .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_PlayerHP.lua"

local Stubs = assert(loadfile(repo .. "/.github/scripts/msuf_test_stubs.lua"))()
local Secrets = assert(loadfile(repo .. "/tools/tests/classpower_secrets.lua"))()

local failures = {}
local function Check(condition, message)
    if not condition then failures[#failures + 1] = message end
end

local S = {}

--- Builds a fresh Player HP feature over the given bars settings.
local function Build(bars, player)
    local env = Stubs.New({ timer = "queue" })
    env:InstallGlobals({ secretValue = true })
    Secrets.Install()
    _G.MSUF_CP_CORE_BUILDERS = nil
    _G.MSUF_UF_NormalizePlayerHPShape = function(value)
        value = value and tostring(value):upper() or "BAR"
        return value ~= "" and value or "BAR"
    end
    _G.MSUF_UF_NormalizeClassPowerShape = function() return "BAR" end
    _G.MSUF_UF_ShapeOutlineAlpha = function() return 1 end
    _G.MSUF_SetFontChecked = function(region, path, size, flags)
        region:SetFont(path, size, flags)
        return true
    end
    _G.CurveConstants = { ScaleTo100 = { curve = "ScaleTo100" } }
    _G.UnitHealthPercent = function(_, _, curve)
        if curve == _G.CurveConstants.ScaleTo100 then return S.percent100 end
        return S.percent
    end
    local ns = { ExportPublic = function(name, value) _G[name] = value return value end }
    assert(loadfile(PLAYER_HP))("MidnightSimpleUnitFrames", ns)

    local b = { playerHPBarEnabled = true, playerHPBarWidthMode = "custom", playerHPBarWidth = 180,
        playerHPBarHeight = 8 }
    for key, value in pairs(bars or {}) do b[key] = value end
    _G.MSUF_DB = { bars = b, player = player or { showHP = true }, general = {} }

    local playerFrame = CreateFrame("Frame", nil, UIParent)
    playerFrame:SetSize(200, 40)
    playerFrame.shown = true
    local api = _G.MSUF_CP_CORE_BUILDERS.PLAYER_HP({
        CP = {},
        _cpDB = { bars = b },
        UnitHealth = function() return S.hp end,
        UnitHealthMax = function() return S.maxHP end,
        UnitClass = function() return "Warrior", "WARRIOR" end,
        RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } },
        CreateFrame = CreateFrame,
        GetPlayerFrame = function() return playerFrame end,
        ResolveTexture = function() return "Interface\\Buttons\\WHITE8x8" end,
    })
    S.hp, S.maxHP = 500, 1000
    api.Refresh(playerFrame)
    assert(api.PHP.visible and api.PHP.right, "the Player HP bar did not build")
    return api, playerFrame
end

--- Records the native formatted writes of a FontString (secret arguments
--- reach the C sink unformatted, exactly as the client accepts them).
local function RecordFormatted(fs)
    fs.formatted = nil
    fs.SetFormattedText = function(self, pattern, ...)
        self.formatted = { pattern = pattern, n = select("#", ...), ... }
        self.text = nil
    end
end

local function Watched(fn)
    local stop = Secrets.Watch(PLAYER_HP)
    local ok, err = pcall(fn)
    local violations = stop()
    return ok, err, violations
end

local function SecretHealth()
    S.hp, S.maxHP = Secrets.New("number"), Secrets.New("number")
    S.percent100, S.percent = Secrets.New("number"), Secrets.New("number")
end

-- 1. Mirroring the player frame's text: a slot painted from secret health reads
--    back as a secret string.
for _, shape in ipairs({ "BAR", "ORB" }) do
    local api, playerFrame = Build({ playerHPBarShape = shape })
    local PHP = api.PHP
    local secretText = Secrets.New("string")
    playerFrame._msufTextRuntime = { healthSlotCount = 1 }
    playerFrame.hpTextLeft = playerFrame:CreateFontString(nil, "OVERLAY")
    playerFrame.hpTextLeft.shown = true
    playerFrame.hpTextCenter = playerFrame:CreateFontString(nil, "OVERLAY")
    playerFrame.hpTextCenter.shown = true
    playerFrame.hpTextCenter.GetText = function() return secretText end
    playerFrame.hpTextRight = playerFrame:CreateFontString(nil, "OVERLAY")
    playerFrame.hpTextRight.shown = false
    SecretHealth()
    local ok, err, violations = Watched(function() api.Update("UNIT_HEALTH") end)
    Check(ok, shape .. ": copying secret player text raised: " .. tostring(err))
    Check(#violations == 0, shape .. ": copied player text was compared while secret:\n    "
        .. table.concat(violations, "\n    "))
    Check(PHP.center.text == secretText, shape .. ": the secret player text did not reach the centre slot")
end

-- 2. Own text: the percent goes through the C sink.
do
    local api = Build({ playerHPBarUsePlayerText = false, playerHPBarTextRight = "CURPERCENT" })
    local PHP = api.PHP
    S.hp, S.maxHP = 500, 1000
    api.Update("UNIT_HEALTH")
    Check(PHP.right.text == "500 50%", "plain own text changed: " .. tostring(PHP.right.text))
    RecordFormatted(PHP.right)
    SecretHealth()
    local ok, err, violations = Watched(function() api.Update("UNIT_HEALTH") end)
    Check(ok, "own text with secret health raised: " .. tostring(err))
    Check(#violations == 0, "own text compared a secret:\n    " .. table.concat(violations, "\n    "))
    local formatted = PHP.right.formatted
    Check(formatted and formatted.pattern == "%.0f%%" and formatted[1] == S.percent100,
        "own text with secret health is blank instead of the native percent")
    Check(PHP.left.text == "" and PHP.center.text == "", "slots without a percent mode must stay empty")
end

do
    local api = Build({ playerHPBarUsePlayerText = false, playerHPBarTextRight = "PERCENT",
        playerHPBarTextRightHidePercentSymbol = true })
    RecordFormatted(api.PHP.right)
    SecretHealth()
    api.Update("UNIT_HEALTH")
    local formatted = api.PHP.right.formatted
    Check(formatted and formatted.pattern == "%.0f" and formatted[1] == S.percent100,
        "a hidden percent symbol must drop the % from the native format")
end

do
    -- Compact (orb) text shows the percent while health is secret.
    local api = Build({ playerHPBarUsePlayerText = false, playerHPBarShape = "ORB",
        playerHPBarTextRight = "CURRENT" })
    RecordFormatted(api.PHP.center)
    SecretHealth()
    api.Update("UNIT_HEALTH")
    local formatted = api.PHP.center.formatted
    Check(formatted and formatted.pattern == "%.0f%%" and formatted[1] == S.percent100,
        "compact text with secret health is blank instead of the native percent")
end

if #failures > 0 then
    error("classpower_player_hp_secret_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_player_hp_secret_smoke: ok (secret copy, own percent, hidden symbol, compact)")
