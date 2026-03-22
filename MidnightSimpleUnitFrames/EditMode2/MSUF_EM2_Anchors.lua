-- ============================================================================
-- MSUF_EM2_Anchors.lua — Phase 4: Anchor chain system
-- When element A moves, all elements anchored to A follow with same delta.
-- Chains propagate recursively (A→B→C: moving A moves B and C).
-- Width/height binding: child.width can track parent.width.
-- ============================================================================
local addonName, ns = ...
local EM2 = _G.MSUF_EM2
if not EM2 then return end

local Anchors = {}
EM2.Anchors = Anchors

local floor = math.floor

-- chains[childKey] = { parent = parentKey, bindWidth = bool, bindHeight = bool }
local chains = {}

-- ── Registration ────────────────────────────────────────────────────────────
function Anchors.Link(childKey, parentKey, opts)
    if not childKey or not parentKey then return end
    opts = opts or {}
    chains[childKey] = {
        parent     = parentKey,
        bindWidth  = opts.bindWidth or false,
        bindHeight = opts.bindHeight or false,
    }
end

function Anchors.Unlink(childKey)
    chains[childKey] = nil
end

function Anchors.GetParent(childKey)
    local c = chains[childKey]
    return c and c.parent
end

-- ── Query: all direct children of a parent ──────────────────────────────────
function Anchors.GetChildren(parentKey)
    local result = {}
    for child, info in pairs(chains) do
        if info.parent == parentKey then
            result[#result + 1] = child
        end
    end
    return result
end

-- ── Recursive children (full chain) ─────────────────────────────────────────
function Anchors.GetAllDescendants(parentKey, visited)
    visited = visited or {}
    if visited[parentKey] then return {} end
    visited[parentKey] = true
    local result = {}
    for child, info in pairs(chains) do
        if info.parent == parentKey and not visited[child] then
            result[#result + 1] = child
            local sub = Anchors.GetAllDescendants(child, visited)
            for _, s in ipairs(sub) do result[#result + 1] = s end
        end
    end
    return result
end

-- ── Propagate movement delta to all descendants ─────────────────────────────
-- Called after dragging parentKey by (dx, dy) in screen space.
-- Moves child movers and their underlying frames.
function Anchors.PropagateMove(parentKey, dx, dy)
    if dx == 0 and dy == 0 then return end
    local children = Anchors.GetAllDescendants(parentKey)
    if #children == 0 then return end

    local movers = EM2.Movers and EM2.Movers.All()
    if not movers then return end

    for _, childKey in ipairs(children) do
        local mover = movers[childKey]
        if mover and mover:IsShown() then
            local l = (mover:GetLeft() or 0) + dx
            local b = (mover:GetBottom() or 0) + dy
            mover:ClearAllPoints()
            mover:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l, b)

            -- Move underlying frame
            local cfg = EM2.Registry and EM2.Registry.Get(childKey)
            if cfg then
                local frame = cfg.getFrame and cfg.getFrame()
                if frame then
                    local fS = frame:GetEffectiveScale()
                    local uiS = UIParent:GetEffectiveScale()
                    local ratio = uiS / fS
                    pcall(function()
                        frame:ClearAllPoints()
                        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", l * ratio, b * ratio)
                    end)
                end

                -- Save to DB
                if cfg.getConf then
                    local conf = cfg.getConf()
                    if conf then
                        local w = mover:GetWidth() or 50
                        local h = mover:GetHeight() or 20
                        local uiW = UIParent:GetWidth() or 1
                        local uiH = UIParent:GetHeight() or 1
                        conf.offsetX = floor((l + w * 0.5) - uiW * 0.5 + 0.5)
                        conf.offsetY = floor((b + h * 0.5) - uiH * 0.5 + 0.5)
                    end
                end
            end
        end
    end
end

-- ── Width/height binding sync ───────────────────────────────────────────────
-- Call after any resize to propagate to bound children.
function Anchors.SyncDimensions(parentKey)
    local parentMover = EM2.Movers and EM2.Movers.Get(parentKey)
    if not parentMover then return end
    local pw = parentMover:GetWidth() or 0
    local ph = parentMover:GetHeight() or 0

    for childKey, info in pairs(chains) do
        if info.parent == parentKey and (info.bindWidth or info.bindHeight) then
            local cfg = EM2.Registry and EM2.Registry.Get(childKey)
            if cfg and cfg.getConf then
                local conf = cfg.getConf()
                if conf then
                    if info.bindWidth  then conf.width  = floor(pw + 0.5) end
                    if info.bindHeight then conf.height = floor(ph + 0.5) end
                end
            end
        end
    end
end

-- ── Clear all chains (on exit edit mode) ────────────────────────────────────
function Anchors.Clear()
    for k in pairs(chains) do chains[k] = nil end
end
