-- Regression for external fonts that publish path/size before glyph metrics
-- settle. The first apply is provisional; one delayed epoch must force a real
-- second SetFont, while unresolved retries stay probe-only and bounded.
_G = _G or _ENV

local runtimePath = "MidnightSimpleUnitFrames/Core/MSUF_FontRuntime.lua"
local activePath = "Interface\\AddOns\\Platynator\\Assets\\Fonts\\Poppins-SemiBold.ttf"
local timers, pendingTimerKeys = {}, {}
local framePasses, followerPasses, relayouts = 0, 0, 0

local measure = { path = "Fonts\\FRIZQT__.TTF", size = 14, widthReady = true, setCalls = 0 }
function measure:Hide() end
function measure:SetFont(path, size, flags)
    self.setCalls = self.setCalls + 1
    self.path, self.size, self.flags = path, size, flags
    return true
end
function measure:GetFont() return self.path, self.size, self.flags end
function measure:SetText(text) self.text = text end
function measure:GetStringWidth() return self.widthReady and 101 or 0 end

local fs = { path = "Fonts\\FRIZQT__.TTF", size = 10, setCalls = 0, glyphFace = "fallback" }
function fs:SetFont(path, size, flags)
    self.setCalls = self.setCalls + 1
    self.path, self.size, self.flags = path, size, flags
    if self.setCalls >= 2 then self.glyphFace = "requested" end
    return true
end
function fs:GetFont() return self.path, self.size, self.flags end
function fs:SetTextColor() end
function fs:SetShadowColor() end
function fs:SetShadowOffset() end

local frame = { unit = "target", msufConfigKey = "target", powerText = fs }
_G.MSUF_NS = { Fonts = {} }
_G.MSUF_DB = {
    general = { fontKey = activePath, fontSize = 14, powerFontSize = 10 },
    target = { powerFontSize = 10 },
}
_G.MSUF_GetFontPath = function() return activePath end
_G.MSUF_GetFontFlags = function() return "" end
_G.MSUF_GetConfiguredFontColor = function() return 1, 1, 1 end
_G.MSUF_FontPathMatches = function(a, b)
    return tostring(a):gsub("/", "\\"):lower() == tostring(b):gsub("/", "\\"):lower()
end
_G.MSUF_ForEachUnitFrame = function(callback)
    framePasses = framePasses + 1
    callback(frame)
end
_G.MSUF_UpdateCastbarVisuals_Immediate = function() followerPasses = followerPasses + 1 end
_G.MSUF_ForceTextLayoutForUnitKey = function() relayouts = relayouts + 1 end
_G.MSUF_ScheduleDelayOnce = function(key, delay, callback)
    assert(type(key) == "string" and key:match("^UF_FONT_COLD_RELAYOUT_%d+$"),
        "font settle scheduler key is not generation-specific")
    assert(type(delay) == "number" and delay > 0, "font settle delay must be positive")
    if pendingTimerKeys[key] then return end
    pendingTimerKeys[key] = true
    timers[#timers + 1] = function()
        pendingTimerKeys[key] = nil
        callback()
    end
end
_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }
_G.UIParent = { CreateFontString = function() return measure end }
_G.CreateFrame = function()
    return { RegisterEvent = function() end, UnregisterEvent = function() end, SetScript = function() end }
end

-- Production-shaped epoch-aware two-level SafeSet cache.
_G.MSUF_SetFontSafe = function(region, path, size, flags)
    local epoch = tonumber(_G.MSUF_FontApplyEpoch) or 0
    if region._msufSafeFontRequestPath == path
        and region._msufSafeFontRequestSize == size
        and region._msufSafeFontRequestFlags == flags
        and region._msufSafeFontRequestEpoch == epoch
    then
        return true, path, "cached"
    end
    if region._msufSafeFontPath ~= path
        or region._msufSafeFontSize ~= size
        or region._msufSafeFontFlags ~= flags
        or region._msufSafeFontEpoch ~= epoch
    then
        local applied = region:SetFont(path, size, flags)
        if applied == false then return false, path, "failed" end
        region._msufSafeFontPath = path
        region._msufSafeFontSize = size
        region._msufSafeFontFlags = flags
        region._msufSafeFontEpoch = epoch
    end
    region._msufSafeFontRequestPath = path
    region._msufSafeFontRequestSize = size
    region._msufSafeFontRequestFlags = flags
    region._msufSafeFontRequestEpoch = epoch
    return true, path, "requested"
end

assert(loadfile(runtimePath))("MidnightSimpleUnitFrames", _G.MSUF_NS)
local update = assert(_G.MSUF_UpdateAllFonts_Immediate)

-- First tuple match is deliberately false-ready.
update()
assert(fs.setCalls == 1 and fs.glyphFace == "fallback", "initial apply no longer models provisional glyphs")
assert(#timers == 1, "first accepted tuple must schedule one delayed settle")
table.remove(timers, 1)()
assert(fs.setCalls == 2 and fs.glyphFace == "requested", "settle did not force a second SetFont")
assert(relayouts == 1, "settle did not reflow text exactly once")
assert(#timers == 0, "settled font left a timer active")

local settledCalls = fs.setCalls
update()
assert(fs.setCalls == settledCalls, "settled tuple lost its zero-SetFont fast path")
assert(#timers == 0, "settled explicit refresh restarted cold recovery")

-- Unready work must be probe-only. Switching paths while a retry is pending
-- gets a fresh timer/key; the old generation callback must be a no-op.
activePath = "Interface\\AddOns\\Missing_Test\\Fonts\\First.ttf"
_G.MSUF_DB.general.fontKey = activePath
measure.widthReady = false
local framesBefore, followersBefore = framePasses, followerPasses
update()
assert(#timers == 1, "new font generation did not start recovery")
table.remove(timers, 1)()
assert(#timers == 1, "unready probe did not schedule its bounded backoff")

activePath = "Interface\\AddOns\\Missing_Test\\Fonts\\Second.ttf"
_G.MSUF_DB.general.fontKey = activePath
update()
assert(#timers == 2, "path switch inherited/deduped the old generation timer")
local probeCallsBeforeStale = measure.setCalls
table.remove(timers, 1)()
assert(measure.setCalls == probeCallsBeforeStale and #timers == 1,
    "stale generation callback probed or replaced the new path")

local callbacks = 0
while #timers > 0 do
    callbacks = callbacks + 1
    assert(callbacks <= 10, "font recovery exceeded its bounded retry budget")
    table.remove(timers, 1)()
end
assert(callbacks == 6, "font recovery retry budget changed unexpectedly")
assert(framePasses == framesBefore + 2 and followerPasses == followersBefore + 2,
    "unready retries performed a full consumer fanout")
_G.MSUF_MarkFontApplyFailed()
assert(#timers == 0, "timed-out tuple restarted recovery from a late FontString failure")

activePath = "Interface\\AddOns\\Missing_Test\\Fonts\\Third.ttf"
_G.MSUF_DB.general.fontKey = activePath
update()
assert(#timers == 1, "new font path inherited an exhausted retry budget")

local function Read(path)
    local file = assert(io.open(path, "rb"))
    local text = file:read("*a")
    file:close()
    return text
end

local libs = Read("MidnightSimpleUnitFrames/Foundation/MSUF_Libs.lua")
assert(libs:find("_msufSafeFontEpoch", 1, true)
    and libs:find("_msufSafeFontRequestEpoch", 1, true)
    and libs:find("MSUF_RequestFontRecovery", 1, true),
    "SafeSet/LSM callback is not wired to the settle generation")
local main = Read("MidnightSimpleUnitFrames/MidnightSimpleUnitFrames.lua")
assert(main:find("MSUF_InvalidateFontMetricCaches", 1, true)
    and main:find("_msufLastSetT = nil", 1, true),
    "font settle does not invalidate metric/text caches")
for _, path in ipairs({
    "MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Render.lua",
    "MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_Auras.lua",
    "MidnightSimpleUnitFrames/GroupFrames/MSUF_GF_SpellIndicators.lua",
}) do
    assert(Read(path):find("MSUF_FontApplyEpoch", 1, true), path .. " is missing the font epoch gate")
end

print("font_cold_start_settle_smoke: ok")
