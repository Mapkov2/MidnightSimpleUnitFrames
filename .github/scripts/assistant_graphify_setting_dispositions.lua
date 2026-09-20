-- Deterministic review ledger for Graphify setting-shaped nodes which do
-- not resolve to an executable Assistant setting contract.
--
-- The path inventory is intentionally exact. Broad categories are only
-- assigned after membership in this reviewed set is established, so a new or
-- renamed Graphify candidate fails the release gate even if its spelling would
-- otherwise match a category rule. Graphify output is read-only input to the
-- gate; this module never runs Graphify or writes graphify-out.
local M = {
    schemaVersion = 1,
}

M.categoryPolicy = {
    api_runtime = {
        reason = "Graphify extracted a callable module API or method table member as a setting-shaped node; it is runtime behavior, not persisted user configuration.",
    },
    local_projection = {
        reason = "Graphify extracted a transient frame, route, preview, or edit-mode object member; the value is runtime-local and is not a SavedVariables control.",
    },
    assistant_metadata = {
        reason = "Graphify extracted Assistant-only descriptor, routing, or workflow metadata; it describes a target but is not itself mutable user configuration.",
    },
    container_internal = {
        reason = "Graphify extracted a namespace, aggregate table, migration marker, or internal container; scalar child controllers own any user-facing values.",
    },
    canonical_alias = {
        reason = "This backing scalar or compatibility channel is owned by a named canonical Assistant controller; it must not become a second independent controller.",
    },
    action_route = {
        reason = "Graphify extracted a Menu action sentinel as a setting; the named Assistant action owns the operation.",
    },
    compatibility_fallback = {
        reason = "This is an explicitly reviewed legacy, migration, import, fallback, or compatibility projection without an independent user-facing control identity.",
    },
}

-- Action sentinels discovered as setting-shaped nodes. Owners are verified
-- against Registry:GetAction by the crosswalk release gate.
M.actionOwners = {
    ["profile.copy_current"] = "copy_profile",
    ["profile.create"] = "create_profile",
    ["profile.delete_current"] = "delete_profile",
    ["profile.reset_current"] = "reset_profile",
    ["profiles.browse_wago"] = "copy_wago_profiles_link",
}

-- Backing channel aliases with an unambiguous canonical color controller.
-- These owners are verified as executable settings by the release gate.
M.aliasOwners = {
    -- Legacy per-unit power bar mirrors. MSUF_ReadUnitPowerBarEnabled
    -- (Kernel/MSUF_Util.lua) reads <unit>.showPowerBar first and only falls
    -- back to these while the unit key is nil, so the unit control owns the
    -- visible identity (AutoCoverage CANONICAL_PATH_OWNERS, 2026-09-09).
    ["bars.showPlayerPowerBar"] = "player.showPowerBar",
    ["bars.showTargetPowerBar"] = "target.showPowerBar",
    ["bars.showFocusPowerBar"] = "focus.showPowerBar",
    ["bars.showBossPowerBar"] = "boss.showPowerBar",
    ["general.fontSlug"] = "fontScope.shared.fontMonochrome",
    ["general.healPredEnabled"] = "general.showSelfHealPrediction",
    ["general.powerGradientDirDown"] = "general.powerGradientDirection",
    ["general.powerGradientDirLeft"] = "general.powerGradientDirection",
    ["general.powerGradientDirRight"] = "general.powerGradientDirection",
    ["general.powerGradientDirUp"] = "general.powerGradientDirection",
    ["player.boldText"] = "fontScope.player.outline",
    ["player.noOutline"] = "fontScope.player.outline",
    ["general.aggroBorderB"] = "general.aggroBorderColor",
    ["general.aggroBorderG"] = "general.aggroBorderColor",
    ["general.aggroBorderR"] = "general.aggroBorderColor",
    ["general.barBgTexture"] = "general.barBackgroundTexture",
    ["general.barBgClassColor"] = "general.barBgColorMode",
    ["general.barBgMatchHPColor"] = "general.barBgColorMode",
    ["general.barBorderA"] = "general.barOutlineColor",
    ["general.barBorderB"] = "general.barOutlineColor",
    ["general.barBorderG"] = "general.barOutlineColor",
    ["general.barBorderR"] = "general.barOutlineColor",
    ["general.barOutlineColorB"] = "general.barOutlineColor",
    ["general.barOutlineColorG"] = "general.barOutlineColor",
    ["general.barOutlineColorR"] = "general.barOutlineColor",
    ["general.castbarInterruptFeedbackB"] = "general.castbarInterruptFeedbackColor",
    ["general.castbarInterruptFeedbackG"] = "general.castbarInterruptFeedbackColor",
    ["general.castbarInterruptFeedbackR"] = "general.castbarInterruptFeedbackColor",
    ["general.castbarInterruptUnavailableB"] = "general.castbarInterruptUnavailableColor",
    ["general.castbarInterruptUnavailableG"] = "general.castbarInterruptUnavailableColor",
    ["general.castbarInterruptUnavailableR"] = "general.castbarInterruptUnavailableColor",
    ["general.castbarInterruptibleB"] = "general.castbarInterruptibleColor",
    ["general.castbarInterruptibleG"] = "general.castbarInterruptibleColor",
    ["general.castbarInterruptibleR"] = "general.castbarInterruptibleColor",
    ["general.castbarNonInterruptibleB"] = "general.castbarNonInterruptibleColor",
    ["general.castbarNonInterruptibleG"] = "general.castbarNonInterruptibleColor",
    ["general.castbarNonInterruptibleR"] = "general.castbarNonInterruptibleColor",
    ["general.healAbsorbBarColorA"] = "general.healAbsorbBarColor",
    ["general.healAbsorbBarColorB"] = "general.healAbsorbBarColor",
    ["general.healAbsorbBarColorG"] = "general.healAbsorbBarColor",
    ["general.healAbsorbBarColorR"] = "general.healAbsorbBarColor",
    ["general.hlPurgeColorB"] = "general.purgeBorderColor",
    ["general.hlPurgeColorG"] = "general.purgeBorderColor",
    ["general.hlPurgeColorR"] = "general.purgeBorderColor",
    ["general.powerBarBgColorB"] = "general.powerBarBgColor",
    ["general.powerBarBgColorG"] = "general.powerBarBgColor",
    ["general.powerBarBgColorR"] = "general.powerBarBgColor",
    ["general.purgeBorderColorB"] = "general.purgeBorderColor",
    ["general.purgeBorderColorG"] = "general.purgeBorderColor",
    ["general.purgeBorderColorR"] = "general.purgeBorderColor",
    ["general.restedStateIndicatorIconStyle"] = "player.restedStateIndicatorIconStyle",
    ["general.shortenNameShowDots"] = "fontScope.shared.shortenNameNoEllipsis",
    ["gf_party.barOutlineColorA"] = "barScope.gf_party.barOutlineColor",
    ["gf_raid.barOutlineColorA"] = "barScope.gf_raid.barOutlineColor",
    ["player.hpTextMode"] = "player.textRight",
    ["player.powerTextMode"] = "player.powerTextRight",
}

local REVIEWED_PATHS = [=[
Auras3.ApplyFontsFromGlobal
Auras3.RefreshAll
Bars.ApplyBarBackgroundVisual
Bars.CompileHealthBackgroundPlan
Bars.RefreshHealthGradientBackground
Bars.RefreshHealthBarBackgroundColor
Bars._ApplyOverlayTextureAlpha
Bars._ClassBackgroundColor
Bars._DarkTint
Bars._MatchHPColor
Castbars.Apply
Castbars.Backend
Castbars.Disable
Castbars.Enable
Castbars.Engine
Castbars.IsEnabled
Castbars.NativeOwner
Castbars.Runtime
Castbars.Visuals
ClassPower.Apply
ClassPower.Disable
ClassPower.Enable
ClassPower.IsEnabled
Focus.ClearHover
Focus.ClearPopupFocus
Focus.GetSelection
Focus.Hide
Focus.NotifyPositionChanged
Focus.NotifySettingChanged
Focus.NudgeSelection
Focus.OpenFullSettings
Focus.Pulse
Focus.RefreshPopupFocus
Focus.ResetPosition
Focus.SetHover
Focus.SetPopupFocus
Focus.SetSelection
Focus.Show
Focus.Sync
Gameplay.BeginHistory
Gameplay.CheckpointHistory
Gameplay.Clamp
Gameplay.CommitHistory
Gameplay.EnableKeyboardNudge
Gameplay.GetNudgeStep
Gameplay.GetPlayerSpecID
Gameplay.IsTextInputFocused
Gameplay.RefreshKeyboardNudge
Gameplay.ReleaseKeyboardNudge
Gameplay.RoundInt
Gameplay.SelectNudgeFrame
Gameplay.SetupArrowNudge
Gameplay.SyncNudgeEvents
Profile.ActiveProfileName
Profile.CharMeta
Profile.CharacterKey
Profile.CompactName
Profile.CopyURL
Profile.DeleteCreated
Profile.DisplayProfileName
Profile.ExportKind
Profile.GetSpecProfile
Profile.KindLabels
Profile.List
Profile.NewCharacterProfile
Profile.ProfileExists
Profile.Refresh
Profile.ResolveProfileName
Profile.ResolveSpecID
Profile.SetNewCharacterProfile
Profile.SetSpecAutoSwitch
Profile.SetSpecProfile
Profile.ShowReload
Profile.SpecAutoSwitchEnabled
Profile.SpecLabel
Profile.SpecMeta
Profile.SummaryText
auras3
auras3.DBRef
auras3.GetDurationBarColor
auras3._msufAuras3TranslatedFromLegacyAuras2
auras3.boss.custom1.placed.reminderEnabled
auras3.boss.custom4.placed.sortMethod
auras3.focus.custom1.placed.reminderEnabled
auras3.focus.custom4.placed.sortMethod
auras3.player.custom1.placed.reminderEnabled
auras3.shared
auras3.showBoss
auras3.showFocus
auras3.showTarget
auras3.target.custom1.placed.reminderEnabled
auras3.target.custom4.placed.sortMethod
bars
bars._msufDetachedPowerBorderMigrated_v1
bars.showTargetPowerBar
bars.showPlayerPowerBar
bars.showFocusPowerBar
bars.showBossPowerBar
bars.altMana
bars.classPower
bars.classPowerFullColorEnabled
bars.classPowerSlotColorModes
bars.classPowerTextAnchor
bars.classPowerTextFormat
bars.classPowerTextOffset
bars.continuousTextFormat
bars.cpCond
bars.cpSound
bars.detachedPowerBarBgTexture
bars.detachedPowerBarTexture
bars.highlightBorderThickness
bars.playerHPBar
bars.powerBarBgMatchBarColor
bars.stagger
boss.buff
boss.debuff
boss._bossLayoutMigrated
castbars.CASTBAR_DETAIL_FIELDS
castbars.CASTBAR_KEYS
castbars._GetFontFlags
castbars._GetFontPath
classPower.SetBackdropColor
classPower.SetFrameLevel
classPower.enabled
classPower.notches
classPower.runeTexts
classPower.segmentBgs
classPower.segmentEdges
classPower.segments
classPower.text
classPower.text.SetJustifyV
focus.ClearFocus
focus.buff
focus.debuff
focus.IsObjectType
focus.active
focus.kind
focus.slot
gameplay
gameplay.apexAlert
gameplay.combatOffset
gameplay.combatState
gameplay.combatTimer
gameplay.combat_enter_color
gameplay.combat_state_color_sync
gameplay.crosshair
gameplay.crosshair_in
gameplay.crosshair_out
gameplay.enter
gameplay.firstDance
gameplay.kickTracker
gameplay.leave
gameplay.playerTotems
gameplay.reset
gameplay.timer
general
general.UIScale
general._fontScopeKey
general._msuf2Width
general._msufFactoryProfileApplied
general._msufPreviewDragHintExperienced
general.aggroBorderB
general.aggroBorderG
general.aggroBorderR
general.barBackgroundAlpha
general.barBgClassColor
general.barBgMatchHPColor
general.barBgTexture
general.barBorderA
general.barBorderB
general.barBorderG
general.barBorderR
general.barOutlineColorB
general.barOutlineColorG
general.barOutlineColorMode
general.barOutlineColorR
general.blizzardEditModeSnapshot
general.boldText
general.bossCastSpellNameMaxChars
general.bossCastSpellNameMaxLen
general.bossCastSpellNameReserved
general.bossCastSpellNameReservedSpace
general.bossCastSpellNameShortening
general.bossSpellNameMaxLen
general.bossSpellNameReservedSpace
general.castbarBg
general.castbarBorder
general.castbarInterruptFeedbackB
general.castbarInterruptFeedbackG
general.castbarInterruptFeedbackR
general.castbarInterruptUnavailableB
general.castbarInterruptUnavailableG
general.castbarInterruptUnavailableR
general.castbarInterruptibleB
general.castbarInterruptibleG
general.castbarInterruptibleR
general.castbarNativeTimer
general.castbarNonInterruptibleB
general.castbarNonInterruptibleG
general.castbarNonInterruptibleR
general.classBarBg
general.classBarBgA
general.classPowerBgColorOverrides
general.classPowerColorOverrides
general.colorHealthTextByHealth
general.colorPowerTextByType
general.darkBarB
general.darkBarG
general.darkBarR
general.dispelBorderEnabled
general.enableAggroHighlight
general.enableHealPrediction
general.enableHighlightOnHover
general.fontBaselineOffset
general.fontMonochrome
general.fontShadowDistance
general.fontShadowOpacity
general.fontShadowStrength
general.fontTextAlpha
general.healAbsorbBarColorA
general.healAbsorbBarColorB
general.healAbsorbBarColorG
general.healAbsorbBarColorR
general.healPredictionColorA
general.healPredictionColorB
general.healPredictionColorG
general.healPredictionColorR
general.hlDispelBorderEnabled
general.hlPurgeBorderEnabled
general.hlPurgeColorB
general.hlPurgeColorG
general.hlPurgeColorR
general.hpOffsetX
general.hpOffsetY
general.hpPowerTextSelectedKey
general.hpTextLayer
general.hpTextMode
general.hpTextOffsetX
general.hpTextOffsetY
general.hpTextReverse
general.meleeRangeSpellID
general.minimapIconDB
general.minimapIconDB.hide
general.nameAnchor
general.nameClassColor
general.nameColorB
general.nameColorG
general.nameColorMode
general.nameColorR
general.nameNpcClassColor
general.nameOffsetX
general.nameOffsetY
general.nameShortenEnabled
general.nameTextAnchor
general.nameTextLayer
general.nameTextOffsetX
general.nameTextOffsetY
general.noOutline
general.npcNameRed
general.powerBarBgColorA
general.powerBarBgColorB
general.powerBarBgColorG
general.powerBarBgColorR
general.powerBarColorB
general.powerBarColorG
general.powerBarColorMode
general.powerBarColorR
general.powerColorOverrides
general.powerOffsetX
general.powerOffsetY
general.powerTextLayer
general.powerTextMode
general.powerTextOffsetX
general.powerTextOffsetY
general.purgeBorderColorB
general.purgeBorderColorG
general.purgeBorderColorR
general.purgeBorderEnabled
general.rangeFadeLayerMode
general.reducedMotion
general.shortenNameClipSide
general.shortenNameMaxChars
general.shortenNameShowDots
general.shortenNames
general.statusIndicators
general.statusTextEnabled
general.textBackdrop
general.textLayer
general.unifiedBar
general.useShortNumbers
gf_mythicraid.masqueEnabled
gf_party.barOutlineColorA
gf_party.fontSize
gf_party.gradientDirection
gf_party.masqueEnabled
gf_raid.barOutlineColorA
gf_raid.fontSize
gf_raid.gradientDirection
gf_raid.masqueEnabled
global.analytics
global.assistantNoMatch
global.bindings
global.bindings.commands
global.char
global.cooldownAnchorProviderDecisions
global.defaultProfileForNewChars
global.firstLoad6
global.firstLoad6ProfileImported
global.global
global.global.assistantNoMatch
global.global.assistantQueuedChanges
global.guidedTour6
global.names
global.profiles
global.reason
global.upgradeHighlights
player.barOutlineColorA
player.boldText
player.buff
player.debuff
player.castbar
player.class
player.fontOverride
player.health
player.hpPowerTextOverride
player.hpTextMode
player.items
player.noOutline
player.power
player.powerTextMode
player.powerTextOffsetX
player.powerTextOffsetY
player.showHPText
profile.PosX
profile.PosY
profile.Positions
profile.ScaleSize
profile._msufDefaultsRevision
profile._msufDispelPriorityMigration
profile._msufProfileNormalizationRevision
profile._msufProfileSchema
profile.anchor
profile.aura
profile.auras
profile.auras2
profile.auras3
profile.bars
profile.boss
profile.copy_current
profile.create
profile.deadAlive
profile.delete_current
profile.duration
profile.fromAlpha
profile.fromCurrent
profile.general
profile.general._msufPreviewDragHintExperienced
profile.general.anchorName
profile.general.fontBaselineOffset
profile.general.previewDragHintAnimationEnabled
profile.general.showGameMenuButton
profile.general.showNavigationIcons
profile.gf_mythicraid
profile.gf_party
profile.gf_raid
profile.health
profile.maxPower
profile.pointCharge
profile.power
profile.reset_current
profile.rune
profile.scaleFrom
profile.scaleOrigin
profile.scaleTo
profile.shortenNameClipSide
profile.shortenNameFrontMaskPx
profile.shortenNameMaxChars
profile.shortenNameShowDots
profile.shortenNames
profile.smoothing
profile.spellSucceeded
profile.toAlpha
profile.type
profile.unitframes
profile.warlockPred
profiles.Default
profiles.browse_wago
target.Click
target.buff
target.debuff
target.GetCenter
target.GetFrameLevel
target.GetHeight
target.GetObjectType
target.GetParent
target.GetBackdropBorderColor
target.GetBackdropColor
target.GetScript
target.GetWidth
target.getColorByClass
target.setColorByClass
target.HookScript
target.IsActive
target.IsEnabled
target.HasFocus
target.IsShown
target.Nudge
target.ReleasePreviewInteraction
target.ReleaseRuntimePreview
target.SetCounter
target.SetBackdropBorderColor
target.SetBackdropColor
target.SetScript
target.Switch
target._animationEnabled
target._dragging
target._lastEmpowerProgress
target._lastEmpowerStageTick
target._msuf2CollapsibleEntry
target._msuf2CompactExpandButton
target._msuf2CompactHeader
target._msuf2FixedPreviewExpanderRecord
target._msuf2GuidedActionHooks
target._msuf2PinnedFloating
target._msuf2PinnedPreviewPageKey
target._msuf2PinnedPreviewWrapper
target._msuf2PreferredRestoreHeight
target._msuf2PreferredRestoreYOffset
target._msuf2UnitPageHostShown
target._msuf2BackdropBorderR
target._msuf2BackdropInfoApplied
target._msuf2BackdropR
target._msuf2GlassApplied
target._msuf2SliderVisualReady
target._msufEM2BeginDrag
target._msufGFEM2Kind
target._msufCPPreviewHostShown
target._stageFlashStart
target._stageFlashUntil
target.anchor
target.captureState
target.cdm
target.colors
target.controlResults
target.currentStageId
target.currentStageIndex
target.cursors
target.dbKey
target.events
target.fonts
target.frame
target.frameType
target.full
target.gate
target.geometry
target.getOpacity
target.h
target.hasOpacity
target.hpPowerTextOverride
target.key
target.keys
target.layer
target.layout
target.norms
target.playerHP
target.playerHPTextures
target.preferences
target.prefix
target.reanchor
target.restoreState
target.schema
target.scope
target.sectionMetadata
target.sectionResults
target.setRGB
target.skippedControls
target.stageResults
target.status
target.strata
target.structure
target.syncNow
target.textures
target.title
target.unitOrScope
target.visuals
target.w
target.x
target.yTop
boss.showClassTextIndicator
boss.showRaceIndicator
boss.classTextIndicatorSize
boss.raceIndicatorSize
boss.statusAFKTextSize
boss.statusAFKTimerSize
boss.statusDNDTextSize
boss.statusGhostTextSize
boss.statusAFKTimerEnabled
classPower.GetFrameLevel
classPower._msufCPPreviewAnim
classPower._msufCPPreviewAnim.bars.classPowerShowText
classPower._msufCPPreviewAnim.spec.nativeDurationText
classPower._msufSecondaryTimer
classPower.textOwner
classPower.textOwner.EnableMouse
classPower.textOwner.SetFrameLevel
focus.showClassTextIndicator
focus.showRaceIndicator
focus.classTextIndicatorSize
focus.raceIndicatorSize
focus.statusAFKTextSize
focus.statusAFKTimerSize
focus.statusDNDTextSize
focus.statusGhostTextSize
focus.statusAFKTimerEnabled
focustarget.showClassTextIndicator
focustarget.showRaceIndicator
focustarget.classTextIndicatorSize
focustarget.raceIndicatorSize
focustarget.statusAFKTextSize
focustarget.statusAFKTimerSize
focustarget.statusDNDTextSize
focustarget.statusGhostTextSize
focustarget.statusAFKTimerEnabled
general.dispelTypeColorOverrides
general.fontSlug
general.healPredEnabled
general.powerGradientDirDown
general.powerGradientDirLeft
general.powerGradientDirRight
general.powerGradientDirUp
general.statusAFKTimerEnabled
pet.showClassTextIndicator
pet.showRaceIndicator
pet.classTextIndicatorSize
pet.raceIndicatorSize
pet.statusAFKTimerSize
pet.statusAFKTimerEnabled
player.classTextIndicatorSize
player.raceIndicatorSize
player.statusAFKTimerSize
player.statusAFKTimerEnabled
target.classTextIndicatorSize
target.raceIndicatorSize
target.statusAFKTimerSize
target.statusAFKTimerEnabled
target.type
targettarget.showClassTextIndicator
targettarget.showRaceIndicator
targettarget.classTextIndicatorSize
targettarget.raceIndicatorSize
targettarget.statusAFKTimerSize
targettarget.statusAFKTimerEnabled
]=]

local reviewed = {}
local reviewedCount = 0
for path in REVIEWED_PATHS:gmatch("[^\r\n]+") do
    assert(path ~= "", "blank Graphify disposition path")
    assert(not reviewed[path], "duplicate Graphify disposition path: " .. path)
    reviewed[path] = true
    reviewedCount = reviewedCount + 1
end

local API_ROOTS = {
    Auras3 = true, Bars = true, Castbars = true, ClassPower = true,
    Focus = true, Gameplay = true, Profile = true,
}

local CONTAINER_PATHS = {
    ["auras3"] = true,
    ["auras3.DBRef"] = true,
    ["auras3.shared"] = true,
    ["bars"] = true,
    ["bars.altMana"] = true,
    ["bars.classPower"] = true,
    ["bars.classPowerFullColorEnabled"] = true,
    ["bars.classPowerSlotColorModes"] = true,
    ["bars.classPowerTextOffset"] = true,
    ["bars.cpCond"] = true,
    ["bars.cpSound"] = true,
    ["bars.playerHPBar"] = true,
    ["bars.stagger"] = true,
    ["castbars.CASTBAR_DETAIL_FIELDS"] = true,
    ["castbars.CASTBAR_KEYS"] = true,
    ["classPower.notches"] = true,
    ["classPower.runeTexts"] = true,
    ["classPower.segmentBgs"] = true,
    ["classPower.segmentEdges"] = true,
    ["classPower.segments"] = true,
    ["classPower.text"] = true,
    ["gameplay"] = true,
    ["gameplay.apexAlert"] = true,
    ["gameplay.combatOffset"] = true,
    ["gameplay.combatState"] = true,
    ["gameplay.combatTimer"] = true,
    ["gameplay.crosshair"] = true,
    ["gameplay.firstDance"] = true,
    ["gameplay.kickTracker"] = true,
    ["gameplay.playerTotems"] = true,
    ["general"] = true,
    ["general.classPowerBgColorOverrides"] = true,
    ["general.classPowerColorOverrides"] = true,
    ["general.dispelTypeColorOverrides"] = true,
    ["general.minimapIconDB"] = true,
    ["general.powerColorOverrides"] = true,
    ["general.statusIndicators"] = true,
    ["global.analytics"] = true,
    ["global.assistantNoMatch"] = true,
    ["global.bindings"] = true,
    ["global.bindings.commands"] = true,
    ["global.char"] = true,
    ["global.cooldownAnchorProviderDecisions"] = true,
    ["global.global"] = true,
    ["global.global.assistantNoMatch"] = true,
    ["global.global.assistantQueuedChanges"] = true,
    ["global.profiles"] = true,
    ["player.items"] = true,
    ["profile.Units"] = true,
    ["profile.aura"] = true,
    ["profile.auras"] = true,
    ["profile.auras2"] = true,
    ["profile.auras3"] = true,
    ["profile.bars"] = true,
    ["profile.boss"] = true,
    ["profile.general"] = true,
    ["profile.gf_mythicraid"] = true,
    ["profile.gf_party"] = true,
    ["profile.gf_raid"] = true,
    ["profile.profile"] = true,
    ["profile.unitframes"] = true,
    ["profiles.Default"] = true,
}

local function IsCallablePath(path)
    local root = path:match("^([^.]+)%.")
    if API_ROOTS[root] then return true end
    local member = path:match("%.([^.]+)$") or ""
    return member:match("^[A-Z][%w_]*$") ~= nil
        and (member:match("^Apply") or member:match("^Clear")
            or member:match("^Disable") or member:match("^Enable")
            or member:match("^Get") or member:match("^Hide")
            or member:match("^Hook") or member:match("^Is")
            or member:match("^Notify") or member:match("^Nudge")
            or member:match("^Open") or member:match("^Pulse")
            or member:match("^Refresh") or member:match("^Reset")
            or member:match("^Set") or member:match("^Show")
            or member:match("^Switch") or member:match("^Sync")) ~= nil
end

local function IsLocalProjection(path)
    return path:match("^classPower%.") ~= nil
        or path:match("^focus%.") ~= nil
        or path:match("^target%.") ~= nil
        or path == "player.HealthBar"
        or path == "player.castbar"
        or path == "player.fontOverride"
        or path == "player.health"
        or path == "player.power"
end

function M.ClassifyGraphCandidate(path, tier)
    path = tostring(path or "")
    if not reviewed[path] then return nil end

    local actionOwner = M.actionOwners[path]
    if actionOwner then
        return { category = "action_route", ownerAction = actionOwner, policy = M.categoryPolicy.action_route }
    end

    local settingOwner = M.aliasOwners[path]
    if settingOwner then
        return { category = "canonical_alias", ownerSetting = settingOwner, policy = M.categoryPolicy.canonical_alias }
    end

    if IsCallablePath(path) then
        return { category = "api_runtime", policy = M.categoryPolicy.api_runtime }
    end

    if CONTAINER_PATHS[path]
        or path:find("._msuf", 1, true)
        or path:match("^profile%._msuf")
    then
        return { category = "container_internal", policy = M.categoryPolicy.container_internal }
    end

    if tier == "assistant_only" then
        return { category = "assistant_metadata", policy = M.categoryPolicy.assistant_metadata }
    end

    if IsLocalProjection(path) then
        return { category = "local_projection", policy = M.categoryPolicy.local_projection }
    end

    return { category = "compatibility_fallback", policy = M.categoryPolicy.compatibility_fallback }
end

function M.ReviewedGraphPathCount()
    return reviewedCount
end

function M.ReviewedGraphPaths()
    local out = {}
    for path in pairs(reviewed) do out[#out + 1] = path end
    table.sort(out)
    return out
end

-- candidates: array of { path, tier }
-- context:
--   evidenceByPath[path] = { sourceFile, sourceLocation }
--   hasExecutableSetting(key), hasExecutableAction(key)
function M.ValidateGraphCandidates(candidates, context)
    context = context or {}
    local report = {
        candidateCount = 0,
        reviewedCount = reviewedCount,
        classifiedCount = 0,
        byCategory = {},
        unclassified = {},
        stale = {},
        missingEvidence = {},
        invalidOwners = {},
    }
    local seen = {}

    for i = 1, #(candidates or {}) do
        local row = candidates[i] or {}
        local path = tostring(row.path or "")
        report.candidateCount = report.candidateCount + 1
        if path ~= "" then seen[path] = true end

        local disposition = M.ClassifyGraphCandidate(path, row.tier)
        if not disposition then
            report.unclassified[#report.unclassified + 1] = path
        else
            report.classifiedCount = report.classifiedCount + 1
            report.byCategory[disposition.category] = (report.byCategory[disposition.category] or 0) + 1
            local evidence = context.evidenceByPath and context.evidenceByPath[path]
            if type(evidence) ~= "table"
                or tostring(evidence.sourceFile or "") == ""
                or tostring(evidence.sourceLocation or "") == ""
            then
                report.missingEvidence[#report.missingEvidence + 1] = path
            end
            if disposition.ownerSetting
                and not (type(context.hasExecutableSetting) == "function"
                    and context.hasExecutableSetting(disposition.ownerSetting))
            then
                report.invalidOwners[#report.invalidOwners + 1] =
                    path .. " -> setting:" .. tostring(disposition.ownerSetting)
            end
            if disposition.ownerAction
                and not (type(context.hasExecutableAction) == "function"
                    and context.hasExecutableAction(disposition.ownerAction))
            then
                report.invalidOwners[#report.invalidOwners + 1] =
                    path .. " -> action:" .. tostring(disposition.ownerAction)
            end
        end
    end

    for path in pairs(reviewed) do
        if not seen[path] then report.stale[#report.stale + 1] = path end
    end
    table.sort(report.unclassified)
    table.sort(report.stale)
    table.sort(report.missingEvidence)
    table.sort(report.invalidOwners)
    report.pass = #report.unclassified == 0
        and #report.stale == 0
        and #report.missingEvidence == 0
        and #report.invalidOwners == 0
        and report.classifiedCount == report.candidateCount
    return report
end

-- Exact inventory of generated Registry scalars which intentionally have no
-- Menu2 destination. This closes the former unsafe proof where the routing
-- audit accepted any entry merely because its category contained
-- "Auto (generated)". A new, removed, or newly mapped key now fails.
local REVIEWED_GENERATED_NO_MENU_KEYS = [=[
general.absorbBarColorA
general.absorbBarColorB
general.absorbBarColorG
general.absorbBarColorMigrationV2
general.absorbBarColorR
general.aggroBorderColorB
general.aggroBorderColorG
general.aggroBorderColorR
general.aggroIndicatorMode
general.anchorName
general.anchorToCooldown
general.barBorderStyle
general.barOutlineThickness
general.bossCastSpellNameFont
general.bossCastSpellNameOutline
general.bossCastTimeFont
general.bossCastTimeOutline
general.bossCastbarBackend
general.bossCastbarTestMode
general.castbarBgA
general.castbarBgB
general.castbarBgG
general.castbarBgR
general.castbarBorderA
general.castbarBorderB
general.castbarBorderG
general.castbarBorderR
general.castbarFocusBackend
general.castbarFocusShowTargetName
general.castbarFocusSpellNameFont
general.castbarFocusSpellNameOutline
general.castbarFocusTimeFont
general.castbarFocusTimeOutline
general.castbarGlobalHeight
general.castbarGlobalWidth
general.castbarGraceMs
general.castbarIconZoom
general.castbarInterruptColor
general.castbarPlayerDetached
general.castbarPlayerMatchUnitWidth
general.castbarPlayerMatchUnitframe
general.castbarPlayerPreviewEnabled
general.castbarPlayerSameWidthAsCDMEssential
general.castbarPlayerSpellNameFont
general.castbarPlayerSpellNameOutline
general.castbarPlayerTimeFont
general.castbarPlayerTimeOutline
general.castbarShowIcon
general.castbarShowSpellName
general.castbarTargetBackend
general.castbarTargetDetached
general.castbarTargetMatchUnitWidth
general.castbarTargetMatchUnitframe
general.castbarTargetSameWidthAsCDMEssential
general.castbarTargetShowTargetName
general.castbarTargetSpellNameFont
general.castbarTargetSpellNameOutline
general.castbarTargetTimeFont
general.castbarTargetTimeOutline
general.castbarTextB
general.castbarTextG
general.castbarTextR
general.castbarTextUseCustom
general.classBarBgB
general.classBarBgG
general.classBarBgR
general.classPowerPreviewAnimate
general.combatStateIndicatorAnchor
general.combatStateIndicatorLayer
general.combatStateIndicatorPos
general.darkBarTone
general.darkBgBrightness
general.darkMode
general.designerHelpSeen
general.disableBlizzardUnitFrames
general.disableUnitInfoTooltips
general.editModeBgAlpha
general.editModeClampToScreen
general.editModeGridEnabled
general.editModeGridStep
general.editModeHideWhiteArrows
general.editModeSnapEnabled
general.editModeSnapMode
general.editModeSnapModeFrames
general.editModeSnapModeGrid
general.emTutorialSeen
general.flashFullH
general.flashFullPoint
general.flashFullRelPoint
general.flashFullW
general.flashFullX
general.flashFullXpx
general.flashFullY
general.flashFullYpx
general.focusCastbarTestMode
general.fontColorCustomB
general.fontColorCustomG
general.fontColorCustomR
general.gradientDirDown
general.gradientDirLeft
general.gradientDirRight
general.gradientDirUp
general.hasMovedFramesInEditMode
general.healthBarGradientColorB
general.healthBarGradientColorG
general.healthBarGradientColorR
general.healthGradientHighB
general.healthGradientHighG
general.healthGradientHighR
general.healthGradientLowB
general.healthGradientLowG
general.healthGradientLowR
general.healthGradientMidB
general.healthGradientMidG
general.healthGradientMidR
general.healthLossColorB
general.healthLossColorG
general.healthLossColorR
general.healthTextThrottleMs
general.hidePercentSymbol
general.hlAggroColorB
general.hlAggroColorG
general.hlAggroColorR
general.hlAggroSize
general.hardKillBlizzardPlayerFrame
general.hpFontSize
general.hpTextSeparator
general.hpTextSpacerEnabled
general.hpTextSpacerX
general.hpTextSpacerY
general.incomingResIndicatorAnchor
general.incomingResIndicatorLayer
general.incomingResIndicatorPos
general.leaderIconLayer
general.leaderIconOffsetX
general.leaderIconOffsetY
general.leaderIconStyle
general.levelIndicatorAnchor
general.levelIndicatorLayer
general.levelIndicatorOffsetX
general.levelIndicatorOffsetY
general.linkEditModes
general.nameFontSize
general.npcClassColorBar
general.petFrameColorB
general.petFrameColorG
general.petFrameColorR
general.playerCastbarOverrideB
general.playerCastbarOverrideG
general.playerCastbarOverrideR
general.playerCastbarSameWidthAsCDMEssential
general.playerCastbarTestMode
general.portraitBgColorA
general.portraitBgColorB
general.portraitBgColorG
general.portraitBgColorR
general.portraitBgEnabled
general.portraitBorderColorA
general.portraitAlpha
general.portraitBorderArt
general.portraitBorderColorB
general.portraitBorderColorG
general.portraitBorderColorR
general.portraitBorderDirection
general.portraitBorderStyle
general.portraitBorderThickness
general.portraitClassStyle
general.portraitDetachedPoint
general.portraitDetachedTo
general.portraitFillBorder
general.portraitHeight
general.portraitLevelOffset
general.portraitOffsetX
general.portraitOffsetY
general.portraitOverlayAlign
general.portraitPanX
general.portraitPanY
general.portraitPlacement
general.portraitShape
general.portraitEdgeSoftness
general.portraitSizeMode
general.portraitSizeOverride
general.portraitWidth
general.portraitZoom
general.powerBarGradientColorB
general.powerBarGradientColorG
general.powerBarGradientColorR
general.powerLossColorB
general.powerLossColorG
general.powerLossColorR
general.powerFontSize
general.powerTextSeparator
general.powerTextSpacerEnabled
general.powerTextSpacerX
general.powerTextSpacerY
general.powerTextThrottleMs
general.pvpIndicatorAnchor
general.pvpIndicatorLayer
general.pvpIndicatorOffsetX
general.pvpIndicatorOffsetY
general.pvpIndicatorSize
general.quickSetupClassBarOffered
general.raidGroupNameAnchor
general.raidGroupNameOffsetX
general.raidGroupNameOffsetY
general.raidGroupNameStyle
general.raidMarkerSize
general.rangeFadeAlpha
general.rangeFadeEnabled
general.rangeFadePortrait
general.restedStateIndicatorAnchor
general.restedStateIndicatorLayer
general.restedStateIndicatorIconStyle
general.restedStateIndicatorOffsetX
general.restedStateIndicatorOffsetY
general.restedStateIndicatorSize
general.restedStateIndicatorSymbol
general.roundedUnitframes
general.shortenNameFrontMaskPx
general.showBossCastTargetName
general.showCombatStateIndicator
general.showIncomingResIndicator
general.showLeaderIcon
general.showLevel
general.showPvpIndicator
general.showRaidGroupInName
general.showRaidMarker
general.showRestingIndicator
general.showTotalAbsorbAmount
general.stateIconsTestMode
general.suppressBCDMHandoffNotice
general.targetCastbarSameWidthAsCDMEssential
general.targetCastbarTestMode
general.tempMaxHealthColorB
general.tempMaxHealthColorG
general.tempMaxHealthColorR
general.unifiedBarB
general.unifiedBarG
general.unifiedBarR
general.unitDispelOwnershipVersion
general.unitPreviewGuidesEnabled
general.useBarBorder
general.useClassColors
general.useCustomFontColor
general.useModernWidgets
]=]

local reviewedGeneratedNoMenu = {}
local reviewedGeneratedNoMenuCount = 0
for key in REVIEWED_GENERATED_NO_MENU_KEYS:gmatch("[^\r\n]+") do
    assert(key ~= "", "blank generated no-menu disposition key")
    assert(not reviewedGeneratedNoMenu[key], "duplicate generated no-menu disposition key: " .. key)
    reviewedGeneratedNoMenu[key] = true
    reviewedGeneratedNoMenuCount = reviewedGeneratedNoMenuCount + 1
end

-- Exact explicit Registry controls which intentionally have no fixed Menu2
-- destination. They mutate only transient Aura workspace selection state and
-- are owned by whichever current Unit/Group Aura page is active; inventing a
-- default page would route the user to the wrong frame.
local REVIEWED_CONTEXTUAL_NO_MENU_SETTINGS = {
    ["menu.auraBlacklistPreset"] = {
        ownerContext = "auraContent",
        evidence = "MSUF_AssistantRegistry_Auras_Menu_Blacklist.lua contextualMenuState and the active Aura owner resolvers in MSUF_AssistantKnowledge.lua/MSUF_AssistantRegistry_Workflows_PendingFlows.lua",
    },
    ["menu.auraBlacklistSpell"] = {
        ownerContext = "auraContent",
        evidence = "MSUF_AssistantRegistry_Auras_Menu_Blacklist.lua contextualMenuState and the active Aura owner resolvers in MSUF_AssistantKnowledge.lua/MSUF_AssistantRegistry_Workflows_PendingFlows.lua",
    },
}
local reviewedContextualNoMenuCount = 0
for key, review in pairs(REVIEWED_CONTEXTUAL_NO_MENU_SETTINGS) do
    assert(key ~= "" and type(review) == "table", "invalid contextual no-menu disposition")
    assert(tostring(review.ownerContext or "") ~= "", "contextual no-menu owner is missing: " .. key)
    assert(tostring(review.evidence or "") ~= "", "contextual no-menu evidence is missing: " .. key)
    reviewedContextualNoMenuCount = reviewedContextualNoMenuCount + 1
end

M.categoryPolicy.runtime_metadata = {
    reason = "This exact generated scalar stores migration, preview, test-mode, edit-mode, backend, tutorial, or throttling state and has no independent visible Menu2 control.",
}
M.categoryPolicy.menu_window_geometry = {
    reason = "This exact generated scalar persists the internal Menu2 window dimensions; it is not an independent user-facing setting.",
}
M.categoryPolicy.compound_control_channel = {
    reason = "This exact generated scalar is a backing channel or shared fallback for a selector-bound compound Bars control; the runtime catalog closure owns the visible scoped operation, so the scalar is not a second independent Menu target.",
}
M.categoryPolicy.contextual_menu_state = {
    reason = "This explicit transient Menu state is owned by the currently active Aura content workspace; it has no truthful fixed Menu2 page when no Aura owner is open.",
}

local GENERATED_COMPOUND_CONTROL_CHANNELS = {
    ["general.healthBarGradientColorB"] = true,
    ["general.healthBarGradientColorG"] = true,
    ["general.healthBarGradientColorR"] = true,
    ["general.healthLossColorB"] = true,
    ["general.healthLossColorG"] = true,
    ["general.healthLossColorR"] = true,
    ["general.powerBarGradientColorB"] = true,
    ["general.powerBarGradientColorG"] = true,
    ["general.powerBarGradientColorR"] = true,
    ["general.powerLossColorB"] = true,
    ["general.powerLossColorG"] = true,
    ["general.powerLossColorR"] = true,
    ["general.powerGradientDirDown"] = true,
    ["general.powerGradientDirLeft"] = true,
    ["general.powerGradientDirRight"] = true,
    ["general.powerGradientDirUp"] = true,
}

local GENERATED_ALIAS_PREFIX_OWNERS = {
    absorbBarColor = "general.absorbBarColor",
    aggroBorderColor = "general.aggroBorderColor",
    barOutlineColor = "general.barOutlineColor",
    castbarBg = "general.castbarBackgroundColor",
    castbarBorder = "general.castbarBorderColor",
    castbarText = "general.castbarFontColor",
    classBarBg = "general.classBarBgColor",
    fontColorCustom = "general.customFontColor",
    healthGradientHigh = "general.healthGradientHigh",
    healthGradientLow = "general.healthGradientLow",
    healthGradientMid = "general.healthGradientMid",
    hlAggroColor = "general.aggroBorderColor",
    petFrameColor = "general.petFrameColor",
    playerCastbarOverride = "general.playerCastbarOverrideColor",
    portraitBgColor = "general.portraitBgColor",
    portraitBorderColor = "general.portraitBorderColor",
    tempMaxHealthColor = "general.tempMaxHealthColor",
    unifiedBar = "general.unifiedBarColor",
}

local function GeneratedAliasOwner(key)
    local prefix = tostring(key or ""):match("^general%.(.+)[RGBA]$")
    return prefix and GENERATED_ALIAS_PREFIX_OWNERS[prefix] or nil
end

local function IsGeneratedRuntimeMetadata(key)
    key = tostring(key or "")
    return key:find("Migration", 1, true) ~= nil
        or key:find("Revision", 1, true) ~= nil
        or key:find("Version", 1, true) ~= nil
        or key:find("Backend", 1, true) ~= nil
        or key:find("TestMode", 1, true) ~= nil
        or key:find("Preview", 1, true) ~= nil
        or key:find("Throttle", 1, true) ~= nil
        or key:find("Tutorial", 1, true) ~= nil
        or key:find("Seen", 1, true) ~= nil
        or key:find("hasMoved", 1, true) ~= nil
        or key:find("GraceMs", 1, true) ~= nil
        or key:match("^general%.editMode") ~= nil
        or key:match("^general%.flashFull") ~= nil
end

function M.ClassifyGeneratedNoMenuSetting(setting)
    local key = tostring(type(setting) == "table" and setting.key or setting or "")
    local contextual = REVIEWED_CONTEXTUAL_NO_MENU_SETTINGS[key]
    if contextual then
        return {
            category = "contextual_menu_state",
            ownerContext = contextual.ownerContext,
            evidence = contextual.evidence,
            policy = M.categoryPolicy.contextual_menu_state,
        }
    end
    if not reviewedGeneratedNoMenu[key] then return nil end

    local owner = GeneratedAliasOwner(key)
    if owner then
        return { category = "canonical_alias", ownerSetting = owner, policy = M.categoryPolicy.canonical_alias }
    end
    if GENERATED_COMPOUND_CONTROL_CHANNELS[key] then
        return { category = "compound_control_channel", policy = M.categoryPolicy.compound_control_channel }
    end
    if IsGeneratedRuntimeMetadata(key) then
        return { category = "runtime_metadata", policy = M.categoryPolicy.runtime_metadata }
    end
    if key == "general.msuf2WindowH" or key == "general.msuf2WindowW" then
        return { category = "menu_window_geometry", policy = M.categoryPolicy.menu_window_geometry }
    end
    return { category = "compatibility_fallback", policy = M.categoryPolicy.compatibility_fallback }
end

function M.ReviewedGeneratedNoMenuCount()
    return reviewedGeneratedNoMenuCount
end

function M.ReviewedNoMenuCount()
    return reviewedGeneratedNoMenuCount + reviewedContextualNoMenuCount
end

function M.ValidateGeneratedNoMenuSettings(settings, context)
    context = context or {}
    local report = {
        candidateCount = 0,
        reviewedCount = reviewedGeneratedNoMenuCount + reviewedContextualNoMenuCount,
        classifiedCount = 0,
        byCategory = {},
        unclassified = {},
        stale = {},
        invalidEvidence = {},
        invalidOwners = {},
    }
    local seen = {}

    for i = 1, #(settings or {}) do
        local setting = settings[i] or {}
        local key = tostring(setting.key or "")
        report.candidateCount = report.candidateCount + 1
        if key ~= "" then seen[key] = true end
        local disposition = M.ClassifyGeneratedNoMenuSetting(setting)
        if not disposition then
            report.unclassified[#report.unclassified + 1] = key
        else
            report.classifiedCount = report.classifiedCount + 1
            report.byCategory[disposition.category] = (report.byCategory[disposition.category] or 0) + 1
            local contextual = disposition.category == "contextual_menu_state"
            local validEvidence = tostring(setting.type or "") ~= ""
                and type(setting.get) == "function"
                and type(setting.set) == "function"
                and type(setting.apply) == "function"
                and ((contextual
                        and setting.generated ~= true
                        and tostring(setting.dbPath or "") == ""
                        and tostring(setting.contextualMenuState or "") == tostring(disposition.ownerContext or "")
                        and tostring(disposition.evidence or "") ~= "")
                    or (not contextual
                        and setting.generated == true
                        and tostring(setting.dbPath or "") ~= ""))
            if not validEvidence then report.invalidEvidence[#report.invalidEvidence + 1] = key end
            if disposition.ownerSetting
                and not (type(context.hasExecutableSetting) == "function"
                    and context.hasExecutableSetting(disposition.ownerSetting))
            then
                report.invalidOwners[#report.invalidOwners + 1] =
                    key .. " -> setting:" .. tostring(disposition.ownerSetting)
            end
            if disposition.ownerContext
                and tostring(setting.contextualMenuState or "") ~= tostring(disposition.ownerContext)
            then
                report.invalidOwners[#report.invalidOwners + 1] =
                    key .. " -> context:" .. tostring(disposition.ownerContext)
            end
        end
    end

    for key in pairs(reviewedGeneratedNoMenu) do
        if not seen[key] then report.stale[#report.stale + 1] = key end
    end
    for key in pairs(REVIEWED_CONTEXTUAL_NO_MENU_SETTINGS) do
        if not seen[key] then report.stale[#report.stale + 1] = key end
    end
    table.sort(report.unclassified)
    table.sort(report.stale)
    table.sort(report.invalidEvidence)
    table.sort(report.invalidOwners)
    report.pass = #report.unclassified == 0
        and #report.stale == 0
        and #report.invalidEvidence == 0
        and #report.invalidOwners == 0
        and report.classifiedCount == report.candidateCount
    return report
end


return M
