local addonName, ns = ...
ns = ns or {}

local function Shared()
    local db = _G.MSUF_DB and _G.MSUF_DB.group and _G.MSUF_DB.group.shared
    return db or {}
end

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
            unitToken = unit,
            auraIndex = i,
            parent = slot,
            showCountdownFrame = true,
            showCountdownNumbers = false,
            iconInfo = { iconWidth = 18, iconHeight = 18 },
        })
    end
end
