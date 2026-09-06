local NS, check, new_frame, new_region, root = ...
assert(type(NS) == "table", "Run through tests/MapkoSkin/run.lua with this file as argument 2 and MSUF root as argument 3")
local function Load(path, addon)
    return assert(loadfile(root .. "/" .. path))("MidnightSimpleUnitFrames", addon)
end
local M = {}
function M.Lines(text) return text:gmatch("[^\r\n]+") end
function M.WordList(text) local out = {}; for word in text:gmatch("%S+") do out[#out + 1] = word end; return out end
function M.AssignNamedValues(target, names, ...)
    local i = 0
    for name in names:gmatch("%S+") do i = i + 1; target[name] = select(i, ...) end
end
function M.Tr(text) return text end
local msuf = { MSUF2 = M }
local savedMSUFDB = _G.MSUF_DB
_G.MSUF_DB = { general = {} }
local savedEnabled = NS.DB.enabled
NS.DB.enabled = true
local createFrame = CreateFrame
CreateFrame = function(...)
    local frame = createFrame(...)
    function frame:HookScript(script, callback)
        local previous = self:GetScript(script)
        self:SetScript(script, function(...)
            if previous then previous(...) end
            callback(...)
        end)
    end
    return frame
end
local savedGetAPI = _G.MapkoSkin.GetAPI
_G.MapkoSkin.GetAPI = nil
Load("MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua", {})
_G.MapkoSkin.GetAPI = savedGetAPI
Load("MidnightSimpleUnitFrames/Shell/UI/MSUF_Widgets.lua", msuf)
Load("MidnightSimpleUnitFrames/Shell/UI/MSUF_MapkoSkin.lua", msuf)
local earlyHost = new_frame("Frame", "MSUFEarlyHost")
local earlyClose = msuf.UI.CloseButton(earlyHost)
check(NS.WindowActionSkin.GetKind(earlyClose) == "close" and not earlyClose._label:IsShown(),
    "pre-Menu2 close button missed the skin or retained a duplicate text X")
local earlyInput = new_frame("EditBox", "MSUFEarlyInput", earlyHost)
msuf.UI.EditBox(earlyInput)
check(NS.Registry.GetSurface(earlyInput) and NS.Registry.GetSurface(earlyInput).spec.role == "input",
    "pre-Menu2 input did not opt into the shared skin")
Load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme_Tokens.lua", msuf)
Load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_Theme.lua", msuf)
Load("MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_WindowControls.lua", msuf)
local T, provider = M.Theme, msuf.MenuSkin
provider.BindColors(T.colors)
local parent = new_frame("Frame", "MSUFIntegrationHost")
local frame = new_frame("Frame", "MSUFIntegrationShell", parent)
local stock = frame:CreateTexture(nil, "BACKGROUND")
stock:Show()
frame._msuf2Bg = stock
local child = new_frame("Frame", "MSUFIntegrationChild", frame)
local semantic = child:CreateTexture(nil, "ARTWORK")
semantic:Show()
T.ApplySurface(frame, "shell")
check(NS.Registry.GetSurface(frame) and not stock:IsShown() and semantic:IsShown(),
    "MSUF shell did not opt into MapkoSkin or hid semantic child content")
local button = T.Button(parent, "Native label", 120, 24)
local onClick = function() end
button:SetScript("OnClick", onClick)
local clickProxy = button:GetScript("OnClick")
button:SetActive(true)
local surface = NS.Registry.GetSurface(button)
check(surface and surface.active and button:GetText() == "Native label" and not button._msuf2Fill.L:IsShown(),
    "MSUF button lost label/selection or paints both renderers")
local allocations = #button.textures
for i = 1, 100 do
    provider.Button(button, true, i % 2 == 0, button.RefreshVisual)
end
check(#button.textures == allocations and button:GetScript("OnClick") == clickProxy,
    "MSUF hover allocated textures or replaced the guarded click handler")
local close = T.CloseButton(parent)
check(NS.WindowActionSkin.GetKind(close) == "close" and not close._msuf2CloseLineA:IsShown(),
    "authored MSUF close control did not receive the explicit window-action style")
local group = M.CreateWindowControlGroup(parent, 3)
local maximize = M.CreateWindowControlButton(group, "maximize")
maximize:SetWindowControlIcon("restore")
check(NS.WindowActionSkin.GetKind(maximize) == "minimize" and not group._msuf2ControlGroupBase:IsShown(),
    "maximized MSUF window did not keep its restore glyph in the skin")
local originalAccent = { unpack(T.colors.accent) }
local oldColor = NS.CopyValue(NS.DB.theme.colors.accent)
NS.Theme.SetColor("accent", 0.17, 0.28, 0.39, 1)
check(T.colors.accent[1] == 0.17 and T.colors.accent[3] == 0.39 and NS.Registry.GetSurface(button).active,
    "MapkoSkin live palette change missed MSUF or cleared selection")
NS.Theme.SetColor("accent", unpack(oldColor))
NS.DB.enabled = false
NS.Registry.NotifyListeners("adapter", "master")
check(not provider.IsActive() and stock:IsShown() and semantic:IsShown()
    and not NS.Registry.GetSurface(frame).visible and button._msuf2Fill.L:IsShown()
    and button:GetScript("OnClick") == clickProxy and close._msuf2CloseLineA:IsShown(),
    "disabling MapkoSkin did not restore native MSUF chrome and behavior")
check(next(MSUF_DB.general) == nil, "MSUF integration wrote profile preferences")
check(earlyClose._label:IsShown() and earlyClose:GetText() == "x",
    "pre-Menu2 text X did not restore after master disable")
local restoredAccent = { unpack(T.colors.accent) }
local nativePanel = new_frame("Frame", "MSUFNativeBeforeEnable", parent)
T.ApplySurface(nativePanel, "shell")
check(nativePanel._msuf2PanelAsset and nativePanel._msuf2PanelAsset.C:IsShown(),
    "native MSUF panel fixture did not build the actual nine-part artwork")
NS.DB.enabled = true
NS.Registry.NotifyListeners("adapter", "master")
check(provider.IsActive() and NS.Registry.GetSurface(frame).visible and not stock:IsShown(),
    "MapkoSkin master re-enable failed to reacquire MSUF surfaces")
local allHidden = true
for _, key in ipairs({ "TL", "T", "TR", "L", "C", "R", "BL", "B", "BR" }) do
    allHidden = allHidden and not nativePanel._msuf2PanelAsset[key]:IsShown()
end
check(allHidden, "MSUF glass retained native center or corner artwork after enable")
MSUF_DB.general.mapkoSkinMenus = false
provider.Refresh()
check(not provider.IsActive() and nativePanel._msuf2PanelAsset.C:IsShown() and NS.DB.enabled,
    "MSUF-only toggle disabled MapkoSkin globally or failed to restore chrome")
MSUF_DB.general.mapkoSkinMenus = nil
provider.Refresh()
check(provider.IsActive() and not nativePanel._msuf2PanelAsset.C:IsShown(),
    "MSUF-only toggle did not reapply the skin")
local late = new_frame("Frame", "MSUFIntegrationLatePopup", parent)
T.ApplySurface(late, "popup")
check(NS.Registry.GetSurface(late) and NS.Registry.GetSurface(late).spec.role == "popup",
    "late MSUF dialog missed the provider")
local actionStyle = NS.DB.icons.windowActions.style
NS.WindowActionSkin.SetOption("style", "native")
check(close._msuf2CloseLineA:IsShown(), "native action option did not restore the authored MSUF X")
NS.WindowActionSkin.SetOption("style", actionStyle)
check(not close._msuf2CloseLineA:IsShown(), "modern action option did not reclaim the MSUF X")
NS.DB.enabled = false
NS.Registry.NotifyListeners("adapter", "master")
check(T.colors.accent[1] == restoredAccent[1] and T.colors.accent[3] == restoredAccent[3],
    "repeated enable/disable changed the saved MSUF palette")
local api = NS.GetAPI(2, 1)
for _, entry in ipairs(api:GetRegisteredAddons()) do
    check(entry.name ~= "MidnightSimpleUnitFrames_Options", "options created a duplicate skin client")
end
NS.DB.enabled = savedEnabled
_G.MSUF_DB = savedMSUFDB
CreateFrame = createFrame
