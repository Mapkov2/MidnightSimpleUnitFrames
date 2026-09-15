-- arena_editmode_exit_restore_smoke.lua
-- Behavioural smoke for the owner-reported defect "a basic template of the
-- arena frames stays stuck on screen after leaving MSUF Edit Mode".
--
-- Loads the real Edit Mode state machine (Core + Movers), the real
-- LoadConditions arena preview owner, the ArenaMatch prep display, the arena
-- castbar preview module and ArenaTrinkets against a modelled secure state
-- driver (RegisterStateDriver / RegisterUnitWatch resolution with combat
-- lockdown). Every scenario boots a fresh load, snapshots it, enters and leaves
-- Edit Mode, and requires every arena frame and preview element to match the
-- fresh-load snapshot again (shown state, alpha, mouse, synthetic preview/prep
-- ownership, visibility owner, castbar preview, trinket holder, preview gates).
--
-- The arena roster is read from the engine's arena config-key fan-out and the
-- LoadConditions preview roster, so a later raise from 3 to 5 opponents is
-- iterated automatically instead of being hard-coded here.
--
-- Run from the repository root:
--   lua .github/scripts/auras3_test_driver.lua tools/tests/arena_editmode_exit_restore_smoke.lua <repoRoot> [flavor|all] [scenario]

local root = tostring((arg and arg[1]) or "."):gsub("\\", "/"):gsub("/+$", "")
if root == "" then root = "." end
local ONLY_FLAVOR = arg and arg[2]
local ONLY_SCENARIO = arg and arg[3]
local FLAVORS = { "Mainline", "TBC", "Mists" }
-- Client arena slot fact (Game/Shared/Initialize.lua MSUF_MAX_ARENA_FRAMES).
local FLAVOR_ARENA_SLOTS = { Mainline = 3, TBC = 5, Mists = 5 }

local function Check(ok, message)
    if not ok then error(message, 2) end
end

local function Path(relative)
    return root .. "/" .. relative
end

local function Read(relative)
    local handle = assert(io.open(Path(relative), "rb"), "missing file: " .. relative)
    local source = handle:read("*a")
    handle:close()
    return (source:gsub("\r\n", "\n"))
end

local FILES = {
    loadConditions = "MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_LoadConditions.lua",
    editCore = "MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Core.lua",
    editMovers = "MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Movers.lua",
    arenaMatch = "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaMatch.lua",
    arenaTrinkets = "MidnightSimpleUnitFrames/Features/Gameplay/MSUF_Feature_ArenaTrinkets.lua",
    arenaCastbarPreview = "MidnightSimpleUnitFrames/Castbars/MSUF_ArenaCastbars_Preview.lua",
    metadata = "MidnightSimpleUnitFrames/Libs/MSUFUnitFrames/MSUF_UF_Metadata.lua",
}

local function ArenaRoster()
    local count = 0
    local metadata = Read(FILES.metadata)
    for block in metadata:gmatch("arena%s*=%s*(%b{})") do
        if block:find('"arena1"', 1, true) then
            for index in block:gmatch('"arena(%d+)"') do
                count = math.max(count, tonumber(index))
            end
        end
    end
    local loadConditions = Read(FILES.loadConditions)
    local previewUnits = loadConditions:match("local ARENA_PREVIEW_UNITS%s*=%s*(%b{})")
    Check(previewUnits ~= nil, "could not read the LoadConditions arena preview roster")
    for index in previewUnits:gmatch("arena(%d+)%s*=%s*true") do
        count = math.max(count, tonumber(index))
    end
    Check(count >= 1, "could not read the engine arena roster")
    return count
end

local BASE_GLOBALS = {}
for key in pairs(_G) do BASE_GLOBALS[key] = true end

local function ResetGlobals()
    local extra = {}
    for key in pairs(_G) do
        if not BASE_GLOBALS[key] then extra[#extra + 1] = key end
    end
    for index = 1, #extra do _G[extra[index]] = nil end
end

--------------------------------------------------------------------------------
-- World model
--------------------------------------------------------------------------------

local function NewWorld(flavor, roster)
    ResetGlobals()
    local W = {
        flavor = flavor,
        roster = roster,
        now = 0,
        seq = 0,
        timers = {},
        combat = false,
        liveUnits = {},
        violations = {},
        eventFrames = {},
        bus = {},
        drivers = {},
        watches = {},
        secureDepth = 0,
        matchState = 0,
        inArena = false,
        prepSpecs = 0,
        auraRefreshes = 0,
    }

    local function Violation(message)
        W.violations[#W.violations + 1] = message
    end

    local function ProtectedWrite(widget, what)
        if widget._protected and W.combat and W.secureDepth == 0 then
            Violation(what .. " on protected " .. tostring(widget._name) .. " during combat lockdown")
        end
    end

    local Methods = {}
    local WidgetMeta = { __index = Methods }
    local function Widget(name, protected, parent)
        local widget = setmetatable({
            _name = name,
            _protected = protected == true,
            _shown = true,
            _alpha = 1,
            _mouse = false,
            _parent = parent,
            _scripts = {},
            _attributes = {},
        }, WidgetMeta)
        if type(name) == "string" then _G[name] = widget end
        return widget
    end
    W.Widget = Widget

    function Methods:Show() ProtectedWrite(self, "Show"); self._shown = true end
    function Methods:Hide() ProtectedWrite(self, "Hide"); self._shown = false end
    function Methods:SetShown(shown) if shown then self:Show() else self:Hide() end end
    function Methods:IsShown() return self._shown == true end
    function Methods:IsVisible() return self._shown == true end
    function Methods:SetAlpha(alpha) self._alpha = alpha end
    function Methods:GetAlpha() return self._alpha end
    function Methods:EnableMouse(enabled) ProtectedWrite(self, "EnableMouse"); self._mouse = enabled and true or false end
    function Methods:SetPoint() ProtectedWrite(self, "SetPoint") end
    function Methods:ClearAllPoints() ProtectedWrite(self, "ClearAllPoints") end
    function Methods:SetText(text) self._text = text end
    function Methods:GetText() return self._text end
    function Methods:GetStatusBarTexture()
        self._fill = self._fill or Widget(nil, false, self)
        return self._fill
    end
    function Methods:CreateTexture() return Widget(nil, false, self) end
    function Methods:CreateFontString() return Widget(nil, false, self) end
    function Methods:SetScript(kind, fn) self._scripts[kind] = fn end
    function Methods:GetScript(kind) return self._scripts[kind] end
    function Methods:HookScript(kind, fn)
        local previous = self._scripts[kind]
        self._scripts[kind] = function(...)
            if previous then previous(...) end
            return fn(...)
        end
    end
    function Methods:RegisterEvent(event)
        self._events = self._events or {}
        self._events[event] = true
        if not self._eventListed then
            self._eventListed = true
            W.eventFrames[#W.eventFrames + 1] = self
        end
    end
    function Methods:UnregisterEvent(event) if self._events then self._events[event] = nil end end
    function Methods:UnregisterAllEvents() self._events = nil end
    function Methods:SetAttribute(key, value) self._attributes[key] = value end
    function Methods:GetAttribute(key) return self._attributes[key] end
    function Methods:GetParent() return self._parent end
    function Methods:GetName() return self._name end
    local function NoOp() end
    for _, name in ipairs({
        "SetSize", "SetWidth", "SetHeight", "SetFrameStrata", "SetFrameLevel", "SetAllPoints",
        "SetTexture", "SetTexCoord", "SetColorTexture", "SetVertexColor", "SetDrawEdge", "Clear",
        "SetCooldown", "SetMinMaxValues", "SetValue", "SetStatusBarColor", "SetTextColor",
        "SetJustifyH", "SetFont",
    }) do
        Methods[name] = NoOp
    end

    -- Secure state driver model (Blizzard_RestrictedAddOnEnvironment/SecureStateDriver.lua):
    -- a driver resolves immediately and on every manager tick; a unit watch
    -- evaluates existence immediately on registration and on every tick.
    local function UnitExistsModel(unit)
        return W.liveUnits[unit] == true
    end

    local function ParseSecureOptions(expression)
        for clause in (expression .. ";"):gmatch("([^;]*);") do
            local conditions, action = clause:match("^%s*%[([^%]]*)%]%s*(%S+)%s*$")
            if not conditions then
                action = clause:match("^%s*(%S+)%s*$")
                conditions = ""
            end
            if action then
                local ok, target = true, "target"
                for token in conditions:gmatch("[^,]+") do
                    token = token:match("^%s*(.-)%s*$")
                    if token:sub(1, 1) == "@" then
                        target = token:sub(2)
                    elseif token == "exists" then
                        ok = ok and UnitExistsModel(target)
                    elseif token == "noexists" then
                        ok = ok and not UnitExistsModel(target)
                    elseif token == "combat" then
                        ok = ok and W.combat
                    elseif token == "nocombat" then
                        ok = ok and not W.combat
                    else
                        error("secure option model does not know condition: " .. token)
                    end
                end
                if ok then return action end
            end
        end
        return nil
    end

    local function SecureSetShown(frame, shown)
        W.secureDepth = W.secureDepth + 1
        if shown then frame:Show() else frame:Hide() end
        W.secureDepth = W.secureDepth - 1
    end

    local function ResolveDriver(frame)
        local action = ParseSecureOptions(W.drivers[frame])
        if action == "show" then SecureSetShown(frame, true)
        elseif action == "hide" then SecureSetShown(frame, false) end
    end

    local function ResolveWatch(frame)
        SecureSetShown(frame, UnitExistsModel(frame.MSUFUnitKey))
    end

    local function SecureRegistrationWrite(what)
        if W.combat then Violation(what .. " from insecure code during combat lockdown") end
    end

    _G.RegisterStateDriver = function(frame, state, expression)
        Check(state == "visibility", "unexpected secure driver state: " .. tostring(state))
        SecureRegistrationWrite("RegisterStateDriver")
        W.drivers[frame] = expression
        ResolveDriver(frame)
    end
    _G.UnregisterStateDriver = function(frame, state)
        Check(state == "visibility", "unexpected secure driver removal: " .. tostring(state))
        SecureRegistrationWrite("UnregisterStateDriver")
        W.drivers[frame] = nil
    end
    _G.RegisterUnitWatch = function(frame)
        SecureRegistrationWrite("RegisterUnitWatch")
        W.watches[frame] = true
        ResolveWatch(frame)
    end
    _G.UnregisterUnitWatch = function(frame)
        SecureRegistrationWrite("UnregisterUnitWatch")
        W.watches[frame] = nil
    end
    _G.UnitWatchRegistered = function(frame) return W.watches[frame] == true end
    _G.SecureCmdOptionParse = ParseSecureOptions

    function W.SecureTick()
        for frame in pairs(W.drivers) do
            if W.watches[frame] then
                Violation("secure driver and unit watch both own " .. tostring(frame._name))
            end
            ResolveDriver(frame)
        end
        for frame in pairs(W.watches) do ResolveWatch(frame) end
    end

    function W.VisibilityOwner(frame)
        local driver, watched = W.drivers[frame], W.watches[frame] == true
        if driver and watched then return "both:" .. driver end
        if driver then return "driver:" .. driver end
        if watched then return "watch" end
        return "none"
    end

    -- Timers and events
    _G.C_Timer = {
        After = function(delay, fn)
            W.seq = W.seq + 1
            W.timers[#W.timers + 1] = { at = W.now + (tonumber(delay) or 0), seq = W.seq, fn = fn }
        end,
    }

    function W.RunTimers()
        local guard = 0
        while #W.timers > 0 do
            guard = guard + 1
            Check(guard < 5000, "timer storm while settling Edit Mode")
            local best = 1
            for index = 2, #W.timers do
                local candidate, current = W.timers[index], W.timers[best]
                if candidate.at < current.at or (candidate.at == current.at and candidate.seq < current.seq) then
                    best = index
                end
            end
            local timer = table.remove(W.timers, best)
            if timer.at > W.now then W.now = timer.at end
            timer.fn()
        end
    end

    function W.Fire(event, ...)
        local frames = W.eventFrames
        for index = 1, #frames do
            local frame = frames[index]
            local handler = frame._scripts.OnEvent
            if frame._events and frame._events[event] and handler then handler(frame, event, ...) end
        end
        local handlers = W.bus[event]
        if handlers then
            for index = 1, #handlers do handlers[index](event, ...) end
        end
    end

    _G.MSUF_EventBus_Register = function(event, _, handler)
        W.bus[event] = W.bus[event] or {}
        table.insert(W.bus[event], handler)
        return true
    end

    function W.EnterCombat()
        W.combat = true
        _G.MSUF_InCombat = true
        W.Fire("PLAYER_REGEN_DISABLED")
        W.RunTimers()
        W.SecureTick()
    end

    -- lagInCombatFlag models an MSUF_InCombat mirror that is cleared only after
    -- every PLAYER_REGEN_ENABLED handler ran (worst-case handler order).
    function W.LeaveCombat(lagInCombatFlag)
        W.combat = false
        if not lagInCombatFlag then _G.MSUF_InCombat = false end
        W.Fire("PLAYER_REGEN_ENABLED")
        _G.MSUF_InCombat = false
        W.RunTimers()
        W.SecureTick()
    end

    -- Client globals
    _G.InCombatLockdown = function() return W.combat end
    _G.UnitAffectingCombat = function(unit) return W.combat and unit == "player" end
    _G.UnitExists = function(unit) return W.liveUnits[unit] == true end
    _G.IsInInstance = function()
        if W.inArena then return true, "arena" end
        return false, "none"
    end
    _G.CreateFrame = function(_, name, parent, template)
        local protected = type(template) == "string" and template:find("Secure", 1, true) ~= nil
        return Widget(name, protected, parent)
    end
    _G.UIParent = Widget("UIParent", false)
    _G.GetTime = function() return W.now end
    -- Client fact the engine reads for arena slots (Game/Shared/Initialize.lua).
    _G.MSUF_MAX_ARENA_FRAMES = W.roster
    -- Harness screen rects for the Edit Mode mover bounds; regions without a
    -- _rect have no layout, matching an unplaced region.
    _G.MSUF_UF_FrameRectToUI = function(region)
        local rect = type(region) == "table" and region._rect
        if rect then return rect[1], rect[2], rect[3], rect[4] end
        return nil
    end
    _G.MSUF_ShowConfigCombatLockMessage = function() end

    -- Harness-only arena opponent data; the values only have to be internally
    -- consistent for the prep display path.
    _G.GetNumArenaOpponentSpecs = function() return W.prepSpecs end
    _G.GetArenaOpponentSpec = function(index)
        if index <= W.prepSpecs then return 100 + index, 2 end
        return 0, 2
    end
    _G.GetSpecializationInfoByID = function(specID)
        local token = ({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST" })[specID - 100] or "MAGE"
        return specID, "Spec" .. specID, "", 1, "DAMAGER", token, token
    end

    if flavor == "Mainline" then
        _G.C_EventUtils = { IsEventValid = function(event) return event == "PVP_MATCH_STATE_CHANGED" end }
        _G.Enum = { PvPMatchState = { Inactive = 0, Waiting = 1, StartUp = 2, Engaged = 3, PostRound = 4, Complete = 5 } }
        _G.C_PvP = {
            IsMatchConsideredArena = function() return W.inArena end,
            IsMatchActive = function() return W.inArena and W.matchState == 3 end,
            IsMatchComplete = function() return false end,
            GetActiveMatchState = function() return W.matchState end,
        }
    else
        _G.C_EventUtils = { IsEventValid = function() return false end }
        _G.IsActiveBattlefieldArena = function() return W.inArena end
    end

    _G.MSUF_DB = {
        general = { enableArenaCastbar = true },
        arena = { enabled = true, showTrinket = true },
    }

    -- Castbar preview seams owned by Castbars/MSUF_CastbarPreviews.lua.
    _G.MSUF_ShouldUseMSUFCastbar = function() return true end
    _G.MSUF_CreateCastbarPreviewFrame = function(_, name)
        local preview = Widget(name, false, _G.UIParent)
        preview.statusBar = Widget(nil, false, preview)
        preview.castTargetText = Widget(nil, false, preview)
        return preview
    end
    _G.MSUF_UpdatePlayerCastbarPreview = function()
        if not W.combat and type(_G.MSUF_UpdateArenaCastbarPreview) == "function" then
            _G.MSUF_UpdateArenaCastbarPreview()
        end
    end
    _G.MSUF_HideAllCastbarPreviews = function()
        local general = _G.MSUF_DB and _G.MSUF_DB.general
        if general then
            general.castbarPlayerPreviewEnabled = false
            general.arenaCastbarTestMode = false
        end
        if type(_G.MSUF_HideAllArenaCastbarPreviews) == "function" then
            _G.MSUF_HideAllArenaCastbarPreviews()
        end
    end

    -- Unit-frame engine model (Libs/MSUFUnitFrames Runtime + Factory contracts).
    local UF = { frames = {}, frameList = {}, elements = {}, Config = { dirty = false } }
    W.UF = UF
    local deferredApply, deferredNames, deferredDriver = false, nil, nil

    local function EnsureDeferredDriver()
        if deferredDriver then return end
        deferredDriver = _G.CreateFrame("Frame")
        deferredDriver:RegisterEvent("PLAYER_REGEN_ENABLED")
        deferredDriver:SetScript("OnEvent", function()
            if deferredApply then
                deferredApply = false
                UF.Apply(nil)
            end
            if deferredNames then
                local names = {}
                for name in pairs(deferredNames) do names[#names + 1] = name end
                deferredNames = nil
                UF.RefreshElements(nil, names, "MSUF_DEFERRED_REFRESH")
            end
        end)
    end
    UF.Factory = { EnsureDeferredDriver = EnsureDeferredDriver }

    function UF.RegisterElement(name, element)
        UF.elements[name] = element
        return true
    end

    function UF.UnitsForConfigKey(key)
        if key == "arena" then
            local units = {}
            for index = 1, W.roster do units[index] = "arena" .. index end
            return units
        end
        if UF.frames[key] then return { key } end
        return nil
    end

    function UF.GetFrame(unit) return UF.frames[unit] end
    function UF.ForEachFrame(fn)
        for index = 1, #UF.frameList do fn(UF.frameList[index]) end
    end
    function UF.MarkDirty()
        deferredApply = true
    end
    UF.ApplyRangeModifier = function() end

    local function InScope(list, frame)
        if not list then return true end
        for index = 1, #list do
            if list[index] == frame.MSUFUnitKey then return true end
        end
        return false
    end

    local function ApplyElement(frame, name)
        if name == "Alpha" then
            frame:SetAlpha(frame.MSUFSpec.alpha)
            return
        end
        local element = UF.elements[name]
        if not element then return end
        frame._smokeActiveElements = frame._smokeActiveElements or {}
        if element.IsEnabled(frame, frame.MSUFSpec) then
            frame._smokeActiveElements[name] = true
            element.Apply(frame, frame.MSUFSpec)
        elseif frame._smokeActiveElements[name] then
            frame._smokeActiveElements[name] = nil
            element.Disable(frame)
        end
    end

    local function PaintRuntime(frame)
        if W.liveUnits[frame.MSUFUnitKey] then
            frame.nameText:SetText("live " .. frame.MSUFUnitKey)
        end
    end

    function UF.RefreshElements(unit, names)
        if type(names) ~= "table" then return false end
        if W.combat then
            deferredNames = deferredNames or {}
            for index = 1, #names do deferredNames[names[index]] = true end
            EnsureDeferredDriver()
            return false
        end
        local list = unit and UF.UnitsForConfigKey(unit) or nil
        if unit and not list then return false end
        for index = 1, #UF.frameList do
            local frame = UF.frameList[index]
            if InScope(list, frame) then
                for nameIndex = 1, #names do ApplyElement(frame, names[nameIndex]) end
            end
        end
        return true
    end

    function UF.UpdateRuntime(unit)
        local list = unit and UF.UnitsForConfigKey(unit) or nil
        if unit and not list then return false end
        for index = 1, #UF.frameList do
            local frame = UF.frameList[index]
            if InScope(list, frame) then PaintRuntime(frame) end
        end
        return true
    end

    -- MSUF_UF_Factory.lua ApplyFrame: spec apply, then hand visibility to the
    -- native unit watch unless LoadConditions manages it.
    function UF.Apply(unit)
        if W.combat then
            deferredApply = true
            EnsureDeferredDriver()
            return false
        end
        local list = unit and UF.UnitsForConfigKey(unit) or nil
        for index = 1, #UF.frameList do
            local frame = UF.frameList[index]
            if InScope(list, frame) then
                ApplyElement(frame, "LoadConditions")
                ApplyElement(frame, "Alpha")
                PaintRuntime(frame)
                local watched = _G.UnitWatchRegistered(frame) == true
                frame._msufUnitWatched = watched and true or nil
                if frame._msufVisibilityManaged ~= true and not watched then
                    frame:Enable()
                    frame._msufUnitWatched = true
                end
            end
        end
        return true
    end

    local MSUF = {
        UF = UF,
        Secrets = { UnitExistsPlain = function(unit) return W.liveUnits[unit] == true end },
        ExportPublic = function(name, value)
            _G[name] = value
            return value
        end,
        Client = {
            IsRetail = flavor == "Mainline",
            IsMists = flavor == "Mists",
            SupportsUnit = function() return true end,
        },
        MSUF_Auras3 = {
            RefreshEditPreview = function() W.auraRefreshes = W.auraRefreshes + 1 end,
            RequestScope = function() end,
        },
    }
    W.MSUF = MSUF
    _G.MSUF_NS = MSUF

    local function Load(relative)
        local chunk = assert(loadfile(Path(relative)))
        chunk("MidnightSimpleUnitFrames", MSUF)
    end

    function W.SpawnArenaFrames()
        for index = 1, W.roster do
            local unit = "arena" .. index
            local frame = Widget("MSUF_" .. unit, true)
            frame.MSUFUnitKey = unit
            frame.MSUFSpec = { unit = unit, enabled = true, alpha = 0.8 }
            frame._msufUnitState = {}
            frame.hpBar = Widget(nil, false, frame)
            frame.targetPowerBar = Widget(nil, false, frame)
            frame.nameText = Widget(nil, false, frame)
            frame.levelText = Widget(nil, false, frame)
            frame._mouse = true
            frame.ForceUpdate = function() return true end
            -- MSUF_UF_Factory.lua SpawnFrame Enable/Disable contract.
            frame.Enable = function(self)
                _G.RegisterUnitWatch(self)
                self:Show()
                return true
            end
            frame.Disable = function(self)
                _G.UnregisterUnitWatch(self)
                self._msufUnitWatched = nil
                self:Hide()
            end
            frame:Show()
            UF.frames[unit] = frame
            UF.frameList[#UF.frameList + 1] = frame
        end
        UF.Apply(nil)
        W.SecureTick()
    end

    function W.Boot()
        Load(FILES.loadConditions)
        Check(type(UF.elements.LoadConditions) == "table", "LoadConditions did not register")
        Load(FILES.editCore)
        Load(FILES.editMovers)
        local em2 = _G.MSUF_EM2
        Check(type(em2) == "table" and em2.State and em2.Movers, "Edit Mode state machine did not load")
        -- Mover overlays are UI chrome drawn above the frames; they never own
        -- unit-frame visibility, so the harness does not draw them.
        em2.Movers.Show = function() end
        em2.Movers.Hide = function() end
        em2.Movers.SyncAll = function() end
        Load(FILES.arenaMatch)
        Load(FILES.arenaTrinkets)
        Load(FILES.arenaCastbarPreview)
        W.SpawnArenaFrames()
        W.Fire("PLAYER_ENTERING_WORLD")
        W.RunTimers()
        W.SecureTick()
    end

    -- MSUF_Auras3_EditMode.lua UnitPreviewActive("arenaN") gate inputs.
    function W.AuraPreviewGate()
        local state = rawget(_G, "MSUF_EditState")
        local editActive = (type(state) == "table" and state.active == true)
            or rawget(_G, "MSUF_UnitEditModeActive") == true
        return (editActive and rawget(_G, "MSUF_UnitPreviewActive") == true)
            or rawget(_G, "MSUF2_ArenaPageAuraPreviewActive") == true
    end

    function W.Snapshot()
        local lines = {}
        local function Add(key, value) lines[#lines + 1] = key .. "=" .. tostring(value) end
        for index = 1, W.roster do
            local unit = "arena" .. index
            local frame = UF.frames[unit]
            local shown = frame:IsShown()
            Add(unit .. ".shown", shown)
            Add(unit .. ".alpha", frame:GetAlpha())
            Add(unit .. ".mouse", frame._mouse)
            Add(unit .. ".previewForced", frame._msufArenaPreviewForced == true)
            Add(unit .. ".prepForced", frame._msufArenaPrepForced == true)
            Add(unit .. ".visibleName", shown and frame.nameText:GetText() or "<hidden>")
            Add(unit .. ".visibilityOwner", W.VisibilityOwner(frame))
            local castbar = rawget(_G, "MSUF_ArenaCastbarPreview" .. index)
            Add(unit .. ".castbarPreviewShown", castbar ~= nil and castbar:IsShown())
            local trinket = rawget(_G, "MSUF_ArenaTrinket" .. index)
            Add(unit .. ".trinketShown", trinket ~= nil and trinket:IsShown())
        end
        Add("MSUF_ArenaTestMode", rawget(_G, "MSUF_ArenaTestMode") == true)
        Add("MSUF2_ArenaUnitframePreviewActive", rawget(_G, "MSUF2_ArenaUnitframePreviewActive") == true)
        Add("MSUF_PreviewTestMode", rawget(_G, "MSUF_PreviewTestMode") == true)
        Add("MSUF_UnitEditModeActive", rawget(_G, "MSUF_UnitEditModeActive") == true)
        Add("MSUF_UnitPreviewActive", rawget(_G, "MSUF_UnitPreviewActive") == true)
        Add("auraPreviewGate", W.AuraPreviewGate())
        Add("previewAnimationArenaGate", rawget(_G, "MSUF_ArenaTestMode") == true
            or rawget(_G, "MSUF2_ArenaUnitframePreviewActive") == true)
        return lines
    end

    return W
end

--------------------------------------------------------------------------------
-- Scenario helpers
--------------------------------------------------------------------------------

local function CheckNoViolations(W, context)
    Check(#W.violations == 0, context .. ": " .. tostring(W.violations[1]))
end

local function CompareSnapshot(context, expected, actual)
    Check(#expected == #actual, context .. ": snapshot shape changed")
    local differences = {}
    for index = 1, #expected do
        if expected[index] ~= actual[index] then
            differences[#differences + 1] = "expected fresh-load " .. expected[index] .. " but found " .. actual[index]
        end
    end
    if #differences > 0 then
        error(context .. ":\n  " .. table.concat(differences, "\n  "), 2)
    end
end

-- Edit Mode drags every client arena slot as one group: the arena unit and
-- castbar movers need one supplemental mouse region per slot 2..N, and decoy
-- frames beyond the client slot count (arena4-5 on Mainline, arena6 on
-- TBC/Mists) must never join them.
local function ArenaRect(index)
    return index * 100, index * 100 + 80, -index * 40, -index * 40 - 30
end

local function CheckArenaMoverCoverage(W, context)
    local registry = _G.MSUF_EM2.Registry
    local lanes = {
        {
            key = "arena",
            resolve = function(index) return W.UF.frames["arena" .. index] end,
            place = function(index, frame)
                W.UF.frames["arena" .. index] = frame
                _G["MSUF_arena" .. index] = frame
            end,
        },
        {
            key = "castbar_arena",
            resolve = function(index) return rawget(_G, "MSUF_ArenaCastbarPreview" .. index) end,
            place = function(index, frame) _G["MSUF_ArenaCastbarPreview" .. index] = frame end,
        },
    }
    for _, lane in ipairs(lanes) do
        local cfg = registry and registry.Get(lane.key)
        Check(type(cfg) == "table" and type(cfg.getSupplementalMoverBounds) == "function",
            context .. ": " .. lane.key .. " mover has no supplemental regions")
        local frames = {}
        for index = 1, W.roster do
            local frame = lane.resolve(index)
            Check(frame ~= nil, context .. ": " .. lane.key .. " slot " .. index .. " has no frame inside Edit Mode")
            frame._rect = { ArenaRect(index) }
            frames[index] = frame
        end
        for index = W.roster + 1, 6 do
            Check(lane.resolve(index) == nil, context .. ": " .. lane.key .. " slot " .. index .. " exists beyond the client slot count")
            lane.place(index, { _rect = { 9000, 9080, 9000, 8970 } })
        end
        local bounds = cfg.getSupplementalMoverBounds()
        for index = W.roster + 1, 6 do lane.place(index, nil) end
        for index = 1, W.roster do frames[index]._rect = nil end
        Check(type(bounds) == "table" and #bounds == W.roster - 1,
            context .. ": " .. lane.key .. " mover has " .. tostring(type(bounds) == "table" and #bounds)
                .. " supplemental regions, expected " .. (W.roster - 1))
        for index = 2, W.roster do
            local l, r, t, b = ArenaRect(index)
            local region = bounds[index - 1]
            Check(region.l == l and region.r == r and region.t == t and region.b == b,
                context .. ": " .. lane.key .. " supplemental region " .. (index - 1) .. " is not bound to arena" .. index)
        end
    end
end

local function EnterEditMode(W, context)
    Check(_G.MSUF_SetMSUFEditModeDirect(true, "arena") == true, context .. ": Edit Mode refused to open")
    W.RunTimers()
    W.SecureTick()
    CheckNoViolations(W, context .. " (enter)")
    Check(_G.MSUF_EM2.State.IsActive() == true, context .. ": Edit Mode is not active after entry")
    Check(rawget(_G, "MSUF_ArenaTestMode") == true,
        context .. ": arena preview flag was not raised on entry (harness would be vacuous)")
    local castbars = 0
    for index = 1, W.roster do
        local unit = "arena" .. index
        local frame = W.UF.frames[unit]
        Check(frame:IsShown(), context .. ": " .. unit .. " is not shown inside Edit Mode")
        if not W.liveUnits[unit] then
            Check(frame._msufArenaPreviewForced == true,
                context .. ": " .. unit .. " did not receive the synthetic Edit Mode preview")
        else
            Check(frame._msufArenaPreviewForced ~= true,
                context .. ": live " .. unit .. " was overwritten by the Edit Mode preview")
        end
        local castbar = rawget(_G, "MSUF_ArenaCastbarPreview" .. index)
        if castbar then
            Check(castbar:IsShown(), context .. ": arena castbar preview " .. index .. " is hidden inside Edit Mode")
            castbars = castbars + 1
        end
    end
    Check(castbars >= 1, context .. ": no arena castbar preview appeared inside Edit Mode")
    Check(W.AuraPreviewGate() == true, context .. ": arena aura preview gate is closed inside Edit Mode")
    CheckArenaMoverCoverage(W, context)
end

local function ExitEditMode(W, context)
    local refreshes = W.auraRefreshes
    _G.MSUF_SetMSUFEditModeDirect(false)
    W.RunTimers()
    W.SecureTick()
    CheckNoViolations(W, context .. " (exit)")
    Check(_G.MSUF_EM2.State.IsActive() ~= true, context .. ": Edit Mode is still active after exit")
    Check(W.auraRefreshes > refreshes, context .. ": aura previews were not refreshed on exit")
end

local function Boot(flavor, roster, configure)
    local W = NewWorld(flavor, roster)
    if configure then configure(W) end
    W.Boot()
    CheckNoViolations(W, flavor .. " boot")
    return W, W.Snapshot()
end

--------------------------------------------------------------------------------
-- Scenarios
--------------------------------------------------------------------------------

local function IdleScenario(flavor, roster)
    local W, fresh = Boot(flavor, roster)
    local context = flavor .. "/idle"
    for index = 1, roster do
        Check(not W.UF.frames["arena" .. index]:IsShown(),
            context .. ": arena" .. index .. " is visible on a fresh load without an opponent")
    end
    for cycle = 1, 2 do
        local step = context .. " cycle " .. cycle
        EnterEditMode(W, step)
        ExitEditMode(W, step)
        CompareSnapshot(step, fresh, W.Snapshot())
    end
end

local function CombatScenario(flavor, roster, lagInCombatFlag)
    local W, fresh = Boot(flavor, roster)
    local context = flavor .. "/combat" .. (lagInCombatFlag and "-lagged-flag" or "")
    EnterEditMode(W, context)
    -- Edit Mode closes itself on PLAYER_REGEN_DISABLED; the protected restore
    -- must wait for PLAYER_REGEN_ENABLED.
    W.EnterCombat()
    CheckNoViolations(W, context .. " (combat exit)")
    Check(_G.MSUF_EM2.State.IsActive() ~= true, context .. ": Edit Mode stayed open in combat")
    W.LeaveCombat(lagInCombatFlag)
    CheckNoViolations(W, context .. " (regen)")
    CompareSnapshot(context .. " after PLAYER_REGEN_ENABLED", fresh, W.Snapshot())
    EnterEditMode(W, context .. " re-entry")
    ExitEditMode(W, context .. " re-entry")
    CompareSnapshot(context .. " re-entry", fresh, W.Snapshot())
end

local function PrepScenario(flavor, roster)
    local prepCount = math.min(2, roster)
    local W, fresh = Boot(flavor, roster, function(world)
        world.inArena = true
        world.matchState = 2
        world.prepSpecs = prepCount
    end)
    local context = flavor .. "/arena-prep"
    for index = 1, roster do
        local frame = W.UF.frames["arena" .. index]
        Check(frame:IsShown() == (index <= prepCount),
            context .. ": fresh prep load did not show exactly the opponent slots (arena" .. index .. ")")
    end
    for cycle = 1, 2 do
        local step = context .. " cycle " .. cycle
        EnterEditMode(W, step)
        ExitEditMode(W, step)
        CompareSnapshot(step, fresh, W.Snapshot())
    end
end

local function LiveOpponentScenario(flavor, roster)
    local W, fresh = Boot(flavor, roster, function(world)
        world.inArena = true
        world.matchState = 3
        world.liveUnits.arena1 = true
    end)
    local context = flavor .. "/live-opponent"
    Check(W.UF.frames.arena1:IsShown(), context .. ": live arena1 is hidden on a fresh load")
    EnterEditMode(W, context)
    ExitEditMode(W, context)
    CompareSnapshot(context, fresh, W.Snapshot())
end

-- The Menu2 Arena page preview was on when Edit Mode closed: exit must drop
-- that flag too, or the arena preview sync re-applies the synthetic frames.
local function Menu2PreviewScenario(flavor, roster)
    local W, fresh = Boot(flavor, roster)
    local context = flavor .. "/menu2-arena-preview"
    EnterEditMode(W, context)
    _G.MSUF2_ArenaUnitframePreviewActive = true
    ExitEditMode(W, context)
    Check(rawget(_G, "MSUF2_ArenaUnitframePreviewActive") ~= true,
        context .. ": Menu2 arena page preview flag survived Edit Mode exit")
    CompareSnapshot(context, fresh, W.Snapshot())
end

local SCENARIOS = {
    { "idle", function(flavor, count) IdleScenario(flavor, count) end },
    { "combat", function(flavor, count) CombatScenario(flavor, count, false) end },
    { "combat-lagged-flag", function(flavor, count) CombatScenario(flavor, count, true) end },
    { "arena-prep", function(flavor, count) PrepScenario(flavor, count) end },
    { "live-opponent", function(flavor, count) LiveOpponentScenario(flavor, count) end },
    { "menu2-arena-preview", function(flavor, count) Menu2PreviewScenario(flavor, count) end },
}

local roster = ArenaRoster()
Check(roster >= 5, "engine arena roster stops at arena" .. roster .. "; TBC/Mists need arena4-5")
local ran, scenariosRan = 0, 0
for _, flavor in ipairs(FLAVORS) do
    if not ONLY_FLAVOR or ONLY_FLAVOR == "all" or ONLY_FLAVOR == flavor then
        for _, scenario in ipairs(SCENARIOS) do
            if not ONLY_SCENARIO or ONLY_SCENARIO == scenario[1] then
                -- Client fact: Mainline keeps 3 arena frames; TBC/Mists expose arena1-5.
                scenario[2](flavor, FLAVOR_ARENA_SLOTS[flavor])
                scenariosRan = scenariosRan + 1
            end
        end
        ran = ran + 1
    end
end
Check(ran > 0, "unknown flavor filter: " .. tostring(ONLY_FLAVOR))
Check(scenariosRan > 0, "unknown scenario filter: " .. tostring(ONLY_SCENARIO))
ResetGlobals()

print(("arena_editmode_exit_restore_smoke: ok (%d flavor(s), %d scenario run(s), %d arena frames)"):format(ran, scenariosRan, roster))
