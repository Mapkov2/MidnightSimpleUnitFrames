--- Runtime/MSUF_BlizzEditModeBridge.lua
--- Bridge between MSUF Edit Mode and Blizzard's Edit Mode: mirrors enter/exit
--- when general.linkEditModes allows it. Split out of the former chat/tooltip
--- runtime file; it must stay free of frames, events, and tickers.
local addonName, MSUF = ...
MSUF = MSUF or {}
local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end
local function PublishCompat(name, value)
    return ExportPublic(name, value)
end

local function MSUF_Chat_RunEnsureDB()
    local ensureDB = _G.MSUF_EnsureDB
    if type(ensureDB) == "function" then
        ensureDB()
        return true
    end
    return false
end

--- [8c6] Removed legacy Options UI relayout functions (Player/Bars).
--- These were dead/duplicate layout builders superseded by MSUF_Options_Core.lua.
do
    local SetBlizzardEditModeFromMSUF = _G.MSUF_SetBlizzardEditModeFromMSUF
    if type(SetBlizzardEditModeFromMSUF) ~= "function" then
        SetBlizzardEditModeFromMSUF = function(active)
            if InCombatLockdown and InCombatLockdown() then
                return
            end
            MSUF_Chat_RunEnsureDB()
            if MSUF_DB and MSUF_DB.general and MSUF_DB.general.linkEditModes == false then
                return
            end
            local emf = _G.EditModeManagerFrame
            if not emf then return end
            if active then
                if not _G.MSUF_BlizzEditModeStartedByMSUF then
                    PublishCompat("MSUF_BlizzEditModeStartedByMSUF", true)
                end
                if type(securecallfunction) == "function" and type(_G.ShowUIPanel) == "function" then
                    securecallfunction(_G.ShowUIPanel, emf) --- this will show the edit mode panel and enter edit mode
                elseif emf.Show then
                    emf:Show()
                elseif emf.EnterEditMode then
                    emf:EnterEditMode()
                end
            else
                if not _G.MSUF_BlizzEditModeStartedByMSUF then return end
                PublishCompat("MSUF_BlizzEditModeStartedByMSUF", nil)
                if type(securecallfunction) == "function" and type(emf.ExitEditMode) == "function" then
                    securecallfunction(emf.ExitEditMode, emf)
                elseif emf.ExitEditMode then
                    emf:ExitEditMode()
                end
                if type(securecallfunction) == "function" and type(_G.HideUIPanel) == "function" and emf.IsShown and emf:IsShown() then
                    securecallfunction(_G.HideUIPanel, emf)
                elseif emf.Hide and emf.IsShown and emf:IsShown() then
                    emf:Hide()
                end
            end
        end
    end
    PublishCompat("MSUF_SetBlizzardEditModeFromMSUF", SetBlizzardEditModeFromMSUF)
    --- Namespaced mirror of the _G export above; new internal callers should
    --- use this instead of the global.
    MSUF.EditMode = MSUF.EditMode or {}
    MSUF.EditMode.SetBlizzardEditMode = SetBlizzardEditModeFromMSUF
end
--- [8c6] Removed PLAYER_LOGIN Options relayout hook (Bars).
MSUF.MSUF_UpdateAllFonts = MSUF.MSUF_UpdateAllFonts or _G.MSUF_UpdateAllFonts
