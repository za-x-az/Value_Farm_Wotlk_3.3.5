-- ValueFarm addon V0.1 Beta
local ValueFarm = CreateFrame("Frame", "ValueFarmFrame", UIParent)
ValueFarm:RegisterEvent("ADDON_LOADED")
ValueFarm:RegisterEvent("CHAT_MSG_LOOT")
ValueFarm:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ValueFarm:RegisterEvent("CHAT_MSG_SKILL")
ValueFarm:RegisterEvent("CHAT_MSG_MONEY")
ValueFarm.lastProspectedOre = nil
ValueFarm.prospectingActive = false
ValueFarm.prospectQueue = {}

-- Debug
ValueFarm.debug = false
ValueFarm.debugLines = {}
ValueFarm.maxDebugLines = 200

-- Gathering detection (only track loot right after a gather cast)
ValueFarm.gatheringExpires = 0
ValueFarm.gatheringSpells = {
    ["Herb Gathering"] = true,
    ["Mining"] = true,
    ["Skinning"] = true,
}

-- Icons (real play/pause + refresh + gear)
ValueFarm.ICON_PLAY    = "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
ValueFarm.ICON_PAUSE   = "Interface\\AddOns\\ValueFarm\\PauseButton.tga"
ValueFarm.ICON_RESET   = "Interface\\AddOns\\ValueFarm\\ResetButton.tga"
ValueFarm.ICON_OPTIONS = "Interface\\Icons\\INV_Misc_Gear_01"
ValueFarm.ICON_MINIMAP = "Interface\\Icons\\Achievement_bg_tophealer_av"

-- Ignore list (Eternals and Crystallized)
ValueFarm.ignoreCreatedItems = {
    ["Eternal Earth"] = true, ["Eternal Water"] = true, ["Eternal Fire"] = true,
    ["Eternal Air"] = true, ["Eternal Shadow"] = true, ["Eternal Life"] = true,
    ["Crystallized Earth"] = true, ["Crystallized Water"] = true, ["Crystallized Fire"] = true,
    ["Crystallized Air"] = true, ["Crystallized Shadow"] = true, ["Crystallized Life"] = true,
}

-- Debug helper
function ValueFarm:Debug(msg)
    if not self.debug then return end
    local stamp = date("%H:%M:%S")
    local line = "|cff888888[" .. stamp .. "]|r " .. tostring(msg)
    table.insert(self.debugLines, line)
    if #self.debugLines > self.maxDebugLines then
        table.remove(self.debugLines, 1)
    end
    self:UpdateDebugWindow()
end

function ValueFarm:DebugF(fmt, ...)
    if self.debug then self:Debug(string.format(fmt, ...)) end
end

ValueFarm:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "ValueFarm" then
            if not ValueFarmDB then
                ValueFarmDB = {
                    lootData = {}, startTime = 0, elapsedTime = 0, running = false,
                    totalValue = 0, totalMoney = 0,
                    trashData = {count = 0, value = 0},
                    visible = true,
                    herbNodesGathered = 0, oreVeinsGathered = 0,
                    prospectData = { totalOres = 0, oreTypes = {}, gems = {} },
                    windowScale = 1.0, miniMode = false,
                    windowW = 250, windowH = 360,
                    posX = 0, posY = 0,
                    minimapAngle = nil,
                }
            else
                if not ValueFarmDB.prospectData then
                    ValueFarmDB.prospectData = { totalOres = 0, oreTypes = {}, gems = {} }
                end
                if ValueFarmDB.herbNodesGathered == nil then ValueFarmDB.herbNodesGathered = 0 end
                if ValueFarmDB.oreVeinsGathered == nil then ValueFarmDB.oreVeinsGathered = 0 end
                if ValueFarmDB.windowScale == nil then ValueFarmDB.windowScale = 1.0 end
                if ValueFarmDB.miniMode == nil then ValueFarmDB.miniMode = false end
                if ValueFarmDB.posX == nil then ValueFarmDB.posX = 0 end
                if ValueFarmDB.posY == nil then ValueFarmDB.posY = 0 end
                if ValueFarmDB.windowW == nil then ValueFarmDB.windowW = 250 end
                if ValueFarmDB.windowH == nil then ValueFarmDB.windowH = 360 end
            end
            ValueFarm:CreateUI()
            ValueFarm:CreateDebugWindow()
            ValueFarm:CreateOptionsWindow()
            ValueFarm:CreateMinimapButton()
            ValueFarm:ApplyScale()
            ValueFarm:ApplySize()
            ValueFarm:ApplyPosition()
            ValueFarm:ApplyMiniMode()
            ValueFarm:StartTracking()
            ValueFarm:HookChatMessages()
            ValueFarm:UpdateStartPauseButton()
            ValueFarm:Debug("ValueFarm V0.1 Beta loaded.")
        end
    elseif event == "CHAT_MSG_LOOT" then
        ValueFarm:Debug("Event CHAT_MSG_LOOT fired")
        ValueFarm:UpdateLootData(...)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        ValueFarm:Debug("Event UNIT_SPELLCAST_SUCCEEDED fired")
        ValueFarm:OnSpellCast(...)
    elseif event == "CHAT_MSG_SKILL" then
        ValueFarm:Debug("Event CHAT_MSG_SKILL fired")
        ValueFarm:OnSkillMessage(...)
    elseif event == "CHAT_MSG_MONEY" then
        ValueFarm:Debug("Event CHAT_MSG_MONEY fired")
        ValueFarm:UpdateLootData(...)
    end
end)

function ValueFarm:CreateUI()
    self.frame = CreateFrame("Frame", "ValueFarmMainFrame", UIParent)
    self.frame:SetSize(ValueFarmDB.windowW or 250, ValueFarmDB.windowH or 360)
    self.frame:SetPoint("CENTER", UIParent, "CENTER", ValueFarmDB.posX or 0, ValueFarmDB.posY or 0)
    self.frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 6, right = 6, top = 6, bottom = 6 }
    })
    self.frame:SetBackdropColor(0, 0, 0, 0.80)
    self.frame:SetBackdropBorderColor(1, 1, 1, 1)
    self.frame:SetMovable(true)
    self.frame:EnableMouse(true)
    self.frame:RegisterForDrag("LeftButton")
    self.frame:SetScript("OnDragStart", self.frame.StartMoving)
    self.frame:SetScript("OnDragStop", function()
        self.frame:StopMovingOrSizing()
        local cx, cy = self.frame:GetCenter()
        local px, py = UIParent:GetCenter()
        ValueFarmDB.posX = cx - px
        ValueFarmDB.posY = cy - py
        ValueFarm:DebugF("Window moved to X=%.1f Y=%.1f", ValueFarmDB.posX, ValueFarmDB.posY)
    end)

    self.title = self.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.title:SetPoint("TOP", self.frame, "TOP", 0, -8)
    self.title:SetText("|cffffd700Value Farm V0.1 Beta|r")

    -- Button Frame
    self.buttonFrame = CreateFrame("Frame", "ValueFarmButtonFrame", self.frame)
    self.buttonFrame:SetSize(240, 32)
    self.buttonFrame:SetPoint("TOP", self.title, "BOTTOM", 0, -4)

    -- Play/Pause icon button
    self.startPauseButton = CreateFrame("Button", nil, self.buttonFrame)
    self.startPauseButton:SetSize(28, 28)
    self.startPauseButton:SetPoint("LEFT", self.buttonFrame, "LEFT", 40, 0)
    self.startPauseButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    self.startPauseButton:SetScript("OnClick", function()
        ValueFarmDB.running = not ValueFarmDB.running
        if ValueFarmDB.running then ValueFarmDB.startTime = GetTime() end
        ValueFarm:UpdateStartPauseButton()
        ValueFarm:DisplayData()
        ValueFarm:Debug("Tracking toggled: " .. (ValueFarmDB.running and "ON" or "OFF"))
    end)
    self.startPauseButton:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText(ValueFarmDB.running and "Pause" or "Start")
        GameTooltip:Show()
    end)
    self.startPauseButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Reset icon button
    self.resetButton = CreateFrame("Button", nil, self.buttonFrame)
    self.resetButton:SetSize(28, 28)
    self.resetButton:SetPoint("CENTER", self.buttonFrame, "CENTER", 0, 0)
    self.resetButton:SetNormalTexture(ValueFarm.ICON_RESET)
    self.resetButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    self.resetButton:SetScript("OnClick", function()
        ValueFarmDB.lootData = {}
        ValueFarmDB.trashData = {count = 0, value = 0}
        ValueFarmDB.startTime = 0
        ValueFarmDB.elapsedTime = 0
        ValueFarmDB.running = false
        ValueFarmDB.totalValue = 0
        ValueFarmDB.totalMoney = 0
        ValueFarmDB.herbNodesGathered = 0
        ValueFarmDB.oreVeinsGathered = 0
        ValueFarmDB.prospectData = { totalOres = 0, oreTypes = {}, gems = {} }
        ValueFarm:ClearTextLines()
        ValueFarm:DisplayData()
        ValueFarm:UpdateHerbCount()
        ValueFarm:UpdateProspectCount()
        ValueFarm:UpdateStartPauseButton()
        ValueFarm:Debug("Data reset.")
        print("Loot tracking reset.")
    end)
    self.resetButton:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Reset")
        GameTooltip:Show()
    end)
    self.resetButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Options icon button (gear)
    self.optionsButton = CreateFrame("Button", nil, self.buttonFrame)
    self.optionsButton:SetSize(28, 28)
    self.optionsButton:SetPoint("RIGHT", self.buttonFrame, "RIGHT", -40, 0)
    self.optionsButton:SetNormalTexture(ValueFarm.ICON_OPTIONS)
    self.optionsButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    self.optionsButton:SetScript("OnClick", function()
        if ValueFarm.optionsFrame:IsShown() then
            ValueFarm.optionsFrame:Hide()
        else
            ValueFarm.optionsFrame:Show()
        end
    end)
    self.optionsButton:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_TOP")
        GameTooltip:SetText("Options")
        GameTooltip:Show()
    end)
    self.optionsButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Content Frame (stretches to fill window)
    self.textFrame = CreateFrame("Frame", nil, self.frame)
    self.textFrame.textLines = {}
    for i = 1, 20 do
        local textLineName = self.textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        textLineName:SetPoint("TOPLEFT", 8, -2 - (i - 1) * 13)
        textLineName:SetJustifyH("LEFT")
        textLineName:SetWordWrap(false)

        local textLineValue = self.textFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        textLineValue:SetPoint("TOPRIGHT", -8, -2 - (i - 1) * 13)
        textLineValue:SetWidth(70)
        textLineValue:SetJustifyH("RIGHT")
        textLineValue:SetWordWrap(false)

        self.textFrame.textLines[i] = {name = textLineName, value = textLineValue}
    end

    -- Herb / Ore Counter Frame (popup)
    self.herbFrame = CreateFrame("Frame", "HerbCountFrame", self.frame)
    self.herbFrame:SetSize(220, 70)
    self.herbFrame:SetPoint("TOP", self.textFrame, "BOTTOM", 0, -4)
    self.herbFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    self.herbFrame:EnableMouse(true)
    self.herbFrame:SetMovable(true)
    self.herbFrame:RegisterForDrag("LeftButton")
    self.herbFrame:SetScript("OnDragStart", self.herbFrame.StartMoving)
    self.herbFrame:SetScript("OnDragStop", self.herbFrame.StopMovingOrSizing)
    self.herbFrame:Hide()

    self.herbCountText = self.herbFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.herbCountText:SetPoint("TOP", self.herbFrame, "TOP", 0, -8)
    self.herbCountText:SetText("Herb nodes: " .. ValueFarmDB.herbNodesGathered)

    self.oreCountText = self.herbFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    self.oreCountText:SetPoint("TOP", self.herbCountText, "BOTTOM", 0, -2)
    self.oreCountText:SetText("Ore veins: " .. ValueFarmDB.oreVeinsGathered)

    local resetHerbButton = CreateFrame("Button", nil, self.herbFrame, "UIPanelButtonTemplate")
    resetHerbButton:SetSize(60, 24)
    resetHerbButton:SetPoint("BOTTOMLEFT", self.herbFrame, "BOTTOMLEFT", 10, 8)
    resetHerbButton:SetText("Reset")
    resetHerbButton:SetScript("OnClick", function()
        ValueFarmDB.herbNodesGathered = 0
        ValueFarmDB.oreVeinsGathered = 0
        self.herbCountText:SetText("Herb nodes: " .. ValueFarmDB.herbNodesGathered)
        self.oreCountText:SetText("Ore veins: " .. ValueFarmDB.oreVeinsGathered)
    end)

    local closeHerbButton = CreateFrame("Button", nil, self.herbFrame, "UIPanelButtonTemplate")
    closeHerbButton:SetSize(60, 24)
    closeHerbButton:SetPoint("BOTTOMRIGHT", self.herbFrame, "BOTTOMRIGHT", -10, 8)
    closeHerbButton:SetText("Close")
    closeHerbButton:SetScript("OnClick", function() self.herbFrame:Hide() end)

    -- Prospecting Frame (popup)
    self.prospectFrame = CreateFrame("Frame", "ProspectCountFrame", UIParent)
    self.prospectFrame:SetSize(330, 280)
    self.prospectFrame:SetPoint("CENTER", UIParent, "CENTER", 300, 0)
    self.prospectFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    self.prospectFrame:SetBackdropColor(0, 0, 0, 0.85)
    self.prospectFrame:SetBackdropBorderColor(1, 0.8, 0, 1)
    self.prospectFrame:EnableMouse(true)
    self.prospectFrame:SetMovable(true)
    self.prospectFrame:RegisterForDrag("LeftButton")
    self.prospectFrame:SetScript("OnDragStart", self.prospectFrame.StartMoving)
    self.prospectFrame:SetScript("OnDragStop", self.prospectFrame.StopMovingOrSizing)
    self.prospectFrame:Hide()

    local prospectTitle = self.prospectFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    prospectTitle:SetPoint("TOP", self.prospectFrame, "TOP", 0, -12)
    prospectTitle:SetText("|cffffd700Prospecting Tracker|r")

    self.prospectCountText = self.prospectFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    self.prospectCountText:SetPoint("TOP", prospectTitle, "BOTTOM", 0, -8)
    self.prospectCountText:SetText("Total ores prospected: 0")

    self.prospectContent = CreateFrame("Frame", nil, self.prospectFrame)
    self.prospectContent:SetSize(310, 170)
    self.prospectContent:SetPoint("TOP", self.prospectCountText, "BOTTOM", 0, -8)
    self.prospectContent.textLines = {}
    for i = 1, 12 do
        local textLine = self.prospectContent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        textLine:SetPoint("TOPLEFT", 10, -4 - (i - 1) * 13)
        textLine:SetWidth(290)
        textLine:SetJustifyH("LEFT")
        textLine:SetWordWrap(false)
        self.prospectContent.textLines[i] = textLine
    end

    local resetProspectButton = CreateFrame("Button", nil, self.prospectFrame, "UIPanelButtonTemplate")
    resetProspectButton:SetSize(60, 24)
    resetProspectButton:SetPoint("BOTTOMLEFT", self.prospectFrame, "BOTTOMLEFT", 10, 10)
    resetProspectButton:SetText("Reset")
    resetProspectButton:SetScript("OnClick", function()
        ValueFarmDB.prospectData = { totalOres = 0, oreTypes = {}, gems = {} }
        ValueFarm:UpdateProspectCount()
        print("Prospecting data reset.")
    end)

    local closeProspectButton = CreateFrame("Button", nil, self.prospectFrame, "UIPanelButtonTemplate")
    closeProspectButton:SetSize(60, 24)
    closeProspectButton:SetPoint("BOTTOMRIGHT", self.prospectFrame, "BOTTOMRIGHT", -10, 10)
    closeProspectButton:SetText("Close")
    closeProspectButton:SetScript("OnClick", function() self.prospectFrame:Hide() end)

    self:UpdateLayout()
end

-- Layout: stretch text frame + set line widths based on current window size
function ValueFarm:UpdateLayout()
    if not self.frame or not self.textFrame then return end
    self.textFrame:ClearAllPoints()
    self.textFrame:SetPoint("TOPLEFT", self.buttonFrame, "BOTTOMLEFT", 0, -4)
    self.textFrame:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -6, 6)
    local tfw = self.textFrame:GetWidth()
    for _, tl in ipairs(self.textFrame.textLines) do
        tl.name:SetWidth(math.max(60, tfw - 80))
    end
end

-- Debug window
function ValueFarm:CreateDebugWindow()
    self.debugFrame = CreateFrame("Frame", "ValueFarmDebugFrame", UIParent)
    self.debugFrame:SetSize(420, 260)
    self.debugFrame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 20, 20)
    self.debugFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    self.debugFrame:SetBackdropColor(0, 0, 0, 0.9)
    self.debugFrame:SetBackdropBorderColor(0, 0.8, 1, 1)
    self.debugFrame:SetMovable(true)
    self.debugFrame:EnableMouse(true)
    self.debugFrame:RegisterForDrag("LeftButton")
    self.debugFrame:SetScript("OnDragStart", self.debugFrame.StartMoving)
    self.debugFrame:SetScript("OnDragStop", self.debugFrame.StopMovingOrSizing)
    self.debugFrame:Hide()

    local title = self.debugFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", self.debugFrame, "TOPLEFT", 8, -6)
    title:SetText("|cff00ccffValueFarm Debug|r")

    local clearButton = CreateFrame("Button", nil, self.debugFrame, "UIPanelButtonTemplate")
    clearButton:SetSize(60, 20)
    clearButton:SetPoint("TOPRIGHT", self.debugFrame, "TOPRIGHT", -6, -4)
    clearButton:SetText("Clear")
    clearButton:SetScript("OnClick", function()
        ValueFarm.debugLines = {}
        ValueFarm:UpdateDebugWindow()
    end)

    local closeButton = CreateFrame("Button", nil, self.debugFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(60, 20)
    closeButton:SetPoint("TOPRIGHT", clearButton, "TOPLEFT", -4, 0)
    closeButton:SetText("Close")
    closeButton:SetScript("OnClick", function()
        ValueFarm.debugFrame:Hide()
        ValueFarm.debug = false
        print("ValueFarm debug turned OFF.")
    end)

    local scroll = CreateFrame("ScrollFrame", "ValueFarmDebugScroll", self.debugFrame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", self.debugFrame, "TOPLEFT", 8, -26)
    scroll:SetPoint("BOTTOMRIGHT", self.debugFrame, "BOTTOMRIGHT", -28, 8)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(380, 1)
    content.textLines = {}
    for i = 1, self.maxDebugLines do
        local line = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        line:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -((i - 1) * 12))
        line:SetWidth(380)
        line:SetJustifyH("LEFT")
        line:SetWordWrap(false)
        content.textLines[i] = line
    end
    scroll:SetScrollChild(content)
    self.debugScroll = scroll
    self.debugContent = content
end

function ValueFarm:UpdateDebugWindow()
    if not self.debugContent then return end
    local total = #self.debugLines
    local showCount = math.min(total, self.maxDebugLines)
    for i = 1, self.maxDebugLines do
        if i <= showCount then
            self.debugContent.textLines[i]:SetText(self.debugLines[total - showCount + i])
            self.debugContent.textLines[i]:Show()
        else
            self.debugContent.textLines[i]:SetText("")
            self.debugContent.textLines[i]:Hide()
        end
    end
    self.debugContent:SetHeight(math.max(1, showCount * 12))
    if self.debugScroll then
        local maxScroll = self.debugScroll:GetVerticalScrollRange()
        self.debugScroll:SetVerticalScroll(maxScroll)
    end
end

-- Options window: Scale + Width/Height (RESIZE)
function ValueFarm:CreateOptionsWindow()
    self.optionsFrame = CreateFrame("Frame", "ValueFarmOptionsFrame", UIParent)
    self.optionsFrame:SetSize(260, 260)
    self.optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 200, 100)
    self.optionsFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    self.optionsFrame:SetBackdropColor(0, 0, 0, 0.85)
    self.optionsFrame:SetBackdropBorderColor(1, 0.8, 0, 1)
    self.optionsFrame:SetMovable(true)
    self.optionsFrame:EnableMouse(true)
    self.optionsFrame:RegisterForDrag("LeftButton")
    self.optionsFrame:SetScript("OnDragStart", self.optionsFrame.StartMoving)
    self.optionsFrame:SetScript("OnDragStop", self.optionsFrame.StopMovingOrSizing)
    self.optionsFrame:Hide()

    local title = self.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", self.optionsFrame, "TOP", 0, -10)
    title:SetText("|cffffd700ValueFarm Options|r")

    -- Mini mode checkbox
    local miniLabel = self.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    miniLabel:SetPoint("TOPLEFT", self.optionsFrame, "TOPLEFT", 16, -38)
    miniLabel:SetText("Mini Mode")

    local miniCheck = CreateFrame("CheckButton", nil, self.optionsFrame, "UICheckButtonTemplate")
    miniCheck:SetPoint("LEFT", miniLabel, "RIGHT", 8, 0)
    miniCheck:SetChecked(ValueFarmDB.miniMode)
    miniCheck:SetScript("OnClick", function()
        ValueFarmDB.miniMode = miniCheck:GetChecked()
        ValueFarm:ApplyMiniMode()
        ValueFarm:DisplayData()
    end)

    -- Scale slider
    local scaleLabel = self.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    scaleLabel:SetPoint("TOPLEFT", self.optionsFrame, "TOPLEFT", 16, -70)
    scaleLabel:SetText("Scale")

    self.scaleSlider = CreateFrame("Slider", "ValueFarmScaleSlider", self.optionsFrame, "OptionsSliderTemplate")
    self.scaleSlider:SetPoint("TOPLEFT", scaleLabel, "BOTTOMLEFT", 0, -4)
    self.scaleSlider:SetSize(220, 16)
    self.scaleSlider:SetMinMaxValues(0.5, 2.0)
    self.scaleSlider:SetValueStep(0.05)
    self.scaleSlider:SetValue(ValueFarmDB.windowScale)
    _G["ValueFarmScaleSliderText"]:SetText(string.format("%.2f", ValueFarmDB.windowScale))
    _G["ValueFarmScaleSliderLow"]:SetText("0.5")
    _G["ValueFarmScaleSliderHigh"]:SetText("2.0")
    self.scaleSlider:SetScript("OnValueChanged", function(_, value)
        if ValueFarm.suppressSlider then return end
        ValueFarmDB.windowScale = value
        _G["ValueFarmScaleSliderText"]:SetText(string.format("%.2f", value))
        ValueFarm:ApplyScale()
    end)

    -- Width slider (RESIZE)
    local wLabel = self.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    wLabel:SetPoint("TOPLEFT", self.optionsFrame, "TOPLEFT", 16, -120)
    wLabel:SetText("Width")

    self.widthSlider = CreateFrame("Slider", "ValueFarmWidthSlider", self.optionsFrame, "OptionsSliderTemplate")
    self.widthSlider:SetPoint("TOPLEFT", wLabel, "BOTTOMLEFT", 0, -4)
    self.widthSlider:SetSize(220, 16)
    self.widthSlider:SetMinMaxValues(260, 400)
    self.widthSlider:SetValueStep(10)
    self.widthSlider:SetValue(ValueFarmDB.windowW)
    _G["ValueFarmWidthSliderText"]:SetText(tostring(ValueFarmDB.windowW))
    _G["ValueFarmWidthSliderLow"]:SetText("260")
    _G["ValueFarmWidthSliderHigh"]:SetText("400")
    self.widthSlider:SetScript("OnValueChanged", function(_, value)
        if ValueFarm.suppressSlider then return end
        ValueFarmDB.windowW = math.floor(value + 0.5)
        _G["ValueFarmWidthSliderText"]:SetText(tostring(ValueFarmDB.windowW))
        ValueFarm:ApplySize()
    end)

    -- Height slider (RESIZE)
    local hLabel = self.optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hLabel:SetPoint("TOPLEFT", self.optionsFrame, "TOPLEFT", 16, -170)
    hLabel:SetText("Height")

    self.heightSlider = CreateFrame("Slider", "ValueFarmHeightSlider", self.optionsFrame, "OptionsSliderTemplate")
    self.heightSlider:SetPoint("TOPLEFT", hLabel, "BOTTOMLEFT", 0, -4)
    self.heightSlider:SetSize(220, 16)
    self.heightSlider:SetMinMaxValues(200, 500)
    self.heightSlider:SetValueStep(10)
    self.heightSlider:SetValue(ValueFarmDB.windowH)
    _G["ValueFarmHeightSliderText"]:SetText(tostring(ValueFarmDB.windowH))
    _G["ValueFarmHeightSliderLow"]:SetText("200")
    _G["ValueFarmHeightSliderHigh"]:SetText("500")
    self.heightSlider:SetScript("OnValueChanged", function(_, value)
        if ValueFarm.suppressSlider then return end
        ValueFarmDB.windowH = math.floor(value + 0.5)
        _G["ValueFarmHeightSliderText"]:SetText(tostring(ValueFarmDB.windowH))
        ValueFarm:ApplySize()
    end)

    -- Buttons
    local resetScaleButton = CreateFrame("Button", nil, self.optionsFrame, "UIPanelButtonTemplate")
    resetScaleButton:SetSize(100, 22)
    resetScaleButton:SetPoint("BOTTOMLEFT", self.optionsFrame, "BOTTOMLEFT", 14, 12)
    resetScaleButton:SetText("Reset Layout")
    resetScaleButton:SetScript("OnClick", function()
        ValueFarmDB.windowScale = 1.0
        ValueFarmDB.miniMode = false
        ValueFarmDB.windowW = 250
        ValueFarmDB.windowH = 360
        miniCheck:SetChecked(false)
        ValueFarm:UpdateOptionsSliders()
        ValueFarm:ApplyScale()
        ValueFarm:ApplySize()
        ValueFarm:ApplyMiniMode()
        ValueFarm:DisplayData()
    end)

    local closeOptionsButton = CreateFrame("Button", nil, self.optionsFrame, "UIPanelButtonTemplate")
    closeOptionsButton:SetSize(70, 22)
    closeOptionsButton:SetPoint("BOTTOMRIGHT", self.optionsFrame, "BOTTOMRIGHT", -14, 12)
    closeOptionsButton:SetText("Close")
    closeOptionsButton:SetScript("OnClick", function() self.optionsFrame:Hide() end)
end

function ValueFarm:UpdateOptionsSliders()
    if not self.optionsFrame then return end
    self.suppressSlider = true
    self.scaleSlider:SetValue(ValueFarmDB.windowScale or 1.0)
    self.widthSlider:SetValue(ValueFarmDB.windowW or 250)
    self.heightSlider:SetValue(ValueFarmDB.windowH or 360)
    _G["ValueFarmScaleSliderText"]:SetText(string.format("%.2f", ValueFarmDB.windowScale or 1.0))
    _G["ValueFarmWidthSliderText"]:SetText(tostring(ValueFarmDB.windowW or 250))
    _G["ValueFarmHeightSliderText"]:SetText(tostring(ValueFarmDB.windowH or 360))
    self.suppressSlider = false
end

function ValueFarm:ApplyScale()
    if self.frame and ValueFarmDB.windowScale then
        self.frame:SetScale(ValueFarmDB.windowScale)
    end
end

function ValueFarm:ApplySize()
    if not self.frame then return end
    self.frame:SetSize(ValueFarmDB.windowW or 250, ValueFarmDB.windowH or 360)
    self:UpdateLayout()
    self:DisplayData()
end

function ValueFarm:ApplyPosition()
    if not self.frame then return end
    self.frame:ClearAllPoints()
    self.frame:SetPoint("CENTER", UIParent, "CENTER", ValueFarmDB.posX or 0, ValueFarmDB.posY or 0)
end

function ValueFarm:ApplyMiniMode()
    if not self.frame then return end
    if ValueFarmDB.miniMode then
        -- Slim mini HUD with items + icons
        self.frame:SetSize(190, 200)
        self.title:SetText("|cffffd700VF|r")
        self.title:Show()
        self.buttonFrame:ClearAllPoints()
        self.buttonFrame:SetPoint("TOP", self.title, "BOTTOM", 0, -2)
        self.buttonFrame:SetSize(170, 24)
        self.startPauseButton:SetSize(22, 22)
        self.startPauseButton:SetPoint("LEFT", self.buttonFrame, "LEFT", 30, 0)
        self.resetButton:SetSize(22, 22)
        self.resetButton:SetPoint("CENTER", self.buttonFrame, "CENTER", 0, 0)
        self.optionsButton:SetSize(22, 22)
        self.optionsButton:SetPoint("RIGHT", self.buttonFrame, "RIGHT", -30, 0)
        self.textFrame:Show()
        self:UpdateLayout()
        self:DisplayData()
    else
        self.frame:SetSize(ValueFarmDB.windowW or 250, ValueFarmDB.windowH or 360)
        self.title:SetText("|cffffd700Value Farm V0.1 Beta|r")
        self.title:Show()
        self.buttonFrame:ClearAllPoints()
        self.buttonFrame:SetPoint("TOP", self.title, "BOTTOM", 0, -4)
        self.buttonFrame:SetSize(240, 32)
        self.startPauseButton:SetSize(28, 28)
        self.startPauseButton:SetPoint("LEFT", self.buttonFrame, "LEFT", 40, 0)
        self.resetButton:SetSize(28, 28)
        self.resetButton:SetPoint("CENTER", self.buttonFrame, "CENTER", 0, 0)
        self.optionsButton:SetSize(28, 28)
        self.optionsButton:SetPoint("RIGHT", self.buttonFrame, "RIGHT", -40, 0)
        self.textFrame:Show()
        self:UpdateLayout()
        self:DisplayData()
    end
end

function ValueFarm:UpdateStartPauseButton()
    if not self.startPauseButton then return end
    if ValueFarmDB.running then
        self.startPauseButton:SetNormalTexture(ValueFarm.ICON_PAUSE)
    else
        self.startPauseButton:SetNormalTexture(ValueFarm.ICON_PLAY)
    end
end

-- Minimap button
function ValueFarm:CreateMinimapButton()
    local btn = CreateFrame("Button", "ValueFarmMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetMovable(true)
    btn:SetClampedToScreen(true)
    btn:RegisterForClicks("AnyUp")
    btn:RegisterForDrag("LeftButton")
    btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", btn, "CENTER", 0, 0)
    icon:SetTexture(ValueFarm.ICON_MINIMAP)
    btn.icon = icon

    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT", btn, "TOPLEFT", -11, 11)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    local angle = ValueFarmDB.minimapAngle or 0.785
    local x = math.cos(angle) * 80
    local y = math.sin(angle) * 80
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", Minimap, "CENTER", x, y)

    btn:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local a = math.atan2(cy - my, cx - mx)
            s:ClearAllPoints()
            s:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * 80, math.sin(a) * 80)
            ValueFarmDB.minimapAngle = a
        end)
    end)
    btn:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)

    btn:SetScript("OnClick", function(_, button)
        if button == "LeftButton" then
            ValueFarmDB.visible = not ValueFarmDB.visible
            ValueFarm:DisplayData()
            ValueFarm:Debug("Window visibility toggled: " .. (ValueFarmDB.visible and "ON" or "OFF"))
        elseif button == "RightButton" then
            if IsShiftKeyDown() then
                if ValueFarm.optionsFrame:IsShown() then
                    ValueFarm.optionsFrame:Hide()
                else
                    ValueFarm.optionsFrame:Show()
                end
            else
                ValueFarmDB.miniMode = not ValueFarmDB.miniMode
                ValueFarm:ApplyMiniMode()
                ValueFarm:Debug("Mini mode toggled: " .. (ValueFarmDB.miniMode and "ON" or "OFF"))
            end
        end
    end)

    btn:SetScript("OnEnter", function(s)
        GameTooltip:SetOwner(s, "ANCHOR_LEFT")
        GameTooltip:SetText("Value Farm V0.1 Beta")
        GameTooltip:AddLine("Left Click: Hide / Show window", 1, 1, 1)
        GameTooltip:AddLine("Right Click: Toggle mini mode", 1, 1, 1)
        GameTooltip:AddLine("Shift + Right Click: Options", 1, 1, 1)
        GameTooltip:AddLine("Drag: Move button", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function ValueFarm:StartTracking()
    self.timer = self:CreateTimer()
    self.updateTime = 0
    self.timer:SetScript("OnUpdate", function(_, elapsed)
        self.updateTime = self.updateTime + elapsed
        if ValueFarmDB.running then
            ValueFarmDB.elapsedTime = ValueFarmDB.elapsedTime + elapsed
            if self.updateTime >= 1 then
                self.updateTime = 0
                ValueFarm:DisplayData()
            end
        end
    end)
end

function ValueFarm:CreateTimer()
    local timer = CreateFrame("Frame")
    timer:Show()
    return timer
end

function ValueFarm:HookChatMessages()
    local orig_AddMessage = ChatFrame1.AddMessage
    ChatFrame1.AddMessage = function(frame, text, ...)
        if text and string.find(text, "You create") then
            ValueFarm:Debug("Chat hook saw 'You create': " .. tostring(text))
            local itemLink = string.match(text, "(|c%x+|H.+|h%[.+%]|h|r)")
            if itemLink then
                local itemName = string.match(itemLink, "%[(.+)%]")
                if itemName and ValueFarm.ignoreCreatedItems[itemName] then
                    ValueFarm:Debug("Ignored created item: " .. itemName)
                    return orig_AddMessage(frame, text, ...)
                end
            end
        end

        if text and ValueFarm.prospectingActive then
            if string.find(text, "prospects into") then
                ValueFarm:Debug("Chat hook saw 'prospects into': " .. tostring(text))
                local oreLink = string.match(text, "Found that (|c%x+|H.+|h%[.+%]|h|r)")
                if oreLink then
                    local oreName = string.match(oreLink, "%[(.+)%]")
                    if oreName then
                        if not ValueFarmDB.prospectData.oreTypes[oreName] then
                            ValueFarmDB.prospectData.oreTypes[oreName] = 0
                        end
                        ValueFarmDB.prospectData.oreTypes[oreName] = ValueFarmDB.prospectData.oreTypes[oreName] + 5
                        ValueFarm:UpdateProspectCount()
                    end
                end
            end

            if string.find(text, "You receive") then
                ValueFarm:Debug("Chat hook saw 'You receive': " .. tostring(text))
                local itemLink = string.match(text, "(|c%x+|H.+|h%[.+%]|h|r)")
                if itemLink then
                    local count = tonumber(string.match(text, "x(%d+)")) or 1
                    local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
                    if itemID then
                        local itemName, _, itemRarity = GetItemInfo(itemID)
                        if itemName then
                            ValueFarm:ProcessProspectGem(itemName, itemRarity, count, itemID)
                        else
                            C_Timer.After(0.5, function()
                                local delayedName, _, delayedRarity = GetItemInfo(itemID)
                                if delayedName then
                                    ValueFarm:ProcessProspectGem(delayedName, delayedRarity, count, itemID)
                                end
                            end)
                        end
                    end
                end
            end
        end

        return orig_AddMessage(frame, text, ...)
    end
end

function ValueFarm:OnSkillMessage(message)
    ValueFarm:Debug("OnSkillMessage: " .. tostring(message))
end

function ValueFarm:UpdateLootData(lootMessage)
    if not ValueFarmDB.running then
        ValueFarm:Debug("UpdateLootData ignored (tracking paused)")
        return
    end
    ValueFarm:Debug("UpdateLootData raw: " .. tostring(lootMessage))

    local gold = tonumber(string.match(lootMessage, "(%d+) Gold")) or 0
    local silver = tonumber(string.match(lootMessage, "(%d+) Silver")) or 0
    local copper = tonumber(string.match(lootMessage, "(%d+) Copper")) or 0
    local totalCopper = copper + (silver * 100) + (gold * 10000)

    if totalCopper > 0 then
        ValueFarm:DebugF("Money looted: %dg %ds %dc (total %dc)", gold, silver, copper, totalCopper)
        ValueFarmDB.totalMoney = ValueFarmDB.totalMoney + totalCopper
        ValueFarm:DisplayData()
        return
    end

    local inWindow = GetTime() <= (self.gatheringExpires or 0)
    if not inWindow then
        ValueFarm:Debug("Item loot ignored (outside gathering window)")
        return
    end
    ValueFarm:Debug("Inside gathering window; item will be tracked")

    local itemLink = string.match(lootMessage, "(|c%x+|H.+|h%[.+%]|h|r)")
    if not itemLink then
        ValueFarm:Debug("No item link found in message")
        return
    end

    local count = tonumber(string.match(lootMessage, "x(%d+)%.?%s*$"))
        or tonumber(string.match(lootMessage, "x(%d+)"))
        or 1

    local itemID = tonumber(string.match(itemLink, "item:(%d+)"))
    if not itemID then
        ValueFarm:Debug("Could not extract itemID from link")
        return
    end

    ValueFarm:DebugF("Link=%s | itemID=%d | count=%d", itemLink, itemID, count)

    local itemName, _, itemRarity = GetItemInfo(itemID)
    if itemName then
        ValueFarm:DebugF("Cached item: %s (rarity %d)", itemName, itemRarity)
        self:ProcessLootItem(itemName, itemRarity, count)
    else
        ValueFarm:DebugF("Item %d not cached; queuing tooltip + delayed lookup", itemID)
        local tooltip = CreateFrame("GameTooltip", "ValueFarmTooltip", nil, "GameTooltipTemplate")
        tooltip:SetOwner(UIParent, "ANCHOR_NONE")
        tooltip:SetHyperlink(itemLink)
        tooltip:Hide()
        C_Timer.After(0.5, function()
            local delayedName, _, delayedRarity = GetItemInfo(itemID)
            if delayedName then
                ValueFarm:DebugF("Delayed item resolved: %s (rarity %d)", delayedName, delayedRarity)
                ValueFarm:ProcessLootItem(delayedName, delayedRarity, count)
            else
                ValueFarm:DebugF("Delayed item %d still not cached; gave up", itemID)
            end
        end)
    end
end

function ValueFarm:ProcessProspectGem(itemName, itemRarity, count, itemID)
    ValueFarm:DebugF("Prospect gem: %s x%d (rarity %d)", itemName, count, itemRarity)
    if not ValueFarmDB.prospectData.gems[itemName] then
        ValueFarmDB.prospectData.gems[itemName] = {count = 0, rarity = itemRarity}
    end
    ValueFarmDB.prospectData.gems[itemName].count = ValueFarmDB.prospectData.gems[itemName].count + count
    self:UpdateProspectCount()
end

function ValueFarm:ProcessLootItem(itemName, itemRarity, count)
    ValueFarm:DebugF("ProcessLootItem: %s x%d (rarity %d)", itemName, count, itemRarity)
    if itemRarity == 0 then
        ValueFarmDB.trashData.count = ValueFarmDB.trashData.count + count
    else
        if not ValueFarmDB.lootData[itemName] then
            ValueFarmDB.lootData[itemName] = {count = 0, rarity = itemRarity}
        end
        ValueFarmDB.lootData[itemName].count = ValueFarmDB.lootData[itemName].count + count
    end
    ValueFarm:DisplayData()
end

function ValueFarm:ClearTextLines()
    for _, textLine in ipairs(self.textFrame.textLines) do
        textLine.name:SetText("")
        textLine.value:SetText("")
    end
end

function ValueFarm:DisplayData()
    if ValueFarmDB.visible then
        self.frame:Show()
    else
        self.frame:Hide()
        return
    end

    local mini = ValueFarmDB.miniMode
    local maxItems = mini and 8 or 16

    local lines = {
        "|cffffff00Time:|r |cffffffff" .. ValueFarm:FormatTime(ValueFarmDB.elapsedTime) .. "|r",
        "|cffffff00Herbs:|r |cffffffff" .. ValueFarmDB.herbNodesGathered .. "|r  |cffffff00Ores:|r |cffffffff" .. ValueFarmDB.oreVeinsGathered .. "|r",
        "|cffffff00Items:|r"
    }

    for i, line in ipairs(lines) do
        if self.textFrame.textLines[i] then
            self.textFrame.textLines[i].name:SetText(line)
            self.textFrame.textLines[i].value:SetText("")
        end
    end

    local sortedItems = {}
    for itemName, data in pairs(ValueFarmDB.lootData) do
        table.insert(sortedItems, {name = itemName, count = data.count, rarity = data.rarity})
    end
    table.sort(sortedItems, function(a, b) return a.count > b.count end)

    local itemCount = 0
    for _, itemData in ipairs(sortedItems) do
        if itemCount >= maxItems then break end
        itemCount = itemCount + 1
        local itemColor = select(4, GetItemQualityColor(itemData.rarity))
        local displayName = itemData.name .. " x" .. itemData.count
        if self.textFrame.textLines[itemCount + #lines] then
            self.textFrame.textLines[itemCount + #lines].name:SetText(itemColor .. displayName)
            self.textFrame.textLines[itemCount + #lines].value:SetText("")
        end
    end

    if ValueFarmDB.trashData.count > 0 and itemCount < maxItems then
        itemCount = itemCount + 1
        local displayName = "Trash x" .. ValueFarmDB.trashData.count
        if self.textFrame.textLines[itemCount + #lines] then
            self.textFrame.textLines[itemCount + #lines].name:SetText("|cff9d9d9d" .. displayName)
            self.textFrame.textLines[itemCount + #lines].value:SetText("")
        end
    end

    for i = itemCount + #lines + 1, 20 do
        if self.textFrame.textLines[i] then
            self.textFrame.textLines[i].name:SetText("")
            self.textFrame.textLines[i].value:SetText("")
        end
    end
end

function ValueFarm:UpdateProspectCount()
    if not self.prospectFrame then return end
    local totalOres = ValueFarmDB.prospectData.totalOres
    self.prospectCountText:SetText("Total ores prospected: " .. totalOres)

    for _, textLine in ipairs(self.prospectContent.textLines) do
        textLine:SetText("")
    end

    local lineIndex = 1
    if next(ValueFarmDB.prospectData.oreTypes) then
        self.prospectContent.textLines[lineIndex]:SetText("|cffffff00Ore Types:|r")
        lineIndex = lineIndex + 1
        local sortedOres = {}
        for oreName, count in pairs(ValueFarmDB.prospectData.oreTypes) do
            table.insert(sortedOres, {name = oreName, count = count})
        end
        table.sort(sortedOres, function(a, b) return a.count > b.count end)
        for _, oreData in ipairs(sortedOres) do
            if lineIndex > 12 then break end
            self.prospectContent.textLines[lineIndex]:SetText("  " .. oreData.name .. " x" .. oreData.count)
            lineIndex = lineIndex + 1
        end
        lineIndex = lineIndex + 1
    end

    if next(ValueFarmDB.prospectData.gems) then
        if lineIndex <= 12 then
            self.prospectContent.textLines[lineIndex]:SetText("|cffffff00Gems Obtained:|r")
            lineIndex = lineIndex + 1
        end
        local sortedGems = {}
        for gemName, data in pairs(ValueFarmDB.prospectData.gems) do
            table.insert(sortedGems, {name = gemName, count = data.count, rarity = data.rarity})
        end
        table.sort(sortedGems, function(a, b) return a.count > b.count end)
        for _, gemData in ipairs(sortedGems) do
            if lineIndex > 12 then break end
            local gemColor = select(4, GetItemQualityColor(gemData.rarity))
            self.prospectContent.textLines[lineIndex]:SetText("  " .. gemColor .. gemData.name .. " x" .. gemData.count .. "|r")
            lineIndex = lineIndex + 1
        end
    end
end

function ValueFarm:FormatTime(seconds)
    local hours = math.floor(seconds / 3600)
    seconds = seconds % 3600
    local minutes = math.floor(seconds / 60)
    seconds = seconds % 60
    return string.format("%02dh %02dm %02ds", hours, minutes, seconds)
end

function ValueFarm:OnSpellCast(unit, spellName, spellID)
    ValueFarm:DebugF("OnSpellCast unit=%s spellName=%s spellID=%s", tostring(unit), tostring(spellName), tostring(spellID))
    if unit ~= "player" then return end

    if ValueFarm.gatheringSpells[spellName] then
        self.gatheringExpires = GetTime() + 3
        ValueFarm:DebugF("Gathering window opened until %.2f for spell '%s'", self.gatheringExpires, spellName)
    end

    if spellName == "Herb Gathering" then
        ValueFarmDB.herbNodesGathered = ValueFarmDB.herbNodesGathered + 1
        ValueFarm:Debug("Herb node counted (" .. ValueFarmDB.herbNodesGathered .. ")")
        if self.herbCountText then
            self.herbCountText:SetText("Herb nodes: " .. ValueFarmDB.herbNodesGathered)
        end
        ValueFarm:DisplayData()
    end

    if spellName == "Mining" then
        ValueFarmDB.oreVeinsGathered = ValueFarmDB.oreVeinsGathered + 1
        ValueFarm:Debug("Ore vein counted (" .. ValueFarmDB.oreVeinsGathered .. ")")
        if self.oreCountText then
            self.oreCountText:SetText("Ore veins: " .. ValueFarmDB.oreVeinsGathered)
        end
        ValueFarm:DisplayData()
    end

    if spellName == "Prospecting" or spellID == 31252 then
        ValueFarmDB.prospectData.totalOres = ValueFarmDB.prospectData.totalOres + 5
        self.prospectingActive = true
        ValueFarm:Debug("Prospecting active for 3s")
        C_Timer.After(3, function()
            self.prospectingActive = false
            ValueFarm:Debug("Prospecting window closed")
        end)
        self:UpdateProspectCount()
    end
end

function ValueFarm:UpdateHerbCount()
    if self.herbCountText then
        self.herbCountText:SetText("Herb nodes: " .. ValueFarmDB.herbNodesGathered)
    end
    if self.oreCountText then
        self.oreCountText:SetText("Ore veins: " .. ValueFarmDB.oreVeinsGathered)
    end
end

SLASH_VALUEFARM1 = "/vf"
SlashCmdList["VALUEFARM"] = function(msg)
    if msg == "start" then
        ValueFarmDB.running = true
        ValueFarmDB.startTime = GetTime()
        ValueFarm:UpdateStartPauseButton()
        print("Loot tracking started.")
    elseif msg == "pause" then
        ValueFarmDB.running = false
        ValueFarm:UpdateStartPauseButton()
        print("Loot tracking paused.")
    elseif msg == "reset" then
        ValueFarmDB.lootData = {}
        ValueFarmDB.trashData = {count = 0, value = 0}
        ValueFarmDB.startTime = 0
        ValueFarmDB.elapsedTime = 0
        ValueFarmDB.running = false
        ValueFarmDB.totalValue = 0
        ValueFarmDB.totalMoney = 0
        ValueFarmDB.herbNodesGathered = 0
        ValueFarmDB.oreVeinsGathered = 0
        ValueFarmDB.prospectData = { totalOres = 0, oreTypes = {}, gems = {} }
        ValueFarm:ClearTextLines()
        ValueFarm:DisplayData()
        ValueFarm:UpdateHerbCount()
        ValueFarm:UpdateProspectCount()
        ValueFarm:UpdateStartPauseButton()
        print("Loot tracking reset.")
    elseif msg == "show" then
        ValueFarmDB.visible = true
        ValueFarm:DisplayData()
        print("ValueFarm window shown.")
    elseif msg == "hide" then
        ValueFarmDB.visible = false
        ValueFarm:DisplayData()
        print("ValueFarm window hidden.")
    elseif msg == "mini" then
        ValueFarmDB.miniMode = not ValueFarmDB.miniMode
        ValueFarm:ApplyMiniMode()
        print("Mini mode: " .. (ValueFarmDB.miniMode and "ON" or "OFF"))
    elseif msg == "debug" then
        ValueFarm.debug = not ValueFarm.debug
        if ValueFarm.debug then
            ValueFarm.debugFrame:Show()
            ValueFarm:Debug("Debug logging enabled.")
        else
            ValueFarm.debugFrame:Hide()
        end
        print("ValueFarm debug: " .. (ValueFarm.debug and "ON" or "OFF"))
    elseif msg == "debug clear" then
        ValueFarm.debugLines = {}
        ValueFarm:UpdateDebugWindow()
        print("ValueFarm debug cleared.")
    elseif msg == "options" then
        if ValueFarm.optionsFrame:IsShown() then
            ValueFarm.optionsFrame:Hide()
        else
            ValueFarm.optionsFrame:Show()
        end
    elseif msg == "herb show" then
        ValueFarm.herbFrame:Show()
        print("Herb counter shown.")
    elseif msg == "herb hide" then
        ValueFarm.herbFrame:Hide()
        print("Herb counter hidden.")
    elseif msg == "prospect show" then
        ValueFarm.prospectFrame:Show()
        print("Prospecting tracker shown.")
    elseif msg == "prospect hide" then
        ValueFarm.prospectFrame:Hide()
        print("Prospecting tracker hidden.")
    elseif msg == "info" then
        print("|cffffff00ValueFarm V0.1 Beta Info:|r")
        print(" - Tracks gathered items (mining, herbing, skinning) sorted by quantity")
        print(" - Session specific list of the amount gathered of WotLK herbs & Crystalized Life.")
        print(" - Keep track of time spent farming.")
        print(" - Track number of herb nodes and ore veins you succeeded in gathering")
        print(" - Track prospecting: ores used and gems obtained (sorted by quantity)")
        print(" - Mini mode, scale + width/height resize, debug window via /vf options")
        print(" - Minimap button: LClick hide/show, RClick mini, Shift+RClick options")
        print("|cffff0000Known bugs/errors or other stuff not working as I want it to yet:|r")
        print(" - Crafted items may still appear; combining Crystallized can re-add items.")
        print("|cff00ff00Features to be added later:|r")
        print(" - Adding % of gathering Crystalized life from herb nodes.")
        print(" - Scroll feature.")
        print(" - Adding Herb/hr and AH value.")
        print("|cffffff00This addon is by Zaximus, made for the 3.3.5 WoW client.|r")
    else
        print("Usage: /vf [start|pause|reset|show|hide|mini|debug|debug clear|options|herb show|herb hide|prospect show|prospect hide|info]")
        print("start - Start tracking loot")
        print("pause - Pause tracking loot")
        print("reset - Reset all data")
        print("show - Show the ValueFarm window")
        print("hide - Hide the ValueFarm window")
        print("mini - Toggle mini mode")
        print("debug - Toggle debug window + logging")
        print("debug clear - Clear debug log")
        print("options - Open the options window")
        print("herb show - Show herb/ore counter window")
        print("herb hide - Hide herb/ore counter window")
        print("prospect show - Show prospecting tracker window")
        print("prospect hide - Hide prospecting tracker window")
        print("info - Show information about the addon")
    end
end