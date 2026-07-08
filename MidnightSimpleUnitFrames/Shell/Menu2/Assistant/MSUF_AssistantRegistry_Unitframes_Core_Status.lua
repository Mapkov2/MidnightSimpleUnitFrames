-- Assistant UnitFrames status helper core.
-- Builds status-icon resolver and apply helpers for the shared UnitFrames registry core.
local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or {}

local M = MSUF.MSUF2 or _G.MSUF2 or {}
MSUF.MSUF2 = M

local A = MSUF.Assistant or {}
MSUF.Assistant = A
M.Assistant = A

A.UnitframesRegistry = A.UnitframesRegistry or {}

function A.UnitframesRegistry.BuildStatusCoreContext(ctx)
    if type(ctx) ~= "table" then return nil end

    local UnitframeData = ctx.UnitframeData
    local ApplyUnit = ctx.ApplyUnit
    local CallGlobal = ctx.CallGlobal

    if type(UnitframeData) ~= "table" then return nil end
    if type(ApplyUnit) ~= "function" or type(CallGlobal) ~= "function" then return nil end

    local STATUS_CONTROL_SPEC_DATA = UnitframeData.STATUS_CONTROL_SPECS
    local STATUS_TEXT_STATE_SPECS = UnitframeData.STATUS_TEXT_STATE_SPECS

    local function ExpandStatusAliases(aliases)
        local out = {}
        local seen = {}
        local function add(value)
            value = tostring(value or "")
            if value == "" or seen[value] then return end
            seen[value] = true
            out[#out + 1] = value
        end
        for i = 1, #(aliases or {}) do
            local alias = tostring(aliases[i] or "")
            add(alias)
            if alias:find("raid marker", 1, true) then
                add(alias:gsub(" marker", " indicator"))
                add(alias:gsub(" marker", " icon"))
                add(alias:gsub(" marker", " symbol"))
            end
            if alias:find(" icon", 1, true) then
                add(alias:gsub(" icon", " indicator"))
                add(alias:gsub(" icon", " symbol"))
            end
            if alias:find(" indicator", 1, true) then
                add(alias:gsub(" indicator", " icon"))
                add(alias:gsub(" indicator", " symbol"))
            end
            if alias:find(" symbol", 1, true) then
                add(alias:gsub(" symbol", " icon"))
                add(alias:gsub(" symbol", " indicator"))
            end
        end
        return out
    end

    local function ApplyStatus(unit, reason, statusRuntime, level, runtimeRefreshed)
        if statusRuntime and not runtimeRefreshed then
            CallGlobal("MSUF_RefreshStatusIndicators", unit, reason or "MSUF_ASSISTANT_STATUS")
        end
        if level then
            if unit == "boss" and _G.MSUF_BossTestMode and type(_G.MSUF_ApplyBossUnitframePreviewState) == "function" then
                _G.MSUF_ApplyBossUnitframePreviewState(true, reason or "MSUF_ASSISTANT_STATUS")
            end
        end
        ApplyUnit(unit, reason or "MSUF_ASSISTANT_STATUS", { preview = true, text = true, fonts = level })
    end

    local function ApplyStatusRefresh(unit, refresh, statusRuntime, level)
        local runtimeRefreshed = false
        if refresh then
            CallGlobal(refresh, unit, "MSUF_ASSISTANT_STATUS")
            runtimeRefreshed = true
        end
        ApplyStatus(unit, "MSUF_ASSISTANT_STATUS", statusRuntime, level, runtimeRefreshed)
    end

    local function StatusIconOpts(spec, opts)
        opts = opts or {}
        opts.category = "Status Icons"
        opts.frameType = opts.frameType or "unitframe"
        opts.refresh = opts.refresh or (spec and spec.refresh)
        opts.applyOpts = opts.applyOpts or { preview = true, text = true }
        return opts
    end

    local function ApplyStatusTextState()
        CallGlobal("MSUF_RequestStatusTextRefresh")
        ApplyUnit("player", "MSUF_ASSISTANT_STATUS_TEXT_STATE", { preview = true, text = true })
    end

    local STATUS_CONTROL_SPECS = {}
    for i = 1, #(STATUS_CONTROL_SPEC_DATA or {}) do
        local source = STATUS_CONTROL_SPEC_DATA[i]
        local spec = {}
        for key, value in pairs(source) do
            spec[key] = value
        end
        spec.aliases = ExpandStatusAliases(source.aliases)
        STATUS_CONTROL_SPECS[i] = spec
    end

    local function NormalizeStatusPhrase(text)
        text = tostring(text or ""):lower()
        text = text:gsub("target%s+of%s+target", "targettarget")
        text = text:gsub("focus%s+target", "focustarget")
        text = text:gsub("[\"'`]", "")
        text = text:gsub("[^%w]+", " ")
        return (text:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " "))
    end

    local function StatusPhraseContains(text, phrase)
        phrase = NormalizeStatusPhrase(phrase)
        if phrase == "" then return false end
        return (" " .. text .. " "):find(" " .. phrase .. " ", 1, true) ~= nil
    end

    local function StatusSpecAllowed(unit, spec)
        return spec and (not spec.units or spec.units[unit] == true)
    end

    local function ResolveUnitStatusSpec(unit, text)
        text = NormalizeStatusPhrase(text)
        for i = 1, #STATUS_CONTROL_SPECS do
            local spec = STATUS_CONTROL_SPECS[i]
            if StatusSpecAllowed(unit, spec) then
                if StatusPhraseContains(text, spec.label) or StatusPhraseContains(text, spec.value) then return spec end
                for j = 1, #(spec.aliases or {}) do
                    if StatusPhraseContains(text, spec.aliases[j]) then return spec end
                end
            end
        end
        return nil
    end

    return {
        ApplyStatusRefresh = ApplyStatusRefresh,
        ApplyStatusTextState = ApplyStatusTextState,
        ResolveUnitStatusSpec = ResolveUnitStatusSpec,
        StatusIconOpts = StatusIconOpts,
        STATUS_CONTROL_SPECS = STATUS_CONTROL_SPECS,
        STATUS_TEXT_STATE_SPECS = STATUS_TEXT_STATE_SPECS,
        STATUS_ICON_PACK_FALLBACK_VALUES = UnitframeData.STATUS_ICON_PACK_FALLBACK_VALUES,
        STATUS_SYMBOL_ALIASES = UnitframeData.STATUS_SYMBOL_ALIASES,
        STATUS_ANCHOR_VALUES = UnitframeData.STATUS_ANCHOR_VALUES,
        STATUS_CORNER_ANCHOR_VALUES = UnitframeData.STATUS_CORNER_ANCHOR_VALUES,
        STATUS_ANCHOR_ALIASES = UnitframeData.STATUS_ANCHOR_ALIASES,
        RAID_GROUP_STYLE_VALUES = UnitframeData.RAID_GROUP_STYLE_VALUES,
        RAID_GROUP_STYLE_ALIASES = UnitframeData.RAID_GROUP_STYLE_ALIASES,
    }
end
