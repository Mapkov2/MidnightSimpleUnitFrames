local addonName, ns = ...
ns = ns or {}

-- PERF LOCALS (core runtime)
--  - Reduce global table lookups in high-frequency event/render paths.
--  - Secret-safe: localizing function references only (no value comparisons).
local type, tostring, tonumber, select = type, tostring, tonumber, select
local pairs, ipairs, next = pairs, ipairs, next
local math_min, math_max, math_floor = math.min, math.max, math.floor
local string_format, string_match, string_sub = string.format, string.match, string.sub
local UnitExists, UnitIsPlayer = UnitExists, UnitIsPlayer
local UnitHealth, UnitHealthMax = UnitHealth, UnitHealthMax
local UnitPower, UnitPowerMax = UnitPower, UnitPowerMax
local UnitPowerType = UnitPowerType
local UnitHealthPercent, UnitPowerPercent = UnitHealthPercent, UnitPowerPercent
local InCombatLockdown = InCombatLockdown
local CreateFrame, GetTime = CreateFrame, GetTime

-- Boss unit token helpers (perf)
-- Avoid pattern matching (string:match) in hot paths. Pattern matching is
-- noticeably heavier than simple substring/tonumber checks.
-- Returns bossIndex (number) if u is "bossN" (N>=1), otherwise nil.
-- NOTE: Keep global names stable so call-sites across files can use them.
if type(_G.MSUF_GetBossIndexFromToken) ~= "function" then
    function _G.MSUF_GetBossIndexFromToken(u)
        if type(u) ~= "string" then
            return nil
        end
        -- Fast prefix check
        if string_sub(u, 1, 4) ~= "boss" then
            return nil
        end
        local n = tonumber(string_sub(u, 5))
        if n and n >= 1 then
            return n
        end
        return nil
    end
end

if type(_G.MSUF_IsBossUnitToken) ~= "function" then
    function _G.MSUF_IsBossUnitToken(u)
        return _G.MSUF_GetBossIndexFromToken(u) ~= nil
    end
end

local MSUF_POWER_BAR_SHOW_KEYS = {
    player = "showPlayerPowerBar",
    target = "showTargetPowerBar",
    focus  = "showFocusPowerBar",
    boss   = "showBossPowerBar",
}

if type(_G.MSUF_CanonPowerBarUnitKey) ~= "function" then
    function _G.MSUF_CanonPowerBarUnitKey(unitKey)
        if type(unitKey) ~= "string" then return nil end
        unitKey = unitKey:lower()
        if unitKey == "tot" or unitKey == "targetoftarget" or unitKey == "target_of_target" then
            unitKey = "targettarget"
        elseif _G.MSUF_GetBossIndexFromToken(unitKey) then
            unitKey = "boss"
        end
        if unitKey == "player" or unitKey == "target" or unitKey == "focus" or unitKey == "boss" then
            return unitKey
        end
        return nil
    end
end

if type(_G.MSUF_ReadUnitPowerBarEnabled) ~= "function" then
    function _G.MSUF_ReadUnitPowerBarEnabled(unitKey, db)
        db = db or _G.MSUF_DB
        local k = _G.MSUF_CanonPowerBarUnitKey(unitKey)
        if not k then return true end
        local u = db and db[k]
        if u and u.showPowerBar ~= nil then
            return u.showPowerBar ~= false
        end
        local legacyKey = MSUF_POWER_BAR_SHOW_KEYS[k]
        local bars = db and db.bars
        if legacyKey and bars and bars[legacyKey] ~= nil then
            return bars[legacyKey] ~= false
        end
        return true
    end
end

local function MSUF_ReadUnitPowerBarNumber(unitKey, field, legacyField, defaultVal, minVal, maxVal, db)
    db = db or _G.MSUF_DB
    local k = _G.MSUF_CanonPowerBarUnitKey(unitKey)
    local u = k and db and db[k]
    local v = u and u[field]
    if type(v) ~= "number" then
        local bars = db and db.bars
        v = bars and bars[legacyField]
    end
    v = tonumber(v) or defaultVal
    if minVal and v < minVal then v = minVal end
    if maxVal and v > maxVal then v = maxVal end
    return v
end

local function MSUF_ReadUnitPowerBarBool(unitKey, field, legacyField, defaultVal, db)
    db = db or _G.MSUF_DB
    local k = _G.MSUF_CanonPowerBarUnitKey(unitKey)
    local u = k and db and db[k]
    local v = u and u[field]
    if v == nil then
        local bars = db and db.bars
        v = bars and bars[legacyField]
    end
    if v == nil then return defaultVal and true or false end
    return v == true
end

if type(_G.MSUF_ReadUnitPowerBarHeight) ~= "function" then
    function _G.MSUF_ReadUnitPowerBarHeight(unitKey, db)
        return MSUF_ReadUnitPowerBarNumber(unitKey, "powerBarHeight", "powerBarHeight", 3, 1, 80, db)
    end
end

if type(_G.MSUF_ReadUnitPowerBarEmbed) ~= "function" then
    function _G.MSUF_ReadUnitPowerBarEmbed(unitKey, db)
        return MSUF_ReadUnitPowerBarBool(unitKey, "embedPowerBarIntoHealth", "embedPowerBarIntoHealth", true, db)
    end
end

if type(_G.MSUF_ReadUnitPowerBarBorderEnabled) ~= "function" then
    function _G.MSUF_ReadUnitPowerBarBorderEnabled(unitKey, db)
        return MSUF_ReadUnitPowerBarBool(unitKey, "powerBarBorderEnabled", "powerBarBorderEnabled", false, db)
    end
end

if type(_G.MSUF_ReadUnitPowerBarBorderThickness) ~= "function" then
    function _G.MSUF_ReadUnitPowerBarBorderThickness(unitKey, db)
        db = db or _G.MSUF_DB
        local k = _G.MSUF_CanonPowerBarUnitKey(unitKey)
        local u = k and db and db[k]
        local v = u and u.powerBarBorderThickness
        if type(v) ~= "number" then
            local bars = db and db.bars
            v = bars and (bars.powerBarBorderThickness or bars.powerBarBorderSize)
        end
        v = tonumber(v) or 1
        if v < 0 then v = 0 elseif v > 10 then v = 10 end
        return v
    end
end

-- MSUF_Util.lua
-- Stateless helpers / pure functions extracted from MidnightSimpleUnitFrames.lua
-- Keep names stable (globals) to avoid touching call-sites.

ns.MSUF_Util = ns.MSUF_Util or {}
local U = ns.MSUF_Util
_G.MSUF_Util = U

-- Atlas helper used by status/state indicator icons.
-- Some call-sites use a global helper name; provide it here as a safe fallback
-- so indicator modules can remain self-contained without load-order fragility.
-- Returns true if something was applied.
if type(_G._MSUF_SetAtlasOrFallback) ~= "function" then
    function _G._MSUF_SetAtlasOrFallback(tex, atlasName, fallbackTexture)
        if not tex then
            return false
        end

        if atlasName and tex.SetAtlas then
            -- SetAtlas may error if atlasName is invalid in the current build.
            local ok = pcall(tex.SetAtlas, tex, atlasName, true)
            if ok then
                return true
            end
        end

        if fallbackTexture and tex.SetTexture then
            tex:SetTexture(fallbackTexture)
            return true
        end

        return false
    end
end

function MSUF_DeepCopy(value, seen)
    if type(value) ~= "table" then
        return value
    end
    seen = seen or {}
    if seen[value] then
        return seen[value]
    end
    local copy = {}
    seen[value] = copy
    for k, v in pairs(value) do
        copy[MSUF_DeepCopy(k, seen)] = MSUF_DeepCopy(v, seen)
    end
    return copy
end

function MSUF_CaptureKeys(src, keys)
    local out = {}
    if type(src) ~= "table" or type(keys) ~= "table" then
        return out
    end
    for i = 1, #keys do
        local k = keys[i]
        out[k] = src[k]
    end
    return out
end

function MSUF_RestoreKeys(dst, snap)
    if type(dst) ~= "table" or type(snap) ~= "table" then return end
    for k, v in pairs(snap) do
        dst[k] = v -- assigning nil removes the key (restores defaults)
    end
end

function MSUF_GetNumber(v, default, minValue, maxValue)
    local n = tonumber(v) or default
    if minValue and n < minValue then
        n = minValue
    end
    if maxValue and n > maxValue then
        n = maxValue
    end
    return n
end

function MSUF_Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

function MSUF_SetTextIfChanged(fs, text)
    if not fs then return end
    local v = text
    if v == nil then v = "" end

    -- Secret-safe diff gate: only compare/cache plain Lua values.
    -- Secret values must pass straight through to C-side SetText().
    local sv = _G.issecretvalue
    if sv and sv(v) == true then
        fs._msufLastText = nil
        fs:SetText(v)
        return
    end

    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then
        if fs._msufLastText == v then return end
        fs._msufLastText = v
        fs:SetText(v)
        return
    end

    fs._msufLastText = nil
    fs:SetText(v)
end

function MSUF_SetCastTimeText(frame, seconds)
    local fs = frame and frame.timeText
    if not fs then return end

    if type(seconds) == "nil" then
        MSUF_SetTextIfChanged(fs, "")
        return
    end

    -- Midnight/Beta "secret value" safety:
    -- Avoid arithmetic directly on potentially secret values by converting to a Lua number.
    local n = tonumber(seconds)
    if type(n) ~= "number" then
        MSUF_SetTextIfChanged(fs, "")
        return
    end

    if fs.SetFormattedText then
        fs:SetFormattedText("%.1f", n)
    else
        MSUF_SetTextIfChanged(fs, string.format("%.1f", n))
    end
end

function MSUF_SetAlphaIfChanged(f, a)
    if not f or not f.SetAlpha or a == nil then return end
    local prev = f._msufAlpha
    if prev == nil or math.abs(prev - a) > 0.001 then
        f:SetAlpha(a)
        f._msufAlpha = a
    end
end

function MSUF_SetWidthIfChanged(f, w)
    if not f or not f.SetWidth or not w or w <= 0 then return end
    local prev = f._msufW
    if prev == nil or math.abs(prev - w) > 0.01 then
        f:SetWidth(w)
        f._msufW = w
    end
end

function MSUF_SetHeightIfChanged(f, h)
    if not f or not f.SetHeight or not h or h <= 0 then return end
    local prev = f._msufH
    if prev == nil or math.abs(prev - h) > 0.01 then
        f:SetHeight(h)
        f._msufH = h
    end
end

function MSUF_SetPointIfChanged(f, point, relTo, relPoint, ofsX, ofsY)
    if not f or not f.SetPoint then return end
    local c = f._msufAnchor
    if not c then
        c = {}
        f._msufAnchor = c
    end
    if c.point ~= point or c.relTo ~= relTo or c.relPoint ~= relPoint or c.ofsX ~= ofsX or c.ofsY ~= ofsY then
        f:ClearAllPoints()
        f:SetPoint(point, relTo, relPoint, ofsX, ofsY)
        c.point, c.relTo, c.relPoint, c.ofsX, c.ofsY = point, relTo, relPoint, ofsX, ofsY
    end
end

function MSUF_SetJustifyHIfChanged(fs, justify)
    if not fs or not fs.SetJustifyH or not justify then return end
    if fs._msufJustifyH ~= justify then
        fs:SetJustifyH(justify)
        fs._msufJustifyH = justify
    end
end

function MSUF_SetSliderValueSilent(slider, value)
    if not slider or not slider.SetValue then return end
    slider.MSUF_SkipCallback = true
    slider:SetValue(value)
    slider.MSUF_SkipCallback = false
end

function MSUF_ClampToSlider(slider, value)
    if type(value) ~= "number" then return value end
    if slider and type(slider.minVal) == "number" then
        value = math.max(slider.minVal, value)
    end
    if slider and type(slider.maxVal) == "number" then
        value = math.min(slider.maxVal, value)
    end
    return value
end

-- Table exports (optional convenience)
U.DeepCopy = MSUF_DeepCopy
U.CaptureKeys = MSUF_CaptureKeys
U.RestoreKeys = MSUF_RestoreKeys
U.Clamp = MSUF_Clamp
U.GetNumber = MSUF_GetNumber
U.SetTextIfChanged = MSUF_SetTextIfChanged
U.SetCastTimeText = MSUF_SetCastTimeText
U.SetAlphaIfChanged = MSUF_SetAlphaIfChanged
U.SetWidthIfChanged = MSUF_SetWidthIfChanged
U.SetHeightIfChanged = MSUF_SetHeightIfChanged
U.SetPointIfChanged = MSUF_SetPointIfChanged
U.SetJustifyHIfChanged = MSUF_SetJustifyHIfChanged
U.SetSliderValueSilent = MSUF_SetSliderValueSilent
U.ClampToSlider = MSUF_ClampToSlider

-- Also keep existing ns exports where older code expects them.
ns.MSUF_DeepCopy = MSUF_DeepCopy
ns.MSUF_CaptureKeys = MSUF_CaptureKeys
ns.MSUF_RestoreKeys = MSUF_RestoreKeys

do
    local UIParent = UIParent
    local GetPhysicalScreenSize = GetPhysicalScreenSize
    local InCombatLockdown = InCombatLockdown

    local _cachedPhysH
    local _cachedBase768

    local function EnsureBase()
        local physH
        if GetPhysicalScreenSize then
            local _, h = GetPhysicalScreenSize()
            physH = h
        end

        if physH and physH > 0 then
            if physH ~= _cachedPhysH then
                _cachedPhysH = physH
                _cachedBase768 = 768 / physH
            end
        else
            _cachedPhysH = nil
            _cachedBase768 = nil
        end
    end

    local function GetStepFor(frame)
        EnsureBase()

        local eff = 1
        if frame and frame.GetEffectiveScale then
            eff = frame:GetEffectiveScale() or 1
        elseif UIParent and UIParent.GetEffectiveScale then
            eff = UIParent:GetEffectiveScale() or 1
        elseif UIParent and UIParent.GetScale then
            eff = UIParent:GetScale() or 1
        end
        if eff == 0 then eff = 1 end

        if _cachedBase768 then
            return _cachedBase768 / eff
        end
        return 1 / eff
    end

    local function RoundToGrid(v, step)
        if step == 0 or v == 0 then
            return v
        end
        local q = v / step
        if q >= 0 then
            q = math.floor(q + 0.5)
        else
            q = math.ceil(q - 0.5)
        end
        local out = q * step
        if out == 0 then out = 0 end
        return out
    end

    function _G.MSUF_Snap(frame, v)
        if type(v) ~= "number" then
            return v
        end
        local step = GetStepFor(frame)
        return RoundToGrid(v, step)
    end

    function _G.MSUF_Scale(v)
        return _G.MSUF_Snap(UIParent, v)
    end

    function _G.MSUF_UpdatePixelPerfect()
        if InCombatLockdown and InCombatLockdown() then
            return false
        end
        _cachedPhysH = nil
        _cachedBase768 = nil
        EnsureBase()
        return true
    end
end

-- Phase 2: Global helpers relocated from MSUF_UpdateManager.lua
-- (These must load before any consumer; MSUF_Util.lua is in TOC slot 2.)

-- Fast-path replacement for protected calls.
-- Intentionally does NOT catch errors (for maximum performance).
-- Preserves (ok, ...) return convention and returns false if fn is not callable.
if not _G.MSUF_FastCall then
    function _G.MSUF_FastCall(fn, ...)
        if type(fn) ~= "function" then
             return false
        end
        return true, fn(...)
    end
end

-- Global helper: "any edit mode" (MSUF Edit Mode OR Blizzard Edit Mode)
if not _G.MSUF_IsInAnyEditMode then
    function _G.MSUF_IsInAnyEditMode()
        local st = rawget(_G, "MSUF_EditState")
        if st and st.active == true then
             return true
        end
        if rawget(_G, "MSUF_UnitEditModeActive") == true then
             return true
        end
         return false
    end
end

do
    local _lastConfigCombatMessage = 0

    if type(_G.MSUF_IsConfigCombatLocked) ~= "function" then
        function _G.MSUF_IsConfigCombatLocked()
            if InCombatLockdown and InCombatLockdown() then return true end
            local uac = _G.UnitAffectingCombat
            if type(uac) == "function" and uac("player") then return true end
            return false
        end
    end

    if type(_G.MSUF_ShowConfigCombatLockMessage) ~= "function" then
        function _G.MSUF_ShowConfigCombatLockMessage()
            local now = (GetTime and GetTime()) or 0
            if now > 0 and (now - _lastConfigCombatMessage) < 1.25 then return end
            _lastConfigCombatMessage = now

            local msg = "|cffffd700MSUF:|r Menu and Edit Mode are locked in combat. Leave combat to configure MSUF."
            local tr = ns and ns.Translate
            if type(tr) == "function" then msg = tr(msg) or msg end
            if _G.UIErrorsFrame and _G.UIErrorsFrame.AddMessage then
                _G.UIErrorsFrame:AddMessage(msg, 1, 0.82, 0.1)
            end
            if print then print(msg) end
        end
    end

    if type(_G.MSUF_BlockConfigCombatLocked) ~= "function" then
        function _G.MSUF_BlockConfigCombatLocked()
            local locked = _G.MSUF_IsConfigCombatLocked and _G.MSUF_IsConfigCombatLocked()
            if locked then
                if _G.MSUF_ShowConfigCombatLockMessage then _G.MSUF_ShowConfigCombatLockMessage() end
                return true
            end
            return false
        end
    end
end

-- Global helper: restore UIPanelButtonTemplate pieces if another skin/hide pass removed them.
-- This is defensive and safe to call repeatedly; it only touches obvious regions (Left/Middle/Right/Normal/Font).
if not _G.MSUF_ForceShowUIPanelButtonPieces then
    function _G.MSUF_ForceShowUIPanelButtonPieces(btn)
        if not btn then return end

        local name = (btn.GetName and btn:GetName()) or nil
        local left  = btn.Left   or (name and _G[name .. "Left"])   or nil
        local mid   = btn.Middle or (name and _G[name .. "Middle"]) or nil
        local right = btn.Right  or (name and _G[name .. "Right"])  or nil

        local function ShowTex(t)
            if not t then return end
            if t.SetAlpha then t:SetAlpha(1) end
            if t.Show then t:Show() end
        end

        ShowTex(left)
        ShowTex(mid)
        ShowTex(right)

        local nt = (btn.GetNormalTexture and btn:GetNormalTexture()) or nil
        ShowTex(nt)

        local fs = (btn.GetFontString and btn:GetFontString()) or btn.Text or nil
        if fs then
            if fs.SetAlpha then fs:SetAlpha(1) end
            if fs.SetDrawLayer then fs:SetDrawLayer("OVERLAY", 7) end
            if fs.Show then fs:Show() end
        end

        if btn.SetAlpha then btn:SetAlpha(1) end
    end
end

-- Keybinding support (Bindings.xml auto-discovered by WoW, NOT in TOC)
BINDING_HEADER_MSUF_HEADER = "Midnight Simple Unit Frames"
BINDING_NAME_MSUF_TOGGLE_OPTIONS = "Toggle MSUF Options"
BINDING_NAME_MSUF_TOGGLE_EDITMODE = "Toggle MSUF Edit Mode"
local MSUF_BINDING_COMMANDS = {
    "MSUF_TOGGLE_OPTIONS",
    "MSUF_TOGGLE_EDITMODE",
}

local function MSUF_EnsureGlobalBindingState()
    _G.MSUF_GlobalDB = _G.MSUF_GlobalDB or {}
    local gdb = _G.MSUF_GlobalDB
    gdb.global = gdb.global or {}
    gdb.global.bindings = gdb.global.bindings or {}
    gdb.global.bindings.commands = gdb.global.bindings.commands or {}
    return gdb.global.bindings.commands
end

local function MSUF_GetBindingKeysForCommand(command)
    local keys = {}
    if type(command) ~= "string" or command == "" or type(_G.GetBindingKey) ~= "function" then
        return keys
    end

    local seen = {}
    local count = select("#", _G.GetBindingKey(command))
    for i = 1, count do
        local key = select(i, _G.GetBindingKey(command))
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end

    table.sort(keys)
    return keys
end

local function MSUF_CopyBindingKeys(keys)
    local out = {}
    if type(keys) ~= "table" then return out end

    local seen = {}
    for i = 1, #keys do
        local key = keys[i]
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            out[#out + 1] = key
        end
    end

    table.sort(out)
    return out
end

local function MSUF_BindingListsEqual(a, b)
    a = MSUF_CopyBindingKeys(a)
    b = MSUF_CopyBindingKeys(b)
    if #a ~= #b then return false end
    for i = 1, #a do
        if a[i] ~= b[i] then return false end
    end
    return true
end

local function MSUF_GetStoredBindingKeys(command)
    local commands = MSUF_EnsureGlobalBindingState()
    return MSUF_CopyBindingKeys(commands[command])
end

local function MSUF_SetStoredBindingKeys(command, keys)
    if type(command) ~= "string" or command == "" then return end
    local commands = MSUF_EnsureGlobalBindingState()
    commands[command] = MSUF_CopyBindingKeys(keys)
end

local _msufBindingSyncInFlight = false
local _msufBindingApplyPending = false

local function MSUF_ApplyStoredBindingsToCurrentSet()
    if _msufBindingSyncInFlight then return end
    if type(_G.SetBinding) ~= "function" then return end
    if type(_G.InCombatLockdown) == "function" and _G.InCombatLockdown() then
        _msufBindingApplyPending = true
        return
    end

    _msufBindingApplyPending = false
    _msufBindingSyncInFlight = true

    for i = 1, #MSUF_BINDING_COMMANDS do
        local command = MSUF_BINDING_COMMANDS[i]
        local liveKeys = MSUF_GetBindingKeysForCommand(command)
        for j = 1, #liveKeys do
            _G.SetBinding(liveKeys[j])
        end

        local storedKeys = MSUF_GetStoredBindingKeys(command)
        for j = 1, #storedKeys do
            _G.SetBinding(storedKeys[j], command)
        end
    end

    _msufBindingSyncInFlight = false
end

local function MSUF_SyncCurrentBindingsIntoGlobalStore()
    if _msufBindingSyncInFlight then return end
    for i = 1, #MSUF_BINDING_COMMANDS do
        local command = MSUF_BINDING_COMMANDS[i]
        local liveKeys = MSUF_GetBindingKeysForCommand(command)
        if not MSUF_BindingListsEqual(liveKeys, MSUF_GetStoredBindingKeys(command)) then
            MSUF_SetStoredBindingKeys(command, liveKeys)
        end
    end
end

local function MSUF_HasAnyStoredGlobalBindings()
    for i = 1, #MSUF_BINDING_COMMANDS do
        if #MSUF_GetStoredBindingKeys(MSUF_BINDING_COMMANDS[i]) > 0 then
            return true
        end
    end
    return false
end

function MSUF_Keybind_ToggleOptions()
    if type(_G.MSUF_OpenStandaloneOptionsWindow) == "function" then
        local win = _G.MSUF_StandaloneOptionsWindow
        if win and win.IsShown and win:IsShown() then
            if _G.MSUF_HideStandaloneOptionsWindow then
                _G.MSUF_HideStandaloneOptionsWindow()
            elseif win.Hide then
                win:Hide()
            end
        else
            _G.MSUF_OpenStandaloneOptionsWindow("home")
        end
    end
end

function MSUF_Keybind_ToggleEditMode()
    if type(_G.MSUF_SetMSUFEditModeDirect) == "function" then
        local st = _G.MSUF_EditState
        local nextActive = true
        if st and st.active ~= nil then
            nextActive = not st.active
        end
        pcall(_G.MSUF_SetMSUFEditModeDirect, nextActive, nil)
    elseif type(_G.MSUF_ToggleEditMode) == "function" then
        pcall(_G.MSUF_ToggleEditMode)
    end
end

-- i18n UI helpers — prevent text overflow in translated locales.
-- Checkbox text in narrow columns can overflow when German/Spanish/French
-- strings are longer than English. These helpers clamp the FontString
-- width so text truncates instead of overlapping adjacent UI elements.
-- Usage:  MSUF_ClampCheckboxText(cb, maxPixelWidth)

--- Clamp a checkbox's label FontString to a max pixel width.
--- Disables word-wrap so long translations truncate cleanly.
--- Safe to call on nil / non-checkbox frames (no-op).
function MSUF_ClampCheckboxText(cb, maxWidth)
    if not cb or not maxWidth then return end
    local fs = cb.Text or cb.text
    if (not fs) and cb.GetName then
        local name = cb:GetName()
        if name then fs = _G[name .. "Text"] end
    end
    if not (fs and fs.SetWidth) then return end
    fs:SetWidth(maxWidth)
    if fs.SetWordWrap then fs:SetWordWrap(false) end
    if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(false) end
end
_G.MSUF_ClampCheckboxText = MSUF_ClampCheckboxText

do
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:RegisterEvent("UPDATE_BINDINGS")
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    f:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_LOGIN" then
            if not MSUF_HasAnyStoredGlobalBindings() then
                MSUF_SyncCurrentBindingsIntoGlobalStore()
            end
            MSUF_ApplyStoredBindingsToCurrentSet()
            return
        end

        if event == "UPDATE_BINDINGS" then
            MSUF_SyncCurrentBindingsIntoGlobalStore()
            return
        end

        if event == "PLAYER_REGEN_ENABLED" and _msufBindingApplyPending then
            MSUF_ApplyStoredBindingsToCurrentSet()
        end
    end)
end
