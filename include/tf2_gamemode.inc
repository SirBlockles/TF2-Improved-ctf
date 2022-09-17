/*
	tf2 gamemode detector
	by Powerlord, reformatted by muddy

	originally written by Powerlord, with code grammar and naming changes to match my personal code style
	original snippet: https://forums.alliedmods.net/showthread.php?t=226621
*/

#include <sdktools>

// These correspond to tf_gamerules m_nGameType netprop
enum {
    TF2_GameType_Unknown,
    TF2_GameType_CTF = 1,
    TF2_GameType_CP = 2,
    TF2_GameType_PL = 3,
    TF2_GameType_Arena = 4,
}

enum TFMode {
    TFMode_Unknown,
    TFMode_CTF,
    TFMode_5CP,
    TFMode_Payload,
    TFMode_Arena,
    TFMode_AD,
    TFMode_TC,
    TFMode_PayloadRace,
    TFMode_KOTH,
    TFMode_SD,
    TFMode_MVM,
    TFMode_Training,
    TFMode_Itemtest,
}

stock TFMode getTFMode() {   
	// get gamemodes through netprops first if available

	if (GameRules_GetProp("m_bIsInTraining")) { return TFMode_Training; }

	if (GameRules_GetProp("m_bIsInItemTestingMode")) { return TFMode_Itemtest; }

	if (GameRules_GetProp("m_bPlayingSpecialDeliveryMode")) { return TFMode_SD; }

	if (GameRules_GetProp("m_bPlayingMannVsMachine")) { return TFMode_MVM; }

	if (GameRules_GetProp("m_bPlayingKoth")) { return TFMode_KOTH; }

	// now check via gametype netprop
	switch (GameRules_GetProp("m_nGameType")) {
		case TF2_GameType_CTF: { return TFMode_CTF; }

		// 5cp, atk/def, and tc all show up as this game type
		// koth and mvm  too, but we already filtered those
		case TF2_GameType_CP: {
			// Check for multi-stage maps first.
			int roundCount = 0;
			int roundCP = -1;
			int priority = -1;

			int restrictWinner = -1;
			int restrictCount = 0;

			while ((roundCP = FindEntityByClassname(roundCP, "team_control_point_round")) != -1) {
				roundCount++;

				restrictWinner = GetEntProp(roundCP, Prop_Data, "m_iInvalidCapWinner");
				if (restrictWinner > 1) { restrictCount++; }

				int newPriority = GetEntProp(roundCP, Prop_Data, "m_nPriority");
				if (newPriority > priority) { priority = newPriority; }

				// Only TC maps have multiple rounds with the same priority, and it's the highest priority
				// Sadly, this will fail to detect push/pull TC maps
				else if (newPriority == priority) { return TFMode_TC; }
			}

			// All rounds have a winner restriction, so it must be a A/D cp map
			if (roundCount > 1 && roundCount == restrictCount) { return TFMode_AD; }

			// We had multiple rounds, but not all of them were restricted...
			// must be a push/pull TC map
			else if (roundCount > 1) { return TFMode_TC; }

			// Now for single round maps... same check on control point master
			int masterCP = FindEntityByClassname(-1, "team_control_point_master");

			if (masterCP > -1) {
				restrictWinner = GetEntProp(masterCP, Prop_Data, "m_iInvalidCapWinner");
				// Single round restricted are always A/D (gorge, gravelpit)
				if (restrictWinner > 1) { return TFMode_AD; }
			}
			return TFMode_5CP;
		}

		// pl and plr both show up as this game type
		case TF2_GameType_PL: {
		
			// All plr maps have this entity
			if (FindEntityByClassname(-1, "tf_logic_multiple_escort") > -1) { return TFMode_PayloadRace; }
            
            return TFMode_Payload;
        }

		case TF2_GameType_Arena: { return TFMode_Arena; }
	}
	return TFMode_Unknown;
}