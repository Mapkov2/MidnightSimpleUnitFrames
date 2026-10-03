local PixelLayoutRegion = _G.MSUF_PixelLayoutRegion or function(region, policy, ...) if type(policy) == "string" then return region[policy](region, ...) end return region end
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
local ExportPublic = MSUF.ExportPublic
local unpack = table.unpack or unpack
local floor = math.floor

local function Clamp(value, minValue, maxValue)
    value = tonumber(value) or minValue
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end
local Tr = MSUF.Translate
M.TranslateText = Tr
-- The core (Kernel/MSUF_Util.lua) owns the combat lock and its throttled,
-- translated message, and publishes both on MSUF.Public before the Options
-- package can load. A handler running for a combat event passes the event:
-- at PLAYER_REGEN_DISABLED the lockdown has not started yet.
local function IsConfigCombatLocked(event)
    return MSUF.Public.IsConfigCombatLocked(event) and true or false
end
local function ShowConfigCombatLockMessage()
    return MSUF.Public.ShowConfigCombatLockMessage()
end
local function BlockConfigCombatLocked(silent)
    if not IsConfigCombatLocked() then return false end
    if not silent then ShowConfigCombatLockMessage() end
    return true
end
M.IsConfigCombatLocked = M.IsConfigCombatLocked or IsConfigCombatLocked
M.ShowConfigCombatLockMessage = ShowConfigCombatLockMessage
-- A menu file lists the core functions it calls by their global names. Each
-- must exist when the file loads: the core loads before this load-on-demand
-- addon on every client, so a missing one is a wiring bug and MSUF.Require
-- raises naming the file. The calls still go through _G, so a hook installed
-- on the global later applies.
function M.RequireGlobals(context, names)
    local Require = MSUF.Require
    for i = 1, #names do Require(names[i], context) end
end

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
-- Transient chrome (the status and history feedback lines) fades out
-- on a MenuTimer task. Quiesce cancels every task, so each owner registers how
-- its chrome settles at once; nothing stale waits for the next open.
local quiesceSettlers = {}
function Runtime:SetQuiesceSettler(key, settle)
    quiesceSettlers[key] = settle
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
    local function Run(...)
        if not task.active then return end
        task.active = false
        menuRuntimeTasks[task] = nil
        if generation ~= menuRuntimeGeneration or IsConfigCombatLocked() then return end
        return callback(...)
    end
    -- The supported client returns a cancellable timer. Register the task only
    -- after native scheduling succeeds, so an error cannot strand pending work.
    task.timer = rawTimerAPI.NewTimer(delay, Run)
    menuRuntimeTasks[task] = true
    return task
end

local MenuTimer = {}
function MenuTimer.After(delay, callback)
    return Runtime:Schedule(delay, callback, "C_Timer.After")
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
    return true
end
function Runtime:Quiesce(reason, event)
    reason = tostring(reason or "menu-hide")
    local combat = IsConfigCombatLocked(event)
    self.active = false
    self:CancelPendingTasks(reason)
    if type(self._quiesceScale) == "function" then self._quiesceScale(combat) end
    local apply = M.ApplyService
    if apply and type(apply.Quiesce) == "function" then apply.Quiesce(combat) end
    local search = M.SearchBridge
    if search and type(search.CancelSearchBackgroundIndex) == "function" then search.CancelSearchBackgroundIndex() end
    local theme = M.Theme
    if theme and type(theme.StopAllMenuAnimations) == "function" then theme.StopAllMenuAnimations() end
    for _, settle in pairs(quiesceSettlers) do settle(reason) end
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
    -- The first explicit tooltip claims the widget, so the search layer's
    -- automatic help tooltip never doubles it; an automatic one yields to a
    -- later explicit call (its handler then stays silent).
    if opts.autoHelp then
        widget._msuf2TooltipWired = widget._msuf2TooltipWired or "auto"
    else
        widget._msuf2TooltipWired = "manual"
    end
    local function ShowTooltip(self)
        if not _G.GameTooltip then return end
        -- A disabled control explains why; the reason rides on this tooltip.
        local Widgets = M.Widgets
        local reason = Widgets and Widgets.DisabledReasonText and Widgets.DisabledReasonText(widget)
        if opts.enabled and not opts.enabled(self) then
            if not reason then return end
            _G.GameTooltip:SetOwner(self, owner)
            local resolved = ResolveText(title, self)
            if resolved and resolved ~= "" then _G.GameTooltip:SetText(Tr(resolved), titleColor[1] or 1, titleColor[2] or 1, titleColor[3] or 1) end
            _G.GameTooltip:AddLine(reason, 1, 0.82, 0.35, true)
            _G.GameTooltip:Show()
            return
        end
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
        if resolvedBody and resolvedBody ~= "" then _G.GameTooltip:AddLine(Tr(resolvedBody), bodyColor[1] or 0.80, bodyColor[2] or 0.86,
            bodyColor[3] or 1.00, true) end
        if reason then _G.GameTooltip:AddLine(reason, 1, 0.82, 0.35, true) end
        _G.GameTooltip:Show()
    end
    local function HideTooltip()
        if _G.GameTooltip then _G.GameTooltip:Hide() end
    end
    local function Wire(target)
        target._msuf2TooltipTarget = true
        if opts.hook and target.HookScript then
            target:HookScript("OnEnter", ShowTooltip)
            target:HookScript("OnLeave", HideTooltip)
        elseif target.SetScript then
            target:SetScript("OnEnter", ShowTooltip)
            target:SetScript("OnLeave", HideTooltip)
        end
    end
    Wire(widget)
    if opts.labelHit and widget._msuf2LabelHit and widget._msuf2LabelHit ~= widget then
        if opts.labelHitWhenDisabled then
            widget._msuf2KeepLabelHitMouseWhenDisabled = true
            if widget._msuf2LabelHit.EnableMouse then
                widget._msuf2LabelHit._msuf2MouseEnabledStateApplied = true
                widget._msuf2LabelHit:EnableMouse(true)
            end
        end
        Wire(widget._msuf2LabelHit)
    end
    return widget
end
ExportPublic("MSUF_AddTooltip", _G.MSUF_AddTooltip or AddTooltip)
M.AddTooltip = M.AddTooltip or AddTooltip
--- AddTooltip for any control kind: a segment's option buttons sit on top of
--- its holder and catch the mouse, so they carry the same tooltip.
function M.AddControlTooltip(control, title, body, opts)
    if not control then return control end
    AddTooltip(control, title, body, opts)
    if control._msuf2ControlKind == "segment" and type(control.buttons) == "table" then
        for i = 1, #control.buttons do AddTooltip(control.buttons[i], title, body, opts) end
    end
    return control
end
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

-- The nudge owner, its arrow buttons and the "active box" slot are dynamic
-- globals on purpose, not a template-name convenience: SetOverrideBindingClick
-- addresses the SecureActionButtonTemplate buttons by global name, each
-- button's OnClick resolves its target through _G[spec.activeName], and the
-- preview views read the same literal global (MSUF_UFPreview_ActiveNudgeBox)
-- in their getActive fallback. Routing the slot through a table on M would
-- leave those readers stale, so the names stay spec-driven and global.
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
        owner = PixelLayoutRegion(CreateFrame("Frame", ownerName, UIParent))
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
            btn = PixelLayoutRegion(CreateFrame("Button", btnName, owner, "SecureActionButtonTemplate"))
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
-- StaticPopup_Show puts every dialog on DIALOG (StaticPopup_SetUpPosition), the
-- menu's normal strata. In MSUF Edit Mode the window sits higher (Window
-- priority), so a menu prompt would open behind it: lift it to the window's
-- strata. The next StaticPopup_Show of that dialog frame resets it to DIALOG.
local STRATA_RANK = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5,
    FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function RaisePopupOverMenuWindow(dialog)
    local window = M.frame
    if not (dialog and dialog.SetFrameStrata and dialog.GetFrameStrata and window and window.IsShown
        and window:IsShown() and window.GetFrameStrata) then return end
    local strata = window:GetFrameStrata()
    if (STRATA_RANK[strata] or 0) <= (STRATA_RANK[dialog:GetFrameStrata()] or 0) then return end
    dialog:SetFrameStrata(strata)
    if dialog.Raise then dialog:Raise() end
end
-- Menu prompts. Nothing here writes Blizzard's StaticPopupDialogs: the one
-- prompt layer is the core's (Shell/UI/MSUF_Widgets.lua, MSUF.UI.ShowPrompt,
-- which also documents the spec). The menu passes its look: the menu popup
-- panel and priority for the owned frame, and a generic dialog lifted over the
-- menu window.
local PROMPT_STYLE = {
    panel = function(parent) return M.CreateMenuPopupPanel(parent) end,
    text = function(text)
        if M.Theme and M.Theme.StyleFontString then M.Theme.StyleFontString(text, M.Theme.colors and M.Theme.colors.text or { 1, 1, 1, 1 }, 0) end
    end,
    priority = function(frame) M.ApplyPopupFramePriority(frame) end,
    raise = RaisePopupOverMenuWindow,
}
--- Shows the prompt for `key` and returns its frame.
function M.ShowPrompt(key, spec)
    return MSUF.UI.ShowPrompt(key, spec, PROMPT_STYLE)
end
function M.HidePrompt(key)
    return MSUF.UI.HidePrompt(key)
end
function M.IsPromptShown(key)
    return MSUF.UI.IsPromptShown(key)
end
--- Host API kept for callers outside this addon that register a named dialog
--- and call StaticPopup_Show themselves: the MSUF Suite's page-reset, copy-bars
--- and run-history prompts. Without it
--- the Suite would either raise in StaticPopup_Show or run those actions
--- without asking. Nothing in the Options addon calls it (menu_prompt_ownership
--- smoke); the menu's own prompts use M.ShowPrompt.
function M.InstallStaticPopup(key, spec, defaults)
    if not (_G.StaticPopupDialogs and key and type(spec) == "table") then return nil end
    local existing = _G.StaticPopupDialogs[key]
    if existing then return existing end
    for field, value in pairs(defaults or STATIC_POPUP_DEFAULTS) do
        if spec[field] == nil then spec[field] = value end
    end
    local onShow = spec.OnShow
    spec.OnShow = function(dialog, data)
        RaisePopupOverMenuWindow(dialog)
        if onShow then return onShow(dialog, data) end
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
M.PlayerPowerSourceValues = M.ValueTextList(
    "AUTO", "Automatic (current behavior)",
    "MANA", "Mana")
M.PlayerPowerSourceSearchLabel = "Mana / Automatic displayed resource"
M.PlayerPowerSourceTooltip = "Automatic preserves the current profile behavior for the active class and specialization, including Maelstrom, Insanity, and Ebon Might hand-offs. Mana explicitly keeps Mana on the Player power bar. Vehicles always use their native resource; classes without a Mana pool keep their normal resource while the preference stays saved."
function M.NormalizePlayerPowerSource(value)
    return value == "MANA" and "MANA" or "AUTO"
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
                for prop in tostring(spec.copyProps or props):gmatch("%S+") do
                    local key = spec[prop]
                    if key then
                        out[#out + 1] = key
                    end
                end
                -- colorPrefix names a key family rather than one key, so it is
                -- expanded here: a copied text indicator has to bring its color
                -- along with its placement or the copy looks half applied.
                local colorPrefix = spec.colorPrefix
                if colorPrefix then
                    out[#out + 1] = colorPrefix .. "ColorR"
                    out[#out + 1] = colorPrefix .. "ColorG"
                    out[#out + 1] = colorPrefix .. "ColorB"
                end
                local extra = spec.copyExtra
                if extra then
                    for j = 1, #extra do
                        out[#out + 1] = extra[j]
                    end
                end
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
--- Names that a Pick call asked for but the source module never published.
--- Binding by name string means a renamed or removed helper silently becomes a
--- nil local, and the failure only surfaces much later as "attempt to call a nil
--- value" far from its cause. Every miss is recorded here and reported once, so
--- the offending name is named at bind time. The return value is unchanged (the
--- caller still receives nil), which keeps this purely diagnostic.
M.PickMissing = M.PickMissing or {}
local pickMissing = M.PickMissing
local pickMissingSeen = {}

local function NotePickMiss(name)
    if pickMissingSeen[name] then return end
    pickMissingSeen[name] = true
    pickMissing[#pickMissing + 1] = name
    local report = (MSUF and MSUF.ReportError) or _G.MSUF_ReportError
    if type(report) == "function" then
        report("Menu2", "Pick could not resolve '" .. name .. "': the source module does not publish it")
    end
end

function M.Pick(source, names)
    local values, count = {}, 0
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        count = count + 1
        local value = source[name]
        if value == nil then NotePickMiss(name) end
        values[count] = value
    end
    return unpack(values, 1, count)
end
function M.PickFallbackTable(source, fallbacks, names, target)
    target = type(target) == "table" and target or {}
    source = source or {}
    fallbacks = fallbacks or {}
    for name in tostring(names or ""):gmatch("%S+") do
        target[name] = source[name] or fallbacks[name]
    end
    return target
end
function M.Assign(target, values)
    if type(target) ~= "table" or type(values) ~= "table" then return target end
    for key, value in pairs(values) do target[key] = value end
    return target
end
function M.AppendValues(target, ...)
    if type(target) ~= "table" then
        target = {}
    end
    for i = 1, select("#", ...) do
        target[#target + 1] = select(i, ...)
    end
    return target
end
function M.AppendNamedValues(target, source, names)
    if type(target) ~= "table" then
        target = {}
    end
    source = source or {}
    for name in tostring(names or ""):gmatch("%S+") do
        target[#target + 1] = source[name]
    end
    return target
end
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
    assert(type(getValue) == "function" and type(setValue) == "function", "boolean control requires get/set owners")
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
        if refresh then return refresh() end
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
---   reason    = string | fn(control) -> string|nil
---                                  -- optional: hover text telling why `controls` are disabled.
---                                  -- Wired only while this entry holds them off; when several
---                                  -- entries disable one control, the first (most general) wins.
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
    -- One reusable scratch map (control -> reason or false) per group, filled
    -- during a refresh and applied once at its end: no per-refresh tables.
    local pendingReasons
    for i = 1, #entries do
        if entries[i].reason ~= nil then
            pendingReasons = {}
            break
        end
    end
    local function noteReason(control, reason)
        if not control then return end
        local current = pendingReasons[control]
        if reason then
            if not current then pendingReasons[control] = reason end
        elseif current == nil then
            pendingReasons[control] = false
        end
    end
    local function noteReasons(target, reason)
        if type(target) == "table" and target[1] ~= nil and not target.GetObjectType then
            for i = 1, #target do noteReason(target[i], reason) end
        else
            noteReason(target, reason)
        end
    end
    local function refresh()
        local cfg
        if source then cfg = source() end
        for i = 1, #entries do
            local e = entries[i]
            if (not e.when) or e.when(cfg) then
                if e.enable then setEnabled(e.enable, not e.enableOn or not not e.enableOn(cfg)) end
                if e.controls then
                    local on = e.on and (e.on(cfg) and true or false) or false
                    setEnabled(e.controls, on)
                    if e.reason ~= nil then noteReasons(e.controls, (not on) and e.reason or false) end
                end
            end
        end
        if opts.override then opts.override(cfg, setEnabled) end
        if pendingReasons and W.SetControlDisabledReason then
            for control, reason in pairs(pendingReasons) do
                W.SetControlDisabledReason(control, reason or nil)
                pendingReasons[control] = nil
            end
        end
        if opts.also then opts.also() end
    end
    if opts.noTrack then return refresh end
    if opts.track then return opts.track(ctx, refresh) or refresh end
    return M.TrackRefresh(ctx, refresh)
end
function M.RequestOrRefresh(ctx, reason)
    return M.RequestRefresh(ctx, reason)
end
function M.NormalizeHpMode(mode)
    if mode == nil then return "CURPERCENT" end
    if mode == "FULL_ONLY" then return "CURRENT" end
    if mode == "PERCENT_ONLY" then return "PERCENT" end
    if mode == "FULL_PLUS_PERCENT" then return "CURPERCENT" end
    if mode == "PERCENT_PLUS_FULL" then return "PERCENTCUR" end
    return mode
end
function M.NormalizePowerMode(mode)
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
    return _G.MSUF_GetPlayerSpecID()
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
            if class and (tonumber(g.nameplateMeleeSpellIDByClass[class])
                or 0) <= 0 then g.nameplateMeleeSpellIDByClass[class] = M.GetGameplayMeleeSpellID(g) end
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
--- `text` cut to at most `limit` UTF-8 characters, ending in "..." when it was
--- cut; a multi-byte character is never split.
function M.ShortenUtf8(text, limit)
    text = tostring(text or "")
    if M.TruncateUtf8Chars(text, limit) == text then return text end
    return M.TruncateUtf8Chars(text, math.max(1, limit - 3)) .. "..."
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
    local panel = PixelLayoutRegion(CreateFrame("Frame", opts.name, parent, opts.template or (theme.Template and theme.Template() or nil)))
    local bg = opts.bg or colors.glassPopup or { 0.014, 0.024, 0.050, 0.985 }
    local border = opts.border or { 0.10, 0.22, 0.44, 0.80 }
    if panel.SetBackdrop then
        PixelLayoutRegion(panel, "SetBackdrop", {
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        panel:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 0.985)
        panel:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 0.80)
    else
        local fill = PixelLayoutRegion(panel:CreateTexture(nil, "BACKGROUND"))
        fill:SetAllPoints()
        fill:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 0.985)
        local edge = PixelLayoutRegion(panel:CreateTexture(nil, "BORDER"))
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
    local fn = rawget(_G, "MSUF_IsInEditMode")
        or (includeBlizzard and rawget(_G, "IsEditModeActive") or nil)
    if type(fn) == "function" then
        return fn() and true or false
    end
    return rawget(_G, "MSUF_UnitEditModeActive") == true
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
    local setFn = rawget(_G, "MSUF_SetMSUFEditModeDirect")
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
    local fn = rawget(_G, "MSUF_SetMSUFEditModeDirect")
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
Bigger steps: Hold SHIFT while adjusting sliders to change values faster.|Fine tuning: Hold CTRL while adjusting sliders for smaller steps.|Quick reset: If something feels off, try /msuf reset for frame positions.|Factory reset: Use Dashboard > Display & recovery > MSUF Factory Reset or /msuf fullreset confirm + /reload.|Edit Mode: Use Toggle Edit Mode to move frames quickly, then fine-tune with the position popup.
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
    pendingReloadRecommendedLabel = tostring(label or "")
    if pendingReloadRecommendedLabel == "" then pendingReloadRecommendedLabel = "these changes" end
    pendingReloadRecommendedLabel = Tr(pendingReloadRecommendedLabel)
    M.ShowPrompt("MSUF_RELOAD_RECOMMENDED", {
        text = string.format(Tr("MSUF recommends reloading the UI to ensure all changes apply correctly.\n\nApply: %s\n\nReload now?"),
            pendingReloadRecommendedLabel),
        accept = RELOAD or Tr("Reload"),
        cancel = CANCEL or Tr("Not now"),
        onAccept = function()
            pendingReloadRecommendedLabel = nil
            ReloadUI()
        end,
        onCancel = function() pendingReloadRecommendedLabel = nil end,
    })
end
ExportPublic("MSUF_ShowReloadRecommendedPopup", ShowReloadRecommendedPopup)
-- Escape does not answer it: a menu-owned prompt (M.ShowPrompt).
local function ShowGroupFrameReloadRequiredPopup()
    return M.ShowPrompt("MSUF2_GROUPFRAMES_RELOAD_REQUIRED", {
        text = Tr("Group frames were enabled or disabled.\n\nA UI reload is required to fully apply this change.\n\nReload now?"),
        accept = RELOAD or Tr("Reload"),
        cancel = CANCEL or Tr("Not now"),
        hideOnEscape = false,
        onAccept = function()
            if InCombatLockdown() then
                print(Tr("|cffff5555MSUF|r: Can't reload UI in combat. Leave combat, then type /reload."))
                return
            end
            ReloadUI()
        end,
    })
end
ExportPublic("MSUF_ShowGroupFrameReloadRequiredPopup", ShowGroupFrameReloadRequiredPopup)
-- One popup for every link: frames are never freed, and a new named frame,
-- edit box and button per click used to leak a global each time.
local copyLinkPopup
function M.HideMenuCopyLinkPopup()
    if copyLinkPopup and copyLinkPopup.Hide then copyLinkPopup:Hide() end
end
local function EnsureCopyLinkPopup()
    if copyLinkPopup then return copyLinkPopup end
    if not _G.CreateFrame then return nil end
    local frame = PixelLayoutRegion(_G.CreateFrame("Frame", "MSUF_CopyLinkPopup", _G.UIParent, "BackdropTemplate"))
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
        PixelLayoutRegion(frame, "SetBackdrop", {
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
    local title = PixelLayoutRegion(frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"))
    title:SetPoint("TOP", frame, "TOP", 0, -16)
    title:SetText(Tr("Link"))
    if M.Theme and M.Theme.StyleFontString then M.Theme.StyleFontString(title, M.Theme.colors and M.Theme.colors.text or { 1, 1, 1, 1 }, 1) end
    frame._msufTitleFS = title
    local hint = PixelLayoutRegion(frame:CreateFontString(nil, "OVERLAY", "GameFontNormal"))
    hint:SetPoint("TOP", title, "BOTTOM", 0, -8)
    hint:SetText(Tr("Press Ctrl+C to copy:"))
    hint:SetTextColor(0.90, 0.90, 0.90, 1)
    if M.Theme and M.Theme.StyleFontString then M.Theme.StyleFontString(hint, M.Theme.colors and M.Theme.colors.text or { 0.90, 0.90, 0.90, 1 }, 0) end
    local editBox = PixelLayoutRegion(_G.CreateFrame("EditBox", nil, frame, "InputBoxTemplate"))
    editBox:EnableMouse(true)
    editBox:SetAutoFocus(false)
    editBox:SetSize(360, 32)
    editBox:SetPoint("TOP", hint, "BOTTOM", 0, -12)
    if editBox.SetTextInsets then editBox:SetTextInsets(8, 8, 0, 0) end
    if M.Theme and M.Theme.SkinEditBox then M.Theme.SkinEditBox(editBox) end
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    editBox:SetScript("OnEnterPressed", function() frame:Hide() end)
    frame._msufEditBox = editBox
    local ok = PixelLayoutRegion(_G.CreateFrame("Button", nil, frame, "UIPanelButtonTemplate"))
    ok:EnableMouse(true)
    ok:Enable()
    ok:SetSize(120, 24)
    ok:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    ok:SetText(_G.OKAY or Tr("Okay"))
    ok:RegisterForClicks("LeftButtonUp")
    ok:SetScript("OnClick", function() frame:Hide() end)
    frame._msufOkButton = ok
    _G.MSUF_SkinButton(ok)
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
    -- A shown popup is hidden first, so OnShow fills in the new link.
    if frame.IsShown and frame:IsShown() then frame:Hide() end
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
-- The alpha-build notice. Alpha builds used to register it as the named dialog
-- MSUF_ALPHA_DISCORD, which nothing ever showed (no StaticPopup_Show of it in
-- Classic, Retail or the Suite, nor in their history). It is a prompt now and
-- stays unwired, as before; showing it on alpha builds is the owner's call.
-- One shared accessor, MSUF.GetAddonVersion from Game/Shared/Initialize.lua:
-- the core resolves it once from the TOC this client loaded, so the Options
-- package never reports its own "## Version" here.
function M.ShowAlphaDiscordPrompt()
    local getVersion = MSUF.GetAddonVersion
    local version = type(getVersion) == "function" and getVersion() or nil
    if not (type(version) == "string" and version:lower():find("alpha", 1, true)) then return nil end
    return M.ShowPrompt("MSUF_ALPHA_DISCORD", {
        text = Tr("|cffb088f0MSUF Alpha Build|r\n\nThis is an early Alpha version.\nPlease report bugs and share feedback on our Discord!\n\n|cff7289dahttps://discord.gg/2Gf9b2Wprz|r"),
        accept = Tr("Copy Discord Link"),
        cancel = CLOSE or Tr("Close"),
        onAccept = function() ShowCopyLink("Discord", "https://discord.gg/2Gf9b2Wprz") end,
    })
end

local function PlayerDisplayName()
    local name
    if type(_G.UnitName) == "function" then
        name = _G.UnitName("player")
    end
    if type(_G.issecretvalue) == "function" and _G.issecretvalue(name) then name = nil end
    if type(name) == "string" then name = name:match("^[^-]+") else name = nil end
    if not name or name == "" or name == "Unknown" then name = M.Tr("Player") end
    return name
end
M.PlayerDisplayName = PlayerDisplayName

local function TrimText(text)
    text = tostring(text or "")
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end
M.TrimText = TrimText

-- Registration-time lookup only; delayed builders keep their own page owner.
function M.FindPageEntry(widget)
    while widget do
        local entry = widget._msuf2PageEntry
        if entry then return entry end
        widget = widget.GetParent and widget:GetParent()
    end
end
function M.PageKeyForWidget(widget)
    local entry = M.FindPageEntry(widget)
    return entry and entry.key
end

function M.CreateGuidedCopyOpener(copyPopup, copy)
    return function()
        local popup = copyPopup and copyPopup.GetPopup and copyPopup.GetPopup()
        if popup and popup.IsShown and popup:IsShown() then return true end
        if copyPopup then copyPopup.Show(copy) end
        popup = copyPopup and copyPopup.GetPopup and copyPopup.GetPopup()
        return popup and popup.IsShown and popup:IsShown() or false
    end
end
