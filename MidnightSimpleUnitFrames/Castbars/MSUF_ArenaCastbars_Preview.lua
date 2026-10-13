--- Edit/menu previews for arena castbars: the arena descriptor of
--- MSUF_CastbarPoolPreviews.lua.
---
--- Every slot is suffixed (MSUF_ArenaCastbarPreview1..N, N from the arena pool:
--- MSUF.Client.MaxArenaOpponents). Frames.Get("arenaPreview", i) owns lookup.

local _, MSUF = ...
local Castbars = MSUF.Require("MSUF", "Castbars/MSUF_ArenaCastbars_Preview.lua").Castbars
local Pools = Castbars.Pools
local Previews = Castbars.Previews
local Publish = Castbars.PublicAPI.Publish

assert(Pools.DefinePreview, "MSUF_CastbarPoolPreviews.lua must load first")

local api = Pools.DefinePreview(Pools.kinds.arena, {
    namePrefix = "MSUF_ArenaCastbarPreview",
    firstUnsuffixed = false,
    indexField = "_msufArenaIndex",
    label = "Greater Pyroblast",
    targetLabel = "Arena Ally",
    showTargetKey = "showArenaCastTargetName",
    showTimeKey = "showArenaCastTime",
    testModeKey = "arenaCastbarTestMode",
}).api

Previews.UpdateArenaCastbarPreview = api.Update
Publish("MSUF_UpdateArenaCastbarPreview", Previews.UpdateArenaCastbarPreview)
