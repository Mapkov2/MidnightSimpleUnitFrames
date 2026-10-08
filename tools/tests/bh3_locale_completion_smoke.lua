-- Exact reviewed keys plus real locale loaders and German/Chinese Options graphs.
-- Engine stubs verify text delivery, not live font coverage or clipping.
local root=assert(arg[1]):gsub("\\", "/"):gsub("/$", "")
local KEYS={
    "Player Name Position",
    "Target Name Position",
    "Focus Name Position",
    "Target of Target Name Position",
    "Focus Target Name Position",
    "Pet Name Position",
    "Player Castbar",
    "Target Castbar",
    "Focus Castbar",
    "Boss Castbar",
    "Tools",
    "Detached powerbar",
    "Embedded powerbar",
    "%s (unavailable on this client)",
    "Blizzard TotemFrame is not available on this client.",
    "Blizzard has no native Pet Target frame.",
    "%d relevant color",
    "%d relevant colors",
    "Fixed slots and missing-aura reminders are unavailable on Classic. Saved settings are kept; active auras still work.",
    "Reminder clicks are unavailable on Classic",
    "Custom enchant reminders are unavailable on Classic. The normal player buff lane still shows weapon enchants.",
    "PART 3 - Shape Class Resources with its interactive preview and independent Edit Mode placement.",
    "Independent placement",
    "Place Class Resources independently in Edit Mode.",
    "Independent layouts",
    "Place Unitframes and Class Resources independently in Edit Mode.",
    "Texture layers use the unit frame's strata. Use Layer (0-30) to set their order.",
    "Shows or hides the bundled MSUF release notes.",
    "Review or run setup again",
    "Get the essentials right in a few minutes",
    "Resume setup",
    "Run setup again",
    "Opens a copyable link to the MSUF profile imports on Wago.",
    "Find settings and help",
    "Search enabled features in your own words.",
    "Set up Suite",
    "Opens the MSUF Suite setup: profile, modules and UI scaling.",
    "Shows the Suite page that switches each optional module on or off.",
    "%d of %d modules on",
    "Selects a pending scale percentage; use Apply to commit it.",
    "QUICK SETUP",
    "~5 min",
    "Set the essentials first: placement, frame basics, text, auras, and shared style.",
    "5.76 and older",
    "Your current profile stays exactly as it is. Take a quick tour of the new controls, then decide what you want to configure.",
    "Setup and individual styling now live in the matching Unitframe and Party/Raid menus. Frames > Auras holds the expanded shared styles.",
    "per-frame Aura controls and expanded shared styling in Frames > Auras",
}
local packs={}
local locales={"enUS","enGB","deDE","esES","esMX","frFR","itIT","ptBR","ruRU","koKR","zhCN","zhTW"}
for _,locale in ipairs(locales) do
 local env={GetLocale=function() return locale end};env._G=env;setmetatable(env,{__index=_G})
 local ns={};env.MSUF_NS=ns;env.MSUF=ns
 for _,file in ipairs({"MSUF_Localization",locale}) do
  local fn=assert(loadfile(root.."/MidnightSimpleUnitFrames/Locales/"..file..".lua"));setfenv(fn,env);fn("MSUF",ns)
 end
 assert(ns.FinalizeLocale()==locale);packs[locale]=ns.L
 for _,key in ipairs(KEYS) do
  local value=rawget(ns.L,key);assert(type(value)=="string",locale..": missing reviewed key "..key)
  if locale~="enUS" and locale~="enGB" and key~="~5 min" then assert(value~=key,locale..": English fallback "..key) end
 end
 assert(string.format(ns.L["%d of %d modules on"],2,7):find("2",1,true))
 assert(string.format(ns.L["%s (unavailable on this client)"],"Focus"):find("Focus",1,true))
end
local MenuWorld=assert(loadfile(root.."/tools/tests/menu_core_world.lua"))()
local Slice=assert(loadfile(root.."/.github/scripts/msuf_source_slice.lua"))()
local function Read(path)local f=assert(io.open(root.."/"..path,"rb"));local s=f:read("*a");f:close();return s end
for _,case in ipairs({{"Vanilla","deDE"},{"Mists","zhCN"}}) do
 local flavor,locale=case[1],case[2];local seen={}
 local mw=MenuWorld.Open(root,flavor,{locale=locale,page="home",beforeCore=function(world)
  local original=world.widgets.Methods.SetText
  world.widgets.Methods.SetText=function(self,text,...) if type(text)=="string" then seen[text]=true end;return original(self,text,...) end
 end,beforeOptions=function(world) assert(world.core.FinalizeLocale()==locale) end})
 assert(mw.core.GetEffectiveLocale()==locale)
 local ns=mw.core;local M=mw.M
 for _,key in ipairs(KEYS) do assert(M.Tr(key)==packs[locale][key],locale..": Options disagrees on "..key) end
 -- The complete first-load scene paints actual translated text through Theme.Font.
 ns.FirstLoad6={ShouldShowDashboard=function() return true end,GetState=function()return {status="pending",installKind="fresh"}end,GetInstallKind=function()return "fresh"end}
 assert(M.BuildFirstLoadDashboardScene({wrapper=mw.env.CreateFrame("Frame",nil,mw.env.UIParent),width=900,SetContentHeight=function()end}))
 assert(seen[packs[locale]["QUICK SETUP"]],locale..": first-load heading was not painted in the selected language")
 assert(seen[packs[locale]["Set the essentials first: placement, frame basics, text, auras, and shared style."]],locale..": first-load explanation was not translated")
 ns.FirstLoad6.ShouldShowDashboard=function()return false end
 ns.GuidedTour6.GetState=function()return {status="completed"}end
 M.InvalidatePage("home");mw:Select("home")
 assert(seen[packs[locale]["Review or run setup again"]],locale..": completed setup title was not translated")
 assert(seen[packs[locale]["Run setup again"]],locale..": completed setup action was not translated")
 -- Real mover label function with the real selected locale, including whole phrases.
 local file="MidnightSimpleUnitFrames/Shell/EditMode/MSUF_EditMode_Movers.lua"
 local source=Read(file)
 local code=Slice.Declarations(source,{"local UNIT_NAME_POSITION_LABELS", "local function MoverLabelText"},file).."\nreturn MoverLabelText"
 local f=assert(loadstring(code));setfenv(f,setmetatable({Tr=M.Tr,U={}},{__index=_G}));local label=f()
 for _,unit in ipairs({"player","target","focus","targettarget","focustarget","pet"}) do
  local value=label(unit,{popupType="unit"});assert(value and value~=({player="Player Name Position",target="Target Name Position",focus="Focus Name Position",targettarget="Target of Target Name Position",focustarget="Focus Target Name Position",pet="Pet Name Position"})[unit])
 end
end
print("BH3 locale completion: 47 keys x 12 packs, real German/Chinese LoD text and mover labels passed")
