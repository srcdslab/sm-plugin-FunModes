/*
    (). FunModes V2:

    @file           MagnetPull.sp
    @Usage          Functions for the MagnetPull mode.
                    Once the zombies are out, every few seconds a magnetic pulse pulls the humans towards
                    the middle of the zombies (or towards each other) for a few seconds.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_MagnetPull

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "MagnetPull"

static int g_iMagnetPullIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iMagnetPullIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define MAGNET_CONVAR_EVERY  0
#define MAGNET_CONVAR_LAST   1
#define MAGNET_CONVAR_LEVEL  2
#define MAGNET_CONVAR_TARGET 3
#define MAGNET_CONVAR_TOGGLE 4

int g_iMagnet_Every;
int g_iMagnet_Last;
int g_iMagnet_Level;
int g_iMagnet_Target;
bool g_bMagnetPull_Enabled;

public void OnPluginStart_MagnetPull()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_CHAOS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_magnet", Cmd_MagnetPullToggle, ADMFLAG_CONVARS, "Turn Magnet Pull On/Off");
	RegAdminCmd("sm_magnet_settings", Cmd_MagnetPullSettings, ADMFLAG_CONVARS, "Open Magnet Pull Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		MAGNET_CONVAR_EVERY, "sm_magnet_every",
		"45", "Seconds between two magnetic pulses",
		("20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		MAGNET_CONVAR_LAST, "sm_magnet_last",
		"3", "Seconds a magnetic pulse lasts",
		("2,3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		MAGNET_CONVAR_LEVEL, "sm_magnet_level",
		"1", ("Pull strength [0 = weak, 1 = medium, 2 = strong, 3 = very strong]"),
		("0,1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		MAGNET_CONVAR_TARGET, "sm_magnet_target",
		"0", ("Where the humans are pulled [0 = towards the zombies, 1 = towards each other]"),
		("0,1"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		MAGNET_CONVAR_TOGGLE, "sm_magnet_enable",
		"1", "Enable/Disable Magnet Pull Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= MAGNET_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(MagnetPull_OnConVarChange);

	THIS_MODE_INFO.enableIndex = MAGNET_CONVAR_TOGGLE;
}

public void InitCvarsValues_MagnetPull()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iMagnet_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, MAGNET_CONVAR_EVERY, Int);
	g_iMagnet_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, MAGNET_CONVAR_LAST, Int);
	g_iMagnet_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, MAGNET_CONVAR_LEVEL, Int);
	g_iMagnet_Target = _FUNMODES_CVAR_GET_VALUE(modeIndex, MAGNET_CONVAR_TARGET, Int);
	g_bMagnetPull_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, MAGNET_CONVAR_TOGGLE, Bool);
}

void MagnetPull_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case MAGNET_CONVAR_EVERY:
			g_iMagnet_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case MAGNET_CONVAR_LAST:
			g_iMagnet_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case MAGNET_CONVAR_LEVEL:
			g_iMagnet_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case MAGNET_CONVAR_TARGET:
			g_iMagnet_Target = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case MAGNET_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				MagnetPull_Reset();
			}

			g_bMagnetPull_Enabled = val;
		}
	}
}

public void OnMapEnd_MagnetPull()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	MagnetPull_Reset();
}

float g_fMagnet_LevelPull[] = { 20.0, 40.0, 65.0, 100.0 };     // speed added every 0.2 s
int g_iMagnet_Color[4] = { 255, 64, 192, 255 };

bool g_bMagnet_Active;
float g_fMagnet_Next;
float g_fMagnet_Ends;

void MagnetPull_Reset()
{
	g_bMagnet_Active = false;
	g_fMagnet_Next = 0.0;
}

public void Event_RoundStart_MagnetPull()
{
	MagnetPull_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Magnet is on: sometimes something pulls you towards {olive}%s{lightgreen}...", THIS_MODE_INFO.tag, g_iMagnet_Target == 0 ? "the zombies" : "each other");
}

/* The middle point of the zombies or the humans, false if nobody's there */
bool MagnetPull_Centre(bool zombies, float centre[3])
{
	float pos[3];
	int count;
	centre[0] = 0.0;
	centre[1] = 0.0;
	centre[2] = 0.0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		if (zombies ? !ZR_IsClientZombie(i) : !ZR_IsClientHuman(i))
			continue;

		GetClientAbsOrigin(i, pos);
		AddVectors(centre, pos, centre);
		count++;
	}

	if (!count)
		return false;

	ScaleVector(centre, 1.0 / float(count));
	return true;
}

void MagnetPull_Start()
{
	g_bMagnet_Active = true;
	g_fMagnet_Ends = GetGameTime() + float(g_iMagnet_Last);

	CPrintToChatAll("%s {olive}MAGNETIC PULSE! {lightgreen}You're being pulled towards {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, g_iMagnet_Target == 0 ? "the zombies" : "each other");
	PrintCenterTextAll("MAGNETIC PULL!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 75);
}

public void OnCheck_MagnetPull(bool zombiesNow)
{
	if (!g_bMagnet_Active)
		return;

	if (GetGameTime() >= g_fMagnet_Ends)
	{
		g_bMagnet_Active = false;
		return;
	}

	float centre[3];
	if (!MagnetPull_Centre(g_iMagnet_Target == 0, centre))
		return;

	DrawRingAt(centre, 120.0, 20.0, 0.3, g_iMagnet_Color, 10.0);

	int level = (g_iMagnet_Level < 0 || g_iMagnet_Level >= sizeof(g_fMagnet_LevelPull)) ? 1 : g_iMagnet_Level;
	float pull = g_fMagnet_LevelPull[level];
	float pos[3], dir[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanAlive(i))
			continue;

		GetClientAbsOrigin(i, pos);
		MakeVectorFromPoints(pos, centre, dir);
		dir[2] = 0.0;
		if (GetVectorLength(dir) < 50.0)
			continue;

		NormalizeVector(dir, dir);
		ShovePlayer(i, dir[0] * pull, dir[1] * pull, 0.0);
	}
}

public void OnTick_MagnetPull()
{
	if (!g_bMagnet_Active && HazardDue(g_fMagnet_Next, g_iMagnet_Every))
		MagnetPull_Start();
}

public Action Cmd_MagnetPullToggle(int client, int args)
{
	if (!g_bMagnetPull_Enabled)
	{
		CReplyToCommand(client, "%s Magnet Pull is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	MagnetPull_Reset();

	CPrintToChatAll("%s Magnet Pull is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Sometimes something pulls you...", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* MagnetPull Settings */
public Action Cmd_MagnetPullSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_MagnetPullSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Magnetic pulse now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bMagnet_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_MagnetPullSettings(Menu menu, MenuAction action, int param1, int param2)
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
				MagnetPull_Start();
				Cmd_MagnetPullSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
