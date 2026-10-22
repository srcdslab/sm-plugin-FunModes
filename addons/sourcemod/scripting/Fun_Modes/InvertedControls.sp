/*
    (). FunModes V2:

    @file           InvertedControls.sp
    @Usage          Functions for the IC mode.
                    Mode 0: everyone's controls are inverted (sv_accelerate) while it's on.
                    Mode 1: once the zombies are out, every few seconds the chosen players' movement is
                    flipped for a few seconds: forward walks back, left strafes right.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_IC

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "IC"

static int g_iICIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iICIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define IC_CONVAR_TOGGLE 0
#define IC_CONVAR_MODE   1
#define IC_CONVAR_EVERY  2
#define IC_CONVAR_LAST   3
#define IC_CONVAR_WHO    4

#define IC_MODE_ALWAYS 0
#define IC_MODE_BURSTS 1

#define IC_WHO_ALL      0
#define IC_WHO_HALF     1
#define IC_WHO_ONE      2
#define IC_WHO_EVERYONE 3

#define IC_MOVE (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT)

bool g_bIC_Enabled;
int g_iIC_Mode;
int g_iIC_Every;
int g_iIC_Last;
int g_iIC_Who;

bool g_bIC_Accelerated;             // we changed sv_accelerate
float g_fIC_OldAccelerate;

bool g_bIC_Active;
float g_fIC_Next;                   // 0 = schedule when the zombies come
float g_fIC_Ends;
bool g_bIC_Flipped[MAXPLAYERS + 1];
Handle g_hIC_Hud;

/* CALLED ON PLUGIN START */
public void OnPluginStart_IC()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_CHAOS;

	/* Admin Commands */
	static const char commands[][] =
	{
		"sm_invertedcon",
		"sm_invertcon",
		"sm_invertedcontrols",
		"sm_fm_ic"
	};

	for (int i = 0; i < sizeof(commands); i++)
	{
		RegAdminCmd(commands[i], Cmd_ICToggle, ADMFLAG_CONVARS, "Enable/Disable Inverted controls");
	}

	RegAdminCmd("sm_ic_settings", Cmd_ICSettings, ADMFLAG_CONVARS, "Open IC Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		IC_CONVAR_TOGGLE, "sm_ic_enable",
		"1", "Enable/Disable Inverted Controls mode.",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		IC_CONVAR_MODE, "sm_ic_mode",
		"0", "Inverted Controls mode [0 = everyone all the time (sv_accelerate) 1 = random players every few seconds]",
		("0,1"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		IC_CONVAR_EVERY, "sm_ic_every",
		"45", "Mode 1: seconds between two inversions",
		("20,30,45,60,90,120"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		IC_CONVAR_LAST, "sm_ic_last",
		"5", "Mode 1: seconds an inversion lasts",
		("3,5,8,10,15"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		IC_CONVAR_WHO, "sm_ic_who",
		"0", "Mode 1: who gets inverted [0 = all humans 1 = half the humans 2 = one random human 3 = everyone]",
		("0,1,2,3"), CONVAR_INT
	);

	for (int i = 0; i <= IC_CONVAR_WHO; i++)
		THIS_MODE_INFO.cvars[i].HookChange(IC_OnConVarChange);

	THIS_MODE_INFO.enableIndex = IC_CONVAR_TOGGLE;

	g_hIC_Hud = CreateModeHud();
}

public void InitCvarsValues_IC()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_bIC_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, IC_CONVAR_TOGGLE, Bool);
	g_iIC_Mode = _FUNMODES_CVAR_GET_VALUE(modeIndex, IC_CONVAR_MODE, Int);
	g_iIC_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, IC_CONVAR_EVERY, Int);
	g_iIC_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, IC_CONVAR_LAST, Int);
	g_iIC_Who = _FUNMODES_CVAR_GET_VALUE(modeIndex, IC_CONVAR_WHO, Int);
}

void IC_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case IC_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				IC_Reset();
			}

			g_bIC_Enabled = val;
		}

		case IC_CONVAR_MODE:
		{
			g_iIC_Mode = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

			// Switch the running mode over
			IC_Reset();
			if (THIS_MODE_INFO.isOn && g_iIC_Mode == IC_MODE_ALWAYS)
				IC_Accelerate(true);
		}

		case IC_CONVAR_EVERY:
			g_iIC_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case IC_CONVAR_LAST:
			g_iIC_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case IC_CONVAR_WHO:
			g_iIC_Who = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);
	}
}

public void OnMapEnd_IC()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	IC_Reset();
}

public void OnPluginEnd_IC()
{
	IC_Accelerate(false);
}

/* Inverts everyone's controls with a negative sv_accelerate, or puts the old value back */
void IC_Accelerate(bool on)
{
	ConVar cvar = FindConVar("sv_accelerate");
	if (cvar == null)
		return;

	if (on)
	{
		if (!g_bIC_Accelerated)
			g_fIC_OldAccelerate = cvar.FloatValue;

		g_bIC_Accelerated = true;
		cvar.IntValue = -5;
	}
	else if (g_bIC_Accelerated)
	{
		cvar.FloatValue = g_fIC_OldAccelerate;
		g_bIC_Accelerated = false;
	}
}

void IC_Clear()
{
	g_bIC_Active = false;
	g_fIC_Next = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_bIC_Flipped[i] = false;
}

void IC_Reset()
{
	IC_Clear();
	IC_Accelerate(false);
}

public void Event_RoundStart_IC()
{
	IC_Clear();
	if (THIS_MODE_INFO.isOn && g_iIC_Mode == IC_MODE_BURSTS)
		CPrintToChatAll("%s Inverted Controls is on: sometimes forward means backwards...", THIS_MODE_INFO.tag);
}

/* Flips the movement for the players under the effect */
public void OnPlayerRunCmd_IC(int client, int &buttons, float vel[3], bool &changed)
{
	if (!g_bIC_Active || !g_bIC_Flipped[client] || !IsPlayerAlive(client))
		return;

	vel[0] = -vel[0];
	vel[1] = -vel[1];

	int flipped = buttons & ~IC_MOVE;
	if (buttons & IN_FORWARD)
		flipped |= IN_BACK;

	if (buttons & IN_BACK)
		flipped |= IN_FORWARD;

	if (buttons & IN_MOVELEFT)
		flipped |= IN_MOVERIGHT;

	if (buttons & IN_MOVERIGHT)
		flipped |= IN_MOVELEFT;

	buttons = flipped;
	changed = true;
}

void IC_Start()
{
	IC_Clear();

	int list[MAXPLAYERS + 1], count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (HazardHits(i, g_iIC_Who == IC_WHO_EVERYONE) && !IsFakeClient(i))
			list[count++] = i;
	}

	for (int i = count - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}

	int flipped = count;
	if (g_iIC_Who == IC_WHO_HALF)
		flipped = (count + 1) / 2;
	else if (g_iIC_Who == IC_WHO_ONE)
		flipped = count > 0 ? 1 : 0;

	for (int i = 0; i < flipped; i++)
		g_bIC_Flipped[list[i]] = true;

	g_bIC_Active = flipped > 0;
	g_fIC_Ends = GetGameTime() + float(g_iIC_Last);
	if (!g_bIC_Active)
	{
		g_fIC_Next = GetGameTime() + float(g_iIC_Every);
		return;
	}

	if (g_iIC_Who == IC_WHO_ONE)
		CPrintToChatAll("%s {olive}%N{lightgreen}'s controls are inverted for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, list[0], g_iIC_Last);
	else
		CPrintToChatAll("%s Controls inverted for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, g_iIC_Last);

	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 50);
	IC_ShowHud();
}

void IC_End()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bIC_Flipped[i] && IsClientInGame(i))
			PrintCenterText(i, "Controls back to normal");
	}

	IC_Clear();
	g_fIC_Next = GetGameTime() + float(g_iIC_Every);
}

void IC_ShowHud()
{
	int left = RoundToCeil(g_fIC_Ends - GetGameTime());
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bIC_Flipped[i] || !IsClientInGame(i))
			continue;

		SetHudTextParams(-1.0, 0.44, 1.2, 192, 96, 255, 255, 0, 0.0, 0.0, 0.0);
		ShowModeHud(i, g_hIC_Hud, "CONTROLS INVERTED! (%d)", left > 0 ? left : 0);
	}
}

public void OnTick_IC()
{
	if (g_iIC_Mode != IC_MODE_BURSTS || !g_bZombiesSeen)
		return;

	float now = GetGameTime();
	if (!g_bIC_Active)
	{
		if (g_fIC_Next == 0.0)
			g_fIC_Next = now + float(g_iIC_Every);

		if (now >= g_fIC_Next)
			IC_Start();

		return;
	}

	if (now >= g_fIC_Ends)
		IC_End();
	else
		IC_ShowHud();
}

public Action Cmd_ICToggle(int client, int args)
{
	if (!g_bIC_Enabled)
	{
		CReplyToCommand(client, "%s Inverted Controls is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;

	IC_Reset();
	if (THIS_MODE_INFO.isOn && g_iIC_Mode == IC_MODE_ALWAYS)
		IC_Accelerate(true);

	CPrintToChatAll("%s Inverted Controls is now {olive}%s!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	return Plugin_Handled;
}

/* IC Settings */
public Action Cmd_ICSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_ICSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Invert the controls now", (THIS_MODE_INFO.isOn && g_bRoundLive && g_iIC_Mode == IC_MODE_BURSTS && !g_bIC_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_ICSettings(Menu menu, MenuAction action, int param1, int param2)
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
				IC_Start();
				Cmd_ICSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
