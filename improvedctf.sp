/*
	Improved CTF 2 (iCTF EX?)
	by muddy
	
	gameplay tweaks to make CTF more fast-paced, preventing teams from being in double-defending
	situations, as well as a couple other tweaks to encourage teamplay and working together.
	
	TODO:
	* see if there's a way to surpress "possibly unintended assignment" warning - it is, in fact, intended
	
	ROAD TO v3.0:
	* add round time and overtime mechanics to prevent CTF games from taking 45 minutes
	* some maps add their own round timers. should i hijack these ones and force my CTF timer mechanics over them?
	* note to self: my roundtimer-override prototype from testco might be a place to cannibalize some boilerplate timer code
	* idea from this TF2Maps resource: https://tf2maps.net/downloads/ctf-timer-logic.10041/ - respawn team when their intel is captured?
	
	TO-DO EVENTUALLY:
	* 1flag ("invade") CTF support...? since both teams can drop and pick up a neutral flag, the return system in 1flag doesn't even need to be implemented - just coverkills and assists.
	* special delivery support - when the australium is dropped, the team who dropped it is the only team who can pick it up normally. the opposing team should be able to return it just like normal CTF, then.
	
	round time brainstorm ideas:
	starting round time: 10 minutes?
	time added per capture: 3 minutes?
	time added if capturing team is: losing? winning? tied?
	
	when time runs out...
	* the team with the most captures so far wins.
	* if scores are tied and both flags are home, the round ends in a stalemate.
	* otherwise, the team with its flag at home wins. if both flags are away, the first team to recover their flag wins.
	* maybe: if a team is one point down but has the enemy flag, overtime to let them cap and bring it into a tie? feels like it'd defeat the purpose of overtime if it lasted for 2 captures...
*/

#include <sourcemod>
#include <entity>
#include <tf2>
#include <tf2_stocks>
#include <sdkhooks>
#include <tf2attributes>

#pragma newdecls required;
#pragma semicolon 1;

//uncomment to enable debug mode
//#define DEBUG

//hud text. TODO: do these values look OK on the default HUD at all resolutions? i should probably test that...
#define TEXT_Y 0.9
#define TEXT_XRED 0.68
#define TEXT_XBLU 0.3

const int MAX_FLAGS = 12; //most maps only need 2, but this lets up to 6 flags per team function correctly for whackass maps (cough cough achievement_engineer)

//logic vars
int flagEnts[MAX_FLAGS];
bool capBlocked[MAX_FLAGS];
Handle ringTimers[MAX_FLAGS];
float carryTime[MAX_FLAGS][MAXPLAYERS+1];
float grabTick[MAX_FLAGS];
int flagCarrier[MAX_FLAGS];
int firstCarrier[MAX_FLAGS];

//cvars
ConVar cvar_time;
ConVar cvar_cap_radius;
ConVar cvar_cap_bonus;
ConVar cvar_cap_carrierbonus;
ConVar cvar_cover;
ConVar cvar_capassist;
ConVar cvar_hud_text;
ConVar cvar_hud_visuals;

int beam_sprite;
int halo_sprite;

public Plugin myinfo =  {
	name = "Improved CTF",
	author = "muddy & Ribbon",
	description = "Custom flag return system and extra mechanics that reward teamplay by making you look like a badass",
	version = "2.0",
	url = ""
}

public void OnPluginStart() {
	//Set ConVars for this plugin
	cvar_time =			CreateConVar("sm_ictf_cap_time", "25.0", "Time, in seconds, flag takes to return without player influence", FCVAR_NONE, true, 0.1, true, 60.0);
	cvar_cap_bonus =	CreateConVar("sm_ictf_cap_bonus", "0.25", "multiplier for how much extra time is shaved off per capture rate", FCVAR_NONE, true, 0.0, false);
	cvar_cap_radius =	CreateConVar("sm_ictf_cap_radius", "115.0", "Determines size of flag return zone", FCVAR_NONE, true, 0.0, false);
	cvar_cap_carrierbonus = CreateConVar("sm_ictf_cap_carrierbonus", "1", "extra capture rate for flag carrier (eg 1 = flag carrier counts as x2 to return their own flag, x3 if carrier is scout)", FCVAR_NONE, true, 0.0, true, 10.0);
	cvar_capassist =	CreateConVar("sm_ictf_cap_assist", "1", "if enabled, replace TF2's cap assist system with one that awards the assist based on carry time.", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_cover =		CreateConVar("sm_ictf_coverkills", "1", "enable cover-kill system. adds a notification when a player kills an enemy threatening their flag carrier", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_hud_text =		CreateConVar("sm_ictf_cap_hud", "1", "Enables/Disables on-screen text for return rate and time", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_hud_visuals =	CreateConVar("sm_ictf_cap_visualizer", "2", "Visualize return area of dropped flag?\n0- Do not show capture area\n1- Show capture ring, plus shrinking inner ring\n2- Show outer ring, static inner ring", FCVAR_NONE, true, 0.0, true, 2.0);
	
	HookEntityOutput("item_teamflag", "OnDrop", flagDrop);
	HookEntityOutput("item_teamflag", "OnReturn", flagReturn);
	
	HookEvent("teamplay_round_start", roundStart);
	HookEvent("teamplay_flag_event", flagEvent);
	HookEvent("player_death", playerDeathEvent);
}

public void OnMapStart() {
	//flag flag table on new map
	for(int i = 0; i < MAX_FLAGS; i++) {
		flagEnts[i] = -1;
	}
	
	//precache the laser sprites for flag hologram
	beam_sprite = PrecacheModel("materials/sprites/laserbeam.vmt");  
	halo_sprite = PrecacheModel("materials/sprites/glow01.vmt");
	
	hookAllFlags();
}

public Action roundStart(Event event, const char[] name, bool dontBroadcast) {
	hookAllFlags();
	
	//clean up temporary values every round. code hygiene is very important //i must've been high writing that comment WTF
	for(int i = 0; i < MAX_FLAGS; i++) {
		for(int j = 1; j <= MaxClients; j++) {
			carryTime[i][j] = 0.0;
		}
		carryTime[i][0] = 0.0;
		grabTick[i] = 0.0;
		flagCarrier[i] = -1;
		firstCarrier[i] = -1;
		capBlocked[i] = false;
	}
	
	return Plugin_Handled;
}

void flagThink(int flag) {
	//known flag types: 0 = CTF, 4 = SD australium
	//unknown flagtypes: neutral/1-flag CTF? MvM bomb?
	if(GetEntProp(flag, Prop_Send, "m_nType") != 0) { return; }	//ignore flags that aren't CTF flags
	
	if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 0) { // FLAG IS AT HOME
		return; //no special behavior to be done while at home
	} else if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 1) { // FLAG IS BEING CARRIED
		return;
	} else if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 2) { // FLAG IS DROPPED
		float flagPos[3];
		float plyPos[3];
		float dist;
		float capRadius = GetConVarFloat(cvar_cap_radius);
		TFTeam flagTeam = view_as<TFTeam>(GetEntProp(flag, Prop_Send, "m_iTeamNum"));
		TFTeam plyTeam;
		GetEntPropVector(flag, Prop_Send, "m_vecOrigin", flagPos);
		int flagArrIndex;
		int friendlyCapForce = 0;
		bool enemyCapForce = false;

		for(int i = 0; i < MAX_FLAGS; i++) {
			if(flag == flagEnts[i]) {
				flagArrIndex = i;
			}
		}
		
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
		
		if(GetConVarBool(cvar_hud_text)) { printTimeText(GetEntPropFloat(flag, Prop_Send, "m_flResetTime") - GetGameTime(), flagTeam); }
		
		if(enemyCapForce) { //if even a single enemy is on the cap, block it from progressing at all
			SetEntPropFloat(flag, Prop_Send, "m_flResetTime", GetEntPropFloat(flag, Prop_Send, "m_flResetTime") + 0.255); //technically the flag's think cycle is scheduled to run every 0.25s but over time it still goes down veeeeery slowly. at 0.255 it doesn't... just gonna roll with it :D
			capBlocked[flagArrIndex] = true;
			if(GetConVarBool(cvar_hud_text)) { printCaptureText("(\\)", flagTeam); } //i wonder if someone knows a prettier way to depict the "no" sign with text that would work here
		} else {
			float capFactor = friendlyCapForce * GetConVarFloat(cvar_cap_bonus);
			SetEntPropFloat(flag, Prop_Send, "m_flResetTime", GetEntPropFloat(flag, Prop_Send, "m_flResetTime") - capFactor);
			capBlocked[flagArrIndex] = false;
			if(friendlyCapForce > 0 && GetConVarBool(cvar_hud_text)) {
				char capText[4];
				Format(capText, sizeof(capText), "x%i", friendlyCapForce);
				printCaptureText(capText, flagTeam);
			}
		}
	}
}

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
	
	float innerRadius = (GetEntPropFloat(flag, Prop_Send, "m_flResetTime")-GetGameTime()) * (GetConVarFloat(cvar_cap_radius)/(GetConVarFloat(cvar_time)/2));
	
	//make the visual capture area a bit smaller than it actually is - hard-coded 15 Hu smaller in radius; a 140 radius will look like 125
	TE_SetupBeamRingPoint(flagPos, GetConVarFloat(cvar_cap_radius)*2-20.0, (GetConVarFloat(cvar_cap_radius)*2-20.1), beam_sprite, halo_sprite, 1, 15, 0.22, 4.0, 0.0, ringColor, 1, 0);
	TE_SendToAll();
	if(GetConVarInt(cvar_hud_visuals) == 2) {
		TE_SetupBeamRingPoint(flagPos, 60.1, 60.0, beam_sprite, halo_sprite, 1, 15, 0.22, 2.0, 0.0, innerColor, 1, 0);
	} else {
		TE_SetupBeamRingPoint(flagPos, innerRadius-20.0, (innerRadius - 20.1), beam_sprite, halo_sprite, 1, 15, 0.22, 2.0, 0.0, innerColor, 1, 0);
	}
	TE_SendToAll();
	
	if(!IsValidEntity(flag) || !IsValidEdict(flag)) { return Plugin_Stop; } //we're running a loop where somehow the flag stopped existing without being returned first
	if(GetEntProp(flag, Prop_Send, "m_nFlagStatus") == 2) { ringTimers[flagArrIndex] = CreateTimer(0.16, drawRingTimer, flag); } //loop for as long as we are dropped
	return Plugin_Continue;
}

/*
	flag is caller AND activator, so choosing which to name "flag" is arbitrary
	
	reset time is the game tick that the flag should return at and is calculated as a difference of when it should
	return, compared to what the current game time is. Thus, we change the time to a different tick in the future,
	and the flag will correctly return on its own in that time.
	we get the old downtime before we change it, in case we're on a map that has a different flag reset time.
*/
void flagDrop(const char[] output, int flag, int activator, float delay) {
	if(GetEntProp(flag, Prop_Send, "m_nType") != 0) { return; } //ignore other flag types (ie SD australium)
	float downTime = GetConVarFloat(cvar_time); //our desired flag-down time
	float oldDownTime = GetEntPropFloat(flag, Prop_Send, "m_flMaxResetTime"); //the flag's original down-time, in case we're on a map that doesn't use 60sec
	int flagArrIndex;
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flag == flagEnts[i]) {
			flagArrIndex = i;
		}
	}
	
	//override default return time
	SetEntPropFloat(flag, Prop_Send, "m_flResetTime", GetEntPropFloat(flag, Prop_Send, "m_flResetTime") - (oldDownTime-downTime));
	SetEntPropFloat(flag, Prop_Send, "m_flMaxResetTime", downTime);
	
	if(GetConVarInt(cvar_hud_visuals) > 0) {
		ringTimers[flagArrIndex] = CreateTimer(0.16, drawRingTimer, flag);
	}
	
	flagReset(flag);
}

public Action flagEvent(Event event, const char[] name, bool dontBroadcast) {
	int type = GetEventInt(event, "eventtype");
	int ply = GetEventInt(event, "player");
	//int carrier = GetEventInt(event, "carrier");
	int flag = -1;
	int flagArrIndex = -1;
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flagEnts[i] > 0 && (GetEntPropEnt(flagEnts[i], Prop_Send, "m_hPrevOwner") == ply)) {
			flag = flagEnts[i];
			flagArrIndex = i;
		}
	}
	
	switch(type) {
		case 1: { //pickup
			grabTick[flagArrIndex] = GetGameTime();
			flagCarrier[flagArrIndex] = ply;
			bool firstGrab = GetEventBool(event, "home");
			if(firstGrab) { firstCarrier[flagArrIndex] = ply; } //TF2 keeps track of the first person to steal the intel and awards them a point, so we have to also keep track and undo it.
		} case 2: { //capture
			//add carrier's time to the total before we divvy it up
			float plyCarryTime = GetGameTime() - grabTick[flagArrIndex];
			carryTime[flagArrIndex][ply] += plyCarryTime;
			carryTime[flagArrIndex][0] += plyCarryTime; //index 0 is used for total time since console cannot carry flag
			grabTick[flagArrIndex] = 0.0;
			int assister = -1;
			int assisterPercent = 0;
			flagCarrier[flagArrIndex] = 0;
			
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
			
			flagReset(flag);
		} case 3: { //defend (carrier kill) - remember: flag is undefined in this scenario!
			
		} case 4: { //drop
			float plyCarryTime = GetGameTime() - grabTick[flagArrIndex];
			carryTime[flagArrIndex][ply] += plyCarryTime;
			carryTime[flagArrIndex][0] += plyCarryTime;
			grabTick[flagArrIndex] = 0.0;
			flagCarrier[flagArrIndex] = 0;
			
			flagReset(flag);
		}
	}
	return Plugin_Continue;
}

//cover-kill system. inspired by and heavily based on Unreal Tournament's SmartCTF mod.
public Action playerDeathEvent(Event event, const char[] name, bool dontBroadcast) {
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int killer = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	int deathflags = GetEventInt(event, "death_flags");
	//ignore deadringer, suicides, world deaths ("finished off" is not a world death), or if disabled
	if(deathflags & TF_DEATHFLAG_DEADRINGER || killer <= 0 || victim == killer || !GetConVarBool(cvar_cover)) { return Plugin_Continue; }
	
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
			if(coverKill && killer == flagCarrier[i]) { PrintCenterTextAll("%N covered their own ass!", killer); }
			else if(coverKill) { PrintCenterTextAll("%N covered the flag carrier!", killer); }
			
			//clean up our raytrace handles now that we're done
			delete rayVictimCarrier;
			delete rayKillerCarrier;
		}
	}
	
	return Plugin_Continue;
}

bool RayFilter_Vision(int ent, int contentsMask) { //if a trace hits without entities, it's theoretically a potential sniper headshot and thus "line-of-sight"
	return false;
}

//reset collision so players can pick up flags again
void flagReset(int flag) {
	SetEntProp(flag, Prop_Send, "m_usSolidFlags", 140);
	SetEntProp(flag, Prop_Send, "m_nSolidType", 0);
}

//reset all carry time back to 0 once a flag returns
void flagReturn(const char[] output, int flag, int activator, float delay) {
	int flagArrIndex;
	
	for(int i = 0; i < MAX_FLAGS; i++) {
		if(flag == flagEnts[i]) {
			flagArrIndex = i;
		}
	}
	
	for(int i = 1; i <= MaxClients; i++) {
		if(IsClientConnected(i)) {
			carryTime[flagArrIndex][i] = 0.0;
		}
	}
	
	flagReset(flag);
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

void printCaptureText(const char[] text, TFTeam team) {
	//prints the capture rate of downed flags to the screen
	//checks sets parameters based on flag team
	switch(team) {
		case TFTeam_Unassigned: {
			SetHudTextParams(-1.0, TEXT_Y, 0.27, 200, 200, 200, 255, 0, 0.0, 0.0, 0.0);
		}
		case TFTeam_Red: {
			SetHudTextParams(TEXT_XRED, TEXT_Y, 0.27, 255, 120, 120, 255, 0, 0.0, 0.0, 0.0);
		}
		case TFTeam_Blue: {
			SetHudTextParams(TEXT_XBLU, TEXT_Y, 0.27, 120, 120, 255, 255, 0, 0.0, 0.0, 0.0);
		}
	}
	//Iterates through every client
	for(int i=1; i <= MaxClients; i++) {
		// Early out if client is not active, not connected, or fake
		if(!IsClientInGame(i) || IsFakeClient(i))  {
			continue;
		}
		//Display the text showing capture rate
		ShowHudText(i, -1, text);
	}
}

void printTimeText(float capTimeRemaining, TFTeam team) {
	//prints the return time left of downed flags to the screen
	//checks sets parameters based on flag team
	switch(team) {
		case TFTeam_Unassigned: {
			SetHudTextParams(-1.0, TEXT_Y+0.032, 0.27, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
		}
		case TFTeam_Red: {
			SetHudTextParams(TEXT_XRED, TEXT_Y+0.032, 0.27, 255, 135, 135, 255, 0, 0.0, 0.0, 0.0);
		}
		case TFTeam_Blue: {
			SetHudTextParams(TEXT_XBLU, TEXT_Y+0.032, 0.27, 135, 135, 255, 255, 0, 0.0, 0.0, 0.0);
		}
	}
	//Iterates through every client
	for(int i=1; i <= MaxClients; i++) {
		// Early out if client is not active, not connected, or fake
		if(!IsClientInGame(i) || IsFakeClient(i))  {
			continue;
		}
		//Display the text showing return time
		ShowHudText(i, -1, "%i", RoundFloat(capTimeRemaining));
	}
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
