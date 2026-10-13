-- boss_castbar_scale_and_range_alpha_use_pooled_bars_smoke.lua <repoRoot>
--
-- Boss castbars are the bars of the boss pool (MSUF_BossCastbarN, Castbars/
-- MSUF_CastbarPools.lua). The range alpha of a boss unit frame
-- (MSUF_UF_Elements_Alpha.lua) and the MSUF scale pass (Runtime/MSUF_UIScaleRuntime.lua)
-- reach those bars and nothing else. They used to look up the pre-pool names
-- (MSUF_boss1CastBar, MSUF_Boss1CastBar), which no code creates, and the scale pass
-- reached a pooled bar only through the MSUF_BossCastbars table, not by its frame name.
--
-- Plain Lua 5.1, repo root as arg 1.

local root = assert(arg and arg[1], "repository root argument missing"):gsub("\\", "/"):gsub("/$", "")
local CORE = root .. "/MidnightSimpleUnitFrames/"

local failures = 0
local function Check(ok, message)
    if not ok then
        failures = failures + 1
        print("FAIL " .. message)
    end
end

local function NewRegion(name)
    local region = { name = name, alpha = 1, scale = 1 }
    function region:SetAlpha(alpha) self.alpha = alpha end
    function region:GetAlpha() return self.alpha end
    function region:SetScale(scale) self.scale = scale end
    function region:GetScale() return self.scale end
    return region
end

---------------------------------------------------------------------------
-- 1. Range alpha of a boss unit frame
---------------------------------------------------------------------------
do
    local PoolNamespace = assert(loadfile(root .. "/tools/tests/castbar_pool_namespace.lua"))()
    local MSUF = PoolNamespace(root, 3)
    _G.InCombatLockdown = function() return false end
    _G.issecretvalue = function() return false end
    _G.CreateFrame = function() return NewRegion("anon") end

    local UF = { elements = {} }
    UF.Clamp01 = function(v, fallback)
        v = tonumber(v)
        if v == nil then return fallback end
        if v < 0 then return 0 elseif v > 1 then return 1 end
        return v
    end
    UF.RegisterElement = function(name, element) UF.elements[name] = element end
    MSUF.UF = UF
    MSUF.Secrets = { IsNil = function(v) return v == nil end, NotSecret = function() return true end }
    local function Load(rel) assert(loadfile(CORE .. rel))("MidnightSimpleUnitFrames", MSUF) end
    Load("Kernel/MSUF_Require.lua")
    Load("Kernel/MSUF_Util.lua")
    Load("UnitFrames/Engine/Elements/MSUF_UF_Visuals_Common.lua")
    Load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Alpha.lua")

    local function Frame(unit)
        local frame = NewRegion(unit)
        frame.MSUFUnitKey = unit
        frame.MSUFSpec = { range = { active = true, layerMode = "frame", alpha = 0.4 } }
        return frame
    end
    local boss1, boss2 = Frame("boss1"), Frame("boss2")
    UF.frames = { boss1 = boss1, boss2 = boss2 }
    for _, frame in ipairs({ boss1, boss2 }) do UF.CompileAlphaRuntime(frame, frame.MSUFSpec) end

    -- boss2's bar is built (pool table plus named frame); boss1's is not. The
    -- pre-pool names exist as decoys.
    local pooled = NewRegion("MSUF_BossCastbar2")
    pooled.unit = "boss2"
    _G.MSUF_BossCastbars = { [2] = pooled }
    _G.MSUF_BossCastbar2 = pooled
    local decoyLower, decoyUpper = NewRegion("MSUF_boss1CastBar"), NewRegion("MSUF_Boss1CastBar")
    _G.MSUF_boss1CastBar, _G.MSUF_Boss1CastBar = decoyLower, decoyUpper

    UF.ApplyRangeModifier(boss1, 0.4, true)
    UF.ApplyRangeModifier(boss2, 0.4, true)
    Check(math.abs(pooled.alpha - 0.4) < 1e-6, "the pooled boss2 castbar alpha is " .. pooled.alpha .. ", expected 0.40")
    Check(decoyLower.alpha == 1 and decoyUpper.alpha == 1,
        "range alpha reached a pre-pool boss castbar name (" .. decoyLower.alpha .. ", " .. decoyUpper.alpha .. ")")
    _G.MSUF_BossCastbars, _G.MSUF_BossCastbar2 = nil, nil
    _G.MSUF_boss1CastBar, _G.MSUF_Boss1CastBar = nil, nil
end

---------------------------------------------------------------------------
-- 2. The MSUF scale pass
---------------------------------------------------------------------------
do
    local MSUF = {
        ExportPublic = function(name, value) _G[name] = value return value end,
        Translate = function(text) return text end,
        UF = { frames = {} },
    }
    _G.MSUF_NS = MSUF
    _G.InCombatLockdown = function() return false end
    _G.C_Timer = { After = function() end }
    _G.CreateFrame = function()
        local frame = {}
        function frame:RegisterEvent() end
        function frame:UnregisterEvent() end
        function frame:UnregisterAllEvents() end
        function frame:SetScript() end
        return frame
    end
    _G.UIParent = NewRegion("UIParent")
    _G.MSUF_ShowConfigCombatLockMessage = function() end
    _G.MSUF_EnsureDB = function() _G.MSUF_DB = _G.MSUF_DB or { general = {} } end
    _G.MSUF_InstallGlobalScaleGate = function() end
    assert(loadfile(CORE .. "Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", MSUF)
    assert(loadfile(CORE .. "Runtime/MSUF_UIScaleRuntime.lua"))("MidnightSimpleUnitFrames", MSUF)

    -- A pooled boss bar known only by its frame name (the pool table is not
    -- published yet), a published pool bar, and the pre-pool decoy.
    local named = NewRegion("MSUF_BossCastbar3")
    local tabled = NewRegion("MSUF_BossCastbar1")
    local decoy = NewRegion("MSUF_boss2CastBar")
    _G.MSUF_BossCastbar3 = named
    _G.MSUF_BossCastbar1 = tabled
    _G.MSUF_BossCastbars = { tabled }
    _G.MSUF_boss2CastBar = decoy

    _G.MSUF_ApplyMsufScale(0.8)
    Check(math.abs(tabled.scale - 0.8) < 1e-6, "the published boss pool bar was not scaled: " .. tabled.scale)
    Check(math.abs(named.scale - 0.8) < 1e-6, "a pooled boss bar known by its frame name was not scaled: " .. named.scale)
    Check(decoy.scale == 1, "the scale pass reached a pre-pool boss castbar name: " .. decoy.scale)
end

if failures > 0 then error(("boss castbar scale and range alpha smoke: %d failure(s)"):format(failures)) end
print("boss_castbar_scale_and_range_alpha_use_pooled_bars_smoke: ok")
