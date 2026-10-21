/*
    (). FunModes V2:

    @file           Blackout.sp
    @Usage          Functions for the Blackout mode.
                    Once the zombies are out, every few seconds the screens of a few random players go black
                    (blackout) or white (flashbang) for a moment, then fade back.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Blackout

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Blackout"

static int g_iBlackoutIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iBlackoutIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define BLACKOUT_CONVAR_EVERY    0
#define BLACKOUT_CONVAR_COUNT    1
#define BLACKOUT_CONVAR_LAST     2
#define BLACKOUT_CONVAR_TYPE     3
#define BLACKOUT_CONVAR_EVERYONE 4
#define BLACKOUT_CONVAR_TOGGLE   5

int g_iBlackout_Every;
int g_iBlackout_Count;
int g_iBlackout_Last;
int g_iBlackout_Type;
bool g_bBlackout_Everyone;
bool g_bBlackout_Enabled;

public void OnPluginStart_Blackout()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_CHAOS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_blackout", Cmd_BlackoutToggle, ADMFLAG_CONVARS, "Turn Blackout On/Off");
	RegAdminCmd("sm_blackout_settings", Cmd_BlackoutSettings, ADMFLAG_CONVARS, "Open Blackout Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		BLACKOUT_CONVAR_EVERY, "sm_blackout_every",
		"20", "Seconds between two blackouts",
		("10,15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BLACKOUT_CONVAR_COUNT, "sm_blackout_count",
		"2", "Players hit each time (64 = everyone)",
		("1,2,3,5,10,64"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BLACKOUT_CONVAR_LAST, "sm_blackout_last",
		"2", "Seconds the screen stays fully dark or bright",
		("1,2,3,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BLACKOUT_CONVAR_TYPE, "sm_blackout_type",
		"2", ("Blackout type [0 = black (blackout), 1 = white (flashbang), 2 = random]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BLACKOUT_CONVAR_EVERYONE, "sm_blackout_everyone",
		"0", "The zombies can be hit too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		BLACKOUT_CONVAR_TOGGLE, "sm_blackout_enable",
		"1", "Enable/Disable Blackout Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= BLACKOUT_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Blackout_OnConVarChange);

	THIS_MODE_INFO.enableIndex = BLACKOUT_CONVAR_TOGGLE;
}

public void InitCvarsValues_Blackout()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iBlackout_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, BLACKOUT_CONVAR_EVERY, Int);
	g_iBlackout_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, BLACKOUT_CONVAR_COUNT, Int);
	g_iBlackout_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, BLACKOUT_CONVAR_LAST, Int);
	g_iBlackout_Type = _FUNMODES_CVAR_GET_VALUE(modeIndex, BLACKOUT_CONVAR_TYPE, Int);
	g_bBlackout_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, BLACKOUT_CONVAR_EVERYONE, Bool);
	g_bBlackout_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, BLACKOUT_CONVAR_TOGGLE, Bool);
}

void Blackout_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case BLACKOUT_CONVAR_EVERY:
			g_iBlackout_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BLACKOUT_CONVAR_COUNT:
			g_iBlackout_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BLACKOUT_CONVAR_LAST:
			g_iBlackout_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BLACKOUT_CONVAR_TYPE:
			g_iBlackout_Type = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BLACKOUT_CONVAR_EVERYONE:
			g_bBlackout_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case BLACKOUT_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Blackout_Reset();
			}

			g_bBlackout_Enabled = val;
		}
	}
}

public void OnMapEnd_Blackout()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Blackout_Reset();
}

#define BLACKOUT_FLASH_SOUND "weapons/flashbang/flashbang_explode2.wav"

#define BLACKOUT_BLACK  0
#define BLACKOUT_WHITE  1
#define BLACKOUT_RANDOM 2

float g_fBlackout_Next;             // 0 = schedule when the zombies come

public void OnMapStart_Blackout()
{
	PrecacheSound(BLACKOUT_FLASH_SOUND, true);
}

void Blackout_Reset()
{
	g_fBlackout_Next = 0.0;
}

public void Event_RoundStart_Blackout()
{
	g_fBlackout_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Blackouts are on: your screen might go dark at the worst moment...", THIS_MODE_INFO.tag);
}

void Blackout_Hit()
{
	int list[MAXPLAYERS + 1], count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (HazardHits(i, g_bBlackout_Everyone) && !IsFakeClient(i))
			list[count++] = i;
	}

	for (int i = count - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}

	int hits = g_iBlackout_Count < count ? g_iBlackout_Count : count;
	for (int i = 0; i < hits; i++)
	{
		int client = list[i];
		bool white = g_iBlackout_Type == BLACKOUT_WHITE || (g_iBlackout_Type == BLACKOUT_RANDOM && GetRandomInt(0, 1) == 1);
		int c = white ? 255 : 0;

		// Fully dark or bright, held, then fading back over a second
		ScreenTint(client, c, c, c, 255, float(g_iBlackout_Last), 1.0);
		if (white)
		{
			EmitSoundToClient(client, BLACKOUT_FLASH_SOUND);
			PrintCenterText(client, "FLASHBANGED!");
		}
		else
			PrintCenterText(client, "BLACKOUT!");
	}

	if (hits > 0 && hits < count)
		CPrintToChatAll("%s {olive}%d {lightgreen}player%s lost their sight!", THIS_MODE_INFO.tag, hits, hits == 1 ? "" : "s");
	else if (hits > 0)
		CPrintToChatAll("%s Everyone lost their sight!", THIS_MODE_INFO.tag);
}

public void OnTick_Blackout()
{
	if (HazardDue(g_fBlackout_Next, g_iBlackout_Every))
		Blackout_Hit();
}

public Action Cmd_BlackoutToggle(int client, int args)
{
	if (!g_bBlackout_Enabled)
	{
		CReplyToCommand(client, "%s Blackout is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Blackout_Reset();

	CPrintToChatAll("%s Blackout is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Your screen might go dark at the worst moment...", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Blackout Settings */
public Action Cmd_BlackoutSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_BlackoutSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Blackout now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_BlackoutSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Blackout_Hit();
				Cmd_BlackoutSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
