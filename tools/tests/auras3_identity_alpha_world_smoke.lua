-- Auras 3 identity alpha cache against the real Core: a 20 player raid on the emulated secure header takes roster,
-- world, faction and flag events, config re-applies, combat edges and member polarity flips (hide, refresh,
-- reveal). The alpha of every native aura container must match, step by step, the run whose gate sink writes every
-- result, and the cache must save most of the native writes. The oracle is the same source with the repeat check
-- removed, so the two runs differ in nothing else. Real geometry syncs (ButtonVisuals) are part of both runs.
-- Usage: lua tools/tests/auras3_identity_alpha_world_smoke.lua <repoRoot>
local root = assert(arg[1], "repo root required"):gsub("\\", "/"):gsub("/$", "")
local Harness = dofile(root .. "/tools/tests/group_header_world.lua")
local REPEAT_CHECK = "if region._msufA3GateAlpha == alpha then return true end"

local function OracleSource()
    local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Identity.lua", "rb"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    local first, last = source:find(REPEAT_CHECK, 1, true)
    assert(first, "the gate sink no longer has its repeat check, update this smoke")
    return source:sub(1, first - 1) .. source:sub(last + 1)
end

local function Run(oracle)
    local writes, flip, trail = 0, {}, {}
    local oraclePath
    local h = Harness.New(root, "Mainline", { beforeBoot = function(h)
        local loadGraph = h.world.LoadGraph
        function h.world:LoadGraph(addon, ...)
            if addon ~= "MidnightSimpleUnitFrames_Options" then return loadGraph(self, addon, ...) end
        end
        h.env.C_AddOns.IsAddOnLoaded = function() return true end
        h.env.UnitCanAssist = function(_, unit) return not flip[unit] end
        local M = h.widgets.Methods
        local function Noop() end
        for _, name in ipairs({ "SetAuraGroupFilterString", "SetAuraGroupLayout", "SetAuraGroupMaxFrameCount",
            "SetAuraGroupCandidateFilters", "SetAuraGroupSortMethod", "AddAuraGroup", "AddAuraSlot",
            "SetAuraSlotFilterString", "SetAuraSlotCandidateFilters", "SetAuraSlotSortMethod", "AddItemEnchantment",
            "SetFlowLayoutAnchorPoint", "SetFlowLayoutGrowthDirection", "SetFlowLayoutMaximumLineSize" }) do M[name] = Noop end
        function M:SetEnabled(enabled) self.nativeEnabled = enabled end
        function M:GetUnit() return self.nativeUnit end
        function M:SetUnit(unit) self.nativeUnit = unit end
        local setAlpha = M.SetAlpha
        function M:SetAlpha(alpha)
            if self._msufA3NativeLaneConfig ~= nil then writes = writes + 1 end
            return setAlpha(self, alpha)
        end
        if oracle then
            oraclePath = os.tmpname()
            local file = assert(io.open(oraclePath, "wb"))
            file:write(OracleSource())
            file:close()
            local loadFile = h.world.LoadFile
            function h.world:LoadFile(path, addon, namespace)
                if path:gsub("\\", "/"):find("MSUF_Auras3_Runtime_Identity.lua", 1, true) then path = oraclePath end
                return loadFile(self, path, addon, namespace)
            end
        end
    end })
    if oraclePath then os.remove(oraclePath) end

    -- The next-frame scheduler carries every reveal; unrelated queued features may trip over the offline stubs.
    local function Pump()
        for _ = 1, 3 do
            for _, frame in ipairs(h.widgets.frames) do
                local onUpdate = frame.scripts and frame.scripts.OnUpdate
                local info = onUpdate and debug.getinfo(onUpdate, "S")
                if info and info.source:find("MSUF_Scheduler.lua", 1, true) then pcall(onUpdate, frame, 0.02) end
            end
        end
    end
    local function Drain() h:RunTimers(); Pump(); h:RunTimers() end
    local function Snap(label)
        local parts = {}
        for index, frame in ipairs(h.widgets.frames) do
            if frame._msufA3NativeLaneConfig ~= nil then parts[#parts + 1] = index .. "=" .. tostring(frame.alpha) end
        end
        trail[#trail + 1] = label .. " " .. table.concat(parts, ",")
    end
    local function Reapply(conf)
        h.GF.InvalidateCompiledSpecs("raid")
        h.GF.RefreshHeaderLayout()
        Drain()
    end
    local function Burst()
        for _, event in ipairs({ "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "UNIT_FACTION",
            "UNIT_FLAGS", "ENTERED_DIFFERENT_INSTANCE_FROM_PARTY", "PARTY_MEMBER_DISABLE", "PARTY_MEMBER_ENABLE" }) do
            h:Event(event, event:find("UNIT_", 1, true) and "player" or nil)
            Snap(event .. "+event")
            Drain()
            Snap(event .. "+timers")
        end
    end
    local function Edge(units, hostile)
        for _, unit in ipairs(units) do flip[unit] = hostile or nil end
        for _, unit in ipairs(units) do h:Event("UNIT_FLAGS", unit) end
        Snap("edge+event")
        Drain()
        Snap("edge+timers")
    end

    local conf = h.GF.GetConf("raid")
    conf.enabled = true
    conf.auras = { enabled = true }
    Reapply(conf)
    h:SetRaid(20)
    h:Event("GROUP_ROSTER_UPDATE")
    Drain()
    Snap("raid")
    for _ = 1, 3 do
        Burst()
        Edge({ "raid3", "raid7" }, true)
        Edge({ "raid3" }, false)
        Edge({ "raid7", "raid11", "raid15" }, true)
        h:Event("UNIT_FACTION", "player")
        Drain()
        Snap("faction")
        Edge({ "raid7", "raid11", "raid15" }, false)
        h:EnterCombat()
        Edge({ "raid2" }, true)
        h:LeaveCombat()
        Drain()
        Snap("regen")
        Edge({ "raid2" }, false)
        Reapply(conf)
        Snap("reapply")
        conf.enabled = false
        Reapply(conf)
        Snap("disable")
        conf.enabled = true
        Reapply(conf)
        Snap("enable")
        h:SetRaid(8)
        h:Event("GROUP_ROSTER_UPDATE")
        Drain()
        Snap("shrink")
        h:SetRaid(20)
        h:Event("GROUP_ROSTER_UPDATE")
        Drain()
        Snap("regrow")
    end
    return trail, writes
end

local cachedTrail, cachedWrites = Run(false)
local oracleTrail, oracleWrites = Run(true)

assert(#cachedTrail == #oracleTrail and #cachedTrail > 50, "the scenario must run to the end in both worlds")
local states = {}
for step = 1, #cachedTrail do
    assert(cachedTrail[step] == oracleTrail[step],
        ("container alpha diverged at step %d:\n  cached %s\n  oracle %s"):format(step, cachedTrail[step], oracleTrail[step]))
    states[cachedTrail[step]:match("%S+$")] = true
end
local distinct = 0
for _ in pairs(states) do distinct = distinct + 1 end
assert(distinct >= 3, "the scenario never hid or revealed an owner: " .. distinct .. " alpha states")
assert(cachedWrites * 2 < oracleWrites,
    ("the cache saved too little: %d native alpha writes against %d when every result is written"):format(cachedWrites, oracleWrites))
print(("auras3_identity_alpha_world_smoke: OK (%d steps, %d alpha states, %d writes against %d)"):format(
    #cachedTrail, distinct, cachedWrites, oracleWrites))
