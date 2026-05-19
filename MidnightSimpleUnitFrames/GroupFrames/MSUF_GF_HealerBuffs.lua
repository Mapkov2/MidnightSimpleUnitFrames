-- MSUF_GF_HealerBuffs.lua — Group Frames Phase 5a: Healer Buff Placement Runtime
-- Per-spec spell families, compilation, aura matching, icon/bar indicators.
-- Midnight 12.0 secret-safe, zero combat overhead.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end

local issecretvalue = _G.issecretvalue
local C_UnitAuras = _G.C_UnitAuras
local CUA_GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local CUA_GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local CreateFrame = _G.CreateFrame
local UnitExists = _G.UnitExists
local UnitClass = _G.UnitClass
local GetSpecialization = _G.GetSpecialization
local GetSpecializationInfo = _G.GetSpecializationInfo
local IsPlayerSpell = _G.IsPlayerSpell
local C_Spell = _G.C_Spell
local select = select
local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local tostring = tostring
local math_floor = math.floor
local AuraFilter = GF.AuraFilter or _G.MSUF_GF_AuraFilter
local MSUF_ResolveIconTexturePath = _G.MSUF_ResolveIconTexturePath
local MSUF_SetIconTexture = _G.MSUF_SetIconTexture

local HB = {}
GF.HealerBuffs = HB

------------------------------------------------------------------------
-- Spell Family Data (EQoL parity: healer specs + augmentation)
------------------------------------------------------------------------
local FAMILY_DATA = {
    -- Preservation Evoker
    { id = "evoker_pres_reversion",      classToken = "EVOKER",  specId = 1468, spellIds = {366155},  name = "Reversion" },
    { id = "evoker_pres_echo",           classToken = "EVOKER",  specId = 1468, spellIds = {364343},  name = "Echo" },
    { id = "evoker_pres_dream_breath",   classToken = "EVOKER",  specId = 1468, spellIds = {355941},  name = "Dream Breath" },
    { id = "evoker_pres_lifebind",       classToken = "EVOKER",  specId = 1468, spellIds = {373267},  name = "Lifebind" },
    -- Augmentation Evoker
    { id = "evoker_aug_ebon_might",      classToken = "EVOKER",  specId = 1473, spellIds = {395152},  name = "Ebon Might" },
    { id = "evoker_aug_prescience",      classToken = "EVOKER",  specId = 1473, spellIds = {410089},  name = "Prescience" },
    { id = "evoker_aug_shifting_sands",  classToken = "EVOKER",  specId = 1473, spellIds = {413984},  name = "Shifting Sands" },
    { id = "evoker_aug_blistering_scales", classToken = "EVOKER", specId = 1473, spellIds = {360827}, name = "Blistering Scales" },
    -- Restoration Druid
    { id = "druid_rejuvenation",         classToken = "DRUID",   specId = 105,  spellIds = {774},     name = "Rejuvenation" },
    { id = "druid_regrowth",             classToken = "DRUID",   specId = 105,  spellIds = {8936},    name = "Regrowth" },
    { id = "druid_lifebloom",            classToken = "DRUID",   specId = 105,  spellIds = {33763},   name = "Lifebloom" },
    { id = "druid_wild_growth",          classToken = "DRUID",   specId = 105,  spellIds = {48438},   name = "Wild Growth" },
    { id = "druid_germination",          classToken = "DRUID",   specId = 105,  spellIds = {155777},  name = "Germination" },
    -- Discipline Priest
    { id = "priest_atonement",           classToken = "PRIEST",  specId = 256,  spellIds = {194384},  name = "Atonement" },
    { id = "priest_pw_shield",           classToken = "PRIEST",  specId = 256,  spellIds = {17},      name = "Power Word: Shield" },
    -- Holy Priest
    { id = "priest_renew",              classToken = "PRIEST",  specId = 257,  spellIds = {139},     name = "Renew" },
    { id = "priest_prayer_of_mending",  classToken = "PRIEST",  specId = 257,  spellIds = {41635},   name = "Prayer of Mending" },
    { id = "priest_echo_of_light",      classToken = "PRIEST",  specId = 257,  spellIds = {77489},   name = "Echo of Light" },
    -- Mistweaver Monk
    { id = "monk_renewing_mist",         classToken = "MONK",    specId = 270,  spellIds = {119611},  name = "Renewing Mist" },
    { id = "monk_enveloping_mist",       classToken = "MONK",    specId = 270,  spellIds = {124682},  name = "Enveloping Mist" },
    { id = "monk_soothing_mist",         classToken = "MONK",    specId = 270,  spellIds = {115175},  name = "Soothing Mist" },
    -- Restoration Shaman
    { id = "shaman_riptide",             classToken = "SHAMAN",  specId = 264,  spellIds = {61295},   name = "Riptide" },
    { id = "shaman_earth_shield",        classToken = "SHAMAN",  specId = 264,  spellIds = {974,383648}, name = "Earth Shield" },
    { id = "shaman_earthliving_weapon",  classToken = "SHAMAN",  specId = 264,  spellIds = {382024},  name = "Earthliving Weapon" },
    -- Holy Paladin
    { id = "paladin_beacon_of_light",    classToken = "PALADIN", specId = 65,   spellIds = {53563},   name = "Beacon of Light" },
    { id = "paladin_beacon_of_faith",    classToken = "PALADIN", specId = 65,   spellIds = {156910},  name = "Beacon of Faith" },
    { id = "paladin_eternal_flame",      classToken = "PALADIN", specId = 65,   spellIds = {156322},  name = "Eternal Flame" },
}

-- Build lookup tables
local FAMILY_BY_ID = {}
local SPELL_TO_FAMILY = {}
for _, fam in ipairs(FAMILY_DATA) do
    FAMILY_BY_ID[fam.id] = fam
    for _, sid in ipairs(fam.spellIds) do
        SPELL_TO_FAMILY[sid] = fam.id
    end
end
HB.FAMILY_BY_ID = FAMILY_BY_ID
HB.FAMILY_DATA = FAMILY_DATA
HB.SPELL_TO_FAMILY = SPELL_TO_FAMILY

------------------------------------------------------------------------
-- Per-spec default presets (which indicators to show for each healer spec)
------------------------------------------------------------------------
local SPEC_PRESETS = {
    [105]  = { "druid_rejuvenation", "druid_lifebloom", "druid_wild_growth", "druid_germination", "druid_regrowth" }, -- Resto Druid
    [256]  = { "priest_atonement", "priest_pw_shield" },                                                              -- Disc Priest
    [257]  = { "priest_renew", "priest_prayer_of_mending", "priest_echo_of_light" },                                  -- Holy Priest
    [264]  = { "shaman_riptide", "shaman_earth_shield", "shaman_earthliving_weapon" },                                -- Resto Shaman
    [270]  = { "monk_renewing_mist", "monk_enveloping_mist", "monk_soothing_mist" },                                  -- MW Monk
    [65]   = { "paladin_beacon_of_light", "paladin_beacon_of_faith", "paladin_eternal_flame" },                       -- Holy Pala
    [1468] = { "evoker_pres_reversion", "evoker_pres_echo", "evoker_pres_dream_breath", "evoker_pres_lifebind" },     -- Pres Evoker
    [1473] = { "evoker_aug_ebon_might", "evoker_aug_prescience", "evoker_aug_shifting_sands" },                       -- Aug Evoker
}
HB.SPEC_PRESETS = SPEC_PRESETS

------------------------------------------------------------------------
-- Get current player spec
------------------------------------------------------------------------
local _playerClass = select(2, UnitClass("player"))
local _cachedSpecId

local function GetPlayerSpecId()
    if GetSpecializationInfo and GetSpecialization then
        local specIndex = GetSpecialization()
        if specIndex then
            local specId = GetSpecializationInfo(specIndex)
            _cachedSpecId = specId
            return specId
        end
    end
    return _cachedSpecId
end

------------------------------------------------------------------------
-- Get spell texture (cached)
------------------------------------------------------------------------
local _spellTexCache = {}
local function GetSpellTexture(spellId)
    local cached = _spellTexCache[spellId]
    if cached then return cached end
    if C_Spell and C_Spell.GetSpellTexture then
        local tex = C_Spell.GetSpellTexture(spellId)
        if tex then
            tex = (type(MSUF_ResolveIconTexturePath) == "function" and MSUF_ResolveIconTexturePath(tex)) or tex
            _spellTexCache[spellId] = tex
            return tex
        end
    end
    -- Fallback
    local _, _, icon = GetSpellInfo(spellId)
    if icon then
        icon = (type(MSUF_ResolveIconTexturePath) == "function" and MSUF_ResolveIconTexturePath(icon)) or icon
        _spellTexCache[spellId] = icon
    end
    return icon
end

------------------------------------------------------------------------
-- DB: Healer buff placement config
------------------------------------------------------------------------
-- Stored in MSUF_DB.gf_party.healerBuffs / gf_raid.healerBuffs
-- Structure:
--   enabled = true/false
--   slots = { [1] = { familyId="druid_rejuvenation", anchor="CENTER", x=0, y=0, size=20, desaturateMissing=true, showCooldown=true }, ... }
--   useSpecPreset = true (auto-populate from current spec)

local DEFAULT_HB_CONF = {
    enabled          = false,
    useSpecPreset    = true,
    iconSize         = 20,
    spacing          = 1,
    anchor           = "CENTER",
    growthX          = "RIGHT",
    growthY          = "DOWN",
    maxSlots         = 5,
    desaturateMissing = true,
    showCooldown     = true,
    slots            = {},  -- populated from spec preset
}

function HB.EnsureConf(kind)
    local db = _G.MSUF_DB
    if not db then return DEFAULT_HB_CONF end
    local key = GF.GetConfigDBKey and GF.GetConfigDBKey(kind) or ((kind == "raid") and "gf_raid" or "gf_party")
    local gfConf = db[key]
    if not gfConf then return DEFAULT_HB_CONF end
    if type(gfConf.healerBuffs) ~= "table" then
        gfConf.healerBuffs = {}
        for k, v in pairs(DEFAULT_HB_CONF) do
            if gfConf.healerBuffs[k] == nil then gfConf.healerBuffs[k] = v end
        end
    end
    local hb = gfConf.healerBuffs
    for k, v in pairs(DEFAULT_HB_CONF) do
        if hb[k] == nil then hb[k] = v end
    end
    if type(hb.slots) ~= "table" then hb.slots = {} end
    return hb
end

------------------------------------------------------------------------
-- Compile active slots (from spec preset or manual config)
------------------------------------------------------------------------
local _compiledSlots = {} -- [kind] = { familyId, spellIds, texture, ... }
local _compiledGen = { party = 0, raid = 0 }

local function CompileSlots(kind)
    local hbConf = HB.EnsureConf(kind)
    if not hbConf.enabled then return {} end

    local slots = {}

    if hbConf.useSpecPreset then
        local specId = GetPlayerSpecId()
        local preset = specId and SPEC_PRESETS[specId]
        if preset then
            for i, famId in ipairs(preset) do
                local fam = FAMILY_BY_ID[famId]
                if fam then
                    local tex = fam.spellIds[1] and GetSpellTexture(fam.spellIds[1])
                    slots[#slots + 1] = {
                        familyId = famId,
                        spellIds = fam.spellIds,
                        texture  = tex,
                        name     = fam.name,
                    }
                end
            end
        end
    else
        -- Manual slots from DB
        for i, slotCfg in ipairs(hbConf.slots) do
            if slotCfg.familyId then
                local fam = FAMILY_BY_ID[slotCfg.familyId]
                if fam then
                    local tex = fam.spellIds[1] and GetSpellTexture(fam.spellIds[1])
                    slots[#slots + 1] = {
                        familyId = slotCfg.familyId,
                        spellIds = fam.spellIds,
                        texture  = tex,
                        name     = fam.name,
                        -- Per-slot overrides
                        size     = slotCfg.size,
                        anchor   = slotCfg.anchor,
                        x        = slotCfg.x,
                        y        = slotCfg.y,
                    }
                end
            end
        end
    end

    local maxSlots = hbConf.maxSlots or 5
    if #slots > maxSlots then
        for i = maxSlots + 1, #slots do slots[i] = nil end
    end

    return slots
end

function HB.GetCompiledSlots(kind)
    return CompileSlots(kind)
end

------------------------------------------------------------------------
-- Icon pool for healer buff indicators
------------------------------------------------------------------------
local function CreateHBIcon(parent, size)
    local icon = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    icon:SetSize(size, size)
    icon:EnableMouse(false)

    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(icon)
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon.texture = tex

    local cd = CreateFrame("Cooldown", nil, icon, "CooldownFrameTemplate")
    cd:SetAllPoints(icon)
    cd:SetDrawEdge(true)
    cd:SetDrawSwipe(true)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(false)
    icon.cooldown = cd

    local count = icon:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 2, -2)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 1, 1, 1)
    count:SetText("")
    count:Hide()
    icon.count = count

    icon:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets   = { left = 0, right = 0, top = 0, bottom = 0 },
    })
    icon:SetBackdropColor(0, 0, 0, 0.6)
    icon:SetBackdropBorderColor(0, 0, 0, 1)
    icon:Hide()
    return icon
end

local function EnsureHBIconPool(f, count, size, parent)
    f._msufGFHBIcons = f._msufGFHBIcons or {}
    local pool = f._msufGFHBIcons
    for i = 1, count do
        if not pool[i] then
            pool[i] = CreateHBIcon(parent, size)
        end
        local ic = pool[i]
        ic:SetSize(size, size)
        if ic.GetParent and ic:GetParent() ~= parent then ic:SetParent(parent) end
        if ic.SetFrameLevel and parent and parent.GetFrameLevel then
            ic:SetFrameLevel(parent:GetFrameLevel() + 4)
        end
    end
    return pool
end

------------------------------------------------------------------------
-- Aura scan: check which families are active on a unit
------------------------------------------------------------------------
local _slotBuf2 = {}
local _slotCount2 = 0

local function CaptureSlots2(...)
    local count = select("#", ...)
    for i = 1, count do _slotBuf2[i] = select(i, ...) end
    for i = count + 1, _slotCount2 do _slotBuf2[i] = nil end
    _slotCount2 = count
    return _slotBuf2, count
end

local function QueryAuraSlots(unit, filter, maxCount)
    if GF and GF.QueryAuraSlots then
        return GF.QueryAuraSlots(unit, filter, maxCount)
    end
    if not CUA_GetAuraSlots and C_UnitAuras then CUA_GetAuraSlots = C_UnitAuras.GetAuraSlots end
    if not CUA_GetAuraSlots then return _slotBuf2, 0 end
    if maxCount then
        return CaptureSlots2(CUA_GetAuraSlots(unit, filter, maxCount))
    end
    return CaptureSlots2(CUA_GetAuraSlots(unit, filter))
end

local function QueryAuraData(unit, slot)
    if GF and GF.GetAuraDataBySlot then
        return GF.GetAuraDataBySlot(unit, slot)
    end
    if not CUA_GetAuraDataBySlot and C_UnitAuras then CUA_GetAuraDataBySlot = C_UnitAuras.GetAuraDataBySlot end
    return CUA_GetAuraDataBySlot and CUA_GetAuraDataBySlot(unit, slot)
end

-- Returns: activeFamilies[familyId] = auraData
local _wantedPlayerSpells = {}
local _activeFamilies = {}

local function ScanFamiliesForUnit(unit, compiledSlots, kind)
    AuraFilter = AuraFilter or GF.AuraFilter or _G.MSUF_GF_AuraFilter
    local result = _activeFamilies
    for k in pairs(result) do result[k] = nil end

    if not (unit and UnitExists(unit)) then return result end
    if (not CUA_GetAuraSlots or not CUA_GetAuraDataBySlot) and C_UnitAuras then
        CUA_GetAuraSlots = CUA_GetAuraSlots or C_UnitAuras.GetAuraSlots
        CUA_GetAuraDataBySlot = CUA_GetAuraDataBySlot or C_UnitAuras.GetAuraDataBySlot
    end
    if not ((GF and GF.QueryAuraSlots and GF.GetAuraDataBySlot) or (CUA_GetAuraSlots and CUA_GetAuraDataBySlot)) then return result end

    for k in pairs(_wantedPlayerSpells) do _wantedPlayerSpells[k] = nil end

    for i = 1, #compiledSlots do
        local slot = compiledSlots[i]
        local spellIds = slot.spellIds
        for j = 1, #spellIds do
            local sid = spellIds[j]
            _wantedPlayerSpells[sid] = slot.familyId
        end
    end

    local slots, slotCount = QueryAuraSlots(unit, "HELPFUL|PLAYER")
    for i = 2, slotCount do
        local aura = QueryAuraData(unit, slots[i])
        if aura then
            local sid = aura.spellId
            if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
                sid = tonumber(sid)
                local famId = sid and _wantedPlayerSpells[sid]
                if famId and not result[famId] then
                    result[famId] = aura
                end
            end
        end
    end

    return result
end

------------------------------------------------------------------------
-- Apply cooldown (secret-safe)
------------------------------------------------------------------------
local _getDuration
local function ApplyHBCooldown(icon, unit, auraInstanceID)
    local cd = icon.cooldown
    if not cd then return end
    if not _getDuration then
        _getDuration = C_UnitAuras and C_UnitAuras.GetAuraDuration
    end
    if not _getDuration or not auraInstanceID then cd:Clear(); return end
    local obj = _getDuration(unit, auraInstanceID)
    if obj ~= nil and type(obj) ~= "number" then
        local setFn = cd._msufHBCdSetFn
        if setFn == nil then
            setFn = type(cd.SetCooldownFromDurationObject) == "function" and cd.SetCooldownFromDurationObject or false
            cd._msufHBCdSetFn = setFn
        end
        if setFn then setFn(cd, obj) end
    else
        cd:Clear()
    end
end

------------------------------------------------------------------------
-- Apply stack count (secret-safe)
------------------------------------------------------------------------
local _getStackCount
local function ApplyHBStackCount(icon, unit, auraInstanceID)
    local fs = icon.count
    if not fs then return end
    if not _getStackCount then
        _getStackCount = C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount
    end
    if _getStackCount and auraInstanceID then
        local stacks = _getStackCount(unit, auraInstanceID, 2, 99)
        if stacks ~= nil then
            if issecretvalue and issecretvalue(stacks) then
                fs:SetText("2+"); fs:Show(); return
            end
            local n = tonumber(stacks)
            if n and n >= 2 then fs:SetText(n); fs:Show(); return end
        end
    end
    fs:SetText(""); fs:Hide()
end

local _visibleCompiledSlots = {}

local function RebuildVisibleCompiledSlots(kind, compiledSlots)
    AuraFilter = AuraFilter or GF.AuraFilter or _G.MSUF_GF_AuraFilter
    for i = 1, #_visibleCompiledSlots do _visibleCompiledSlots[i] = nil end
    local shown = 0
    if AuraFilter and AuraFilter.ShouldSuppressFamily then
        for i = 1, #compiledSlots do
            local slot = compiledSlots[i]
            if not AuraFilter.ShouldSuppressFamily(kind, slot.spellIds, "buff") then
                shown = shown + 1
                _visibleCompiledSlots[shown] = slot
            end
        end
    else
        for i = 1, #compiledSlots do
            shown = shown + 1
            _visibleCompiledSlots[shown] = compiledSlots[i]
        end
    end
    return _visibleCompiledSlots, shown
end

------------------------------------------------------------------------
-- Render healer buff indicators for one frame
------------------------------------------------------------------------
function HB.UpdateFrame(f, unit)
    if not f or not unit then return end
    local kind = f._msufGFKind or "party"

    -- SpellIndicators supersedes HealerBuffs — hide HB icons and bail
    local conf = GF.GetConf(kind)
    local si = conf and conf.spellIndicators
    if si and si.enabled then
        if f._msufGFHBIcons then
            for i = 1, #f._msufGFHBIcons do f._msufGFHBIcons[i]:Hide() end
        end
        return
    end

    local hbConf = HB.EnsureConf(kind)

    if not hbConf.enabled then
        -- Hide all HB icons
        if f._msufGFHBIcons then
            for i = 1, #f._msufGFHBIcons do f._msufGFHBIcons[i]:Hide() end
        end
        return
    end

    if not UnitExists(unit) then
        if f._msufGFHBIcons then
            for i = 1, #f._msufGFHBIcons do f._msufGFHBIcons[i]:Hide() end
        end
        return
    end

    local compiledSlots = CompileSlots(kind)
    if #compiledSlots == 0 then
        if f._msufGFHBIcons then
            for i = 1, #f._msufGFHBIcons do f._msufGFHBIcons[i]:Hide() end
        end
        return
    end

    local visibleSlots, visibleCount = RebuildVisibleCompiledSlots(kind, compiledSlots)
    if visibleCount == 0 then
        if f._msufGFHBIcons then
            for i = 1, #f._msufGFHBIcons do f._msufGFHBIcons[i]:Hide() end
        end
        return
    end

    local iconSize = hbConf.iconSize or 20
    local spacing  = hbConf.spacing or 1
    local anchor   = hbConf.anchor or "CENTER"
    local growthX  = hbConf.growthX or "RIGHT"
    local growthY  = hbConf.growthY or "DOWN"
    local desat    = hbConf.desaturateMissing ~= false
    local showCD   = hbConf.showCooldown ~= false
    local parent   = f.statusIconLayer or f.barGroup or f

    local pool = EnsureHBIconPool(f, #compiledSlots, iconSize, parent)

    -- Scan which families are active
    local active = ScanFamiliesForUnit(unit, visibleSlots, kind)

    for i = 1, visibleCount do
        local slot = visibleSlots[i]
        local ic = pool[i]
        if ic then
            -- Set texture (spell icon)
            if slot.texture then
                if type(MSUF_SetIconTexture) == "function" then
                    MSUF_SetIconTexture(ic.texture, slot.texture, "")
                else
                    ic.texture:SetTexture(slot.texture)
                end
            end

            local famActive = active[slot.familyId]
            if famActive then
                -- Active: full color, cooldown, stacks
                ic.texture:SetDesaturated(false)
                ic.texture:SetAlpha(1)
                ic:SetBackdropBorderColor(0, 0.8, 0, 1) -- green border = active
                if showCD then
                    ApplyHBCooldown(ic, unit, famActive.auraInstanceID)
                else
                    ic.cooldown:Clear()
                end
                ApplyHBStackCount(ic, unit, famActive.auraInstanceID)
            else
                -- Missing: desaturated, no cooldown
                ic.texture:SetDesaturated(desat)
                ic.texture:SetAlpha(desat and 0.4 or 1)
                ic:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
                ic.cooldown:Clear()
                if ic.count then ic.count:SetText(""); ic.count:Hide() end
            end

            -- Position
            ic:ClearAllPoints()
            local col = (i - 1) % (visibleCount)
            local xMul = (growthX == "LEFT") and -1 or 1
            local yMul = (growthY == "UP") and 1 or -1
            local ox = col * (iconSize + spacing) * xMul
            local oy = 0 -- single row for now
            ic:SetPoint(anchor, parent, anchor, ox, oy)
            ic:Show()
        end
    end

    -- Hide excess
    for i = visibleCount + 1, #pool do
        pool[i]:Hide()
    end
end

function HB.HideFrame(f)
    local pool = f and f._msufGFHBIcons
    if not pool then return end
    for i = 1, #pool do
        local icon = pool[i]
        if icon and icon:IsShown() then icon:Hide() end
    end
end

local function FrameWantsHealerBuffs(f, kind, conf)
    if not f or f._msufGFPreviewActive then return false end
    local c = f._c
    if c and c.healerBuffsEn ~= nil then
        return c.healerBuffsEn == true
    end
    conf = conf or (GF.GetConf and GF.GetConf(kind or f._msufGFKind or "party"))
    if not (conf and conf.healerBuffs and conf.healerBuffs.enabled == true) then return false end
    local si = conf.spellIndicators
    return not (si and si.enabled)
end

local function AnyHealerBuffsEnabled()
    if type(GF.GetConf) ~= "function" then return true end
    local party = GF.GetConf("party")
    local raid = GF.GetConf("raid")
    if not party or not raid then return true end
    return (party.healerBuffs and party.healerBuffs.enabled == true)
        or (raid.healerBuffs and raid.healerBuffs.enabled == true)
end

local _installRuntimeHooks = AnyHealerBuffsEnabled()

------------------------------------------------------------------------
-- Hook into UNIT_AURA coalescing (from Effects.lua)
------------------------------------------------------------------------
if _installRuntimeHooks then
    local origUpdateDispel = GF._UpdateDispel
    if type(origUpdateDispel) == "function" then
        GF._UpdateDispel = function(f, unit)
            origUpdateDispel(f, unit)
            if f._msufIsGroupFrame and unit and UnitExists(unit) and not f._msufGFPreviewActive then
                local kind = f._msufGFKind or "party"
                if FrameWantsHealerBuffs(f, kind) then
                    HB.UpdateFrame(f, unit)
                else
                    HB.HideFrame(f)
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Hook into full refresh
------------------------------------------------------------------------
if _installRuntimeHooks then
    local origUpdateButton = GF.UpdateButton
    if type(origUpdateButton) == "function" then
        GF.UpdateButton = function(f, unit)
            if GF.IsFrameRuntimeEnabled and not GF.IsFrameRuntimeEnabled(f, f and f._msufGFKind) then
                if f then HB.HideFrame(f) end
                return
            end
            origUpdateButton(f, unit)
            if f._msufIsGroupFrame and unit and UnitExists(unit) and not f._msufGFPreviewActive then
                local kind = f._msufGFKind or "party"
                if FrameWantsHealerBuffs(f, kind) then
                    HB.UpdateFrame(f, unit)
                else
                    HB.HideFrame(f)
                end
            end
        end
        _G.MSUF_GF_UpdateButton = GF.UpdateButton
    end
end

------------------------------------------------------------------------
-- Spec change listener (re-compile on spec swap)
------------------------------------------------------------------------
if _installRuntimeHooks then
    local ef = CreateFrame("Frame")
    ef:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    ef:RegisterEvent("PLAYER_TALENT_UPDATE")
    ef:SetScript("OnEvent", function()
        if GF.UpdateAnyEnabledFlag then GF.UpdateAnyEnabledFlag() end
        if GF._anyEnabled == false then return end
        _cachedSpecId = nil
        GF.ForEachFrame(function(f, kind)
            if f.unit and UnitExists(f.unit) then
                local conf = GF.GetConf(kind)
                if FrameWantsHealerBuffs(f, kind, conf) then
                    HB.UpdateFrame(f, f.unit)
                else
                    HB.HideFrame(f)
                end
            end
        end)
    end)
end

------------------------------------------------------------------------
-- DB defaults patch
------------------------------------------------------------------------
do
    local function addDefaults(defaults)
        if defaults.healerBuffs == nil then
            defaults.healerBuffs = {
                enabled = false,
                useSpecPreset = true,
                iconSize = 20,
                spacing = 1,
                anchor = "CENTER",
                growthX = "RIGHT",
                growthY = "DOWN",
                maxSlots = 5,
                desaturateMissing = true,
                showCooldown = true,
                slots = {},
            }
        end
    end
    if GF.PARTY_DEFAULTS then addDefaults(GF.PARTY_DEFAULTS) end
    if GF.RAID_DEFAULTS then addDefaults(GF.RAID_DEFAULTS) end
end

------------------------------------------------------------------------
-- Global exports
------------------------------------------------------------------------
_G.MSUF_GF_HB_UpdateFrame = HB.UpdateFrame
_G.MSUF_GF_HB_HideFrame   = HB.HideFrame
_G.MSUF_GF_HB_EnsureConf  = HB.EnsureConf
_G.MSUF_GF_HB_GetSlots    = HB.GetCompiledSlots
_G.MSUF_GF_HB_FAMILY_DATA = FAMILY_DATA
_G.MSUF_GF_HB_SPEC_PRESETS = SPEC_PRESETS
