# Song Manager

A grandMA3 Lua plugin that gives you per-song control over your show file,
driven by a song's short name and BPM.

By default it manages **Sequences**, **Macros**, **Pages**, and **TimeCodes**
per song, but you can add any other pool from the menu (Preset pools, Groups,
Filters, Effects, or anything else you can address with a command-line class
keyword).

## Features

- Menu-driven UI (`PopupInput` / `TextInput` / `Confirm`) - no external files,
  a single `.lua` script.
- **First-run setup wizard**: choose which pool types to manage and their
  starting numbers before you add any songs.
- **Per-song object blocks**: each song gets its own contiguous range of pool
  numbers per pool type (configurable block size), auto-allocated or entered
  manually.
- **Custom executor / bump button placement** per song, with the pool type
  that gets the bump button configurable (defaults to Sequence).
- **Template views**: keeps one or more views (e.g. View 173) scrolled to the
  active song's objects by revealing them and re-storing the view over
  itself. Supports a shared/global list of views plus a personal list of
  view numbers per operator (`My Personal Views`), for multi-user / synced
  sessions.
- **BPM reference**: a dedicated executor driving a Speed Master pool object,
  with one-tap multiplier shortcuts (`1/8`, `1/4`, `1/2`, `1`, `2`, `4`, `8`),
  a tap-tempo option, and manual BPM entry.
- **Set List integration**: `Next Song` / `Previous Song` navigation that
  fires each song's start macro on activation, with a per-song (or default)
  gap in seconds that auto-advances to the next song using `Timer()`.
- **One-click settings reset**, plus a separate, deliberately harder-to-hit
  **full reset** that deletes every object the plugin created (requires
  typing `DELETE` to confirm).

## Install

1. In grandMA3: `Pool > Plugins`, right click an empty slot, **Store
   Plugin**.
2. Right click the new plugin object, **Edit**, and paste the entire
   contents of `SongManager.lua` in.
3. Assign the plugin to an executor button or a macro line and press it to
   open the main menu.

## Usage

- First press runs the **setup wizard**: enable/disable Sequence, Macro,
  Page, TimeCode, and set each one's starting number and how many numbers
  each song reserves (block size). Also sets the template view number, the
  starting bump-button executor, and the BPM reference executor.
- **Songs > + New Song**: enter a short name, full name, and BPM. Choose
  auto-assigned pool numbers (recommended) or enter each pool number
  yourself.
- **Go To Song**: activates a song - switches to its executor page, scrolls
  and re-stores the template view(s) over the song's objects, sets the BPM
  reference, and (if Set List is enabled) fires the song's start macro.
- **BPM Reference**: apply `x1/8` ... `x8` against the active song's BPM,
  tap tempo, or type a BPM directly.
- **Set List**: enable/disable, set a default advance gap, and step through
  songs with `Next Song` / `Previous Song`. Per-song gaps can be set from
  **Songs > (a song) > Set List Gap**; `0` means manual advance only.
- **Settings**: add extra pool types (e.g. label `Preset Pool 25`, class
  `Preset`, pool ID `25`), manage template views (including personal,
  per-operator views), change bump-button placement, tweak the BPM
  reference executor, and reset.

## Command syntax notes - please verify on your console

Most of the command-line syntax used here (`Store`, `Label`, `Delete`,
`Assign ... At Executor`, `Page`, `Store View ... /o`) is standard, stable
grandMA3 syntax. Three spots are best-guesses that were written without a
live console to verify against, and are worth checking on your version
before relying on the plugin in a show - they're centralized in the
`COMMANDS` table at the top of `SongManager.lua` so they're easy to tweak
in one place:

| Key                       | Default template            | Used for |
|----------------------------|-----------------------------|----------|
| `COMMANDS.loadView`        | `Load View %d`               | Manually recalling a template view onto the current display |
| `COMMANDS.revealPool`      | `SelectDrag %s`               | Scrolling an already-open pool window to a song's objects |
| `COMMANDS.speedMasterAt`   | `SpeedMaster %d At %s`        | Setting the BPM reference Speed Master's rate |

If any of these don't behave as expected on your console/version, edit the
template string - the rest of the plugin (data model, menus, pool
allocation, executor assignment, set list, reset) does not depend on them.

Two more assumptions worth knowing about: Set List auto-advance multiplies
the configured gap in seconds by 1000 and passes it to `Timer()`, assuming
its delay parameter is in milliseconds; and tap tempo assumes `Time()`
returns milliseconds. If tempo/timing feels off, these are the first things
to check.

## Data storage

Song and settings data is stored as a single serialized Lua table in a
show-global variable (`GlobalVars()`), so it travels with the show file.
Each operator's personal template view list and last tap-tempo timestamp
are stored in `UserVars()`, so they're per-profile.

## Troubleshooting: nothing appears when the plugin is pressed

grandMA3 loads a plugin's code as a Lua module: it runs the whole file once
(to define everything) and then calls whatever that file *returns* on every
subsequent invocation. This file ends with `return main` - that return
statement is what grandMA3 is actually looking for. If you see
`LUA: no reference to main function found for plugin` in the command line
history, the code you pasted in doesn't end with that `return` (e.g. an
older copy, or the paste got truncated) - re-paste the current version of
`SongManager.lua` in full, all the way to the last line.

Otherwise, the script prints two diagnostic lines via `Printf` on every
press - `"SongManager: plugin invoked"` and `"SongManager: data loaded, ..."`
- check your command line / status history for these first:

- **Neither line appears**: `main` isn't being reached at all - check for the
  `no reference to main function` message above, and that the button/executor
  is assigned to *this* plugin object.
- **Both lines appear but no popup shows**: the script is running but a UI
  call isn't rendering - check the status/error history for a line starting
  `SongManager Error:` (the plugin also tries to show this as a popup). If an
  error is genuinely happening, please report it (with a screenshot/text of
  the message) so it can be root-caused.
- **Lines appear once, then never again on later presses**: check whether the
  plugin is mid-dialog already (e.g. the console lost focus while a
  `TextInput`/`Confirm`/`PopupInput` was open) - re-focus the display and
  press again, or the currently-open dialog needs to be dismissed first.

Variable reads (`GetVar`) on startup are also wrapped defensively so that an
unexpected error there can't silently kill the whole script before any UI
has had a chance to show.

## Troubleshooting: the menu opens but selecting an option does nothing

This was a real bug, now fixed: `PopupInput`'s documented `items` format
(`{{'str'|'int'|..., name, ...}, ...}`) doesn't match how real, working
grandMA3 plugins actually call it - they pass `items` as a flat array of
plain strings. Passing the documented tuple shape instead means the value
`PopupInput` returns for your selection never matches any menu label, so
every `if val == "..."` check in the menu code silently falls through and
the same menu just redraws - indistinguishable from the button not doing
anything. If you're running a copy of this file from before this fix,
re-paste the current version.
