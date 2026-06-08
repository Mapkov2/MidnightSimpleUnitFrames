local _, ns = ...
ns = ns or {}

ns.MSUF_CastbarRegistry = ns.MSUF_CastbarRegistry or {}

local Registry = ns.MSUF_CastbarRegistry
Registry.bars = Registry.bars or {}

function Registry:Register(key, unit, frame, styleGetter)
    if not key then
        return
    end

    self.bars[key] = {
        unit = unit,
        frame = frame,
        styleGetter = styleGetter,
    }
end

function Registry:Unregister(key)
    if not key then
        return
    end

    self.bars[key] = nil
end

function Registry:Get(key)
    if not key then
        return nil
    end

    return self.bars[key]
end

function Registry:Iterate()
    return pairs(self.bars)
end
