-- Each slice below is one function, cut at its own `end`; it used to stop at
-- the declaration that happened to follow, which is not a boundary.
local Slice = assert(loadfile(".github/scripts/msuf_source_slice.lua"),
    "rounded_forbidden_mask_owner_smoke must run with the repository root as the working directory")()
local Read = Slice.Read
local ROUNDED = "MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedFrames.lua"
local DISPEL = "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_DispelVisuals.lua"
local PREVIEW = "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_EffectPreview.lua"
local FACADE = "MidnightSimpleUnitFrames/Auras3/Runtime/MSUF_Auras3_Runtime_Facade.lua"

local rounded = Read(ROUNDED)
assert(not rounded:find("_msufRoundedMaskOwners", 1, true),
    "native forbidden regions must not retain a mutable rounded owner registry")

-- Reason: the assertions are about how one preparation function configures a
-- mask before handing the region to Blizzard.
local prepareSource = Slice.Function(rounded, "local function PrepareFrozenDispelOverlayMask", ROUNDED)
assert(not prepareSource:find("ClearAllPoints", 1, true),
    "fresh native dispel masks must not perform redundant point clearing")
assert(not prepareSource:find("MaskedTextures", 1, true),
    "frozen native dispel masks entered the mutable rounded mask registry")
local setTexture = assert(prepareSource:find("mask:SetTexture", 1, true),
    "frozen native dispel mask texture setup missing")
local setPoints = assert(prepareSource:find("mask:SetAllPoints", 1, true),
    "frozen native dispel mask layout missing")
local addMask = assert(prepareSource:find("region:AddMaskTexture(mask)", 1, true),
    "frozen native dispel mask binding missing")
assert(setTexture < setPoints and setPoints < addMask,
    "native dispel mask is not fully configured before binding")

local compile = loadstring or load
local harness = [[
local calls = {}
local roundedMaskPath = "rounded-mask"
local anchor = {}
local function IsCombatLocked() return false end
local function DeferApply() error("unexpected defer") end
local function FrameIsGroup() return true end
local function RoundedGroupFramesEnabled() return true end
local function RoundedUnitFramesEnabled() return true end
local function RoundedFrameEnabled() return true end
local function RoundedPowerBarsEnabled() return false end
local function SurfaceMaskPath() return roundedMaskPath end
local function PowerIsEmbedded() return false end
local function CanCreateRoundedRegion() return true end
local function UpdateRoundedMediaState() calls[#calls + 1] = "media" end
local function SE_SnapOff(mask) mask:SnapOff() end
local function ApplyRoundedMediaSlice(mask, path) mask:Slice(path) end
]] .. prepareSource .. [[

return PrepareFrozenDispelOverlayMask, calls, anchor
]]
local prepare, calls, anchor = assert(compile(harness))()
local sealed = false
local mask = {
    SnapOff = function() assert(not sealed); calls[#calls + 1] = "snap" end,
    SetTexture = function(_, path) assert(not sealed and path == "rounded-mask"); calls[#calls + 1] = "texture" end,
    SetAllPoints = function(_, target) assert(not sealed and target == anchor); calls[#calls + 1] = "points" end,
    Slice = function(_, path) assert(not sealed and path == "rounded-mask"); calls[#calls + 1] = "slice" end,
    ClearAllPoints = function() assert(not sealed, "forbidden ClearAllPoints") end,
}
local owner = {
    CreateMaskTexture = function()
        calls[#calls + 1] = "create"
        return mask
    end,
}
local region = {
    AddMaskTexture = function(_, value)
        assert(value == mask)
        calls[#calls + 1] = "bind"
    end,
}
local frame = { health = anchor }
assert(prepare(frame, region, owner) == true, "frozen native dispel mask preparation failed")
assert(table.concat(calls, ",") == "media,create,snap,texture,points,slice,bind",
    "frozen native dispel mask setup order changed: " .. table.concat(calls, ","))
sealed = true
assert(not pcall(mask.ClearAllPoints),
    "test mask did not model the post-AddDispelTypeTexture forbidden state")

local dispel = Read(DISPEL)
local nilSensorPrepare = assert(compile("local A3={}\n"
    .. Slice.Function(dispel, "local function PrepareDispelSensorVisual", DISPEL)
    .. "\nreturn PrepareDispelSensorVisual"))()
assert(nilSensorPrepare(nil, nil, nil) == false, "nil dispel inputs did not return before capturing visuals")
local preview = Read(PREVIEW)
local facade = Read(FACADE)
local initializerStart = assert(dispel:find("local function PrepareDispelSensorVisual", 1, true))
local initializerEnd = assert(dispel:find("\nreturn {", initializerStart, true))
local overlayStart = assert(dispel:find('if sensor%.visual == "overlay" then%s+region:SetTexture%(', initializerStart))
local overlayBranch = dispel:sub(overlayStart, initializerEnd - 1)
local prepareCall = assert(overlayBranch:find(
    "PrepareRoundedDispelOverlayRegion(parentFrame, region, button)", 1, true),
    "native dispel overlay is not prepared with its explicit owner")
local blizzardHandoff = assert(overlayBranch:find(
    "owner:AddDispelTypeTexture(region, GetSensorOverlayOptions(sensor._msufA3NativeVisualInputs))", 1, true),
    "native dispel overlay Blizzard handoff missing")
assert(prepareCall < blizzardHandoff,
    "native dispel overlay is masked after Blizzard makes it forbidden")
assert(not dispel:find("RegisterRoundedDispelOverlayRegion", 1, true),
    "legacy post-handoff native dispel registration remains")
assert(preview:find("RegisterRoundedDispelOverlayPreviewRegion(frame, region)", 1, true),
    "MSUF-owned dispel overlay preview lost its mutable rounded registration")
assert(facade:find("function A3.RefreshRoundedDispelOverlayMasks()", 1, true),
    "rounded setting changes cannot recreate frozen native dispel masks")
assert(facade:find("A3.InvalidateNativeVisualInputs()", 1, true),
    "native dispel-mask recreation does not invalidate the content memo")
assert(facade:find("A3._roundedDispelVisualSignature == signature", 1, true),
    "unchanged rounded signatures still recreate native dispel masks")
-- Reason: the module-apply callback and the settings apply function are one
-- function each.
local modulesApplied = Slice.Function(rounded,
    'ExportPublic("MSUF_RoundedUF_OnModulesApplied", function', ROUNDED)
assert(modulesApplied:find("RefreshFrozenDispelOverlayMasks()", 1, true),
    "profile/module applies do not recreate frozen native dispel masks")
local applyRounded = Slice.Function(rounded, "local function ApplyRoundedUnitframes", ROUNDED)
assert(applyRounded:find("RefreshFrozenDispelOverlayMasks()", 1, true),
    "direct rounded setting changes do not recreate frozen native dispel masks")

-- Per-frame content and native mask preparation agree on live inputs, while
-- the settings signature stays unchanged. Use the real refresh bridge.
do
    local unitHealth,groupHealth,groupBars={},{},{}
    local unit={MSUFUnitKey="target",MSUFSpec={power={enabled=true,embed=true}},hpBar=unitHealth}
    local group={_msufIsGroupFrame=true,_msufGFKind="party",health=groupHealth,barGroup=groupBars,
        MSUFSpec={scope="group",power={enabled=true,embed=true}}}
    local msuf={UF={ForEachFrame=function(fn)fn(unit)end},GF={ForEachFrame=function(fn)fn(group)end},
        ExportPublic=function()end}
    _G.MSUF_DB={bars={roundedFramesEnabled=true,roundedPowerBars=true}}
    assert(loadfile("MidnightSimpleUnitFrames/UnitFrames/Effects/MSUF_UF_RoundedSurface.lua"))("MSUF",msuf)
    local kit=msuf.RoundedSurfaceKit
    local powerEmbedded=kit.PowerIsEmbedded
    if not powerEmbedded then
        powerEmbedded=assert(compile(Slice.Function(rounded,"local function PowerIsEmbedded",ROUNDED)
            .."\nreturn PowerIsEmbedded"))()
    end
    local nativePrepare=assert(compile([[
        local kit,PowerIsEmbedded=...
        local FrameIsGroup,RoundedFrameEnabled=kit.FrameIsGroup,kit.RoundedFrameEnabled
        local RoundedPowerBarsEnabled,SurfaceMaskPath=kit.RoundedPowerBarsEnabled,kit.SurfaceMaskPath
        local IsCombatLocked,DeferApply=kit.IsCombatLocked,kit.DeferApply
        local CanCreateRoundedRegion,UpdateRoundedMediaState=kit.CanCreateRoundedRegion,kit.UpdateRoundedMediaState
        local SE_SnapOff,ApplyRoundedMediaSlice=function()end,function()end
    ]]..prepareSource.."\nreturn PrepareFrozenDispelOverlayMask"))(kit,powerEmbedded)
    local builds=0
    local owner={CreateMaskTexture=function()
        return {SetTexture=function()end,SetAllPoints=function(self,target)self.anchor=target end}
    end}
    local latest={}
    local function BuildMask(frame)
        builds=builds+1
        latest[frame]=nil
        local region={AddMaskTexture=function(_,mask)latest[frame]=mask end}
        nativePrepare(frame,region,owner)
        frame.Auras={_msufA3Applied=true,_msufA3DispelFrameSignature=kit.DispelFrameSignature(frame)}
    end
    local function BuildMasks()
        for _,frame in ipairs({unit,group}) do
            BuildMask(frame)
        end
        return true
    end
    local auras={_runtimeFrames={target=unit},InvalidateNativeVisualInputs=function()end,
        RenderFrame=BuildMask,RefreshAll=BuildMasks}
    local install=assert(compile("local A3,MSUF=...\n"
        ..Slice.Function(facade,"local function RefreshFrameDispelMasks",FACADE).."\n"
        ..Slice.Function(facade,"local function InstallVisualInteractions",FACADE)
        .."\nreturn InstallVisualInteractions"))(auras,msuf)
    install(auras,msuf,function()return false end,kit.DispelFrameSignature)
    msuf.MSUF_Auras3=auras
    local refresh=assert(compile("local Kit,MSUF=...\n"
        ..Slice.Function(rounded,"local function RefreshFrozenDispelOverlayMasks",ROUNDED)
        .."\nreturn RefreshFrozenDispelOverlayMasks"))(kit,msuf)
    refresh()
    local global=kit.DispelVisualSignature()
    assert(latest[unit].anchor==unit and latest[group].anchor==groupBars,"embedded rounded masks missed shared anchors")
    unit.MSUFSpec.power.detached=true
    group.MSUFSpec.power.embed=false
    refresh()
    assert(builds==4,"embed/detach changes were missing from the per-frame content gate")
    assert(latest[unit].anchor==unitHealth and latest[group].anchor==groupHealth,"detached masks kept embedded anchors")
    unit.MSUFSpec.power.detached=false
    group.MSUFSpec.power.embed=true
    refresh()
    assert(builds==6 and latest[unit].anchor==unit and latest[group].anchor==groupBars,"embedded mask restore kept detached anchors")
    unit._msufRUFForcedStyle="SQUARE"
    refresh()
    assert(builds==7 and latest[unit]==nil,"forced frame style was missing from the per-frame content gate")
    unit._msufRUFForcedStyle="ROUNDED"
    refresh()
    assert(builds==8 and latest[unit].anchor==unit,"forced rounded style did not restore its mask")
    refresh()
    assert(builds==8,"unchanged live frame inputs rebuilt rounded masks")
    assert(kit.DispelVisualSignature()==global,"live frame inputs changed global rounded settings content")
end

io.write("rounded_forbidden_mask_owner_smoke: ok\n")
