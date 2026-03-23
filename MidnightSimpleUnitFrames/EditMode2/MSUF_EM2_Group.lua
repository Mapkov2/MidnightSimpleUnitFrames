local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 or not EM2.Registry or not EM2.PopupFactory then return end

local Reg = EM2.Registry
local F = EM2.PopupFactory
local floor, max, min = math.floor, math.max, math.min
local pf

local function GroupDB()
    local db = _G.MSUF_DB
    return db and db.group
end

local function ScopeConf(scope)
    local g = GroupDB()
    return g and g[scope]
end

local function GetAnchorXY(conf, defaultY)
    local fn = _G.MSUF_Group_GetOffsets
    if type(fn) == "function" then
        return fn(conf, defaultY)
    end
    local anchor = conf and conf.anchor or { "TOPLEFT", nil, "TOPLEFT", 20, defaultY or -200 }
    return tonumber(anchor[4]) or 0, tonumber(anchor[5]) or 0
end

local function SetAnchorXY(conf, x, y, defaultY)
    local fn = _G.MSUF_Group_SetOffsets
    if type(fn) == "function" then
        fn(conf, x, y, defaultY)
        return
    end
    conf.anchor = conf.anchor or { "TOPLEFT", nil, "TOPLEFT", 0, 0 }
    conf.anchor[4], conf.anchor[5] = x, y
end

local function Apply()
    if not pf or not pf.scope then return end
    local conf = ScopeConf(pf.scope)
    if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then _G.MSUF_EM_UndoBeforeChange("group", pf.scope) end
    local function num(box, d, lo, hi)
        local v = tonumber(box and box.GetText and box:GetText()) or d
        if lo and v < lo then v = lo end
        if hi and v > hi then v = hi end
        return floor(v + 0.5)
    end
    local defaultY = (pf.scope == "raid") and -400 or -200
    local x = num(pf.xBox, 0)
    local y = num(pf.yBox, 0)
    SetAnchorXY(conf, x, y, defaultY)
    conf.width = num(pf.wBox, conf.width or 90, 20, 400)
    conf.height = num(pf.hBox, conf.height or 36, 8, 200)
    conf.spacing = num(pf.spacingBox, conf.spacing or 2, 0, 20)
    if pf.wrapBox then conf.wrapAfter = num(pf.wrapBox, conf.wrapAfter or 5, 1, 10) end
    if pf.growthDrop and pf._growthValue then conf.growthDirection = pf._growthValue end
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
    if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
    if type(_G.MSUF_Group_RefreshAll) == "function" then _G.MSUF_Group_RefreshAll() end
=======
=======
>>>>>>> theirs
=======
>>>>>>> theirs
    if type(_G.MSUF_Group_SyncPreview) == "function" then
        _G.MSUF_Group_SyncPreview()
    else
        if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
        if type(_G.MSUF_Group_RefreshAll) == "function" then _G.MSUF_Group_RefreshAll() end
    end
<<<<<<< ours
<<<<<<< ours
>>>>>>> theirs
=======
>>>>>>> theirs
=======
>>>>>>> theirs
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local function Sync()
    if not pf or not pf.scope then return end
    local conf = ScopeConf(pf.scope)
    if not conf then return end
    local x, y = GetAnchorXY(conf, (pf.scope == "raid") and -400 or -200)
    pf._titleFS:SetText(pf.scope == "raid" and "Raid" or "Party")
    pf.xBox:SetText(x)
    pf.yBox:SetText(y)
    pf.wBox:SetText(conf.width or 90)
    pf.hBox:SetText(conf.height or 36)
    pf.spacingBox:SetText(conf.spacing or 2)
    if pf.wrapBox then pf.wrapBox:SetText(conf.wrapAfter or 5) end
    pf._growthValue = conf.growthDirection or "DOWN"
    if pf.growthDrop then pf.growthDrop:SetValue(pf._growthValue) end
    pf.wrapRow:SetShown(pf.scope == "raid")
    pf._recalcScroll()
end

local function Build()
    if pf then return pf end
    pf = F.Panel("MSUF_EM2_GroupPopup", 380, 360, "Party")
    local top = pf._contentTop
    local GROWTH = { { "DOWN", "Down" }, { "UP", "Up" }, { "RIGHT", "Right" }, { "LEFT", "Left" } }

    local c1, b1 = F.Card(pf, top, "Position & Size", -2, true)
    local xy = F.PairRow(pf, b1, c1, { label1 = "X:", label2 = "Y:", key1 = "xBox", key2 = "yBox", onChanged = Apply })
    local wh = F.PairRow(pf, b1, c1, { label1 = "W:", label2 = "H:", key1 = "wBox", key2 = "hBox", anchorTo = xy, onChanged = Apply })
    c1:RecalcHeight()

    local c2, b2 = F.Card(pf, c1, "Layout", -6, true)
    local sp = F.PairRow(pf, b2, c2, { label1 = "Space:", label2 = "Wrap:", key1 = "spacingBox", key2 = "wrapBox", onChanged = Apply })
    pf.wrapRow = sp
    local dd = F.SizeAnchorRow(pf, b2, c2, { sizeKey = nil, anchorKey = "growthDrop", stateKey = "_growthValue", options = GROWTH, anchorTo = sp, onChanged = Apply, sizeLabel = "", anchorLabel = "Growth" })
    c2:RecalcHeight()

    local ok, cancel = F.FooterButtons(pf)
    ok:SetScript("OnClick", function() Apply(); pf:Hide() end)
    cancel:SetScript("OnClick", function() pf:Hide() end)
    pf._recalcScroll = function() pf:UpdateScrollHeight(280) end
    return pf
end

local GroupPopup = {}
EM2.GroupPopup = GroupPopup
function GroupPopup.Open(scope) if InCombatLockdown and InCombatLockdown() then return end Build(); pf.scope = scope; Sync(); pf:Show() end
function GroupPopup.Close() if pf then pf:Hide() end end
function GroupPopup.IsOpen() return pf and pf:IsShown() or false end
function GroupPopup.Sync() if pf and pf:IsShown() then Sync() end end

local PARTY_PREVIEW = {
    { name = "Thrall", class = "SHAMAN", role = "HEALER", hp = 0.86, power = 0.74 },
    { name = "Jaina", class = "MAGE", role = "DAMAGER", hp = 0.48, power = 0.92 },
    { name = "Anduin", class = "PRIEST", role = "HEALER", hp = 0.95, power = 0.53 },
    { name = "Garrosh", class = "WARRIOR", role = "TANK", hp = 0.71, power = 0.25 },
}

local RAID_PREVIEW = {
    { name = "Garrosh", class = "WARRIOR", role = "TANK", hp = 1.00, power = 0.35 },
    { name = "Tyrande", class = "DRUID", role = "TANK", hp = 0.82, power = 0.58 },
    { name = "Anduin", class = "PRIEST", role = "HEALER", hp = 0.95, power = 0.45 },
    { name = "Thrall", class = "SHAMAN", role = "HEALER", hp = 0.88, power = 0.70 },
    { name = "Velen", class = "PRIEST", role = "HEALER", hp = 0.90, power = 0.62 },
    { name = "Jaina", class = "MAGE", role = "DAMAGER", hp = 0.67, power = 0.91 },
    { name = "Valeera", class = "ROGUE", role = "DAMAGER", hp = 0.54, power = 0.84 },
    { name = "Rexxar", class = "HUNTER", role = "DAMAGER", hp = 0.79, power = 0.73 },
    { name = "Kael", class = "MAGE", role = "DAMAGER", hp = 0.42, power = 0.95 },
    { name = "Illidan", class = "DEMONHUNTER", role = "DAMAGER", hp = 0.61, power = 0.48 },
    { name = "Muradin", class = "WARRIOR", role = "DAMAGER", hp = 0.76, power = 0.31 },
    { name = "Maiev", class = "DEMONHUNTER", role = "DAMAGER", hp = 0.69, power = 0.67 },
    { name = "Malfurion", class = "DRUID", role = "HEALER", hp = 0.93, power = 0.57 },
    { name = "Uther", class = "PALADIN", role = "HEALER", hp = 0.87, power = 0.64 },
    { name = "Baine", class = "WARRIOR", role = "TANK", hp = 0.84, power = 0.28 },
    { name = "Lor'themar", class = "HUNTER", role = "DAMAGER", hp = 0.58, power = 0.79 },
    { name = "Talanji", class = "PRIEST", role = "HEALER", hp = 0.91, power = 0.60 },
    { name = "Genn", class = "ROGUE", role = "DAMAGER", hp = 0.65, power = 0.52 },
    { name = "Alleria", class = "HUNTER", role = "DAMAGER", hp = 0.72, power = 0.86 },
    { name = "Khadgar", class = "MAGE", role = "DAMAGER", hp = 0.83, power = 0.94 },
}

local function ApplyPreviewFrame(frame, data)
    if not (frame and data) then return end
    frame:Show()
    if frame.nameText then frame.nameText:SetText(data.name or "") end
    if frame.hpText then
        frame.hpText:SetText(string.format("%d%%", floor(((data.hp or 0) * 100) + 0.5)))
        frame.hpText:Show()
    end
    _G.MSUF_SetBarValue(frame.hpBar, data.hp or 1, false)
    if frame.powerBar then
        frame.powerBar:Show()
        _G.MSUF_SetBarValue(frame.powerBar, data.power or 0, false)
    end
    if frame.roleIcon then
        local atlas = (data.role == "TANK" and "roleicon-tank") or (data.role == "HEALER" and "roleicon-healer") or "roleicon-dps"
        frame.roleIcon:SetAtlas(atlas, true)
        frame.roleIcon:Show()
    end
    if frame.stateText then
        frame.stateText:SetText("")
        frame.stateText:Hide()
    end
    frame:SetAlpha(1)
end

local function ShowPreviewPool(group, scope, frames, container, data)
    if not (group and frames and container) then return end
    container:Show()
    for i = 1, #frames do
        local frame = frames[i]
        if data[i] then
            ApplyPreviewFrame(frame, data[i])
        elseif frame then
            frame:Hide()
        end
    end
    if group.roster then
        group.roster.type = scope
        group.roster.count = #data
        group.roster.units = group.roster.units or {}
        wipe(group.roster.units)
        for i = 1, #data do
            group.roster.units[i] = scope .. i
        end
    end
end

function _G.MSUF_Group_SyncPreview()
    if not _G.MSUF_GroupPreviewActive then
        if ns.Group and ns.Group.ScheduleRosterRebuild then ns.Group.ScheduleRosterRebuild() end
<<<<<<< ours
<<<<<<< ours
<<<<<<< ours
=======
        if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
>>>>>>> theirs
=======
        if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
>>>>>>> theirs
=======
        if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
>>>>>>> theirs
        if type(_G.MSUF_Group_RefreshAll) == "function" then _G.MSUF_Group_RefreshAll() end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        return
    end
    if type(_G.MSUF_EnsureGroupFrames) == "function" then _G.MSUF_EnsureGroupFrames() end
    local group = ns.Group
    if not group then return end

    local activeKey = EM2.State and EM2.State.GetUnitKey and EM2.State.GetUnitKey()
    local wantRaid = (pf and pf.scope == "raid") or (activeKey == "group_raid")
    if wantRaid then
        if group.partyContainer then group.partyContainer:Hide() end
        ShowPreviewPool(group, "raid", group.raidFrames, group.raidContainer, RAID_PREVIEW)
    else
        if group.raidContainer then group.raidContainer:Hide() end
        ShowPreviewPool(group, "party", group.partyFrames, group.partyContainer, PARTY_PREVIEW)
    end

    if type(_G.MSUF_LayoutGroupFrames) == "function" then
        _G.MSUF_LayoutGroupFrames()
        if wantRaid and group.raidContainer then
            group.raidContainer:Show()
        elseif group.partyContainer then
            group.partyContainer:Show()
        end
    end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

local function RegisterAll()
    Reg.Register({
        key = "group_party", label = "Party", order = 70, popupType = "group", canResize = true, canNudge = true,
        getFrame = function() return (ns.Group and ns.Group.partyContainer) end,
        getConf = function() local g = GroupDB(); return g and g.party end,
        isEnabled = function() local g = GroupDB(); return g and g.enabled ~= false end,
    })
    Reg.Register({
        key = "group_raid", label = "Raid", order = 80, popupType = "group", canResize = true, canNudge = true,
        getFrame = function() return (ns.Group and ns.Group.raidContainer) end,
        getConf = function() local g = GroupDB(); return g and g.raid end,
        isEnabled = function() local g = GroupDB(); return g and g.enabled ~= false end,
    })
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    C_Timer.After(0, RegisterAll)
end)
