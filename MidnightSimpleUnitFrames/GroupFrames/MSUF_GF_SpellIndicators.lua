-- MSUF_GF_SpellIndicators.lua - Group Frames: Per-Spell Indicator Engine
-- Tracks player-cast healer HoTs on party/raid members.
-- 2-tier: placed indicators (icon/square/bar/number) + frame effects (healthtint/border/glow/pulse/namecolor/framealpha).
-- Uses proven HealerBuffs scan pattern (HELPFUL filter, spellId lookup).
-- Called directly from Effects.lua FlushAuraDirty + UpdateAll (no hook wrapping).
-- Multi-spec tracking, zero combat overhead.
-- Midnight 12.0 secret-safe.
local _, ns = ...
ns = ns or (_G.MSUF_NS) or {}
_G.MSUF_NS = ns

local GF = ns.GF
if not GF then return end
local SI = GF.SpellIndicators
if not SI then return end

local C_UnitAuras   = _G.C_UnitAuras
local CUA_GetAuraSlots = C_UnitAuras and C_UnitAuras.GetAuraSlots
local CUA_GetAuraDataBySlot = C_UnitAuras and C_UnitAuras.GetAuraDataBySlot
local CreateFrame   = _G.CreateFrame
local UnitExists    = _G.UnitExists
local GetTime       = _G.GetTime
local issecretvalue = _G.issecretvalue
local pairs         = pairs
local type          = type
local ipairs        = ipairs
local select        = select
local tonumber      = tonumber
local math_floor    = math.floor
local math_max      = math.max
local table_sort    = table.sort
local table_concat  = table.concat

-- Reusable tables (cleared per call, zero GC allocation)
local _siBestByType = {}

------------------------------------------------------------------------
-- Compiled lookup: spellId → auraName (rebuilt on spec change)
------------------------------------------------------------------------
local _compiledSpec
local _compiledMultiKey
local _reverseLookup
local _nameLookup
local _auraSpecMap = {} -- auraName → specKey (multi-spec config routing)
local _isMultiMode = false

local function CompileLookup(specKey, siCfg)
    if specKey ~= "multi" then
        -- Single-spec mode
        if specKey == _compiledSpec and _reverseLookup and not _isMultiMode then return end
        _compiledSpec     = specKey
        _compiledMultiKey = nil
        _isMultiMode      = false
        _reverseLookup    = SI.BuildReverseLookup(specKey)
        _nameLookup       = SI.BuildNameLookup and SI.BuildNameLookup(specKey) or nil
        for k in pairs(_auraSpecMap) do _auraSpecMap[k] = nil end
        return
    end
    -- Multi-spec mode
    local ms = siCfg and siCfg.multiSpecs
    if not ms then return end
    local parts = {}
    for sk in pairs(ms) do parts[#parts + 1] = sk end
    table_sort(parts)
    local key = table_concat(parts, ",")
    if key == _compiledMultiKey and _reverseLookup and _isMultiMode then return end
    _compiledMultiKey = key
    _compiledSpec     = nil
    _isMultiMode      = true
    _reverseLookup    = {}
    _nameLookup       = nil
    for k in pairs(_auraSpecMap) do _auraSpecMap[k] = nil end
    for _, sk in ipairs(parts) do
        local ids = SI.SpellIDs[sk]
        if ids then
            for auraName, spellId in pairs(ids) do
                if not _reverseLookup[spellId] then
                    _reverseLookup[spellId] = auraName
                    _auraSpecMap[auraName] = _auraSpecMap[auraName] or sk
                end
            end
        end
        local alts = SI.AltSpellIDs[sk]
        if alts then
            for altId, auraName in pairs(alts) do
                if not _reverseLookup[altId] then
                    _reverseLookup[altId] = auraName
                    _auraSpecMap[auraName] = _auraSpecMap[auraName] or sk
                end
            end
        end
        local secrets = SI.SecretSpellIDs[sk]
        if secrets then
            for auraName, spellId in pairs(secrets) do
                if not _reverseLookup[spellId] then
                    _reverseLookup[spellId] = auraName
                    _auraSpecMap[auraName] = _auraSpecMap[auraName] or sk
                end
            end
        end
        local nl = SI.BuildNameLookup and SI.BuildNameLookup(sk)
        if nl then
            if not _nameLookup then _nameLookup = {} end
            for name, auraKey in pairs(nl) do
                if not _nameLookup[name] then
                    _nameLookup[name] = auraKey
                    _auraSpecMap[auraKey] = _auraSpecMap[auraKey] or sk
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Config helpers
------------------------------------------------------------------------
local function GetSIConfig(kind)
    local conf = GF.GetConf(kind)
    return conf and conf.spellIndicators
end

local function ResolveSpec(siCfg)
    if not siCfg then return nil end
    local spec = siCfg.spec or "auto"
    if spec == "multi" then
        local ms = siCfg.multiSpecs
        if ms then
            for _ in pairs(ms) do return "multi" end
        end
        return nil
    end
    if spec == "auto" then return SI.GetPlayerSpec() end
    return spec
end

------------------------------------------------------------------------
-- Auto-populate defaults for a spec (one-time, cold path)
------------------------------------------------------------------------
local function EnsureSpecConfig(siCfg, specKey)
    if not siCfg or not specKey then return nil end
    siCfg.specs = siCfg.specs or {}
    local defaults = SI.SpecDefaults[specKey]

    local function DeepCopy(src)
        if type(src) ~= "table" then return src end
        local dst = {}
        for k, v in pairs(src) do
            dst[k] = DeepCopy(v)
        end
        return dst
    end

    local specCfg = siCfg.specs[specKey]
    if not specCfg then
        specCfg = {}
        siCfg.specs[specKey] = specCfg
    end
    if not defaults then return specCfg end

    for auraName, def in pairs(defaults) do
        local entry = specCfg[auraName]
        if not entry then
            entry = DeepCopy(def)
            if entry.onlyOwn == nil then entry.onlyOwn = true end
            specCfg[auraName] = entry
        else
            if entry.placed == nil and def.placed ~= nil then
                entry.placed = DeepCopy(def.placed)
            end
            if entry.frame == nil and def.frame ~= nil then
                entry.frame = DeepCopy(def.frame)
            end
            if entry.onlyOwn == nil then entry.onlyOwn = (def.onlyOwn ~= false) end
        end
    end

    return specCfg
end

function SI.EnsureSpecConfig(siCfg, specKey)
    return EnsureSpecConfig(siCfg, specKey)
end

------------------------------------------------------------------------
-- Scan: player-cast auras by C-side filter, optional all-caster fallback
------------------------------------------------------------------------
local _slotBuf = {}
local _slotCount = 0
local HELPFUL_ALL = "HELPFUL"
local HELPFUL_PLAYER = "HELPFUL|PLAYER"

local function CaptureSlots(...)
    local count = select("#", ...)
    for i = 1, count do _slotBuf[i] = select(i, ...) end
    for i = count + 1, _slotCount do _slotBuf[i] = nil end
    _slotCount = count
    return _slotBuf, count
end

local function SIQuerySlots(unit, filter, maxCount)
    if GF and GF.QueryAuraSlots then
        return GF.QueryAuraSlots(unit, filter, maxCount)
    end
    if not CUA_GetAuraSlots and C_UnitAuras then CUA_GetAuraSlots = C_UnitAuras.GetAuraSlots end
    if not CUA_GetAuraSlots then return _slotBuf, 0 end
    if maxCount then
        return CaptureSlots(CUA_GetAuraSlots(unit, filter, maxCount))
    end
    return CaptureSlots(CUA_GetAuraSlots(unit, filter))
end

local function SIQueryAuraData(unit, slot)
    if GF and GF.GetAuraDataBySlot then
        return GF.GetAuraDataBySlot(unit, slot)
    end
    if not CUA_GetAuraDataBySlot and C_UnitAuras then CUA_GetAuraDataBySlot = C_UnitAuras.GetAuraDataBySlot end
    return CUA_GetAuraDataBySlot and CUA_GetAuraDataBySlot(unit, slot)
end

local _scanResults = {}
local _scanOnlyOwnByAura = {}

local function MarkScanAuraConfig(auraName, auraCfg)
    if not auraCfg or auraCfg.enabled == false then return false end
    if auraCfg.onlyOwn == false then
        _scanOnlyOwnByAura[auraName] = false
        return true
    end
    if _scanOnlyOwnByAura[auraName] == nil then
        _scanOnlyOwnByAura[auraName] = true
    end
    return false
end

local function BuildScanConfig(siCfg, specKey)
    for k in pairs(_scanOnlyOwnByAura) do _scanOnlyOwnByAura[k] = nil end
    local wantsAllCasters = false

    if specKey == "multi" then
        local ms = siCfg and siCfg.multiSpecs
        if ms then
            for sk in pairs(ms) do
                local specCfg = EnsureSpecConfig(siCfg, sk)
                if specCfg then
                    for auraName, auraCfg in pairs(specCfg) do
                        if MarkScanAuraConfig(auraName, auraCfg) then
                            wantsAllCasters = true
                        end
                    end
                end
            end
        end
    else
        local specCfg = EnsureSpecConfig(siCfg, specKey)
        if specCfg then
            for auraName, auraCfg in pairs(specCfg) do
                if MarkScanAuraConfig(auraName, auraCfg) then
                    wantsAllCasters = true
                end
            end
        end
    end

    return wantsAllCasters
end

local function ScanAuraSlots(unit, filter, fromPlayerFilter)
    local slots, count = SIQuerySlots(unit, filter)
    for i = 2, count do
        local aura = SIQueryAuraData(unit, slots[i])
        if aura then
            local sid = aura.spellId
            local matched
            -- Secret-safety guard + tag-strip: secret-tagged integers need
            -- tonumber() before use as hash key (Midnight 12.0 semantics).
            if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
                sid = tonumber(sid)
                if sid then matched = _reverseLookup[sid] end
            end
            if not matched and _nameLookup then
                local aName = aura.name
                if aName ~= nil and not (issecretvalue and issecretvalue(aName)) then
                    matched = _nameLookup[aName]
                end
            end
            if matched and not _scanResults[matched] then
                local onlyOwn = _scanOnlyOwnByAura[matched]
                if onlyOwn ~= nil and (fromPlayerFilter or onlyOwn == false) then
                    _scanResults[matched] = aura
                end
            end
        end
    end
end

local function ScanUnit(unit, kind, siCfg, specKey)
    for k in pairs(_scanResults) do _scanResults[k] = nil end
    if not _reverseLookup then return end
    if (not CUA_GetAuraSlots or not CUA_GetAuraDataBySlot) and C_UnitAuras then
        CUA_GetAuraSlots = CUA_GetAuraSlots or C_UnitAuras.GetAuraSlots
        CUA_GetAuraDataBySlot = CUA_GetAuraDataBySlot or C_UnitAuras.GetAuraDataBySlot
    end
    if not (CUA_GetAuraSlots and CUA_GetAuraDataBySlot) then return end

    local wantsAllCasters = BuildScanConfig(siCfg, specKey)
    ScanAuraSlots(unit, HELPFUL_PLAYER, true)
    if wantsAllCasters then
        ScanAuraSlots(unit, HELPFUL_ALL, false)
    end
end

function GF.SpellIndicatorsUnitAuraRelevant(f, unit, kind, updateInfo)
    if not updateInfo or updateInfo.isFullUpdate then return true end

    local siCfg = GetSIConfig(kind or (f and f._msufGFKind) or "party")
    if not siCfg or not siCfg.enabled then return false end

    local specKey = ResolveSpec(siCfg)
    if not specKey then return false end
    CompileLookup(specKey, siCfg)

    local added = updateInfo.addedAuras
    if added then
        for i = 1, #added do
            local aura = added[i]
            if aura then
                local sid = aura.spellId
                if sid ~= nil and not (issecretvalue and issecretvalue(sid)) then
                    sid = tonumber(sid)
                    if sid and _reverseLookup and _reverseLookup[sid] then return true end
                end
                if _nameLookup then
                    local auraName = aura.name
                    if auraName ~= nil and not (issecretvalue and issecretvalue(auraName)) and _nameLookup[auraName] then
                        return true
                    end
                end
            end
        end
    end

    local tracked = f and f._msufSIDedupIDs
    if not tracked then return false end

    local updated = updateInfo.updatedAuraInstanceIDs
    if updated then
        for i = 1, #updated do
            if tracked[updated[i]] then return true end
        end
    end

    local removed = updateInfo.removedAuraInstanceIDs
    if removed then
        for i = 1, #removed do
            if tracked[removed[i]] then return true end
        end
    end

    return false
end

local function ResolveCooldownFontString(cd)
    if not cd then return nil end
    local cached = cd._msufCooldownFontString
    if cached and cached ~= false then return cached end

    local retryAt = cd._msufCooldownFontStringRetryAt
    local now = GetTime()
    if type(retryAt) == "number" and now < retryAt then
        return nil
    end

    if cd.EnumerateRegions then
        for region in cd:EnumerateRegions() do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                cd._msufCooldownFontString = region
                cd._msufCooldownFontStringRetryAt = nil
                return region
            end
        end
    end

    cd._msufCooldownFontStringRetryAt = now + 0.50
    cd._msufCooldownFontString = false
    return nil
end

local function ResolveCooldownBaseColor()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    if g and g.useCustomFontColor == true then
        local r = g.fontColorCustomR
        local gg = g.fontColorCustomG
        local b = g.fontColorCustomB
        if type(r) == "number" and type(gg) == "number" and type(b) == "number" then
            return r, gg, b, 1
        end
    end
    return 1, 1, 1, 1
end

local function ApplyPlacedCooldownStyle(cd, ownerFrame, numberOnly)
    if not cd then return end
    local kind = (ownerFrame and ownerFrame._msufGFKind) or "party"
    local conf = GF.GetConf and GF.GetConf(kind)
    local reverse = (not numberOnly) and conf and conf.cooldownSwipeDarkenOnLoss == true or false

    if cd._msufGFSIDrawEdge ~= false then
        cd._msufGFSIDrawEdge = false
        cd:SetDrawEdge(false)
    end
    if cd.SetDrawBling and cd._msufGFSIDrawBling ~= false then
        cd._msufGFSIDrawBling = false
        cd:SetDrawBling(false)
    end
    local wantSwipe = not numberOnly
    if cd._msufGFSIDrawSwipe ~= wantSwipe then
        cd._msufGFSIDrawSwipe = wantSwipe
        cd:SetDrawSwipe(wantSwipe)
    end
    if cd._msufGFSIReverse ~= reverse then
        cd._msufGFSIReverse = reverse
        cd:SetReverse(reverse)
    end
end

local function ClearA2CooldownScope(ind)
    if not ind then return end
    ind._msufA2_cdDurationObj = nil
    ind._msufA2_durationObj = nil
    ind._msufA2_cdMgrRegistered = nil
    ind._msufA2_cdPending = nil
    ind._msufA2_hideCDNumbers = nil
    local cd = ind.cooldown
    if cd then
        cd._msufA2_durationObj = nil
    end
end

local function ApplyPlacedCooldownFont(ind, cfg, fontSizeOverride)
    local cd = ind and ind.cooldown
    if not cd then return nil end

    local fs = ResolveCooldownFontString(cd)
    if not fs then return nil end

    local cdSize = fontSizeOverride or cfg.cooldownSize or 8
    local gfs = _G.MSUF_GetGlobalFontSettings
    local fp, ff
    if type(gfs) == "function" then fp, ff = gfs() end
    if not fp then
        fp = GF and GF.ResolveFontPath and GF.ResolveFontPath() or "Fonts\\FRIZQT__.TTF"
        ff = GF and GF.ResolveFontFlags and GF.ResolveFontFlags() or "OUTLINE"
    end
    local wantFlags = cfg.cooldownOutline or ff or "OUTLINE"
    if cd._msufGFCdTextSize ~= cdSize or cd._msufGFCdFontPath ~= fp then
        fs:SetFont(fp, cdSize, wantFlags)
        cd._msufGFCdTextSize = cdSize
        cd._msufGFCdFontPath = fp
    end
    if cd._msufGFCdAnchor ~= "CENTER" or cd._msufGFCdOX ~= 0 or cd._msufGFCdOY ~= 0 then
        cd._msufGFCdAnchor = "CENTER"
        cd._msufGFCdOX = 0
        cd._msufGFCdOY = 0
        fs:ClearAllPoints()
        fs:SetPoint("CENTER", ind, "CENTER", 0, 0)
    end

    local r, g, b, a = ResolveCooldownBaseColor()
    if cd._msufGFCdColorR ~= r or cd._msufGFCdColorG ~= g
        or cd._msufGFCdColorB ~= b or cd._msufGFCdColorA ~= a
    then
        cd._msufGFCdColorR = r
        cd._msufGFCdColorG = g
        cd._msufGFCdColorB = b
        cd._msufGFCdColorA = a
        if fs.SetTextColor then
            fs:SetTextColor(r, g, b, a)
        elseif fs.SetVertexColor then
            fs:SetVertexColor(r, g, b, a)
        end
    end

    return fs
end

local function ApplyPreviewTextStyle(fs, cfg, fallbackSize, forceFallbackSize)
    if not fs then return end
    local gfs = _G.MSUF_GetGlobalFontSettings
    local fp, ff
    if type(gfs) == "function" then fp, ff = gfs() end
    if not fp then
        fp = GF and GF.ResolveFontPath and GF.ResolveFontPath() or "Fonts\\FRIZQT__.TTF"
        ff = GF and GF.ResolveFontFlags and GF.ResolveFontFlags() or "OUTLINE"
    end
    local fontSize = forceFallbackSize and fallbackSize or (cfg.cooldownSize or fallbackSize or 8)
    fs:SetFont(fp, fontSize or 8, cfg.cooldownOutline or ff or "OUTLINE")
    local r, g, b, a = ResolveCooldownBaseColor()
    fs:SetTextColor(r, g, b, a)
end

local function GetPlacedNumberSize(size)
    local fontSize = tonumber(size) or 12
    local width = math_max(18, math_floor(fontSize * 2.2 + 0.5))
    local height = math_max(10, math_floor(fontSize * 1.4 + 0.5))
    return width, height
end

------------------------------------------------------------------------
-- Placed indicator creation
------------------------------------------------------------------------
local function CreatePlacedIcon(parent, size)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(size, size)
    f:EnableMouse(false)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    f.texture = tex

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(true)
    cd:SetReverse(false)
    cd:SetHideCountdownNumbers(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    f.cooldown = cd

    local overlay = CreateFrame("Frame", nil, f)
    overlay:SetAllPoints()
    overlay:SetFrameLevel(cd:GetFrameLevel() + 5)
    local cnt = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cnt:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT", -1, 1)
    cnt:SetDrawLayer("OVERLAY", 2)
    cnt:SetJustifyH("RIGHT")
    cnt:SetText("")
    cnt:Hide()
    f.count = cnt

    f:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0.8)
    f:Hide()
    return f
end

local function CreatePlacedNumber(parent, size)
    local w, h = GetPlacedNumberSize(size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(w, h)
    f:EnableMouse(false)

    local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetDrawEdge(false)
    cd:SetDrawSwipe(false)
    cd:SetReverse(false)
    cd:SetHideCountdownNumbers(false)
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    f.cooldown = cd

    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    txt:SetPoint("CENTER", f, "CENTER", 0, 0)
    txt:SetText("")
    txt:Hide()
    f.previewText = txt

    f:Hide()
    return f
end

local function CreatePlacedSquare(parent, size)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(size, size)
    f:EnableMouse(false)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 1)
    f.texture = tex
    f:Hide()
    return f
end

local function CreatePlacedBar(parent, w, h)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)
    f:EnableMouse(false)
    f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    f:SetBackdropColor(1, 1, 1, 0.9)
    f:SetBackdropBorderColor(0, 0, 0, 0.7)
    local tex = f:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 1)
    f.texture = tex
    f:Hide()
    return f
end

local function GetOrCreatePlaced(f, auraName, itype, size, parent, barWidth, layer)
    f._msufSIPlaced = f._msufSIPlaced or {}
    local ind = f._msufSIPlaced[auraName]
    if not ind or ind._siType ~= itype then
        if ind then ind:Hide() end
        if itype == "bar" then
            ind = CreatePlacedBar(parent, barWidth or (size * 3), size)
        elseif itype == "number" then
            ind = CreatePlacedNumber(parent, size)
        elseif itype == "square" then
            ind = CreatePlacedSquare(parent, size)
        else
            ind = CreatePlacedIcon(parent, size)
        end
        ind._siType = itype
        f._msufSIPlaced[auraName] = ind
    end
    if itype == "bar" then
        ind:SetSize(barWidth or (size * 3), size)
    elseif itype == "number" then
        local w, h = GetPlacedNumberSize(size)
        ind:SetSize(w, h)
    else
        ind:SetSize(size, size)
    end
    if ind:GetParent() ~= parent then ind:SetParent(parent) end
    if ind.SetFrameLevel then
        if GF.SetFrameLayerLevel then
            GF.SetFrameLayerLevel(ind, f, layer, 9)
        elseif parent.GetFrameLevel then
            ind:SetFrameLevel(parent:GetFrameLevel() + (layer or 9))
        end
    end
    return ind
end

------------------------------------------------------------------------
-- Resolve color for a trackable aura
------------------------------------------------------------------------
local function GetAuraColor(specKey, auraName)
    local track = SI.TrackableAuras[specKey]
    if not track then return nil end
    for _, info in ipairs(track) do
        if info.name == auraName then return info.color end
    end
    return nil
end

-- Multi-spec: resolve color from any matching spec
local function GetAuraColorMulti(auraName)
    local sk = _auraSpecMap[auraName]
    if sk then return GetAuraColor(sk, auraName) end
    return nil
end

------------------------------------------------------------------------
-- Apply one placed indicator
------------------------------------------------------------------------
local function ApplyPlaced(f, unit, auraName, cfg, auraData, parent, specKey, isPreview, scale, layer)
    if not cfg or cfg.type == "none" then
        local old = f and f._msufSIPlaced and f._msufSIPlaced[auraName]
        if old then old:Hide() end
        return
    end
    local itype  = cfg.type or "icon"
    local size   = cfg.size or 18
    if scale and scale ~= 1 then
        size = size * scale
        if size < 6 then size = 6 end
    end
    local anchor = cfg.anchor or "TOPLEFT"
    local barWidth = (itype == "bar") and (cfg.barWidth or (size * 3)) or nil
    if barWidth and scale and scale ~= 1 then
        barWidth = barWidth * scale
        if barWidth < 8 then barWidth = 8 end
    end
    local displaySize = size
    local ind = GetOrCreatePlaced(f, auraName, itype, displaySize, parent, barWidth, layer)

    ind:ClearAllPoints()
    ind:SetPoint(anchor, parent, anchor, cfg.x or 0, cfg.y or 0)

    if auraData then
        if ind.previewText then
            ind.previewText:SetText("")
            ind.previewText:Hide()
        end

        if itype == "icon" or itype == "number" then
            local sk = _isMultiMode and (_auraSpecMap[auraName] or specKey) or specKey
            local isNumber = (itype == "number")

            if ind.texture then
                if isNumber then
                    ind.texture:Hide()
                else
                    ind.texture:SetTexture(SI.GetAuraIcon(sk, auraName))
                    ind.texture:SetDesaturated(false)
                    ind.texture:SetAlpha(1)
                    ind.texture:Show()
                end
            end

            if ind.cooldown then
                local aid = auraData.auraInstanceID
                local showCdText = isNumber or cfg.showCooldown ~= false
                ApplyPlacedCooldownStyle(ind.cooldown, f, isNumber)
                ind.cooldown:SetHideCountdownNumbers(not showCdText)
                if aid and unit and C_UnitAuras and C_UnitAuras.GetAuraDuration then
                    local obj = C_UnitAuras.GetAuraDuration(unit, aid)
                    if obj and ind.cooldown.SetCooldownFromDurationObject then
                        ind.cooldown:SetCooldownFromDurationObject(obj)
                        ClearA2CooldownScope(ind)
                        if showCdText then
                            ApplyPlacedCooldownFont(ind, cfg, isNumber and displaySize or nil)
                        end
                    else
                        ind.cooldown:Clear()
                        ClearA2CooldownScope(ind)
                    end
                else
                    ind.cooldown:Clear()
                    ClearA2CooldownScope(ind)
                end
            end

            if ind.count then
                if isNumber then
                    ind.count:SetText("")
                    ind.count:Hide()
                else
                    local aid = auraData.auraInstanceID
                    if aid and unit and C_UnitAuras and C_UnitAuras.GetAuraApplicationDisplayCount then
                        local display = C_UnitAuras.GetAuraApplicationDisplayCount(unit, aid, 2, 99)
                        if display ~= nil then
                            ind.count:SetText(display)
                            ind.count:Show()
                        else
                            ind.count:SetText("")
                            ind.count:Hide()
                        end
                    else
                        ind.count:SetText("")
                        ind.count:Hide()
                    end
                end
            end
        elseif itype == "square" or itype == "bar" then
            local sk = _isMultiMode and (_auraSpecMap[auraName] or specKey) or specKey
            local c = GetAuraColor(sk, auraName) or {0.5, 0.8, 0.5}
            ind.texture:SetColorTexture(c[1], c[2], c[3], 1)
        end
        ind:Show()
    elseif cfg.missing and isPreview then
        if itype == "icon" then
            local sk = _isMultiMode and (_auraSpecMap[auraName] or specKey) or specKey
            ind.texture:SetTexture(SI.GetAuraIcon(sk, auraName))
            ind.texture:SetDesaturated(true)
            ind.texture:SetAlpha(0.35)
            ind.texture:Show()
            if ind.cooldown then ind.cooldown:Clear() end
            if ind.count then ind.count:SetText(""); ind.count:Hide() end
            if ind.previewText then ind.previewText:SetText(""); ind.previewText:Hide() end
        elseif itype == "number" then
            if ind.cooldown then
                ApplyPlacedCooldownStyle(ind.cooldown, f, true)
                ind.cooldown:Clear()
                ind.cooldown:SetHideCountdownNumbers(false)
            end
            ClearA2CooldownScope(ind)
            if ind.previewText then
                ApplyPreviewTextStyle(ind.previewText, cfg, displaySize, true)
                ind.previewText:SetText("9")
                ind.previewText:Show()
            end
        elseif itype == "square" or itype == "bar" then
            ind.texture:SetColorTexture(0.3, 0.3, 0.3, 0.5)
        end
        ind:Show()
    else
        if ind.cooldown then
            ind.cooldown:Clear()
            ClearA2CooldownScope(ind)
        end
        if ind.count then
            ind.count:SetText("")
            ind.count:Hide()
        end
        if ind.previewText then
            ind.previewText:SetText("")
            ind.previewText:Hide()
        end
        ind:Hide()
    end

    -- Highlight: yellow pulsing border when this SI is selected in the editor
    local GF = ns.GF
    local isHL = GF and GF._highlightedSI == auraName
    if isHL and ind:IsShown() then
        if not ind._msufSIHighlight then
            local hl = CreateFrame("Frame", nil, ind, "BackdropTemplate")
            hl:SetPoint("TOPLEFT", ind, "TOPLEFT", -2, 2)
            hl:SetPoint("BOTTOMRIGHT", ind, "BOTTOMRIGHT", 2, -2)
            hl:SetFrameLevel(ind:GetFrameLevel() + 10)
            hl:EnableMouse(false)
            hl:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
            hl:SetBackdropColor(0, 0, 0, 0)
            hl:SetBackdropBorderColor(1, 0.82, 0, 1)
            local ag = hl:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local anim = ag:CreateAnimation("Alpha")
            anim:SetFromAlpha(1.0)
            anim:SetToAlpha(0.25)
            anim:SetDuration(0.5)
            anim:SetSmoothing("IN_OUT")
            hl._animGroup = ag
            ind._msufSIHighlight = hl
        end
        ind._msufSIHighlight:Show()
        if ind._msufSIHighlight._animGroup then ind._msufSIHighlight._animGroup:Play() end
    elseif ind._msufSIHighlight then
        if ind._msufSIHighlight._animGroup then ind._msufSIHighlight._animGroup:Stop() end
        ind._msufSIHighlight:Hide()
    end
end

------------------------------------------------------------------------
-- Frame-level effects
------------------------------------------------------------------------
local function EnsureHealthTint(f)
    if f._msufSIHealthTint then return f._msufSIHealthTint end
    local bar = f.health
    if not bar then return nil end
    local tex = bar:CreateTexture(nil, "OVERLAY", nil, 1)
    tex:SetAllPoints(bar)
    tex:SetBlendMode("ADD")
    tex:SetColorTexture(1, 1, 1, 0.15)
    tex:Hide()
    f._msufSIHealthTint = tex
    return tex
end

local function EnsureBorderOverlay(f)
    if f._msufSIBorderOverlay then return f._msufSIBorderOverlay end
    local anchor = f.barGroup or f
    local overlay = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    overlay:SetAllPoints(anchor)
    overlay:SetFrameLevel(anchor:GetFrameLevel() + 8)
    overlay:EnableMouse(false)
    overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 2 })
    overlay:SetBackdropColor(0, 0, 0, 0)
    overlay:Hide()
    f._msufSIBorderOverlay = overlay
    return overlay
end

------------------------------------------------------------------------
-- Glow effect: animated pulsing border (C-side AnimationGroup, zero Lua)
------------------------------------------------------------------------
local function EnsureGlowOverlay(f)
    if f._msufSIGlow then return f._msufSIGlow end
    local anchor = f.barGroup or f
    local glow = CreateFrame("Frame", nil, anchor, "BackdropTemplate")
    glow:SetPoint("TOPLEFT", anchor, "TOPLEFT", -2, 2)
    glow:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 2, -2)
    glow:SetFrameLevel(anchor:GetFrameLevel() + 9)
    glow:EnableMouse(false)
    glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 3 })
    glow:SetBackdropColor(0, 0, 0, 0)
    glow:SetBackdropBorderColor(1, 1, 1, 0.8)

    local ag = glow:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(1.0)
    anim:SetToAlpha(0.25)
    anim:SetDuration(0.7)
    anim:SetSmoothing("IN_OUT")
    glow._animGroup = ag

    glow:Hide()
    f._msufSIGlow = glow
    return glow
end

------------------------------------------------------------------------
-- Pulse effect: animated health bar overlay (C-side AnimationGroup)
------------------------------------------------------------------------
local function EnsurePulseOverlay(f)
    if f._msufSIPulse then return f._msufSIPulse end
    local bar = f.health
    if not bar then return nil end
    local pulse = CreateFrame("Frame", nil, bar)
    pulse:SetAllPoints(bar)
    pulse:SetFrameLevel(bar:GetFrameLevel() + 2)
    pulse:EnableMouse(false)
    local tex = pulse:CreateTexture(nil, "OVERLAY", nil, 2)
    tex:SetAllPoints()
    tex:SetBlendMode("ADD")
    tex:SetColorTexture(1, 1, 1, 0.25)
    pulse._tex = tex

    local ag = pulse:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(1.0)
    anim:SetToAlpha(0.1)
    anim:SetDuration(0.5)
    anim:SetSmoothing("IN_OUT")
    pulse._animGroup = ag

    pulse:Hide()
    f._msufSIPulse = pulse
    return pulse
end

------------------------------------------------------------------------
-- Reset / Apply frame effects
------------------------------------------------------------------------
local function ResetFrameEffects(f)
    -- Clear health bar color override → restore normal health color
    local hadHealthTint = f._msufSIHealthColorR
    f._msufSIHealthColorR = nil
    f._msufSIHealthColorG = nil
    f._msufSIHealthColorB = nil
    if hadHealthTint then
        -- Invalidate diff-gate stamp so ApplyHealthColor re-applies unconditionally
        f._msufGFHCStamp = nil
        if GF._ApplyHealthColor and f.health and f.unit then
            GF._ApplyHealthColor(f, f._msufGFKind or "party", f.unit)
        end
    end
    -- Legacy tint overlay (hide if still exists from old config)
    if f._msufSIHealthTint then f._msufSIHealthTint:Hide() end
    if f._msufSIBorderOverlay then f._msufSIBorderOverlay:Hide() end
    if f._msufSIGlow then
        if f._msufSIGlow._animGroup then f._msufSIGlow._animGroup:Stop() end
        f._msufSIGlow:Hide()
    end
    if f._msufSIPulse then
        if f._msufSIPulse._animGroup then f._msufSIPulse._animGroup:Stop() end
        f._msufSIPulse:Hide()
    end
    if f._msufSINameColorActive and f.nameText then
        f._msufSINameColorActive = nil
        -- Restore configured name color (CLASS/CUSTOM/DEFAULT — not hardcoded white)
        local kind = f._msufGFKind or "party"
        local unit = f.unit
        local classToken
        if unit and UnitClass then
            local _, ct = UnitClass(unit)
            classToken = ct
        end
        if GF.ResolveNameColor then
            local nr, ng, nb = GF.ResolveNameColor(kind, classToken)
            f.nameText:SetTextColor(nr or 1, ng or 1, nb or 1, 1)
        else
            local fr, fg, fb = GF.ResolveFontColor(kind)
            f.nameText:SetTextColor(fr or 1, fg or 1, fb or 1, 1)
        end
    end
end

local function ApplyFrameEffect(f, auraName, cfg, auraData)
    if not cfg or not cfg.type or not auraData then return end
    local c = cfg.color or {1, 1, 1, 1}

    if cfg.type == "healthtint" then
        -- Full bar color override (not a tint overlay)
        -- Sets _msufSIHealthColorR/G/B on frame → ApplyHealthColor in Effects respects it
        if f.health then
            f._msufSIHealthColorR = c[1]
            f._msufSIHealthColorG = c[2]
            f._msufSIHealthColorB = c[3]
            f.health:SetStatusBarColor(c[1], c[2], c[3], 1)
            if GF.ApplyHealthBarAlpha then
                GF.ApplyHealthBarAlpha(f, f._msufGFKind or "party")
            end
        end
    elseif cfg.type == "border" then
        local overlay = EnsureBorderOverlay(f)
        if overlay then
            local thickness = cfg.thickness or 2
            local curThick = overlay._msufThickness
            if curThick ~= thickness then
                overlay:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = thickness })
                overlay:SetBackdropColor(0, 0, 0, 0)
                overlay._msufThickness = thickness
            end
            overlay:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
            overlay:Show()
        end
    elseif cfg.type == "glow" then
        local glow = EnsureGlowOverlay(f)
        if glow then
            local thickness = cfg.thickness or 3
            local curThick = glow._msufThickness
            if curThick ~= thickness then
                glow:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = thickness })
                glow:SetBackdropColor(0, 0, 0, 0)
                glow._msufThickness = thickness
            end
            glow:ClearAllPoints()
            glow:SetPoint("TOPLEFT", (f.barGroup or f), "TOPLEFT", -thickness, thickness)
            glow:SetPoint("BOTTOMRIGHT", (f.barGroup or f), "BOTTOMRIGHT", thickness, -thickness)
            glow:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 0.9)
            glow:SetAlpha(1)
            glow:Show()
            if glow._animGroup and not glow._animGroup:IsPlaying() then
                glow._animGroup:Play()
            end
        end
    elseif cfg.type == "pulse" then
        local pulse = EnsurePulseOverlay(f)
        if pulse then
            local a = cfg.alpha or c[4] or 0.25
            pulse._tex:SetColorTexture(c[1], c[2], c[3], a)
            pulse:SetAlpha(1)
            pulse:Show()
            if pulse._animGroup and not pulse._animGroup:IsPlaying() then
                pulse._animGroup:Play()
            end
        end
    elseif cfg.type == "namecolor" then
        if f.nameText then
            f._msufSINameColorActive = auraName
            f.nameText:SetTextColor(c[1], c[2], c[3], c[4] or 1)
        end
    end
end

------------------------------------------------------------------------
-- Multi-spec dedup buffer (pre-allocated)
------------------------------------------------------------------------
local _multiProcessed = {}

------------------------------------------------------------------------
-- Core update iteration (shared logic for single/multi)
------------------------------------------------------------------------
local function IterateSpecConfig(f, unit, specKey, specCfg, parent, scale, bestByType, dedup, processed, siLayer)
    for auraName, auraCfg in pairs(specCfg) do
        if auraCfg and auraCfg.enabled ~= false then
            if not processed or not processed[auraName] then
                if processed then processed[auraName] = true end
                local auraData = _scanResults[auraName]
                if auraCfg.placed then
                    ApplyPlaced(f, unit, auraName, auraCfg.placed, auraData, parent, specKey, false, scale, siLayer)
                end
                if auraData and auraData.auraInstanceID and (auraCfg.placed or auraCfg.frame) then
                    dedup[auraData.auraInstanceID] = true
                    if auraCfg.placed then
                        local ptype = auraCfg.placed.type
                        if ptype == nil or ptype == "icon" then
                            f._msufSIHasIconPlaced = true
                        end
                    end
                end
                if auraCfg.frame and auraCfg.frame.type and auraData then
                    local ft = auraCfg.frame.type
                    local prio = auraCfg.frame.priority or 5
                    local best = bestByType[ft]
                    if not best or prio < best.prio then
                        bestByType[ft] = { name = auraName, cfg = auraCfg.frame, data = auraData, prio = prio }
                    end
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- Main update
------------------------------------------------------------------------
function GF.UpdateSpellIndicators(f, unit)
    if not f or not unit then return end
    if not UnitExists(unit) then GF.HideSpellIndicators(f); return end

    local kind  = f._msufGFKind or "party"
    local siCfg = GetSIConfig(kind)
    if not siCfg or not siCfg.enabled then GF.HideSpellIndicators(f); return end

    local specKey = ResolveSpec(siCfg)
    if not specKey then GF.HideSpellIndicators(f); return end

    CompileLookup(specKey, siCfg)

    local parent = f.barGroup or f
    local scale = GF.GetDynamicScale and GF.GetDynamicScale(GF.GetConf(kind)) or 1

    ScanUnit(unit, kind, siCfg, specKey)
    ResetFrameEffects(f)

    if not f._msufSIDedupIDs then f._msufSIDedupIDs = {} end
    local dedup = f._msufSIDedupIDs
    for k in pairs(dedup) do dedup[k] = nil end
    f._msufSIHasIconPlaced = false

    -- Reuse module-level table (cleared per call, zero GC)
    local bestByType = _siBestByType
    for k in pairs(bestByType) do bestByType[k] = nil end
    local siLayer = siCfg.layer or 9

    if specKey == "multi" then
        for k in pairs(_multiProcessed) do _multiProcessed[k] = nil end
        local ms = siCfg.multiSpecs
        if ms then
            for sk in pairs(ms) do
                local specCfg = EnsureSpecConfig(siCfg, sk)
                if specCfg then
                    IterateSpecConfig(f, unit, sk, specCfg, parent, scale, bestByType, dedup, _multiProcessed, siLayer)
                end
            end
        end
    else
        local specCfg = EnsureSpecConfig(siCfg, specKey)
        if not specCfg then GF.HideSpellIndicators(f); return end
        IterateSpecConfig(f, unit, specKey, specCfg, parent, scale, bestByType, dedup, nil, siLayer)
    end

    for _, fx in pairs(bestByType) do
        ApplyFrameEffect(f, fx.name, fx.cfg, fx.data)
    end

    if f._msufSIPlaced then
        for auraName, ind in pairs(f._msufSIPlaced) do
            local enabled = false
            if specKey == "multi" then
                local ms = siCfg.multiSpecs
                if ms then
                    for sk in pairs(ms) do
                        local sc = siCfg.specs and siCfg.specs[sk]
                        local ac = sc and sc[auraName]
                        if ac and ac.enabled ~= false and ac.placed then enabled = true; break end
                    end
                end
            else
                local sc = siCfg.specs and siCfg.specs[specKey]
                local ac = sc and sc[auraName]
                if ac and ac.enabled ~= false and ac.placed then enabled = true end
            end
            if not enabled then ind:Hide() end
        end
    end
end

function GF.HideSpellIndicators(f)
    if f._msufSIPlaced then
        for _, ind in pairs(f._msufSIPlaced) do ind:Hide() end
    end
    if f._msufSIDedupIDs then
        for k in pairs(f._msufSIDedupIDs) do f._msufSIDedupIDs[k] = nil end
    end
    f._msufSIHasIconPlaced = false
    ResetFrameEffects(f)
end

------------------------------------------------------------------------
-- Preview
------------------------------------------------------------------------
function GF.PreviewSpellIndicators(f, kind, classToken, specIdx)
    local siCfg = GetSIConfig(kind)
    if not siCfg or not siCfg.enabled then GF.HideSpellIndicators(f); return end
    local specKey
    if (siCfg.spec or "auto") == "multi" then
        specKey = "multi"
    elseif classToken and specIdx then
        specKey = SI.SpecMap[classToken .. "_" .. specIdx]
    else
        specKey = ResolveSpec(siCfg)
    end
    if not specKey then GF.HideSpellIndicators(f); return end

    CompileLookup(specKey, siCfg)

    local parent = f.barGroup or f
    ResetFrameEffects(f)
    if f._msufSIPlaced then
        for _, ind in pairs(f._msufSIPlaced) do ind:Hide() end
    end
    local siLayer = siCfg.layer or 9

    local function PreviewSpecConfig(sk, specCfg, processed, bestByType)
        local function PreviewAura(auraName, auraCfg)
            if not auraCfg or auraCfg.enabled == false then return end
            if processed then
                if processed[auraName] then return end
                processed[auraName] = true
            end
            local mock = { icon = SI.GetAuraIcon(sk, auraName), auraInstanceID = nil, applications = 0 }
            if auraCfg.placed then ApplyPlaced(f, nil, auraName, auraCfg.placed, mock, parent, sk, true, nil, siLayer) end
            if auraCfg.frame and auraCfg.frame.type then
                local ft = auraCfg.frame.type
                local prio = auraCfg.frame.priority or 5
                local best = bestByType[ft]
                if not best or prio < best.prio then
                    bestByType[ft] = { name = auraName, cfg = auraCfg.frame, data = mock, prio = prio }
                end
            end
        end

        local trackable = SI.TrackableAuras and SI.TrackableAuras[sk]
        if trackable then
            for _, info in ipairs(trackable) do
                PreviewAura(info.name, specCfg[info.name])
            end
        end
        for auraName, auraCfg in pairs(specCfg) do
            PreviewAura(auraName, auraCfg)
        end
    end

    if specKey == "multi" then
        local ms = siCfg.multiSpecs
        if not ms then return end
        local bestByType = {}
        for k in pairs(_multiProcessed) do _multiProcessed[k] = nil end
        for sk in pairs(ms) do
            local specCfg = EnsureSpecConfig(siCfg, sk)
            if specCfg then
                PreviewSpecConfig(sk, specCfg, _multiProcessed, bestByType)
            end
        end
        for _, fx in pairs(bestByType) do ApplyFrameEffect(f, fx.name, fx.cfg, fx.data) end
        return
    end

    local specCfg = EnsureSpecConfig(siCfg, specKey)
    if not specCfg then return end

    local bestByType = {}
    PreviewSpecConfig(specKey, specCfg, nil, bestByType)
    for _, fx in pairs(bestByType) do
        ApplyFrameEffect(f, fx.name, fx.cfg, fx.data)
    end
end

------------------------------------------------------------------------
-- Import / Export helpers
------------------------------------------------------------------------
do
    local function SerializeValue(v)
        local vt = type(v)
        if vt == "string" then return string.format("%q", v) end
        if vt == "number" then return tostring(v) end
        if vt == "boolean" then return v and "true" or "false" end
        if vt ~= "table" then return "nil" end
        local parts = {}
        for key, val in pairs(v) do
            local ks
            local kt = type(key)
            if kt == "string" then
                ks = "[" .. string.format("%q", key) .. "]"
            elseif kt == "number" then
                ks = "[" .. key .. "]"
            end
            if ks then parts[#parts + 1] = ks .. "=" .. SerializeValue(val) end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    function SI.ExportConfig(siCfg, specKey)
        if not siCfg or not specKey then return nil end
        local data = {}
        if siCfg.specs and siCfg.specs[specKey] then
            data.specs = siCfg.specs[specKey]
        end
        if siCfg.sortOrder and siCfg.sortOrder[specKey] then
            data.sortOrder = siCfg.sortOrder[specKey]
        end
        data.specKey = specKey
        return SerializeValue(data)
    end

    function SI.ImportConfig(siCfg, str)
        if not siCfg or not str or str == "" then return false end
        local fn = loadstring("return " .. str)
        if not fn then return false end
        setfenv(fn, {})
        local ok, data = pcall(fn)
        if not ok or type(data) ~= "table" then return false end
        local sk = data.specKey
        if not sk or type(sk) ~= "string" then return false end
        if not SI.SpecInfo[sk] then return false end
        siCfg.specs = siCfg.specs or {}
        if data.specs and type(data.specs) == "table" then
            siCfg.specs[sk] = data.specs
        end
        siCfg.sortOrder = siCfg.sortOrder or {}
        if data.sortOrder and type(data.sortOrder) == "table" then
            siCfg.sortOrder[sk] = data.sortOrder
        end
        return true, sk
    end
end

------------------------------------------------------------------------
-- Default factories + migration
------------------------------------------------------------------------
do
local function MakeBuffDefaults()
    return {
        enabled = true, anchor = "BOTTOMRIGHT", growth = "LEFTUP",
        x = 0, y = 0, size = 22, perRow = 4, max = 6, spacing = 1,
        layer = 5,
        filterMode = "RAID_PLAYER",
        showCooldownSwipe = true,
        showCooldown = true, cooldownAnchor = "CENTER",
        cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
        showStacks = true, stackAnchor = "BOTTOMRIGHT",
        stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
    }
end
local function MakeDebuffDefaults()
    return {
        enabled = true, anchor = "TOPLEFT", growth = "RIGHTDOWN",
        x = 0, y = 0, size = 20, perRow = 3, max = 6, spacing = 1,
        layer = 6,
        showDispelBorder = true,
        showCooldownSwipe = true,
        showCooldown = true, cooldownAnchor = "CENTER",
        cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 8, cooldownOutline = "OUTLINE",
        showStacks = true, stackAnchor = "BOTTOMRIGHT",
        stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
    }
end
local function MakeExternalsDefaults()
    return {
        enabled = true, anchor = "CENTER", growth = "RIGHTDOWN",
        x = 0, y = 0, size = 28, perRow = 3, max = 2, spacing = 1,
        layer = 7,
        showCooldownSwipe = true,
        showCooldown = true, cooldownAnchor = "CENTER",
        cooldownOffsetX = 0, cooldownOffsetY = 0, cooldownSize = 10, cooldownOutline = "OUTLINE",
        showStacks = false, stackAnchor = "BOTTOMRIGHT",
        stackOffsetX = 2, stackOffsetY = -2, stackSize = 10, stackOutline = "OUTLINE",
    }
end
local function MakePrivateAuraDefaults()
    return {
        enabled = true, max = 4, size = 20, anchor = "TOPRIGHT",
        direction = "LEFT", spacing = 1, x = 0, y = 0,
        layer = 8,
        showCountdown = true, showNumbers = false,
        showDispelType = false, showDuration = false,
        durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -1,
    }
end

local function EnsureAuraGroupDefaults(group, defaults)
    if type(group) ~= "table" or type(defaults) ~= "table" then return end
    for key, value in pairs(defaults) do
        if group[key] == nil then group[key] = value end
    end
end

local function EnsureBlizzardAuraDefaults(auras)
    if type(auras) ~= "table" then return end
    if auras.renderer == nil then auras.renderer = "BLIZZARD" end
    if type(auras.blizzardTypes) ~= "table" then auras.blizzardTypes = {} end
    local types = auras.blizzardTypes
    if types.buffs == nil then types.buffs = true end
    if types.debuffs == nil then types.debuffs = true end
    if types.dispels == nil then types.dispels = true end
    if types.externals == nil then types.externals = true end
    if types.privateAuras == nil then types.privateAuras = true end
    if auras.blizzardIconSize == nil then auras.blizzardIconSize = 20 end
    if auras.blizzardShowCooldownText == nil then auras.blizzardShowCooldownText = true end
    if auras.blizzardOrganizationType == nil then auras.blizzardOrganizationType = "default" end
    if auras.blizzardDispelMode == nil then auras.blizzardDispelMode = "allDispellable" end
    auras.blizzardContainerAnchor = "FRAME"
    auras.blizzardContainerX = 0
    auras.blizzardContainerY = 0
end

function GF.MigrateAuraConfig(conf, isRaid)
    if not conf then return end
    if conf.aurasEnabled ~= nil and not conf.auras then
        local b = MakeBuffDefaults()
        b.enabled = conf.aurasEnabled ~= false
        b.anchor = conf.auraAnchor or "BOTTOMLEFT"
        b.size = conf.auraIconSize or 20
        b.perRow = conf.auraPerRow or (conf.auraMaxIcons or 4)
        b.max = conf.auraMaxIcons or 4
        b.spacing = conf.auraSpacing or 1
        local d = MakeDebuffDefaults()
        d.size = conf.auraIconSize or 20
        d.max = conf.auraMaxIcons or 4
        d.spacing = conf.auraSpacing or 1
        conf.auras = { enabled = conf.aurasEnabled, buff = b, debuff = d, externals = MakeExternalsDefaults() }
        conf.aurasEnabled = nil; conf.auraMaxIcons = nil; conf.auraIconSize = nil
        conf.auraAnchor = nil; conf.auraGrowthX = nil; conf.auraGrowthY = nil
        conf.auraSpacing = nil; conf.auraPerRow = nil
    end
    if not conf.auras then
        local b = MakeBuffDefaults(); local d = MakeDebuffDefaults(); local e = MakeExternalsDefaults()
        if isRaid then
            b.size = 16; b.max = 3; b.perRow = 3
            d.size = 14; d.max = 3; d.perRow = 3
            e.size = 24; e.max = 2; e.perRow = 2
        end
        conf.auras = { enabled = true, buff = b, debuff = d, externals = e }
    end
    if conf.privateAurasEnabled ~= nil and not conf.privateAuras then
        conf.privateAuras = {
            enabled = conf.privateAurasEnabled,
            max = conf.privateAuraMax or 4, size = conf.privateAuraSize or 20,
            anchor = conf.privateAuraAnchor or "TOPRIGHT",
            direction = "LEFT", spacing = 1,
            x = conf.privateAuraX or 0, y = conf.privateAuraY or 0,
            showCountdown = conf.privateAuraCountdown ~= false,
            showNumbers = false, showDispelType = false, showDuration = false,
            durationAnchor = "BOTTOM", durationOffsetX = 0, durationOffsetY = -1,
        }
        conf.privateAurasEnabled = nil; conf.privateAuraMax = nil
        conf.privateAuraSize = nil; conf.privateAuraAnchor = nil
        conf.privateAuraX = nil; conf.privateAuraY = nil; conf.privateAuraCountdown = nil
    end
    if not conf.privateAuras then conf.privateAuras = MakePrivateAuraDefaults() end
    EnsureBlizzardAuraDefaults(conf.auras)
    if type(conf.auras.buff) ~= "table" then conf.auras.buff = MakeBuffDefaults() end
    if type(conf.auras.debuff) ~= "table" then conf.auras.debuff = MakeDebuffDefaults() end
    if type(conf.auras.externals) ~= "table" then conf.auras.externals = MakeExternalsDefaults() end
    EnsureAuraGroupDefaults(conf.auras.buff, MakeBuffDefaults())
    EnsureAuraGroupDefaults(conf.auras.debuff, MakeDebuffDefaults())
    EnsureAuraGroupDefaults(conf.auras.externals, MakeExternalsDefaults())
    if not conf.spellIndicators then conf.spellIndicators = { enabled = false, spec = "auto", specs = {}, layer = 9 } end
end
end -- do block

------------------------------------------------------------------------
_G.MSUF_GF_UpdateSpellIndicators  = GF.UpdateSpellIndicators
_G.MSUF_GF_HideSpellIndicators   = GF.HideSpellIndicators
_G.MSUF_GF_PreviewSpellIndicators = GF.PreviewSpellIndicators
_G.MSUF_GF_MigrateAuraConfig     = GF.MigrateAuraConfig
