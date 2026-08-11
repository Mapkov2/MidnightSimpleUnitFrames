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
            sourceVersion = "5.76 and older",
            title = "Your MSUF 6.0 highlights",
            intro = "Your current profile stays exactly as it is. Take a quick tour of the new controls, then decide what you want to configure.",
            highlights = {
                {
                    id = "page_history",
                    icon = "home",
                    pageKey = "uf_player",
                    title = "Back and Forward between pages",
                    summary = "New Back and Forward arrows in the bottom-left menu bar remember the pages you visit.",
                    impact = "Jump between recent settings pages without finding them again in navigation or search.",
                    missed = "Back and Forward page history in the bottom-left menu bar",
                    action = "Try the Back button",
                },
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
                    summary = "Build up to three frame-specific Custom lanes on Player, Target, Focus and Boss, whitelist exact buff or debuff SpellIDs, and track your own DoTs on the Target frame with a curated per-class lane.",
                    impact = "Your MSUF frames can act as focused WeakAura-style trackers with icons, timers, duration bars and full-frame tint, border, glow or pulse effects.",
                    missed = "three Custom Aura trackers per supported Unitframe, exact spell whitelists and full-frame effects",
                    action = "Build a Custom tracker",
                },
                {
                    id = "auras3_rework",
                    icon = "auras3_styling",
                    pageKey = "auras3_styling",
                    title = "Aura settings in the right place",
                    summary = "Setup and individual styling now live in the matching Unitframe and Party/Raid menus. Appearance > Auras holds the expanded shared styles.",
                    impact = "Configure each frame in context, then use Auras for shared icon shapes, borders, shadows, colors and spacing.",
                    missed = "per-frame Aura controls and expanded shared styling in Appearance > Auras",
                    action = "Open shared Aura styles",
                },
                {
                    id = "priority_frames",
                    icon = "gf_priority",
                    pageKey = "gf_priority",
                    route = {
                        accordion = "gf_priority:who_appears",
                    },
                    title = "Priority Frames for the units that matter",
                    summary = "Pin up to five group members by hand, or let MSUF pick the tanks automatically, and give them their own strip that never reshuffles mid-fight.",
                    impact = "The people you have to watch keep one fixed spot on screen, with the Party or Raid look and click-casting they already had.",
                    missed = "Priority Frames, manual and automatic pinning, and their own placement",
                    action = "Set up Priority Frames",
                },
                {
                    id = "group_frames",
                    icon = "gf_layout",
                    pageKey = "gf_layout",
                    -- Frame Basics is not open by default, so without this the
                    -- card landed on a page showing only the scope bar and the
                    -- group preview.
                    route = {
                        accordion = "gf_layout:general",
                    },
                    title = "Adaptive Party and Raid layouts",
                    summary = "Party, Raid and Mythic Raid gained adaptive layouts and scaling, per-lane aura filters and blacklists, a focused Dispel Overlay page, and per-group control over whether MSUF or Blizzard draws the frames.",
                    impact = "One group setup can follow you from a five-man into a raid, and you decide per lane which auras are allowed to show at all.",
                    missed = "adaptive group layouts and scaling, group aura filters and blacklists, the Dispel Overlay page and the group provider controls",
                    action = "Open Group Layout",
                },
                {
                    id = "spell_indicators",
                    icon = "gf_indicators",
                    pageKey = "gf_indicators",
                    route = {
                        accordion = "gf_indicators:si",
                    },
                    title = "Spell Indicators on Group Frames",
                    summary = "Track chosen buffs on Party and Raid frames as icon, square, bar or number indicators, with custom spell lists and corner indicators.",
                    impact = "You can see missing or expiring externals and key buffs directly on the frames, with expiring icon glows, health-bar highlights and full-frame effects.",
                    missed = "Spell Indicators with custom aura lists, corner indicators and expiring-effect warnings",
                    action = "Open Spell Indicators",
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
                    summary = "Health text can show abbreviated or full values with more consistent formatting, and the new Maximum Health Loss overlay can mark lost maximum health on unit and group frames.",
                    impact = "You can choose compact readability or exact numbers without giving up the layout you already use.",
                    missed = "the new health abbreviations, full values, text formats and the Maximum Health Loss overlay",
                    action = "Open HP Text Editor",
                },
                {
                    id = "fill_direction",
                    icon = "opt_bars",
                    pageKey = "uf_player",
                    route = {
                        unit = "player",
                        accordion = "uf_player:frame_basics",
                    },
                    title = "Fill Direction for Health and Power",
                    summary = "Every Unit Frame can fill its Health and Power left to right, right to left, bottom to top or top to bottom.",
                    impact = "Vertical and mirrored bar layouts become a per-frame choice - something no other unit frame addon currently offers.",
                    missed = "the per-frame Fill Direction control for Health and Power bars",
                    action = "Choose a Fill Direction",
                },
                {
                    id = "portraits",
                    icon = "uf_target",
                    pageKey = "uf_player",
                    route = {
                        unit = "player",
                        accordion = "uf_player:portrait",
                    },
                    title = "Portraits: attached, detached or overlay",
                    summary = "Portraits can stay attached, float freely or render as an overlay inside the health bar, with independent size, nine-point anchoring, opacity and pannable zoom.",
                    impact = "Rectangular and watermark-style portraits become possible, and Relief rings plus shape-following borders frame Square, Circle, Rounded and Diamond portraits.",
                    missed = "the new portrait placement modes, Relief rings and shape-following portrait borders",
                    action = "Open Portrait settings",
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
                    -- Cast Target Text is a card on the Castbar section's Spell
                    -- tab, so the route has to open the section and pick the
                    -- tab; landing on the bare Target page showed no castbar.
                    route = {
                        unit = "target",
                        unitCastbarTab = "spell",
                        accordion = "uf_target:castbar",
                    },
                    title = "Cast target text",
                    summary = "Target, Focus and Boss cast bars can now show who the current spell is targeting, with dedicated text styling.",
                    impact = "You can identify the destination of an important cast without shifting attention away from the cast bar.",
                    missed = "cast-target names and their text styling on Target, Focus and Boss frames",
                    action = "Open Target Cast Bar",
                },
                {
                    id = "colors_painter",
                    icon = "opt_colors",
                    pageKey = "opt_colors",
                    title = "One Colors page with click-to-paint",
                    summary = "Every color moved onto one page, grouped into Player & Target, Party & Raid, Castbar, Aura, Power and Class Resource workspaces with their own live preview.",
                    impact = "You can click the element in the preview to paint it instead of hunting for the matching swatch, and reuse any color from a recent or saved palette.",
                    missed = "the rebuilt Colors page, click-to-paint previews, palettes and the new color picker",
                    action = "Open the Colors page",
                },
                {
                    id = "status_icon_packs",
                    icon = "modules",
                    pageKey = "uf_player",
                    route = {
                        unit = "player",
                        accordion = "uf_player:status_icons",
                    },
                    title = "Status icon packs",
                    summary = "Role, leader, raid marker, ready check and every other status icon can switch between twelve bundled styles or your own custom icons, per indicator.",
                    impact = "Status icons can finally match your UI style instead of always using Blizzard art, and external packs can register through SharedMedia.",
                    missed = "the twelve status icon styles and per-indicator custom icons",
                    action = "Pick an icon style",
                },
                {
                    -- Deliberately linkless: layer sliders live on many pages,
                    -- so the scene renders an inline dummy of the layer
                    -- sub-menu on this card instead of routing anywhere.
                    id = "frame_layers",
                    icon = "uf_player",
                    pageKey = "uf_player",
                    title = "One 0-30 layer scale for everything",
                    summary = "Text, status icons, auras, borders, bar outlines, group indicators and class resources all order themselves on one shared 0-30 layer scale.",
                    impact = "You decide exactly what draws in front of what, and the Layer Overview beside any layer slider shows the whole stack at once.",
                    missed = "the addon-wide 0-30 layer scale and the Layer Overview",
                },
                {
                    -- Edit Mode is a screen mode, not a menu page. Its action is
                    -- special-cased in the scene so the button starts the mode
                    -- instead of only landing on the Dashboard behind it.
                    id = "edit_mode",
                    icon = "modules",
                    pageKey = "home",
                    title = "MSUF Edit Mode, rebuilt",
                    summary = "Edit Mode gained a dockable toolbar, redesigned quick popups on every frame, and Undo and Redo that behave the same there as in the menu.",
                    impact = "You can move, size and copy frames directly on screen and step back out of any mistake without reopening the menu.",
                    missed = "the rebuilt Edit Mode toolbar, its quick popups and shared Undo and Redo",
                    action = "Start Edit Mode",
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
                {
                    -- The only highlight with a screenshot: rounded corners are
                    -- the one 6.0 change that a description cannot demonstrate.
                    -- `preview` is a media key the menu resolves; this module
                    -- stays free of presentation paths.
                    id = "rounded_frames",
                    icon = "opt_bars",
                    pageKey = "opt_bars",
                    preview = "rounded_frames",
                    route = {
                        accordion = "opt_bars:bars_rounded",
                    },
                    title = "Rounded frames, corner for corner",
                    summary = "Rounded unit and group frames now share one clean corner style with five strength levels, used by Health, embedded or detached Power, frame outlines and the aggro, dispel and highlight borders.",
                    impact = "Every rounded element follows the same geometry, so corners no longer disagree with each other or lose their mask after a reload.",
                    missed = "the rebuilt rounded corner style and its five strength levels",
                    action = "Open Rounded Texture",
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

-- This module loads early enough that `MSUF_GlobalDB` can still be missing, and
-- profile repair or a full reset can replace the root afterwards. Without
-- re-resolving it, the completed/skipped status is written into an orphaned
-- table while ShouldShow keeps deriving "pending" from that same orphan - the
-- release tour then reopens on every single menu visit. Mirrors the
-- SyncLiveState in MSUF_FirstLoad.lua, which fixed the identical defect there.
local function SyncLiveState()
    local liveDB = rawget(_G, "MSUF_GlobalDB")
    if type(liveDB) ~= "table" then
        _G.MSUF_GlobalDB = globalDB
        return state
    end
    if type(liveDB.global) ~= "table" then
        liveDB.global = {}
    end
    globalDB = liveDB
    local liveState = globalDB.global.upgradeHighlights
    if liveState ~= state then
        if type(liveState) == "table" and liveState.revision == REVISION
            and type(liveState.releases) == "table" then
            state = liveState
        else
            globalDB.global.upgradeHighlights = state
        end
    end
    state.schema = 1
    state.revision = REVISION
    state.releases = type(state.releases) == "table" and state.releases or {}
    return state
end

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
    -- Every read and write path reaches this through PendingRelease, so one
    -- sync here keeps the whole controller on the live SavedVariables root.
    SyncLiveState()
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

function Controller:SyncSavedVariables()
    return SyncLiveState()
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
    SyncLiveState()
    local releaseKey = DATA.currentRelease
    state.initialized = true
    state.releases[releaseKey] = NewRecord("pending")
    state.updatedAt = Now()
    return true, releaseKey
end

function Controller:BaselineKnownReleases()
    SyncLiveState()
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
