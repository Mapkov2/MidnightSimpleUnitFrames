--- Addon Compartment integration for WoW 12.0 Midnight.
--- Zero overhead: no events, no OnUpdate, only fires on user click/hover.

local _, MSUF = ...
local API = MSUF.MinimapButton

function MSUF_AddonCompartment_OnClick(_, btn)
    if btn == "RightButton" then
        API.ToggleEditMode()
        return
    end
    API.ToggleOptionsWindow()
end

function MSUF_AddonCompartment_OnEnter(_, menuButtonFrame)
    local tt = GameTooltip
    if not tt then return end
    API.BuildTooltip(tt, menuButtonFrame, {
        versionLabel = true,
        blankAfterVersion = false,
        leftText = "|cffffffffLeft Click:|r Open MSUF Menu",
        shiftText = false,
        show = true,
    })
end

function MSUF_AddonCompartment_OnLeave()
    if GameTooltip then GameTooltip:Hide() end
end
