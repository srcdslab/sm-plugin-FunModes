/*
    (). FunModes V2:

    @file           ZombieFrenzy.sp
    @Usage          Functions for the ZombieFrenzy mode.
                    Once the zombies are out, every few seconds the humans' screens flash red and the zombies
                    get faster for a few seconds.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_ZombieFrenzy

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "ZombieFrenzy"

static int g_iZombieFrenzyIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iZombieFrenzyIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define FRENZY_CONVAR_EVERY  0
#define FRENZY_CONVAR_LAST   1
#define FRENZY_CONVAR_SPEED  2
#define FRENZY_CONVAR_TOGGLE 3

int g_iFrenzy_Every;
int g_iFrenzy_Last;
float g_fFrenzy_Speed;
bool g_bZombieFrenzy_Enabled;

public void OnPluginStart_ZombieFrenzy()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_ZOMBIES;

	/* COMMANDS */
	RegAdminCmd("sm_fm_frenzy", Cmd_ZombieFrenzyToggle, ADMFLAG_CONVARS, "Turn Zombie Frenzy On/Off");
	RegAdminCmd("sm_frenzy_settings", Cmd_ZombieFrenzySettings, ADMFLAG_CONVARS, "Open Zombie Frenzy Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		FRENZY_CONVAR_EVERY, "sm_frenzy_every",
		"45", "Seconds between two frenzies",
		("20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		FRENZY_CONVAR_LAST, "sm_frenzy_last",
		"5", "Seconds a frenzy lasts",
		("3,5,8,10"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		FRENZY_CONVAR_SPEED, "sm_frenzy_speed",
		"1.5", "Zombie speed during a frenzy (x normal speed)",
		("1.2,1.35,1.5,1.75,2.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		FRENZY_CONVAR_TOGGLE, "sm_frenzy_enable",
		"1", "Enable/Disable Zombie Frenzy Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= FRENZY_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(ZombieFrenzy_OnConVarChange);

	THIS_MODE_INFO.enableIndex = FRENZY_CONVAR_TOGGLE;
}

public void InitCvarsValues_ZombieFrenzy()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iFrenzy_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, FRENZY_CONVAR_EVERY, Int);
	g_iFrenzy_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, FRENZY_CONVAR_LAST, Int);
	g_fFrenzy_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, FRENZY_CONVAR_SPEED, Float);
	g_bZombieFrenzy_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, FRENZY_CONVAR_TOGGLE, Bool);
}

void ZombieFrenzy_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case FRENZY_CONVAR_EVERY:
			g_iFrenzy_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case FRENZY_CONVAR_LAST:
			g_iFrenzy_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case FRENZY_CONVAR_SPEED:
			g_fFrenzy_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case FRENZY_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				ZombieFrenzy_Reset();
			}

			g_bZombieFrenzy_Enabled = val;
		}
	}
}

public void OnMapEnd_ZombieFrenzy()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	ZombieFrenzy_Reset();
}

int g_iFrenzy_Color[4] = { 255, 32, 64, 255 };

bool g_bFrenzy_Active;
float g_fFrenzy_Next;
float g_fFrenzy_Ends;

void ZombieFrenzy_Reset()
{
	g_bFrenzy_Active = false;
	g_fFrenzy_Next = 0.0;
	ResetModeMults(THIS_MODE_INDEX);
}

public void Event_RoundStart_ZombieFrenzy()
{
	ZombieFrenzy_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Zombie Frenzy is on: when the screen flashes red, the zombies get {olive}FAST{lightgreen}!", THIS_MODE_INFO.tag);
}

void ZombieFrenzy_Start()
{
	g_bFrenzy_Active = true;
	g_fFrenzy_Ends = GetGameTime() + float(g_iFrenzy_Last);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && ZR_IsClientHuman(i))
			ScreenTint(i, 255, 0, 0, 90, 0.3, 1.0);
	}

	CPrintToChatAll("%s {olive}THE ZOMBIES ARE IN A FRENZY {lightgreen}for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, g_iFrenzy_Last);
	PrintCenterTextAll("ZOMBIE FRENZY!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 35);
}

public void OnCheck_ZombieFrenzy(bool zombiesNow)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			SetSpeedMult(i, THIS_MODE_INDEX, (g_bFrenzy_Active && IsPlayerAlive(i) && ZR_IsClientZombie(i)) ? g_fFrenzy_Speed : 1.0);
	}
}

public void OnTick_ZombieFrenzy()
{
	if (g_bFrenzy_Active)
	{
		if (GetGameTime() >= g_fFrenzy_Ends)
		{
			g_bFrenzy_Active = false;
			PrintCenterTextAll("The frenzy is over");
			return;
		}

		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i) && IsPlayerAlive(i) && ZR_IsClientZombie(i))
				DrawPlayerRing(i, g_iFrenzy_Color, 30.0);
		}

		return;
	}

	if (HazardDue(g_fFrenzy_Next, g_iFrenzy_Every))
		ZombieFrenzy_Start();
}

public Action Cmd_ZombieFrenzyToggle(int client, int args)
{
	if (!g_bZombieFrenzy_Enabled)
	{
		CReplyToCommand(client, "%s Zombie Frenzy is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	ZombieFrenzy_Reset();

	CPrintToChatAll("%s Zombie Frenzy is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When the screen flashes red, the zombies get {olive}FAST{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* ZombieFrenzy Settings */
public Action Cmd_ZombieFrenzySettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_ZombieFrenzySettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Frenzy now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bFrenzy_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_ZombieFrenzySettings(Menu menu, MenuAction action, int param1, int param2)
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
				ZombieFrenzy_Start();
				Cmd_ZombieFrenzySettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
