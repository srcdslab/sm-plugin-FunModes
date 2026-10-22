/*
    (). FunModes V2:

    @file           Buddy.sp
    @Usage          Functions for the Buddy mode.
                    When the zombies come, the humans are paired up. If your buddy falls, you die (or bleed).
                    Optionally you also bleed while you're too far from your buddy.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Buddy

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Buddy"

static int g_iBuddyIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iBuddyIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define BUDDY_CONVAR_DIE    0
#define BUDDY_CONVAR_BLEED  1
#define BUDDY_CONVAR_DIST   2
#define BUDDY_CONVAR_TOGGLE 3

bool g_bBuddy_Die;
int g_iBuddy_Bleed;
float g_fBuddy_MaxDist;
bool g_bBuddy_Enabled;

public void OnPluginStart_Buddy()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_SURVIVAL;

	/* COMMANDS */
	RegAdminCmd("sm_fm_buddy", Cmd_BuddyToggle, ADMFLAG_CONVARS, "Turn Buddy System On/Off");
	RegAdminCmd("sm_buddy_settings", Cmd_BuddySettings, ADMFLAG_CONVARS, "Open Buddy System Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		BUDDY_CONVAR_DIE, "sm_buddy_die",
		"1", "When your buddy falls you die (else you bleed)",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		BUDDY_CONVAR_BLEED, "sm_buddy_bleed",
		"3", "Health lost per second when bleeding or too far from your buddy",
		("1,2,3,5,10"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BUDDY_CONVAR_DIST, "sm_buddy_max_distance",
		"0.0", "Bleed when further than this from your buddy (0 = no distance rule)",
		("0.0,500.0,800.0,1200.0,2000.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		BUDDY_CONVAR_TOGGLE, "sm_buddy_enable",
		"1", "Enable/Disable Buddy System Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= BUDDY_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Buddy_OnConVarChange);

	THIS_MODE_INFO.enableIndex = BUDDY_CONVAR_TOGGLE;

	Buddy_OnPluginStart();
}

public void InitCvarsValues_Buddy()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_bBuddy_Die = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUDDY_CONVAR_DIE, Bool);
	g_iBuddy_Bleed = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUDDY_CONVAR_BLEED, Int);
	g_fBuddy_MaxDist = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUDDY_CONVAR_DIST, Float);
	g_bBuddy_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUDDY_CONVAR_TOGGLE, Bool);
}

void Buddy_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case BUDDY_CONVAR_DIE:
			g_bBuddy_Die = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case BUDDY_CONVAR_BLEED:
			g_iBuddy_Bleed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BUDDY_CONVAR_DIST:
			g_fBuddy_MaxDist = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case BUDDY_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Buddy_Reset();
			}

			g_bBuddy_Enabled = val;
		}
	}
}

public void OnMapEnd_Buddy()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Buddy_Reset();
}

bool g_bBuddy_Paired;               // pairs made this round
int g_iBuddy[MAXPLAYERS + 1];       // buddy's userid, 0 = none
bool g_bBuddy_Bleeding[MAXPLAYERS + 1];
bool g_bBuddy_Solo[MAXPLAYERS + 1]; // odd one out this round
Handle g_hBuddy_Hud;

void Buddy_OnPluginStart()
{
	g_hBuddy_Hud = CreateModeHud();
}

void Buddy_Reset()
{
	g_bBuddy_Paired = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iBuddy[i] = 0;
		g_bBuddy_Bleeding[i] = false;
		g_bBuddy_Solo[i] = false;
	}
}

public void Event_RoundStart_Buddy()
{
	Buddy_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Buddy System is on: you get a buddy when the zombies come - {olive}keep them alive{lightgreen}!", THIS_MODE_INFO.tag);
}

void Buddy_Pair()
{
	Buddy_Reset();
	g_bBuddy_Paired = true;

	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);
	for (int i = 0; i + 1 < count; i += 2)
	{
		int a = list[i], b = list[i + 1];
		g_iBuddy[a] = GetClientUserId(b);
		g_iBuddy[b] = GetClientUserId(a);

		CPrintToChat(a, "%s Your buddy is {olive}%N{lightgreen}. If they fall, %s", THIS_MODE_INFO.tag, b, g_bBuddy_Die ? "so do you!" : "you start bleeding!");
		CPrintToChat(b, "%s Your buddy is {olive}%N{lightgreen}. If they fall, %s", THIS_MODE_INFO.tag, a, g_bBuddy_Die ? "so do you!" : "you start bleeding!");
	}

	if (count % 2 == 1)
	{
		g_bBuddy_Solo[list[count - 1]] = true;
		CPrintToChat(list[count - 1], "%s Odd one out - you're on your own this round.", THIS_MODE_INFO.tag);
	}

	CPrintToChatAll("%s Buddies are paired! %s", THIS_MODE_INFO.tag, g_bBuddy_Die ? "If your buddy falls, you fall with them." : "If your buddy falls, you bleed.");
}

public void OnCheck_Buddy(bool zombiesNow)
{
	if (!g_bBuddy_Paired)
	{
		if (zombiesNow)
			Buddy_Pair();

		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_iBuddy[i] || !IsHumanAlive(i))
			continue;

		int buddy = GetClientOfUserId(g_iBuddy[i]);
		if (IsHumanAlive(buddy))
			continue;

		g_iBuddy[i] = 0;
		if (!buddy)
		{
			// Left the server: not the buddy's fault
			g_bBuddy_Solo[i] = true;
			CPrintToChat(i, "%s Your buddy left the server - you're on your own now.", THIS_MODE_INFO.tag);
		}
		else if (g_bBuddy_Die)
		{
			CPrintToChatAll("%s {olive}%N {lightgreen}fell, and takes their buddy {olive}%N {lightgreen}with them!", THIS_MODE_INFO.tag, buddy, i);
			ForcePlayerSuicide(i);
		}
		else
		{
			g_bBuddy_Bleeding[i] = true;
			CPrintToChat(i, "%s Your buddy {olive}%N {lightgreen}fell - you're bleeding {olive}%d HP/s{lightgreen}!", THIS_MODE_INFO.tag, buddy, g_iBuddy_Bleed);
		}
	}
}

public void OnTick_Buddy()
{
	if (!g_bBuddy_Paired)
		return;

	float me[3], them[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanAlive(i))
			continue;

		if (g_bBuddy_Bleeding[i])
		{
			HurtPlayer(i, g_iBuddy_Bleed);
			if (!IsFakeClient(i))
			{
				SetHudTextParams(-1.0, 0.22, 1.1, 255, 60, 60, 255, 0, 0.0, 0.0, 0.0);
				ShowModeHud(i, g_hBuddy_Hud, "YOUR BUDDY FELL - BLEEDING %d HP/s", g_iBuddy_Bleed);
			}

			continue;
		}

		int buddy = g_iBuddy[i] ? GetClientOfUserId(g_iBuddy[i]) : 0;
		if (IsHumanAlive(buddy))
		{
			GetClientAbsOrigin(i, me);
			GetClientAbsOrigin(buddy, them);

			int dist = RoundToNearest(GetVectorDistance(me, them));
			bool far = g_fBuddy_MaxDist > 0.0 && dist > g_fBuddy_MaxDist;
			if (far)
				HurtPlayer(i, g_iBuddy_Bleed);

			if (IsFakeClient(i))
				continue;

			if (far)
			{
				SetHudTextParams(-1.0, 0.22, 1.1, 255, 60, 60, 255, 0, 0.0, 0.0, 0.0);
				ShowModeHud(i, g_hBuddy_Hud, "TOO FAR FROM YOUR BUDDY %N (%d) - GET BACK! -%d HP/s", buddy, dist, g_iBuddy_Bleed);
			}
			else
			{
				SetHudTextParams(-1.0, 0.22, 1.1, 64, 192, 255, 255, 0, 0.0, 0.0, 0.0);
				ShowModeHud(i, g_hBuddy_Hud, "Buddy: %N (%d units away)", buddy, dist);
			}
		}
		else if (g_bBuddy_Solo[i] && !IsFakeClient(i))
		{
			SetHudTextParams(-1.0, 0.22, 1.1, 64, 192, 255, 255, 0, 0.0, 0.0, 0.0);
			ShowModeHud(i, g_hBuddy_Hud, "No buddy - you're on your own");
		}
	}
}

public Action Cmd_BuddyToggle(int client, int args)
{
	if (!g_bBuddy_Enabled)
	{
		CReplyToCommand(client, "%s Buddy System is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Buddy_Reset();

	CPrintToChatAll("%s Buddy System is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s You get a buddy when the zombies come - {olive}keep them alive{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Buddy Settings */
public Action Cmd_BuddySettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_BuddySettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("pair", "Make new pairs now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_BuddySettings(Menu menu, MenuAction action, int param1, int param2)
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

			if (strcmp(info, "pair") == 0)
			{
				Buddy_Pair();
				Cmd_BuddySettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
