-- Options/MSUF_Options_Portraits.lua
-- v4.324: the standalone Global Style > Portraits page is retired.
--
-- Portrait editing now lives inside each Unit Frame page:
-- Player/Target/Target of Target/Focus/Boss/Pet > Portrait.
--
-- This file stays in the TOC as a compatibility stub for older callers/addon
-- load orders. It intentionally registers no separate Settings page and keeps
-- no shared/override portrait UI alive.

local addonName, ns = ...
ns = ns or {}

function ns.MSUF_RegisterPortraitsOptions_Full()
    return nil
end

function ns.MSUF_RegisterPortraitsOptions()
    return nil
end

