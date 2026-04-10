-- MSUF_Transitions.lua — Animation helpers for Options/SlashMenu UI.
-- Only includes transitions actually used by the addon.
local _, ns = ...
ns = ns or {}
local T = {}
ns.MSUF_Transitions = T

local type = type

-- AnimationGroup cache per frame
local function GetOrCreateGroup(frame)
    if not frame then return nil end
    local ag = frame._msufTransGroup
    if ag then
        ag:Stop()
        local anims = { ag:GetAnimations() }
        for i = 1, #anims do anims[i]:SetParent(nil) end
        return ag
    end
    ag = frame:CreateAnimationGroup()
    frame._msufTransGroup = ag
    return ag
end

local function AddAlpha(ag, from, to, duration, order)
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(from); a:SetToAlpha(to)
    a:SetDuration(duration); a:SetOrder(order or 1)
    a:SetSmoothing("IN_OUT")
    return a
end

local function AddScale(ag, fromX, fromY, toX, toY, duration, order)
    local s = ag:CreateAnimation("Scale")
    s:SetScaleFrom(fromX, fromY); s:SetScaleTo(toX, toY)
    s:SetDuration(duration); s:SetOrder(order or 1)
    s:SetSmoothing("IN_OUT")
    return s
end

function T.FadeIn(frame, duration, onFinish)
    if not frame then return end
    duration = duration or 0.2
    local ag = GetOrCreateGroup(frame)
    if not ag then if frame.Show then frame:Show() end; return end
    AddAlpha(ag, 0, 1, duration)
    if onFinish then ag:SetScript("OnFinished", onFinish) else ag:SetScript("OnFinished", nil) end
    frame:SetAlpha(0); frame:Show(); ag:Play()
end

function T.Dismiss(frame, duration, onFinish)
    if not frame then return end
    duration = duration or 0.15
    local ag = GetOrCreateGroup(frame)
    if not ag then if frame.Hide then frame:Hide() end; return end
    AddAlpha(ag, 1, 0, duration)
    ag:SetScript("OnFinished", function()
        frame:Hide(); frame:SetAlpha(1)
        if onFinish then onFinish() end
    end)
    ag:Play()
end

function T.ScaleReveal(frame, duration, onFinish)
    if not frame then return end
    duration = duration or 0.2
    local ag = GetOrCreateGroup(frame)
    if not ag then if frame.Show then frame:Show() end; return end
    AddAlpha(ag, 0, 1, duration)
    AddScale(ag, 0.92, 0.92, 1, 1, duration)
    if onFinish then ag:SetScript("OnFinished", onFinish) else ag:SetScript("OnFinished", nil) end
    frame:SetAlpha(0); frame:Show(); ag:Play()
end

function T.ScaleDismiss(frame, duration, onFinish)
    if not frame then return end
    duration = duration or 0.15
    local ag = GetOrCreateGroup(frame)
    if not ag then if frame.Hide then frame:Hide() end; return end
    AddAlpha(ag, 1, 0, duration)
    AddScale(ag, 1, 1, 0.92, 0.92, duration)
    ag:SetScript("OnFinished", function()
        frame:Hide(); frame:SetAlpha(1); frame:SetScale(1)
        if onFinish then onFinish() end
    end)
    ag:Play()
end

function T.Cancel(frame)
    if not frame then return end
    local ag = frame._msufTransGroup
    if ag and ag.IsPlaying and ag:IsPlaying() then ag:Stop() end
end
