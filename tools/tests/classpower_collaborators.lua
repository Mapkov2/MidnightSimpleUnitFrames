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
    -- Integrations/MSUF_Integration_ThirdPartyAnchors.lua: a cooldown frame measures only while it is
    -- shown with a plain positive width; its width is rescaled into the target frame's scale. No frame
    -- (a fresh session without a provider) measures nothing.
    MSUF_GetUsableCooldownAnchorSize = function(frame)
        if not (frame and frame.GetWidth) then return nil end
        if frame.IsShown and frame:IsShown() ~= true then return nil end
        local width = frame:GetWidth()
        if type(width) ~= "number" or width <= 0 then return nil end
        return width, frame.GetHeight and frame:GetHeight() or nil
    end,
    MSUF_GetCooldownAnchorScaledWidth = function(frame, targetFrame, knownWidth)
        local width = knownWidth
        if width == nil then width = _G.MSUF_GetUsableCooldownAnchorSize(frame) end
        if type(width) ~= "number" or width <= 0 then return nil end
        local source = frame and frame.GetEffectiveScale and frame:GetEffectiveScale() or 1
        local target = targetFrame and targetFrame.GetEffectiveScale and targetFrame:GetEffectiveScale() or 1
        if type(source) ~= "number" or source <= 0 then source = 1 end
        if type(target) ~= "number" or target <= 0 then target = 1 end
        return width * source / target
    end,
    -- UnitFrames/Engine/MSUF_UF_Config.lua with no settings cache yet: the class colour comes from
    -- the client's table, else the default blue; an NPC colour is left to the element's own defaults.
    MSUF_UFCore_GetClassBarColorFast = function(classToken)
        local classColors = _G.RAID_CLASS_COLORS
        local color = classToken and classColors and classColors[classToken]
        if color then return color.r, color.g, color.b end
        return 0.12, 0.62, 0.95
    end,
    MSUF_UFCore_GetNPCReactionColorFast = function() return nil end,
    -- Runtime/MSUF_BarBackgroundRuntime.lua paints the health bar background; a harness that does not
    -- load it has no background to repaint.
    MSUF_RefreshHealthBarBackgroundColor = function() end,
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
    -- State/MSUF_Defaults.lua: a fresh session gets a profile; readers fill
    -- their own defaults, so the stand-in profile starts empty.
    MSUF_EnsureDB = function()
        if type(_G.MSUF_DB) ~= "table" then _G.MSUF_DB = {} end
        return _G.MSUF_DB
    end,
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

--- One top-level `local function NAME(...) ... end` read from a shipped file, for
--- a pure provider whose file a harness does not load (its owner needs a long
--- load chain): the stand-in is the shipped source, so it cannot drift from it.
function Collaborators.SourceFunction(root, relative, name)
    local path = root .. "/" .. relative
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local body = source:gsub("\r\n", "\n"):match("\n(local function " .. name .. "%(.-\nend)\n")
    assert(body, path .. " no longer defines 'local function " .. name .. "(...) ... end'")
    return assert(loadstring(body .. "\nreturn " .. name, "@" .. relative .. ":" .. name))()
end

--- One top-level `local NAME = { ... }` table literal read from a shipped file (a
--- constant table whose owner a harness does not load), for the same reason.
function Collaborators.SourceTable(root, relative, name)
    local path = root .. "/" .. relative
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()
    local literal = source:gsub("\r\n", "\n"):match("\nlocal " .. name .. " = (%b{})")
    assert(literal, path .. " no longer defines 'local " .. name .. " = { ... }'")
    return assert(loadstring("return " .. literal, "@" .. relative .. ":" .. name))()
end

--- Gives ns the real Kernel API (MSUF.Require / MSUF.Optional, ExportPublic and
--- its registry), the real font stack, media resolver and colours, and defines
--- every stand-in the harness did not define. Harnesses that compile unit-frame
--- specs without ClassPower call this alone.
function Collaborators.InstallProviders(root, ns)
    -- The real Kernel namespace API (Bootstrap's ExportPublic and registry,
    -- Require/Optional); a harness export stub without the registry is replaced.
    local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
    RequireFixture.InstallKernel(root, ns, nil, nil, true)
    -- ClassPower resolves and applies its fonts through the real font owners
    -- (Kernel/MSUF_Libs.lua, Runtime/MSUF_Fonts.lua, Runtime/MSUF_FontRegistry.lua).
    if not (ns.Fonts and ns.Fonts.ResolveKeyPath) then
        assert(loadfile(root .. "/tools/tests/runtime_media_fixture.lua"))().LoadFonts(root, ns)
    end
    if ns.Optional("MSUF_ResolveSafeFontPath") == nil then
        RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/Runtime/MSUF_FontRegistry.lua", ns)
    end
    for name, standin in pairs(Collaborators.STANDINS) do
        if _G[name] == nil then _G[name] = standin end
    end
    -- Runtime/MSUF_MediaRuntime.lua: the bar and castbar texture resolver.
    if not (ns.Media and ns.Media.GetBarTexture) then
        RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/Runtime/MSUF_MediaRuntime.lua", ns)
    end
    -- Runtime/MSUF_Colors.lua: the resource bar colours.
    if ns.Optional("MSUF_GetPowerBarColor") == nil then
        RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/Runtime/MSUF_Colors.lua", ns)
    end
    return ns
end

--- The providers the unit-frame config compiler (UnitFrames/Engine/MSUF_UF_Config.lua)
--- and its shared helpers require when they load or compile: InstallProviders, then
--- Geometry and Util (pixel regions, general DB), the bar background runtime, the
--- event bus, the scheduler and the unit-frame metadata, in TOC order. The two owners
--- that sit behind long load chains are modelled: State/MSUF_Defaults.lua publishes a
--- pure normalizer (its shipped source is the stand-in), and a profile without a
--- castbar backend choice uses the MSUF castbar (Castbars/MSUF_Castbars_Backend.lua).
function Collaborators.InstallConfigProviders(root, ns)
    local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
    Collaborators.InstallProviders(root, ns)
    local function load(path)
        RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/" .. path, ns)
    end
    load("Shell/EditMode/MSUF_EditMode_Geometry.lua")
    load("Kernel/MSUF_Util.lua")
    if ns.Optional("MSUF_NormalizePortraitClassStyleValue") == nil then
        ns.ExportPublic("MSUF_NormalizePortraitClassStyleValue", Collaborators.SourceFunction(root,
            "MidnightSimpleUnitFrames/State/MSUF_Defaults.lua", "MSUF_Defaults_NormalizePortraitClassStyleValue"))
    end
    if ns.Optional("MSUF_ShouldUseMSUFCastbar") == nil then
        ns.ExportPublic("MSUF_ShouldUseMSUFCastbar", function() return true end)
    end
    load("Runtime/MSUF_BarBackgroundRuntime.lua")
    load("Kernel/MSUF_EventBus.lua")
    -- The scheduler binds C_Timer.After at load; the client always has it.
    local clientTimer = _G.C_Timer
    _G.C_Timer = clientTimer or { After = function(_, callback) callback() end }
    load("Kernel/MSUF_Scheduler.lua")
    _G.C_Timer = clientTimer
    load("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")
    return ns
end

--- Gives ns the real Kernel API (InstallProviders) and defines every ClassPower
--- collaborator the harness did not define.
function Collaborators.Install(root, ns, lifecycle)
    -- Native health/affecting-combat functions exist on every supported client.
    -- Sparse CP-only fixtures previously left them absent while Extra Health
    -- was off. Model the same inert 0/1/false values as callable native APIs.
    if _G.UnitHealth == nil then _G.UnitHealth = function() return 0 end end
    if _G.UnitHealthMax == nil then _G.UnitHealthMax = function() return 1 end end
    if _G.UnitAffectingCombat == nil then _G.UnitAffectingCombat = function() return false end end
    local RequireFixture = assert(loadfile(root .. "/tools/tests/require_fixture.lua"))()
    Collaborators.InstallProviders(root, ns)
    -- Native power identity is available on every supported client.
    _G.Enum = _G.Enum or {}
    Enum.PowerType = Enum.PowerType or { Mana = 0, Rage = 1, Focus = 2, Energy = 3, ComboPoints = 4 }
    -- PlayerHP now uses the real UF lifecycle and combat refusal. Retain
    -- explicit fixture injection, but never replace those owners with no-ops.
    if lifecycle ~= false and not (ns.UF and ns.UF.AttachFrame) then
        local injected = {}
        for name in pairs(Collaborators.STANDINS) do injected[name] = _G[name] end
        local roundLayout, refreshPower = _G.MSUF_SetRoundLayoutToNearestPixel, _G.MSUF_RefreshPlayerPowerBar
        -- Providers these owners require and this harness does not load are
        -- deferred: using one raises (require_fixture.lua DeferRequired).
        local load = function(path)
            RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/" .. path, ns)
        end
        load("Shell/EditMode/MSUF_EditMode_Geometry.lua")
        load("Kernel/MSUF_Util.lua")
        for name, value in pairs(injected) do _G[name] = value end
        load("Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua")
        load("Libs/MSUFUnitFrames/MSUF_UF_Secrets.lua")
        load("Kernel/MSUF_EventBus.lua")
        -- C_Timer exists on every supported client and the real scheduler needs
        -- it; a harness without one runs callbacks at once (the stub default).
        if _G.C_Timer == nil then _G.C_Timer = { After = function(_, callback) callback() end } end
        load("Kernel/MSUF_Scheduler.lua")
        load("Libs/MSUFUnitFrames/MSUF_UF_Core.lua")
        load("UnitFrames/Engine/Elements/MSUF_UF_Elements_Bridges.lua")
        local shapes = {}
        for _, name in ipairs({ "MSUF_UF_NormalizeClassPowerShape", "MSUF_UF_NormalizePlayerHPShape", "MSUF_UF_ShapeOutlineAlpha" }) do
            shapes[name] = _G[name]
        end
        load("UnitFrames/Engine/MSUF_UF_Shared.lua")
        for name, value in pairs(shapes) do _G[name] = value end
        -- A harness-defined rounding provider is kept; otherwise Util's real one stays.
        if roundLayout ~= nil then _G.MSUF_SetRoundLayoutToNearestPixel = roundLayout end
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
        RequireFixture.LoadShipped(root, "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Power.lua", ns)
    end
    ns.UFText = ns.UFText or {}
    if ns.UFText.DISPATCH_KEY == nil then ns.UFText.DISPATCH_KEY = Collaborators.DispatchKey(root) end
    -- Auras3 is a separate module no ClassPower harness loads. Its public table without the native
    -- sensor factory is the state in which the native aura slots stay pending until Auras3 is ready;
    -- a smoke that exercises the sensors publishes its own table (a global or ExportPublic) first.
    if ns.Optional("MSUF_Auras3") == nil then ns.ExportPublic("MSUF_Auras3", {}) end
    -- The ClassPower files a smoke loads next require further providers at load;
    -- those this harness does not load are deferred and raise when used.
    RequireFixture.DeferRequiredIn(root, ns, "/ClassPower/")
    return ns
end

return Collaborators
