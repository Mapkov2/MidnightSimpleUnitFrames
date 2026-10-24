local _, MSUF = ...
MSUF = MSUF or {}
local M = MSUF.MSUF2 or {}
MSUF.MSUF2 = M

-- Global Aura Appearance > Icon Skin: what this aura type shows (Buff, Debuff,
-- Player Defensives, Dots on Target) and the way to the Icon Skins page (Style
-- group, MSUF_Menu2_IconSkins.lua), the one place where skins are chosen. The
-- skin is drawn by the shared painter in Auras3/MSUF_Auras3_IconSkins.lua.
local AurasPage = M.AurasPage
local A3 = MSUF.MSUF_Auras3
local Model = A3 and A3.MenuModel
local W = M.Widgets
local T = M.Theme
if not (AurasPage and Model and W and T and M.AuraControls) then return end

--- Builds the status (Appearance pages only), above the Icon Border & Shadow
--- section whose look a skin replaces: no second skin setting here.
function AurasPage.BuildIconSkinSection(StyleState)
    local Page = M.IconSkinsPage
    if not (StyleState.appearanceGlobalsOnly and Page and Page.StatusRow) then return end
    local kind = StyleState.appearanceKind
    local S = {}
    function S.SkinDraws() return Page.SkinDraws(kind) end
    StyleState.iconSkin = S
    local section = AurasPage.Section(StyleState.b, StyleState.baseId .. "_icon_skin", "Icon Skin", 72, false)
    local width = StyleState.BodyWidth(section)
    local _, open = Page.StatusRow(StyleState.ctx, section, 24, -16, width - 48, kind)
    AurasPage.Own(M.AuraControls.RegisterAuraControl(StyleState.ctx, open, "Open Icon Skins", "button",
        "style.appearance.icon-skin.open", "navigation", Page.PAGE))
end

--- Wraps the Icon Border & Shadow gate so it also follows the skin: while the
--- skin this aura type shows draws its icons, the user's border and shadow
--- details grey out. Returns the gates.
function AurasPage.WrapIconSkinGates(StyleState)
    local gates, S = StyleState.iconStyleGates, StyleState.iconSkin
    if not (gates and S and W.SetControlsEnabled) then return gates end
    local apply = gates.Apply
    function gates.Apply(editable)
        apply(editable)
        if S.SkinDraws() then
            W.SetControlsEnabled(gates.border, false)
            W.SetControlsEnabled(gates.shadow, false)
        end
    end
    return gates
end
