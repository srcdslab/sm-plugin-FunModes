/*
    (). FunModes V2:

    @file           EventRoulette.sp
    @Usage          Functions for the EventRoulette mode, it must be included after all the other modes.
                    At each round start it turns on random modes from the pool the admins chose and turns them off
                    at round end. With a shuffle time set, it also picks again during the round. Modes an admin
                    switched on by hand are never touched. The pool is saved in configs/FunModes/Roulette.cfg.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_EventRoulette

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "EventRoulette"

static int g_iEventRouletteIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iEventRouletteIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define ROULETTE_CONVAR_PER        0
#define ROULETTE_CONVAR_NOREPEAT   1
#define ROULETTE_CONVAR_SHUFFLEMIN 2
#define ROULETTE_CONVAR_SHUFFLEMAX 3
#define ROULETTE_CONVAR_TOGGLE     4

int g_iRoulette_PerRound;
bool g_bRoulette_NoRepeat;
int g_iRoulette_ShuffleMin;
int g_iRoulette_ShuffleMax;
bool g_bEventRoulette_Enabled;

public void OnPluginStart_EventRoulette()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_MAIN;
	THIS_MODE_INFO.roulette = false;

	/* COMMANDS */
	RegAdminCmd("sm_fm_roulette", Cmd_EventRouletteToggle, ADMFLAG_CONVARS, "Turn Event Roulette On/Off");
	RegAdminCmd("sm_roulette_settings", Cmd_EventRouletteSettings, ADMFLAG_CONVARS, "Open Event Roulette Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		ROULETTE_CONVAR_PER, "sm_roulette_modes",
		"1", "Modes turned on at a time",
		("1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ROULETTE_CONVAR_NOREPEAT, "sm_roulette_norepeat",
		"1", "The modes picked last time can't be picked again",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		ROULETTE_CONVAR_SHUFFLEMIN, "sm_roulette_shuffle_min",
		"0", "Least seconds before picking again during the round (0 = once a round)",
		("0,30,45,60,90,120,180,300"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ROULETTE_CONVAR_SHUFFLEMAX, "sm_roulette_shuffle_max",
		"0", "Most seconds before picking again during the round",
		("0,30,45,60,90,120,180,300"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ROULETTE_CONVAR_TOGGLE, "sm_roulette_enable",
		"1", "Enable/Disable Event Roulette Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= ROULETTE_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(EventRoulette_OnConVarChange);

	THIS_MODE_INFO.enableIndex = ROULETTE_CONVAR_TOGGLE;

	EventRoulette_OnPluginStart();
}

public void InitCvarsValues_EventRoulette()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iRoulette_PerRound = _FUNMODES_CVAR_GET_VALUE(modeIndex, ROULETTE_CONVAR_PER, Int);
	g_bRoulette_NoRepeat = _FUNMODES_CVAR_GET_VALUE(modeIndex, ROULETTE_CONVAR_NOREPEAT, Bool);
	g_iRoulette_ShuffleMin = _FUNMODES_CVAR_GET_VALUE(modeIndex, ROULETTE_CONVAR_SHUFFLEMIN, Int);
	g_iRoulette_ShuffleMax = _FUNMODES_CVAR_GET_VALUE(modeIndex, ROULETTE_CONVAR_SHUFFLEMAX, Int);
	g_bEventRoulette_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, ROULETTE_CONVAR_TOGGLE, Bool);
}

void EventRoulette_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case ROULETTE_CONVAR_PER:
			g_iRoulette_PerRound = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ROULETTE_CONVAR_NOREPEAT:
			g_bRoulette_NoRepeat = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case ROULETTE_CONVAR_SHUFFLEMIN:
			g_iRoulette_ShuffleMin = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ROULETTE_CONVAR_SHUFFLEMAX:
			g_iRoulette_ShuffleMax = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ROULETTE_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				EventRoulette_Reset();
			}

			g_bEventRoulette_Enabled = val;
		}
	}
}

public void OnMapEnd_EventRoulette()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	EventRoulette_Reset();
}

#define ROULETTE_CONFIG "configs/FunModes/Roulette.cfg"

bool g_bRoulette_Last[MAX_MODES_NUM];      // what it picked last time
float g_fRoulette_NextShuffle;              // game time of the next pick during the round, 0 = none
char g_sRoulette_ThisRound[192];

void EventRoulette_OnPluginStart()
{
	EventRoulette_LoadPool();
}

/* Turns off what the roulette turned on */
void EventRoulette_TurnOffMine()
{
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (!g_ModesInfo[i].byRoulette)
			continue;

		g_ModesInfo[i].byRoulette = false;
		if (g_ModesInfo[i].isOn)
			FunModes_SetModeState(i, false);
	}
}

void EventRoulette_Reset()
{
	EventRoulette_TurnOffMine();
	g_fRoulette_NextShuffle = 0.0;
	g_sRoulette_ThisRound[0] = '\0';
	for (int i = 0; i < MAX_MODES_NUM; i++)
		g_bRoulette_Last[i] = false;
}

void EventRoulette_OnToggle(bool on)
{
	if (on && g_bRoundLive)
		EventRoulette_Spin();
}

bool EventRoulette_CanPick(int modeIndex)
{
	if (modeIndex == THIS_MODE_INDEX || !g_ModesInfo[modeIndex].roulette || g_ModesInfo[modeIndex].isOn)
		return false;

	if (g_bRoulette_NoRepeat && g_bRoulette_Last[modeIndex])
		return false;

	// The mode must be enabled to be turned on
	FM_ConVar cvar;
	cvar = g_ModesInfo[modeIndex].cvars[g_ModesInfo[modeIndex].enableIndex];
	return FUNMODES_CVAR_GET_VALUE(cvar, Bool);
}

void EventRoulette_PlanShuffle()
{
	if (g_iRoulette_ShuffleMin <= 0 && g_iRoulette_ShuffleMax <= 0)
	{
		g_fRoulette_NextShuffle = 0.0;
		return;
	}

	int low = g_iRoulette_ShuffleMin, high = g_iRoulette_ShuffleMax;
	if (low <= 0)
		low = high;

	if (high < low)
		high = low;

	g_fRoulette_NextShuffle = GetGameTime() + float(GetRandomInt(low, high));
}

/* Turns off the last picks and turns on new random modes */
void EventRoulette_Spin(bool roundStart = false)
{
	// What it turned on before can't come straight back
	for (int i = 0; i < g_iLastModeIndex; i++)
		g_bRoulette_Last[i] = g_ModesInfo[i].byRoulette;

	EventRoulette_TurnOffMine();

	int list[MAX_MODES_NUM], count;
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (EventRoulette_CanPick(i))
			list[count++] = i;
	}

	// Everything was picked last time: allow repeats rather than nothing
	if (!count)
	{
		for (int i = 0; i < g_iLastModeIndex; i++)
		{
			g_bRoulette_Last[i] = false;
			if (EventRoulette_CanPick(i))
				list[count++] = i;
		}
	}

	g_sRoulette_ThisRound[0] = '\0';
	for (int picked = 0; picked < g_iRoulette_PerRound && count > 0; picked++)
	{
		int pos = GetRandomInt(0, count - 1);
		int mode = list[pos];
		list[pos] = list[--count];

		g_bSkipRestartRound = true;
		bool on = FunModes_SetModeState(mode, true);
		g_bSkipRestartRound = false;
		if (!on)
			continue;

		g_ModesInfo[mode].byRoulette = true;

		// The other modes already had their round start, the picked one gets it now
		if (roundStart)
			g_ModesInfo[mode].forwards.Call_Event_RoundStart();

		Format(g_sRoulette_ThisRound, sizeof(g_sRoulette_ThisRound), "%s%s%s", g_sRoulette_ThisRound, g_sRoulette_ThisRound[0] ? ", " : "", g_ModesInfo[mode].name);
	}

	if (g_sRoulette_ThisRound[0])
		CPrintToChatAll("%s The roulette picked: {olive}%s", THIS_MODE_INFO.tag, g_sRoulette_ThisRound);
	else
		CPrintToChatAll("%s No mode left to pick in the roulette.", THIS_MODE_INFO.tag);

	EventRoulette_PlanShuffle();
}

public void Event_RoundStart_EventRoulette()
{
	g_fRoulette_NextShuffle = 0.0;
	if (THIS_MODE_INFO.isOn)
		EventRoulette_Spin(true);
}

public void Event_RoundEnd_EventRoulette()
{
	// The next round starts with a fresh spin
	EventRoulette_TurnOffMine();
	g_fRoulette_NextShuffle = 0.0;
}

public void OnTick_EventRoulette()
{
	if (g_fRoulette_NextShuffle == 0.0)
		return;

	int left = RoundToCeil(g_fRoulette_NextShuffle - GetGameTime());
	if (left > 0 && left <= 3)
		PrintCenterTextAll("Event shuffle in %d...", left);

	if (left <= 0)
		EventRoulette_Spin();
}

/* ---------------------------------------------------------------- pool */

void EventRoulette_LoadPool()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), ROULETTE_CONFIG);

	KeyValues kv = new KeyValues("Roulette");
	if (kv.ImportFromFile(path))
	{
		for (int i = 0; i < g_iLastModeIndex; i++)
		{
			if (i != THIS_MODE_INDEX)
				g_ModesInfo[i].roulette = kv.GetNum(g_ModesInfo[i].name, g_ModesInfo[i].roulette ? 1 : 0) != 0;
		}
	}

	delete kv;
}

void EventRoulette_SavePool()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), ROULETTE_CONFIG);

	KeyValues kv = new KeyValues("Roulette");
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (i != THIS_MODE_INDEX)
			kv.SetNum(g_ModesInfo[i].name, g_ModesInfo[i].roulette ? 1 : 0);
	}

	kv.ExportToFile(path);
	delete kv;
}

void EventRoulette_PoolMenu(int client, int firstItem)
{
	Menu menu = new Menu(Menu_EventRoulettePool);
	menu.SetTitle("%s - Modes the roulette can pick", THIS_MODE_INFO.name);

	char index[4], line[64];
	for (int i = 0; i < g_iLastModeIndex; i++)
	{
		if (i == THIS_MODE_INDEX)
			continue;

		IntToString(i, index, sizeof(index));
		FormatEx(line, sizeof(line), "[%s] %s", g_ModesInfo[i].roulette ? "ON" : "  -  ", g_ModesInfo[i].name);
		menu.AddItem(index, line);
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

int Menu_EventRoulettePool(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				Cmd_EventRouletteSettings(param1, 0);
		}

		case MenuAction_Select:
		{
			char index[4];
			menu.GetItem(param2, index, sizeof(index));

			int mode = StringToInt(index);
			g_ModesInfo[mode].roulette = !g_ModesInfo[mode].roulette;
			EventRoulette_SavePool();

			EventRoulette_PoolMenu(param1, GetMenuSelectionPosition());
		}
	}

	return 0;
}

public Action Cmd_EventRouletteToggle(int client, int args)
{
	if (!g_bEventRoulette_Enabled)
	{
		CReplyToCommand(client, "%s Event Roulette is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	EventRoulette_Reset();

	CPrintToChatAll("%s Event Roulette is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Random modes every round!", THIS_MODE_INFO.tag);

	EventRoulette_OnToggle(THIS_MODE_INFO.isOn);

	return Plugin_Handled;
}

/* EventRoulette Settings */
public Action Cmd_EventRouletteSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_EventRouletteSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("spin", "Spin again now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("pool", "Modes in the roulette...");
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_EventRouletteSettings(Menu menu, MenuAction action, int param1, int param2)
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

			if (strcmp(info, "spin") == 0)
			{
				EventRoulette_Spin();
				Cmd_EventRouletteSettings(param1, 0);
			}
			else if (strcmp(info, "pool") == 0)
			{
				EventRoulette_PoolMenu(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
