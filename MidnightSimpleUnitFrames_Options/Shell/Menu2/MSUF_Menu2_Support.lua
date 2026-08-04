--- MSUF2 support features split out of the legacy standalone slash menu.
--- Keep this file free of page/UI construction so the old SlashMenu file can be
--- removed from the TOC without losing shared runtime helpers.

local addonName, MSUF = ...
MSUF = MSUF or {}
addonName = (type(MSUF.AddonName) == "string" and MSUF.AddonName ~= "" and MSUF.AddonName)
    or "MidnightSimpleUnitFrames"
local function EnsureMenu2Namespace()
    local namespace = MSUF.MSUF2 or _G.MSUF2 or {}
    MSUF.MSUF2 = namespace
    if _G.MSUF2 ~= namespace then _G.MSUF2 = namespace end
    return namespace
end
MSUF.GetMenu2Namespace = MSUF.GetMenu2Namespace or EnsureMenu2Namespace
local M = MSUF.GetMenu2Namespace()
MSUF.MSUF2 = M
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local unpack = table.unpack or unpack
local floor = math.floor
local abs = math.abs
local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
local function Print(msg)
    if type(print) == "function" then print("|cff00ff00MSUF:|r " .. tostring(msg or "")) end
end
local function ForEachCoreFrame(fn)
    local uf = MSUF and MSUF.UF
    if uf and type(uf.ForEachFrame) == "function" then
        uf.ForEachFrame(function(frame)
            if frame then fn(frame, frame.MSUFUnitKey or frame.unit) end
        end)
        return true
    end
    local frames = uf and uf.frames
    if type(frames) ~= "table" then return false end
    for unitKey, frame in pairs(frames) do fn(frame, unitKey) end
    return true
end
local function Tr(text)
    if type(M.Tr) == "function" then
        local translated = M.Tr(text)
        if translated ~= nil then return translated end
    end
    if type(MSUF.Translate) == "function" then return MSUF.Translate(text) end
    if type(MSUF.TR) == "function" then
        local translated = MSUF.TR(text)
        if translated ~= nil then return translated end
    end
    local locale = MSUF.L or _G.MSUF_L
    if type(locale) == "table" and locale[text] ~= nil then return locale[text] end
    return text
end
M.TranslateText = M.TranslateText or Tr
local function IsConfigCombatLocked()
    if type(_G.MSUF_IsConfigCombatLocked) == "function" then return _G.MSUF_IsConfigCombatLocked() and true or false end
    if _G.InCombatLockdown and _G.InCombatLockdown() then return true end
    return false
end
local function ShowConfigCombatLockMessage()
    if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
        _G.MSUF_ShowConfigCombatLockMessage()
    else
        Print("Menu and Edit Mode are locked in combat. Leave combat to configure MSUF.")
    end
end
local function BlockConfigCombatLocked(silent)
    if not IsConfigCombatLocked() then return false end
    if not silent then ShowConfigCombatLockMessage() end
    return true
end
M.IsConfigCombatLocked = M.IsConfigCombatLocked or IsConfigCombatLocked

-- Every delayed Menu2-only task goes through this registry. C_Timer.After
-- cannot be cancelled, so a callback queued while the menu is open would
-- otherwise still wake once after combat starts even if its body immediately
-- returned. Retail's NewTimer handle lets the combat/menu-hide teardown remove
-- the callback itself: zero delayed Menu2 execution during combat.
local rawTimerAPI = _G.C_Timer
local menuRuntimeGeneration = 0
local menuRuntimeTasks = {}
local Runtime = M.MenuRuntime
if type(Runtime) ~= "table" then
    Runtime = {}
    M.MenuRuntime = Runtime
end

function Runtime:CancelPendingTasks(reason)
    menuRuntimeGeneration = menuRuntimeGeneration + 1
    local cancelled = 0
    while true do
        local task = next(menuRuntimeTasks)
        if task == nil then break end
        menuRuntimeTasks[task] = nil
        task.active = false
        if task.timer and type(task.timer.Cancel) == "function" then
            task.timer:Cancel()
        end
        cancelled = cancelled + 1
    end
    self.lastReason = tostring(reason or "menu-hide")
    return cancelled
end

function Runtime:Schedule(delay, callback, label)
    if type(callback) ~= "function" or IsConfigCombatLocked() then return nil end
    delay = math.max(0, tonumber(delay) or 0)
    local generation = menuRuntimeGeneration
    local task = {
        active = true,
        label = tostring(label or "menu-task"),
    }
    function task:Cancel()
        if not self.active then return end
        self.active = false
        menuRuntimeTasks[self] = nil
        if self.timer and type(self.timer.Cancel) == "function" then
            self.timer:Cancel()
        end
    end
    menuRuntimeTasks[task] = true
    local function Run(...)
        if not task.active then return end
        task.active = false
        menuRuntimeTasks[task] = nil
        if generation ~= menuRuntimeGeneration or IsConfigCombatLocked() then return end
        return callback(...)
    end
    if rawTimerAPI and type(rawTimerAPI.NewTimer) == "function" then
        local timer = rawTimerAPI.NewTimer(delay, Run)
        if timer or not task.active then
            task.timer = timer
            return task
        end
    end
    if rawTimerAPI and type(rawTimerAPI.After) == "function" then
        -- Compatibility-only path for harnesses/old clients. The generation
        -- gate keeps it inert; supported Retail clients use cancellable timers.
        rawTimerAPI.After(delay, Run)
        return task
    end
    Run()
    return task
end

local MenuTimer = {}
function MenuTimer.After(delay, callback)
    Runtime:Schedule(delay, callback, "C_Timer.After")
end
function MenuTimer.NewTimer(delay, callback)
    return Runtime:Schedule(delay, callback, "C_Timer.NewTimer")
end
M.MenuTimer = MenuTimer
function Runtime:PendingTaskCount()
    local count = 0
    for _ in pairs(menuRuntimeTasks) do count = count + 1 end
    return count
end
function Runtime:Resume(reason)
    self.active = true
    self.lastReason = tostring(reason or "menu-show")
    local assistant = (MSUF and MSUF.Assistant) or M.Assistant
    if assistant and type(assistant.SetMenuRuntimeActive) == "function" then
        assistant.SetMenuRuntimeActive(true, self.lastReason)
    elseif assistant then
        assistant._menuRuntimeActive = true
        assistant._menuRuntimeReason = self.lastReason
    end
    return true
end
function Runtime:Quiesce(reason)
    reason = tostring(reason or "menu-hide")
    local combat = IsConfigCombatLocked()
    self.active = false
    self:CancelPendingTasks(reason)
    if type(self._quiesceScale) == "function" then self._quiesceScale(combat) end
    local apply = M.ApplyService
    if apply and type(apply.Quiesce) == "function" then apply.Quiesce(combat) end
    local search = M.SearchBridge
    if search and type(search.CancelSearchBackgroundIndex) == "function" then search.CancelSearchBackgroundIndex() end
    local assistant = (MSUF and MSUF.Assistant) or M.Assistant
    if assistant and type(assistant.SetMenuRuntimeActive) == "function" then
        assistant.SetMenuRuntimeActive(false, reason)
    elseif assistant then
        assistant._menuRuntimeActive = false
        assistant._menuRuntimeReason = reason
    end
    local theme = M.Theme
    if theme and type(theme.StopAllMenuAnimations) == "function" then theme.StopAllMenuAnimations() end
    return true
end
local function EnsureGeneral()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then ensureDB() end
    ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
    _G.MSUF_DB.general = type(_G.MSUF_DB.general) == "table" and _G.MSUF_DB.general or {}
    return _G.MSUF_DB.general
end
local function AddTooltip(widget, title, body, opts)
    if not (widget and (widget.SetScript or widget.HookScript)) then return widget end
    opts = opts or {}
    local owner = opts.owner or "ANCHOR_RIGHT"
    local titleColor = opts.titleColor or { 1, 1, 1 }
    local bodyColor = opts.bodyColor or { 0.80, 0.86, 1.00 }
    local function ResolveText(value, ownerFrame) return type(value) == "function" and value(ownerFrame) or value end
    local function ShowTooltip(self)
        if not _G.GameTooltip then return end
        if opts.enabled and not opts.enabled(self) then return end
        local resolvedTitle = ResolveText(title, self)
        local resolvedBody = ResolveText(body, self)
        _G.GameTooltip:SetOwner(self, owner)
        if resolvedTitle and resolvedTitle ~= "" then
            if opts.titleAsLine then
                _G.GameTooltip:AddLine(Tr(resolvedTitle), titleColor[1] or 1, titleColor[2] or 1, titleColor[3] or 1, titleColor[4])
            else
                _G.GameTooltip:SetText(Tr(resolvedTitle), titleColor[1] or 1, titleColor[2] or 1, titleColor[3] or 1, titleColor[4])
            end
        end
        if resolvedBody and resolvedBody ~= "" then _G.GameTooltip:AddLine(Tr(resolvedBody), bodyColor[1] or 0.80, bodyColor[2] or 0.86, bodyColor[3] or 1.00, true) end
        _G.GameTooltip:Show()
    end
    local function HideTooltip()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end
    local function Wire(target)
        if opts.hook and target.HookScript then
            target:HookScript("OnEnter", ShowTooltip)
            target:HookScript("OnLeave", HideTooltip)
        elseif target.SetScript then
            target:SetScript("OnEnter", ShowTooltip)
            target:SetScript("OnLeave", HideTooltip)
        end
    end
    Wire(widget)
    if opts.labelHit and widget._msuf2LabelHit and widget._msuf2LabelHit ~= widget then Wire(widget._msuf2LabelHit) end
    return widget
end
ExportPublic("MSUF_AddTooltip", _G.MSUF_AddTooltip or AddTooltip)
M.AddTooltip = M.AddTooltip or AddTooltip
local PREVIEW_NUDGE_DIRECTIONS = { { "LEFT", -1, 0 }, { "RIGHT", 1, 0 }, { "UP", 0, 1 }, { "DOWN", 0, -1 } }
local PREVIEW_NUDGE_BINDING_PREFIXES = { "", "SHIFT-", "CTRL-", "CTRL-SHIFT-", "SHIFT-CTRL-" }

local function ReleasePreviewKeyboardCapture(box)
    local helpers = M.PreviewHelpers
    if helpers and type(helpers.ReleaseKeyboardCapture) == "function" then
        helpers.ReleaseKeyboardCapture(box)
    elseif box and box.SetPropagateKeyboardInput then
        box:SetPropagateKeyboardInput(true)
    end
end

local function PreviewBindingOwner_OnEvent(self, event)
    if event == "PLAYER_REGEN_DISABLED" then
        self.__msufPendingClear = true
        ReleasePreviewKeyboardCapture(self.__msufActiveBox)
        return
    end
    if event ~= "PLAYER_REGEN_ENABLED" then return end
    if InCombatLockdown and InCombatLockdown() then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self.__msufPendingClear = nil
    if self.__msufActiveName then _G[self.__msufActiveName] = nil end
    ReleasePreviewKeyboardCapture(self.__msufActiveBox)
    self.__msufActiveBox = nil
    self.__msufActiveName = nil
    if ClearOverrideBindings then ClearOverrideBindings(self) end
    if self.Hide then self:Hide() end
end

local function EnsurePreviewBindingOwner(ownerName)
    if not ownerName then return nil end
    local owner = _G[ownerName]
    if not owner then
        owner = CreateFrame("Frame", ownerName, UIParent)
        _G[ownerName] = owner
    end
    if owner.SetScript and owner.__msufPreviewBindingOwner ~= true then
        owner.__msufPreviewBindingOwner = true
        owner:SetScript("OnEvent", PreviewBindingOwner_OnEvent)
    end
    return owner
end

-- Shared secure arrow-key binding for preview-only movers. The helper only runs
-- while preview handles are selected and exits before touching protected state in combat.
function M.SetPreviewArrowBindings(box, enabled, spec)
    spec = spec or {}
    local ownerName = spec.ownerName
    local activeName = spec.activeName
    local owner = ownerName and _G[ownerName]
    if InCombatLockdown and InCombatLockdown() then
        ReleasePreviewKeyboardCapture(box)
        if activeName and (enabled or _G[activeName] == box or box == nil) then _G[activeName] = nil end
        if not enabled or not box then
            if spec.onDisable then spec.onDisable(box) end
        end
        if owner then
            if owner.SetScript and owner.__msufPreviewBindingOwner ~= true then
                owner.__msufPreviewBindingOwner = true
                owner:SetScript("OnEvent", PreviewBindingOwner_OnEvent)
            end
            owner.__msufActiveBox = box
            owner.__msufActiveName = activeName
            owner.__msufPendingClear = true
            if owner.RegisterEvent then owner:RegisterEvent("PLAYER_REGEN_ENABLED") end
        end
        return false
    end
    if owner and ClearOverrideBindings then ClearOverrideBindings(owner) end
    if owner and owner.Hide then owner:Hide() end
    if not enabled or not box then
        if spec.onDisable then spec.onDisable(box) end
        if activeName and (_G[activeName] == box or box == nil) then _G[activeName] = nil end
        if owner then
            owner.__msufPendingClear = nil
            owner.__msufActiveBox = nil
            owner.__msufActiveName = nil
            if owner.UnregisterEvent then
                owner:UnregisterEvent("PLAYER_REGEN_DISABLED")
                owner:UnregisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
        return
    end
    if activeName then _G[activeName] = box end
    owner = EnsurePreviewBindingOwner(ownerName)
    if not owner then return false end
    owner.__msufPendingClear = nil
    owner.__msufActiveBox = box
    owner.__msufActiveName = activeName
    owner:Show()
    if owner.RegisterEvent then
        owner:RegisterEvent("PLAYER_REGEN_DISABLED")
        owner:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
    local prefix = spec.buttonPrefix or ownerName or "MSUF_Preview_Nudge"
    for i = 1, #PREVIEW_NUDGE_DIRECTIONS do
        local dir = PREVIEW_NUDGE_DIRECTIONS[i]
        local btnName = prefix .. dir[1]
        local btn = _G[btnName]
        if not btn then
            btn = CreateFrame("Button", btnName, owner, "SecureActionButtonTemplate")
            btn:SetSize(1, 1)
            btn:Hide()
            btn:SetScript("OnClick", function(self)
                local s = self._msufNudgeSpec or {}
                local active = s.getActive and s.getActive() or (s.activeName and _G[s.activeName])
                if s.onClick then s.onClick(active, self._msufDx or 0, self._msufDy or 0, self) end
            end)
        end
        btn._msufNudgeSpec = spec
        btn._msufDx, btn._msufDy = dir[2], dir[3]
        if SetOverrideBindingClick then
            for j = 1, #PREVIEW_NUDGE_BINDING_PREFIXES do
                SetOverrideBindingClick(owner, false, PREVIEW_NUDGE_BINDING_PREFIXES[j] .. dir[1], btnName)
            end
        end
    end
end
local STATIC_POPUP_DEFAULTS = { timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3 }
function M.InstallStaticPopup(key, spec, defaults)
    if not (_G.StaticPopupDialogs and key and type(spec) == "table") then return nil end
    local existing = _G.StaticPopupDialogs[key]
    if existing then return existing end
    for field, value in pairs(defaults or STATIC_POPUP_DEFAULTS) do
        if spec[field] == nil then spec[field] = value end
    end
    _G.StaticPopupDialogs[key] = spec
    return spec
end
local function LeftJustifyButtonText(btn, leftPad)
    leftPad = leftPad or 10
    if not (btn and btn.GetFontString) then return end
    local fontString = btn:GetFontString()
    if not fontString then return end
    if fontString.SetJustifyH then fontString:SetJustifyH("LEFT") end
    if fontString.ClearAllPoints and fontString.SetPoint then
        fontString:ClearAllPoints()
        fontString:SetPoint("LEFT", btn, "LEFT", leftPad, 0)
        fontString:SetPoint("RIGHT", btn, "RIGHT", -8, 0)
    end
end
ExportPublic("MSUF_LeftJustifyButtonText", _G.MSUF_LeftJustifyButtonText or LeftJustifyButtonText)
function M.ValueTextList(...)
    local out = {}
    local n = select("#", ...)
    for i = 1, n, 2 do
        local value = select(i, ...)
        local text = select(i + 1, ...)
        out[#out + 1] = { value = value, text = text ~= nil and text or value }
    end
    return out
end
function M.Lines(rows) return tostring(rows or ""):gmatch("[^\r\n]+") end
function M.ValueTextRows(rows)
    local out = {}
    for line in M.Lines(rows) do
        local value, text = line:match("^(.-)=(.*)$")
        if value then out[#out + 1] = { value = value, text = text ~= "" and text or value } end
    end
    return out
end
function M.ValueTextPairs(rows)
    local out = {}
    for item in tostring(rows or ""):gmatch("[^|\r\n]+") do
        local value, text = item:match("^(.-)=(.*)$")
        if value then out[#out + 1] = { value = value, text = text ~= "" and text or value } end
    end
    return out
end
function M.KeyLabelRows(rows)
    local out = {}
    for line in M.Lines(rows) do
        local key, label = line:match("^(.-)=(.*)$")
        if key then out[#out + 1] = { key = key, label = label ~= "" and label or key } end
    end
    return out
end
function M.KeyLabelMap(rows)
    local out = {}
    for item in tostring(rows or ""):gmatch("[^|\r\n]+") do
        local key, label = item:match("^(.-)=(.*)$")
        if key then out[key] = label ~= "" and label or key end
    end
    return out
end
function M.PipeRows(rows)
    local out = {}
    for line in M.Lines(rows) do
        local cols, n = {}, 0
        for col in (line .. "|"):gmatch("(.-)|") do n = n + 1; cols[n] = col end
        out[#out + 1] = cols
    end
    return out
end
function M.ColorRows(...)
    local out = {}
    local n = select("#", ...)
    if n == 1 and type((...)) == "string" then
        for line in tostring((...) or ""):gmatch("[^;\r\n]+") do
            local key, label, r, g, b = line:match("^([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
            if key then out[#out + 1] = { key = key, label = label, dr = tonumber(r), dg = tonumber(g), db = tonumber(b) } end
        end
        return out
    end
    for i = 1, n, 5 do
        out[#out + 1] = { key = select(i, ...), label = select(i + 1, ...), dr = select(i + 2, ...), dg = select(i + 3, ...), db = select(i + 4, ...) }
    end
    return out
end
function M.KeySet(...)
    local out = {}
    for i = 1, select("#", ...) do
        out[select(i, ...)] = true
    end
    return out
end
function M.KeySetFromWords(text)
    local out = {}
    for key in tostring(text or ""):gmatch("%S+") do out[key] = true end
    return out
end
function M.WordList(text)
    local out = {}
    for value in tostring(text or ""):gmatch("%S+") do out[#out + 1] = value end
    return out
end

--- Cold Menu2 copy dialogs derive field lists from control specs.
function M.CopyFieldsFromSpecs(specs, values, seed, props)
    local out = type(seed) == "table" and seed or M.WordList(seed or "")
    props = props or "show iconStyle x y anchor size layer symbol"
    for value in tostring(values or ""):gmatch("%S+") do
        for i = 1, #(specs or {}) do
            local spec = specs[i]
            if spec.value == value then
                for prop in tostring(spec.copyProps or props):gmatch("%S+") do local key = spec[prop]; if key then out[#out + 1] = key end end
                -- colorPrefix names a key family rather than one key, so it is
                -- expanded here: a copied text indicator has to bring its color
                -- along with its placement or the copy looks half applied.
                local colorPrefix = spec.colorPrefix
                if colorPrefix then
                    out[#out + 1] = colorPrefix .. "ColorR"
                    out[#out + 1] = colorPrefix .. "ColorG"
                    out[#out + 1] = colorPrefix .. "ColorB"
                end
                local extra = spec.copyExtra; if extra then for j = 1, #extra do out[#out + 1] = extra[j] end end
                break
            end
        end
    end
    return out
end
local COMMON_FALLBACKS = {
    Noop = function() end, Nil = function() return nil end, False = function() return false end, True = function() return true end, TruePair = function() return true, true end,
    One = function() return 1 end, Empty = function() return "" end, Identity = function(v) return v end, Round = function(value) return floor((tonumber(value) or 0) + 0.5) end,
    WhiteRGB = function() return 1, 1, 1 end, BlackRGBA = function() return 0, 0, 0, 1 end, DarkRGBA = function() return 0.02, 0.03, 0.04, 0.9 end, HealthRGB = function() return 0.2, 0.8, 0.2 end, PowerRGB = function() return 0.2, 0.45, 1.0 end,
    Center = function() return "CENTER" end, Right = function() return "RIGHT" end, Status = function() return "Status" end, QuestionIcon = function() return "Interface\\Icons\\INV_Misc_QuestionMark" end, ZeroPair = function() return 0, 0 end,
}
M.Fallbacks = M.Fallbacks or COMMON_FALLBACKS
function M.SetMenuStateValue(field, value)
    local result
    if type(M.PersistMenuStateValue) == "function" then
        result = M.PersistMenuStateValue(field, value)
    else
        M[field] = value
        result = value
    end
    if (field == "gfScope" or field == "auraScope") and type(M.RefreshLayerOverviewContext) == "function" then
        M.RefreshLayerOverviewContext()
    end
    return result
end
function M.TextSlotOffsetKeys(kind, slot)
    if kind == "name" then return "nameOffsetX", "nameOffsetY" end
    if kind == "hp" and not slot then return "hpOffsetX", "hpOffsetY" end
    if kind == "power" and not slot then return "powerOffsetX", "powerOffsetY" end
    local prefix
    if kind == "hp" then
        prefix = (slot == "left" and "hpTextLeft") or (slot == "right" and "hpTextRight") or "hpTextCenter"
    elseif kind == "power" then
        prefix = (slot == "left" and "powerTextLeft") or (slot == "right" and "powerTextRight") or "powerTextCenter"
    end
    if not prefix then return "nameOffsetX", "nameOffsetY" end
    return prefix .. "OffsetX", prefix .. "OffsetY"
end
function M.TextSlotFontSizeKey(kind, slot)
    local prefix
    if kind == "hp" then
        prefix = (slot == "left" and "hpTextLeft") or (slot == "right" and "hpTextRight") or "hpTextCenter"
    elseif kind == "power" then
        prefix = (slot == "left" and "powerTextLeft") or (slot == "right" and "powerTextRight") or "powerTextCenter"
    end
    return prefix and (prefix .. "FontSize") or nil
end
local function DeepCopyValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do
        local outKey = type(k) == "table" and DeepCopyValue(k, seen) or k
        out[outKey] = type(v) == "table" and DeepCopyValue(v, seen) or v
    end
    return out
end

function M.DeepCopy(value, seen)
    return DeepCopyValue(value, seen)
end
local function PickValues(source, names, fallbacks, defaultEmpty)
    local values, count = {}, 0
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        local value = source[name]
        if fallbacks then value = value or fallbacks[name]
        elseif defaultEmpty then value = value or {} end
        values[count] = value
    end
    return unpack(values, 1, count)
end
local function PickTableValues(target, source, names, fallbacks, defaultEmpty)
    target = type(target) == "table" and target or {}
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        local value = source[name]
        if fallbacks then value = value or fallbacks[name]
        elseif defaultEmpty then value = value or {} end
        target[name] = value
    end
    return target
end
function M.Pick(source, names) return PickValues(source, names) end
function M.PickDefaults(source, names) return PickValues(source, names, nil, true) end
function M.PickFallbacks(source, fallbacks, names) return PickValues(source, names, fallbacks or {}) end
function M.PickFallbackTable(source, fallbacks, names, target) return PickTableValues(target, source, names, fallbacks or {}) end
function M.Assign(target, values)
    if type(target) ~= "table" or type(values) ~= "table" then return target end
    for key, value in pairs(values) do target[key] = value end
    return target
end
function M.AppendValues(target, ...) if type(target) ~= "table" then target = {} end; for i = 1, select("#", ...) do target[#target + 1] = select(i, ...) end; return target end
function M.AppendNamedValues(target, source, names) if type(target) ~= "table" then target = {} end; source = source or {}; for name in tostring(names or ""):gmatch("%S+") do target[#target + 1] = source[name] end; return target end
function M.AssignNamedValues(target, names, ...)
    if type(target) ~= "table" then target = {} end
    local index = 1
    for name in tostring(names or ""):gmatch("%S+") do
        target[name] = select(index, ...)
        index = index + 1
    end
    return target
end
function M.BuildControlSpecs(specs, handlers, nameFn, list)
    local controls = {}
    if type(specs) ~= "table" or type(handlers) ~= "table" then return controls end
    for i = 1, #specs do
        local spec = specs[i]
        local handler = spec and (handlers[spec[1]] or handlers["*"] or handlers.default)
        if handler then
            local control, name = handler(spec, i)
            if control ~= nil then
                controls[name or (nameFn and nameFn(spec, i, control)) or spec.name or i] = control
                if list then list[#list + 1] = control end
            end
        end
    end
    return controls
end

-- Shared Page binder helpers.
-- These keep page files focused on "which control exists" instead of repeating the
-- same create/place/bind ceremony. Callers still supply the exact get/set closures,
-- so no page-specific state or apply behavior is hidden here.  The optional final
-- metadata table accepts controlId/identityKey/settingKey (and the corresponding
-- action/navigation fields) for incremental runtime-catalog migration.
function M.BindBoolWidget(ctx, widget, getValue, setValue, metadata)
    M.BindToggle(ctx, widget,
        function() return getValue() and true or false end,
        function(v) setValue(v and true or false) end,
        metadata)
    return widget
end
function M.BindNumberWidget(ctx, widget, getValue, setValue, fallback, opts)
    opts = type(opts) == "table" and opts or {}
    M.BindSlider(ctx, widget,
        function() return tonumber(getValue()) or fallback or 0 end,
        function(v)
            v = tonumber(v) or fallback or 0
            if opts.roundStep and (opts.step or 1) >= 1 then v = floor(v + 0.5) end
            setValue(v)
        end,
        opts)
    return widget
end
function M.BindDropdownWidget(ctx, widget, getValue, setValue, metadata)
    M.BindDropdown(ctx, widget, getValue, setValue, metadata)
    return widget
end
function M.BindSwitchAt(ctx, parent, label, x, y, width, getValue, setValue, metadata)
    return M.BindBoolWidget(ctx, M.Widgets.SwitchAt(parent, label, x, y, width or 180), getValue, setValue, metadata)
end
function M.BindToggleAt(ctx, parent, label, x, y, width, getValue, setValue, metadata)
    return M.BindBoolWidget(ctx, M.Widgets.ToggleAt(parent, label, x, y, width or 180), getValue, setValue, metadata)
end
function M.BindSliderAt(ctx, parent, label, x, y, minVal, maxVal, step, width, getValue, setValue, opts)
    local widget = M.Widgets.Slider(parent, label, minVal, maxVal, step, width)
    M.Widgets.MoveWidget(widget, parent, x, y, width)
    return M.BindNumberWidget(ctx, widget, getValue, setValue, opts and opts.fallback, opts)
end
function M.BindDropdownAt(ctx, parent, label, x, y, values, width, getValue, setValue, metadata)
    local widget = M.Widgets.Dropdown(parent, label, values, width)
    M.Widgets.MoveWidget(widget, parent, x, y, width)
    return M.BindDropdownWidget(ctx, widget, getValue, setValue, metadata)
end
function M.BindTextInputAt(ctx, parent, label, x, y, width, getValue, setValue, commitOnBlur, metadata)
    local widget = M.Widgets.TextInput(parent, label, width)
    M.Widgets.MoveWidget(widget, parent, x, y, width)
    M.BindTextInput(ctx, widget,
        function() return getValue() or "" end,
        function(v) setValue(v or "") end,
        commitOnBlur,
        metadata)
    return widget
end
function M.CallIf(fn, ...)
    if type(fn) == "function" then return fn(...) end
end

-- Lets callbacks call a refresh function before its body is assigned later in the page build.
function M.RefreshProxy()
    local refresh
    return function(candidate)
        -- Toggle callbacks may pass their new boolean value to an `afterSet` handler.
        -- Only functions install the proxy target; every other value is a refresh request.
        if type(candidate) == "function" then
            refresh = candidate
            return candidate
        end
        return M.CallIf(refresh)
    end
end

--- Declarative "master toggle gates dependent controls" helper.
--- Replaces the repeated hand-written refresh closures that read a config value and call
--- SetControlEnabled/SetControlsEnabled for each control group. The single most duplicated
--- logic shape in the Pages layer (see disabledRefresh closures), so collapsing each gate
--- from ~3 lines to one declarative row both shrinks pages and removes copy/paste drift.
---
--- source: optional fn returning the config table passed to each entry's predicates.
--- entries: list of {
---   on        = fn(cfg) -> bool   -- whether `controls` are enabled (required)
---   controls  = widget | {widgets} -- gated by `on`
---   enable    = widget | {widgets} -- the master toggle itself; enabled by `enableOn` (default: always on)
---   enableOn  = fn(cfg) -> bool    -- optional gate for `enable` (e.g. hasTotemFrame)
---   when      = fn(cfg) -> bool    -- optional: skip this entry entirely when false (control left untouched)
--- }
--- opts.also:    extra fn run at the end of every refresh (e.g. a preview repaint).
--- opts.override: fn(cfg, setEnabled) run last, for page-specific final adjustments
---               (e.g. a "managed power" branch that force-disables a group).
--- opts.track:   custom registration fn(ctx, refresh); defaults to M.TrackRefresh.
---               Pass M.TrackCollapsibleRefresh-style closures here to keep a page's
---               existing refresh wiring (collapsible/section refreshers).
--- opts.noTrack: when true, return the bare refresh fn WITHOUT registering it (caller
---               wires it into its own combined closure).
--- Returns the refresh fn.
function M.BindGateGroup(ctx, source, entries, opts)
    opts = opts or {}
    local W = M.Widgets
    local function setEnabled(target, enabled)
        if not target then return end
        if type(target) == "table" and target[1] ~= nil and not target.GetObjectType then
            W.SetControlsEnabled(target, enabled)
        else
            W.SetControlEnabled(target, enabled)
        end
    end
    local function refresh()
        local cfg = M.CallIf(source)
        for i = 1, #entries do
            local e = entries[i]
            if (not e.when) or e.when(cfg) then
                if e.enable then setEnabled(e.enable, e.enableOn and (e.enableOn(cfg) and true or false) or true) end
                if e.controls then setEnabled(e.controls, e.on and (e.on(cfg) and true or false) or false) end
            end
        end
        if opts.override then opts.override(cfg, setEnabled) end
        M.CallIf(opts.also)
    end
    if opts.noTrack then return refresh end
    if opts.track then return opts.track(ctx, refresh) or refresh end
    return M.TrackRefresh(ctx, refresh)
end
function M.RequestOrRefresh(ctx, reason) if M.RequestRefresh then return M.RequestRefresh(ctx, reason) end; return M.CallIf(M.Refresh, ctx) end
function M.NormalizeHpMode(mode)
    if type(_G.MSUF_NormalizeHpTextMode) == "function" then return _G.MSUF_NormalizeHpTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
    return mode
end
function M.NormalizePowerMode(mode)
    if type(_G.MSUF_NormalizePowerTextMode) == "function" then return _G.MSUF_NormalizePowerTextMode(mode) end
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_SLASH_MAX" then return "CURMAX" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" or mode == "PERCENT_PLUS_FULL" then return "CURPERCENT" end
    return mode
end
function M.ApplyGameplay()
    if MSUF and type(MSUF.MSUF_RequestGameplayApply) == "function" then
        local result = MSUF.MSUF_RequestGameplayApply()
        return result ~= false
    end
    if MSUF and type(MSUF.MSUF_ApplyGameplayVisuals) == "function" then
        local result = MSUF.MSUF_ApplyGameplayVisuals()
        return result ~= false
    end
    return false
end
local function GameplayDB()
    local db
    if type(M.EnsureDB) == "function" then db = M.EnsureDB() end
    if type(db) ~= "table" then
        ExportPublic("MSUF_DB", type(_G.MSUF_DB) == "table" and _G.MSUF_DB or {})
        db = _G.MSUF_DB
    end
    db.gameplay = type(db.gameplay) == "table" and db.gameplay or {}
    return db.gameplay
end
function M.GetGameplayPlayerSpecID()
    if MSUF and type(MSUF.MSUF_GetPlayerSpecID) == "function" then
        return MSUF.MSUF_GetPlayerSpecID()
    end
    if type(_G.MSUF_GetPlayerSpecID) == "function" then
        return _G.MSUF_GetPlayerSpecID()
    end
    if GetSpecialization and GetSpecializationInfo then
        local spec = GetSpecialization()
        if spec then
            local id = GetSpecializationInfo(spec)
            return id
        end
    end
    return nil
end
function M.ResolveGameplaySpellInput(value)
    local text = tostring(value or ""):match("^%s*(.-)%s*$")
    if text == "" then return 0 end
    local linkID = text:match("[Ss][Pp][Ee][Ll][Ll]:(%d+)")
    if linkID then return tonumber(linkID) or 0 end
    local asNumber = tonumber(text)
    if asNumber then return floor(asNumber + 0.5) end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(text)
        if type(info) == "table" and info.spellID then return tonumber(info.spellID) or 0 end
    end
    if text ~= "" and GetSpellInfo then
        local _, _, _, _, _, _, spellID = GetSpellInfo(text)
        return tonumber(spellID) or 0
    end
    return 0
end
function M.GetGameplaySpellName(id)
    id = tonumber(id) or 0
    if id <= 0 then return nil end
    if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
        local info = C_Spell.GetSpellInfo(id)
        if type(info) == "table" and info.name then return info.name end
    end
    if GetSpellInfo then
        local name = GetSpellInfo(id)
        return name
    end
    return nil
end
function M.GetGameplayMeleeSpellID(g)
    g = g or GameplayDB()
    local id = 0
    if g.meleeSpellPerSpec and type(g.nameplateMeleeSpellIDBySpec) == "table" then
        local specID = M.GetGameplayPlayerSpecID()
        if specID then id = tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0 end
    end
    if id <= 0 and g.meleeSpellPerClass and type(g.nameplateMeleeSpellIDByClass) == "table" and UnitClass then
        local _, class = UnitClass("player")
        if class then id = tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0 end
    end
    if id <= 0 then id = tonumber(g.nameplateMeleeSpellID) or 0 end
    return id
end
function M.SeedGameplayMeleeSpellScope(scope)
    local g = GameplayDB()
    if scope == "spec" then
        g.nameplateMeleeSpellIDBySpec = type(g.nameplateMeleeSpellIDBySpec) == "table" and g.nameplateMeleeSpellIDBySpec or {}
        local specID = M.GetGameplayPlayerSpecID()
        if specID and (tonumber(g.nameplateMeleeSpellIDBySpec[specID]) or 0) <= 0 then g.nameplateMeleeSpellIDBySpec[specID] = M.GetGameplayMeleeSpellID(g) end
    elseif scope == "class" then
        g.nameplateMeleeSpellIDByClass = type(g.nameplateMeleeSpellIDByClass) == "table" and g.nameplateMeleeSpellIDByClass or {}
        if UnitClass then
            local _, class = UnitClass("player")
            if class and (tonumber(g.nameplateMeleeSpellIDByClass[class]) or 0) <= 0 then g.nameplateMeleeSpellIDByClass[class] = M.GetGameplayMeleeSpellID(g) end
        end
    end
end
function M.SetGameplayMeleeSpellID(value)
    local spellID = M.ResolveGameplaySpellInput(value)
    local g = GameplayDB()
    if g.meleeSpellPerSpec then
        g.nameplateMeleeSpellIDBySpec = type(g.nameplateMeleeSpellIDBySpec) == "table" and g.nameplateMeleeSpellIDBySpec or {}
        local specID = M.GetGameplayPlayerSpecID()
        if specID then g.nameplateMeleeSpellIDBySpec[specID] = spellID end
    elseif g.meleeSpellPerClass and UnitClass then
        g.nameplateMeleeSpellIDByClass = type(g.nameplateMeleeSpellIDByClass) == "table" and g.nameplateMeleeSpellIDByClass or {}
        local _, class = UnitClass("player")
        if class then g.nameplateMeleeSpellIDByClass[class] = spellID end
    end
    g.nameplateMeleeSpellID = spellID
    return spellID
end
function M.StatusBarTextureItems(followText)
    local ui = MSUF and MSUF.UI
    if ui and type(ui.StatusBarTextureItems) == "function" then return ui.StatusBarTextureItems(followText) end
    local out = {}
    if followText then out[#out + 1] = { value = "", text = followText } end
    for _, name in ipairs({ "Blizzard", "Flat", "RaidHP", "RaidPower", "Skills", "Outline" }) do
        out[#out + 1] = { value = name, text = name, previewKind = "statusbar" }
    end
    return out
end
function M.PercentValue(value)
    return tostring(floor((tonumber(value) or 0) * 100 + 0.5)) .. "%"
end
function M.ParsePercentValue(text)
    local raw = tostring(text or "")
    local value = tonumber((raw:gsub("%%", ""):gsub(",", ".")))
    if value == nil then return nil end
    if raw:find("%%") or value > 1 then return value / 100 end
    return value
end
function M.UsePercentInput(widget)
    if widget and widget.SetValueFormatter then widget:SetValueFormatter(M.PercentValue) end
    if widget and widget.SetValueParser then widget:SetValueParser(M.ParsePercentValue) end
end
function M.Clamp01(value, fallback)
    value = tonumber(value)
    if value == nil then return fallback or 0 end
    if value < 0 then return 0 end
    if value > 1 then return 1 end
    return value
end
function M.AlphaLabel(label, value)
    return tostring(label or "") .. ": " .. M.PercentValue(value)
end
function M.BindSliderLiveLabel(ctx, widget, readValue, labelFn, percentInput)
    if percentInput then M.UsePercentInput(widget) end
    local function SetLabel(value)
        if widget and widget._msuf2Title then widget._msuf2Title:SetText(labelFn(value)) end
    end
    widget:HookScript("OnValueChanged", function(_, value) SetLabel(value) end)
    local function RefreshLabel() SetLabel(readValue()) end
    M.TrackRefresh(ctx, RefreshLabel)
    return widget
end
function M.BindSliderDragPreview(widget, callback)
    if not (widget and type(callback) == "function") then return widget end
    local active = false
    local function Begin(_, value)
        active = true
        callback(true, tonumber(value) or (widget.GetValue and widget:GetValue()) or 0)
    end
    local function Finish()
        if not active then return end
        active = false
        callback(false)
    end
    if type(widget.SetInteractionCallbacks) == "function" then
        widget:SetInteractionCallbacks(Begin, Finish)
    elseif widget.HookScript then
        widget:HookScript("OnMouseDown", function(self, button)
            if button and button ~= "LeftButton" then return end
            if self.IsEnabled and not self:IsEnabled() then return end
            Begin(self, self.GetValue and self:GetValue())
        end)
        widget:HookScript("OnMouseUp", Finish)
    end
    if widget.HookScript then
        widget:HookScript("OnValueChanged", function(_, value)
            if active then callback(true, tonumber(value) or 0) end
        end)
        widget:HookScript("OnHide", Finish)
    end
    return widget
end

local rangeFadePreviewOwners = { unit = {}, group = {} }
local function RefreshRangeFadePreviewBox(surface, box)
    if not box then return end
    local shown = not box.IsShown or box:IsShown()
    if shown and type(box.RequestRefresh) == "function" then
        box:RequestRefresh(surface == "group" and "GROUP_PREVIEW_RANGE_FADE_SLIDER"
            or "MSUF2_RANGE_FADE_SLIDER_PREVIEW")
        return
    end
    if shown and surface == "unit" then
        local preview = MSUF and MSUF.UFPreview
        if preview and type(preview.RequestRefreshForBox) == "function" then
            preview.RequestRefreshForBox(box, "MSUF2_RANGE_FADE_SLIDER_PREVIEW")
        end
    end
end
function M.SetRangeFadePreviewState(surface, active, alpha, layerMode)
    surface = surface == "group" and "group" or "unit"
    local owners = rangeFadePreviewOwners[surface]
    local candidates = {}
    local function Add(box)
        if not box or candidates[box] then return end
        candidates[box] = true
        if active then owners[box] = true end
    end
    if surface == "unit" then
        local preview = MSUF and MSUF.UFPreview
        Add(preview and preview.active)
        Add(M.UnitPage and M.UnitPage._sharedUnitPreviewBox)
    else
        for i = 1, #(M._gfNativePreviews or {}) do Add(M._gfNativePreviews[i]) end
        Add(M.GroupPreview and M.GroupPreview._sharedNativeBox)
    end
    for box in pairs(owners) do candidates[box] = true end
    local previewAlpha = active and Clamp(alpha, 0, 1) or nil
    local previewLayer = active and (layerMode == "health" and "health" or "frame") or nil
    for box in pairs(candidates) do
        box._msuf2RangeFadePreviewAlpha = previewAlpha
        box._msuf2RangeFadePreviewLayerMode = previewLayer
        RefreshRangeFadePreviewBox(surface, box)
        if not active then owners[box] = nil end
    end
end
function M.TruncateUtf8Chars(value, maxChars)
    value = tostring(value or "")
    maxChars = tonumber(maxChars) or 0
    if maxChars <= 0 or value == "" then return "" end
    local bytePos, valueLen, chars = 1, #value, 0
    while bytePos <= valueLen and chars < maxChars do
        local b = string.byte(value, bytePos)
        if not b then break end
        if b < 128 then
            bytePos = bytePos + 1
        elseif b < 224 then
            bytePos = bytePos + 2
        elseif b < 240 then
            bytePos = bytePos + 3
        else
            bytePos = bytePos + 4
        end
        chars = chars + 1
    end
    return string.sub(value, 1, bytePos - 1)
end
function M.CleanToTInlineCustomSeparator(value, maxChars)
    value = tostring(value or ""):gsub("[%c]", " ")
    return M.TruncateUtf8Chars(value, maxChars or 5)
end
function M.ApplyPopupFramePriority(frame)
    if not frame then return end
    if type(M.ApplyMenuPopupFramePriority) == "function" then
        M.ApplyMenuPopupFramePriority(frame)
    elseif type(M.ApplyMenuFramePriority) == "function" then
        M.ApplyMenuFramePriority(frame, M.MENU_POPUP_FRAME_LEVEL or 400)
    else
        if frame.SetFrameStrata then frame:SetFrameStrata("FULLSCREEN_DIALOG") end
        if frame.SetFrameLevel then frame:SetFrameLevel(M.MENU_POPUP_FRAME_LEVEL or 400) end
    end
end
function M.CreateMenuPopupPanel(parent, opts)
    opts = opts or {}
    local theme = M.Theme or {}
    local colors = theme.colors or {}
    local panel = CreateFrame("Frame", opts.name, parent, opts.template or (theme.Template and theme.Template() or nil))
    local bg = opts.bg or colors.glassPopup or { 0.014, 0.024, 0.050, 0.985 }
    local border = opts.border or { 0.10, 0.22, 0.44, 0.80 }
    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        panel:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.985)
        panel:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 0.80)
    else
        local fill = panel:CreateTexture(nil, "BACKGROUND")
        fill:SetAllPoints()
        fill:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 0.985)
        local edge = panel:CreateTexture(nil, "BORDER")
        edge:SetPoint("TOPLEFT")
        edge:SetPoint("TOPRIGHT")
        edge:SetHeight(1)
        edge:SetColorTexture(border[1], border[2], border[3], border[4] or 0.80)
    end
    if theme.ApplyGlass then theme.ApplyGlass(panel, opts.glass or "popup") end
    if opts.priority ~= false then M.ApplyPopupFramePriority(panel) end
    if opts.mouse ~= false and panel.EnableMouse then panel:EnableMouse(true) end
    return panel
end
M.Noop = M.Noop or M.Fallbacks.Noop
function M.OnOffBadge(enabled, onText, offText)
    return {
        text = enabled and (onText or "Shown") or (offText or "Hidden"),
        kind = enabled and "ok" or "muted",
    }
end
function M.BadgeNumber(value)
    value = tonumber(value) or 0
    if value == math.floor(value) then return tostring(math.floor(value)) end
    return string.format("%.1f", value)
end
function M.OptionText(values, value, fallback)
    if type(values) == "function" then values = values() end
    if type(values) == "table" then
        for i = 1, #values do
            local item = values[i]
            if type(item) == "table" then
                local itemValue = item.value
                if itemValue == nil then itemValue = item.key or item[1] end
                if tostring(itemValue) == tostring(value) then return item.text or item.label or tostring(value or fallback or "") end
            end
        end
    end
    if value == nil or value == "" then return fallback or "" end
    return tostring(value)
end
function M.NormalizePortraitClassStyle(value)
    if value == "class_colored_border" or value == "colored" then return "RONDO_COLOR" end
    if value == "wow_icon_border" or value == "wow" then return "RONDO_WOW" end
    local fn = _G.MSUF_NormalizePortraitClassStyleValue
    if type(fn) == "function" then return fn(value) end
    local PM = MSUF and MSUF.PortraitMedia
    if PM and type(PM.NormalizeClassPack) == "function" then return PM.NormalizeClassPack(value) end
    if value == "RONDO_COLOR" or value == "RONDO_WOW" or value == "BLIZZARD" then return value end
    return "BLIZZARD"
end
function M.IsMSUFEditModeActive(includeBlizzard)
    local st = rawget(_G, "MSUF_EditState")
    if type(st) == "table" and st.active ~= nil then return st.active == true end
    local em2 = rawget(_G, "MSUF_EM2")
    local state = em2 and em2.State
    if state and type(state.IsActive) == "function" then return state.IsActive() and true or false end
    local fn = rawget(_G, "MSUF_IsMSUFEditModeActive")
        or rawget(_G, "MSUF_IsInEditMode")
        or rawget(_G, "MSUF_IsEditModeActive")
        or (includeBlizzard and rawget(_G, "IsEditModeActive") or nil)
    if type(fn) == "function" then
        return fn() and true or false
    end
    return rawget(_G, "MSUF_UnitEditModeActive") == true
        or rawget(_G, "MSUF_EDITMODE_ACTIVE") == true
end
function M.IsEditModeCombatLocked(includeBlizzard)
    local fn = includeBlizzard and rawget(_G, "IsEditModeCombatLocked") or nil
    if type(fn) == "function" then
        return fn() and true or false
    end
    return (_G.InCombatLockdown and _G.InCombatLockdown()) and true or false
end
local function EditModeState()
    local em2 = rawget(_G, "MSUF_EM2")
    local state = type(em2) == "table" and em2.State or nil
    return type(state) == "table" and state or nil
end
local function RefreshEditModeSurfaces()
    if type(M.RefreshMenuFramePriority) == "function" then M.RefreshMenuFramePriority() end
    if type(M.RefreshDashboardEditModeButton) == "function" then M.RefreshDashboardEditModeButton() end
    if M.frame and type(M.frame.RefreshStatus) == "function" then M.frame:RefreshStatus() end
end
function M.EditModeLifecycleStatus(includeBlizzard)
    local state = EditModeState()
    local setFn = rawget(_G, "MSUF_SetMSUFEditModeDirect") or rawget(_G, "MSUF_SetEditMode")
    local unitKey = rawget(_G, "MSUF_CurrentEditUnitKey")
    if state and type(state.GetUnitKey) == "function" then unitKey = state.GetUnitKey() or unitKey end
    return {
        active = M.IsMSUFEditModeActive(includeBlizzard) and true or false,
        combatLocked = M.IsEditModeCombatLocked(includeBlizzard) and true or false,
        unitKey = unitKey,
        hasDirectHelper = type(setFn) == "function",
        hasStateEnter = state and type(state.Enter) == "function" or false,
        hasStateExit = state and type(state.Exit) == "function" or false,
        hasStateCancel = state and type(state.CancelAll) == "function" or false,
    }
end
function M.SetMSUFEditModeActive(active, unitKey, opts)
    opts = opts or {}
    active = active and true or false
    local before = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if before.active == active then return true, active and "already_enabled" or "already_disabled", before end
    if active and before.combatLocked then
        if type(_G.MSUF_ShowConfigCombatLockMessage) == "function" then
            _G.MSUF_ShowConfigCombatLockMessage()
        elseif type(M.ShowConfigCombatLockMessage) == "function" then
            M.ShowConfigCombatLockMessage()
        end
        return false, "combat_locked", before
    end
    local fn = rawget(_G, "MSUF_SetMSUFEditModeDirect") or rawget(_G, "MSUF_SetEditMode")
    if type(fn) == "function" then
        local result = fn(active, unitKey)
        if result == false then return false, "helper_failed", before end
        RefreshEditModeSurfaces()
        local after = M.EditModeLifecycleStatus(opts.includeBlizzard)
        if after.active == active then return true, active and "enabled" or "disabled", after end
        return false, "helper_failed", after
    end
    local state = EditModeState()
    if active and state and type(state.Enter) == "function" then
        state.Enter(unitKey)
    elseif (not active) and state and type(state.Exit) == "function" then
        state.Exit(opts.source or "msuf2_menu")
    else
        return false, active and "missing_enter_helper" or "missing_exit_helper", before
    end
    RefreshEditModeSurfaces()
    local after = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if after.active == active then return true, active and "enabled" or "disabled", after end
    return false, "helper_failed", after
end
function M.CancelMSUFEditMode(opts)
    opts = opts or {}
    local before = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if not before.active then return true, "already_disabled", before end
    local state = EditModeState()
    if not (state and type(state.CancelAll) == "function") then return false, "missing_cancel_helper", before end
    local result = state.CancelAll()
    if result == false then return false, "helper_failed", before end
    RefreshEditModeSurfaces()
    local after = M.EditModeLifecycleStatus(opts.includeBlizzard)
    if not after.active then return true, "canceled", after end
    return false, "helper_failed", after
end
function M.ToggleMSUFEditMode(unitKey, opts)
    opts = opts or {}
    local status = M.EditModeLifecycleStatus(opts.includeBlizzard)
    return M.SetMSUFEditModeActive(not status.active, unitKey, opts)
end
function M.TrackRefresh(ctx, refresh)
    if type(refresh) ~= "function" then return nil end
    if type(M.AddRefresher) == "function" then M.AddRefresher(ctx, refresh) end
    if ctx and (
        ctx._msuf2Building == true
        or (ctx.entry and ctx.entry._msuf2Building == true)
        or (ctx.hiddenBuild == true)
        or (ctx.entry and ctx.entry.hiddenBuild == true)
    ) then return refresh end
    refresh()
    return refresh
end
function M.TrackCollapsibleRefresh(ctx, section, refresh)
    refresh = M.TrackRefresh(ctx, refresh)
    local entry = section and section._msuf2CollapsibleEntry
    if entry then
        entry._msuf2RefreshState = refresh
        entry._msuf2TrackedRefreshState = refresh
    end
    return refresh
end
function M.TrackMethodRefresh(ctx, object, method)
    return M.TrackRefresh(ctx, function()
        local fn = object and object[method]; if type(fn) == "function" then return fn(object) end
    end)
end
local tips = {}
for tip in ([[
Bigger steps: Hold SHIFT while adjusting sliders to change values faster.|Fine tuning: Hold CTRL while adjusting sliders for smaller steps.|Quick reset: If something feels off, try /msuf reset for frame positions.|Factory reset: Use Menu > Advanced > Factory Reset or /msuf fullreset confirm + /reload.|Edit Mode: Use Toggle Edit Mode to move frames quickly, then fine-tune with the position popup.
Profiles safety: Create a new profile before big experiments so you can switch back instantly.|Colors: The Colors tab lets you customize fonts, bars, castbars and highlights.|Gameplay: The Gameplay tab contains extra UI tools and warnings you can enable or disable.|Recommended: Sensei Resource Bar pairs well with MSUF for clean resource tracking.|UI scale tip: MSUF has its own UI scale, separate from Blizzard global UI scale.
Troubleshoot: If visuals do not update, a quick /reload fixes most UI state issues.|Readability: Slightly larger fonts often help more than bigger frames.|During development of MSUF Unhalted, R41z0r and other addon developers helped out.|Danders is a strong Party/Raidframe addon and works well with MSUF.|Community: If you like MSUF, share it with a friend.
]]):gmatch("[^|]+") do
    tips[#tips + 1] = (tip:gsub("^%s+", ""):gsub("%s+$", ""))
end
local function GetNextTip()
    local g = EnsureGeneral()
    local count = #tips
    if count == 0 then return nil, 0, 0 end
    local index = tonumber(g.tipCycleIndex) or 1
    index = floor(index)
    if index < 1 or index > count then index = 1 end
    local tip = tips[index]
    local nextIndex = index + 1
    if nextIndex > count then nextIndex = 1 end
    g.tipCycleIndex = nextIndex
    return tip, index, count
end
ExportPublic("MSUF_GetNextTip", GetNextTip)
local pendingReloadRecommendedLabel
local function ShowReloadRecommendedPopup(label)
    if BlockConfigCombatLocked(false) then return end
    if not _G.StaticPopupDialogs then return end
    pendingReloadRecommendedLabel = tostring(label or "")
    if pendingReloadRecommendedLabel == "" then pendingReloadRecommendedLabel = "these changes" end
    pendingReloadRecommendedLabel = Tr(pendingReloadRecommendedLabel)
    M.InstallStaticPopup("MSUF_RELOAD_RECOMMENDED", {
        text = Tr("MSUF recommends reloading the UI to ensure all changes apply correctly.\n\nApply: %s\n\nReload now?"),
        button1 = _G.RELOAD or Tr("Reload"),
        button2 = _G.CANCEL or Tr("Not now"),
        OnAccept = function()
            pendingReloadRecommendedLabel = nil
            if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
        end,
        OnCancel = function() pendingReloadRecommendedLabel = nil end,
    })
    _G.StaticPopup_Show("MSUF_RELOAD_RECOMMENDED", pendingReloadRecommendedLabel)
end
ExportPublic("MSUF_ShowReloadRecommendedPopup", ShowReloadRecommendedPopup)
local function ShowGroupFrameReloadRequiredPopup()
    if not (_G.StaticPopupDialogs and _G.StaticPopup_Show) then
        if _G.print then _G.print(Tr("|cffffd700MSUF:|r Group frames were enabled or disabled. Reload the UI with /reload.")) end
        return
    end
    M.InstallStaticPopup("MSUF2_GROUPFRAMES_RELOAD_REQUIRED", {
        text = Tr("Group frames were enabled or disabled.\n\nA UI reload is required to fully apply this change.\n\nReload now?"),
        button1 = _G.RELOAD or Tr("Reload"),
        button2 = _G.CANCEL or Tr("Not now"),
        hideOnEscape = false,
        OnAccept = function()
            if _G.InCombatLockdown and _G.InCombatLockdown() then
                if _G.print then _G.print(Tr("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload.")) end
                return
            end
            if type(_G.ReloadUI) == "function" then _G.ReloadUI() end
        end,
    })
    _G.StaticPopup_Show("MSUF2_GROUPFRAMES_RELOAD_REQUIRED")
end
ExportPublic("MSUF_ShowGroupFrameReloadRequiredPopup", ShowGroupFrameReloadRequiredPopup)
local copyLinkPopup
local copyLinkPopupSerial = 0
function M.HideMenuCopyLinkPopup()
    if copyLinkPopup and copyLinkPopup.Hide then copyLinkPopup:Hide() end
end
local function EnsureCopyLinkPopup()
    if not _G.CreateFrame then return nil end
    if copyLinkPopup then
        copyLinkPopup:Hide()
        copyLinkPopup = nil
    end
    copyLinkPopupSerial = copyLinkPopupSerial + 1
    local frame = _G.CreateFrame("Frame", "MSUF_CopyLinkPopup" .. tostring(copyLinkPopupSerial), _G.UIParent, "BackdropTemplate")
    frame:SetSize(420, 152)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface/Tooltips/UI-Tooltip-Background",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 16,
            edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        frame:SetBackdropColor(0, 0, 0, 0.90)
        frame:SetBackdropBorderColor(0.10, 0.10, 0.10, 0.90)
    end
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText(Tr("Link"))
    if M.Theme and M.Theme.StyleFontString then M.Theme.StyleFontString(title, M.Theme.colors and M.Theme.colors.text or { 1, 1, 1, 1 }, 1) end
    frame._msufTitleFS = title
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
    hint:SetText(Tr("Press Ctrl+C to copy:"))
    hint:SetTextColor(0.90, 0.90, 0.90, 1)
    if M.Theme and M.Theme.StyleFontString then M.Theme.StyleFontString(hint, M.Theme.colors and M.Theme.colors.text or { 0.90, 0.90, 0.90, 1 }, 0) end
    local editBox = _G.CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetSize(360, 32)
    editBox:SetPoint("TOP", hint, "BOTTOM", 0, -12)
    if editBox.SetTextInsets then editBox:SetTextInsets(8, 8, 0, 0) end
    if M.Theme and M.Theme.SkinEditBox then M.Theme.SkinEditBox(editBox) end
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnEnterPressed", function() frame:Hide() end)
    frame._msufEditBox = editBox
    local ok = _G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ok:EnableMouse(true)
    ok:Enable()
    ok:SetSize(120, 24)
    ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    ok:SetText(_G.OKAY or Tr("Okay"))
    ok:RegisterForClicks("LeftButtonUp")
    ok:SetScript("OnClick", function() frame:Hide() end)
    frame._msufOkButton = ok
    if type(_G.MSUF_SkinButton) == "function" then _G.MSUF_SkinButton(ok) end
    frame:SetScript("OnShow", function(self)
        if self._msufTitleFS then self._msufTitleFS:SetText(Tr(self._msufTitle or "Link")) end
        if self._msufEditBox then
            self._msufEditBox:SetText(self._msufUrl or "")
            self._msufEditBox:HighlightText()
            self._msufEditBox:SetFocus()
        end
    end)
    frame:SetScript("OnHide", function(self)
        if self._msufEditBox then
            self._msufEditBox:SetText("")
            self._msufEditBox:ClearFocus()
        end
        if copyLinkPopup == self then copyLinkPopup = nil end
        self._msufTitle = nil
        self._msufUrl = nil
    end)
    frame:Hide()
    copyLinkPopup = frame
    return frame
end
local function ShowCopyLink(title, url)
    local frame = EnsureCopyLinkPopup()
    if not frame then return end
    if frame.SetFrameStrata then frame:SetFrameStrata("FULLSCREEN_DIALOG") end
    if frame.SetFrameLevel then frame:SetFrameLevel(100) end
    frame._msufTitle = tostring(title or "Link")
    frame._msufUrl = tostring(url or "")
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", _G.UIParent, "CENTER", 0, 0)
    frame:Show()
    if frame.Raise then frame:Raise() end
    if frame._msufEditBox and frame._msufEditBox.EnableMouse then frame._msufEditBox:EnableMouse(true) end
    if frame._msufEditBox and frame._msufEditBox.SetFocus then frame._msufEditBox:SetFocus() end
    if frame._msufEditBox and frame._msufEditBox.HighlightText then frame._msufEditBox:HighlightText() end
    if frame._msufOkButton and frame._msufOkButton.EnableMouse then frame._msufOkButton:EnableMouse(true) end
    if frame._msufOkButton and frame._msufOkButton.Enable then frame._msufOkButton:Enable() end
    if frame._msufOkButton and frame._msufOkButton.Raise then frame._msufOkButton:Raise() end
end
ExportPublic("MSUF_ShowCopyLink", ShowCopyLink)
do
    local version = _G.C_AddOns and _G.C_AddOns.GetAddOnMetadata
        and _G.C_AddOns.GetAddOnMetadata(addonName or "MidnightSimpleUnitFrames", "Version")
    local isAlpha = type(version) == "string" and version:lower():find("alpha", 1, true) ~= nil
    if isAlpha then
        M.InstallStaticPopup("MSUF_ALPHA_DISCORD", {
            text = Tr("|cffb088f0MSUF Alpha Build|r\n\nThis is an early Alpha version.\nPlease report bugs and share feedback on our Discord!\n\n|cff7289dahttps://discord.gg/2Gf9b2Wprz|r"),
            button1 = Tr("Copy Discord Link"),
            button2 = _G.CLOSE or Tr("Close"),
            OnAccept = function()
                if type(_G.MSUF_ShowCopyLink) == "function" then _G.MSUF_ShowCopyLink("Discord", "https://discord.gg/2Gf9b2Wprz") end
            end,
        })
    end
end
