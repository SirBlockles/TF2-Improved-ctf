/*
	Improved CTF EX
	by muddy
	
	gameplay tweaks to make CTF more fast-paced, preventing teams from being in double-defending
	situations, as well as a couple other tweaks to encourage teamplay and working together.
	my ultimate goal is that this plugin, combined with well-designed maps, could unleash the true
	gameplay potential of CTF, held back only by its few critical design flaws.
	
	TODO:
	GAMEPLAY:
	* playtesting!
	
	COSMETIC:
	* "mission begins in 20 seconds" if setup time is between 20-30 seconds (as is the default value)
	
	TECHNICAL:
	* leaving the plugin running for a long time (eg overnight) makes flags eventually crash clients on drop... why?
	* see if there's a way to surpress "possibly unintended assignment" warning - it is, in fact, intended
	* translation keys for HUD alerts, location text, and coverkills?
	
	CREDITS:
	https://forums.alliedmods.net/showthread.php?t=98812 - code snippet for finding center of capture zone brush ents
*/

//uncomment to enable debug mode
//#define DEBUG

//stock includes
#include <sourcemod>
#include <entity>
#include <tf2>
#include <tf2_stocks>
#include <clientprefs>

//custom includes
#include <tf2_gamemode>
#include <tf2_roundtime>
#include <sdkhooks>
#include <tf2attributes>

#pragma newdecls required;
#pragma semicolon 1;

//default hudtext locations. can be adjusted by clients with cookies.
#define TEXT_X 0.01
#define TEXT_YRED 0.4
#define TEXT_YBLU -0.4

const int MAX_FLAGS = 12; //technically this whole time this plugin has been theoretically written to support maps like achievement engineer that have more than 1 flag per team, but i've never actually *tested* it...

//logic vars
int flagEnts[MAX_FLAGS];
bool capBlocked[MAX_FLAGS];
Handle ringTimers[MAX_FLAGS];
float carryTime[MAX_FLAGS][MAXPLAYERS+1];
float grabTick[MAX_FLAGS];
int flagCarrier[MAX_FLAGS];
int firstCarrier[MAX_FLAGS];
float flagDropPos[MAX_FLAGS][3];
int roundTimer = -1;
int redTeamEnt, bluTeamEnt;
bool roundEndManual = false;

//cvars
ConVar cvar_cap_time;
ConVar cvar_cap_overtime;
ConVar cvar_cap_radius;
ConVar cvar_cap_bonus;
ConVar cvar_cap_carrierbonus;
ConVar cvar_cap_respawn;
ConVar cvar_cap_visualizer;
ConVar cvar_cover;
ConVar cvar_capassist;
ConVar cvar_roundtime;
ConVar cvar_roundtime_setuptime;
ConVar cvar_roundtime_starttime;
ConVar cvar_roundtime_maxtime;
ConVar cvar_roundtime_cap_time;
ConVar cvar_roundtime_cap_mode;
ConVar cvar_roundtime_overtime;
ConVar cvar_hud_dropstatus;
ConVar cvar_hud_carrystatus;
ConVar cvar_hud_alerts;

//clientprefs
Cookie plyPrefXPosRed, plyPrefYPosRed, plyPrefXPosBlu, plyPrefYPosBlu;

//sprites
int beam_sprite;
int halo_sprite;

public Plugin myinfo =  {
	name = "Improved CTF",
	author = "muddy & Ribbon",
	description = "CTF tweaks that minimise and discourage stalematey and defensive play",
	version = "3.0",
	url = "https://github.com/SirBlockles/improved-CTF"
}

public void OnPluginStart() {
	//Set ConVars for this plugin
	cvar_cap_time = CreateConVar("sm_ictf_cap_time", "25", "Time, in seconds, flag takes to return without player influence.", FCVAR_NONE, true, 0.1, true, 90.0);
	cvar_cap_overtime = CreateConVar("sm_ictf_cap_overtime", "1.0", "sm_ictf_cap_bonus is multiplied by this value during overtime.", FCVAR_NONE, true, 0.0, true, 20.0);
	cvar_cap_bonus = CreateConVar("sm_ictf_cap_bonus", "0.25", "how much time (in seconds) is shaved off per capture rate every time the flag runs a think tick (approx. every 0.25 sec)", FCVAR_NONE, true, 0.0, false);
	cvar_cap_radius = CreateConVar("sm_ictf_cap_radius", "115.0", "Determines radius of flag return & block area", FCVAR_NONE, true, 0.0, false);
	cvar_cap_visualizer = CreateConVar("sm_ictf_cap_visualizer", "2", "Visualize return area of dropped flag?\n0- Do not show capture area\n1- Show capture ring, plus shrinking inner ring\n2- Show outer ring, static inner ring", FCVAR_NONE, true, 0.0, true, 2.0);
	cvar_cap_respawn = CreateConVar("sm_ictf_cap_respawn", "1", "Respawn rules for when a team's flag is captured:\n0- Do not respawn anyone on flag capture\n1- Respawn team whose flag has been captured\n2- Respawn team whose flag has been captured, only if they're now behind in score", FCVAR_NONE, true, 0.0, true, 2.0);
	cvar_cap_carrierbonus = CreateConVar("sm_ictf_cap_carrierbonus", "1", "Capture rate modifier for flag carrier (eg value of 1 = flag carrier counts as x2 to return their own flag, or x3 if they are scout)", FCVAR_NONE, true, 0.0, true, 10.0);
	cvar_capassist = CreateConVar("sm_ictf_cap_assist", "1", "If enabled, replace TF2's cap assist system with one that awards the assist based on carry time.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_cover = CreateConVar("sm_ictf_coverkills", "2", "Cover-kill system. Adds HUD alerts showing when a player killed someone threatening the flag carrier.\n0- Do not enable coverkills at all\n1- Enable coverkill notifications for all kills that protect the flag carrier\n2-Enable coverkill notifications but not for when the flag carrier self-defends", FCVAR_NONE, true, 0.0, true, 2.0);
	cvar_roundtime = CreateConVar("sm_ictf_roundtime_enable", "1", "Enable iCTF round time management. If a map has an existing round timer, this plugin will hijack that one and use custom timing.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_roundtime_setuptime = CreateConVar("sm_ictf_roundtime_setup", "26", "Time, in seconds, of setup phase. Flags cannot be picked up during setup time. If set to 0, there will be no setup phase.", FCVAR_NONE, true, 0.0, true, 101.0);
	cvar_roundtime_starttime = CreateConVar("sm_ictf_roundtime_starttime", "600", "Time, in seconds, the round starts with.", FCVAR_NONE, true, 0.0, true, 3200.0);
	cvar_roundtime_maxtime = CreateConVar("sm_ictf_roundtime_maxtime", "720", "Round time cap. Capturing the flag will not add time beyond this amount.", FCVAR_NONE, true, 0.0, true, 3200.0);
	cvar_roundtime_cap_time = CreateConVar("sm_ictf_roundtime_capture_time", "120", "Time, in seconds, to add to the round time on capture. Use the capture mode CVAR to adjust rules for when this time is added.", FCVAR_NONE, true, 0.0, true, 3200.0);
	cvar_roundtime_cap_mode = CreateConVar("sm_ictf_roundtime_capture_mode", "1", "Conditions for when round time is added on capture:\n0- Round time is not added, ever\n1- Round time is added when scores are even, or capturing team is losing\n2- Round time is added *ONLY* if capturing team is losing\n3- Round time is added on every capture, regardless of score", FCVAR_NONE, true, 0.0, true, 3.0);
	cvar_roundtime_overtime = CreateConVar("sm_ictf_roundtime_overtime", "1", "Overtime rules for iCTF timer:\n0- no overtime (round ends in stalemate if tied)\n1- overtime if tied and both flags are out - first flag to return home wins. stalemate otherwise", FCVAR_NONE, true, 0.0, true, 2.0);
	cvar_hud_dropstatus = CreateConVar("sm_ictf_hud_dropped", "1", "Enables/disables HUD text showing capture rate and return time when flag is dropped", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_hud_carrystatus = CreateConVar("sm_ictf_hud_carried", "1", "Enables/disables HUD text showing who is carrying the flag\n0- do not show at all\n1- show carrier name and location\n2- show carrier name without location", FCVAR_NONE, true, 0.0, true, 2.0);
	cvar_hud_alerts = CreateConVar("sm_ictf_hud_alerts", "1", "Enables/disables enhanced HUD alerts which are shorter, include player names, and return events. (eg: \"Your team dropped the enemy intelligence!\" -> \"<player> dropped the RED/BLU flag!\")", FCVAR_NONE, true, 0.0, true, 1.0);
	
	//hooks
	HookEntityOutput("item_teamflag", "OnDrop1", flagDrop);
	HookEntityOutput("item_teamflag", "OnReturn", flagReturn);
	HookEntityOutput("item_teamflag", "OnPickup1", flagPickup);
	HookEntityOutput("item_teamflag", "OnCapture1", flagCapture);
	HookEvent("teamplay_round_start", roundStart);
	HookEvent("teamplay_win_panel", roundWinEvent, EventHookMode_Pre);
	HookEvent("player_death", playerDeathEvent);
	
	//clientprefs
	plyPrefXPosRed = RegClientCookie("ictf_hudpos_red_x", "position of RED's HUD text on the X axis. a value of 0.0 aligns left. Use a negative number to align right.", CookieAccess_Public);
	plyPrefYPosRed = RegClientCookie("ictf_hudpos_red_y", "position of RED's HUD text on the Y axis. a value of 0.0 aligns top. Use a negative number to align bottom.", CookieAccess_Public);
	plyPrefXPosBlu = RegClientCookie("ictf_hudpos_blu_x", "position of BLU's HUD text on the X axis. a value of 0.0 aligns left. Use a negative number to align right.", CookieAccess_Public);
	plyPrefYPosBlu = RegClientCookie("ictf_hudpos_blu_y", "position of BLU's HUD text on the Y axis. a value of 0.0 aligns top. Use a negative number to align bottom.", CookieAccess_Public);
}

public void OnMapStart() {
	//flush flag table on new map
	for(int i = 0; i < MAX_FLAGS; i++) {
		flagEnts[i] = -1;
		if(ringTimers[i] != INVALID_HANDLE) { KillTimer(ringTimers[i]); }
	}
	
	int temp = -1;
	while ((temp = FindEntityByClassname(temp, "tf_team")) != INVALID_ENT_REFERENCE) {
		if(GetEntProp(temp, Prop_Send, "m_iTeamNum") == 2) { redTeamEnt = temp; }
		else if (GetEntProp(temp, Prop_Send, "m_iTeamNum") == 3) { bluTeamEnt = temp; }
	}
	
	if (redTeamEnt == -1 || bluTeamEnt == -1) {
		SetFailState("[iCTF] FATAL: Could not find tf_team entities for RED and BLU");
	}
	
	//precache the laser sprites for flag hologram
	beam_sprite = PrecacheModel("materials/sprites/laserbeam.vmt");  
	halo_sprite = PrecacheModel("materials/sprites/glow01.vmt");
}

public Action roundStart(Event event, const char[] name, bool dontBroadcast) {
	bool firstRound = GetEventBool(event, "full_reset");
	
	//flag entities don't reset between rounds, so only hook them on the first round to prevent multi-hooking
	if(firstRound) {
		hookAllFlags();
		SetConVarInt(FindConVar("tf_flag_return_on_touch"), 1, true);
		
		#if defined DEBUG
		PrintToChatAll("[DEBUG] round is a full restart, hooking flag entities...");
		#endif
	} 
	
	roundEndManual = false;
	
	//clean up temporary values every round.
	for(int i = 0; i < MAX_FLAGS; i++) {
		for(int j = 1; j <= MaxClients; j++) {
			carryTime[i][j] = 0.0;
		}
		carryTime[i][0] = 0.0;
		grabTick[i] = 0.0;
		flagCarrier[i] = -1;
		firstCarrier[i] = -1;
		capBlocked[i] = false;
		
		flagDropPos[i] = NULL_VECTOR;
	}
	
	int timerMode = GetConVarInt(cvar_roundtime);
	if(getTFMode() == TFMode_CTF && timerMode > 0) {		
		roundTimer = findRoundTimer(true);
		
		SetVariantInt(1);
		AcceptEntityInput(roundTimer, "ShowInHUD");
		
		SetVariantInt(GetConVarInt(cvar_roundtime_maxtime));
		AcceptEntityInput(roundTimer, "SetMaxTime");
		
		int setupTime = GetConVarInt(cvar_roundtime_setuptime);
		if(setupTime > 0) {
			SetVariantInt(setupTime);
			AcceptEntityInput(roundTimer, "SetSetupTime");
		} else { RequestFrame(startRound); } //round timers need a single frame to have their time set correctly
		
		HookSingleEntityOutput(roundTimer, "OnSetupFinished", timerSetupEnd, true);
		HookSingleEntityOutput(roundTimer, "OnFinished", timerRoundEnd, true);
		
		DispatchSpawn(roundTimer);
		AcceptEntityInput(roundTimer, "Resume");
	}
	
	return Plugin_Handled;
}

void timerSetupEnd(const char[] output, int caller, int activator, float delay) {
	RequestFrame(startRound); //timer needs a single frame to accept starting the round time
}

void timerRoundEnd(const char[] output, int caller, int activator, float delay) {
	int redScore = GetEntProp(redTeamEnt, Prop_Send, "m_nFlagCaptures");
	int bluScore = GetEntProp(bluTeamEnt, Prop_Send, "m_nFlagCaptures");
	bool redSecure = true;
	bool bluSecure = true;
	TFTeam winningTeam = TFTeam_Unassigned;
	roundEndManual = true;
	
	if(redScore > bluScore) {
		winningTeam = TFTeam_Red;
	} else if (bluScore > redScore) {
		winningTeam = TFTeam_Blue;
	} else { //if scores are tied, consult flag status to determine next move
		for(int i = 0; i < MAX_FLAGS; i++) {
			if(flagEnts[i] > 0) {
				if( GetEntProp(flagEnts[i], Prop_Send, "m_iTeamNum") == 2) { //flag is red
					if(GetEntProp(flagEnts[i], Prop_Send, "m_nFlagStatus") != 0) {
						redSecure = false;
					}
				} else if (GetEntProp(flagEnts[i], Prop_Send, "m_iTeamNum") == 3) { //flag is blu
					if(GetEntProp(flagEnts[i], Prop_Send, "m_nFlagStatus") != 0) {
						bluSecure = false;
					}
				}
			}
		}
	}
	
	#if defined DEBUG
	PrintToChatAll("[DEBUG] win evaluation: red: %i, blu: %i", redSecure, bluSecure);
	#endif
	
	if(GetConVarBool(cvar_roundtime_overtime)) { //overtime win condition handling
		if(!redSecure && !bluSecure) { //neither team's flag is home, so overtime
			GameRules_SetProp("m_bInOvertime", 1);
			PrintCenterTextAll("FIRST FLAG RETURNED WINS!");
			return;
		} else if(redSecure && !bluSecure) { //if one team's flag is home, and not the other, then they win overtime before it even starts
			winningTeam = TFTeam_Red;
		} else if(bluSecure && !redSecure) {
			winningTeam = TFTeam_Blue;
		} //if both teams flags are home, then neither team wins and it's a stalemate.
	}
	//end the round
	int winEnt = -1;
	winEnt = FindEntityByClassname(winEnt, "game_round_win");
	
	if (winEnt < 1) {
		winEnt = CreateEntityByName("game_round_win");
		if (IsValidEntity(winEnt)) { DispatchSpawn(winEnt); }
		else { PrintToChatAll("[iCTF] FATAL: Could not create game_round_win entity! Round can't end! This is a bug!"); }
	}
	
	SetVariantInt(view_as<int>(winningTeam));
	AcceptEntityInput(winEnt, "SetTeam");
	AcceptEntityInput(winEnt, "RoundWin");
	
	//force return all flags after the round has ended
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flagEnts[i] > 0) {
			AcceptEntityInput(flagEnts[i], "ForceReset");
		}
	}
}

void startRound() {
	SetVariantInt(GetConVarInt(cvar_roundtime_starttime));
	AcceptEntityInput(roundTimer, "SetTime");
}

//we have to set this as soon as gamerules is created so that vanilla CTF overtime doesn't fire.
public void OnEntityCreated(int ent, const char[] classname) {
	if(StrEqual(classname, "tf_gamerules")) {
		#if defined DEBUG
		PrintToServer("[DEBUG] iCTF: Found gamerules, patching overtime...");
		#endif
		
		DispatchKeyValue(ent, "ctf_overtime", "0");
		SetEntProp(ent, Prop_Data, "m_bOvertimeAllowedForCTF", 0);
	}
}

public Action roundWinEvent(Event event, const char[] name, bool dontBroadcast) {
	TFTeam winningTeam = view_as<TFTeam>(GetEventInt(event, "winning_team"));
	int redScore = GetEntProp(redTeamEnt, Prop_Send, "m_nFlagCaptures");
	int bluScore = GetEntProp(bluTeamEnt, Prop_Send, "m_nFlagCaptures");
	
	//firing game_round_win manually makes some of this information incorrect, so we have to fix it up
	if(getTFMode() == TFMode_CTF && roundEndManual) {
		//set to full round rather than multi-stage mini-round
		SetEventInt(event, "round_complete", 1);
		
		//set win reason text based on round outcome.
		//default value of 4 is already "you're ALL losers!" from stalemate, so only change it if a team wins
		if(winningTeam != TFTeam_Unassigned) {
			if(redScore == bluScore) { SetEventInt(event, "winreason", 11); } //"<team> defended their reactor core until it returned" is as close as vanilla win reasons can get to describing the overtime win condition
			else { SetEventInt(event, "winreason", 6); } //"<team> had more points when the time limit was reached"
		}
	}
	
	return Plugin_Continue;
}

void flagThink(int flag) {
	//known flag types: 0 = CTF, 4 = SD australium
	//unknown flagtypes: neutral/1-flag CTF? MvM bomb?
	if(GetEntProp(flag, Prop_Send, "m_nType") != 0) { return; }	//ignore flags that aren't CTF flags
	int flagArrIndex = -1;
	TFTeam flagTeam = view_as<TFTeam>(GetEntProp(flag, Prop_Send, "m_iTeamNum"));
	char hudText[128];
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flag == flagEnts[i]) {
			flagArrIndex = i;
		}
	}
	
	if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 0) { // FLAG IS AT HOME
		if(GameRules_GetProp("m_bInSetup")) { //make flag non-solid during setup time
			SetEntProp(flag, Prop_Send, "m_usSolidFlags", 4);
			SetEntProp(flag, Prop_Send, "m_nSolidType", 1);
		} else {
			SetEntProp(flag, Prop_Send, "m_usSolidFlags", 140);
			SetEntProp(flag, Prop_Send, "m_nSolidType", 0);
		}
	} else if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 1) { // FLAG IS BEING CARRIED
		if(GetConVarInt(cvar_hud_carrystatus) > 0 && flagCarrier[flagArrIndex] > 0) {
			Format(hudText, sizeof(hudText), "%N", flagCarrier[flagArrIndex]);
		}
		
	} else if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 2) { // FLAG IS DROPPED
		float flagPos[3];
		float plyPos[3];
		float dist;
		float capRadius = GetConVarFloat(cvar_cap_radius);
		TFTeam plyTeam;
		GetEntPropVector(flag, Prop_Send, "m_vecOrigin", flagPos);
		int friendlyCapForce = 0;
		bool enemyCapForce = false;
		
		for(int i = 1; i <= MaxClients; i++) {
			if(i < 1 || i >= MaxClients || !IsClientInGame(i) || !IsPlayerAlive(i)) { continue; }
			
			plyTeam = TF2_GetClientTeam(i);
			GetClientAbsOrigin(i, plyPos);
			dist = GetVectorDistance(flagPos, plyPos);
			
			capBlocked[flagArrIndex] = false; //reset our globally tracked capture block, and only re-true it if another player is within the capture zone this think cycle.
			
			if(dist <= capRadius) { //player is within "capture" radius
				if(plyTeam == flagTeam && condCheck(i)) {
					friendlyCapForce += 1;
					if(TF2_GetPlayerClass(i) == TFClass_Scout) { friendlyCapForce = friendlyCapForce + 1; }
					
					for(int j = 0; j < MAX_FLAGS; j++) {
						if(flagCarrier[j] == i) { friendlyCapForce += GetConVarInt(cvar_cap_carrierbonus); } //grant extra capture rate to flag carriers if enabled (ie blu carrier returning blu flag)
					}
					
					//scan players' weapons and check for capture rate bonus attrib (pain train or custom weapons)
					for(int j = 0; j <= 2; j++) {
						friendlyCapForce = friendlyCapForce + TF2Attrib_HookValueInt(0, "add_player_capturevalue", GetPlayerWeaponSlot(i, j));
					}
				}
			}
		}
		
		//after same-team players have been calculated, do stuff for enemy-team players.
		//we could've included this in one for loop if not for the chance that the first player in the loop is an enemy.
		//if that were the case, they couldn't see the centertext since friendlyCapForce isn't above 0 yet, so we have to
		//write two separate for loops anyway, might as well just do it this way.
		for(int i = 1; i <= MaxClients; i++) {
			if(i < 1 || i >= MaxClients || !IsClientInGame(i) || !IsPlayerAlive(i)) { continue; }
			
			plyTeam = TF2_GetClientTeam(i);
			GetClientAbsOrigin(i, plyPos);
			dist = GetVectorDistance(flagPos, plyPos);
			
			capBlocked[flagArrIndex] = false;
			
			if(dist <= capRadius) { //player is within "capture" radius
				if(plyTeam != flagTeam && condCheck(i)) {
					enemyCapForce = true;
					capBlocked[flagArrIndex] = true;
					if(friendlyCapForce > 0) { PrintCenterText(i, "An enemy is blocking flag pickup!"); }
				}
			}
		}
		
		//make flag non-solid when a friendly is returning it, so that defenders can prevent people running in and resetting the return time by grabbing it and dying.
		if(friendlyCapForce > 0) {
			SetEntProp(flag, Prop_Send, "m_usSolidFlags", 4);
			SetEntProp(flag, Prop_Send, "m_nSolidType", 1);
		} else {
			SetEntProp(flag, Prop_Send, "m_usSolidFlags", 140);
			SetEntProp(flag, Prop_Send, "m_nSolidType", 0);
		}
		
		if(GetConVarBool(cvar_hud_dropstatus)) {
			Format(hudText, sizeof(hudText), "%i", RoundToNearest(GetEntPropFloat(flag, Prop_Send, "m_flResetTime") - GetGameTime()));
		}
		
		if(enemyCapForce) { //if even a single enemy is on the cap, block it from progressing at all
			SetEntPropFloat(flag, Prop_Send, "m_flResetTime", GetEntPropFloat(flag, Prop_Send, "m_flResetTime") + 0.255); //technically the flag's think cycle is scheduled to run every 0.25s but over time it still goes down veeeeery slowly. at 0.255 it doesn't... just gonna roll with it :D
			capBlocked[flagArrIndex] = true;
			
			if(GetConVarBool(cvar_hud_dropstatus)) { Format(hudText, sizeof(hudText), "(\\)\n%s", hudText); } //i wonder if someone knows a prettier way to depict the "no" sign with text that would work here
		} else {
			float overtimeFactor = 1.0;
			if(GameRules_GetProp("m_bInOvertime")) { overtimeFactor = GetConVarFloat(cvar_cap_overtime); } //only get overtime factor during overtime, otherwise the value of 1.0 will leave it unchanged.
			
			float capFactor = (GetConVarFloat(cvar_cap_bonus) * overtimeFactor) * friendlyCapForce;
			SetEntPropFloat(flag, Prop_Send, "m_flResetTime", GetEntPropFloat(flag, Prop_Send, "m_flResetTime") - capFactor);
			capBlocked[flagArrIndex] = false;
			
			if(GetConVarBool(cvar_hud_dropstatus)) {
				if(friendlyCapForce > 0) {
					Format(hudText, sizeof(hudText), "x%i\n%s", friendlyCapForce, hudText);
				} else {
					Format(hudText, sizeof(hudText), " \n%s", hudText);
				}
			}
		}
	}
	
	//location string logic
	int locationMode = GetConVarInt(cvar_hud_carrystatus);
	if(locationMode == 1 && GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 1 && flagCarrier[flagArrIndex] > 0) { //only show location while on the move, stock compass is good for when dropped
		
		float flagRatio;
		
		if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 1) { //carried
			float pos[3];
			GetEntPropVector(flagCarrier[flagArrIndex], Prop_Send, "m_vecOrigin", pos);
			flagRatio = calcFlagDistRatio(pos);
		} else if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 2) { //dropped
			float pos[3];
			GetEntPropVector(flag, Prop_Send, "m_vecOrigin", pos);
			flagRatio = calcFlagDistRatio(pos);
		}
		
		if(flagRatio < 0.18) {
			Format(hudText, sizeof(hudText), "%s\nRED Intel", hudText);
		} else if(flagRatio < (1.0/1.8)) {
			Format(hudText, sizeof(hudText), "%s\nRED Base", hudText);
		} else if(flagRatio < 1.8) {
			Format(hudText, sizeof(hudText), "%s\nMid", hudText);
		} else if(flagRatio < (1.0/0.18)) {
			Format(hudText, sizeof(hudText), "%s\nBLU Base", hudText);
		} else {
			Format(hudText, sizeof(hudText), "%s\nBLU Intel", hudText);
		}
		
		#if defined DEBUG
		Format(hudText, sizeof(hudText), "%s (%.2f)", hudText, flagRatio);
		#endif
	} else if(locationMode == 2 && GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 1) {
		Format(hudText, sizeof(hudText), "%s\n ", hudText); //add empty 2nd line so that players aligning text from the bottom up will have consistent placement
	}
	
	//print the HUD text if not empty, and not for neutral flags
	if(hudText[0] != '\0' && flagTeam != TFTeam_Unassigned) {
	
		for(int i=1; i <= MaxClients; i++) {
			//setup position and color
			
			if(!IsClientInGame(i) || IsFakeClient(i)) { continue; }
			
			switch(flagTeam) {
				case TFTeam_Red: {
					char workStr[16];
					float xPos, yPos;
					
					GetClientCookie(i, plyPrefXPosRed, workStr, sizeof(workStr));
					if(workStr[0] != '\0') {
						xPos = StringToFloat(workStr);
					} else {
						xPos = TEXT_X;
					}
					
					
					GetClientCookie(i, plyPrefYPosRed, workStr, sizeof(workStr));
					if(workStr[0] != '\0') {
						yPos = StringToFloat(workStr);
					} else {
						yPos = TEXT_YRED;
					}
					
					SetHudTextParams(xPos, yPos, 0.27, 255, 120, 120, 255, 0, 0.0, 0.0, 0.0);
				} case TFTeam_Blue: {
					char workStr[16];
					float xPos, yPos;
					
					GetClientCookie(i, plyPrefXPosBlu, workStr, sizeof(workStr));
					if(workStr[0] != '\0') {
						xPos = StringToFloat(workStr);
					} else {
						xPos = TEXT_X;
					}
					
					
					GetClientCookie(i, plyPrefYPosBlu, workStr, sizeof(workStr));
					if(workStr[0] != '\0') {
						yPos = StringToFloat(workStr);
					} else {
						yPos = TEXT_YBLU;
					}
					
					SetHudTextParams(xPos, yPos, 0.27, 120, 120, 255, 255, 0, 0.0, 0.0, 0.0);
				}
			}
			ShowHudText(i, -1, hudText);
		}
	}
}

//block same-team touching to override insta-returning when tf_flag_return_on_touch is set to 1
//this lets the return cvar adjust the "flag must be home to capture" mechanic without overriding my return system.
Action flagTouch(int flag, int ply) {
	if(ply <= MaxClients && ply > 0 && IsClientConnected(ply)) {
		if(GetClientTeam(ply) == GetEntProp(flag, Prop_Send, "m_iTeamNum")) {
			
			return Plugin_Stop;
		}
	}
	return Plugin_Continue;
}

/*
	I am stoned as fuck trying to write code for some reason, so here's my goal here:
	1) Make a timer, it needs to know the flag it is generating the ring for.
	2) Loop it every 0.015 (1 tick) sec, move the ring generation code into here
	3) check the capBlocked[] array with your flag's array index, and change hologram behavior for when capture is blocked (colors)
*/
Action drawRingTimer(Handle timer, int flag) {
	float flagPos[3];
	GetEntPropVector(flag, Prop_Send, "m_vecOrigin", flagPos);
	TFTeam flagTeam = view_as<TFTeam>(GetEntProp(flag, Prop_Send, "m_iTeamNum"));
	int flagArrIndex;
	
	for(int j = 0; j < MAX_FLAGS; j++) {
		if(flag == flagEnts[j]) {
			flagArrIndex = j;
		}
	}
	
	int ringColor[4];
	int innerColor[4];
	
	if(flagTeam == TFTeam_Unassigned) { //neutral flag futureproofing - 1flag CTF/SD support is on the "eventually" list but not until standard CTF is feature-complete
		if(!capBlocked[flagArrIndex]) {
			ringColor = {255,255,255,145};
			innerColor = {120,120,120,200};
		} else {
			ringColor = {150,150,150,185};
			innerColor = {50,50,50,255};
		}
	} else if (flagTeam == TFTeam_Red) {
		if(!capBlocked[flagArrIndex]) {
			ringColor = {255,192,192,120};
			innerColor = {255,75,75,150};
		} else {
			ringColor = {255,120,120,140};
			innerColor = {255,0,0,150};
		}
	} else if(flagTeam == TFTeam_Blue) {
		if(!capBlocked[flagArrIndex]) {
			ringColor = {192,192,255,120};
			innerColor = {75,75,255,150};
		} else {
			ringColor = {120,120,255,140};
			innerColor = {0,0,255,150};
		}
	}
	
	float innerRadius = (GetEntPropFloat(flag, Prop_Send, "m_flResetTime")-GetGameTime()) * (GetConVarFloat(cvar_cap_radius)/(GetConVarFloat(cvar_cap_time)/2));
	
	//make the visual capture area a bit smaller than it actually is - hard-coded 15 Hu smaller in radius; a 140 radius will look like 125
	TE_SetupBeamRingPoint(flagPos, GetConVarFloat(cvar_cap_radius)*2-20.0, (GetConVarFloat(cvar_cap_radius)*2-20.1), beam_sprite, halo_sprite, 0, 0, 0.22, 4.0, 0.0, ringColor, 1, 0);
	TE_SendToAll();
	if(GetConVarInt(cvar_cap_visualizer) == 2) {
		TE_SetupBeamRingPoint(flagPos, 60.1, 60.0, beam_sprite, halo_sprite, 0, 0, 0.22, 2.0, 0.0, innerColor, 1, 0);
	} else {
		TE_SetupBeamRingPoint(flagPos, innerRadius-20.0, (innerRadius - 20.1), beam_sprite, halo_sprite, 0, 0, 0.22, 2.0, 0.0, innerColor, 1, 0);
	}
	TE_SendToAll();
	
	if(!IsValidEntity(flag) || !IsValidEdict(flag)) { return Plugin_Stop; } //we're running a loop where somehow the flag stopped existing without being returned first
	if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 2) { ringTimers[flagArrIndex] = CreateTimer(0.16, drawRingTimer, flag); } //loop for as long as we are dropped
	return Plugin_Continue;
}

//cover-kill system. inspired by and heavily based on Unreal Tournament's SmartCTF mod.
public Action playerDeathEvent(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int killer = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	int deathflags = GetEventInt(event, "death_flags");
	//ignore deadringer, suicides, world deaths ("finished off" is not a world death), or if disabled
	if(deathflags & TF_DEATHFLAG_DEADRINGER || killer <= 0 || victim == killer || GetConVarInt(cvar_cover) < 1) { return Plugin_Continue; }
	
	float killerPos[3], victimPos[3], killerAng[3], victimAng[3];
	
	GetClientEyePosition(killer, killerPos);
	GetClientEyeAngles(killer, killerAng);
	
	GetClientEyePosition(victim, victimPos);
	GetClientEyeAngles(victim, victimAng);
	
	float posDiff_KillerVictim[3]; SubtractVectors(killerPos, victimPos, posDiff_KillerVictim);
	
	//get forward angle vectors from eye angles
	GetAngleVectors(victimAng, victimAng, NULL_VECTOR, NULL_VECTOR);
	GetAngleVectors(killerAng, killerAng, NULL_VECTOR, NULL_VECTOR);
	
	NormalizeVector(killerAng, killerAng);
	NormalizeVector(victimAng, victimAng);
	NormalizeVector(posDiff_KillerVictim, posDiff_KillerVictim);
	
	for(int i = 0; i < MAX_FLAGS; i++) { //check for cover kills for each flag when a player is killed
		if(flagCarrier[i] > 0 && GetClientTeam(flagCarrier[i]) == GetClientTeam(killer)) {
			bool coverKill = false;
			
			float carrierPos[3];
			GetClientEyePosition(flagCarrier[i], carrierPos);
			
			Handle rayVictimCarrier = TR_TraceRayFilterEx(victimPos, carrierPos, MASK_NPCWORLDSTATIC, RayType_EndPoint, RayFilter_Vision);
			Handle rayKillerCarrier = TR_TraceRayFilterEx(killerPos, carrierPos, MASK_NPCWORLDSTATIC, RayType_EndPoint, RayFilter_Vision);
			
			float posDiff_VictimCarrier[3]; SubtractVectors(victimPos, carrierPos, posDiff_VictimCarrier);
			NormalizeVector(posDiff_VictimCarrier, posDiff_VictimCarrier);
			float angleDiff_VictimCarrier = GetVectorDotProduct(posDiff_VictimCarrier, victimAng);
			
			//COVER-KILL CHECKS
			//1) victim was within 512 Hu or killer was within 256 Hu of the carrier
			if(GetVectorDistance(victimPos, carrierPos, false) <= 512) {
				#if defined DEBUG
				PrintToChatAll("[DEBUG] %N defended %N from %N because %N fulfilled condition 1a", killer, flagCarrier[i], victim, victim);
				#endif
				coverKill = true;
			}
			
			else if(GetVectorDistance(killerPos, carrierPos, false) <= 256) {
				#if defined DEBUG
				PrintToChatAll("[DEBUG] %N defended %N from %N because %N fulfilled condition 1b", killer, flagCarrier[i], victim, killer);
				#endif
				coverKill = true;
			}
			
			//2) victim is within 1536 Hu of carrier, and can see them both in angle and in obstruction (raytrace)
			if(GetVectorDistance(victimPos, carrierPos, false) <= 1600 && angleDiff_VictimCarrier <= -0.58 && !TR_DidHit(rayVictimCarrier)) {
				#if defined DEBUG
				PrintToChatAll("[DEBUG] %N defended %N from %N because %N fulfilled condition 2", killer, flagCarrier[i], victim, victim);
				#endif
				coverKill = true;
			}
			
			//3) victim is within 1024 Hu of carrier, and KILLER has line-of-sight on carrier
			else if(GetVectorDistance(victimPos, carrierPos, false) <= 1024 && !TR_DidHit(rayKillerCarrier)) {
				#if defined DEBUG
				PrintToChatAll("[DEBUG] %N defended %N from %N because %N fulfilled condition 3", killer, flagCarrier[i], victim, killer);
				#endif
				coverKill = true;
			}
			
			//4) victim is within 768 Hu of carrier, has line-of-sight, but is turned away from carrier (else would've triggered #2)
			else if(GetVectorDistance(victimPos, carrierPos, false) <= 768 && !TR_DidHit(rayVictimCarrier)) {
				#if defined DEBUG
				PrintToChatAll("[DEBUG] %N defended %N from %N because %N fulfilled condition 4", killer, flagCarrier[i], victim, victim);
				#endif
				coverKill = true;
			}
			
			//5) victim is a scoped-in sniper, within 3200 Hu of carrier, that has line-of-sight and is aiming at the carrier
			//use scoped in OR sniper check together for soft-support for randomizer or other plugins that give the other classes sniper rifles
			else if((TF2_IsPlayerInCondition(victim, TFCond_Zoomed) || TF2_GetPlayerClass(victim) == TFClass_Sniper) && GetVectorDistance(victimPos, carrierPos, false) <= 3200 && angleDiff_VictimCarrier <= -0.98 && !TR_DidHit(rayVictimCarrier)) {
				#if defined DEBUG
				PrintToChatAll("[DEBUG] %N defended %N from %N because %N fulfilled condition 5", killer, flagCarrier[i], victim, victim);
				#endif
				coverKill = true;
			}
			
			//we've successfully covered the flag carrier. woohoo!
			if(coverKill) {
				if(killer == flagCarrier[i] && GetConVarInt(cvar_cover) == 1) {
					PrintCenterTextAll("%N covered their own ass!", killer);
				} else if(killer != flagCarrier[i]) {
					PrintCenterTextAll("%N covered the flag carrier!", killer);
				}
			}
			
			//clean up our raytrace handles now that we're done
			delete rayVictimCarrier;
			delete rayKillerCarrier;
		}
	}
	
	return Plugin_Continue;
}

//calculate distance to the capture zone of each team to determine how close to that team's base the supplied entity is.
float calcFlagDistRatio(float pos[3]) {	
	float basePos[3], redDist, bluDist;
	int baseEnt = -1;
	
	while(baseEnt = FindEntityByClassname(baseEnt, "func_capturezone")) {
		if(baseEnt == -1) { break; }
		
		TFTeam baseTeam = view_as<TFTeam>(GetEntProp(baseEnt, Prop_Send, "m_iTeamNum"));
		
		float baseMins[3], baseMaxs[3];
		
		GetEntPropVector(baseEnt, Prop_Send, "m_vecOrigin", basePos);
		GetEntPropVector(baseEnt, Prop_Send, "m_vecMins", baseMins);
		GetEntPropVector(baseEnt, Prop_Send, "m_vecMaxs", baseMaxs);
		
		basePos[0] += (baseMins[0] + baseMaxs[0]) * 0.5;
		basePos[1] += (baseMins[1] + baseMaxs[1]) * 0.5;
		basePos[2] += (baseMins[2] + baseMaxs[2]) * 0.5;
		
		if(baseTeam == TFTeam_Red) {
			redDist = GetVectorDistance(basePos, pos);
		} else if(baseTeam == TFTeam_Blue) {
			bluDist = GetVectorDistance(basePos, pos);
		} else { //???
			continue;
		}
	}

	return redDist / bluDist;
}

bool RayFilter_Vision(int ent, int contentsMask) { //if a trace hits without entities, it's theoretically a potential sniper headshot and thus "line-of-sight"
	return false;
}

//reset collision so players can pick up flags again
void flagResetSolid(int flag) {
	SetEntProp(flag, Prop_Send, "m_usSolidFlags", 140);
	SetEntProp(flag, Prop_Send, "m_nSolidType", 0);
}

/*
	reset time is the game tick that the flag should return at and is calculated as a difference of when it should
	return, compared to what the current game time is. Thus, we change the time to a different tick in the future,
	and the flag will correctly return on its own in that time.
	we get the old downtime before we change it, in case we're on a map that has a different flag reset time.
*/
void flagDrop(const char[] output, int flag, int ply, float delay) {
	if(GetEntProp(flag, Prop_Send, "m_nType") != 0) { return; } //ignore other flag types (ie SD australium)
	float downTime = GetConVarFloat(cvar_cap_time); //our desired flag-down time
	float oldDownTime = GetEntPropFloat(flag, Prop_Send, "m_flMaxResetTime"); //the flag's original down-time, in case we're on a map that doesn't use 60sec
	int flagArrIndex;
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flag == flagEnts[i]) {
			flagArrIndex = i;
		}
	}
	
	GetEntPropVector(flag, Prop_Send, "m_vecOrigin", flagDropPos[flagArrIndex]);
	
	//override default return time
	SetEntPropFloat(flag, Prop_Send, "m_flResetTime", GetEntPropFloat(flag, Prop_Send, "m_flResetTime") - (oldDownTime-downTime));
	SetEntPropFloat(flag, Prop_Send, "m_flMaxResetTime", downTime);
	
	if(GetConVarInt(cvar_cap_visualizer) > 0) {
		ringTimers[flagArrIndex] = CreateTimer(0.16, drawRingTimer, flag);
	}
	
	//enhanced HUD alert
	if(GetConVarBool(cvar_hud_alerts) && flagCarrier[flagArrIndex] > 0) {
		TFTeam dropperTeam = TF2_GetClientTeam(flagCarrier[flagArrIndex]);
		char workStr[64];
		
		if(dropperTeam == TFTeam_Red) {
			Format(workStr, sizeof(workStr), "%N dropped the BLU flag!", flagCarrier[flagArrIndex]);
			showHudAlert(workStr, "ico_notify_flag_dropped", TFTeam_Unassigned, TFTeam_Red);
		} else if(dropperTeam == TFTeam_Blue) {
			Format(workStr, sizeof(workStr), "%N dropped the RED flag!", flagCarrier[flagArrIndex]);
			showHudAlert(workStr, "ico_notify_flag_dropped", TFTeam_Unassigned, TFTeam_Blue);
		}
	}
	
	//add carry time to total for carry assist
	float plyCarryTime = GetGameTime() - grabTick[flagArrIndex];
	
	carryTime[flagArrIndex][ply] += plyCarryTime;
	carryTime[flagArrIndex][0] += plyCarryTime;
	grabTick[flagArrIndex] = 0.0;
	flagCarrier[flagArrIndex] = -1;
	
	
	#if defined DEBUG
	PrintToChatAll("[DEBUG] flagCarrier for flag %i set to -1 (dropped)", flagArrIndex);
	#endif
	
	flagResetSolid(flag);
}

//reset all carry time back to 0 once a flag returns, and handle overtime win condition
void flagReturn(const char[] output, int flag, int activator, float delay) {
	int flagArrIndex;
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flag == flagEnts[i]) {
			flagArrIndex = i;
			firstCarrier[i] = -1;
		}
	}
	
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i)) {
			carryTime[flagArrIndex][i] = 0.0;
		}
	}
	
	//return detection
	bool closeSave = false;
	char returnStr[1024];
	int numReturners = 0;
	float flagRatio = calcFlagDistRatio(flagDropPos[flagArrIndex]);
	TFTeam flagTeam = view_as<TFTeam>(GetEntProp(flag, Prop_Send, "m_iTeamNum"));
	
	//consider a return to be a close save if it's within the enemy team's "Intel" area (as calculated by the HUD text)
	if(flagRatio < 0.18 && flagTeam == TFTeam_Blue) {
		closeSave = true;
	} else if (flagRatio >= (1.0/0.18) && flagTeam == TFTeam_Red) {
		closeSave = true;
	}
	
	//process players returning the flag
	for(int ply = 1; ply <= MaxClients; ply++) {
		if(ply < 1 || ply >= MaxClients || !IsClientInGame(ply) || !IsPlayerAlive(ply)) { continue; }
		
		TFTeam plyTeam = TF2_GetClientTeam(ply);
		if(plyTeam != flagTeam) { continue; }
		float plyPos[3];
		
		float capRadius = GetConVarFloat(cvar_cap_radius);
		
		GetClientAbsOrigin(ply, plyPos);
		float dist = GetVectorDistance(flagDropPos[flagArrIndex], plyPos);
		
		if(dist <= capRadius && condCheck(ply)) { //player is within return radius
			if(numReturners == 0) { Format(returnStr, sizeof(returnStr), "%N", ply); }
			else { Format(returnStr, sizeof(returnStr), "%s, %N", returnStr, ply); }
			
			if(closeSave) { PrintCenterText(ply, "Nice save!"); }
			
			//extra log events for parsers like logstf to track returns
			char plyID[32];
			char plyTeamStr[12];
			
			GetClientAuthId(ply, AuthId_Steam3, plyID, sizeof(plyID));
			
			if(GetClientTeam(ply) == 2) {
				plyTeamStr = "Red";
			} else if(GetClientTeam(ply) == 3) {
				plyTeamStr = "Blue";
			} else {
				plyTeamStr = "Spectator";
			}
			
			LogToGame("\"%N<%i><%s><%s>\" triggered \"flagreturn\" (closesave \"%i\")", ply, GetClientUserId(ply), plyID, plyTeamStr, closeSave);
			
			numReturners += 1;
		}
	}
	
	flagResetSolid(flag);
	
	//improved HUD alert for flags being returned
	if(GetConVarBool(cvar_hud_alerts)) {
		if(numReturners > 0) {
			if(flagTeam == TFTeam_Red) {
				if(closeSave) {
					Format(returnStr, sizeof(returnStr), "%s saved the RED flag!", returnStr);
					showHudAlert(returnStr, "ico_notify_highfive", _, flagTeam);
				}
				else {
					Format(returnStr, sizeof(returnStr), "%s returned the RED flag!", returnStr);
					showHudAlert(returnStr, "ico_notify_flag_home", _, flagTeam);
				}
			} else if(flagTeam == TFTeam_Blue) {
				if(closeSave) {
					Format(returnStr, sizeof(returnStr), "%s saved the BLU flag!", returnStr);
					showHudAlert(returnStr, "ico_notify_highfive", _, flagTeam);
				}
				else {
					Format(returnStr, sizeof(returnStr), "%s returned the BLU flag!", returnStr);
					showHudAlert(returnStr, "ico_notify_flag_home", _, flagTeam);
				}
			}
		} else {
			if(flagTeam == TFTeam_Red) {
				showHudAlert("The RED flag was returned!", "ico_notify_flag_home", _, flagTeam);
			} else if(flagTeam == TFTeam_Blue) {
				showHudAlert("The BLU flag was returned!", "ico_notify_flag_home", _, flagTeam);
			}
		}
	}
	
	if(GameRules_GetProp("m_bInOvertime")) {
		//just manually call the function that's run when the round timer ends so it can recalculate the winning team.
		//all these values are just placeholders that aren't actually used by the function and are only there because of the entityoutput requirement.
		timerRoundEnd("output", -1, -1, 0.0);
		return;
	}
}

void flagPickup(const char[] output, int flag, int ply, float delay) {

	int flagArrIndex = -1;
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flagEnts[i] == flag) {
			flagArrIndex = i;
		}
	}

	grabTick[flagArrIndex] = GetGameTime();
	flagCarrier[flagArrIndex] = ply;
	if(firstCarrier[flagArrIndex] < 1) { firstCarrier[flagArrIndex] = ply; } //TF2 keeps track of the first person to steal the intel and awards them a point, so we have to also keep track and undo it.
	
	#if defined DEBUG
	PrintToChatAll("[DEBUG] PICKUP: carrier for flag %i set to player %N - flag infos: parent %i, prevown %i", flagArrIndex, ply, GetEntPropEnt(flagEnts[flagArrIndex], Prop_Send, "moveparent"), GetEntPropEnt(flagEnts[flagArrIndex], Prop_Send, "m_hPrevOwner"));
	#endif
	
	if(GetConVarBool(cvar_hud_alerts)) {
		TFTeam carrierTeam = TF2_GetClientTeam(ply);
		char workStr[64];
		
		if(carrierTeam == TFTeam_Red) {
			Format(workStr, sizeof(workStr), "%N stole the BLU flag!", ply);
			showHudAlert(workStr, "ico_notify_flag_moving", TFTeam_Unassigned, TFTeam_Red);
		} else if(carrierTeam == TFTeam_Blue) {
			Format(workStr, sizeof(workStr), "%N stole the RED flag!", ply);
			showHudAlert(workStr, "ico_notify_flag_moving", TFTeam_Unassigned, TFTeam_Blue);
		}
	}
}

void flagCapture(const char[] output, int flag, int ply, float delay) {
	int flagArrIndex = -1;
	TFTeam flagTeam = view_as<TFTeam>(GetEntProp(flag, Prop_Send, "m_iTeamNum"));
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flagEnts[i] == flag) {
			flagArrIndex = i;
		}
	}
	
	int redScore = GetEntProp(redTeamEnt, Prop_Send, "m_nFlagCaptures");
	int bluScore = GetEntProp(bluTeamEnt, Prop_Send, "m_nFlagCaptures");

	//enhanced HUD alert that shows the player's name
	if(GetConVarBool(cvar_hud_alerts)) {
		char workStr[64];
		if(flagTeam == TFTeam_Red) {
			Format(workStr, sizeof(workStr), "%N captured the RED flag!", flagCarrier[flagArrIndex]);
			showHudAlert(workStr, "ico_notify_flag_home", TFTeam_Unassigned, TFTeam_Blue);
			
		} else if(flagTeam == TFTeam_Blue) {
			Format(workStr, sizeof(workStr), "%N captured the BLU flag!", flagCarrier[flagArrIndex]);
			showHudAlert(workStr, "ico_notify_flag_home", TFTeam_Unassigned, TFTeam_Red);
		}
	}

	//respawn team whose flag was just captured based on configuration.
	int respawnMode = GetConVarInt(cvar_cap_respawn);
	if(respawnMode == 1) {
		for(int i = 1; i <= MaxClients; i++) {
			if(IsClientConnected(i) && !IsPlayerAlive(i) && (TF2_GetClientTeam(i) == flagTeam && TF2_GetClientTeam(i) > TFTeam_Spectator) ) {
				TF2_RespawnPlayer(i);
			}
		}
	} else if(respawnMode == 2) {
		if( (redScore > bluScore && flagTeam == TFTeam_Blue) || (redScore < bluScore && flagTeam == TFTeam_Red) ) {
			for(int i = 1; i <= MaxClients; i++) {
				if(IsClientConnected(i) && !IsPlayerAlive(i) && (TF2_GetClientTeam(i) == flagTeam && TF2_GetClientTeam(i) > TFTeam_Spectator) ) {
					TF2_RespawnPlayer(i);
				}
			}
		}
	}

	//this event fires AFTER the score has been added, so for adding round time we need to decrement it first.
	//doing this between respawn and round time lets us calculate respawns based on the post-capture score while doing round time based on pre-capture score
	if(flagTeam == TFTeam_Blue) { redScore -= 1; }
	else { bluScore -= 1; }

	//add round time based on configuration
	int timeMode = GetConVarInt(cvar_roundtime_cap_mode);
	if(timeMode == 1) {
		//mode 1: if scores are even or capturing team is losing

		#if defined DEBUG
		if(redScore == bluScore || (flagTeam == TFTeam_Red && bluScore < redScore) || (flagTeam == TFTeam_Blue && bluScore > redScore) ) {
			PrintToChatAll("[DEBUG] addtime mode 1: red %i - %i blu: ADDING TIME", redScore, bluScore);
		} else {
			PrintToChatAll("[DEBUG] addtime mode 1: red %i - %i blu: *NOT* ADDING TIME", redScore, bluScore);
		}
		#endif
		
		if(redScore == bluScore || (flagTeam == TFTeam_Red && bluScore < redScore) || (flagTeam == TFTeam_Blue && bluScore > redScore) ) {
			SetVariantInt(GetConVarInt(cvar_roundtime_cap_time));
			AcceptEntityInput(roundTimer, "AddTime");
		}
		
	} else if(timeMode == 2) {
		//mode 2: ONLY if capturing team is losing
		
		#if defined DEBUG
		if((flagTeam == TFTeam_Red && bluScore < redScore) || (flagTeam == TFTeam_Blue && bluScore > redScore) ) {
			PrintToChatAll("[DEBUG] addtime mode 2: red %i - %i blu: ADDING TIME", redScore, bluScore);
		} else {
			PrintToChatAll("[DEBUG] addtime mode 2: red %i - %i blu: *NOT* ADDING TIME", redScore, bluScore);
		}
		#endif
		
		if((flagTeam == TFTeam_Red && bluScore < redScore) || (flagTeam == TFTeam_Blue && bluScore > redScore) ) {
			SetVariantInt(GetConVarInt(cvar_roundtime_cap_time));
			AcceptEntityInput(roundTimer, "AddTime");
		}
		
	} else if(timeMode == 3) {
		//mode 3: every capture, regardless of score
		
		#if defined DEBUG
		PrintToChatAll("[DEBUG] addtime mode 3: ADDING TIME", redScore, bluScore);
		#endif

		SetVariantInt(GetConVarInt(cvar_roundtime_cap_time));
		AcceptEntityInput(roundTimer, "AddTime");
	}

	//add carrier's time to the total before we divvy it up
	float plyCarryTime = GetGameTime() - grabTick[flagArrIndex];
	carryTime[flagArrIndex][ply] += plyCarryTime;
	carryTime[flagArrIndex][0] += plyCarryTime; //index 0 is used for total time since console cannot carry flag
	grabTick[flagArrIndex] = 0.0;
	int assister = -1;
	int assisterPercent = 0;
	flagCarrier[flagArrIndex] = 0;

	#if defined DEBUG
	PrintToChatAll("[DEBUG] carrier for %i set to 0 (capture event)", flagArrIndex);
	#endif

	for(int i = 1; i <= MaxClients; i++) {
		int carryPercent = RoundToNearest((carryTime[flagArrIndex][i]/carryTime[flagArrIndex][0]) * 100);
		if(IsClientConnected(i) && carryPercent > 0 && carryPercent < 100) {
			PrintCenterText(i, "Carried %i%% of the time: %.1f sec", carryPercent, carryTime[flagArrIndex][i]);
			if(carryPercent > assisterPercent && i != ply) { assister = i; assisterPercent = carryPercent; } //award the assist point to whomever besides the capper had the longest carry time
		}
		else if(IsClientConnected(i) && carryPercent == 100) { PrintCenterText(i, "Solocap, %.1f sec", carryTime[flagArrIndex][0]); } //don't bother checking for assists on a solocap
	}

	if(assister > 0 && GetConVarBool(cvar_capassist)) { //assist handling
		//let the assister know they're being credited. i'm one of those people who puts math functions as arguments instead of putting it in a variable when i can :)
		PrintCenterText(assister, "Assist! Carried %i%% of the time (%.1f sec)", RoundToNearest((carryTime[flagArrIndex][assister]/carryTime[flagArrIndex][0]) * 100), carryTime[flagArrIndex][assister]);
		
		//manually editing player score is extremely annoying. we can hack around this using player_escort_score, which gives 1 point under Captures
		Event scoreEvent = CreateEvent("player_escort_score", true);
		SetEventInt(scoreEvent, "points", 1);
		SetEventInt(scoreEvent, "player", assister);

		FireEvent(scoreEvent, false);
		
		if(firstCarrier[flagArrIndex] != ply) { //by default, the first player to grab the intel gets a capture point as well as the capturer, so we have to undo it in favor of our assist system
			scoreEvent = CreateEvent("player_escort_score", true);
			SetEventInt(scoreEvent, "points", -1); //removes 1 capture score from the original assister to undo the one they unrightfully "earned"
			SetEventInt(scoreEvent, "player", firstCarrier[flagArrIndex]);
			FireEvent(scoreEvent, false);
		}
	}

	//reset carry time after capture
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i)) {
			carryTime[flagArrIndex][i] = 0.0;
		}
	}

	carryTime[flagArrIndex][0] = 0.0;
	firstCarrier[flagArrIndex] = -1;
}

/*
	Check if a player is in an invalid capture cond.
	If they are, they fail the cond check and will not be able
	to contribute towards returning their flag.
*/
bool condCheck(int ply) {
	if(TF2_IsPlayerInCondition(ply, TFCond_Cloaked) || 
	TF2_IsPlayerInCondition(ply, TFCond_Ubercharged) || 
	TF2_IsPlayerInCondition(ply, TFCond_CloakFlicker) ||
	TF2_IsPlayerInCondition(ply, TFCond_Bonked) ||
	TF2_IsPlayerInCondition(ply, TFCond_MegaHeal) ||
	TF2_IsPlayerInCondition(ply, TFCond_DisguisedAsDispenser) ||
	TF2_IsPlayerInCondition(ply, TFCond_UberchargedCanteen) ||
	TF2_IsPlayerInCondition(ply, TFCond_Stealthed))
	{
		return false;
	}
	return true;
}

stock void showHudAlert(const char[] text, const char[] icon = "ico_build", TFTeam showTeam = TFTeam_Unassigned, TFTeam teamBG = TFTeam_Unassigned) {
	int alertEnt = CreateEntityByName("game_text_tf");
	char workStr[8];
	
	DispatchKeyValue(alertEnt, "message", text);
	
	IntToString(view_as<int>(showTeam), workStr, sizeof(workStr));
	DispatchKeyValue(alertEnt, "display_to_team", workStr);
	
	DispatchKeyValue(alertEnt, "icon", icon);
	
	IntToString(view_as<int>(teamBG), workStr, sizeof(workStr));
	DispatchKeyValue(alertEnt, "background", workStr);
	
	DispatchSpawn(alertEnt);
	
	AcceptEntityInput(alertEnt, "Display", alertEnt, alertEnt);
	CreateTimer(4.0, killHudAlert, alertEnt);
}


public Action killHudAlert(Handle timer, int ent) {
	if ((ent > 0) && IsValidEntity(ent)) {
		AcceptEntityInput(ent, "kill");
	}
	
	return Plugin_Stop;
}

//SDKHook all flags on the map and store them into our array
void hookAllFlags() {
	int index = 0;
	int i = -1;
	
	while(i = FindEntityByClassname(i, "item_teamflag")) {
		if(index > MAX_FLAGS) { PrintToServer("Capped out! iCTF only supports a max of %i flags!", MAX_FLAGS); break; }
		
		flagEnts[index] = i;
		index++;
		if(i == -1 && index > 0) { break; }
		if(GetEntProp(i, Prop_Send, "m_iTeamNum") > 1) { //ignore neutral flags
			#if defined DEBUG
			PrintToServer("[DEBUG] iCTF: Hooked flag %i in array slot %i", i, index-1);
			#endif
			SDKHook(i, SDKHook_Think, flagThink);
			SDKHook(i, SDKHook_Touch, flagTouch);
		}
	}
}
