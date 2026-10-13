-- Element strategies share scheduling while retaining their own anchor math,
-- rounding, persistence, history category and popup behavior.
local _, MSUF = ...
local Kinds = {}
MSUF.EditModeKinds = Kinds
local Geometry = MSUF.Geometry
local Driver = MSUF.EditModeDragDriver
local hosted = {}
local nativeGameplay = {}

MSUF.EditModeController.Kinds = Kinds

local function Bounds(_, frame)
    return Geometry.Edges(frame)
end

local function History(_, key, cfg)
    local category = cfg.historyCategory or (cfg.popupType == "castbar" and "castbar" or "unit")
    local historyKey = cfg.historyKey or (cfg.popupType == "castbar" and (cfg.castbarUnit or key:sub(9)) or key)
    if cfg.externalPublicElement == true then category, historyKey = "external", key end
    return category, historyKey
end

local function OpenPopup(_, key, parent)
    return MSUF.EditModeController.Popups.Open(key, parent)
end

local function ApplyDrag(strategy, context, ...)
    local record = context.driverCallback and context or hosted[context]
    if record then return record.driverCallback(record.mover, ...) end
    return strategy.move(context, ...)
end

local function HostedUpdate(owner, elapsed)
    local context = hosted[owner]
    if context then context.strategy:applyDrag(context, elapsed) end
end

local function BeginDrag(strategy, mover, key, cfg, start)
    if start and start.driverCallback then
        local context = { mover = mover, driverCallback = start.driverCallback, strategy = strategy }
        hosted[mover] = context
        Driver.Attach(mover, HostedUpdate)
        return context
    end
    local context = strategy.build(mover, key, cfg, start)
    if context then context.strategy = cfg and Kinds.For(key, cfg, context.bar) or strategy end
    return context
end

local function Commit(strategy, context, ...)
    if context.driverCallback then
        hosted[context.mover] = nil
        Driver.Detach(context.mover)
        return true
    end
    return strategy.finish(context, ...)
end

for kind in ("unit stacked castbar subframe group aura external gameplay"):gmatch("%S+") do
    Kinds[kind] = {
        kind = kind, bounds = Bounds, beginDrag = BeginDrag, applyDrag = ApplyDrag,
        commit = Commit, history = History, openPopup = OpenPopup,
    }
end

function Kinds.For(key, cfg, frame)
    if cfg.externalPublicElement == true then return Kinds.external end
    if type(cfg.subframeOffsetXKey) == "string" and type(cfg.subframeOffsetYKey) == "string" then return Kinds.subframe end
    if cfg.popupType == "castbar" or tostring(key):sub(1, 8) == "castbar_" then return Kinds.castbar end
    if key == "gf_party" or key == "gf_raid" or key == "gf_mythicraid" or key == "gf_priority"
        or (frame and frame._msufIsGroupFrame == true) then return Kinds.group end
    if cfg.popupType == "aura" or tostring(key):sub(1, 5) == "aura_" then return Kinds.aura end
    if cfg.popupType == "gameplay" then return Kinds.gameplay end
    if key == "boss" or key == "arena" then return Kinds.stacked end
    return Kinds.unit
end

function Kinds.Bind(kind, build, move, finish)
    local strategy = assert(Kinds[kind], "unknown Edit Mode kind")
    strategy.build, strategy.move, strategy.finish = build, move, finish
end

function Kinds.Attach(kind, owner, callback)
    return assert(Kinds[kind], "unknown Edit Mode kind"):beginDrag(owner, nil, nil, { driverCallback = callback })
end

function Kinds.Detach(owner)
    local context = hosted[owner]
    if context then context.strategy:commit(context) else Driver.Detach(owner) end
end

function Kinds.EndGameplayDrag(frame, cancel)
    if not frame._msufDragging then return false end
    nativeGameplay[frame] = nil
    frame._msufDragging = nil
    if cancel then frame._msufAppliedPositionX, frame._msufAppliedPositionY = nil, nil end
    if cancel and frame._msufGameplayHistoryTransaction then
        frame._msufGameplayHistoryTransaction = nil
        MSUF.EditModeController.Undo.CancelChange()
    end
    frame:StopMovingOrSizing()
    return true
end

function Kinds.Clear()
    local held = nativeGameplay
    nativeGameplay = {}
    for owner in pairs(held) do Kinds.EndGameplayDrag(owner, true) end
    hosted = {}
    Driver.Clear()
end

local function StoreCenteredOffset(frame, db, xKey, yKey, anchor, roundValues, RoundInt)
    local x, y = frame:GetCenter()
    if not (x and y) then return end

    -- GetCenter reports each region in its own effective-scale space. Anchoring to a scaled
    -- unit frame therefore needs both centers converted through screen pixels into the moving
    -- frame's space (the space SetPoint offsets are applied in), or the stored offsets drift
    -- and the next re-anchor jumps the frame.
    local frameScale = (frame.GetEffectiveScale and frame:GetEffectiveScale()) or 1
    if not frameScale or frameScale <= 0 then frameScale = 1 end

    local ax, ay = UIParent:GetCenter()
    local anchorScale = (UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or frameScale
    if anchor and anchor.GetCenter then
        local tx, ty = anchor:GetCenter()
        if tx and ty then
            ax, ay = tx, ty
            anchorScale = (anchor.GetEffectiveScale and anchor:GetEffectiveScale()) or anchorScale
        end
    end
    if not (ax and ay) then return end
    if not anchorScale or anchorScale <= 0 then anchorScale = frameScale end

    local dx = ((x * frameScale) - (ax * anchorScale)) / frameScale
    local dy = ((y * frameScale) - (ay * anchorScale)) / frameScale
    if roundValues ~= false then
        dx, dy = RoundInt(dx), RoundInt(dy)
    end
    db[xKey], db[yKey] = dx, dy
end

local function BeginGameplayDrag(strategy, frame, label, source, select, beginHistory)
    if label ~= nil then
        local selectFrame = select or MSUF.Gameplay.SelectNudgeFrame
        local begin = beginHistory or MSUF.Gameplay.BeginHistory
        selectFrame(frame, true)
        begin(frame, label, source)
        frame._msufDragging = true
        nativeGameplay[frame] = true
        frame:StartMoving()
        return frame
    end
    return BeginDrag(strategy, frame, label, source, select)
end

local function ApplyGameplayDrag(strategy, context, ...)
    if context.driverCallback then return ApplyDrag(strategy, context, ...) end
    return StoreCenteredOffset(context, ...)
end

Kinds.gameplay.beginDrag = BeginGameplayDrag
Kinds.gameplay.applyDrag = ApplyGameplayDrag

local function CommitGameplayDrag(strategy, context)
    if context.driverCallback then return Commit(strategy, context) end
    -- The runtime owns rounding, re-anchoring, cache/slider sync and history.
    -- Complete the same native release path as the client's OnDragStop.
    if not context._msufDragging then return false end
    local finish = context:GetScript("OnDragStop")
    if not finish then return false end
    finish(context)
    return true
end
Kinds.gameplay.commit = CommitGameplayDrag
