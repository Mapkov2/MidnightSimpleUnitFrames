-- Additional observations replayed from the original committed builders.
local Semantics = {}
local function Encode(value)
    if value == nil then return "<nil>" end
    return (tostring(value):gsub("[\r\n\t]", " "))
end
function Semantics.Open(M, area, env)
    local rows, bindings, placements = {}, {}, {}
    local bind, move = M.BindNumberWidget, M.Widgets.MoveWidget
    M.BindNumberWidget = function(ctx, widget, get, set, fallback, opts)
        bindings[widget] = tonumber(fallback) or 0
        return bind(ctx, widget, get, set, fallback, opts)
    end
    M.Widgets.MoveWidget = function(widget, parent, x, y, width, align)
        placements[widget] = { align = align }
        return move(widget, parent, x, y, width, align)
    end
    local function Add(...)
        local values = { ... }
        for i = 1, select("#", ...) do values[i] = Encode(select(i, ...)) end
        rows[#rows + 1] = table.concat(values, "\t")
    end
    local function Snapshot(page, state, wanted)
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local control = M.RuntimeControlCatalog.Get(record.controlId)
            local widget = control and control.widget
            if record.pageKey == page and widget and wanted(widget) then
                local command = widget._msuf2CommandAction
                local placement = placements[widget]
                local title = widget._msuf2Title
                local scope, key = tostring(record.settingKey):match("^([^.]+)%.(.+)$")
                local saved = scope and env.MSUF_DB[scope] and env.MSUF_DB[scope][key]
                Add("intent", page, state, record.controlId, record.kind, area == "pvp_trinket" and bindings[widget] or "",
                    placement and placement.align, title and title:GetJustifyH(),
                    widget._msuf2TitleJustify, command and command.get and command.get(), saved)
            end
        end
    end
    local function Probe(page, env, wanted, check)
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local control = M.RuntimeControlCatalog.Get(record.controlId)
            local widget = control and control.widget
            local command = widget and widget._msuf2CommandAction
            local scope, key = tostring(record.settingKey):match("^([^.]+)%.(.+)$")
            if record.pageKey == page and widget and wanted(widget) and command and command.get and scope and env.MSUF_DB[scope] then
                local conf = env.MSUF_DB[scope]
                local original = conf[key]
                for _, sample in ipairs({ { "absent" }, { "false", false }, { "zero", 0 }, { "invalid", "invalid" } }) do
                    conf[key] = sample[2]
                    Add("default", page, record.controlId, sample[1], command.get(), conf[key])
                    check(conf[key] == sample[2], "default reader wrote " .. record.controlId)
                end
                conf[key] = original
                if area == "pvp_trinket" and record.kind == "slider" then
                    for _, sample in ipairs({ { "absent" }, { "invalid", "invalid" }, { "zero", 0 } }) do
                        command.set(sample[2])
                        Add("command-set", page, record.controlId, sample[1], conf[key], command.get())
                        conf[key] = original
                    end
                end
            end
        end
    end
    local function PrepareReset(page, env, wanted, absent)
        for _, record in ipairs(M.RuntimeControlCatalog.GetRecords()) do
            local control = M.RuntimeControlCatalog.Get(record.controlId)
            local widget = control and control.widget
            local scope, key = tostring(record.settingKey):match("^([^.]+)%.(.+)$")
            if record.pageKey == page and widget and wanted(widget) and scope and env.MSUF_DB[scope] then
                local value = env.MSUF_DB[scope][key]
                if absent then env.MSUF_DB[scope][key] = nil
                elseif type(value) == "boolean" then env.MSUF_DB[scope][key] = not value
                elseif type(value) == "number" then env.MSUF_DB[scope][key] = value + 1 end
            end
        end
    end
    return { Snapshot = Snapshot, Probe = Probe, PrepareReset = PrepareReset, Add = Add, Result = function()
        table.sort(rows)
        return table.concat(rows, "\n") .. "\n"
    end }
end
return Semantics
