local DCB    = DjinnisCircularBars
local LAB    = LibStub("LibActionButton-1.0")
local LibWin = LibStub("LibWindow-1.1")
local Masque = LibStub("Masque", true)

local math_cos = math.cos
local math_sin = math.sin
local math_pi  = math.pi
local math_max = math.max

-- ============================================================
-- CircularBar prototype
-- ============================================================

local CircularBar    = {}
local CircularBar_MT = { __index = CircularBar }
DCB.CircularBar = CircularBar

-- Monotonically increasing counter used to make frame names unique per
-- constructor call. Prevents "Frame already exists" errors when a bar is
-- deleted and later recreated with the same id in the same session.
local _nextGen = 0

-- ============================================================
-- Constructor
-- ============================================================

function CircularBar:New(id, config)
    local self = setmetatable({}, CircularBar_MT)
    self.id         = id
    self.config     = config
    self.buttons    = {}
    self.hoverCount = 0

    _nextGen = _nextGen + 1
    self._gen = _nextGen

    -- Root frame: invisible 1x1, holds state drivers, LibWindow positions this
    local rootName = "DCBBar" .. id .. "_" .. self._gen
    local root = CreateFrame("Frame", rootName, UIParent, "SecureHandlerStateTemplate")
    root:SetSize(1, 1)
    root:SetMovable(true)
    root:SetClampedToScreen(true)
    self.frame = root

    -- Set secure attributes now, at construction time (outside combat).
    -- SetAttribute on a SecureHandlerStateTemplate frame is a protected call
    -- blocked during combat lockdown; these values never change so one-time
    -- setup here avoids the need to call SetAttribute again later.
    root:SetAttribute("_onstate-vis", [[
        if newstate == "show" then self:Show() else self:Hide() end
    ]])
    root:SetAttribute("_onstate-state", [[
        control:ChildUpdate("state", newstate)
    ]])

    -- Restore saved position
    LibWin.RegisterConfig(root, config.position)
    LibWin.RestorePosition(root)

    -- Overlay: drag handle + settings trigger when unlocked.
    -- EditModeSystemSelectionTemplate gives it the native WoW Edit Mode look
    -- (white selection border with corner handles).
    local overlay = CreateFrame("Frame", rootName .. "Overlay", root,
        "EditModeSystemSelectionTemplate")
    overlay:SetFrameLevel(root:GetFrameLevel() + 2)
    overlay:EnableMouse(false)
    -- WoW 11.0.2+ requires a .system property on Edit Mode selection frames.
    if not overlay.system then
        overlay.system = { GetSystemName = function() return "DCBBar_" .. id end }
    end

    -- Bar name label: use template's built-in Label if present, else create one.
    if overlay.Label then
        overlay.Label:SetText(config.name or ("Bar " .. id))
        self.overlayLabel = overlay.Label
    else
        local label = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetPoint("CENTER")
        label:SetText(config.name or ("Bar " .. id))
        self.overlayLabel = label
    end

    -- Hint shown when Edit Mode is active.
    local hint = overlay:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    hint:SetPoint("BOTTOM", overlay, "BOTTOM", 0, 6)
    hint:SetText("|cff888888Drag to move  Click for settings|r")
    hint:Hide()
    self.overlayHint = hint

    -- Drag to reposition.
    overlay:RegisterForDrag("LeftButton")
    overlay:SetScript("OnDragStart", function()
        root:StartMoving()
        root.isMoving = true
    end)
    overlay:SetScript("OnDragStop", function()
        root:StopMovingOrSizing()
        root.isMoving    = nil
        root.wasDragging = true
        LibWin.SavePosition(root)
    end)
    -- OnDragStop fires before OnMouseUp; wasDragging lets us suppress the
    -- click action that would otherwise fire after every drag.
    overlay:SetScript("OnMouseUp", function()
        if root.wasDragging then
            root.wasDragging = nil
            return
        end
        DCB:ShowEditPanel(self)
    end)

    overlay:Hide()
    self.overlay = overlay

    -- Masque group (optional)
    if Masque then
        self.masqueGroup = Masque:Group(
            "DjinnisCircularBars",
            config.name or ("Bar " .. id),
            "dcb_bar_" .. id
        )
        self.masqueGroup:RegisterCallback(function(group, option, value)
            if option == "Scale" then
                -- Masque scale affects button size; update bounding box
                self:UpdateLayout()
            end
        end)
    end

    root:SetScale(config.scale or 1.0)
    self:ApplyAlpha()

    self:UpdateButtons()
    self:UpdateLayout()
    self:ApplyClickThrough()
    self:ApplyVisibilityDriver()

    -- Inject option group into global options if they're already built
    if DCB.options then
        DCB.options.args["bar_" .. id] = self:BuildOptionObject()
        LibStub("AceConfigRegistry-3.0"):NotifyChange("DjinnisCircularBars")
    end

    return self
end

-- ============================================================
-- Button management
-- ============================================================

function CircularBar:UpdateButtons()
    if InCombatLockdown() then return end
    local cfg  = self.config
    local N    = cfg.numButtons
    local slot = cfg.firstSlot or 1

    for i = 1, N do
        local actionSlot = slot + i - 1
        if not self.buttons[i] then
            local btnName = "DCBBar" .. self.id .. "_" .. self._gen .. "Btn" .. i
            local btn = LAB:CreateButton(actionSlot, btnName, self.frame, nil)
            btn:SetState(0, "action", actionSlot)
            self.buttons[i] = btn
            self:AttachFadeHandlers(btn)
            if self.masqueGroup then
                btn:AddToMasque(self.masqueGroup)
            end
        else
            self.buttons[i]:SetState(0, "action", actionSlot)
        end
        local btn = self.buttons[i]
        btn:SetSize(cfg.buttonSize or 45, cfg.buttonSize or 45)
        btn:SetParent(self.frame)
        btn:Show()
        btn:SetAttribute("statehidden", nil)
    end

    -- Hide buttons beyond the current count
    for i = N + 1, #self.buttons do
        self.buttons[i]:Hide()
        self.buttons[i]:SetAttribute("statehidden", true)
    end

    self:UpdateButtonConfig()
    self:ApplyButtonLock()
    self:ApplyClickThrough()
end

function CircularBar:ApplyButtonLock()
    if InCombatLockdown() then return end
    local locked = DCB.db.profile.buttonlock
    for _, btn in ipairs(self.buttons) do
        btn:SetAttribute("buttonlock", locked or false)
    end
end

function CircularBar:UpdateButtonConfig()
    local cfg      = self.config
    local globalDB = DCB.db.profile
    local btnCfg = {
        tooltip      = globalDB.tooltip or "enabled",
        showGrid     = globalDB.showGrid or false,
        hideElements = {
            macro    = not cfg.showMacrotext,
            hotkey   = not cfg.showHotkey,
            equipped = not cfg.showBorder,
        },
    }
    local showCount = cfg.showCount ~= false
    for _, btn in ipairs(self.buttons) do
        btn:UpdateConfig(btnCfg)
        -- LAB never calls Count:Show/Hide, only SetText, so we control it directly.
        if btn.Count then
            if showCount then btn.Count:Show() else btn.Count:Hide() end
        end
    end
end

-- ============================================================
-- Polar coordinate layout
-- ============================================================

function CircularBar:UpdateLayout()
    if InCombatLockdown() then return end
    local cfg      = self.config
    local N        = cfg.numButtons
    local radius   = cfg.radius   or 150
    local arcDeg   = cfg.arcDegrees or 180
    local startDeg = cfg.startAngle or 0
    local btnSize  = cfg.buttonSize or 45

    if N == 0 then return end

    local step
    if N == 1 then
        step = 0
    elseif arcDeg >= 360 then
        step = 360 / N       -- full circle: no duplicate endpoint
    else
        step = arcDeg / (N - 1)  -- arc: endpoints are first and last buttons
    end

    -- Resize overlay to cover bounding box of the arc
    local bbox = (radius + btnSize) * 2
    self.overlay:SetSize(bbox, bbox)
    self.overlay:ClearAllPoints()
    self.overlay:SetPoint("CENTER", self.frame, "CENTER", 0, 0)

    for i = 1, N do
        local btn = self.buttons[i]
        if btn then
            local angleDeg = startDeg + (i - 1) * step
            local angleRad = angleDeg * math_pi / 180
            btn:ClearAllPoints()
            btn:SetPoint("CENTER", self.frame, "CENTER",
                radius * math_cos(angleRad),
                radius * math_sin(angleRad))
        end
    end
end

-- ============================================================
-- Click-through
-- ============================================================

function CircularBar:ApplyClickThrough()
    if InCombatLockdown() then return end
    local interactive
    if self.config.clickthrough then
        -- Click-through is on: buttons are only interactive while the modifier is held.
        -- Seed the correct state based on what's currently pressed.
        local mk = DjinnisCircularBars.db.profile.modifierKey
        interactive = (mk == "CTRL"  and IsControlKeyDown())
                   or (mk == "ALT"   and IsAltKeyDown())
                   or (mk == "SHIFT" and IsShiftKeyDown())
                   or (mk == "NONE")
    else
        interactive = true
    end
    for _, btn in ipairs(self.buttons) do
        btn:EnableMouse(interactive)
    end
end

-- Called by DCB:OnModifierStateChanged when a relevant modifier key is pressed/released.
function CircularBar:UpdateModifierState(modHeld)
    if InCombatLockdown() then return end
    if not self.config.clickthrough then return end
    for _, btn in ipairs(self.buttons) do
        btn:EnableMouse(modHeld)
    end
end

-- ============================================================
-- Fade-on-hover
-- ============================================================

function CircularBar:AttachFadeHandlers(btn)
    local bar = self
    btn:HookScript("OnEnter", function()
        bar.hoverCount = bar.hoverCount + 1
        if bar.config.fadeout and bar.hoverCount == 1 then
            local delay = bar.config.fadeinDelay or 0.0
            if delay > 0 then
                C_Timer.After(delay, function()
                    if bar.hoverCount > 0 and bar.config.fadeout then
                        UIFrameFadeIn(bar.frame, 0.2, bar.frame:GetAlpha(), bar.config.alpha or 1.0)
                    end
                end)
            else
                UIFrameFadeIn(bar.frame, 0.2, bar.frame:GetAlpha(), bar.config.alpha or 1.0)
            end
        end
    end)
    btn:HookScript("OnLeave", function()
        bar.hoverCount = math_max(0, bar.hoverCount - 1)
        if bar.config.fadeout and bar.hoverCount == 0 then
            C_Timer.After(bar.config.fadeoutDelay or 1.5, function()
                if bar.hoverCount == 0 and bar.config.fadeout then
                    UIFrameFadeOut(bar.frame, 0.5, bar.frame:GetAlpha(), bar.config.fadeoutAlpha or 0.1)
                end
            end)
        end
    end)
end

-- ============================================================
-- Visibility driver
-- ============================================================

function CircularBar:BuildVisibilityDriver()
    local parts = { "[petbattle]hide" }
    local vis   = self.config.visibility
    if vis.vehicleui   then tinsert(parts, "[vehicleui]hide")   end
    if vis.overridebar then tinsert(parts, "[overridebar]hide") end
    if vis.combat      then tinsert(parts, "[combat]hide")      end
    if vis.nocombat    then tinsert(parts, "[nocombat]hide")    end
    if vis.pet         then tinsert(parts, "[pet]hide")         end
    if vis.nopet       then tinsert(parts, "[nopet]hide")       end
    if vis.always      then
        tinsert(parts, "hide")
        return table.concat(parts, ";")
    end
    if vis.custom and vis.customdata and vis.customdata ~= "" then
        tinsert(parts, vis.customdata .. "hide")
    end
    tinsert(parts, "show")
    return table.concat(parts, ";")
end

function CircularBar:ApplyVisibilityDriver()
    if self.unlocked then return end
    RegisterStateDriver(self.frame, "vis", self:BuildVisibilityDriver())
end

function CircularBar:DisableVisibilityDriver()
    UnregisterStateDriver(self.frame, "vis")
    self.frame:Show()
end

-- ============================================================
-- Lock / Unlock / Edit Mode
-- ============================================================

function CircularBar:Lock()
    if not self.unlocked then return end
    self.unlocked = nil
    self.overlay:EnableMouse(false)
    self.overlay:RegisterForDrag()   -- no args clears all registered drag buttons
    self.overlay:Hide()
    LibWin.SavePosition(self.frame)
    self:ApplyVisibilityDriver()
    DCB:HideEditPanel()
end

function CircularBar:Unlock()
    if self.unlocked then return end
    self.unlocked = true
    self:DisableVisibilityDriver()
    self.frame:Show()
    self.overlay:Show()
    self.overlay:EnableMouse(true)
    self.overlay:RegisterForDrag("LeftButton")
end

function CircularBar:ShowEditModeHint()
    if self.overlayHint then
        self.overlayHint:Show()
    end
end

function CircularBar:HideEditModeHint()
    if self.overlayHint then
        self.overlayHint:Hide()
    end
end

function CircularBar:Enable()
    self.config.enabled = true
    self:ApplyAlpha()
    self.frame:Show()
    self:ApplyVisibilityDriver()
end

function CircularBar:Disable()
    self.config.enabled = false
    self:DisableVisibilityDriver()
    self.frame:Hide()
end

function CircularBar:Destroy()
    self:DisableVisibilityDriver()
    if DCB.StateDriver then
        DCB.StateDriver:Clear(self)
    end
    for _, btn in ipairs(self.buttons) do
        btn:Hide()
        btn:SetParent(UIParent)
    end
    self.frame:Hide()
    self.frame:SetParent(nil)
    if DCB.bars[self.id] == self then
        DCB.bars[self.id] = nil
    end
end

-- ============================================================
-- Quick settings context menu (right-click in Edit Mode)
-- ============================================================

function CircularBar:OpenQuickSettings()
    LibStub("AceConfigDialog-3.0"):Open("DjinnisCircularBars", "bar_" .. self.id)
end

-- ============================================================
-- Unified config re-apply (called when any setting changes)
-- ============================================================

function CircularBar:ApplyAlpha()
    if self.config.fadeout and self.hoverCount == 0 then
        self.frame:SetAlpha(self.config.fadeoutAlpha or 0.1)
    else
        self.frame:SetAlpha(self.config.alpha or 1.0)
    end
end

function CircularBar:ApplyConfig()
    self.frame:SetScale(self.config.scale or 1.0)
    self:ApplyAlpha()
    self:UpdateButtons()
    self:UpdateLayout()
    self:ApplyClickThrough()
    self:ApplyVisibilityDriver()
    if DCB.StateDriver then
        DCB.StateDriver:Apply(self)
    end
end
