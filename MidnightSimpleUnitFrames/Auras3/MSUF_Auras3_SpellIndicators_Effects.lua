--- Auras3/SpellIndicator_Effects: frame/icon effects, output gates and retirement of owned effect surfaces.
--- Registered at load time; the original entrypoint owns initialization order.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}
local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
A3.SpellIndicatorModules = A3.SpellIndicatorModules or {}
A3.SpellIndicatorModules.Effects = function(config)
local type, tostring, tonumber, pairs = type, tostring, tonumber, pairs
local math_min, math_max = math.min, math.max
local FrameLayers = MSUF.UF and MSUF.UF.Layers or {}
local SPELL_FRAME_EFFECT_BASE_OFFSET = tonumber(FrameLayers.SPELL_FRAME_EFFECT_BASE_OFFSET) or 1
local CreateFrame = _G.CreateFrame
local InCombat = _G.InCombatLockdown or function() return false end
local issecretvalue = _G.issecretvalue or function(_) return false end
local ICON_ALERT_TEXTURE = [[Interface\SpellActivationOverlay\IconAlert]]
local ICON_ALERT_ANTS_TEXTURE = [[Interface\SpellActivationOverlay\IconAlertAnts]]
local FRAME_GLOW_TEXTURE = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames")
    .. "\\Media\\Borders\\frame_glow_radial.tga"
local Runtime = A3.SpellIndicators
local SetAssistAlpha
local Round = config.Round
local ClampNumber = config.ClampNumber
local Clamp01 = config.Clamp01
local ResolveFrameStrata = config.ResolveFrameStrata
local SyncFrameStrata = config.SyncFrameStrata
local SpellIconBaseOffset = config.SpellIconBaseOffset
local NormalizeFrameEffect = config.NormalizeFrameEffect
local function SpellIndicatorHealthBar(parentFrame)
    return parentFrame and (parentFrame.hpBar or parentFrame.Health or parentFrame.health)
end

local function SpellIndicatorHealthFill(parentFrame)
    local bar = SpellIndicatorHealthBar(parentFrame)
    if not (bar and bar.GetStatusBarTexture) then return nil end
    return bar:GetStatusBarTexture()
end

local function EnsureEffectRoot(button, parentFrame)
    if not (button and parentFrame) then return nil end
    local target = SpellIndicatorHealthBar(parentFrame)
    if not target then return nil end
    local root = button._msufA3SpellIndicatorEffectRoot
    if not root then
        -- Live effects stay below the native AuraSlot so Blizzard's secret
        -- visibility is inherited. The AuraSlot itself sits at the universal
        -- base; this child's absolute level therefore remains independent from
        -- the separately levelled icon host. Menu previews use a neutral owner.
        root = CreateFrame("Frame", nil, button)
        root:EnableMouse(false)
        root:SetAllPoints(target)
        button._msufA3SpellIndicatorEffectRoot = root
    end
    return root
end

local function EnsureTint(button, parentFrame)
    local root = EnsureEffectRoot(button, parentFrame)
    if not root then return nil end
    local tint = button._msufA3SpellIndicatorHealthTint
    if not tint then
        tint = root:CreateTexture(nil, "OVERLAY")
        tint:SetTexture("Interface\\Buttons\\WHITE8X8")
        button._msufA3SpellIndicatorHealthTint = tint
    end
    return tint
end

local function EnsureEdges(button, parentFrame)
    local root = EnsureEffectRoot(button, parentFrame)
    if not root then return nil end
    local edges = button._msufA3SpellIndicatorEdges
    if not edges then
        edges = {}
        for i = 1, 4 do
            local tex = root:CreateTexture(nil, "OVERLAY")
            tex:SetTexture("Interface\\Buttons\\WHITE8X8")
            edges[i] = tex
        end
        button._msufA3SpellIndicatorEdges = edges
    end
    return edges
end

-- Genuine animated action-button glow. The 22-frame ants animation is driven
-- by a C-side AnimationGroup, so active indicators add no Lua OnUpdate work.
-- Only the square icon effect uses this renderer; the full-frame glow has its
-- own aspect-ratio-safe halo below. Because the roots are children of the
-- native AuraSlot button, Blizzard's secret visibility is inherited without
-- reading or branching on it in addon Lua.
local function EnsureAnimatedGlow(owner)
    if not owner then return nil end
    local data = owner._msufA3AnimatedGlow
    if data then return data end

    local halo = owner:CreateTexture(nil, "OVERLAY", nil, 6)
    halo:SetTexture(ICON_ALERT_TEXTURE)
    halo:SetTexCoord(0.0078125, 0.5078125, 0.27734375, 0.52734375)
    halo:SetBlendMode("ADD")

    local ants = owner:CreateTexture(nil, "OVERLAY", nil, 7)
    ants:SetTexture(ICON_ALERT_ANTS_TEXTURE)
    ants:SetBlendMode("ADD")
    local animation = ants:CreateAnimationGroup()
    animation:SetLooping("REPEAT")
    local flipbook = animation:CreateAnimation("FlipBook")
    flipbook:SetFlipBookRows(5)
    flipbook:SetFlipBookColumns(5)
    flipbook:SetFlipBookFrames(22)
    flipbook:SetFlipBookFrameWidth(48)
    flipbook:SetFlipBookFrameHeight(48)
    flipbook:SetDuration(0.37)

    data = { halo = halo, ants = ants, animation = animation }
    owner._msufA3AnimatedGlow = data
    return data
end

local function AnchorAnimatedGlow(data, target, padding)
    if not (data and target) or (data.target == target and data.padding == padding) then return end
    data.target = target
    data.padding = padding
    local haloPadding = padding * 1.55
    data.halo:ClearAllPoints()
    data.halo:SetPoint("TOPLEFT", target, "TOPLEFT", -haloPadding, haloPadding)
    data.halo:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", haloPadding, -haloPadding)
    data.ants:ClearAllPoints()
    data.ants:SetPoint("TOPLEFT", target, "TOPLEFT", -padding, padding)
    data.ants:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", padding, -padding)
end

local function StartAnimatedGlow(owner, target, r, g, b, a, padding)
    local data = EnsureAnimatedGlow(owner)
    if not data then return false end
    padding = ClampNumber(padding, 3, 1, 24)
    AnchorAnimatedGlow(data, target or owner, padding)
    if data.r ~= r or data.g ~= g or data.b ~= b or data.a ~= a then
        data.r, data.g, data.b, data.a = r, g, b, a
        data.halo:SetDesaturated(true)
        data.ants:SetDesaturated(true)
        data.halo:SetVertexColor(r, g, b, a)
        data.ants:SetVertexColor(r, g, b, a)
    end
    data.active = true
    data.halo:Show()
    data.ants:Show()
    if not data.animation:IsPlaying() then data.animation:Play() end
    return true
end

local function StopAnimatedGlow(owner)
    local data = owner and owner._msufA3AnimatedGlow
    if not data then return end
    data.active = nil
    if data.animation:IsPlaying() then data.animation:Stop() end
    data.halo:Hide()
    data.ants:Hide()
end

-- Full-frame glow: a soft halo built from eight static slices of one radial
-- gradient (4 corner quarters + 4 center-cross edge strips). Corners stay
-- round at any bar aspect ratio instead of smearing Blizzard's square
-- action-button alert art across a wide health bar, and there is no
-- animation, so an active glow costs zero Lua and zero C-side ticks.
local FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH = 31 / 64, 33 / 64
-- The glow rectangle sits this many pixels inside the bar edge, so the bright
-- core overlaps the bar's own border art and the halo reads as attached to
-- the frame instead of floating next to it.
local FRAME_GLOW_INSET = 2

local function EnsureFrameGlow(owner)
    if not owner then return nil end
    local data = owner._msufA3FrameGlow
    if data then return data end
    local pieces = {}
    for i = 1, 8 do
        local tex = owner:CreateTexture(nil, "OVERLAY", nil, 6)
        tex:SetTexture(FRAME_GLOW_TEXTURE)
        pieces[i] = tex
    end
    pieces[1]:SetTexCoord(0, 0.5, 0, 0.5)                                   -- top-left corner
    pieces[2]:SetTexCoord(0.5, 1, 0, 0.5)                                   -- top-right corner
    pieces[3]:SetTexCoord(0, 0.5, 0.5, 1)                                   -- bottom-left corner
    pieces[4]:SetTexCoord(0.5, 1, 0.5, 1)                                   -- bottom-right corner
    pieces[5]:SetTexCoord(FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH, 0, 0.5) -- top edge
    pieces[6]:SetTexCoord(FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH, 0.5, 1) -- bottom edge
    pieces[7]:SetTexCoord(0, 0.5, FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH) -- left edge
    pieces[8]:SetTexCoord(0.5, 1, FRAME_GLOW_EDGE_LOW, FRAME_GLOW_EDGE_HIGH) -- right edge
    data = { pieces = pieces }
    owner._msufA3FrameGlow = data
    return data
end

local function AnchorFrameGlow(data, target, extent)
    if not (data and target) or (data.target == target and data.extent == extent) then return end
    data.target = target
    data.extent = extent
    local pieces = data.pieces
    local inset = FRAME_GLOW_INSET
    for i = 1, 8 do pieces[i]:ClearAllPoints() end
    pieces[1]:SetPoint("BOTTOMRIGHT", target, "TOPLEFT", inset, -inset)
    pieces[2]:SetPoint("BOTTOMLEFT", target, "TOPRIGHT", -inset, -inset)
    pieces[3]:SetPoint("TOPRIGHT", target, "BOTTOMLEFT", inset, inset)
    pieces[4]:SetPoint("TOPLEFT", target, "BOTTOMRIGHT", -inset, inset)
    for i = 1, 4 do pieces[i]:SetSize(extent, extent) end
    pieces[5]:SetPoint("BOTTOMLEFT", target, "TOPLEFT", inset, -inset)
    pieces[5]:SetPoint("BOTTOMRIGHT", target, "TOPRIGHT", -inset, -inset)
    pieces[5]:SetHeight(extent)
    pieces[6]:SetPoint("TOPLEFT", target, "BOTTOMLEFT", inset, inset)
    pieces[6]:SetPoint("TOPRIGHT", target, "BOTTOMRIGHT", -inset, inset)
    pieces[6]:SetHeight(extent)
    pieces[7]:SetPoint("TOPRIGHT", target, "TOPLEFT", inset, -inset)
    pieces[7]:SetPoint("BOTTOMRIGHT", target, "BOTTOMLEFT", inset, inset)
    pieces[7]:SetWidth(extent)
    pieces[8]:SetPoint("TOPLEFT", target, "TOPRIGHT", -inset, -inset)
    pieces[8]:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", -inset, inset)
    pieces[8]:SetWidth(extent)
end

local function StartFrameGlow(owner, target, r, g, b, a, extent)
    local data = EnsureFrameGlow(owner)
    if not data then return false end
    extent = ClampNumber(extent, 8, 4, 48)
    AnchorFrameGlow(data, target or owner, extent)
    local pieces = data.pieces
    if data.r ~= r or data.g ~= g or data.b ~= b or data.a ~= a then
        data.r, data.g, data.b, data.a = r, g, b, a
        for i = 1, 8 do pieces[i]:SetVertexColor(r, g, b, a) end
    end
    data.active = true
    for i = 1, 8 do pieces[i]:Show() end
    return true
end

local function StopFrameGlow(owner)
    local data = owner and owner._msufA3FrameGlow
    if not (data and data.active) then return end
    data.active = nil
    local pieces = data.pieces
    for i = 1, 8 do pieces[i]:Hide() end
end

local function NameFontString(parentFrame)
    if not parentFrame then return nil end
    return parentFrame.Name
        or parentFrame.name
        or parentFrame.NameText
        or parentFrame.nameText
        or parentFrame._nameFS
end

local function UnregisterNameOverlay(button)
    local overlay = button and button._msufA3SpellIndicatorNameOverlay
    if overlay then
        overlay._msufA3NameSource = nil
        overlay:Hide()
    end
end

local function SyncNameOverlayFont(overlay, source)
    if not (overlay and source) then return end
    local path, size, flags = source:GetFont()
    if path and size then
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        local applyResolved = _G.MSUF_ApplyResolvedFont
        if type(applyResolved) == "function" then
            applyResolved(overlay, path, size, flags, general and general.fontKey)
        else
            local ok, applied = pcall(overlay.SetFont, overlay, path, size, flags)
            if (not ok or applied == false) and type(_G.MSUF_MarkFontApplyFailed) == "function" then
                _G.MSUF_MarkFontApplyFailed()
            end
        end
    end
    if source.GetJustifyH then overlay:SetJustifyH(source:GetJustifyH()) end
    if source.GetJustifyV then overlay:SetJustifyV(source:GetJustifyV()) end
    if source.GetShadowColor then overlay:SetShadowColor(source:GetShadowColor()) end
    if source.GetShadowOffset then overlay:SetShadowOffset(source:GetShadowOffset()) end
    overlay:ClearAllPoints()
    overlay:SetAllPoints(source)
    -- GetText can itself be secret on restricted units. It is forwarded as an
    -- opaque value only; no comparison or branch is performed on it.
    overlay:SetText(source:GetText())
end

local function RegisterNameOverlay(button, parentFrame, root)
    local source = NameFontString(parentFrame)
    if not (button and source and root) then return nil end
    local overlay = button._msufA3SpellIndicatorNameOverlay
    if not overlay then
        overlay = root:CreateFontString(nil, "OVERLAY")
        button._msufA3SpellIndicatorNameOverlay = overlay
    end
    if overlay._msufA3NameSource ~= source then
        UnregisterNameOverlay(button)
        overlay._msufA3NameSource = source
    end
    -- PTR 5 applies AuraButton access restrictions immediately after this
    -- initializer returns. Do not retain a SetText hook that would later write
    -- to this descendant while aura data is secret.
    SyncNameOverlayFont(overlay, source)
    return overlay
end

local function StopPulse(root)
    local pulse = root and root._msufA3SpellIndicatorPulse
    if pulse and pulse:IsPlaying() then pulse:Stop() end
    if root then root:SetAlpha(1) end
end

local function StartPulse(root)
    if not root then return end
    local pulse = root._msufA3SpellIndicatorPulse
    if not pulse then
        pulse = root:CreateAnimationGroup()
        local alpha = pulse:CreateAnimation("Alpha")
        alpha:SetFromAlpha(0.45)
        alpha:SetToAlpha(1)
        alpha:SetDuration(0.7)
        if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
        pulse:SetLooping("BOUNCE")
        root._msufA3SpellIndicatorPulse = pulse
    end
    if not pulse:IsPlaying() then pulse:Play() end
end

local function HideButtonFrameEffect(button)
    if not button then return end
    button._msufA3FrameEffectApplied = nil
    local root = button._msufA3SpellIndicatorEffectRoot
    if root then
        StopPulse(root)
        StopAnimatedGlow(root)
        StopFrameGlow(root)
        root:Hide()
    end
    UnregisterNameOverlay(button)
end

local function HideButtonIconEffect(button)
    if not button then return end
    local root = button._msufA3SpellIndicatorIconEffectRoot
    if root then
        StopAnimatedGlow(root)
        root:SetAlpha(1)
        root:Hide()
    end
end

function Runtime.HideFrameEffects(parentFrame)
    if not parentFrame then return end
    -- The owning native container is hidden before this cleanup. Native
    -- AuraButtons may be forbidden, so do not touch them from Lua here.
    parentFrame._msufA3SpellIndicatorEffectButtons = nil
    -- Clean up objects created by the pre-native implementation, if a profile
    -- was hot-reloaded from an older build in the same session.
    if parentFrame._msufA3SpellIndicatorEffectRoot then parentFrame._msufA3SpellIndicatorEffectRoot:Hide() end
end

function Runtime.HideIconEffects(parentFrame)
    if not parentFrame then return end
    parentFrame._msufA3SpellIndicatorIconEffectButtons = nil
end

local function EnsurePandemicPulse(root)
    if not root then return nil end
    local pulse = root._msufA3PandemicActivePulse
    if pulse then return pulse end
    pulse = root:CreateAnimationGroup()
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(0.45)
    alpha:SetToAlpha(1)
    alpha:SetDuration(0.7)
    if alpha.SetSmoothing then alpha:SetSmoothing("IN_OUT") end
    pulse:SetLooping("BOUNCE")
    root._msufA3PandemicActivePulse = pulse
    return pulse
end

local ForgetReminderEnchantPlaceholder

function Runtime.HideMissing(parentFrame)
    if not parentFrame then return end
    local missing = parentFrame._msufA3SpellIndicatorMissingFrames
    if missing then
        for _, frame in pairs(missing) do
            if frame then
                ForgetReminderEnchantPlaceholder(frame)
                frame:Hide()
            end
        end
    end
end

--- Retire every click-to-cast button on this frame regardless of root. The
--- buttons are protected, so combat leaves them in place; they are children
--- of the UnitFrame and follow its visibility until the next apply.
function Runtime.HideReminderCastButtons(parentFrame)
    local store = parentFrame and parentFrame._msufA3ReminderCastButtons
    if not store then return false end
    if InCombat() then return true end
    for _, button in pairs(store) do
        button._msufA3CastOwnerKey = nil
        button:Hide()
    end
    parentFrame._msufA3ReminderCastSignatures = nil
    return false
end

function Runtime.HideAll(parentFrame)
    Runtime.HideFrameEffects(parentFrame)
    Runtime.HideIconEffects(parentFrame)
    Runtime.HideMissing(parentFrame)
    return Runtime.HideReminderCastButtons(parentFrame)
end

function Runtime.HideRootMissing(parentFrame, slotRoot, ownerContainer)
    local missing = parentFrame and parentFrame._msufA3SpellIndicatorMissingFrames
    local slots = slotRoot and slotRoot.slots
    if not (missing and type(slots) == "table") then return false end
    local any = false
    for i = 1, #slots do
        local frame = missing[slots[i] and slots[i].slotKey]
        if frame and (ownerContainer == nil
            or frame._msufA3MissingOwnerContainer == ownerContainer) then
            frame:Hide()
            any = true
        end
    end
    return any
end

--- Buff Reminder click-to-cast.
---
--- One SecureActionButton per reminder slot, written once and then left
--- alone: no OnUpdate, no event registration and no aura read. A click just
--- casts the spell the slot was configured with, which is why it keeps
--- working while the aura is up (re-applying a poison or flask) as well as
--- while it is missing.
---
--- Everything here is protected-frame work, so it runs strictly out of
--- combat; the caller re-queues an apply for PLAYER_REGEN_ENABLED instead.
--- The buttons are children of the UnitFrame, never of an AuraButton: that
--- tree is access-restricted while auras are secret and forbids scripts.
--- The cast button covers the AuraButton, so it also swallows the mouse
--- motion that would raise Blizzard's aura tooltip. Show the slot's own
--- spell instead -- that is plain catalog data, readable under every secret
--- restriction, and it names the very spell the click will cast. Scripts run
--- on hover only; nothing here is registered, polled or timed.
local function ReminderCastButtonOnEnter(self)
    local tooltip = _G.GameTooltip
    if not (self._msufA3CastTooltip and tooltip) then return end
    local itemID = self._msufA3CastItemID
    if itemID and type(tooltip.SetItemByID) == "function" then
        tooltip:SetOwner(self, "ANCHOR_RIGHT")
        tooltip:SetItemByID(itemID)
        tooltip:Show()
        return
    end
    local spellID = self._msufA3CastSpellID
    if not (spellID and type(tooltip.SetSpellByID) == "function") then return end
    tooltip:SetOwner(self, "ANCHOR_RIGHT")
    tooltip:SetSpellByID(spellID)
    tooltip:Show()
end

local function ReminderCastButtonOnLeave()
    local tooltip = _G.GameTooltip
    if tooltip and tooltip.Hide then tooltip:Hide() end
end

local function EnsureReminderCastButton(store, parentFrame, slot)
    local button = store[slot.slotKey]
    if not button then
        button = CreateFrame("Button", nil, parentFrame, "SecureActionButtonTemplate")
        -- Both edges, exactly like Blizzard's action buttons: the secure
        -- handler itself decides which one fires from ActionButtonUseKeyDown,
        -- so registering only one would drop the click for half the users.
        button:RegisterForClicks("AnyUp", "AnyDown")
        button:SetScript("OnEnter", ReminderCastButtonOnEnter)
        button:SetScript("OnLeave", ReminderCastButtonOnLeave)
        store[slot.slotKey] = button
    end
    return button
end

--- Returns true when combat blocked the work and the caller must retry.
function Runtime.SyncReminderCastButtons(parentFrame, slotRoot)
    if not (parentFrame and type(slotRoot) == "table") then return false end
    local rootKey = slotRoot.rootKey or "SpellIndicators"
    local signatures = parentFrame._msufA3ReminderCastSignatures
    local wanted = slotRoot._msufA3StructuralSignature
    -- Hot-path exit. The root's structural signature already folds every
    -- slot's spell, unit, anchor, offset and size, so one string compare
    -- decides whether any secure work is needed at all.
    if signatures and signatures[rootKey] == wanted then return false end
    local store = parentFrame._msufA3ReminderCastButtons
    local slots = type(slotRoot.slots) == "table" and slotRoot.slots or nil
    local wantsCast = false
    if slots then
        for i = 1, #slots do
            local candidate = slots[i]
            if candidate and (candidate.castSpellID or candidate.castItem) then
                wantsCast = true
                break
            end
        end
    end
    if not (store or wantsCast) then
        signatures = signatures or {}
        parentFrame._msufA3ReminderCastSignatures = signatures
        signatures[rootKey] = wanted
        return false
    end
    if InCombat() then return true end
    if not store then
        store = {}
        parentFrame._msufA3ReminderCastButtons = store
    end
    -- Mark this root's current buttons for retirement, then un-mark the ones
    -- the new slot list still wants. A shrunk whitelist must not leave an
    -- invisible click target sitting on the frame.
    for _, button in pairs(store) do
        if button._msufA3CastOwnerKey == rootKey then button._msufA3CastRetire = true end
    end
    for i = 1, (slots and #slots or 0) do
        local slot = slots[i]
        local spellID = slot and slot.castSpellID
        local castItem = slot and slot.castItem
        if spellID or castItem then
            local button = EnsureReminderCastButton(store, parentFrame, slot)
            button._msufA3CastRetire = nil
            button._msufA3CastOwnerKey = rootKey
            button:ClearAllPoints()
            button:SetSize(slot.width or slot.size or 1, slot.height or slot.size or 1)
            button:SetPoint(slot.anchor or "TOPLEFT", parentFrame, slot.anchor or "TOPLEFT",
                slot.x or 0, slot.y or 0)
            SyncFrameStrata(button, ResolveFrameStrata(parentFrame, slot.strata))
            -- Detail 2 sits one step above the AuraButton (1) and the
            -- placeholder (0) inside the same 32-wide Layer band, so the
            -- click target is always the topmost of the three.
            button:SetFrameLevel(FrameLayers.ElementLevel and FrameLayers.ElementLevel(slot.layer, 9, 2)
                or ((parentFrame:GetFrameLevel() or 0) + SpellIconBaseOffset(parentFrame) + (slot.layer or 9) + 1))
            -- Exactly one action type may be live on a secure button, so the
            -- unused attribute is cleared rather than left behind.
            button:SetAttribute("type", castItem and "item" or "spell")
            button:SetAttribute("spell", not castItem and spellID or nil)
            button:SetAttribute("item", castItem)
            button:SetAttribute("unit", slot.castUnit)
            button._msufA3CastSpellID = not castItem and spellID or nil
            button._msufA3CastItemID = slot.castItemID
            button._msufA3CastTooltip = slot.showTooltip ~= false
            button:Show()
        end
    end
    for _, button in pairs(store) do
        if button._msufA3CastRetire then
            button._msufA3CastRetire = nil
            button._msufA3CastOwnerKey = nil
            button:Hide()
        end
    end
    signatures = signatures or {}
    parentFrame._msufA3ReminderCastSignatures = signatures
    signatures[rootKey] = wanted
    return false
end

--- Retire every addon-owned surface belonging to one Spell Indicator root:
--- the reminder placeholders (keyed by their owning container) and the
--- click-to-cast buttons (keyed by root). A3._HideLane alone cannot reach
--- either -- both are UnitFrame siblings, not container children -- so a
--- root that stops existing while the frame stays visible would otherwise
--- leave a dimmed icon and an invisible click target behind.
---
--- Returns `deferred`: true when combat blocked the protected Hide and the
--- caller has to re-run this after PLAYER_REGEN_ENABLED.
function Runtime.RetireRoot(parentFrame, rootKey, ownerContainer)
    if not parentFrame then return false end
    local missing = parentFrame._msufA3SpellIndicatorMissingFrames
    if missing and ownerContainer then
        for _, frame in pairs(missing) do
            if frame._msufA3MissingOwnerContainer == ownerContainer then
                ForgetReminderEnchantPlaceholder(frame)
                frame:Hide()
            end
        end
    end
    local store = parentFrame._msufA3ReminderCastButtons
    if not store then return false end
    rootKey = rootKey or "SpellIndicators"
    local pending = false
    for _, button in pairs(store) do
        if button._msufA3CastOwnerKey == rootKey then
            if InCombat() then
                pending = true
            else
                button._msufA3CastOwnerKey = nil
                button:Hide()
            end
        end
    end
    local signatures = parentFrame._msufA3ReminderCastSignatures
    if signatures and not pending then signatures[rootKey] = nil end
    return pending
end

local function LayoutEdges(button, parentFrame, target, effect)
    local edges = EnsureEdges(button, parentFrame)
    if not edges then return end
    local color = effect and effect.color or {}
    local r, g, b = Clamp01(color[1], 1), Clamp01(color[2], 1), Clamp01(color[3], 1)
    local a = Clamp01(color[4], 1)
    local thickness = ClampNumber(effect and effect.thickness, effect and effect.type == "glow" and 3 or 2, 1, 16)
    if effect and (effect.type == "glow" or effect.type == "pulse") then
        thickness = math_max(thickness, 3)
        a = math_min(1, a * 0.85)
    end
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    top:ClearAllPoints()
    top:SetPoint("TOPLEFT", target, "TOPLEFT", -thickness, thickness)
    top:SetPoint("TOPRIGHT", target, "TOPRIGHT", thickness, thickness)
    top:SetHeight(thickness)
    bottom:ClearAllPoints()
    bottom:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", -thickness, -thickness)
    bottom:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", thickness, -thickness)
    bottom:SetHeight(thickness)
    left:ClearAllPoints()
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
    left:SetWidth(thickness)
    right:ClearAllPoints()
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    right:SetWidth(thickness)
    for i = 1, 4 do
        local edge = edges[i]
        if edge.SetBlendMode then edge:SetBlendMode(effect and (effect.type == "glow" or effect.type == "pulse") and "ADD" or "BLEND") end
        edge:SetVertexColor(r, g, b, a)
        edge:Show()
    end
    local rounded = _G.MSUF_RoundedUF_OnSpellIndicatorEdge
    if rounded and rounded(button, parentFrame, target, true, thickness, r, g, b, a,
        effect and effect.type == "pulse" and "ADD" or "BLEND") then
        for i = 1, 4 do edges[i]:Hide() end
    end
end

local function HideEffectRegions(button)
    local tint = button and button._msufA3SpellIndicatorHealthTint
    if tint then tint:Hide() end
    local edges = button and button._msufA3SpellIndicatorEdges
    if edges then
        for i = 1, #edges do
            if edges[i] then edges[i]:Hide() end
        end
    end
    local rounded = _G.MSUF_RoundedUF_OnSpellIndicatorEdge
    if rounded then rounded(button, nil, nil, false) end
    StopAnimatedGlow(button and button._msufA3SpellIndicatorEffectRoot)
    StopFrameGlow(button and button._msufA3SpellIndicatorEffectRoot)
    UnregisterNameOverlay(button)
end

--- Absolute frame level of one full-frame effect surface on the shared 0..30
--- scale. Kept as its own function because the live apply and the post-sync
--- re-stamp below must never compute a different number for the same effect.
local function FrameEffectLevel(effect, kind, parentFrame, healthBar)
    -- Saved priorities use 1 as the strongest effect.
    local priority = effect.priority or 5
    -- Layer is a cold-compiled 0..30 local offset. Zero preserves the
    -- established priority band exactly; no SavedVariables reads occur here.
    local layer = effect.layer or 0
    local targetOwner = healthBar
    if kind == "namecolor" then
        local nameSource = NameFontString(parentFrame)
        targetOwner = nameSource and nameSource.GetParent and nameSource:GetParent() or parentFrame
    end
    return FrameLayers.AuraEffectLevel and FrameLayers.AuraEffectLevel(layer, priority, targetOwner)
        or FrameLayers.ElementLevel and FrameLayers.ElementLevel(layer, 0, 11 - priority)
        or ((parentFrame:GetFrameLevel() or 0) + SPELL_FRAME_EFFECT_BASE_OFFSET + (11 - priority) + layer)
end

local function ForgetButtonFrameEffect(button, parentFrame)
    local buttons = parentFrame and parentFrame._msufA3SpellIndicatorEffectButtons
    if buttons then buttons[button] = nil end
    HideButtonFrameEffect(button)
    return false
end

local function ApplyButtonFrameEffect(button, slot, parentFrame, nativePandemic)
    if not (button and slot and parentFrame) then return false end
    local effect = slot.frameEffect
    if type(effect) ~= "table" then
        return ForgetButtonFrameEffect(button, parentFrame)
    end
    local kind = tostring(effect.type or "none"):lower()
    if kind ~= "healthtint" and kind ~= "border" and kind ~= "glow" and kind ~= "pulse" and kind ~= "namecolor" then
        return ForgetButtonFrameEffect(button, parentFrame)
    end

    -- Visible frame effects must follow the C-side StatusBar fill. The owning
    -- frame stays on the stable health-bar rectangle; only its textures/edges
    -- inherit the current-health geometry, so no UNIT_HEALTH Lua work is added.
    local target = SpellIndicatorHealthFill(parentFrame)
    local root = target and EnsureEffectRoot(button, parentFrame)
    local healthBar = SpellIndicatorHealthBar(parentFrame)
    if not (root and healthBar) then
        HideButtonFrameEffect(button)
        return false
    end
    root:ClearAllPoints()
    root:SetAllPoints(healthBar)
    SyncFrameStrata(root, ResolveFrameStrata(parentFrame, effect.strata or slot.strata))
    if root.SetFrameLevel then
        root:SetFrameLevel(FrameEffectLevel(effect, kind, parentFrame, healthBar))
    end
    -- Retained so Runtime.RefreshFrameEffects can recompute this exact level
    -- after the owning native container has moved (see that function).
    button._msufA3FrameEffectApplied = effect
    StopPulse(root)
    HideEffectRegions(button)

    local color = effect.color or {}
    local r = Clamp01(color[1], 1)
    local g = Clamp01(color[2], 1)
    local b = Clamp01(color[3], 1)
    local a = Clamp01(color[4], 1)
    if kind == "healthtint" then
        local tint = EnsureTint(button, parentFrame)
        tint:ClearAllPoints()
        tint:SetAllPoints(target)
        if tint.SetBlendMode then tint:SetBlendMode("BLEND") end
        tint:SetVertexColor(r, g, b, Clamp01(effect.tintAlpha, a > 0 and a or 0.20))
        tint:Show()
    elseif kind == "namecolor" then
        local name = RegisterNameOverlay(button, parentFrame, root)
        if name then
            name:SetTextColor(r, g, b, a)
            name:Show()
        end
    elseif kind == "glow" then
        -- The +0.16 alpha boost matches the Menu2 effect preview; the halo's
        -- soft falloff otherwise reads dimmer than the same alpha on a solid
        -- border. Extent compensates for the inset overlap into the bar.
        StartFrameGlow(root, target, r, g, b, math_min(1, a + 0.16),
            Round((ClampNumber(effect.thickness, 3, 1, 16) + 2) * 2.5) + FRAME_GLOW_INSET)
    else
        LayoutEdges(button, parentFrame, target, effect)
        if kind == "pulse" and nativePandemic ~= true then StartPulse(root) end
    end

    parentFrame._msufA3SpellIndicatorEffectButtons = parentFrame._msufA3SpellIndicatorEffectButtons or {}
    parentFrame._msufA3SpellIndicatorEffectButtons[button] = true
    root:Show()
    return true
end

-- Presence is an independent, plain-boolean output gate.  Keep it outside the
-- secret-backed AuraButton tree and compose it with the already validated
-- UnitCanAssist polarity rather than letting either lifecycle overwrite the
-- other's alpha.
local function GroupOutputVisible(parentFrame, identityMode)
    if not parentFrame then return false end
    -- Unit-frame Spell Indicators do not participate in the Group presence or
    -- UnitCanAssist state machines. Their outer effect surfaces must therefore
    -- remain transparent to this Group-only composition helper.
    if parentFrame._msufA3GroupAuraOutputOwned ~= true then return true end
    if parentFrame._msufA3GroupAuraPresenceVisible == false then
        return false
    end
    if identityMode == "assist" then
        return parentFrame._msufA3GroupAuraAssistReady == true
            and parentFrame._msufA3GroupAuraCanAssist == true
    end
    if identityMode == "hostile" then
        return parentFrame._msufA3GroupAuraAssistReady == true
            and parentFrame._msufA3GroupAuraCanAssist == false
    end
    return true
end

--- Cold-path adapter for the options preview.  It deliberately reuses the
--- live renderer so Border, Glow, Pulse, Health Tint, Name Overlay, layer and
--- priority cannot drift into a second Menu2-only implementation.
function Runtime.ApplyPreviewFrameEffect(owner, effect, parentFrame)
    if not (owner and type(effect) == "table" and parentFrame) then
        if owner then HideButtonFrameEffect(owner) end
        return false
    end
    if owner.Show then owner:Show() end
    local applied = ApplyButtonFrameEffect(owner, {
        frameEffect = effect,
        strata = effect.strata,
    }, parentFrame)
    if not applied and owner.Hide then owner:Hide() end
    return applied
end

function Runtime.HidePreviewFrameEffect(owner)
    if not owner then return false end
    HideButtonFrameEffect(owner)
    if owner.Hide then owner:Hide() end
    return true
end

local function ApplyAlwaysButtonFrameEffect(button, slot, parentFrame)
    if not (button and slot and parentFrame and type(slot.frameEffect) == "table") then
        HideButtonFrameEffect(button)
        return false
    end

    -- The full-frame surface remains a descendant of the one native AuraSlot.
    -- Its absolute level is independent from the icon host, while native secret
    -- visibility, Group presence, range and identity alpha all flow through the
    -- existing ancestor chain without Lua lifecycle hooks.
    return ApplyButtonFrameEffect(button, slot, parentFrame)
end

--- Installs a full-frame effect as one of Blizzard's native Pandemic regions.
--- The region is a descendant of the AuraButton, so the protected Shown aspect
--- is owned entirely by CustomAuraButtonMixin. No MSUF event, ticker, aura-data
--- read, or Lua OnUpdate participates in the visibility transition.
function Runtime.BindPandemicFrameEffect(button, effect, parentFrame)
    if not (button and type(button.AddPandemicRegion) == "function" and parentFrame) then return false end
    effect = NormalizeFrameEffect(effect)
    if not effect then return false end
    if button._msufA3PandemicFrameEffectRegion then return true end
    local nativePulse = tostring(effect.type or "none"):lower() == "pulse"
        and type(button.AddPandemicActiveAnimation) == "function"
    if not ApplyButtonFrameEffect(button,
        { frameEffect = effect, strata = effect.strata }, parentFrame, nativePulse) then return false end
    local region = button._msufA3SpellIndicatorEffectRoot
    if not region then return false end
    region:Hide()
    button:AddPandemicRegion(region)
    button._msufA3PandemicFrameEffectRegion = region
    -- 12.1.5 owns Pandemic animation lifecycle in native code. Register the
    -- looping pulse once; do not query or play it afterward because Blizzard
    -- seals QueryAnimationProgress and AddAnimations on inbound groups.
    if nativePulse and button._msufA3PandemicActivePulseBound ~= true then
        local pulse = EnsurePandemicPulse(region)
        if pulse then
            button:AddPandemicActiveAnimation(pulse)
            button._msufA3PandemicActivePulseBound = true
        end
    end
    return true
end

local function ApplyButtonIconEffect(button, slot, parentFrame)
    if not (button and slot and parentFrame) then return false end
    if slot.visual ~= "icon" or slot.iconEffect ~= "glow" then
        local buttons = parentFrame._msufA3SpellIndicatorIconEffectButtons
        if buttons then buttons[button] = nil end
        HideButtonIconEffect(button)
        return false
    end

    local visualOwner = button._msufA3SpellIndicatorVisualHost or button
    local root = button._msufA3SpellIndicatorIconEffectRoot
    if not root then
        root = CreateFrame("Frame", nil, visualOwner)
        root:EnableMouse(false)
        button._msufA3SpellIndicatorIconEffectRoot = root
    end
    root:ClearAllPoints()
    root:SetAllPoints(visualOwner)
    SyncFrameStrata(root, ResolveFrameStrata(parentFrame, slot.strata))
    if root.SetFrameLevel then root:SetFrameLevel((visualOwner:GetFrameLevel() or 0) + 4) end
    local color = slot.color or {}
    local size = ClampNumber(slot.size, 18, 1, 128)
    StartAnimatedGlow(root, root,
        Clamp01(color[1], 1), Clamp01(color[2], 1), Clamp01(color[3], 1), Clamp01(color[4], 1),
        math_max(2, size * 0.15))
    parentFrame._msufA3SpellIndicatorIconEffectButtons = parentFrame._msufA3SpellIndicatorIconEffectButtons or {}
    parentFrame._msufA3SpellIndicatorIconEffectButtons[button] = true
    root:Show()
    root:SetAlpha(1)
    return true
end

-- Fixed-slot buttons and their effect descendants already inherit the owning
-- AuraContainer's assist alpha. This helper only mirrors the same plain boolean
-- onto addon-owned missing-indicator previews.
function Runtime.ApplyGroupAssistGate(parentFrame, canAssist, ready)
    if not parentFrame then return false end
    parentFrame._msufA3GroupAuraOutputOwned = true
    local any = false
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    parentFrame._msufA3GroupAuraAssistReady = ready ~= false and known
    if known then
        parentFrame._msufA3GroupAuraCanAssist = canAssist
    else
        parentFrame._msufA3GroupAuraCanAssist = nil
    end
    local assistVisible = GroupOutputVisible(parentFrame, "assist")
    local hostileVisible = GroupOutputVisible(parentFrame, "hostile")
    local missing = parentFrame._msufA3SpellIndicatorMissingFrames
    if missing then
        for _, frame in pairs(missing) do
            local mode = frame and frame._msufA3IdentityCandidateMode
            if mode == "assist" then
                any = SetAssistAlpha(frame, assistVisible, 1) or any
            elseif mode == "hostile" then
                any = SetAssistAlpha(frame, hostileVisible, 1) or any
            end
        end
    end
    return any
end

-- Ordinary Unit exact-ID containers inherit their visible AuraButtons and
-- effect descendants through container alpha. Missing-indicator surfaces are
-- parent-frame siblings, so mirror the same identity gate only onto surfaces
-- owned by this container. Neutral and other-container surfaces stay untouched.
function Runtime.ApplyUnitIdentityGate(container, canAssist, ready)
    local parentFrame = container and container._msufA3ParentFrame
    local missing = parentFrame and parentFrame._msufA3SpellIndicatorMissingFrames
    if not missing then return false end
    local known = issecretvalue(canAssist) ~= true and type(canAssist) == "boolean"
    local any = false
    for _, frame in pairs(missing) do
        if frame and frame._msufA3MissingOwnerContainer == container then
            local mode = frame._msufA3IdentityCandidateMode
            if mode == "assist" or mode == "hostile" then
                local visible = ready == true and known
                    and (mode == "hostile" and canAssist == false
                        or mode == "assist" and canAssist == true)
                any = SetAssistAlpha(frame, visible, 1) or any
            end
        end
    end
    return any
end

function Runtime.ApplyGroupPresenceGate(parentFrame, present)
    if not parentFrame or type(present) ~= "boolean" then return false end
    parentFrame._msufA3GroupAuraOutputOwned = true
    parentFrame._msufA3GroupAuraPresenceVisible = present
    local any = false
    local missing = parentFrame._msufA3SpellIndicatorMissingFrames
    if missing then
        for _, frame in pairs(missing) do
            local mode = frame and frame._msufA3IdentityCandidateMode or "neutral"
            any = SetAssistAlpha(frame, GroupOutputVisible(parentFrame, mode), 1) or any
        end
    end
    return any
end

--- PTR 7 seals a native AuraButton and everything below it right after
--- initializeFrame returns. Writing to such a descendant is refused outright,
--- so ask before touching one. The return itself can be secret on a restricted
--- object; anything but a plain true fails closed.
local function CanWriteEffectSurface(root)
    local canAccess = root and root.CanBeAccessedInContext
    if type(canAccess) ~= "function" then return true end
    local allowed = canAccess(root)
    if issecretvalue(allowed) == true then return false end
    return allowed == true
end

--- Re-stamps the absolute frame level of every reachable full-frame effect
--- surface. Effect descendants inherit native AuraSlot visibility directly, so
--- this needs no aura scan and never reads AuraSlot:IsShown() -- it only
--- re-asserts layout data on MSUF-owned frames.
---
--- The roots are children of native AuraSlot buttons inside a shared
--- AuraContainer, and the client shifts every descendant when a container's own
--- level changes -- which is how a configured Layer could end up above the very
--- Name text it must render below. The geometry guards keep a container that
--- already owns buttons from moving at all; this pass repairs the surfaces that
--- are still writable, which is every menu-preview owner and every button that
--- has not been sealed yet. A sealed one stays where it is instead of erroring.
function Runtime.RefreshFrameEffects(parentFrame)
    if not parentFrame then return false end
    local buttons = parentFrame._msufA3SpellIndicatorEffectButtons
    if type(buttons) ~= "table" then return false end
    local healthBar = SpellIndicatorHealthBar(parentFrame)
    if not healthBar then return false end
    local any = false
    for button in pairs(buttons) do
        local effect = button and button._msufA3FrameEffectApplied
        local root = button and button._msufA3SpellIndicatorEffectRoot
        if type(effect) == "table" and root and root.SetFrameLevel
            and CanWriteEffectSurface(root) then
            root:SetFrameLevel(FrameEffectLevel(effect,
                tostring(effect.type or "none"):lower(), parentFrame, healthBar))
            any = true
        end
    end
    return any
end

function Runtime.ReleaseContainerEffects(container, parentFrame)
    if not container then return end
    parentFrame = parentFrame or container._msufA3ParentFrame
    -- Initialized AuraButtons and descendants can be access-restricted while
    -- aura data is secret. Their effect and icon descendants disappear with
    -- the owning container without addon-side lifecycle work.
    if parentFrame then
        parentFrame._msufA3SpellIndicatorEffectButtons = nil
        parentFrame._msufA3SpellIndicatorIconEffectButtons = nil
    end
end


-- Dependency installation is cold and precedes any native button creation.
-- Keep mutable native delegates in locals, including a later Install() rebind.
local function Install(assistAlpha)
    SetAssistAlpha = assistAlpha
end
local function BindReminderCleanup(forget)
    ForgetReminderEnchantPlaceholder = forget
end

return {
    ApplyButtonIconEffect = ApplyButtonIconEffect,
    ApplyAlwaysButtonFrameEffect = ApplyAlwaysButtonFrameEffect,
    GroupOutputVisible = GroupOutputVisible,
    Install = Install,
    BindReminderCleanup = BindReminderCleanup,
}
end
