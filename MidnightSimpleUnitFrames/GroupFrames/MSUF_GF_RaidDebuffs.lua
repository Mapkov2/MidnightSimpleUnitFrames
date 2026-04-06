-- MSUF_GF_RaidDebuffs.lua — Group Frames: Priority Raid Debuff Display
-- Shows a single large debuff icon for the highest-priority harmful aura.
-- Priority: dispellable > raid-flagged > duration-based > fallback.
-- Midnight 12.0 secret-safe, zero combat overhead when disabled.
local _, ns = ...
ns = ns or (_G and _G.MSUF_NS) or {}
if _G then _G.MSUF_NS = ns end

local GF = ns.GF
if not GF then return end

local issecretvalue   = _G.issecretvalue
local C_UnitAuras     = _G.C_UnitAuras
local UnitExists      = _G.UnitExists
local CreateFrame     = _G.CreateFrame
local GetTime         = _G.GetTime
local math_floor      = math.floor
local math_max        = math.max

local GameTooltip     = _G.GameTooltip

------------------------------------------------------------------------
-- Priority scoring (higher = more important)
-- Returns a plain number — never touches secret fields unsafely
------------------------------------------------------------------------
local function ScoreAura(aura)
    if not aura then return 0 end
    local score = 1

    -- Dispellable debuffs are high priority
    local dn = aura.dispelName
    if dn and not (issecretvalue and issecretvalue(dn)) then
        if dn == "Magic" or dn == "Curse" or dn == "Poison" or dn == "Disease" then
            score = score + 100
        end
    end

    -- Raid-flagged debuffs (isRaid) are very high priority
    local ir = aura.isRaid
    if ir and not (issecretvalue and issecretvalue(ir)) and ir then
        score = score + 200
    end

    -- Boss debuffs (from boss units) get bonus
    local src = aura.sourceUnit
    if src and not (issecretvalue and issecretvalue(src)) then
        if src == "boss1" or src == "boss2" or src == "boss3" or src == "boss4" or src == "boss5" then
            score = score + 150
        end
    end

    -- Short duration = more urgent
    local dur = aura.duration
    if dur and not (issecretvalue and issecretvalue(dur)) then
        if dur > 0 and dur <= 10 then
            score = score + 50
        elseif dur > 0 and dur <= 30 then
            score = score + 20
        end
    end

    return score
end

------------------------------------------------------------------------
-- Ensure raid debuff icon frame (lazy-created on each GF unit frame)
------------------------------------------------------------------------
local function EnsureRDFrame(f, conf)
    if f._msufRaidDebuff then return f._msufRaidDebuff end

    local rdConf = conf.raidDebuffs
    if not rdConf then return nil end

    local parent = f._msufBarGroup or f
    local rd = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    local sz = rdConf.size or 28
    rd:SetSize(sz, sz)
    rd:SetFrameLevel(parent:GetFrameLevel() + (rdConf.layer or 12))
    rd:EnableMouse(false)

    -- Backdrop
    rd:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    rd:SetBackdropColor(0, 0, 0, 0)
    rd:SetBackdropBorderColor(0, 0, 0, 1)

    -- Icon texture
    local tex = rd:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", rd, "TOPLEFT", 1, -1)
    tex:SetPoint("BOTTOMRIGHT", rd, "BOTTOMRIGHT", -1, 1)
    rd._icon = tex

    -- Cooldown
    local cd = CreateFrame("Cooldown", nil, rd, "CooldownFrameTemplate")
    cd:SetAllPoints(rd._icon)
    cd:SetDrawEdge(true)
    cd:SetDrawSwipe(true)
    cd:SetReverse(true)
    cd:SetHideCountdownNumbers(true)
    rd._cooldown = cd

    -- Overlay for count/timer text
    local overlay = CreateFrame("Frame", nil, rd)
    overlay:SetAllPoints(rd)
    overlay:SetFrameLevel(cd:GetFrameLevel() + 5)

    -- Stack count
    local count = overlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("BOTTOMRIGHT", rd, "BOTTOMRIGHT", -1, 1)
    count:SetDrawLayer("OVERLAY", 2)
    count:SetJustifyH("RIGHT")
    count:SetTextColor(1, 0.9, 0, 1)
    rd._count = count

    -- Timer text
    local timer = overlay:CreateFontString(nil, "OVERLAY")
    timer:SetFont("Fonts\\FRIZQT__.TTF", rdConf.timerSize or 10, "OUTLINE")
    timer:SetPoint("CENTER", rd, "CENTER", 0, 0)
    timer:SetTextColor(1, 0.9, 0, 1)
    rd._timer = timer

    -- Tooltip
    if rd.SetMouseMotionEnabled then
        rd:SetMouseMotionEnabled(true)
        rd:SetMouseClickEnabled(false)
    else
        rd:EnableMouse(true)
    end
    rd:SetScript("OnEnter", function(self)
        local unit = self._rdUnit
        local aid  = self._rdAuraID
        if not unit or not aid then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT")
        if GameTooltip.SetUnitAuraByAuraInstanceID then
            GameTooltip:SetUnitAuraByAuraInstanceID(unit, aid, "HARMFUL")
        end
        GameTooltip:Show()
    end)
    rd:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    rd:Hide()
    f._msufRaidDebuff = rd
    return rd
end

------------------------------------------------------------------------
-- Timer OnUpdate (lightweight: only runs when RD icon is shown)
------------------------------------------------------------------------
local function RDTimerUpdate(self, elapsed)
    local exp = self._rdExpires
    if not exp or exp == 0 then
        if self._timer then self._timer:SetText("") end
        return
    end
    local rem = exp - GetTime()
    if rem <= 0 then
        if self._timer then self._timer:SetText("") end
        return
    end
    if rem >= 60 then
        self._timer:SetText(math_floor(rem / 60) .. "m")
    elseif rem >= 10 then
        self._timer:SetText(math_floor(rem))
    else
        self._timer:SetText(("%.1f"):format(rem))
    end
end

------------------------------------------------------------------------
-- Main scan: find highest-priority HARMFUL aura and display it
-- Called from UNIT_AURA dispatch in GF_Effects
------------------------------------------------------------------------
function GF.UpdateRaidDebuff(f, unit)
    local kind = f._msufGFKind or "party"
    local conf = GF.GetConf(kind)
    local rdConf = conf.raidDebuffs
    if not rdConf or rdConf.enabled ~= true then
        if f._msufRaidDebuff and f._msufRaidDebuff:IsShown() then
            f._msufRaidDebuff:Hide()
        end
        return
    end

    if not unit or not UnitExists(unit) then
        if f._msufRaidDebuff then f._msufRaidDebuff:Hide() end
        return
    end

    -- Scan HARMFUL auras for highest-priority debuff
    local bestScore = 0
    local bestAura  = nil
    local bestAID   = nil
    local filter = rdConf.onlyDispellable and "HARMFUL|RAID" or "HARMFUL"

    local slots = { C_UnitAuras.GetAuraSlots(unit, filter) }
    for i = 2, #slots do
        local slot = slots[i]
        local aura = C_UnitAuras.GetAuraDataBySlot(unit, slot)
        if aura then
            local aid = aura.auraInstanceID
            local score = ScoreAura(aura)
            if score > bestScore then
                bestScore = score
                bestAura  = aura
                bestAID   = aid
            end
        end
    end

    local rd = EnsureRDFrame(f, conf)
    if not rd then return end

    if not bestAura or bestScore <= 0 then
        rd:Hide()
        rd:SetScript("OnUpdate", nil)
        return
    end

    -- Apply icon (secret-safe: icon field may be secret for other players' auras)
    local icon = bestAura.icon
    if icon and not (issecretvalue and issecretvalue(icon)) then
        rd._icon:SetTexture(icon)
    else
        rd._icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    -- Size + position from config
    local sz = rdConf.size or 28
    rd:SetSize(sz, sz)
    rd:ClearAllPoints()
    local anchor = rdConf.anchor or "CENTER"
    local parent = f._msufBarGroup or f
    rd:SetPoint(anchor, parent, anchor, rdConf.x or 0, rdConf.y or 0)
    rd:SetFrameLevel(parent:GetFrameLevel() + (rdConf.layer or 12))

    -- Store for tooltip
    rd._rdUnit   = unit
    rd._rdAuraID = bestAID

    -- Cooldown swipe (secret-safe: duration object)
    local dur = bestAura.duration
    local exp = bestAura.expirationTime
    if dur and exp and not (issecretvalue and issecretvalue(dur))
       and not (issecretvalue and issecretvalue(exp)) and dur > 0 then
        rd._cooldown:SetCooldown(exp - dur, dur)
        rd._rdExpires = exp
    else
        rd._cooldown:Clear()
        rd._rdExpires = nil
    end

    -- Stack count
    local apps = bestAura.applications
    if apps and not (issecretvalue and issecretvalue(apps)) and apps > 1 then
        rd._count:SetText(apps)
        rd._count:Show()
    else
        rd._count:SetText("")
        rd._count:Hide()
    end

    -- Timer text
    if rdConf.showTimer ~= false then
        rd._timer:SetFont("Fonts\\FRIZQT__.TTF", rdConf.timerSize or 10, "OUTLINE")
        rd:SetScript("OnUpdate", RDTimerUpdate)
    else
        rd._timer:SetText("")
        rd:SetScript("OnUpdate", nil)
    end

    -- Dispel-type border color
    local dn = bestAura.dispelName
    if dn and not (issecretvalue and issecretvalue(dn)) then
        local dc = C_UnitAuras.GetAuraDispelTypeColor and C_UnitAuras.GetAuraDispelTypeColor(dn)
        if dc then
            rd:SetBackdropBorderColor(dc.r or 0.8, dc.g or 0, dc.b or 0, 1)
        else
            rd:SetBackdropBorderColor(0.8, 0, 0, 1)
        end
    else
        rd:SetBackdropBorderColor(0.8, 0, 0, 1)
    end

    rd:Show()
end
