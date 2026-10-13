--- Edit/menu previews for boss castbars: the boss descriptor of
--- MSUF_CastbarPoolPreviews.lua.
---
--- Slot 1 is MSUF_BossCastbarPreview, slots 2..N are MSUF_BossCastbarPreview<N>.
--- The batch API (MSUF_BeginBossCastbarPreviewBatch/EndBossCastbarPreviewBatch)
--- folds the refreshes of a multi-setting apply into one. The preview globals
--- stay as compatibility aliases of the pool preview module.

local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_BossCastbars_Preview.lua").Castbars
local Pools = Castbars.Pools
local Previews = Castbars.Previews
local Publish = Castbars.PublicAPI.Publish

assert(Pools.DefinePreview, "MSUF_CastbarPoolPreviews.lua must load first")

local api = Pools.DefinePreview(Pools.kinds.boss, {
    namePrefix = "MSUF_BossCastbarPreview",
    firstUnsuffixed = true,
    indexField = "_msufBossIndex",
    label = "Celestial Ruin",
    targetLabel = "Cleave Training Dummy",
    showTargetKey = "showBossCastTargetName",
    showTimeKey = "showBossCastTime",
    testModeKey = "bossCastbarTestMode",
}).api

Previews.BeginBossCastbarPreviewBatch = api.BeginBatch
Publish("MSUF_BeginBossCastbarPreviewBatch", Previews.BeginBossCastbarPreviewBatch)
Previews.EndBossCastbarPreviewBatch = api.EndBatch
Publish("MSUF_EndBossCastbarPreviewBatch", Previews.EndBossCastbarPreviewBatch)
Previews.UpdateBossCastbarPreview = api.Update
Publish("MSUF_UpdateBossCastbarPreview", Previews.UpdateBossCastbarPreview)
