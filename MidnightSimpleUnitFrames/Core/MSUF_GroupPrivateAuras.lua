local addonName, ns = ...
ns = ns or {}

<<<<<<< ours
<<<<<<< HEAD
local type = type
local wipe = wipe
local tonumber = tonumber
local InCombatLockdown = InCombatLockdown

=======
>>>>>>> a9840c2c35bdbd4dac6e74093eb8213332edd006
=======
>>>>>>> theirs
local function Shared()
    local db = _G.MSUF_DB and _G.MSUF_DB.group and _G.MSUF_DB.group.shared
    return db or {}
end

<<<<<<< ours
<<<<<<< HEAD
local function PrivateAurasSupported()
    return C_UnitAuras
        and type(C_UnitAuras.AddPrivateAuraAnchor) == "function"
        and type(C_UnitAuras.RemovePrivateAuraAnchor) == "function"
end

local function ClearAnchors(frame)
    if not frame then return end
    local anchors = frame._privateAnchors
    if type(anchors) ~= "table" then return end
    if PrivateAurasSupported() then
        for i = 1, #anchors do
            local anchorID = anchors[i]
            if anchorID then
                C_UnitAuras.RemovePrivateAuraAnchor(anchorID)
            end
        end
    end
    wipe(anchors)
end

function _G.MSUF_Group_OnAssignedUnit(frame, unit)
    if not frame then return end

    local container = frame.privateAuraContainer
    if not container then return end

    ClearAnchors(frame)

    if not unit or not PrivateAurasSupported() then
        container:Hide()
        return
    end

    -- Safety net: Blizzard private aura anchor APIs are not safe to rebuild in combat.
    if InCombatLockdown and InCombatLockdown() then
        return
    end

    local sh = Shared()
    local maxSlots = tonumber(sh.maxPrivateAuras) or 3
    if maxSlots <= 0 then
        container:Hide()
        return
    end

    local anchors = frame._privateAnchors
    if type(anchors) ~= "table" then
        anchors = {}
        frame._privateAnchors = anchors
    end

=======
local function ClearAnchors(frame)
    if not frame or not frame._privateAnchors or not C_UnitAuras or not C_UnitAuras.RemovePrivateAuraAnchor then return end
    for i = 1, #frame._privateAnchors do
        C_UnitAuras.RemovePrivateAuraAnchor(frame._privateAnchors[i])
    end
    wipe(frame._privateAnchors)
end

function _G.MSUF_Group_OnAssignedUnit(frame, unit)
    if not C_UnitAuras or not C_UnitAuras.AddPrivateAuraAnchor then return end
    if not frame then return end
    ClearAnchors(frame)
    if not unit or not frame.privateAuraContainer then return end

    local sh = Shared()
    local maxSlots = sh.maxPrivateAuras or 3
    if maxSlots <= 0 then
        frame.privateAuraContainer:Hide()
        return
    end
    frame._privateAnchors = frame._privateAnchors or {}
    local container = frame.privateAuraContainer
>>>>>>> theirs
    local slots = container._slots
    if type(slots) ~= "table" then
        slots = {}
        container._slots = slots
    end
<<<<<<< ours

=======
>>>>>>> theirs
    container:SetSize(maxSlots * 20, 18)
    container:Show()

    for i = 1, maxSlots do
        local slot = slots[i]
<<<<<<< ours
        if not slot then
            slot = CreateFrame("Frame", nil, container)
            slot:SetSize(18, 18)
            slot:SetPoint("LEFT", container, "LEFT", (i - 1) * 20, 0)
            slots[i] = slot
        end
        slot:Show()

        anchors[i] = C_UnitAuras.AddPrivateAuraAnchor({
=======
local function ClearAnchors(frame)
    if not frame or not frame._privateAnchors or not C_UnitAuras or not C_UnitAuras.RemovePrivateAuraAnchor then return end
    for i = 1, #frame._privateAnchors do
        C_UnitAuras.RemovePrivateAuraAnchor(frame._privateAnchors[i])
    end
    wipe(frame._privateAnchors)
end

function _G.MSUF_Group_OnAssignedUnit(frame, unit)
    if not C_UnitAuras or not C_UnitAuras.AddPrivateAuraAnchor then return end
    if not frame then return end
    ClearAnchors(frame)
    if not unit or not frame.privateAuraContainer then return end

    local sh = Shared()
    local maxSlots = sh.maxPrivateAuras or 3
    if maxSlots <= 0 then
        frame.privateAuraContainer:Hide()
        return
    end
    frame._privateAnchors = frame._privateAnchors or {}
    frame.privateAuraContainer:SetSize(maxSlots * 20, 18)
    frame.privateAuraContainer:Show()

    for i = 1, maxSlots do
        local slot = frame.privateAuraContainer._slots and frame.privateAuraContainer._slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, frame.privateAuraContainer)
            slot:SetSize(18, 18)
            slot:SetPoint("LEFT", frame.privateAuraContainer, "LEFT", (i - 1) * 20, 0)
            frame.privateAuraContainer._slots = frame.privateAuraContainer._slots or {}
            frame.privateAuraContainer._slots[i] = slot
        end
        frame._privateAnchors[i] = C_UnitAuras.AddPrivateAuraAnchor({
>>>>>>> a9840c2c35bdbd4dac6e74093eb8213332edd006
=======
        if not (slot and slot.SetPoint and slot.SetSize) then
            slot = CreateFrame("Frame", nil, container)
            slot:SetSize(18, 18)
            slots[i] = slot
        end
        slot:ClearAllPoints()
        slot:SetPoint("LEFT", container, "LEFT", (i - 1) * 20, 0)
        if slot.Show then slot:Show() end
        frame._privateAnchors[i] = C_UnitAuras.AddPrivateAuraAnchor({
>>>>>>> theirs
            unitToken = unit,
            auraIndex = i,
            parent = slot,
            showCountdownFrame = true,
            showCountdownNumbers = false,
            iconInfo = { iconWidth = 18, iconHeight = 18 },
        })
    end
<<<<<<< ours
<<<<<<< HEAD

    for i = maxSlots + 1, #slots do
        if slots[i] then
            slots[i]:Hide()
        end
    end
=======
>>>>>>> a9840c2c35bdbd4dac6e74093eb8213332edd006
=======

    for i = maxSlots + 1, #slots do
        local slot = slots[i]
        if slot and slot.Hide then
            slot:Hide()
        end
    end
>>>>>>> theirs
end
