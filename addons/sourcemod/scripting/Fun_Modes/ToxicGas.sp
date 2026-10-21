/*
    (). FunModes V2:

    @file           ToxicGas.sp
    @Usage          Functions for the ToxicGas mode.
                    Once the zombies are out, every few seconds green clouds of gas appear where some humans
                    stand, hurting whoever stays inside them until they fade away.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_ToxicGas

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "ToxicGas"

static int g_iToxicGasIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iToxicGasIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define GAS_CONVAR_EVERY   0
#define GAS_CONVAR_COUNT   1
#define GAS_CONVAR_LAST    2
#define GAS_CONVAR_RADIUS  3
#define GAS_CONVAR_DAMAGE  4
#define GAS_CONVAR_ZOMBIES 5
#define GAS_CONVAR_TOGGLE  6

int g_iGas_Every;
int g_iGas_Count;
int g_iGas_Last;
float g_fGas_Radius;
int g_iGas_Damage;
bool g_bGas_Zombies;
bool g_bToxicGas_Enabled;

public void OnPluginStart_ToxicGas()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_gas", Cmd_ToxicGasToggle, ADMFLAG_CONVARS, "Turn Toxic Gas On/Off");
	RegAdminCmd("sm_gas_settings", Cmd_ToxicGasSettings, ADMFLAG_CONVARS, "Open Toxic Gas Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		GAS_CONVAR_EVERY, "sm_gas_every",
		"45", "Seconds between two gas leaks",
		("20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GAS_CONVAR_COUNT, "sm_gas_count",
		"2", "Gas clouds per leak",
		("1,2,3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GAS_CONVAR_LAST, "sm_gas_last",
		"15", "Seconds a gas cloud lasts",
		("10,15,20,30"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GAS_CONVAR_RADIUS, "sm_gas_radius",
		"200.0", "Radius of a gas cloud",
		("150.0,200.0,300.0,400.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		GAS_CONVAR_DAMAGE, "sm_gas_damage",
		"5", "Damage per second inside a gas cloud",
		("3,5,10,20"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GAS_CONVAR_ZOMBIES, "sm_gas_zombies",
		"0", "The gas hurts the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		GAS_CONVAR_TOGGLE, "sm_gas_enable",
		"1", "Enable/Disable Toxic Gas Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= GAS_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(ToxicGas_OnConVarChange);

	THIS_MODE_INFO.enableIndex = GAS_CONVAR_TOGGLE;
}

public void InitCvarsValues_ToxicGas()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iGas_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, GAS_CONVAR_EVERY, Int);
	g_iGas_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, GAS_CONVAR_COUNT, Int);
	g_iGas_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, GAS_CONVAR_LAST, Int);
	g_fGas_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, GAS_CONVAR_RADIUS, Float);
	g_iGas_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, GAS_CONVAR_DAMAGE, Int);
	g_bGas_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, GAS_CONVAR_ZOMBIES, Bool);
	g_bToxicGas_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, GAS_CONVAR_TOGGLE, Bool);
}

void ToxicGas_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case GAS_CONVAR_EVERY:
			g_iGas_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GAS_CONVAR_COUNT:
			g_iGas_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GAS_CONVAR_LAST:
			g_iGas_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GAS_CONVAR_RADIUS:
			g_fGas_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case GAS_CONVAR_DAMAGE:
			g_iGas_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GAS_CONVAR_ZOMBIES:
			g_bGas_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case GAS_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				ToxicGas_Reset();
			}

			g_bToxicGas_Enabled = val;
		}
	}
}

public void OnMapEnd_ToxicGas()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	ToxicGas_Reset();
}

#define GAS_MAX 8

int g_iGas_Color[4] = { 128, 255, 64, 255 };

float g_fGas_Next;
float g_fGas_Pos[GAS_MAX][3];
float g_fGas_Ends[GAS_MAX];         // 0 = slot free
float g_fGas_Owed[MAXPLAYERS + 1];

void ToxicGas_Reset()
{
	g_fGas_Next = 0.0;
	for (int i = 0; i < GAS_MAX; i++)
		g_fGas_Ends[i] = 0.0;

	for (int i = 1; i <= MaxClients; i++)
		g_fGas_Owed[i] = 0.0;
}

public void Event_RoundStart_ToxicGas()
{
	ToxicGas_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Toxic Gas is on: stay out of the {olive}green clouds{lightgreen}!", THIS_MODE_INFO.tag);
}

void ToxicGas_Release()
{
	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);

	float now = GetGameTime();
	int made;
	for (int i = 0; i < GAS_MAX && made < g_iGas_Count && made < count; i++)
	{
		if (g_fGas_Ends[i] > now)
			continue;

		GetClientAbsOrigin(list[made], g_fGas_Pos[i]);
		g_fGas_Ends[i] = now + float(g_iGas_Last);
		made++;
	}

	if (made)
	{
		CPrintToChatAll("%s Toxic gas is leaking - get out of the {olive}green clouds{lightgreen}!", THIS_MODE_INFO.tag);
		EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 55);
	}
}

public void OnCheck_ToxicGas(bool zombiesNow)
{
	float now = GetGameTime(), pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bGas_Zombies))
			continue;

		GetClientAbsOrigin(i, pos);

		bool inside = false;
		for (int j = 0; j < GAS_MAX && !inside; j++)
			inside = g_fGas_Ends[j] > now && GetVectorDistance(pos, g_fGas_Pos[j]) <= g_fGas_Radius;

		if (!inside)
			continue;

		g_fGas_Owed[i] += float(g_iGas_Damage) * 0.2;
		int whole = RoundToFloor(g_fGas_Owed[i]);
		if (whole > 0)
		{
			g_fGas_Owed[i] -= float(whole);
			if (!IsFakeClient(i))
				ScreenTint(i, 60, 200, 40, 90, 0.2, 0.4);

			HurtPlayer(i, whole);
		}
	}
}

public void OnTick_ToxicGas()
{
	float now = GetGameTime();
	for (int i = 0; i < GAS_MAX; i++)
	{
		if (g_fGas_Ends[i] <= now)
			continue;

		// A few stacked rings make the cloud look like a puffy dome
		DrawRingAt(g_fGas_Pos[i], g_fGas_Radius, g_fGas_Radius * 0.9, 1.0, g_iGas_Color, 20.0);

		float up[3];
		up = g_fGas_Pos[i];
		up[2] += 40.0;
		DrawRingAt(up, g_fGas_Radius * 0.8, g_fGas_Radius * 0.7, 1.0, g_iGas_Color, 20.0);

		up[2] += 40.0;
		DrawRingAt(up, g_fGas_Radius * 0.5, g_fGas_Radius * 0.4, 1.0, g_iGas_Color, 20.0);
	}

	if (HazardDue(g_fGas_Next, g_iGas_Every))
		ToxicGas_Release();
}

public Action Cmd_ToxicGasToggle(int client, int args)
{
	if (!g_bToxicGas_Enabled)
	{
		CReplyToCommand(client, "%s Toxic Gas is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	ToxicGas_Reset();

	CPrintToChatAll("%s Toxic Gas is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Stay out of the {olive}green clouds{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* ToxicGas Settings */
public Action Cmd_ToxicGasSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_ToxicGasSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Release gas now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_ToxicGasSettings(Menu menu, MenuAction action, int param1, int param2)
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
			char info[16];
			menu.GetItem(param2, info, sizeof(info));

			if (strcmp(info, "now") == 0)
			{
				ToxicGas_Release();
				Cmd_ToxicGasSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
