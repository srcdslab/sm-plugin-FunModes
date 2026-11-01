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

char g_sSimon_ActionNames[][] = { "Simon_Act_Crouch", "Simon_Act_Jump", "Simon_Act_Shoot", "Simon_Act_Reload", "Simon_Act_Use", "Simon_Act_Still" };   // phrase names
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
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Simon_Intro");
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

		SetHudTextParams(-1.0, HUD_Y_SIMON, 1.2, 96, 160, 255, 255, 0, 0.0, 0.0, 0.0);
		char action[64];
		FormatEx(action, sizeof(action), "%T", g_sSimon_ActionNames[g_iSimon_Action], i);
		if (g_bSimon_Says)
			ShowModeHud(i, g_hSimon_Hud, "%t", "Simon_HudSays", action, left);
		else
			ShowModeHud(i, g_hSimon_Hud, "%s! (%d)", action, left);
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
		{
			char action[64];
			FormatEx(action, sizeof(action), "%T", g_sSimon_ActionNames[g_iSimon_Action], i);
			CPrintToChat(i, "%s %t", THIS_MODE_INFO.tag, "Simon_YouDidnt", action);
		}
		else if (g_bSimon_Says)
			CPrintToChat(i, "%s %t", THIS_MODE_INFO.tag, "Simon_YouMoved");
		else
			CPrintToChat(i, "%s %t", THIS_MODE_INFO.tag, "Simon_DidntSay");

		HurtPlayer(i, g_iSimon_Damage);
	}

	if (!failed)
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Simon_AllRight");
	else if (!g_bSimon_Says)
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, failed == 1 ? "Simon_FellFor" : "Simon_FellForPlural", failed);
	else
	{
		char action[64];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;

			FormatEx(action, sizeof(action), "%T", g_sSimon_ActionNames[g_iSimon_Action], i);
			CPrintToChat(i, "%s %t", THIS_MODE_INFO.tag, failed == 1 ? "Simon_Failed" : "Simon_FailedPlural", failed, action);
		}
	}

	SimonSays_Reset();
	g_fSimon_Next = GetGameTime() + float(g_iSimon_Every);
}

public void OnCheck_SimonSays(bool zombiesNow)
{
	float now = GetGameTime();
	if (!g_bSimon_Active)
	{
		// A command given from the menu can run before the zombies are out, the automatic ones wait for them
		if (!g_bZombiesSeen)
			return;

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
		CReplyToCommand(client, "%s %t", THIS_MODE_INFO.tag, "FM_Disabled", "Simon Says");
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	SimonSays_Reset();

	CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "FM_NowOn" : "FM_NowOff", "Simon Says");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Simon_Hint");

	return Plugin_Handled;
}

/* SimonSays Settings */
public Action Cmd_SimonSaysSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_SimonSaysSettings);

	menu.SetTitle("%T", "FM_MenuSettings", client, THIS_MODE_INFO.name);

	FM_AddItemT(menu, client, "now", "Simon_MenuNow", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bSimon_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FM_AddItemT(menu, client, "cvars", "FM_MenuShowCvars", ITEMDRAW_DEFAULT, "\n");

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
