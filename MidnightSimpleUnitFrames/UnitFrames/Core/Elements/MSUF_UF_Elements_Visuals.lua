local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitThreatSituation = UnitThreatSituation
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local CheckInteractDistance = CheckInteractDistance
local UnitClass = UnitClass
local UnitReaction = UnitReaction
local UnitCanAttack = UnitCanAttack
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsUnit = UnitIsUnit
local UnitIsConnected = UnitIsConnected
local UnitIsPlayer = UnitIsPlayer
local UnitPhaseReason = UnitPhaseReason
local UnitInRange = UnitInRange
local SetPortraitTexture = SetPortraitTexture
local InCombatLockdown = InCombatLockdown
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local tonumber = tonumber
local type = type
local pairs = pairs
local ipairs = ipairs
local next = next
local select = select
local wipe = wipe
local max = math.max
local abs = math.abs
local floor = math.floor
local C_Spell = _G.C_Spell
local C_SpellBook = _G.C_SpellBook
local LibStub = _G.LibStub
local C_Spell_IsSpellInRange = C_Spell and C_Spell.IsSpellInRange
local C_SpellBook_IsSpellInSpellBook = C_SpellBook and C_SpellBook.IsSpellInSpellBook
local DispelState = UF and UF.DispelState or {}
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)

-- WoW marks select unit-API returns as "secret values" when reading them
-- would leak hidden combat info. Using a secret value in a comparison
-- ("if x == false then") or as a table key raises a hard error. Helpers
-- below use NotSecretValue to gate every comparison on a unit-API return.
--
-- `issecretvalue(v)` is a C builtin returning true for secret values, nil
-- otherwise; it never throws. We bind it once at module load — direct local
-- dispatch, single C call per check, no Lua-wrapper overhead.
local issecretvalue = _G.issecretvalue
local NotSecretValue
if issecretvalue then
    NotSecretValue = function(v) return not issecretvalue(v) end
else
    NotSecretValue = function(_) return true end
end

local EMPTY_EVENTS = {}
local PORTRAIT_2D_EVENTS = { "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION" }
local ALPHA_RANGE_UNIT_EVENTS = {
    "UNIT_CONNECTION", "UNIT_IN_RANGE_UPDATE", "UNIT_PHASE",
    "UNIT_CTR_OPTIONS", "UNIT_OTHER_PARTY_CHANGED",
}
local ALPHA_RANGE_GLOBAL_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UNIT_INVENTORY_CHANGED",
}
local ALPHA_RANGE_TARGET_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UNIT_INVENTORY_CHANGED",
    "PLAYER_TARGET_CHANGED",
}
local ALPHA_RANGE_FOCUS_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UNIT_INVENTORY_CHANGED",
    "PLAYER_FOCUS_CHANGED",
}
local ALPHA_RANGE_TARGET_TARGET_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UNIT_INVENTORY_CHANGED",
    "PLAYER_TARGET_CHANGED", "UNIT_TARGET",
}
local ALPHA_RANGE_FOCUS_TARGET_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UNIT_INVENTORY_CHANGED",
    "PLAYER_FOCUS_CHANGED", "UNIT_TARGET",
}
local ALPHA_RANGE_BOSS_EVENTS = {
    "SPELL_UPDATE_COOLDOWN", "SPELLS_CHANGED", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "INSTANCE_ENCOUNTER_ENGAGE_UNIT",
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "UNIT_INVENTORY_CHANGED",
}
local BORDER_AURA_EVENTS = { "UNIT_AURA" }
local BORDER_THREAT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local DISPEL_CAPABILITY_EVENTS = {
    "PLAYER_SPECIALIZATION_CHANGED",
    "ACTIVE_PLAYER_SPECIALIZATION_CHANGED",
    "PLAYER_TALENT_UPDATE",
    "TRAIT_CONFIG_UPDATED",
    "SPELLS_CHANGED",
}

local function IsDispelCapabilityEvent(event)
    return event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "ACTIVE_PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "SPELLS_CHANGED"
end
local WHITE = "Interface\\Buttons\\WHITE8x8"
local MEDIA_ROOT = "Interface\\AddOns\\" .. tostring(addonName or "MidnightSimpleUnitFrames") .. "\\Media\\"
local DISPEL_OVERLAY_TEXTURES = {
    TOP = MEDIA_ROOT .. "MSUF_Grad_V.tga",
    BOTTOM = MEDIA_ROOT .. "MSUF_Grad_V_Rev.tga",
    LEFT = MEDIA_ROOT .. "MSUF_Grad_H.tga",
    RIGHT = MEDIA_ROOT .. "MSUF_Grad_H_Rev.tga",
}
local TARGET_INTERACT_DISTANCE_INDEX = 4
local RANGE_CHECK_CACHE_AGE = 0.25
local QUESTION_MARK = "Interface\\ICONS\\INV_Misc_QuestionMark"
local ADDON_PATH = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames")
local PORTRAIT_MASKS = {
    SQUARE = WHITE,
    CIRCLE = ADDON_PATH .. "\\Media\\Masks\\circle_mask.tga",
    ROUNDED = ADDON_PATH .. "\\Media\\Masks\\rounded_mask.tga",
    DIAMOND = ADDON_PATH .. "\\Media\\Masks\\diamond_mask.tga",
}
local DYNAMIC_PORTRAIT_BORDER = {
    CLASS_COLOR = true,
    REACTION = true,
}
local QUEUED_2D_PORTRAIT_EVENTS = {
    UNIT_PORTRAIT_UPDATE = true,
    UNIT_MODEL_CHANGED = true,
    UNIT_CONNECTION = true,
    MSUF_UNIT_IDENTITY_SOFT = true,
}

local function SetShown(obj, show)
    if not obj then
        return
    end
    show = show == true
    if obj._msufShown == show then
        return
    end
    obj._msufShown = show
    if obj.SetShown then
        obj:SetShown(show)
    elseif show then
        obj:Show()
    else
        obj:Hide()
    end
end

local function Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then
        value = fallback or 1
    end
    if value < 0 then
        return 0
    elseif value > 1 then
        return 1
    end
    return value
end

local function AlphaDiffers(current, target)
    if type(current) ~= "number" then
        return true
    end
    return abs(current - target) > 0.001
end

local function SetFrameAlpha(frame, alpha)
    if not (frame and frame.SetAlpha) then
        return
    end
    alpha = Clamp01(alpha, 1)
    if frame._msufLastAlpha == alpha then
        local current = frame.GetAlpha and frame:GetAlpha()
        if current == nil or not AlphaDiffers(current, alpha) then
            return
        end
    end
    frame:SetAlpha(alpha)
    frame._msufLastAlpha = alpha
end

local function SetAlphaCached(obj, alpha, field, force)
    if not (obj and obj.SetAlpha) then
        return
    end
    alpha = Clamp01(alpha, 1)
    field = field or "_msufAlpha"
    if force or obj[field] == nil or AlphaDiffers(obj[field], alpha) then
        obj:SetAlpha(alpha)
        obj[field] = alpha
    end
end

local function SetAlphaFromBool(obj, boolValue, inAlpha, outAlpha, field)
    if not (obj and obj.SetAlpha) then
        return
    end
    if boolValue == false then
        SetAlphaCached(obj, outAlpha, field)
    else
        SetAlphaCached(obj, inAlpha, field)
    end
end

local Portrait = {}
local portraitQueue = {}
local portraitQueueCount = 0
local portraitQueueDriver
local portraitQueueScheduled = false
local ApplyUnitPortrait
local ResolvePortraitBorderColor
local PortraitBorderNeedsUpdate
local LayoutPortraitBorder

local function SetTextureCached(texture, value)
    if texture and texture._msufTexture ~= value then
        texture:SetTexture(value)
        texture._msufTexture = value
        texture._msufAtlas = nil
    end
end

local function SetTexCoordCached(texture, l, r, t, b)
    if texture and (texture._msufL ~= l or texture._msufR ~= r or texture._msufT ~= t or texture._msufB ~= b) then
        texture:SetTexCoord(l, r, t, b)
        texture._msufL, texture._msufR, texture._msufT, texture._msufB = l, r, t, b
    end
end

local function SetAtlasCached(texture, atlas)
    if texture and texture.SetAtlas and texture._msufAtlas ~= atlas then
        texture:SetAtlas(atlas)
        texture._msufAtlas = atlas
        texture._msufTexture = nil
        texture._msufL, texture._msufR, texture._msufT, texture._msufB = nil, nil, nil, nil
    end
end

local function SetVertexColorCached(texture, r, g, b, a)
    if texture and (texture._msufR ~= r or texture._msufG ~= g or texture._msufBv ~= b or texture._msufA ~= a) then
        texture:SetVertexColor(r, g, b, a)
        texture._msufR, texture._msufG, texture._msufBv, texture._msufA = r, g, b, a
    end
end

local function ClearPortraitTexture(texture)
    if not texture then
        return
    end
    texture:SetTexture(nil)
    texture._msufTexture = nil
    texture._msufAtlas = nil
end

local function PortraitFrameVisible(frame)
    if not frame then
        return false
    end
    if frame.IsShown and not frame:IsShown() then
        return false
    end
    local holder = frame.MSUFPortraitHolder
    if holder and holder.IsShown and not holder:IsShown() then
        return false
    end
    return holder ~= nil
end

local function FlushQueuedPortraits()
    portraitQueueScheduled = false
    if portraitQueueDriver then
        portraitQueueDriver:Hide()
    end

    local count = portraitQueueCount
    portraitQueueCount = 0
    for i = 1, count do
        local frame = portraitQueue[i]
        portraitQueue[i] = nil
        if frame and frame._msufPortraitQueued == true then
            frame._msufPortraitQueued = nil
            local p = frame.MSUFSpec and frame.MSUFSpec.portrait
            local texture = frame.portrait
            if p and p.enabled == true and p.render ~= "CLASS" and texture and PortraitFrameVisible(frame) then
                frame._msufPortraitNeedsVisibleRefresh = nil
                ApplyUnitPortrait(texture, frame.unit)
                if PortraitBorderNeedsUpdate("MSUF_PORTRAIT_FLUSH", p) then
                    LayoutPortraitBorder(frame.MSUFPortraitHolder, p, ResolvePortraitBorderColor(frame, p))
                end
            elseif p and p.enabled == true and texture and not PortraitFrameVisible(frame) then
                frame._msufPortraitNeedsVisibleRefresh = true
            end
        end
    end
end

local function QueuePortraitUpdate(frame)
    if not frame then
        return
    end
    if frame._msufPortraitQueued ~= true then
        portraitQueueCount = portraitQueueCount + 1
        portraitQueue[portraitQueueCount] = frame
        frame._msufPortraitQueued = true
    end
    if portraitQueueScheduled then
        return
    end
    portraitQueueScheduled = true
    if not portraitQueueDriver then
        portraitQueueDriver = CreateFrame("Frame")
        portraitQueueDriver:Hide()
        portraitQueueDriver:SetScript("OnUpdate", FlushQueuedPortraits)
    end
    portraitQueueDriver:Show()
end

local function EnsurePortrait(frame)
    local holder = frame.MSUFPortraitHolder
    if holder then
        return holder, frame.portrait
    end

    holder = CreateFrame("Frame", nil, frame)
    holder:EnableMouse(false)
    frame.MSUFPortraitHolder = holder
    if frame.HookScript and not frame._msufPortraitOnShowHooked then
        frame._msufPortraitOnShowHooked = true
        frame:HookScript("OnShow", function(self)
            if self._msufPortraitNeedsVisibleRefresh == true and Portrait.Update then
                self._msufPortraitNeedsVisibleRefresh = nil
                Portrait.Update(self, "MSUF_PORTRAIT_ONSHOW", self.unit)
            end
        end)
    end

    local bg = holder:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture(WHITE)
    bg:SetAllPoints(holder)
    bg:Hide()
    holder.bg = bg
    frame.MSUFPortraitBG = bg

    local tex = holder:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(holder)
    frame.portrait = tex
    frame.Portrait = tex

    if holder.CreateMaskTexture and tex.AddMaskTexture then
        local mask = holder:CreateMaskTexture()
        mask:SetAllPoints(holder)
        tex:AddMaskTexture(mask)
        bg:AddMaskTexture(mask)
        holder.mask = mask
    end

    local border = CreateFrame("Frame", nil, holder)
    border:EnableMouse(false)
    border:SetAllPoints(holder)
    holder.border = border
    frame.MSUFPortraitBorder = border

    local edges = {}
    for i = 1, 4 do
        local edge = border:CreateTexture(nil, "OVERLAY")
        edge:SetTexture(WHITE)
        edge:Hide()
        edges[i] = edge
    end
    holder.edges = edges
    return holder, tex
end

local function ApplyPortraitMask(holder, p)
    local mask = holder and holder.mask
    if not mask then
        return
    end
    SetTextureCached(mask, PORTRAIT_MASKS[p and p.shape or "SQUARE"] or WHITE)
end

local function LayoutPortrait(frame, p)
    local holder = frame.MSUFPortraitHolder
    if not holder then
        return
    end

    local size = tonumber(p and p.size) or tonumber(frame.MSUFSpec and frame.MSUFSpec.height) or 30
    if size < 1 then
        size = 1
    end
    local side = p and p.side == "RIGHT" and "RIGHT" or "LEFT"
    local x = tonumber(p and p.x) or 0
    local y = tonumber(p and p.y) or 0
    local anchor = frame.Health or frame.hpBar or frame
    if frame._msufPowerBarReserved then
        anchor = frame
    end

    local baseLevel = frame:GetFrameLevel() or 1
    if frame.Health and frame.Health.GetFrameLevel then
        baseLevel = frame.Health:GetFrameLevel() or baseLevel
    end
    if holder._msufLevel ~= baseLevel + 6 then
        holder:SetFrameLevel(baseLevel + 6)
        holder._msufLevel = baseLevel + 6
    end
    if holder.border and holder.border._msufLevel ~= baseLevel + 7 then
        holder.border:SetFrameLevel(baseLevel + 7)
        holder.border._msufLevel = baseLevel + 7
    end

    if holder._msufSize ~= size then
        holder:SetSize(size, size)
        holder._msufSize = size
    end
    if holder._msufSide ~= side or holder._msufX ~= x or holder._msufY ~= y or holder._msufAnchor ~= anchor then
        holder:ClearAllPoints()
        if side == "RIGHT" then
            holder:SetPoint("LEFT", anchor, "RIGHT", x, y)
        else
            holder:SetPoint("RIGHT", anchor, "LEFT", x, y)
        end
        holder._msufSide, holder._msufX, holder._msufY, holder._msufAnchor = side, x, y, anchor
    end
end

local function UnitClassToken(unit)
    if UnitClass then
        local _, token = UnitClass(unit)
        if type(token) == "string" then
            return token
        end
    end
    return nil
end

local function ApplyClassPortrait(texture, unit, p, class)
    class = class or UnitClassToken(unit)
    local classStyle = p and p.classStyle or "BLIZZARD"
    if class and classStyle == "BLIZZARD" and texture and texture.SetAtlas then
        SetAtlasCached(texture, "classicon-" .. class)
        return
    end

    local PM = MSUF and MSUF.PortraitMedia
    local path, l, r, t, b
    if PM and PM.ResolveClassPortrait then
        local visual = PM.ResolveClassPortrait(class, classStyle)
        if type(visual) == "table" then
            path, l, r, t, b = visual.texture, visual.left, visual.right, visual.top, visual.bottom
        end
    end
    if not path then
        path, l, r, t, b = QUESTION_MARK, 0, 1, 0, 1
    end
    SetTextureCached(texture, path)
    SetTexCoordCached(texture, l or 0, r or 1, t or 0, b or 1)
end

ApplyUnitPortrait = function(texture, unit)
    SetTexCoordCached(texture, 0.08, 0.92, 0.08, 0.92)
    texture._msufTexture = nil
    texture._msufAtlas = nil
    if SetPortraitTexture then
        SetPortraitTexture(texture, unit, true)
    else
        SetTextureCached(texture, QUESTION_MARK)
    end
end

ResolvePortraitBorderColor = function(frame, p, class)
    local border = p and p.border
    local style = border and border.style or "NONE"
    if style == "NONE" then
        return nil
    end
    if style == "CLASS_COLOR" then
        class = class or UnitClassToken(frame.unit)
        local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
        if c then
            return c.r or 1, c.g or 1, c.b or 1, 1
        end
        return 1, 1, 1, 1
    elseif style == "REACTION" then
        local reaction = UnitReaction and UnitReaction(frame.unit, "player")
        reaction = tonumber(reaction)
        if reaction then
            if reaction <= 2 then return 1, 0, 0, 1 end
            if reaction <= 4 then return 1, 0.6, 0, 1 end
            return 0, 1, 0, 1
        end
        return 1, 1, 1, 1
    end
    return border.r or 1, border.g or 1, border.b or 1, border.a or 1
end

PortraitBorderNeedsUpdate = function(event, p)
    if event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" then
        return true
    end
    local style = p and p.border and p.border.style
    return DYNAMIC_PORTRAIT_BORDER[style] == true
end

LayoutPortraitBorder = function(holder, p, r, g, b, a)
    local border = holder and holder.border
    local edges = holder and holder.edges
    if not (border and edges) then
        return
    end
    if not r then
        if edges then
            for i = 1, 4 do
                SetShown(edges[i], false)
            end
        end
        return
    end

    local cfg = p and p.border
    local thick = max(1, tonumber(cfg and cfg.thickness) or 2)
    local fill = cfg and cfg.fill == true
    local key = thick .. "|" .. (fill and "1" or "0")
    local top, bottom, left, right = edges[1], edges[2], edges[3], edges[4]
    if holder._msufBorderKey ~= key then
        top:ClearAllPoints()
        bottom:ClearAllPoints()
        left:ClearAllPoints()
        right:ClearAllPoints()
        if fill then
            top:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
            top:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
            bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
            bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
            left:SetPoint("TOPLEFT", holder, "TOPLEFT", 0, 0)
            left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", 0, 0)
            right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", 0, 0)
            right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", 0, 0)
        else
            top:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
            top:SetPoint("TOPRIGHT", holder, "TOPRIGHT", thick, thick)
            bottom:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -thick, -thick)
            bottom:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
            left:SetPoint("TOPLEFT", holder, "TOPLEFT", -thick, thick)
            left:SetPoint("BOTTOMLEFT", holder, "BOTTOMLEFT", -thick, -thick)
            right:SetPoint("TOPRIGHT", holder, "TOPRIGHT", thick, thick)
            right:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", thick, -thick)
        end
        top:SetHeight(thick)
        bottom:SetHeight(thick)
        left:SetWidth(thick)
        right:SetWidth(thick)
        holder._msufBorderKey = key
    end
    for i = 1, 4 do
        SetVertexColorCached(edges[i], r, g, b, a)
        SetShown(edges[i], true)
    end
end

local function ApplyPortraitBackground(holder, p)
    local bg = holder and holder.bg
    local cfg = p and p.bg
    if not bg then
        return
    end
    if not (cfg and cfg.enabled == true) then
        SetShown(bg, false)
        return
    end
    SetVertexColorCached(bg, cfg.r or 0.05, cfg.g or 0.05, cfg.b or 0.05, cfg.a or 0.85)
    SetShown(bg, true)
end

function Portrait.GetEvents(frame, spec)
    local p = spec and spec.portrait
    if p and p.enabled == true and p.render ~= "CLASS" then
        return PORTRAIT_2D_EVENTS
    end
    return EMPTY_EVENTS
end

function Portrait.IsEnabled(frame, spec)
    return spec and spec.portrait and spec.portrait.enabled == true
end

function Portrait.Create(frame)
    EnsurePortrait(frame)
end

function Portrait.Apply(frame, spec)
    local p = spec and spec.portrait
    local holder = EnsurePortrait(frame)
    if not (p and p.enabled == true) then
        Portrait.Disable(frame)
        return
    end
    LayoutPortrait(frame, p)
    ApplyPortraitMask(holder, p)
    ApplyPortraitBackground(holder, p)
    LayoutPortraitBorder(holder, p, ResolvePortraitBorderColor(frame, p))
    SetShown(holder, true)
    SetShown(frame.portrait, true)
end

function Portrait.Disable(frame)
    local holder = frame.MSUFPortraitHolder
    frame._msufPortraitNeedsVisibleRefresh = nil
    if holder then
        SetShown(holder, false)
        if holder.bg then SetShown(holder.bg, false) end
        if holder.edges then
            for i = 1, 4 do
                SetShown(holder.edges[i], false)
            end
        end
    elseif frame.portrait then
        SetShown(frame.portrait, false)
    end
end

function Portrait.Update(frame, event, unit)
    local p = frame.MSUFSpec and frame.MSUFSpec.portrait
    local texture = frame.portrait
    if not (p and p.enabled == true and texture and frame.MSUFPortraitHolder) then
        return
    end
    unit = unit or frame.unit
    if not PortraitFrameVisible(frame) then
        frame._msufPortraitNeedsVisibleRefresh = true
        if p.render ~= "CLASS" and event == "MSUF_UNIT_IDENTITY_SOFT" then
            ClearPortraitTexture(texture)
        end
        return
    end

    local class
    if p.render == "CLASS" then
        frame._msufPortraitNeedsVisibleRefresh = nil
        frame._msufPortraitQueued = nil
        class = UnitClassToken(unit)
        ApplyClassPortrait(texture, unit, p, class)
    else
        if QUEUED_2D_PORTRAIT_EVENTS[event] == true then
            if event == "MSUF_UNIT_IDENTITY_SOFT" then
                ClearPortraitTexture(texture)
            end
            QueuePortraitUpdate(frame)
        else
            frame._msufPortraitNeedsVisibleRefresh = nil
            frame._msufPortraitQueued = nil
            ApplyUnitPortrait(texture, unit)
        end
    end
    if PortraitBorderNeedsUpdate(event, p) then
        LayoutPortraitBorder(frame.MSUFPortraitHolder, p, ResolvePortraitBorderColor(frame, p, class))
    end
end

local Alpha = {}

local TARGET_RANGE_SPELLS = {
    enemy = {
        DEATHKNIGHT = { 49576, 47541 },
        DEMONHUNTER = { 185123, 183752, 204021 },
        DRUID = { 8921, 5176, 339, 6795, 33786, 22568 },
        EVOKER = { 362969 },
        HUNTER = { 75, 466930 },
        MAGE = { 116, 133, 44425, 44614, 118, 5019 },
        MONK = { 117952, 115546, 115078, 100780 },
        PALADIN = { 20473, 20271, 62124, 183218, 853, 35395 },
        PRIEST = { 585, 8092, 589, 5019 },
        ROGUE = { 185565, 36554, 185763, 2094, 921 },
        SHAMAN = { 188196, 8042, 117014, 370, 73899 },
        WARLOCK = { 686, 232670, 234153, 198590, 5782, 5019 },
        WARRIOR = { 355, 100, 5246 },
    },
    friendly = {
        DEATHKNIGHT = { 47541 },
        DEMONHUNTER = {},
        DRUID = { 8936, 774, 88423, 2782 },
        EVOKER = { 361469, 355913, 360823 },
        HUNTER = {},
        MAGE = { 1459, 475 },
        MONK = { 116670, 115450 },
        PALADIN = { 19750, 85673, 4987, 213644 },
        PRIEST = { 2061, 17, 21562, 527 },
        ROGUE = { 57934, 36554, 921 },
        SHAMAN = { 8004, 188070, 546 },
        WARRIOR = { 3411 },
        WARLOCK = { 20707, 5697 },
    },
    resurrect = {
        DEATHKNIGHT = { 61999 },
        DEMONHUNTER = {},
        DRUID = { 50769, 20484 },
        EVOKER = { 361227 },
        HUNTER = {},
        MAGE = {},
        MONK = { 115178 },
        PALADIN = { 7328, 391054 },
        PRIEST = { 2006, 212036 },
        ROGUE = {},
        SHAMAN = { 2008 },
        WARRIOR = {},
        WARLOCK = { 20707 },
    },
    pet = {
        DEATHKNIGHT = { 47541 },
        DEMONHUNTER = {},
        DRUID = {},
        EVOKER = {},
        HUNTER = { 136 },
        MAGE = {},
        MONK = {},
        PALADIN = {},
        PRIEST = {},
        ROGUE = {},
        SHAMAN = {},
        WARRIOR = {},
        WARLOCK = { 755 },
    },
}

local activeTargetRangeSpells = {
    enemy = {},
    friendly = {},
    resurrect = {},
    pet = {},
}
local targetRangeSpellsBuilt

local TEXT_ALPHA_FIELDS = {
    "nameText",
    "levelText",
    "hpTextLeft",
    "hpTextCenter",
    "hpTextRight",
    "powerTextLeft",
    "powerTextCenter",
    "powerTextRight",
    "totInlineSep",
    "totInlineText",
    "raidGroupNameText",
    "statusIndicatorText",
}

local STATUS_ALPHA_FIELDS = {
    "raidTargetIcon",
    "LeaderIndicator",
    "levelText",
    "raidGroupNameText",
    "eliteIcon",
    "statusIndicatorText",
    "combatStateIndicatorIcon",
    "restingIndicatorIcon",
    "incomingResIndicatorIcon",
}

local function ClearAlphaField(obj, field)
    if obj then
        obj[field] = nil
    end
end

local function StatusBarTexture(bar)
    return bar and bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
end

local function SetStatusBarLayerAlpha(bar, alpha, field, force)
    if not bar then
        return
    end
    SetAlphaCached(bar, 1, (field or "_msufAlphaStatusBar") .. "Object", force)
    SetAlphaCached(StatusBarTexture(bar), alpha, field or "_msufAlphaStatusTexture", force)
end

local function SetTextureLayerAlpha(texture, alpha, field, force)
    SetAlphaCached(texture, alpha, field or "_msufAlphaLayer", force)
end

local function SetTextLayerAlpha(frame, alpha, force)
    for i = 1, #TEXT_ALPHA_FIELDS do
        SetAlphaCached(frame and frame[TEXT_ALPHA_FIELDS[i]], alpha, "_msufAlphaText", force)
    end
end

local function SetStatusLayerAlpha(frame, alpha, force)
    for i = 1, #STATUS_ALPHA_FIELDS do
        local region = frame and frame[STATUS_ALPHA_FIELDS[i]]
        if region then
            local base = tonumber(region._msufStatusAlpha) or 1
            SetAlphaCached(region, base * alpha, "_msufAlphaStatus", force)
        end
    end
end

local function SetPortraitLayerAlpha(frame, alpha, force)
    SetAlphaCached(frame and frame.MSUFPortraitHolder, alpha, "_msufAlphaPortraitHolder", force)
    SetAlphaCached(frame and frame.portrait, 1, "_msufAlphaPortraitTexture", force)
end

local function ResetLegacyLayerAlphas(frame, force)
    if not frame then
        return
    end
    SetStatusBarLayerAlpha(frame.hpBar or frame.Health, 1, "_msufAlphaHealth", force)
    SetStatusBarLayerAlpha(frame.incomingHealBar, 1, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.absorbBar, 1, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.healAbsorbBar, 1, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.targetPowerBar or frame.Power or frame.powerBar, 1, "_msufAlphaPower", force)
    SetTextureLayerAlpha(frame.bg or frame.hpBarBG, 1, "_msufAlphaBackground", force)
    if frame.bg ~= frame.hpBarBG then
        SetTextureLayerAlpha(frame.hpBarBG, 1, "_msufAlphaBackground", force)
    end
    SetTextureLayerAlpha(frame.powerBarBG, 1, "_msufAlphaBackground", force)
    SetTextLayerAlpha(frame, 1, force)
    SetStatusLayerAlpha(frame, 1, force)
    SetPortraitLayerAlpha(frame, 1, force)
    frame._msufAlphaLayeredMode = nil
end

local rangeCheckLib
local rangeCheckCallbackRegistered

local function RequestRangeAlphaRefresh()
    if _G.MSUF_RequestAlphaRefresh then
        _G.MSUF_RequestAlphaRefresh(false)
    elseif _G.MSUF_RefreshAllUnitAlphas then
        _G.MSUF_RefreshAllUnitAlphas()
    elseif UF and UF.ForceUpdate then
        UF.ForceUpdate()
    end
end

local function GetRangeCheckLib()
    if rangeCheckLib ~= nil then
        return rangeCheckLib or nil
    end
    if type(LibStub) ~= "function" then
        rangeCheckLib = false
        return nil
    end
    local lib = LibStub("LibRangeCheck-3.0", true)
    if not lib then
        rangeCheckLib = false
        return nil
    end
    rangeCheckLib = lib
    if not rangeCheckCallbackRegistered
        and type(lib.RegisterCallback) == "function"
        and lib.CHECKERS_CHANGED
    then
        lib.RegisterCallback(MSUF, lib.CHECKERS_CHANGED, RequestRangeAlphaRefresh)
        rangeCheckCallbackRegistered = true
    end
    return lib
end

local function RangeCheckLibIsInRange(unit)
    local lib = GetRangeCheckLib()
    if not (lib and type(lib.GetRange) == "function") then
        return nil
    end

    local minRange, maxRange = lib:GetRange(unit, nil, true, RANGE_CHECK_CACHE_AGE)
    if maxRange ~= nil then
        return true
    end
    if minRange ~= nil then
        return false
    end
    return nil
end

local function UpdateActiveRangeSpells()
    targetRangeSpellsBuilt = true
    for category, spells in pairs(activeTargetRangeSpells) do
        wipe(spells)
    end
    if not C_SpellBook_IsSpellInSpellBook then
        return
    end
    local _, class = UnitClass and UnitClass("player")
    if not class then
        return
    end
    for category, classSpells in pairs(TARGET_RANGE_SPELLS) do
        local dst = activeTargetRangeSpells[category]
        local src = classSpells and classSpells[class]
        if dst and src then
            for i = 1, #src do
                local spellID = src[i]
                if C_SpellBook_IsSpellInSpellBook(spellID, nil, true) then
                    dst[spellID] = true
                end
            end
        end
    end
end

local function EnsureRangeSpells()
    if targetRangeSpellsBuilt ~= true then
        UpdateActiveRangeSpells()
    end
end

local function InteractDistance(unit)
    if not CheckInteractDistance or (InCombatLockdown and InCombatLockdown()) then
        return nil
    end
    return CheckInteractDistance(unit, TARGET_INTERACT_DISTANCE_INDEX)
end

local function UnitSpellRange(unit, spells)
    if not C_Spell_IsSpellInRange then
        return nil
    end
    local outOfRange
    for spellID in pairs(spells) do
        local inRange = C_Spell_IsSpellInRange(spellID, unit)
        if inRange == true or inRange == 1 then
            return true
        elseif inRange == false or inRange == 0 then
            outOfRange = true
        end
    end
    if outOfRange then
        return false
    end
    return nil
end

local function UnitInSpellsRange(unit, category)
    EnsureRangeSpells()
    local spells = activeTargetRangeSpells[category]
    if not spells or not next(spells) then
        return InteractDistance(unit)
    end

    local inRange = UnitSpellRange(unit, spells)
    if inRange ~= true and not (InCombatLockdown and InCombatLockdown()) then
        local interactDistance = InteractDistance(unit)
        if NotSecretValue(interactDistance) and interactDistance ~= nil then
            return interactDistance
        end
    end
    if inRange == nil then
        return nil
    end
    return inRange and true or false
end

local function FriendlyRangeGuard(unit)
    local canAttack = UnitCanAttack and UnitCanAttack("player", unit)
    if NotSecretValue(canAttack) and canAttack then
        return nil
    end

    local isPlayer = UnitIsPlayer and UnitIsPlayer(unit)
    if NotSecretValue(isPlayer) and isPlayer and UnitPhaseReason then
        local phaseReason = UnitPhaseReason(unit)
        if NotSecretValue(phaseReason) and phaseReason then
            return false
        end
    end
    if UnitInRange then
        local inRange, checkedRange = UnitInRange(unit)
        if NotSecretValue(checkedRange) and checkedRange and NotSecretValue(inRange) and not inRange then
            return false
        end
    end
    return nil
end

local function FriendlyIsInRange(unit)
    local guarded = FriendlyRangeGuard(unit)
    if guarded ~= nil then
        return guarded
    end
    return UnitInSpellsRange(unit, "friendly")
end

local function UnitIsInRange(unit)
    if not unit then
        return true
    end
    local exists = UnitExists and UnitExists(unit)
    if UnitExists and NotSecretValue(exists) and not exists then
        return true
    end
    if unit == "player" then
        return true
    end
    if UnitIsUnit then
        local isPlayer = UnitIsUnit(unit, "player")
        if NotSecretValue(isPlayer) and isPlayer then
            return true
        end
    end

    local connected = UnitIsConnected and UnitIsConnected(unit)
    if NotSecretValue(connected) and connected == false then
        return false
    end

    local guarded = FriendlyRangeGuard(unit)
    if guarded ~= nil then
        return guarded
    end

    local libInRange = RangeCheckLibIsInRange(unit)
    if libInRange ~= nil then
        return libInRange
    end

    local deadOrGhost = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if NotSecretValue(deadOrGhost) and deadOrGhost then
        return UnitInSpellsRange(unit, "resurrect")
    end
    local canAttack = UnitCanAttack and UnitCanAttack("player", unit)
    if NotSecretValue(canAttack) and canAttack then
        return UnitInSpellsRange(unit, "enemy")
    end

    if UnitIsUnit then
        local isPet = UnitIsUnit(unit, "pet")
        if NotSecretValue(isPet) and isPet then
            return UnitInSpellsRange(unit, "pet")
        end
    end

    return FriendlyIsInRange(unit)
end

MSUF.UnitIsInRange = UnitIsInRange
_G.MSUF_UnitIsInRange = UnitIsInRange

local function NormalizeAlphaLayerMode(mode)
    if mode == true or mode == 1 or mode == "background" or mode == "backdrop" or mode == "bg" then
        return "background"
    elseif mode == 2 or mode == "health" or mode == "hp" or mode == "hpbar" then
        return "health"
    end
    return "foreground"
end

local function NormalizeRangeLayerMode(mode)
    return NormalizeAlphaLayerMode(mode) == "health" and "health" or "frame"
end

local function InCombatForEvent(event)
    if event == "PLAYER_REGEN_DISABLED" then
        return true
    elseif event == "PLAYER_REGEN_ENABLED" then
        return false
    elseif _G.MSUF_InCombat ~= nil then
        return _G.MSUF_InCombat == true
    end
    return InCombatLockdown and InCombatLockdown() and true or false
end

local function AlphaPair(cfg, mode)
    if not cfg then
        return 1, 1
    end
    local inAlpha = cfg.inCombat or 1
    local outAlpha = cfg.outCombat or 1
    if cfg.layered ~= true then
        return inAlpha, outAlpha
    end
    if mode == "background" then
        return cfg.backgroundInCombat or inAlpha, cfg.backgroundOutOfCombat or outAlpha
    elseif mode == "health" then
        return cfg.healthInCombat or cfg.foregroundInCombat or inAlpha,
            cfg.healthOutOfCombat or cfg.foregroundOutOfCombat or outAlpha
    end
    return cfg.foregroundInCombat or inAlpha, cfg.foregroundOutOfCombat or outAlpha
end

local function CompileAlphaRuntime(frame, cfg, force)
    if not frame then
        return nil
    end
    if not cfg then
        frame._msufAlphaRuntimeCfg = nil
        frame._msufAlphaRuntime = nil
        return nil
    end
    if force ~= true and frame._msufAlphaRuntimeCfg == cfg and frame._msufAlphaRuntime then
        return frame._msufAlphaRuntime
    end

    local rt = frame._msufAlphaRuntime
    if not rt then
        rt = {}
        frame._msufAlphaRuntime = rt
    end
    frame._msufAlphaRuntimeCfg = cfg

    local baseIn = cfg.inCombat or 1
    local baseOut = cfg.outCombat or 1
    local layered = cfg.layered == true
    local layerMode = NormalizeAlphaLayerMode(cfg.layerMode)

    rt.layered = layered
    rt.frameIn = layered and 1 or baseIn
    rt.frameOut = layered and 1 or baseOut
    rt.fgIn = cfg.foregroundInCombat or baseIn
    rt.fgOut = cfg.foregroundOutOfCombat or baseOut
    rt.bgIn = cfg.backgroundInCombat or baseIn
    rt.bgOut = cfg.backgroundOutOfCombat or baseOut
    rt.hpIn = layerMode == "health" and (cfg.healthInCombat or cfg.foregroundInCombat or baseIn) or rt.fgIn
    rt.hpOut = layerMode == "health" and (cfg.healthOutOfCombat or cfg.foregroundOutOfCombat or baseOut) or rt.fgOut
    rt.powerIn = layerMode == "health" and 1 or rt.fgIn
    rt.powerOut = layerMode == "health" and 1 or rt.fgOut
    rt.preserveHPColor = cfg.preserveHPColor == true
    rt.rangeMode = cfg.rangeLayerMode == "health" and "health" or "frame"
    rt.rangePortrait = cfg.rangePortrait == true
    rt.rangeEnabled = cfg.rangeEnabled == true
    rt.rangeIn = cfg.rangeIn or 1
    rt.rangeOut = cfg.rangeOut or 0.5
    return rt
end

local function CurrentAlpha(cfg, mode, event)
    local inAlpha, outAlpha = AlphaPair(cfg, mode)
    return InCombatForEvent(event) and inAlpha or outAlpha
end

local function AlphaNeedsCombatRefresh(cfg)
    return cfg and cfg.combatEvents == true
end

local function EnsureAlphaFrameSet(field)
    local frames = Alpha[field]
    if type(frames) ~= "table" then
        frames = setmetatable({}, { __mode = "k" })
        Alpha[field] = frames
    end
    return frames
end

local function TrackAlphaFrame(frame, cfg)
    if not frame then
        return
    end
    EnsureAlphaFrameSet("activeFrames")[frame] = cfg and cfg.active == true or nil
    EnsureAlphaFrameSet("combatFrames")[frame] = AlphaNeedsCombatRefresh(cfg) and true or nil
    EnsureAlphaFrameSet("rangeFrames")[frame] = cfg and cfg.rangeEnabled == true or nil
end

local function UntrackAlphaFrame(frame)
    if not frame then
        return
    end
    if Alpha.activeFrames then
        Alpha.activeFrames[frame] = nil
    end
    if Alpha.combatFrames then
        Alpha.combatFrames[frame] = nil
    end
    if Alpha.rangeFrames then
        Alpha.rangeFrames[frame] = nil
    end
end

local function RangeMultiplierFromState(frame, rt, inRange)
    frame._msufAlphaRangeKnown = inRange
    return inRange and (rt.rangeIn or 1) or (rt.rangeOut or 0.5)
end

local function CurrentRangeMultiplier(frame, rt, event, eventUnit, eventRange)
    if not (rt and rt.rangeEnabled == true and frame and frame.unit) then
        return 1
    end
    local manual = tonumber(frame._msufManualRangeMul)
    if manual ~= nil then
        return Clamp01(manual, 1)
    end

    if event == "UNIT_IN_RANGE_UPDATE" and (not eventUnit or eventUnit == frame.unit) then
        if NotSecretValue(eventRange) then
            if eventRange == true or eventRange == 1 then
                return RangeMultiplierFromState(frame, rt, true)
            elseif eventRange == false or eventRange == 0 then
                return RangeMultiplierFromState(frame, rt, false)
            end
        end
    end

    local inRange = UnitIsInRange(frame.unit)
    if inRange == nil then
        inRange = true
    end
    return RangeMultiplierFromState(frame, rt, inRange and true or false)
end

local function ApplyLayeredAlpha(frame, frameAlpha, fgAlpha, bgAlpha, hpAlpha, powerAlpha, healthBgAlpha, portraitAlpha, statusAlpha, force)
    SetFrameAlpha(frame, frameAlpha)
    SetStatusBarLayerAlpha(frame.hpBar or frame.Health, hpAlpha, "_msufAlphaHealth", force)
    SetStatusBarLayerAlpha(frame.incomingHealBar, hpAlpha, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.absorbBar, hpAlpha, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.healAbsorbBar, hpAlpha, "_msufAlphaPrediction", force)
    SetStatusBarLayerAlpha(frame.targetPowerBar or frame.Power or frame.powerBar, powerAlpha, "_msufAlphaPower", force)
    SetTextureLayerAlpha(frame.bg or frame.hpBarBG, healthBgAlpha, "_msufAlphaBackground", force)
    if frame.bg ~= frame.hpBarBG then
        SetTextureLayerAlpha(frame.hpBarBG, healthBgAlpha, "_msufAlphaBackground", force)
    end
    SetTextureLayerAlpha(frame.powerBarBG, bgAlpha, "_msufAlphaBackground", force)
    SetTextLayerAlpha(frame, 1, force)
    SetStatusLayerAlpha(frame, statusAlpha or fgAlpha, force)
    SetPortraitLayerAlpha(frame, portraitAlpha, force)
    frame._msufAlphaLayeredMode = true
end

local function ApplyCompiledAlpha(frame, cfg, event, eventUnit, eventRange)
    if not frame then
        return
    end
    if not cfg then
        SetFrameAlpha(frame, 1)
        ResetLegacyLayerAlphas(frame, true)
        return
    end
    local force = event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" or event == "MSUF_VISUALS"
        or event == "MSUF_ALPHA"
    local rt = CompileAlphaRuntime(frame, cfg, force)
    if not rt then
        return
    end

    local inCombat
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif _G.MSUF_InCombat ~= nil then
        inCombat = _G.MSUF_InCombat == true
    else
        inCombat = InCombatLockdown and InCombatLockdown() and true or false
    end

    local frameAlpha = inCombat and rt.frameIn or rt.frameOut
    local fgAlpha = 1
    local bgAlpha = 1
    local hpAlpha = 1
    local powerAlpha = 1
    local healthBgAlpha = 1
    local portraitAlpha = 1
    local statusAlpha = 1

    if rt.layered then
        fgAlpha = inCombat and rt.fgIn or rt.fgOut
        bgAlpha = inCombat and rt.bgIn or rt.bgOut
        hpAlpha = inCombat and rt.hpIn or rt.hpOut
        powerAlpha = inCombat and rt.powerIn or rt.powerOut
        healthBgAlpha = rt.preserveHPColor == true and hpAlpha or bgAlpha
        statusAlpha = fgAlpha
    end

    local rangeMul = CurrentRangeMultiplier(frame, rt, event, eventUnit, eventRange)
    local rangeMode = rt.rangeMode
    if rangeMul < 1 then
        if rangeMode == "health" then
            hpAlpha = hpAlpha * rangeMul
            healthBgAlpha = healthBgAlpha * rangeMul
            if rt.rangePortrait == true then
                portraitAlpha = portraitAlpha * rangeMul
            end
        else
            frameAlpha = frameAlpha * rangeMul
        end
    end

    if _G.MSUF_UnitEditModeActive == true and frameAlpha < 0.35 then
        frameAlpha = 0.35
    end

    local useLayeredApply = rt.layered or (rangeMode == "health" and rangeMul < 1)
    if not force
        and frame._msufAlphaLastLayered == useLayeredApply
        and frame._msufAlphaLastFrame == frameAlpha
        and frame._msufAlphaLastFG == fgAlpha
        and frame._msufAlphaLastBG == bgAlpha
        and frame._msufAlphaLastHP == hpAlpha
        and frame._msufAlphaLastPower == powerAlpha
        and frame._msufAlphaLastHealthBG == healthBgAlpha
        and frame._msufAlphaLastPortrait == portraitAlpha
        and frame._msufAlphaLastStatus == statusAlpha
        and frame._msufAlphaRangeMul == rangeMul then
        return
    end

    if useLayeredApply then
        ApplyLayeredAlpha(frame, frameAlpha, fgAlpha, bgAlpha, hpAlpha, powerAlpha, healthBgAlpha, portraitAlpha, statusAlpha, force)
    else
        SetFrameAlpha(frame, frameAlpha)
        if frame._msufAlphaLayeredMode == true or event == "MSUF_APPLY" or event == "MSUF_FORCE_UPDATE" then
            ResetLegacyLayerAlphas(frame, force)
        end
    end

    frame._msufAlphaEffective = frameAlpha
    frame._msufAlphaRangeMul = rangeMul
    frame._msufAlphaLastLayered = useLayeredApply
    frame._msufAlphaLastFrame = frameAlpha
    frame._msufAlphaLastFG = fgAlpha
    frame._msufAlphaLastBG = bgAlpha
    frame._msufAlphaLastHP = hpAlpha
    frame._msufAlphaLastPower = powerAlpha
    frame._msufAlphaLastHealthBG = healthBgAlpha
    frame._msufAlphaLastPortrait = portraitAlpha
    frame._msufAlphaLastStatus = statusAlpha
end

function Alpha.IsEnabled(frame, spec)
    return spec and spec.alpha and spec.alpha.active == true
end

function Alpha.GetEvents(frame, spec)
    local cfg = spec and spec.alpha
    if cfg and cfg.rangeEnabled == true then
        return ALPHA_RANGE_UNIT_EVENTS
    end
    return EMPTY_EVENTS
end

function Alpha.GetUnitlessEvents(frame, spec)
    local cfg = spec and spec.alpha
    if not cfg then
        return EMPTY_EVENTS
    end
    if cfg.rangeEnabled == true then
        local unit = frame and frame.unit
        if unit == "targettarget" then
            return ALPHA_RANGE_TARGET_TARGET_EVENTS
        elseif unit == "focustarget" then
            return ALPHA_RANGE_FOCUS_TARGET_EVENTS
        elseif unit == "target" then
            return ALPHA_RANGE_TARGET_EVENTS
        elseif unit == "focus" then
            return ALPHA_RANGE_FOCUS_EVENTS
        elseif unit == "boss1" or unit == "boss2" or unit == "boss3" or unit == "boss4" or unit == "boss5" then
            return ALPHA_RANGE_BOSS_EVENTS
        end
        return ALPHA_RANGE_GLOBAL_EVENTS
    end
    return EMPTY_EVENTS
end

function Alpha.Apply(frame, spec)
    TrackAlphaFrame(frame, spec and spec.alpha)
    if spec and spec.alpha and spec.alpha.rangeEnabled == true and not GetRangeCheckLib() then
        EnsureRangeSpells()
    end
    ApplyCompiledAlpha(frame, spec and spec.alpha, "MSUF_APPLY")
end

function Alpha.Update(frame, event, unit, ...)
    if event == "SPELLS_CHANGED"
        or event == "PLAYER_ENTERING_WORLD"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "CHARACTER_POINTS_CHANGED"
    then
        if GetRangeCheckLib() then
            targetRangeSpellsBuilt = false
        else
            UpdateActiveRangeSpells()
        end
    end
    ApplyCompiledAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, event, unit, ...)
end

function Alpha.Disable(frame)
    if not frame then
        return
    end
    UntrackAlphaFrame(frame)
    frame._msufAlphaRuntimeCfg = nil
    frame._msufAlphaRuntime = nil
    ClearAlphaField(frame, "_msufLastAlpha")
    SetFrameAlpha(frame, 1)
    ResetLegacyLayerAlphas(frame)
end

do
    local pending
    local pendingCombatOnly

    local function FlushAlphaRefresh()
        local combatOnly = pendingCombatOnly
        pending = nil
        pendingCombatOnly = nil
        if combatOnly == true and _G.MSUF_RefreshCombatUnitAlphas then
            return _G.MSUF_RefreshCombatUnitAlphas()
        elseif _G.MSUF_RefreshAllUnitAlphas then
            return _G.MSUF_RefreshAllUnitAlphas()
        end
    end

    function Alpha.RequestRefresh(combatOnly)
        if pending then
            if combatOnly ~= true then
                pendingCombatOnly = nil
            end
            return true
        end
        pending = true
        pendingCombatOnly = combatOnly == true
        if _G.MSUF_ScheduleOnce then
            _G.MSUF_ScheduleOnce("UF_ALPHA_FLUSH", FlushAlphaRefresh)
        elseif _G.C_Timer and _G.C_Timer.After then
            _G.C_Timer.After(0, FlushAlphaRefresh)
        else
            FlushAlphaRefresh()
        end
        return true
    end
end

_G.MSUF_RequestAlphaRefresh = function(combatOnly)
    return Alpha.RequestRefresh(combatOnly)
end

_G.MSUF_GetDesiredUnitAlpha = function(key)
    local unit = key == "boss" and "boss1" or key
    if unit == "tot" or unit == "targetoftarget" then
        unit = "targettarget"
    end
    local spec = unit and UF.Config and UF.Config.GetSpec and UF.Config.GetSpec(unit)
    local cfg = spec and spec.alpha
    if not cfg then
        return 1
    end
    return CurrentAlpha(cfg, cfg.layered == true and cfg.layerMode or "foreground", "MSUF_ALPHA")
end

local function ResolveFrameSpec(frame, key)
    local unit = frame and frame.unit or key
    if key and key ~= "boss" and UF.IsManagedUnit and UF.IsManagedUnit(key) then
        unit = key
    end
    if unit and UF.Config and UF.Config.RefreshUnit then
        return UF.Config.RefreshUnit(unit)
    elseif unit and UF.Config and UF.Config.GetSpec then
        return UF.Config.GetSpec(unit)
    end
    return frame and frame.MSUFSpec
end

_G.MSUF_ApplyUnitAlpha = function(frame, key)
    if not frame then
        return false
    end
    local spec = ResolveFrameSpec(frame, key)
    frame.MSUFSpec = spec or frame.MSUFSpec
    frame.cachedConfig = frame.MSUFSpec
    TrackAlphaFrame(frame, frame.MSUFSpec and frame.MSUFSpec.alpha)
    ApplyCompiledAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, "MSUF_ALPHA")
    return true
end

_G.MSUF_ApplyRangeFadeAlphaFast = function(frame, key, mul)
    if not frame then
        return false
    end
    local spec = ResolveFrameSpec(frame, key)
    frame.MSUFSpec = spec or frame.MSUFSpec
    frame.cachedConfig = frame.MSUFSpec
    local cfg = frame.MSUFSpec and frame.MSUFSpec.alpha
    TrackAlphaFrame(frame, cfg)
    if not (cfg and cfg.rangeEnabled == true) then
        return false
    end
    mul = Clamp01(mul, 1)
    frame._msufManualRangeMul = mul < 1 and mul or nil
    ApplyCompiledAlpha(frame, cfg, "MSUF_RANGE")
    return true
end

if CreateFrame and not Alpha.stateDriver then
    local driver = CreateFrame("Frame")
    driver:RegisterEvent("PLAYER_REGEN_DISABLED")
    driver:RegisterEvent("PLAYER_REGEN_ENABLED")
    driver:RegisterEvent("PLAYER_ENTERING_WORLD")
    driver:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" then
            _G.MSUF_InCombat = true
            Alpha.RequestRefresh(true)
        elseif event == "PLAYER_REGEN_ENABLED" then
            _G.MSUF_InCombat = false
            Alpha.RequestRefresh(true)
        else
            _G.MSUF_InCombat = InCombatLockdown and InCombatLockdown() and true or false
            Alpha.RequestRefresh(false)
        end
    end)
    Alpha.stateDriver = driver
end

local function UnitDispelRuntimeEnabled(spec)
    local a3 = MSUF and (MSUF.MSUF_Auras3 or _G.MSUF_Auras3)
    if not (a3 and type(a3.BackendEnabled) == "function" and a3.BackendEnabled() == true) then
        return false
    end
    if not spec or spec.scope == "group" then return false end
    local border = spec.border
    local overlay = spec.dispelOverlay
    return (border and border.dispel == true) or (overlay and overlay.enabled == true)
end

local function DispelTriggerNeedsCapability(trigger)
    trigger = DispelState.NormalizeOverlayTrigger and DispelState.NormalizeOverlayTrigger(trigger) or trigger
    return trigger == "BY_ME" or trigger == "BORDER"
end

local function UnitDispelNeedsCapability(spec)
    local border = spec and spec.border
    local overlay = spec and spec.dispelOverlay
    if border and border.dispel == true and DispelTriggerNeedsCapability(border.dispelTrigger or "BY_ME") then
        return true
    end
    if overlay and overlay.enabled == true then
        local trigger = overlay.trigger or "BORDER"
        if trigger == "BORDER" then
            if not border or border.dispel ~= true then return true end
            return DispelTriggerNeedsCapability(border.dispelTrigger or "BY_ME")
        end
        return DispelTriggerNeedsCapability(trigger)
    end
    return false
end

local function DispelTriggerNeeds(trigger, needs)
    trigger = DispelState.NormalizeOverlayTrigger and DispelState.NormalizeOverlayTrigger(trigger) or trigger
    if trigger == "ANY_DEBUFF" then
        needs.needAnyDebuff = true
    elseif trigger == "DISPEL_TYPE" then
        needs.needAnyDispelType = true
    elseif trigger == "PLAYER_CAST" then
        needs.needPlayerCast = true
    else
        needs.needDispellable = true
    end
end

local function ResetUnitDispelState(frame, borderEnabled)
    frame._msufUFBorderAuraStateKnown = true
    frame._msufUFBorderAuraEnabled = borderEnabled == true
    frame._msufUFBorderAuraState = nil
    frame._msufUFBorderAuraColorR = nil
    frame._msufUFBorderAuraColorG = nil
    frame._msufUFBorderAuraColorB = nil
    frame._msufUFBorderAuraColorA = nil
    frame._msufUFDispelOverlayActive = false
    frame._msufUFDispelOverlayR = nil
    frame._msufUFDispelOverlayG = nil
    frame._msufUFDispelOverlayB = nil
    frame._msufUFDispelOverlayA = nil
end

local function UpdateUnitDispelState(frame, spec)
    local border = spec and spec.border
    local overlay = spec and spec.dispelOverlay
    local borderEnabled = border and border.dispel == true
    ResetUnitDispelState(frame, borderEnabled)
    if not (DispelState and DispelState.Update and UnitDispelRuntimeEnabled(spec)) then
        return nil
    end

    local needs = frame._msufUFDispelNeeds
    if not needs then
        needs = {}
        frame._msufUFDispelNeeds = needs
    end
    needs.needAnyDebuff = false
    needs.needAnyDispelType = false
    needs.needDispellable = false
    needs.needPlayerCast = false

    if borderEnabled then
        DispelTriggerNeeds(border.dispelTrigger or "BY_ME", needs)
    end
    if overlay and overlay.enabled == true then
        local trigger = overlay.trigger or "BORDER"
        if trigger == "BORDER" and borderEnabled then
            DispelTriggerNeeds(border.dispelTrigger or "BY_ME", needs)
        else
            DispelTriggerNeeds(trigger, needs)
        end
    end

    local snapshot = DispelState.Update(frame, needs)
    if not snapshot then return nil end

    if borderEnabled then
        local trigger = border.dispelTrigger or "BY_ME"
        local active = DispelState.ActiveForTrigger(snapshot, trigger, false) == true
        frame._msufUFBorderAuraState = active and "dispel" or nil
        if active then
            frame._msufUFBorderAuraColorR, frame._msufUFBorderAuraColorG, frame._msufUFBorderAuraColorB, frame._msufUFBorderAuraColorA =
                DispelState.ColorForTrigger(snapshot, trigger, spec and spec.dispel, 1)
        end
    end

    if overlay and overlay.enabled == true then
        local trigger = overlay.trigger or "BORDER"
        local borderActive = frame._msufUFBorderAuraState == "dispel"
        local activeTrigger = trigger == "BORDER" and not borderEnabled and "BY_ME" or trigger
        local active = DispelState.ActiveForTrigger(snapshot, activeTrigger, borderActive) == true
        frame._msufUFDispelOverlayActive = active
        if active then
            local colorTrigger = trigger == "BORDER" and borderEnabled and (border and border.dispelTrigger or "BY_ME") or activeTrigger
            frame._msufUFDispelOverlayR, frame._msufUFDispelOverlayG, frame._msufUFDispelOverlayB, frame._msufUFDispelOverlayA =
                DispelState.ColorForTrigger(snapshot, colorTrigger, spec and spec.dispel, overlay.alpha or 0.35)
        end
    end

    return snapshot
end

local function HideDispelOverlays(frame, except)
    local tex = frame and frame.MSUFDispelOverlay
    if tex and tex ~= except then SetShown(tex, false) end
    tex = frame and frame.MSUFDispelOverlayFrame
    if tex and tex ~= except then SetShown(tex, false) end
    tex = frame and frame.MSUFDispelOverlayHealth
    if tex and tex ~= except then SetShown(tex, false) end
end

local function EnsureDispelOverlayLayer(frame)
    local layer = frame.MSUFDispelOverlayLayer
    if not layer then
        layer = CreateFrame("Frame", nil, frame)
        layer:SetAllPoints(frame)
        layer:EnableMouse(false)
        frame.MSUFDispelOverlayLayer = layer
    end
    if layer.SetFrameLevel and frame.GetFrameLevel then
        local level = (frame:GetFrameLevel() or 1) + 35
        if layer._msufDispelOverlayLevel ~= level then
            layer:SetFrameLevel(level)
            layer._msufDispelOverlayLevel = level
        end
    end
    return layer
end

local function DispelOverlayParent(frame, cfg)
    if cfg and cfg.onHealth ~= false and frame.hpBar and frame.hpBar.CreateTexture then
        return frame.hpBar, "MSUFDispelOverlayHealth"
    end
    return EnsureDispelOverlayLayer(frame), "MSUFDispelOverlayFrame"
end

local function EnsureDispelOverlay(frame, cfg)
    local parent, key = DispelOverlayParent(frame, cfg)
    local tex = frame[key]
    if not tex then
        tex = parent:CreateTexture(nil, "OVERLAY")
        if tex.SetDrawLayer then
            tex:SetDrawLayer("OVERLAY", 7)
        end
        tex:SetColorTexture(0.25, 0.75, 1, 0.35)
        tex:SetBlendMode("BLEND")
        tex:Hide()
        frame[key] = tex
    end
    frame.MSUFDispelOverlay = tex
    HideDispelOverlays(frame, tex)
    return tex
end

local function DispelOverlayTarget(frame, cfg)
    if cfg and cfg.onHealth ~= false and frame.hpBar then
        return frame.hpBar
    end
    return frame
end

local function LayoutDispelOverlay(tex, frame, cfg)
    local target = DispelOverlayTarget(frame, cfg)
    local style = cfg and cfg.style or "FULL"
    local h = frame.GetHeight and frame:GetHeight() or 16
    local thickness = max(2, floor((tonumber(h) or 16) * 0.18 + 0.5))
    tex:ClearAllPoints()
    if style == "TOP" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetHeight(thickness)
    elseif style == "BOTTOM" then
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        tex:SetHeight(thickness)
    elseif style == "LEFT" then
        tex:SetPoint("TOPLEFT", target, "TOPLEFT", 0, 0)
        tex:SetPoint("BOTTOMLEFT", target, "BOTTOMLEFT", 0, 0)
        tex:SetWidth(thickness)
    elseif style == "RIGHT" then
        tex:SetPoint("TOPRIGHT", target, "TOPRIGHT", 0, 0)
        tex:SetPoint("BOTTOMRIGHT", target, "BOTTOMRIGHT", 0, 0)
        tex:SetWidth(thickness)
    else
        tex:SetAllPoints(target)
    end
end

local function DispelOverlayAlpha(alpha, cfg, spec)
    alpha = tonumber(alpha) or tonumber(cfg and cfg.alpha) or 0.35
    if cfg and cfg.onHealth ~= false
        and (cfg.style or "FULL") == "FULL"
        and spec and spec.health and spec.health.mode == "dark"
        and alpha > 0.18 then
        return 0.18
    end
    return alpha
end

local function PaintDispelOverlay(tex, style, r, g, b, a)
    local texture = DISPEL_OVERLAY_TEXTURES[style or "FULL"]
    if texture then
        tex:SetTexture(texture)
        tex:SetVertexColor(r, g, b, a)
    else
        tex:SetColorTexture(r, g, b, a)
    end
end

local function UpdateDispelOverlayTexture(frame, spec)
    local cfg = spec and spec.dispelOverlay
    local tex = frame.MSUFDispelOverlay
    if not (cfg and cfg.enabled == true and frame._msufUFDispelOverlayActive == true) then
        HideDispelOverlays(frame)
        return
    end
    tex = EnsureDispelOverlay(frame, cfg)
    LayoutDispelOverlay(tex, frame, cfg)
    PaintDispelOverlay(tex, cfg.style,
        frame._msufUFDispelOverlayR or 0.25,
        frame._msufUFDispelOverlayG or 0.75,
        frame._msufUFDispelOverlayB or 1,
        DispelOverlayAlpha(frame._msufUFDispelOverlayA, cfg, spec))
    SetShown(tex, true)
end

local DispelOverlay = {}

function DispelOverlay.IsEnabled(frame, spec)
    return UnitDispelRuntimeEnabled(spec)
end

function DispelOverlay.GetEvents()
    return BORDER_AURA_EVENTS
end

function DispelOverlay.GetUnitlessEvents(frame, spec)
    return UnitDispelNeedsCapability(spec) and DISPEL_CAPABILITY_EVENTS or nil
end

function DispelOverlay.Apply(frame, spec)
    UpdateUnitDispelState(frame, spec)
    UpdateDispelOverlayTexture(frame, spec)
end

function DispelOverlay.Disable(frame)
    ResetUnitDispelState(frame, false)
    HideDispelOverlays(frame)
end

function DispelOverlay.Update(frame, event)
    local spec = frame and frame.MSUFSpec
    UpdateUnitDispelState(frame, spec)
    UpdateDispelOverlayTexture(frame, spec)
    local active = frame and frame._msufActiveElements
    local borders = active and active.Borders == true and UF.elements and UF.elements.Borders
    if borders and borders.Update then
        borders.Update(frame, IsDispelCapabilityEvent(event) and "MSUF_DISPEL_CAPABILITY" or "MSUF_DISPEL_STATE", frame.unit)
    end
end

UF.RegisterElement("DispelOverlay", DispelOverlay)

local Borders = {}
local IsAggroBorderUnit

function Borders.GetEvents(frame, spec)
    local cfg = spec and spec.border
    if not cfg then
        return EMPTY_EVENTS
    end
    if cfg.aggro == true and IsAggroBorderUnit(frame) then
        return BORDER_THREAT_EVENTS
    end
    return EMPTY_EVENTS
end

function Borders.GetUnitlessEvents(frame, spec)
    return EMPTY_EVENTS
end

local EDGE_KEYS = { "top", "bottom", "left", "right" }
local DISPEL_GLOW_KEY = "msufDispel"
local dispelGlowColor = { 0, 0, 0, 1 }
local dispelProcGlowOptions = { color = dispelGlowColor, key = DISPEL_GLOW_KEY }

local function GlowLib()
    if LCG then
        return LCG
    end
    if LibStub then
        LCG = LibStub("LibCustomGlow-1.0", true)
    end
    return LCG
end

local function StopDispelGlowOn(anchor)
    local lib = GlowLib()
    if not (lib and anchor) then return end
    if lib.PixelGlow_Stop then lib.PixelGlow_Stop(anchor, DISPEL_GLOW_KEY) end
    if lib.AutoCastGlow_Stop then lib.AutoCastGlow_Stop(anchor, DISPEL_GLOW_KEY) end
    if lib.ProcGlow_Stop then lib.ProcGlow_Stop(anchor, DISPEL_GLOW_KEY) end
end

local function StopDispelGlow(frame)
    if not frame then return end
    if not frame._msufDispelGlowActive
        and not frame._msufDispelGlowAnchor
        and not frame._msufDispelGlowStyle
    then
        return
    end
    frame._msufDispelGlowActive = nil
    local anchor = frame._msufDispelGlowAnchor
    frame._msufDispelGlowAnchor = nil
    frame._msufDispelGlowStyle = nil
    frame._msufDispelGlowR = nil
    frame._msufDispelGlowG = nil
    frame._msufDispelGlowB = nil
    frame._msufDispelGlowLines = nil
    frame._msufDispelGlowFreq = nil
    frame._msufDispelGlowThick = nil
    StopDispelGlowOn(anchor)
    if frame.MSUFBorderOverlay and frame.MSUFBorderOverlay ~= anchor then
        StopDispelGlowOn(frame.MSUFBorderOverlay)
    end
    if frame._msufRoundedHighlightGlowAnchor and frame._msufRoundedHighlightGlowAnchor ~= anchor then
        StopDispelGlowOn(frame._msufRoundedHighlightGlowAnchor)
    end
    if frame._msufRGF_GlowAnchor and frame._msufRGF_GlowAnchor ~= anchor then
        StopDispelGlowOn(frame._msufRGF_GlowAnchor)
    end
    if frame ~= anchor then
        StopDispelGlowOn(frame)
    end
end

local function StartDispelGlow(frame, r, g, b, spec)
    local dispel = spec and spec.dispel
    if not (dispel and dispel.glowEnabled == true) then
        StopDispelGlow(frame)
        return
    end
    local lib = GlowLib()
    if not lib then
        StopDispelGlow(frame)
        return
    end
    local anchor = frame._msufRoundedHighlightGlowAnchor
        or frame._msufRGF_GlowAnchor
        or frame.MSUFBorderOverlay
        or frame
    local style = dispel.glowStyle or "PIXEL"
    local lines = tonumber(dispel.glowLines) or 8
    local freq = tonumber(dispel.glowFrequency) or 0.25
    local thick = tonumber(dispel.glowThickness) or 2
    local secretColor = issecretvalue and (issecretvalue(r) or issecretvalue(g) or issecretvalue(b))
    if secretColor then
        r, g, b = dispel.r or 0.25, dispel.g or 0.75, dispel.b or 1
    end
    if frame._msufDispelGlowActive == true
        and frame._msufDispelGlowAnchor == anchor
        and frame._msufDispelGlowStyle == style
        and frame._msufDispelGlowR == r
        and frame._msufDispelGlowG == g
        and frame._msufDispelGlowB == b
        and frame._msufDispelGlowLines == lines
        and frame._msufDispelGlowFreq == freq
        and frame._msufDispelGlowThick == thick
    then
        return
    end
    local oldAnchor = frame._msufDispelGlowAnchor
    if oldAnchor and (oldAnchor ~= anchor or frame._msufDispelGlowStyle ~= style) then
        StopDispelGlowOn(oldAnchor)
    end
    if anchor ~= frame then
        StopDispelGlowOn(frame)
    end
    dispelGlowColor[1], dispelGlowColor[2], dispelGlowColor[3] = r, g, b
    if style == "AUTOCAST" and lib.AutoCastGlow_Start then
        lib.AutoCastGlow_Start(anchor, dispelGlowColor, lines, freq, nil, nil, nil, DISPEL_GLOW_KEY)
    elseif style == "PROC" and lib.ProcGlow_Start then
        dispelProcGlowOptions.color = dispelGlowColor
        dispelProcGlowOptions.key = DISPEL_GLOW_KEY
        lib.ProcGlow_Start(anchor, dispelProcGlowOptions)
    elseif lib.PixelGlow_Start then
        lib.PixelGlow_Start(anchor, dispelGlowColor, lines, freq, nil, thick, nil, nil, nil, DISPEL_GLOW_KEY)
    end
    frame._msufDispelGlowActive = true
    frame._msufDispelGlowAnchor = anchor
    frame._msufDispelGlowStyle = style
    frame._msufDispelGlowR = r
    frame._msufDispelGlowG = g
    frame._msufDispelGlowB = b
    frame._msufDispelGlowLines = lines
    frame._msufDispelGlowFreq = freq
    frame._msufDispelGlowThick = thick
end

local function EnsureBorderOverlay(parent)
    local overlay = parent.MSUFBorderOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, parent)
        overlay:SetAllPoints(parent)
        overlay:EnableMouse(false)
        parent.MSUFBorderOverlay = overlay
    end
    if parent.GetFrameLevel and overlay.SetFrameLevel then
        local level = (parent:GetFrameLevel() or 1) + 40
        if overlay._msufBorderLevel ~= level then
            overlay:SetFrameLevel(level)
            overlay._msufBorderLevel = level
        end
    end
    return overlay
end

local function EnsureEdge(parent, key)
    parent.MSUFBorderEdges = parent.MSUFBorderEdges or {}
    local overlay = EnsureBorderOverlay(parent)
    local edge = parent.MSUFBorderEdges[key]
    if edge and edge.GetParent and edge:GetParent() ~= overlay then
        edge:Hide()
        edge = nil
        parent.MSUFBorderEdges[key] = nil
    end
    if edge then
        return edge
    end
    edge = overlay:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(0, 0, 0, 1)
    parent.MSUFBorderEdges[key] = edge
    return edge
end

local function LayoutBorder(frame, thickness)
    EnsureBorderOverlay(frame)
    thickness = tonumber(thickness) or 1
    if thickness < 1 then
        thickness = 1
    end
    local top = EnsureEdge(frame, "top")
    local bottom = EnsureEdge(frame, "bottom")
    local left = EnsureEdge(frame, "left")
    local right = EnsureEdge(frame, "right")
    if frame._msufBorderThickness == thickness and frame._msufBorderLayoutReady == true then
        return
    end
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    left:ClearAllPoints()
    right:ClearAllPoints()
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", thickness, thickness)
    top:SetHeight(thickness)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -thickness, -thickness)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
    bottom:SetHeight(thickness)
    left:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
    left:SetPoint("BOTTOMLEFT", bottom, "TOPLEFT", 0, 0)
    left:SetWidth(thickness)
    right:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, 0)
    right:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    right:SetWidth(thickness)
    frame._msufBorderThickness = thickness
    frame._msufBorderLayoutReady = true
end

local function BorderNormalEnabled(cfg)
    return cfg and cfg.enabled == true and (tonumber(cfg.thickness) or 0) > 0
end

local function IsBossUnit(unit)
    if type(unit) ~= "string" or unit:sub(1, 4) ~= "boss" then return false end
    local index = tonumber(unit:sub(5))
    return index ~= nil and index >= 1 and index <= 5
end

function IsAggroBorderUnit(frame)
    local unit = frame and frame.unit
    if unit == "player" or unit == "target" or unit == "focus" then return true end
    return IsBossUnit(unit) or (frame and frame.MSUFSpec and frame.MSUFSpec.scope == "group")
end

local function IsPurgeBorderUnit(frame)
    local unit = frame and frame.unit
    return unit == "target" or unit == "focus" or unit == "targettarget"
end

local function TestScopeApplies(frame, scope)
    if not frame then return false end
    scope = scope or "shared"
    if scope == "shared" then return true end
    local spec = frame.MSUFSpec
    local groupKind = frame._msufGFKind or spec and spec.groupKind
    if scope == "party" or scope == "gf_party" then
        return groupKind == "party"
    elseif scope == "raid" or scope == "gf_raid" then
        return groupKind == "raid" or groupKind == "mythicraid"
    elseif scope == "mythicraid" or scope == "gf_mythicraid" then
        return groupKind == "mythicraid"
    elseif groupKind then
        return false
    elseif scope == "boss" then
        return IsBossUnit(frame.unit)
    end
    return frame.unit == scope or frame.configKey == scope or frame.unitKey == scope
end

local function RefreshBorderTestFrames()
    if UF and UF.RefreshBorders then
        UF.RefreshBorders()
    end
    local gf = MSUF and MSUF.GF
    if gf then
        if gf.RefreshVisuals then
            gf.RefreshVisuals()
        elseif gf.MarkAllDirty then
            gf.MarkAllDirty((gf.DIRTY_VISUAL or 2) + (gf.DIRTY_LAYOUT or 32))
        end
    end
end

local function RefreshBorderTestModesActive()
    _G.MSUF_BorderTestModesActive = _G.MSUF_AggroBorderTestMode == true
        or _G.MSUF_DispelBorderTestMode == true
        or _G.MSUF_PurgeBorderTestMode == true
        or _G.MSUF_BossTargetBorderTestMode == true
end

local function SetBorderTestMode(flag, scopeFlag, active, scope)
    _G[flag] = active == true
    if scopeFlag then _G[scopeFlag] = scope or "shared" end
    RefreshBorderTestModesActive()
    RefreshBorderTestFrames()
    return true
end

_G.MSUF_SetAggroBorderTestMode = _G.MSUF_SetAggroBorderTestMode or function(active, scope)
    return SetBorderTestMode("MSUF_AggroBorderTestMode", "MSUF_AggroBorderTestScope", active, scope)
end

_G.MSUF_SetDispelBorderTestMode = _G.MSUF_SetDispelBorderTestMode or function(active, scope)
    return SetBorderTestMode("MSUF_DispelBorderTestMode", "MSUF_DispelBorderTestScope", active, scope)
end

_G.MSUF_SetPurgeBorderTestMode = _G.MSUF_SetPurgeBorderTestMode or function(active, scope)
    return SetBorderTestMode("MSUF_PurgeBorderTestMode", "MSUF_PurgeBorderTestScope", active, scope)
end

_G.MSUF_SetBossTargetBorderTestMode = _G.MSUF_SetBossTargetBorderTestMode or function(active)
    return SetBorderTestMode("MSUF_BossTargetBorderTestMode", nil, active, "boss")
end

local function AggroTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_AggroBorderTestMode == true
        and IsAggroBorderUnit(frame)
        and TestScopeApplies(frame, _G.MSUF_AggroBorderTestScope)
end

local function DispelTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_DispelBorderTestMode == true
        and TestScopeApplies(frame, _G.MSUF_DispelBorderTestScope)
end

local function PurgeTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_PurgeBorderTestMode == true
        and IsPurgeBorderUnit(frame)
        and TestScopeApplies(frame, _G.MSUF_PurgeBorderTestScope)
end

local function BossTargetTestApplies(frame)
    return _G.MSUF_BorderTestModesActive == true
        and _G.MSUF_BossTargetBorderTestMode == true
        and IsBossUnit(frame and frame.unit)
end

local function BorderHighlightEnabled(frame, cfg)
    if cfg and (cfg.dispel == true or cfg.aggro == true or cfg.purge == true) then
        return true
    end
    if _G.MSUF_BorderTestModesActive ~= true then
        return false
    end
    return AggroTestApplies(frame)
        or DispelTestApplies(frame)
        or PurgeTestApplies(frame)
        or BossTargetTestApplies(frame)
end

local function BorderNormalThickness(cfg)
    local thickness = cfg and tonumber(cfg.thickness) or nil
    if not thickness or thickness < 1 then
        return 1
    end
    return thickness
end

local function BorderHighlightThickness(cfg)
    local thickness = cfg and tonumber(cfg.highlightThickness) or nil
    if not thickness or thickness < 1 then
        thickness = cfg and tonumber(cfg.thickness) or nil
    end
    if not thickness or thickness < 1 then
        return 1
    end
    return thickness
end

local function SetBorder(frame, show, r, g, b, a)
    if not frame.MSUFBorderEdges then
        return
    end
    r, g, b, a = r or 0, g or 0, b or 0, a or 1
    if frame._msufBorderShown == show
        and frame._msufBorderR == r
        and frame._msufBorderG == g
        and frame._msufBorderB == b
        and frame._msufBorderA == a then
        return
    end
    frame._msufBorderShown = show
    frame._msufBorderR, frame._msufBorderG, frame._msufBorderB, frame._msufBorderA = r, g, b, a
    for i = 1, #EDGE_KEYS do
        local edge = frame.MSUFBorderEdges[EDGE_KEYS[i]]
        if edge then
            edge:SetVertexColor(r, g, b, a)
            SetShown(edge, show)
        end
    end
end

local function AuraBorderState(frame)
    local auras = frame.Auras
    local debuffs = auras and auras.Debuffs
    local cfg = frame.MSUFSpec and frame.MSUFSpec.border
    local wantsDispel = cfg and cfg.dispel == true
    if frame._msufUFBorderAuraStateKnown == true and frame._msufUFBorderAuraEnabled == (wantsDispel and true or false) then
        return frame._msufUFBorderAuraState,
            frame._msufUFBorderAuraColorR,
            frame._msufUFBorderAuraColorG,
            frame._msufUFBorderAuraColorB,
            frame._msufUFBorderAuraColorA
    end
    if debuffs and debuffs._msufBorderAuraStateKnown == true and debuffs._msufBorderAuraEnabled == (wantsDispel and true or false) then
        return debuffs._msufBorderAuraState,
            debuffs._msufBorderAuraColorR,
            debuffs._msufBorderAuraColorG,
            debuffs._msufBorderAuraColorB,
            debuffs._msufBorderAuraColorA
    end
    if frame._msufGFBorderAuraStateKnown == true and frame._msufGFBorderAuraEnabled == (wantsDispel and true or false) then
        return frame._msufGFBorderAuraState,
            frame._msufGFBorderAuraColorR,
            frame._msufGFBorderAuraColorG,
            frame._msufGFBorderAuraColorB,
            frame._msufGFBorderAuraColorA
    end
    return nil
end

local function ThreatState(frame)
    if not (UnitThreatSituation and frame and frame.unit) then
        return false
    end
    local unit = frame.unit
    local spec = frame.MSUFSpec
    if spec and spec.scope == "group" then
        local exists = UnitExists and UnitExists(unit)
        if exists ~= nil and NotSecretValue(exists) and exists == false then
            return false
        end
        local cfg = spec.border
        local mode = cfg and cfg.aggroMode
        if mode == "TANK" or mode == "HEALER" then
            local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(unit) or nil
            if role == nil or not NotSecretValue(role) or role ~= mode then
                return false
            end
        end
        local status = UnitThreatSituation(unit)
        if status == nil or not NotSecretValue(status) then
            return false
        end
        status = tonumber(status)
        return status ~= nil and status >= 1
    end

    local status
    if unit == "player" then
        status = UnitThreatSituation("player", "target")
        if status == nil then
            status = UnitThreatSituation("player")
        end
    else
        status = UnitThreatSituation("player", unit)
    end
    if status == nil or not NotSecretValue(status) then
        return false
    end
    status = tonumber(status)
    return status ~= nil and status >= 2
end

local function GeneralDB()
    local db = _G.MSUF_DB
    return db and db.general or nil
end

local function DispelTestColor(frame)
    local dispel = frame and frame.MSUFSpec and frame.MSUFSpec.dispel
    if dispel and dispel.colorMode == "TYPE" then
        local dispelType = tostring(_G.MSUF_DispelBorderTestType or "Magic")
        local prefix = "type" .. dispelType
        return dispel[prefix .. "R"] or dispel.r or 0.25,
            dispel[prefix .. "G"] or dispel.g or 0.75,
            dispel[prefix .. "B"] or dispel.b or 1,
            1
    end
    return dispel and dispel.r or 0.25, dispel and dispel.g or 0.75, dispel and dispel.b or 1, 1
end

local function AggroColor(cfg)
    return cfg and cfg.aggroR or 1.00,
        cfg and cfg.aggroG or 0.55,
        cfg and cfg.aggroB or 0.00,
        1
end

local function PurgeColor(cfg)
    local general = GeneralDB()
    return cfg and cfg.purgeR or tonumber(general and (general.hlPurgeColorR or general.purgeBorderColorR)) or 1.00,
        cfg and cfg.purgeG or tonumber(general and (general.hlPurgeColorG or general.purgeBorderColorG)) or 0.85,
        cfg and cfg.purgeB or tonumber(general and (general.hlPurgeColorB or general.purgeBorderColorB)) or 0.00,
        1
end

local function BossTargetColor(cfg)
    if cfg and cfg.bossTargetR then
        return cfg.bossTargetR or 1, cfg.bossTargetG or 0.82, cfg.bossTargetB or 0, 1
    end
    local general = GeneralDB()
    local color = general and general.bossTargetHighlightColor
    if type(color) == "table" then
        return tonumber(color[1]) or 1, tonumber(color[2]) or 0.82, tonumber(color[3]) or 0, tonumber(color[4]) or 1
    end
    return 1, 0.82, 0, 1
end

function Borders.Create(frame)
    LayoutBorder(frame, 1)
end

function Borders.Apply(frame, spec)
    local cfg = spec and spec.border
    if not cfg or not (BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg)) then
        LayoutBorder(frame, 1)
        StopDispelGlow(frame)
        SetBorder(frame, false)
    elseif cfg.dispel == true or cfg.aggro == true or cfg.purge == true then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        Borders.Update(frame, "MSUF_BORDER_APPLY", frame.unit)
    else
        LayoutBorder(frame, BorderNormalThickness(cfg))
        StopDispelGlow(frame)
        SetBorder(frame, true, cfg.r or 0, cfg.g or 0, cfg.b or 0, cfg.a or 1)
    end
end

function Borders.IsEnabled(frame, spec)
    local cfg = spec and spec.border
    return BorderNormalEnabled(cfg) or BorderHighlightEnabled(frame, cfg) or false
end

function Borders.Disable(frame)
    StopDispelGlow(frame)
    SetBorder(frame, false)
end

function Borders.Update(frame)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.border
    local normalEnabled = BorderNormalEnabled(cfg)
    if not cfg or not (normalEnabled or BorderHighlightEnabled(frame, cfg)) then
        StopDispelGlow(frame)
        SetBorder(frame, false)
        return
    end
    local testActive = _G.MSUF_BorderTestModesActive == true
    local auraState, auraR, auraG, auraB, auraA = AuraBorderState(frame)
    if testActive and DispelTestApplies(frame) then
        local r, g, b, a = DispelTestColor(frame)
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, r, g, b, a)
        StartDispelGlow(frame, r, g, b, frame.MSUFSpec)
        return
    end
    if cfg.dispel and auraState == "dispel" then
        local r, g, b, a = auraR or 0.25, auraG or 0.75, auraB or 1, auraA or 1
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, r, g, b, a)
        StartDispelGlow(frame, r, g, b, frame.MSUFSpec)
        return
    end
    StopDispelGlow(frame)
    if (testActive and AggroTestApplies(frame)) or (cfg.aggro and IsAggroBorderUnit(frame) and ThreatState(frame)) then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, AggroColor(cfg))
        return
    end
    if testActive and PurgeTestApplies(frame) then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, PurgeColor(cfg))
        return
    end
    if testActive and BossTargetTestApplies(frame) then
        LayoutBorder(frame, BorderHighlightThickness(cfg))
        SetBorder(frame, true, BossTargetColor(cfg))
        return
    end
    if not normalEnabled then
        SetBorder(frame, false)
        return
    end
    LayoutBorder(frame, BorderNormalThickness(cfg))
    SetBorder(frame, true, cfg.r or 0, cfg.g or 0, cfg.b or 0, cfg.a or 1)
end

local Auras = {
    events = { "UNIT_AURA" },
}

local function GetAuraCore()
    return MSUF.AuraCore or _G.MSUF_AuraCore
end

function Auras.IsEnabled(frame, spec)
    local A3 = MSUF.MSUF_Auras3 or _G.MSUF_Auras3
    if not (A3 and type(A3.BackendEnabled) == "function" and A3.BackendEnabled() == true) then
        return false
    end
    if not (frame and spec and spec.auras and spec.auras.enabled == true) then
        return false
    end
    local cfg = A3 and A3.ResolveUnitFrameConfig and A3.ResolveUnitFrameConfig(frame.unit, frame)
    if not cfg then
        return true
    end
    return cfg.enabled == true and (
        (cfg.showBuffs and (cfg.maxBuffs or 0) > 0)
        or (cfg.showDebuffs and (cfg.maxDebuffs or 0) > 0)
        or (cfg.showExternals and (cfg.maxExternals or 0) > 0)
    )
end

function Auras.Enable(frame)
    local core = GetAuraCore()
    if core and core.Enable then
        return core.Enable(frame, "unit")
    end
    local A3 = MSUF.MSUF_Auras3 or _G.MSUF_Auras3
    if A3 and A3.SetUnitFrameOwner then
        frame._msufA3UnitAuraOwner = true
        A3.SetUnitFrameOwner(frame.unit, frame, true)
    end
    if A3 and A3.EnableFrame then
        A3.EnableFrame(frame)
    end
end

function Auras.Disable(frame)
    local core = GetAuraCore()
    if core and core.Disable then
        return core.Disable(frame, "unit")
    end
    local A3 = MSUF.MSUF_Auras3 or _G.MSUF_Auras3
    frame._msufA3UnitAuraOwner = nil
    if A3 and A3.SetUnitFrameOwner then
        A3.SetUnitFrameOwner(frame.unit, frame, false)
    end
    if A3 and A3.DisableFrame then
        A3.DisableFrame(frame)
    end
end

function Auras.Update(frame, event, unit, updateInfo)
    local core = GetAuraCore()
    if core and core.Update then
        return core.Update(frame, event, unit or frame.unit, updateInfo, "unit")
    end
    local A3 = MSUF.MSUF_Auras3 or _G.MSUF_Auras3
    if A3 and A3.HandleUnitAura then
        A3.HandleUnitAura(unit or frame.unit, updateInfo, frame)
    elseif A3 and A3.RenderFrame then
        A3.RenderFrame(frame, updateInfo)
    end
end

UF.RegisterElement("Portrait", Portrait)
UF.RegisterElement("Alpha", Alpha)
UF.RegisterElement("Auras", Auras)
UF.RegisterElement("Borders", Borders)

local function RefreshUnitDispelFrame(frame)
    if not frame then return end
    local active = frame._msufActiveElements
    if active and active.DispelOverlay == true then
        DispelOverlay.Update(frame, "MSUF_DISPEL_REFRESH", frame.unit)
    end
    if active and active.Borders == true and Borders.Update then
        Borders.Update(frame, "MSUF_DISPEL_REFRESH", frame.unit)
    end
end

_G.MSUF_RefreshUnitDispelOverlays = function()
    if UF.ForEachFrame then
        UF.ForEachFrame(RefreshUnitDispelFrame)
        return true
    end
    return false
end

_G.MSUF_RefreshDispelOutlineStates = _G.MSUF_RefreshUnitDispelOverlays
_G.MSUF_DispelOutline_ApplyEventRegistration = _G.MSUF_RefreshUnitDispelOverlays

_G.MSUF_RefreshCombatUnitAlphas = function()
    local combatFrames = Alpha.combatFrames
    local rangeFrames = Alpha.rangeFrames
    if type(combatFrames) ~= "table" and type(rangeFrames) ~= "table" then
        return false
    end
    Alpha.refreshToken = (Alpha.refreshToken or 0) + 1
    local token = Alpha.refreshToken
    local refreshed = false
    local function refresh(frame, owner)
        local active = frame and frame._msufActiveElements
        local cfg = frame and frame.MSUFSpec and frame.MSUFSpec.alpha
        if frame and frame._msufAlphaRefreshToken == token then
            return
        end
        if frame and active and active.Alpha == true and cfg and (cfg.combatEvents == true or cfg.rangeEnabled == true) then
            frame._msufAlphaRefreshToken = token
            ApplyCompiledAlpha(frame, frame.MSUFSpec.alpha, "MSUF_ALPHA_COMBAT")
            refreshed = true
        else
            owner[frame] = nil
        end
    end
    if type(combatFrames) == "table" then
        for frame in pairs(combatFrames) do
            refresh(frame, combatFrames)
        end
    end
    if type(rangeFrames) == "table" then
        for frame in pairs(rangeFrames) do
            refresh(frame, rangeFrames)
        end
    end
    return refreshed
end

_G.MSUF_Alpha_UpdatePreserveMissingHP = function(frame)
    if frame then
        ApplyCompiledAlpha(frame, frame.MSUFSpec and frame.MSUFSpec.alpha, "MSUF_ALPHA")
    end
end
