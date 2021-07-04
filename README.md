# TF2-Improved-ctf (Updated 7/4/21)
### Version b4
Tired of needing to defend an intel for 60 second whole seconds before it returns? Do you know how many scouts can throw their bodies at it in that time? Improved CTF is here to help

## What does it do?
Allows players of the same team (or opposite teams in Special Delivery) to stand within a visualized capture radius of a flag to speed up the return time. This capture speed is impacted by number of players within the flag's radius along with vanilla methods of increasing capture rate (Scout and The Pain Train). Admins can also modify the default flag timer and more to suit their server's preference.

## Installation
This plugin requires Sourcemod and only works with Team Fortress 2

Place the included .SMX file into your server's `tf/addons/sourcemod/plugins` folder. On server or plugin startup, "Improved CTF enabled" should print to your server's console.

## Customization
Improved CTF includes several Cvars to help you make your gameplay just right.
```
sm_ictf_version - Prints the installed version of Improved CTF
sm_ictf_enable - Set to 0 to disable ICTF. Set to 1 to enable. (Default: 1)
sm_ictf_flag_time - Sets the initial time, in seconds, until the flag is returned. (Default: 30)
sm_ictf_cap_multiplier - Determines how much capping players effect the return time, as a decimal representing percentage. (Default: 0.6)
sm_ictf_cap_radius - Determines the distance, in hammer units, from the flag players can return it. Changes the ring visual to match. (Default: 100.0)
sm_ictf_hud_text - Enables/disables on-screen text for a flag's capture rate (Default: 1)
```

## Planned features
- Wider gamemode support
- Custom weapon capture rate support

## Changelog
```
Version b3.3.2 (July 4, 2021)
- Internal code cleanup
  - Updated to newdecls
  - replaced hard #defined red and blu team indexes with native TFTeam type, making certain logic easier to read
  - added semicolons where there were none for consistency's sake

Version b3.3.1 (5/13/20)
- Added custom HUD text to show the flag's current capture rate. Shown only when a flag is down and on the screen at the bottom next to the flag status
- Added cvar "sm_ictf_hud_text" to give the option to disable HUD text for all players
- Fixed The Pain Train not giving the 2x capture rate on flags
- Fixed beam ring not being representative of the flag's true capture radius
- Adjusted default beam ring size to compensate being bigger than intended
- Updated syntax

Version b3.2 (4/30/20)
- Fixed players being able to return the flag while cloaked, ubercharged, bonked, ect.
- Improved code readability

Version b3.1
- Improved code readability
- Privated unnecessarily public functions
- Flag timer can now be a decimal

Version b3.0
- First public version
- Changed the flag capture indicator from a jank hexagon to a circle
- Capture area will now disappear instantly when the flag is returned
```