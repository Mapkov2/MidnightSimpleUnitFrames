-- Exact top-search navigation uses real menu owners and navigation only.
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
for _,name in ipairs({"SetNumeric","SetTextInsets","SetMaxLetters","ClearFocus","SetCursorPosition","HighlightText"}) do
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
world:Boot()
local failure=world:FirstFailure();assert(not failure,failure and failure.message)
local e,n=world.env,world.core
local M=n.MSUF2
local api=M.Search._CoreAPI
local routing=M.Search._RoutingAPI
local F,V,S=n.ProfileFields,n.ProfileVariants,n.ProfileSync
e.MSUF_EnsureDB(true)
e.MSUF_ActiveProfile="Default"
e.MSUF_GlobalDB={profiles={Default=e.MSUF_DB,Other={general={},player={width=222}}},char={},global={}}
M.ProfileSearch.ContextChanged()
-- Native window chrome is a fixture boundary. Page builders, selector/accordion
-- routing, catalog identities and exact resolution remain the product owners.
M.scrollChild=e.CreateFrame("Frame")
M.GetContentMetrics=function() return 900,800 end
M.SetActivePageHeader=function() end
M.RunStickyHeaderActivation=function() end
M.SetTitle,M.UpdateNav=function() end,function() end
M.frame=e.CreateFrame("Frame",nil,e.UIParent);M.frame:Show()
M.ApplyService.Flush=function() return true end
n.ProfileRuntime.Apply=function() V.ResolveCurrent() end
local function Search(query) return api.SearchPages(query) end
local function FirstControl(query,predicate)
 for _,row in ipairs(Search(query)) do
  if predicate(row) then return row end
 end
 error("missing control for "..query)
end
local function Ends(value,suffix) return type(value)=="string" and value:sub(-#suffix)==suffix end
local function Navigate(row)
 local selected,anchored,exact=routing.OpenSearchTarget(row.key,"deliberately unrelated","",nil,row.route,row.exactTarget)
 assert(selected and anchored and exact,"exact routing failed or found no anchor: "..tostring(row.label))
 local record,widget,source=M.RuntimeControlCatalog.ResolveExactTarget(row.key,row.exactTarget)
 assert(record and widget and source=="control_id" and record.controlId==row.exactTarget.controlId,"ID resolver drift")
 if row.exactTarget.sectionId then
  assert(M.cache[row.key].sections[row.exactTarget.sectionId],"declared accordion is absent")
 end
 return record,widget
end
local snapshot=F.Copy(e.MSUF_DB)
local portrait=FirstControl("2D portrait",function(row) return row.exactTarget and Ends(row.exactTarget.settingKey,".portraitRender") end)
assert(F.Equal(snapshot,e.MSUF_DB),"cold search wrote saved configuration")
assert(portrait.exactTarget.controlId,"cold static search lost its declared ID")
Navigate(portrait)
local dragon=FirstControl("Drachen spiegeln",function(row) return row.exactTarget and Ends(row.exactTarget.settingKey,".portraitDragonFlip") end)
Navigate(dragon)
local cost=FirstControl("Mana-Vorschau",function(row) return row.exactTarget and row.exactTarget.settingKey=="bars.manaUpcomingCost" end)
assert(Search("Mana-Vorschau")[1]==cost,"mana preview must rank its actual control first")
Navigate(cost)
local pain=Search("Zähne zusammenbeißen")
local painFound=false
for _,row in ipairs(pain) do
 if row.exactTarget and row.exactTarget.settingKey=="bars.showIgnorePain" then painFound=true;Navigate(row) end
end
assert(painFound==(n.Client.IsRetail and not n.Client.IsForever),"retail-only resource ghost")
for _,row in ipairs(Search("Ignore Pain")) do
 local key=row.exactTarget and row.exactTarget.settingKey
 if not (n.Client.IsRetail and not n.Client.IsForever) then
  assert(key~="bars.showIgnorePain" and key~="bars.ignorePainTimeMarker","unsupported resource result")
 end
end
local variant=FirstControl("Profilvariante",function(row) return row.exactTarget and Ends(row.exactTarget.controlId,".variant.select") end)
Navigate(variant)
local sync=FirstControl("Profil synchronisieren",function(row) return row.exactTarget and Ends(row.exactTarget.controlId,".sync.group.select") end)
Navigate(sync)
assert(FirstControl("Profile synchronization",function(row) return row.exactTarget and Ends(row.exactTarget.controlId,".sync.group.select") end))
-- Public names never enter IDs/payloads; identity, not a normalized name, owns a target.
local name="Ä | / : % \' same name "..string.rep("x",24)
assert(V.Replace(e.MSUF_DB,{version=1,entries={{name=name,enabled=false,conditions={},patch={}},{name="Second",enabled=false,conditions={},patch={}}}}))
assert(S.Replace({{name=name,members={Default=true,Other=true},modules={unitframes=true},exclude={}}}))
local editor=FirstControl("Save conditions",function(row) return row.providerRow and row.providerRow.profileSearchToken end)
assert(editor.exactTarget.controlId:match("^[%w_%.:/%-]+$") and #editor.exactTarget.controlId<=160)
local before=F.Copy(e.MSUF_DB)
Navigate(editor)
-- Reuse the real warm page, then change its selected entry through search only.
local function Named(path,entryName)
 Search(path)
 local id
 for _,row in ipairs(M.ProfileSearch.Collect()) do
  if row.help==entryName and row.controlId:find("variant.condition.context.",1,true) then id=row.controlId;break end
 end
 for _,row in ipairs(api.GetSearchRecords()) do
  if row.exactTarget and row.exactTarget.controlId==id then return row end
 end
 error("missing named editor "..entryName)
end
local where=Named("Where",name)
Navigate(where)
local warm=M.cache.profiles
Navigate(where)
assert(M.cache.profiles==warm,"same entry unnecessarily rebuilt a warm page")
local second=Named("Where","Second")
Navigate(second)
assert(M.cache.profiles~=warm,"new entry reused another entry's editor")
Navigate(where)
local enabled
local enabledID=where.exactTarget.controlId:gsub("variant.condition.context.","variant.enabled.",1)
for _,row in ipairs(api.GetSearchRecords()) do
 if row.exactTarget and row.exactTarget.controlId==enabledID then enabled=row;break end
end
assert(enabled,"named toggle is absent")
Navigate(enabled)
assert(F.Equal(before,e.MSUF_DB) and not V.IsRecording(),"search entered recording/changed variant values")
local oldTarget=editor.exactTarget
assert(V.Replace(e.MSUF_DB,{version=1,entries={{name="Renamed",enabled=false,conditions={},patch={}}}}))
Search("Save conditions")
assert(routing.OpenSearchTarget("profiles","","",nil,nil,oldTarget)==false,"renamed entry reused stale target")
assert(V.Replace(e.MSUF_DB,{version=1,entries={{name=name,enabled=false,conditions={},patch={}}}}))
Search("Save conditions")
assert(routing.OpenSearchTarget("profiles","","",nil,nil,oldTarget)==false,"recreated name reused stale identity")
local current=FirstControl("Save conditions",function(row) return row.providerRow and row.providerRow.profileSearchToken end)
local active=e.MSUF_DB
e.MSUF_DB=e.MSUF_GlobalDB.profiles.Other;e.MSUF_ActiveProfile="Other"
Search("Save conditions")
assert(routing.OpenSearchTarget("profiles","","",nil,nil,current.exactTarget)==false,"search switched profiles")
e.MSUF_DB=active;e.MSUF_ActiveProfile="Default"
Search("Save conditions")
local repeatTarget=FirstControl("Save conditions",function(row) return row.providerRow and row.providerRow.profileSearchToken end)
local collections=0
local original=M.ProfileSearch.Collect
M.RegisterSearchProvider("profile-editors",function() collections=collections+1;return original() end,M.ProfileSearch.ContextChanged)
for _,query in ipairs({"Save conditions","Sav","Save","Save co","Save conditions"}) do Search(query) end
assert(collections==1,"profile editor collection ran per query character")
-- Unknown IDs fail closed even beside another valid widget with the same label.
local wrong={pageKey=repeatTarget.key,controlId="menu2.profiles.foreign.invalid",sectionId="profiles_variants"}
local selected,anchored,matched=routing.OpenSearchTarget("profiles","Variant","Variant",nil,nil,wrong)
assert(selected and not anchored and not matched,"unknown control used text/geometry fallback")
local names=e.MSUF_GetAllProfiles;local reads=0
local huge={};for i=1,5000 do huge[i]="Profile"..i end
e.MSUF_GetAllProfiles=function() reads=reads+1;return huge end
local bounded=M.ProfileSearch.Collect()
assert(#bounded==4000 and reads==1,"editor exceeded the existing provider row ceiling or repeated profile sorting")
e.MSUF_GetAllProfiles=names
local raid=Search("raid")[1];assert(raid and raid.key=="gf_layout" and raid.kind=="page","raid page is buried below an unrelated FAQ")
-- Size controls are discoverable while cold and select their exact range tab.
-- Opening another range or the base-size controls must never write settings.
do
 local cold={}
 for _,spec in ipairs({{"width","general","width"},{"frameScaleMode","general","scale mode"},
  {"tier10Width","tier10","1 10 width"},{"tier20Height","tier20","11 20 height"},
  {"tier25Growth","tier25","21 25 growth"},{"tier40X","tier40","26 horizontal position"},
  {"scaleAt20","tier20","11 20 group size scale"}}) do
  local suffix=".field."..spec[1]:lower()
  local row=FirstControl(spec[3],function(candidate)
   return candidate.key=="gf_layout" and candidate.exactTarget and Ends(candidate.exactTarget.controlId,suffix)
  end)
  assert(row.exactTarget.sectionId=="scaling" and row.exactTarget.prepareKind=="groupSizingTab"
   and row.exactTarget.prepareValue==spec[2],"cold sizing result lost exact tab: "..spec[1])
  cold[#cold+1]={row=row,tab=spec[2]}
 end
 M.SetMenuStateValue("gfScope","raid")
 local beforeSizing=F.CopySnapshot(e.MSUF_DB)
 for _,spec in ipairs(cold) do
  local _,widget=Navigate(spec.row)
  local node=widget
  while node and not node._msuf2GroupSizingTab do node=node.GetParent and node:GetParent() end
  assert(node and node._msuf2GroupSizingTab==spec.tab and node:IsShown(),"sizing result landed in hidden/wrong tab")
  assert(F.Equal(beforeSizing,e.MSUF_DB),"sizing search navigation changed settings")
 end
 local sections=M.cache.gf_layout.sections
 for _,id in ipairs({"layout_rules","resize_appearance","tier10","tier20","tier25","tier40"}) do
  assert(not sections[id],"obsolete sizing accordion remains: "..id)
 end
 local order=sections.anchor._msuf2CollapsibleEntry.builder.collapsibles
 local indices={}
 for i,entry in ipairs(order) do indices[entry.sectionId]=i end
 assert(indices.anchor==indices.general+1 and indices.scaling==indices.anchor+1,
  "group order must be Basics, Anchor, Size & Scaling")
 -- Warm search must retain the preparation contract after runtime registration.
 local warm=FirstControl("1 10 width",function(row)
  return row.key=="gf_layout" and row.exactTarget and Ends(row.exactTarget.controlId,".field.tier10width")
 end)
 Navigate(warm)
 local _,base=Navigate(cold[1].row)
 assert(F.Equal(beforeSizing,e.MSUF_DB),"warm sizing navigation changed settings")
end
print("search feature targets: "..flavor.." PASS (cold exact IDs, feature queries/client gates, profile identity/prepare, no mutation/fallback)")
