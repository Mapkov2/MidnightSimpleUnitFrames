-- Assigned/saved key -> actual Bindings.xml -> real loader/finalizer -> real menu.
-- Only client widget/API fixtures are supplied; no Menu2 implementation is replaced.
local root=assert(arg[1]);local flavor=arg[2] or "Mainline"
local World=assert(loadfile(root.."/tools/tests/client_world.lua"))()
local world=World.New(root,flavor)
local widgetMethods=getmetatable(world.env.UIParent).__index
for _,name in ipairs({"Normal","Highlight","Pushed"}) do
 widgetMethods["Set"..name.."Texture"]=function(self,path)
  local texture=self["fixture"..name] or self:CreateTexture();texture:SetTexture(path);self["fixture"..name]=texture
 end
 widgetMethods["Get"..name.."Texture"]=function(self) return self["fixture"..name] end
end
for _,name in ipairs({"EnableKeyboard","SetPropagateKeyboardInput","SetNumeric","SetTextInsets","SetMaxLetters","ClearFocus","SetCursorPosition","HighlightText"}) do
 widgetMethods[name]=function(self,...) self["fixture"..name]={...} end
end
widgetMethods.HasFocus=function() return false end
widgetMethods.SetAutoFocus=function(self,value) self.autoFocus=value end
widgetMethods.SetValueStep=function(self,value) self.valueStep=value end
widgetMethods.SetObeyStepOnDrag=function(self,value) self.obeyStep=value end
widgetMethods.SetScrollChild=function(self,child) self.scrollChild=child end
widgetMethods.GetScrollChild=function(self) return self.scrollChild end
widgetMethods.SetVerticalScroll=function(self,value) self.verticalScroll=value end
widgetMethods.GetVerticalScroll=function(self) return self.verticalScroll or 0 end
widgetMethods.GetVerticalScrollRange=function() return 0 end
widgetMethods.Click=function(self) local fn=self:GetScript("OnClick");if fn then return fn(self,"LeftButton") end end
local nativeCreate=world.env.CreateFrame
world.env.CreateFrame=function(kind,...)
 local f=nativeCreate(kind,...)
 if kind=="Slider" then f:SetValue(0)
 elseif kind=="CheckButton" then
  f.SetChecked=function(self,value) self.checked=value end
  f.GetChecked=function(self) return self.checked end
 end
 return f
end
local e = world.env
-- WoW binding storage is the fixture boundary; assignment and XML handlers
-- below are the actual addon code. No menu/open/keybind implementation is replaced.
local command, chosenKey = "MSUF_TOGGLE_OPTIONS", "CTRL-SHIFT-F10"
local liveBindings = { ["ALT-F11"] = command }
local savedBindings, savedSet, saveCalls = nil, nil, 0
e.GetBindingKey = function(action)
    local keys = {}
    for key, value in pairs(liveBindings) do if value == action then keys[#keys + 1] = key end end
    table.sort(keys)
    return unpack(keys)
end
e.GetBindingAction = function(key) return liveBindings[key] or "" end
e.SetBinding = function(key, action) liveBindings[key] = action; return true end
e.GetCurrentBindingSet = function() return 2 end
e.SaveBindings = function(bindingSet)
    savedBindings, savedSet, saveCalls = {}, bindingSet, saveCalls + 1
    for key, action in pairs(liveBindings) do savedBindings[key] = action end
end
local file = assert(io.open(root .. "/MidnightSimpleUnitFrames/Bindings.xml", "rb"))
local bindingXML = file:read("*a"); file:close()
local handlers = {}
for attrs, body in bindingXML:gmatch("<Binding%s+([^>]+)>(.-)</Binding>") do
    local name = attrs:match('name="([^"]+)"')
    if name then
        handlers[name] = assert(loadstring(body, "@Bindings.xml:" .. name))
        setfenv(handlers[name], e)
    end
end
local function PressAssignedKey()
    local action = e.GetBindingAction(chosenKey)
    assert(action == command, "chosen key no longer resolves to the Options command")
    assert(handlers[action], "assigned command missing from actual Bindings.xml")()
end
local runtimeErrors = {}
e.geterrorhandler = function() return function(message) runtimeErrors[#runtimeErrors + 1] = tostring(message) end end
local loaded, loadCalls = { MidnightSimpleUnitFrames = true }, 0
e.InCombatLockdown = function() return false end
e.UnitAffectingCombat = function() return false end
e.C_AddOns.IsAddOnLoaded = function(name) return loaded[name] == true, loaded[name] == true end
e.C_AddOns.LoadAddOn = function(name)
    assert(name == "MidnightSimpleUnitFrames_Options", "unexpected demand load: " .. tostring(name))
    loadCalls = loadCalls + 1
    world:LoadGraph(name, world.optionsPaths, world.options)
    local failure = world:FirstFailure()
    assert(not failure, failure and failure.message)
    loaded[name] = true
    return true
end
local suffix = world.client.tocSuffix or flavor
local gameType = world.client.isForever and "camelot" or nil
world.corePaths = World.Graph(root, World.CoreTOC(suffix), e.GetLocale(), gameType)
world.optionsPaths = World.Graph(root, World.OptionsTOC(suffix), e.GetLocale(), gameType)
world:LoadGraph("MidnightSimpleUnitFrames", world.corePaths, world.core)
assert(not world:FirstFailure(), "core failed to load")
assert(e.MSUF_IsOptionsLoaded() == false and loadCalls == 0, "Options were not cold")
assert(e.MSUF_SetManagedBinding(command, chosenKey:lower()) == true, "managed key assignment failed")
local assigned = e.MSUF_GetManagedBindingKeys(command)
assert(#assigned == 1 and assigned[1] == chosenKey and liveBindings["ALT-F11"] == nil,
    "managed assignment did not replace the previous key")
assert(saveCalls == 1 and savedSet == 2 and savedBindings[chosenKey] == command,
    "managed assignment was not saved to the current binding set")
local stored = e.MSUF_GlobalDB.global.bindings.commands[command]
assert(#stored == 1 and stored[1] == chosenKey, "saved binding mirror lost the chosen key")
assert(loadCalls == 0, "assigning the key eagerly loaded Options")
PressAssignedKey()
assert(loadCalls == 1 and world.core.OptionsLODReady == true,
    "cold keybind did not finish Options readiness: " .. tostring(world.core.OptionsLODLoadError))
assert(e.MSUF_IsOptionsLoaded() == true, "loader rejects completed Options")
world.widgets:RunTimers(100)
local M = world.core.MSUF2
assert(M.frame and M.frame:IsShown(), "configured keybind did not open the real menu")
PressAssignedKey()
assert(not M.frame:IsShown(), "configured keybind did not close the real menu")
e.SlashCmdList.MSUF2OPTIONS("")
assert(M.frame:IsShown() and loadCalls == 1, "slash failed after demand load or loaded twice")
assert(type(e.MSUF_OpenExactSettingControl) == "function", "cooldown anchor Fix navigation missing")
if world.core.Client.HostsCooldownManager then
    local anchorBefore = e.MSUF_DB.general.anchorToCooldown
    local focused = e.MSUF_OpenExactSettingControl("general.anchorToCooldown", "Follow Blizzard's Essential Cooldowns", "uf_player")
    assert(#runtimeErrors == 0, table.concat(runtimeErrors, "\n"))
    assert(focused, "cooldown anchor Fix did not resolve its real setting")
    assert(e.MSUF_DB.general.anchorToCooldown == anchorBefore, "cooldown anchor navigation changed its setting")
end
assert(M.OpenExactColorSettingPicker == nil and M.OpenExactCatalogControl == nil,
    "removed execution interfaces remain published")
assert(#runtimeErrors == 0, table.concat(runtimeErrors, "\n"))
print("options_loader_readiness_smoke: PASS (" .. flavor .. "; assigned/saved key, actual XML dispatch, cold readiness, real open/close and slash)")
