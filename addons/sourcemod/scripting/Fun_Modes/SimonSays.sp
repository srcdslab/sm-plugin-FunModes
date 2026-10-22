/*
    (). FunModes V2:

    @file           SimonSays.sp
    @Usage          Functions for the SimonSays mode.
                    Once the zombies are out, every few seconds a command shows up (crouch, jump, shoot, reload,
                    press E, stand still). Do it in time when SIMON SAYS so, don't when he doesn't. Wrong costs health.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_SimonSays

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "SimonSays"

static int g_iSimonSaysIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iSimonSaysIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define SIMON_CONVAR_EVERY    0
#define SIMON_CONVAR_WINDOW   1
#define SIMON_CONVAR_DAMAGE   2
#define SIMON_CONVAR_TRICK    3
#define SIMON_CONVAR_EVERYONE 4
#define SIMON_CONVAR_TOGGLE   5

int g_iSimon_Every;
int g_iSimon_Window;
int g_iSimon_Damage;
int g_iSimon_Trick;
bool g_bSimon_Everyone;
bool g_bSimonSays_Enabled;

public void OnPluginStart_SimonSays()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_GAMES;

	/* COMMANDS */
	RegAdminCmd("sm_fm_simon", Cmd_SimonSaysToggle, ADMFLAG_CONVARS, "Turn Simon Says On/Off");
	RegAdminCmd("sm_simon_settings", Cmd_SimonSaysSettings, ADMFLAG_CONVARS, "Open Simon Says Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		SIMON_CONVAR_EVERY, "sm_simon_every",
		"20", "Seconds between two commands",
		("15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		SIMON_CONVAR_WINDOW, "sm_simon_window",
		"3", "Seconds to do the command",
		("2,3,4,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		SIMON_CONVAR_DAMAGE, "sm_simon_damage",
		"25", "Damage for getting it wrong (1000 = slay)",
		("10,25,50,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		SIMON_CONVAR_TRICK, "sm_simon_trick",
		"30", "Percent of the commands given without Simon says",
		("0,20,30,50"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		SIMON_CONVAR_EVERYONE, "sm_simon_everyone",
		"0", "The zombies play too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		SIMON_CONVAR_TOGGLE, "sm_simon_enable",
		"1", "Enable/Disable Simon Says Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= SIMON_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(SimonSays_OnConVarChange);

	THIS_MODE_INFO.enableIndex = SIMON_CONVAR_TOGGLE;

	SimonSays_OnPluginStart();
}

public void InitCvarsValues_SimonSays()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iSimon_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, SIMON_CONVAR_EVERY, Int);
	g_iSimon_Window = _FUNMODES_CVAR_GET_VALUE(modeIndex, SIMON_CONVAR_WINDOW, Int);
	g_iSimon_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, SIMON_CONVAR_DAMAGE, Int);
	g_iSimon_Trick = _FUNMODES_CVAR_GET_VALUE(modeIndex, SIMON_CONVAR_TRICK, Int);
	g_bSimon_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, SIMON_CONVAR_EVERYONE, Bool);
	g_bSimonSays_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, SIMON_CONVAR_TOGGLE, Bool);
}

void SimonSays_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case SIMON_CONVAR_EVERY:
			g_iSimon_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case SIMON_CONVAR_WINDOW:
			g_iSimon_Window = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case SIMON_CONVAR_DAMAGE:
			g_iSimon_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case SIMON_CONVAR_TRICK:
			g_iSimon_Trick = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case SIMON_CONVAR_EVERYONE:
			g_bSimon_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case SIMON_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				SimonSays_Reset();
			}

			g_bSimonSays_Enabled = val;
		}
	}
}

public void OnMapEnd_SimonSays()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	SimonSays_Reset();
}

#define SIMON_MOVE (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP)

#define SIMON_STILL 5

char g_sSimon_ActionNames[][] = { "CROUCH", "JUMP", "SHOOT", "RELOAD", "PRESS E", "STAND STILL" };
int g_iSimon_Buttons[] = { IN_DUCK, IN_JUMP, IN_ATTACK, IN_RELOAD, IN_USE, SIMON_MOVE };

bool g_bSimon_Active;
bool g_bSimon_Says;                 // "Simon says" was said this time
int g_iSimon_Action;
float g_fSimon_Ends;
float g_fSimon_Next;                // 0 = schedule the first one
bool g_bSimon_In[MAXPLAYERS + 1];   // part of this command
bool g_bSimon_Did[MAXPLAYERS + 1];  // pressed the action's key (for STAND STILL: moved)
Handle g_hSimon_Hud;

void SimonSays_OnPluginStart()
{
	g_hSimon_Hud = CreateModeHud();
}

void SimonSays_Reset()
{
	g_bSimon_Active = false;
	g_fSimon_Next = 0.0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_bSimon_In[i] = false;
		g_bSimon_Did[i] = false;
	}
}

public void Event_RoundStart_SimonSays()
{
	SimonSays_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Simon Says is on: only do it when {olive}SIMON SAYS {lightgreen}so!", THIS_MODE_INFO.tag);
}

public void OnPlayerRunCmd_SimonSays(int client, int &buttons, float vel[3], bool &changed)
{
	if (g_bSimon_Active && g_bSimon_In[client] && (buttons & g_iSimon_Buttons[g_iSimon_Action]))
		g_bSimon_Did[client] = true;
}

bool SimonSays_Plays(int client)
{
	return HazardHits(client, g_bSimon_Everyone) && !IsFakeClient(client);
}

void SimonSays_ShowHud()
{
	int left = RoundToCeil(g_fSimon_Ends - GetGameTime());
	if (left < 0)
		left = 0;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bSimon_In[i] || !IsClientInGame(i))
			continue;

		SetHudTextParams(-1.0, 0.40, 1.2, 96, 160, 255, 255, 0, 0.0, 0.0, 0.0);
		if (g_bSimon_Says)
			ShowModeHud(i, g_hSimon_Hud, "SIMON SAYS: %s! (%d)", g_sSimon_ActionNames[g_iSimon_Action], left);
		else
			ShowModeHud(i, g_hSimon_Hud, "%s! (%d)", g_sSimon_ActionNames[g_iSimon_Action], left);
	}
}

void SimonSays_Start()
{
	SimonSays_Reset();
	g_iSimon_Action = GetRandomInt(0, sizeof(g_sSimon_ActionNames) - 1);

	// "Stand still" only makes sense when Simon says it
	g_bSimon_Says = g_iSimon_Action == SIMON_STILL || GetRandomInt(1, 100) > g_iSimon_Trick;
	g_fSimon_Ends = GetGameTime() + float(g_iSimon_Window);

	int players;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!SimonSays_Plays(i))
			continue;

		g_bSimon_In[i] = true;
		players++;
	}

	g_bSimon_Active = players > 0;
	if (!g_bSimon_Active)
	{
		g_fSimon_Next = GetGameTime() + float(g_iSimon_Every);
		return;
	}

	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 110);
	SimonSays_ShowHud();
}

void SimonSays_End()
{
	int failed;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_bSimon_In[i] || !SimonSays_Plays(i))
			continue;

		bool fail;
		if (g_iSimon_Action == SIMON_STILL)
			fail = g_bSimon_Did[i];         // moved
		else
			fail = g_bSimon_Says ? !g_bSimon_Did[i] : g_bSimon_Did[i];

		if (!fail)
			continue;

		failed++;
		if (g_bSimon_Says && g_iSimon_Action != SIMON_STILL)
			CPrintToChat(i, "%s You didn't {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, g_sSimon_ActionNames[g_iSimon_Action]);
		else if (g_bSimon_Says)
			CPrintToChat(i, "%s You moved!", THIS_MODE_INFO.tag);
		else
			CPrintToChat(i, "%s Simon didn't say so!", THIS_MODE_INFO.tag);

		HurtPlayer(i, g_iSimon_Damage);
	}

	if (!failed)
		CPrintToChatAll("%s Everyone got it right!", THIS_MODE_INFO.tag);
	else if (!g_bSimon_Says)
		CPrintToChatAll("%s Simon didn't say! {olive}%d {lightgreen}player%s fell for it.", THIS_MODE_INFO.tag, failed, failed == 1 ? "" : "s");
	else
		CPrintToChatAll("%s {olive}%d {lightgreen}player%s failed to {olive}%s{lightgreen}.", THIS_MODE_INFO.tag, failed, failed == 1 ? "" : "s", g_sSimon_ActionNames[g_iSimon_Action]);

	SimonSays_Reset();
	g_fSimon_Next = GetGameTime() + float(g_iSimon_Every);
}

public void OnCheck_SimonSays(bool zombiesNow)
{
	if (!g_bZombiesSeen)
		return;

	float now = GetGameTime();
	if (!g_bSimon_Active)
	{
		if (g_fSimon_Next == 0.0)
			g_fSimon_Next = now + 10.0;

		if (now >= g_fSimon_Next)
			SimonSays_Start();

		return;
	}

	if (now >= g_fSimon_Ends)
		SimonSays_End();
}

public void OnTick_SimonSays()
{
	if (g_bSimon_Active)
		SimonSays_ShowHud();
}

public Action Cmd_SimonSaysToggle(int client, int args)
{
	if (!g_bSimonSays_Enabled)
	{
		CReplyToCommand(client, "%s Simon Says is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	SimonSays_Reset();

	CPrintToChatAll("%s Simon Says is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Only do it when {olive}SIMON SAYS {lightgreen}so!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* SimonSays Settings */
public Action Cmd_SimonSaysSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_SimonSaysSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Give a command now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bSimon_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_SimonSaysSettings(Menu menu, MenuAction action, int param1, int param2)
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
				SimonSays_Start();
				Cmd_SimonSaysSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
