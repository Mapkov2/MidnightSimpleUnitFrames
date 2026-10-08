local ROOT = assert(arg[1]):gsub("\\", "/"):gsub("/$", "") .. "/"
-- Probe: Preview selection bar X/Y field, Escape after typing a value.
-- Client model used by the stub: EditBox:ClearFocus() runs OnEditFocusLost
-- before it returns (the guard pattern MSUF itself relies on in
-- MSUF_Menu2_Widgets_Controls.lua:967-971 and 1167-1172; Blizzard's TimeManager
-- commits only in OnEditFocusLost after ClearFocus from Enter/Escape:
-- ui\live:Interface/AddOns/Blizzard_TimeManager/Mainline/Blizzard_TimeManager.lua:262-272).
-- Run from repo root.
local function NewObject(kind)
    local o = { _scripts = {}, _shown = true, _text = "", _kind = kind }
    local mt = {}
    mt.__index = function(t, k)
        local f = rawget(mt, k)
        if f then return f end
        if type(k) == "string" and k:match("^%u") then return function() return t end end -- no-op for cosmetic methods
        return nil
    end
    function mt.SetScript(self, name, fn) self._scripts[name] = fn end
    function mt.GetScript(self, name) return self._scripts[name] end
    function mt.HookScript(self, name, fn) local old = self._scripts[name]; self._scripts[name] = function(...) if old then old(...) end fn(...) end end
    function mt.SetText(self, t) self._text = t end
    function mt.GetText(self) return self._text end
    function mt.IsShown(self) return self._shown end
    function mt.Show(self) self._shown = true end
    function mt.Hide(self) self._shown = false end
    function mt.SetShown(self, v) self._shown = v and true or false end
    function mt.CreateTexture() return NewObject("Texture") end
    function mt.CreateFontString() return NewObject("FontString") end
    function mt.CreateAnimationGroup() return NewObject("AnimationGroup") end
    function mt.CreateAnimation() return NewObject("Animation") end
    function mt.SetFocus(self) self._focus = true; local f = self._scripts.OnEditFocusGained; if f then f(self) end end
    function mt.ClearFocus(self)
        if not self._focus then return end
        self._focus = nil
        local f = self._scripts.OnEditFocusLost
        if f then f(self) end
    end
    function mt.GetFrameLevel() return 1 end
    return setmetatable(o, mt)
end
_G.CreateFrame = function(kind) return NewObject(kind) end
_G.UIParent = NewObject("Frame")

local NS = { MSUF2 = {} }
assert(loadfile(ROOT .. "MidnightSimpleUnitFrames_Options/Shell/Menu2/MSUF_Menu2_PreviewSelectionBar.lua"))("x", NS)
local SB = NS.MSUF2.PreviewSelectionBar

local stored = { x = 12, y = 4 }
local writes = {}
local handle = { _key = "name", _label = "Name", IsShown = function() return true end }
local box = NewObject("Frame")
box._selectedHandle = handle
SB.Create(box, {
    IsPlaced = function() return true end,
    HandleList = function() return { handle } end,
    ReadOffsets = function() return stored.x, stored.y end,
    WriteOffsets = function(_, _, x, y, reason)
        stored.x, stored.y = x, y
        writes[#writes + 1] = reason .. "(" .. x .. "," .. y .. ")"
        return true
    end,
})
local editX = box._msuf2SelectionBar.editX
print("before: stored x", stored.x, "field", editX:GetText())
editX:SetFocus()
editX:SetText("250")            -- user types a value
editX._scripts.OnEscapePressed(editX) -- then presses Escape to cancel
print("after Escape: stored x", stored.x, "expected 12 (cancelled)", "writes:", table.concat(writes, " "))

assert(stored.x == 12 and #writes == 0, "Escape committed the typed coordinate")
writes = {}
editX:SetFocus()
editX:SetText("30")
editX._scripts.OnEnterPressed(editX)
print("after Enter: stored x", stored.x, "writes:", #writes, table.concat(writes, " "))

assert(stored.x == 30 and #writes == 1, "Enter writes more than once")
writes = {}
editX:SetFocus()
editX:SetText("40")
editX:ClearFocus()
assert(stored.x == 40 and #writes == 1, "ordinary blur must commit once")
