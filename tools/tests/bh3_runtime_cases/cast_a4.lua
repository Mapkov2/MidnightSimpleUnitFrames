-- probe_a4_bg_texture_cache.lua <repoRoot>
-- Castbar background texture: a key resolved before LibSharedMedia knows it is
-- cached as the fallback forever; the LSM refresh clears only the foreground caches.
local root = arg[1]
local registered = {}
local LSM = {}
function LSM:Fetch(kind, key, noDefault)
    if kind == "statusbar" then return registered[key] end
    return nil
end
local ns = { LSM = LSM }
function ns.ExportPublic(name, value) _G[name] = value; return value end
function ns.Require(name) local v = _G[name]; assert(v ~= nil, "missing " .. name); return v end
_G.MSUF_EnsureDB = function() end
_G.MSUF_NormalizeFontPath = function(p) return p end
_G.MSUF_GetInternalFontPathByKey = function() return nil end
_G.MSUF_UpdateCastbarEditInfo = function() end
_G.MSUF_SyncCastbarPositionPopup = function() end
_G.MSUF_IsPlayerInCombat = function() return false end
_G.MSUF_DB = { general = { castbarTexture = "Late Media Bar", castbarBackgroundTexture = "Late Media Bar" } }
-- Load the real shared predicates without replacing this fixture's visual providers.
local utilityNS = { ExportPublic = function(_, value) return value end }
local previousMSUF = _G.MSUF
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Util.lua"))("MidnightSimpleUnitFrames", utilityNS)
_G.MSUF = previousMSUF
ns.Util = utilityNS.Util
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Castbars/MSUF_Castbars_Core.lua"))("MidnightSimpleUnitFrames", ns)

print("login (key not registered yet): fg=" .. _G.MSUF_GetCastbarTexture() .. "  bg=" .. _G.MSUF_GetCastbarBackgroundTexture())
-- The media addon registers the texture; MSUF's LibSharedMedia_Registered handler
-- (Kernel/MSUF_Libs.lua RunStatusbarMediaRefresh) clears the caches and re-applies.
registered["Late Media Bar"] = "Interface\\AddOns\\LateMedia\\bar.tga"
_G.MSUF_ClearResolvedStatusbarTextureCache()
print("after LSM register + cache clear: fg=" .. _G.MSUF_GetCastbarTexture() .. "  bg=" .. _G.MSUF_GetCastbarBackgroundTexture())
print("expected bg = Interface\\AddOns\\LateMedia\\bar.tga")

assert(_G.MSUF_GetCastbarBackgroundTexture() == registered["Late Media Bar"], "background cached unresolved LSM fallback")
