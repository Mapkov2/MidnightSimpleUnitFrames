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
    assert(loadfile(repo .. "/tools/tests/classpower_collaborators.lua"))().Install(repo, ns)
    _G.MSUF_CP_CONST = nil
    assert(loadfile(repo .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_Constants.lua"))("MidnightSimpleUnitFrames", ns)
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
    local stop = Secrets.Watch(PLAYER_HP, { strict = true })
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

-- 5. The mirror of the player frame's text follows the text writers' change-key modes
--    (rt.healthDispatchKeyMode, named by MSUF.UFText.DISPATCH_KEY in the text formatter).
--    Each mode stamps the values its writer compared; the text is copied only from a
--    frame stamped for the same health inputs. The mode numbers are written out here on
--    purpose: they are what the writers compile, so a renamed or renumbered enum shows.
--    The whole update is also budgeted in VM instructions (this stub world, one health
--    repaint) at what it cost when the modes were bare numbers. The percent modes, which
--    the default text uses, may not cost more; the others read a set, which is 2 to 6
--    instructions more than a literal compare chain whose first branches are one compare.
--    2026-10-03: a copied slot without a plain colour stamp reads FontString:GetTextColor,
--    which is secret for a slot painted from secret health (section 7). The issecretvalue
--    check on that read costs 13 instructions per mirrored slot in this stub world (a C
--    call in the client), +39 on the rows that copy (current stamps): 621 -> 660 unset,
--    655 -> 694 percent. Stale stamps copy nothing and stay as they were.
do
    local ALLOWANCE = 6
    local COPY_COLOUR_CHECK = 39
    local MODES = {
        -- { label, mode, stamped health, stamped max, budget with current stamps, budget with stale stamps,
        --   allowance } for 500 of 1000 health
        { "unset", nil, false, false, 619, 742, ALLOWANCE },
        { "none", 0, false, false, 618, 741, ALLOWANCE },
        { "current", 1, 500, false, 616, 739, ALLOWANCE },
        { "max", 2, false, 1000, 617, 740, ALLOWANCE },
        { "current and max", 3, 500, 1000, 620, 743, ALLOWANCE },
        { "percent", 4, 50, false, 655, 778, 0 },
        { "percent and max", 5, 50, 1000, 656, 779, 0 },
    }
    local DISPATCH_KEY = assert(loadfile(repo .. "/tools/tests/classpower_collaborators.lua"))().DispatchKey(repo)
    for index, name in ipairs({ "NONE", "CURRENT", "MAX", "CURRENT_MAX", "PERCENT", "PERCENT_MAX" }) do
        Check(DISPATCH_KEY[name] == index - 1, "the change-key mode " .. name .. " is not " .. (index - 1))
    end
    for _, row in ipairs(MODES) do
        local label, mode, stampHP, stampMax = row[1], row[2], row[3], row[4]
        for _, stale in ipairs({ false, true }) do
            local budget = (stale and row[6] or row[5] + COPY_COLOUR_CHECK) + row[7]
            local api, playerFrame = Build({ playerHPBarUsePlayerText = true })
            for _, slot in ipairs({ { "hpTextLeft", "L" }, { "hpTextCenter", "C" }, { "hpTextRight", "R" } }) do
                local fs = playerFrame:CreateFontString(nil, "OVERLAY")
                fs.shown = true
                fs._aText = slot[2]
                playerFrame[slot[1]] = fs
            end
            local rt = { healthSlotCount = 1, healthDispatchKeyMode = mode, _lastHealthTextHP = stampHP,
                _lastHealthTextMax = stampMax }
            if stale then
                -- A frame stamped for other inputs: one more health, one more max.
                if stampHP ~= false then rt._lastHealthTextHP = stampHP + 1 else rt._lastHealthTextHP = 1 end
                if stampMax ~= false then rt._lastHealthTextMax = stampMax + 1 end
            end
            playerFrame._msufTextRuntime = rt
            S.hp, S.maxHP = 500, 1000
            api.PHP._hp = nil -- the bar repaints its text as if the health had just changed
            local work = 0
            debug.sethook(function() work = work + 1 end, "", 1)
            api.Update("UNIT_HEALTH")
            debug.sethook()
            Check(work <= budget, "mode " .. label .. (stale and " (stale stamps)" or " (current stamps)") .. ": the update costs "
                .. work .. " VM instructions, budget " .. budget)
            local copied = api.PHP.right.text == "R" and api.PHP.left.text == "L" and api.PHP.center.text == "C"
            Check(copied == not stale, "mode " .. label .. (stale and " (stale stamps)" or " (current stamps)")
                .. (stale and " copied text rendered for other health inputs" or " did not copy the rendered text")
                .. ": right=" .. tostring(api.PHP.right.text))
        end
    end
end

--- Records the colour writes of a widget method ("SetStatusBarColor", "SetTextColor").
local function RecordColor(widget, method)
    local inner = widget[method]
    widget.writes = {}
    widget[method] = function(self, r, g, b, a)
        self.writes[#self.writes + 1] = { r, g, b, a }
        return inner(self, r, g, b, a)
    end
end

-- 6. HP colour "HP Gradient": the shared helper (MSUF_UF_Elements_BarsCommon.lua
--    GradientColor) evaluates UnitHealthPercent(unit, true, curve) per channel, which
--    is SecretReturns while health is secret. The components go to SetStatusBarColor
--    unread, no secret survives as a change stamp (the second update compared the
--    first one's), and a plain colour afterwards is stamped again.
do
    local api = Build({ playerHPBarColorMode = "GRADIENT", playerHPBarUsePlayerText = false,
        playerHPBarTextRight = "NONE" })
    local bar = api.PHP.bar
    RecordColor(bar, "SetStatusBarColor")
    _G.MSUF_NS = _G.MSUF_NS or {}
    _G.MSUF_NS.UFBarTextCommon = { GradientColor = function() return S.gradR, S.gradG, S.gradB, true end }
    for pass = 1, 2 do
        SecretHealth()
        S.gradR, S.gradG, S.gradB = Secrets.New("number"), Secrets.New("number"), 0
        bar.writes = {}
        local ok, err, violations = Watched(function() api.Update("UNIT_HEALTH") end)
        Check(ok, "gradient pass " .. pass .. ": a secret gradient colour raised: " .. tostring(err))
        Check(#violations == 0, "gradient pass " .. pass .. ": a secret gradient colour was compared:\n    "
            .. table.concat(violations, "\n    "))
        local write = bar.writes[#bar.writes]
        Check(write and rawequal(write[1], S.gradR) and rawequal(write[2], S.gradG),
            "gradient pass " .. pass .. ": the secret gradient colour did not reach SetStatusBarColor")
        Check(bar._phpR == nil and bar._msufStatusR == nil,
            "gradient pass " .. pass .. ": a secret gradient colour was kept as a change stamp")
    end
    S.hp, S.maxHP = 400, 1000
    S.gradR, S.gradG, S.gradB = 1, 0.8, 0
    bar.writes = {}
    api.Update("UNIT_HEALTH")
    S.hp = 410
    api.Update("UNIT_HEALTH")
    Check(#bar.writes == 1 and bar.writes[1][2] == 0.8,
        "a plain gradient colour after secret health is not painted once and stamped: " .. #bar.writes .. " writes")
    _G.MSUF_NS.UFBarTextCommon = nil
end

-- 7. Mirrored text with "HP text color by health": the player frame paints its slots
--    with a secret colour (MSUF_UF_Text_Common.lua SetHealthTextSlotColorSecret clears
--    _msufTextR), so FontString:GetTextColor reads back secret (SecretReturnsForAspect
--    VertexColor). The copy hands it to SetTextColor unread and keeps no secret stamp;
--    a plain colour afterwards is painted once and stamped again.
for _, shape in ipairs({ "BAR", "ORB" }) do
    local api, playerFrame = Build({ playerHPBarUsePlayerText = true, playerHPBarShape = shape })
    local PHP = api.PHP
    playerFrame._msufTextRuntime = { healthSlotCount = 1 }
    for _, key in ipairs({ "hpTextLeft", "hpTextCenter", "hpTextRight" }) do
        local fs = playerFrame:CreateFontString(nil, "OVERLAY")
        fs.shown = true
        fs._aText = "50%"
        fs.GetTextColor = function() return S.textR, S.textG, S.textB, S.textA end
        playerFrame[key] = fs
    end
    local slots = shape == "ORB" and { PHP.center } or { PHP.left, PHP.center, PHP.right }
    for _, fs in ipairs(slots) do RecordColor(fs, "SetTextColor") end
    for pass = 1, 2 do
        SecretHealth()
        S.textR, S.textG, S.textB, S.textA = Secrets.New("number"), Secrets.New("number"),
            Secrets.New("number"), Secrets.New("number")
        for _, fs in ipairs(slots) do fs.writes = {} end
        local ok, err, violations = Watched(function() api.Update("UNIT_HEALTH") end)
        local label = shape .. " text colour pass " .. pass
        Check(ok, label .. ": a secret player text colour raised: " .. tostring(err))
        Check(#violations == 0, label .. ": a secret player text colour was compared:\n    "
            .. table.concat(violations, "\n    "))
        for _, fs in ipairs(slots) do
            local write = fs.writes[#fs.writes]
            Check(write and rawequal(write[1], S.textR) and rawequal(write[4], S.textA),
                label .. ": the secret player text colour did not reach SetTextColor")
            Check(fs._phpTextR == nil and fs._phpTextA == nil, label .. ": a secret text colour was kept as a stamp")
        end
    end
    S.textR, S.textG, S.textB, S.textA = 1, 0.5, 0, 1
    for _, fs in ipairs(slots) do fs.writes = {} end
    SecretHealth()
    api.Update("UNIT_HEALTH")
    SecretHealth()
    api.Update("UNIT_HEALTH")
    for _, fs in ipairs(slots) do
        Check(#fs.writes == 1 and fs.writes[1][2] == 0.5, shape
            .. ": a plain player text colour after a secret one is not painted once and stamped: "
            .. #fs.writes .. " writes")
    end
end

if #failures > 0 then
    error("classpower_player_hp_secret_smoke:\n  " .. table.concat(failures, "\n  "), 0)
end
print("classpower_player_hp_secret_smoke: ok (secret copy, own percent, hidden symbol, compact, change-key modes,"
    .. " secret gradient, secret text colour)")
