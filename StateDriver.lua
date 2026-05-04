local DCB = DjinnisCircularBars

-- ============================================================
-- StateDriver: builds and applies action-bar-page state drivers
-- Uses LAB's SetState system: each button pre-registers states
-- for all 10 pages, and the root frame propagates via ChildUpdate.
-- ============================================================

local StateDriver   = {}
StateDriver.__index = StateDriver
DCB.StateDriver = StateDriver

-- Returns the default action bar page for a given firstSlot.
-- Slots 1-12 = page 1, 13-24 = page 2, ... 109-120 = page 10.
local function DefaultPage(firstSlot)
    return math.floor(((firstSlot or 1) - 1) / 12) + 1
end

-- Builds the macro-conditional string for RegisterStateDriver.
-- Format: [condition]pageNum;[condition]pageNum;...;defaultPage
function StateDriver:Build(config)
    local parts = {}
    local s     = config.states

    -- Modifier overrides (highest priority)
    if s.modifierStates.CTRL  > 0 then
        tinsert(parts, "[mod:ctrl]"  .. s.modifierStates.CTRL)
    end
    if s.modifierStates.ALT   > 0 then
        tinsert(parts, "[mod:alt]"   .. s.modifierStates.ALT)
    end
    if s.modifierStates.SHIFT > 0 then
        tinsert(parts, "[mod:shift]" .. s.modifierStates.SHIFT)
    end

    -- Stance/form map (e.g. Druid forms, Warrior stances)
    if s.stanceMap then
        for stanceIdx, page in pairs(s.stanceMap) do
            if type(page) == "number" and page > 0 then
                tinsert(parts, "[stance:" .. stanceIdx .. "]" .. page)
            end
        end
    end

    -- Raw custom conditional (user-entered macro syntax)
    if s.customConditions and s.customConditions ~= "" then
        tinsert(parts, s.customConditions)
    end

    -- Fallback default page
    tinsert(parts, tostring(DefaultPage(config.firstSlot)))

    return table.concat(parts, ";")
end

-- Apply paging state driver to a bar.
--
-- Each button is pre-configured with SetState(page, "action", slot) for
-- all 10 pages. The root frame registers a state driver that outputs a
-- page number; its _onstate-state handler calls ChildUpdate("state", page)
-- which triggers each button's built-in _childupdate-state attribute,
-- running UpdateState(page) and redisplaying the correct action slot.
function StateDriver:Apply(bar)
    if InCombatLockdown() then return end
    local config = bar.config

    if not config.states.enabled then
        self:Clear(bar)
        return
    end

    local firstSlot    = config.firstSlot or 1
    local buttonOffset = (firstSlot - 1) % 12  -- position of button 1 within its 12-slot page

    -- Pre-configure all 10 action bar pages on each button.
    for i, btn in ipairs(bar.buttons) do
        local posOnPage = buttonOffset + (i - 1)  -- 0-based offset within the page
        for page = 1, 10 do
            local pageSlot = (page - 1) * 12 + posOnPage + 1
            btn:SetState(page, "action", pageSlot)
        end
        -- State 0 (initial/fallback): use the button's fixed slot
        btn:SetState(0, "action", firstSlot + i - 1)
    end

    -- _onstate-state is set once in CircularBar:New() (construction is always
    -- outside combat). Only register the driver here; do not call SetAttribute.
    RegisterStateDriver(bar.frame, "state", self:Build(config))
end

-- Remove state driver and reset buttons to their fixed slots.
function StateDriver:Clear(bar)
    if InCombatLockdown() then return end
    UnregisterStateDriver(bar.frame, "state")
    -- _onstate-state is permanent (set in constructor); do not nil it.
    local firstSlot = (bar.config.firstSlot or 1)
    for i, btn in ipairs(bar.buttons) do
        btn:SetState(0, "action", firstSlot + i - 1)
        btn:SetAttribute("state", "0")
    end
end
