/*
    (). FunModes V2:

    @file           VIPMode.sp
    @Usage          Functions for the VIPMode Mode.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_VIPMode

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "VIPMode"

static int g_iVIPModeIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iVIPModeIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define VIPMODE_CONVAR_TIMER     0
#define VIPMODE_CONVAR_COUNT     1
#define VIPMODE_CONVAR_LASER     2
#define VIPMODE_CONVAR_VIP_MAX   3
#define VIPMODE_CONVAR_TOGGLE    4
#define VIPMODE_CONVAR_REPLACE   5
#define VIPMODE_CONVAR_HUD       6

bool g_bDiedFromLaser[MAXPLAYERS + 1];
bool g_bIsVIP[MAXPLAYERS + 1];

Handle g_hKillAllTimer = null;
Handle g_hVIPRoundStartTimer = null;
Handle g_hVIPBeaconTimer[MAXPLAYERS + 1] = { null, ... };

float g_fVIP_Timer;
float g_fVIP_KillDelay;
bool g_bVIP_LaserException;
int g_iVIP_Max;
bool g_bVIP_Enabled;
bool g_bVIP_Replace;
bool g_bVIP_Hud;

Handle g_hVIP_Hud;

/* The players an admin chose as VIP (Steam IDs): VIP every round until they leave the server */
ArrayList g_aVIP_Chosen;

public void OnPluginStart_VIPMode()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_SURVIVAL;

	RegAdminCmd("sm_fm_vipmode", Cmd_VIPModeToggle, ADMFLAG_CONVARS, "Turn VIPMode On/Off");
	RegAdminCmd("sm_vipmode_setvip", Cmd_SetVIP, ADMFLAG_CONVARS, "sm_vipmode_setvip <player> - VIP every round until they leave (again to undo)");

	g_aVIP_Chosen = new ArrayList(ByteCountToCells(32));

	// Only a real leave, not a map change (player_disconnect isn't fired on map change)
	HookEvent("player_disconnect", Event_VIPDisconnect, EventHookMode_Pre);
	RegConsoleCmd("sm_checkvip", Cmd_CheckVIP);
	RegAdminCmd("sm_vipmode_settings", Cmd_VIPModeSettings, ADMFLAG_CONVARS, "Open VIPMode Settings Menu");

	DECLARE_FM_CVAR(
		VIPMODE_CONVAR_TIMER, "sm_vipmode_timer",
		"15", "How many seconds after round start before choosing the VIPs",
		("15,25,40,60"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[VIPMODE_CONVAR_TIMER].HookChange(VIPMode_OnConVarChange);

	DECLARE_FM_CVAR(
		VIPMODE_CONVAR_COUNT, "sm_vipmode_counter",
		"3", "How many seconds to wait before killing all CTs when all VIPs die",
		("2,3,5,10"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[VIPMODE_CONVAR_COUNT].HookChange(VIPMode_OnConVarChange);

	DECLARE_FM_CVAR(
		VIPMODE_CONVAR_LASER, "sm_vipmode_laser",
		"1", "Whether laser deaths should be ignored as a VIP death exception",
		("0,1"), CONVAR_BOOL
	);
	THIS_MODE_INFO.cvars[VIPMODE_CONVAR_LASER].HookChange(VIPMode_OnConVarChange);

	DECLARE_FM_CVAR(
		VIPMODE_CONVAR_VIP_MAX, "sm_vipmode_max_vips",
		"1", "Maximum number of VIPs to pick each round",
		("1,2,3,4,5"), CONVAR_INT
	);
	THIS_MODE_INFO.cvars[VIPMODE_CONVAR_VIP_MAX].HookChange(VIPMode_OnConVarChange);

	DECLARE_FM_CVAR(
		VIPMODE_CONVAR_TOGGLE, "sm_vipmode_enable",
		"1", "Enable/Disable VIPMode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);
	THIS_MODE_INFO.cvars[VIPMODE_CONVAR_TOGGLE].HookChange(VIPMode_OnConVarChange);

	DECLARE_FM_CVAR(
		VIPMODE_CONVAR_REPLACE, "sm_vipmode_replace",
		"0", "When all the VIPs die pick new VIPs instead of killing all the humans",
		("0,1"), CONVAR_BOOL
	);
	THIS_MODE_INFO.cvars[VIPMODE_CONVAR_REPLACE].HookChange(VIPMode_OnConVarChange);

	DECLARE_FM_CVAR(
		VIPMODE_CONVAR_HUD, "sm_vipmode_hud",
		"1", "Show the VIPs names on everyone's screen",
		("0,1"), CONVAR_BOOL
	);
	THIS_MODE_INFO.cvars[VIPMODE_CONVAR_HUD].HookChange(VIPMode_OnConVarChange);

	THIS_MODE_INFO.enableIndex = VIPMODE_CONVAR_TOGGLE;

	g_hVIP_Hud = CreateModeHud();
}

public void InitCvarsValues_VIPMode()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_fVIP_Timer = _FUNMODES_CVAR_GET_VALUE(modeIndex, VIPMODE_CONVAR_TIMER, Float);
	g_fVIP_KillDelay = _FUNMODES_CVAR_GET_VALUE(modeIndex, VIPMODE_CONVAR_COUNT, Float);
	g_bVIP_LaserException = _FUNMODES_CVAR_GET_VALUE(modeIndex, VIPMODE_CONVAR_LASER, Bool);
	g_iVIP_Max = _FUNMODES_CVAR_GET_VALUE(modeIndex, VIPMODE_CONVAR_VIP_MAX, Int);
	g_bVIP_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, VIPMODE_CONVAR_TOGGLE, Bool);
	g_bVIP_Replace = _FUNMODES_CVAR_GET_VALUE(modeIndex, VIPMODE_CONVAR_REPLACE, Bool);
	g_bVIP_Hud = _FUNMODES_CVAR_GET_VALUE(modeIndex, VIPMODE_CONVAR_HUD, Bool);
}

void VIPMode_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case VIPMODE_CONVAR_TIMER:
			g_fVIP_Timer = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case VIPMODE_CONVAR_COUNT:
			g_fVIP_KillDelay = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case VIPMODE_CONVAR_LASER:
			g_bVIP_LaserException = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case VIPMODE_CONVAR_VIP_MAX:
			g_iVIP_Max = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case VIPMODE_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn)
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, val, THIS_MODE_INFO.index);

			g_bVIP_Enabled = val;
		}

		case VIPMODE_CONVAR_REPLACE:
			g_bVIP_Replace = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case VIPMODE_CONVAR_HUD:
			g_bVIP_Hud = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
	}
}

public void OnMapEnd_VIPMode()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);

	g_hKillAllTimer = null;
	g_hVIPRoundStartTimer = null;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_hVIPBeaconTimer[i] = null;
		g_bDiedFromLaser[i] = false;
	}
}

public void OnClientPutInServer_VIPMode(int client)
{
	if (!THIS_MODE_INFO.isOn)
		return;

	if (g_bSDKHook_OnTakeDamage[client])
		return;
	
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	g_bSDKHook_OnTakeDamage[client] = true;
}

public void OnClientDisconnect_VIPMode(int client)
{
	delete g_hVIPBeaconTimer[client];

	// Plugin unload: no "VIP left" messages, new VIPs or slay timers
	if (!THIS_MODE_INFO.isOn || g_bUnloading)
		return;

	if (!g_bIsVIP[client])
		return;
	
	RemoveClientVIP(client, true, "VIPMode_VIPDeathDisconnect");
}

public void Event_RoundStart_VIPMode()
{
	if (!THIS_MODE_INFO.isOn)
		return;

	delete g_hKillAllTimer;
	
	/* DELETE VIP BEACON TIMER */
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bIsVIP[i] = false;
		g_bDiedFromLaser[i] = false;
		delete g_hVIPBeaconTimer[i];
	}

	delete g_hVIPRoundStartTimer;
	g_hVIPRoundStartTimer = CreateTimer(g_fVIP_Timer, VIPRoundStart_Timer, _, TIMER_FLAG_NO_MAPCHANGE);
}

public void ZR_OnClientInfected_VIPMode(int client)
{
	if (!THIS_MODE_INFO.isOn || !g_bIsVIP[client])
		return;

	// Becoming a mother zombie isn't the humans' fault: another VIP takes over
	if (g_bInfectionIsMother)
	{
		RemoveClientVIP(client, false, "VIPMode_VIPMother");
		VIP_PickRandom();
		return;
	}

	RemoveClientVIP(client, true, "VIPMode_VIPInfected");
}

/* The VIPs' names on everyone's screen */
public void OnTick_VIPMode()
{
	if (!g_bVIP_Hud || !GetCurrentVIPsCount())
		return;

	char names[160];
	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bIsVIP[i] || !IsClientInGame(i))
			continue;

		Format(names, sizeof(names), "%s%s%N", names, count ? ", " : "", i);
		count++;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		SetHudTextParams(-1.0, HUD_Y_VIP, 1.1, 255, 215, 0, 255, 0, 0.0, 0.0, 0.0);
		if (g_bIsVIP[i] && IsPlayerAlive(i))
			ShowModeHud(i, g_hVIP_Hud, "YOU ARE A VIP - STAY ALIVE!");
		else
			ShowModeHud(i, g_hVIP_Hud, count > 1 ? "VIPs: %s" : "VIP: %s", names);
	}
}

public void Event_PlayerTeam_VIPMode(Event event)
{
	if (!THIS_MODE_INFO.isOn)
		return;
	
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!client || !g_bIsVIP[client])
		return;

	int team = event.GetInt("team");
	if (team == CS_TEAM_SPECTATOR || team == CS_TEAM_NONE) 
		RemoveClientVIP(client, true, "VIPMode_VIPDeathSpec");
}

public void Event_PlayerDeath_VIPMode(int client)
{
	if (!THIS_MODE_INFO.isOn)
		return;

	if (!g_bIsVIP[client])
		return;

	if (g_bDiedFromLaser[client])
	{
		CPrintToChatAll("%s %T", THIS_MODE_INFO.tag, "VIPMode_VIPDeathLaser", client, client);
		RemoveClientVIP(client, false);
		g_bDiedFromLaser[client] = false;
		return;
	}

	RemoveClientVIP(client, true, "VIPMode_VIPDeath");
}

public void OnTakeDamage_VIPMode(int victim, int &attacker, float &damage, Action &result)
{
	#pragma unused result

	if (!THIS_MODE_INFO.isOn || !g_bVIP_LaserException)
		return;

	if (!g_bIsVIP[victim])
		return;

	if (!IsValidEntity(attacker))
		return;

	char classname[64];
	if (!GetEntityClassname(attacker, classname, sizeof(classname)))
		return;

	/* if attacker entity is not trigger_hurt */
	if (strcmp(classname, "trigger_hurt") != 0)
		return;

	/* we should now check if trigger_hurt is from a laser */
	int parent = GetEntPropEnt(attacker, Prop_Data, "m_hParent");
	if (!IsValidEntity(parent))
		return;

	bool isFromLaser = false;
	char parentClassName[64];
	if (!GetEntityClassname(parent, parentClassName, sizeof(parentClassName)))
		return;

	if (strcmp(parentClassName, "func_movelinear") == 0 || strcmp(parentClassName, "func_door") == 0)
		isFromLaser = true;

	if (!isFromLaser)
		return;

	g_bDiedFromLaser[victim] = false;
	if (damage > GetClientHealth(victim))
		g_bDiedFromLaser[victim] = true;
}

public Action Cmd_VIPModeToggle(int client, int args)
{
	if (!g_bVIP_Enabled)
	{
		CReplyToCommand(client, "%s VIPMode is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;

	CPrintToChatAll("%s VIPMode is now %s!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");

	if (THIS_MODE_INFO.isOn)
	{
		FunModes_HookEvent(g_bEvent_RoundStart, "round_start", Event_RoundStart);
		FunModes_HookEvent(g_bEvent_PlayerDeath, "player_death", Event_PlayerDeath);
	}

	delete g_hKillAllTimer;
	delete g_hVIPRoundStartTimer;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (THIS_MODE_INFO.isOn && IsClientInGame(i))
			OnClientPutInServer_VIPMode(i);

		g_bIsVIP[i] = false;
		g_bDiedFromLaser[i] = false;
		delete g_hVIPBeaconTimer[i];
	}

	// Turned on during a round: the VIPs come this round too, not only from the next round start.
	// Zombies already out -> picked now, else after the usual VIP timer
	if (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bRoundEnd)
	{
		if (g_bZombiesSeen)
			VIP_PickVIPs();
		else
			g_hVIPRoundStartTimer = CreateTimer(g_fVIP_Timer, VIPRoundStart_Timer, _, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Handled;
}

Action VIPRoundStart_Timer(Handle timer)
{
	g_hVIPRoundStartTimer = null;

	if (!THIS_MODE_INFO.isOn)
		return Plugin_Stop;

	VIP_PickVIPs();
	return Plugin_Stop;
}

/* The chosen VIPs who are alive humans, then random humans until there are as many VIPs as the max */
void VIP_PickVIPs()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bIsVIP[i] && IsHumanAlive(i) && VIP_IsChosen(i))
			VIP_Make(i);
	}

	while (GetCurrentVIPsCount() < g_iVIP_Max && VIP_PickRandom()) {}
}

bool VIP_IsChosen(int client)
{
	return ChosenListHas(g_aVIP_Chosen, client);
}

/* Chooses the player as VIP (every round until they leave), or un-chooses them. Returns true when now chosen */
bool VIP_ToggleChosen(int admin, int target)
{
	if (!ChosenListToggle(g_aVIP_Chosen, target))
	{
		CPrintToChatAll("%s {olive}%N {lightgreen}is no longer a chosen VIP.", THIS_MODE_INFO.tag, target);
		LogAction(admin, target, "\"%L\" removed \"%L\" from the chosen VIPs", admin, target);
		return false;
	}

	CPrintToChatAll("%s {olive}%N {lightgreen}is now VIP every round until they leave, and can't be a mother zombie.", THIS_MODE_INFO.tag, target);
	LogAction(admin, target, "\"%L\" chose \"%L\" as VIP", admin, target);

	// Already in a round: VIP right now
	if (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bIsVIP[target] && IsHumanAlive(target))
		VIP_Make(target);

	return true;
}

void Event_VIPDisconnect(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (client)
		ChosenListForget(g_aVIP_Chosen, client);
}

/* The VIPs (and the chosen VIPs) are never picked as mother zombie (asked by ZR_OnClientMotherZombieEligible) */
bool VIPMode_BlocksMother(int client)
{
	return THIS_MODE_INFO.isOn && (g_bIsVIP[client] || VIP_IsChosen(client));
}

void RemoveClientVIP(int client, bool kill, const char[] translation = "")
{
	g_bIsVIP[client] = false;
	delete g_hVIPBeaconTimer[client];
	
	CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, translation, client);
	
	if (kill && GetCurrentVIPsCount() == 0 && g_bVIP_Replace)
	{
		VIP_PickVIPs();
		return;
	}

	if (kill && GetCurrentVIPsCount() == 0)
	{
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "VIPMode_KillAll", RoundToNearest(g_fVIP_KillDelay));

		delete g_hKillAllTimer;
		g_hKillAllTimer = CreateTimer(g_fVIP_KillDelay, VIPMode_KillAllTimer, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

/* A random living human who isn't a VIP yet becomes one, false if there is nobody left */
bool VIP_PickRandom()
{
	int players[MAXPLAYERS + 1];
	int count;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanAlive(i) || g_bIsVIP[i])
			continue;

		players[count] = i;
		count++;
	}

	if (!count)
		return false;

	VIP_Make(players[GetRandomInt(0, count - 1)]);
	return true;
}

void VIP_Make(int client)
{
	g_bIsVIP[client] = true;

	delete g_hVIPBeaconTimer[client];
	g_hVIPBeaconTimer[client] = CreateTimer(
		1.0,
		VIP_BeaconTimer,
		GetClientUserId(client),
		TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE
	);

	CPrintToChatAll("%s %N is VIP!", THIS_MODE_INFO.tag, client);
}

Action VIP_BeaconTimer(Handle timer, int userid)
{
	int client = GetClientOfUserId(userid);

	if (!client || !IsPlayerAlive(client) || !THIS_MODE_INFO.isOn)
		return Plugin_Stop;

	BeaconPlayer(client, 1);

	return Plugin_Continue;
}

Action VIPMode_KillAllTimer(Handle timer)
{
	g_hKillAllTimer = null;

	if (!THIS_MODE_INFO.isOn)
		return Plugin_Stop;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_CT)
			continue;

		ForcePlayerSuicide(i);
	}

	return Plugin_Stop;
}

stock int GetCurrentVIPsCount()
{
	int count;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bIsVIP[i])
			count++;
	}

	return count;
}

public Action Cmd_SetVIP(int client, int args)
{
	if (!THIS_MODE_INFO.isOn)
		return Plugin_Handled;

	if (args < 1)
		return Plugin_Handled;

	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));

	int target = FindTarget(client, arg, false, false);
	if (target < 1)
		return Plugin_Handled;

	VIP_ToggleChosen(client, target);
	return Plugin_Handled;
}

public Action Cmd_CheckVIP(int client, int args)
{
	bool found;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bIsVIP[i])
			continue;

		CReplyToCommand(client, "%s VIP: %N", THIS_MODE_INFO.tag, i);
		found = true;
	}

	if (!found)
		CReplyToCommand(client, "%s no VIP", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

public Action Cmd_VIPModeSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_VIPModeSettings);

	menu.SetTitle("%s - Settings\nChosen VIPs stay VIP every round until they leave,\nand are never picked as mother zombie\n ", THIS_MODE_INFO.name);
	menu.AddItem("pick", "Choose a VIP...");

	char line[48];
	FormatEx(line, sizeof(line), "Clear the chosen VIPs (%d)", g_aVIP_Chosen.Length);
	menu.AddItem("clear", line, g_aVIP_Chosen.Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	menu.AddItem("cvars", "Show Cvars");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

void VIP_ChooseMenu(int client)
{
	Menu menu = new Menu(Menu_VIPChoose);
	menu.SetTitle("Choose a VIP\nPick a chosen one again to undo\n ");

	char info[12], line[64];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsClientSourceTV(i))
			continue;

		IntToString(GetClientUserId(i), info, sizeof(info));
		FormatEx(line, sizeof(line), "%N%s%s", i, VIP_IsChosen(i) ? " [CHOSEN]" : "", g_bIsVIP[i] ? " [VIP]" : "");
		menu.AddItem(info, line);
	}

	if (!menu.ItemCount)
		menu.AddItem("", "Nobody on the server", ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_VIPChoose(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				Cmd_VIPModeSettings(param1, 0);
		}

		case MenuAction_Select:
		{
			char info[12];
			menu.GetItem(param2, info, sizeof(info));

			int target = GetClientOfUserId(StringToInt(info));
			if (target)
				VIP_ToggleChosen(param1, target);
			else
				CPrintToChat(param1, "%s That player left.", THIS_MODE_INFO.tag);

			VIP_ChooseMenu(param1);
		}
	}

	return 0;
}

int Menu_VIPModeSettings(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				DisplayModeInfo(param1, g_iPreviousModeIndex[param1]);
		}

		case MenuAction_Select:
		{
			char info[8];
			menu.GetItem(param2, info, sizeof(info));

			if (strcmp(info, "pick") == 0)
				VIP_ChooseMenu(param1);
			else if (strcmp(info, "clear") == 0)
			{
				g_aVIP_Chosen.Clear();
				CPrintToChatAll("%s The chosen VIPs were cleared.", THIS_MODE_INFO.tag);
				LogAction(param1, -1, "\"%L\" cleared the chosen VIPs", param1);
				Cmd_VIPModeSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
