-- GuildManager UI
-- Three tabs: Log, Roster, Alts. Plain Wrath 3.3.5a frame API.
-- No OnKeyDown on Frames, no post-Wrath templates.

GuildManager = GuildManager or {}
GuildManager.UI = {}
local UI    = GuildManager.UI
local addon = GuildManager

-- =========================================================
-- Constants
-- =========================================================
local ROW_HEIGHT = 15
local ROW_COUNT  = 18

-- Per-column widths used by the Roster view (header + each row cell).
-- All values are pixels. The order here MUST match the header build order.
local COL_DEFS = {
    { key = "lvl",    label = "Lvl",         sort = "level",  width = 32  },
    { key = "name",   label = "Name",        sort = "name",   width = 130 },
    { key = "online", label = "Last Online", sort = "online", width = 110 },
    { key = "rank",   label = "Rank",        sort = "rank",   width = 110 },
    { key = "note",   label = "Note",        sort = "note",   width = 160 },
    { key = "onote",  label = "Officer Note",sort = "onote",  width = 180 },
}
local COL_GAP = 4

local BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local PANEL_BACKDROP = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local TYPE_COLOR = {
    SEEN    = "|cffaaaaaa",
    JOIN    = "|cff44ff44",
    LEAVE   = "|cffff5555",
    PROMOTE = "|cffaaff66",
    DEMOTE  = "|cffff8800",
    NOTE    = "|cffff77ff",
    ONOTE   = "|cffcc88ff",
    LEVEL   = "|cff66ccff",
}

local TYPE_LABEL = {
    SEEN    = "Initial",
    JOIN    = "Joined",
    LEAVE   = "Left",
    PROMOTE = "Promoted",
    DEMOTE  = "Demoted",
    NOTE    = "Public Note",
    ONOTE   = "Officer Note",
    LEVEL   = "Leveled",
}

local TYPE_ORDER = { "JOIN", "LEAVE", "LEVEL", "PROMOTE", "DEMOTE", "NOTE", "ONOTE", "SEEN" }

local CLASS_COLOR = {
    DEATHKNIGHT = "|cffc41f3b",
    DRUID       = "|cffff7d0a",
    HUNTER      = "|cffabd473",
    MAGE        = "|cff69ccf0",
    PALADIN     = "|cfff58cba",
    PRIEST      = "|cffffffff",
    ROGUE       = "|cfffff569",
    SHAMAN      = "|cff0070de",
    WARLOCK     = "|cff9482c9",
    WARRIOR     = "|cffc79c6e",
}

-- =========================================================
-- UI state
-- =========================================================
local activeView   = "LOG"   -- "LOG", "ROSTER", "ALTS", "MACROS"

-- Macros tab state
local CHANNEL_OPTIONS = { "1","2","3","4","5","6","7","8","9",
                         "GUILD","OFFICER","SAY","PARTY","RAID","YELL" }
local macroSelectedChannel = "GUILD"

-- Log view
local typeFilters = {
    SEEN = true, JOIN = true, LEAVE = true,
    PROMOTE = true, DEMOTE = true,
    NOTE = true, ONOTE = true, LEVEL = true,
}
local logSearchText = ""
local showLineNumbers = true

-- Roster view
local rosterShowOffline    = true
local rosterPlayerSearch   = ""
local rosterNoteSearch     = ""
local rosterSortBy         = "name"   -- "level" | "name" | "online" | "rank"
local rosterSortReverse    = false
local groupAltsWithMain    = false

local frame  -- main frame, lazy-built

-- =========================================================
-- Helpers
-- =========================================================
local function colorize(typeKey, text)
    return (TYPE_COLOR[typeKey] or "|cffffffff") .. text .. "|r"
end

local function fmtDateLong(epoch)
    if not epoch then return "?" end
    -- 02 Nov '26 20:01
    return date("%d %b '%y %H:%M", epoch)
end

local function fmtSince(epoch)
    if not epoch then return "?" end
    local d = time() - epoch
    if d < 60     then return "online" end
    if d < 3600   then return ("%d min"):format(math.floor(d / 60)) end
    if d < 86400  then return ("%d hrs"):format(math.floor(d / 3600)) end
    if d < 604800 then return ("%d days"):format(math.floor(d / 86400)) end
    if d < 2592000 then
        local weeks = math.floor(d / 604800)
        local days = math.floor((d - weeks * 604800) / 86400)
        if days > 0 then
            return ("%d wks, %d days"):format(weeks, days)
        end
        return ("%d wks"):format(weeks)
    end
    if d < 31536000 then
        local months = math.floor(d / 2592000)
        local days = math.floor((d - months * 2592000) / 86400)
        if days > 0 then
            return ("%d mos, %d days"):format(months, days)
        end
        return ("%d mos"):format(months)
    end
    local years = math.floor(d / 31536000)
    return ("%d yrs"):format(years)
end

local function lastSeenColor(epoch, online)
    if online then return "|cff44ff44" end
    if not epoch then return "|cff888888" end
    local d = time() - epoch
    if d < 86400   then return "|cff99ff99" end  -- < 1 day
    if d < 604800  then return "|cffffffff" end  -- < 7 days
    if d < 2592000 then return "|cffffff66" end  -- < 30 days
    if d < 7776000 then return "|cffffaa00" end  -- < 90 days
    return "|cffff4444"
end

local function classColor(classFile, name)
    return (CLASS_COLOR[classFile or ""] or "|cffeeeeee") .. (name or "?") .. "|r"
end

local function trimName(s, maxlen)
    if not s then return "" end
    if #s <= maxlen then return s end
    return s:sub(1, maxlen - 1) .. "..."
end

local function lowerSafe(s) return (s or ""):lower() end

-- =========================================================
-- Window build (lazy)
-- =========================================================
local function build()
    if frame then return frame end

    local f = CreateFrame("Frame", "GuildManagerMainFrame", UIParent)
    f:SetSize(820, 480)
    f:SetPoint("CENTER")
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0, 0, 0, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- ===== Header =====
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFFFFCC00Guild Manager|r")
    f.title = title

    -- Author credit (small, muted, anchored to the title)
    local author = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    author:SetPoint("TOP", title, "BOTTOM", 0, -1)
    author:SetText("|cff888888By Veronica-Vasilieva|r")
    f.author = author

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", author, "BOTTOM", 0, -1)
    f.subtitle = subtitle

    local rightHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rightHeader:SetPoint("TOPRIGHT", -34, -22)
    rightHeader:SetJustifyH("RIGHT")
    f.rightHeader = rightHeader

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    -- ===== Tabs =====
    f.tabButtons = {}
    local function makeViewBtn(label, viewKey)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(86, 22)
        b:SetText(label)
        b:SetScript("OnClick", function()
            activeView = viewKey
            UI:Refresh()
        end)
        f.tabButtons[viewKey] = b
        return b
    end
    f.tabLog    = makeViewBtn("Log",    "LOG")
    f.tabRoster = makeViewBtn("Roster", "ROSTER")
    f.tabAlts   = makeViewBtn("Alts",   "ALTS")
    f.tabMacros = makeViewBtn("Macros", "MACROS")
    f.tabLog:SetPoint("TOPLEFT", 16, -48)
    f.tabRoster:SetPoint("TOPLEFT", f.tabLog,    "TOPRIGHT", 4, 0)
    f.tabAlts:SetPoint("TOPLEFT",   f.tabRoster, "TOPRIGHT", 4, 0)
    f.tabMacros:SetPoint("TOPLEFT", f.tabAlts,   "TOPRIGHT", 4, 0)

    -- ===== Log view controls =====
    -- Search box
    local logSearch = CreateFrame("EditBox", "GuildManagerLogSearch", f, "InputBoxTemplate")
    logSearch:SetSize(220, 20)
    logSearch:SetPoint("TOPLEFT", f.tabLog, "BOTTOMLEFT", 8, -8)
    logSearch:SetAutoFocus(false)
    logSearch:SetScript("OnTextChanged", function(self)
        logSearchText = self:GetText() or ""
        UI:Refresh()
    end)
    logSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    logSearch:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.logSearch = logSearch

    local logSearchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logSearchLabel:SetPoint("BOTTOMLEFT", logSearch, "TOPLEFT", -4, 1)
    logSearchLabel:SetText("Search Filter")
    f.logSearchLabel = logSearchLabel

    -- Filter side panel
    f.filterPanel = CreateFrame("Frame", nil, f)
    f.filterPanel:SetSize(150, 320)
    f.filterPanel:SetPoint("TOPRIGHT", -18, -100)
    f.filterPanel:SetBackdrop(PANEL_BACKDROP)
    f.filterPanel:SetBackdropColor(0, 0, 0, 0.6)

    local fpTitle = f.filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fpTitle:SetPoint("TOP", 0, -8)
    fpTitle:SetText("Display Changes")

    f.filterChecks = {}
    local cbY = -30
    for _, key in ipairs(TYPE_ORDER) do
        local cb = CreateFrame("CheckButton", "GuildManagerFC_" .. key, f.filterPanel, "OptionsBaseCheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", 10, cbY)
        cb:SetChecked(typeFilters[key])
        local labelKey = key
        cb:SetScript("OnClick", function(self)
            typeFilters[labelKey] = self:GetChecked() and true or false
            UI:Refresh()
        end)
        local lbl = f.filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(colorize(key, TYPE_LABEL[key] or key))
        f.filterChecks[key] = cb
        cbY = cbY - 22
    end

    -- Check all / uncheck all
    local checkAll = CreateFrame("Button", nil, f.filterPanel, "UIPanelButtonTemplate")
    checkAll:SetSize(60, 20)
    checkAll:SetText("All")
    checkAll:SetPoint("BOTTOMLEFT", 10, 10)
    checkAll:SetScript("OnClick", function()
        for _, k in ipairs(TYPE_ORDER) do typeFilters[k] = true end
        for _, cb in pairs(f.filterChecks) do cb:SetChecked(true) end
        UI:Refresh()
    end)
    local clearAll = CreateFrame("Button", nil, f.filterPanel, "UIPanelButtonTemplate")
    clearAll:SetSize(60, 20)
    clearAll:SetText("None")
    clearAll:SetPoint("BOTTOMRIGHT", -10, 10)
    clearAll:SetScript("OnClick", function()
        for _, k in ipairs(TYPE_ORDER) do typeFilters[k] = false end
        for _, cb in pairs(f.filterChecks) do cb:SetChecked(false) end
        UI:Refresh()
    end)

    -- ===== Roster view controls =====
    f.rosterShowOfflineCB = CreateFrame("CheckButton", "GuildManagerShowOffline", f, "OptionsBaseCheckButtonTemplate")
    f.rosterShowOfflineCB:SetSize(20, 20)
    f.rosterShowOfflineCB:SetPoint("TOPLEFT", f.tabLog, "BOTTOMLEFT", 0, -8)
    f.rosterShowOfflineCB:SetChecked(rosterShowOffline)
    f.rosterShowOfflineCB:SetScript("OnClick", function(self)
        rosterShowOffline = self:GetChecked() and true or false
        UI:Refresh()
    end)
    f.rosterShowOfflineLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.rosterShowOfflineLabel:SetPoint("LEFT", f.rosterShowOfflineCB, "RIGHT", 2, 0)
    f.rosterShowOfflineLabel:SetText("Show Offline")

    local rosterPSearch = CreateFrame("EditBox", "GuildManagerRosterPSearch", f, "InputBoxTemplate")
    rosterPSearch:SetSize(140, 20)
    rosterPSearch:SetPoint("LEFT", f.rosterShowOfflineLabel, "RIGHT", 100, 0)
    rosterPSearch:SetAutoFocus(false)
    rosterPSearch:SetScript("OnTextChanged", function(self)
        rosterPlayerSearch = self:GetText() or ""
        UI:Refresh()
    end)
    rosterPSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    rosterPSearch:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.rosterPSearch = rosterPSearch

    local rosterPSearchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterPSearchLabel:SetPoint("BOTTOMLEFT", rosterPSearch, "TOPLEFT", -4, 1)
    rosterPSearchLabel:SetText("Player Search")
    f.rosterPSearchLabel = rosterPSearchLabel

    local rosterNSearch = CreateFrame("EditBox", "GuildManagerRosterNSearch", f, "InputBoxTemplate")
    rosterNSearch:SetSize(140, 20)
    rosterNSearch:SetPoint("LEFT", rosterPSearch, "RIGHT", 80, 0)
    rosterNSearch:SetAutoFocus(false)
    rosterNSearch:SetScript("OnTextChanged", function(self)
        rosterNoteSearch = self:GetText() or ""
        UI:Refresh()
    end)
    rosterNSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    rosterNSearch:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.rosterNSearch = rosterNSearch

    local rosterNSearchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterNSearchLabel:SetPoint("BOTTOMLEFT", rosterNSearch, "TOPLEFT", -4, 1)
    rosterNSearchLabel:SetText("Note Search")
    f.rosterNSearchLabel = rosterNSearchLabel

    -- Column header strip (Roster mode only)
    f.colHeader = CreateFrame("Frame", nil, f)
    f.colHeader:SetHeight(20)
    f.colHeader:SetPoint("TOPLEFT", 16, -106)
    f.colHeader:SetPoint("RIGHT", -18, 0)

    local function makeHeader(def)
        local b = CreateFrame("Button", nil, f.colHeader)
        b:SetSize(def.width, 20)
        b:SetNormalFontObject("GameFontNormal")
        b:SetHighlightFontObject("GameFontHighlight")
        b:SetText(def.label)
        b:GetFontString():SetJustifyH("LEFT")
        b:GetFontString():ClearAllPoints()
        b:GetFontString():SetPoint("LEFT", b, "LEFT", 0, 0)
        b:GetFontString():SetWidth(def.width)
        local sortKey = def.sort
        b:SetScript("OnClick", function()
            if rosterSortBy == sortKey then
                rosterSortReverse = not rosterSortReverse
            else
                rosterSortBy = sortKey
                rosterSortReverse = false
            end
            UI:Refresh()
        end)
        return b
    end

    f.colHeaderBtns = {}
    local prev
    for _, def in ipairs(COL_DEFS) do
        local b = makeHeader(def)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", COL_GAP, 0)
        else
            b:SetPoint("LEFT", 0, 0)
        end
        f.colHeaderBtns[def.key] = b
        prev = b
    end

    -- ===== List panel + scroll =====
    f.listPanel = CreateFrame("Frame", nil, f)
    f.listPanel:SetPoint("TOPLEFT", 16, -130)
    f.listPanel:SetPoint("BOTTOMRIGHT", -180, 56)
    f.listPanel:SetBackdrop(PANEL_BACKDROP)
    f.listPanel:SetBackdropColor(0, 0, 0, 0.6)

    -- For Alts view we don't need the filter side panel, so list expands.
    local scroll = CreateFrame("ScrollFrame", "GuildManagerListScroll", f.listPanel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() UI:Refresh() end)
    end)
    f.scroll = scroll

    -- Row pool
    -- Single-string rows used by Log + Alts + Macros views.
    f.rows = {}
    -- Per-column rows used by the Roster view (one FontString per column).
    f.rowCells = {}
    -- Per-row buttons used by the Macros view (Send + Delete on each row).
    f.rowMacroBtns = {}
    for i = 1, ROW_COUNT do
        local rowY = -((i - 1) * ROW_HEIGHT) - 2

        -- Single-string row (Log / Alts / Macros text portion)
        local row = f.listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, rowY)
        row:SetPoint("RIGHT",   scroll, "RIGHT",  -4, 0)
        row:SetHeight(ROW_HEIGHT)
        row:SetJustifyH("LEFT")
        f.rows[i] = row

        -- Per-column cells (Roster).
        local cells = {}
        local prevCell
        for _, def in ipairs(COL_DEFS) do
            local fs = f.listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWidth(def.width)
            fs:SetHeight(ROW_HEIGHT)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            if prevCell then
                fs:SetPoint("LEFT", prevCell, "RIGHT", COL_GAP, 0)
            else
                fs:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, rowY)
            end
            cells[def.key] = fs
            prevCell = fs
        end
        f.rowCells[i] = cells

        -- Per-row Macros buttons (Send + Delete) anchored to the right.
        local delBtn = CreateFrame("Button", nil, f.listPanel, "UIPanelButtonTemplate")
        delBtn:SetSize(46, ROW_HEIGHT - 1)
        delBtn:SetText("Del")
        delBtn:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)
        delBtn:SetPoint("TOP",   scroll, "TOP",    0, rowY)
        delBtn:Hide()

        local sendBtn = CreateFrame("Button", nil, f.listPanel, "UIPanelButtonTemplate")
        sendBtn:SetSize(50, ROW_HEIGHT - 1)
        sendBtn:SetText("Send")
        sendBtn:SetPoint("RIGHT", delBtn, "LEFT", -3, 0)
        sendBtn:Hide()

        f.rowMacroBtns[i] = { send = sendBtn, del = delBtn }
    end

    -- ===== Alts view inputs =====
    f.altInputAlt  = CreateFrame("EditBox", "GuildManagerAltInput",  f, "InputBoxTemplate")
    f.altInputMain = CreateFrame("EditBox", "GuildManagerMainInput", f, "InputBoxTemplate")
    f.altInputAlt:SetSize(120, 20)
    f.altInputMain:SetSize(120, 20)
    f.altInputAlt:SetPoint("BOTTOMLEFT",  24, 22)
    f.altInputMain:SetPoint("LEFT", f.altInputAlt, "RIGHT", 12, 0)
    f.altInputAlt:SetAutoFocus(false)
    f.altInputMain:SetAutoFocus(false)
    f.altInputAlt:SetScript("OnEscapePressed",  f.altInputAlt.ClearFocus)
    f.altInputMain:SetScript("OnEscapePressed", f.altInputMain.ClearFocus)

    f.altInputAltLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.altInputAltLabel:SetPoint("BOTTOMLEFT", f.altInputAlt, "TOPLEFT", 0, 2)
    f.altInputAltLabel:SetText("Alt name")
    f.altInputMainLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.altInputMainLabel:SetPoint("BOTTOMLEFT", f.altInputMain, "TOPLEFT", 0, 2)
    f.altInputMainLabel:SetText("Main name")

    f.altBtnSet = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.altBtnSet:SetSize(60, 22)
    f.altBtnSet:SetText("Set")
    f.altBtnSet:SetPoint("LEFT", f.altInputMain, "RIGHT", 8, 0)
    f.altBtnSet:SetScript("OnClick", function()
        local a = f.altInputAlt:GetText()
        local m = f.altInputMain:GetText()
        if a and a ~= "" and m and m ~= "" then
            local ok, msg = addon:SetAlt(a, m)
            print("|cFFFFCC00Guild Manager|r: " .. tostring(msg))
            f.altInputAlt:SetText("")
            f.altInputMain:SetText("")
            UI:Refresh()
        end
    end)

    f.altBtnUnset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.altBtnUnset:SetSize(60, 22)
    f.altBtnUnset:SetText("Unset")
    f.altBtnUnset:SetPoint("LEFT", f.altBtnSet, "RIGHT", 4, 0)
    f.altBtnUnset:SetScript("OnClick", function()
        local a = f.altInputAlt:GetText()
        if a and a ~= "" then
            local ok, msg = addon:SetAlt(a, nil)
            print("|cFFFFCC00Guild Manager|r: " .. tostring(msg))
            f.altInputAlt:SetText("")
            UI:Refresh()
        end
    end)

    -- ===== Macros view: compose form =====
    -- Message label + multi-line EditBox bg
    f.macroMsgLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroMsgLabel:SetPoint("TOPLEFT", f.tabLog, "BOTTOMLEFT", 0, -6)
    f.macroMsgLabel:SetText("Message  |cff888888(saves account-wide, max ~255 chars)|r")

    f.macroMsgBg = CreateFrame("Frame", nil, f)
    f.macroMsgBg:SetPoint("TOPLEFT",  f.macroMsgLabel, "BOTTOMLEFT", 0, -2)
    f.macroMsgBg:SetSize(560, 44)
    f.macroMsgBg:SetBackdrop(PANEL_BACKDROP)
    f.macroMsgBg:SetBackdropColor(0, 0, 0, 0.7)
    f.macroMsgBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    f.macroMsg = CreateFrame("EditBox", "GuildManagerMacroMsg", f.macroMsgBg)
    f.macroMsg:SetFontObject("ChatFontSmall")
    f.macroMsg:SetAutoFocus(false)
    f.macroMsg:SetMultiLine(true)
    f.macroMsg:SetMaxLetters(255)
    f.macroMsg:SetPoint("TOPLEFT",     6, -4)
    f.macroMsg:SetPoint("BOTTOMRIGHT", -6, 4)
    f.macroMsg:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Channel selector label
    f.macroChanLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroChanLabel:SetPoint("TOPLEFT", f.macroMsgBg, "BOTTOMLEFT", 0, -6)
    f.macroChanLabel:SetText("Channel:")

    -- Row of channel buttons (1-9, then named)
    f.macroChanBtns = {}
    local prevChanBtn
    for _, opt in ipairs(CHANNEL_OPTIONS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        local width = #opt > 2 and 56 or 26
        b:SetSize(width, 20)
        b:SetText(opt)
        if prevChanBtn then
            b:SetPoint("LEFT", prevChanBtn, "RIGHT", 2, 0)
        else
            b:SetPoint("LEFT", f.macroChanLabel, "RIGHT", 6, 0)
        end
        local choice = opt
        b:SetScript("OnClick", function()
            macroSelectedChannel = choice
            UI:Refresh()
        end)
        f.macroChanBtns[opt] = b
        prevChanBtn = b
    end

    -- Save button
    f.macroSaveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.macroSaveBtn:SetSize(80, 22)
    f.macroSaveBtn:SetText("Save Macro")
    f.macroSaveBtn:SetPoint("TOPLEFT", f.macroChanLabel, "BOTTOMLEFT", 0, -28)
    f.macroSaveBtn:SetScript("OnClick", function()
        local text = f.macroMsg:GetText() or ""
        local ok, msg = addon:AddMacro(macroSelectedChannel, text)
        if ok then
            print("|cFFFFCC00Guild Manager|r: macro saved.")
            f.macroMsg:SetText("")
            f.macroMsg:ClearFocus()
        else
            print("|cFFFFCC00Guild Manager|r: " .. tostring(msg))
        end
        UI:Refresh()
    end)

    -- ===== Footer (Log mode) =====
    f.numberedCB = CreateFrame("CheckButton", "GuildManagerNumberedCB", f, "OptionsBaseCheckButtonTemplate")
    f.numberedCB:SetSize(20, 20)
    f.numberedCB:SetPoint("BOTTOMLEFT", 24, 22)
    f.numberedCB:SetChecked(showLineNumbers)
    f.numberedCB:SetScript("OnClick", function(self)
        showLineNumbers = self:GetChecked() and true or false
        UI:Refresh()
    end)
    f.numberedLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.numberedLabel:SetPoint("LEFT", f.numberedCB, "RIGHT", 2, 0)
    f.numberedLabel:SetText("Numbered Lines")

    f.clearLogBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.clearLogBtn:SetSize(90, 22)
    f.clearLogBtn:SetText("Clear Log")
    f.clearLogBtn:SetPoint("BOTTOMRIGHT", f.listPanel, "BOTTOMRIGHT", -4, -28)
    f.clearLogBtn:SetScript("OnClick", function()
        addon:ClearLog()
        UI:Refresh()
    end)

    -- Roster mode footer
    f.groupAltsCB = CreateFrame("CheckButton", "GuildManagerGroupAltsCB", f, "OptionsBaseCheckButtonTemplate")
    f.groupAltsCB:SetSize(20, 20)
    f.groupAltsCB:SetPoint("BOTTOMLEFT", 24, 22)
    f.groupAltsCB:SetChecked(groupAltsWithMain)
    f.groupAltsCB:SetScript("OnClick", function(self)
        groupAltsWithMain = self:GetChecked() and true or false
        UI:Refresh()
    end)
    f.groupAltsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.groupAltsLabel:SetPoint("LEFT", f.groupAltsCB, "RIGHT", 2, 0)
    f.groupAltsLabel:SetText("Group Alts With Main")

    -- Status text (bottom right of list area)
    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMRIGHT", f.listPanel, "TOPRIGHT", 0, 2)

    frame = f
    return f
end

-- =========================================================
-- Roster row collection + sorting
-- =========================================================
local function collectRosterRows()
    local guild = addon:GetCurrentGuild()
    local rows = {}
    if not guild then return rows, 0, 0 end

    local online, total = 0, 0
    local needle = lowerSafe(rosterPlayerSearch)
    local noteNeedle = lowerSafe(rosterNoteSearch)

    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, _, level, _, _, note, officerNote, isOnline, _, classFile
            = GetGuildRosterInfo(i)
        if name and name ~= "" then
            total = total + 1
            if isOnline then online = online + 1 end

            local pass = true
            if not rosterShowOffline and not isOnline then pass = false end
            if pass and needle ~= "" and not lowerSafe(name):find(needle, 1, true) then
                pass = false
            end
            if pass and noteNeedle ~= "" then
                local nMatch = (note    and lowerSafe(note):find(noteNeedle, 1, true))
                            or (officerNote and lowerSafe(officerNote):find(noteNeedle, 1, true))
                if not nMatch then pass = false end
            end

            if pass then
                local rec = guild.members[name]
                table.insert(rows, {
                    name        = name,
                    rank        = rank or "",
                    level       = level or 0,
                    online      = isOnline and true or false,
                    note        = note or "",
                    officerNote = officerNote or "",
                    classFile   = classFile or (rec and rec.classFile) or "",
                    joinDate    = rec and rec.joinDate or "?",
                    lastSeen    = isOnline and time() or (rec and rec.lastOnline) or nil,
                    main        = guild.alts[name],
                    altsList    = nil,  -- filled below if needed
                })
            end
        end
    end

    -- Sort
    local key = rosterSortBy
    local rev = rosterSortReverse
    table.sort(rows, function(a, b)
        local av, bv
        if     key == "level"  then av, bv = a.level, b.level
        elseif key == "name"   then av, bv = a.name:lower(), b.name:lower()
        elseif key == "online" then
            -- Online first; among offline, more-recent first
            local at = a.online and math.huge or (a.lastSeen or 0)
            local bt = b.online and math.huge or (b.lastSeen or 0)
            av, bv = at, bt
            -- Default direction for "online" sort: most recent first
            if not rev then return at > bt else return at < bt end
        elseif key == "rank"   then av, bv = a.rank:lower(), b.rank:lower()
        elseif key == "note"   then av, bv = a.note:lower(), b.note:lower()
        elseif key == "onote"  then av, bv = a.officerNote:lower(), b.officerNote:lower()
        else av, bv = a.name:lower(), b.name:lower() end
        if av == bv then return a.name:lower() < b.name:lower() end
        if rev then return av > bv else return av < bv end
    end)

    -- Group alts with mains
    if groupAltsWithMain then
        -- Build map: main -> {alts}
        local byMain = {}
        for _, r in ipairs(rows) do
            if r.main then
                byMain[r.main] = byMain[r.main] or {}
                table.insert(byMain[r.main], r)
            end
        end
        local newRows = {}
        local seen = {}
        for _, r in ipairs(rows) do
            if not seen[r.name] then
                if r.main then
                    -- skip, will be added under main
                else
                    table.insert(newRows, r)
                    seen[r.name] = true
                    local kids = byMain[r.name]
                    if kids then
                        for _, alt in ipairs(kids) do
                            if not seen[alt.name] then
                                table.insert(newRows, alt)
                                seen[alt.name] = true
                            end
                        end
                    end
                end
            end
        end
        -- Append any orphan alts whose main isn't in current roster
        for _, r in ipairs(rows) do
            if not seen[r.name] then
                table.insert(newRows, r)
                seen[r.name] = true
            end
        end
        rows = newRows
    end

    return rows, online, total
end

-- =========================================================
-- Log row collection
-- =========================================================
local function collectLogRows()
    local guild = addon:GetCurrentGuild()
    local rows = {}
    if not guild then return rows, 0 end

    local needle = lowerSafe(logSearchText)
    local total = #guild.log
    for i = total, 1, -1 do  -- newest first
        local e = guild.log[i]
        if e and typeFilters[e.type] then
            if needle ~= "" then
                local hay = lowerSafe((e.who or "") .. " " .. (e.details or "") .. " " .. (TYPE_LABEL[e.type] or e.type))
                if hay:find(needle, 1, true) then
                    table.insert(rows, { entry = e, n = i })
                end
            else
                table.insert(rows, { entry = e, n = i })
            end
        end
    end
    return rows, total
end

-- =========================================================
-- Macros rows
-- =========================================================
local function collectMacrosRows()
    local rows = {}
    local list = addon:GetMacros()
    for i, m in ipairs(list) do
        table.insert(rows, { index = i, channel = m.channel, text = m.text })
    end
    return rows
end

-- =========================================================
-- Alts rows
-- =========================================================
local function collectAltsRows()
    local guild = addon:GetCurrentGuild()
    local rows = {}
    if not guild then return rows end
    for alt, main in pairs(guild.alts) do
        table.insert(rows, { alt = alt, main = main })
    end
    table.sort(rows, function(a, b)
        if a.main == b.main then return a.alt < b.alt end
        return a.main < b.main
    end)
    return rows
end

-- =========================================================
-- Refresh
-- =========================================================
local function setVis(widget, visible)
    if visible then widget:Show() else widget:Hide() end
end

function UI:Refresh()
    local f = frame
    if not f or not f:IsShown() then return end

    local logMode    = (activeView == "LOG")
    local rosterMode = (activeView == "ROSTER")
    local altsMode   = (activeView == "ALTS")
    local macrosMode = (activeView == "MACROS")

    -- Toggle Log controls
    setVis(f.logSearch,         logMode)
    setVis(f.logSearchLabel,    logMode)
    setVis(f.filterPanel,       logMode)
    setVis(f.numberedCB,        logMode)
    setVis(f.numberedLabel,     logMode)
    setVis(f.clearLogBtn,       logMode)

    -- Toggle Roster controls
    setVis(f.rosterShowOfflineCB,    rosterMode)
    setVis(f.rosterShowOfflineLabel, rosterMode)
    setVis(f.rosterPSearch,          rosterMode)
    setVis(f.rosterPSearchLabel,     rosterMode)
    setVis(f.rosterNSearch,          rosterMode)
    setVis(f.rosterNSearchLabel,     rosterMode)
    setVis(f.colHeader,              rosterMode)
    setVis(f.groupAltsCB,            rosterMode)
    setVis(f.groupAltsLabel,         rosterMode)

    -- Toggle Alts controls
    setVis(f.altInputAlt,       altsMode)
    setVis(f.altInputMain,      altsMode)
    setVis(f.altInputAltLabel,  altsMode)
    setVis(f.altInputMainLabel, altsMode)
    setVis(f.altBtnSet,         altsMode)
    setVis(f.altBtnUnset,       altsMode)

    -- Toggle Macros controls
    setVis(f.macroMsgLabel,  macrosMode)
    setVis(f.macroMsgBg,     macrosMode)
    setVis(f.macroChanLabel, macrosMode)
    setVis(f.macroSaveBtn,   macrosMode)
    for _, b in pairs(f.macroChanBtns or {}) do setVis(b, macrosMode) end

    -- List panel sizing: full width when no side filter panel showing.
    -- Macros mode also pushes the list lower to make room for the compose form.
    f.listPanel:ClearAllPoints()
    if macrosMode then
        f.listPanel:SetPoint("TOPLEFT", 16, -200)
    else
        f.listPanel:SetPoint("TOPLEFT", 16, -130)
    end
    if logMode then
        f.listPanel:SetPoint("BOTTOMRIGHT", -180, 56)
    else
        f.listPanel:SetPoint("BOTTOMRIGHT", -18, 56)
    end

    -- Tab highlight
    for view, b in pairs(f.tabButtons) do
        if view == activeView then b:LockHighlight() else b:UnlockHighlight() end
    end

    -- Subtitle + header text per view
    local key = addon:GetCurrentGuildKey()
    local guildLabel = key and key:gsub("::", " / ") or "(not in a guild)"
    if logMode then
        f.subtitle:SetText("|cFFFFCC00Guild Roster Event Log|r   " .. guildLabel)
    elseif rosterMode then
        f.subtitle:SetText("|cFFFFCC00Guild Roster|r   " .. guildLabel)
    elseif macrosMode then
        f.subtitle:SetText("|cFFFFCC00Saved Macros|r   account-wide")
    else
        f.subtitle:SetText("|cFFFFCC00Alts|r   " .. guildLabel)
    end

    -- Body
    local data, total, onlineCount = {}, 0, 0
    if logMode then
        data, total = collectLogRows()
        f.rightHeader:SetText(("Total Entries: |cffffffff%d|r"):format(total))
    elseif rosterMode then
        local rosterRows
        rosterRows, onlineCount, total = collectRosterRows()
        data = rosterRows
        f.rightHeader:SetText(("|cffffffff%d|r / %d Online"):format(onlineCount, total))
    elseif macrosMode then
        data = collectMacrosRows()
        f.rightHeader:SetText(("|cffffffff%d|r macros  -  channel: |cffffcc00%s|r"):format(
            #data, macroSelectedChannel))
    else
        data = collectAltsRows()
        f.rightHeader:SetText(("|cffffffff%d|r mappings"):format(#data))
    end

    -- Highlight the currently selected channel button in Macros mode.
    if macrosMode then
        for opt, b in pairs(f.macroChanBtns) do
            if opt == macroSelectedChannel then b:LockHighlight() else b:UnlockHighlight() end
        end
    end

    local count = #data
    FauxScrollFrame_Update(f.scroll, count, ROW_COUNT, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(f.scroll)

    -- Header sort arrow indicator
    if rosterMode then
        local mark = rosterSortReverse and "  v" or "  ^"
        for _, def in ipairs(COL_DEFS) do
            local label = def.label
            if rosterSortBy == def.sort then label = label .. mark end
            f.colHeaderBtns[def.key]:SetText(label)
        end
    end

    local function hideCells(i)
        local cells = f.rowCells[i]
        if cells then
            for _, c in pairs(cells) do c:SetText(""); c:Hide() end
        end
    end
    local function hideSingle(i)
        local row = f.rows[i]
        if row then row:SetText(""); row:Hide() end
    end
    local function hideMacroBtns(i)
        local btns = f.rowMacroBtns[i]
        if btns then btns.send:Hide(); btns.del:Hide() end
    end

    for i = 1, ROW_COUNT do
        local idx = i + offset
        local item = data[idx]

        if not item then
            hideSingle(i)
            hideCells(i)
            hideMacroBtns(i)
        elseif logMode then
            hideCells(i)
            hideMacroBtns(i)
            local row = f.rows[i]
            -- Restore default right anchor (macros mode may have shortened it)
            row:SetPoint("RIGHT", f.scroll, "RIGHT", -4, 0)
            local e = item.entry
            local n = item.n
            local label = TYPE_LABEL[e.type] or e.type
            local detail = e.details and (" - " .. e.details) or ""
            local prefix = ""
            if showLineNumbers then
                prefix = ("|cff888888%4d)|r "):format(n)
            end
            row:SetText(("%s|cffaaaaaa%s|r  %s  |cffffffff%s|r%s"):format(
                prefix, fmtDateLong(e.t), colorize(e.type, label), e.who or "?", detail))
            row:Show()
        elseif rosterMode then
            hideSingle(i)
            hideMacroBtns(i)
            local r = item
            local cells = f.rowCells[i]

            -- Lvl
            local lvlTxt = (r.level and r.level > 0) and tostring(r.level) or "?"
            cells.lvl:SetText("|cffffffff" .. lvlTxt .. "|r")

            -- Name + alt/main tag
            local mainTag = ""
            if r.main then
                mainTag = "  |cffaaaaff(alt)|r"
            else
                local g = addon:GetCurrentGuild()
                if g then
                    for _, m in pairs(g.alts) do
                        if m == r.name then
                            mainTag = "  |cffffcc00<M>|r"
                            break
                        end
                    end
                end
            end
            cells.name:SetText(classColor(r.classFile, r.name) .. mainTag)

            -- Last online
            local onlineRaw = r.online and "Online" or fmtSince(r.lastSeen)
            cells.online:SetText(lastSeenColor(r.lastSeen, r.online) .. onlineRaw .. "|r")

            -- Rank / Note / Officer Note
            cells.rank:SetText(r.rank or "")
            cells.note:SetText(r.note or "")
            cells.onote:SetText(r.officerNote or "")

            for _, c in pairs(cells) do c:Show() end
        elseif macrosMode then
            hideCells(i)
            local row = f.rows[i]
            local previewMax = 60
            local preview = item.text or ""
            if #preview > previewMax then
                preview = preview:sub(1, previewMax) .. "..."
            end
            preview = preview:gsub("\n", " "):gsub("|", "||")
            row:SetText(("|cffffcc00[%s]|r  |cffffffff%s|r"):format(
                tostring(item.channel), preview))
            -- Make room for buttons on the right
            row:SetPoint("RIGHT", f.scroll, "RIGHT", -110, 0)
            row:Show()

            local btns = f.rowMacroBtns[i]
            if btns then
                btns.send:Show()
                btns.del:Show()
                local idx = item.index
                btns.send:SetScript("OnClick", function()
                    local ok, msg = addon:SendMacro(idx)
                    if not ok then
                        print("|cFFFFCC00Guild Manager|r: " .. tostring(msg))
                    end
                end)
                btns.del:SetScript("OnClick", function()
                    addon:RemoveMacro(idx)
                    UI:Refresh()
                end)
            end
        else
            -- Alts view: single-string row
            hideCells(i)
            hideMacroBtns(i)
            local row = f.rows[i]
            -- Restore default right anchor in case it was changed by macros mode
            row:SetPoint("RIGHT", f.scroll, "RIGHT", -4, 0)
            row:SetText(("|cffeeeeee%s|r  |cff888888is alt of|r  |cffffcc00%s|r"):format(item.alt, item.main))
            row:Show()
        end
    end

    -- Status line (just hide; the right-header carries the headline now)
    f.status:SetText("")
end

function UI:RefreshIfShown()
    if frame and frame:IsShown() then UI:Refresh() end
end

function UI:Toggle()
    local f = build()
    if f:IsShown() then f:Hide() else f:Show(); UI:Refresh() end
end

function UI:Show()
    local f = build()
    f:Show()
    UI:Refresh()
end

function UI:Hide()
    if frame then frame:Hide() end
end
