--- Auras3/SpellIndicator_Reminders: missing-aura surfaces and one lazy weapon-enchantment event owner.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
A3.SpellIndicatorModules = A3.SpellIndicatorModules or {}
A3.SpellIndicatorModules.Reminders = function(config, effects)
local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local math_max = math.max
local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local CreateFrame = _G.CreateFrame
local GetTime = _G.GetTime
local Runtime = A3.SpellIndicators
local ClampNumber = config.ClampNumber
local ResolveFrameStrata = config.ResolveFrameStrata
local SyncFrameStrata = config.SyncFrameStrata
local SpellIconBaseOffset = config.SpellIconBaseOffset
local GroupOutputVisible = effects.GroupOutputVisible
local SetAssistAlpha
local ForgetReminderEnchantPlaceholder
local function D()
    return Runtime._deps
end

local EMPTY_REMINDER_COLOR = {}

local function SetTextureDesaturated(tex, desaturated)
    if not (tex and tex.SetDesaturated) then return end
    tex:SetDesaturated(desaturated == true)
end

--- Temporary weapon enchants (oils, stones, poisons applied to a weapon) are
--- not auras: they never reach an AuraContainer's parse, groups or slots, so
--- no AuraButton can ever cover an enchant placeholder. Their state is plain
--- data though -- C_PaperDollInfo carries no secret annotation at all -- so
--- the placeholder can simply carry the state itself, in every kind of
--- content. Read on demand only; WEAPON_ENCHANT_CHANGED drives the refresh,
--- so nothing here polls.
local function ReminderEnchantInfo(slot)
    local invSlot = slot and slot.enchantInventorySlot
    local api = _G.C_PaperDollInfo
    if not (invSlot and type(api) == "table"
        and type(api.GetTemporaryEnchantmentInfo) == "function") then return nil end
    return api.GetTemporaryEnchantmentInfo(invSlot)
end

--- Every live enchant placeholder in the UI, keyed by the surface itself.
--- WEAPON_ENCHANT_CHANGED can fire mid-fight (an oil or imbue running out),
--- so the handler must touch exactly these one or two textures and nothing
--- else -- no frame walk, no slot scan.
local enchantPlaceholders, enchantDriver

local function EnsureEnchantPlaceholderDuration(frame)
    local duration = frame and frame._msufA3EnchantDuration
    if duration then return duration end
    local durationUtil = _G.C_DurationUtil
    local createDuration = durationUtil and durationUtil.CreateDuration
    if not (frame and type(createDuration) == "function") then return nil end
    duration = createDuration()
    if not (duration
        and type(duration.SetTimeFromEnd) == "function"
        and type(duration.SetTimeSpan) == "function") then
        return nil
    end
    frame._msufA3EnchantDuration = duration
    return duration
end

local function SyncEnchantPlaceholderCooldown(frame, slot, duration, enabled)
    local cooldown = frame and frame._msufA3EnchantCooldown
    if enabled ~= true or not (frame and duration) then
        if cooldown then
            if type(cooldown.Clear) == "function" then cooldown:Clear() end
            cooldown:Hide()
        end
        return false
    end
    if not cooldown then
        cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
        if not (cooldown and type(cooldown.SetCooldownFromDurationObject) == "function") then
            return false
        end
        cooldown:SetAllPoints(frame)
        if type(cooldown.SetDrawSwipe) == "function" then cooldown:SetDrawSwipe(true) end
        if type(cooldown.SetSwipeColor) == "function" then cooldown:SetSwipeColor(0, 0, 0, 0.58) end
        if type(cooldown.SetHideCountdownNumbers) == "function" then cooldown:SetHideCountdownNumbers(true) end
        if type(cooldown.SetDrawBling) == "function" then cooldown:SetDrawBling(false) end
        if type(cooldown.SetDrawEdge) == "function" then cooldown:SetDrawEdge(false) end
        if type(cooldown.SetFrameLevel) == "function" and type(frame.GetFrameLevel) == "function" then
            cooldown:SetFrameLevel((frame:GetFrameLevel() or 0) + 1)
        end
        frame._msufA3EnchantCooldown = cooldown
    end
    if type(cooldown.SetReverse) == "function" then
        cooldown:SetReverse(slot and slot.cooldownSwipeReverse == true)
    end
    local deps = D()
    local shape = deps and deps.IconShape
    local shapeKey = slot and slot.iconShape
    if cooldown._msufA3EnchantShape ~= shapeKey
        and type(shape) == "table" and type(shape.ApplyCooldownShape) == "function" then
        local mask = type(shape.EnsureMask) == "function" and shape.EnsureMask(frame, shapeKey) or nil
        shape.ApplyCooldownShape(cooldown, shapeKey, mask)
        cooldown._msufA3EnchantShape = shapeKey
    end
    cooldown:SetCooldownFromDurationObject(duration, true)
    cooldown:Show()
    return true
end

local function ClearEnchantPlaceholderDuration(frame, slot)
    if not frame then return false end
    local duration = frame._msufA3EnchantDuration
    if duration then duration:SetTimeSpan(0, 0) end
    local deps = D()
    if deps and type(deps.ConfigureStandaloneAuraDurationText) == "function" then
        deps.ConfigureStandaloneAuraDurationText(frame, frame._label, slot, duration, false)
    elseif frame._label then
        frame._label:SetText("")
        frame._label:Hide()
    end
    SyncEnchantPlaceholderCooldown(frame, slot, duration, false)
    frame._msufA3EnchantTimerVisible = nil
    frame._msufA3EnchantTimerID = nil
    frame._msufA3EnchantTimerRemainingMs = nil
    frame._msufA3EnchantTimerTotalSeconds = nil
    frame._msufA3EnchantTimerConfiguredSeconds = nil
    return false
end

--- Convert one event snapshot into a stable native Duration. Blizzard exposes
--- only remaining time, not the enchant's base duration, so mirror its manager:
--- combine its exact remaining value with the configured Oil/stone total and
--- preserve that denominator while the remaining value counts down. Text stays
--- exact after login while the swipe immediately reflects elapsed time.
local function SyncEnchantPlaceholderDuration(frame, slot, enchantInfo)
    local wantsText = slot and slot.showCooldownText == true
    local wantsSwipe = slot and slot.showCooldownSwipe == true
    local remainingMs = enchantInfo and enchantInfo.hasExpirationTime == true
        and tonumber(enchantInfo.remainingTimeMs) or nil
    if not (remainingMs and remainingMs > 0 and (wantsText or wantsSwipe)) then
        return ClearEnchantPlaceholderDuration(frame, slot)
    end

    local duration = EnsureEnchantPlaceholderDuration(frame)
    if not duration then return ClearEnchantPlaceholderDuration(frame, slot) end
    local enchantID = tonumber(enchantInfo.enchantID)
    local previousRemainingMs = frame._msufA3EnchantTimerRemainingMs
    local configuredSeconds = tonumber(slot.enchantDurationSeconds) or (60 * 60)
    local resetTotal = frame._msufA3EnchantTimerID ~= enchantID
        or previousRemainingMs == nil or remainingMs > previousRemainingMs
        or frame._msufA3EnchantTimerConfiguredSeconds ~= configuredSeconds
    local remainingSeconds = remainingMs / 1000
    local totalSeconds = frame._msufA3EnchantTimerTotalSeconds
    if resetTotal or not totalSeconds then
        -- Blizzard provides no original enchant duration. Use the configured
        -- Oil/stone duration as the denominator, but never make the total
        -- shorter than the readable remaining value.
        totalSeconds = math_max(configuredSeconds, remainingSeconds)
    end
    duration:SetTimeFromEnd(GetTime() + remainingSeconds, totalSeconds)
    frame._msufA3EnchantTimerID = enchantID
    frame._msufA3EnchantTimerRemainingMs = remainingMs
    frame._msufA3EnchantTimerTotalSeconds = totalSeconds
    frame._msufA3EnchantTimerConfiguredSeconds = configuredSeconds

    local deps = D()
    local textVisible = false
    if deps and type(deps.ConfigureStandaloneAuraDurationText) == "function" then
        textVisible = deps.ConfigureStandaloneAuraDurationText(
            frame, frame._label, slot, duration, wantsText) == true
    elseif frame._label then
        frame._label:SetText("")
        frame._label:Hide()
    end
    SyncEnchantPlaceholderCooldown(frame, slot, duration, wantsSwipe)
    frame._msufA3EnchantTimerVisible = textVisible or nil
    return textVisible
end

--- Lit while the enchant runs, dimmed to the reminder look while it is
--- missing. Same two states a covered aura placeholder produces, just driven
--- by a readable value instead of by occlusion.
---
--- Unchanged state paints nothing: an enchant event that does not affect this
--- slot costs one API read and one comparison, which is the whole in-combat
--- budget of the feature.
local function ApplyEnchantPlaceholderState(frame, slot, force)
    local tex = frame and frame._tex
    if not tex then return false end
    local enchantInfo = ReminderEnchantInfo(slot)
    local active = enchantInfo ~= nil
    -- Duration must refresh even when the boolean active state is unchanged:
    -- reapplying the same oil raises WEAPON_ENCHANT_CHANGED with active=true.
    SyncEnchantPlaceholderDuration(frame, slot, enchantInfo)
    if force ~= true and frame._msufA3EnchantActive == active then return active end
    frame._msufA3EnchantActive = active
    local tint = slot.reminderColor or EMPTY_REMINDER_COLOR
    if active then
        SetTextureDesaturated(tex, false)
        tex:SetVertexColor(1, 1, 1, 1)
    else
        SetTextureDesaturated(tex, slot.reminderDesaturate ~= false)
        tex:SetVertexColor(tint[1] or 1, tint[2] or 1, tint[3] or 1, slot.reminderAlpha or 0.45)
    end
    return active
end
Runtime._ApplyEnchantPlaceholderState = ApplyEnchantPlaceholderState

--- One shared, lazily created event owner. A profile without enchant
--- reminders never builds it and never registers the event at all.
local function TrackReminderEnchantPlaceholder(frame, slot)
    if not frame then return end
    enchantPlaceholders = enchantPlaceholders or {}
    enchantPlaceholders[frame] = slot
    if enchantDriver then return end
    enchantDriver = CreateFrame("Frame")
    enchantDriver:SetScript("OnEvent", function()
        for placeholder, tracked in pairs(enchantPlaceholders) do
            ApplyEnchantPlaceholderState(placeholder, tracked)
        end
    end)
    enchantDriver:RegisterEvent("WEAPON_ENCHANT_CHANGED")
    enchantDriver:RegisterEvent("WEAPON_SLOT_CHANGED")
    -- The enchant state survives a reload, but no change event announces it.
    enchantDriver:RegisterEvent("PLAYER_ENTERING_WORLD")
end

ForgetReminderEnchantPlaceholder = function(frame)
    if not frame then return end
    if enchantPlaceholders then enchantPlaceholders[frame] = nil end
    ClearEnchantPlaceholderDuration(frame, frame._msufA3ReminderSlot)
end

--- Mirror the slot's icon shape onto the reminder placeholder. Without the
--- same mask a circular or diamond aura icon leaves the placeholder's square
--- corners uncovered, which reads as a permanent artefact around a running
--- aura. A rectangular slot clears the mask again.
local function ApplyMissingShape(frame, tex, shape)
    local deps = D()
    local Shape = deps and deps.IconShape
    if type(Shape) ~= "table" or type(Shape.ApplyMask) ~= "function" then return end
    local mask = shape and type(Shape.EnsureMask) == "function" and Shape.EnsureMask(frame, shape) or nil
    if mask then Shape.ApplyMask(tex, mask) else Shape.ClearMask(tex) end
end

local function EnsureMissingFrame(parentFrame, slot)
    if not (parentFrame and slot and slot.showWhenMissing == true) then return nil end
    parentFrame._msufA3SpellIndicatorMissingFrames = parentFrame._msufA3SpellIndicatorMissingFrames or {}
    local frame = parentFrame._msufA3SpellIndicatorMissingFrames[slot.slotKey]
    if not frame then
        frame = CreateFrame("Frame", nil, parentFrame._msufHealthVisualRoot or parentFrame)
        frame._tex = frame:CreateTexture(nil, "OVERLAY")
        frame._tex:SetAllPoints(frame)
        frame._label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame._label:SetPoint("CENTER", frame, "CENTER", 0, 0)
        parentFrame._msufA3SpellIndicatorMissingFrames[slot.slotKey] = frame
    end
    frame._msufA3IdentityCandidateMode = Runtime.IdentityCandidateMode(slot)
    SetAssistAlpha(frame, GroupOutputVisible(parentFrame,
        frame._msufA3IdentityCandidateMode or "neutral"), 1)
    return frame
end

local function SyncMissingFrame(parentFrame, slot, button, ownerContainer)
    local frame = EnsureMissingFrame(parentFrame, slot)
    if not frame then
        local missing = parentFrame and parentFrame._msufA3SpellIndicatorMissingFrames and parentFrame._msufA3SpellIndicatorMissingFrames[slot and slot.slotKey]
        if missing then missing:Hide() end
        return
    end
    frame._msufA3MissingOwnerContainer = ownerContainer
    frame._msufA3ReminderSlot = slot
    frame:ClearAllPoints()
    frame:SetSize(slot.width or slot.size or 1, slot.height or slot.size or 1)
    frame:SetPoint(slot.anchor or "TOPLEFT", parentFrame, slot.anchor or "TOPLEFT", slot.x or 0, slot.y or 0)
    SyncFrameStrata(frame, ResolveFrameStrata(parentFrame, slot.strata))
    frame:SetFrameLevel(FrameLayers.ElementLevel and FrameLayers.ElementLevel(slot.layer, 9, 0)
        or ((parentFrame:GetFrameLevel() or 0) + SpellIconBaseOffset(parentFrame) + (slot.layer or 9) - 1))
    local tex = frame._tex
    local label = frame._label
    local alpha = slot.reminderAlpha or 0.45
    local tint = slot.reminderColor or EMPTY_REMINDER_COLOR
    local r, g, b = tint[1] or 1, tint[2] or 1, tint[3] or 1
    if slot.visual == "square" or slot.visual == "bar" then
        ApplyMissingShape(frame, tex, nil)
        tex:SetTexture("Interface\\Buttons\\WHITE8X8")
        tex:SetTexCoord(0, 1, 0, 1)
        SetTextureDesaturated(tex, false)
        tex:SetVertexColor(r, g, b, alpha)
        tex:Show()
        label:Hide()
    elseif slot.visual == "number" then
        ApplyMissingShape(frame, tex, nil)
        tex:Hide()
        label:SetText("0")
        label:SetTextColor(r, g, b, alpha)
        label:Show()
    elseif slot.visual == "icon" then
        -- The placeholder must occupy the AuraButton's rect exactly and carry
        -- the same icon shape: a live aura covers it pixel for pixel, so any
        -- size or mask mismatch would leak a bright rim around a running aura.
        ApplyMissingShape(frame, tex, slot.iconShape)
        tex:SetTexture(slot.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
        -- Match the live AuraButton crop exactly. PrepareAuraButton derives
        -- the icon TexCoord from the same zoom, so a fixed crop here would
        -- reframe the art the moment the aura came up.
        local inset = (1 - (100 / ClampNumber(slot.iconZoom, 100, 100, 200))) * 0.5
        tex:SetTexCoord(inset, 1 - inset, inset, 1 - inset)
        if slot.enchantSlot then
            -- No AuraButton can ever cover an enchant placeholder, so the icon
            -- carries both states itself and joins the shared event owner.
            TrackReminderEnchantPlaceholder(frame, slot)
            ApplyEnchantPlaceholderState(frame, slot, true)
        else
            ForgetReminderEnchantPlaceholder(frame)
            SetTextureDesaturated(tex, slot.reminderDesaturate ~= false)
            tex:SetVertexColor(r, g, b, alpha)
        end
        tex:Show()
        if not (slot.enchantSlot and frame._msufA3EnchantTimerVisible == true) then label:Hide() end
    else
        ApplyMissingShape(frame, tex, nil)
        tex:Hide()
        label:Hide()
    end
    -- Deliberately NOT gated on `button`: a slot's AuraButton is allocated
    -- up front and merely hidden while its aura is absent, so button ~= nil
    -- says nothing about the aura. The placeholder stays visible and lets the
    -- native button occlude it.
    frame:SetShown(slot.showWhenMissing == true)
end


local function Install(assistAlpha)
    SetAssistAlpha = assistAlpha
end

return {
    SyncMissingFrame = SyncMissingFrame,
    ForgetReminderEnchantPlaceholder = ForgetReminderEnchantPlaceholder,
    Install = Install,
}
end
