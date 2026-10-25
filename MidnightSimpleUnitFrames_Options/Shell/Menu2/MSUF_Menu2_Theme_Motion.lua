local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local FILE = "Shell/Menu2/MSUF_Menu2_Theme_Motion.lua"
local PixelLayoutLeaf = MSUF.Require("PreparePixelLayoutLeaf", FILE, MSUF.Util)
local MenuSkin = MSUF.MenuSkin

local function ClampMotionDuration(value, fallback)
    if T.ReducedMotionEnabled() then return 0.001 end
    value = tonumber(value) or tonumber(fallback) or T.motion.standard or 0.105
    local policy = T.motionPolicy or {}
    local minDur = tonumber(policy.min) or 0.045
    local maxDur = tonumber(policy.max) or 0.160
    if value < minDur then return minDur end
    if value > maxDur then return maxDur end
    return value
end
-- Smooth scrolls ask this on every frame, so the profile is read inline.
function T.ReducedMotionEnabled(scrolling)
    local db = MSUF_DB
    local general = type(db) == "table" and db.general or nil
    if type(general) == "table" and (general.reduceMotion == true or general.reducedMotion == true) then return true end
    if scrolling then return MenuSkin.ScrollMotionReduced() end
    return MenuSkin.MotionReduced()
end
function T.MotionDuration(name, fallback)
    if type(name) == "number" then return ClampMotionDuration(name, fallback) end
    local profile = type(name) == "string" and T.motionProfiles[name] or nil
    local key = profile and profile.duration or name
    local value = key and T.motion[key]
    return ClampMotionDuration(value, fallback)
end
local menuAnimationGroups = T._menuAnimationGroups
if menuAnimationGroups == nil then
    menuAnimationGroups = setmetatable({}, { __mode = "k" })
    T._menuAnimationGroups = menuAnimationGroups
end
function T.TrackMenuAnimationGroup(group)
    if group then menuAnimationGroups[group] = true end
    return group
end
function T.StopAllMenuAnimations()
    local stopped = 0
    for group in pairs(menuAnimationGroups) do
        group:Stop()
        stopped = stopped + 1
    end
    return stopped
end
-- Sets an Alpha animation's range, duration and smoothing (and its order when given).
local function ConfigureAlphaAnim(anim, fromAlpha, toAlpha, duration, smoothing, order)
    if anim.SetFromAlpha then anim:SetFromAlpha(fromAlpha) end
    if anim.SetToAlpha then anim:SetToAlpha(toAlpha) end
    if anim.SetDuration then anim:SetDuration(duration) end
    if anim.SetSmoothing then anim:SetSmoothing(smoothing) end
    if order and anim.SetOrder then anim:SetOrder(order) end
end
local function StopAlphaMotion(frame)
    if not frame then return end
    local fade = frame._msuf2AlphaFade
    if fade and fade.Stop then
        if fade.SetScript then fade:SetScript("OnFinished", nil) end
        fade:Stop()
    end
    local scale = frame._msuf2AlphaScale
    if scale and scale.Stop then
        if scale.SetScript then scale:SetScript("OnFinished", nil) end
        scale:Stop()
    end
end
T.StopMotion = StopAlphaMotion
local function PlayAlphaGroup(frame, group, fromAlpha, toAlpha, onFinished)
    group:SetScript("OnFinished", function()
        if frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
    end)
    frame:SetAlpha(fromAlpha or 0)
    if frame.Show then frame:Show() end
    group:Play()
end
function T.PlayAlpha(frame, fromAlpha, toAlpha, duration, onFinished, smoothing)
    if not (frame and frame.SetAlpha and frame.CreateAnimationGroup) then
        if frame and frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
        return
    end
    if frame._msuf2AlphaScale and frame._msuf2AlphaScale.Stop then
        frame._msuf2AlphaScale:SetScript("OnFinished", nil)
        frame._msuf2AlphaScale:Stop()
    end
    local group = frame._msuf2AlphaFade
    local anim = frame._msuf2AlphaFadeAnim
    if not group then
        group = frame:CreateAnimationGroup()
        T.TrackMenuAnimationGroup(group)
        anim = group:CreateAnimation("Alpha")
        frame._msuf2AlphaFade = group
        frame._msuf2AlphaFadeAnim = anim
    elseif group.Stop then
        group:SetScript("OnFinished", nil)
        group:Stop()
    end
    ConfigureAlphaAnim(anim, fromAlpha or 0, toAlpha or 1, ClampMotionDuration(duration, T.motion.standard),
        smoothing or ((toAlpha or 1) > (fromAlpha or 0) and "OUT" or "IN"))
    PlayAlphaGroup(frame, group, fromAlpha, toAlpha, onFinished)
end
function T.PlayAlphaScale(frame, fromAlpha, toAlpha, duration, scaleFrom, scaleTo, onFinished, smoothing, origin)
    if not (frame and frame.SetAlpha and frame.CreateAnimationGroup) then
        if frame and frame.SetAlpha then frame:SetAlpha(toAlpha or 1) end
        if type(onFinished) == "function" then onFinished(frame) end
        return
    end
    if frame._msuf2AlphaFade and frame._msuf2AlphaFade.Stop then
        frame._msuf2AlphaFade:SetScript("OnFinished", nil)
        frame._msuf2AlphaFade:Stop()
    end
    if frame._msuf2AlphaScale and frame._msuf2AlphaScale.Stop then
        frame._msuf2AlphaScale:SetScript("OnFinished", nil)
        frame._msuf2AlphaScale:Stop()
    end
    local group = frame._msuf2AlphaScale
    local alpha, scale = frame._msuf2AlphaScaleAlpha, frame._msuf2AlphaScaleTransform
    if not group then
        group = frame:CreateAnimationGroup()
        T.TrackMenuAnimationGroup(group)
        alpha, scale = group:CreateAnimation("Alpha"), group:CreateAnimation("Scale")
        frame._msuf2AlphaScale = group
        frame._msuf2AlphaScaleAlpha, frame._msuf2AlphaScaleTransform = alpha, scale
    end
    local dur = ClampMotionDuration(duration, T.motion.standard)
    local ok = alpha and scale
    if ok then
        ConfigureAlphaAnim(alpha, fromAlpha or 0, toAlpha or 1, dur,
            smoothing or ((toAlpha or 1) > (fromAlpha or 0) and "OUT" or "IN"), 1)
    end
    if ok and scale.SetScaleFrom and scale.SetScaleTo then
        scale:SetScaleFrom(scaleFrom or 1, scaleFrom or 1)
        scale:SetScaleTo(scaleTo or 1, scaleTo or 1)
    else
        ok = false
    end
    if ok and scale.SetDuration then scale:SetDuration(dur) end
    if ok and scale.SetOrder then scale:SetOrder(1) end
    if ok and scale.SetSmoothing then scale:SetSmoothing(smoothing or "OUT") end
    if ok and scale.SetOrigin then scale:SetOrigin(origin or "CENTER", 0, 0) end
    if not ok then
        if group.Stop then group:Stop() end
        return T.PlayAlpha(frame, fromAlpha, toAlpha, dur, onFinished, smoothing)
    end
    frame._msuf2AlphaScale = group
    PlayAlphaGroup(frame, group, fromAlpha, toAlpha, onFinished)
end
function T.PlayMotion(frame, motion, opts)
    opts = opts or {}
    local profile = type(motion) == "table" and motion or (T.motionProfiles[motion])
    if type(profile) ~= "table" or (profile.type and profile.type ~= "alpha") then
        local toAlpha = opts.toAlpha
        if toAlpha == nil then toAlpha = 1 end
        return T.PlayAlpha(frame, opts.fromAlpha or 0, toAlpha, opts.duration or T.MotionDuration(motion), opts.onFinished, opts.smoothing)
    end
    local fromAlpha = opts.fromAlpha
    if fromAlpha == nil then
        if profile.fromCurrent and frame and frame.GetAlpha then
            fromAlpha = frame:GetAlpha()
        else
            fromAlpha = profile.fromAlpha
        end
    end
    if fromAlpha == nil then fromAlpha = 0 end
    local toAlpha = opts.toAlpha
    if toAlpha == nil then toAlpha = profile.toAlpha end
    if toAlpha == nil then toAlpha = 1 end
    local duration = opts.duration or T.MotionDuration(profile.duration or motion)
    local smoothing = opts.smoothing or profile.smoothing
    local scaleFrom = opts.scaleFrom
    if scaleFrom == nil then scaleFrom = profile.scaleFrom end
    local scaleTo = opts.scaleTo
    if scaleTo == nil then scaleTo = profile.scaleTo end
    if scaleFrom ~= nil and scaleTo ~= nil then return T.PlayAlphaScale(frame, fromAlpha, toAlpha, duration, scaleFrom, scaleTo, opts.onFinished, smoothing,
        opts.scaleOrigin or profile.scaleOrigin) end
    return T.PlayAlpha(frame, fromAlpha, toAlpha, duration, opts.onFinished, smoothing)
end
local function IsDescendantOf(frame, ancestor)
    local current = frame
    while current do
        if current == ancestor then return true end
        current = current.GetParent and current:GetParent()
    end
    return false
end
local function FocusVeilRoot(owner, opts)
    opts = opts or {}
    if opts.root then return opts.root end
    local frame = M.frame
    if not (frame and frame.IsShown and frame:IsShown()) then return nil end
    local host = frame.host or frame._msufMirrorHost
    if host and owner and IsDescendantOf(owner, host) then return host end
    return frame.content or frame
end
local function EnsureFocusVeilFrame()
    if M._focusVeilFrame then return M._focusVeilFrame end
    local overlay = PixelLayoutLeaf(CreateFrame("Frame", "MSUF2FocusVeil", UIParent))
    overlay:SetFrameStrata("TOOLTIP")
    overlay:SetToplevel(false)
    overlay:EnableMouse(false)
    overlay:Hide()
    M._focusVeilFrame = overlay
    return overlay
end
function M.ResetFocusVeil(variant, opts)
    opts = opts or {}
    local overlay = M._focusVeilFrame
    if not overlay then
        M._focusVeilState = nil
        return false
    end
    local state = M._focusVeilState
    if variant and state and state.variant and variant ~= state.variant and not opts.force then return false end
    overlay._msuf2FocusToken = (overlay._msuf2FocusToken or 0) + 1
    StopAlphaMotion(overlay)
    M._focusVeilState = nil
    overlay:Hide()
    overlay:ClearAllPoints()
    overlay:SetAlpha(1)
    return true
end
function M.ShowFocusVeil(owner, variant, opts)
    opts = opts or {}
    variant = variant or "dropdown"
    local root = FocusVeilRoot(owner, opts)
    if not root then
        M.HideFocusVeil(variant, { animated = true })
        return nil
    end
    local overlay = EnsureFocusVeilFrame()
    -- The veil only carries translucent textures; the focus material adds an opaque panel.
    T.ApplyFocusVeil(overlay, variant)
    overlay:ClearAllPoints()
    overlay:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    overlay:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
    if overlay.SetFrameLevel then
        local ref = opts.referenceFrame
        local refLevel = ref and ref.GetFrameLevel and ref:GetFrameLevel()
        overlay:SetFrameLevel(math.max(0, (opts.frameLevel or (refLevel and refLevel - 1) or 119)))
    end
    local state = M._focusVeilState or {}
    M._focusVeilState = state
    state.owner = owner
    state.variant = variant
    state.hiding = nil
    overlay._msuf2FocusToken = (overlay._msuf2FocusToken or 0) + 1
    local fromAlpha = (overlay.IsShown and overlay:IsShown() and overlay.GetAlpha and overlay:GetAlpha()) or 0
    T.PlayMotion(overlay, "focusIn", { fromAlpha = fromAlpha, duration = opts.duration })
    return overlay
end
function M.HideFocusVeil(variant, opts)
    opts = opts or {}
    local overlay = M._focusVeilFrame
    if not overlay then return end
    local state = M._focusVeilState or {}
    M._focusVeilState = state
    if variant and state.variant and variant ~= state.variant and not opts.force then return end
    if opts.animated == false then
        return M.ResetFocusVeil(variant, opts)
    end
    if state.hiding then return end
    if overlay.IsShown and not overlay:IsShown() then
        state.hiding = nil
        overlay:SetAlpha(1)
        return
    end
    state.hiding = true
    overlay._msuf2FocusToken = (overlay._msuf2FocusToken or 0) + 1
    local closeToken = overlay._msuf2FocusToken
    local fromAlpha = (overlay.GetAlpha and overlay:GetAlpha()) or 1
    T.PlayMotion(overlay, "focusOut", { fromAlpha = fromAlpha, duration = opts.duration, onFinished = function(self)
        if self._msuf2FocusToken ~= closeToken then return end
        state.hiding = nil
        state.owner = nil
        state.variant = nil
        self:Hide()
        self:SetAlpha(1)
    end })
end

T._ConfigureAlphaAnim = ConfigureAlphaAnim
