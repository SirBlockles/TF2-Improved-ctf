/*
	Improved CTF v0.4
	
	TO-DO:
	- Technical
	* Replace hard-coded Pain Train check with check for capture rate bonus weapon attribute - support for custom weapons
	* Look into replacing return timer with hooking the flag entity itself and running our code on its think loop
	
	- Gameplay
	* Return on touch option? Old-school Quake style
	* Capture contesting - If an enemy is in the capture zone the return timer pauses. If a player on the flag's team is in the radius, the enemy can't pick it up.
	
	- Flourish
	* "player (/) DEFENDED the intelligence" killfeed messages on successful returns
*/

#include <sourcemod>
#include <entity>
#include <clients>
#include <tf2>
#include <tf2_stocks>
#include <timers>
#include <sdktools_entoutput>
#include <sdktools_tempents_stocks>
#include <sdktools_tempents>
#include <halflife>

#pragma newdecls required;
#pragma semicolon 1;

#define VERSION "b4"

#define TEXT_Y 0.9
#define TEXT_XRED 0.7
#define TEXT_XBLU 0.3

const int MAX_FLAGS = 8;
int flag_i[8];
float flag_time[8];
TFTeam last_team;
int game_type;
ConVar cvar_enabled;
ConVar cvar_time;
ConVar cvar_mult;
ConVar cvar_cap_radius;
ConVar cvar_hud_text;
Handle flag_timer;

int beam_sprite;
int halo_sprite;


public Plugin myinfo =  {
	name = "Improved CTF",
	author = "muddy, original by Ribbon Heartflat",
	description = "Custom CTF flag return logic to make the game less stalematey",
	version = VERSION,
	url = "sheen.team"
}

public void OnPluginStart() {
	//Set ConVars for this plugin
	CreateConVar("sm_ictf_version", VERSION, "Improved CTF version", FCVAR_NOTIFY|FCVAR_DONTRECORD|FCVAR_SPONLY);
	cvar_enabled = CreateConVar("sm_ictf_enable", "1", "Enables/Disables Improved CTF", FCVAR_NONE, true, 0.0, true, 1.0);
	cvar_time = CreateConVar("sm_ictf_flag_time", "30", "Time, in seconds, flag takes to return without influence from players", FCVAR_NONE, true, 1.0, false);
	cvar_mult = CreateConVar("sm_ictf_cap_multiplier", "0.6", "Determines percentage increase to flag timer speed per cap-rate in flag area", FCVAR_NONE, true, 0.0, false);
	cvar_cap_radius = CreateConVar("sm_ictf_cap_radius", "100.0", "Determines size of flag return zone", FCVAR_NONE, true, 0.0, false);
	cvar_hud_text = CreateConVar("sm_ictf_hud_text", "1", "Enables/Disables on-screen text for return rate", FCVAR_NONE, true, 0.0, true, 1.0);
	InitiateICTF(cvar_enabled, "0", "1");
	HookConVarChange(cvar_enabled, InitiateICTF);
}

void InitiateICTF(Handle convar, const char[] oldValue, const char[] newValue) {
	//Check to see if ICTF is enabled and that the game is, in fact, TF2
	char gamename[3];
	GetGameFolderName(gamename, sizeof(gamename));
	if(StrEqual(gamename,"tf") && cvar_enabled.BoolValue) {
		PrintToServer("Improved CTF enabled");
		//Hook flag event for flag being dropped
		HookEntityOutput("item_teamflag", "OnDrop", OnFlagDrop);
		//Hook flag event for flag being picked up, returned, destroyed, ect.
		HookEntityOutput("item_teamflag", "OnPickup", OnFlagPickup);
		HookEntityOutput("item_teamflag", "OnReturn", OnFlagPickup);
		HookEntityOutput("item_teamflag", "OnKilled", OnFlagPickup);
		HookEntityOutput("item_teamflag", "OnPickupTeam1", OnFlagPickupRed);
		HookEntityOutput("item_teamflag", "OnPickupTeam2", OnFlagPickupBlu);
		//Create the custom flag timer
		flag_timer = CreateTimer(1.0, TimeTick, _, TIMER_REPEAT);
	} else {
		//Unhook flag events
		UnhookEntityOutput("item_teamflag", "OnDrop", OnFlagDrop);
		UnhookEntityOutput("item_teamflag", "OnPickup", OnFlagPickup);
		UnhookEntityOutput("item_teamflag", "OnReturn", OnFlagPickup);
		UnhookEntityOutput("item_teamflag", "OnKilled", OnFlagPickup);
		UnhookEntityOutput("item_teamflag", "OnPickupTeam1", OnFlagPickupRed);
		UnhookEntityOutput("item_teamflag", "OnPickupTeam2", OnFlagPickupBlu);
		//kill the flag timer
		KillTimer(flag_timer, false);
		//reset the offical timers for active flags
		for(int i=0;i<MAX_FLAGS;i++) {
			if(flag_i[i] >= 0) {
				SetVariantInt(cvar_time.IntValue);
				AcceptEntityInput(flag_i[i], "ShowTimer", -1, -1, 0);
			}
		}
		PrintToServer("Improved CTF disabled");
		PrintToServer("Note: Improved CTF only supports Team Fortress 2");
	}
}

public void OnMapStart() {
	//Reset the flag entity table
	for(int i=0;i<MAX_FLAGS;i++) {
		flag_i[i] = -1;
		flag_time[i] = -1.0;
	}
	//Precache the laser sprites
	beam_sprite = PrecacheModel("materials/sprites/laserbeam.vmt");  
	halo_sprite = PrecacheModel("materials/sprites/glow01.vmt");
}


void OnFlagDrop(const char[] output, int caller, int activator, float delay) {
	//Add a newly dropped flags to the entity index table
	for(int i=0;i<MAX_FLAGS;i++) {
		if(flag_i[i] == -1) {
			flag_i[i] = caller;
			//Set the official timer to not decrease
			flag_time[i] = cvar_time.FloatValue;
			SetVariantInt(99999);
			AcceptEntityInput(flag_i[i], "ShowTimer", -1, -1, 0);
			//Gets the game type that flag is used for
			game_type = GetEntData(i, 1628, 4);
			//exit the for loop
			i = 8;
		}
	}
}

void OnFlagPickup(const char[] output, int caller, int activator, float delay) {
	last_team = TFTeam_Unassigned;
	FlagRemove(caller);
}

void OnFlagPickupRed(const char[] output, int caller, int activator, float delay) {
	//Set the last held team to RED (for neutral flag purposes)
	last_team = TFTeam_Red;
	FlagRemove(caller);
}

void OnFlagPickupBlu(const char[] output, int caller, int activator, float delay) {
	//Set the last held team to BLU (for neutral flag purposes)
	last_team = TFTeam_Blue;
	FlagRemove(caller);
}

void FlagRemove(int caller) {
	//Remove killed flag from the entity index table
	for(int i=0;i<MAX_FLAGS;i++) {
		if(flag_i[i] == caller) {
			flag_i[i] = -1;
			flag_time[i] = -1.0;
		}
	}
}

bool ConditionCheck(int player_i) {
	//Check if player is in any of these contraband conditions
	//if they are, in_cond will be passed as true 
	bool if_cond = false;
	if(TF2_IsPlayerInCondition(player_i, TFCond_Cloaked) || 
	TF2_IsPlayerInCondition(player_i, TFCond_Ubercharged) || 
	TF2_IsPlayerInCondition(player_i, TFCond_CloakFlicker) ||
	TF2_IsPlayerInCondition(player_i, TFCond_Bonked) ||
	TF2_IsPlayerInCondition(player_i, TFCond_MegaHeal) ||
	TF2_IsPlayerInCondition(player_i, TFCond_DisguisedAsDispenser) ||
	TF2_IsPlayerInCondition(player_i, TFCond_UberchargedCanteen) ||
	TF2_IsPlayerInCondition(player_i, TFCond_Stealthed))
	{
		if_cond = true;
	}
	return if_cond;
}

void PrintCaptureText(float mult, TFTeam team) {
	//prints the capture rate of downed flags to the screen
	//checks sets parameters based on flag team
	switch(team) {
		case TFTeam_Unassigned: {
			SetHudTextParams(-1.0, TEXT_Y, 1.0, 255, 255, 255, 200, 0, 0.0, 0.0, 0.0);
		}
		case TFTeam_Red: {
			SetHudTextParams(TEXT_XRED, TEXT_Y, 1.0, 255, 0, 0, 200, 0, 0.0, 0.0, 0.0);
		}
		case TFTeam_Blue: {
			SetHudTextParams(TEXT_XBLU, TEXT_Y, 1.0, 0, 0, 255, 200, 0, 0.0, 0.0, 0.0);
		}
	}
	char buffer[8];
	Format(buffer, sizeof(buffer), "x%i", RoundFloat(mult));
	//Iterates through every client
	for(int c=1;c <= MaxClients; c++) {
		// Early out if client is not active, not connected, or fake
		if(!IsClientInGame(c) || IsFakeClient(c) || !IsPlayerAlive(c))  {
			continue;
		}
		//Display the text showing capture rate
		ShowHudText(c, -1, buffer);
	}
}

Action TimeTick(Handle timer) {
	float flag_pos[3];
	float c_pos[3];
	TFTeam team = TFTeam_Unassigned;
	TFTeam c_team;
	float mult = 0.0;
	int ring_color[4] = {192,192,192,150};
	int prog_color[4] = {192,192,192,150};
	float inner_beam;

	//Iterate through the entity table
	for(int i=0;i<MAX_FLAGS;i++) {
		// Early out if a flag is not indexed
		if(flag_i[i] == -1) {
			continue;
		}
		//Get the flag's location
		GetEntPropVector(flag_i[i], Prop_Send, "m_vecOrigin", flag_pos);
		//Get the flag's team
		team = view_as<TFTeam>(GetEntData(flag_i[i], 512, 4));
		//Iterate through all clients
		for(int c=1;c <= MaxClients; c++) {
			// Early out if client is not active, not connected, or fake
			if(!IsClientInGame(c) || IsFakeClient(c) || !IsPlayerAlive(c)) {
				continue;
			}
			//Get the client's team and check to see if they are the same team as the flag
			c_team = TF2_GetClientTeam(c);
			//simplified logic that should accomplish the same as the original now that they all use the TFTeam type
			if( (team == TFTeam_Unassigned && last_team != c_team) || (team == c_team) ) {
				//Get the client's location
				GetClientAbsOrigin(c, c_pos);
				//Get the squared distance from the flag
				float distance = Pow((c_pos[0] - flag_pos[0]), 2.0) + Pow((c_pos[1] - flag_pos[1]), 2.0) + Pow((c_pos[2] - flag_pos[2]), 2.0);
				//Check to see if the squared distance is less than the squared radius
				if(distance < Pow(cvar_cap_radius.FloatValue,2.0)) {
					if(!ConditionCheck(c)) {
						//Gets the player's melee weapon index from the weapon's entity ID 
						int c_wep = GetEntProp(GetPlayerWeaponSlot(c, 2), Prop_Send, "m_iItemDefinitionIndex");
						//if the player's class is a scout or they have the pain train equiped, then double their capture rate
						if(TF2_GetPlayerClass(c) == TFClass_Scout || c_wep == 154) {
							mult += 2.0;
						} else {
							mult += 1.0;
						}
					}
				}
			}
		}
		//Determine ring colors based on if someone is capping and the flag's team
		switch(team) {
			case TFTeam_Unassigned: {
				if(game_type != NOTEAM) {
					ring_color = {235,201,52,255};
				} else {
					ring_color = {192,192,192,255};
				}
				if(mult > 0.0) {
					if(last_team == TFTeam_Red) {
						prog_color = {102,102,255,255};
					} else {
						prog_color = {255,102,102,255};
					}
				} else {
					prog_color = {192,192,192,255};
				}
			}
			case TFTeam_Red: {
				ring_color = {255,102,102,255};
				if(mult > 0.0) {
					prog_color = {255,102,102,255};
				} else {
					prog_color = {192,192,192,255};
				}
			}
			case TFTeam_Blue: {
				ring_color = {102,102,255,255};
				if(mult > 0.0) {
					prog_color = {102,102,255,255};
				} else {
					prog_color = {192,192,192,255};
				}
			}
		}
		//Reduce the flag's timer by the multiplier + one second
		flag_time[i] -= 1 + (mult * cvar_mult.FloatValue);
		//Get the progress circle's radius
		inner_beam = (flag_time[i]/cvar_time.FloatValue) * cvar_cap_radius.FloatValue*2;

		//Reset the flag if the timer is zero or less
		if(flag_time[i] <= 0.0) {
			AcceptEntityInput(flag_i[i], "ForceReset", -1, -1);
		} else {
			//Create the two circles if the timer is still active
			float laser_pos[3];
			laser_pos[0] = flag_pos[0];
			laser_pos[1] = flag_pos[1] + cvar_cap_radius.FloatValue;
			laser_pos[2] = flag_pos[2];
			flag_pos[2] += 7.0;
			TE_SetupBeamRingPoint(flag_pos, cvar_cap_radius.FloatValue*2, (cvar_cap_radius.FloatValue*2+0.1), beam_sprite, halo_sprite, 1, 15, 1.0, 4.0, 0.0, ring_color, 0, 0);
			TE_SendToAll();
			TE_SetupBeamRingPoint(flag_pos, inner_beam, (inner_beam + 0.1), beam_sprite, halo_sprite, 1, 15, 1.0, 2.0, 0.0, prog_color, 0, 0);
			TE_SendToAll();
			//Check to see if hud text is enabled
			if(cvar_hud_text.BoolValue) {
				PrintCaptureText(mult, team);
			}
		}
		//reset mult
		mult = 0.0;
	}
}