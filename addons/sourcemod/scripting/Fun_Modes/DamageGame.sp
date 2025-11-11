#pragma semicolon 1
#pragma newdecls required

int g_iDealtDamage[MAXPLAYERS + 1] = {-1, ...};

ConVarInfo g_cvInfoDamageGame[2] = 
{
	{null, "15.0,20.0,30.0,40.0", "float"},
	{null, "5.0,10.0,15.0,20.0", "float"}
};

/* CALLED on Plugin Start */
stock void PluginStart_DamageGame()
{
	/* ADMIN COMMANDS */
	RegAdminCmd("sm_fm_damage", Cmd_DamageGame, ADMFLAG_CONVARS, "Enable/Disable Damage Game mode.");
	RegAdminCmd("sm_fm_damagegame", Cmd_DamageGame, ADMFLAG_CONVARS, "Enable/Disable Damage Game mode.");
	RegAdminCmd("sm_fm_dg", Cmd_DamageGame, ADMFLAG_CONVARS, "Enable/Disable Damage Game mode.");
	
	/* CONVARS */
	g_cvDamageGameTimer = CreateConVar("sm_damagegame_time_interval", "15.0", "Damage Game Timer Interval");
	g_cvDamageGameDamage = CreateConVar("sm_damagegame_damage", "15.0", "The amount of damage to apply to players who don't shoot zombies");
	
	DamageGame_SetCvarsInfo();
}

void DamageGame_SetCvarsInfo()
{
	ConVar cvars[sizeof(g_cvInfoDamageGame)];
	cvars[0] = g_cvDamageGameTimer;
	cvars[1] = g_cvDamageGameDamage;
	
	for (int i = 0; i < sizeof(g_cvInfoDamageGame); i++)
		g_cvInfoDamageGame[i].cvar = cvars[i];
}

Action Cmd_DamageGame(int client, int args)
{
	g_bIsDamageGameOn = !g_bIsDamageGameOn;
	CPrintToChatAll("%s Damage Game is now {olive}%s.", DamageGame_Tag, (g_bIsDamageGameOn) ? "Enabled" : "Disabled");

	if(g_bIsDamageGameOn)
	{
		/* Events Hooks */
		FunModes_HookEvent(g_bEvent_RoundStart, "round_start", Event_RoundStart);
		FunModes_HookEvent(g_bEvent_RoundEnd, "round_end", Event_RoundEnd);
		FunModes_HookEvent(g_bEvent_PlayerDeath, "player_death", Event_PlayerDeath);
		
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientConnected(i))
				continue;
			
			OnClientPutInServer(i);
		}
		
		DamageGame_StartTimers();
		
		CPrintToChatAll("%s Humans with lowest damage dealt to zombies will get damaged every %.2f seconds!", DamageGame_Tag, g_cvDamageGameTimer.FloatValue);
	}
	else
	{
		delete g_hDamageGameTimer;
	}
			
	return Plugin_Handled;
}

void DamageGame_StartTimers()
{
	delete g_hDamageGameTimer;
	g_hDamageGameTimer = CreateTimer(g_cvDamageGameTimer.FloatValue, Timer_DamageGame, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_DamageGame(Handle timer)
{
	if (!g_bMotherZombie || g_bRoundEnd)
		return Plugin_Handled;
		
	PrintToChatAll("Timer Called");

	int lowestDamage = 999999, count, clients[MAXPLAYERS + 1];
	
	for (int i = 1; i <= MaxClients; i++)
	{
		int thisDamage = 0;
		if (g_iDealtDamage[i] < 0)
		{
			if (!IsClientInGame(i) || !IsPlayerAlive(i) || ZR_IsClientZombie(i))
				continue;
				
			g_iDealtDamage[i] = 0;
		}
		else
		{
			thisDamage = g_iDealtDamage[i];
		}
		
		if (thisDamage >= 0 && thisDamage < lowestDamage)
		{
			lowestDamage = thisDamage;
		}
	}
	
	if (lowestDamage == 999999)
		return Plugin_Continue;
		
	for (int i = 1; i <= MaxClients; i++)
	{
		if (lowestDamage == g_iDealtDamage[i])
		{
			clients[count] = i;
			count++;
		}
	}
	
	PrintToChatAll("Lowest damage: %d", lowestDamage);
	// We got the players who dealt the lowest damage, Lets damage THEM!
	for (int i = 0; i < count; i++)
	{
		int client = clients[i];
		SDKHooks_TakeDamage(client, 0, 0, g_cvDamageGameDamage.FloatValue);
		CPrintToChat(client, "%s You have been damaged for being a bad defender", DamageGame_Tag);
		CPrintToChatAll("%s %N {olive}got damaged for being a bad defender!", DamageGame_Tag, client);
	}
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_iDealtDamage[i] >= 0)
			PrintToChatAll("%N - %d", i, g_iDealtDamage[i]);
	}
	
	return Plugin_Continue;
}

stock void RoundStart_DamageGame()
{
	if (!g_bIsDamageGameOn)
		return;
		
	for (int i = 1; i <= MaxClients; i++)
		g_iDealtDamage[i] = -1;
		
	DamageGame_StartTimers();
}

stock void PlayerDeath_DamageGame(int userid)
{
	if (!g_bIsDamageGameOn)
		return;
	
	int client = GetClientOfUserId(userid);
	if (!client)
		return;
		
	g_iDealtDamage[client] = -1;
}

stock void ClientDisconnect_DamageGame(int client)
{
	g_iDealtDamage[client] = -1;
}

stock void DamageGame_OnTakeDamagePost(int victim, int attacker, float damage)
{
	if (!(IsPlayerAlive(victim) && ZR_IsClientZombie(victim)))
		return;
	
	if (!(0 < attacker <= MaxClients && IsPlayerAlive(attacker) && ZR_IsClientHuman(attacker)))
		return;
	
	g_iDealtDamage[attacker] += RoundToNearest(damage);
}