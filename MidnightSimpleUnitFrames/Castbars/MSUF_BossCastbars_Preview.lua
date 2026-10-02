--- Castbars/MSUF_BossCastbars_Preview.lua
--- Edit/menu previews for boss castbars: the boss descriptor of
--- MSUF_CastbarPoolPreviews.lua.
---
--- Slot 1 is MSUF_BossCastbarPreview, slots 2..N are MSUF_BossCastbarPreview<N>.
--- The batch API (MSUF_BeginBossCastbarPreviewBatch/EndBossCastbarPreviewBatch)
--- folds the refreshes of a multi-setting apply into one. The preview globals
--- stay as compatibility aliases of the pool preview module.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local ExportPublic = MSUF.ExportPublic

local Pools = assert(MSUF.Castbars and MSUF.Castbars.Pools, "MSUF_CastbarPools.lua must load first")
assert(Pools.DefinePreview, "MSUF_CastbarPoolPreviews.lua must load first")

local api = Pools.DefinePreview(Pools.kinds.boss, {
    namePrefix = "MSUF_BossCastbarPreview",
    firstUnsuffixed = true,
    publishFirstSlot = function(frame) ExportPublic("MSUF_BossCastbarPreview", frame) end,
    indexField = "_msufBossIndex",
    label = "Celestial Ruin",
    targetLabel = "Cleave Training Dummy",
    showTargetKey = "showBossCastTargetName",
    showTimeKey = "showBossCastTime",
    testModeKey = "bossCastbarTestMode",
}).api

ExportPublic("MSUF_BeginBossCastbarPreviewBatch", api.BeginBatch)
ExportPublic("MSUF_EndBossCastbarPreviewBatch", api.EndBatch)
ExportPublic("MSUF_UpdateBossCastbarPreview", api.Update)
ExportPublic("MSUF_HideAllBossCastbarPreviews", api.HideAll)
ExportPublic("MSUF_CreateBossCastbarPreview", api.Create)
ExportPublic("MSUF_ApplyBossCastbarPreviewLayout", api.ApplyLayout)
ExportPublic("MSUF_PositionBossCastbarPreview", api.Position)
