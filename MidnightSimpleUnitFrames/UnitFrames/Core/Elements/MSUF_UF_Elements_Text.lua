local _, MSUF = ...
local Text = MSUF and MSUF.UFText
local UF = Text and Text.UF
if not (Text and UF) then return end

local TextStructure = {}
TextStructure.GetEvents = Text.GetEvents
TextStructure.GetUnitlessEvents = Text.GetUnitlessEvents
TextStructure.Create = Text.Create
TextStructure.Apply = Text.Apply
TextStructure.IsEnabled = Text.IsEnabled

UF.RegisterElement("Text", TextStructure)
