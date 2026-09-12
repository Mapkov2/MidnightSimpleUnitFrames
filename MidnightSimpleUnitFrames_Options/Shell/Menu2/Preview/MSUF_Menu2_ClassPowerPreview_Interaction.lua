--- Owns preview offset writes, runtime apply requests and exact settings routes.
local _, MSUF = ...
local M = MSUF.MSUF2

local RequestClassPowerPreviewRefresh = M.ClassPowerStackPreview.RequestRefresh
local floor = math.floor
local function Round(value)
    return floor((tonumber(value) or 0) + 0.5)
end

local function CallApply(handle, reason)
    local kind = handle and handle._applyKind
    local moveOnly = reason == "CLASSPOWER_PREVIEW_MOVE" and kind ~= "powerText"
    if not moveOnly then
        if kind == "class" or kind == "classText" then
            _G.MSUF_ClassPower_Apply({ anchor = true, cdm = true, playerHP = true, syncNow = false })
            _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)
        elseif kind == "power" or kind == "powerText" then
            if kind == "powerText" then _G.MSUF_ForceTextLayoutForUnitKey("player") end
            _G.MSUF_ApplyPowerBarEmbedLayout_ForUnitKey("player", true)
            _G.MSUF_ClassPower_Apply({ playerHP = true })
        elseif kind == "hp" or kind == "hpText" then
            _G.MSUF_ClassPower_Apply({ playerHP = true })
        end
    end
    M.RequestGeneralApply(reason or "MSUF2_CLASSPOWER_PREVIEW_MOVE", {
        preview = true, applyAll = false, notify = false, history = false,
    })
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

--- Handle writes update the same SavedVariables offsets used by runtime
--- ClassPower, but only repaint this preview unless the caller asks to apply.
local function WriteHandle(handle, x, y, skipApply)
    local store = StoreForHandle(handle)
    if not (store and handle and handle._xKey and handle._yKey) then return end
    store[handle._xKey] = Round(x)
    store[handle._yKey] = Round(y)
    if handle._applyKind == "powerText" and type(M.SyncDirectTextOffsets) == "function" then
        M.SyncDirectTextOffsets(store, handle._xKey)
        M.SyncDirectTextOffsets(store, handle._yKey)
    end
    if type(M.RefreshVisibleSliders) == "function" then M.RefreshVisibleSliders("CLASSPOWER_PREVIEW_MOVE") end
    RequestClassPowerPreviewRefresh(handle._preview, "CLASSPOWER_PREVIEW_DRAG")
    if not skipApply then CallApply(handle, "CLASSPOWER_PREVIEW_MOVE") end
end
local function ClassPowerRouteForHandle(handle)
    local kind = handle and (handle._applyKind or handle._layerKey or handle._key) or "class"
    local section, state, tab = "classpower_display"
    if kind == "classText" then section, state, tab = "classpower_visuals", "classPowerStyleTab", "text"
    elseif kind == "power" or kind == "powerText" then section, state, tab = "classpower_detached_power", "classPowerDetachedPowerTab", kind == "power" and "layout" or "text"
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
    Round = Round, Apply = CallApply, Read = ReadHandle, Write = WriteHandle,
    OpenSettings = OpenClassPowerHandleSettings,
}
