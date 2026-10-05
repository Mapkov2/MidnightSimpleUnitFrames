--- EditMode/MSUF_EditMode_Layout_Nudge.lua - Edit Mode arrow-key nudging
--- Moves the selected frame, castbar, resource bar or preview target by
--- 1/5/10 px or one grid step through override bindings on secure buttons.
local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
local _, MSUF = ...
-- Functions other modules publish are resolved where they are called
-- (most load after Edit Mode): MSUF.Require raises naming this file when
-- one is missing, and a hook installed on the global still applies.
local CALLER = "Shell/EditMode/MSUF_EditMode_Layout_Nudge.lua"
local ExportPublic = (MSUF or _G.MSUF_NS or {}).ExportPublic

local EM2 = _G.MSUF_EM2
if not EM2 then return end

local floor = math.floor
local abs   = math.abs
local U     = EM2.Util or {}
local round = U.Round

local RefreshUFPreview       = U.RefreshUFPreview
local ApplySettingsForKeySafe = U.ApplySettingsForKeySafe
local ApplyAllSettingsSafe   = U.ApplyAllSettingsSafe
local IsConfigCombatLocked   = U.IsConfigCombatLocked
local BlockConfigCombatLocked = U.BlockConfigCombatLocked

local Nudge = {}
EM2.Nudge = Nudge

local owner

local function GetPreviewNudgeTarget()
    local target = _G.MSUF_EM2_ActivePreviewNudgeTarget
    if type(target) ~= "table" or type(target.Nudge) ~= "function" then return nil end
    if type(target.IsActive) == "function" and not target:IsActive() then return nil end
    local frame = target.frame
    if frame and frame.IsShown and not frame:IsShown() then return nil end
    return target
end

local function MSUF_EM2_SetPreviewNudgeTarget(target)
    if target == nil or type(target) == "table" then
        ExportPublic("MSUF_EM2_ActivePreviewNudgeTarget", target)
    end
end
ExportPublic("MSUF_EM2_SetPreviewNudgeTarget", MSUF_EM2_SetPreviewNudgeTarget)

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
    if unit == "arena" then return "arenaCastbarOffsetX", "arenaCastbarOffsetY" end
    local fn = _G.MSUF_GetCastbarPrefix
    if type(fn) ~= "function" then return nil, nil end
    local prefix = fn(unit)
    if not prefix or prefix == "" then return nil, nil end
    return prefix .. "OffsetX", prefix .. "OffsetY"
end
--- The drag ticker writes castbar drags to the same keys.
Nudge.GetCastbarOffsetKeys = GetCastbarOffsetKeys

local CASTBAR_NUDGE_DEFAULTS = {
    player = { 0, 5 },
    target = { 65, -15 },
    focus  = { 65, -15 },
    boss   = { 0, 0 },
    arena  = { 0, 0 },
}

local function IsFiniteNudgeNumber(value)
    return type(value) == "number"
        and value == value
        and value > -math.huge
        and value < math.huge
end

local function RoundNudgeOffset(value)
    if type(round) == "function" then return round(value) end
    return value >= 0 and floor(value + 0.5) or -floor(-value + 0.5)
end

local function NudgeCastbarDefaultOffsets(unit)
    local defaults = _G.MSUF_GetCastbarDefaultOffsets
    if type(defaults) == "function" then
        local x, y = defaults(unit)
        x, y = tonumber(x), tonumber(y)
        if IsFiniteNudgeNumber(x) and IsFiniteNudgeNumber(y) then return x, y end
        return nil, nil
    end
    local fallback = CASTBAR_NUDGE_DEFAULTS[unit]
    return fallback and fallback[1] or nil, fallback and fallback[2] or nil
end

local function ReadCastbarOffset(general, key, fallbackKey, defaultValue)
    local raw = general[key]
    if raw == nil and fallbackKey then raw = general[fallbackKey] end
    if raw == nil then raw = defaultValue end
    local value = tonumber(raw)
    if not IsFiniteNudgeNumber(value) then return nil end
    return value
end

local function CallCastbarNudgeSync(fn, ...)
    if type(fn) ~= "function" then return true end
    return true, fn(...)
end

local function SyncCastbarNudge(unit)
    local ok = CallCastbarNudgeSync(MSUF.Require("MSUF_SyncCastbarPositionPopup", CALLER), unit)
    if EM2.Movers then ok = CallCastbarNudgeSync(EM2.Movers.SyncAll) and ok end
    if EM2.Focus then ok = CallCastbarNudgeSync(EM2.Focus.NotifyPositionChanged, "castbar_" .. unit, true) and ok end
    ok = CallCastbarNudgeSync(RefreshUFPreview, "EM2_CASTBAR_NUDGE", unit) and ok
    return ok
end

local function ApplyCastbarNudge(unit)
    if type(ApplySettingsForKeySafe) ~= "function" then return false end
    local applied = ApplySettingsForKeySafe("castbar_" .. unit)
    return applied == true
end

local function RestoreCastbarNudge(general, xKey, yKey, previousX, previousY, unit)
    general[xKey], general[yKey] = previousX, previousY
    ApplyCastbarNudge(unit)
    SyncCastbarNudge(unit)
end

local function NudgeCastbar(unit, ndx, ndy)
    if not CASTBAR_NUDGE_DEFAULTS[unit] then return false end
    local isActive = EM2.State and EM2.State.IsActive
    if type(isActive) ~= "function" then return false end
    if not isActive() then return false end
    if type(BlockConfigCombatLocked) ~= "function" then return false end
    if BlockConfigCombatLocked() then return false end
    if not IsFiniteNudgeNumber(ndx) or not IsFiniteNudgeNumber(ndy) then return false end

    local db = _G.MSUF_DB
    local general = db and db.general
    if type(general) ~= "table" then return false end

    local xKey, yKey = GetCastbarOffsetKeys(unit)
    if type(xKey) ~= "string" or xKey == "" or type(yKey) ~= "string" or yKey == "" then return false end
    local defaultX, defaultY = NudgeCastbarDefaultOffsets(unit)
    if not IsFiniteNudgeNumber(defaultX) or not IsFiniteNudgeNumber(defaultY) then return false end

    local fallbackX = unit == "focus" and "castbarTargetOffsetX" or nil
    local fallbackY = unit == "focus" and "castbarTargetOffsetY" or nil
    local currentX = ReadCastbarOffset(general, xKey, fallbackX, defaultX)
    local currentY = ReadCastbarOffset(general, yKey, fallbackY, defaultY)
    if not currentX or not currentY then return false end

    local nextX = RoundNudgeOffset(currentX + ndx)
    local nextY = RoundNudgeOffset(currentY + ndy)
    if not IsFiniteNudgeNumber(nextX) or not IsFiniteNudgeNumber(nextY)
        or abs(nextX) > 4096 or abs(nextY) > 4096
    then
        return false
    end
    if nextX == currentX and nextY == currentY then return false end

    local undo = EM2.Undo
    if type(ApplySettingsForKeySafe) ~= "function" then return false end
    if not (undo and type(undo.PrepareChange) == "function" and type(undo.CommitPrepared) == "function") then return false end

    local snapshot = undo.PrepareChange("castbar", unit)
    if type(snapshot) ~= "table" then return false end

    local previousX, previousY = general[xKey], general[yKey]
    general[xKey], general[yKey] = nextX, nextY

    if not ApplyCastbarNudge(unit)
        or tonumber(general[xKey]) ~= nextX
        or tonumber(general[yKey]) ~= nextY
        or not SyncCastbarNudge(unit)
    then
        RestoreCastbarNudge(general, xKey, yKey, previousX, previousY, unit)
        return false
    end
    local committed = undo.CommitPrepared(snapshot)
    if committed ~= true then
        RestoreCastbarNudge(general, xKey, yKey, previousX, previousY, unit)
        return false
    end
    return true
end

local function NudgeResource(cfg, ndx, ndy)
    if not (cfg and cfg.canNudge == true and cfg.popupType == "resource"
        and type(cfg.getConf) == "function" and type(cfg.getFrame) == "function"
        and type(cfg.commitSubframePosition) == "function") then return false end
    if not cfg.getFrame() then return false end
    local conf = cfg.getConf()
    local xKey, yKey = cfg.subframeOffsetXKey, cfg.subframeOffsetYKey
    if type(conf) ~= "table" or type(xKey) ~= "string" or type(yKey) ~= "string" then return false end
    local currentX = tonumber(conf[xKey]) or 0
    local currentY = tonumber(conf[yKey]) or (cfg.resourceKind == "power" and -4 or 0)
    local nextX, nextY = RoundNudgeOffset(currentX + ndx), RoundNudgeOffset(currentY + ndy)
    if not IsFiniteNudgeNumber(nextX) or not IsFiniteNudgeNumber(nextY)
        or abs(nextX) > 3000 or abs(nextY) > 3000
        or (nextX == currentX and nextY == currentY) then return false end

    local undo = EM2.Undo
    if not (undo and type(undo.PrepareChange) == "function"
        and type(undo.CommitPrepared) == "function") then return false end
    local snapshot = undo.PrepareChange(cfg.historyCategory, cfg.historyKey)
    if type(snapshot) ~= "table" then return false end
    local previousX, previousY = conf[xKey], conf[yKey]
    local previousTopAnchor = conf.classPowerCooldownTopAnchor
    conf[xKey], conf[yKey] = nextX, nextY
    if cfg.resourceKind == "classpower" and nextY ~= currentY then
        conf.classPowerCooldownTopAnchor = true
    end
    if cfg.commitSubframePosition() ~= true
        or tonumber(conf[xKey]) ~= nextX or tonumber(conf[yKey]) ~= nextY
        or undo.CommitPrepared(snapshot) ~= true then
        conf[xKey], conf[yKey] = previousX, previousY
        if cfg.resourceKind == "classpower" then conf.classPowerCooldownTopAnchor = previousTopAnchor end
        cfg.commitSubframePosition()
        return false
    end
    if EM2.ResourcePopup and EM2.ResourcePopup.Sync then EM2.ResourcePopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(cfg.key, true) end
    RefreshUFPreview("EM2_RESOURCE_NUDGE", cfg.resourceUnit or "player")
    return true
end

-- Saved variables while Edit Mode may nudge (active, not combat locked).
local function NudgeDB()
    if not EM2.State or not EM2.State.IsActive() then return nil end
    if BlockConfigCombatLocked() then return nil end
    return _G.MSUF_DB
end

-- One aura group of unitKey (buff, debuff, private, custom1-4) by ndx/ndy:
-- boss and arena scopes edited together move as one, like their drag.
local function NudgeAuraGroup(db, auraGroup, unitKey, ndx, ndy)
    local auraPopupOpen = EM2.AuraPopup and EM2.AuraPopup.IsOpen()
    if unitKey then
        local a2 = db.auras3
        if a2 then
            a2.perUnit = a2.perUnit or {}
            if _G.MSUF_EM_UndoBeforeChange then
                _G.MSUF_EM_UndoBeforeChange("aura", unitKey, true)
            end
            local isBoss = type(unitKey) == "string" and unitKey:match("^boss%d+$")
            local isArena = type(unitKey) == "string" and unitKey:match("^arena%d+$")
            local applyKeys
            if isBoss and a2.shared and a2.shared.bossEditTogether ~= false then
                applyKeys = { "boss1","boss2","boss3","boss4","boss5" }
            elseif isArena and a2.shared and a2.shared.arenaEditTogether ~= false then
                applyKeys = {}
                for i = 1, tonumber(_G.MSUF_MAX_ARENA_FRAMES) or 3 do
                    applyKeys[i] = "arena" .. i
                end
            else
                applyKeys = { unitKey }
            end
            local GROUP_KEYS = {
                buff    = { "buffGroupOffsetX",   "buffGroupOffsetY"   },
                debuff  = { "debuffGroupOffsetX", "debuffGroupOffsetY" },
                private = { "privateOffsetX",     "privateOffsetY"     },
            }
            local CUSTOM_GROUP_INDEX = { custom1 = 1, custom2 = 2, custom3 = 3, custom4 = 4 }
            local pair = GROUP_KEYS[auraGroup]
            local customIndex = CUSTOM_GROUP_INDEX[auraGroup]
            if pair then
                local kx, ky = pair[1], pair[2]
                local shared = a2.shared or {}
                for _, k in ipairs(applyKeys) do
                    a2.perUnit[k] = a2.perUnit[k] or {}
                    local uc = a2.perUnit[k]
                    --- Match Aura Menu/drag ownership: a Shared-layout
                    --- scope's local table is dormant and must not revive
                    --- stale fields on the first keyboard nudge.
                    if uc.overrideLayout ~= true then uc.layout = {} end
                    uc.layout = uc.layout or {}
                    uc.overrideLayout = true
                    local lay = uc.layout
                    local cx = (lay[kx] ~= nil) and lay[kx] or (shared[kx] or 0)
                    local cy = (lay[ky] ~= nil) and lay[ky] or (shared[ky] or 0)
                    lay[kx] = floor(((tonumber(cx) or 0) + ndx) + 0.5)
                    lay[ky] = floor(((tonumber(cy) or 0) + ndy) + 0.5)
                end
            elseif customIndex then
                --- Custom containers persist position as placed.x/y on the
                --- menu-model item, and the model collapses boss1-5 into a
                --- single "boss" record - dedupe by item so a together-edit
                --- does not add the delta once per boss key.
                local model = MSUF and MSUF.MSUF_Auras3 and MSUF.MSUF_Auras3.MenuModel
                if model and type(model.CustomContainer) == "function" then
                    local seen = {}
                    for _, k in ipairs(applyKeys) do
                        local item = model.CustomContainer(k, customIndex, true)
                        if item and not seen[item] then
                            seen[item] = true
                            if type(item.placed) ~= "table" then item.placed = {} end
                            local placed = item.placed
                            placed.x = floor(((tonumber(placed.x) or 0) + ndx) + 0.5)
                            placed.y = floor(((tonumber(placed.y) or 0) + ndy) + 0.5)
                        end
                    end
                end
            end
            local a3 = MSUF and MSUF.MSUF_Auras3
            if a3 and type(a3.RequestScope) == "function" then
                for _, k in ipairs(applyKeys) do a3.RequestScope(k, "AURAS3_EDITMODE_NUDGE") end
            elseif a3 and type(a3.RefreshUnit) == "function" then
                for _, k in ipairs(applyKeys) do a3.RefreshUnit(k) end
            elseif a3 and type(a3.RefreshAll) == "function" then
                a3.RefreshAll()
            end
            if a3 and type(a3.RefreshEditPreview) == "function" then
                a3.RefreshEditPreview(unitKey)
            end
            if auraPopupOpen and EM2.AuraPopup.Sync then EM2.AuraPopup.Sync() end
            local syncFn = _G.MSUF_SyncAuras3PositionPopup
            if type(syncFn) == "function" then syncFn(unitKey) end
            -- The unit preview belongs to the load-on-demand menu.
            local refreshPreview = MSUF.Optional("MSUF_UFPreview_RequestRefresh")
            if refreshPreview then refreshPreview("AURAS3_EDITMODE_NUDGE") end
        end
    end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    return unitKey ~= nil
end

local function NudgeTarget(dx, dy, exactDelta)
    local db = NudgeDB()
    if not db then return false end
    local s = exactDelta and 1 or GetStep()
    local ndx, ndy = dx * s, dy * s

    local selectedKey = EM2.State.GetUnitKey and EM2.State.GetUnitKey() or nil
    local selectedCfg = selectedKey and EM2.Registry and EM2.Registry.Get(selectedKey) or nil
    if selectedCfg and selectedCfg.externalPublicElement == true then
        local external = EM2.ExternalElements
        return external and type(external.Nudge) == "function"
            and external.Nudge(selectedKey, ndx, ndy) == true or false
    end
    if selectedCfg and selectedCfg.popupType == "resource" then
        return NudgeResource(selectedCfg, ndx, ndy)
    end

    local previewTarget = GetPreviewNudgeTarget()
    if previewTarget then
        previewTarget:Nudge(ndx, ndy)
        if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(nil, true) end
        return true
    end

    if EM2.CastPopup and EM2.CastPopup.IsOpen() then
        local castPF = _G.MSUF_EM2_CastPopup
        local unit = (EM2.CastPopup.GetUnit and EM2.CastPopup.GetUnit()) or (castPF and castPF.unit)
        return NudgeCastbar(unit, ndx, ndy)
    end

    local auraGroup = _G.MSUF_EM2_ActiveAuraGroup
    local auraPopupOpen = EM2.AuraPopup and EM2.AuraPopup.IsOpen()
    local a2PopupOpen = false
    do local ap = _G.MSUF_EM2_AuraPopup; a2PopupOpen = ap and ap.IsShown and ap:IsShown() or false end
    if auraGroup and (auraPopupOpen or a2PopupOpen) then
        local unitKey = _G.MSUF_EM2_ActiveAuraUnit
        if not unitKey then
            local auraPF = _G.MSUF_EM2_AuraPopup
            unitKey = auraPF and auraPF.unit
        end
        return NudgeAuraGroup(db, auraGroup, unitKey, ndx, ndy)
    end

    if EM2.Focus and EM2.Focus.NudgeSelection and EM2.Focus.NudgeSelection(ndx, ndy) then
        return true
    end

    local key = EM2.State.GetUnitKey() or "player"
    if (key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority")
        and MSUF.Require("MSUF_GF_EM2_NudgePreview", CALLER)(key, ndx, ndy)
    then
        if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
        return true
    end

    local conf = db[key]
    if not conf then return false end
    if _G.MSUF_EM_UndoBeforeChange then
        _G.MSUF_EM_UndoBeforeChange("unit", key, true)
    end
    conf.offsetX = floor(((tonumber(conf.offsetX) or 0) + ndx) + 0.5)
    conf.offsetY = floor(((tonumber(conf.offsetY) or 0) + ndy) + 0.5)
    if not ApplySettingsForKeySafe(key) then
        ApplyAllSettingsSafe()
    end
    if EM2.UnitPopup and EM2.UnitPopup.IsOpen() then EM2.UnitPopup.Sync() end
    if EM2.Movers and EM2.Movers.SyncAll then EM2.Movers.SyncAll() end
    if EM2.Focus and EM2.Focus.NotifyPositionChanged then EM2.Focus.NotifyPositionChanged(key, true) end
    RefreshUFPreview("EM2_UNIT_NUDGE", key)
    return true
end

local NUDGE_DIRS = { { "UP", 0, 1 }, { "DOWN", 0, -1 }, { "LEFT", -1, 0 }, { "RIGHT", 1, 0 } }
local function NudgeButtonClick(self)
    NudgeTarget(self._msufDx or 0, self._msufDy or 0)
end

-- Exact pixel nudge of the current selection, for the gamepad's right stick
-- (Game/Forever/PadNavigation.lua). Unlike the arrow keys it ignores modifiers.
function Nudge.By(dx, dy)
    return NudgeTarget(dx, dy, true)
end

-- Exact pixel nudge of one aura group, which the gamepad moves without its
-- popup open (Game/Forever/PadEditMode.lua).
function Nudge.AuraBy(unitKey, auraGroup, dx, dy)
    local db = NudgeDB()
    if not (db and unitKey and auraGroup) then return false end
    return NudgeAuraGroup(db, auraGroup, unitKey, dx, dy)
end

function Nudge.Enable()
    if not owner then
        owner = PixelLayoutRegion(CreateFrame("Frame", "MSUF_EM2_NudgeOwner", UIParent))
        owner:Hide()
        owner.__msufPendingClear = false
        owner:SetScript("OnEvent", function(self, event)
            if event == "PLAYER_REGEN_ENABLED" and self.__msufPendingClear then
                self.__msufPendingClear = false
                if ClearOverrideBindings then ClearOverrideBindings(self) end
                self:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end)

        for i = 1, #NUDGE_DIRS do
            local dir = NUDGE_DIRS[i]
            local btnName = "MSUF_EM2_Nudge" .. dir[1]
            local btn = PixelLayoutRegion(CreateFrame("Button", btnName, UIParent, "SecureActionButtonTemplate"))
            btn._msufDx, btn._msufDy = dir[2], dir[3]
            btn:SetSize(1, 1)
            btn:Hide()
            btn:SetScript("OnClick", NudgeButtonClick)
        end
    end

    if IsConfigCombatLocked() then
        owner.__msufPendingClear = true
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if ClearOverrideBindings then ClearOverrideBindings(owner) end
    for i = 1, #NUDGE_DIRS do
        local dir = NUDGE_DIRS[i][1]
        SetOverrideBindingClick(owner, false, dir, "MSUF_EM2_Nudge" .. dir)
    end
end

function Nudge.Disable()
    MSUF_EM2_SetPreviewNudgeTarget(nil)
    if not owner then return end
    -- Edit Mode exits at PLAYER_REGEN_DISABLED, where the configuration lock
    -- already refuses but the binding write is still allowed: only a real
    -- lockdown defers it, or the arrows stay bound for the whole fight.
    if InCombatLockdown() then
        owner.__msufPendingClear = true
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    ClearOverrideBindings(owner)
end

local function MSUF_EnableArrowKeyNudge(enable)
    if enable then Nudge.Enable() else Nudge.Disable() end
end
ExportPublic("MSUF_EnableArrowKeyNudge", MSUF_EnableArrowKeyNudge)
