-- Cursor-free unit menus for Forever's native gamepad UI. Blizzard installs
-- priority overrides on UIParent, so SetBindingClick alone cannot reliably
-- reach a unit frame. Own only our overrides and yield to native UI bindings;
-- never register addon callbacks or frames with Blizzard's binding manager.
local _, MSUF = ...
if not (MSUF.Client and MSUF.Client.IsForever) then return end
local Menus = MSUF.UnitMenus
local PadNav = MSUF.PadNavigation
local PixelLayoutRegion = PadNav.Kit.PixelLayoutRegion
local owner, hint
local inCombat, dirty, applied = false, true, nil
local bindings, anchors = {}, {}
local STICK_PRESS_KEY = "PADRSTICK"

local function Shown(frame)
    return frame and frame:IsShown()
end

local function GameplayActive()
    if inCombat or _G.InCombatLockdown() or not PadNav.IsGamepadUI() or PadNav.IsCapturing()
        or Shown(_G.SmartNavigation) or Shown(_G.GamepadRadial) then return false end
    if _G.GetCurrentKeyBoardFocus and _G.GetCurrentKeyBoardFocus() then return false end
    local utility = _G.GamepadSharedUtility
    local manager = utility and utility.InputBindingManager
    if not (manager and manager.coreSet and manager:IsOnlyCoreBindingSetActive()) then return false end
    local mode = _G.GamepadMode
    if mode and (mode.IsHUDBindingModifierDown() or mode.IsTargetingModifierDown()
        or mode.IsLeftModifierDown() or mode.IsRightModifierDown()) then return false end
    return true
end

local function CollectBindings()
    bindings = {}
    for _, entry in ipairs({ { Menus.TargetBinding, "MSUF_UnitMenuTarget" }, { Menus.PlayerBinding, "MSUF_UnitMenuPlayer" } }) do
        -- Forever keeps keyboard and gamepad bindings in separate key modes.
        -- Request gamepad keys explicitly, as the native binding helpers do.
        -- WoW maps physical and virtual controllers to the same PAD key names;
        -- neither the controller brand nor its displayed button labels matter.
        local keys = { _G.GetBindingKey(entry[1], 1) }
        for _, key in ipairs(keys) do
            if key:find("PAD", 1, true) then bindings[key] = entry[2] end
        end
    end
    -- Only override keys explicitly assigned to an MSUF menu. In particular,
    -- leave the native stick-press ping available when no menu key is bound.
    dirty = false
end

local function EnsureOwner()
    if owner then return end
    owner = PixelLayoutRegion(CreateFrame("Frame", "MSUF_UnitMenuBindingOwner", nil, "SecureHandlerStateTemplate"))
    owner:SetParent(_G.UIParent)
    -- Combat can begin before an insecure event handler may clear bindings.
    -- This restricted handler clears only MSUF's overrides during lockdown.
    owner:SetAttribute("_onstate-combat", [[if newstate == "combat" then self:ClearBindings() end]])
    _G.RegisterStateDriver(owner, "combat", "[combat] combat; peace")
    hint = PixelLayoutRegion(CreateFrame("Frame"))
    hint:SetParent(_G.UIParent)
    hint:SetSize(1, 1)
    hint:SetFrameStrata("TOOLTIP")
    hint.text = PixelLayoutRegion(hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"))
    hint.text:SetPoint("TOP", hint, "TOP")
    hint:Hide()
end

local function Anchor(button, unit)
    local frame = _G["MSUF_" .. unit]
    if not (frame and frame:IsVisible()) then frame = _G.UIParent end
    if anchors[button] ~= frame then
        button:ClearAllPoints()
        if frame == _G.UIParent then
            button:SetSize(1, 1)
            button:SetPoint("CENTER", frame, "CENTER")
        else
            button:SetPoint("TOPLEFT", frame, "TOPLEFT")
            button:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
        end
        anchors[button] = frame
    end
    return frame
end

function Menus.UpdateGamepad()
    if inCombat or _G.InCombatLockdown() then
        if hint then hint:Hide() end
        return
    end
    if not Menus.Target then return end
    local active = GameplayActive()
    if dirty then CollectBindings() end
    if not owner and not active then return end
    EnsureOwner()
    -- A native binding group may have been pushed and popped between polls.
    -- Recover our priority only in gameplay, without rebinding every tick.
    if active and applied == true then
        for key, name in pairs(bindings) do
            if _G.GetBindingAction(key, true) ~= "CLICK " .. name .. ":LeftButton" then
                applied = nil
                break
            end
        end
    end
    if applied ~= active then
        _G.ClearOverrideBindings(owner)
        if active then
            for key, name in pairs(bindings) do
                _G.SetOverrideBindingClick(owner, true, key, name, "LeftButton")
            end
        end
        applied = active
    end
    local targetAnchor = Anchor(Menus.Target, _G.UnitExists("target") and "target" or "player")
    local playerAnchor = Anchor(Menus.Player, "player")
    local hintAnchor = bindings[STICK_PRESS_KEY] == "MSUF_UnitMenuPlayer" and playerAnchor or targetAnchor
    -- R3 is the stick's click, not its movement. Spell out the physical action
    -- beside the current unit rather than requiring familiarity with "R3".
    if active and bindings[STICK_PRESS_KEY] and hintAnchor ~= _G.UIParent then
        hint:ClearAllPoints()
        hint:SetPoint("TOP", hintAnchor, "BOTTOM", 0, -4)
        hint.text:SetText(MSUF.Translate("Press right stick: Unit menu"))
        hint:Show()
    else
        hint:Hide()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        applied = nil -- The secure combat handler clears the live overrides.
        if hint then hint:Hide() end
        return
    elseif event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_LOGIN" then
        inCombat = _G.InCombatLockdown() == true
    elseif event == "UPDATE_BINDINGS" then
        dirty, applied = true, nil
    end
    Menus.UpdateGamepad()
end)
