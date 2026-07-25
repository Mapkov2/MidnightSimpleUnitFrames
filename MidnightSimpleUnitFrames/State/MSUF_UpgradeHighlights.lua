--- Release-based highlight tours for existing MSUF profiles.
---
--- The registry is intentionally separate from the generated changelog. A new
--- release only needs one ordered release entry plus its curated highlights;
--- persisted completion is tracked per release and never mutates profile data.

local addonName, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
_G.MSUF = _G.MSUF or MSUF

local _G = _G
local type, tostring = type, tostring
local time = time

local REVISION = 1
local TERMINAL = {
    baseline = true,
    completed = true,
    skipped = true,
}

local DATA = {
    schema = 1,
    currentRelease = "6.0",
    releaseOrder = { "6.0" },
    releases = {
        ["6.0"] = {
            sourceVersion = "5.71 and older",
            title = "Your MSUF 6.0 highlights",
            intro = "Your current profile stays exactly as it is. Take a quick tour of the new controls, then decide what you want to configure.",
            highlights = {
                {
                    id = "custom_aura_tracking",
                    icon = "auras3_styling",
                    pageKey = "uf_player",
                    route = {
                        unit = "player",
                        unitAuraTab = "custom1",
                        unitAuraTool = "whitelist",
                        accordion = "uf_player:auras",
                    },
                    title = "Custom Aura tracking on Unitframes",
                    summary = "Build up to three frame-specific Custom lanes on Player, Target, Focus and Boss, then whitelist exact buff or debuff SpellIDs.",
                    impact = "Your MSUF frames can act as focused WeakAura-style trackers with icons, timers, duration bars and full-frame tint, border, glow or pulse effects.",
                    missed = "three Custom Aura trackers per supported Unitframe, exact spell whitelists and full-frame effects",
                    action = "Build a Custom tracker",
                },
                {
                    id = "auras3_rework",
                    icon = "auras3_styling",
                    pageKey = "auras3_styling",
                    title = "Auras3: a full Aura menu rework",
                    summary = "The 5.71 Auras2 page has been rebuilt as Auras3, with separate Unitframe and Group workspaces plus Buff, Debuff and Custom lanes.",
                    impact = "Each lane gets its own live preview, layout, growth, sorting, filters, blacklist or whitelist, cooldown text, swipe, stacks and duration bars.",
                    missed = "the rebuilt Auras3 workspace, lane-specific previews, layouts, sorting, filters and styling",
                    action = "Explore the Aura rework",
                },
                {
                    id = "group_frames",
                    icon = "gf_layout",
                    pageKey = "gf_layout",
                    title = "Adaptive Party and Raid layouts",
                    summary = "Group frames gained smarter layouts, stronger status handling, range behavior and clearer health feedback.",
                    impact = "You can make one group setup adapt more cleanly between party, raid and encounter needs.",
                    missed = "adaptive group layouts, range behavior and group status controls",
                    action = "Open Group Layout",
                },
                {
                    id = "health_text",
                    icon = "uf_player",
                    pageKey = "uf_player",
                    route = {
                        unit = "player",
                        unitTextTab = "hp",
                        accordion = "uf_player:text",
                    },
                    title = "New health values and text formats",
                    summary = "Health text can show abbreviated or full values with more consistent formatting across unit and group frames.",
                    impact = "You can choose compact readability or exact numbers without giving up the layout you already use.",
                    missed = "the new health abbreviations, full values and text-format options",
                    action = "Open HP Text Editor",
                },
                {
                    id = "class_resources",
                    icon = "classpower",
                    pageKey = "classpower",
                    title = "More flexible class resources",
                    summary = "Class resources gained detached layouts, additional shapes and finer per-slot and full-state colors.",
                    impact = "You can move class information where your eyes already are and make important states easier to read.",
                    missed = "detached class resources, new shapes and per-state colors",
                    action = "Configure Class Resources",
                },
                {
                    id = "cast_target_text",
                    icon = "opt_castbar",
                    pageKey = "uf_target",
                    title = "Cast target text",
                    summary = "Target, Focus and Boss cast bars can now show who the current spell is targeting, with dedicated text styling.",
                    impact = "You can identify the destination of an important cast without shifting attention away from the cast bar.",
                    missed = "cast-target names and their text styling on Target, Focus and Boss frames",
                    action = "Open Target Cast Bar",
                },
                {
                    id = "assistant",
                    icon = "home",
                    pageKey = "home",
                    title = "The optional local MSUF Assistant",
                    summary = "A new on-demand Assistant can find exact settings, explain controls and prepare reversible changes.",
                    impact = "You can ask for a setting in plain language while the Assistant remains inactive when you do not use it.",
                    missed = "the local Assistant for exact settings, explanations and reversible changes",
                    action = "Try the Assistant",
                },
                {
                    id = "menu_accent",
                    icon = "opt_misc",
                    pageKey = "opt_misc",
                    route = {
                        accordion = "opt_misc:misc_menu_behavior",
                    },
                    title = "Menu accent colors",
                    summary = "The MSUF menu can now follow your class color, a curated preset like Ember, Jade or Violet, or any custom color.",
                    impact = "The accent colors navigation, tabs and highlights; panels stay midnight unless you turn on Tint menu surfaces. Applied after a UI reload.",
                    missed = "class-color, preset and custom accent options for the MSUF menu",
                    action = "Pick a menu accent",
                },
            },
        },
    },
}

MSUF.UpgradeHighlightData = DATA

local globalDB = rawget(_G, "MSUF_GlobalDB")
if type(globalDB) ~= "table" then
    globalDB = {}
    _G.MSUF_GlobalDB = globalDB
end
if type(globalDB.global) ~= "table" then
    globalDB.global = {}
end

local function Now()
    return type(time) == "function" and time() or 0
end

local state = globalDB.global.upgradeHighlights
if type(state) ~= "table" or state.revision ~= REVISION then
    state = {
        schema = 1,
        revision = REVISION,
        releases = {},
    }
    globalDB.global.upgradeHighlights = state
end
state.schema = 1
state.revision = REVISION
state.releases = type(state.releases) == "table" and state.releases or {}

local Controller = MSUF.UpgradeHighlights or {}
MSUF.UpgradeHighlights = Controller

local function NewRecord(status)
    return {
        status = status or "pending",
        index = 0,
        outcomes = {},
        firstSeenAt = Now(),
    }
end

local function FirstLoadKind()
    local firstLoad = MSUF.FirstLoad6
    if type(firstLoad) == "table" and type(firstLoad.GetInstallKind) == "function" then
        return firstLoad:GetInstallKind()
    end
    return "fresh"
end

local function InitializeKnownReleases()
    if state.initialized == true then return end
    -- A genuine 6.0 fresh install has nothing to upgrade from. Existing
    -- profiles instead leave the release unseen so it becomes pending below.
    if FirstLoadKind() == "fresh" then
        for i = 1, #DATA.releaseOrder do
            local releaseKey = DATA.releaseOrder[i]
            local record = NewRecord("baseline")
            record.baselinedAt = Now()
            state.releases[releaseKey] = record
        end
    end
    state.initialized = true
    state.initializedAt = Now()
end

local function EnsureRecord(releaseKey)
    local record = state.releases[releaseKey]
    if type(record) ~= "table" then
        record = NewRecord("pending")
        state.releases[releaseKey] = record
    end
    record.outcomes = type(record.outcomes) == "table" and record.outcomes or {}
    record.index = tonumber(record.index) or 0
    if record.status ~= "pending" and record.status ~= "active" and record.status ~= "skip_warning" and not TERMINAL[record.status] then
        record.status = "pending"
    end
    return record
end

local function PendingRelease()
    InitializeKnownReleases()
    for i = 1, #DATA.releaseOrder do
        local releaseKey = DATA.releaseOrder[i]
        local spec = DATA.releases[releaseKey]
        if type(spec) == "table" and type(spec.highlights) == "table" then
            local record = EnsureRecord(releaseKey)
            if not TERMINAL[record.status] then
                return releaseKey, spec, record
            end
        end
    end
end

local function FinishFirstLoad(releaseKey, result)
    local firstLoad = MSUF.FirstLoad6
    if type(firstLoad) == "table" and type(firstLoad.IsTerminal) == "function"
        and type(firstLoad.Complete) == "function" and not firstLoad:IsTerminal() then
        firstLoad:Complete("upgrade_highlights_" .. tostring(releaseKey) .. "_" .. tostring(result))
    end
end

function Controller:GetState()
    InitializeKnownReleases()
    return state
end

function Controller:GetCurrent()
    return PendingRelease()
end

function Controller:ShouldShow()
    return PendingRelease() ~= nil
end

function Controller:Start()
    local releaseKey, spec, record = PendingRelease()
    if not releaseKey then return false, "no_pending_release" end
    record.status = "active"
    record.index = record.index > 0 and record.index or 1
    record.startedAt = record.startedAt or Now()
    record.updatedAt = Now()
    return true, releaseKey, spec, record
end

function Controller:Advance(outcome)
    local releaseKey, spec, record = PendingRelease()
    if not releaseKey then return false, "no_pending_release" end
    if record.status == "pending" then self:Start() end
    if record.status ~= "active" then return false, record.status end

    local count = #spec.highlights
    local index = record.index > 0 and record.index or 1
    local highlight = spec.highlights[index]
    if highlight then
        record.outcomes[highlight.id] = outcome == "opened" and "opened" or "reviewed"
    end
    if index >= count then
        record.status = "completed"
        record.index = count
        record.completedAt = Now()
        record.updatedAt = record.completedAt
        FinishFirstLoad(releaseKey, "completed")
        return true, "completed", releaseKey, highlight
    end
    record.index = index + 1
    record.updatedAt = Now()
    return true, "active", releaseKey, highlight
end

function Controller:Back()
    local _, _, record = PendingRelease()
    if not record or record.status ~= "active" then return false end
    record.index = math.max(1, (record.index or 1) - 1)
    record.updatedAt = Now()
    return true
end

function Controller:RequestSkip()
    local releaseKey, spec, record = PendingRelease()
    if not releaseKey then return false, "no_pending_release" end
    record.returnStatus = record.status == "active" and "active" or "pending"
    local remaining = 0
    for i = 1, #spec.highlights do
        if record.outcomes[spec.highlights[i].id] == nil then remaining = remaining + 1 end
    end
    record.pendingSkipCount = remaining
    record.status = "skip_warning"
    record.updatedAt = Now()
    return true
end

function Controller:CancelSkip()
    local _, _, record = PendingRelease()
    if not record or record.status ~= "skip_warning" then return false end
    record.status = record.returnStatus == "active" and "active" or "pending"
    record.returnStatus = nil
    record.pendingSkipCount = nil
    record.updatedAt = Now()
    return true
end

function Controller:ConfirmSkip()
    local releaseKey, spec, record = PendingRelease()
    if not releaseKey or record.status ~= "skip_warning" then return false end
    record.status = "skipped"
    record.skippedAt = Now()
    record.skippedCount = tonumber(record.pendingSkipCount) or #spec.highlights
    record.returnStatus = nil
    record.pendingSkipCount = nil
    record.updatedAt = record.skippedAt
    FinishFirstLoad(releaseKey, "skipped")
    return true, releaseKey
end

function Controller:ResetCurrent()
    local releaseKey = DATA.currentRelease
    state.initialized = true
    state.releases[releaseKey] = NewRecord("pending")
    state.updatedAt = Now()
    return true, releaseKey
end

function Controller:BaselineKnownReleases()
    state.initialized = true
    for i = 1, #DATA.releaseOrder do
        local releaseKey = DATA.releaseOrder[i]
        local record = NewRecord("baseline")
        record.baselinedAt = Now()
        state.releases[releaseKey] = record
    end
    state.updatedAt = Now()
    return true
end

function Controller:GetDebugSummary()
    local releaseKey, spec, record = PendingRelease()
    if releaseKey then
        return releaseKey, record.status, record.index, #spec.highlights
    end
    local current = state.releases[DATA.currentRelease]
    return DATA.currentRelease, type(current) == "table" and current.status or "none",
        type(current) == "table" and current.index or 0,
        #(DATA.releases[DATA.currentRelease].highlights or {})
end
