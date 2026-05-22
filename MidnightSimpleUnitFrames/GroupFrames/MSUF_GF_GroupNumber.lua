-- MSUF_GF_GroupNumber.lua
-- Renders the subgroup number (1-8) on each Group Frame.
--
-- Lives outside MSUF_GF_Render.lua as a self-contained, non-invasive feature
-- module. Hooks the public GF API (RefreshVisuals / RefreshFonts / MarkAllDirty
-- / ShowPreview / RefreshPreviewBox) to keep its FontStrings in sync.
--
-- Subgroup resolution:
--   * Real raid units ("raid<N>")  → GetRaidRosterInfo(N) (3rd return).
--   * Out-of-raid / preview ("raid<N>" but no roster info) → synthesized as
--                                    floor((N-1)/5)+1 so previews show 1..8.
--   * "player"                     → look up own raid index, else group 1.
--   * "party<N>" or solo player    → group 1 (party is one subgroup by API).
--   * Frames with explicit override (frame._msufGroupNumberOverride = N) → N.
--
-- Secret-safe (Midnight 12.0):
--   * GetRaidRosterInfo's subgroup return is gated through `issecretvalue`
--     before any type/arithmetic check (matches MSUF's project rule:
--     issecretvalue check MUST come first).
--   * UnitIsUnit's bool return follows the established UFCore guard pattern
--     (treat secret as "unknown", continue scanning).
--   * No comparisons or arithmetic on any direct API return without a guard.
--
-- Performance:
--   * Lazy FontString creation (one per frame, on first paint).
--   * Coalesced refresh (1 frame OnUpdate; multiple events per tick collapse
--     to one walk of GF.frames).
--   * Per-FS diff gates on font key, color key, anchor key, and last value
--     so SetFont/SetTextColor/SetPoint/SetText only fire on actual change.
--   * Hot path is O(#GF.frames) (~5..40 frames); no per-frame allocations.

local addonName, ns = ...

local _G              = _G
local CreateFrame     = CreateFrame
local pairs           = pairs
local type            = type
local tonumber        = tonumber
local string_match    = string.match
local string_format   = string.format
local math_floor      = math.floor
local select          = select
local UnitIsUnit      = UnitIsUnit
local IsInRaid        = IsInRaid
local GetRaidRosterInfo = GetRaidRosterInfo
local InCombatLockdown = InCombatLockdown
local bitlib          = bit or bit32
local bit_band        = bitlib and bitlib.band

-- ---------------------------------------------------------------------------
-- Defaults: mirror the slider/dropdown defaults declared in MSUF_Options_GF.lua
-- so this module is self-sufficient if the option section never wrote them.
-- ---------------------------------------------------------------------------
local DEFAULT_SHOW    = false
local DEFAULT_SIZE    = 12
local DEFAULT_ANCHOR  = "BOTTOMRIGHT"
local DEFAULT_X       = -2
local DEFAULT_Y       = 2

local VALID_ANCHORS = {
    TOPLEFT = true, TOPRIGHT = true,
    BOTTOMLEFT = true, BOTTOMRIGHT = true,
    CENTER = true,
}

-- ---------------------------------------------------------------------------
-- Font & color resolution. Font family is global; GF scopes only affect
-- style/color values.
-- ---------------------------------------------------------------------------
local function _ResolveFontPath()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    local key = (g and g.fontKey) or "FRIZQT"
    local fn = _G.MSUF_GetFontPathForKey
    if type(fn) == "function" then
        local p = fn(key)
        if type(p) == "string" and p ~= "" then return p end
    end
    local resolve = _G.MSUF_ResolveFontPath or function(path) return path end
    return resolve("Fonts\\FRIZQT__.TTF", 12, "")
end

local function _ResolveFontKey()
    local g = _G.MSUF_DB and _G.MSUF_DB.general
    return (g and g.fontKey) or "FRIZQT"
end

local function _ResolveOutline(kindConf)
    local o = kindConf and kindConf.fontOutline
    if o == nil or o == false or o == "" or o == "NONE" then return "" end
    if o == "OUTLINE" or o == "THICKOUTLINE" or o == "MONOCHROME" then return o end
    return "OUTLINE"
end

local function _ResolveColor()
    local fn = _G.MSUF_GetConfiguredFontColor
    if type(fn) == "function" then
        local r, g, b = fn()
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b
        end
    end
    return 1, 1, 1
end

-- ---------------------------------------------------------------------------
-- Subgroup resolution. Returns a plain-Lua number, or nil if unresolvable.
-- ---------------------------------------------------------------------------
local function _ResolveSubgroup(frame)
    -- Render-side / preview override hook
    local ov = frame._msufGroupNumberOverride
    if type(ov) == "number" then return ov end

    local unit = frame.unit
    if type(unit) ~= "string" then return nil end

    local sv = _G.issecretvalue

    -- Player itself: scan roster (only inside a real raid). Outside → group 1.
    if unit == "player" then
        if IsInRaid and IsInRaid() then
            for i = 1, 40 do
                local r = UnitIsUnit("raid" .. i, "player")
                if sv and sv(r) == true then
                    -- secret-tainted bool; skip and keep scanning
                elseif r then
                    local _, _, sub = GetRaidRosterInfo(i)
                    if not (sv and sv(sub) == true) and type(sub) == "number" then
                        return sub
                    end
                    return nil
                end
            end
            return nil
        end
        return 1
    end

    -- Party slots are always group 1 (party never has subgroups).
    if string_match(unit, "^party%d+$") then return 1 end

    -- Raid slots: real roster first, then synthesized (preview / out-of-raid).
    local idx = string_match(unit, "^raid(%d+)$")
    if idx then
        local n = tonumber(idx)
        if n then
            local _, _, sub = GetRaidRosterInfo(n)
            if not (sv and sv(sub) == true) and type(sub) == "number" then
                return sub
            end
            -- Preview / no real raid: 5 members per group, 8 groups.
            return math_floor((n - 1) / 5) + 1
        end
    end

    return nil
end

-- ---------------------------------------------------------------------------
-- Per-frame FontString lifecycle + diff-gated paint
-- ---------------------------------------------------------------------------
local function _GetOrCreateFS(frame)
    local fs = frame._msufGroupNumberFS
    if fs then return fs end
    fs = frame.groupNumberText
    if fs then
        frame._msufGroupNumberFS = fs
        return fs
    end
    fs = frame:CreateFontString(nil, "OVERLAY")
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    frame._msufGroupNumberFS = fs
    return fs
end

local function _UpdateFrame(frame, kindConf)
    local enabled = kindConf and kindConf.showGroupNumber
    if enabled == nil then enabled = DEFAULT_SHOW end
    if not enabled then
        local fs = frame._msufGroupNumberFS
        if fs and fs:IsShown() then fs:Hide() end
        return
    end

    local sub = _ResolveSubgroup(frame)
    if not sub then
        local fs = frame._msufGroupNumberFS
        if fs and fs:IsShown() then fs:Hide() end
        return
    end

    local fs = _GetOrCreateFS(frame)

    -- Font (path + size + outline)
    local size = kindConf.groupNumberSize
    if type(size) ~= "number" or size < 4 then size = DEFAULT_SIZE end
    local path    = _ResolveFontPath(kindConf)
    local outline = _ResolveOutline(kindConf)
    local key     = _ResolveFontKey(kindConf)
    local fontKey = path .. "\1" .. size .. "\1" .. outline
    if fs._msufFontKey ~= fontKey then
        local safeSetFont = _G.MSUF_SetFontSafe
        if type(safeSetFont) == "function" then
            safeSetFont(fs, path, size, outline, key)
        else
            fs:SetFont(path, size, outline)
        end
        fs._msufFontKey = fontKey
    end

    -- Color
    local r, g, b = _ResolveColor()
    local colorKey = r * 1e6 + g * 1e3 + b
    if fs._msufColorKey ~= colorKey then
        fs:SetTextColor(r, g, b, 1)
        fs._msufColorKey = colorKey
    end

    -- Anchor
    local anc = kindConf.groupNumberAnchor
    if not VALID_ANCHORS[anc] then anc = DEFAULT_ANCHOR end
    local x = kindConf.groupNumberX; if type(x) ~= "number" then x = DEFAULT_X end
    local y = kindConf.groupNumberY; if type(y) ~= "number" then y = DEFAULT_Y end
    local anchorKey = anc .. "\1" .. x .. "\1" .. y
    if fs._msufAnchorKey ~= anchorKey then
        fs:ClearAllPoints()
        fs:SetPoint(anc, frame, anc, x, y)
        fs._msufAnchorKey = anchorKey
    end

    -- Text. `sub` is always a plain Lua number out of _ResolveSubgroup
    -- (any secret return was filtered upstream), so string_format is safe.
    if fs._msufLastSub ~= sub then
        fs:SetText(string_format("%d", sub))
        fs._msufLastSub = sub
    end

    if not fs:IsShown() then fs:Show() end
end

-- ---------------------------------------------------------------------------
-- Coalesced refresh: one walk of GF.frames per render tick, regardless of how
-- many events / hooks fire between ticks.
-- ---------------------------------------------------------------------------
local _scheduler
local _pending = false
local _eventFrame
local _eventsActive = false
local _regenListening = false
local _combatDeferred = false
local _deferInvalidateAnchor = false
local _deferInvalidateFont = false
local _Schedule
local _InvalidateAll

local function _EnsureEventFrame()
    if not _eventFrame then _eventFrame = CreateFrame("Frame") end
    _eventFrame:SetScript("OnEvent", _Schedule)
    return _eventFrame
end

local function _ListenRegen()
    if _regenListening then return end
    local f = _EnsureEventFrame()
    f:RegisterEvent("PLAYER_REGEN_ENABLED")
    _regenListening = true
end

local function _StopRegen()
    if _eventFrame and _regenListening then
        _eventFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    _regenListening = false
end

local function _InCombat()
    return InCombatLockdown and InCombatLockdown()
end

local function _AnyEnabled()
    local NS = _G.MSUF_NS
    local GF = NS and NS.GF
    if not GF or not GF.GetConf then return false end
    local party = GF.GetConf("party")
    if party and party.enabled == true and party.showGroupNumber == true then return true end
    local raidKind = (GF.GetLiveRaidKind and GF.GetLiveRaidKind()) or "raid"
    local raid = GF.GetConf(raidKind)
    if raid and raid.enabled == true and raid.showGroupNumber == true then return true end
    if raidKind ~= "raid" then
        raid = GF.GetConf("raid")
        if raid and raid.enabled == true and raid.showGroupNumber == true then return true end
    end
    return false
end

local function _SetEvents(active)
    if active == _eventsActive then return end
    if active then
        local f = _EnsureEventFrame()
        f:RegisterEvent("GROUP_ROSTER_UPDATE")
        f:RegisterEvent("PLAYER_ENTERING_WORLD")
        _eventsActive = true
    else
        if _eventFrame then
            _eventFrame:UnregisterAllEvents()
            _eventFrame:SetScript("OnEvent", nil)
        end
        _eventsActive = false
        _regenListening = false
    end
end

local function _HideAll()
    local NS = _G.MSUF_NS
    local GF = NS and NS.GF
    if not GF or not GF.frames then return end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if f then
                local fs = f._msufGroupNumberFS or f.groupNumberText
                if fs and fs:IsShown() then fs:Hide() end
            end
        end
    else
        for f in pairs(GF.frames) do
            local fs = f._msufGroupNumberFS or f.groupNumberText
            if fs and fs:IsShown() then fs:Hide() end
        end
    end
end

local function _RefreshAll()
    _pending = false
    _combatDeferred = false
    _StopRegen()
    if _deferInvalidateAnchor or _deferInvalidateFont then
        local invalAnchor = _deferInvalidateAnchor
        local invalFont = _deferInvalidateFont
        _deferInvalidateAnchor = false
        _deferInvalidateFont = false
        _InvalidateAll(invalAnchor, invalFont)
    end
    if not _AnyEnabled() then
        if _eventsActive then
            _SetEvents(false)
            _HideAll()
        end
        return
    end
    _SetEvents(true)
    local NS = _G.MSUF_NS
    local GF = NS and NS.GF
    if not GF or not GF.frames or not GF.GetConf then return end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            if type(f) == "table" and f.unit then
                local kind = f._msufGFKind or "party"
                local conf = GF.GetConf(kind)
                if conf and (conf.enabled == true or f._msufGFPreviewActive) then _UpdateFrame(f, conf) end
            end
        end
    else
        for f in pairs(GF.frames) do
            if type(f) == "table" and f.unit then
                local kind = f._msufGFKind or "party"
                local conf = GF.GetConf(kind)
                if conf and (conf.enabled == true or f._msufGFPreviewActive) then _UpdateFrame(f, conf) end
            end
        end
    end
end

_Schedule = function()
    if _InCombat() then
        _pending = false
        _combatDeferred = true
        _ListenRegen()
        return
    end
    if not _AnyEnabled() then
        _pending = false
        if _combatDeferred then
            _combatDeferred = false
            _StopRegen()
        end
        if _eventsActive then
            _SetEvents(false)
            _HideAll()
        end
        return
    end
    if _pending then return end
    _pending = true
    if not _scheduler then _scheduler = CreateFrame("Frame") end
    _scheduler:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        _RefreshAll()
    end)
end

local function _RequestInvalidate(invalAnchor, invalFont)
    if _InCombat() then
        _deferInvalidateAnchor = _deferInvalidateAnchor or invalAnchor
        _deferInvalidateFont = _deferInvalidateFont or invalFont
        return
    end
    _InvalidateAll(invalAnchor, invalFont)
end

_InvalidateAll = function(invalAnchor, invalFont)
    local NS = _G.MSUF_NS
    local GF = NS and NS.GF
    if not GF or not GF.frames then return end
    local list = GF.frameList
    if list then
        for i = 1, #list do
            local f = list[i]
            local fs = f and f._msufGroupNumberFS
            if fs then
                if invalAnchor then fs._msufAnchorKey = nil end
                if invalFont   then
                    fs._msufFontKey  = nil
                    fs._msufColorKey = nil
                end
            end
        end
    else
        for f in pairs(GF.frames) do
            local fs = f._msufGroupNumberFS
            if fs then
                if invalAnchor then fs._msufAnchorKey = nil end
                if invalFont   then
                    fs._msufFontKey  = nil
                    fs._msufColorKey = nil
                end
            end
        end
    end
end

local function _HasAnyDirtyBit(bits, ...)
    if type(bits) ~= "number" then return true end
    for i = 1, select("#", ...) do
        local flag = select(i, ...)
        if type(flag) == "number" then
            if bit_band then
                if bit_band(bits, flag) ~= 0 then return true end
            elseif bits % (flag + flag) >= flag then
                return true
            end
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- API hooks. Idempotent under repeated _Init attempts (deferral path).
-- ---------------------------------------------------------------------------
local _hooked = false

local function _Init()
    local NS = _G.MSUF_NS
    local GF = NS and NS.GF
    if not GF then return false end
    if _hooked then return true end
    _hooked = true

    -- RefreshVisuals: enable/disable + roster changes propagate here
    if type(GF.RefreshVisuals) == "function" then
        local orig = GF.RefreshVisuals
        GF.RefreshVisuals = function(...)
            orig(...)
            _Schedule()
        end
    end

    -- RefreshFonts: invalidate font + color caches, then repaint
    if type(GF.RefreshFonts) == "function" then
        local orig = GF.RefreshFonts
        GF.RefreshFonts = function(...)
            orig(...)
            _RequestInvalidate(false, true)
            _Schedule()
        end
    end

    -- MarkAllDirty: only layout/geometry/font bits affect group-number paint.
    if type(GF.MarkAllDirty) == "function" then
        local orig = GF.MarkAllDirty
        GF.MarkAllDirty = function(level, ...)
            orig(level, ...)
            local bits = (type(level) == "number") and level or (GF.DIRTY_ALL or 0x3F)
            local anchorDirty = _HasAnyDirtyBit(bits, GF.DIRTY_GEOMETRY or 0x01, GF.DIRTY_LAYOUT or 0x20)
            local fontDirty = _HasAnyDirtyBit(bits, GF.DIRTY_FONT or 0x04)
            if bits == (GF.DIRTY_ALL or 0x3F) then
                anchorDirty = true
                fontDirty = true
            end
            if anchorDirty or fontDirty then
                _RequestInvalidate(anchorDirty, fontDirty)
                _Schedule()
            end
        end
    end

    -- ShowPreview / RefreshPreviewBox: ensure preview frames get painted
    -- as soon as they're created or rebuilt. They live in GF.frames during
    -- preview, so the standard refresh walks them.
    if type(GF.ShowPreview) == "function" then
        local orig = GF.ShowPreview
        GF.ShowPreview = function(...)
            orig(...)
            _RequestInvalidate(true, true)
            _Schedule()
        end
    end
    if type(GF.RefreshPreviewBox) == "function" then
        local orig = GF.RefreshPreviewBox
        GF.RefreshPreviewBox = function(...)
            orig(...)
            _Schedule()
        end
    end

    -- Public hooks for render-side / preview integrations.
    GF.UpdateGroupNumberFrame = function(frame)
        if type(frame) ~= "table" then return end
        if _InCombat() and not frame._msufGFPreviewActive then
            if not _combatDeferred then _Schedule() end
            return
        end
        local kind = frame._msufGFKind or "party"
        local conf = GF.GetConf(kind)
        if conf then _UpdateFrame(frame, conf) end
    end
    GF.RefreshGroupNumbers = _Schedule
    GF.SetGroupNumberOverride = function(frame, n)
        if type(frame) ~= "table" then return end
        if type(n) == "number" then
            frame._msufGroupNumberOverride = n
        else
            frame._msufGroupNumberOverride = nil
        end
        local fs = frame._msufGroupNumberFS
        if fs then fs._msufLastSub = nil end
        _Schedule()
    end

    _Schedule()
    return true
end

-- File-load attempt: if GF is not yet on ns (unusual for our TOC ordering),
-- defer until ADDON_LOADED for our addon, with PLAYER_LOGIN as a safety net.
if not _Init() then
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("ADDON_LOADED")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(self, event, name)
        if event == "ADDON_LOADED" and name ~= addonName then return end
        if _Init() then self:UnregisterAllEvents() end
    end)
end
