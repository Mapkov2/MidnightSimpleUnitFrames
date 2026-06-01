local l=5 local r=10
local function o()local e=MSUF_DB
local t=e and e.general or nil local a=e and e.player and e.player.castbar or nil
local n=a and a.channelTickUseCustom==true if not n and not(t and t.castbarShowChannelTicks==true)then
return false,0,nil,false end
local e=n and tonumber(a.channelTickCount)or l e=e or l
if e<0 then e=0
elseif e>r then e=r
end return e>0,e,n and a.channelTickPosPct or nil,n
end local function i()local e=o()return e==true
end local function d(e,t)if not(e and e.unit=="player")then return end local n=e.statusBar
if not(n and n.CreateTexture)then return end local a=e._msufPlayerChannelHasteMarkers
if not a then a={}e._msufPlayerChannelHasteMarkers=a end
t=t or l for t=1,t do
if a[t]then else
local e=n:CreateTexture(nil,"OVERLAY",nil,7)e:SetColorTexture(1,1,1,1)if e.SetAlpha then e:SetAlpha(1)end e:SetWidth(2)e:SetPoint("TOP",n,"TOP",0,0)e:SetPoint("BOTTOM",n,"BOTTOM",0,0)e:Hide()a[t]=e
end end
if not e._msufPlayerChannelHasteMarkersHooked and n.HookScript then e._msufPlayerChannelHasteMarkersHooked=true
n:HookScript("OnSizeChanged",function()if e then
e._msufPlayerChannelHasteMarkersForce=true end
end)end
end local function h(e,n)local e=e and e._msufPlayerChannelHasteMarkers if not e then return end
for n=n,#e do local e=e[n]if e and e.Hide then e:Hide()end end
end local function s(e)local n=e and e._msufPlayerChannelHasteMarkers if not n then return end
for e=1,#n do local e=n[e]if e and e.Hide then e:Hide()end end
if e then e._msufPlayerChannelHasteMarkersLastW=nil
e._msufPlayerChannelHasteMarkersLastF=nil end
end local function r(e,a)if not(e and e.unit=="player")then return end local n,l,r,i=o()if not n then s(e)return end
if not(e.MSUF_isChanneled and not e.isEmpower)then s(e)return end
local n=e.statusBar if not(n and n.GetWidth)then return end
d(e,l)local o=e._msufPlayerChannelHasteMarkers
if not o then return end local t=n:GetWidth()or 0
if t<=1 then t=e._msufPlayerChannelHasteMarkersLastW or 200
e._msufPlayerChannelHasteMarkersForce=true end
if e._msufPlayerChannelHasteMarkersForce then a=true
e._msufPlayerChannelHasteMarkersForce=nil end
local s=e._msufPlayerChannelHasteMarkersLastW if not a and s==t then
else e._msufPlayerChannelHasteMarkersLastW=t
e._msufPlayerChannelHasteMarkersLastF=nil local d=(e._msufStripeReverseFill==true)local s=l+1 for l=1,l do
local e=o[l]if e and e.SetPoint then
if e.SetAlpha then e:SetAlpha(1)end local a
if i and type(r)=="table"and type(r[l])=="number"then local e=r[l]if e<0 then e=0 elseif e>100 then e=100 end a=t*(e/100)else local e=l/s
if e<0.02 then e=0.02 end if e>0.98 then e=0.98 end
a=t*e end
e:ClearAllPoints()if d then
e:SetPoint("TOP",n,"TOPRIGHT",-a,0)e:SetPoint("BOTTOM",n,"BOTTOMRIGHT",-a,0)else e:SetPoint("TOP",n,"TOPLEFT",a,0)e:SetPoint("BOTTOM",n,"BOTTOMLEFT",a,0)end
end end
h(e,l+1)end
for e=1,l do local e=o[e]if e then if e.SetAlpha then e:SetAlpha(1)end
if e.Show then e:Show()end end
end end
function _G.MSUF_UpdateCastbarChannelTicks()r(_G.MSUF_PlayerCastbar,true)r(_G.MSUF_PlayerCastbarPreview,true)end
_G.MSUF_IsChannelTickLinesEnabled=i _G.MSUF_PlayerChannelHasteMarkers_Update=r
_G.MSUF_PlayerChannelHasteMarkers_Hide=s _G.MSUF_PlayerChannelHasteMarkers_Ensure=d
_G.MSUF_ApplyPlayerChannelTickMarkers=_G.MSUF_UpdateCastbarChannelTicks