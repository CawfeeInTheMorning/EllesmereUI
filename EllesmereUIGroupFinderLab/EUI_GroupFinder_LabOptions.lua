if EUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (EllesmereUI_ClientGate.lua)
-------------------------------------------------------------------------------
-- EUI_GroupFinder_LabOptions.lua: the lab's settings, its own sidebar section
-- ("Group Finder Lab", through the plugin api). the live module's page, plus
-- a Results List page. the live module's own page stays untouched.
-------------------------------------------------------------------------------
local FOLDER, ns = ...
if EllesmereUI.HELD_BACK_ADDONS[FOLDER] then return end -- held back (EllesmereUIGroupFinder.lua)
local EUI = EllesmereUI
if not EUI.RegisterPlugin then return end

local PAGE_SEARCH = "Premade Search"
local PAGE_APPS = "Applications"

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")

    local AddAppsSections, AddListSections

    -----------------------------------------------------------------------
    -- Applications settings (greyed while the module is off)
    -----------------------------------------------------------------------
    local function APCfg() return ns.AppsCfg() end
    local function APGet(key, default)
        local c = APCfg()
        local v = c and c[key]
        if v == nil then return default end
        return v
    end
    local function APSet(key, val)
        local c = APCfg()
        if c then c[key] = val end
        ns.ApplyApplications()
    end
    local function ModOff() return not ns.Enabled() end
    local function APOff() return ModOff() or APGet("enabled", false) ~= true end
    local function APOffTip() return ModOff() and "Group Finder" or "Show Applications in Group Finder" end

    local function BuildSearchPage(pageName, parent, yOffset)
        local W = EUI.Widgets
        local y = yOffset
        local _, h

        if EUI.ClearContentHeader then EUI:ClearContentHeader() end
        parent._showRowDivider = true

        -- off until enabled; toggling reloads. beside it the note while the
        -- competing filter is loaded (show specialization lives in the
        -- window's group settings menu)
        local PGFLoaded = ns.Blocked
        local pgfNote = PGFLoaded()
            and { type = "label", text = EUI.COLOR_CODES.ERROR
                    .. EllesmereUI.L("Premade Groups Filter is loaded. Disable it to use the Group Finder.") .. "|r" }
            or EUI.BlankRowCfg()
        _, h = W:SectionHeader(parent, "GROUP FINDER", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Enable Group Finder",
              disabled = function() return PGFLoaded() and not ns.Enabled() end,
              disabledTooltip = "Premade Groups Filter", requireState = "disabled",
              tooltip = "Premade Groups search filters, group list and the M+ applications bar in the Dungeons & Raids window. Requires a reload.",
              getValue = function() return ns.Enabled() end,
              setValue = function(v)
                  v = v and true or false
                  if v == ns.Enabled() then return end
                  -- Only saved once the reload is confirmed.
                  EUI:ShowConfirmPopup({
                      title       = v and "Enable Group Finder" or "Disable Group Finder",
                      message     = v and "Your UI will reload to turn on the Group Finder."
                                      or "Your UI will reload to turn off the Group Finder.",
                      confirmText = "Reload Now",
                      cancelText  = "Cancel",
                      reload      = true,
                      onConfirm   = function() ns.SetEnabled(v) end,
                      onCancel    = function() EUI:RefreshPage() end,
                  })
              end },
            pgfNote);  y = y - h

        -- list look, sign-up options and icon size live in the group settings
        -- menu on the panel; the lab's list and its icons here
        y = AddListSections(parent, y)

        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y - yOffset)
    end

    -- applications: their own page, the reset buttons with them
    local function BuildAppsPage(parent, yOffset)
        local W = EUI.Widgets
        local y = yOffset
        local _, h
        if EUI.ClearContentHeader then EUI:ClearContentHeader() end
        parent._showRowDivider = true
        y = AddAppsSections(parent, y)
        _, h = W:Spacer(parent, y, 20); y = y - h
        parent:SetHeight(math.abs(y - yOffset))
        return math.abs(y - yOffset)
    end

    -- the lab's results list and its icons
    function AddListSections(parent, y)
        local W = EUI.Widgets
        local _, h
        _, h = W:SectionHeader(parent, "RESULTS LIST", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Title Text Size", min = 8, max = 20, step = 1,
              tooltip = "The group's title, the first line.",
              getValue = function() return ns.OwnListSize("titleSize") end,
              setValue = function(v) ns.SetOwnListSize("titleSize", v) end },
            { type = "toggle", text = "Colored Group Names",
              tooltip = "Green name when a group is new, Red name when you were declined or instance locked.",
              getValue = function() return ns.Cfg().nameColors ~= false end,
              setValue = function(v)
                  ns.Cfg().nameColors = v and true or false
                  if ns.Redecorate then ns.Redecorate() end
              end })
        y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Dungeon / Raid Text Size", min = 8, max = 20, step = 1,
              tooltip = "The dungeon or raid name, the second line.",
              getValue = function() return ns.OwnListSize("nameSize") end,
              setValue = function(v) ns.SetOwnListSize("nameSize", v) end },
            { type = "slider", text = "Activity Text Size", min = 8, max = 20, step = 1,
              tooltip = "The playstyle and region tag, the third line.",
              getValue = function() return ns.OwnListSize("lineSize") end,
              setValue = function(v) ns.SetOwnListSize("lineSize", v) end })
        y = y - h
        _, h = W:DualRow(parent, y,
            { type = "slider", text = "Row Height", min = 20, max = 64, step = 1,
              tooltip = "How tall each row is. Lines that no longer fit drop off from the bottom: the playstyle line first, then the dungeon / raid name (its short name then sits ahead of the title).",
              getValue = function() return ns.OwnListRowHeight() end,
              setValue = function(v) ns.SetOwnListRowHeight(v) end },
            EUI.BlankRowCfg())
        y = y - h

        _, h = W:SectionHeader(parent, "MYTHIC+", y); y = y - h
        _, h = W:DualRow(parent, y,
            { type = "toggle", text = "Raider.IO Rating Colors",
              tooltip = "Colours the leader's rating with Raider.IO's score colours. Off, the game's own rating colours.",
              disabled = function() return not (RaiderIO and RaiderIO.GetScoreColor) end,
              disabledTooltip = "Raider.IO",
              getValue = function() return ns.Cfg().rioRatingColors ~= false end,
              setValue = function(v)
                  ns.Cfg().rioRatingColors = v and true or false
                  if ns.Redecorate then ns.Redecorate() end
              end },
            { type = "slider", text = "Rating Text Size", min = 8, max = 20, step = 1,
              tooltip = "The leader's Mythic+ rating beside the role icons.",
              getValue = function() return ns.OwnListSize("scoreSize") end,
              setValue = function(v) ns.SetOwnListSize("scoreSize", v) end })
        y = y - h

        _, h = W:SectionHeader(parent, "DISPLAY", y); y = y - h
        local function Circle() return ns.OwnListGet("iconShape") ~= "square" end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Icon Shape",
              tooltip = "The members' icons: round like the game's, or square. Spec icons or class colours with the role on top (Show Specialization in the Group Settings menu).",
              values = { circle = "Circle", square = "Square" }, order = { "circle", "square" },
              getValue = function() return ns.OwnListGet("iconShape") end,
              setValue = function(v) ns.SetOwnListValue("iconShape", v); EUI:RefreshPage(true) end },
            { type = "slider", text = "Role Icon Size", min = 100, max = 160, step = 5,
              tooltip = "Size of the role and specialization icons in the group list.",
              getValue = function() return tonumber(ns.Cfg().iconSize) or ns.DEFAULTS.iconSize end,
              setValue = function(v)
                  ns.Cfg().iconSize = v
                  if ns.Redecorate then ns.Redecorate() end
              end })
        y = y - h
        local texValues, texOrder = EUI.GetBorderTextureDropdown()
        local borderRow
        borderRow, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Border Style",
              tooltip = "The border around square icons.",
              values = texValues, order = texOrder,
              disabled = Circle, disabledTooltip = "Icon Shape: Square",
              getValue = function() return ns.OwnListGet("borderTexture") end,
              setValue = function(v)
                  -- a new style starts on its own colour
                  ns.SetOwnListValue("borderColor", nil)
                  ns.SetOwnListValue("borderTexture", v)
                  EUI:RefreshPage(true)
              end },
            { type = "slider", text = "Border Size", min = 0, max = 4, step = 1,
              tooltip = "In pixels. 0 for no border. Round icons get a ring.",
              getValue = function() return tonumber(ns.OwnListGet("borderSize")) or 0 end,
              setValue = function(v) ns.SetOwnListValue("borderSize", v) end })
        y = y - h
        do
            -- border colour swatch beside the size slider
            local rgn = borderRow and borderRow._rightRegion
            if rgn and EUI.BuildColorSwatch then
                local swatch, update = EUI.BuildColorSwatch(rgn, rgn:GetFrameLevel() + 5,
                    function()
                        local r, g, b = ns.OwnListBorderColor()
                        return r, g, b, 1
                    end,
                    function(r, g, b)
                        ns.SetOwnListValue("borderColor", { r = r, g = g, b = b })
                    end, false, 20)
                swatch:SetPoint("RIGHT", rgn._lastInline or rgn._control, "LEFT", -12, 0)
                rgn._lastInline = swatch
                if EUI.RegisterWidgetRefresh then EUI.RegisterWidgetRefresh(update) end
            end
        end
        _, h = W:DualRow(parent, y,
            { type = "dropdown", text = "Missing Role Icons",
              tooltip = "How open slots show the role the group still needs (Show Missing Roles in the Group Settings menu): the game's small greyed marks, or EllesmereUI's role icons.",
              values = { blizzard = "Blizzard", ellesmere = "EllesmereUI" }, order = { "blizzard", "ellesmere" },
              getValue = function() return ns.OwnListGet("missingIcons") end,
              setValue = function(v) ns.SetOwnListValue("missingIcons", v) end },
            { type = "toggle", text = "Row Art",
              tooltip = "The instance's art across the left half of each group, fading out to the right.",
              getValue = function() return ns.Cfg().cawfeeRowArt == true end,
              setValue = function(v)
                  ns.Cfg().cawfeeRowArt = v and true or false
                  if ns.LabRetagRows then ns.LabRetagRows() end
              end })
        y = y - h
        return y
    end

    local function ResetMessage(scope)
        if scope == "session" then return EllesmereUI.L("Reset the session application counts to zero?") end
        if scope == "account" then return EllesmereUI.L("Reset the account application counts to zero?") end
        return EllesmereUI.L("Reset the character application counts to zero?")
    end

    AddAppsSections = function(parent, y)
        local W = EUI.Widgets
        local _, h

        _, h = W:SectionHeader(parent, "APPLICATIONS", y); y = y - h

        local scopeValues = { session = "Session", character = "Character", account = "Account" }
        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Applications in Group Finder",
              tooltip="A bar at the top of the Dungeons & Raids sidebar counting your Mythic+ Group Finder applications and how they ended, each count inside its part of the bar. Other dungeon difficulties, raids, delves and other groups are not counted.",
              disabled=ModOff, disabledTooltip="Group Finder",
              getValue=function() return APGet("enabled", false) == true end,
              setValue=function(v) APSet("enabled", v and true or false); EUI:RefreshPage() end },
            { type="dropdown", text="Counts Shown",
              tooltip="Which totals the card shows. Hover the card for all three.",
              values=scopeValues, order={ "session", "character", "account" },
              disabled=APOff, disabledTooltip=APOffTip,
              getValue=function() return APGet("scope", "character") end,
              setValue=function(v) APSet("scope", v) end });  y = y - h

        -- Application Visibility: which results get a share of the bar, one
        -- checklist row per saved show* key (all on when unset).
        local VIS_LABEL = "Application Visibility"
        local VIS_ITEMS = {
            { key = "showAccepted",  label = "Accepted",  tooltip = "Invites you accepted." },
            { key = "showDeclined",  label = "Declined",  tooltip = "Declined by the leader, the group filled, or the application timed out." },
            { key = "showDelisted",  label = "Delisted",  tooltip = "The group was delisted before answering." },
            { key = "showCancelled", label = "Cancelled", tooltip = "You cancelled the application." },
        }
        -- Global search sees row labels and tooltips only, so this row's entry,
        -- registered before the row (the index keeps the first one), carries the
        -- checklist's names as search text; it is never shown.
        if EllesmereUI._RegisterSearchEntry then
            local words = {}
            for i = 1, #VIS_ITEMS do
                local label = VIS_ITEMS[i].label
                words[#words + 1] = label
                local loc = EllesmereUI.L(label)
                if loc ~= label then words[#words + 1] = loc end
            end
            local labelLoc = EllesmereUI.L(VIS_LABEL)
            EllesmereUI._RegisterSearchEntry(VIS_LABEL, labelLoc ~= VIS_LABEL and labelLoc or nil,
                table.concat(words, " "), EllesmereUI._buildingModule, EllesmereUI._buildingPage,
                parent._currentSection and parent._currentSection._sectionName)
        end

        -- Built-in textures, then SharedMedia's.
        local tex, names, order = ns.BarTextureTables()
        local texValues, texOrder = {}, {}
        for _, key in ipairs(order) do
            if key ~= "---" then texValues[key] = names[key] or key end
            texOrder[#texOrder + 1] = key
        end
        texValues._menuOpts = { itemHeight = 28, background = function(key) return tex[key] end }
        local visRow
        visRow, h = W:DualRow(parent, y,
            -- Placeholder: carries the label and its disabled look; the
            -- checklist below takes its place.
            { type="dropdown", text=VIS_LABEL,
              tooltip="Choose which application results show on the bar.",
              disabled=APOff, disabledTooltip=APOffTip,
              values={ __placeholder = "..." }, order={ "__placeholder" },
              getValue=function() return "__placeholder" end,
              setValue=function() end },
            { type="dropdown", text="Bar Texture", values=texValues, order=texOrder,
              disabled=APOff, disabledTooltip=APOffTip,
              getValue=function() return APGet("texture", "none") end,
              setValue=function(v) APSet("texture", v) end });  y = y - h

        if not EUI._prebuilding then
            local rgn = visRow._leftRegion
            if rgn._control then rgn._control:Hide() end
            local visDD, visDDRefresh = EUI.BuildVisOptsCBDropdown(
                rgn, 210, rgn:GetFrameLevel() + 2, VIS_ITEMS,
                function(key) return APGet(key, true) == true end,
                function(key, v) APSet(key, v and true or false) end,
                nil, nil, nil, nil, nil, { disabled = APOff, disabledTooltip = APOffTip })
            EUI.PanelPP.Point(visDD, "RIGHT", rgn, "RIGHT", -20, 0)
            rgn._control = visDD
            rgn._lastInline = nil
            EUI.RegisterWidgetRefresh(visDDRefresh)
        end

        _, h = W:DualRow(parent, y,
            { type="toggle", text="Show Title",
              tooltip="The \"M+ Applications\" title above the bar.",
              disabled=APOff, disabledTooltip=APOffTip,
              getValue=function() return APGet("showTitle", true) ~= false end,
              setValue=function(v) APSet("showTitle", v and true or false) end },
            EUI.BlankRowCfg());  y = y - h

        _, h = W:SectionHeader(parent, "RESET APPLICATION COUNTS", y); y = y - h
        local function Reset(label, scope)
            return function()
                EUI:ShowConfirmPopup({
                    title = label,
                    message = ResetMessage(scope),
                    confirmText = "Reset", cancelText = "Cancel",
                    onConfirm = function() ns.ResetApplications(scope) end,
                })
            end
        end
        -- The module's on state only changes with a reload, so build time is enough.
        local offOpts
        if ModOff() then
            local tip = EUI.DisabledTooltip("Group Finder")
            offOpts = { { disabled = true, tooltip = tip }, { disabled = true, tooltip = tip }, { disabled = true, tooltip = tip } }
        end
        _, h = W:WideTripleButton(parent, "Reset Session", "Reset Character", "Reset Account", y,
            Reset("Reset Session", "session"), Reset("Reset Character", "character"), Reset("Reset Account", "account"),
            nil, offOpts)
        y = y - h
        return y
    end

    EUI.RegisterPlugin(FOLDER, {
        label   = "Group Finder Lab",
        modules = { {
            key         = "GroupFinder",
            title       = "Group Finder",
            description = "Premade Groups search filters and our own filtered results list in the Dungeons & Raids window (lab build).",
            pages       = { PAGE_SEARCH, PAGE_APPS },
            buildPage   = function(pageName, parent, yOffset)
                if pageName == PAGE_APPS then return BuildAppsPage(parent, yOffset) end
                return BuildSearchPage(pageName, parent, yOffset)
            end,
            onReset     = function()
                ns.ResetSettings()
                if ns.Enabled() then
                    ns.Search_Layout()
                    ns.ApplyApplications()
                end
            end,
        } },
    })
end)
if IsLoggedIn() then initFrame:GetScript("OnEvent")(initFrame) end
