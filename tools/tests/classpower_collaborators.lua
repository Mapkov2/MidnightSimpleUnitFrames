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
function Collaborators.Install(root, ns)
    if type(ns.Require) ~= "function" then
        ns.ExportPublic = ns.ExportPublic or function(name, value) _G[name] = value return value end
        assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Require.lua"))("MidnightSimpleUnitFrames", ns)
    end
    for name, standin in pairs(Collaborators.STANDINS) do
        if _G[name] == nil then _G[name] = standin end
    end
    ns.UFText = ns.UFText or {}
    if ns.UFText.DISPATCH_KEY == nil then ns.UFText.DISPATCH_KEY = Collaborators.DispatchKey(root) end
    return ns
end

return Collaborators
