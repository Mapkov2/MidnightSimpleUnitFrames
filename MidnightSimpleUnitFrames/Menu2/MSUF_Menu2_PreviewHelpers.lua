local addonName, ns = ...
ns = ns or {}

local M = ns.MSUF2 or {}
ns.MSUF2 = M
_G.MSUF2 = M

local H = M.PreviewHelpers or {}
M.PreviewHelpers = H

function H.SnapOff(region)
    if region and region.SetSnapToPixelGrid then
        region:SetSnapToPixelGrid(false)
        if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
    end
end

function H.MaskOwner(mock, tex, anchor)
    local owner = tex and tex.GetParent and tex:GetParent() or nil
    if owner and owner.CreateMaskTexture then return owner end
    if anchor and anchor.CreateMaskTexture then return anchor end
    return mock
end

function H.EnsureRoundedMask(mock, key, anchor, tex, maskStoreKey, maskTexture, snapOff)
    if not (mock and anchor) then return nil end
    local owner = H.MaskOwner(mock, tex, anchor)
    if not (owner and owner.CreateMaskTexture) then return nil end

    maskStoreKey = maskStoreKey or "_msufPreviewRoundedMasks"
    mock[maskStoreKey] = mock[maskStoreKey] or {}
    local store = mock[maskStoreKey]
    local bucket = store[key]
    if type(bucket) ~= "table" or bucket.SetTexture then
        bucket = {}
        store[key] = bucket
    end

    local ownerKey = tex or owner
    local mask = bucket[ownerKey]
    if not mask then
        mask = owner:CreateMaskTexture(nil, "ARTWORK")
        local snapOffFn = snapOff or H.SnapOff
        snapOffFn(mask)
        bucket[ownerKey] = mask
    end
    mask:ClearAllPoints()
    mask:SetTexture(maskTexture, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(anchor)
    return mask
end

function H.SetMask(mock, tex, mask, maskedStoreKey)
    if not (mock and tex and tex.AddMaskTexture) then return end
    maskedStoreKey = maskedStoreKey or "_msufPreviewRoundedMasked"
    mock[maskedStoreKey] = mock[maskedStoreKey] or {}
    local store = mock[maskedStoreKey]
    local old = store[tex]
    if old == mask then return end
    if old and tex.RemoveMaskTexture then pcall(tex.RemoveMaskTexture, tex, old) end
    store[tex] = nil
    if mask then
        local ok = pcall(tex.AddMaskTexture, tex, mask)
        if ok then store[tex] = mask end
    end
end

function H.ClearMasks(mock, maskedStoreKey)
    local store = mock and mock[maskedStoreKey or "_msufPreviewRoundedMasked"]
    if store then
        for tex, mask in pairs(store) do
            if tex and tex.RemoveMaskTexture and mask then pcall(tex.RemoveMaskTexture, tex, mask) end
        end
    end
    if mock then mock[maskedStoreKey or "_msufPreviewRoundedMasked"] = nil end
end

function H.BaseEdgeColor()
    local fn = _G.MSUF_GetBarOutlineColor
    if type(fn) == "function" then
        local ok, r, g, b = pcall(fn)
        if ok and type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return r, g, b, 1
        end
    end

    local gen = _G.MSUF_DB and _G.MSUF_DB.general
    if gen then
        return tonumber(gen.barOutlineColorR) or 0,
               tonumber(gen.barOutlineColorG) or 0,
               tonumber(gen.barOutlineColorB) or 0,
               1
    end
    return 0, 0, 0, 1
end
