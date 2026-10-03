-- static_popup_stub.lua: Blizzard's StaticPopup system for test worlds.
--
-- Modelled on Blizzard_StaticPopup/StaticPopup.lua and
-- Blizzard_StaticPopup_Game/GameDialogDefs.lua, which agree on live, forever,
-- classic, classic_era and classic_anniversary:
--   * StaticPopupDialogs holds the two generic definitions; every write to it
--     is recorded in stub.writes (addon code must never add one);
--   * StaticPopup_Show reuses the visible dialog of the same `which` (for a
--     `multiple` definition only one with the same data table), cancelling it
--     with reason "override", puts the dialog on DIALOG strata, then runs the
--     definition's OnShow;
--   * GENERIC_CONFIRMATION formats data.text with data.text_arg1/2, labels its
--     buttons from data.acceptText/cancelText (YES/NO), runs data.callback on
--     accept and data.cancelCallback on the second button and on Escape;
--   * GENERIC_INPUT_BOX does the same with an edit box (DONE/CANCEL labels,
--     data.maxLetters or 24), passes the text to data.callback, and keeps its
--     accept button disabled while the box is empty.
-- Usage: local Stub = dofile(root .. "/tools/tests/static_popup_stub.lua")
--        local popups = Stub.Install(env)  -- env needs CreateFrame and UIParent

local Stub = {}

local function Format(text, a, b)
    return string.format(text, a, b)
end

local function GenericDefinitions(env)
    local confirmation = {
        text = "", button1 = "", button2 = "",
        OnShow = function(dialog, data)
            dialog:SetFormattedText(data.text, data.text_arg1, data.text_arg2)
            dialog:GetButton1():SetText(data.acceptText or env.YES)
            dialog:GetButton2():SetText(data.cancelText or env.NO)
            if data.showAlert then dialog.AlertIcon:Show() end
        end,
        OnAccept = function(_, data) data.callback() end,
        OnCancel = function(_, data)
            local cancelCallback = data and data.cancelCallback or nil
            if cancelCallback ~= nil then cancelCallback() end
        end,
        hideOnEscape = 1, timeout = 0, multiple = 1, whileDead = 1, wide = 1,
    }
    local input = {
        text = "", button1 = "", button2 = "", hasEditBox = 1,
        OnShow = function(dialog, data)
            dialog:SetFormattedText(data.text, data.text_arg1, data.text_arg2)
            dialog:GetButton1():SetText(data.acceptText or env.DONE)
            dialog:GetButton2():SetText(data.cancelText or env.CANCEL)
            dialog:GetEditBox():SetMaxLetters(data.maxLetters or 24)
        end,
        OnAccept = function(dialog, data) data.callback(dialog:GetEditBox():GetText()) end,
        OnCancel = function(_, data)
            if data.cancelCallback ~= nil then data.cancelCallback() end
        end,
        hideOnEscape = 1, timeout = 0, multiple = 1, whileDead = 1,
    }
    return { GENERIC_CONFIRMATION = confirmation, GENERIC_INPUT_BOX = input }
end

local function Label(frame)
    function frame:SetText(text) self.label = text end
    function frame:GetText() return self.label end
    function frame:SetEnabled(on) self.enabled = on and true or false end
    function frame:IsEnabled() return self.enabled ~= false end
    return frame
end

function Stub.Install(env)
    local stub = { writes = {}, shown = {}, created = 0 }
    local definitions = GenericDefinitions(env)
    env.YES, env.NO = env.YES or "Yes", env.NO or "No"
    env.DONE, env.CANCEL = env.DONE or "Done", env.CANCEL or "Cancel"
    env.StaticPopupDialogs = setmetatable({}, {
        __index = definitions,
        __newindex = function(t, key, value)
            stub.writes[#stub.writes + 1] = tostring(key)
            rawset(t, key, value)
        end,
    })
    local dialogs = env.StaticPopupDialogs

    local function Visible(which, data)
        local info = dialogs[which]
        for _, dialog in ipairs(stub.shown) do
            if dialog.which == which and (not info.multiple or dialog.data == data) then return dialog end
        end
    end
    local function Remove(dialog)
        for i = #stub.shown, 1, -1 do
            if stub.shown[i] == dialog then table.remove(stub.shown, i) end
        end
        dialog:Hide()
    end
    local function NewDialog()
        local dialog = env.CreateFrame("Frame", nil, env.UIParent)
        stub.created = stub.created + 1
        dialog.button1 = Label(env.CreateFrame("Button", nil, dialog))
        dialog.button2 = Label(env.CreateFrame("Button", nil, dialog))
        dialog.AlertIcon = env.CreateFrame("Frame", nil, dialog)
        dialog.AlertIcon:Hide()
        local edit = Label(env.CreateFrame("Frame", nil, dialog))
        function edit:SetMaxLetters(count) self.maxLetters = count end
        dialog.editBox = edit
        function dialog:SetFormattedText(text, a, b) self.text = Format(text, a, b) end
        function dialog:GetButton1() return self.button1 end
        function dialog:GetButton2() return self.button2 end
        function dialog:GetEditBox() return self.editBox end
        return dialog
    end

    function env.StaticPopup_Show(which, a1, a2, data)
        local info = dialogs[which]
        if not info then error("Dialog " .. tostring(which) .. " does not exist.", 2) end
        local dialog = Visible(which, data)
        if dialog then
            Remove(dialog)
            if info.OnCancel then info.OnCancel(dialog, dialog.data, "override") end
        else
            dialog = NewDialog()
        end
        dialog.which, dialog.data, dialog.text = which, data, nil
        dialog.hideOnEscape = info.hideOnEscape
        dialog.AlertIcon:Hide()
        dialog.editBox:SetText("")
        dialog.button1:SetText(info.button1)
        dialog.button2:SetText(info.button2)
        if info.text ~= "" then dialog:SetFormattedText(info.text, a1, a2) end
        dialog:SetFrameStrata("DIALOG")
        dialog:Show()
        stub.shown[#stub.shown + 1] = dialog
        if info.OnShow then info.OnShow(dialog, data) end
        return dialog
    end
    function env.StaticPopup_ShowCustomGenericConfirmation(data)
        env.StaticPopup_Show("GENERIC_CONFIRMATION", nil, nil, data)
    end
    function env.StaticPopup_ShowCustomGenericInputBox(data)
        env.StaticPopup_Show("GENERIC_INPUT_BOX", nil, nil, data)
    end
    function env.StaticPopup_FindVisible(which, data)
        if not dialogs[which] then return nil end
        return Visible(which, data)
    end
    function env.StaticPopup_Visible(which)
        for _, dialog in ipairs(stub.shown) do
            if dialog.which == which then return "StaticPopup", dialog end
        end
    end
    function env.StaticPopup_Hide(which, data)
        for i = #stub.shown, 1, -1 do
            local dialog = stub.shown[i]
            if dialog.which == which and (not data or data == dialog.data) then Remove(dialog) end
        end
    end

    --- Click button 1 or 2 of a shown dialog (StaticPopup_OnClick).
    function stub.Click(dialog, index)
        local info = dialogs[dialog.which]
        if index == 1 and info.hasEditBox and dialog.editBox:GetText() == "" then return false end
        local handler = index == 1 and info.OnAccept or info.OnCancel
        local keepOpen = handler and handler(dialog, dialog.data, "clicked")
        if not keepOpen then Remove(dialog) end
        return true
    end
    --- The game menu's Escape (StaticPopup_EscapePressed).
    function stub.Escape()
        local closed = false
        for i = #stub.shown, 1, -1 do
            local dialog = stub.shown[i]
            if dialog.hideOnEscape then
                local info = dialogs[dialog.which]
                if info.OnCancel then info.OnCancel(dialog, dialog.data, "clicked") end
                Remove(dialog)
                closed = true
            end
        end
        return closed
    end
    --- Shown dialogs for one generic prompt key (data.referenceKey).
    function stub.ForKey(key)
        local out = {}
        for _, dialog in ipairs(stub.shown) do
            if type(dialog.data) == "table" and dialog.data.referenceKey == key then out[#out + 1] = dialog end
        end
        return out
    end
    return stub
end

return Stub
