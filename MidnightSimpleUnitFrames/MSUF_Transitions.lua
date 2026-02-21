-- MSUF_Transitions.lua
-- Centralized UI transition system for Midnight Simple Unit Frames.
--
-- Design goals:
--   * AnimationGroup-based (WoW-native, no manual OnUpdate polling)
--   * Secret-safe: no comparisons or arithmetic on protected values
--   * Zero-leak: animations only tick while playing, groups are recycled
--   * Maintainable: one API surface, drop-in for any Show()/Hide() site
--   * Subtle & fast: professional feel, never delays user interaction
--
-- Usage:
--   local T = ns.MSUF_Transitions
--   T.FadeIn(frame, 0.15)                    -- simple fade in
--   T.FadeOut(frame, 0.12, function() end)    -- fade out with onFinish
--   T.CrossFade(oldFrame, newFrame, 0.18)     -- page switch transition
--   T.ScaleReveal(frame, 0.15)               -- scale 0.97→1.0 + fade in
--   T.SlideIn(frame, "LEFT", 20, 0.18)       -- slide from offset + fade
--   T.Dismiss(frame, 0.12)                   -- fade out then :Hide()
--
-- All durations are in seconds. Recommended range: 0.10 – 0.22s
-- Anything longer feels sluggish in a game UI.

local addonName, ns = ...
ns = ns or {}

-- =========================================================================
-- Perf locals (safe: function refs only, no secret values)
-- =========================================================================
local type        = type
local CreateFrame = CreateFrame
local GetTime     = GetTime

-- =========================================================================
-- Module table
-- =========================================================================
local T = {}
ns.MSUF_Transitions = T
if _G then _G.MSUF_Transitions = T end

-- =========================================================================
-- Constants – tweak these for global feel
-- =========================================================================
T.DURATION_FAST   = 0.10   -- micro-interactions (tooltip, highlight)
T.DURATION_NORMAL = 0.15   -- standard panel open/close
T.DURATION_SLOW   = 0.22   -- emphasis (first-open, edit mode overlay)

-- Scale reveal parameters
local SCALE_REVEAL_FROM = 0.97   -- subtle: almost full size already
local SCALE_REVEAL_TO   = 1.0

-- =========================================================================
-- Internal: AnimationGroup pool
-- Each frame gets at most ONE transition group (recycled). This avoids
-- creating dozens of groups on rapid open/close cycles.
-- =========================================================================
local ANIM_KEY = "__msufTransitionAG"

--- Get or create the transition AnimationGroup for a frame.
--- Stops any in-progress transition before returning.
---@param frame table  WoW frame
---@return table animGroup
local function GetOrCreateGroup(frame)
    local ag = frame[ANIM_KEY]
    if ag then
        -- Stop cleanly so OnFinished doesn't fire for the old transition
        if ag.Stop then ag:Stop() end
        -- Clear all existing animations for reuse
        -- (WoW AnimationGroups don't support removing children,
        --  so we mark stale ones and create fresh as needed.)
        ag._msufStale = true
    end

    -- Always create a fresh group to avoid stale animation state.
    -- Old group is stopped and will be GC'd.
    ag = frame:CreateAnimationGroup()
    frame[ANIM_KEY] = ag
    ag._msufStale = false
    return ag
end

--- Create an Alpha animation on a group.
---@param ag table        AnimationGroup
---@param from number     start alpha (0–1)
---@param to number       end alpha (0–1)
---@param duration number seconds
---@param order number?   animation order (default 1)
---@return table animation
local function AddAlpha(ag, from, to, duration, order)
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(from)
    a:SetToAlpha(to)
    a:SetDuration(duration)
    a:SetOrder(order or 1)
    a:SetSmoothing("IN_OUT")
    return a
end

--- Create a Scale animation on a group.
---@param ag table
---@param fromX number
---@param fromY number
---@param toX number
---@param toY number
---@param duration number
---@param order number?
---@return table animation
local function AddScale(ag, fromX, fromY, toX, toY, duration, order)
    local a = ag:CreateAnimation("Scale")
    a:SetScaleFrom(fromX, fromY)
    a:SetScaleTo(toX, toY)
    a:SetDuration(duration)
    a:SetOrder(order or 1)
    a:SetSmoothing("IN_OUT")
    -- Scale from center
    a:SetOrigin("CENTER", 0, 0)
    return a
end

--- Create a Translation animation on a group.
---@param ag table
---@param offsetX number   start offset (pixels)
---@param offsetY number   start offset (pixels)
---@param duration number
---@param order number?
---@return table animation
local function AddTranslation(ag, offsetX, offsetY, duration, order)
    local a = ag:CreateAnimation("Translation")
    a:SetOffset(-offsetX, -offsetY)  -- negative = animate TO final position
    a:SetDuration(duration)
    a:SetOrder(order or 1)
    a:SetSmoothing("OUT")
    return a
end


-- =========================================================================
-- PUBLIC API
-- =========================================================================

--- FadeIn: Show frame with alpha transition 0 → 1.
--- Frame is shown immediately (at alpha 0) so layout is instant.
---@param frame table
---@param duration number?  (default DURATION_NORMAL)
---@param onFinish function?
function T.FadeIn(frame, duration, onFinish)
    if not frame then return end
    duration = duration or T.DURATION_NORMAL

    -- Ensure visible at alpha 0 before animation starts
    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.Show then frame:Show() end

    local ag = GetOrCreateGroup(frame)
    AddAlpha(ag, 0, 1, duration)

    ag:SetScript("OnFinished", function(self)
        if frame.SetAlpha then frame:SetAlpha(1) end
        if type(onFinish) == "function" then onFinish(frame) end
    end)

    ag:Play()
end

--- FadeOut: Fade frame alpha 1 → 0. Does NOT hide the frame.
--- Use Dismiss() if you want auto-Hide after fade.
---@param frame table
---@param duration number?
---@param onFinish function?
function T.FadeOut(frame, duration, onFinish)
    if not frame then return end
    duration = duration or T.DURATION_NORMAL

    local ag = GetOrCreateGroup(frame)
    AddAlpha(ag, 1, 0, duration)

    ag:SetScript("OnFinished", function(self)
        if frame.SetAlpha then frame:SetAlpha(0) end
        if type(onFinish) == "function" then onFinish(frame) end
    end)

    ag:Play()
end

--- Dismiss: Fade out then Hide(). This is the "close panel" transition.
--- The frame is hidden after the animation completes, not before.
---@param frame table
---@param duration number?
---@param onFinish function?
function T.Dismiss(frame, duration, onFinish)
    if not frame then return end
    T.FadeOut(frame, duration, function(f)
        if f and f.Hide then f:Hide() end
        if f and f.SetAlpha then f:SetAlpha(1) end  -- restore for next Show
        if type(onFinish) == "function" then onFinish(f) end
    end)
end

--- ScaleReveal: Show with subtle scale-up + fade. Premium open feel.
--- Scale goes from 0.97 → 1.0 (barely perceptible, but feels "alive").
---@param frame table
---@param duration number?
---@param onFinish function?
function T.ScaleReveal(frame, duration, onFinish)
    if not frame then return end
    duration = duration or T.DURATION_NORMAL

    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.Show then frame:Show() end

    local ag = GetOrCreateGroup(frame)
    AddAlpha(ag, 0, 1, duration)
    AddScale(ag, SCALE_REVEAL_FROM, SCALE_REVEAL_FROM,
             SCALE_REVEAL_TO, SCALE_REVEAL_TO, duration)

    ag:SetScript("OnFinished", function(self)
        if frame.SetAlpha then frame:SetAlpha(1) end
        -- Reset scale to exactly 1.0 (avoid floating point drift)
        if frame.SetScale then
            local baseScale = frame._msufBaseScale or frame:GetScale()
            frame:SetScale(baseScale)
        end
        if type(onFinish) == "function" then onFinish(frame) end
    end)

    ag:Play()
end

--- ScaleDismiss: Reverse of ScaleReveal – scale down + fade out then Hide.
---@param frame table
---@param duration number?
---@param onFinish function?
function T.ScaleDismiss(frame, duration, onFinish)
    if not frame then return end
    duration = duration or T.DURATION_NORMAL

    local ag = GetOrCreateGroup(frame)
    AddAlpha(ag, 1, 0, duration)
    AddScale(ag, SCALE_REVEAL_TO, SCALE_REVEAL_TO,
             SCALE_REVEAL_FROM, SCALE_REVEAL_FROM, duration)

    ag:SetScript("OnFinished", function(self)
        if frame.Hide then frame:Hide() end
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.SetScale then
            local baseScale = frame._msufBaseScale or 1.0
            frame:SetScale(baseScale)
        end
        if type(onFinish) == "function" then onFinish(frame) end
    end)

    ag:Play()
end

--- SlideIn: Show with directional slide + fade. Good for side panels.
---@param frame table
---@param direction string  "LEFT"|"RIGHT"|"TOP"|"BOTTOM"
---@param offset number?    pixels to slide (default 20)
---@param duration number?
---@param onFinish function?
function T.SlideIn(frame, direction, offset, duration, onFinish)
    if not frame then return end
    direction = direction or "LEFT"
    offset    = offset or 20
    duration  = duration or T.DURATION_NORMAL

    local ox, oy = 0, 0
    if direction == "LEFT"   then ox = -offset
    elseif direction == "RIGHT"  then ox = offset
    elseif direction == "TOP"    then oy = offset
    elseif direction == "BOTTOM" then oy = -offset
    end

    if frame.SetAlpha then frame:SetAlpha(0) end
    if frame.Show then frame:Show() end

    local ag = GetOrCreateGroup(frame)
    AddAlpha(ag, 0, 1, duration)
    AddTranslation(ag, ox, oy, duration)

    ag:SetScript("OnFinished", function(self)
        if frame.SetAlpha then frame:SetAlpha(1) end
        if type(onFinish) == "function" then onFinish(frame) end
    end)

    ag:Play()
end

--- CrossFade: Transition between two frames (page switch).
--- Old frame fades out (and hides), new frame fades in.
--- The overlap creates a smooth visual handoff.
---@param oldFrame table?   (nil-safe: just fades in new)
---@param newFrame table
---@param duration number?
---@param onFinish function?
function T.CrossFade(oldFrame, newFrame, duration, onFinish)
    duration = duration or T.DURATION_FAST

    -- Fade out old (if present)
    if oldFrame and oldFrame.IsShown and oldFrame:IsShown() then
        T.Dismiss(oldFrame, duration)
    end

    -- Fade in new
    if newFrame then
        T.FadeIn(newFrame, duration, onFinish)
    end
end

--- Pulse: Brief scale-up and back. "Confirm" or "attention" micro-animation.
--- Does not change visibility.
---@param frame table
---@param intensity number?  scale factor (default 1.03)
---@param duration number?   total pulse time (default 0.20)
function T.Pulse(frame, intensity, duration)
    if not frame then return end
    intensity = intensity or 1.03
    duration  = duration or 0.20
    local half = duration * 0.5

    local ag = GetOrCreateGroup(frame)

    -- Order 1: scale up
    AddScale(ag, 1, 1, intensity, intensity, half, 1)
    -- Order 2: scale back
    AddScale(ag, intensity, intensity, 1, 1, half, 2)

    ag:SetScript("OnFinished", function(self)
        if frame.SetScale then
            local baseScale = frame._msufBaseScale or frame:GetScale()
            frame:SetScale(baseScale)
        end
    end)

    ag:Play()
end

--- Flash: Brief alpha dip and back. Subtle "I heard you" feedback.
---@param frame table
---@param depth number?    alpha dip target (default 0.6)
---@param duration number? total flash time (default 0.18)
function T.Flash(frame, depth, duration)
    if not frame then return end
    depth    = depth or 0.6
    duration = duration or 0.18
    local half = duration * 0.5

    local ag = GetOrCreateGroup(frame)
    AddAlpha(ag, 1, depth, half, 1)
    AddAlpha(ag, depth, 1, half, 2)

    ag:SetScript("OnFinished", function(self)
        if frame.SetAlpha then frame:SetAlpha(1) end
    end)

    ag:Play()
end


-- =========================================================================
-- CONVENIENCE: Drop-in replacements for frame:Show() / frame:Hide()
--
-- These can be used as direct wrappers around existing Show/Hide calls
-- without restructuring the caller code:
--
--   -- Before:
--   panel:Show()
--   -- After:
--   MSUF_Transitions.Show(panel)
--
-- If a frame has ._msufNoTransition = true, transitions are skipped
-- (useful for frames that must appear instantly, e.g. during combat).
-- =========================================================================

function T.Show(frame, duration)
    if not frame then return end
    if frame._msufNoTransition then
        if frame.SetAlpha then frame:SetAlpha(1) end
        if frame.Show then frame:Show() end
        return
    end
    T.FadeIn(frame, duration or T.DURATION_FAST)
end

function T.Hide(frame, duration)
    if not frame then return end
    if frame._msufNoTransition then
        if frame.Hide then frame:Hide() end
        return
    end
    T.Dismiss(frame, duration or T.DURATION_FAST)
end


-- =========================================================================
-- INTEGRATION HELPERS
-- =========================================================================

--- Cancel any running transition on a frame and reset to clean state.
--- Use this before programmatic SetAlpha/Show/Hide calls that shouldn't
--- be interfered with by a lingering animation.
---@param frame table
function T.Cancel(frame)
    if not frame then return end
    local ag = frame[ANIM_KEY]
    if ag and ag.Stop then
        ag:Stop()
    end
    -- Don't touch alpha/scale here – caller decides final state
end

--- Check if a transition is currently playing on a frame.
---@param frame table
---@return boolean
function T.IsPlaying(frame)
    if not frame then return false end
    local ag = frame[ANIM_KEY]
    if ag and ag.IsPlaying then
        return ag:IsPlaying()
    end
    return false
end
