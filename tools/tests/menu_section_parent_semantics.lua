-- Additional storage and numeric-binding observations, kept apart from frozen historical rows.
local Gaps = {}
local DISPEL_KEYS = {
    "unitDispelOverlayAlpha", "unitDispelOverlayEnabled", "unitDispelOverlayOnHealth",
    "unitDispelOverlayStyle", "unitDispelOverlayTrigger", "unitDispelSymbolAlpha",
    "unitDispelSymbolAnchor", "unitDispelSymbolEnabled", "unitDispelSymbolGrowth",
    "unitDispelSymbolLayer", "unitDispelSymbolMode", "unitDispelSymbolSize",
    "unitDispelSymbolSpacing", "unitDispelSymbolStrata", "unitDispelSymbolStyle", "unitDispelSymbolTrigger",
}
local function Encode(value)
    if value == nil then return "<nil>" end
    return (tostring(value):gsub("[\r\n\t]", " "))
end
function Gaps.Open(M, area, env)
    local rows, bindings = {}, {}
    local bind = M.BindNumberWidget
    M.BindNumberWidget = function(ctx, widget, get, set, fallback, opts)
        bindings[widget] = tonumber(fallback) or 0
        return bind(ctx, widget, get, set, fallback, opts)
    end
    local function Add(...)
        local values = {}
        for i = 1, select("#", ...) do values[i] = Encode(select(i, ...)) end
        rows[#rows + 1] = table.concat(values, "\t")
    end
    local function Storage(record)
        local scope, key = tostring(record.settingKey):match("^([^.]+)%.(.+)$")
        if scope then return scope, key end
        scope = record.pageKey:match("^uf_(.+)$")
        local which, suffix = record.controlId:match("%.unit%.dispel%.(overlay)%.([^.]+)$")
        if not which then which, suffix = record.controlId:match("%.unit%.dispel%.(symbol)%.([^.]+)$") end
        if which and suffix == "enabled" then
            return scope, "unitDispel" .. (which == "overlay" and "Overlay" or "Symbol") .. "Enabled"
        end
        for _, candidate in ipairs(DISPEL_KEYS) do
            if suffix == candidate:lower() then return scope, candidate end
        end
    end
    local function Controls(page, wanted, callback)
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local control = M.RuntimeControlCatalog.Get(record.controlId)
            local widget = control and control.widget
            if record.pageKey == page and widget and wanted(widget) then
                local scope, key = Storage(record)
                local command = widget._msuf2CommandAction
                if scope and env.MSUF_DB[scope] and command and command.get then
                    callback(record, widget, command, env.MSUF_DB[scope], key)
                elseif record.classification == "setting" and record.controlId:find(".unit.dispel.", 1, true) then
                    error("unobserved dispel storage: " .. record.controlId)
                end
            end
        end
    end
    local function Snapshot(page, state, wanted)
        Controls(page, wanted, function(record, widget, command, conf, key)
            Add("storage", page, state, record.controlId, key, conf[key], env.MSUF_DB.general[key], command.get(), bindings[widget])
        end)
    end
    local function Probe(page, _, wanted, check)
        Controls(page, wanted, function(record, widget, command, conf, key)
            local original, general = conf[key], env.MSUF_DB.general[key]
            for _, sample in ipairs({ { "absent" }, { "false", false }, { "zero", 0 }, { "invalid", "invalid" } }) do
                conf[key] = sample[2]
                Add("default", page, record.controlId, key, sample[1], command.get(), conf[key], bindings[widget])
                check(conf[key] == sample[2], "storage reader wrote " .. record.controlId)
            end
            if area == "dispel_overlay" or area == "dispel_symbol" then
                conf[key] = nil
                for _, sample in ipairs({ { "absent" }, { "false", false }, { "zero", 0 }, { "invalid", "invalid" } }) do
                    env.MSUF_DB.general[key] = sample[2]
                    Add("legacy-fallback", page, record.controlId, key, sample[1], command.get(), conf[key], env.MSUF_DB.general[key])
                    check(conf[key] == nil and env.MSUF_DB.general[key] == sample[2], "legacy reader wrote " .. record.controlId)
                end
                env.MSUF_DB.general[key] = general
            end
            conf[key] = original
            if record.kind == "slider" then
                for _, sample in ipairs({ { "absent" }, { "invalid", "invalid" }, { "zero", 0 } }) do
                    command.set(sample[2])
                    Add("command-set", page, record.controlId, key, sample[1], conf[key], command.get(), bindings[widget])
                    conf[key] = original
                end
            end
        end)
    end
    local function PrepareReset(page, _, wanted, absent)
        Controls(page, wanted, function(_, _, command, conf, key)
            local value = command.get()
            if absent then conf[key] = nil
            elseif type(value) == "boolean" then conf[key] = not value
            elseif type(value) == "number" then conf[key] = value + 1
            elseif type(value) == "string" then conf[key] = "customized" end
        end)
    end
    return { Snapshot = Snapshot, Probe = Probe, PrepareReset = PrepareReset, Add = Add, Result = function()
        table.sort(rows)
        return table.concat(rows, "\n") .. "\n"
    end }
end
return Gaps
