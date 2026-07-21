local root = arg and arg[1] or "."

local function Equal(actual, expected, label)
    if actual ~= expected then
        error((label or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local requestedPath = "Interface\\AddOns\\SharedMedia_Test\\Fonts\\Cold.ttf"
local activePath = requestedPath
local timers, pendingTimerKeys = {}, {}
local refreshCalls = 0
local followerOrder, groupFontCalls, auraFontCalls, focusFontCalls = {}, 0, 0, 0, 0

_G.MSUF = nil
_G.MSUF_NS = nil
_G.MSUF_UpdateAllFonts = nil
_G.MSUF_UpdateAllFonts_Immediate = nil
_G.UpdateAllFonts = nil
_G.MSUF_FontPathKey = nil
_G.MSUF_FontPathSerial = nil
_G.MSUF_FontApplyFailureSerial = 0
_G.MSUF_FontApplyEpoch = 0
_G.MSUF_DB = {
    general = {
        fontKey = activePath,
        fontSize = 12,
        nameFontSize = 12,
        hpFontSize = 12,
        powerFontSize = 12,
        textBackdrop = false,
        fontTextAlpha = 1,
    },
    player = {},
}
_G.MSUF_GetFontPath = function() return activePath end
_G.MSUF_GetFontFlags = function() return "" end
_G.MSUF_ResolveSafeFontPath = function(path) return path end
_G.MSUF_GetConfiguredFontColor = function() return 1, 1, 1 end
_G.MSUF_ResolveFontShadowMetrics = function() return 1, 1, -1 end
_G.MSUF_FocusKick_ApplyTimeTextFont = function()
    focusFontCalls = focusFontCalls + 1
    followerOrder[#followerOrder + 1] = "focus"
end
_G.MSUF_FontApplicationMatches = function(region, path, size)
    local actualPath, actualSize = region:GetFont()
    return actualPath == path and math.abs((actualSize or 0) - size) <= 0.01
end
_G.MSUF_ScheduleDelayOnce = function(key, delay, callback)
    assert(type(key) == "string" and key:match("^UF_FONT_COLD_RELAYOUT_%d+$"),
        "cold retry key is not generation-specific")
    assert(type(delay) == "number" and delay > 0, "cold retry delay must be positive")
    if pendingTimerKeys[key] then return end
    pendingTimerKeys[key] = true
    timers[#timers + 1] = function()
        pendingTimerKeys[key] = nil
        callback()
    end
end
_G.C_Timer = { After = function(_, callback) timers[#timers + 1] = callback end }

local measure = {
    path = "Fonts\\FRIZQT__.TTF",
    size = 14,
    flags = "",
    setCalls = 0,
    glyphFace = "fallback",
    widthReady = true,
}
function measure:Hide() end
function measure:SetFont(path, size, flags)
    self.setCalls = self.setCalls + 1
    self.path, self.size, self.flags = path, size, flags
    if self.setCalls >= 2 then self.glyphFace = "requested" end
    return true
end
function measure:GetFont() return self.path, self.size, self.flags end
function measure:SetText() end
function measure:GetStringWidth() return self.widthReady and 100 or 0 end
_G.UIParent = { CreateFontString = function() return measure end }

local loginFrame
_G.CreateFrame = function()
    local frame = {}
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:SetScript(_, callback) loginFrame = callback end
    return frame
end

local common = {
    UF = {}, type = type, tonumber = tonumber, format = string.format,
    abs = math.abs, floor = math.floor, max = math.max,
}
local textMSUF = { UFBarTextCommon = common, Secrets = {} }
assert(loadfile(root .. "/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Text_Common.lua"))(
    "MidnightSimpleUnitFrames", textMSUF)
local SetUnitFont = assert(textMSUF.UFText and textMSUF.UFText.SetFont)

local fontString = {
    path = "Fonts\\FRIZQT__.TTF",
    size = 12,
    flags = "",
    setFontCalls = 0,
    glyphFace = "fallback",
}
function fontString:SetFont(path, size, flags)
    self.setFontCalls = self.setFontCalls + 1
    self.path, self.size, self.flags = path, size, flags
    if self.setFontCalls >= 2 then self.glyphFace = "requested" end
    return true
end
function fontString:GetFont() return self.path, self.size, self.flags end
function fontString:SetTextColor() end
function fontString:SetShadowColor() end
function fontString:SetShadowOffset() end

local spec = {
    font = activePath,
    fontFlags = "",
    fontShadow = false,
    textColor = { r = 1, g = 1, b = 1, a = 1 },
}
local MSUF = {
    ExportPublic = function(name, value) _G[name] = value; return value end,
    UF = {
        frames = {},
        RefreshElements = function()
            refreshCalls = refreshCalls + 1
            spec.font = activePath
            return SetUnitFont(fontString, spec, 12, "name")
        end,
    },
    GF = {
        RefreshFonts = function()
            groupFontCalls = groupFontCalls + 1
            followerOrder[#followerOrder + 1] = "gf"
        end,
    },
    MSUF_Auras3 = {
        ApplyFontsFromGlobal = function()
            auraFontCalls = auraFontCalls + 1
            followerOrder[#followerOrder + 1] = "aura"
        end,
    },
}

assert(loadfile(root .. "/MidnightSimpleUnitFrames/Runtime/MSUF_FontRuntime.lua"))(
    "MidnightSimpleUnitFrames", MSUF)
local UpdateAllFonts = assert(MSUF.Fonts.UpdateAllFonts, "font runtime update export missing")
assert(type(loginFrame) == "function", "login font kick was not installed")

-- Exact path/size and positive width on the first call are still provisional.
UpdateAllFonts()
Equal(fontString.setFontCalls, 1, "provisional consumer SetFont calls")
Equal(fontString.glyphFace, "fallback", "provisional consumer glyph face")
Equal(measure.setCalls, 1, "initial hidden prewarm calls")
Equal(#timers, 1, "mandatory delayed settle")
table.remove(timers, 1)()
Equal(measure.setCalls, 2, "delayed readiness probe calls")
Equal(fontString.setFontCalls, 2, "epoch-forced consumer SetFont calls")
Equal(fontString.glyphFace, "requested", "settled consumer glyph face")
Equal(fontString._msufFontPending, nil, "settled consumer pending marker")
Equal(fontString._msufFontEpoch, _G.MSUF_FontApplyEpoch, "settled consumer epoch")
Equal(refreshCalls, 2, "initial plus final UF fanout")
Equal(groupFontCalls, 2, "initial plus final group-font fanout")
Equal(auraFontCalls, 2, "initial plus final aura-font fanout")
Equal(focusFontCalls, 2, "initial plus final focus-font fanout")
Equal(table.concat(followerOrder, ","), "gf,aura,focus,gf,aura,focus",
    "group font source precedes aura overlay copy")
Equal(#timers, 0, "settled timer count")

-- The public wrapper must not become a no-op when ApplyCommitState is absent.
local settledCalls, settledRefreshes = fontString.setFontCalls, refreshCalls
_G.MSUF_UpdateAllFonts()
Equal(refreshCalls, settledRefreshes + 1, "public wrapper dispatch")
Equal(fontString.setFontCalls, settledCalls, "settled zero-SetFont fast path")
Equal(#timers, 0, "settled public wrapper timer count")

-- Unready retries are hidden-probe-only and bounded.
activePath = "Interface\\AddOns\\Missing_Test\\Fonts\\First.ttf"
_G.MSUF_DB.general.fontKey = activePath
measure.widthReady = false
local beforeUnreadyRefreshes = refreshCalls
UpdateAllFonts()
Equal(refreshCalls, beforeUnreadyRefreshes + 1, "unready initial fanout")
local callbacks = 0
while #timers > 0 do
    callbacks = callbacks + 1
    assert(callbacks <= 10, "unready recovery exceeded its bound")
    table.remove(timers, 1)()
end
Equal(callbacks, 6, "unready retry budget")
Equal(refreshCalls, beforeUnreadyRefreshes + 1, "unready probe-only fanout count")

activePath = "Interface\\AddOns\\Missing_Test\\Fonts\\Second.ttf"
_G.MSUF_DB.general.fontKey = activePath
UpdateAllFonts()
Equal(#timers, 1, "new path fresh retry budget")

print("font_runtime_cold_apply_smoke: ok")
