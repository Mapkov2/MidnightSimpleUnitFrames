local _, MSUF = ...
local M = MSUF.MSUF2
local T = M.Theme
local SharedUI, MenuSkin = MSUF.UI, MSUF.MenuSkin

SharedUI.BindMenu2Theme(T)
M.UI = SharedUI

-- Apply the saved menu accent as soon as SavedVariables are readable so every
-- themed consumer (window shell, popups, edit-mode chrome) bakes the same
-- accent family. BuildWindow keeps a guarded second call as a fallback.
do
    local applyMenuAccent = T.ApplyMenuAccent
    function T.ApplyMenuAccent()
        local applied = applyMenuAccent()
        if applied then MenuSkin.BindColors(T.colors) end
        return applied
    end
    local function ApplySavedAccent()
        T.ApplyMenuAccent()
    end
    if IsLoggedIn() then
        ApplySavedAccent()
    else
        local accentInit = CreateFrame("Frame")
        accentInit:RegisterEvent("PLAYER_LOGIN")
        accentInit:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            ApplySavedAccent()
        end)
    end
end

