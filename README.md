# Improved CTF (iCTF)
iCTF aims to improve CTF by implementing additional gameplay mechanics that make the gamemode less defensive and encourages teamplay. this plugin originally started as a fork of [Ribbon Heart's iCTF](https://forums.alliedmods.net/showthread.php?t=323866), but most of the code has since been rewritten or refactored. additionally, some secondary mechanics and stats have been added, inspired by the SmartCTF mod from Unreal Tournament '99.

## features
### flag returning
when dropped, the flag has a "return zone" around it that can be interacted with by players:
* friendly players standing on the flag will make its return timer count down faster, allowing them to "capture-return" it.
* a defender returning the flag also makes it non-solid, preventing an enemy from running by and resetting the return time as long as a defender is standing on it.
* enemy players standing on the flag will prevent the timer from going down at all, effectively blocking defenders from returning it until they are dealt with.

additionally, the flag by default takes 25 seconds to return without defensive intervention, (default CTF flags take 60 sec) this can be adjusted, though.

### capture assist system
vanilla TF2's "capture assist" system in CTF is garbage. by default, the first player to pick up the flag from the enemy base is credited with the assist if another player goes on to capture it. this means if player 1 grabs the flag, immediately dies, then player 2 comes in and gets it out of the base and dies, then player 3 finishes the capture, player 1 gets the assist despite the fact that player 2 carried it more and contributed more to the capture.

iCTF instead keeps track of how long each player carried the flag during its time out until its capture, and awards the assist that way. the player who carried the flag the longest (or, if that player is also the capper, the player who carried it the second-longest) is awarded the assist point, instead of arbitrarily giving it to the player who grabbed it first.
### cover-kill system
a mechanic straight from UT99's SmartCTF. a cover kill is a kill that defends your flag carrier as defined by any of the following criteria being met:
* you are the flagcarrier and are defending yourself
* enemy is within 512 Hu (Hammer units) of the flagcarrier
* you are within 256 Hu of the flagcarrier
* enemy is within 1536 Hu of the flagcarrier, has line-of-sight on the flagcarrier, and is looking in their direction
* enemy is within 768 Hu of the flagcarrier, has line-of-sight on the flagcarrier, but is NOT looking in their direction
* enemy is within 1024 Hu of the flagcarrier, and you have line-of-sight on the flagcarrier
* enemy is within 3200 Hu of the flagcarrier, has line-of-sight on the flagcarrier, and is a sniper aiming at them

if any of these conditions are met, you will have covered your flagcarrier. all it does for now is add a little HUD notice to make you look cool, it doesn't actually give any support or defense points.
## dependencies
[TF2Items](https://forums.alliedmods.net/showthread.php?p=1050170) - checks equipped weapons for capture rate bonus attribute (paintrain, as well as support for custom weapons)


## cvars & configuration
values in `[brackets]` are the default for the CVAR
`sm_ictf_cap_time [25]` - time, in seconds, that the flag will take to return once dropped, without any player intervention. overrides the default map drop time.

`sm_ictf_cap_bonus [0.25]` - how much time to take off the return timer for every capture rate returning the flag.

`sm_ictf_cap_radius [115]` - radius of the return area around the dropped flag.

`sm_ictf_cap_carrierbonus [1]` - if you're carrying the enemy flag while returning your own, you gain this much extra capture rate (eg a value of 1 means a scout carrying the flag has a capture rate of x3 while returning his own flag, while everyone else is x2)

`sm_ictf_cap_hud <0/[1]>` - enable/disable the HUD elements showing the return time left and the capture rate for dropped flags.

`sm_ictf_cap_visualizer <0/1/[2]>` - controls visual indicators around dropped flags.  
0: disabled entirely (no visualizer)  
1: the outer ring is the capture area, the inner ring shrinks as the return time decreases. (old visualizer)  
2: the inner  and outer ring both do not move, and the visualizer is basically a "holographic control point."  

`sm_ictf_cap_assist <0/[1]>` - enable/disable the custom carry-time based assist system.

`sm_ictf_coverkills <0/[1]>` - enable/disable the cover-kill system.
## planned features
* round timer & overtime mechanics so that rounds don't last 45 minutes
* output additional log events for competitive log parsers (returns, saves, covers, cap assists, etc)
* stop being lazy and keep track of players who return the flag for some extra systems
  * "close save" system from SmartCTF (returns near enemy capture zone)
  * "\<player\> defended the intelligence!" killfeed notices for returns, maybe? 

## changelog
```
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