--- Auras3/MSUF_Auras3_UnitFrames.lua
--- WoW 12.1 native AuraContainer/AuraButton runtime.
---
--- MSUF 6.0 is 12.1-only for aura display work. This file intentionally does
--- not inspect or transform aura payload data itself. Blizzard's native
--- AuraContainer owns tracking, filtering, and assignment; MSUF only builds the
--- visual containers, initializeFrame customization, layout, and refresh surface.
local addonName, MSUF = ...
MSUF = MSUF or (_G.MSUF_NS) or {}

local ExportPublic = MSUF.ExportPublic or function(name, value)
    _G[name] = value
    return value
end

local A3 = MSUF.MSUF_Auras3
if type(A3) ~= "table" then
    A3 = {}
    MSUF.MSUF_Auras3 = A3
end
ExportPublic("MSUF_Auras3", A3)
local SpellIndicatorsRuntime = A3.SpellIndicators or {}
A3.SpellIndicators = SpellIndicatorsRuntime

local UF = MSUF.UF
if not (UF and UF.RegisterElement) then return end
if A3.__unitFrameBackendLoaded then return end
A3.__unitFrameBackendLoaded = true

-- Runtime responsibilities are loaded by MSUF_UFCore_Elements.xml.
-- Construct owners in dependency order and pass only their prerequisite roles.
-- Each factory captures its exact imports as locals; role tables are never
-- looked up on live paths. Resolve the four forward callbacks before publishing
-- the UF element. Deliberately dynamic A3 identity routes remain dynamic.
local factories = assert(MSUF.Auras3RuntimeFactories, "Auras3 runtime modules were not loaded")
local Platform = factories.Platform(addonName, MSUF, A3, UF, ExportPublic)
local Schema = factories.Schema(addonName, MSUF, A3, UF, ExportPublic)
local Appearance = factories.Appearance(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
})
local Sort = factories.Sort(addonName, MSUF, A3, UF, ExportPublic, {
    Schema = Schema,
})
local Signatures = factories.Signatures(addonName, MSUF, A3, UF, ExportPublic)
local ConfigValues = factories.ConfigValues(addonName, MSUF, A3, UF, ExportPublic, {
    Appearance = Appearance,
    Platform = Platform,
    Schema = Schema,
    Signatures = Signatures,
})
local DispelConfig = factories.DispelConfig(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    Appearance = Appearance,
    ConfigValues = ConfigValues,
})
local LaneConfig = factories.LaneConfig(addonName, MSUF, A3, UF, ExportPublic, {
    ConfigValues = ConfigValues,
    Platform = Platform,
    Schema = Schema,
    Sort = Sort,
    Appearance = Appearance,
})
local CustomConfig = factories.CustomConfig(addonName, MSUF, A3, UF, ExportPublic, {
    ConfigValues = ConfigValues,
    Platform = Platform,
    Schema = Schema,
    Sort = Sort,
    Appearance = Appearance,
})
local UnitConfig = factories.UnitConfig(addonName, MSUF, A3, UF, ExportPublic, {
    ConfigValues = ConfigValues,
    DispelConfig = DispelConfig,
    CustomConfig = CustomConfig,
    LaneConfig = LaneConfig,
})
local GroupConfig = factories.GroupConfig(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    DispelConfig = DispelConfig,
    LaneConfig = LaneConfig,
    ConfigValues = ConfigValues,
    Appearance = Appearance,
})
local DurationText = factories.DurationText(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    Schema = Schema,
})
local NativeContract = factories.NativeContract(addonName, MSUF, A3, UF, ExportPublic, {
    Schema = Schema,
    Platform = Platform,
    GroupConfig = GroupConfig,
})
local OwnerConfig = factories.OwnerConfig(addonName, MSUF, A3, UF, ExportPublic, {
    Signatures = Signatures,
})
local ButtonVisuals = factories.ButtonVisuals(addonName, MSUF, A3, UF, ExportPublic, {
    ConfigValues = ConfigValues,
    DurationText = DurationText,
    Platform = Platform,
    Schema = Schema,
    Appearance = Appearance,
    CustomConfig = CustomConfig,
    NativeContract = NativeContract,
})
local DispelVisuals = factories.DispelVisuals(addonName, MSUF, A3, UF, ExportPublic, {
    Appearance = Appearance,
    ConfigValues = ConfigValues,
    Platform = Platform,
    NativeContract = NativeContract,
})
local EffectPreview = factories.EffectPreview(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    DispelConfig = DispelConfig,
    Appearance = Appearance,
    DispelVisuals = DispelVisuals,
    ConfigValues = ConfigValues,
})
local Containers = factories.Containers(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    Sort = Sort,
    NativeContract = NativeContract,
    Schema = Schema,
    Appearance = Appearance,
    DispelVisuals = DispelVisuals,
    ConfigValues = ConfigValues,
    CustomConfig = CustomConfig,
    ButtonVisuals = ButtonVisuals,
    Signatures = Signatures,
})
local Identity = factories.Identity(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    OwnerConfig = OwnerConfig,
    ConfigValues = ConfigValues,
})
local Presence = factories.Presence(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    Identity = Identity,
    Containers = Containers,
})
local IdentityEvents = factories.IdentityEvents(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    Identity = Identity,
    Presence = Presence,
})
local NativeApply = factories.NativeApply(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    Containers = Containers,
    Sort = Sort,
    NativeContract = NativeContract,
    DurationText = DurationText,
    OwnerConfig = OwnerConfig,
    ConfigValues = ConfigValues,
    Identity = Identity,
    Signatures = Signatures,
    CustomConfig = CustomConfig,
    ButtonVisuals = ButtonVisuals,
    Appearance = Appearance,
})

-- Bind captured callbacks only after every native/configuration owner exists.
NativeContract.Bind({
    RefreshAppliedNativeRoot = NativeApply.RefreshAppliedNativeRoot,
})
NativeContract.Bind = nil
Containers.Bind({
    RegisterNativeContainer = NativeApply.RegisterNativeContainer,
})
Containers.Bind = nil
IdentityEvents.Bind({
    ApplyLane = NativeApply.ApplyLane,
    RecreateGroupSlots = NativeApply.RecreateGroupSlots,
})
IdentityEvents.Bind = nil
NativeApply.Initialize()
NativeApply.Initialize = nil

-- Public registration is last: callbacks cannot observe partially wired modules.
factories.Facade(addonName, MSUF, A3, UF, ExportPublic, {
    Platform = Platform,
    NativeApply = NativeApply,
    IdentityEvents = IdentityEvents,
    NativeContract = NativeContract,
    GroupConfig = GroupConfig,
    Schema = Schema,
    UnitConfig = UnitConfig,
    ConfigValues = ConfigValues,
})
MSUF.Auras3RuntimeFactories = nil
