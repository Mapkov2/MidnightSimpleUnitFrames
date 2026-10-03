--- Reads preview offsets and opens exact settings routes. Edit Mode owns movement.
local _, MSUF = ...
local M = MSUF.MSUF2

local floor = math.floor
local function Round(value)
    return floor((tonumber(value) or 0) + 0.5)
end

local function StoreForHandle(handle)
    if not handle then return nil end
    local db = M.EnsureDB()
    return handle._store == "player" and db.player or db.bars
end
local function ReadHandle(handle)
    local store = StoreForHandle(handle)
    local x = store and tonumber(store[handle._xKey]) or nil
    local y = store and tonumber(store[handle._yKey]) or nil
    if x == nil then x = tonumber(handle._defaultX) or 0 end
    if y == nil then y = tonumber(handle._defaultY) or 0 end
    return x, y
end

local function ClassPowerRouteForHandle(handle)
    local kind = handle and (handle._applyKind or handle._layerKey or handle._key) or "class"
    local section, state, tab = "classpower_display"
    if kind == "classText" then section, state, tab = "classpower_visuals", "classPowerStyleTab", "text"
    elseif kind == "power" or kind == "powerText" then section, state, tab = "classpower_detached_power", "classPowerDetachedPowerTab", kind == "power"
        and "layout" or "text"
    elseif kind == "hp" or kind == "hpText" then section, state, tab = "classpower_player_hp", "classPowerPlayerHPTab", kind == "hp" and "layout" or "text" end
    if state then
        M.SetMenuStateValue(state, tab)
    end
    return section
end
local function OpenClassPowerHandleSettings(handle)
    if not (M and type(M.SelectPage) == "function") then return false end
    _G.MSUF_EM2_MenuFocusRequest = {
        pageKey = "classpower",
        sectionId = ClassPowerRouteForHandle(handle),
        component = handle and handle._key,
        source = "classpower-preview",
        explicit = true,
        changedAt = GetTime and GetTime() or 0,
    }
    return M.SelectPage("classpower") ~= false
end

M.ClassPowerPreviewInteraction = {
    Round = Round, Read = ReadHandle,
    Store = StoreForHandle,
    OpenSettings = OpenClassPowerHandleSettings,
}
