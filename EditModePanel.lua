local DCB        = DjinnisCircularBars
local math_floor = math.floor

-- Singleton quick-settings panel shown when a bar's Edit Mode overlay is clicked.
--
-- Uses MinimalSliderWithSteppersTemplate directly rather than
-- EditModeSettingSliderTemplate. The Edit Mode wrapper mixin registers
-- callbacks that call EditModeSystemSettingsDialog, which is only valid inside
-- the native Edit Mode dialog. Using the bare slider avoids that dependency
-- and the double-OnLoad stacking bug that caused sliders to not render.

local PANEL_W  = 290
local LABEL_W  = 90     -- label column width
local SLIDER_W = 156    -- MinimalSliderWithSteppers width (fills remaining space)
local SLIDER_H = 32
local PAD      = 14
local PANEL_H  = 200

local panel, currentBar
local savedPosX, savedPosY   -- session-only: last position after a drag

-- --------------------------------------------------------
-- Slider factory
-- --------------------------------------------------------

local function makeSlider(parent, labelText, minVal, maxVal, stepSize)
    -- Plain container; no template mixin so no OnLoad side-effects.
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(LABEL_W + 5 + SLIDER_W, SLIDER_H)
    f._minVal        = minVal
    f._maxVal        = maxVal
    f._stepSize      = stepSize
    f._currentValue  = minVal
    f.initInProgress = false

    local label = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
    label:SetSize(LABEL_W, SLIDER_H)
    label:SetPoint("LEFT", f, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetText(labelText)
    f.Label = label

    -- MinimalSliderWithSteppers fires its own OnLoad during CreateFrame.
    local slider = CreateFrame("Frame", nil, f, "MinimalSliderWithSteppersTemplate")
    slider:SetSize(SLIDER_W, SLIDER_H)
    slider:SetPoint("LEFT", label, "RIGHT", 5, 0)
    if slider.MinText then slider.MinText:Hide() end
    if slider.MaxText then slider.MaxText:Hide() end
    f.Slider = slider

    -- Integer right-label formatter.
    local intFmt = function(v) return tostring(math_floor(v + 0.5)) end
    f.formatters = {}
    if MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        local key = MinimalSliderWithSteppersMixin.Label.Right
        if CreateMinimalSliderFormatter then
            f.formatters[key] = CreateMinimalSliderFormatter(key, intFmt)
        else
            f.formatters[key] = intFmt
        end
    end

    -- Register directly on the slider widget; no mixin OnLoad needed.
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        if f.initInProgress then return end
        value = math_floor(value + 0.5)
        if value == f._currentValue then return end
        f._currentValue = value
        if f._onChange then f._onChange(value) end
    end, f)

    return f
end

-- Set slider to a value without firing the onChange callback.
local function sliderSetValue(f, value)
    f.initInProgress = true
    local steps = math_floor((f._maxVal - f._minVal) / f._stepSize + 0.5)
    if f.Slider and f.Slider.Init then
        f.Slider:Init(value, f._minVal, f._maxVal, steps, f.formatters)
    end
    f._currentValue  = math_floor(value + 0.5)
    f.initInProgress = false
end

-- --------------------------------------------------------
-- Panel construction (deferred until first use)
-- --------------------------------------------------------

local function buildPanel()
    if panel then return end

    panel = CreateFrame("Frame", "DCBQuickEditPanel", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(PANEL_W, PANEL_H)
    panel:SetFrameStrata("DIALOG")
    panel:SetFrameLevel(200)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetMovable(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) self:StartMoving() end)
    panel:SetScript("OnDragStop",  function(self)
        self:StopMovingOrSizing()
        savedPosX = self:GetLeft()
        savedPosY = self:GetBottom()
    end)

    if panel.SetBackdrop then
        panel:SetBackdrop({
            bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 8, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        panel:SetBackdropColor(0.08, 0.08, 0.12, 0.95)
        panel:SetBackdropBorderColor(0.4, 0.7, 1.0, 1.0)
    end

    -- Title
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT",  panel, "TOPLEFT",  PAD, -10)
    title:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -28, -10)
    title:SetJustifyH("LEFT")
    panel.titleText = title

    -- Close button
    local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() panel:Hide() end)

    -- Sliders stacked with 4 px gap, starting 36 px below the top
    local Y0  = -36
    local GAP = 4

    local sRadius = makeSlider(panel, "Radius",      20, 600, 5)
    local sArc    = makeSlider(panel, "Arc Degrees",  0, 360, 1)
    local sAngle  = makeSlider(panel, "Start Angle",  0, 359, 1)

    sRadius:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, Y0)
    sArc:SetPoint(   "TOPLEFT", panel, "TOPLEFT", PAD, Y0 - (SLIDER_H + GAP))
    sAngle:SetPoint( "TOPLEFT", panel, "TOPLEFT", PAD, Y0 - (SLIDER_H + GAP) * 2)

    sRadius._onChange = function(v)
        if not currentBar then return end
        currentBar.config.radius = v
        currentBar:UpdateLayout()
    end
    sArc._onChange = function(v)
        if not currentBar then return end
        currentBar.config.arcDegrees = v
        currentBar:UpdateLayout()
    end
    sAngle._onChange = function(v)
        if not currentBar then return end
        currentBar.config.startAngle = v
        currentBar:UpdateLayout()
    end

    panel.sRadius = sRadius
    panel.sArc    = sArc
    panel.sAngle  = sAngle

    -- "All Settings" opens the full AceConfig dialog for this bar
    local allBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    allBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 10)
    allBtn:SetSize(200, 22)
    allBtn:SetText("All Settings")
    allBtn:SetScript("OnClick", function()
        if currentBar then
            currentBar:OpenQuickSettings()
            panel:Hide()
        end
    end)

    panel:Hide()
end

-- --------------------------------------------------------
-- Public API consumed by CircularBar and DjinnisCircularBars
-- --------------------------------------------------------

function DCB:ShowEditPanel(bar)
    buildPanel()
    currentBar = bar
    local cfg = bar.config

    panel.titleText:SetText(cfg.name or ("Bar " .. bar.id))

    sliderSetValue(panel.sRadius, cfg.radius     or 150)
    sliderSetValue(panel.sArc,    cfg.arcDegrees or 180)
    sliderSetValue(panel.sAngle,  cfg.startAngle or 0)

    panel:ClearAllPoints()
    if savedPosX then
        panel:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", savedPosX, savedPosY)
    else
        panel:SetPoint("LEFT", bar.overlay, "RIGHT", 10, 0)
    end
    panel:Show()
    panel:Raise()
end

function DCB:HideEditPanel()
    if panel then panel:Hide() end
    currentBar = nil
end
