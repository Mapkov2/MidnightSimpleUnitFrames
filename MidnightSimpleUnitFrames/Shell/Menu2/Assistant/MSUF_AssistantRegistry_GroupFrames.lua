-- Assistant GroupFrames registry: declares group layout, bars, status, and copy controls.
-- It writes saved config and delegates secure/header refresh to GroupFrame runtime helpers.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

local Registry = A.Registry or { settings = {}, settingsByKey = {}, actions = {}, actionsByKey = {}, todos = {} }
A.Registry = Registry
A.Workflow = A.Workflow or {}

local C = A.RegistryCore
if type(C) ~= "table" then return end

-- GroupFrames registry domain.
-- Registers party/raid/mythicraid controls against the group DB. Group header rebuilds and
-- secure combat deferral remain in the group runtime, not in these assistant setters.
local Registry = C.Registry
local UNIT_LABELS = C.UNIT_LABELS
local AddAliasesForUnit = C.AddAliasesForUnit
local EnsureDB = C.EnsureDB
local GeneralDB = C.GeneralDB
local GroupDB = C.GroupDB
local ClampNumber = C.ClampNumber
local ApplyGroup = C.ApplyGroup
local GroupFramesData = A.GroupFramesRegistryData
if type(GroupFramesData) ~= "table" then return end

A.GroupFramesRegistry = A.GroupFramesRegistry or {}
local BuildGroupFramesCore = A.GroupFramesRegistry.BuildCoreContext
local GroupFramesCore = type(BuildGroupFramesCore) == "function" and BuildGroupFramesCore({
    Registry = Registry,
    UNIT_LABELS = UNIT_LABELS,
    AddAliasesForUnit = AddAliasesForUnit,
    EnsureDB = EnsureDB,
    GeneralDB = GeneralDB,
    GroupDB = GroupDB,
    ClampNumber = ClampNumber,
    ApplyGroup = ApplyGroup,
    GroupFramesData = GroupFramesData,
}) or nil
if type(GroupFramesCore) ~= "table" or type(GroupFramesCore.Settings) ~= "table" then return end

A.GroupFramesRegistry.Settings = GroupFramesCore.Settings
A.GroupFramesRegistry.Actions = {
    Registry = Registry,
    M = M,
    MSUF = MSUF,
    UNIT_LABELS = UNIT_LABELS,
    ResolveGroupStatusIcon = GroupFramesCore.ResolveGroupStatusIcon,
    ResetGroupStatusIcon = GroupFramesCore.ResetGroupStatusIcon,
    GROUP_STATUS_ICON_SPECS = GroupFramesCore.GROUP_STATUS_ICON_SPECS or {},
}
A.GroupFramesRegistry.SpellIndicators = {
    Registry = Registry,
    MSUF = MSUF,
    UNIT_LABELS = UNIT_LABELS,
    AddAliasesForUnit = AddAliasesForUnit,
    GroupDB = GroupDB,
    ClampNumber = ClampNumber,
    ApplyGroup = ApplyGroup,
}
