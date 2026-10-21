/*
    (). FunModes V2:
        
    @file           FunModes.sp
    @Usage          This is the main plugin file, it contains all the forwards.
*/

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <cstrike>
#include <sdktools>
#include <sdkhooks>
#include <multicolors>
#include <zombiereloaded>

#undef REQUIRE_PLUGIN
#tryinclude <DynamicChannels>
#define REQUIRE_PLUGIN

#include "Fun_Modes/Core/Core.sp"

public Plugin myinfo =
{
	name = "FunModes",
	author = "Dolly, Hobbitten",
	description = "bunch of fun modes for ze mode",
	version = "3.0.0",
	url = "https://nide.gg"
}

public void OnPluginStart()
{
	/* TRANSLATIONS LAODS */
	LoadTranslations("common.phrases");
	LoadTranslations("FunModes.phrases");

	/* HUD HANDLE */
	g_hHudMsg = CreateHudSynchronizer();

	g_cvHUDChannel = CreateConVar("sm_funmodes_hud_channel", "4", "The channel for the hud if using DynamicChannels", _, true, 0.0, true, 5.0);

	Shared_OnPluginStart();
	Forwards_OnPluginStart();

	DECLARE_FM_FORWARD_PARAM0(InitCvarsValues)

	AutoExecConfig();

	static const char commands[][] = { "sm_fm_cvars", "sm_funmodes", "sm_funmode" };
	for(int i = 0; i < sizeof(commands); i++)
	{
		RegAdminCmd(commands[i], Cmd_FunModes, ADMFLAG_CONVARS, "Show all available funmodes");
	}

	RegAdminCmd("sm_fmcvar", Cmd_FunModesCvars, ADMFLAG_CONVARS, "Change a FunModes cvar");
	RegAdminCmd("sm_fm", Cmd_FunModesState, ADMFLAG_CONVARS, "sm_fm <mode> [on|off] | sm_fm list | sm_fm stop");

	g_iNetPropAmmoIndex = FindSendPropInfo("CBasePlayer", "m_iAmmo");
	if (g_iNetPropAmmoIndex == -1)
		SetFailState("[FunModes] Could not find offset `CBasePlayer::m_iAmmo`");

	GameData gd = new GameData("sdkhooks.games/engine.ep2v");
	if (gd == null)
		LogError("[FunModes] Could not find \"sdkhooks.games/engine.ep2v.txt\" file.");
	else
	{
		int offset = gd.GetOffset("Weapon_Switch");
		if (offset == -1)
		{
			delete gd;
			LogError("[FunModes] Could not find the offset of \"Weapon_Switch\", some features may be neglected");
			return;
		}

		StartPrepSDKCall(SDKCall_Player);
		PrepSDKCall_SetVirtual(offset);
		
		PrepSDKCall_AddParameter(SDKType_CBaseEntity, SDKPass_Pointer);
		PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_ByValue);
		
		g_hSwitchSDKCall = EndPrepSDKCall();
		
		if (g_hSwitchSDKCall == null)
			LogError("[FunModes] Incorrect offset for \"Weapon_Switch\", Cannot get a good SDKCall Handle");

		delete gd;
	}
}

public void OnPluginEnd()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		OnClientDisconnect(i);
	}

	DECLARE_FM_FORWARD_PARAM0(OnPluginEnd)
}

public void OnMapStart()
{
	g_LaserSprite = PrecacheModel("sprites/laser.vmt");
	g_HaloSprite = PrecacheModel("materials/sprites/halo.vtf");
	g_iLaserBeam = PrecacheModel("materials/sprites/laserbeam.vmt");

	PrecacheSound(Beacon_Sound, true);

	Shared_OnMapStart();

	DECLARE_FM_FORWARD_PARAM0(OnMapStart)
}

public void OnMapEnd()
{
	DECLARE_FM_FORWARD_PARAM0(OnMapEnd)

	Shared_OnMapEnd();
}

public void OnClientPutInServer(int client)
{
	DECLARE_FM_FORWARD_PARAM1(OnClientPutInServer, client)
}

public void OnClientDisconnect(int client)
{
	g_bSDKHook_OnTakeDamagePost[client] = false;
	g_bSDKHook_OnTakeDamage[client] = false;
	g_bSDKHook_WeaponEquip[client] = false;
	DECLARE_FM_FORWARD_PARAM1(OnClientDisconnect, client)
}

public void ZR_OnClientInfected(int client, int attacker, bool motherInfect)
{		
	g_bInfectionIsMother = motherInfect;
	DECLARE_FM_FORWARD_PARAM1(ZR_OnClientInfected, client)
	if (motherInfect && !g_bMotherZombie)
		g_bMotherZombie = true;

	// React at once instead of waiting for the next check
	FunModes_RunCheck();
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnd = false;
	g_bMotherZombie = false;
	Shared_RoundStart();
	DECLARE_FM_FORWARD_PARAM0(Event_RoundStart)
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	g_bRoundEnd = true;
	g_bMotherZombie = false;
	Shared_RoundEnd();
	DECLARE_FM_FORWARD_PARAM0(Event_RoundEnd)
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	DECLARE_FM_FORWARD_PARAM1(Event_PlayerSpawn, client)
}

void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	DECLARE_FM_FORWARD_PARAM1(Event_PlayerTeam, event)
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	DECLARE_FM_FORWARD_PARAM1(Event_PlayerDeath, client)

	// React at once instead of waiting for the next check
	FunModes_RunCheck();
}

void OnTakeDamagePost(int victim, int attacker, int inflictor, float damage, int damagetype)
{
	DECLARE_FM_FORWARD_PARAM3(OnTakeDamagePost, victim, attacker, damage)
}

Action OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype)
{
	Action result = Plugin_Continue;

	DECLARE_FM_FORWARD_PARAM4(OnTakeDamage, victim, attacker, damage, result)

	return result;
}

Action OnWeaponEquip(int client, int weapon)
{
	Action result = Plugin_Continue;

	DECLARE_FM_FORWARD_PARAM3(OnWeaponEquip, client, weapon, result)

	return result;
}

/* Events Hooks functions */
void FunModes_HookEvent(bool &modeBool, const char[] name, EventHook callback)
{
	if (!modeBool)
	{
		modeBool = true;
		HookEvent(name, callback);
	}
}

void FunModes_RestartRound()
{
	// The Event Roulette turns modes on at round start or during it, no restart then
	if (g_bSkipRestartRound)
		return;

	// slay all players before terminating the round
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		ForcePlayerSuicide(i);
	}

	CS_TerminateRound(3.0, CSRoundEnd_Draw);
}

public void OnAllPluginsLoaded()
{
	g_bPlugin_DynamicChannels = LibraryExists("DynamicChannels");
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bPlugin_DynamicChannels = true;
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "DynamicChannels", false) == 0)
		g_bPlugin_DynamicChannels = false;
}

public void OnPlayerRunCmdPost(int client, int buttons, int impulse)
{
	DECLARE_FM_FORWARD_PARAM3(OnPlayerRunCmdPost, client, buttons, impulse)
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
	bool changed = false;
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (g_ModesInfo[i].isOn)
			g_ModesInfo[i].forwards.Call_OnPlayerRunCmd(client, buttons, vel, changed);
	}

	return changed ? Plugin_Changed : Plugin_Continue;
}

/* Buys go to the modes that lock weapons, until one of them blocks it */
public Action CS_OnBuyCommand(int client, const char[] weapon)
{
	Action result = Plugin_Continue;
	for (int i = 0; i < g_iLastModeIndex && result == Plugin_Continue; i++)
	{
		if (g_ModesInfo[i].isOn)
			g_ModesInfo[i].forwards.Call_OnBuyCommand(client, weapon, result);
	}

	return result;
}

/* Chat goes to the modes that read answers from it, until one of them handles it */
public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	Action result = Plugin_Continue;
	for (int i = 0; i < g_iLastModeIndex && result == Plugin_Continue; i++)
	{
		if (g_ModesInfo[i].isOn)
			g_ModesInfo[i].forwards.Call_OnClientSayCommand(client, sArgs, result);
	}

	return result;
}

float GetDistanceBetween(int origin, int target, bool squarred = false)
{
	float fOrigin[3], fTarget[3];

	GetEntPropVector(origin, Prop_Data, "m_vecOrigin", fOrigin);
	GetEntPropVector(target, Prop_Data, "m_vecOrigin", fTarget);

	return GetVectorDistance(fOrigin, fTarget, squarred);
}

stock void BeaconPlayer(int client, int mode, float distance = 0.0, int color[4] = {0,0,0,0})
{
	float vec[3];
	GetClientAbsOrigin(client, vec);
	vec[2] += 10;

	if (mode == 0)
	{
		TE_SetupBeamRingPoint(vec, (distance - 10.0), distance, g_LaserSprite, g_HaloSprite, 0, 15, 0.1, 10.0, 0.0, color, 10, 0);
		TE_SendToAll();
	}
	else
	{
		TE_SetupBeamRingPoint(vec, 10.0, 375.0, g_LaserSprite, g_HaloSprite, 0, 15, 0.5, 5.0, 0.0, g_ColorCyan, 10, 0);
		TE_SendToAll();

		int rainbowColor[4];
		float f = GetGameTime();
		float frequency = 2.5;
		rainbowColor[0] = RoundFloat(Sine(frequency * f + 0.0) * 127.0 + 128.0);
		rainbowColor[1] = RoundFloat(Sine(frequency * f + 2.0943951) * 127.0 + 128.0);
		rainbowColor[2] = RoundFloat(Sine(frequency * f + 4.1887902) * 127.0 + 128.0);
		rainbowColor[3] = 255;

		TE_SetupBeamRingPoint(vec, 10.0, 375.0, g_LaserSprite, g_HaloSprite, 0, 10, 0.6, 10.0, 0.5, rainbowColor, 10, 0);

		TE_SendToAll();
		EmitAmbientSound(Beacon_Sound, vec, client, SNDLEVEL_RAIDSIREN);
	}
}

Action Cmd_FunModes(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	g_iMenuCategory[client] = -1;

	Menu menu = new Menu(Menu_MainModes);
	menu.SetTitle("[FunModes] Available modes!");

	char index[6], line[64];

	// Modes that don't belong to a category (the Event Roulette) come first
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (g_ModesInfo[i].category != FM_CAT_MAIN)
			continue;

		FormatEx(index, sizeof(index), "m%d", i);
		FormatEx(line, sizeof(line), "%s%s", g_ModesInfo[i].name, g_ModesInfo[i].isOn ? " [ON]" : "");
		menu.AddItem(index, line);
	}

	for (int cat = 0; cat < view_as<int>(FM_CAT_COUNT); cat++)
	{
		int total, on;
		for (int i = 0; i < g_iLastModeIndex; i++)
		{
			if (g_ModesInfo[i].category != view_as<FM_Category>(cat))
				continue;

			total++;
			if (g_ModesInfo[i].isOn)
				on++;
		}

		if (!total)
			continue;

		FormatEx(index, sizeof(index), "c%d", cat);
		if (on)
			FormatEx(line, sizeof(line), "%s (%d on)", g_sCategoryNames[cat], on);
		else
			FormatEx(line, sizeof(line), "%s", g_sCategoryNames[cat]);

		menu.AddItem(index, line);
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

int Menu_MainModes(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Select:
		{
			char index[6];
			menu.GetItem(param2, index, sizeof(index));

			if (index[0] == 'c')
				DisplayCategory(param1, StringToInt(index[1]));
			else
				DisplayModeInfo(param1, StringToInt(index[1]));
		}
	}
	
	return 0;
}

void DisplayCategory(int client, int cat)
{
	g_iMenuCategory[client] = cat;

	Menu menu = new Menu(Menu_Category);
	menu.SetTitle("[FunModes] %s", g_sCategoryNames[cat]);

	char index[4], line[64];
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (g_ModesInfo[i].category != view_as<FM_Category>(cat))
			continue;

		IntToString(i, index, sizeof(index));
		FormatEx(line, sizeof(line), "%s%s", g_ModesInfo[i].name, g_ModesInfo[i].isOn ? " [ON]" : "");
		menu.AddItem(index, line);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_Category(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				Cmd_FunModes(param1, 0);
		}

		case MenuAction_Select:
		{
			char index[4];
			menu.GetItem(param2, index, sizeof(index));
			DisplayModeInfo(param1, StringToInt(index));
		}
	}

	return 0;
}

void DisplayModeInfo(int client, int modeIndex)
{
	g_iPreviousModeIndex[client] = modeIndex;

	Menu menu = new Menu(Menu_DisplayConVars);

	ModeInfo info;
	info = g_ModesInfo[modeIndex];

	FM_ConVar cvar;
	cvar = info.cvars[info.enableIndex];
	bool enabled = FUNMODES_CVAR_GET_VALUE(cvar, Bool);

	menu.SetTitle("%s - Mode Info\nStatus: %s - %s\n", info.name, enabled?"Enabled":"Disabled", info.isOn?"On":"Off");

	menu.AddItem(info.name, "Toggle", enabled?ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	menu.AddItem(info.name, "Settings");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_DisplayConVars(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;
		
		case MenuAction_Cancel:
		{
			if (param2 != MenuCancel_ExitBack)
				return 0;

			if (g_iMenuCategory[param1] >= 0)
				DisplayCategory(param1, g_iMenuCategory[param1]);
			else
				Cmd_FunModes(param1, 0);
		}
		
		case MenuAction_Select:
		{
			char modeName[32];
			menu.GetItem(param2, modeName, sizeof(modeName));

			char functionName[46];
			FormatEx(functionName, sizeof(functionName), "Cmd_%s%s", modeName, (param2 == 0) ? "Toggle" : "Settings");

			Function myFunction = GetFunctionByName(null, functionName);
			if (myFunction == INVALID_FUNCTION)
				return -1;

			Call_StartFunction(null, myFunction);

			Call_PushCell(param1);
			Call_PushCell(0);

			Call_Finish();

			if (param2 == 0)
				DisplayModeInfo(param1, g_iPreviousModeIndex[param1]);
		}
	}

	return 0;
}

void ShowCvarsInfo(int client, ModeInfo info)
{
	g_iPreviousModeIndex[client] = info.index;

	info = g_ModesInfo[info.index];

	Menu menu = new Menu(Menu_CvarsInfo);

	menu.SetTitle("%s - ConVars List", info.name);

	for (int i = 0; i < sizeof(ModeInfo::cvars); i++)
	{
		if (!FUNMODES_CVAR_ISVALID(info.cvars[i]) || info.cvars[i].type == CONVAR_STRING)
			continue;

		char index[3];
		IntToString(i, index, sizeof(index));

		menu.AddItem(index, info.cvars[i].name);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_CvarsInfo(Menu menu, MenuAction action, int param1, int param2)
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
			char indexStr[3];
			menu.GetItem(param2, indexStr, sizeof(indexStr));

			ShowCvarInfo(param1, g_ModesInfo[g_iPreviousModeIndex[param1]].cvars[StringToInt(indexStr)]);
		}
	}

	return 0;
}

void ShowCvarInfo(int client, FM_ConVar thisCvarInfo)
{
	g_iPreviousModeIndex[client] = thisCvarInfo.modeIndex;

	Menu menu = new Menu(Menu_ShowCvarInfo);

	menu.SetTitle("%s\n- %s", thisCvarInfo.name, thisCvarInfo.description);

	int valsCount;
	for (int i = 0; i < sizeof(thisCvarInfo.values); i++)
	{
		if (thisCvarInfo.values[i] == ',')
			valsCount++;
	}

	valsCount++;

	char[][] dataEx = new char[valsCount][8];
	ExplodeString(thisCvarInfo.values, ",", dataEx, valsCount, 8);

	any currentVal = GetValFromCvar(thisCvarInfo, thisCvarInfo.type);

	bool currentValExists = false;
	for (int i = 0; i < valsCount; i++)
	{
		any val = GetValFromCvar(_, thisCvarInfo.type, dataEx[i]);
		if (val == currentVal)
			currentValExists = true;

		char data[22];
		FormatEx(data, sizeof(data), "%d|%d|%s", thisCvarInfo.modeIndex, thisCvarInfo.cvarIndex, dataEx[i]);

		menu.AddItem(data, dataEx[i], val == currentVal ? ITEMDRAW_DISABLED : ITEMDRAW_DEFAULT);
	}

	if (!currentValExists)
		menu.AddItem(NULL_STRING, FUNMODES_CVAR_GET_VALUE(thisCvarInfo, String), ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

int Menu_ShowCvarInfo(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				ShowCvarsInfo(param1, g_ModesInfo[g_iPreviousModeIndex[param1]]);
		}

		case MenuAction_Select:
		{
			char data[100];
			menu.GetItem(param2, data, sizeof(data));

			char dataEx[3][22];
			ExplodeString(data, "|", dataEx, sizeof(dataEx), sizeof(dataEx[]));

			int modeIndex = StringToInt(dataEx[0]); 
			int cvarIndex = StringToInt(dataEx[1]);

			FM_ConVar cvar;
			cvar = g_ModesInfo[modeIndex].cvars[cvarIndex];
			FUNMODES_CVAR_SET_VALUE(cvar, String, dataEx[2]);

			// Just to avoid some random sourcemod bug...
			strcopy(g_ModesInfo[modeIndex].cvars[cvarIndex].currentValue, sizeof(FM_ConVar::currentValue), dataEx[2]);

			CPrintToChat(param1, "{gold}[FunModes]{lightgreen} You have changed {olive}%s {lightgreen}value to {olive}%s.", cvar.name, dataEx[2]);

			ShowCvarInfo(param1, cvar);
		}
	}

	return 0;
}

any GetValFromCvar(FM_ConVar cvar = {}, ConVarType type, const char[] valStr = "")
{
	switch (type)
	{
		case CONVAR_INT: 	return (FUNMODES_CVAR_ISVALID(cvar)) ? FUNMODES_CVAR_GET_VALUE(cvar, Int) 	: StringToInt(valStr);
		case CONVAR_FLOAT: 	return (FUNMODES_CVAR_ISVALID(cvar)) ? FUNMODES_CVAR_GET_VALUE(cvar, Float) : StringToFloat(valStr);
		case CONVAR_BOOL: 	return (FUNMODES_CVAR_ISVALID(cvar)) ? FUNMODES_CVAR_GET_VALUE(cvar, Bool) 	: view_as<bool>(StringToInt(valStr));
	}

	return 0;
}

Action Cmd_FunModesCvars(int client, int args)
{
	if (args < 1)
	{
		CReplyToCommand(client, "[FunModes] Usage: sm_fmcvar <cvar> <value>");
		return Plugin_Handled;
	}

	char cvarName[sizeof(FM_ConVar::name)];
	GetCmdArg(1, cvarName, sizeof(cvarName));

	bool exists;
	FM_ConVar cvar;
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (exists)
			break;

		for (int j = 0; j < sizeof(ModeInfo::cvars); j++)
		{
			cvar = g_ModesInfo[i].cvars[j];
			if (!FUNMODES_CVAR_ISVALID(cvar))
				continue;

			if (strcmp(cvar.name, cvarName, false) != 0)
				continue;

			exists = true;
			break;
		}
	}

	if (!exists)
	{
		CReplyToCommand(client, "{gold}[FunModes]{lightgreen} Cannot find the specified cvar.");
		return Plugin_Handled;
	}

	if (args < 2)
	{
		CReplyToCommand(client, "{gold}[FunModes]{lightgreen} %s value is: {olive}%s", cvar.name, cvar.currentValue);
		return Plugin_Handled;
	}

	char newValue[sizeof(FM_ConVar::defaultValue)];
	GetCmdArg(2, newValue, sizeof(newValue));

	FUNMODES_CVAR_SET_VALUE(cvar, String, newValue);
	int cvarIndex = cvar.cvarIndex;
	int modeIndex = cvar.modeIndex;

	g_ModesInfo[modeIndex].cvars[cvarIndex] = cvar;
	CReplyToCommand(client, "{gold}[FunModes]{lightgreen} changed %s value to: {olive}%s", cvar.name, cvar.currentValue);

	return Plugin_Handled;
}

stock void SendHudText(int client, const char[] message, bool isFar = false, int color = -1)
{
	static bool dynamicAvailable;
	int hudChannel = -1;

	if (!dynamicAvailable)
		dynamicAvailable = g_bPlugin_DynamicChannels && GetFeatureStatus(FeatureType_Native, "GetDynamicChannel") == FeatureStatus_Available;

	int channel = g_cvHUDChannel.IntValue;
	if (channel < 0 || channel > 5)
		channel = 4;

#if defined _DynamicChannels_included_
	if (dynamicAvailable)
		hudChannel = GetDynamicChannel(channel);
#endif

	if (isFar)
		SetHudTextParams(-0.2, 1.0, 0.7, 255, 13, 55, 255);
	else
		SetHudTextParams(-1.0, 0.1, 2.0, 255, 36, 255, 13);

	switch(color)
	{
		case 0:
		{
			SetHudTextParams(-1.0, 0.1, 2.0, 255, 36, 255, 13);
		}
		case 1:
		{
			SetHudTextParams(-1.0, 0.1, 2.0, 255, 0, 0, 50);
		}
		case 2:
		{
			SetHudTextParams(-1.0, 0.1, 2.0, 124, 252, 0, 50);
		}
	}

	if (dynamicAvailable)
	{
		ShowHudText(client, hudChannel, "%s", message);
		return;
	}

	ClearSyncHud(client, g_hHudMsg);
	ShowSyncHudText(client, g_hHudMsg, "%s", message);
}

stock bool HasPlayerItem(int client, const char[] weapon)
{
	int max = GetEntPropArraySize(client, Prop_Send, "m_hMyWeapons");
	for (int i = 0; i < max; i++)
	{
		int ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
		if (ent == -1 || !IsValidEntity(ent))
			continue;

		char className[32];
		GetEntityClassname(ent, className, sizeof(className));
		if (strcmp(className, weapon, false) == 0)
			return true;
	}

	return false;
}

public void OnConfigsExecuted()
{
	delete g_hKV;
	g_hKV = new KeyValues("FunModes_Cvars");

	// No file yet: start an empty one, it gets filled as the cvars change
	if (!g_hKV.ImportFromFile(FUNMODES_CVAR_CONFIG) || !g_hKV.GotoFirstSubKey())
	{
		g_hKV.Rewind();
		return;
	}

	// The cvars are matched by name, so adding a mode or a cvar never shifts the saved values
	do
	{
		char name[sizeof(FM_ConVar::name)];
		g_hKV.GetString("name", name, sizeof(name));

		int modeIndex, cvarIndex;
		if (!FunModes_FindCvar(name, modeIndex, cvarIndex))
			continue;

		FM_ConVar cvar;
		cvar = g_ModesInfo[modeIndex].cvars[cvarIndex];

		char defaultValue[sizeof(FM_ConVar::defaultValue)];
		g_hKV.GetString("default", defaultValue, sizeof(defaultValue));
		if (!defaultValue[0])
			continue;

		cvar.defaultValue = defaultValue;

		cvar.autoChange = true;

		char currentValue[sizeof(FM_ConVar::currentValue)];
		g_hKV.GetString("currentvalue", currentValue, sizeof(currentValue));
		if (currentValue[0])
			FUNMODES_CVAR_SET_VALUE(cvar, String, currentValue);
		else
			FUNMODES_CVAR_SET_VALUE(cvar, String, defaultValue);

		cvar.autoChange = false;

		char description[sizeof(FM_ConVar::description)];
		g_hKV.GetString("description", description, sizeof(description));
		if (description[0])
			cvar.description = description;

		char values[sizeof(FM_ConVar::values)];
		g_hKV.GetString("values", values, sizeof(values));
		if (values[0])
			cvar.values = values;

		g_ModesInfo[modeIndex].cvars[cvarIndex] = cvar;
		g_ModesInfo[modeIndex].cvars[cvarIndex].currentValue = cvar.currentValue;
	} while (g_hKV.GotoNextKey());

	g_hKV.Rewind();
}

bool FunModes_FindCvar(const char[] name, int &modeIndex, int &cvarIndex)
{
	if (!name[0])
		return false;

	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		for (int j = 0; j < sizeof(ModeInfo::cvars); j++)
		{
			if (strcmp(g_ModesInfo[i].cvars[j].name, name, false) != 0)
				continue;

			modeIndex = i;
			cvarIndex = j;
			return true;
		}
	}

	return false;
}

/* Saves a cvar's current value in the config, adding the cvar to it if it's not there yet */
void FunModes_SaveCvar(FM_ConVar cvar)
{
	if (g_hKV == null)
		return;

	g_hKV.Rewind();

	int lastKey = -1;
	bool found = false;
	if (g_hKV.GotoFirstSubKey())
	{
		do
		{
			char section[8];
			g_hKV.GetSectionName(section, sizeof(section));
			if (StringToInt(section) > lastKey)
				lastKey = StringToInt(section);

			char name[sizeof(FM_ConVar::name)];
			g_hKV.GetString("name", name, sizeof(name));
			if (strcmp(name, cvar.name, false) != 0)
				continue;

			g_hKV.SetString("currentValue", cvar.currentValue);
			found = true;
			break;
		} while (g_hKV.GotoNextKey());
	}

	g_hKV.Rewind();

	if (!found)
	{
		char key[8];
		IntToString(lastKey + 1, key, sizeof(key));
		g_hKV.JumpToKey(key, true);
		g_hKV.SetString("name", cvar.name);
		g_hKV.SetString("Default", cvar.defaultValue);
		g_hKV.SetString("description", cvar.description);
		g_hKV.SetString("currentValue", cvar.currentValue);
		g_hKV.Rewind();
	}

	g_hKV.ExportToFile(FUNMODES_CVAR_CONFIG);
}

int FunModes_FindMode(const char[] name)
{
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (strcmp(g_ModesInfo[i].name, name, false) == 0)
			return i;
	}

	return -1;
}

/* Turns a mode on or off the same way its toggle command does, returns whether it's now in the wanted state */
bool FunModes_SetModeState(int modeIndex, bool on, int client = 0)
{
	if (g_ModesInfo[modeIndex].isOn == on)
		return true;

	char functionName[46];
	FormatEx(functionName, sizeof(functionName), "Cmd_%sToggle", g_ModesInfo[modeIndex].name);

	Function toggle = GetFunctionByName(null, functionName);
	if (toggle == INVALID_FUNCTION)
		return false;

	Call_StartFunction(null, toggle);
	Call_PushCell(client);
	Call_PushCell(0);
	Call_Finish();

	return g_ModesInfo[modeIndex].isOn == on;
}

Action Cmd_FunModesState(int client, int args)
{
	if (args < 1)
	{
		if (client)
			Cmd_FunModes(client, 0);
		else
			ReplyToCommand(client, "[FunModes] Usage: sm_fm <mode> [on|off] | sm_fm list | sm_fm stop");

		return Plugin_Handled;
	}

	char arg[32];
	GetCmdArg(1, arg, sizeof(arg));

	if (strcmp(arg, "list", false) == 0)
	{
		char line[256];
		for (int i = 0; i < g_iLastModeIndex; i++)
		{
			char entry[48];
			FormatEx(entry, sizeof(entry), "%s%s%s", line[0] ? ", " : "", g_ModesInfo[i].name, g_ModesInfo[i].isOn ? " [ON]" : "");
			if (strlen(line) + strlen(entry) > 180)
			{
				ReplyToCommand(client, "[FunModes] %s", line);
				line[0] = '\0';
				FormatEx(entry, sizeof(entry), "%s%s", g_ModesInfo[i].name, g_ModesInfo[i].isOn ? " [ON]" : "");
			}

			StrCat(line, sizeof(line), entry);
		}

		ReplyToCommand(client, "[FunModes] %s", line);
		return Plugin_Handled;
	}

	if (strcmp(arg, "stop", false) == 0)
	{
		for (int i = 0; i < g_iLastModeIndex; i++)
			FunModes_SetModeState(i, false, client);

		CPrintToChatAll("{gold}[FunModes]{lightgreen} {olive}%N {lightgreen}stopped all the modes.", client);
		LogAction(client, -1, "\"%L\" stopped all the funmodes", client);
		return Plugin_Handled;
	}

	int modeIndex = FunModes_FindMode(arg);
	if (modeIndex == -1)
	{
		CReplyToCommand(client, "{gold}[FunModes]{lightgreen} Unknown mode {olive}%s{lightgreen}, type sm_fm list", arg);
		return Plugin_Handled;
	}

	bool on = !g_ModesInfo[modeIndex].isOn;
	if (args >= 2)
	{
		char state[8];
		GetCmdArg(2, state, sizeof(state));
		if (strcmp(state, "on", false) == 0 || strcmp(state, "1") == 0)
			on = true;
		else if (strcmp(state, "off", false) == 0 || strcmp(state, "0") == 0)
			on = false;
		else
		{
			ReplyToCommand(client, "[FunModes] Usage: sm_fm <mode> [on|off]");
			return Plugin_Handled;
		}
	}

	if (!FunModes_SetModeState(modeIndex, on, client))
		CReplyToCommand(client, "{gold}[FunModes]{lightgreen} Couldn't turn {olive}%s {lightgreen}%s.", g_ModesInfo[modeIndex].name, on ? "on" : "off");
	else
		LogAction(client, -1, "\"%L\" turned the funmode %s %s", client, g_ModesInfo[modeIndex].name, on ? "on" : "off");

	return Plugin_Handled;
}
