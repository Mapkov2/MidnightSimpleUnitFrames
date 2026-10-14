-- classpower_collaborators.lua -- the cross-file providers ClassPower requires.
--
-- ClassPower resolves its collaborators through MSUF.Require when its files
-- load (Kernel/MSUF_Require.lua): every provider loads before it in each client
-- TOC, so a missing one is a load-order break and must fail loudly. A harness
-- that loads the ClassPower files without the real Kernel, Runtime, unit-frame
-- runtime and Castbars installs these stand-ins first. Each answers what the
-- real provider answers in a fresh session that has none of the optional
-- state: no profile-scoped layout cache, no effective cooldown frame, no cached
-- screen position, the client's default font. A global the harness defined
-- itself is kept.
--
--   local Collaborators = assert(loadfile(root .. "/tools/tests/classpower_collaborators.lua"))()
--   Collaborators.Install(root, ns)   -- before the first ClassPower file
--
-- Plain Lua 5.1.

local Collaborators = {}

local function NormalizedPath(path)
    return (tostring(path or ""):gsub("/", "\\"):lower())
end

Collaborators.STANDINS = {
    MSUF_GetProfileScopedCache = function() return nil end,
    MSUF_GetEffectiveCooldownFrame = function() return nil end,
    MSUF_ApplyCachedUnitFrameScreenPosition = function() return false end,
    MSUF_CacheUnitFrameScreenPosition = function() return false end,
    MSUF_ApplyPowerBarEmbedLayout = function() return false end,
    MSUF_ApplyPowerBarEmbedLayout_All = function() return false end,
    MSUF_FontPathEquals = function(a, b) return NormalizedPath(a) == NormalizedPath(b) end,
    MSUF_MarkFontApplyFailed = function() end,
    MSUF_GetGlobalFontSettings = function() return nil end,
    MSUF_GetFontPath = function() return nil end,
    MSUF_GetFontFlags = function() return nil end,
    MSUF_RegisterAnyEditModeListener = function() end,
    -- Kernel/MSUF_Util.lua outside the Mainline pixel-layout path: a policy
    -- string calls that method, anything else hands the region back.
    MSUF_PixelLayoutRegion = function(region, policy, ...)
        if type(policy) == "string" then return region[policy](region, ...) end
        return region
    end,
}

--- ClassPower/MSUF_CP_PlayerHP.lua reads the text change-key modes from
--- MSUF.UFText.DISPATCH_KEY at load. The table is compiled in the unit-frame
--- text formatter, which a harness without the unit-frame engine does not load:
--- read its literal from that file, so the stand-in cannot drift from it.
function Collaborators.DispatchKey(root)
    local path = root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Format.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local literal = source:gsub("\r\n", "\n"):match("\nlocal DISPATCH_KEY = (%b{})")
    assert(literal, path .. " no longer defines 'local DISPATCH_KEY = { ... }'")
    return assert(loadstring("return " .. literal))()
end

--- Gives ns the real MSUF.Require / MSUF.Optional and defines every stand-in
--- the harness did not define.
function Collaborators.Install(root, ns, lifecycle)
    -- Native health/affecting-combat functions exist on every supported client.
    -- Sparse CP-only fixtures previously left them absent while Extra Health
    -- was off. Model the same inert 0/1/false values as callable native APIs.
    if _G.UnitHealth == nil then _G.UnitHealth = function() return 0 end end
    if _G.UnitHealthMax == nil then _G.UnitHealthMax = function() return 1 end end
    if _G.UnitAffectingCombat == nil then _G.UnitAffectingCombat = function() return false end end
    if type(ns.Require) ~= "function" then
        ns.ExportPublic = ns.ExportPublic or function(name, value) _G[name] = value return value end
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", ns)
    end
    for name, standin in pairs(Collaborators.STANDINS) do
        if _G[name] == nil then _G[name] = standin end
    end
    -- Native power identity is available on every supported client.
    _G.Enum = _G.Enum or {}
    Enum.PowerType = Enum.PowerType or { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4 }
    -- PlayerHP now uses the real UF lifecycle and combat refusal. Retain
    -- explicit fixture injection, but never replace those owners with no-ops.
    if lifecycle ~= false and not (ns.UF and ns.UF.AttachFrame) then
        local injected = {}
        for name in pairs(Collaborators.STANDINS) do injected[name] = _G[name] end
        local roundLayout, refreshPower = _G.MSUF_SetRoundLayoutToNearestPixel, _G.MSUF_RefreshPlayerPowerBar
        local load = function(path)
            assert(loadfile(root .. "/MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
        end
        load("Shell/EditMode/MSUF_EditMode_Geometry.lua")
        load("Kernel/MSUF_Util.lua")
        for name, value in pairs(injected) do _G[name] = value end
        load("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")
        load("Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua")
        load("Kernel/MSUF_EventBus.lua")
        load("Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
        load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua")
        local shapes = {}
        for _, name in ipairs({ "MSUF_UF_NormalizeClassPowerShape", "MSUF_UF_NormalizePlayerHPShape", "MSUF_UF_ShapeOutlineAlpha" }) do
            shapes[name] = _G[name]
        end
        load("UnitFrames/Engine/MSUF_UF_Shared.lua")
        for name, value in pairs(shapes) do _G[name] = value end
        _G.MSUF_SetRoundLayoutToNearestPixel = roundLayout
        if refreshPower then _G.MSUF_RefreshPlayerPowerBar = refreshPower end
        local player = _G.MSUF_player
        if player then ns.UF.frames.player = player end
        -- This widget kit normally leaves Show/Hide scripts to its caller.
        -- Model the native edges of the newly attached resource host so the
        -- real engine can suspend and restore its event recipe.
        local createFrame = _G.CreateFrame
        _G.CreateFrame = function(kind, name, parent, ...)
            local frame = createFrame(kind, name, parent, ...)
            if name == "MSUF_ClassPowerPlayerHealthBar" then
                local show, hide = frame.Show, frame.Hide
                frame.Show = function(self)
                    local wasShown = self:IsShown()
                    show(self)
                    local script = self:GetScript("OnShow")
                    if not wasShown and script then script(self) end
                end
                frame.Hide = function(self)
                    local wasShown = self:IsShown()
                    hide(self)
                    local script = self:GetScript("OnHide")
                    if wasShown and script then script(self) end
                end
            end
            return frame
        end
    end
    -- Load the real Power element, which owns the ClassPower subscription in
    -- every client before the ClassPower stack. Stand-alone CP fixtures have
    -- no unit-frame registry or value updates to drive.
    if not ns.ClassPowerOwnership then
        ns.UF = ns.UF or {}
        ns.UF.RegisterElement = ns.UF.RegisterElement or function() end
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua"))(
            "MidnightSimpleUnitFrames", ns)
    end
    ns.UFText = ns.UFText or {}
    if ns.UFText.DISPATCH_KEY == nil then ns.UFText.DISPATCH_KEY = Collaborators.DispatchKey(root) end
    return ns
end

return Collaborators
