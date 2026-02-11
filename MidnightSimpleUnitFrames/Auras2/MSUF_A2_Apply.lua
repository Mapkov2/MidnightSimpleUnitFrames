-- ============================================================================
-- MSUF Auras2 - Apply Module (Phase 3 Split)
-- Extracted from MSUF_A2_Render.lua to keep Render lean and enable future diff-based optimizations.
-- ============================================================================

local addonName, ns = ...
ns = (rawget(_G, "MSUF_NS") or ns) or {}
local API = ns.MSUF_Auras2
if type(API) ~= "table" then
    API = {}
    ns.MSUF_Auras2 = API
end

API.state = (type(API.state) == "table") and API.state or {}
local state = API.state

API.Apply = (type(API.Apply) == "table") and API.Apply or {}
local Apply = API.Apply

state.aurasByUnit = (type(state.aurasByUnit) == "table") and state.aurasByUnit or {}
local AurasByUnit = state.aurasByUnit

-- Hot locals (avoid global lookups)
local type = type
local GetTime = GetTime
local CreateFrame = CreateFrame
local GameTooltip = GameTooltip
local UIParent = UIParent
local floor = math.floor
local max = math.max

-- FastCall / SafeCall (no pcall in hot paths)
local MSUF_A2_FastCall = _G.MSUF_A2_FastCall
if type(MSUF_A2_FastCall) ~= "function" then
    MSUF_A2_FastCall = function(fn, ...)
        if fn == nil then return false end
        return true, fn(...)
    end
end

local function SafeCall(fn, ...)
    local ok, a, b, c, d, e = MSUF_A2_FastCall(fn, ...)
    if not ok then return nil end
    return a, b, c, d, e
end

-- Secret-safe value test.
-- In 12.0+ the supported check is the global API `issecretvalue(value)`.
-- Some environments also expose `C_Secrets.IsSecret(value)`; we keep it as a fallback.
-- IMPORTANT: Never boolean-test/compare a potentially-secret value directly.
local function _A2_IsSecretValue(v)
    local fn = _G and _G.issecretvalue
    if type(fn) == "function" then
        local ok, r = MSUF_A2_FastCall(fn, v)
        if ok and r == true then
            return true
        end
    end

    local s = C_Secrets and C_Secrets.IsSecret
    if type(s) == "function" then
        local ok, r = MSUF_A2_FastCall(s, v)
        if ok and r == true then
            return true
        end
    end

    return false
end

-- DB wrappers (Render binds EnsureDB into API.DB, but Apply can be loaded earlier)
local MSUF_DB = _G.MSUF_DB

local function EnsureDB()
    local a2, shared
    if API.EnsureDB then
        a2, shared = API.EnsureDB()
    else
        local DB = API.DB
        if DB and DB.Ensure then
            a2, shared = DB.Ensure()
        else
            local g = _G.MSUF_DB
            a2 = g and g.auras2
            shared = a2 and a2.shared
        end
    end
    MSUF_DB = _G.MSUF_DB
    return a2, shared
end

local function GetAuras2DB()
    if API.GetDB then return API.GetDB() end
    local DB = API.DB
    if DB and DB.GetCached then
        local a2, shared = DB.GetCached()
        if a2 and shared then return a2, shared end
    end
    return EnsureDB()
end

local function IsEditModeActive()
    if API.IsEditModeActive then
        return API.IsEditModeActive()
    end
    local f = _G.MSUF_IsEditModeActive
    if type(f) == "function" then return f() end
    return false
end

-- Masque helpers (may be nil if Masque module not present)
local Masque_IsEnabled, Masque_AddButton, Masque_RemoveButton, Masque_PrepareButton
local Masque_SyncIconOverlayLevels, Masque_PrepareDispelBorder, Masque_PrepareOwnHighlightBorder, Masque_PrepareOtherHighlightBorder
local Masque_RequestReskin
do
    local M = API.Masque
    Masque_IsEnabled = M and M.IsEnabled
    Masque_AddButton = M and M.AddButton
    Masque_RemoveButton = M and M.RemoveButton
    Masque_PrepareButton = M and M.PrepareButton
    Masque_SyncIconOverlayLevels = M and M.SyncIconOverlayLevels
    Masque_PrepareDispelBorder = M and M.PrepareDispelBorder
    Masque_PrepareOwnHighlightBorder = M and M.PrepareOwnHighlightBorder
    Masque_PrepareOtherHighlightBorder = M and M.PrepareOtherHighlightBorder
    Masque_RequestReskin = M and M.RequestReskin
end



-- ------------------------------------------------------------
-- Model helpers (late-bound)
-- ------------------------------------------------------------
local _A2_Model = API and API.Model
local _A2_GetPlayerAuraIdSetCached = _A2_Model and _A2_Model.GetPlayerAuraIdSetCached

local function _A2_ResolveGetPlayerAuraIdSetCached()
    local f = _A2_GetPlayerAuraIdSetCached
    if f then return f end
    _A2_Model = API and API.Model
    f = _A2_Model and _A2_Model.GetPlayerAuraIdSetCached
    _A2_GetPlayerAuraIdSetCached = f
    return f
end

local function MSUF_A2_GetEffectiveTextSizes(unitKey, shared)
    local stackSize = (shared and shared.stackTextSize) or 14
    local cooldownSize = (shared and shared.cooldownTextSize) or 14

    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == 'table' then
            if type(u.layout.stackTextSize) == 'number' and u.layout.stackTextSize > 0 then
                stackSize = u.layout.stackTextSize
            end
            if type(u.layout.cooldownTextSize) == 'number' and u.layout.cooldownTextSize > 0 then
                cooldownSize = u.layout.cooldownTextSize
            end
        end
    end

    stackSize = tonumber(stackSize) or 14
    cooldownSize = tonumber(cooldownSize) or 14
    stackSize = math.max(6, math.min(40, stackSize))
    cooldownSize = math.max(6, math.min(40, cooldownSize))
    return stackSize, cooldownSize
end


local MSUF_A2_GetCooldownFontString
local MSUF_A2_GetCooldownFontString_Safe  -- forward declaration (late-bound)


local function MSUF_A2_GetEffectiveCooldownTextOffsets(unitKey, shared)
    local offX, offY = nil, nil
    local enabled = false

    -- shared defaults (optional)
    if shared then
        if shared.cooldownTextOffsetX ~= nil then offX = shared.cooldownTextOffsetX; enabled = true end
        if shared.cooldownTextOffsetY ~= nil then offY = shared.cooldownTextOffsetY; enabled = true end
    end

    -- per-unit override (optional)
    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == "table" then
            if u.layout.cooldownTextOffsetX ~= nil then offX = u.layout.cooldownTextOffsetX; enabled = true end
            if u.layout.cooldownTextOffsetY ~= nil then offY = u.layout.cooldownTextOffsetY; enabled = true end
        end
    end

    -- 0-regression: if user never set any offsets, don't touch anchors.
    if not enabled then
        return 0, 0, false
    end

    offX = tonumber(offX) or 0
    offY = tonumber(offY) or 0
    offX = math.max(-2000, math.min(2000, offX))
    offY = math.max(-2000, math.min(2000, offY))
    return offX, offY, true
end

local function MSUF_A2_ApplyCooldownTextOffsets(icon, unitKey, shared)
    local fs = MSUF_A2_GetCooldownFontString_Safe(icon)
    if not fs then return end

    local offX, offY, enabled = MSUF_A2_GetEffectiveCooldownTextOffsets(unitKey, shared)
    if not enabled then
        return
    end

    -- Only re-anchor when the requested offsets actually change.
    if fs._msufA2_cdOffApplied ~= true or fs._msufA2_cdOffX ~= offX or fs._msufA2_cdOffY ~= offY then
        fs._msufA2_cdOffApplied = true
        fs._msufA2_cdOffX = offX
        fs._msufA2_cdOffY = offY

        if fs.ClearAllPoints then fs:ClearAllPoints() end
        if fs.SetPoint then fs:SetPoint("CENTER", icon, "CENTER", offX, offY) end
    end
end




local function MSUF_A2_GetEffectiveStackTextOffsets(unitKey, shared)
    local offX, offY = nil, nil
    local enabled = false

    if shared then
        if shared.stackTextOffsetX ~= nil then offX = shared.stackTextOffsetX; enabled = true end
        if shared.stackTextOffsetY ~= nil then offY = shared.stackTextOffsetY; enabled = true end
    end

    if MSUF_DB and MSUF_DB.auras2 and MSUF_DB.auras2.perUnit and unitKey then
        local u = MSUF_DB.auras2.perUnit[unitKey]
        if u and u.overrideLayout == true and type(u.layout) == "table" then
            if u.layout.stackTextOffsetX ~= nil then offX = u.layout.stackTextOffsetX; enabled = true end
            if u.layout.stackTextOffsetY ~= nil then offY = u.layout.stackTextOffsetY; enabled = true end
        end
    end

    -- 0-regression: if user never set any offsets, don't touch anchors.
    if not enabled then
        return 0, 0, false
    end

    offX = tonumber(offX) or 0
    offY = tonumber(offY) or 0
    offX = math.max(-2000, math.min(2000, offX))
    offY = math.max(-2000, math.min(2000, offY))
    return offX, offY, true
end

local function MSUF_A2_ApplyStackTextOffsets(icon, unitKey, shared, stackAnchorOverride)
    if not icon or not icon.count then return end

    local offX, offY, enabled = MSUF_A2_GetEffectiveStackTextOffsets(unitKey, shared)
    if not enabled then
        return
    end

    local stackAnchor = stackAnchorOverride or (shared and shared.stackCountAnchor) or "TOPRIGHT"

    local point, relPoint, xBase, yBase, justify
    if stackAnchor == "TOPLEFT" then
        point, relPoint, xBase, yBase, justify = "TOPLEFT", "TOPLEFT", -4, 7, "LEFT"
    elseif stackAnchor == "BOTTOMLEFT" then
        point, relPoint, xBase, yBase, justify = "BOTTOMLEFT", "BOTTOMLEFT", -4, -7, "LEFT"
    elseif stackAnchor == "BOTTOMRIGHT" then
        point, relPoint, xBase, yBase, justify = "BOTTOMRIGHT", "BOTTOMRIGHT", 4, -7, "RIGHT"
    else
        point, relPoint, xBase, yBase, justify = "TOPRIGHT", "TOPRIGHT", 4, 7, "RIGHT"
    end

    local fs = icon.count
    if fs._msufA2_stackOffApplied ~= true
        or fs._msufA2_stackOffX ~= offX
        or fs._msufA2_stackOffY ~= offY
        or fs._msufA2_stackOffAnchor ~= stackAnchor
    then
        fs._msufA2_stackOffApplied = true
        fs._msufA2_stackOffX = offX
        fs._msufA2_stackOffY = offY
        fs._msufA2_stackOffAnchor = stackAnchor

        fs:ClearAllPoints()
        fs:SetPoint(point, icon, relPoint, xBase + offX, yBase + offY)
        if fs.SetJustifyH and justify then fs:SetJustifyH(justify) end
    end
end

local function MSUF_A2_SetFontSize(fs, size)
    if not fs or not fs.SetFont then return false end

    size = tonumber(size)
    if not size or size <= 0 then return false end

    -- Prefer the resolved font file from GetFont(); if missing (FontObject-only),
    -- fall back to the FontObject's GetFont().
    local font, _, flags = nil, nil, nil
    if fs.GetFont then
        font, _, flags = fs:GetFont()
    end
    if not font and fs.GetFontObject then
        local fo = fs:GetFontObject()
        if fo and fo.GetFont then
            font, _, flags = fo:GetFont()
        end
    end

    if not font then
        return false
    end

    fs:SetFont(font, size, flags)
    return ok == true
end


-- Apply the MSUF global font (face/outline/shadow) to a FontString, using the provided size.
-- NOTE: Size is still driven by Auras (shared/per-unit). This only binds font face + flags + shadow.
local function MSUF_A2_ApplyFont(fs, fontPath, size, flags, useShadow)
    if not fs or not fs.SetFont then return false end

    size = tonumber(size)
    if not size or size <= 0 then return false end

    if not fontPath or fontPath == "" then
        -- Fallback: keep current font file if global isn't resolved yet.
        if fs.GetFont then
            local curFont, _, curFlags = fs:GetFont()
            if curFont and curFont ~= "" then
                fontPath = curFont
                if not flags or flags == "" then
                    flags = curFlags
                end
            end
        end
        if not fontPath or fontPath == "" then
            fontPath = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        end
    end

    local stamp = tostring(fontPath) .. "|" .. tostring(size) .. "|" .. tostring(flags or "")
    if fs._msufA2_fontStamp ~= stamp then
        fs:SetFont(fontPath, size, flags)
        if ok then
            fs._msufA2_fontStamp = stamp
        end
    end

    local wantShadow = (useShadow == true)
    local shadowStamp = wantShadow and 1 or 0
    if fs._msufA2_shadowStamp ~= shadowStamp then
        if wantShadow then
            if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 1) end
            if fs.SetShadowOffset then fs:SetShadowOffset(1, -1) end
        else
            if fs.SetShadowOffset then fs:SetShadowOffset(0, 0) end
        end
        fs._msufA2_shadowStamp = shadowStamp
    end

    return true
end

-- ------------------------------------------------------------
-- Cooldown text (fontstring scan + coloring + optional text) is handled by:
--   Auras2/MSUF_A2_CooldownText.lua
-- IMPORTANT: Render.lua can load before MSUF_A2_CooldownText.lua depending on TOC order.
-- So we late-bind these entrypoints and keep a tiny pending queue for icons created early.
-- ------------------------------------------------------------


local function MSUF_A2_ResolveCooldownFontStringFn()
    local f = MSUF_A2_GetCooldownFontString
    if f then return f end
    f = (_G and _G.MSUF_A2_GetCooldownFontString) or ((API and API.CooldownText) and API.CooldownText.GetCooldownFontString)
    MSUF_A2_GetCooldownFontString = f
    return f
end

MSUF_A2_GetCooldownFontString_Safe = function(icon)
    local f = MSUF_A2_ResolveCooldownFontStringFn()
    return f and f(icon) or nil
end

local function MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
    local CT = API and API.CooldownText
    local f = CT and CT.RegisterIcon
    if f then
        return f(icon)
    end

    -- CooldownText module not loaded yet: queue a one-time pending register.
    local st = API and API.state
    if st and icon and icon._msufA2_cdPending ~= true then
        icon._msufA2_cdPending = true
        local pending = st._msufA2_cdPending
        if type(pending) ~= "table" then
            pending = {}
            st._msufA2_cdPending = pending
        end
        pending[#pending + 1] = icon
    end
end

local function MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    local CT = API and API.CooldownText
    local f = CT and CT.UnregisterIcon
    if f then
        return f(icon)
    end
end

-- (Phase 5) Dispel border colors moved to Auras2/MSUF_A2_Colors.lua
-- ------------------------------------------------------------
-- Masque (optional)
-- ------------------------------------------------------------
local Masque = API.Masque
local Masque_IsEnabled = Masque and Masque.IsEnabled
local Masque_AddButton = Masque and Masque.AddButton
local Masque_RemoveButton = Masque and Masque.RemoveButton
local Masque_RequestReskin = Masque and Masque.RequestReskin
local Masque_SyncIconOverlayLevels = Masque and Masque.SyncIconOverlayLevels
local Masque_PrepareButton = Masque and Masque.PrepareButton

-- ------------------------------------------------------------
-- Icon factory
-- ------------------------------------------------------------

-- ------------------------------------------------------------
-- Icon borders / highlights (Masque-safe)
-- ------------------------------------------------------------
-- Overlay level syncing and border-detection are handled by MSUF_A2_Masque.lua



-- ------------------------------------------------------------
-- Step 7 perf (cumulative): shared tooltip handlers + cached preview defs + cooldown set gating
-- ------------------------------------------------------------

-- One-time tooltip handlers (assigned once per icon). We only toggle EnableMouse per update.
local function MSUF_A2_IconOnEnter(self)
    if not self then return end
    -- DB guard (tooltip should never error if called early)
    if not MSUF_DB or not MSUF_DB.auras2 or not MSUF_DB.auras2.shared then
        EnsureDB()
    end
    if not MSUF_DB or not MSUF_DB.auras2 or not MSUF_DB.auras2.shared then return end
    local shared = MSUF_DB.auras2.shared
    if shared.showTooltip ~= true then return end

    -- Preview tooltip (fake auras shown in Edit Mode)
    if self._msufA2_isPreview then
        if GameTooltip then
			local owner = self._msufTooltipOwner or self
			-- Tooltip should never error even if called from a stale/early frame
			if not owner then return end
			GameTooltip:SetOwner(owner, "ANCHOR_NONE")
			GameTooltip:ClearAllPoints()
			GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
            GameTooltip:SetText("Auras 2.0 Preview", 1, 1, 1)
            local kind = self._msufA2_previewKind
            if kind and kind ~= "" then
                GameTooltip:AddLine(kind, 0.9, 0.9, 0.9, true)
            end
            local cat = (self._msufFilter == "HELPFUL") and "Buff" or "Debuff"
            GameTooltip:AddLine("Category: " .. cat, 0.7, 0.7, 0.7, true)
            if self._msufSpellId then
                GameTooltip:AddLine("SpellID: " .. tostring(self._msufSpellId), 0.7, 0.7, 0.7, true)
            end
            GameTooltip:Show()
        end
        return
    end

	if not GameTooltip then return end
	local owner = self._msufTooltipOwner or self
	if not owner then return end
	GameTooltip:SetOwner(owner, "ANCHOR_NONE")
	GameTooltip:ClearAllPoints()
	GameTooltip:SetPoint("TOPLEFT", owner, "TOPRIGHT", 12, 0)
    local ok = false
    if GameTooltip.SetUnitAuraByAuraInstanceID and self._msufUnit and self._msufAuraInstanceID then
        GameTooltip:SetUnitAuraByAuraInstanceID(self._msufUnit, self._msufAuraInstanceID)
        ok = true
    elseif self._msufSpellId and GameTooltip.SetSpellByID then
        GameTooltip:SetSpellByID(self._msufSpellId)
        ok = true
    end
    if not ok then
        GameTooltip:SetText("Aura")
    end
    GameTooltip:Show()
end

local function MSUF_A2_IconOnLeave(self)
    if GameTooltip then GameTooltip:Hide() end
end

-- Cached preview definitions (no per-render table allocations)

-- Cached preview definitions (no per-render table allocations)
local MSUF_A2_PREVIEW_BUFF_DEFS = {
    -- Recognizable buffs (variety helps spacing/rows). Some show timers, some are permanent.
    { tex = "Interface\\Icons\\Spell_Holy_WordFortitude",        spellId = 21562, isHelpful = true,  previewKind = "Buff preview",  cdDur = 300, cdElapsed = 245 },
    { tex = "Interface\\Icons\\Spell_Holy_ArcaneIntellect",      spellId = 1459,  isHelpful = true,  previewKind = "Buff preview",  cdDur = 120, cdElapsed = 50  },
    { tex = "Interface\\Icons\\Spell_Nature_Rejuvenation",       spellId = 774,   isHelpful = true,  previewKind = "Buff preview",  cdDur = 18,  cdElapsed = 6   },
    { tex = "Interface\\Icons\\Spell_Holy_MagicalSentry",        spellId = 0,     isHelpful = true,  previewKind = "Buff preview",  permanent = true            },
    { tex = "Interface\\Icons\\Ability_Mage_TimeWarp",           spellId = 80353, isHelpful = true,  previewKind = "Buff preview",  cdDur = 40,  cdElapsed = 12  },
    { tex = "Interface\\Icons\\Spell_Nature_LightningShield",    spellId = 324,   isHelpful = true,  previewKind = "Buff preview",  cdDur = 90,  cdElapsed = 30  },
}



local MSUF_A2_PREVIEW_DEBUFF_DEFS = {
    -- Recognizable debuffs (variety helps spacing/rows). Some show timers, some are permanent.
    { tex = "Interface\\Icons\\Spell_Shadow_ShadowWordPain",       spellId = 589,   isHelpful = false, previewKind = "Debuff preview", cdDur = 20,  cdElapsed = 7   },
    { tex = "Interface\\Icons\\Spell_Shadow_AbominationExplosion", spellId = 172,   isHelpful = false, previewKind = "Debuff preview", cdDur = 14,  cdElapsed = 2   },
    { tex = "Interface\\Icons\\Ability_Rogue_Rupture",             spellId = 1943,  isHelpful = false, previewKind = "Debuff preview", cdDur = 24,  cdElapsed = 11  },
    { tex = "Interface\\Icons\\Spell_Shadow_CurseOfTounges",       spellId = 1714,  isHelpful = false, previewKind = "Debuff preview", cdDur = 30,  cdElapsed = 18  },
    { tex = "Interface\\Icons\\Spell_Nature_Slow",                 spellId = 0,     isHelpful = false, previewKind = "Debuff preview", permanent = true            },
    { tex = "Interface\\Icons\\Spell_Shadow_VampiricAura",         spellId = 34914, isHelpful = false, previewKind = "Debuff preview", cdDur = 60,  cdElapsed = 35  },
}

-- Private Aura preview icons (Edit Mode only; does not affect Blizzard private aura anchors)
local MSUF_A2_PREVIEW_PRIVATE_DEFS = {
    -- Private aura preview icons (Edit Mode only; does not affect Blizzard private aura anchors)
    { tex = "Interface\\Icons\\Ability_Creature_Cursed_03",     spellId = 0,     isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 12,  cdElapsed = 3  },
    { tex = "Interface\\Icons\\Spell_Shadow_AntiMagicShell",    spellId = 48707, isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 25,  cdElapsed = 10 },
    { tex = "Interface\\Icons\\Spell_Arcane_Arcane01",          spellId = 0,     isHelpful = true,  previewKind = "Private preview", isPrivate = true, permanent = true           },
    { tex = "Interface\\Icons\\Spell_Fire_Fireball02",          spellId = 133,   isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 45,  cdElapsed = 20 },
    { tex = "Interface\\Icons\\INV_Misc_QuestionMark",          spellId = 0,     isHelpful = true,  previewKind = "Private preview", isPrivate = true, cdDur = 90,  cdElapsed = 60 },
}



local function MSUF_A2_PreviewUnitLabel(unit)
    if unit == "player" then return "Player" end
    if unit == "target" then return "Target" end
    if unit == "focus" then return "Focus" end
    if type(unit) == "string" then
        local n = unit:match("^boss(%d+)$")
        if n then return "Boss " .. n end
    end
    return tostring(unit or "Unit")
end

local function AcquireIcon(container, index)
    container._msufIcons = container._msufIcons or {}
    container._msufA2_iconByAid = container._msufA2_iconByAid or {}
    local icon = container._msufIcons[index]
    if icon then
        -- Ensure Masque state is synced even for pooled/reused buttons
        local _, shared = GetAuras2DB()
        if Masque_IsEnabled and Masque_IsEnabled(shared) then
            if Masque_AddButton then Masque_AddButton(icon, shared) end
        else
            if Masque_RemoveButton then Masque_RemoveButton(icon) end
        end
        -- Preview label safety: never let preview text stick on reused icons.
        if icon._msufA2_previewLabel then
            icon._msufA2_previewLabel:Hide()
        end
        icon._msufA2_previewLabelText = nil

        icon._msufA2_container = container
        return icon
    end

    icon = CreateFrame("Button", nil, container, BackdropTemplateMixin and "BackdropTemplate" or nil)
    icon._msufA2_container = container
    icon:SetSize(26, 26)
    icon:EnableMouse(true)

    icon.tex = icon:CreateTexture(nil, "ARTWORK")
    icon.tex:SetAllPoints()
    icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Masque expects these canonical fields on a Button
    icon.Icon = icon.tex
    if Masque_PrepareButton then Masque_PrepareButton(icon) end

    icon.cooldown = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    icon.cooldown:SetAllPoints()
    icon.Cooldown = icon.cooldown
    SafeCall(icon.cooldown.SetDrawEdge, icon.cooldown, false)
    SafeCall(icon.cooldown.SetDrawSwipe, icon.cooldown, true)
    SafeCall(icon.cooldown.SetDrawBling, icon.cooldown, false)
    SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
    SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)

    -- Auras2: Expiration accuracy/stuck-at-0 fix (secret-safe)
    -- Some clients do not fire UNIT_AURA exactly at natural expiration, which can leave an icon visible at 0.
    -- We hook the Cooldown widget's OnCooldownDone and revalidate auraInstanceID, then request a coalesced refresh.
    if icon.cooldown and not icon.cooldown._msufA2_doneHooked then
        icon.cooldown._msufA2_doneHooked = true
        icon.cooldown._msufA2_parentIcon = icon
        icon.cooldown:SetScript("OnCooldownDone", function(cd)
            local ic = cd and cd._msufA2_parentIcon
            if not ic then return end
            if ic._msufA2_isPreview then return end
            local unit = ic._msufUnit
            local aid = ic._msufAuraInstanceID
            if not unit or not aid then return end

            if C_UnitAuras and type(C_UnitAuras.GetAuraDataByAuraInstanceID) == "function" then
                local auraData = C_UnitAuras.GetAuraDataByAuraInstanceID(unit, aid)
                -- Secret-safe: don't compare auraData to nil; use type() gating.
                if type(auraData) ~= "table" then
                    -- Aura is gone: immediately hide this recycled icon and force a refresh so layout closes gaps.
                    if ic._msufA2_cdMgrRegistered == true then
                        MSUF_A2_CooldownTextMgr_UnregisterIcon(ic)
                    end
                    ic._msufA2_cdDurationObj = nil
                    if ic.cooldown then
                        ic.cooldown._msufA2_durationObj = nil
                    end
                    ic:Hide()
                    if _G and type(_G.MSUF_Auras2_RefreshUnit) == "function" then
                        _G.MSUF_Auras2_RefreshUnit(unit)
                    elseif _G and type(_G.MSUF_Auras2_RefreshAll) == "function" then
                        _G.MSUF_Auras2_RefreshAll()
                    end
                end
            end
        end)
    end

    -- Count must render ABOVE the cooldown swipe.
    -- A Cooldown widget is a child frame and can cover parent fontstrings due to framelevel.
    -- So we create a dedicated count frame with a higher framelevel than the cooldown.
    icon._msufCountFrame = CreateFrame("Frame", nil, icon)
    icon._msufCountFrame:SetAllPoints()
    do
        local baseLevel = (icon.cooldown and icon.cooldown.GetFrameLevel and icon.cooldown:GetFrameLevel()) or icon:GetFrameLevel() or 1
        icon._msufCountFrame:SetFrameLevel(baseLevel + 5)
    end

    icon.count = icon._msufCountFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    icon.Count = icon.count
    icon.count:SetPoint("TOPRIGHT", icon, "TOPRIGHT", 4, 7) -- slightly more right
    icon.count:SetJustifyH("RIGHT")


-- Preview label (Edit Mode only). Created once and toggled on/off per icon render.
icon._msufA2_previewLabel = icon._msufCountFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
-- Label should always identify the bar without obscuring icons.
-- Anchor it slightly above the first icon, left-aligned (matches "Private" bar readability).
icon._msufA2_previewLabel:SetPoint("BOTTOMLEFT", icon, "TOPLEFT", 2, 6)
icon._msufA2_previewLabel:SetWordWrap(false)
icon._msufA2_previewLabel:SetNonSpaceWrap(false)
icon._msufA2_previewLabel:SetJustifyH("LEFT")
icon._msufA2_previewLabel:SetJustifyV("MIDDLE")
icon._msufA2_previewLabel:SetTextColor(1, 1, 1, 0.95)
icon._msufA2_previewLabel:SetShadowColor(0, 0, 0, 1)
icon._msufA2_previewLabel:SetShadowOffset(1, -1)
icon._msufA2_previewLabel:Hide()

    -- Bind stack count to global font settings (face/outline/shadow). Size follows Auras layout (shared/per-unit).
    do
        local fontPath, fontFlags, _, _, _, _, useShadow
        if type(MSUF_GetGlobalFontSettings) == "function" then
            fontPath, fontFlags, _, _, _, _, useShadow = MSUF_GetGlobalFontSettings()
        end
        local _, shared = GetAuras2DB()
        local stackSize = (shared and shared.stackTextSize) or 14
        if icon.count and fontPath then
            MSUF_A2_ApplyFont(icon.count, fontPath, stackSize, fontFlags, useShadow)
            icon._msufA2_lastStackTextSize = stackSize
        end
    end



    -- Strong highlight glow (used for "Highlight own buffs/debuffs")
    icon._msufOwnGlow = icon:CreateTexture(nil, "OVERLAY")
    icon._msufOwnGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    icon._msufOwnGlow:SetBlendMode("ADD")
    icon._msufOwnGlow:SetPoint("CENTER", icon, "CENTER", 0, 0)
    icon._msufOwnGlow:SetSize(42, 42)
    icon._msufOwnGlow:SetAlpha(0.95)
    icon._msufOwnGlow:Hide()


-- Private aura marker (player-only): small lock in the top-left corner.
-- We keep this lightweight and purely visual (no glow libs / no combat-unsafe calls).
icon._msufPrivateMark = icon:CreateTexture(nil, "OVERLAY")
icon._msufPrivateMark:SetTexture("Interface\\Buttons\\UI-GroupLoot-LockIcon")
icon._msufPrivateMark:SetSize(12, 12)
icon._msufPrivateMark:SetPoint("TOPLEFT", icon, "TOPLEFT", -2, 2)
icon._msufPrivateMark:SetAlpha(0.9)
icon._msufPrivateMark:Hide()

    -- Register with Masque if enabled
    do
        local _, shared = GetAuras2DB()
        if Masque_IsEnabled and Masque_IsEnabled(shared) and Masque_AddButton then
            Masque_AddButton(icon, shared)
        end
    end

    -- Step 7 perf: assign tooltip scripts once (no per-update SetScript churn)
    if not icon._msufA2_scriptsHooked then
        icon._msufA2_scriptsHooked = true
        icon:SetScript("OnEnter", MSUF_A2_IconOnEnter)
        icon:SetScript("OnLeave", MSUF_A2_IconOnLeave)
        icon:EnableMouse(false)
    end

    icon:Hide()
    container._msufIcons[index] = icon
    return icon
end

-- Shared helper: apply the stack-count anchor styling to an icon's count fontstring.
-- Safe to call repeatedly; it re-anchors only when the anchor setting changes.
local function MSUF_A2_ApplyStackCountAnchorStyle(icon, stackAnchor)
    if not icon or not icon.count then return end

    stackAnchor = stackAnchor or "TOPRIGHT"
    if (not icon._msufCountStyledA2) or (icon._msufA2_lastStackAnchor ~= stackAnchor) then
        icon._msufCountStyledA2 = true
        icon._msufA2_lastStackAnchor = stackAnchor

        local point, relPoint, xOff, yOff, justify
        if stackAnchor == "TOPLEFT" then
            point, relPoint, xOff, yOff, justify = "TOPLEFT", "TOPLEFT", -4, 7, "LEFT"
        elseif stackAnchor == "BOTTOMLEFT" then
            point, relPoint, xOff, yOff, justify = "BOTTOMLEFT", "BOTTOMLEFT", -4, -7, "LEFT"
        elseif stackAnchor == "BOTTOMRIGHT" then
            point, relPoint, xOff, yOff, justify = "BOTTOMRIGHT", "BOTTOMRIGHT", 4, -7, "RIGHT"
        else
            point, relPoint, xOff, yOff, justify = "TOPRIGHT", "TOPRIGHT", 4, 7, "RIGHT"
        end

        icon.count:ClearAllPoints()
        icon.count:SetPoint(point, icon, relPoint, xOff, yOff)
        icon.count:SetJustifyH(justify)
        icon.count:SetTextColor(1, 1, 1, 1)

        -- Shadow is driven by the global font pipeline.
        local useShadow = false
        if type(MSUF_GetGlobalFontSettings) == "function" then
            local _, _, _, _, _, _, sh = MSUF_GetGlobalFontSettings()
            useShadow = (sh == true)
        end
        if useShadow then
            icon.count:SetShadowColor(0, 0, 0, 1)
            icon.count:SetShadowOffset(1, -1)
        else
            icon.count:SetShadowOffset(0, 0)
        end
    end
end

local function HideUnused(container, fromIndex)
    if not container or not container._msufIcons then return end
    for i = fromIndex, #container._msufIcons do
        local icon = container._msufIcons[i]
        if icon then
            local aid = icon._msufAuraInstanceID
            local map = container._msufA2_iconByAid
            if aid and map and map[aid] == icon then
                map[aid] = nil
            end
            icon._msufAuraInstanceID = nil
            icon._msufFilter = nil
            -- If this icon is registered with the cooldown text manager, unregister to avoid holding refs.
            if icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
            icon:Hide()
        end
    end
end

-- Layout a container's icon grid.
-- IMPORTANT: This is called once per container (mixed, buffs, debuffs).
-- If buffs/debuffs have different icon sizes, call this with the desired iconSize for that container.
local function LayoutIcons(container, count, iconSize, spacing, perRow, growth, rowWrap)
    if count <= 0 then
        -- Layout stamp reset so next show does a full reflow
        if container then
            container._msufA2_layoutIconSize = nil
            container._msufA2_layoutSpacing = nil
            container._msufA2_layoutPerRow = nil
            container._msufA2_layoutGrowth = nil
            container._msufA2_layoutRowWrap = nil
            container._msufA2_layoutCount = 0
        end
        HideUnused(container, 1)
        return 0
    end

	    -- Defensive defaults / normalization.
	    -- (All inputs should be numeric except growth/rowWrap, but older stamps or bad calls can leak strings.)
	    iconSize = tonumber(iconSize) or 20
	    if iconSize < 1 then iconSize = 20 end
	
	    spacing = tonumber(spacing) or 2
	    if spacing < 0 then spacing = 0 end
	
	    perRow = tonumber(perRow) or 1
	    perRow = math.floor(perRow)
	    if perRow < 1 then perRow = 1 end
	    if perRow > 40 then perRow = 40 end
	
	    if growth ~= "LEFT" and growth ~= "RIGHT" and growth ~= "UP" and growth ~= "DOWN" then
	        growth = "RIGHT"
	    end
	
	    -- keep old behavior if missing/invalid.
	    if rowWrap ~= "UP" and rowWrap ~= "DOWN" then
	        rowWrap = "DOWN"
	    end

    if not container then
        return 0
    end

    -- avoid a full reflow (ClearAllPoints/SetPoint/SetSize) when layout inputs are unchanged.
    -- In addition, if ONLY the icon count changed, we do a delta-layout:
    --  • count increased: anchor only the newly-used indices
    --  • count decreased: just hide extras (existing points remain valid)
    local oldCount = container._msufA2_layoutCount or 0

    local sameParams = (
        container._msufA2_layoutIconSize == iconSize
        and container._msufA2_layoutSpacing == spacing
        and container._msufA2_layoutPerRow == perRow
        and container._msufA2_layoutGrowth == growth
        and container._msufA2_layoutRowWrap == rowWrap
    )

    if sameParams then
        if oldCount == count then
            -- Nothing changed: ensure the icons exist (no layout work)
            for i = 1, count do
                AcquireIcon(container, i)
            end
            HideUnused(container, count + 1)
            return math.ceil(count / perRow)
        end

        -- Count changed but layout inputs are identical.
        if count > oldCount then
            local stepX = (iconSize + spacing)
            local stepY = (iconSize + spacing)
            local vertical = (growth == "UP" or growth == "DOWN")
            local needReskin = false

            for i = oldCount + 1, count do
                local icon = AcquireIcon(container, i)
                icon:SetSize(iconSize, iconSize)
                if icon.MSUF_MasqueAdded and icon._msufA2_masqueSized ~= iconSize then
                    icon._msufA2_masqueSized = iconSize
                    needReskin = true
                end

                local row, col
                if vertical then
                    -- Vertical growth: fill a column first, then wrap into the next column.
                    col = math.floor((i - 1) / perRow)
                    row = (i - 1) % perRow
                else
                    -- Horizontal growth: fill a row first, then wrap into the next row.
                    row = math.floor((i - 1) / perRow)
                    col = (i - 1) % perRow
                end

                local x = stepX * col
                if (not vertical) and growth == "LEFT" then
                    x = -x
                end

                local y
                if vertical then
                    y = stepY * row
                    if growth == "DOWN" then
                        y = -y
                    end
                else
                    if rowWrap == "UP" then
                        y = stepY * row
                    else
                        y = -stepY * row
                    end
                end

                icon:ClearAllPoints()
                icon:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", x, y)
            end

            if needReskin then
                if Masque_RequestReskin then Masque_RequestReskin() end
            end
        else
            -- Count shrank: keep existing anchors; just ensure base indices exist.
            for i = 1, count do
                AcquireIcon(container, i)
            end
        end

        container._msufA2_layoutCount = count
        HideUnused(container, count + 1)
        return math.ceil(count / perRow)
    end

    -- Full reflow (layout inputs changed)
    container._msufA2_layoutIconSize = iconSize
    container._msufA2_layoutSpacing = spacing
    container._msufA2_layoutPerRow = perRow
    container._msufA2_layoutGrowth = growth
    container._msufA2_layoutRowWrap = rowWrap
    container._msufA2_layoutCount = count

    local stepX = (iconSize + spacing)
    local stepY = (iconSize + spacing)

    local vertical = (growth == "UP" or growth == "DOWN")
    local needReskin = false

    for i = 1, count do
        local icon = AcquireIcon(container, i)
        -- Only run when layout inputs changed, so always set size + anchors here.
        icon:SetSize(iconSize, iconSize)
        if icon.MSUF_MasqueAdded and icon._msufA2_masqueSized ~= iconSize then
            icon._msufA2_masqueSized = iconSize
            needReskin = true
        end

        local row, col
        if vertical then
            -- Vertical growth: fill a column first, then wrap into the next column.
            col = math.floor((i - 1) / perRow)
            row = (i - 1) % perRow
        else
            -- Horizontal growth: fill a row first, then wrap into the next row.
            row = math.floor((i - 1) / perRow)
            col = (i - 1) % perRow
        end

        local x = stepX * col
        if (not vertical) and growth == "LEFT" then
            x = -x
        end

        local y
        if vertical then
            y = stepY * row
            if growth == "DOWN" then
                y = -y
            end
        else
            if rowWrap == "UP" then
                y = stepY * row
            else
                y = -stepY * row
            end
        end

        icon:ClearAllPoints()
        icon:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", x, y)
    end

    if needReskin then
        if Masque_RequestReskin then Masque_RequestReskin() end
    end

    HideUnused(container, count + 1)
    return math.ceil(count / perRow)
end

function Apply.CommitIcon(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor, layoutSig)
    if not icon then return false end

    -- Always keep these stable for tooltip/refresh paths.
    icon._msufUnit = unit
    icon._msufFilter = isHelpful and "HELPFUL" or "HARMFUL"

    local container = icon._msufA2_container or icon:GetParent()
    local map = container and container._msufA2_iconByAid

    local prevAid = icon._msufAuraInstanceID
    if not aura then
        if prevAid and map and map[prevAid] == icon then
            map[prevAid] = nil
        end
        icon._msufAuraInstanceID = nil
        return false
    end

    local aid = aura._msufAuraInstanceID or aura.auraInstanceID
    if prevAid and prevAid ~= aid and map and map[prevAid] == icon then
        map[prevAid] = nil
    end
    icon._msufAuraInstanceID = aid
    if aid and map then
        map[aid] = icon
    end

    local last = icon._msufA2_last
    local ls   = layoutSig or 0
	-- IMPORTANT (Midnight/Beta secrets): even numeric aura fields can become secret values and
	-- *any* comparison can throw. Therefore we only use auraInstanceID + layoutSig + our own
	-- boolean flags for the conservative diff gate. We never compare aura.applications/
	-- expirationTime/duration here.

		-- Step 2 (Signature/Diff): we extend the gate with a few *config booleans* that affect
		-- visuals/cooldown rendering. These are safe to read/compare (they come from our DB),
		-- and ensure live-apply never regresses even when layoutSig doesn't include a specific toggle.
		local showStacks = (shared and shared.showStackCount == true) or false
		local showCdText = not (shared and shared.showCooldownText == false)
		local showCdSwipe = (shared and shared.showCooldownSwipe == true) or false
		local cdReverse = (shared and shared.cooldownSwipeDarkenOnLoss == true) or false
		local showTip = (shared and shared.showTooltip == true) or false

    -- Conservative diff: include the flags that affect visuals, and include layoutSig so
    -- any config/layout/visual setting change forces a re-apply (no live-apply regressions).
    if last
        and last.layoutSig == ls
        and last.aid == aid
        and last.isHelpful == isHelpful
        and last.hidePermanent == hidePermanent
        and last.masterOn == masterOn
        and last.isOwn == isOwn
        and last.stackAnchor == stackCountAnchor
	        and last.showStacks == showStacks
	        and last.showCdText == showCdText
	        and last.showCdSwipe == showCdSwipe
	        and last.cdReverse == cdReverse
	        and last.showTip == showTip
    then
        -- Fast-path: same aura instance + same layout/visual config.
        -- We skip the heavy visual apply (texture/border/backdrop/layout), but we still
        -- do a tiny refresh of *safe* dynamic parts that can change while the aura
        -- instance stays the same (e.g. stack display count), and we keep tooltip
        -- gating correct for Edit Mode.
        if type(MSUF_A2_ApplyIconTextSizing) == "function" then
            MSUF_A2_ApplyIconTextSizing(icon, unit, shared)
        end
        if type(MSUF_A2_ApplyIconTooltip) == "function" then
            MSUF_A2_ApplyIconTooltip(icon, shared)
        end
        if type(MSUF_A2_ApplyIconStacks) == "function" then
            -- Uses C_UnitAuras.GetAuraApplicationDisplayCount (unit, auraInstanceID) and
            -- never reads aura.applications (which can be secret/absent).
            MSUF_A2_ApplyIconStacks(icon, unit, shared, stackCountAnchor, nil, false, false)
        end

        -- Aura refreshes (same auraInstanceID) can change duration/expiration without changing any of our
        -- conservative diff keys. If we skip a full ApplyAuraToIcon, the cooldown swipe/text would keep
        -- counting down the old timer. Refresh the Cooldown widget + centralized text manager here.
        if (showCdText or showCdSwipe) and unit and aid and icon.cooldown then
            local cd = icon.cooldown
            local hadTimer = false

            if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
                local obj = C_UnitAuras.GetAuraDuration(unit, aid)
                -- In some environments this can be numeric; only Duration Objects are supported here.
                if obj ~= nil and type(obj) ~= "number" then
                    local applied = false
                    if type(cd.SetCooldownFromDurationObject) == "function" then
                        cd:SetCooldownFromDurationObject(obj)
                        applied = true
                    elseif type(cd.SetTimerDuration) == "function" then
                        cd:SetTimerDuration(obj)
                        applied = true
                    end
                    if applied then
                        hadTimer = true
                        icon._msufA2_cdDurationObj = obj
                        cd._msufA2_durationObj = obj
                    end
                end
            end

            -- Keep these in sync with MSUF_A2_ApplyIconCooldown() so later clears are correct.
            icon._msufA2_lastCooldownAuraInstanceID = aid
            icon._msufA2_lastHadTimer = hadTimer

            local CT = API and API.CooldownText
            local wantText = (showCdText and icon._msufA2_hideCDNumbers ~= true) and true or false
            if CT then
                if wantText and hadTimer then
                    if CT.RegisterIcon then CT.RegisterIcon(icon) end
                    if CT.TouchIcon then CT.TouchIcon(icon) end
                elseif icon._msufA2_cdMgrRegistered == true and CT.UnregisterIcon then
                    CT.UnregisterIcon(icon)
                end
            end

            if not hadTimer then
                -- If the API explicitly reports no expiration, hard-clear the cooldown (prevents stale timers).
                -- Secret-safe: never compare/boolean-test possible secret returns.
                if C_UnitAuras and type(C_UnitAuras.DoesAuraHaveExpirationTime) == "function" then
                    local v = C_UnitAuras.DoesAuraHaveExpirationTime(unit, aid)
                    if not _A2_IsSecretValue(v) then
                        local tv = type(v)
                        local noExp = false
	                        if tv == "boolean" then
	                            -- Safe: `v` is confirmed non-secret.
	                            noExp = (v == false)
	                        elseif tv == "number" then
	                            -- Safe: `v` is confirmed non-secret.
	                            noExp = (v <= 0)
                        end
                        if noExp then
                            if cd.Clear then cd:Clear() end
                            if cd.SetCooldown then cd:SetCooldown(0, 0) end
                            icon._msufA2_cdDurationObj = nil
                            cd._msufA2_durationObj = nil
                        end
                    end
                end
            end
        end

        return true
    end

    if not last then
        last = {}
        icon._msufA2_last = last
    end
    last.layoutSig = ls
    last.aid = aid
    last.isHelpful = isHelpful
    last.hidePermanent = hidePermanent
    last.masterOn = masterOn
    last.isOwn = isOwn
    last.stackAnchor = stackCountAnchor
	    last.showStacks = showStacks
	    last.showCdText = showCdText
	    last.showCdSwipe = showCdSwipe
	    last.cdReverse = cdReverse
	    last.showTip = showTip

    return ApplyAuraToIcon(icon, unit, aura, shared, isHelpful, hidePermanent, masterOn, isOwn, stackCountAnchor)
end


-- Advanced filter evaluation (Target-only for now):
-- Highlights / markers (no base border for buffs/debuffs; private aura bar unaffected)
local function SetDispelBorder(icon, unit, aura, isHelpful, shared, allowHighlights, isOwn)
    if not icon then return end

    if not shared then
        local _, s = GetAuras2DB()
        shared = s
    end

    local masqueOn = (Masque_IsEnabled and Masque_IsEnabled(shared)) and true or false

    -- Keep MSUF overlays above Masque regions (Masque can re-apply framelevels on skin changes).
    if masqueOn and icon.MSUF_MasqueAdded and Masque_SyncIconOverlayLevels then
        Masque_SyncIconOverlayLevels(icon)
    end

    -- Optional: keep Auras 2.0 icons borderless even when Masque skinning is enabled.
    -- Some Masque skins add an outline/backdrop; this lets the user suppress those regions.
    if masqueOn and icon.MSUF_MasqueAdded and shared and shared.masqueHideBorder == true then
        if icon._msufA2_masqueBorderHidden ~= true then
            icon._msufA2_masqueBorderHidden = true
            local b = icon.Border
            if b and b.Hide then  if b.SetAlpha then b:SetAlpha(0) end; b:Hide()  end
            local n = icon.Normal
            if n and n.Hide then  if n.SetAlpha then n:SetAlpha(0) end; n:Hide()  end
            local bd = icon.Backdrop
            if bd and bd.Hide then if bd.SetAlpha then bd:SetAlpha(0) end; bd:Hide() end
        end
    else
        -- If suppression was previously active and is now disabled, restore visibility.
        if icon._msufA2_masqueBorderHidden == true then
            icon._msufA2_masqueBorderHidden = false
            local b = icon.Border
            if b and b.Show then  if b.SetAlpha then b:SetAlpha(1) end; b:Show()  end
            local n = icon.Normal
            if n and n.Show then  if n.SetAlpha then n:SetAlpha(1) end; n:Show()  end
            local bd = icon.Backdrop
            if bd and bd.Show then if bd.SetAlpha then bd:SetAlpha(1) end; bd:Show() end
        end
    end

    -- Default: hide optional visuals (no base border work).
    if icon._msufOwnGlow then icon._msufOwnGlow:Hide() end
    if icon._msufPrivateMark then icon._msufPrivateMark:Hide() end

    local auraInstanceID = nil

    if aura ~= nil then
        auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    elseif icon and icon._msufAuraInstanceID ~= nil then
        auraInstanceID = icon._msufAuraInstanceID
    end

    -- Preview-private always wins (Edit Mode preview).
    if aura and aura._msufA2_previewIsPrivate == true then
        local pr, pg, pb = MSUF_A2_GetPrivatePlayerHighlightRGB()
        if icon._msufOwnGlow then
            icon._msufOwnGlow:SetVertexColor(pr, pg, pb, 1)
            icon._msufOwnGlow:Show()
        end
        if icon._msufPrivateMark then icon._msufPrivateMark:Show() end
        return
    end

    -- Player private aura highlight (12.0+ / Midnight safe): use Secrets by auraInstanceID.
    if unit == "player" and shared and shared.highlightPrivateAuras == true and auraInstanceID then
        if C_Secrets and type(C_Secrets.ShouldUnitAuraInstanceBeSecret) == "function" then
            local isSecret = C_Secrets.ShouldUnitAuraInstanceBeSecret(unit, auraInstanceID)
            if not _A2_IsSecretValue(isSecret) then
                local t = type(isSecret)
                local yes = false
	                if t == "boolean" then
	                    -- Safe: `isSecret` is confirmed non-secret.
	                    yes = isSecret
	                elseif t == "number" then
	                    -- Safe: `isSecret` is confirmed non-secret.
	                    yes = (isSecret > 0)
	                end
                if yes then
                    local pr, pg, pb = MSUF_A2_GetPrivatePlayerHighlightRGB()
                    if icon._msufOwnGlow then
                        icon._msufOwnGlow:SetVertexColor(pr, pg, pb, 1)
                        icon._msufOwnGlow:Show()
                    end
                    if icon._msufPrivateMark then icon._msufPrivateMark:Show() end
                    return
                end
            end
        end
    end

    if allowHighlights ~= true then
        return
    end

    -- Own aura highlight (glow only; no border)
    if isOwn and shared then
        if isHelpful and shared.highlightOwnBuffs == true then
            local r, g, b = MSUF_A2_GetOwnBuffHighlightRGB()
            if icon._msufOwnGlow then
                icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                icon._msufOwnGlow:Show()
            end
            return
        elseif (not isHelpful) and shared.highlightOwnDebuffs == true then
            local r, g, b = MSUF_A2_GetOwnDebuffHighlightRGB()
            if icon._msufOwnGlow then
                icon._msufOwnGlow:SetVertexColor(r, g, b, 1)
                icon._msufOwnGlow:Show()
            end
            return
        end
    end
end


local function MSUF_A2_AuraHasExpiration(unit, aura)
    -- Returns true if this aura should be treated as expiring (i.e. show cooldown swipe / timer),
    -- false if it is clearly permanent (duration == 0).
    --
    -- Secret-safe rules:
    --  * Never tostring()/string.* aura fields (can be secret).
    --  * Only treat numeric 0 as proof of permanence.
    --  * On uncertainty, assume expiring (safer for visuals; avoids incorrectly hiding timed auras).
    if aura == nil then return true end

    local auraInstanceID = aura.auraInstanceID
    if auraInstanceID == nil then
        -- Some call sites pass raw aura data without instance ID; assume expiring.
        return true
    end

    -- 1) Primary: DoesAuraHaveExpirationTime (best signal).
    if C_UnitAuras and type(C_UnitAuras.DoesAuraHaveExpirationTime) == "function" then
        local has = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
	if not _A2_IsSecretValue(has) then
	        local t = type(has)
	        if t == "boolean" then
	            -- Safe: `has` is confirmed non-secret.
	            return has
	        elseif t == "number" then
	            -- Safe: `has` is confirmed non-secret.
	            return (has > 0)
	        end
	    end
    end

	-- 2) Strict permanence check: ONLY hide when duration is explicitly numeric 0.
	-- In 12.0+ / Midnight, aura tables may not safely expose spellId; do NOT rely on it.
	-- Use GetAuraDuration/DoesAuraHaveExpirationTime signals only.
	if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
        local d = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
	    if type(d) == "number" and not _A2_IsSecretValue(d) then
	        if d <= 0 then return false end
	        return true
	    end
    end

    -- 3) Duration Objects: NOT a reliable permanence signal in Midnight/Beta; treat as expiring.
    return true
end




-- Cooldown clearing needs a stricter signal than MSUF_A2_AuraHasExpiration():
-- That helper intentionally treats "unknown" as non-expiring for the Hide-Permanent filter.
-- For cooldown timers, "unknown" must NOT clear, or debuff countdowns can "drop out" on boss/focus.
-- This returns TRUE only when the API explicitly reports a ZERO duration / no-expiration state.
local function MSUF_A2_AuraIsKnownPermanent(unit, aura)
    -- For cooldown timers: return TRUE only when we can *safely* prove the aura is permanent.
    -- Secret-safe: never tostring()/string.* aura fields.
    if aura == nil then return false end

    local auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    if auraInstanceID == nil then return false end

	if C_UnitAuras and type(C_UnitAuras.DoesAuraHaveExpirationTime) == "function" then
	    local v = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
	    if not _A2_IsSecretValue(v) then
	        local tv = type(v)
	        	if tv == "boolean" then
	            	-- v=false => no expiration => permanent (safe: v is confirmed non-secret)
	            	return (v == false)
	        	elseif tv == "number" then
	            	-- v<=0 => no expiration => permanent (safe: v is confirmed non-secret)
	            	return (v <= 0)
	        end
	    end
	end

	-- Only numeric 0 is accepted as a permanence signal.
	-- Do NOT rely on aura.spellId in 12.0+/Midnight.
	if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
	    local d = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
			if type(d) == "number" and not _A2_IsSecretValue(d) then
		        -- Safe: d is confirmed non-secret.
		        return (d <= 0)
	    end
	end

    return false
end


-- Cooldown helper (secret-safe): use Duration Objects only (no legacy Remaining* APIs).
local function MSUF_A2_TrySetCooldownFromAura(icon, unit, aura, wantCountdownText)
    if not icon or not icon.cooldown or not aura then return false end

    local auraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
    if auraInstanceID == nil then
        -- Clear cached state + unregister
        icon._msufA2_cdDurationObj = nil
        if icon.cooldown then
            icon.cooldown._msufA2_durationObj = nil
        end
        if icon._msufA2_cdMgrRegistered == true then
            MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
        end
        return false
    end

    if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
        local obj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
        if obj ~= nil then
            local cd = icon.cooldown
            local applied = false
            if type(cd.SetCooldownFromDurationObject) == "function" then
                cd:SetCooldownFromDurationObject(obj)
                applied = true
            elseif type(cd.SetTimerDuration) == "function" then
                cd:SetTimerDuration(obj)
                applied = true
            end

            if applied then
                -- Cache the Duration Object for the shared manager (no remaining-time arithmetic).
                icon._msufA2_cdDurationObj = obj
                cd._msufA2_durationObj = obj

                -- Register this icon for centralized cooldown text color updates.
                if wantCountdownText ~= false then
                    MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
                elseif icon._msufA2_cdMgrRegistered == true then
                    MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
                end
                return true
            end
        end
    end

    -- Clear cached state + unregister if we can't apply a timer.
    icon._msufA2_cdDurationObj = nil
    if icon.cooldown then
        icon.cooldown._msufA2_durationObj = nil
    end
    if icon._msufA2_cdMgrRegistered == true then
        MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    end
    return false
end

-- Patch 3: make per-icon apply logic more maintainable (no feature regression)
local function MSUF_A2_ApplyIconTextSizing(icon, unit, shared)
    local countFS = icon and icon.count
    if not (countFS and countFS.SetFont) then
        return
    end

    local stackSize
    if type(MSUF_A2_GetEffectiveTextSizes) == "function" then
        stackSize = MSUF_A2_GetEffectiveTextSizes(unit, shared)
    end
    stackSize = stackSize or 10

    if icon._msufA2_lastStackTextSize ~= stackSize then
        icon._msufA2_lastStackTextSize = stackSize

        local fontPath, fontFlags, useShadow, shadowX, shadowY, shadowA
        if type(MSUF_GetGlobalFontSettings) == "function" then
            fontPath, fontFlags, useShadow, shadowX, shadowY, shadowA = MSUF_GetGlobalFontSettings()
        end
        fontPath = fontPath or "Fonts\\FRIZQT__.TTF"
        fontFlags = fontFlags or ""

        countFS:SetFont(fontPath, stackSize, fontFlags)
        if useShadow then
            countFS:SetShadowOffset(shadowX or 1, shadowY or -1)
            countFS:SetShadowColor(0, 0, 0, shadowA or 1)
        else
            countFS:SetShadowOffset(0, 0)
            countFS:SetShadowColor(0, 0, 0, 0)
        end
    end
end

local function MSUF_A2_ApplyIconCooldownTextSizing(icon, unit, shared)
    if not icon then return end

    local cooldown = icon.cooldown
    if not cooldown then return end

    local cdFS = MSUF_A2_GetCooldownFontString_Safe(icon)
    if not cdFS then return end

    local _, cooldownSize
    if type(MSUF_A2_GetEffectiveTextSizes) == "function" then
        _, cooldownSize = MSUF_A2_GetEffectiveTextSizes(unit, shared)
    end
    cooldownSize = cooldownSize or 12

    if icon._msufA2_lastCooldownTextSize ~= cooldownSize then
        icon._msufA2_lastCooldownTextSize = cooldownSize

        local fontPath, fontFlags, useShadow, shadowX, shadowY, shadowA
        if type(MSUF_GetGlobalFontSettings) == "function" then
            fontPath, fontFlags, useShadow, shadowX, shadowY, shadowA = MSUF_GetGlobalFontSettings()
        end
        fontPath = fontPath or "Fonts\\FRIZQT__.TTF"
        fontFlags = fontFlags or ""

        cdFS:SetFont(fontPath, cooldownSize, fontFlags)
        if useShadow then
            cdFS:SetShadowOffset(shadowX or 1, shadowY or -1)
            cdFS:SetShadowColor(0, 0, 0, shadowA or 1)
        else
            cdFS:SetShadowOffset(0, 0)
            cdFS:SetShadowColor(0, 0, 0, 0)
        end
    end

    if type(MSUF_A2_ApplyCooldownTextOffsets) == "function" then
        MSUF_A2_ApplyCooldownTextOffsets(icon, unit, shared)
    end
end

local function MSUF_A2_ApplyIconStacks(icon, unit, shared, stackAnchorOverride, forcedDisp, forceHideCooldownNumbers, allowQuery)
    if shared and shared.showStackCount == false then
        if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
            SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
        end
        if icon.count then
            icon.count:SetText("")
            icon.count:Hide()
        end
        icon._msufA2_stackWasShown, icon._msufA2_lastStackDisp, icon._msufA2_lastStackText = false, nil, nil
        icon._msufA2_lastStackStamp = nil

        if icon._msufA2_hideCDNumbers == true then
            icon._msufA2_hideCDNumbers = false
            if icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
        end

        return false
    end

    local stackAnchor = stackAnchorOverride or (shared and shared.stackCountAnchor) or "TOPRIGHT"
    MSUF_A2_ApplyStackCountAnchorStyle(icon, stackAnchor)

    local disp = forcedDisp
    local dispText = nil
    local keepExistingText = false

    if disp ~= nil then
        -- Preview / forced stack display path.
        dispText = tostring(disp)
        icon._msufA2_lastStackDisp = disp
        icon._msufA2_lastStackText = dispText
    else
        if allowQuery ~= false and icon._msufAuraInstanceID then
            -- Cached path: Store invalidates per-aura on UNIT_AURA deltas; avoids per-frame API calls.
            local Store = API and API.Store
            local dispStamp

            if Store and Store.GetStackCount then
                disp, dispStamp = Store.GetStackCount(unit, icon._msufAuraInstanceID)
            elseif C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                disp = C_UnitAuras.GetAuraApplicationDisplayCount(unit, icon._msufAuraInstanceID, 2, 99)
            end

            if dispStamp ~= nil and icon._msufA2_lastStackStamp == dispStamp and icon._msufA2_lastStackText ~= nil then
                -- Same stamp: reuse cached text to avoid tostring()/allocations.
                dispText = icon._msufA2_lastStackText
                keepExistingText = (dispText == nil and icon._msufA2_stackWasShown == true) and true or false
                disp = icon._msufA2_lastStackDisp
                if dispText == nil then
                    disp = nil
                end
            else
                icon._msufA2_lastStackStamp = dispStamp

                if disp ~= nil then
                    dispText = tostring(disp)
                    -- Cache the last display so "time-only" refresh paths can render stacks without API calls.
                    -- IMPORTANT (secret-safe): we never compare these values, we only re-display them.
                    icon._msufA2_lastStackDisp = disp
                    icon._msufA2_lastStackText = dispText
                else
                    icon._msufA2_lastStackDisp = nil
                    icon._msufA2_lastStackText = nil
                end
            end
        else
            -- Fast-path: no API calls. Only re-display the cached value (if any).
            dispText = icon._msufA2_lastStackText
            -- Legacy-safety: older builds used a sentinel for _msufA2_lastStackDisp.
            -- If we don't have a cached text yet, keep whatever is currently shown.
            keepExistingText = (dispText == nil and icon._msufA2_stackWasShown == true) and true or false
            disp = icon._msufA2_lastStackDisp
            if dispText == nil then
                disp = nil
            end
        end
    end

    MSUF_A2_ApplyStackTextOffsets(icon, unit, shared, stackAnchor)

    if disp ~= nil or dispText ~= nil or keepExistingText then
        local wantHideNums = (forceHideCooldownNumbers == true)
        if icon._msufA2_hideCDNumbers ~= wantHideNums then
            icon._msufA2_hideCDNumbers = wantHideNums
            if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
                SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, wantHideNums)
            end
            if wantHideNums and icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
        end

        -- Secret-safe: do not compare the display count (can be secret). Avoid Show/Hide churn only.
        if icon.count then
            local sr, sg, sb = MSUF_A2_GetStackCountRGB()
            icon.count:SetTextColor(sr, sg, sb, 1)
            if keepExistingText ~= true then
                icon.count:SetText(dispText or tostring(disp))
            end
            if not icon.count:IsShown() then
                icon.count:Show()
            end
        end

        icon._msufA2_stackWasShown = true
        -- Cache already updated above (query/forced paths). In cache-only mode we keep it as-is.
        return true
    end

    if icon._msufA2_stackWasShown == true and InCombatLockdown and InCombatLockdown() then
        return true
    end

    if icon._msufA2_hideCDNumbers == true and forceHideCooldownNumbers ~= true then
        icon._msufA2_hideCDNumbers = false
        if icon.cooldown and icon.cooldown.SetHideCountdownNumbers then
            SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, false)
        end
    end

    if icon.count then
        if icon._msufA2_stackWasShown == true or icon._msufA2_lastStackDisp ~= nil then
            icon.count:SetText("")
            icon.count:Hide()
        end
    end
    icon._msufA2_stackWasShown, icon._msufA2_lastStackDisp, icon._msufA2_lastStackText = false, nil, nil
        icon._msufA2_lastStackStamp = nil
    return false
end

local function MSUF_A2_EffectiveHidePermanent(shared, hidePermanentOverride)
    if hidePermanentOverride ~= nil then
        return (hidePermanentOverride == true)
    end
    -- Prefer the legacy/shared flag first because some UIs still write shared.hidePermanent.
    if shared and shared.hidePermanent ~= nil then
        return (shared.hidePermanent == true)
    end
    local sf = shared and shared.filters
    if sf and sf.hidePermanent ~= nil then
        return (sf.hidePermanent == true)
    end
    return false
end

local function MSUF_A2_ApplyIconCooldown(icon, unit, aura, shared, previewDef)
    if not icon.cooldown then return false end
    SafeCall(icon.cooldown.Show, icon.cooldown)

    local wantText = not (shared and shared.showCooldownText == false)
    if wantText and icon and icon._msufA2_hideCDNumbers == true then
        wantText = false
    end

    if icon.cooldown.SetHideCountdownNumbers then
        SafeCall(icon.cooldown.SetHideCountdownNumbers, icon.cooldown, not wantText)
    end
    if not wantText and icon._msufA2_cdMgrRegistered == true then
        MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
    end

    local swipeWanted = (shared and shared.showCooldownSwipe and true) or false
    if icon._msufA2_lastSwipeWanted ~= swipeWanted then
        icon._msufA2_lastSwipeWanted = swipeWanted
        SafeCall(icon.cooldown.SetDrawSwipe, icon.cooldown, swipeWanted)
    end

    local reverseWanted = (shared and shared.cooldownSwipeDarkenOnLoss == true) or false
    if icon._msufA2_lastReverseWanted ~= reverseWanted then
        icon._msufA2_lastReverseWanted = reverseWanted
        if icon.cooldown.SetReverse then
            SafeCall(icon.cooldown.SetReverse, icon.cooldown, reverseWanted)
        end
    end

    if previewDef ~= nil then
        icon._msufA2_cdDurationObj = nil
        icon.cooldown._msufA2_durationObj = nil
        icon._msufA2_lastCooldownAuraInstanceID = nil
        icon._msufA2_lastHadTimer = nil

        local hadTimer = false
        local isPermanent = (previewDef.permanent == true) or (previewDef.noTimer == true)

        if isPermanent then
            if icon.cooldown and icon.cooldown.Clear then icon.cooldown:Clear() end
            if icon.cooldown and icon.cooldown.SetCooldown then icon.cooldown:SetCooldown(0, 0) end
            icon._msufA2_previewCooldownStart = nil
            icon._msufA2_previewCooldownDur = nil
        else
            -- Allow per-preview timing variety (so previews can show both permanent + timed auras).
            local pd = tonumber(previewDef.cdDur or previewDef.cooldownDur or previewDef.duration) or 25
            if pd < 1 then pd = 1 end
            if pd > 36000 then pd = 36000 end

            local elapsed = nil
            if previewDef.cdElapsed ~= nil then
                elapsed = tonumber(previewDef.cdElapsed)
            elseif previewDef.elapsed ~= nil then
                elapsed = tonumber(previewDef.elapsed)
            elseif previewDef.cdRemaining ~= nil then
                local rem = tonumber(previewDef.cdRemaining)
                if rem ~= nil then elapsed = pd - rem end
            end
            if elapsed == nil then elapsed = 10 end
            if elapsed < 0 then elapsed = 0 end
            if elapsed > pd then elapsed = pd * 0.5 end

            local ps = GetTime() - elapsed
            SafeCall(icon.cooldown.SetCooldown, icon.cooldown, ps, pd)
            icon._msufA2_previewCooldownStart = ps
            icon._msufA2_previewCooldownDur = pd
            hadTimer = true
        end

        if wantText and hadTimer then
            MSUF_A2_ApplyIconCooldownTextSizing(icon, unit, shared)
        end

        if wantText and icon._msufA2_hideCDNumbers ~= true and hadTimer then
            MSUF_A2_CooldownTextMgr_RegisterIcon(icon)
        elseif icon._msufA2_cdMgrRegistered == true then
            MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
        end

        return hadTimer
    end

    local prevAuraID = icon._msufA2_lastCooldownAuraInstanceID
    local prevHadTimer = (icon._msufA2_lastHadTimer == true)

    icon._msufA2_lastCooldownAuraInstanceID = icon._msufAuraInstanceID
    local hadTimer = MSUF_A2_TrySetCooldownFromAura(icon, unit, aura, wantText)
    icon._msufA2_lastHadTimer = hadTimer
    if hadTimer and wantText then
        MSUF_A2_ApplyIconCooldownTextSizing(icon, unit, shared)
    end

    if not hadTimer then
        local sameAura = (prevAuraID ~= nil and prevAuraID == icon._msufAuraInstanceID)
        if MSUF_A2_AuraIsKnownPermanent(unit, aura) or (not sameAura) or (sameAura and not prevHadTimer) then
            if icon.cooldown and icon.cooldown.Clear then icon.cooldown:Clear() end
            if icon.cooldown and icon.cooldown.SetCooldown then icon.cooldown:SetCooldown(0, 0) end
        end
    end
    return hadTimer
end

local function MSUF_A2_ApplyIconTooltip(icon, shared)
    local wantTip = (shared and shared.showTooltip == true)

    -- IMPORTANT (Edit Mode QoL): Aura icons must never block dragging the split preview bars.
    -- In Edit Mode, the movers are the interaction surface; icons should be purely visual.
    -- (Tooltips can be re-enabled simply by leaving Edit Mode.)
    if IsEditModeActive and IsEditModeActive() then
        wantTip = false
    end

    icon:EnableMouse((wantTip and true) or false)
end

ApplyAuraToIcon = function(icon, unit, aura, shared, isHelpful, hidePermanentOverride, allowHighlights, isOwn, stackAnchorOverride)
    if not icon or not aura then return end

    icon._msufUnit = unit
    -- Clear preview tooltip metadata (icons are recycled)
    local wasPreview = (icon._msufA2_isPreview == true)
    icon._msufA2_isPreview = nil
    icon._msufA2_previewKind = nil
    if wasPreview then
        -- If preview modified this icon, force a full visual refresh even if auraInstanceID matches prior cache.
        icon._msufA2_lastVisualAuraInstanceID = nil
    end

    icon._msufAuraInstanceID = aura._msufAuraInstanceID or aura.auraInstanceID
	-- IMPORTANT (12.0+ / Midnight): do NOT read/store aura.spellId; it may be absent/secret.
	icon._msufSpellId = nil

    local newFilter = isHelpful and "HELPFUL" or "HARMFUL"
    if icon._msufFilter ~= newFilter then
        icon._msufFilter = newFilter
    end

    -- Texture updates must be secret-safe: only touch when bound auraInstanceID changes.
    local auraInstanceID = icon._msufAuraInstanceID
    if auraInstanceID ~= nil and icon._msufA2_lastVisualAuraInstanceID ~= auraInstanceID then
        icon._msufA2_lastVisualAuraInstanceID = auraInstanceID
        local newTex = aura.icon
        if newTex ~= nil and icon.tex then
            icon.tex:SetTexture(newTex)
        end
    end

    -- Stack count font sizing (cooldown text sizing handled in MSUF_A2_ApplyIconCooldown)
    if shared.showStackCount == true then
        MSUF_A2_ApplyIconTextSizing(icon, unit, shared)
    end

    -- Stacks (may affect countdown number hiding policy)
    MSUF_A2_ApplyIconStacks(icon, unit, shared, stackAnchorOverride)

    -- Hide permanent auras (secret-safe)
    if MSUF_A2_EffectiveHidePermanent(shared, hidePermanentOverride) then
        local hasExpiration = MSUF_A2_AuraHasExpiration(unit, aura)
        if not hasExpiration then
            -- Ensure this icon is not kept alive by the cooldown text manager.
            icon._msufA2_cdDurationObj = nil
            if icon.cooldown then
                icon.cooldown._msufA2_durationObj = nil
            end
            if icon._msufA2_cdMgrRegistered == true then
                MSUF_A2_CooldownTextMgr_UnregisterIcon(icon)
            end
            icon:Hide()
            return false
        end
    end

    -- Cooldown (secret-safe)
    MSUF_A2_ApplyIconCooldown(icon, unit, aura, shared)

    -- Dispel/Highlight border (secret-safe)
    SetDispelBorder(icon, unit, aura, isHelpful, shared, allowHighlights, isOwn)

    -- Tooltip: scripts are assigned once per icon; we only toggle mouse.
    MSUF_A2_ApplyIconTooltip(icon, shared)

    icon:Show()
    return true
end
-- Goal:
--  * Avoid rebuilding/merging large aura lists on UNIT_AURA bursts when nothing about the unit's
--    auraInstanceID sets changed.
--  * Keep this secret-safe: we only hash auraInstanceIDs and config values; no expiration arithmetic.
--
-- If signatures match, we run a *visual-only* refresh over already-assigned icons.
-- ------------------------------------------------------------



local function MSUF_A2_RefreshAssignedIcons(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs, forceQuery)
    if not entry or not unit or not shared then return end

    -- Visual-only refresh for already-assigned icons.
    -- IMPORTANT: Do NOT call GetAuraDataByAuraInstanceID here (hot path).
    local useSingleRow = (entry.mixed ~= nil) and ((entry.mixed.IsShown and entry.mixed:IsShown()) or false)
    local mixedCount  = entry._msufA2_lastMixedCount  or 0
    local debuffCount = entry._msufA2_lastDebuffCount or 0
    local buffCount   = entry._msufA2_lastBuffCount   or 0

    local applySizing = (shared.showStackCount == true) and MSUF_A2_ApplyIconTextSizing or nil
    local applyTip    = MSUF_A2_ApplyIconTooltip
    local applyStacks = MSUF_A2_ApplyIconStacks
    local setBorder   = SetDispelBorder

    local doQuery = (forceQuery == true)
    local showCdText  = not (shared and shared.showCooldownText == false)
    local showCdSwipe = (shared and shared.showCooldownSwipe == true) or false
    local refreshCD   = MSUF_A2_RefreshIconCooldownFast

    local function RefreshContainer(container, count)
        if not container or count <= 0 then return end
        local icons = container._msufIcons or container.icons
        if not icons then return end

        for idx = 1, count do
            local icon = icons[idx]
            local aid = icon and icon._msufAuraInstanceID
            if aid ~= nil then
                if applySizing then
                    applySizing(icon, unit, shared)
                end
                if applyTip then
                    applyTip(icon, shared)
                end
                if applyStacks then
                    -- Fast-path: no API calls; only re-display cached stack text if any.
                    applyStacks(icon, unit, shared, stackCountAnchor, nil, false, doQuery)
                    if doQuery and refreshCD then
                        refreshCD(icon, unit, aid, shared, showCdText, showCdSwipe, true)
                    end
                end
                if setBorder then
                    local isHelpful = (icon._msufFilter == "HELPFUL")
                    local last = icon._msufA2_last
                    local isOwn = (last and last.isOwn == true) or false
                    setBorder(icon, unit, nil, isHelpful, shared, masterOn, isOwn)
                end
            end
        end
    end

    if useSingleRow then
        RefreshContainer(entry.mixed, mixedCount)
    else
        RefreshContainer(entry.debuffs, debuffCount)
        RefreshContainer(entry.buffs, buffCount)
    end
end


local function MSUF_A2_RefreshIconCooldownFast(icon, unit, auraInstanceID, shared, showCdText, showCdSwipe, doTouch)
    if not icon or not unit or not auraInstanceID or not icon.cooldown then return end
    if not (showCdText or showCdSwipe) then return end

    local cd = icon.cooldown
    local hadTimer = false

    if C_UnitAuras and type(C_UnitAuras.GetAuraDuration) == "function" then
        local obj = C_UnitAuras.GetAuraDuration(unit, auraInstanceID)
        -- In some environments this can be numeric; only Duration Objects are supported here.
        if obj ~= nil and type(obj) ~= "number" then
            local applied = false
            if type(cd.SetCooldownFromDurationObject) == "function" then
                cd:SetCooldownFromDurationObject(obj)
                applied = true
            elseif type(cd.SetTimerDuration) == "function" then
                cd:SetTimerDuration(obj)
                applied = true
            end
            if applied then
                hadTimer = true
                icon._msufA2_cdDurationObj = obj
                cd._msufA2_durationObj = obj
            end
        end
    end

    -- Keep these in sync with MSUF_A2_ApplyIconCooldown() so later clears are correct.
    icon._msufA2_lastCooldownAuraInstanceID = auraInstanceID
    icon._msufA2_lastHadTimer = hadTimer

    local CT = API and API.CooldownText
    local wantText = (showCdText and icon._msufA2_hideCDNumbers ~= true) and true or false
    if CT then
        if wantText and hadTimer then
            if CT.RegisterIcon then CT.RegisterIcon(icon) end
            if doTouch == true and CT.TouchIcon then CT.TouchIcon(icon) end
        elseif icon._msufA2_cdMgrRegistered == true and CT.UnregisterIcon then
            CT.UnregisterIcon(icon)
        end
    end

    if wantText and hadTimer and type(MSUF_A2_ApplyIconCooldownTextSizing) == "function" then
        MSUF_A2_ApplyIconCooldownTextSizing(icon, unit, shared)
    end

    if not hadTimer then
        -- If the API explicitly reports no expiration, hard-clear the cooldown (prevents stale timers).
        if C_UnitAuras and type(C_UnitAuras.DoesAuraHaveExpirationTime) == "function" then
            local v = C_UnitAuras.DoesAuraHaveExpirationTime(unit, auraInstanceID)
            if not _A2_IsSecretValue(v) then
                local tv = type(v)
                local noExp = false
                if tv == "boolean" then
                    noExp = (v == false)
                elseif tv == "number" then
                    noExp = (v <= 0)
                end
                if noExp then
                    if cd.Clear then cd:Clear() end
                    if cd.SetCooldown then cd:SetCooldown(0, 0) end
                    icon._msufA2_cdDurationObj = nil
                    cd._msufA2_durationObj = nil
                end
            end
        end
    end
end


local function MSUF_A2_RefreshAssignedIconsDelta(entry, unit, shared, masterOn, stackCountAnchor, hidePermanentBuffs, upd, updN)
    if not entry or not unit or not shared then return end
    if not upd or not updN or updN <= 0 then return end

    -- Delta refresh: only update icons for the auraInstanceIDs that actually changed.
    -- IMPORTANT: Do NOT call GetAuraDataByAuraInstanceID here (hot path).
    local useSingleRow = (entry.mixed ~= nil) and ((entry.mixed.IsShown and entry.mixed:IsShown()) or false)

    -- NOTE (bugfix): The authoritative auraInstanceID → icon map lives on the
    -- icon containers (entry.debuffs/entry.buffs/entry.mixed) as
    -- container._msufA2_iconByAid, because CommitIcon() writes into that map.
    --
    -- The previous refactor accidentally looked for maps on the entry object
    -- (entry._msufA2_iconByAid*), which are never assigned. That made the
    -- delta refresh a no-op: stacks and refreshed durations would only update
    -- when a new aura forced a full re-assign.
    local mixedMap  = (entry.mixed  and entry.mixed._msufA2_iconByAid)  or entry._msufA2_iconByAidMixed
    local debuffMap = (entry.debuffs and entry.debuffs._msufA2_iconByAid) or entry._msufA2_iconByAidDebuff
    local buffMap   = (entry.buffs  and entry.buffs._msufA2_iconByAid)  or entry._msufA2_iconByAidBuff

    local applySizing = (shared.showStackCount == true) and MSUF_A2_ApplyIconTextSizing or nil
    local applyTip    = MSUF_A2_ApplyIconTooltip
    local applyStacks = MSUF_A2_ApplyIconStacks
    local setBorder   = SetDispelBorder

    local showCdText  = not (shared.showCooldownText == false)
    local showCdSwipe = (shared.showCooldownSwipe == true) or false

    for i = 1, updN do
        local aid = upd[i]
        if aid ~= nil then
            local icon = nil
            if useSingleRow then
                icon = (mixedMap and mixedMap[aid]) or (debuffMap and debuffMap[aid]) or (buffMap and buffMap[aid])
            else
                icon = (debuffMap and debuffMap[aid]) or (buffMap and buffMap[aid]) or (mixedMap and mixedMap[aid])
            end

            if icon and icon._msufAuraInstanceID ~= nil then
                if applySizing then
                    applySizing(icon, unit, shared)
                end
                if applyTip then
                    applyTip(icon, shared)
                end
                if applyStacks then
                    -- Delta path: allowQuery=true so stacks refresh correctly on UNIT_AURA.
                    applyStacks(icon, unit, shared, stackCountAnchor, nil, false, true)
                end

                if (showCdText or showCdSwipe) and icon.cooldown then
                    MSUF_A2_RefreshIconCooldownFast(icon, unit, aid, shared, showCdText, showCdSwipe, true)
                end

                if setBorder then
                    local isHelpful = (icon._msufFilter == "HELPFUL")
                    local last = icon._msufA2_last
                    local isOwn = (last and last.isOwn == true) or false
                    setBorder(icon, unit, nil, isHelpful, shared, masterOn, isOwn)
                end
            end
        end
    end
end




local MSUF_A2_RENDER_BUDGET = 18

-- ------------------------------------------------------------
-- Auras 2.0 Render helpers (Patch 2): consolidate buff/debuff flow
--  * Reduces duplicate code in RenderUnit()
--  * Avoids per-render table churn where possible
--  * Keeps "hide permanent" BUFF-only behavior consistent (also in fast refresh)
-- ------------------------------------------------------------

local MSUF_A2_EMPTY = {}




local function MSUF_A2_ApplyPreviewIcon(icon, tex, spellId, opts, unit, shared, stackCountAnchor, previewLabelText)
    if not icon then return end

    icon._msufUnit = unit
    icon._msufAuraInstanceID = nil
    icon._msufA2_lastCooldownAuraInstanceID = nil
    icon._msufA2_lastHadTimer = nil
    icon._msufA2_lastVisualAuraInstanceID = nil
    icon._msufSpellId = spellId
    icon._msufFilter = (opts and opts.isHelpful) and "HELPFUL" or "HARMFUL"

    -- Mark as preview so tooltips can describe the fake aura type
    icon._msufA2_isPreview = true
    icon._msufA2_previewKind = (opts and opts.previewKind) or nil
    icon._msufA2_previewLabelText = previewLabelText

    if icon.tex then
        icon.tex:SetTexture(tex)
    end

    -- Apply per-unit text sizes in preview too (stacks + cooldown text).
    MSUF_A2_ApplyIconTextSizing(icon, unit, shared)

    -- Cooldown setup (preview uses synthetic timers, but still shares swipe/text settings + manager).
    if icon.cooldown then
        MSUF_A2_ApplyIconCooldown(icon, unit, nil, shared, opts)
    end

    -- Stack preview (optional). Keep preview cycling fields used by the preview ticker.
    local forcedDisp, forceHideNums = nil, false
    if opts and opts.stackText then
        local curN = tonumber(opts.stackText) or 2
        forcedDisp = curN
        forceHideNums = true

        local maxN = tonumber(opts.stackText)
        if type(maxN) == "number" then
            if maxN < 5 then maxN = 5 end
            icon._msufA2_previewStackMax = maxN
        else
            icon._msufA2_previewStackMax = nil
        end
        icon._msufA2_previewStackCur = icon._msufA2_previewStackCur or curN
    else
        icon._msufA2_previewStackCur = nil
        icon._msufA2_previewStackMax = nil
    end

    -- For preview: apply cooldown first, then stacks can optionally hide countdown numbers (stack demo).
    MSUF_A2_ApplyIconStacks(icon, unit, shared, stackCountAnchor, forcedDisp, forceHideNums)


-- Preview label text (only in Edit Mode previews)
if icon._msufA2_previewLabel then
    local t = previewLabelText
    if (not t or t == "") and opts and opts.previewLabel then
        t = opts.previewLabel
    end
    if t and t ~= "" then
        icon._msufA2_previewLabel:SetText(t)
        icon._msufA2_previewLabel:SetWidth(icon:GetWidth() or 26)
        icon._msufA2_previewLabel:Show()
    else
        icon._msufA2_previewLabel:Hide()
    end
end

    -- Highlights + borders share the live pipeline (preview injects simple override flags).
    local pa = icon._msufA2_previewAura
    if type(pa) ~= "table" then
        pa = {}
        icon._msufA2_previewAura = pa
    end
    pa._msufAuraInstanceID = nil
    pa.auraInstanceID = nil
    pa.spellId = spellId
    pa._msufA2_previewIsPrivate = (opts and ((opts.isPrivate == true) or (opts.previewKind == "private"))) and true or false

    SetDispelBorder(icon, unit, pa, (icon._msufFilter == "HELPFUL"), shared, true, (opts and (opts.isOwn or opts.own)))
    -- IMPORTANT (Edit Mode QoL): Preview icons must never block dragging the mover bars.
    -- The mover is the interaction surface; preview icons are purely visual.
    icon:EnableMouse(false)

    icon:Show()
end

local function MSUF_A2_RenderPreviewIcons(entry, unit, shared, useSingleRow, buffCap, debuffCap, stackCountAnchor)
    if not entry then return 0, 0 end

    local buffDefs = MSUF_A2_PREVIEW_BUFF_DEFS
    local debuffDefs = MSUF_A2_PREVIEW_DEBUFF_DEFS

    local uLabel = MSUF_A2_PreviewUnitLabel(unit)
    local buffLabel = uLabel .. " Buff"
    local debuffLabel = uLabel .. " Debuff"

    local debuffCount = tonumber(debuffCap) or 0
    if debuffCount < 0 then debuffCount = 0 end
    if debuffCount > 80 then debuffCount = 80 end

    local buffCount = tonumber(buffCap) or 0
    if buffCount < 0 then buffCount = 0 end
    if buffCount > 80 then buffCount = 80 end

    local nDeb = (debuffDefs and #debuffDefs) or 0
    local nBuf = (buffDefs and #buffDefs) or 0
    if nDeb < 1 then nDeb = 1 end
    if nBuf < 1 then nBuf = 1 end

    -- Debuffs first
    for i = 1, debuffCount do
        local def = debuffDefs[((i - 1) % nDeb) + 1]
        local icon = AcquireIcon(useSingleRow and entry.mixed or entry.debuffs, i)
        -- Only label the first icon (avoids text spam when showing many icons).
        local label = (i == 1) and debuffLabel or nil
        MSUF_A2_ApplyPreviewIcon(icon, def.tex, def.spellId, def, unit, shared, stackCountAnchor, label)
    end

    -- Buffs next (append in mixed mode)
    for i = 1, buffCount do
        local def = buffDefs[((i - 1) % nBuf) + 1]
        local idx = useSingleRow and (debuffCount + i) or i
        local icon = AcquireIcon(useSingleRow and entry.mixed or entry.buffs, idx)
        local label = (i == 1) and buffLabel or nil
        MSUF_A2_ApplyPreviewIcon(icon, def.tex, def.spellId, def, unit, shared, stackCountAnchor, label)
    end

    if useSingleRow then
        HideUnused(entry.mixed, (debuffCount + buffCount) + 1)
    else
        HideUnused(entry.debuffs, debuffCount + 1)
        HideUnused(entry.buffs, buffCount + 1)
    end

    return buffCount, debuffCount
end


local function MSUF_A2_RenderPreviewPrivateIcons(entry, unit, shared, privIconSize, spacing, stackCountAnchor)
    if not entry or not entry.private then return 0 end
    -- Target private auras are disabled in MSUF (kept for future-proofing); do not render preview there.
    if unit == "target" then
        HideUnused(entry.private, 1)
        return 0
    end

    local defs = MSUF_A2_PREVIEW_PRIVATE_DEFS
    local uLabel = MSUF_A2_PreviewUnitLabel(unit)

    local maxN = 0
    if type(shared) == "table" then
        local cap = (unit == "player") and shared.privateAuraMaxPlayer or shared.privateAuraMaxOther
        if type(cap) == "number" and cap >= 0 then
            maxN = math.floor(cap)
        end
    end
    if maxN < 0 then maxN = 0 end
    if maxN > 80 then maxN = 80 end

    if type(privIconSize) ~= "number" or privIconSize <= 0 then privIconSize = 26 end
    if type(spacing) ~= "number" then spacing = 2 end

    local nDefs = (defs and #defs) or 0
    if nDefs < 1 then nDefs = 1 end

    local count = maxN
    local prev
    for i = 1, count do
        local def = defs[((i - 1) % nDefs) + 1]
        local icon = AcquireIcon(entry.private, i)
        icon:SetSize(privIconSize, privIconSize)
        icon:ClearAllPoints()
        if not prev then
            icon:SetPoint("BOTTOMLEFT", entry.private, "BOTTOMLEFT", 0, 0)
        else
            icon:SetPoint("LEFT", prev, "RIGHT", spacing, 0)
        end
        prev = icon

        local label = (i == 1) and (uLabel .. " Private") or nil
        MSUF_A2_ApplyPreviewIcon(icon, def.tex, def.spellId, def, unit, shared, stackCountAnchor, label)
    end
    HideUnused(entry.private, count + 1)
    return count
end





-- Bind aura cooldown/stack texts to the global font pipeline (called from UpdateAllFonts).
local function MSUF_A2_ApplyFontsFromGlobal()
    local _, shared = GetAuras2DB()
    if type(AurasByUnit) ~= "table" then return end

    if type(MSUF_GetGlobalFontSettings) ~= "function" then return end
    local fontPath, fontFlags, _, _, _, _, useShadow = MSUF_GetGlobalFontSettings()

    -- If the user changed the global font color, rebuild the cooldown color curve's "normal" point.
    if API and API.InvalidateCooldownTextCurve then
        API.InvalidateCooldownTextCurve()
    elseif _G and type(_G.MSUF_A2_InvalidateCooldownTextCurve) == "function" then
        _G.MSUF_A2_InvalidateCooldownTextCurve()
    end

    for unitKey, entry in pairs(AurasByUnit) do
        if entry then
            for _, container in ipairs({ entry.buffs, entry.debuffs, entry.mixed }) do
                if container and container._msufIcons then
                    local stackSize, cooldownSize = MSUF_A2_GetEffectiveTextSizes(unitKey, shared)
                    for i = 1, #container._msufIcons do
                        local icon = container._msufIcons[i]
                        if icon then
                            if icon.count then
                                local ok = MSUF_A2_ApplyFont(icon.count, fontPath, stackSize, fontFlags, useShadow)
                                if ok then
                                    icon._msufA2_lastStackTextSize = stackSize
                                end
                            end

                            if icon.cooldown then
                                -- Force a rescan of the countdown FontString on demand (built lazily by Blizzard)
                                icon.cooldown._msufCooldownFontString = nil
                                icon.cooldown._msufCooldownFontStringLastTry = 0
                            end
                            local cdFS = MSUF_A2_GetCooldownFontString_Safe(icon)
                            if cdFS then
                                local ok = MSUF_A2_ApplyFont(cdFS, fontPath, cooldownSize, fontFlags, useShadow)
                                if ok then
                                    icon._msufA2_lastCooldownTextSize = cooldownSize
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end
-- ============================================================================
-- Exports (Render calls these via API.Apply)
-- ============================================================================

Apply.GetEffectiveTextSizes = MSUF_A2_GetEffectiveTextSizes
Apply.GetEffectiveCooldownTextOffsets = MSUF_A2_GetEffectiveCooldownTextOffsets
Apply.ApplyCooldownTextOffsets = MSUF_A2_ApplyCooldownTextOffsets
Apply.GetEffectiveStackTextOffsets = MSUF_A2_GetEffectiveStackTextOffsets
Apply.ApplyStackTextOffsets = MSUF_A2_ApplyStackTextOffsets
Apply.ApplyFont = MSUF_A2_ApplyFont

Apply.ApplyFontsFromGlobal = MSUF_A2_ApplyFontsFromGlobal
API.ApplyFontsFromGlobal = API.ApplyFontsFromGlobal or MSUF_A2_ApplyFontsFromGlobal

-- Global compatibility wrapper (older core/Options may call this)
if _G and type(_G.MSUF_Auras2_ApplyFontsFromGlobal) ~= "function" then
    _G.MSUF_Auras2_ApplyFontsFromGlobal = function()
        local f = API and API.ApplyFontsFromGlobal
        if f then return f() end
    end
end


Apply.ApplyStackCountAnchorStyle = MSUF_A2_ApplyStackCountAnchorStyle
Apply.AcquireIcon = AcquireIcon
Apply.HideUnused = HideUnused
Apply.LayoutIcons = LayoutIcons

Apply.RefreshAssignedIcons = MSUF_A2_RefreshAssignedIcons
Apply.RefreshAssignedIconsDelta = MSUF_A2_RefreshAssignedIconsDelta

Apply.RenderPreviewIcons = MSUF_A2_RenderPreviewIcons
Apply.RenderPreviewPrivateIcons = MSUF_A2_RenderPreviewPrivateIcons

-- Apply-only export (no globals)
Apply.ApplyAuraToIcon = ApplyAuraToIcon
