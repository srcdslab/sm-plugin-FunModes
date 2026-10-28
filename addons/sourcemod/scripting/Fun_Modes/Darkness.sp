/*
    (). FunModes V2:

    @file           Darkness.sp
    @Usage          Functions for the Darkness mode.
                    Once the zombies are out, every few seconds the lights go out: the screens of the humans
                    (and the zombies, if set) go dark for a few seconds, then slowly come back.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Darkness

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Darkness"

static int g_iDarknessIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iDarknessIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define DARKNESS_CONVAR_EVERY   0
#define DARKNESS_CONVAR_LAST    1
#define DARKNESS_CONVAR_LEVEL   2
#define DARKNESS_CONVAR_ZOMBIES 3
#define DARKNESS_CONVAR_TOGGLE  4

int g_iDarkness_Every;
int g_iDarkness_Last;
int g_iDarkness_Level;
bool g_bDarkness_Zombies;
bool g_bDarkness_Enabled;

public void OnPluginStart_Darkness()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_darkness", Cmd_DarknessToggle, ADMFLAG_CONVARS, "Turn Sudden Darkness On/Off");
	RegAdminCmd("sm_darkness_settings", Cmd_DarknessSettings, ADMFLAG_CONVARS, "Open Sudden Darkness Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		DARKNESS_CONVAR_EVERY, "sm_darkness_every",
		"45", "Seconds between two blackouts of the lights",
		("20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		DARKNESS_CONVAR_LAST, "sm_darkness_last",
		"8", "Seconds the lights stay out",
		("3,5,8,10,15"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		DARKNESS_CONVAR_LEVEL, "sm_darkness_level",
		"2", ("How dark it gets [0 = dim, 1 = dark, 2 = very dark, 3 = pitch black]"),
		("0,1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		DARKNESS_CONVAR_ZOMBIES, "sm_darkness_zombies",
		"0", "The zombies are in the dark too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		DARKNESS_CONVAR_TOGGLE, "sm_darkness_enable",
		"1", "Enable/Disable Sudden Darkness Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= DARKNESS_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Darkness_OnConVarChange);

	THIS_MODE_INFO.enableIndex = DARKNESS_CONVAR_TOGGLE;
}

public void InitCvarsValues_Darkness()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iDarkness_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, DARKNESS_CONVAR_EVERY, Int);
	g_iDarkness_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, DARKNESS_CONVAR_LAST, Int);
	g_iDarkness_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, DARKNESS_CONVAR_LEVEL, Int);
	g_bDarkness_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, DARKNESS_CONVAR_ZOMBIES, Bool);
	g_bDarkness_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, DARKNESS_CONVAR_TOGGLE, Bool);
}

void Darkness_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case DARKNESS_CONVAR_EVERY:
			g_iDarkness_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case DARKNESS_CONVAR_LAST:
			g_iDarkness_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case DARKNESS_CONVAR_LEVEL:
			g_iDarkness_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case DARKNESS_CONVAR_ZOMBIES:
			g_bDarkness_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case DARKNESS_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Darkness_Reset();
			}

			g_bDarkness_Enabled = val;
		}
	}
}

public void OnMapEnd_Darkness()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Darkness_Reset();
}

int g_iDarkness_LevelAlpha[] = { 150, 200, 230, 252 };

float g_fDarkness_Next;

void Darkness_Reset()
{
	g_fDarkness_Next = 0.0;
}

public void Event_RoundStart_Darkness()
{
	g_fDarkness_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Sudden Darkness is on: the lights will go out when you least expect it...", THIS_MODE_INFO.tag);
}

void Darkness_Lights()
{
	int level = g_iDarkness_Level;
	if (level < 0 || level >= sizeof(g_iDarkness_LevelAlpha))
		level = 2;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		if (IsPlayerAlive(i) && ZR_IsClientZombie(i) && !g_bDarkness_Zombies)
			continue;

		ScreenTint(i, 0, 0, 0, g_iDarkness_LevelAlpha[level], float(g_iDarkness_Last), 2.0);
	}

	CPrintToChatAll("%s The lights went out!", THIS_MODE_INFO.tag);
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 35);
}

public void OnTick_Darkness()
{
	if (HazardDue(g_fDarkness_Next, g_iDarkness_Every))
		Darkness_Lights();
}

public Action Cmd_DarknessToggle(int client, int args)
{
	if (!g_bDarkness_Enabled)
	{
		CReplyToCommand(client, "%s Sudden Darkness is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Darkness_Reset();

	CPrintToChatAll("%s Sudden Darkness is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s The lights will go out when you least expect it...", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Darkness Settings */
public Action Cmd_DarknessSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_DarknessSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Lights out now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_DarknessSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Darkness_Lights();
				Cmd_DarknessSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
