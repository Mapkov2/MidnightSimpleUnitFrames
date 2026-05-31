local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF_NS = MSUF
_G.MSUF = MSUF

local UF = MSUF.UF
local GF = MSUF.GF or {}
MSUF.GF = GF

if not (UF and UF.RegisterElement) then return end

local AuraCache = GF.AuraCache or {}
local SetShown = AuraCache.SetShown or function(region, show) if region then region:SetShown(show) end end
local DispelState = UF and UF.DispelState or {}
local UnitThreatSituation = UnitThreatSituation
local CreateFrame = CreateFrame
local tonumber = tonumber
local type = type
local pairs = pairs
local floor = math.floor
local max = math.max
local Secrets = MSUF.Secrets or {}
local IsSecret = Secrets.IsSecret or function(_) return false end
local IsNil = Secrets.IsNil or function(value) return value == nil end
local UnitMissing = Secrets.UnitMissing or function(_) return false end
local Apply = MSUF.Apply or {}
local ApplyColorTexture = Apply.ColorTexture or function(tex, r, g, b, a)
    if not tex then return end
    a = a or 1
    if tex._aColorTexture ~= true or tex._aCTR ~= r or tex._aCTG ~= g
        or tex._aCTB ~= b or tex._aCTA ~= a then
        tex:SetColorTexture(r, g, b, a)
        tex._aColorTexture = true
        tex._aCTR = r
        tex._aCTG = g
        tex._aCTB = b
        tex._aCTA = a
        tex._aTex = nil
    end
end
local ApplyTexture = Apply.Texture or function(tex, texture)
    if not tex then return end
    if tex and IsSecret(texture) then
        tex._aTex = nil
        tex._aColorTexture = nil
        tex:SetTexture(texture)
        return
    end
    if tex._aTex ~= texture then
        tex:SetTexture(texture)
        tex._aTex = texture
        tex._aColorTexture = nil
    end
end
local ApplyText = Apply.Text or function(fs, text)
    if fs and IsSecret(text) then
        fs._aText = nil
        fs:SetText(text)
        return
    end
    text = text or ""
    if fs and fs._aText ~= text then
        fs:SetText(text)
        fs._aText = text
    end
end

local EMPTY = AuraCache.EMPTY or {}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local CORNER_EVENTS = { "UNIT_AURA", "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local CORNER_AURA_EVENTS = { "UNIT_AURA" }
local CORNER_THREAT_EVENTS = { "UNIT_THREAT_SITUATION_UPDATE", "UNIT_THREAT_LIST_UPDATE" }
local SPELL_EVENTS = { "UNIT_AURA" }
local EFFECT_TYPES = { "healthtint", "border", "glow", "pulse", "namecolor" }

local function ClampLayer(layer, fallback)
    layer = floor((tonumber(layer) or fallback or 7) + 0.5)
    if layer < 0 then return 0 end
    if layer > 30 then return 30 end
    return layer
end

local function DrawSubLayer(layer, fallback)
    layer = ClampLayer(layer, fallback)
    if layer > 7 then return 7 end
    return layer
end

local function BaseFrameLevel(frame)
    local base = frame and (frame.hpBar or frame.Health or frame)
    return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

local function EnsureHolder(frame, key, layer)
    frame.MSUFGFIndicatorHolders = frame.MSUFGFIndicatorHolders or {}
    local layerKey = key .. ":" .. ClampLayer(layer, 7)
    local holder = frame.MSUFGFIndicatorHolders[layerKey]
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:EnableMouse(false)
        frame.MSUFGFIndicatorHolders[layerKey] = holder
    end
    local level = BaseFrameLevel(frame) + ClampLayer(layer, 7)
    if holder.SetFrameLevel and holder._msufGFLevel ~= level then
        holder:SetFrameLevel(level)
        holder._msufGFLevel = level
    end
    return holder
end

local function SetAllPointsCached(region, target)
    if not region then return end
    target = target or true
    if region._msufGFAllPointsTarget == target then
        return
    end
    region:ClearAllPoints()
    if target == true then
        region:SetAllPoints()
    else
        region:SetAllPoints(target)
    end
    region._msufGFAllPointsTarget = target
end

local function SetPointCached(region, point, relativeTo, relativePoint, x, y)
    x, y = x or 0, y or 0
    relativePoint = relativePoint or point
    if region._msufGFPoint == point and region._msufGFRel == relativeTo
        and region._msufGFRelPoint == relativePoint and region._msufGFX == x and region._msufGFY == y then
        return
    end
    region._msufGFPoint, region._msufGFRel, region._msufGFRelPoint = point, relativeTo, relativePoint
    region._msufGFX, region._msufGFY = x, y
    region:ClearAllPoints()
    region:SetPoint(point, relativeTo, relativePoint, x, y)
end

local function SetSizeCached(region, w, h)
    h = h or w
    if region._msufGFW == w and region._msufGFH == h then return end
    region._msufGFW, region._msufGFH = w, h
    region:SetSize(w, h)
end

local function SetColorTextureCached(tex, r, g, b, a)
    ApplyColorTexture(tex, r, g, b, a)
end

local function SetTextureCached(tex, texture)
    ApplyTexture(tex, texture)
end

local function SetDesaturatedCached(tex, desaturated)
    if tex and tex.SetDesaturated then
        desaturated = desaturated == true
        if tex._msufGFDesaturated ~= desaturated then
            tex:SetDesaturated(desaturated)
            tex._msufGFDesaturated = desaturated
        end
    end
end

local function SetTextCached(fs, text)
    ApplyText(fs, text)
end

local function HasThreat(unit)
    if not UnitThreatSituation or not unit then return false end
    local status = UnitThreatSituation(unit)
    if IsNil(status) or IsSecret(status) then return false end
    status = tonumber(status)
    return status ~= nil and status >= 1
end

local GroupCornerIndicators = {}

function GroupCornerIndicators.IsEnabled(frame, spec)
    return spec and spec.scope == "group" and spec.cornerIndicators
        and spec.cornerIndicators.enabled == true and spec.cornerIndicators.hasWork == true
end

function GroupCornerIndicators.GetEvents(frame, spec)
    local cfg = spec and spec.cornerIndicators
    if cfg and cfg.needsAura == true and cfg.needsThreat ~= true then return CORNER_AURA_EVENTS end
    if cfg and cfg.needsThreat == true and cfg.needsAura ~= true then return CORNER_THREAT_EVENTS end
    return CORNER_EVENTS
end

local function EnsureCorner(frame, key, layer)
    local holder = EnsureHolder(frame, "corner", layer)
    frame.MSUFGFCornerIndicators = frame.MSUFGFCornerIndicators or {}
    local tex = frame.MSUFGFCornerIndicators[key]
    local sub = DrawSubLayer(layer, 7)
    if not tex or tex:GetParent() ~= holder then
        if tex then tex:Hide() end
        tex = holder:CreateTexture(nil, "OVERLAY", nil, sub)
        frame.MSUFGFCornerIndicators[key] = tex
    elseif tex._msufGFLayer ~= sub and tex.SetDrawLayer then
        tex:SetDrawLayer("OVERLAY", sub)
    end
    tex._msufGFLayer = sub
    return tex, holder
end

local function HideCorners(frame)
    if frame and frame.MSUFGFCornerIndicators then
        for _, tex in pairs(frame.MSUFGFCornerIndicators) do SetShown(tex, false) end
    end
end

local function UpdateCornerIndicators(frame)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.cornerIndicators
    if not (cfg and cfg.enabled == true) then HideCorners(frame); return end
    local unit = frame.unit
    if unit and UnitMissing(unit) then HideCorners(frame); return end
    local snapshot = AuraCache.GetSnapshot and AuraCache.GetSnapshot(frame)
    local threat = HasThreat(unit)
    local slots = cfg.slots or EMPTY
    for i = 1, #slots do
        local slot = slots[i]
        local show, r, g, b = false, 1, 1, 1
        if slot.category == "dispel" then
            show = snapshot and snapshot.dispellable == true
            r, g, b = 0.25, 0.75, 1
            if show and DispelState.ColorForTrigger then
                r, g, b = DispelState.ColorForTrigger(snapshot, "BY_ME", frame.MSUFSpec and frame.MSUFSpec.dispel, cfg.alpha or 1)
            end
        elseif slot.category == "aggro" then
            show = threat
            r, g, b = cfg.aggroR or 1, cfg.aggroG or 0.55, cfg.aggroB or 0
        elseif slot.category == "custom" then
            if slot.ids or slot.names then
                local present = AuraCache.Find and AuraCache.Find(frame, slot.filter, slot.ids, slot.names, false)
                show = (slot.mode == "missing") and not present or present
            end
            r, g, b = slot.r or 0.4, slot.g or 1, slot.b or 0.4
        end
        if show then
            local tex, holder = EnsureCorner(frame, slot.key, cfg.layer)
            local size = max(1, tonumber(cfg.size) or 8)
            SetSizeCached(tex, size, size)
            SetColorTextureCached(tex, r, g, b, cfg.alpha or 1)
            SetPointCached(tex, slot.anchor or "CENTER", holder, slot.anchor or "CENTER", slot.x or 0, slot.y or 0)
            SetShown(tex, true)
        else
            local tex = frame.MSUFGFCornerIndicators and frame.MSUFGFCornerIndicators[slot.key]
            SetShown(tex, false)
        end
    end
end

function GroupCornerIndicators.Apply(frame) UpdateCornerIndicators(frame) end
function GroupCornerIndicators.Update(frame) UpdateCornerIndicators(frame) end
function GroupCornerIndicators.Disable(frame) HideCorners(frame) end

UF.RegisterElement("GroupCornerIndicators", GroupCornerIndicators)

local function ClearCooldown(ind)
    local cd = ind and ind.cooldown
    if cd and not cd._msufGFCleared then
        cd:Clear()
        cd._msufGFCleared = true
    end
end

local function ApplyCooldown(ind, item, data, numberOnly)
    local cd = ind and ind.cooldown
    local placed = item and item.placed
    if not (cd and placed and data) then ClearCooldown(ind); return end
    if IsSecret(data.duration) or IsSecret(data.expirationTime) then ClearCooldown(ind); return end
    local duration = tonumber(data.duration)
    local expiration = tonumber(data.expirationTime)
    if not (duration and duration > 0 and expiration and expiration > 0) then ClearCooldown(ind); return end
    if cd.SetDrawSwipe then cd:SetDrawSwipe(numberOnly and false or placed.showCooldownSwipe == true) end
    if cd.SetDrawEdge then cd:SetDrawEdge(false) end
    if cd.SetDrawBling then cd:SetDrawBling(false) end
    if cd.SetHideCountdownNumbers then cd:SetHideCountdownNumbers(placed.showCooldown ~= true and not numberOnly) end
    cd:SetCooldown(expiration - duration, duration)
    cd._msufGFCleared = nil
end

local function EnsureFontString(parent, field, template)
    local fs = parent[field]
    if not fs then
        fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
        parent[field] = fs
    end
    return fs
end

local function ApplyFont(fs, size)
    local fontPath, flags
    if type(_G.MSUF_GetGlobalFontSettings) == "function" then
        fontPath, flags = _G.MSUF_GetGlobalFontSettings()
    end
    fontPath = fontPath or "Fonts\\FRIZQT__.TTF"
    flags = flags or "OUTLINE"
    size = floor((tonumber(size) or 8) + 0.5)
    if fs._msufGFFontPath ~= fontPath or fs._msufGFFontSize ~= size or fs._msufGFFontFlags ~= flags then
        fs:SetFont(fontPath, size, flags)
        fs._msufGFFontPath, fs._msufGFFontSize, fs._msufGFFontFlags = fontPath, size, flags
    end
end

local function CreatePlaced(parent, indicatorType)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:EnableMouse(false)
    f._msufGFType = indicatorType
    if indicatorType == "icon" then
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        f.texture = tex
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints()
        f.cooldown = cd
        local count = EnsureFontString(f, "count", "GameFontHighlightSmall")
        count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        count:SetJustifyH("RIGHT")
        f:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0)
        f:SetBackdropBorderColor(0, 0, 0, 0.8)
    elseif indicatorType == "number" then
        local cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
        cd:SetAllPoints()
        f.cooldown = cd
        local text = EnsureFontString(f, "numberText", "GameFontHighlight")
        text:SetPoint("CENTER", f, "CENTER", 0, 0)
        text:SetJustifyH("CENTER")
    elseif indicatorType == "bar" then
        local bg = f:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.65)
        f.bg = bg
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
        tex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1, 1)
        f.texture = tex
        f:SetBackdrop({ edgeFile = WHITE, edgeSize = 1 })
        f:SetBackdropColor(0, 0, 0, 0)
        f:SetBackdropBorderColor(0, 0, 0, 0.7)
    else
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        f.texture = tex
    end
    f:Hide()
    return f
end

local function EnsurePlaced(frame, index, item, layer)
    local placed = item.placed
    local holder = EnsureHolder(frame, "spell", layer or 9)
    frame.MSUFGFSpellIndicators = frame.MSUFGFSpellIndicators or {}
    local ind = frame.MSUFGFSpellIndicators[index]
    local indicatorType = placed and placed.type or "icon"
    if not ind or ind._msufGFType ~= indicatorType or ind:GetParent() ~= holder then
        if ind then SetShown(ind, false) end
        ind = CreatePlaced(holder, indicatorType)
        frame.MSUFGFSpellIndicators[index] = ind
    end
    return ind, holder
end

local function GrowthOffset(frame, placed, width, height)
    local key = (placed.anchor or "TOPLEFT") .. ":" .. (placed.growth or "RIGHTDOWN")
    local counters = frame._msufSIGrowthCounters
    counters[key] = (counters[key] or 0) + 1
    local n = counters[key] - 1
    if n <= 0 then return 0, 0 end
    local growth = placed.growth or "RIGHTDOWN"
    local xDir = growth:find("LEFT", 1, true) and -1 or 1
    local yDir = growth:find("UP", 1, true) and 1 or -1
    local col = n % 4
    local row = floor(n / 4)
    return col * (width + 2) * xDir, row * (height + 2) * yDir
end

local function LayoutPlaced(frame, ind, holder, placed)
    local size = max(1, tonumber(placed.size) or 18)
    local w, h = size, size
    if placed.type == "bar" then
        w, h = max(8, tonumber(placed.barWidth) or 42), size
    elseif placed.type == "number" then
        w, h = max(18, floor(size * 2.2 + 0.5)), max(10, floor(size * 1.4 + 0.5))
    end
    SetSizeCached(ind, w, h)
    local dx, dy = GrowthOffset(frame, placed, w, h)
    SetPointCached(ind, placed.anchor or "TOPLEFT", holder, placed.anchor or "TOPLEFT", (placed.x or 0) + dx, (placed.y or 0) + dy)
end

local function ApplyPlaced(frame, index, item, present, data, layer)
    local placed = item.placed
    if not placed then return end
    local show = placed.missing == true and not present or present
    if not show then
        local old = frame.MSUFGFSpellIndicators and frame.MSUFGFSpellIndicators[index]
        if old then
            ClearCooldown(old)
            SetShown(old, false)
        end
        return
    end

    local ind, holder = EnsurePlaced(frame, index, item, layer)
    LayoutPlaced(frame, ind, holder, placed)
    if placed.type == "icon" then
        local icon = data and data.icon or item.icon or 136243
        SetTextureCached(ind.texture, icon)
        SetDesaturatedCached(ind.texture, not present)
        if ind.texture and ind.texture.SetAlpha then ind.texture:SetAlpha(present and 1 or 0.35) end
        ApplyCooldown(ind, item, present and data or nil, false)
        local rawApplications = data and data.applications or nil
        local applications = not IsSecret(rawApplications) and tonumber(rawApplications) or nil
        if IsSecret(rawApplications) then
            ApplyFont(ind.count, max(7, floor((placed.size or 18) * 0.48 + 0.5)))
            SetTextCached(ind.count, rawApplications)
            SetShown(ind.count, true)
        elseif applications and applications > 1 then
            ApplyFont(ind.count, max(7, floor((placed.size or 18) * 0.48 + 0.5)))
            SetTextCached(ind.count, tostring(applications))
            SetShown(ind.count, true)
        else
            SetTextCached(ind.count, "")
            SetShown(ind.count, false)
        end
    elseif placed.type == "number" then
        ApplyFont(ind.numberText, placed.cooldownSize or placed.size or 10)
        ApplyCooldown(ind, item, present and data or nil, true)
        if present then
            local rawApplications = data and data.applications or nil
            local applications = not IsSecret(rawApplications) and tonumber(rawApplications) or nil
            SetTextCached(ind.numberText, IsSecret(rawApplications) and rawApplications or (applications and applications > 1 and tostring(applications) or ""))
        else
            ClearCooldown(ind)
            SetTextCached(ind.numberText, "0")
        end
        SetShown(ind.numberText, true)
    else
        local r, g, b, a = item.r or 0.5, item.g or 0.8, item.b or 0.5, item.a or 1
        if not present then r, g, b, a = 0.3, 0.3, 0.3, 0.5 end
        SetColorTextureCached(ind.texture, r, g, b, a)
    end
    SetShown(ind, true)
end

local function EnsureOverlay(frame, key, parent)
    local overlay = frame[key]
    if not overlay or overlay:GetParent() ~= parent then
        if overlay then overlay:Hide() end
        overlay = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        overlay:EnableMouse(false)
        frame[key] = overlay
    end
    return overlay
end

local function EnsureTextureOverlay(frame, key, parent)
    local tex = frame[key]
    if not tex or tex:GetParent() ~= parent then
        if tex then tex:Hide() end
        tex = parent:CreateTexture(nil, "OVERLAY", nil, 6)
        frame[key] = tex
    end
    return tex
end

local function ClearEffectSet(active)
    if not active then return end
    for i = 1, #EFFECT_TYPES do
        active[EFFECT_TYPES[i]] = nil
    end
end

local function HideEffect(frame, key)
    local obj = frame and frame[key]
    if obj and obj._animGroup then obj._animGroup:Stop() end
    SetShown(obj, false)
end

local function ApplyAnimatedBorder(obj, r, g, b, a, thickness, duration)
    if obj._msufGFThickness ~= thickness then
        obj:SetBackdrop({ edgeFile = WHITE, edgeSize = thickness })
        obj:SetBackdropColor(0, 0, 0, 0)
        obj._msufGFThickness = thickness
    end
    if obj._msufGFR ~= r or obj._msufGFG ~= g or obj._msufGFB ~= b or obj._msufGFA ~= a then
        obj:SetBackdropBorderColor(r, g, b, a)
        obj._msufGFR, obj._msufGFG, obj._msufGFB, obj._msufGFA = r, g, b, a
    end
    if not obj._animGroup then
        local ag = obj:CreateAnimationGroup()
        ag:SetLooping("BOUNCE")
        local anim = ag:CreateAnimation("Alpha")
        anim:SetFromAlpha(1)
        anim:SetToAlpha(0.25)
        anim:SetDuration(duration or 0.7)
        anim:SetSmoothing("IN_OUT")
        obj._animGroup = ag
    end
    if not obj._animGroup:IsPlaying() then obj._animGroup:Play() end
end

local function ResetFrameEffects(frame, active)
    active = active or EMPTY
    if not active.healthtint then HideEffect(frame, "MSUFGFSIHealthTint") end
    if not active.border then HideEffect(frame, "MSUFGFSIBorder") end
    if not active.glow then HideEffect(frame, "MSUFGFSIGlow") end
    if not active.pulse then HideEffect(frame, "MSUFGFSIPulse") end
    if not active.namecolor and frame._msufSINameColorActive then
        frame._msufSINameColorActive = nil
        local rt = MSUF and MSUF.UFTextRuntime
        if rt and rt.UpdateNameColor then rt.UpdateNameColor(frame, "MSUF_GF_SI_NAMECOLOR", frame.unit) end
    end
end

local function ApplyFrameEffects(frame, best)
    if not frame then return end
    local active = frame._msufSIActiveEffects
    if active then
        ClearEffectSet(active)
    else
        active = {}
        frame._msufSIActiveEffects = active
    end
    for i = 1, #EFFECT_TYPES do
        local effectType = EFFECT_TYPES[i]
        local item = best[effectType]
        if item then
            active[effectType] = true
            local effect = item.effect
            local r, g, b, a = effect.r or item.r or 1, effect.g or item.g or 1, effect.b or item.b or 1, effect.a or item.a or 1
            local thickness = max(1, effect.thickness or 2)
            if effectType == "healthtint" then
                local bar = frame.hpBar or frame.Health or frame
                local tex = EnsureTextureOverlay(frame, "MSUFGFSIHealthTint", bar)
                SetAllPointsCached(tex, bar)
                tex:SetBlendMode("ADD")
                SetColorTextureCached(tex, r, g, b, a)
                SetShown(tex, true)
            elseif effectType == "border" then
                local overlay = EnsureOverlay(frame, "MSUFGFSIBorder", frame)
                SetAllPointsCached(overlay, frame)
                if overlay._msufGFThickness ~= thickness then
                    overlay:SetBackdrop({ edgeFile = WHITE, edgeSize = thickness })
                    overlay:SetBackdropColor(0, 0, 0, 0)
                    overlay._msufGFThickness = thickness
                end
                overlay:SetBackdropBorderColor(r, g, b, a)
                SetShown(overlay, true)
            elseif effectType == "glow" then
                local overlay = EnsureOverlay(frame, "MSUFGFSIGlow", frame)
                SetPointCached(overlay, "TOPLEFT", frame, "TOPLEFT", -thickness, thickness)
                overlay:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", thickness, -thickness)
                ApplyAnimatedBorder(overlay, r, g, b, a, thickness, 0.7)
                SetShown(overlay, true)
            elseif effectType == "pulse" then
                local bar = frame.hpBar or frame.Health or frame
                local tex = EnsureTextureOverlay(frame, "MSUFGFSIPulse", bar)
                SetAllPointsCached(tex, bar)
                tex:SetBlendMode("ADD")
                SetColorTextureCached(tex, r, g, b, a)
                if not tex._animGroup then
                    local ag = tex:CreateAnimationGroup()
                    ag:SetLooping("BOUNCE")
                    local anim = ag:CreateAnimation("Alpha")
                    anim:SetFromAlpha(1)
                    anim:SetToAlpha(0.1)
                    anim:SetDuration(0.5)
                    anim:SetSmoothing("IN_OUT")
                    tex._animGroup = ag
                end
                if not tex._animGroup:IsPlaying() then tex._animGroup:Play() end
                SetShown(tex, true)
            elseif effectType == "namecolor" and frame.nameText then
                frame._msufSINameColorActive = item.key
                frame.nameText:SetTextColor(r, g, b, a)
            end
        end
    end
    ResetFrameEffects(frame, active)
end

local GroupSpellIndicators = {}

function GroupSpellIndicators.IsEnabled(frame, spec)
    return spec and spec.scope == "group"
        and spec.spellIndicators
        and spec.spellIndicators.enabled == true
        and #(spec.spellIndicators.items or EMPTY) > 0
end

function GroupSpellIndicators.GetEvents()
    return SPELL_EVENTS
end

local function HideSpellIndicators(frame)
    if frame and frame.MSUFGFSpellIndicators then
        for i = 1, #frame.MSUFGFSpellIndicators do
            local ind = frame.MSUFGFSpellIndicators[i]
            ClearCooldown(ind)
            SetShown(ind, false)
        end
    end
    ResetFrameEffects(frame)
end

local function StoreBest(best, item)
    local effect = item.effect
    if not effect then return end
    local old = best[effect.type]
    if not old or (effect.priority or 5) < (old.effect.priority or 5) then
        best[effect.type] = item
    end
end

local function UpdateSpellIndicators(frame)
    local cfg = frame.MSUFSpec and frame.MSUFSpec.spellIndicators
    if not (cfg and cfg.enabled == true) then HideSpellIndicators(frame); return end
    local unit = frame.unit
    if unit and UnitMissing(unit) then HideSpellIndicators(frame); return end
    local items = cfg.items or EMPTY
    frame._msufSIGrowthCounters = frame._msufSIGrowthCounters or {}
    for k in pairs(frame._msufSIGrowthCounters) do frame._msufSIGrowthCounters[k] = nil end
    local best = frame._msufSIBestEffects or {}
    frame._msufSIBestEffects = best
    for k in pairs(best) do best[k] = nil end

    if cfg.hasMissing ~= true and AuraCache.ContainsAny and not AuraCache.ContainsAny(frame, cfg.watched) then
        if frame.MSUFGFSpellIndicators then
            for i = 1, #frame.MSUFGFSpellIndicators do
                local ind = frame.MSUFGFSpellIndicators[i]
                ClearCooldown(ind)
                SetShown(ind, false)
            end
        end
        ApplyFrameEffects(frame, best)
        return
    end

    for i = 1, #items do
        local item = items[i]
        local present, data = AuraCache.Find and AuraCache.Find(frame, item.filter, item.ids, item.names, item.onlyOwn)
        if item.placed then ApplyPlaced(frame, i, item, present, data, cfg.layer) end
        if present and item.effect then StoreBest(best, item) end
    end
    if frame.MSUFGFSpellIndicators then
        for i = #items + 1, #frame.MSUFGFSpellIndicators do
            local ind = frame.MSUFGFSpellIndicators[i]
            ClearCooldown(ind)
            SetShown(ind, false)
        end
    end
    ApplyFrameEffects(frame, best)
end

function GroupSpellIndicators.Apply(frame) UpdateSpellIndicators(frame) end
function GroupSpellIndicators.Update(frame) UpdateSpellIndicators(frame) end
function GroupSpellIndicators.Disable(frame) HideSpellIndicators(frame) end

UF.RegisterElement("GroupSpellIndicators", GroupSpellIndicators)

GF.CI_SLOT_KEYS = { "TL", "TR", "BL", "BR", "C" }
GF.CI_CATEGORIES = {
    { key = "none", value = "none", label = "None", text = "None" },
    { key = "dispel", value = "dispel", label = "Dispellable", text = "Dispellable" },
    { key = "aggro", value = "aggro", label = "Aggro/Threat", text = "Aggro/Threat" },
    { key = "custom", value = "custom", label = "Custom Spell", text = "Custom Spell" },
}
GF.CI_CUSTOM_FILTERS = {
    { key = "HELPFUL|PLAYER", value = "HELPFUL|PLAYER", label = "Buff (cast by me)", text = "Buff (cast by me)", secretSafe = true },
    { key = "HELPFUL", value = "HELPFUL", label = "Buff (any caster)", text = "Buff (any caster)", secretSafe = false },
    { key = "HARMFUL|PLAYER", value = "HARMFUL|PLAYER", label = "Debuff (cast by me)", text = "Debuff (cast by me)", secretSafe = true },
    { key = "HARMFUL", value = "HARMFUL", label = "Debuff (any caster)", text = "Debuff (any caster)", secretSafe = false },
}
GF.CI_CUSTOM_MODES = {
    { key = "present", value = "present", label = "Show when present", text = "Show when present" },
    { key = "missing", value = "missing", label = "Show when missing", text = "Show when missing" },
}
