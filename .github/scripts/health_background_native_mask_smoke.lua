-- Native geometry/sampling model, not an in-client pixel/taint or CPU measurement.
-- Compare the old inverse StatusBar with the new anchored mask at the output
-- boundary, while making secret arithmetic in production Lua fail loudly.
local root, baseline = arg[1] or ".", arg[2]
local function failSecret() error("secret inspected by addon") end
local secret = setmetatable({}, {__add=failSecret,__sub=failSecret,__mul=failSecret,
  __div=failSecret,__lt=failSecret,__le=failSecret,__tostring=failSecret})
local function isSecret(v) return rawequal(v, secret) end
local function noop() end
local point = {TOPLEFT={0,1},TOPRIGHT={1,1},BOTTOMLEFT={0,0},BOTTOMRIGHT={1,0}}
local BLACK_OUTSIDE = "CLAMPTOBLACKADDITIVE"
local function Contains(r,x,y)
  return x>=r[1] and x<r[3] and y>=r[2] and y<r[4]
end
local function VisibleRect(texture)
  local visible=texture:GetRect()
  for mask in pairs(texture.masks) do
    local r=mask:GetRect()
    -- A solid white texture does not clip at its region bounds by itself:
    -- clamping/repeating white outside the UV range keeps revealing pixels.
    if mask.hWrap==BLACK_OUTSIDE then
      visible[1],visible[3]=math.max(visible[1],r[1]),math.min(visible[3],r[3])
    end
    if mask.vWrap==BLACK_OUTSIDE then
      visible[2],visible[4]=math.max(visible[2],r[2]),math.min(visible[4],r[4])
    end
  end
  return visible
end
-- Sample away from the frame's rounded corners. Fading must reveal the scene
-- under the filled health portion, not a full-width missing-health background.
local fades={{1,1,1},{.35,1,1},{1,.35,1},{1,.35,.35},{1,0,1}}
local function CheckRangeComposition(frame,axis,case)
  local fill=frame.hpBar.texture:GetRect()
  local background=VisibleRect(frame.hpBarBG)
  local checks=0
  for _,fraction in ipairs({.005,.25,.5,.75,.995}) do
    local x,y=120,18
    if axis=="VERTICAL" then y=36*fraction else x=240*fraction end
    local inFill=Contains(fill,x,y)
    local inBackground=Contains(background,x,y)
    for _,fade in ipairs(fades) do
      local fillAlpha=inFill and fade[1]*fade[2] or 0
      local bgAlpha=fade[1]*fade[3]
      -- Green-channel alpha composition: brown scene, green background,
      -- nearly black foreground, matching the reported 100%-HP failure.
      local function Composite(covered)
        local under=.11+(1-.11)*(covered and bgAlpha or 0)
        return .02*fillAlpha+under*(1-fillAlpha)
      end
      assert(math.abs(Composite(inBackground)-Composite(not inFill))<1e-8,
        "range fade exposes background beneath filled health at sample "..case.." ("..frame.MSUFUnitKey..", "..axis..")")
      checks=checks+1
    end
  end
  return checks
end
local function Run(sourceRoot)
  local hp, opaque, pending = 37, false, 0
  local reads, writes, maskBinds, maskCreates = 0, 0, 0, 0
  local SCALE, INVERSE = {}, {}
  _G.CurveConstants={ReverseTo100=INVERSE}
  _G.issecretvalue=isSecret
  _G.UnitHealthPercent=function(_,_,curve)
    reads=reads+1;pending=curve==INVERSE and 100-hp or hp
    return opaque and secret or pending
  end
  _G.UnitHealth=function() pending=hp;return opaque and secret or hp end
  _G.UnitHealthMax=function() return 100 end
  local health
  local C={WHITE="white",SCALE_100=SCALE,UnitHealthPercent=UnitHealthPercent,
    UnitHealth=UnitHealth,UnitHealthMax=UnitHealthMax,
    SnapBarInterpolation=function(bar) bar.current=bar.target;bar._msufInterpolating=nil end,
    SetBarSmoothing=function(bar,enabled,chunked)
      bar._msufSmoothInterp=(enabled or chunked) and 1 or nil
    end}
  local ns={UF={RegisterElement=function(_,v) health=v end},UFBarTextCommon=C}
  assert(loadfile(sourceRoot.."/MidnightSimpleUnitFrames/UnitFrames/Engine/Elements/MSUF_UF_Elements_Health.lua"))("MSUF",ns)
  local function Region()
    local r={points={}}
    function r:ClearAllPoints() self.points={};self.relative=nil end
    function r:SetAllPoints(other) self.relative=other end
    function r:SetPoint(p,other,q,x,y) self.points[#self.points+1]={p,other,q,x,y} end
    function r:GetRect()
      if self.relative then return self.relative:GetRect() end
      local a,b=self.points[1],self.points[2]
      if not a then return {0,0,240,36} end
      assert(b,"incomplete geometry")
      local ar,br=a[2]:GetRect(),b[2]:GetRect()
      local ap,bp=point[a[3]],point[b[3]]
      local ax,ay=ar[1]+ap[1]*(ar[3]-ar[1])+a[4],ar[2]+ap[2]*(ar[4]-ar[2])+a[5]
      local bx,by=br[1]+bp[1]*(br[3]-br[1])+b[4],br[2]+bp[2]*(br[4]-br[2])+b[5]
      local sa,sb=point[a[1]],point[b[1]]
      local w,h=(bx-ax)/(sb[1]-sa[1]),(by-ay)/(sb[2]-sa[2])
      return {ax-sa[1]*w,ay-sa[2]*h,ax+(1-sa[1])*w,ay+(1-sa[2])*h}
    end
    return r
  end
  local function Bar(parent,label)
    local b=Region();b.relative=parent;b.low,b.high,b.current,b.target=0,100,hp,hp
    function b:SetMinMaxValues(lo,hi) self.low,self.high=lo,hi end
    function b:SetValue(value,interp)
      writes=writes+1
      if isSecret(value) then value=pending end
      value=math.max(self.low,math.min(self.high,value))
      self.target=value
      if not interp then self.current=value end
    end
    function b:SetOrientation(axis) self.axis=axis end
    function b:SetReverseFill(v) self.reverse=v end
    b.Show,b.SetStatusBarColor=noop,noop
    local tex={masks={}}
    function tex:GetRect()
      local r=b:GetRect()
      local pct=(b.current-b.low)/(b.high-b.low)
      if b.axis=="VERTICAL" then
        if b.reverse then r[2]=r[4]-(r[4]-r[2])*pct else r[4]=r[2]+(r[4]-r[2])*pct end
      elseif b.reverse then r[1]=r[3]-(r[3]-r[1])*pct else r[3]=r[1]+(r[3]-r[1])*pct end
      return r
    end
    function tex:AddMaskTexture(mask) self.masks[mask]=true;maskBinds=maskBinds+1 end
    function tex:RemoveMaskTexture(mask)
      assert(self.masks[mask],"detached or foreign mask removed")
      self.masks[mask]=nil;maskBinds=maskBinds+1
    end
    function b:GetStatusBarTexture() return self.texture end
    function b:SetStatusBarTexture(asset) self.texture.asset=asset end
    function b:CreateMaskTexture()
      maskCreates=maskCreates+1
      local m=Region()
      function m:SetTexture(asset,hWrap,vWrap)
        self.asset,self.hWrap,self.vWrap=asset,hWrap,vWrap
      end
      return m
    end
    b.texture=tex
    return b
  end
  -- A mask MSUF does not own (the rounded surface puts one here). Health must
  -- never detach it, and must not stack its own clip mask on top of it.
  local function BuildFrame(group,axis,reverse,smooth)
    local frame=Region()
    frame.MSUFUnitKey=group and "raid1" or "target"
    local spec={scope=group and "group" or "single",health={mode="unified",
      backgroundColorMode="custom",backgroundFillMode="missing",vertical=axis=="VERTICAL",
      reverse=reverse,smooth=smooth,texture="foreground",backgroundTexture="pattern"}}
    frame.MSUFSpec=spec
    frame.hpBar=Bar(frame,"hp");frame.healthBackgroundBar=Bar(frame,"bg")
    frame.hpBarBG=frame.healthBackgroundBar.texture
    local foreign=Region();foreign.relative=frame
    foreign.hWrap,foreign.vWrap=BLACK_OUTSIDE,BLACK_OUTSIDE
    frame.hpBarBG.masks[foreign]=true
    return frame,spec,foreign
  end
  local samples,cases,compositionChecks={},0,0
  local steadyReads,steadyWrites,steadyInstructions=0,0,0
  for _,group in ipairs({false,true}) do
    for _,axis in ipairs({"HORIZONTAL","VERTICAL"}) do
      for _,reverse in ipairs({false,true}) do
        for _,smooth in ipairs({false,true}) do
          for _,restricted in ipairs({false,true}) do
            hp,opaque=37,restricted
            local frame,spec,foreign=BuildFrame(group,axis,reverse,smooth)
            health.Apply(frame,spec)
            local update=health.SelectUpdate(frame,spec)
            assert(frame.hpBarBG.masks[foreign],"foreign mask lost during apply")
            if health.SyncBackgroundPlan then assert(frame._msufHealthBackgroundMaskActive,"native mask not selected") end
            for _,value in ipairs({0,1,37,100,99,21,21,73,0,100}) do
              hp=value
              local nr,nw,nb,nm=reads,writes,maskBinds,maskCreates
              debug.sethook(function()
                local s=debug.getinfo(2,"S").source
                if s:find(sourceRoot.."/MidnightSimpleUnitFrames/",1,true) then steadyInstructions=steadyInstructions+1 end
              end,"",1)
              update(frame,"UNIT_HEALTH",frame.MSUFUnitKey)
              debug.sethook()
              steadyReads=steadyReads+reads-nr;steadyWrites=steadyWrites+writes-nw
              assert(nb==maskBinds and nm==maskCreates,"mask reconfigured by health tick")
              for step=1,6 do
                for _,bar in ipairs({frame.hpBar,frame.healthBackgroundBar}) do
                  bar.current=bar.current+(bar.target-bar.current)*.4
                end
                local visible=VisibleRect(frame.hpBarBG)
                samples[#samples+1]=visible;cases=cases+1
                compositionChecks=compositionChecks+CheckRangeComposition(frame,axis,cases)
              end
            end
            -- Settings/layout, text-only plan changes, chunked animation, and
            -- texture replacement must not leave stale native mask bindings.
            spec.health.backgroundFillMode="full";health.Apply(frame,spec)
            health.Apply(frame,spec)
            assert(frame.hpBarBG.masks[foreign],"full mode lost the foreign mask")
            if health.SyncBackgroundPlan then
              assert(not frame._msufHealthBackgroundMaskActive and not frame._msufHealthBackgroundNeedsValue)
              spec.health.backgroundFillMode="missing";health.Apply(frame,spec)
              spec.health.chunked=true;health.Apply(frame,spec)
              assert(not frame._msufHealthBackgroundMaskActive and frame._msufHealthBackgroundNeedsValue)
              spec.health.chunked=false;health.Apply(frame,spec)
              frame._msufTextRuntime={healthSlotCount=1,healthNeedsCurrent=true}
              health.SelectUpdate(frame,spec)
              assert(frame._msufHealthBackgroundMaskActive==group,"absolute/group plan mismatch")
              frame._msufTextRuntime=nil;health.SelectUpdate(frame,spec)
              local old=frame.hpBarBG
              frame.healthBackgroundBar.texture=Bar(frame,"replacement").texture
              frame.hpBarBG=frame.healthBackgroundBar.texture
              health.SelectUpdate(frame,spec)
              assert(not old.masks[frame._msufHealthBackgroundClipMask],"old texture kept native mask")
              assert(frame.hpBarBG.masks[frame._msufHealthBackgroundClipMask],"replacement unmasked")
              spec.health.backgroundFillMode="full";health.Apply(frame,spec)
              health.SelectUpdate(frame,spec)
              spec.health.backgroundFillMode="missing";health.Apply(frame,spec)
              assert(frame._msufHealthBackgroundMaskActive,"mask did not reattach after full mode")
            end
          end
        end
      end
    end
  end
  -- Issue #146. The rounded surface masks this exact texture, and two masks on
  -- one texture render the missing-health background wrong in the live renderer
  -- (the model above composes rects and cannot see it). Rounded frames must
  -- therefore keep the value-driven fill; everyone else keeps the clip mask.
  local gateChecks=0
  if health.SyncBackgroundPlan then
    hp,opaque=37,false
    local frame,spec,foreign=BuildFrame(false,"HORIZONTAL",false,false)
    _G.MSUF_RoundedUF_Active=true
    health.Apply(frame,spec)
    _G.MSUF_RoundedUF_Active=nil
    assert(not frame._msufHealthBackgroundMaskActive,"clip mask stacked on a rounded texture")
    assert(frame._msufHealthBackgroundNeedsValue,"rounded frames lost the value-driven fill")
    assert(frame.hpBarBG.masks[foreign],"rounded mask detached")
    local clip=frame._msufHealthBackgroundClipMask
    assert(not clip or not frame.hpBarBG.masks[clip],"clip mask bound while rounded")
    gateChecks=gateChecks+4

    -- Per-frame bookkeeping is the order-independent half of the same gate: it
    -- still holds while the master flag is briefly down (rounded just toggled).
    for _,key in ipairs({"_msufRGF_MaskedTextures","_msufRUF_MaskedTextures"}) do
      local f,s,fo=BuildFrame(false,"HORIZONTAL",false,false)
      f[key]={[f.hpBarBG]=fo}
      health.Apply(f,s)
      assert(not f._msufHealthBackgroundMaskActive,key.." did not gate the clip mask")
      assert(f._msufHealthBackgroundNeedsValue,key.." lost the value-driven fill")
      gateChecks=gateChecks+2
    end

    -- Without rounded the clip mask is still the selected route.
    local plain,plainSpec=BuildFrame(false,"HORIZONTAL",false,false)
    health.Apply(plain,plainSpec)
    assert(plain._msufHealthBackgroundMaskActive,"unrounded frames lost the native mask")
    assert(not plain._msufHealthBackgroundNeedsValue,"unrounded frames kept the value path")
    gateChecks=gateChecks+2

    -- The engine applies the rounded surface after Health (BarsCommon hands off
    -- at the end of its apply), so the clip mask can already be bound when the
    -- rounded mask arrives. MSUF_UF_RoundedFrames re-syncs at that moment; the
    -- re-sync has to retire the clip mask and leave the rounded one alone.
    local late,lateSpec,lateForeign=BuildFrame(false,"HORIZONTAL",false,false)
    health.Apply(late,lateSpec)
    local lateClip=late._msufHealthBackgroundClipMask
    assert(late.hpBarBG.masks[lateClip],"native mask not bound before the rounded pass")
    _G.MSUF_RoundedUF_Active=true
    late._msufRUF_MaskedTextures={[late.hpBarBG]=lateForeign}
    health.SyncBackgroundPlan(late,true)
    _G.MSUF_RoundedUF_Active=nil
    assert(not late.hpBarBG.masks[lateClip],"late rounded re-sync kept the clip mask")
    assert(late.hpBarBG.masks[lateForeign],"late rounded re-sync dropped the rounded mask")
    assert(late._msufHealthBackgroundNeedsValue,"late rounded re-sync lost the value fill")
    gateChecks=gateChecks+4
  end
  return samples,cases,steadyReads,steadyWrites,steadyInstructions,compositionChecks,gateChecks
end
local current,n,reads,writes,work,compositionChecks,gateChecks=Run(root)

-- The Health side can only gate on what it can see. Pin the rounded module's
-- half of the ordering contract: attaching a rounded mask to a texture that
-- already carries the clip mask must re-sync Health instead of stacking.
do
  local f=assert(io.open(root.."/MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua","rb"))
  local src=f:read("*a"):gsub("\r\n","\n");f:close()
  local attach=src:match("tex:AddMaskTexture%(m%)\n(.-)\n  return true")
  assert(attach,"rounded mask attachment point not found")
  assert(attach:find("_msufHealthBackgroundMaskActive",1,true)
    and attach:find("_msufHealthBackgroundMaskTexture",1,true)
    and attach:find("SyncBackgroundPlan",1,true),
    "rounded mask attachment no longer re-syncs the health background plan")
end
if baseline then
  local old,on,oldReads,oldWrites,oldWork=Run(baseline)
  assert(on==n)
  for i=1,n do for j=1,4 do
    assert(math.abs(current[i][j]-old[i][j])<1e-8,"geometry changed at sample "..i.." edge "..j)
  end end
  assert(reads<oldReads and writes<oldWrites and work<oldWork,"steady work not reduced")
  print(string.format("Native-mask model: %d matched geometry samples; native reads %d -> %d, writes %d -> %d, Health Lua instructions %d -> %d",
    n,oldReads,reads,oldWrites,writes,oldWork,work))
else
  print("Native-mask lifecycle/secret/geometry checks passed: "..n.." samples")
end
print("Range-fade composition checks passed: "..compositionChecks)
print("Rounded-surface gate checks passed: "..gateChecks.." (clip mask yields to the rounded mask)")
print("Live texture UV, pixel rounding, combat/taint and renderer cost remain client checks.")
