-- Native module loading: no service injection may manufacture missing exports.
local ns = {}
local function load(path)
    assert(loadfile("MidnightSimpleUnitFrames/" .. path))("MidnightSimpleUnitFrames", ns)
end
local Stubs = assert(loadfile(".github/scripts/msuf_test_stubs.lua"))()
local env = Stubs.New({ timer = "queue", registerGlobalNames = true })
env:InstallGlobals()
load("Kernel/MSUF_Bootstrap.lua")

local missing = "Interface\\AddOns\\MapkoSkin\\Media\\Fonts\\Expressway ExtraBold.ttf"
local fallback = "Fonts\\FRIZQT___CYR.TTF"
local media, mediaCallback = { font = {}, statusbar = {}, background = {}, msuf_statusicon = {} }
local lsm = {}
function lsm:HashTable(kind) return media[kind] end
function lsm:Fetch(kind, key) return media[kind][key] end
function lsm.RegisterCallback(_, _, fn) mediaCallback = fn end
function lsm.UnregisterCallback() end
_G.LibStub = function(name) if name == "LibSharedMedia-3.0" then return lsm end end
_G.MSUF_BUNDLED_FONTS_REGISTERED = true
local fontMode, attempts = "false", 0
_G.CreateFont = function()
    return {
        SetFont = function(self, path, size, flags)
            if path == missing then
                attempts = attempts + 1
                if fontMode == "false" then return false end
                if fontMode == "throw" then error("invalid external font asset") end
            end
            self.path, self.size, self.flags = path, size, flags
            return true
        end,
        GetFont = function(self) return self.path, self.size, self.flags end,
    }
end
load("Kernel/MSUF_Libs.lua")
load("Runtime/MSUF_FontRegistry.lua")
_G.MSUF_DB = { general = { fontKey = missing } }
for _, mode in ipairs({ "false", "throw" }) do
    fontMode, attempts = mode, 0
    MSUF_InvalidateFontPathCache()
    for i = 1, 4 do
        assert(MSUF_ResolveFontPath(missing, 14, "", missing) == fallback)
        assert(MSUF_GetFontPathForKey(missing) == fallback)
    end
    assert(attempts == 1, "missing asset must be negatively cached")
    assert(MSUF_DB.general.fontKey == missing, "keep the saved font selection")
    local fs = CreateFont()
    assert(MSUF_ApplyResolvedFont(fs, missing, 22, "OUTLINE,SLUG", missing))
    assert(fs.path == fallback)
    assert(MSUF_GetFontPreviewObject(missing).path == fallback)
end
-- LSM may advertise a font whose file was removed. Metadata must not bypass
-- the asset probe or convert a cached rejection into a successful load.
media.font.Mapko = missing
mediaCallback(nil, "font", "Mapko")
assert(MSUF_IsRegisteredLSMFontPath(missing))
fontMode, attempts = "false", 0
for i = 1, 4 do assert(MSUF_ResolveFontPath(missing, 14, "", missing) == fallback) end
assert(attempts == 1, "registered missing font must also retain its negative cache")
-- An actual font becoming available can be reprobed after a media event.
fontMode = "available"
mediaCallback(nil, "font", "Mapko")
assert(MSUF_ResolveFontPath(missing, 14, "", missing) == missing)
local fs = CreateFont()
assert(MSUF_ApplyResolvedFont(fs, missing, 14, "", missing))
assert(fs.path == missing)
local rejected = CreateFont()
local nativeSet = rejected.SetFont
function rejected:SetFont(path, size, flags)
    if path == missing then return false end
    return nativeSet(self, path, size, flags)
end
local applied, appliedPath = MSUF_ApplyResolvedFont(rejected, missing, 14, "", missing)
assert(applied and appliedPath == fallback and rejected.path == fallback)
local cached, cachedPath = MSUF_ApplyResolvedFont(rejected, missing, 14, "", missing)
assert(cached and cachedPath == fallback, "cached result must report the actual fallback")
assert(MSUF_ApplyResolvedFont({ SetFont = function() return false end }, missing, 14, "", missing) == false)
local marker = "real application failure"
local ok, err = pcall(MSUF_SetFontChecked, { SetFont = function() error(marker) end }, missing, 14, "")
assert(not ok and tostring(err):find(marker, 1, true), "real application exceptions must remain visible")
assert(MSUF_SetFontChecked({ SetFont = function() return false end }, missing, 14, "") == false)

-- Exercise the real compact decoder with strict native codec contracts.
local file = assert(io.open("MidnightSimpleUnitFrames/State/MSUF_Defaults.lua", "rb"))
local source = file:read("*a"); file:close()
local decoderSource = assert(source:match("(local function MSUF_Defaults_TryDecodeCompactString.-)local function MSUF_Defaults_WipeInPlace"))
local decode = assert(loadstring(decoderSource .. "\nreturn MSUF_Defaults_TryDecodeCompactString"))()
local payload = { general = { fontKey = missing }, player = { enabled = true } }
local codecMode, calls = "compressed", {}
_G.Enum = { CompressionMethod = { Deflate = 0 } }
_G.C_EncodingUtil = {
    DecodeBase64 = function()
        calls[#calls + 1] = "base64"
        if codecMode == "badBase64" then error("invalid base64") end
        return codecMode == "raw" and "CBOR" or "DEFLATE"
    end,
    DecompressString = function(blob)
        calls[#calls + 1] = "deflate"
        if codecMode == "raw" or codecMode == "badDeflate" then error("invalid deflate") end
        assert(blob == "DEFLATE")
        return "CBOR"
    end,
    DeserializeCBOR = function(blob)
        calls[#calls + 1] = "cbor"
        if blob ~= "CBOR" or codecMode == "badCBOR" then error("unknown cbor value") end
        return payload
    end,
}
for _, mode in ipairs({ "compressed", "raw", "badBase64", "badDeflate", "badCBOR" }) do
    codecMode, calls = mode, {}
    local result = decode("MSUF3:YQ==")
    if mode == "compressed" or mode == "raw" then assert(result == payload) else assert(result == nil) end
    if mode == "compressed" then assert(table.concat(calls, ",") == "base64,deflate,cbor") end
end
codecMode = "compressed"
assert(decode("MSUF1:YQ==") == nil)
assert(decode("MSUF3:a") == nil)

-- Reproduce the reported file-load chain: Anchors -> EnsureDB -> factory
-- decoder, then verify Visuals receives its helper from the provider.
_G.UnitClass = function() return "Warrior", "WARRIOR", 1 end
_G.UnitName = function() return "Tester" end
_G.GetRealmName = function() return "Realm" end
_G.MSUF_DB = nil
load("State/MSUF_StateHelpers.lua")
load("State/MSUF_Defaults.lua")
load("Castbars/MSUF_CastbarAnchors.lua")
assert(type(MSUF_CastbarFrameInset) == "function", "factory bootstrap must not abort anchor exports")
assert(MSUF_CastbarFrameInset({}, { castbarOutlineThickness = 1 }) == 1)
assert(MSUF_CastbarFrameInset({}, { castbarOutlineThickness = 0 }) == 0)
load("Castbars/MSUF_CastbarVisuals.lua")
assert(ns.Castbars.Visuals)

-- The optional addon is absent, but MSUF's profile settings API must exist.
_G.MSUF_EM2 = {}
_G.MSUF_GetGeneralDB = function() return MSUF_DB.general end
_G.EllesmereUI = nil
load("Shell/EditMode/MSUF_EditMode_ExternalProvider.lua")
load("Integrations/MSUF_Integration_EllesmereUnlock.lua")
assert(type(MSUF_EllesmereEditMode_SetEnabled) == "function")
assert(MSUF_EllesmereEditMode_IsAvailable() == false)
assert(MSUF_EllesmereEditMode_SetEnabled(false) == false)
assert(MSUF_DB.general.ellesmereEditModeIntegration == false)
assert(MSUF_EllesmereEditMode_SetEnabled(true) == false)
assert(MSUF_DB.general.ellesmereEditModeIntegration == true)
assert(MSUF_TryOpenExternalEditMode("player") == false)
print("PASS startup rejection: unavailable fonts, codec failures, anchor exports, optional Ellesmere")
