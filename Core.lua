-- GuildManager Core
-- Wrath 3.3.5a native guild roster tracking, event log, alts management.

GuildManager = GuildManager or {}
local addon = GuildManager
addon.version = "1.0"

local LOG_MAX = 5000        -- cap log size per guild to prevent unbounded growth
local SNAPSHOT_DEBOUNCE = 2 -- seconds; coalesce burst GUILD_ROSTER_UPDATE events

local currentGuildKey      -- realm::guildname for the currently active guild
local lastSnapshot         -- previous snapshot used for diffing
local pendingSnapshot      -- coalescing timer-active flag

-- =========================================================
-- SavedVariables bootstrap
-- =========================================================
local function ensureDB()
    if type(GuildManagerDB)     ~= "table" then GuildManagerDB     = {} end
    if type(GuildManagerCharDB) ~= "table" then GuildManagerCharDB = {} end
    if type(GuildManagerDB.guilds) ~= "table" then GuildManagerDB.guilds = {} end
    if type(GuildManagerDB.macros) ~= "table" then GuildManagerDB.macros = {} end
    if not GuildManagerDB.version then GuildManagerDB.version = 1 end
end

-- =========================================================
-- Macros API (account-wide saved messages bound to a channel)
-- macro = { channel = "1".."9" | "SAY" | "GUILD" | "OFFICER" | "PARTY" | "RAID" | "YELL",
--           text    = "..." }
-- =========================================================
function addon:GetMacros()
    if type(GuildManagerDB) ~= "table" or type(GuildManagerDB.macros) ~= "table" then
        return {}
    end
    return GuildManagerDB.macros
end

function addon:AddMacro(channel, text)
    if not channel or channel == "" then return false, "Pick a channel." end
    if not text or text == "" then return false, "Message cannot be empty." end
    GuildManagerDB.macros = GuildManagerDB.macros or {}
    table.insert(GuildManagerDB.macros, { channel = channel, text = text })
    return true
end

function addon:RemoveMacro(index)
    if not GuildManagerDB.macros then return end
    if type(index) ~= "number" then return end
    if index < 1 or index > #GuildManagerDB.macros then return end
    table.remove(GuildManagerDB.macros, index)
end

function addon:SendMacro(index)
    if not GuildManagerDB.macros then return false, "No macros." end
    local m = GuildManagerDB.macros[index]
    if not m then return false, "Macro not found." end
    return addon:Broadcast(m.channel, m.text)
end

local NAMED_CHANNELS = {
    SAY = true, YELL = true, GUILD = true, OFFICER = true,
    PARTY = true, RAID = true, RAID_WARNING = true,
}

function addon:Broadcast(channel, text)
    if not channel or channel == "" then return false, "No channel." end
    if not text or text == "" then return false, "Empty message." end
    -- Numeric channel: SendChatMessage(msg, "CHANNEL", nil, slot)
    local num = tonumber(channel)
    if num and num >= 1 and num <= 9 then
        SendChatMessage(text, "CHANNEL", nil, num)
        return true
    end
    local up = channel:upper()
    if NAMED_CHANNELS[up] then
        if up == "RAID_WARNING" then
            SendChatMessage(text, "RAID_WARNING")
        else
            SendChatMessage(text, up)
        end
        return true
    end
    return false, "Unsupported channel: " .. tostring(channel)
end

local function guildKey(realmName, guildName)
    return (realmName or "?") .. "::" .. (guildName or "?")
end

local function ensureGuildEntry(key)
    local g = GuildManagerDB.guilds[key]
    if not g then
        g = { members = {}, log = {}, alts = {} }
        GuildManagerDB.guilds[key] = g
    end
    if not g.members then g.members = {} end
    if not g.log     then g.log     = {} end
    if not g.alts    then g.alts    = {} end
    return g
end

function addon:GetCurrentGuild()
    if not currentGuildKey then return nil end
    return GuildManagerDB and GuildManagerDB.guilds and GuildManagerDB.guilds[currentGuildKey]
end

function addon:GetCurrentGuildKey()
    return currentGuildKey
end

-- =========================================================
-- Log
-- =========================================================
local function pushLog(guild, entry)
    table.insert(guild.log, entry)
    while #guild.log > LOG_MAX do
        table.remove(guild.log, 1)
    end
end

function addon:ClearLog()
    local g = self:GetCurrentGuild()
    if g then g.log = {} end
end

-- =========================================================
-- Roster snapshot + diff
-- =========================================================
local function snapshotRoster()
    local snap = {}
    local n = GetNumGuildMembers() or 0
    if n == 0 then return snap end
    for i = 1, n do
        local name, rank, rankIndex, level, _, zone, note, officerNote, online, _, classFile
            = GetGuildRosterInfo(i)
        if name and name ~= "" then
            snap[name] = {
                rank        = rank or "",
                rankIndex   = rankIndex or 0,
                level       = level or 0,
                zone        = zone or "",
                note        = note or "",
                officerNote = officerNote or "",
                online      = online and true or false,
                classFile   = classFile or "",
            }
        end
    end
    return snap
end

local function diffSnapshots(old, new, guild)
    local now = time()
    local todayStr = date("%Y-%m-%d", now)

    -- Joins (in new, not in old)
    for name, info in pairs(new) do
        if not old[name] then
            pushLog(guild, {
                t = now, type = "JOIN", who = name,
                details = ("Lvl %d %s"):format(info.level, info.rank),
            })
            local m = guild.members[name]
            if not m then
                m = {}
                guild.members[name] = m
            end
            if not m.joinDate then m.joinDate = todayStr end
        end
    end

    -- Leaves (in old, not in new)
    for name in pairs(old) do
        if not new[name] then
            pushLog(guild, { t = now, type = "LEAVE", who = name })
        end
    end

    -- Changes (in both)
    for name, n in pairs(new) do
        local o = old[name]
        if o then
            if o.rank ~= n.rank then
                local kind = ((o.rankIndex or 0) > (n.rankIndex or 0)) and "PROMOTE" or "DEMOTE"
                pushLog(guild, {
                    t = now, type = kind, who = name,
                    details = ("%s -> %s"):format(o.rank, n.rank),
                })
            end
            if o.note ~= n.note then
                pushLog(guild, {
                    t = now, type = "NOTE", who = name,
                    details = ("'%s' -> '%s'"):format(o.note, n.note),
                })
            end
            if o.officerNote ~= n.officerNote then
                pushLog(guild, {
                    t = now, type = "ONOTE", who = name,
                    details = ("'%s' -> '%s'"):format(o.officerNote, n.officerNote),
                })
            end
            if (n.level or 0) > (o.level or 0) then
                pushLog(guild, {
                    t = now, type = "LEVEL", who = name,
                    details = ("%d -> %d"):format(o.level, n.level),
                })
            end
        end

        -- Track last-online + class info
        local m = guild.members[name]
        if not m then m = {}; guild.members[name] = m end
        if n.online then m.lastOnline = now end
        m.lastRank  = n.rank
        m.lastLevel = n.level
    end
end

-- =========================================================
-- Wrath has no C_Timer.After -- implement a tiny one-shot
-- scheduler via OnUpdate.
-- =========================================================
local scheduler = CreateFrame("Frame")
local queue = {}
scheduler:SetScript("OnUpdate", function(self)
    if #queue == 0 then return end
    local now = GetTime()
    local i = 1
    while i <= #queue do
        if now >= queue[i].when then
            local fn = queue[i].fn
            table.remove(queue, i)
            local ok, err = pcall(fn)
            if not ok and GuildManagerCharDB and GuildManagerCharDB.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555GuildManager scheduler err: " .. tostring(err))
            end
        else
            i = i + 1
        end
    end
end)
local function delayCall(secs, fn)
    table.insert(queue, { when = GetTime() + secs, fn = fn })
end

-- =========================================================
-- Coalesced "do a diff" trigger
-- GUILD_ROSTER_UPDATE can fire many times back-to-back. We
-- wait a couple seconds for the dust to settle before diffing.
-- =========================================================
local function scheduleDiff()
    if pendingSnapshot then return end
    pendingSnapshot = true
    delayCall(SNAPSHOT_DEBOUNCE, function()
        pendingSnapshot = false
        if not IsInGuild() then return end
        local guildName = GetGuildInfo("player")
        if not guildName or guildName == "" then return end
        local realmName = GetRealmName() or "?"
        local key = guildKey(realmName, guildName)
        if key ~= currentGuildKey then
            currentGuildKey = key
            lastSnapshot = nil
        end
        local guild = ensureGuildEntry(currentGuildKey)
        local snap = snapshotRoster()
        local snapCount = 0
        for _ in pairs(snap) do snapCount = snapCount + 1 end

        -- Wrath's GetGuildRosterInfo can briefly return an empty roster
        -- right after a guild context change. Don't seed/diff against
        -- a zero-member snapshot - just wait for the next update.
        if snapCount == 0 then
            return
        end

        -- First time we've ever observed this guild? Seed the log with a
        -- synthetic "SEEN" entry for every current member, and store
        -- joinDate as today (best-effort "past" data). All future diffs
        -- run against this snapshot.
        local firstObservation = (next(guild.members) == nil)
                                and (#guild.log == 0)
                                and (lastSnapshot == nil)
        if firstObservation then
            local now = time()
            local todayStr = date("%Y-%m-%d", now)
            for name, info in pairs(snap) do
                guild.members[name] = guild.members[name] or {}
                guild.members[name].joinDate  = guild.members[name].joinDate  or todayStr
                guild.members[name].lastRank  = info.rank
                guild.members[name].lastLevel = info.level
                guild.members[name].classFile = info.classFile
                if info.online then
                    guild.members[name].lastOnline = now
                end
                table.insert(guild.log, {
                    t = now, type = "SEEN", who = name,
                    details = ("Lvl %d %s"):format(info.level, info.rank),
                })
            end
        elseif lastSnapshot then
            diffSnapshots(lastSnapshot, snap, guild)
        end
        -- Always update classFile in member records from the latest snapshot.
        for name, info in pairs(snap) do
            local m = guild.members[name]
            if m then m.classFile = info.classFile end
        end
        lastSnapshot = snap

        if addon.UI and addon.UI.RefreshIfShown then
            addon.UI:RefreshIfShown()
        end
    end)
end

-- =========================================================
-- Events
-- =========================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:SetScript("OnEvent", function(self, event)
    ensureDB()
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        if IsInGuild() then
            GuildRoster()
        end
    elseif event == "PLAYER_GUILD_UPDATE" then
        if IsInGuild() then
            GuildRoster()
        else
            currentGuildKey = nil
            lastSnapshot = nil
        end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if IsInGuild() then
            scheduleDiff()
        end
    end
end)

-- =========================================================
-- Alts API
-- =========================================================
function addon:SetAlt(altName, mainName)
    local g = self:GetCurrentGuild()
    if not g then return false, "Not in a guild yet." end
    if type(altName) ~= "string" or altName == "" then
        return false, "Need an alt name."
    end
    if mainName == nil or mainName == "" then
        g.alts[altName] = nil
        return true, "Removed alt tag from " .. altName
    end
    g.alts[altName] = mainName
    return true, ("Tagged %s as alt of %s"):format(altName, mainName)
end

function addon:GetMainOf(name)
    local g = self:GetCurrentGuild()
    if not g then return nil end
    return g.alts[name]
end

function addon:GetAltsOf(mainName)
    local out = {}
    local g = self:GetCurrentGuild()
    if not g then return out end
    for alt, main in pairs(g.alts) do
        if main == mainName then table.insert(out, alt) end
    end
    table.sort(out)
    return out
end

function addon:GetMemberRecord(name)
    local g = self:GetCurrentGuild()
    if not g then return nil end
    return g.members[name]
end

-- =========================================================
-- Slash commands
-- =========================================================
SLASH_GUILDMANAGER1 = "/gm"
SLASH_GUILDMANAGER2 = "/guildmanager"
SlashCmdList["GUILDMANAGER"] = function(msg)
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    local lower = msg:lower()

    if msg == "" then
        if addon.UI and addon.UI.Toggle then
            addon.UI:Toggle()
        end
        return
    end

    if lower == "help" then
        print("|cFFFFCC00Guild Manager|r commands:")
        print("  |cffffff00/gm|r                 - toggle the log window")
        print("  |cffffff00/gm setalt <alt> <main>|r")
        print("  |cffffff00/gm unalt <name>|r")
        print("  |cffffff00/gm alts|r             - print all alt mappings")
        print("  |cffffff00/gm clear|r            - clear the event log for this guild")
        print("  |cffffff00/gm debug|r            - toggle debug prints")
        return
    end

    local setalt = msg:match("^[Ss][Ee][Tt][Aa][Ll][Tt]%s+(%S+)%s+(%S+)$")
    if setalt then
        local alt, main = msg:match("^[Ss][Ee][Tt][Aa][Ll][Tt]%s+(%S+)%s+(%S+)$")
        local ok, m = addon:SetAlt(alt, main)
        print("|cFFFFCC00Guild Manager|r: " .. tostring(m))
        if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
        return
    end

    local unalt = msg:match("^[Uu][Nn][Aa][Ll][Tt]%s+(%S+)$")
    if unalt then
        local ok, m = addon:SetAlt(unalt, nil)
        print("|cFFFFCC00Guild Manager|r: " .. tostring(m))
        if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
        return
    end

    if lower == "alts" then
        local g = addon:GetCurrentGuild()
        if not g or not next(g.alts) then
            print("|cFFFFCC00Guild Manager|r: no alt mappings recorded.")
            return
        end
        print("|cFFFFCC00Guild Manager|r alt mappings:")
        for alt, main in pairs(g.alts) do
            print(("  %s -> %s"):format(alt, main))
        end
        return
    end

    if lower == "clear" then
        addon:ClearLog()
        print("|cFFFFCC00Guild Manager|r: event log cleared.")
        if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
        return
    end

    if lower == "debug" then
        ensureDB()
        GuildManagerCharDB.debug = not GuildManagerCharDB.debug
        print("|cFFFFCC00Guild Manager|r: debug = " .. tostring(GuildManagerCharDB.debug))
        return
    end

    print("|cFFFFCC00Guild Manager|r: unknown command. Try /gm help")
end

-- Run db setup at file load so other files can read it safely.
ensureDB()
