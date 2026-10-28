/*
    (). FunModes V2:

    @file           Airstrike.sp
    @Usage          Functions for the Airstrike mode.
                    Once the zombies are out, every few seconds a siren warns of an airstrike,
                    then bombs fall one by one around where the humans were standing.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Airstrike

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Airstrike"

static int g_iAirstrikeIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iAirstrikeIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define AIRSTRIKE_CONVAR_EVERY   0
#define AIRSTRIKE_CONVAR_BOMBS   1
#define AIRSTRIKE_CONVAR_WARN    2
#define AIRSTRIKE_CONVAR_DAMAGE  3
#define AIRSTRIKE_CONVAR_RADIUS  4
#define AIRSTRIKE_CONVAR_ZOMBIES 5
#define AIRSTRIKE_CONVAR_TOGGLE  6

int g_iAirstrike_Every;
int g_iAirstrike_Bombs;
int g_iAirstrike_Warn;
int g_iAirstrike_Damage;
float g_fAirstrike_Radius;
bool g_bAirstrike_Zombies;
bool g_bAirstrike_Enabled;

public void OnPluginStart_Airstrike()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_airstrike", Cmd_AirstrikeToggle, ADMFLAG_CONVARS, "Turn Airstrike On/Off");
	RegAdminCmd("sm_airstrike_settings", Cmd_AirstrikeSettings, ADMFLAG_CONVARS, "Open Airstrike Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		AIRSTRIKE_CONVAR_EVERY, "sm_airstrike_every",
		"60", "Seconds between two airstrikes",
		("30,45,60,90,120"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		AIRSTRIKE_CONVAR_BOMBS, "sm_airstrike_bombs",
		"10", "Bombs per airstrike",
		("5,10,15,25"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		AIRSTRIKE_CONVAR_WARN, "sm_airstrike_warn",
		"5", "Seconds of warning before the bombs fall",
		("3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		AIRSTRIKE_CONVAR_DAMAGE, "sm_airstrike_damage",
		"35", "Damage at the centre of a bomb (1000 = kill)",
		("20,35,50,75,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		AIRSTRIKE_CONVAR_RADIUS, "sm_airstrike_radius",
		"180.0", "Blast radius of a bomb",
		("120.0,180.0,250.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		AIRSTRIKE_CONVAR_ZOMBIES, "sm_airstrike_zombies",
		"0", "Bombs hit the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		AIRSTRIKE_CONVAR_TOGGLE, "sm_airstrike_enable",
		"1", "Enable/Disable Airstrike Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= AIRSTRIKE_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Airstrike_OnConVarChange);

	THIS_MODE_INFO.enableIndex = AIRSTRIKE_CONVAR_TOGGLE;
}

public void InitCvarsValues_Airstrike()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iAirstrike_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, AIRSTRIKE_CONVAR_EVERY, Int);
	g_iAirstrike_Bombs = _FUNMODES_CVAR_GET_VALUE(modeIndex, AIRSTRIKE_CONVAR_BOMBS, Int);
	g_iAirstrike_Warn = _FUNMODES_CVAR_GET_VALUE(modeIndex, AIRSTRIKE_CONVAR_WARN, Int);
	g_iAirstrike_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, AIRSTRIKE_CONVAR_DAMAGE, Int);
	g_fAirstrike_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, AIRSTRIKE_CONVAR_RADIUS, Float);
	g_bAirstrike_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, AIRSTRIKE_CONVAR_ZOMBIES, Bool);
	g_bAirstrike_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, AIRSTRIKE_CONVAR_TOGGLE, Bool);
}

void Airstrike_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case AIRSTRIKE_CONVAR_EVERY:
			g_iAirstrike_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case AIRSTRIKE_CONVAR_BOMBS:
			g_iAirstrike_Bombs = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case AIRSTRIKE_CONVAR_WARN:
			g_iAirstrike_Warn = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case AIRSTRIKE_CONVAR_DAMAGE:
			g_iAirstrike_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case AIRSTRIKE_CONVAR_RADIUS:
			g_fAirstrike_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case AIRSTRIKE_CONVAR_ZOMBIES:
			g_bAirstrike_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case AIRSTRIKE_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Airstrike_Reset();
			}

			g_bAirstrike_Enabled = val;
		}
	}
}

public void OnMapEnd_Airstrike()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Airstrike_Reset();
}

#define AIRSTRIKE_SPREAD 300.0

int g_iAirstrike_Color[4] = { 255, 220, 64, 255 };
float g_fAirstrike_Next;

void Airstrike_Reset()
{
	g_fAirstrike_Next = 0.0;
}

public void Event_RoundStart_Airstrike()
{
	g_fAirstrike_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Airstrikes are on: when the siren sounds, {olive}scatter{lightgreen}!", THIS_MODE_INFO.tag);
}

public void OnTick_Airstrike()
{
	if (HazardDue(g_fAirstrike_Next, g_iAirstrike_Every))
		Airstrike_Call();
}

void Airstrike_Call()
{
	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);
	if (!count)
		return;

	CPrintToChatAll("%s {olive}AIRSTRIKE INCOMING {lightgreen}in {olive}%d {lightgreen}seconds - SCATTER!", THIS_MODE_INFO.tag, g_iAirstrike_Warn);
	PrintCenterTextAll("AIRSTRIKE INCOMING!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 50);

	// Aim now (where the humans are), the bombs fall one by one after the warning
	for (int i = 0; i < g_iAirstrike_Bombs; i++)
	{
		float pos[3];
		GetClientAbsOrigin(list[i % count], pos);
		pos[0] += GetRandomFloat(-AIRSTRIKE_SPREAD, AIRSTRIKE_SPREAD);
		pos[1] += GetRandomFloat(-AIRSTRIKE_SPREAD, AIRSTRIKE_SPREAD);

		DataPack pack;
		CreateDataTimer(float(g_iAirstrike_Warn) + 0.25 * float(i), Airstrike_BombTimer, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_iRoundNum);
		pack.WriteFloatArray(pos, 3);
	}
}

Action Airstrike_BombTimer(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();

	float pos[3];
	pack.ReadFloatArray(pos, 3);

	if (THIS_MODE_INFO.isOn && g_bRoundLive && round == g_iRoundNum)
	{
		DrawBeamDown(pos, 1200.0, 0.3, 6.0, g_iAirstrike_Color);
		ExplodeAt(pos, g_fAirstrike_Radius, g_iAirstrike_Damage, 300.0, g_bAirstrike_Zombies);
	}

	return Plugin_Stop;
}

public Action Cmd_AirstrikeToggle(int client, int args)
{
	if (!g_bAirstrike_Enabled)
	{
		CReplyToCommand(client, "%s Airstrike is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Airstrike_Reset();

	CPrintToChatAll("%s Airstrike is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When the siren sounds, {olive}scatter{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Airstrike Settings */
public Action Cmd_AirstrikeSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_AirstrikeSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Call an airstrike now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_AirstrikeSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Airstrike_Call();
				Cmd_AirstrikeSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
