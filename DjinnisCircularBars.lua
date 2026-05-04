local ADDON_NAME = "DjinnisCircularBars"

local DCB = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
_G.DjinnisCircularBars = DCB

local LAB      = LibStub("LibActionButton-1.0")
local LibWin   = LibStub("LibWindow-1.1")
local Masque   = LibStub("Masque", true)
local LDB      = LibStub("LibDualSpec-1.0", true)

-- ============================================================
-- Saved variable defaults
-- ============================================================

local defaults = {
    profile = {
        locked      = true,
        tooltip     = "enabled",     -- "enabled" | "nocombat" | "disabled"
        buttonlock  = true,
        modifierKey = "CTRL",        -- "CTRL" | "ALT" | "SHIFT" | "NONE"
        showGrid    = false,
        bars = {
            ["**"] = {
                enabled       = true,
                name          = "Bar",
                -- Layout
                numButtons    = 12,
                firstSlot     = 1,
                radius        = 150,
                arcDegrees    = 180,
                startAngle    = 0,
                buttonSize    = 45,
                scale         = 1.0,
                -- Appearance
                alpha         = 1.0,
                fadeout       = false,
                fadeoutAlpha  = 0.1,
                fadeoutDelay  = 1.5,
                fadeinDelay   = 0.0,
                -- Button labels
                showHotkey    = true,
                showMacrotext = true,
                showCount     = true,
                showBorder    = true,
                -- Interaction
                clickthrough  = false,
                -- Action paging
                states = {
                    enabled          = false,
                    modifierStates   = { CTRL = 0, ALT = 0, SHIFT = 0 },
                    stanceMap        = {},
                    customConditions = "",
                },
                -- Position (LibWindow manages this table in-place)
                position = { point = "CENTER", x = 0, y = -200, scale = 1.0 },
                -- Visibility conditionals
                visibility = {
                    vehicleui   = false,
                    overridebar = false,
                    combat      = false,
                    nocombat    = false,
                    pet         = false,
                    nopet       = false,
                    always      = false,
                    custom      = false,
                    customdata  = "",
                },
            },
        },
    },
}

-- ============================================================
-- Addon lifecycle
-- ============================================================

function DCB:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("DjinnisCircularBarsDB", defaults, true)
    self.db.RegisterCallback(self, "OnProfileChanged", "ReloadBars")
    self.db.RegisterCallback(self, "OnProfileCopied",  "ReloadBars")
    self.db.RegisterCallback(self, "OnProfileReset",   "ReloadBars")

    if LDB then
        LDB:EnhanceDatabase(self.db, ADDON_NAME)
    end

    -- Detect corrupt SavedVariables (e.g. from the pre-rawget AddBar infinite loop)
    -- and wipe rather than attempting to create thousands of frames.
    -- ResetProfile() fires ReloadBars synchronously before self.bars exists,
    -- so we wipe the bars table in-place instead.
    local barCount = 0
    for _ in pairs(self.db.profile.bars) do
        barCount = barCount + 1
        if barCount > 100 then break end
    end
    if barCount > 100 then
        geterrorhandler()(("DjinnisCircularBars: %d bars detected (corrupt data from a previous bug). Wiping and reseeding."):format(barCount))
        for k in pairs(self.db.profile.bars) do
            self.db.profile.bars[k] = nil
        end
        -- Reading a missing key through AceDB's ["**"] __index creates the entry
        -- with all defaults populated (position, visibility, states, etc.).
        -- Assigning {} directly would store a plain table that loses those defaults.
        local _ = self.db.profile.bars["1"]
    end

    -- First-run: seed one default bar so the addon is visible immediately
    if not next(self.db.profile.bars) then
        local _ = self.db.profile.bars["1"]
    end

    self.Locked = self.db.profile.locked
    self:SetupOptions()
end

function DCB:OnEnable()
    self.bars = {}

    -- Register events that must be live immediately
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("MODIFIER_STATE_CHANGED", "OnModifierStateChanged")

    if EventRegistry then
        EventRegistry:RegisterCallback("EditMode.Enter", function()
            self:SetEditModeActive(true)
        end, self)
        EventRegistry:RegisterCallback("EditMode.Exit", function()
            self:SetEditModeActive(false)
        end, self)
    end

    -- Defer bar creation one frame so the first render is not blocked.
    -- This keeps PLAYER_LOGIN fast and lets WoW draw its own UI first.
    C_Timer.After(0, function()
        local t0 = GetTimePreciseSec()
        for id, config in pairs(self.db.profile.bars) do
            if config.enabled then
                local bt = GetTimePreciseSec()
                self:CreateBar(id, config)
                local ms = (GetTimePreciseSec() - bt) * 1000
                if ms > 100 then
                    geterrorhandler()(("DjinnisCircularBars: CreateBar(%s) took %.0fms"):format(id, ms))
                end
            end
        end
        local total = (GetTimePreciseSec() - t0) * 1000
        if total > 200 then
            geterrorhandler()(("DjinnisCircularBars: OnEnable bar creation took %.0fms total"):format(total))
        end
    end)
end

function DCB:OnCombatStart()
    self:Lock()
end

-- ============================================================
-- Bar management
-- ============================================================

function DCB:CreateBar(id, config)
    local bar = DCB.CircularBar:New(tostring(id), config)
    self.bars[tostring(id)] = bar
    return bar
end

function DCB:AddBar()
    local n = 1
    -- rawget bypasses AceDB's ["**"] wildcard __index which would make every
    -- key appear to exist; we need the actual stored entries only.
    while rawget(self.db.profile.bars, tostring(n)) do
        n = n + 1
        if n > 200 then
            geterrorhandler()("DjinnisCircularBars: AddBar safety cap reached.")
            return
        end
    end
    local id = tostring(n)
    -- Reading a missing key through AceDB's ["**"] __index creates the entry
    -- with all defaults populated (position, visibility, states, etc.) and
    -- rawsets it, so subsequent rawget sees it. Assigning {} directly stores
    -- a plain table that bypasses default initialization.
    local config = self.db.profile.bars[id]
    local bar = self:CreateBar(id, config)
    -- Option group is injected by CircularBar:New() when DCB.options exists.
    if not self.Locked and not InCombatLockdown() then
        bar:Unlock()
    end
    return bar
end

function DCB:EnableBar(id)
    id = tostring(id)
    self.db.profile.bars[id].enabled = true
    if not self.bars[id] then
        self:CreateBar(id, self.db.profile.bars[id])
        if not self.Locked and not InCombatLockdown() then
            self.bars[id]:Unlock()
        end
    else
        self.bars[id]:Enable()
    end
end

function DCB:DisableBar(id)
    id = tostring(id)
    self.db.profile.bars[id].enabled = false
    if self.bars[id] then
        self.bars[id]:Disable()
    end
end

function DCB:ReloadBars()
    for _, bar in pairs(self.bars) do
        bar:Destroy()
    end
    self.bars = {}
    -- Rebuild options groups
    if self.options then
        for k in pairs(self.options.args) do
            if k:match("^bar_") then
                self.options.args[k] = nil
            end
        end
    end
    -- Recreate bars without re-registering events (OnEnable already did that once).
    C_Timer.After(0, function()
        for id, config in pairs(self.db.profile.bars) do
            if config.enabled then
                self:CreateBar(id, config)
            end
        end
        -- Bars are created in locked state. Sync with the incoming profile's preference.
        self.Locked = true
        if not self.db.profile.locked and not InCombatLockdown() then
            self:Unlock()
        end
    end)
end

-- ============================================================
-- Lock / Unlock
-- ============================================================

function DCB:Lock()
    if not self.Locked then
        self.Locked = true
        self.db.profile.locked = true
        for _, bar in pairs(self.bars) do bar:Lock() end
    end
end

function DCB:Unlock()
    if InCombatLockdown() then
        self:Print("Cannot unlock during combat.")
        return
    end
    if self.Locked then
        self.Locked = false
        self.db.profile.locked = false
        for _, bar in pairs(self.bars) do bar:Unlock() end
    end
end

function DCB:ToggleLock()
    if self.Locked then self:Unlock() else self:Lock() end
end

-- ============================================================
-- Edit Mode integration
-- ============================================================

function DCB:SetEditModeActive(active)
    if active then
        if InCombatLockdown() then return end
        self:Unlock()
        for _, bar in pairs(self.bars) do
            bar:ShowEditModeHint()
        end
    else
        self:Lock()
        for _, bar in pairs(self.bars) do
            bar:HideEditModeHint()
        end
    end
end

-- ============================================================
-- Modifier key handling (click-through override)
-- Event-driven: fires only when a modifier key is pressed or released,
-- not on every frame. Uses Is*KeyDown() to handle L/R variants correctly.
-- ============================================================

function DCB:OnModifierStateChanged(_, key)
    if InCombatLockdown() then return end
    local mk = self.db.profile.modifierKey
    if mk == "NONE" then return end
    local relevant = (mk == "CTRL"  and (key == "LCTRL"  or key == "RCTRL"))
                  or (mk == "ALT"   and (key == "LALT"   or key == "RALT"))
                  or (mk == "SHIFT" and (key == "LSHIFT" or key == "RSHIFT"))
    if not relevant then return end
    local held = (mk == "CTRL"  and IsControlKeyDown())
              or (mk == "ALT"   and IsAltKeyDown())
              or (mk == "SHIFT" and IsShiftKeyDown())
    for _, bar in pairs(self.bars) do
        bar:UpdateModifierState(held)
    end
end

-- ============================================================
-- Slash commands
-- ============================================================

function DCB:ChatCommand(input)
    if InCombatLockdown() then
        self:Print("Cannot open options during combat.")
        return
    end
    input = input and input:trim() or ""
    if input == "" then
        LibStub("AceConfigDialog-3.0"):Open(ADDON_NAME)
    elseif input == "lock" then
        self:Lock()
    elseif input == "unlock" then
        self:Unlock()
    elseif input == "toggle" then
        self:ToggleLock()
    else
        self:Print("Usage: /dcb [lock|unlock|toggle]")
    end
end
