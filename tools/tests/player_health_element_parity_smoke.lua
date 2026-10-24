-- Actual old builder versus actual UF element, with the immutable 9c29a35a oracle.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local Stubs = dofile(root .. "/.github/scripts/msuf_test_stubs.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
local function Build(flavor, old)
    local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
    env:InstallGlobals({ secretValue = true, time = true })
    Secrets.Install()
    MSUF_CP_CONST, MSUF_CP_CORE_BUILDERS = nil, nil
    local ns = { Client = { IsRetail = flavor == "Mainline" or flavor == "Forever",
        IsClassic = flavor ~= "Mainline" and flavor ~= "Forever", IsForever = flavor == "Forever" } }
    ns.ExportPublic = function(name, value) _G[name] = value
    return value end
    MSUF_NS = ns
    local S = { hp = 500, maximum = 1000, percent = 50 }
    UnitHealth = function() return S.hp end
    UnitHealthMax = function() return S.maximum end
    UnitClass = function() return "WARRIOR", "WARRIOR" end
    UnitHealthPercent = function() return S.percent end
    UnitAffectingCombat = function() return false end
    RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    CurveConstants = { ScaleTo100 = {} }
    MSUF_GetFontPath = function() return "Fonts\\FRIZQT__.TTF" end
    MSUF_GetFontFlags = function() return "OUTLINE" end
    MSUF_SetFontChecked = function(fs, path, size, flags) fs:SetFont(path, size, flags)
    return true end
    env.Methods.SetFormattedText = function(self, pattern, number)
        self.nativeFormat, self.nativeArg = pattern, number
        if issecretvalue(number) then self.text = number else self.text = string.format(pattern, number) end
    end
    local load = function(path) assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))("MSUF", ns) end
    dofile(root .. "/tools/tests/classpower_collaborators.lua").Install(root, ns)
    load("Libs/MSUFUnitFrames/MSUF_UF_Layers.lua")
    load("UnitFrames/Engine/MSUF_UF_Shared.lua")
    load("Runtime/MSUF_NumberFormat.lua")
    load("UnitFrames/Engine/Elements/MSUF_UF_Elements_BarsCommon.lua")
    load("UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua")
    load("UnitFrames/Engine/Elements/MSUF_UF_Text_SlotCompile.lua")
    load("UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua")
    load("ClassPower/MSUF_CP_Constants.lua")
    load("ClassPower/MSUF_CP_Visibility.lua")
    if old then
        -- The frozen pre-refactor oracle reads the three shape helpers as globals when it builds; the
        -- client keeps them in the namespace registry, so the replay publishes them for it.
        for _, name in ipairs({ "MSUF_UF_NormalizeClassPowerShape", "MSUF_UF_NormalizePlayerHPShape",
            "MSUF_UF_ShapeOutlineAlpha" }) do
            if rawget(_G, name) == nil then _G[name] = ns.PublicGlobals[name] end
        end
        assert(loadfile(root .. "/tools/fixtures/player_health/CP_PlayerHP.baseline.lua"))("MSUF", ns)
    else
        load("ClassPower/MSUF_CP_PlayerHP.lua")
        load("UnitFrames/Engine/Elements/MSUF_UF_PlayerHP.lua")
    end
    local player = env:CreateFrame("Frame", "ScenePlayer", UIParent)
    player:SetSize(220, 40)
    player:SetFrameLevel(3)
    player:Show()
    player.targetPowerBar = env:CreateFrame("StatusBar", "ScenePower", player)
    player.targetPowerBar:SetSize(190, 8)
    player.targetPowerBar:Show()
    local CP = { container = env:CreateFrame("Frame", "SceneClass", player) }
    CP.container:SetSize(175, 6)
    local b = { playerHPBarEnabled = true, playerHPBarUsePlayerText = false }
    local db = { bars = b, player = {}, general = {} }
    MSUF_DB = db
    local api = MSUF_CP_CORE_BUILDERS.PLAYER_HP({ CP = CP, _cpDB = { bars = b },
        UnitHealth = UnitHealth, UnitHealthMax = UnitHealthMax, UnitClass = UnitClass,
        RAID_CLASS_COLORS = RAID_CLASS_COLORS, CreateFrame = CreateFrame,
        GetPlayerFrame = function() return player end, ResolveTexture = function(key) return "texture:" .. (key or "default") end })
    local actor = { api = api, db = db, S = S, player = player, ns = ns, old = old }
    function actor:Apply()
        MSUF_DB, MSUF_NS = self.db, self.ns
        self.api.Refresh(self.player)
    end
    return actor
end
local function Scalar(value)
    if issecretvalue(value) then return "<secret>" end
    if type(value) == "table" then return value.frameName or value.objectType or "table" end
    return tostring(value)
end
local function Snapshot(a)
    local state, out = a.api.PHP, {}
    local function Add(value) out[#out + 1] = Scalar(value) end
    Add(state.visible)
    for _, key in ipairs({ "frame", "bar", "bg", "shapeEdge", "borderHost", "textFrame", "left", "center", "right" }) do
        local region = state[key]
        Add(key)
    Add(region ~= nil)
        if region then
            for _, field in ipairs({ "shown", "width", "height", "scale", "frameLevel", "orientation", "statusBarTexturePath",
                "texture", "minimum", "maximum", "value", "text", "fontPath", "fontSize", "fontFlags",
                "justifyH", "justifyV", "nativeFormat", "nativeArg", "alpha", "allPoints" }) do Add(region[field]) end
            Add(region.parent)
            for _, field in ipairs({ "color", "vertexColor", "texCoord", "textColor", "shadowColor" }) do
                local values = region[field] or {}
                for i = 1, 8 do Add(values[i]) end
            end
            for _, point in ipairs(region.points or {}) do
                Add(point.point)
    Add(point.relativeTo)
    Add(point.relativePoint)
    Add(point.x)
    Add(point.y)
            end
        end
    end
    for _, edge in ipairs(state.borderEdges or {}) do
        Add(edge.shown)
        for _, p in ipairs(edge.points or {}) do Add(p.point)
    Add(p.relativeTo)
    Add(p.relativePoint)
    Add(p.x)
    Add(p.y) end
    end
    return table.concat(out, "\030")
end
local count = 0
local function Same(old, new)
    old:Apply()
    local expected = Snapshot(old)
    new:Apply()
    local actual = Snapshot(new)
    assert(expected == actual, "actual PlayerHP visual/text/resource parity failed at case " .. count)
    count = count + 1
end
local modes = { "NONE", "CURRENT", "MAX", "DEFICIT", "PERCENT", "CURMAX", "MAXCUR", "CURPERCENT",
    "PERCENTCUR", "MAXPERCENT", "PERCENTMAX", "CURMAXPERCENT", "PERCENTCURMAX", "PERCENTMAXCUR", "UNKNOWN" }
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local old, new = Build(flavor, true), Build(flavor, false)
    for _, shape in ipairs({ "BAR", "ROUND", "CRYSTAL", "ORB", "FOLLOW_POWER", "invalid" }) do
        for _, anchor in ipairs({ "CLASS_TOP", "CLASS_BOTTOM", "POWER_TOP", "POWER_BOTTOM" }) do
            for _, width in ipairs({ "class", "player", "power", "custom" }) do
                for _, color in ipairs({ "GLOBAL", "CLASS", "DARK", "GRADIENT" }) do
                    for _, actor in ipairs({ old, new }) do
                        local b = actor.db.bars
                        b.playerHPBarShape, b.playerHPBarAnchor, b.playerHPBarWidthMode, b.playerHPBarColorMode = shape, anchor, width, color
                        b.playerHPBarWidth, b.playerHPBarHeight, b.playerHPBarGap = 181, 14, 3
                    end
                    Same(old, new)
                end
            end
        end
    end
    for _, shape in ipairs({ "BAR", "ORB", "ROUND", "FOLLOW_POWER" }) do
        for _, mode in ipairs(modes) do
            for _, separator in ipairs({ "", "-", "/", "\\", "|", "<", ">", "~", ":", " :: " }) do
                for variant = 0, 15 do
                    for _, actor in ipairs({ old, new }) do
                        local b, player = actor.db.bars, actor.db.player
                        b.playerHPBarShape, b.playerHPBarTextLeft, b.playerHPBarTextCenter, b.playerHPBarTextRight = shape, mode, mode, mode
                        b.playerHPBarUsePlayerText = variant % 2 == 1
                        b.playerHPBarTextReverse = math.floor(variant / 2) % 2 == 1
                        b.playerHPBarTextSeparator, b.playerHPBarTextEnabled = separator, true
                        b.playerHPBarTextLeftHidePercentSymbol = math.floor(variant / 4) % 2 == 1
                        b.playerHPBarTextCenterHidePercentSymbol, b.playerHPBarTextRightHidePercentSymbol = true, false
                        player.textLeft, player.textCenter, player.textRight = mode, mode, mode
                        player.hpTextSeparator, player.hpTextReverse = separator, b.playerHPBarTextReverse
                        player.powerBarDetached, player.detachedPowerBarShape = true, "ORB"
                        player.detachedPowerOrbSize = 77
                        actor.S.hp, actor.S.maximum = variant < 8 and 13579 or -4, variant < 8 and 999999 or 0
                    end
                    Same(old, new)
                end
            end
        end
    end
    for _, actor in ipairs({ old, new }) do
        actor.S.hp, actor.S.maximum = 250, 1000
        actor.db.bars.playerHPBarUsePlayerText = false
        actor.db.bars.playerHPBarTextLeft, actor.db.bars.playerHPBarTextCenter, actor.db.bars.playerHPBarTextRight = "NONE", "PERCENT", "CURMAX"
    end
    local numeric = { playerHPBarHeight = { -1, 2, 6, 80, 100 }, playerHPBarWidth = { -1, 20, 180, 1200, 2000 },
        playerHPBarGap = { -1, 0, 2, 60, 100 }, playerHPBarOffsetX = { -2000, -1000, 0, 1000, 2000 },
        playerHPBarOffsetY = { -2000, -1000, 0, 1000, 2000 }, playerHPBarFrameLevelOffset = { -1, 0, 7, 30, 50 },
        playerHPBarOrbSize = { -1, 20, 54, 160, 200 }, playerHPBarBgAlpha = { -1, 0, 0.35, 1, 35, 100 },
        playerHPBarOutline = { -1, 0, 1, 8, 10 }, playerHPBarTextSize = { -1, 6, 14, 48, 100 },
        playerHPBarTextOffsetX = { -400, -300, 0, 300, 400 }, playerHPBarTextOffsetY = { -400, -300, 0, 300, 400 } }
    for _, shape in ipairs({ "BAR", "ROUND", "CRYSTAL", "ORB", "FOLLOW_POWER" }) do
        for key, values in pairs(numeric) do
            for _, value in ipairs(values) do
                for _, actor in ipairs({ old, new }) do
                    actor.db.bars.playerHPBarShape, actor.db.bars.playerHPBarWidthMode = shape, "custom"
                    actor.db.bars[key] = value
                end
                Same(old, new)
            end
        end
        for variant = 0, 31 do
            for _, actor in ipairs({ old, new }) do
                local b = actor.db.bars
                b.playerHPBarIndependentVisibility = variant % 2 == 1
                b.playerHPBarHideOOC = math.floor(variant / 2) % 2 == 1
                b.playerHPBarHideWhenFull = math.floor(variant / 4) % 2 == 1
                b.playerHPBarHideWhenEmpty = math.floor(variant / 8) % 2 == 1
                b.playerHPBarSmoothFill = math.floor(variant / 16) % 2 == 1
                b.playerHPBarTexture, b.playerHPBarBgTexture = "foreground", variant % 2 == 1 and "background" or ""
            end
            Same(old, new)
        end
    end
    for _, actor in ipairs({ old, new }) do
        actor.db.bars.playerHPBarHideOOC, actor.db.bars.playerHPBarHideWhenFull, actor.db.bars.playerHPBarHideWhenEmpty = false, false, false
        actor.S.hp, actor.S.maximum, actor.S.percent = Secrets.New("number"), Secrets.New("number"), Secrets.New("number")
    end
    local paths = { root .. "/tools/fixtures/player_health/CP_PlayerHP.baseline.lua",
        root .. "/MidnightSimpleUnitFrames/ClassPower/MSUF_CP_PlayerHP.lua",
        root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_PlayerHP.lua" }
    local stop = Secrets.Watch(paths, { strict = true })
    for _, mode in ipairs(modes) do
        for _, shape in ipairs({ "BAR", "ORB", "ROUND", "CRYSTAL", "FOLLOW_POWER" }) do
            for _, actor in ipairs({ old, new }) do
                actor.db.bars.playerHPBarShape = shape
                actor.db.bars.playerHPBarTextLeft, actor.db.bars.playerHPBarTextCenter, actor.db.bars.playerHPBarTextRight = mode, mode, mode
            end
            Same(old, new)
        end
    end
    assert(#stop() == 0, "strict Watch found a secret operation in the actual parity grid")
end
print("player_health_element_parity_smoke: OK (" .. count .. " actual old/new cases, five clients, strict secrets)")
