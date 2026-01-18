-- Minimal CallbackHandler-1.0 (compatible subset)
-- Provides :New(target, registerName, unregisterName, unregisterAllName)
-- and returns a dispatcher with :Fire(event, ...)

local MAJOR, MINOR = "CallbackHandler-1.0", 7
local LibStub = _G.LibStub
if not LibStub then return end

local CH = LibStub:NewLibrary(MAJOR, MINOR)
if not CH then return end

function CH:New(target, registerName, unregisterName, unregisterAllName)
    assert(type(target) == "table", "CallbackHandler:New() - target must be a table")
    registerName = registerName or "RegisterCallback"
    unregisterName = unregisterName or "UnregisterCallback"
    unregisterAllName = unregisterAllName or "UnregisterAllCallbacks"

    local dispatcher = {
        callbacks = {},
    }

    function dispatcher:Fire(event, ...)
        local bucket = self.callbacks[event]
        if not bucket then return end
        for _, fn in pairs(bucket) do
            if type(fn) == "function" then
                fn(target, event, ...)
            end
        end
    end

    target[registerName] = function(_, event, fn)
        if type(event) ~= "string" or event == "" then return end
        if type(fn) ~= "function" then return end
        dispatcher.callbacks[event] = dispatcher.callbacks[event] or {}
        dispatcher.callbacks[event][fn] = fn
    end

    target[unregisterName] = function(_, event, fn)
        local bucket = dispatcher.callbacks[event]
        if not bucket then return end
        bucket[fn] = nil
        if not next(bucket) then
            dispatcher.callbacks[event] = nil
        end
    end

    target[unregisterAllName] = function(_, event)
        if event then
            dispatcher.callbacks[event] = nil
        else
            dispatcher.callbacks = {}
        end
    end

    return dispatcher
end
