local DCB        = DjinnisCircularBars
local ADDON_NAME = "DjinnisCircularBars"

-- ============================================================
-- SetupOptions: builds and registers the AceConfig options table.
-- Called from DCB:OnInitialize(). Per-bar option groups are injected
-- by CircularBar:New() after each bar is created.
-- ============================================================

function DCB:SetupOptions()
    local options = {
        type        = "group",
        name        = "Circular Bars",
        childGroups = "tree",
        args = {
            -- ------------------------------------------------
            -- Global settings group
            -- ------------------------------------------------
            global = {
                type  = "group",
                name  = "Global Settings",
                order = 1,
                args  = {
                    lock = {
                        order = 1, type = "toggle", name = "Lock Bars",
                        desc  = "Lock bars in place. Unlock to drag-reposition them.",
                        get = function() return DCB.Locked end,
                        set = function(_, v)
                            if v then DCB:Lock() else DCB:Unlock() end
                        end,
                    },
                    editModeNote = {
                        order = 2, type = "description",
                        name  = "Bars also auto-unlock when WoW's Edit Mode is open.",
                    },
                    sep1 = { order = 5, type = "description", name = "" },
                    modifierKey = {
                        order = 10, type = "select", name = "Click-Through Modifier Key",
                        desc  = "Hold this key to temporarily interact with click-through bars.",
                        values = {
                            NONE  = "None (always click-through)",
                            CTRL  = "Ctrl",
                            ALT   = "Alt",
                            SHIFT = "Shift",
                        },
                        get = function() return DCB.db.profile.modifierKey end,
                        set = function(_, v)
                            DCB.db.profile.modifierKey = v
                            -- Reset modifier state tracking on all bars
                            for _, bar in pairs(DCB.bars) do
                                bar.lastModState = nil
                            end
                        end,
                    },
                    sep2 = { order = 15, type = "description", name = "" },
                    tooltip = {
                        order = 20, type = "select", name = "Tooltip",
                        values = {
                            enabled  = "Always show",
                            nocombat = "Hide in combat",
                            disabled = "Never show",
                        },
                        get = function() return DCB.db.profile.tooltip end,
                        set = function(_, v)
                            DCB.db.profile.tooltip = v
                            for _, bar in pairs(DCB.bars) do
                                bar:UpdateButtonConfig()
                            end
                        end,
                    },
                    showGrid = {
                        order = 21, type = "toggle", name = "Show Empty Button Slots",
                        desc  = "Display placeholder buttons for empty action slots.",
                        get = function() return DCB.db.profile.showGrid end,
                        set = function(_, v)
                            DCB.db.profile.showGrid = v
                            for _, bar in pairs(DCB.bars) do
                                bar:UpdateButtonConfig()
                            end
                        end,
                    },
                    buttonlock = {
                        order = 22, type = "toggle", name = "Button Lock",
                        desc  = "Prevent accidental drag-and-drop of actions. Hold the Shift modifier to pick up an action while locked.",
                        get = function() return DCB.db.profile.buttonlock end,
                        set = function(_, v)
                            DCB.db.profile.buttonlock = v
                            for _, bar in pairs(DCB.bars) do
                                bar:ApplyButtonLock()
                            end
                        end,
                    },
                    sep3 = { order = 30, type = "description", name = "" },
                    addBar = {
                        order = 31, type = "execute", name = "Add New Bar",
                        desc  = "Creates a new circular bar with default settings.",
                        func = function()
                            DCB:AddBar()
                        end,
                    },
                },
            },

            -- ------------------------------------------------
            -- Profiles group (AceDBOptions)
            -- ------------------------------------------------
            profiles = LibStub("AceDBOptions-3.0"):GetOptionsTable(DCB.db),
        },
    }

    options.args.profiles.order = 1000

    -- LibDualSpec: enhance profiles with spec-aware switching
    local LDB = LibStub("LibDualSpec-1.0", true)
    if LDB then
        LDB:EnhanceOptions(options.args.profiles, DCB.db)
    end

    DCB.options = options

    LibStub("AceConfig-3.0"):RegisterOptionsTable(ADDON_NAME, options)
    LibStub("AceConfigDialog-3.0"):SetDefaultSize(ADDON_NAME, 700, 560)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions(ADDON_NAME, "Circular Bars")

    DCB:RegisterChatCommand("dcb",          "ChatCommand")
    DCB:RegisterChatCommand("circularbars", "ChatCommand")
end
