-- Executable current-owner checks without changing real UI state or fixture rows.
local function Button(widget, spec)
    assert(spec and type(spec.action) == "function", "declared button action missing")
    local click, script = assert(widget.Click), widget:GetScript("OnClick")
    local calls, token = 0, {}
    widget.Click = function(self, button, down, tail)
        assert(self == widget, "declared button wrong native widget")
        assert(button == "RightButton" and down == true and tail == token, "declared button native inputs lost")
        calls = calls + 1
        return token, nil, false, "native tail"
    end
    local function Verify(action)
        calls = 0
        local ok, a, b, d, e = pcall(action, {}, "RightButton", true, token)
        assert(ok, "declared button current native dispatch failed: " .. tostring(a))
        assert(calls == 1 and a == token and b == nil and d == false and e == "native tail",
            "declared button bypasses complete current native owner/returns")
    end
    local ok, why = pcall(function()
        Verify(spec.action)
        if spec.kind == "button" and spec.set then Verify(spec.set) end
    end)
    widget.Click = click
    assert(ok, why)
    assert(widget:GetScript("OnClick") == script, "declaration changed installed button owner")
end
local function Command(widget, spec, command)
    assert(spec.owner == widget, "control_declaration replaced composite owner")
    if not command then return end
    local old, token, calls = widget._msuf2CommandAction, {}, 0
    widget._msuf2CommandAction = {
        get = function() return token end,
        set = function(value, tail)
            assert(value == token and tail == false, "declared command current inputs lost")
            calls = calls + 1
            return token, nil, false
        end,
    }
    local ok, value = true, nil
    if command.get then ok, value = pcall(spec.get) end
    local goodGet = ok and (not command.get or value == token)
    local a, b, d
    if command.set then ok, a, b, d = pcall(spec.set, token, false) end
    widget._msuf2CommandAction = old
    assert(goodGet and ok and (not command.set or (calls == 1 and a == token and b == nil and d == false)),
        "control_declaration lost current composite command owner/returns")
end
return { Button = Button, Command = Command }
