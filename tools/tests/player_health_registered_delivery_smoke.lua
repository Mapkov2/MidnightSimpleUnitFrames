-- Count every registered owner's real callback, with matched source providers.
local root = assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local fixture = (arg[2] or root):gsub("\\", "/"):gsub("/$", "")
local World = dofile(fixture .. "/tools/tests/classpower_world.lua")
local function Empty() end
local function Count(fn, frame, event)
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, "", 1)
    for _ = 1, 200 do fn(frame, event, "player") end
    debug.sethook()
    return ticks / 200
end
local function Owners(t, event)
    local owners = {}
    for _, frame in ipairs(t.env.frames) do
        if frame:IsEventRegistered(event) and frame:GetScript("OnEvent") then
            owners[#owners + 1] = frame
        end
    end
    return owners
end
local function Start(flavor)
    return World.Start(root, flavor == "Forever" and "Mainline" or flavor, "WARRIOR", 1, World.PT.RAGE, {
        showClassPower = true, playerHPBarEnabled = true, playerHPBarIndependentVisibility = true,
        playerHPBarUsePlayerText = false, playerHPBarWidthMode = "custom", playerHPBarWidth = 180,
    }, { beforeLoad = function()
        MSUF_NS.Client.IsForever = flavor == "Forever"
        dofile(fixture .. "/tools/tests/classpower_collaborators.lua").Install(root, MSUF_NS)
        MSUF_UF_NormalizePlayerHPShape = function(shape) return shape or "BAR" end
        MSUF_UF_ShapeOutlineAlpha = function() return 1 end
        UnitHealthPercent = function() return 50 end
        CurveConstants = { ScaleTo100 = {} }
    end })
end
for _, flavor in ipairs({ "Mainline", "Forever", "Vanilla", "TBC", "Mists" }) do
    local t = Start(flavor)
    MSUF_DB.general.perfLiteClassPowerEvents = false
    t.CP.RefreshPublic()
    local total, bytes = 0, math.huge
    local owners = Owners(t, "UNIT_HEALTH")
    assert(#owners > 0, "no registered delivery")
    for _, frame in ipairs(owners) do
        local fn = frame:GetScript("OnEvent")
        for _ = 1, 40 do fn(frame, "UNIT_HEALTH", "player") end
        total = total + Count(fn, frame, "UNIT_HEALTH") - Count(Empty, frame, "UNIT_HEALTH")
    end
    for _ = 1, 2 do
        collectgarbage("collect")
        collectgarbage("stop")
        local before = collectgarbage("count")
        for _ = 1, 1000 do
            for _, frame in ipairs(owners) do frame:GetScript("OnEvent")(frame, "UNIT_HEALTH", "player") end
        end
        bytes = math.min(bytes, (collectgarbage("count") - before) * 1024 / 1000)
        collectgarbage("restart")
    end
    print(flavor, "all-owner unchanged non-lite UNIT_HEALTH", total, "VM", bytes, "bytes (2 samples/minimum)")
    -- Exact untouched 9c29a35a bound; the frozen pre-correction source costs 193.
    assert(total <= 187 and bytes == 0, "complete registered delivery exceeds untouched baseline")
end
print("player_health_registered_delivery_smoke: OK")
