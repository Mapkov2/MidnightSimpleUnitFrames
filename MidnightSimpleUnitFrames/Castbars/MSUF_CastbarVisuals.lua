local e=_G.MSUF_UpdateCastbarVisuals
local function r(a)if not(a and a.statusBar)then return end
if a.ApplyLayout then a:ApplyLayout()end
if type(_G.MSUF_ApplyCastbarOutline)=="function"then _G.MSUF_ApplyCastbarOutline(a,false)end
if type(_G.MSUF_KickReady_ApplyLayout)=="function"then _G.MSUF_KickReady_ApplyLayout(a)end
if type(_G.MSUF_KickReady_RefreshFrame)=="function"and a.MSUF_castActive then _G.MSUF_KickReady_RefreshFrame(a,nil)end
if a.backgroundBar and type(_G.MSUF_GetCastbarBackgroundColor)=="function"then
local r,n,t,e=_G.MSUF_GetCastbarBackgroundColor()a.backgroundBar:SetVertexColor(r or 0.176,n or 0.176,t or 0.176,e or 1)end
if a.statusBar and type(_G.MSUF_RefreshCastbarStyleCache)=="function"then
_G.MSUF_RefreshCastbarStyleCache(a)if a.MSUF_cachedCastbarTexture then a.statusBar:SetStatusBarTexture(a.MSUF_cachedCastbarTexture)end
if a.backgroundBar and a.MSUF_cachedCastbarBackgroundTexture then a.backgroundBar:SetTexture(a.MSUF_cachedCastbarBackgroundTexture)end
end
end
function _G.MSUF_UpdateCastbarVisuals(...)if type(e)=="function"and e~=_G.MSUF_UpdateCastbarVisuals then e(...)end
local a=_G.MSUF_BossCastbars
if type(a)=="table"then for e=1,#a do r(a[e])end end
end