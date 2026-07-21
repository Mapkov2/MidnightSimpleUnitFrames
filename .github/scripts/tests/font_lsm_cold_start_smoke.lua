local root = arg and arg[1] or "."

local function Equal(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local preseedPath = "Interface\\AddOns\\Platynator\\Assets\\Fonts\\Poppins-SemiBold.ttf"
local latePath = "Interface\\AddOns\\SharedMedia_Test\\Fonts\\Late Font.ttf"
local rejectedPath = "Interface\\AddOns\\Missing_Test\\Fonts\\Missing.ttf"
local recoveredPath = "Interface\\AddOns\\SharedMedia_Test\\Fonts\\Recovered.ttf"
local fonts = { ["Poppins SemiBold"] = preseedPath }
local lsmCallback

local LSM = {}
function LSM:HashTable(mediaType)
    if mediaType == "font" then return fonts end
    return {}
end
function LSM:Fetch(mediaType, key)
    if mediaType == "font" then return fonts[key] end
end
function LSM:Register(mediaType, key, path)
    if mediaType == "font" then fonts[key] = path end
end
function LSM.RegisterCallback(_, event, callback)
    if event == "LibSharedMedia_Registered" then lsmCallback = callback end
end
function LSM.UnregisterCallback() end

local scheduled = {}
local timerCallbacks = {}
_G.MSUF = nil
_G.MSUF_NS = nil
_G.MSUF_LSM = nil
_G.MSUF_LSM_CallbacksRegistered = nil
_G.MSUF_LSM_FontCallbackRegistered = nil
_G.MSUF_BUNDLED_FONTS_REGISTERED = nil
_G.MSUF_IsKnownFileAsset = function() return false end
_G.MSUF_FontPathIsLoadable = function() return false end
_G.MSUF_DB = { general = {} }
_G.InCombatLockdown = function() return false end
_G.LibStub = function(name)
    if name == "LibSharedMedia-3.0" then return LSM end
end
_G.MSUF_ScheduleOnce = function(key, callback)
    scheduled[key] = scheduled[key] or callback
end
_G.C_Timer = {
    After = function(_, callback)
        timerCallbacks[#timerCallbacks + 1] = callback
    end,
}
_G.CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript() end
    function frame:Hide() end
    return frame
end

local MSUF = {
    ExportPublic = function(name, value)
        _G[name] = value
        return value
    end,
}
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Kernel/MSUF_Libs.lua"))(
    "MidnightSimpleUnitFrames", MSUF)

-- Existing registrations must be trusted before any registration callback fires.
Equal(_G.MSUF_IsRegisteredLSMFontPath(preseedPath), true, "preseeded raw LSM path")
Equal(_G.MSUF_ResolveFontPath(preseedPath, 12, "", preseedPath), preseedPath,
    "preseeded path survived a transient negative probe")

-- The 6.0 registry keeps its fast negative cache for arbitrary paths, but an
-- exact later LSM registration must promote that cached false without probing
-- every settled preview call again.
local probeCalls = 0
_G.CreateFont = function()
    return {
        SetFont = function()
            probeCalls = probeCalls + 1
            return false
        end,
    }
end
assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_FontRegistry.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
Equal(_G.MSUF_FontPathIsLoadable(preseedPath, 12, ""), true, "preseeded registry trust")
Equal(probeCalls, 0, "preseeded registry probe calls")
Equal(_G.MSUF_FontPathIsLoadable(recoveredPath, 12, ""), false, "unregistered negative probe")
Equal(_G.MSUF_FontPathIsLoadable(recoveredPath, 12, ""), false, "cached negative probe")
Equal(probeCalls, 1, "negative probe cache calls")
fonts["Recovered Display Name"] = recoveredPath
lsmCallback(nil, "font", "Recovered Display Name")
Equal(_G.MSUF_FontPathIsLoadable(recoveredPath, 12, ""), true, "late registration promotion")
Equal(probeCalls, 1, "late registration avoided another probe")

local appliedCalls = {}
local fontString = { path = "Fonts\\FRIZQT__.TTF", size = 12, flags = "" }
function fontString:SetFont(path, size, flags)
    appliedCalls[#appliedCalls + 1] = path
    self.path, self.size, self.flags = path, size, flags
    return true
end
function fontString:GetFont()
    return self.path, self.size, self.flags
end

local ok, applied, source = _G.MSUF_ApplyResolvedFont(fontString, preseedPath, 12, "", preseedPath)
Equal(ok, true, "preseeded apply result")
Equal(applied, preseedPath, "preseeded applied path")
Equal(source, "requested", "preseeded apply source")
Equal(appliedCalls[1], preseedPath, "preseeded SetFont path")

-- Arbitrary raw paths still fail closed and must never reach SetFont.
local rejectedCalls = 0
local rejected = {}
function rejected:SetFont()
    rejectedCalls = rejectedCalls + 1
    return true
end
function rejected:GetFont()
    return rejectedPath, 12, ""
end
ok = _G.MSUF_ApplyResolvedFont(rejected, rejectedPath, 12, "", rejectedPath)
Equal(ok, false, "unregistered path rejection")
Equal(rejectedCalls, 0, "unregistered path SetFont calls")

-- Profiles persist exact paths, while LSM reports a display key. A late
-- registration of that same path must refresh once despite slash/case variance.
assert(type(lsmCallback) == "function", "LSM registration callback was not installed")
_G.MSUF_DB.general.fontKey = latePath:upper():gsub("\\", "/")
fonts["Late Display Name"] = latePath
lsmCallback(nil, "font", "Late Display Name")
assert(type(scheduled.LSM_FONT_MEDIA_REFRESH) == "function",
    "late raw-path registration did not schedule a font refresh")

fonts["Late Alias"] = latePath
lsmCallback(nil, "font", "Late Alias")
local scheduledCount = 0
for _ in pairs(scheduled) do scheduledCount = scheduledCount + 1 end
Equal(scheduledCount, 1, "late path refresh coalescing")

local refreshCalls = 0
_G.MSUF_UpdateAllFonts = function() refreshCalls = refreshCalls + 1 end
scheduled.LSM_FONT_MEDIA_REFRESH()
Equal(refreshCalls, 1, "late path refresh dispatch")

print("font_lsm_cold_start_smoke: ok")
