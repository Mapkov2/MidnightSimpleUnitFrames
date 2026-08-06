--- Provider-neutral popup for frames registered through MSUF_EditModeAPI.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}

local EM2 = _G.MSUF_EM2
if not EM2 then return end
if type(_G.MSUF_InstallEditPopupUI) == "function" then
    _G.MSUF_InstallEditPopupUI(addonName, MSUF)
end

local Quick = EM2.QuickPopup or {}
local External = EM2.ExternalElements
if not (Quick.CreateShell and External) then return end

local Popup, frame = {}, nil
EM2.ExternalPopup = Popup

local function Blocked()
    return Quick.BlockConfigCombatLocked and Quick.BlockConfigCombatLocked() or false
end

local function SetButtonText(button, text)
    if button and button._label and button._label.SetText then button._label:SetText(text or "") end
end

local function SetButtonEnabled(button, enabled)
    if not button then return end
    button._msufExternalEnabled = enabled == true
    button:EnableMouse(enabled == true)
    button:SetAlpha(enabled and 1 or 0.42)
end

local function FormatValues(label, x, y, width, height)
    if x == nil or y == nil then return tostring(label or "External frame") end
    if width ~= nil and height ~= nil then
        return ("X %s     Y %s     W %s     H %s"):format(x, y, width, height)
    end
    return ("X %s     Y %s"):format(x, y)
end

local function OpenSettings()
    if Blocked() or not frame then return end
    if External.OpenSettings(frame._key) then frame:Hide() end
end

local function ResetPosition()
    if Blocked() or not frame then return end
    if External.Reset(frame._key) then Popup.Sync() end
end

local function Build()
    if frame then return frame end
    frame = Quick.CreateShell("MSUF_EM2_ExternalPopup", {
        width = 420, height = 224, title = "External frame", liveStatus = "Managed by its addon",
        hoverSource = "external-popup", blocker = Blocked,
    })
    frame._summaryFS = Quick.FS(frame, "body")
    frame._summaryFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -76)
    frame._summaryFS:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -20, -76)
    frame._summaryFS:SetJustifyH("LEFT")

    frame._settingsBtn = Quick.ButtonAt(frame, "Open settings", 20, -110, 252, 36, OpenSettings, {
        variant = "primary", hoverWash = true,
    })
    frame._resetBtn = Quick.ButtonAt(frame, "Reset position", 284, -110, 116, 36, ResetPosition, {
        hoverWash = true,
    })
    Quick.AddFooterControls(frame, { anchor = "BOTTOM", bottomGap = 12 })
    if EM2.AttachPopupScaleGrip then EM2.AttachPopupScaleGrip(frame) end
    return frame
end

function Popup.Sync()
    if not (frame and frame._key) then return false end
    local label, group, settingsLabel, canSettings, canReset = External.GetDisplayInfo(frame._key)
    if not label then frame:Hide(); return false end
    frame._titleFS:SetText(label)
    frame._summaryFS:SetText(FormatValues(External.GetInspectorValues(frame._key)))
    SetButtonText(frame._settingsBtn, settingsLabel or ("Open " .. tostring(group or label) .. " settings"))
    SetButtonEnabled(frame._settingsBtn, canSettings)
    SetButtonEnabled(frame._resetBtn, canReset)
    if frame._refreshUndoRedo then frame._refreshUndoRedo() end
    return true
end

function Popup.Open(key)
    if Blocked() or not External.GetRecord(key) then return false end
    Build()._key = key
    if not Popup.Sync() then return false end
    frame:Show()
    return true
end

function Popup.Close() if frame then frame:Hide() end end
function Popup.IsOpen() return frame and frame:IsShown() or false end
function Popup.GetKey() return frame and frame._key or nil end
function Popup.RefreshHistory() if frame and frame:IsShown() and frame._refreshUndoRedo then frame._refreshUndoRedo() end end
