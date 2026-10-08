local root = assert(arg[1]) .. '/MidnightSimpleUnitFrames/'
local now, queue, shakes = 0, {}, 0
local function later(delay, fn)
    assert(type(delay) == 'number' and delay >= 0 and type(fn) == 'function')
    queue[#queue+1] = { at = now + math.max(delay, 1/120), fn = fn }
end
local function advance(seconds)
    local finish = now + seconds
    while true do
        local index, at
        for i, t in ipairs(queue) do if t.at <= finish and (not at or t.at < at) then index, at = i, t.at end end
        if not index then break end
        local t = table.remove(queue, index)
        now = t.at; t.fn()
    end
    now = finish
end
local function noop() end
local region = {}
function region:ClearAllPoints() self.points = {} end
function region:SetPoint(...) self.points = {...}; if self.name == 'MSUF_FocusKickIcon' and self.points[4] == 306 then shakes = shakes+1 end end
function region:SetAllPoints() end
function region:SetHeight(h) assert(type(h)=='number'); self.height=h end
function region:SetWidth(w) assert(type(w)=='number'); self.width=w end
function region:SetSize(w,h) self:SetWidth(w); self:SetHeight(h) end
function region:SetParent(p) assert(type(p)=='table'); self.parent=p end
function region:SetFrameStrata(s) assert(s=='HIGH') end
function region:SetFrameLevel(n) assert(type(n)=='number') end
function region:SetText(s) assert(type(s)=='string'); self.text=s end
function region:GetText() return self.text end
function region:SetAlpha(a) assert(type(a)=='number'); self.alpha=a end
function region:SetColorTexture(...) self.color={...} end
function region:SetVertexColor(...) self.color={...} end
function region:SetTextColor(...) self.color={...} end
function region:SetTexture(t) assert(type(t)=='string' or type(t)=='number'); self.texture=t end
function region:SetTexCoord(...) end
function region:SetJustifyH(s) assert(s=='CENTER') end
function region:SetDesaturated(b) assert(type(b)=='boolean') end
function region:Show() self.shown=true end
function region:Hide()
    local was=self.shown; self.shown=false
    if was then for _, fn in ipairs(self.hooks.OnHide or {}) do fn(self) end end
end
function region:IsShown() return self.shown end
function region:HookScript(event,fn) assert(event=='OnHide'); self.hooks[event]=self.hooks[event] or {}; table.insert(self.hooks[event],fn) end
function region:SetScript(event,fn) assert(event=='OnDragStart' or event=='OnDragStop'); assert(type(fn)=='function'); self.scripts[event]=fn end
function region:EnableMouse(b) assert(type(b)=='boolean') end
function region:SetMovable(b) assert(type(b)=='boolean') end
function region:RegisterForDrag(s) assert(s=='LeftButton') end
local function widget(kind,name,parent)
    return setmetatable({kind=kind,name=name,parent=parent,shown=true,hooks={},scripts={}}, {__index=function(_,k)
        if region[k] then return region[k] end
        if type(k)=='string' and k:match('^[A-Z]') then error('Unsupported widget method '..k) end
    end})
end
function region:CreateTexture(name,layer,template,sublevel) assert(not template); return widget('Texture',name,self) end
function region:CreateFontString(name,layer,template) assert(template=='GameFontNormalSmall'); return widget('FontString',name,self) end
function CreateFrame(kind,name,parent,template)
    assert(kind=='Frame' and template=='BackdropTemplate' and parent==UIParent)
    local f=widget(kind,name,parent); if name then _G[name]=f end; return f
end
UIParent=widget('Frame','UIParent')
C_Timer={After=later}
MSUF_DB={general={enableFocusKickIcon=true,showFocusCastTime=false},focus={enabled=true}}
MSUF_GetFontPath=function() return 'Fonts/FRIZQT__.TTF' end
MSUF_GetFontFlags=function() return 'OUTLINE' end
MSUF_ApplyResolvedFont=function(fs,path,size,flags) assert(fs.kind=='FontString'); fs.font={path,size,flags} end
MSUF_GetConfiguredFontColor=function() return 1,1,1 end
MSUF_KickReady_Init=noop
MSUF_KickReady_IsReady=function() return true end
MSUF_KickReady_EvaluateRGBA=function() return 0,1,0,1 end
local callback
local engine={Subscribe=function(self,unit,fn) assert(unit=='focus'); callback=fn; return true end,
    Unsubscribe=function(self,unit,fn) assert(callback==fn); callback=nil end}
local ns={MSUF_CastbarEngine=engine,ExportPublic=function(name,value) _G[name]=value end}
assert(loadfile(root..'Castbars/MSUF_FocusKickIcon.lua'))('Fixture',ns)
assert(loadfile(root..'Castbars/MSUF_FocusKick_StateDriver.lua'))('Fixture',ns)
MSUF_BuildCastState=function(unit) assert(unit=='focus'); return nil end
MSUF_FocusKickDriver_ForceUpdate(); advance(.01)
callback({active=true},'UNIT_SPELLCAST_START'); advance(.01)
assert(MSUF_FocusKickIcon:IsShown())
print('active: shown='..tostring(MSUF_FocusKickIcon:IsShown()))
local calls=0
local original=MSUF_FocusKickIcon.SetPoint
MSUF_FocusKickIcon.SetPoint=function(self,...)
    local a={...}; if a[4]==306 or a[4]==294 then calls=calls+1 end
    original(self,...)
end
callback(nil,'UNIT_SPELLCAST_INTERRUPTED')
print('interrupt synchronous: shown='..tostring(MSUF_FocusKickIcon:IsShown())..' shake_steps='..calls)
advance(1/120)
print('interrupt next frame: shown='..tostring(MSUF_FocusKickIcon:IsShown())..' shake_steps='..calls)
assert(MSUF_FocusKickIcon:IsShown(), 'feedback hidden on next frame')
advance(.20)
print('interrupt after 200ms: shown='..tostring(MSUF_FocusKickIcon:IsShown())..' shake_steps='..calls)
assert(calls==6 and not MSUF_FocusKickIcon:IsShown(), 'feedback did not finish all shake steps')
callback({active=true},'UNIT_SPELLCAST_START'); advance(.01)
calls=0
MSUF_FocusKick_PlayInterruptFeedback(); advance(.20)
print('feedback without immediate nil-state refresh: shown='..tostring(MSUF_FocusKickIcon:IsShown())..' shake_steps='..calls)
assert(calls==6)
