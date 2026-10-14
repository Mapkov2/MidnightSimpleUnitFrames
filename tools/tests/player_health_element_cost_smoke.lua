-- Compare actual registered dispatchers. Allocation samples retain the minimum.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local measure = arg[2] == "measure"
local World = dofile(root .. "/tools/tests/classpower_world.lua")
local Secrets = dofile(root .. "/tools/tests/classpower_secrets.lua")
-- Exact 9c29a35a dispatcher measurements with this same fixture and two
-- allocation samples. All five client families produce these four vectors.
local limits = { unchanged = { 228.54, 3, 0 }, changing = { 744.54, 5, 0.103 },
    maximum = { 733.54, 4, 0.059 }, secret = { 562.54, 7, 0 } }
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    for _, kind in ipairs({ "unchanged", "changing", "maximum", "secret" }) do
        local native, value = 0, 500
        local t = World.Start(root, flavor == "Forever" and "Mainline" or flavor, "WARRIOR", 1, World.PT.RAGE, {
            showClassPower = false, playerHPBarEnabled = true, playerHPBarUsePlayerText = false,
            playerHPBarIndependentVisibility = true, playerHPBarWidthMode = "custom", playerHPBarWidth = 180,
        }, { beforeLoad = function(_, S)
            MSUF_NS.Client.IsForever = flavor == "Forever"
            Secrets.Install()
            UnitAffectingCombat = function() return false end
            UnitHealth = function() native = native + 1
    return S.health end
            UnitHealthMax = function() native = native + 1
    return S.healthMax end
            UnitClass = function() native = native + 1
    return "WARRIOR", "WARRIOR" end
            UnitHealthPercent = function() native = native + 1
    return S.percent or 50 end
            CurveConstants = { ScaleTo100 = {} }
            MSUF_UF_NormalizePlayerHPShape = function(shape) return shape or "BAR" end
            MSUF_UF_ShapeOutlineAlpha = function() return 1 end
            -- The C formatter accepts secret arguments without Lua formatting.
            _.Methods.SetFormattedText = function(self, pattern, number)
                if issecretvalue(number) then self.text = number else self.text = string.format(pattern, number) end
            end
        end })
        local UF = MSUF_NS.UF
        local state = UF.PlayerHP and UF.PlayerHP.State or World.Upvalue(t.CP.DisableNow, "PHP")
        local owner = UF.PlayerHP and state.frame or t.eventFrame
        local handler = assert(owner:GetScript("OnEvent"))
        for _, name in ipairs({ "SetValue", "SetMinMaxValues", "SetText", "SetFormattedText", "SetStatusBarColor" }) do
            local original = t.env.Methods[name]
            t.env.Methods[name] = function(...) native = native + 1
    return original(...) end
        end
        if kind == "secret" then
            t.S.health, t.S.healthMax, t.S.percent = Secrets.New("number"), Secrets.New("number"), Secrets.New("number")
        end
        local event = kind == "maximum" and "UNIT_MAXHEALTH" or "UNIT_HEALTH"
        local function Operation()
            value = value == 500 and 501 or 500
            if kind == "changing" then t.S.health = value end
            if kind == "maximum" then t.S.healthMax = value + 500 end
            handler(owner, event, "player")
        end
        for _ = 1, 40 do Operation() end
        local ticks = 0
        native = 0
        debug.sethook(function() ticks = ticks + 1 end, "", 1)
        for _ = 1, 200 do Operation() end
        debug.sethook()
        local instructions, calls = ticks / 200, native / 200
        local bytes = math.huge
        for _ = 1, 2 do
            collectgarbage("collect")
            collectgarbage("stop")
            local before = collectgarbage("count")
            for _ = 1, 1000 do Operation() end
            local sample = (collectgarbage("count") - before) * 1024 / 1000
            collectgarbage("restart")
            bytes = math.min(bytes, sample)
        end
        local key = flavor .. " " .. kind
        print(string.format("%s %.17g VM %.17g natives %.17g bytes (2 samples/minimum)", key, instructions, calls, bytes))
        if not measure then
            local base = assert(limits[kind], "missing exact baseline: " .. key)
            assert(instructions <= base[1] and calls <= base[2] and bytes <= base[3], "resource cost exceeds baseline: " .. key)
        end
    end
end
