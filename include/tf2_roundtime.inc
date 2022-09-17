/*
	round time helpers
	by muddy
	
	just some boilerplate code to manipulate and control round timers
	so i can easily import these functions into any plugin i write.
*/

stock int findRoundTimer(bool forceGenerate = false) {
	int timerEnt = FindEntityByClassname(-1, "team_round_timer");
	
	//generate a new round timer if asked to
	if(forceGenerate && timerEnt == -1) {
		timerEnt = CreateEntityByName("team_round_timer");
		
		#if defined DEBUG
		PrintToServer("[DEBUG] Generated new round timer %i", timerEnt);
		#endif
	} else if(timerEnt > -1) {
		#if defined DEBUG
		PrintToServer("[DEBUG] Found existing round timer %i", timerEnt);
		#endif
	} else {
		#if defined DEBUG
		PrintToServer("[DEBUG] Couldn't find existing round timer. Not generating a new one.", timerEnt);
		#endif
	}
	
	return timerEnt;
}