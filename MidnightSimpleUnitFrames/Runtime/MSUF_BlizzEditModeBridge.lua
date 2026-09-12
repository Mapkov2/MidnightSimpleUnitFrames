--- Mirror MSUF Edit Mode through Blizzard's panel lifecycle.
local addonName, MSUF = ...
local ExportPublic = MSUF.ExportPublic
local EnsureDB = MSUF.Require("MSUF_EnsureDB", "Runtime/MSUF_BlizzEditModeBridge.lua")

local function SetBlizzardEditModeFromMSUF(active)
    if InCombatLockdown() then return end
    EnsureDB()
    if MSUF_DB.general.linkEditModes == false then return end

    local frame = EditModeManagerFrame
    if active then
        ShowUIPanel(frame)
        if frame:IsShown() then
            ExportPublic("MSUF_BlizzEditModeStartedByMSUF", true)
        end
    elseif _G.MSUF_BlizzEditModeStartedByMSUF then
        -- OnHide owns ExitEditMode; calling it here as well exits twice.
        HideUIPanel(frame)
        if not frame:IsShown() then
            ExportPublic("MSUF_BlizzEditModeStartedByMSUF", nil)
        end
    end
end

ExportPublic("MSUF_SetBlizzardEditModeFromMSUF", SetBlizzardEditModeFromMSUF)
MSUF.EditMode = MSUF.EditMode or {}
MSUF.EditMode.SetBlizzardEditMode = SetBlizzardEditModeFromMSUF
