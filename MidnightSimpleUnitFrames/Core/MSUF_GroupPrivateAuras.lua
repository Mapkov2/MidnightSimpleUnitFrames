local addonName, ns = ...
ns = ns or {}

local type = type
local wipe = wipe
local tonumber = tonumber
local InCombatLockdown = InCombatLockdown

local function Shared()
    local db = _G.MSUF_DB and _G.MSUF_DB.group and _G.MSUF_DB.group.shared
    return db or {}
end

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

    local slots = container._slots
    if type(slots) ~= "table" then
        slots = {}
        container._slots = slots
    end

    container:SetSize(maxSlots * 20, 18)
    container:Show()

    for i = 1, maxSlots do
        local slot = slots[i]
        if not slot then
            slot = CreateFrame("Frame", nil, container)
            slot:SetSize(18, 18)
            slot:SetPoint("LEFT", container, "LEFT", (i - 1) * 20, 0)
            slots[i] = slot
        end
        slot:Show()

        anchors[i] = C_UnitAuras.AddPrivateAuraAnchor({
            unitToken = unit,
            auraIndex = i,
            parent = slot,
            showCountdownFrame = true,
            showCountdownNumbers = false,
            iconInfo = { iconWidth = 18, iconHeight = 18 },
        })
    end

    for i = maxSlots + 1, #slots do
        if slots[i] then
            slots[i]:Hide()
        end
    end
end
