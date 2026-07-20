-- Focused cold-start live-font readback regression.
-- Run from the repository root with Lua 5.1:
--   lua tools/font_runtime_cold_apply_smoke.lua

local requestedPath = "Interface\\AddOns\\MidnightSimpleUnitFrames\\Media\\Fonts\\Expressway.ttf"
local requestedSize = 9
local setAttempts, fallbackAttempts, getFontReads = 0, 0, 0

local fontString = {
    fontPath = requestedPath,
    fontSize = 14,
    fontFlags = "OUTLINE",
}

function fontString:GetFont()
    getFontReads = getFontReads + 1
    return self.fontPath, self.fontSize, self.fontFlags
end

function fontString:SetFont(path, size, flags)
    if path ~= requestedPath then
        fallbackAttempts = fallbackAttempts + 1
        return false
    end

    setAttempts = setAttempts + 1
    if setAttempts == 1 then
        -- WoW edge case: SetFont reports success while the live FontString
        -- still exposes its provisional cold-start metrics.
        return true
    end

    self.fontPath, self.fontSize, self.fontFlags = path, size, flags
    return true
end

function fontString:SetTextColor() end
function fontString:SetShadowColor() end
function fontString:SetShadowOffset() end

local frame = {
    unit = "target",
    msufConfigKey = "target",
    powerText = fontString,
}

_G.MSUF_NS = { Fonts = {} }
_G.MSUF_DB = {
    general = {
        fontSize = 14,
        powerFontSize = requestedSize,
    },
    target = {
        powerFontSize = requestedSize,
    },
}
_G.MSUF_GetFontPath = function() return requestedPath end
_G.MSUF_GetFontFlags = function() return "OUTLINE" end
_G.MSUF_GetConfiguredFontColor = function() return 1, 1, 1 end
_G.MSUF_FontPathMatches = function(a, b) return a == b end
_G.MSUF_ForEachUnitFrame = function(callback) callback(frame) end

-- Mirror the two safe-font cache layers closely enough to prove that a false
-- success must invalidate them before the cold retry can reach SetFont again.
_G.MSUF_SetFontSafe = function(region, path, size, flags)
    if region._msufSafeFontRequestPath == path
        and region._msufSafeFontRequestSize == size
        and region._msufSafeFontRequestFlags == flags
    then
        return true, region._msufSafeFontAppliedPath or path, region._msufSafeFontSource or "cached"
    end

    local applied = region:SetFont(path, size, flags)
    if applied == false then return false, path, "failed" end

    region._msufSafeFontPath = path
    region._msufSafeFontSize = size
    region._msufSafeFontFlags = flags
    region._msufSafeFontRequestPath = path
    region._msufSafeFontRequestSize = size
    region._msufSafeFontRequestFlags = flags
    region._msufSafeFontAppliedPath = path
    region._msufSafeFontSource = "requested"
    return true, path, "requested"
end

_G.UIParent = nil
_G.CreateFrame = function()
    return {
        RegisterEvent = function() end,
        SetScript = function() end,
        UnregisterEvent = function() end,
    }
end

assert(loadfile("MidnightSimpleUnitFrames/Core/MSUF_FontRuntime.lua"))(
    "MidnightSimpleUnitFrames",
    _G.MSUF_NS
)
local update = assert(_G.MSUF_UpdateAllFonts_Immediate)

update()
assert(fontString.fontSize == 14, "first accepted apply unexpectedly changed live size")
assert(setAttempts == 1, "first cold apply count changed")
assert(fallbackAttempts == 0, "verified cold mismatch incorrectly settled on fallback")
assert(fontString._msufFontRev == nil, "unverified cold apply poisoned font revision")
assert(fontString._msufSafeFontRequestPath == nil, "unverified safe-font request cache survived")
assert(fontString._msufSafeFontPath == nil, "unverified safe-font apply cache survived")

update()
assert(fontString.fontPath == requestedPath, "retry did not apply requested path")
assert(fontString.fontSize == requestedSize, "retry did not repair live size")
assert(setAttempts == 2, "cold retry did not call SetFont exactly once")
assert(fontString._msufFontRev ~= nil, "verified retry was not cached")

local settledRevision = fontString._msufFontRev
local settledReads = getFontReads
update()
assert(setAttempts == 2, "settled font lost the revision fast path")
assert(getFontReads == settledReads, "settled font performed another readback")
assert(fontString._msufFontRev == settledRevision, "settled revision changed")

-- A safe-helper fallback may render immediately, but it must remain pending so
-- the configured font is retried once the client can apply it.
local fallbackPath = "Fonts\\FRIZQT__.TTF"
local fallbackRequests = 0
local fallbackFontString = {
    fontPath = requestedPath,
    fontSize = 14,
    fontFlags = "OUTLINE",
}

function fallbackFontString:GetFont()
    return self.fontPath, self.fontSize, self.fontFlags
end

function fallbackFontString:SetTextColor() end
function fallbackFontString:SetShadowColor() end
function fallbackFontString:SetShadowOffset() end

frame.powerText = fallbackFontString
_G.MSUF_SetFontSafe = function(region, path, size, flags)
    if path ~= requestedPath then return false, path, "failed" end

    fallbackRequests = fallbackRequests + 1
    local appliedPath, source = path, "requested"
    if fallbackRequests == 1 then
        appliedPath, source = fallbackPath, "fallback"
    end
    region.fontPath, region.fontSize, region.fontFlags = appliedPath, size, flags
    region._msufSafeFontPath = appliedPath
    region._msufSafeFontSize = size
    region._msufSafeFontFlags = flags
    region._msufSafeFontRequestPath = path
    region._msufSafeFontRequestSize = size
    region._msufSafeFontRequestFlags = flags
    region._msufSafeFontAppliedPath = appliedPath
    region._msufSafeFontSource = source
    return true, appliedPath, source
end

update()
assert(fallbackFontString.fontPath == fallbackPath, "safe fallback was not preserved for readability")
assert(fallbackFontString._msufFontRev == nil, "safe fallback poisoned configured font revision")
assert(fallbackFontString._msufSafeFontRequestPath == nil, "safe fallback request cache survived")
assert(fallbackRequests == 1, "safe fallback request count changed")

update()
assert(fallbackFontString.fontPath == requestedPath, "configured font was not retried after safe fallback")
assert(fallbackFontString.fontSize == requestedSize, "configured font retry lost requested size")
assert(fallbackFontString._msufFontRev ~= nil, "configured font retry was not cached")
assert(fallbackRequests == 2, "configured font was not retried exactly once")

-- A fully rejected primary apply may use the outer fallback for readability,
-- but that fallback still must not earn the configured-path revision.
local rejectedRequests, outerFallbackRequests = 0, 0
local rejectedFontString = {
    fontPath = requestedPath,
    fontSize = 14,
    fontFlags = "OUTLINE",
}

function rejectedFontString:GetFont()
    return self.fontPath, self.fontSize, self.fontFlags
end

function rejectedFontString:SetTextColor() end
function rejectedFontString:SetShadowColor() end
function rejectedFontString:SetShadowOffset() end

frame.powerText = rejectedFontString
_G.MSUF_SetFontSafe = function(region, path, size, flags)
    if path == requestedPath then
        rejectedRequests = rejectedRequests + 1
        if rejectedRequests == 1 then return false, path, "failed" end
    else
        outerFallbackRequests = outerFallbackRequests + 1
    end

    region.fontPath, region.fontSize, region.fontFlags = path, size, flags
    return true, path, "requested"
end

update()
assert(rejectedFontString.fontPath ~= requestedPath, "outer fallback was not applied after rejection")
assert(rejectedFontString._msufFontRev == nil, "outer fallback poisoned configured font revision")
assert(rejectedRequests == 1, "rejected primary request count changed")
assert(outerFallbackRequests == 1, "outer fallback request count changed")

update()
assert(rejectedFontString.fontPath == requestedPath, "configured font was not retried after outer fallback")
assert(rejectedFontString.fontSize == requestedSize, "outer-fallback recovery lost requested size")
assert(rejectedFontString._msufFontRev ~= nil, "outer-fallback recovery was not cached")
assert(rejectedRequests == 2, "configured font retry count changed after outer fallback")

print("font_runtime_cold_apply_smoke: ok")
