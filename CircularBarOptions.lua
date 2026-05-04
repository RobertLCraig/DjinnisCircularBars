local DCB        = DjinnisCircularBars
local CircularBar = DCB.CircularBar

-- ============================================================
-- Builds a per-bar AceConfig option group.
-- Mixed into the CircularBar prototype; called from CircularBar:New().
-- ============================================================

function CircularBar:BuildOptionObject()
    local id  = self.id
    local bar = self

    local function get(info)
        return DCB.db.profile.bars[id][info[#info]]
    end

    local function set(info, v)
        DCB.db.profile.bars[id][info[#info]] = v
        bar:ApplyConfig()
    end

    -- Helpers for nested settings
    local function getVis(info)
        return DCB.db.profile.bars[id].visibility[info[#info]]
    end
    local function setVis(info, v)
        DCB.db.profile.bars[id].visibility[info[#info]] = v
        bar:ApplyVisibilityDriver()
    end

    local function getModState(mod)
        return DCB.db.profile.bars[id].states.modifierStates[mod]
    end
    local function setModState(mod, v)
        DCB.db.profile.bars[id].states.modifierStates[mod] = v
        DCB.StateDriver:Apply(bar)
    end

    -- Page dropdown values: 0 = disabled, 1-10 = action bar page
    local pageValues = { [0] = "Disabled" }
    for i = 1, 10 do pageValues[i] = "Page " .. i end

    -- Paging args built separately so we can append stance options via a loop.
    local pagingArgs = {
        enabled = {
            order = 1, type = "toggle", name = "Enable Action Paging",
            desc  = "Allows buttons to switch to a different action bar page based on modifier keys, stances or forms.",
            width = "full",
            get   = function() return DCB.db.profile.bars[id].states.enabled end,
            set   = function(_, v)
                DCB.db.profile.bars[id].states.enabled = v
                DCB.StateDriver:Apply(bar)
            end,
        },
        sep1 = { order = 5, type = "description", name = "" },
        ctrlPage = {
            order = 10, type = "select", name = "Ctrl page",
            desc  = "Action bar page shown while Ctrl is held.",
            values = pageValues,
            disabled = function() return not DCB.db.profile.bars[id].states.enabled end,
            get = function() return getModState("CTRL")  end,
            set = function(_, v) setModState("CTRL", v)  end,
        },
        altPage = {
            order = 11, type = "select", name = "Alt page",
            desc  = "Action bar page shown while Alt is held.",
            values = pageValues,
            disabled = function() return not DCB.db.profile.bars[id].states.enabled end,
            get = function() return getModState("ALT")   end,
            set = function(_, v) setModState("ALT", v)   end,
        },
        shiftPage = {
            order = 12, type = "select", name = "Shift page",
            desc  = "Action bar page shown while Shift is held.",
            values = pageValues,
            disabled = function() return not DCB.db.profile.bars[id].states.enabled end,
            get = function() return getModState("SHIFT") end,
            set = function(_, v) setModState("SHIFT", v) end,
        },
        sep2 = { order = 20, type = "description", name = "" },
        customConditions = {
            order = 21, type = "input", name = "Custom Conditional",
            desc  = "Raw macro conditional syntax. Example: [combat]2;[stealth]3;1\nApplied after modifier overrides.",
            width = "full",
            multiline = false,
            disabled = function() return not DCB.db.profile.bars[id].states.enabled end,
            get = function() return DCB.db.profile.bars[id].states.customConditions end,
            set = function(_, v)
                DCB.db.profile.bars[id].states.customConditions = v
                DCB.StateDriver:Apply(bar)
            end,
        },
        sep3 = {
            order = 30, type = "description", name = "",
            hidden = function() return (GetNumShapeshiftForms() or 0) == 0 end,
        },
        stanceHeader = {
            order = 31, type = "description",
            name  = "Stance / Form Paging",
            hidden = function() return (GetNumShapeshiftForms() or 0) == 0 end,
        },
    }

    -- Append one dropdown per stance/form slot (up to 8).
    -- name, hidden, and get/set all use the closure-captured idx.
    for i = 1, 8 do
        local idx = i
        pagingArgs["stance" .. idx] = {
            order = 31 + idx, type = "select",
            name  = function()
                local _, _, _, spellID = GetShapeshiftFormInfo(idx)
                if spellID then
                    local n = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
                    if not n then n = GetSpellInfo(spellID) end
                    if n then return n end
                end
                return "Stance " .. idx
            end,
            desc     = function() return "Page shown in stance/form " .. idx .. "." end,
            values   = pageValues,
            hidden   = function() return (GetNumShapeshiftForms() or 0) < idx end,
            disabled = function() return not DCB.db.profile.bars[id].states.enabled end,
            get = function()
                return DCB.db.profile.bars[id].states.stanceMap[idx] or 0
            end,
            set = function(_, v)
                if v == 0 then
                    DCB.db.profile.bars[id].states.stanceMap[idx] = nil
                else
                    DCB.db.profile.bars[id].states.stanceMap[idx] = v
                end
                DCB.StateDriver:Apply(bar)
            end,
        }
    end

    return {
        type        = "group",
        name        = function() return DCB.db.profile.bars[id].name or ("Bar " .. id) end,
        order       = 10 + (tonumber(id) or 0),
        childGroups = "tab",
        args = {
            -- ------------------------------------------------
            -- General tab
            -- ------------------------------------------------
            general = {
                type  = "group",
                name  = "General",
                order = 1,
                args  = {
                    enabled = {
                        order = 1, type = "toggle", name = "Enabled",
                        width = "full",
                        get = function() return DCB.db.profile.bars[id].enabled end,
                        set = function(_, v)
                            if v then DCB:EnableBar(id) else DCB:DisableBar(id) end
                        end,
                    },
                    name = {
                        order = 2, type = "input", name = "Bar Name",
                        get = get,
                        set = function(info, v)
                            DCB.db.profile.bars[id].name = v
                            bar.overlayLabel:SetText(v)
                            -- Update option group name
                            LibStub("AceConfigRegistry-3.0"):NotifyChange("DjinnisCircularBars")
                        end,
                    },
                    sep1 = { order = 5, type = "description", name = "" },
                    numButtons = {
                        order = 10, type = "range", name = "Number of Buttons",
                        min = 1, max = 60, step = 1,
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].numButtons = v
                            bar:UpdateButtons()
                            bar:UpdateLayout()
                        end,
                    },
                    firstSlot = {
                        order = 11, type = "range", name = "First Action Slot",
                        desc = "Action slot (1-120) assigned to the first button. Slots 1-12 = bar 1, 13-24 = bar 2, etc.",
                        min = 1, max = 120, step = 1,
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].firstSlot = v
                            bar:UpdateButtons()
                        end,
                    },
                    sep2 = { order = 15, type = "description", name = "" },
                    buttonSize = {
                        order = 20, type = "range", name = "Button Size",
                        min = 16, max = 80, step = 1,
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].buttonSize = v
                            bar:UpdateButtons()
                            bar:UpdateLayout()
                        end,
                    },
                    scale = {
                        order = 21, type = "range", name = "Scale",
                        min = 0.5, max = 2.0, bigStep = 0.05, isPercent = false,
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].scale = v
                            bar.frame:SetScale(v)
                        end,
                    },
                },
            },

            -- ------------------------------------------------
            -- Layout tab
            -- ------------------------------------------------
            layout = {
                type  = "group",
                name  = "Layout",
                order = 2,
                args  = {
                    radius = {
                        order = 1, type = "range", name = "Radius",
                        desc  = "Distance in pixels from the arc anchor to button centres.",
                        min   = 20, softMax = 600, bigStep = 5,
                        get   = get, set = function(info, v)
                            DCB.db.profile.bars[id].radius = v
                            bar:UpdateLayout()
                        end,
                    },
                    arcDegrees = {
                        order = 2, type = "range", name = "Arc Degrees",
                        desc  = "Total angular sweep. 360 = full circle. 180 = semicircle.",
                        min   = 0, max = 360, step = 1,
                        get   = get, set = function(info, v)
                            DCB.db.profile.bars[id].arcDegrees = v
                            bar:UpdateLayout()
                        end,
                    },
                    startAngle = {
                        order = 3, type = "range", name = "Start Angle",
                        desc  = "Angle of the first button. 0 = right, 90 = up, 180 = left, 270 = down.",
                        min   = 0, max = 359, step = 1,
                        get   = get, set = function(info, v)
                            DCB.db.profile.bars[id].startAngle = v
                            bar:UpdateLayout()
                        end,
                    },
                },
            },

            -- ------------------------------------------------
            -- Appearance tab
            -- ------------------------------------------------
            appearance = {
                type  = "group",
                name  = "Appearance",
                order = 3,
                args  = {
                    alpha = {
                        order = 1, type = "range", name = "Alpha",
                        desc  = "Overall opacity of the bar.",
                        min   = 0.0, max = 1.0, bigStep = 0.05, isPercent = true,
                        get   = get, set = function(info, v)
                            DCB.db.profile.bars[id].alpha = v
                            bar:ApplyAlpha()
                        end,
                    },
                    sep1 = { order = 5, type = "description", name = "" },
                    fadeout = {
                        order = 10, type = "toggle", name = "Fade Out When Inactive",
                        desc  = "Bar fades to low opacity when the mouse is not over it.",
                        get   = get, set = set,
                    },
                    fadeoutAlpha = {
                        order = 11, type = "range", name = "Fade-out Alpha",
                        min   = 0.0, max = 1.0, bigStep = 0.05, isPercent = true,
                        disabled = function() return not DCB.db.profile.bars[id].fadeout end,
                        get = get,
                        set = function(info, v)
                            DCB.db.profile.bars[id].fadeoutAlpha = v
                            bar:ApplyAlpha()
                        end,
                    },
                    fadeoutDelay = {
                        order = 12, type = "range", name = "Fade-out Delay (sec)",
                        min   = 0.0, max = 5.0, bigStep = 0.25,
                        disabled = function() return not DCB.db.profile.bars[id].fadeout end,
                        get = get,
                        set = function(info, v)
                            DCB.db.profile.bars[id].fadeoutDelay = v
                        end,
                    },
                    fadeinDelay = {
                        order = 13, type = "range", name = "Fade-in Delay (sec)",
                        desc  = "How long to wait after hovering before the bar fades in. Use a small value to prevent flicker when the mouse briefly passes over the bar.",
                        min   = 0.0, max = 2.0, bigStep = 0.05,
                        disabled = function() return not DCB.db.profile.bars[id].fadeout end,
                        get = get,
                        set = function(info, v)
                            DCB.db.profile.bars[id].fadeinDelay = v
                        end,
                    },
                    sep2 = { order = 20, type = "description", name = "" },
                    showHotkey = {
                        order = 21, type = "toggle", name = "Show Keybind Text",
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].showHotkey = v
                            bar:UpdateButtonConfig()
                        end,
                    },
                    showMacrotext = {
                        order = 22, type = "toggle", name = "Show Macro Name",
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].showMacrotext = v
                            bar:UpdateButtonConfig()
                        end,
                    },
                    showCount = {
                        order = 23, type = "toggle", name = "Show Count",
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].showCount = v
                            bar:UpdateButtonConfig()
                        end,
                    },
                    showBorder = {
                        order = 24, type = "toggle", name = "Show Equipped Border",
                        get = get, set = function(info, v)
                            DCB.db.profile.bars[id].showBorder = v
                            bar:UpdateButtonConfig()
                        end,
                    },
                },
            },

            -- ------------------------------------------------
            -- Click-Through tab
            -- ------------------------------------------------
            clickthrough = {
                type  = "group",
                name  = "Click-Through",
                order = 4,
                args  = {
                    clickthrough = {
                        order = 1, type = "toggle", name = "Enable Click-Through",
                        desc  = "Mouse clicks pass through the bar to the game world. Hold the modifier key (configured in global settings) to temporarily interact with the buttons.",
                        width = "full",
                        get   = function() return DCB.db.profile.bars[id].clickthrough end,
                        set   = function(_, v)
                            DCB.db.profile.bars[id].clickthrough = v
                            bar:ApplyClickThrough()
                        end,
                    },
                    modNote = {
                        order = 2, type = "description",
                        name  = "The modifier key for the click-through override is set in Global Settings.",
                    },
                },
            },

            -- ------------------------------------------------
            -- Paging tab
            -- ------------------------------------------------
            paging = {
                type  = "group",
                name  = "Paging",
                order = 5,
                args  = pagingArgs,
            },

            -- ------------------------------------------------
            -- Visibility tab
            -- ------------------------------------------------
            visibility = {
                type  = "group",
                name  = "Visibility",
                order = 6,
                args  = {
                    combat = {
                        order = 1, type = "toggle", name = "Hide in Combat",
                        get = getVis, set = setVis,
                    },
                    nocombat = {
                        order = 2, type = "toggle", name = "Hide out of Combat",
                        get = getVis, set = setVis,
                    },
                    vehicleui = {
                        order = 3, type = "toggle", name = "Hide with Vehicle UI",
                        get = getVis, set = setVis,
                    },
                    overridebar = {
                        order = 4, type = "toggle", name = "Hide with Override Bar",
                        get = getVis, set = setVis,
                    },
                    pet = {
                        order = 5, type = "toggle", name = "Hide when Pet Active",
                        get = getVis, set = setVis,
                    },
                    nopet = {
                        order = 6, type = "toggle", name = "Hide when No Pet",
                        get = getVis, set = setVis,
                    },
                    always = {
                        order = 7, type = "toggle", name = "Always Hide",
                        get = getVis, set = setVis,
                    },
                    sep1 = { order = 15, type = "description", name = "" },
                    custom = {
                        order = 16, type = "toggle", name = "Custom Conditional",
                        get = getVis, set = setVis,
                    },
                    customdata = {
                        order = 17, type = "input", name = "Custom Condition String",
                        desc  = "Macro conditional that triggers the bar hiding. Example: [spec:2] for spec 2.",
                        width = "full",
                        disabled = function() return not DCB.db.profile.bars[id].visibility.custom end,
                        get = function() return DCB.db.profile.bars[id].visibility.customdata end,
                        set = function(_, v)
                            DCB.db.profile.bars[id].visibility.customdata = v
                            bar:ApplyVisibilityDriver()
                        end,
                    },
                },
            },

            -- ------------------------------------------------
            -- Delete bar
            -- ------------------------------------------------
            deleteBar = {
                order = 99, type = "execute", name = "Delete This Bar",
                desc  = "Permanently removes this bar and its buttons.",
                confirm = true,
                confirmText = "Delete this bar? This cannot be undone.",
                func = function()
                    DCB:HideEditPanel()
                    DCB:DisableBar(id)
                    bar:Destroy()
                    DCB.db.profile.bars[id] = nil
                    DCB.options.args["bar_" .. id] = nil
                    LibStub("AceConfigRegistry-3.0"):NotifyChange("DjinnisCircularBars")
                end,
            },
        },
    }
end
