local _, MSUF = ...
local EM = MSUF.Require("MSUF_EM2", "Shell/EditMode/MSUF_EditMode_MultiSelection.lua")
local Multi = { selected = {} }
EM.MultiSelection = Multi
local function Allowed()
    return EM.State.IsActive() and not MSUF.Public.IsConfigCombatLocked()
end
function Multi.Toggle(key)
    if not Allowed() or not EM.Registry.Get(key) then return false end
    Multi.selected[key] = not Multi.selected[key] or nil
    if Multi.SelectionChanged then Multi.SelectionChanged() end
    return true
end
function Multi.Clear()
    for key in pairs(Multi.selected) do Multi.selected[key] = nil end
end
local function Number(value)
    if MSUF.Util.IsSecret(value) then return false end
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end
local function Rectangle(key, cfg)
    local frame = cfg.externalPublicElement and EM.ExternalElements.GetPositionFrame(key) or cfg.getFrame()
    if not frame or frame.IsForbidden and frame:IsForbidden() then return end
    if not (frame.GetLeft and frame.GetRight and frame.GetTop and frame.GetBottom and frame.GetEffectiveScale) then return end
    local l, r, t, b = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
    local s = frame:GetEffectiveScale()
    local parent = UIParent:GetEffectiveScale()
    if not (Number(l) and Number(r) and Number(t) and Number(b) and Number(s) and Number(parent)) or s <= 0 or parent <= 0 then return end
    s = s / parent
    return { key = key, frame = frame, scale = s, l = l * s, r = r * s, t = t * s, b = b * s, dx = 0, dy = 0 }
end
function Multi.Items()
    local items = {}
    for _, key in ipairs(EM.Registry.Order()) do
        local cfg = EM.Registry.Get(key)
        if cfg.canNudge ~= false and (cfg.popupType == "unit" or cfg.popupType == "castbar"
            or cfg.popupType == "resource" or cfg.externalPublicElement or key:match("^gf_")) then
            items[#items + 1] = { key = key, label = cfg.label or key }
        end
    end
    return items
end
local function Rectangles()
    local out = {}
    for _, item in ipairs(Multi.Items()) do
        if Multi.selected[item.key] then
            local rect = Rectangle(item.key, EM.Registry.Get(item.key))
            if not rect then return nil, "A selected element has no available position." end
            out[#out + 1] = rect
        end
    end
    if #out < 2 then return nil, "Select at least two elements." end
    return out
end
function Multi.Plan(mode, dx, dy)
    if not Allowed() then return nil, "Open Edit Mode outside combat first." end
    local items, why = Rectangles()
    if not items then return nil, why end
    if mode == "move" then
        if not Number(dx) or not Number(dy) or math.abs(dx) > 4096 or math.abs(dy) > 4096 then return nil, "Invalid move distance." end
        for _, item in ipairs(items) do item.dx, item.dy = dx, dy end
    elseif mode == "left" or mode == "right" or mode == "top" or mode == "bottom" then
        local field = ({ left = "l", right = "r", top = "t", bottom = "b" })[mode]
        local reference = items[1][field]
        for _, item in ipairs(items) do
            if mode == "left" or mode == "right" then item.dx = reference - item[field]
            else item.dy = reference - item[field] end
        end
    elseif mode == "horizontal" or mode == "vertical" then
        if #items < 3 then return nil, "Select at least three elements to distribute gaps." end
        local low, high = mode == "horizontal" and "l" or "b", mode == "horizontal" and "r" or "t"
        table.sort(items, function(a, b) return a[low] < b[low] end)
        local total = 0
        for _, item in ipairs(items) do total = total + item[high] - item[low] end
        local gap = (items[#items][high] - items[1][low] - total) / (#items - 1)
        local cursor = items[1][low]
        for _, item in ipairs(items) do
            if mode == "horizontal" then item.dx = cursor - item[low] else item.dy = cursor - item[low] end
            cursor = cursor + item[high] - item[low] + gap
        end
    else return nil, "Unknown alignment." end
    return items
end
-- Parent movement is already present in an anchored child's screen position.
-- Apply ancestors first, then move each child only by its remaining distance.
local function Follows(frame, target, seen, depth)
    if frame == target then return true end
    if not frame or seen[frame] or depth >= 32 then return false end
    seen[frame] = true
    if frame.GetPoint then
        local count = frame.GetNumPoints and frame:GetNumPoints() or 1
        for i = 1, count do
            local _, anchor = frame:GetPoint(i)
            if anchor and Follows(anchor, target, seen, depth + 1) then return true end
        end
    end
    local parent = frame.GetParent and frame:GetParent()
    return parent and Follows(parent, target, seen, depth + 1) or false
end
local function OrderMoves(plan)
    local ordered, done = {}, {}
    while #ordered < #plan do
        local progressed = false
        for _, item in ipairs(plan) do
            if not done[item] then
                local blocked = false
                for _, parent in ipairs(plan) do
                    if parent ~= item and not done[parent] and Follows(item.frame, parent.frame, {}, 0) then
                        blocked = true
                        break
                    end
                end
                if not blocked then
                    ordered[#ordered + 1], done[item], progressed = item, true, true
                end
            end
        end
        if not progressed then return nil end
    end
    return ordered
end
local function RemainingMove(item, cfg)
    local current = Rectangle(item.key, cfg)
    if not current then return end
    local x, y = item.l + item.dx - current.l, item.b + item.dy - current.b
    -- Public movers and group-grid positions consume UIParent deltas. The
    -- native unit, castbar and resource offsets use their frame's local scale.
    if not cfg.externalPublicElement and not item.key:match("^gf_") then x, y = x / current.scale, y / current.scale end
    return math.floor(x + 0.5), math.floor(y + 0.5)
end
function Multi.Apply(mode, dx, dy)
    local plan, why = Multi.Plan(mode, dx, dy)
    if not plan then return false, why end
    plan = OrderMoves(plan)
    if not plan then return false, "A selected element has no available position." end
    local before, reason = MSUF.ProfileWorkbench.Snapshot()
    if not before then return false, reason end
    local prepared = MSUF.History.PrepareHistoryChange("Move selected elements", "editmode:multi")
    if not prepared then return false, "Undo is unavailable." end
    local external = {}
    for _, item in ipairs(plan) do
        local cfg = EM.Registry.Get(item.key)
        if cfg.externalPublicElement then
            local snapshot = EM.ExternalElements.CaptureHistoryState(item.key)
            if not snapshot then return false, "Undo is unavailable." end
            external[#external + 1] = snapshot
        end
    end
    local failed, rollback = false, true
    local function Apply()
        EM.Undo.batchActive = true
        for _, item in ipairs(plan) do
            local x, y = RemainingMove(item, EM.Registry.Get(item.key))
            if not x or (x ~= 0 or y ~= 0) and not EM.Nudge.Named(item.key, x, y) then failed = true break end
        end
    end
    local function Finish(ok)
        EM.Undo.batchActive = nil
        if not ok or failed then
            rollback = MSUF.ProfileWorkbench.Rollback(before)
            for _, snapshot in ipairs(external) do
                if not EM.ExternalElements.RestoreHistoryState(snapshot) then rollback = false end
            end
        end
    end
    local ok = MSUF.RunLabeledStep("move selected elements", Apply, Finish)
    if not ok or failed then
        local message = rollback and "The selected elements could not all be moved. Previous positions were restored."
            or "Previous positions could not be restored."
        return false, message
    end
    MSUF.History.CommitPreparedHistory(prepared)
    if EM.Movers then EM.Movers.SyncAll() end
    return true
end
