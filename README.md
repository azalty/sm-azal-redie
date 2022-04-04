# sm-azal-redie
A redie plugin made to be used in any CS:GO gamemod, without any bugs and well supported. Originally made for jailbreak.

## Redie?
Allows players to play like they were alive when they're actually dead, without interfering with the game in any sort.\
Ghosts are invisible, non-tangible and silent.

## Commands
Default commands: `sm_redie`, `sm_ghost` (and their chat equivalent `!redie`, `/ghost`...)\
Those can be modified through the config file.

## Features and differences from the other plugins
- Built to support Jailbreak, making it resistant to highly custom maps
- Ghosts are:
  - Invisible
  - Non-tangible (no collisions)
  - Silent (no walking, running, jumping sounds...)
- Ghosts cannot interact with the following entities:
  - Buttons
  - Triggers (`trigger_multiple`, `trigger_once`)
  - Breakable things
  - Doors
- Command limits supported:
  - Possibility to have a cooldown between each command use
  - Possibility to limit a number of command usages per round per player
- Supports late-loading (loading or reloading the plugin mid-game)
- Noclip feature for Ghosts
- A simple Redie menu
- No bodies, weapons or anything dropped by Ghosts when spawning or dying
- Translations support (currently English, French)

**And... special features:**
- Possibility to enable an experimental hook on teleport triggers to **teleport Ghosts without triggering events** linked to the trigger
- Possibility to **support Health for Ghosts** (or to make them invincible)
- Possibility to (partly) **prevent Ghosts from blocking doors**, and to notify the entire server if they do so
- Possibility to block outputs triggered by Ghosts on certain entities through the config file

## Bugs
If you encounter or notice any bug, please report them [here](https://github.com/azalty/sm-azal-redie/issues).\
The plugin is currently in **BETA**, but seems to works great.\
I plan to add other features if requested.

## Restrict command? (VIP only, Admins only...)
You can restrict the redie commands through `configs/admin_overrides.cfg`.\
There is no cvar to restrict the commands from the plugin itself.

## Credits and inspiration
Plugin based on [Redie by Pyro_](https://forums.alliedmods.net/showthread.php?t=248194) (lots of code, ideas, methods borrowed)
