--- Castbars/MSUF_CastbarPoolPreviews.lua
--- Edit Mode and menu previews of the indexed castbar pools (MSUF_CastbarPools.lua).
---
--- A preview is a non-combat, non-event copy of a pool castbar that mirrors its
--- geometry and styling. It never subscribes to UNIT_SPELLCAST events; the live
--- pool castbars own live state. One prototype serves every pool kind:
--- MSUF_BossCastbars_Preview.lua and MSUF_ArenaCastbars_Preview.lua each pass
--- their pool and the preview-only fields to Pools.DefinePreview.
---
--- Read from the pool descriptor: kind, unitPrefix, maxFrames, framePrefix,
--- poolGlobal, kindFlag, fallbackY, enableKey, db, layoutDelta.
--- Preview descriptor fields:
---   namePrefix      global preview name prefix (MSUF_BossCastbarPreview)
---   firstUnsuffixed true when slot 1 is named namePrefix itself (boss)
---   publishFirstSlot  function(frame) exporting slot 1 under the kind's
---                   documented global (MSUF_BossCastbarPreview)
---   indexField      per-preview slot index field (_msufBossIndex)
---   label           sample spell name
---   targetLabel     sample cast target name
---   showTargetKey   general key of the cast target name toggle
---   showTimeKey     general key of the cast time toggle (test mode)
---   testModeKey     general key of the persistent test mode switch
---
--- Returns the kind's preview object (also Pools.previews[kind]); its api table
--- holds the bound functions the descriptor file exports under the kind's
--- documented global names.

local _, MSUF = ...
MSUF = MSUF or _G.MSUF_NS or _G.MSUF or {}
local Pools = assert(MSUF.Castbars and MSUF.Castbars.Pools, "MSUF_CastbarPools.lua must load first")

local type = type
local tonumber = tonumber
local setmetatable = setmetatable

-- The live pools' geometry (MSUF_CastbarPools.lua).
local ROW_PITCH = Pools.ROW_PITCH
local FALLBACK_X = Pools.FALLBACK_X
local UNITFRAME_GAP = Pools.UNITFRAME_GAP
local Snap = Pools.Snap
local InCombat = Pools.InCombat
-- Preview bar size (px) when the castbar size resolver is missing.
local DEFAULT_WIDTH = 240
local DEFAULT_HEIGHT = 18

local function Translate(text)
    local translate = MSUF.Translate
    if type(translate) == "function" then return translate(text) end
    return text
end

local function GeneralDB()
    local ensure = _G.MSUF_EnsureCastbarGeneralDB
    if type(ensure) == "function" then return ensure() end
    if type(_G.MSUF_EnsureDB) == "function" then
        _G.MSUF_EnsureDB()
    end
    local db = _G.MSUF_DB or {}
    _G.MSUF_DB = db
    db.general = db.general or {}
    return db.general
end

local function CoreFrame(unit)
    local uf = MSUF.UF
    if uf and type(uf.GetFrame) == "function" then
        local frame = uf.GetFrame(unit)
        if frame then return frame end
    end
    local frames = uf and uf.frames
    return frames and frames[unit] or nil
end

local function KindDisabled(kind)
    local db = _G.MSUF_DB
    local unitDB = db and db[kind]
    return unitDB and unitDB.enabled == false or false
end

--- A preview's fill stays hidden (only the bar background shows) until test
--- mode animates it.
local function SetPreviewFillShown(statusBar, shown)
    statusBar:SetValue(0)
    statusBar.MSUF_hideFillTexture = (not shown) or nil
    local fillTexture = statusBar.GetStatusBarTexture and statusBar:GetStatusBarTexture()
    if fillTexture then
        fillTexture:SetAlpha(shown and 1 or 0)
    end
end

local Preview = {}
Preview.__index = Preview

function Preview:Name(index)
    if index == 1 and self.firstUnsuffixed then return self.namePrefix end
    return self.namePrefix .. index
end

function Preview:UnitFrame(index)
    local unit = self.unitPrefix .. index
    return CoreFrame(unit) or _G["MSUF_" .. unit]
end

--- Calls fn(frame, index) for every preview that exists, in slot order.
function Preview:ForEach(fn)
    for index = 1, self.maxFrames do
        local frame = _G[self:Name(index)]
        if frame then fn(frame, index) end
    end
end

--- The persistent Edit Mode condition: the castbar preview option is on and the
--- kind's castbars are in use.
function Preview:ShownInEditMode(general)
    general = general or GeneralDB()
    -- Edit-mode preview flags live in SavedVariables for legacy integrations.
    -- A logout can bypass the normal Edit Mode exit and leave that flag true,
    -- so the runtime session state must remain the authority for visibility.
    if _G.MSUF_UnitEditModeActive ~= true or not general.castbarPlayerPreviewEnabled then
        return false
    end
    if KindDisabled(self.kind) then
        return false
    end
    local shouldUseMSUF = _G.MSUF_ShouldUseMSUFCastbar
    return type(shouldUseMSUF) == "function"
        and shouldUseMSUF(self.kind, general) == true
        or general[self.enableKey] ~= false
end

function Preview:Enabled()
    local general = GeneralDB()
    -- The Menu2 castbar page's transient preview must survive texture and
    -- layout re-applies that funnel through Update, even while the persistent
    -- preview option is off.
    if _G.MSUF2_CastbarPagePreviewUnit == self.kind then
        return not KindDisabled(self.kind)
    end
    return self:ShownInEditMode(general)
end

function Preview:BeginBatch()
    self.batchDepth = self.batchDepth + 1
end

--- Ends one batch level; the last level runs the one refresh the batch held back.
function Preview:EndBatch()
    if self.batchDepth <= 0 then
        self.batchDepth = 0
        return
    end
    self.batchDepth = self.batchDepth - 1
    if self.batchDepth == 0 and self.batchPending then
        self.batchPending = nil
        self:Update()
    end
end

function Preview:HideAll()
    for index = 1, self.maxFrames do
        local frame = _G[self:Name(index)]
        if frame then
            frame:Hide()
        end
    end
end

--- Resolves the bar size of one slot: (width, height, preserveWidth).
function Preview:DesiredSize(index, general, frame)
    if type(_G.MSUF_GetCastbarDesiredSize) == "function" then
        return _G.MSUF_GetCastbarDesiredSize(self.unitPrefix .. index, general, frame, DEFAULT_WIDTH, DEFAULT_HEIGHT)
    end
    return tonumber(general[self.db.width]) or DEFAULT_WIDTH, tonumber(general[self.db.height]) or DEFAULT_HEIGHT
end

--- Creates one preview per unit slot. The preview is intentionally inert: no
--- cast progression, no event registration, just layout and style.
function Preview:Create(index)
    local name = self:Name(index)
    local existing = _G[name]
    if existing then
        return existing
    end

    local width, height = self:DesiredSize(index, GeneralDB(), nil)
    local createPreviewFrame = _G.MSUF_CreateCastbarPreviewFrame
    if type(createPreviewFrame) ~= "function" then
        return nil
    end

    local frame = createPreviewFrame(self.kind, name, {
        parent = UIParent,
        strata = "DIALOG",
        width = width,
        height = height,
        label = self.label,
        showIcon = true,
        showTime = true,
        bgAlpha = 0.8,
        initialValue = 0,
        hideFillTexture = true,
    })
    if not frame then
        return nil
    end

    frame.unit = self.kind
    frame[self.kindFlag] = true
    frame._msufIsPreview = true
    frame[self.indexField] = index
    if frame.statusBar then
        SetPreviewFillShown(frame.statusBar, false)
    end
    if index == 1 then
        self.publishFirstSlot(frame)
    end
    return frame
end

function Preview:ApplyLayout(frame, index)
    if not (frame and frame.statusBar) then
        return
    end

    local general = GeneralDB()
    local width, height, preserveWidth = self:DesiredSize(index, general, frame)
    if width and not preserveWidth then
        width = Snap(frame, width)
    end
    if height then
        height = Snap(frame, height)
    end

    if type(_G.MSUF_ApplyPlayerCastbarSizeAndLayout) == "function" then
        _G.MSUF_ApplyPlayerCastbarSizeAndLayout(frame, general, width, height, preserveWidth)
    else
        frame:SetSize(width, height)
    end

    local kind = self.kind
    if type(_G.MSUF_ApplyCastbarFrameLayer) == "function" then
        _G.MSUF_ApplyCastbarFrameLayer(frame, general, kind)
    end

    if type(_G.MSUF_RefreshCastbarFrame) == "function" then
        _G.MSUF_RefreshCastbarFrame(frame, kind, general)
        if type(_G.MSUF_ApplyCastbarSparkVisual) == "function" then
            _G.MSUF_ApplyCastbarSparkVisual(frame, general)
        end
    elseif type(_G.MSUF_ApplyCastbarVisualsForUnit) == "function" then
        _G.MSUF_ApplyCastbarVisualsForUnit(kind)
    elseif type(_G.MSUF_UpdateCastbarVisuals) == "function" then
        _G.MSUF_UpdateCastbarVisuals(kind)
    end

    local targetText = frame.castTargetText
    if targetText then
        local showTargetName = general[self.showTargetKey] == true
        targetText:SetText(showTargetName and Translate(self.targetLabel) or "")
        if type(_G.MSUF_ApplyCastTargetTextColor) == "function" then
            _G.MSUF_ApplyCastTargetTextColor(frame)
        end
        targetText:SetShown(showTargetName)
    end

    if frame.statusBar then
        SetPreviewFillShown(frame.statusBar, frame.MSUF_testMode and true or false)
    end
end

--- Positioning mirrors the live pool anchoring, so Edit Mode and menu previews
--- show the same detached vs unit-frame-relative behaviour.
function Preview:Position(frame, index)
    if not frame then
        return
    end

    local general = GeneralDB()
    local db = self.db
    local offsetX = Snap(frame, tonumber(general[db.offsetX]) or 0)
    local offsetY = Snap(frame, tonumber(general[db.offsetY]) or 0)

    frame:ClearAllPoints()

    if general[db.detached] == true then
        local layoutX = 0
        local layoutY = -((index - 1) * ROW_PITCH)
        local layoutDelta = _G[self.layoutDelta]
        if type(layoutDelta) == "function" then
            layoutX, layoutY = layoutDelta(index, _G.MSUF_DB[self.kind] or {})
            layoutX = tonumber(layoutX) or 0
            layoutY = tonumber(layoutY) or layoutY
        end
        frame:SetPoint("CENTER", UIParent, "CENTER", offsetX + layoutX, offsetY + (tonumber(layoutY) or 0))
        return
    end

    local unitFrame = self:UnitFrame(index)
    if not unitFrame then
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", FALLBACK_X + offsetX,
            (self.fallbackY + offsetY) - ((index - 1) * ROW_PITCH))
        return
    end

    local unit = self.unitPrefix .. index
    local source = (type(_G.MSUF_GetCastbarUnitframeWidthSource) == "function"
        and _G.MSUF_GetCastbarUnitframeWidthSource(unit)) or unitFrame
    local autoX = 0
    if type(_G.MSUF_GetCastbarAutoAnchorOffsetX) == "function" then
        autoX = _G.MSUF_GetCastbarAutoAnchorOffsetX(general, unit, frame)
    end
    local bottomInset = 0
    if type(_G.MSUF_GetCastbarUnitframeBottomInset) == "function" then
        bottomInset = _G.MSUF_GetCastbarUnitframeBottomInset(unit, frame)
    end
    local gap
    if type(_G.MSUF_GetPhysicalPixelSize) == "function" then
        gap = _G.MSUF_GetPhysicalPixelSize(frame, UNITFRAME_GAP)
    else
        gap = Snap(frame, UNITFRAME_GAP)
    end
    frame:SetPoint("TOPLEFT", source, "BOTTOMLEFT", offsetX + autoX, offsetY - bottomInset - gap)
end

--- Shows one preview under every visible unit frame of the kind and hides the
--- rest. Out of combat only; inside a batch the refresh waits for EndBatch.
function Preview:Update()
    if self.batchDepth > 0 then
        self.batchPending = true
        return
    end
    if InCombat() then
        return
    end
    if not self:Enabled() then
        self:HideAll()
        return
    end

    for index = 1, self.maxFrames do
        local unitFrame = self:UnitFrame(index)
        local frame = self:Create(index)
        if frame and unitFrame and (not unitFrame.IsShown or unitFrame:IsShown()) then
            local castbars = _G[self.poolGlobal]
            local realCastbar = (castbars and castbars[index]) or _G[self.framePrefix .. index]
            if type(_G.MSUF_HardSyncCastbarPreview) == "function" then
                _G.MSUF_HardSyncCastbarPreview(frame, realCastbar)
            end
            self:ApplyLayout(frame, index)
            self:Position(frame, index)
            frame:Show()
        elseif frame then
            frame:Hide()
        end
    end
end

Pools.previews = Pools.previews or {}
--- Every defined preview kind, in definition order (boss, then arena).
Pools.previewOrder = Pools.previewOrder or {}

--- Builds one kind's preview object from its pool and preview descriptor.
--- Called once per kind at load.
function Pools.DefinePreview(pool, desc)
    local poolDesc = pool.descriptor
    local preview = setmetatable({
        kind = poolDesc.kind,
        -- Unit tokens of the kind ("boss", "boss1" ...), for the Edit Mode drag path.
        unitPattern = "^" .. poolDesc.kind .. "%d*$",
        unitPrefix = poolDesc.unitPrefix,
        maxFrames = poolDesc.maxFrames,
        framePrefix = poolDesc.framePrefix,
        poolGlobal = poolDesc.poolGlobal,
        kindFlag = poolDesc.kindFlag,
        fallbackY = poolDesc.fallbackY,
        enableKey = poolDesc.enableKey,
        db = poolDesc.db,
        layoutDelta = poolDesc.layoutDelta,
        namePrefix = desc.namePrefix,
        firstUnsuffixed = desc.firstUnsuffixed == true,
        publishFirstSlot = desc.publishFirstSlot,
        indexField = desc.indexField,
        label = desc.label,
        targetLabel = desc.targetLabel,
        showTargetKey = desc.showTargetKey,
        showTimeKey = desc.showTimeKey,
        testModeKey = desc.testModeKey,
        batchDepth = 0,
    }, Preview)
    -- Bound entry points for the kind's documented globals, which its
    -- descriptor file exports as compatibility aliases.
    preview.api = {
        Update = function() preview:Update() end,
        HideAll = function() preview:HideAll() end,
        Create = function(index) return preview:Create(index) end,
        ApplyLayout = function(frame, index) preview:ApplyLayout(frame, index) end,
        Position = function(frame, index) preview:Position(frame, index) end,
        BeginBatch = function() preview:BeginBatch() end,
        EndBatch = function() preview:EndBatch() end,
    }
    pool.preview = preview
    Pools.previews[preview.kind] = preview
    Pools.previewOrder[#Pools.previewOrder + 1] = preview
    return preview
end
