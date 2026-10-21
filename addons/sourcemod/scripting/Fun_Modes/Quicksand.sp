/*
    (). FunModes V2:

    @file           Quicksand.sp
    @Usage          Functions for the Quicksand mode.
                    Once the zombies are out, every few seconds brown patches of quicksand appear where some
                    humans stand: whoever is inside one is slowed down until it dries out.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Quicksand

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Quicksand"

static int g_iQuicksandIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iQuicksandIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define QUICKSAND_CONVAR_EVERY   0
#define QUICKSAND_CONVAR_COUNT   1
#define QUICKSAND_CONVAR_LAST    2
#define QUICKSAND_CONVAR_RADIUS  3
#define QUICKSAND_CONVAR_SLOW    4
#define QUICKSAND_CONVAR_ZOMBIES 5
#define QUICKSAND_CONVAR_TOGGLE  6

int g_iQuicksand_Every;
int g_iQuicksand_Count;
int g_iQuicksand_Last;
float g_fQuicksand_Radius;
float g_fQuicksand_Slow;
bool g_bQuicksand_Zombies;
bool g_bQuicksand_Enabled;

public void OnPluginStart_Quicksand()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_quicksand", Cmd_QuicksandToggle, ADMFLAG_CONVARS, "Turn Quicksand On/Off");
	RegAdminCmd("sm_quicksand_settings", Cmd_QuicksandSettings, ADMFLAG_CONVARS, "Open Quicksand Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		QUICKSAND_CONVAR_EVERY, "sm_quicksand_every",
		"45", "Seconds between two quicksand patches",
		("20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUICKSAND_CONVAR_COUNT, "sm_quicksand_count",
		"2", "Quicksand patches each time",
		("1,2,3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUICKSAND_CONVAR_LAST, "sm_quicksand_last",
		"15", "Seconds a quicksand patch lasts",
		("10,15,20,30"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUICKSAND_CONVAR_RADIUS, "sm_quicksand_radius",
		"180.0", "Radius of a quicksand patch",
		("120.0,180.0,250.0,350.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		QUICKSAND_CONVAR_SLOW, "sm_quicksand_slow",
		"0.3", "Speed inside the quicksand (x normal speed)",
		("0.15,0.3,0.5,0.7"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		QUICKSAND_CONVAR_ZOMBIES, "sm_quicksand_zombies",
		"1", "The zombies sink too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		QUICKSAND_CONVAR_TOGGLE, "sm_quicksand_enable",
		"1", "Enable/Disable Quicksand Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= QUICKSAND_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Quicksand_OnConVarChange);

	THIS_MODE_INFO.enableIndex = QUICKSAND_CONVAR_TOGGLE;
}

public void InitCvarsValues_Quicksand()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iQuicksand_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUICKSAND_CONVAR_EVERY, Int);
	g_iQuicksand_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUICKSAND_CONVAR_COUNT, Int);
	g_iQuicksand_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUICKSAND_CONVAR_LAST, Int);
	g_fQuicksand_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUICKSAND_CONVAR_RADIUS, Float);
	g_fQuicksand_Slow = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUICKSAND_CONVAR_SLOW, Float);
	g_bQuicksand_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUICKSAND_CONVAR_ZOMBIES, Bool);
	g_bQuicksand_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUICKSAND_CONVAR_TOGGLE, Bool);
}

void Quicksand_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case QUICKSAND_CONVAR_EVERY:
			g_iQuicksand_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUICKSAND_CONVAR_COUNT:
			g_iQuicksand_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUICKSAND_CONVAR_LAST:
			g_iQuicksand_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUICKSAND_CONVAR_RADIUS:
			g_fQuicksand_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case QUICKSAND_CONVAR_SLOW:
			g_fQuicksand_Slow = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case QUICKSAND_CONVAR_ZOMBIES:
			g_bQuicksand_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case QUICKSAND_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Quicksand_Reset();
			}

			g_bQuicksand_Enabled = val;
		}
	}
}

public void OnMapEnd_Quicksand()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Quicksand_Reset();
}

#define QUICKSAND_MAX 8

int g_iQuicksand_Color[4] = { 192, 144, 80, 255 };

float g_fQuicksand_Next;
float g_fQuicksand_Pos[QUICKSAND_MAX][3];
float g_fQuicksand_Ends[QUICKSAND_MAX];

void Quicksand_Reset()
{
	g_fQuicksand_Next = 0.0;
	for (int i = 0; i < QUICKSAND_MAX; i++)
		g_fQuicksand_Ends[i] = 0.0;

	ResetModeMults(THIS_MODE_INDEX);
}

public void Event_RoundStart_Quicksand()
{
	Quicksand_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Quicksand is on: avoid the {olive}brown patches{lightgreen}!", THIS_MODE_INFO.tag);
}

bool Quicksand_IsInside(int client)
{
	if (!HazardHits(client, g_bQuicksand_Zombies))
		return false;

	float now = GetGameTime(), pos[3];
	GetClientAbsOrigin(client, pos);
	for (int i = 0; i < QUICKSAND_MAX; i++)
	{
		if (g_fQuicksand_Ends[i] > now && GetVectorDistance(pos, g_fQuicksand_Pos[i]) <= g_fQuicksand_Radius)
			return true;
	}

	return false;
}

void Quicksand_Spawn()
{
	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);

	float now = GetGameTime();
	int made;
	for (int i = 0; i < QUICKSAND_MAX && made < g_iQuicksand_Count && made < count; i++)
	{
		if (g_fQuicksand_Ends[i] > now)
			continue;

		GetClientAbsOrigin(list[made], g_fQuicksand_Pos[i]);
		g_fQuicksand_Ends[i] = now + float(g_iQuicksand_Last);
		made++;
	}

	if (made)
		CPrintToChatAll("%s {olive}Quicksand! {lightgreen}Get out of the brown patches!", THIS_MODE_INFO.tag);
}

public void OnCheck_Quicksand(bool zombiesNow)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			SetSpeedMult(i, THIS_MODE_INDEX, Quicksand_IsInside(i) ? g_fQuicksand_Slow : 1.0);
	}
}

public void OnTick_Quicksand()
{
	float now = GetGameTime();
	for (int i = 0; i < QUICKSAND_MAX; i++)
	{
		// Swirling inwards
		if (g_fQuicksand_Ends[i] > now)
			DrawRingAt(g_fQuicksand_Pos[i], g_fQuicksand_Radius, g_fQuicksand_Radius * 0.3, 1.0, g_iQuicksand_Color, 16.0);
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && Quicksand_IsInside(i))
			PrintCenterText(i, "QUICKSAND! Get out!");
	}

	if (HazardDue(g_fQuicksand_Next, g_iQuicksand_Every))
		Quicksand_Spawn();
}

public Action Cmd_QuicksandToggle(int client, int args)
{
	if (!g_bQuicksand_Enabled)
	{
		CReplyToCommand(client, "%s Quicksand is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Quicksand_Reset();

	CPrintToChatAll("%s Quicksand is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Avoid the {olive}brown patches{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Quicksand Settings */
public Action Cmd_QuicksandSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_QuicksandSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Quicksand now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_QuicksandSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Quicksand_Spawn();
				Cmd_QuicksandSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
