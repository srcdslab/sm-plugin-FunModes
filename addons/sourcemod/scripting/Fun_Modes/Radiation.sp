/*
    (). FunModes V2:

    @file           Radiation.sp
    @Usage          Functions for the Radiation mode.
                    Once the zombies are out, a human who camps in one spot for too long turns it radioactive:
                    the spot stays for the rest of the round and hurts whoever stands in it.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Radiation

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Radiation"

static int g_iRadiationIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iRadiationIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define RADIATION_CONVAR_AFTER   0
#define RADIATION_CONVAR_RADIUS  1
#define RADIATION_CONVAR_DAMAGE  2
#define RADIATION_CONVAR_MAX     3
#define RADIATION_CONVAR_ZOMBIES 4
#define RADIATION_CONVAR_TOGGLE  5

int g_iRadiation_After;
float g_fRadiation_Radius;
int g_iRadiation_Damage;
int g_iRadiation_Max;
bool g_bRadiation_Zombies;
bool g_bRadiation_Enabled;

public void OnPluginStart_Radiation()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_radiation", Cmd_RadiationToggle, ADMFLAG_CONVARS, "Turn Radiation On/Off");
	RegAdminCmd("sm_radiation_settings", Cmd_RadiationSettings, ADMFLAG_CONVARS, "Open Radiation Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		RADIATION_CONVAR_AFTER, "sm_radiation_after",
		"30", "Seconds of camping before a spot turns radioactive",
		("15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		RADIATION_CONVAR_RADIUS, "sm_radiation_radius",
		"200.0", "Radius of a radioactive spot",
		("150.0,200.0,300.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		RADIATION_CONVAR_DAMAGE, "sm_radiation_damage",
		"5", "Damage per second inside a radioactive spot",
		("3,5,10,20"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		RADIATION_CONVAR_MAX, "sm_radiation_max",
		"5", "Radioactive spots at most per round",
		("3,5,8,12"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		RADIATION_CONVAR_ZOMBIES, "sm_radiation_zombies",
		"0", "Radioactive spots hurt the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		RADIATION_CONVAR_TOGGLE, "sm_radiation_enable",
		"1", "Enable/Disable Radiation Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= RADIATION_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Radiation_OnConVarChange);

	THIS_MODE_INFO.enableIndex = RADIATION_CONVAR_TOGGLE;
}

public void InitCvarsValues_Radiation()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iRadiation_After = _FUNMODES_CVAR_GET_VALUE(modeIndex, RADIATION_CONVAR_AFTER, Int);
	g_fRadiation_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, RADIATION_CONVAR_RADIUS, Float);
	g_iRadiation_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, RADIATION_CONVAR_DAMAGE, Int);
	g_iRadiation_Max = _FUNMODES_CVAR_GET_VALUE(modeIndex, RADIATION_CONVAR_MAX, Int);
	g_bRadiation_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, RADIATION_CONVAR_ZOMBIES, Bool);
	g_bRadiation_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, RADIATION_CONVAR_TOGGLE, Bool);
}

void Radiation_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case RADIATION_CONVAR_AFTER:
			g_iRadiation_After = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case RADIATION_CONVAR_RADIUS:
			g_fRadiation_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RADIATION_CONVAR_DAMAGE:
			g_iRadiation_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case RADIATION_CONVAR_MAX:
			g_iRadiation_Max = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case RADIATION_CONVAR_ZOMBIES:
			g_bRadiation_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case RADIATION_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Radiation_Reset();
			}

			g_bRadiation_Enabled = val;
		}
	}
}

public void OnMapEnd_Radiation()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Radiation_Reset();
}

#define RADIATION_MAX   12
#define RADIATION_CAMP  150.0           // staying within this counts as camping

int g_iRadiation_Color[4] = { 208, 255, 48, 255 };

float g_fRadiation_Zone[RADIATION_MAX][3];
int g_iRadiation_Zones;
float g_fRadiation_Anchor[MAXPLAYERS + 1][3];
float g_fRadiation_Since[MAXPLAYERS + 1];      // 0 = not tracked yet
float g_fRadiation_Owed[MAXPLAYERS + 1];

void Radiation_Reset()
{
	g_iRadiation_Zones = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_fRadiation_Since[i] = 0.0;
		g_fRadiation_Owed[i] = 0.0;
	}
}

public void Event_RoundStart_Radiation()
{
	Radiation_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Radiation is on: camp in one spot too long and it turns {olive}radioactive{lightgreen}!", THIS_MODE_INFO.tag);
}

bool Radiation_InZone(const float pos[3])
{
	for (int i = 0; i < g_iRadiation_Zones; i++)
	{
		if (GetVectorDistance(pos, g_fRadiation_Zone[i]) <= g_fRadiation_Radius)
			return true;
	}

	return false;
}

public void OnCheck_Radiation(bool zombiesNow)
{
	if (!g_bZombiesSeen)
		return;

	float now = GetGameTime(), pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bRadiation_Zombies))
		{
			g_fRadiation_Since[i] = 0.0;
			continue;
		}

		GetClientAbsOrigin(i, pos);

		// Hurt inside the existing zones
		if (Radiation_InZone(pos))
		{
			g_fRadiation_Owed[i] += float(g_iRadiation_Damage) * 0.2;
			int whole = RoundToFloor(g_fRadiation_Owed[i]);
			if (whole > 0)
			{
				g_fRadiation_Owed[i] -= float(whole);
				PrintCenterText(i, "RADIATION! Get out!");
				HurtPlayer(i, whole);
			}
		}

		// Only the humans' camping makes new zones
		if (!ZR_IsClientHuman(i))
			continue;

		if (g_fRadiation_Since[i] == 0.0 || GetVectorDistance(pos, g_fRadiation_Anchor[i]) > RADIATION_CAMP)
		{
			g_fRadiation_Anchor[i] = pos;
			g_fRadiation_Since[i] = now;
			continue;
		}

		if (now - g_fRadiation_Since[i] < float(g_iRadiation_After) || g_iRadiation_Zones >= g_iRadiation_Max
			|| g_iRadiation_Zones >= RADIATION_MAX || Radiation_InZone(g_fRadiation_Anchor[i]))
			continue;

		g_fRadiation_Zone[g_iRadiation_Zones++] = g_fRadiation_Anchor[i];
		g_fRadiation_Since[i] = now;
		CPrintToChatAll("%s {olive}%N {lightgreen}camped too long - that spot is now {olive}RADIOACTIVE!", THIS_MODE_INFO.tag, i);
		EmitAmbientSound(Beacon_Sound, g_fRadiation_Anchor[i], SOUND_FROM_WORLD, SNDLEVEL_NORMAL, _, _, 45);
	}
}

public void OnTick_Radiation()
{
	for (int i = 0; i < g_iRadiation_Zones; i++)
		DrawRingAt(g_fRadiation_Zone[i], g_fRadiation_Radius, g_fRadiation_Radius * 0.85, 1.0, g_iRadiation_Color, 10.0);
}

public Action Cmd_RadiationToggle(int client, int args)
{
	if (!g_bRadiation_Enabled)
	{
		CReplyToCommand(client, "%s Radiation is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Radiation_Reset();

	CPrintToChatAll("%s Radiation is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Camp in one spot too long and it turns {olive}radioactive{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Radiation Settings */
public Action Cmd_RadiationSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_RadiationSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_RadiationSettings(Menu menu, MenuAction action, int param1, int param2)
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
