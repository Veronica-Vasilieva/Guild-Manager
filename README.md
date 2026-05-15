# Guild Manager

A lightweight World of Warcraft addon for **Wrath of the Lich King 3.3.5a** that tracks guild roster events, manages alt/main character relationships, broadcasts saved channel macros, and replaces Blizzard's cramped guild member detail frame with a richer custom panel.

**By Veronica-Vasilieva**

---

## Features

### Event Log
Automatic background tracking of guild changes, written to an account-wide log:

- Joins and leaves
- Promotions and demotions
- Public note edits
- Officer note edits
- Level-ups
- "First observed" entry for every existing member on the first scan of a guild (so you have something to look at immediately)

The log view supports a search filter, per-type checkboxes (toggle which event types appear), numbered lines, and a one-click clear.

### Roster Tab
A column-based listing of the current guild:

- Sortable columns: Level, Name, Last Online, Rank, Note, Officer Note
- Class-coloured names
- Recency-coloured last-online indicator (green for online, fading through yellow / orange / red the longer they have been offline)
- Player Search and Note Search inputs
- Show / hide offline members
- "Group Alts With Main" mode that visually clusters alts under their main

### Alts
Lightweight per-guild alt-of-main mappings, viewable in their own tab and used by the Roster and Member Detail panels.

- Add via the in-game form, the member detail panel, or `/gm setalt`
- `<M>` tag next to mains, `(alt)` next to alts
- Mappings stored per guild and persist across sessions

### Macros
Save chat messages bound to a target channel and broadcast them with one click.

- Compose a message and pick a target: numeric channel 1 - 9, or one of `GUILD`, `OFFICER`, `SAY`, `PARTY`, `RAID`, `YELL`
- Saved macros live in account-wide storage
- Each saved entry has Send and Delete buttons

### Member Detail Panel
Replaces Wrath's small `GuildMemberDetailFrame` whenever a guild member is clicked. The replacement shows:

- Class-coloured name, level, rank
- Joined date, last-seen duration, current zone
- Inline editable Public Note and Officer's Note (saved on Enter)
- Alt relationship: "Alt of X", or list of alts if this character is a main
- Tag-as-alt-of input with Set and Untag buttons
- Invite to Group and Remove from Guild buttons (the latter with a confirmation popup)

---

## Installation

1. Place the `Guild_Manager` folder into `World of Warcraft/Interface/AddOns/`.
2. Make sure the folder name is exactly `Guild_Manager` (the TOC file inside must match: `Guild_Manager.toc`).
3. Restart the client, or `/reload` if already running.
4. At the character-select AddOns dialog, ensure **Guild Manager** is enabled.

---

## Usage

Type `/gm` to toggle the main window. The window has four tabs:

| Tab     | What it shows                                                    |
|---------|------------------------------------------------------------------|
| Log     | Filterable event history with timestamps                         |
| Roster  | Column-sorted live guild roster with class colours and alt tags  |
| Alts    | Alt-of-main mappings with add / remove form                      |
| Macros  | Saved channel-bound messages with Send / Delete                  |

Click any guild member in the Blizzard guild roster window to open the custom member detail panel.

### Slash commands

| Command                              | Effect                                |
|--------------------------------------|---------------------------------------|
| `/gm`                                | Toggle the main window                |
| `/gm setalt <alt> <main>`            | Tag a character as alt of a main      |
| `/gm unalt <name>`                   | Remove an alt tag                     |
| `/gm alts`                           | Print all alt mappings to chat        |
| `/gm clear`                          | Clear the event log for current guild |
| `/gm debug`                          | Toggle debug prints                   |
| `/gm help`                           | Print the full command list           |
| `/guildmanager`                      | Same as `/gm`                         |

---

## Compatibility

Built and tested against Wrath 3.3.5a (Interface 30300) on common private-server cores (TrinityCore, AzerothCore, and Valanior-style derivatives). The addon only uses APIs available in 3.3.5a; there is no compat shim layer to maintain.

It does not use any Cataclysm+ features (no `C_Club`, no `C_Calendar`, no `C_Timer`, no Communities), and it does not bind any `OnKeyDown` handlers on frames, so it cannot cause the keyboard-capture issues that retail-era guild addons typically have when forced onto Wrath clients.

---

## Saved variables

- `GuildManagerDB` - account-wide. Holds per-guild member records, event log, alt mappings, and saved macros.
- `GuildManagerCharDB` - per-character. Holds the debug toggle.

Both are plain Lua tables saved in the usual WTF folder; you can hand-edit if you need to.

---

## Contributing

Bug reports and feature requests are welcome via the repository's issue tracker. Pull requests are also welcome - see the LICENSE for the contribution terms.

---

## License

This project is **source-available**, not open source. The full terms are in [LICENSE](LICENSE). In short:

- You may install and use it as a player.
- You may read the source for educational purposes.
- You may **not** redistribute it, fork it for public release, or incorporate its code into other projects without written permission from the author.

---

## Credits

Created and maintained by **Veronica-Vasilieva**.
