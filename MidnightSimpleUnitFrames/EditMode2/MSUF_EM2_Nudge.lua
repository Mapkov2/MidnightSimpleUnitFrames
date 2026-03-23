-- ============================================================================
-- MSUF_EM2_Nudge.lua
-- Arrow key nudge system. Override bindings for UP/DOWN/LEFT/RIGHT.
-- Shift=5px, Ctrl=10px, Alt=grid step. Targets open popup or current unit.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Nudge = {}
EM2.Nudge = Nudge

local floor = math.floor
local owner

local function GetStep()
    local step = 1
    if IsAltKeyDown and IsAltKeyDown() then
        step = (EM2.Grid and EM2.Grid.GetGridStep()) or 20
    elseif IsControlKeyDown and IsControlKeyDown() then
        step = 10
    elseif IsShiftKeyDown and IsShiftKeyDown() then
        step = 5
    end
    return step
end

local function GetCastbarOffsetKeys(unit)
    if not unit then return nil, nil end
    if unit == "boss" then return "bossCastbarOffsetX", "bossCastbarOffsetY" end
    local fn = _G.MSUF_GetCastbarPrefix
    if type(fn) ~= "function" then return nil, nil end
    local prefix = fn(unit)
    if not prefix or prefix == "" then return nil, nil end
    return prefix .. "OffsetX", prefix .. "OffsetY"
end

local function NudgeGroup(scope, ndx, ndy)
    local db = _G.MSUF_DB
    local g = db and db.group
    local conf = g and g[scope]
    if not conf then return false end
    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
        _G.MSUF_EM_UndoBeforeChange("group", scope, true)
    end
    local getFn = _G.MSUF_Group_GetOffsets
    local setFn = _G.MSUF_Group_SetOffsets
    local defaultY = (scope == "raid") and -400 or -200
    local x, y
    if type(getFn) == "function" then
        x, y = getFn(conf, defaultY)
    else
        local anchor = conf.anchor or { "TOPLEFT", nil, "TOPLEFT", 20, defaultY }
        x = tonumber(conf.offsetX) or tonumber(anchor[4]) or 0
        y = tonumber(conf.offsetY) or tonumber(anchor[5]) or 0
    end
    x = floor((x + ndx) + 0.5)
    y = floor((y + ndy) + 0.5)
    if type(setFn) == "function" then setFn(conf, x, y, defaultY)
    else
        conf.offsetX, conf.offsetY = x, y
        conf.anchor = conf.anchor or { "TOPLEFT", nil, "TOPLEFT", x, y }
        conf.anchor[4], conf.anchor[5] = x, y
    end
    if type(_G.MSUF_LayoutGroupFrames) == "function" then _G.MSUF_LayoutGroupFrames() end
    if type(_G.MSUF_Group_RefreshAll) == "function" then _G.MSUF_Group_RefreshAll() end
    if EM2.GroupPopup and EM2.GroupPopup.IsOpen() then EM2.GroupPopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    return true
end

local function NudgeTarget(dx, dy)
    if not EM2.State or not EM2.State.IsActive() then return end
    if InCombatLockdown and InCombatLockdown() then return end
    local db = _G.MSUF_DB
    if not db then return end
    local s = GetStep()
    local ndx, ndy = dx * s, dy * s

    -- Priority 1: open castbar popup
    if EM2.CastPopup and EM2.CastPopup.IsOpen() then
        db.general = db.general or {}
        local g = db.general
        local castPF = _G.MSUF_EM2_CastPopup
        local unit = castPF and castPF.unit
        if unit then
            local xKey, yKey = GetCastbarOffsetKeys(unit)
            if xKey and yKey then
                if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
                    _G.MSUF_EM_UndoBeforeChange("castbar", unit, true)
                end
                g[xKey] = floor(((tonumber(g[xKey]) or 0) + ndx) + 0.5)
                g[yKey] = floor(((tonumber(g[yKey]) or 0) + ndy) + 0.5)
                if type(_G.MSUF_UpdateCastbarVisuals) == "function" then _G.MSUF_UpdateCastbarVisuals() end
                EM2.CastPopup.Sync()
            end
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        return
    end

    -- Priority 2: aura sub-group (individual buff/debuff/private)
    local auraGroup = _G.MSUF_EM2_ActiveAuraGroup
    local auraPopupOpen = EM2.AuraPopup and EM2.AuraPopup.IsOpen()
    local a2PopupOpen = false
    do local ap = _G.MSUF_Auras2PositionPopup; a2PopupOpen = ap and ap.IsShown and ap:IsShown() or false end
    if auraGroup and (auraPopupOpen or a2PopupOpen) then
        local unitKey = _G.MSUF_EM2_ActiveAuraUnit
        if not unitKey then
            local auraPF = _G.MSUF_EM2_AuraPopup
            unitKey = auraPF and auraPF.unit
        end
        if unitKey then
            local a2 = db.auras2
            if a2 then
                a2.perUnit = a2.perUnit or {}
                if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
                    _G.MSUF_EM_UndoBeforeChange("aura", unitKey, true)
                end
                local isBoss = type(unitKey) == "string" and unitKey:match("^boss%d+$")
                local applyKeys
                if isBoss and a2.shared and a2.shared.bossEditTogether ~= false then
                    applyKeys = { "boss1","boss2","boss3","boss4","boss5" }
                else
                    applyKeys = { unitKey }
                end
                local GROUP_KEYS = {
                    buff    = { "buffGroupOffsetX",   "buffGroupOffsetY"   },
                    debuff  = { "debuffGroupOffsetX", "debuffGroupOffsetY" },
                    private = { "privateOffsetX",     "privateOffsetY"     },
                }
                local pair = GROUP_KEYS[auraGroup]
                if pair then
                    local kx, ky = pair[1], pair[2]
                    local shared = a2.shared or {}
                    for _, k in ipairs(applyKeys) do
                        a2.perUnit[k] = a2.perUnit[k] or {}
                        local uc = a2.perUnit[k]
                        uc.layout = uc.layout or {}
                        uc.overrideLayout = true
                        local lay = uc.layout
                        local cx = (lay[kx] ~= nil) and lay[kx] or (shared[kx] or 0)
                        local cy = (lay[ky] ~= nil) and lay[ky] or (shared[ky] or 0)
                        lay[kx] = floor(((tonumber(cx) or 0) + ndx) + 0.5)
                        lay[ky] = floor(((tonumber(cy) or 0) + ndy) + 0.5)
                    end
                end
                if type(_G.MSUF_Auras2_RefreshUnit) == "function" then
                    for _, k in ipairs(applyKeys) do _G.MSUF_Auras2_RefreshUnit(k) end
                elseif type(_G.MSUF_Auras2_RefreshAll) == "function" then
                    _G.MSUF_Auras2_RefreshAll()
                end
                if auraPopupOpen and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
                local syncFn = _G.MSUF_SyncAuras2PositionPopup
                if type(syncFn) == "function" then syncFn(unitKey) end
            end
        end
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        return
    end

    -- Priority 3: group popup / group mover selection
    if EM2.GroupPopup and EM2.GroupPopup.IsOpen() then
        local groupPF = _G.MSUF_EM2_GroupPopup
        local scope = groupPF and groupPF.scope
        if scope and NudgeGroup(scope, ndx, ndy) then return end
    end

    local key = EM2.State.GetUnitKey() or "player"
    if key == "group_party" or key == "group_raid" then
        if NudgeGroup(key == "group_raid" and "raid" or "party", ndx, ndy) then return end
    end

    -- Priority 4: current unit frame
    local conf = db[key]
    if not conf then return end
    if type(_G.MSUF_EM_UndoBeforeChange) == "function" then
        _G.MSUF_EM_UndoBeforeChange("unit", key, true)
    end
    conf.offsetX = floor(((tonumber(conf.offsetX) or 0) + ndx) + 0.5)
    conf.offsetY = floor(((tonumber(conf.offsetY) or 0) + ndy) + 0.5)
    if type(ApplySettingsForKey) == "function" then
        ApplySettingsForKey(key)
    elseif type(ApplyAllSettings) == "function" then
        ApplyAllSettings()
    end
    if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
end

function Nudge.Enable()
    if not owner then
        owner = CreateFrame("Frame", "MSUF_EM2_NudgeOwner", UIParent)
        owner:Hide()
        owner.__msufPendingClear = false
        owner:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_ENABLED" and self.__msufPendingClear then
                self.__msufPendingClear = false
                if ClearOverrideBindings then ClearOverrideBindings(self) end
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end)

        for _, dir in ipairs({"UP","DOWN","LEFT","RIGHT"}) do
            local btnName = "MSUF_EM2_Nudge" .. dir
            local btn = CreateFrame("Button", btnName, UIParent, "SecureActionButtonTemplate")
            btn:SetSize(1, 1)
            btn:Hide()
            btn:SetScript("OnClick", function()
                if dir == "UP"    then NudgeTarget(0, 1)
                elseif dir == "DOWN"  then NudgeTarget(0, -1)
                elseif dir == "LEFT"  then NudgeTarget(-1, 0)
                elseif dir == "RIGHT" then NudgeTarget(1, 0) end
            end)
        end
    end

    if InCombatLockdown and InCombatLockdown() then
        owner.__msufPendingClear = false
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    for _, dir in ipairs({"UP","DOWN","LEFT","RIGHT"}) do
        SetOverrideBindingClick(owner, false, dir, "MSUF_EM2_Nudge" .. dir)
    end
end

function Nudge.Disable()
    if not owner then return end
    if InCombatLockdown and InCombatLockdown() then
        owner.__msufPendingClear = true
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ClearOverrideBindings(owner)
end

-- Legacy global
function _G.MSUF_EnableArrowKeyNudge(enable)
    if enable then Nudge.Enable() else Nudge.Disable() end
end
