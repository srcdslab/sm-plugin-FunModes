/*
    (). FunModes V2:

    @file           GravityWaves.sp
    @Usage          Functions for the GravityWaves mode.
                    Once the zombies are out, every few seconds a gravity wave gives everyone low gravity
                    for a few seconds (on top of their own gravity).
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_GravityWaves

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "GravityWaves"

static int g_iGravityWavesIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iGravityWavesIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define GRAVITY_CONVAR_EVERY    0
#define GRAVITY_CONVAR_LAST     1
#define GRAVITY_CONVAR_GRAV     2
#define GRAVITY_CONVAR_EVERYONE 3
#define GRAVITY_CONVAR_TOGGLE   4

int g_iGravity_Every;
int g_iGravity_Last;
float g_fGravity_Gravity;
bool g_bGravity_Everyone;
bool g_bGravityWaves_Enabled;

public void OnPluginStart_GravityWaves()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_gravity", Cmd_GravityWavesToggle, ADMFLAG_CONVARS, "Turn Gravity Waves On/Off");
	RegAdminCmd("sm_gravity_settings", Cmd_GravityWavesSettings, ADMFLAG_CONVARS, "Open Gravity Waves Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		GRAVITY_CONVAR_EVERY, "sm_gravity_every",
		"45", "Seconds between two gravity waves",
		("20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GRAVITY_CONVAR_LAST, "sm_gravity_last",
		"8", "Seconds a gravity wave lasts",
		("3,5,8,10,15"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GRAVITY_CONVAR_GRAV, "sm_gravity_gravity",
		"0.25", "Gravity during a wave (x normal gravity)",
		("0.15,0.25,0.4,0.6"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		GRAVITY_CONVAR_EVERYONE, "sm_gravity_everyone",
		"1", "The zombies float too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		GRAVITY_CONVAR_TOGGLE, "sm_gravity_enable",
		"1", "Enable/Disable Gravity Waves Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= GRAVITY_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(GravityWaves_OnConVarChange);

	THIS_MODE_INFO.enableIndex = GRAVITY_CONVAR_TOGGLE;
}

public void InitCvarsValues_GravityWaves()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iGravity_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, GRAVITY_CONVAR_EVERY, Int);
	g_iGravity_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, GRAVITY_CONVAR_LAST, Int);
	g_fGravity_Gravity = _FUNMODES_CVAR_GET_VALUE(modeIndex, GRAVITY_CONVAR_GRAV, Float);
	g_bGravity_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, GRAVITY_CONVAR_EVERYONE, Bool);
	g_bGravityWaves_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, GRAVITY_CONVAR_TOGGLE, Bool);
}

void GravityWaves_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case GRAVITY_CONVAR_EVERY:
			g_iGravity_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GRAVITY_CONVAR_LAST:
			g_iGravity_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GRAVITY_CONVAR_GRAV:
			g_fGravity_Gravity = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case GRAVITY_CONVAR_EVERYONE:
			g_bGravity_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case GRAVITY_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				GravityWaves_Reset();
			}

			g_bGravityWaves_Enabled = val;
		}
	}
}

public void OnMapEnd_GravityWaves()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	GravityWaves_Reset();
}

bool g_bGravity_Active;
float g_fGravity_Next;
float g_fGravity_Ends;

void GravityWaves_Reset()
{
	g_bGravity_Active = false;
	g_fGravity_Next = 0.0;
	ResetModeMults(THIS_MODE_INDEX);
}

public void Event_RoundStart_GravityWaves()
{
	GravityWaves_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Gravity Waves are on: sometimes gravity just... lets go.", THIS_MODE_INFO.tag);
}

void GravityWaves_Start()
{
	g_bGravity_Active = true;
	g_fGravity_Ends = GetGameTime() + float(g_iGravity_Last);

	CPrintToChatAll("%s {olive}GRAVITY WAVE! {lightgreen}Low gravity for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, g_iGravity_Last);
	PrintCenterTextAll("LOW GRAVITY!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 210);
}

public void OnCheck_GravityWaves(bool zombiesNow)
{
	for (int i = 1; i <= MaxClients; i++)
		SetGravityMult(i, THIS_MODE_INDEX, (g_bGravity_Active && HazardHits(i, g_bGravity_Everyone)) ? g_fGravity_Gravity : 1.0);
}

public void OnTick_GravityWaves()
{
	if (g_bGravity_Active)
	{
		if (GetGameTime() >= g_fGravity_Ends)
		{
			g_bGravity_Active = false;
			PrintCenterTextAll("Gravity is back to normal");
		}

		return;
	}

	if (HazardDue(g_fGravity_Next, g_iGravity_Every))
		GravityWaves_Start();
}

public Action Cmd_GravityWavesToggle(int client, int args)
{
	if (!g_bGravityWaves_Enabled)
	{
		CReplyToCommand(client, "%s Gravity Waves is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	GravityWaves_Reset();

	CPrintToChatAll("%s Gravity Waves is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Sometimes gravity just... lets go.", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* GravityWaves Settings */
public Action Cmd_GravityWavesSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_GravityWavesSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Gravity wave now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bGravity_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_GravityWavesSettings(Menu menu, MenuAction action, int param1, int param2)
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
				GravityWaves_Start();
				Cmd_GravityWavesSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
