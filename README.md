

# Improved CTF (iCTF)
iCTF aims to improve CTF by implementing additional gameplay mechanics that make the game faster-paced and minimizes double-defending situations. this plugin originally started as a fork of [Ribbon Heart's iCTF](https://forums.alliedmods.net/showthread.php?t=323866), but most of the code has since been rewritten or refactored. additionally, some secondary mechanics and stats have been added, inspired by the SmartCTF mod from Unreal Tournament '99.

## features
### flag returning
when dropped, the flag has a "return zone" around it that can be interacted with by players:
* friendly players standing on the flag will make its return timer count down faster, allowing them to "capture-return" it.
* a defender returning the flag also makes it non-solid, preventing an enemy from running by and resetting the return time as long as a defender is standing on it.
* enemy players standing on the flag will prevent the timer from going down at all, effectively blocking defenders from returning it until they are dealt with.

by default, the flag takes 25 seconds to return on its own without help from defenders. defenders who were standing on the intel at the time of return are credited with the return if the enhanced HUD alerts are enabled, and the plugin outputs additional log events for flag returns for competitive log parsers like [logs.tf](http://logs.tf). players who return a flag near the enemy's capture zone are awarded a "close save," which doesn't do anything more but is also marked in the alert and log event.

i personally like this approach _much_ more than straight up return-on-touch, because defenders and attackers both have a degree of control over the flag, and must strategize around it to be successful.

### round time
iCTF adds round time to CTF, complete with custom overtime mechanics. all values of the round timer can be customized and adjusted, and it can be configured as to whether or not the timer is only managed on maps that don't have one, or existing maps' timers can be hijacked and controlled by iCTF to create a consistent experience. round time can also be added on flag capture, with a few different specific rules to choose from.

by default, the round has 25 seconds of setup time, starts with 10 minutes of round time, and caps out at 12 minutes. 3 minutes of time is added when a flag is captured when scores are even, or the capturing team is behind (winning team capping doesn't add time).

when the round time expires, the team with the most captures wins. if it's tied, then the following happens:
* if both flags are at home and scores are tied when the round ends, it's a stalemate.
* if both flags are away from home, then overtime begins. in overtime, the first flag to be _returned home_ wins the round. the round basically turns into hold the flag/VIP.
* if one flag is home and the other is out, then the team whose flag is home wins the round. they're basically just immediately fulfilling the overtime condition and winning the round.

(if overtime is disabled then the round just ends in a stalemate when tied regardless of flag status)
### extended HUD
a few extra HUD elements have been added. when a flag is being carried, the carrier's name and rough location is displayed as text on the HUD. the return time and capture rate (if any) are shown when the flag is dropped. the location of these text elements can be adjusted individually per-player with `sm_cookies`.

additionally, the default text alerts showing the flag status ("Your INTELLIGENCE was DROPPED!") have been replaced with shorter messages that feature player names. ("\<player\> stole the RED flag!")

each of these HUD elements can be enabled or disabled independently with cvars.
### capture assist system
vanilla TF2's "capture assist" system in CTF is garbage. by default, the first player to pick up the flag from the enemy base is credited with the assist if another player goes on to capture it. this means if player 1 grabs the flag, immediately dies, then player 2 comes in and gets it out of the base and dies, then player 3 finishes the capture, player 1 gets the assist despite the fact that player 2 carried it more and contributed more to the capture.

iCTF instead keeps track of how long each player carried the flag during its time out until its capture, and awards the assist that way. the player who carried the flag the longest (or, if that player is also the capper, the player who carried it the second-longest) is awarded the assist point, instead of arbitrarily giving it to the player who grabbed it first.
### cover-kill system
a mechanic straight from UT99's SmartCTF. a cover kill is a kill that defends your flag carrier as defined by any of the following criteria being met:
* you are the flagcarrier and are defending yourself (if enabled; off by default)
* enemy is within 512 Hu (Hammer units) of the flagcarrier
* you are within 256 Hu of the flagcarrier
* enemy is within 1536 Hu of the flagcarrier, has line-of-sight on the flagcarrier, and is looking in their direction
* enemy is within 768 Hu of the flagcarrier, has line-of-sight on the flagcarrier, but is NOT looking in their direction
* enemy is within 1024 Hu of the flagcarrier, and you have line-of-sight on the flagcarrier
* enemy is within 3200 Hu of the flagcarrier, has line-of-sight on the flagcarrier, and is a sniper aiming at them

if any of these conditions are met, you will have covered your flagcarrier. this feature is completely vanity and does nothing more than printing the text to the HUD - it can be disabled with no gameplay consequence.
## dependencies
[TF2Items](https://forums.alliedmods.net/showthread.php?p=1050170) - checks equipped weapons for capture rate bonus attribute (paintrain, as well as support for custom weapons)

## cvars & configuration
values in `[brackets]` are the default
### capture/return settings
`sm_ictf_cap_time [25]` - time, in seconds, that the flag will take to return once dropped, without any player intervention. overrides the default map drop time.

`sm_ictf_cap_bonus [0.25]` - how much time to take off the return timer for every capture rate returning the flag.

`sm_ictf_cap_overtime [1.0]` - the value of `sm_ictf_cap_bonus` is multiplied by this value during overtime. set this to 1.0 to make overtime not affect this.

`sm_ictf_cap_radius [115]` - radius of the return zone around the dropped flag.

`sm_ictf_cap_visualizer <0/1/[2]>` - controls visual indicators around dropped flags:

0\) disabled entirely (no visualizer)  

1\) the outer ring is the capture area, the inner ring shrinks as the return time decreases. (old visualizer)

2\) the inner  and outer ring both do not move, and the visualizer is basically a "holographic control point."  

`sm_ictf_cap_carrierbonus [1]` - if you're carrying the enemy flag while returning your own, you gain this much extra capture rate (eg a value of 1 means a scout carrying the flag has a capture rate of x3 while returning his own flag, while everyone else is x2)

`sm_ictf_cap_assist <0/[1]>` - enable/disable the custom carry-time-based assist system.

`sm_ictf_cap_respawn <0/[1]/2>` - controls the rules for respawning the team whose flag has just been captured:

0\) team does not get respawned at all.

1\) team gets respawned if their flag is captured, no matter the score.

2\) team gets respawned if their flag is captured, but only if they're now behind in score.
### round time settings
`sm_ictf_roundtime_enable <0/[1]>` - enables custom round time management. if a map has a built-in round timer, this plugin will detect it and override it instead of spawning a second, clashing timer. if a round timer isn't detected on the map, then it will create one.

remember: 0 is a second, so a value of `36` displays as `0:35` on the round timer. this also applies to round time (start time of `600` displays as `9:59`, not `10:00`)

`sm_ictf_roundtime_setup [26]` - time, in seconds, of setup phase before the round starts. if this is set to 0, then there will be no setup phase. all flags are not solid and cannot be picked up during setup time. 

`sm_ictf_roundtime_starttime [600]` - time, in seconds, of the main round after setup. (or round start if setup is disabled) this can't be higher than the max time.

`sm_ictf_roundtime_maxtime [720]` - time cap of the round timer. time can't go past this amount when being added from captures.

`sm_ictf_roundtime_capture_mode <0/[1]/2/3>` - controls the rules for when time is added on flag capture:

0\) round time is not added on capture.

1\) round time is added on capture if scores are even, or if capturing team is behind.

2\) round time is added on capture _only_ if capturing team is behind.

3\) round time is added on every capture, regardless of score.

`sm_ictf_roundtime_capture_time [180]` - time, in seconds, to add to the round time when the flag is captured, in accordance with the cvar above.

`sm_ictf_roundtime_overtime <0/[1]>` - controls whether or not the custom overtime condition kicks in. if set to 0, the round will end in a stalemate if scores are tied, regardless of the flags' status.

if set to 1, overtime will activate if a flag is away - the first flag to be returned to base will win that team the round. if only one flag is missing when the round ends, the overtime condition is fulfilled immediately and the team whose flag is home just wins the round outright. if both flags are home when the round ends, there is no overtime and the round simply ends in a stalemate.
### extended HUD settings
`sm_ictf_hud_dropped <0/[1]>` - controls whether or not the HUD text showing the flag's return time and capture rate while dropped will be shown to players.

`sm_ictf_hud_carried <0/[1]/2>` - controls whether or not the HUD text showing who's carrying the flag will be shown to players:

0\) does not show carrier info at all

1\) shows carrier's name and rough location. location is determined by distance between flag capture areas, and are vague by design. "RED/BLU Intel", "RED/BLU Base", and "Mid" are as precise as it gets.

2\) shows carrier's name, without the location text.

`sm_ictf_hud_alerts <0/[1]>` - replaces the generic TF game text alert messages with more concise ones that also include the name of   t he player doing them. nothing more than it just looks a little better than vanilla TF2's messages. (eg `"Your INTELLIGENCE was DROPPED!"` -> `"\<player\> dropped the RED/BLU flag!"`)
### misc settings
`sm_ictf_coverkills <0/1/[2]>` - enable/disable the cover-kill system.

0\) disable coverkill system.

1\) enable coverkill system.

2\) enable coverkill system, but don't display the flag carrier defending themself ("\<player\> covered their own ass!" messages)
## planned features & known issues
BUGS:
* leaving this plugin running on a map for a long time crashes stuff when flags drop... is this a plugin problem or a "you've left a map running for over 24 hours" problem? seems to get fixed simply by reloading the map.

FEATURES:
* ~~round timer & overtime mechanics so that rounds don't last 45 minutes~~ done!
* ~~output additional log events for competitive log parsers?~~ done.
* use translation keys for text instead of hardcoded english? (carry HUD, alerts HUD, cover kills)

## changelog
```
ver 3.0 (SEP 16, 2022)
Probably something stupid i forgot that i'll need to hotfix, but i'm running out of reasons to keep this version indev forever...
> added round timer
 >> round time, max time, time added on capture, setup time, and overtime are all adjustable
> flag status HUD overhaul
 >> uses less HUDtext channels, clashes less with other plugins HUDtext
 >> now shows on the left of the screen
 >> adjustable per-player with client cookies
 >> shows flag carrier if flag is stolen
 >> shows approximate flag location based on distance between each team's capture zone
 >> default game text alerts have now been enhanced with short and sweet messages that include player names
> cover-kills can now be set to ignore "covered their own ass!" messages (this is also the default now)
> players are now correctly credited with returning their flag in HUD alerts and log events
 >> doing this near the enemy capture zone is counted as a close save

ver 2.0 (JUL 26, 2022)
> near-complete rewrite. restarted version numbering at v2.0 to keep things easy.
>> return timer now uses the entity's timer and SDK think function instead of maintaining internal SM timers, resulting in much smoother timekeeping
>> return time left is now displayed on the HUD alongside capture rate
>> visualizer runs more smoothly and has alternate mode that does not animate
>> defenders returning their flag prevent enemies from being able to pick it up
>> conversely, enemies standing on your flag block the return timer from advancing
>> capture rate supports custom weapons with capture rate bonus attribtue
>> players carrying an enemy flag gain a +1 capture bonus towards returning their own
>> added custom assist system that awards the assist point to the player who carried it the longest besides the capper
>> added cover-kill system that shows HUD notifications when players defend their friendly flagcarrier

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