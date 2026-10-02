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
}

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
    return ns
end

return Collaborators
