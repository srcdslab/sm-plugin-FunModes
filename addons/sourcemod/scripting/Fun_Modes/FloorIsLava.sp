/*
    (). FunModes V2:

    @file           FloorIsLava.sp
    @Usage          Functions for the FloorIsLava mode.
                    Once the zombies are out, whoever stands still for more than a few seconds starts burning.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_FloorIsLava

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "FloorIsLava"

static int g_iFloorIsLavaIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iFloorIsLavaIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define LAVA_CONVAR_AFTER    0
#define LAVA_CONVAR_DAMAGE   1
#define LAVA_CONVAR_EVERYONE 2
#define LAVA_CONVAR_TOGGLE   3

int g_iLava_After;
int g_iLava_Damage;
bool g_bLava_Everyone;
bool g_bFloorIsLava_Enabled;

public void OnPluginStart_FloorIsLava()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_lava", Cmd_FloorIsLavaToggle, ADMFLAG_CONVARS, "Turn Floor is Lava On/Off");
	RegAdminCmd("sm_lava_settings", Cmd_FloorIsLavaSettings, ADMFLAG_CONVARS, "Open Floor is Lava Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		LAVA_CONVAR_AFTER, "sm_lava_after",
		"3", "Seconds standing still before it burns",
		("2,3,5,8,12"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LAVA_CONVAR_DAMAGE, "sm_lava_damage",
		"10", "Damage per second while standing still (1000 = slay)",
		("5,10,20,50,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LAVA_CONVAR_EVERYONE, "sm_lava_everyone",
		"0", "The zombies burn too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		LAVA_CONVAR_TOGGLE, "sm_lava_enable",
		"1", "Enable/Disable Floor is Lava Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= LAVA_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(FloorIsLava_OnConVarChange);

	THIS_MODE_INFO.enableIndex = LAVA_CONVAR_TOGGLE;

	FloorIsLava_OnPluginStart();
}

public void InitCvarsValues_FloorIsLava()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iLava_After = _FUNMODES_CVAR_GET_VALUE(modeIndex, LAVA_CONVAR_AFTER, Int);
	g_iLava_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, LAVA_CONVAR_DAMAGE, Int);
	g_bLava_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, LAVA_CONVAR_EVERYONE, Bool);
	g_bFloorIsLava_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, LAVA_CONVAR_TOGGLE, Bool);
}

void FloorIsLava_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case LAVA_CONVAR_AFTER:
			g_iLava_After = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LAVA_CONVAR_DAMAGE:
			g_iLava_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LAVA_CONVAR_EVERYONE:
			g_bLava_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case LAVA_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				FloorIsLava_Reset();
			}

			g_bFloorIsLava_Enabled = val;
		}
	}
}

public void OnMapEnd_FloorIsLava()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	FloorIsLava_Reset();
}

#define LAVA_SPOT 64.0                  // moving less than this counts as standing still

float g_fLava_Anchor[MAXPLAYERS + 1][3];
float g_fLava_StillSince[MAXPLAYERS + 1];  // 0 = not tracked yet
float g_fLava_Owed[MAXPLAYERS + 1];
Handle g_hLava_Hud;

void FloorIsLava_OnPluginStart()
{
	g_hLava_Hud = CreateModeHud();
}

void FloorIsLava_Reset()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_fLava_StillSince[i] = 0.0;
		g_fLava_Owed[i] = 0.0;
	}
}

public void Event_RoundStart_FloorIsLava()
{
	FloorIsLava_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s The floor is lava: once the zombies come, don't stand still for more than {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, g_iLava_After);
}

public void OnCheck_FloorIsLava(bool zombiesNow)
{
	if (!g_bZombiesSeen)
		return;

	float now = GetGameTime(), pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bLava_Everyone))
		{
			g_fLava_StillSince[i] = 0.0;
			continue;
		}

		GetClientAbsOrigin(i, pos);
		if (g_fLava_StillSince[i] == 0.0 || GetVectorDistance(pos, g_fLava_Anchor[i]) > LAVA_SPOT)
		{
			g_fLava_Anchor[i] = pos;
			g_fLava_StillSince[i] = now;
			g_fLava_Owed[i] = 0.0;
			continue;
		}

		if (now - g_fLava_StillSince[i] < float(g_iLava_After))
			continue;

		if (g_iLava_Damage >= 1000)
		{
			CPrintToChatAll("%s {olive}%N {lightgreen}stood still too long and melted!", THIS_MODE_INFO.tag, i);
			ForcePlayerSuicide(i);
			continue;
		}

		// This runs every 0.2 s
		g_fLava_Owed[i] += float(g_iLava_Damage) * 0.2;
		int whole = RoundToFloor(g_fLava_Owed[i]);
		if (whole > 0)
		{
			g_fLava_Owed[i] -= float(whole);
			HurtPlayer(i, whole);
		}
	}
}

public void OnTick_FloorIsLava()
{
	if (!g_bZombiesSeen)
		return;

	float now = GetGameTime();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bLava_Everyone) || IsFakeClient(i) || g_fLava_StillSince[i] == 0.0)
			continue;

		float still = now - g_fLava_StillSince[i];
		if (still >= float(g_iLava_After))
		{
			SetHudTextParams(-1.0, 0.52, 1.1, 255, 80, 20, 255, 0, 0.0, 0.0, 0.0);
			ShowModeHud(i, g_hLava_Hud, "THE FLOOR IS LAVA - MOVE! (-%d HP/s)", g_iLava_Damage >= 1000 ? 999 : g_iLava_Damage);
		}
		else if (still >= float(g_iLava_After) - 1.5)
		{
			SetHudTextParams(-1.0, 0.52, 1.1, 255, 200, 40, 255, 0, 0.0, 0.0, 0.0);
			ShowModeHud(i, g_hLava_Hud, "Keep moving...");
		}
	}
}

public Action Cmd_FloorIsLavaToggle(int client, int args)
{
	if (!g_bFloorIsLava_Enabled)
	{
		CReplyToCommand(client, "%s Floor is Lava is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	FloorIsLava_Reset();

	CPrintToChatAll("%s Floor is Lava is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Once the zombies come, {olive}don't stand still{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* FloorIsLava Settings */
public Action Cmd_FloorIsLavaSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_FloorIsLavaSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_FloorIsLavaSettings(Menu menu, MenuAction action, int param1, int param2)
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
			ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
