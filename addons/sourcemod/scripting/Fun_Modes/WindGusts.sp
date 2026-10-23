/*
    (). FunModes V2:

    @file           WindGusts.sp
    @Usage          Functions for the WindGusts mode.
                    Once the zombies are out, every few seconds (or all the time) the wind blows and pushes
                    everyone in one direction, turning every few seconds.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_WindGusts

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "WindGusts"

static int g_iWindGustsIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iWindGustsIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define WIND_CONVAR_EVERY    0
#define WIND_CONVAR_LAST     1
#define WIND_CONVAR_LEVEL    2
#define WIND_CONVAR_TURN     3
#define WIND_CONVAR_EVERYONE 4
#define WIND_CONVAR_TOGGLE   5

int g_iWind_Every;
int g_iWind_Last;
int g_iWind_Level;
int g_iWind_Turn;
bool g_bWind_Everyone;
bool g_bWindGusts_Enabled;

public void OnPluginStart_WindGusts()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_wind", Cmd_WindGustsToggle, ADMFLAG_CONVARS, "Turn Wind Gusts On/Off");
	RegAdminCmd("sm_wind_settings", Cmd_WindGustsSettings, ADMFLAG_CONVARS, "Open Wind Gusts Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		WIND_CONVAR_EVERY, "sm_wind_every",
		"45", "Seconds between two gusts of wind (0 = windy all the time)",
		("0,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		WIND_CONVAR_LAST, "sm_wind_last",
		"10", "Seconds a gust of wind lasts",
		("5,10,15,20"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		WIND_CONVAR_LEVEL, "sm_wind_level",
		"2", ("Wind strength [0 = breeze, 1 = windy, 2 = strong wind, 3 = storm, 4 = hurricane]"),
		("0,1,2,3,4"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		WIND_CONVAR_TURN, "sm_wind_turn",
		"3", "Seconds between two changes of direction",
		("2,3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		WIND_CONVAR_EVERYONE, "sm_wind_everyone",
		"1", "The wind pushes the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		WIND_CONVAR_TOGGLE, "sm_wind_enable",
		"1", "Enable/Disable Wind Gusts Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= WIND_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(WindGusts_OnConVarChange);

	THIS_MODE_INFO.enableIndex = WIND_CONVAR_TOGGLE;

	WindGusts_OnPluginStart();
}

public void InitCvarsValues_WindGusts()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iWind_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, WIND_CONVAR_EVERY, Int);
	g_iWind_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, WIND_CONVAR_LAST, Int);
	g_iWind_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, WIND_CONVAR_LEVEL, Int);
	g_iWind_Turn = _FUNMODES_CVAR_GET_VALUE(modeIndex, WIND_CONVAR_TURN, Int);
	g_bWind_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, WIND_CONVAR_EVERYONE, Bool);
	g_bWindGusts_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, WIND_CONVAR_TOGGLE, Bool);
}

void WindGusts_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case WIND_CONVAR_EVERY:
			g_iWind_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case WIND_CONVAR_LAST:
			g_iWind_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case WIND_CONVAR_LEVEL:
			g_iWind_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case WIND_CONVAR_TURN:
			g_iWind_Turn = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case WIND_CONVAR_EVERYONE:
			g_bWind_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case WIND_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				WindGusts_Reset();
			}

			g_bWindGusts_Enabled = val;
		}
	}
}

public void OnMapEnd_WindGusts()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	WindGusts_Reset();
}

char g_sWind_LevelNames[][] = { "Breeze", "Wind", "Strong wind", "Storm", "Hurricane" };
float g_fWind_LevelPush[] = { 15.0, 30.0, 50.0, 80.0, 120.0 };   // speed added every 0.2 s

bool g_bWind_Active;
float g_fWind_Next;
float g_fWind_Ends;
float g_fWind_TurnAt;
float g_fWind_Angle;                // radians, 0 = east
Handle g_hWind_Hud;

void WindGusts_OnPluginStart()
{
	g_hWind_Hud = CreateModeHud();
}

void WindGusts_Reset()
{
	g_bWind_Active = false;
	g_fWind_Next = 0.0;
}

public void Event_RoundStart_WindGusts()
{
	WindGusts_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Wind is on: hold on tight when the storm comes!", THIS_MODE_INFO.tag);
}

int WindGusts_Level()
{
	return (g_iWind_Level < 0 || g_iWind_Level >= sizeof(g_fWind_LevelPush)) ? 2 : g_iWind_Level;
}

void WindGusts_Start()
{
	g_bWind_Active = true;
	g_fWind_Ends = GetGameTime() + float(g_iWind_Last);
	g_fWind_TurnAt = 0.0;

	if (g_iWind_Every > 0)
	{
		CPrintToChatAll("%s {olive}%s {lightgreen}is blowing for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, g_sWind_LevelNames[WindGusts_Level()], g_iWind_Last);
		PrintCenterTextAll("WIND!");
	}

	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 90);
}

/* Compass name for the way the wind pushes (Source: +x east, +y north) */
void WindGusts_Direction(char[] buffer, int maxlen)
{
	static const char names[][] = { "east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east" };

	int sector = RoundToNearest(g_fWind_Angle / (3.14159 / 4.0)) % 8;
	if (sector < 0)
		sector += 8;

	strcopy(buffer, maxlen, names[sector]);
}

public void OnCheck_WindGusts(bool zombiesNow)
{
	if (!g_bWind_Active)
		return;

	float now = GetGameTime();
	if (now >= g_fWind_TurnAt)
	{
		g_fWind_Angle = GetRandomFloat(0.0, 6.2832);
		g_fWind_TurnAt = now + float(g_iWind_Turn);
	}

	float push = g_fWind_LevelPush[WindGusts_Level()];
	float x = Cosine(g_fWind_Angle) * push;
	float y = Sine(g_fWind_Angle) * push;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (HazardHits(i, g_bWind_Everyone))
			ShovePlayer(i, x, y, 0.0);
	}
}

public void OnTick_WindGusts()
{
	if (g_iWind_Every == 0)
	{
		if (!g_bWind_Active && g_bZombiesSeen)
			WindGusts_Start();
	}
	else if (g_bWind_Active && GetGameTime() >= g_fWind_Ends)
	{
		g_bWind_Active = false;
		PrintCenterTextAll("The wind dies down");
	}
	else if (!g_bWind_Active && HazardDue(g_fWind_Next, g_iWind_Every))
		WindGusts_Start();

	if (!g_bWind_Active)
		return;

	char dir[16];
	WindGusts_Direction(dir, sizeof(dir));
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		SetHudTextParams(-1.0, HUD_Y_WIND, 1.1, 200, 230, 230, 255, 0, 0.0, 0.0, 0.0);
		ShowModeHud(i, g_hWind_Hud, "%s blowing %s", g_sWind_LevelNames[WindGusts_Level()], dir);
	}
}

public Action Cmd_WindGustsToggle(int client, int args)
{
	if (!g_bWindGusts_Enabled)
	{
		CReplyToCommand(client, "%s Wind Gusts is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	WindGusts_Reset();

	CPrintToChatAll("%s Wind Gusts is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Hold on tight when the storm comes!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* WindGusts Settings */
public Action Cmd_WindGustsSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_WindGustsSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Wind now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bWind_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_WindGustsSettings(Menu menu, MenuAction action, int param1, int param2)
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
				WindGusts_Start();
				Cmd_WindGustsSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
