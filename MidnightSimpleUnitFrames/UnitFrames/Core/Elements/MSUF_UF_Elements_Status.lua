local addonName, MSUF = ...

MSUF = MSUF or _G.MSUF_NS or {}
_G.MSUF_NS = MSUF

local UF = MSUF.UF
if not UF then return end

local CreateFrame = CreateFrame
local UnitExists = UnitExists
local UnitIsGroupLeader = UnitIsGroupLeader
local UnitIsGroupAssistant = UnitIsGroupAssistant
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitAffectingCombat = UnitAffectingCombat
local UnitHasIncomingResurrection = UnitHasIncomingResurrection
local UnitLevel = UnitLevel
local UnitClassification = UnitClassification or GetUnitClassification
local UnitIsConnected = UnitIsConnected
local UnitIsPlayer = UnitIsPlayer
local UnitIsGhost = UnitIsGhost
local UnitIsDead = UnitIsDead
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitIsAFK = UnitIsAFK
local UnitIsDND = UnitIsDND
local UnitPhaseReason = UnitPhaseReason
local UnitInRaid = UnitInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local GetRaidTargetIndex = GetRaidTargetIndex
local GetReadyCheckStatus = GetReadyCheckStatus
local SetRaidTargetIconTexture = SetRaidTargetIconTexture
local IsResting = IsResting
local InCombatLockdown = InCombatLockdown
local C_IncomingSummon = C_IncomingSummon
local C_Timer = C_Timer
local type = type
local tostring = tostring
local tonumber = tonumber
local floor = math.floor
local find = string.find
local setmetatable = setmetatable
local issecretvalue = _G.issecretvalue

-- `GetRaidTargetIndex` (and a few sibling unit APIs) can return secret number
-- values for hidden/protected units. Storing such a value on a region and
-- later comparing it with `==`/`~=` taints the comparison and bubbles up
-- "attempt to compare ... a secret value". Use IsSecret to gate every store
-- and comparison; treat secret as "unknown — always re-apply".
local IsSecret = issecretvalue or function(_) return false end

local EMPTY_EVENTS = {}
local WHITE = "Interface\\Buttons\\WHITE8x8"
local ADDON_PATH = "Interface\\AddOns\\" .. (addonName or "MidnightSimpleUnitFrames")
local RAID_MARKER_TEXTURE = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local LEADER_TEXTURE = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ASSIST_TEXTURE = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local READY_TEXTURE_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local READY_TEXTURE_NOT_READY = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local READY_TEXTURE_WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local READY_REZ_TEXTURE = "Interface\\RaidFrame\\Raid-Icon-Rez"
local PHASE_TEXTURE = "Interface\\TargetingFrame\\UI-PhasingIcon"
local STATE_TEXTURE = "Interface\\CharacterFrame\\UI-StateIcon"
local SYMBOL_BASE = ADDON_PATH .. "\\Media\\Symbols\\"
local SUMMON_TEXTURES = {
    [1] = "Interface\\RaidFrame\\Raid-Icon-SummonPending",
    [2] = "Interface\\RaidFrame\\Raid-Icon-SummonAccepted",
    [3] = "Interface\\RaidFrame\\Raid-Icon-SummonDeclined",
}
local STATUS_REFRESH = {
    "StatusIndicators",
    "RaidMarkerIndicator",
    "LeaderIndicator",
    "LevelIndicator",
    "RaidGroupIndicator",
    "EliteIndicator",
    "StatusTextIndicator",
    "CombatIndicator",
    "RestingIndicator",
    "IncomingResIndicator",
    "GroupStatusRuntime",
}
local SYMBOL_PATH_CACHE = {}
local READY_CHECK_TIMERS = setmetatable({}, { __mode = "k" })
local READY_CHECK_TOKEN = 0

local Status = {}

local function ClampLayer(layer, fallback)
    layer = floor((tonumber(layer) or fallback or 7) + 0.5)
    if layer < 0 then
        return 0
    elseif layer > 30 then
        return 30
    end
    return layer
end

local function GetLayerBaseLevel(frame)
    local base = frame and (frame.Health or frame.hpBar or frame)
    return base and base.GetFrameLevel and (base:GetFrameLevel() or 0) or 0
end

local function EnsureLayerFrame(frame, layer)
    if not frame then
        return nil
    end
    layer = ClampLayer(layer, 7)
    local layers = frame.MSUFStatusLayers
    if not layers then
        layers = {}
        frame.MSUFStatusLayers = layers
    end
    local holder = layers[layer]
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:EnableMouse(false)
        if holder.SetClipsChildren then
            holder:SetClipsChildren(false)
        end
        layers[layer] = holder
    end
    if holder.SetFrameLevel then
        local level = GetLayerBaseLevel(frame) + layer
        if holder._msufStatusFrameLevel ~= level then
            holder:SetFrameLevel(level)
            holder._msufStatusFrameLevel = level
        end
    end
    return holder, layer
end

local function SetShown(region, show)
    if region and region._msufStatusShown ~= show then
        region:SetShown(show)
        region._msufStatusShown = show
    end
end

local function SetTexture(region, texture)
    if region and region._msufStatusTexture ~= texture then
        region:SetTexture(texture)
        region._msufStatusTexture = texture
        region._msufStatusAtlas = nil
    end
end

local function SetAtlas(region, atlas)
    if region and region.SetAtlas and region._msufStatusAtlas ~= atlas then
        region:SetAtlas(atlas)
        region._msufStatusAtlas = atlas
        region._msufStatusTexture = nil
        region._msufStatusL, region._msufStatusR, region._msufStatusT, region._msufStatusB = nil, nil, nil, nil
    end
end

local function SetTexCoord(region, l, r, t, b)
    if region and region.SetTexCoord
        and (region._msufStatusL ~= l or region._msufStatusR ~= r or region._msufStatusT ~= t or region._msufStatusB ~= b) then
        region:SetTexCoord(l, r, t, b)
        region._msufStatusL, region._msufStatusR, region._msufStatusT, region._msufStatusB = l, r, t, b
    end
end

local function SetText(region, text, raw)
    if not region then
        return
    end
    if raw == true then
        region:SetText(text)
        region._msufStatusText = nil
    elseif region._msufStatusText ~= text then
        region:SetText(text)
        region._msufStatusText = text
    end
end

local function SetFont(region, spec, size)
    if not region or not region.SetFont then
        return
    end
    local font = spec and spec.font
    local flags = spec and spec.fontFlags or "OUTLINE"
    size = tonumber(size) or 14
    if font and (region._msufStatusFont ~= font or region._msufStatusFontSize ~= size or region._msufStatusFontFlags ~= flags) then
        region:SetFont(font, size, flags)
        region._msufStatusFont, region._msufStatusFontSize, region._msufStatusFontFlags = font, size, flags
    end
end

local function ApplyTextColor(region, spec)
    local c = spec and spec.textColor
    local r, g, b, a = c and c.r or 1, c and c.g or 1, c and c.b or 1, c and c.a or 1
    if region and region.SetTextColor
        and (region._msufStatusR ~= r or region._msufStatusG ~= g or region._msufStatusB ~= b or region._msufStatusA ~= a) then
        region:SetTextColor(r, g, b, a)
        region._msufStatusR, region._msufStatusG, region._msufStatusB, region._msufStatusA = r, g, b, a
    end
end

local function ApplyLayer(region, layer)
    if not (region and region.SetDrawLayer) then
        return
    end
    local sub = ClampLayer(layer, 7) - 1
    if sub > 7 then sub = 7 end
    if region._msufStatusLayer ~= sub then
        region:SetDrawLayer("OVERLAY", sub)
        region._msufStatusLayer = sub
    end
end

local function AnchorRegion(region, frame, cfg)
    if not (region and frame and cfg) then
        return
    end
    local anchor = cfg.anchor or "TOPLEFT"
    local x = tonumber(cfg.x) or 0
    local y = tonumber(cfg.y) or 0
    local target, point, relPoint = frame, anchor, anchor
    if anchor == "NAMERIGHT" and frame.nameText then
        target, point, relPoint = frame.nameText, "LEFT", "RIGHT"
    elseif anchor == "NAMELEFT" and frame.nameText then
        target, point, relPoint = frame.nameText, "RIGHT", "LEFT"
    end
    if region._msufStatusAnchor ~= anchor or region._msufStatusTarget ~= target
        or region._msufStatusX ~= x or region._msufStatusY ~= y then
        region:ClearAllPoints()
        region:SetPoint(point, target, relPoint, x, y)
        region._msufStatusAnchor, region._msufStatusTarget = anchor, target
        region._msufStatusX, region._msufStatusY = x, y
    end
end

local function LayoutRegion(region, frame, spec, cfg, isText)
    if not (region and cfg) then
        return
    end
    if not isText then
        local size = tonumber(cfg.size) or 16
        if region._msufStatusSize ~= size then
            region:SetSize(size, size)
            region._msufStatusSize = size
        end
    else
        SetFont(region, spec, cfg.size)
        ApplyTextColor(region, spec)
        if region.SetJustifyH then
            local anchor = cfg.anchor
            local justify = (anchor == "RIGHT" or anchor == "TOPRIGHT" or anchor == "BOTTOMRIGHT" or anchor == "NAMELEFT") and "RIGHT" or ((anchor == "CENTER" or anchor == "TOP" or anchor == "BOTTOM") and "CENTER" or "LEFT")
            if region._msufStatusJustify ~= justify then
                region:SetJustifyH(justify)
                region._msufStatusJustify = justify
            end
        end
        if region.SetJustifyV and region._msufStatusJustifyV ~= "MIDDLE" then
            region:SetJustifyV("MIDDLE")
            region._msufStatusJustifyV = "MIDDLE"
        end
    end
    ApplyLayer(region, cfg.layer)
    local alpha = spec and spec.status and spec.status.alpha or 1
    if region.SetAlpha and region._msufStatusAlpha ~= alpha then
        region:SetAlpha(alpha)
        region._msufStatusAlpha = alpha
    end
    AnchorRegion(region, frame, cfg)
end

local function AdoptRegion(frame, region, layer)
    local holder = EnsureLayerFrame(frame, layer)
    if region and holder and region.GetParent and region:GetParent() ~= holder then
        if region.SetParent then
            region:SetParent(holder)
            region:ClearAllPoints()
            region._msufStatusAnchor, region._msufStatusTarget = nil, nil
            region._msufStatusX, region._msufStatusY = nil, nil
        else
            return nil
        end
    end
    return holder
end

local function EnsureTexture(frame, field, layer)
    local tex = frame[field]
    local holder = AdoptRegion(frame, tex, layer)
    if tex then
        return tex
    end
    tex = (holder or frame):CreateTexture(nil, "OVERLAY")
    tex:SetTexture(WHITE)
    tex:Hide()
    frame[field] = tex
    return tex
end

local function EnsureText(frame, field, layer)
    local fs = frame[field]
    local holder = AdoptRegion(frame, fs, layer)
    if fs then
        return fs
    end
    fs = (holder or frame):CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:Hide()
    frame[field] = fs
    return fs
end

local function SymbolPath(symbol, useMidnight)
    if type(symbol) ~= "string" or symbol == "" or symbol == "DEFAULT" then
        return nil
    end
    local cacheKey = symbol .. (useMidnight and "\001M" or "\001C")
    local cached = SYMBOL_PATH_CACHE[cacheKey]
    if cached then
        return cached
    end
    local folder = "Combat"
    local suffix = useMidnight and "_midnight_128_clean.tga" or "_classic_128_clean.tga"
    if find(symbol, "^rested_") then
        folder = "Rested"
        suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
    elseif find(symbol, "^resurrection_") then
        folder = "Ress"
        suffix = useMidnight and "_midnight_64.tga" or "_classic_64.tga"
    end
    local path = SYMBOL_BASE .. folder .. "\\" .. symbol .. suffix
    SYMBOL_PATH_CACHE[cacheKey] = path
    return path
end

local function ApplyStateIconTexture(tex, kind, cfg, status)
    local path = SymbolPath(cfg and cfg.symbol, status and status.useMidnight == true)
    if path then
        SetTexture(tex, path)
        SetTexCoord(tex, 0, 1, 0, 1)
        return
    end
    if kind == "combat" then
        if tex.SetAtlas then
            SetAtlas(tex, "UI-HUD-UnitFrame-Player-PortraitCombatIcon")
        else
            SetTexture(tex, STATE_TEXTURE)
            SetTexCoord(tex, 0.5, 1, 0, 0.5)
        end
    elseif kind == "resting" then
        if tex.SetAtlas then
            SetAtlas(tex, "UI-HUD-UnitFrame-Player-PortraitRestingIcon")
        else
            SetTexture(tex, STATE_TEXTURE)
            SetTexCoord(tex, 0, 0.5, 0, 0.5)
        end
    elseif kind == "incomingRes" then
        SetTexture(tex, READY_REZ_TEXTURE)
        SetTexCoord(tex, 0, 1, 0, 1)
    end
end

local function ApplyLeaderTexture(tex, cfg, status, assist)
    local gf = MSUF and MSUF.GF
    local kind = status and status.kind
    if gf and kind then
        local resolver = assist and gf.GetAssistTexture or gf.GetLeaderTexture
        if type(resolver) == "function" then
            local path, l, r, t, b = resolver(kind, cfg and cfg.style)
            if type(path) == "string" and path ~= "" then
                SetTexture(tex, path)
                SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
                return
            end
        end
    end
    local style = cfg and cfg.style
    if type(style) == "string" and style ~= "" and style ~= "DEFAULT" and style ~= "BLIZZARD" then
        local resolver = assist and _G.MSUF_GetAssistStatusIconTexture or _G.MSUF_GetLeaderStatusIconTexture
        if type(resolver) == "function" then
            local path, l, r, t, b = resolver(style, status and status.useMidnight == true)
            if type(path) == "string" and path ~= "" then
                SetTexture(tex, path)
                SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
                return
            end
        end
    end
    SetTexture(tex, assist and ASSIST_TEXTURE or LEADER_TEXTURE)
    SetTexCoord(tex, 0, 1, 0, 1)
end

local function ApplyRoleTexture(tex, cfg, status, role)
    local gf = MSUF and MSUF.GF
    local kind = status and status.kind
    if gf and kind and type(gf.GetRoleTexture) == "function" then
        local path, l, r, t, b = gf.GetRoleTexture(kind, role, cfg and cfg.style)
        if type(path) == "string" and path ~= "" then
            SetTexture(tex, path)
            SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
            return true
        end
    end
    local resolver = _G.MSUF_GetRoleStatusIconTexture
    if type(resolver) == "function" then
        local path, l, r, t, b = resolver(cfg and cfg.style, role, status and status.useMidnight == true)
        if type(path) == "string" and path ~= "" then
            SetTexture(tex, path)
            SetTexCoord(tex, l or 0, r or 1, t or 0, b or 1)
            return true
        end
    end
    return false
end

local function HideField(frame, field)
    SetShown(frame and frame[field], false)
end

local function ApplyConfiguredRegions(frame, spec)
    local status = spec and spec.status
    if not status then
        return
    end
    local cfg = status.raidMarker
    if cfg and cfg.enabled then
        local tex = EnsureTexture(frame, status.group and "raidIcon" or "raidTargetIcon", cfg.layer)
        frame.raidTargetIcon = tex
        frame.raidMarkerIndicator = tex
        SetTexture(tex, RAID_MARKER_TEXTURE)
        LayoutRegion(tex, frame, spec, cfg)
    else
        HideField(frame, "raidIcon")
        HideField(frame, "raidTargetIcon")
    end

    cfg = status.role
    if cfg and cfg.enabled then
        LayoutRegion(EnsureTexture(frame, "roleIcon", cfg.layer), frame, spec, cfg)
    else
        HideField(frame, "roleIcon")
    end

    cfg = status.leader
    if cfg and cfg.enabled then
        local tex = EnsureTexture(frame, status.group and "leaderIcon" or "LeaderIndicator", cfg.layer)
        frame.LeaderIndicator = tex
        frame.leaderIcon = tex
        LayoutRegion(tex, frame, spec, cfg)
    else
        HideField(frame, "leaderIcon")
        HideField(frame, "LeaderIndicator")
    end

    cfg = status.assist
    if cfg and cfg.enabled then
        LayoutRegion(EnsureTexture(frame, "assistIcon", cfg.layer), frame, spec, cfg)
    else
        HideField(frame, "assistIcon")
    end

    cfg = status.level
    if cfg and cfg.enabled then
        LayoutRegion(EnsureText(frame, "levelText", cfg.layer), frame, spec, cfg, true)
    else
        HideField(frame, "levelText")
    end

    cfg = status.raidGroup
    if cfg and cfg.enabled then
        LayoutRegion(EnsureText(frame, "raidGroupNameText", cfg.layer), frame, spec, cfg, true)
    else
        HideField(frame, "raidGroupNameText")
    end

    cfg = status.elite
    if cfg and cfg.enabled then
        LayoutRegion(EnsureTexture(frame, "eliteIcon", cfg.layer), frame, spec, cfg)
    else
        HideField(frame, "eliteIcon")
    end

    cfg = status.statusText
    if cfg and cfg.enabled then
        LayoutRegion(EnsureText(frame, "statusIndicatorText", cfg.layer), frame, spec, cfg, true)
    else
        HideField(frame, "statusIndicatorText")
    end

    cfg = status.combat
    if cfg and cfg.enabled then
        local tex = EnsureTexture(frame, "combatStateIndicatorIcon", cfg.layer)
        ApplyStateIconTexture(tex, "combat", cfg, status)
        LayoutRegion(tex, frame, spec, cfg)
    else
        HideField(frame, "combatStateIndicatorIcon")
    end

    cfg = status.resting
    if cfg and cfg.enabled then
        local tex = EnsureTexture(frame, "restingIndicatorIcon", cfg.layer)
        ApplyStateIconTexture(tex, "resting", cfg, status)
        LayoutRegion(tex, frame, spec, cfg)
    else
        HideField(frame, "restingIndicatorIcon")
    end

    cfg = status.incomingRes
    if cfg and cfg.enabled then
        local tex = EnsureTexture(frame, status.group and "resurrectIcon" or "incomingResIndicatorIcon", cfg.layer)
        frame.incomingResIndicatorIcon = tex
        frame.IncomingResIndicator = tex
        ApplyStateIconTexture(tex, "incomingRes", cfg, status)
        LayoutRegion(tex, frame, spec, cfg)
    else
        HideField(frame, "resurrectIcon")
        HideField(frame, "incomingResIndicatorIcon")
    end

    cfg = status.readyCheck
    if cfg and cfg.enabled then
        LayoutRegion(EnsureTexture(frame, "readyCheckIcon", cfg.layer), frame, spec, cfg)
    else
        HideField(frame, "readyCheckIcon")
    end

    cfg = status.summon
    if cfg and cfg.enabled then
        LayoutRegion(EnsureTexture(frame, "summonIcon", cfg.layer), frame, spec, cfg)
    else
        HideField(frame, "summonIcon")
        frame._msufGFSummonActive = false
    end

    cfg = status.phase
    if cfg and cfg.enabled then
        local tex = EnsureTexture(frame, "phaseIcon", cfg.layer)
        SetTexture(tex, PHASE_TEXTURE)
        SetTexCoord(tex, 0, 1, 0, 1)
        LayoutRegion(tex, frame, spec, cfg)
    else
        HideField(frame, "phaseIcon")
    end
end

local function UpdateRaidMarker(frame, status)
    local cfg = status and status.raidMarker
    local tex = frame.raidTargetIcon
    local unit = frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (cfg and cfg.enabled and tex and GetRaidTargetIndex and SetRaidTargetIconTexture and exists) then
        if tex then
            tex._msufRaidMarkerIndex = nil
            SetShown(tex, false)
        end
        return
    end
    local index = GetRaidTargetIndex(unit)
    if not index then
        tex._msufRaidMarkerIndex = nil
        SetShown(tex, false)
        return
    end
    -- We never store a secret value in `_msufRaidMarkerIndex`, so the cached
    -- field is always nil or a clean number. The `~= index` comparison can
    -- only taint when `index` itself is secret, so guard with IsSecret. The
    -- common cache-hit path on group frames short-circuits via `status.group`
    -- and never reaches IsSecret; non-group frames pay one C call per Update.
    if (status and status.group) or IsSecret(index) then
        tex._msufRaidMarkerIndex = nil
        SetRaidTargetIconTexture(tex, index)
    elseif tex._msufRaidMarkerIndex ~= index then
        SetRaidTargetIconTexture(tex, index)
        tex._msufRaidMarkerIndex = index
    end
    SetShown(tex, true)
end

local function UpdateLeader(frame, status)
    local cfg = status and status.leader
    local tex = frame.LeaderIndicator
    local unit = frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (cfg and cfg.enabled and tex and exists) then
        SetShown(tex, false)
        return
    end
    local isLeader = UnitIsGroupLeader and UnitIsGroupLeader(unit)
    local isAssist = UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
    local leader = (isLeader == true or isLeader == 1)
    local assist = (not leader) and (isAssist == true or isAssist == 1)
    if leader or assist then
        ApplyLeaderTexture(tex, cfg, status, assist)
        SetShown(tex, true)
    else
        SetShown(tex, false)
    end
end

local function UpdateLeaderPair(frame, status)
    local unit = frame and frame.unit
    local leaderCfg = status and status.leader
    local assistCfg = status and status.assist
    local leaderTex = frame and (frame.leaderIcon or frame.LeaderIndicator)
    local assistTex = frame and frame.assistIcon
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    local leaderRaw = exists and UnitIsGroupLeader and UnitIsGroupLeader(unit)
    local leader = leaderRaw == true or leaderRaw == 1
    local assistRaw = exists and (not leader) and UnitIsGroupAssistant and UnitIsGroupAssistant(unit)
    local assist = assistRaw == true or assistRaw == 1

    local showLeader = leaderCfg and leaderCfg.enabled and leaderTex and leader
    local showAssist = assistCfg and assistCfg.enabled and assistTex and assist
    local state = (showLeader and 1 or 0) + (showAssist and 2 or 0)
    local serial = frame and frame.MSUFSpec and frame.MSUFSpec._msufGFCompileSerial or 0
    if frame
        and frame._msufLeaderPairState == state
        and frame._msufLeaderPairSerial == serial
        and (not leaderTex or leaderTex._msufStatusShown == (showLeader and true or false))
        and (not assistTex or assistTex._msufStatusShown == (showAssist and true or false)) then
        return
    end
    if frame then
        frame._msufLeaderPairState = state
        frame._msufLeaderPairSerial = serial
    end

    if showLeader then
        ApplyLeaderTexture(leaderTex, leaderCfg, status, false)
        SetShown(leaderTex, true)
    else
        SetShown(leaderTex, false)
    end

    if showAssist then
        ApplyLeaderTexture(assistTex, assistCfg, status, true)
        SetShown(assistTex, true)
    else
        SetShown(assistTex, false)
    end
end

local function CancelReadyCheckTimer(frame)
    if frame then
        READY_CHECK_TIMERS[frame] = nil
    end
end

local function UpdatePowerRoleVisibility(frame, status)
    local spec = frame and frame.MSUFSpec
    if not (frame and (frame._msufGFKind or (spec and spec.scope == "group"))) then
        if frame then
            frame._msufGFPowRoleHidden = nil
        end
        return false
    end
    local bar = frame and (frame.power or frame.Power or frame.powerBar or frame.targetPowerBar)
    if not bar then
        return false
    end
    local unit = frame.unit
    local c = frame._c
    local gf = MSUF and MSUF.GF
    local role = status and status.roleValue
    if not role then
        if gf and type(gf.GetUnitGroupRole) == "function" then
            role = gf.GetUnitGroupRole(unit)
        else
            role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit) or "DAMAGER"
        end
    end
    if gf and type(gf.NormalizeGroupRole) == "function" then
        role = gf.NormalizeGroupRole(role)
    elseif role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" then
        role = "DAMAGER"
    end

    local hidden = false
    if gf and type(gf.GetEffectivePowerHeight) == "function" then
        hidden = gf.GetEffectivePowerHeight(frame._msufGFKind or status and status.kind or "party", unit, role) <= 0
    elseif c then
        hidden = (role == "TANK" and not c.powTank)
            or (role == "HEALER" and not c.powHealer)
            or (role == "DAMAGER" and not c.powDPS) or false
    end

    local prev = frame._msufGFPowRoleHidden
    frame._msufGFPowRoleHidden = hidden or nil
    if prev ~= nil and prev ~= hidden then
        if frame._msufGFRegEv and gf and type(gf.RegisterUnitEvents) == "function" and unit then
            gf.RegisterUnitEvents(frame, unit)
        end
        if not (InCombatLockdown and InCombatLockdown()) and gf and type(gf.MarkDirty) == "function" then
            gf.MarkDirty(frame, (gf.DIRTY_GEOMETRY or 0x01) + (gf.DIRTY_LAYOUT or 0x20))
        end
    end
    return hidden
end

local function UpdateRole(frame, status)
    local cfg = status and status.role
    local tex = frame and frame.roleIcon
    local unit = frame and frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    local role = UnitGroupRolesAssigned and unit and UnitGroupRolesAssigned(unit) or nil
    if role == "NONE" then role = nil end
    if status then status.roleValue = role end
    UpdatePowerRoleVisibility(frame, status)

    if not (cfg and cfg.enabled and tex and exists and role) then
        SetShown(tex, false)
        return
    end
    if (role == "TANK" and cfg.showTank == false)
        or (role == "HEALER" and cfg.showHealer == false)
        or (role == "DAMAGER" and cfg.showDPS == false) then
        SetShown(tex, false)
        return
    end
    if ApplyRoleTexture(tex, cfg, status, role) then
        SetShown(tex, true)
    else
        SetShown(tex, false)
    end
end

local function UpdateReadyCheck(frame, status, event)
    local cfg = status and status.readyCheck
    local tex = frame and frame.readyCheckIcon
    local unit = frame and frame.unit
    if not (cfg and cfg.enabled and tex and unit) then
        SetShown(tex, false)
        CancelReadyCheckTimer(frame)
        return
    end

    local ready = GetReadyCheckStatus and GetReadyCheckStatus(unit)
    if ready == "ready" then
        CancelReadyCheckTimer(frame)
        SetTexture(tex, READY_TEXTURE_READY)
        SetTexCoord(tex, 0, 1, 0, 1)
        SetShown(tex, true)
    elseif ready == "notready" then
        CancelReadyCheckTimer(frame)
        SetTexture(tex, READY_TEXTURE_NOT_READY)
        SetTexCoord(tex, 0, 1, 0, 1)
        SetShown(tex, true)
    elseif ready == "waiting" then
        CancelReadyCheckTimer(frame)
        SetTexture(tex, READY_TEXTURE_WAITING)
        SetTexCoord(tex, 0, 1, 0, 1)
        SetShown(tex, true)
    elseif event == "READY_CHECK_FINISHED" and tex.IsShown and tex:IsShown() and C_Timer and C_Timer.After then
        READY_CHECK_TOKEN = READY_CHECK_TOKEN + 1
        local token = READY_CHECK_TOKEN
        READY_CHECK_TIMERS[frame] = token
        C_Timer.After(6, function()
            if READY_CHECK_TIMERS[frame] ~= token then return end
            READY_CHECK_TIMERS[frame] = nil
            SetShown(frame and frame.readyCheckIcon, false)
        end)
    else
        SetShown(tex, false)
    end
end

local function UpdateSummon(frame, status)
    local cfg = status and status.summon
    local tex = frame and frame.summonIcon
    local unit = frame and frame.unit
    if not (cfg and cfg.enabled and tex and unit) then
        SetShown(tex, false)
        if frame then frame._msufGFSummonActive = false end
        return
    end
    local summonStatus
    if C_IncomingSummon and C_IncomingSummon.IncomingSummonStatus then
        summonStatus = C_IncomingSummon.IncomingSummonStatus(unit)
    end
    local texture = summonStatus and SUMMON_TEXTURES[summonStatus]
    if texture then
        SetTexture(tex, texture)
        SetTexCoord(tex, 0, 1, 0, 1)
        SetShown(tex, true)
        frame._msufGFSummonActive = true
    else
        SetShown(tex, false)
        frame._msufGFSummonActive = false
    end
end

local function UpdatePhase(frame, status)
    local cfg = status and status.phase
    local tex = frame and frame.phaseIcon
    local unit = frame and frame.unit
    if not (cfg and cfg.enabled and tex and unit) then
        SetShown(tex, false)
        return
    end
    local reason
    local isPlayer = UnitIsPlayer and UnitIsPlayer(unit)
    if (isPlayer == true or isPlayer == 1) and UnitPhaseReason then
        reason = UnitPhaseReason(unit)
    end
    if reason then
        SetTexture(tex, PHASE_TEXTURE)
        SetTexCoord(tex, 0, 1, 0, 1)
        SetShown(tex, true)
    else
        SetShown(tex, false)
    end
end

local function UpdateLevel(frame, status)
    local cfg = status and status.level
    local fs = frame.levelText
    local unit = frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (cfg and cfg.enabled and fs and UnitLevel and exists) then
        SetShown(fs, false)
        return
    end
    local level = UnitLevel(unit)
    level = tonumber(level)
    if not level then
        SetShown(fs, false)
    elseif level == -1 then
        SetText(fs, "??")
        SetShown(fs, true)
    else
        SetText(fs, tostring(level))
        SetShown(fs, true)
    end
end

local function RaidGroupText(style, subgroup)
    if style == "BRACKET" then
        return "[" .. subgroup .. "]"
    elseif style == "NONE" then
        return tostring(subgroup)
    end
    return "(" .. subgroup .. ")"
end

local function UpdateRaidGroup(frame, status)
    local cfg = status and status.raidGroup
    local fs = frame.raidGroupNameText
    local unit = frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (cfg and cfg.enabled and fs and UnitInRaid and GetRaidRosterInfo and exists) then
        SetShown(fs, false)
        return
    end
    local index = UnitInRaid(unit)
    if not index then
        SetShown(fs, false)
        return
    end
    local _, _, subgroup = GetRaidRosterInfo(index)
    if type(subgroup) == "number" and subgroup > 0 then
        SetText(fs, RaidGroupText(cfg.style, subgroup))
        SetShown(fs, true)
    else
        SetShown(fs, false)
    end
end

local function EliteAtlas(state)
    if state == "BOSS" then
        return "nameplates-icon-elite-gold"
    end
    return "nameplates-icon-elite-silver"
end

local function EliteState(unit)
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (UnitClassification and exists) then
        return nil
    end
    local class = UnitClassification(unit)
    if class == "worldboss" then
        return "BOSS"
    elseif class == "rareelite" then
        return "RAREELITE"
    elseif class == "rare" then
        return "RARE"
    elseif class == "elite" then
        return "ELITE"
    end
    if UnitLevel then
        local level = UnitLevel(unit)
        if tonumber(level) == -1 then
            return "BOSS"
        end
    end
    return nil
end

local function UpdateElite(frame, status)
    local cfg = status and status.elite
    local tex = frame.eliteIcon
    if not (cfg and cfg.enabled and tex) then
        SetShown(tex, false)
        return
    end
    local state = status.testMode and "BOSS" or EliteState(frame.unit)
    if state then
        if tex.SetAtlas then
            SetAtlas(tex, EliteAtlas(state))
        else
            SetTexture(tex, "Interface\\TargetingFrame\\UI-TargetingFrame-Skull")
            SetTexCoord(tex, 0, 1, 0, 1)
        end
        SetShown(tex, true)
    else
        SetShown(tex, false)
    end
end

local function StatusText(frame, cfg)
    if cfg and cfg.showDead and UnitIsConnected then
        local connected = UnitIsConnected(frame.unit)
        if connected == false then
            return "OFFLINE", "dead"
        end
    end
    if cfg and cfg.showGhost and UnitIsGhost then
        local ghost = UnitIsGhost(frame.unit)
        if ghost == true or ghost == 1 then
            return "GHOST", "ghost"
        end
    end
    if cfg and cfg.showDead then
        local dead = UnitIsDead and UnitIsDead(frame.unit)
        if not (dead == true or dead == 1) and UnitIsDeadOrGhost then
            dead = UnitIsDeadOrGhost(frame.unit)
        end
        if dead == true or dead == 1 then
            return "DEAD", "dead"
        end
    end
    if cfg and cfg.showAFK and UnitIsAFK then
        local afk = UnitIsAFK(frame.unit)
        if afk == true or afk == 1 then
            return "AFK", "afk"
        end
    end
    if cfg and cfg.showDND and UnitIsDND then
        local dnd = UnitIsDND(frame.unit)
        if dnd == true or dnd == 1 then
            return "DND", "afk"
        end
    end
    return nil
end

local function UpdateStatusText(frame, status, event)
    local cfg = status and status.statusText
    local fs = frame.statusIndicatorText
    local unit = frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (cfg and cfg.enabled and fs and exists) then
        if frame._msufStatusTextValue == nil
            and frame._msufStatusTextLayout == nil
            and fs and fs._msufStatusShown == false then
            return
        end
        frame._msufStatusTextValue = nil
        frame._msufStatusTextLayout = nil
        if fs then
            SetText(fs, "")
            SetShown(fs, false)
        end
        return
    end
    if status.testMode ~= true
        and event == "UNIT_HEALTH"
        and frame._msufStatusTextValue == nil
        and (cfg.showDead == true or cfg.showGhost == true) then
        local deadOrGhost = UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
        if not (deadOrGhost == true or deadOrGhost == 1) then
            return
        end
    elseif status.testMode ~= true
        and event == "UNIT_HEALTH"
        and frame._msufStatusTextValue == nil
        and cfg.showDead ~= true
        and cfg.showGhost ~= true then
        return
    end
    local text, state = status.testMode and "DEAD" or nil, status.testMode and "dead" or nil
    if not text then
        text, state = StatusText(frame, cfg)
    end
    if text then
        local layout = cfg
        if state == "ghost" and cfg.ghost then
            layout = cfg.ghost
        elseif state == "afk" and cfg.afk then
            layout = cfg.afk
        elseif cfg.dead then
            layout = cfg.dead
        end
        if layout and layout.enabled == false then
            if frame._msufStatusTextValue == nil
                and frame._msufStatusTextLayout == nil
                and fs._msufStatusShown == false then
                return
            end
            frame._msufStatusTextValue = nil
            frame._msufStatusTextLayout = nil
            SetText(fs, "")
            SetShown(fs, false)
            return
        end
        if frame._msufStatusTextValue == text
            and frame._msufStatusTextLayout == layout
            and fs._msufStatusShown == true then
            return
        end
        frame._msufStatusTextValue = text
        frame._msufStatusTextLayout = layout
        LayoutRegion(fs, frame, frame.MSUFSpec, layout, true)
        SetText(fs, text)
        SetShown(fs, true)
    else
        if frame._msufStatusTextValue == nil
            and frame._msufStatusTextLayout == nil
            and fs._msufStatusShown == false then
            return
        end
        frame._msufStatusTextValue = nil
        frame._msufStatusTextLayout = nil
        SetText(fs, "")
        SetShown(fs, false)
    end
end

local function UpdateCombat(frame, status)
    local cfg = status and status.combat
    local tex = frame.combatStateIndicatorIcon
    local unit = frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (cfg and cfg.enabled and tex and exists) then
        SetShown(tex, false)
        return
    end
    local active = status.testMode
    if not active and UnitAffectingCombat then
        local activeRaw = UnitAffectingCombat(unit)
        active = activeRaw == true or activeRaw == 1
    end
    SetShown(tex, active == true)
end

local function UpdateResting(frame, status)
    local cfg = status and status.resting
    local tex = frame.restingIndicatorIcon
    if not (cfg and cfg.enabled and tex) then
        SetShown(tex, false)
        return
    end
    local active = status.testMode
    if not active and frame.unit == "player" and IsResting then
        local activeRaw = IsResting()
        active = activeRaw == true or activeRaw == 1
    end
    SetShown(tex, active == true)
end

local function UpdateIncomingRes(frame, status)
    local cfg = status and status.incomingRes
    local tex = frame.incomingResIndicatorIcon
    local unit = frame.unit
    local exists = (not UnitExists) or UnitExists(unit)
    exists = exists == true or exists == 1
    if not (cfg and cfg.enabled and tex and exists) then
        SetShown(tex, false)
        return
    end
    if frame._msufGFSummonActive then
        SetShown(tex, false)
        return
    end
    local active = status.testMode
    if not active and UnitHasIncomingResurrection then
        local activeRaw = UnitHasIncomingResurrection(unit)
        active = activeRaw == true or activeRaw == 1
    end
    SetShown(tex, active == true)
end

function Status.IsEnabled(frame, spec)
    return spec and spec.status and spec.status.enabled == true
end

function Status.GetEvents()
    return EMPTY_EVENTS
end

function Status.GetUnitlessEvents()
    return EMPTY_EVENTS
end

function Status.Apply(frame, spec)
    if frame then
        frame._msufStatusTextValue = nil
        frame._msufStatusTextLayout = nil
    end
    ApplyConfiguredRegions(frame, spec)
end

function Status.Disable(frame)
    HideField(frame, "raidTargetIcon")
    HideField(frame, "raidIcon")
    HideField(frame, "roleIcon")
    HideField(frame, "LeaderIndicator")
    HideField(frame, "leaderIcon")
    HideField(frame, "assistIcon")
    HideField(frame, "levelText")
    HideField(frame, "raidGroupNameText")
    HideField(frame, "eliteIcon")
    HideField(frame, "statusIndicatorText")
    HideField(frame, "combatStateIndicatorIcon")
    HideField(frame, "restingIndicatorIcon")
    HideField(frame, "incomingResIndicatorIcon")
    HideField(frame, "resurrectIcon")
    HideField(frame, "readyCheckIcon")
    HideField(frame, "summonIcon")
    HideField(frame, "phaseIcon")
    frame._msufGFSummonActive = false
    frame._msufStatusTextValue = nil
    frame._msufStatusTextLayout = nil
    CancelReadyCheckTimer(frame)
end

local RAID_MARKER_EVENTS = { "RAID_TARGET_UPDATE" }
local LEADER_EVENTS = { "GROUP_ROSTER_UPDATE", "PARTY_LEADER_CHANGED" }
local LEVEL_EVENTS = { "UNIT_LEVEL" }
local LEVEL_UNITLESS_EVENTS = { "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED" }
local RAID_GROUP_EVENTS = { "GROUP_ROSTER_UPDATE" }
local ELITE_EVENTS = { "UNIT_CLASSIFICATION_CHANGED", "UNIT_LEVEL" }
local STATUS_TEXT_EVENTS = { "UNIT_HEALTH", "UNIT_CONNECTION", "UNIT_FLAGS" }
local STATUS_TEXT_UNITLESS_EVENTS = { "PLAYER_FLAGS_CHANGED" }
local COMBAT_EVENTS = { "UNIT_FLAGS" }
local COMBAT_PLAYER_EVENTS = { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }
local RESTING_PLAYER_EVENTS = { "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" }
local INCOMING_RES_EVENTS = { "INCOMING_RESURRECT_CHANGED" }

local function StatusEnabled(spec, key)
    local status = spec and spec.status
    local cfg = status and status[key]
    return status and status.enabled == true and cfg and cfg.enabled == true
end
local Runtime = {
    EMPTY_EVENTS = EMPTY_EVENTS,
    RAID_MARKER_EVENTS = RAID_MARKER_EVENTS,
    LEADER_EVENTS = LEADER_EVENTS,
    LEVEL_EVENTS = LEVEL_EVENTS,
    LEVEL_UNITLESS_EVENTS = LEVEL_UNITLESS_EVENTS,
    RAID_GROUP_EVENTS = RAID_GROUP_EVENTS,
    ELITE_EVENTS = ELITE_EVENTS,
    STATUS_TEXT_EVENTS = STATUS_TEXT_EVENTS,
    STATUS_TEXT_UNITLESS_EVENTS = STATUS_TEXT_UNITLESS_EVENTS,
    COMBAT_EVENTS = COMBAT_EVENTS,
    COMBAT_PLAYER_EVENTS = COMBAT_PLAYER_EVENTS,
    RESTING_PLAYER_EVENTS = RESTING_PLAYER_EVENTS,
    INCOMING_RES_EVENTS = INCOMING_RES_EVENTS,
    StatusEnabled = StatusEnabled,
    HideField = HideField,
    ApplyConfiguredRegions = ApplyConfiguredRegions,
    CancelReadyCheckTimer = CancelReadyCheckTimer,
    UpdateRaidMarker = UpdateRaidMarker,
    UpdateLeader = UpdateLeader,
    UpdateLeaderPair = UpdateLeaderPair,
    UpdatePowerRoleVisibility = UpdatePowerRoleVisibility,
    UpdateRole = UpdateRole,
    UpdateReadyCheck = UpdateReadyCheck,
    UpdateSummon = UpdateSummon,
    UpdatePhase = UpdatePhase,
    UpdateLevel = UpdateLevel,
    UpdateRaidGroup = UpdateRaidGroup,
    UpdateElite = UpdateElite,
    UpdateStatusText = UpdateStatusText,
    UpdateCombat = UpdateCombat,
    UpdateResting = UpdateResting,
    UpdateIncomingRes = UpdateIncomingRes,
}
MSUF.UFStatusRuntime = Runtime

local StatusStructure = {}
StatusStructure.GetEvents = Status.GetEvents
StatusStructure.GetUnitlessEvents = Status.GetUnitlessEvents
StatusStructure.Create = Status.Create
StatusStructure.Apply = Status.Apply
StatusStructure.Disable = Status.Disable
StatusStructure.IsEnabled = Status.IsEnabled

UF.RegisterElement("StatusIndicators", StatusStructure)

local function RefreshStatus(unit, reason)
    if UF.RefreshElements then
        return UF.RefreshElements(unit, STATUS_REFRESH, reason or "MSUF_STATUS")
    end
    return false
end

UF.RefreshStatusIndicators = RefreshStatus
_G.MSUF_RefreshStatusIndicators = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RequestStatusIconsRefreshForCurrent = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RequestStatusTextRefresh = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RequestStatusCombatIndicatorRefresh = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RequestStatusRestingIndicatorRefresh = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RequestStatusIncomingResIndicatorRefresh = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RefreshLeaderIconFrames = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RefreshRaidMarkerFrames = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RefreshLevelIndicatorFrames = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RefreshRaidGroupNameFrames = function() return RefreshStatus(nil, "MSUF_STATUS") end
_G.MSUF_RefreshEliteIconFrames = function() return RefreshStatus(nil, "MSUF_STATUS") end
