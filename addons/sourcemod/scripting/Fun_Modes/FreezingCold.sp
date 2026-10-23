/*
    (). FunModes V2:

    @file           FreezingCold.sp
    @Usage          Functions for the FreezingCold mode.
                    Once the zombies are out, cold snaps come every few seconds (or it's cold all the time):
                    humans who don't have enough other humans close by freeze and lose health.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_FreezingCold

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "FreezingCold"

static int g_iFreezingColdIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iFreezingColdIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define COLD_CONVAR_EVERY  0
#define COLD_CONVAR_LAST   1
#define COLD_CONVAR_DAMAGE 2
#define COLD_CONVAR_HUDDLE 3
#define COLD_CONVAR_NEED   4
#define COLD_CONVAR_TOGGLE 5

int g_iCold_Every;
int g_iCold_Last;
int g_iCold_Damage;
float g_fCold_Huddle;
int g_iCold_Need;
bool g_bFreezingCold_Enabled;

public void OnPluginStart_FreezingCold()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_cold", Cmd_FreezingColdToggle, ADMFLAG_CONVARS, "Turn Freezing Cold On/Off");
	RegAdminCmd("sm_cold_settings", Cmd_FreezingColdSettings, ADMFLAG_CONVARS, "Open Freezing Cold Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		COLD_CONVAR_EVERY, "sm_cold_every",
		"45", "Seconds between two cold snaps (0 = cold all the time)",
		("0,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		COLD_CONVAR_LAST, "sm_cold_last",
		"15", "Seconds a cold snap lasts",
		("10,15,20,30"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		COLD_CONVAR_DAMAGE, "sm_cold_damage",
		"2", "Damage per second while freezing",
		("1,2,3,5,10"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		COLD_CONVAR_HUDDLE, "sm_cold_huddle",
		"250.0", "How close the other humans must be to keep warm",
		("150.0,250.0,400.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		COLD_CONVAR_NEED, "sm_cold_need",
		"1", "Other humans needed close by to keep warm",
		("1,2,3,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		COLD_CONVAR_TOGGLE, "sm_cold_enable",
		"1", "Enable/Disable Freezing Cold Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= COLD_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(FreezingCold_OnConVarChange);

	THIS_MODE_INFO.enableIndex = COLD_CONVAR_TOGGLE;

	FreezingCold_OnPluginStart();
}

public void InitCvarsValues_FreezingCold()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iCold_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, COLD_CONVAR_EVERY, Int);
	g_iCold_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, COLD_CONVAR_LAST, Int);
	g_iCold_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, COLD_CONVAR_DAMAGE, Int);
	g_fCold_Huddle = _FUNMODES_CVAR_GET_VALUE(modeIndex, COLD_CONVAR_HUDDLE, Float);
	g_iCold_Need = _FUNMODES_CVAR_GET_VALUE(modeIndex, COLD_CONVAR_NEED, Int);
	g_bFreezingCold_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, COLD_CONVAR_TOGGLE, Bool);
}

void FreezingCold_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case COLD_CONVAR_EVERY:
			g_iCold_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case COLD_CONVAR_LAST:
			g_iCold_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case COLD_CONVAR_DAMAGE:
			g_iCold_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case COLD_CONVAR_HUDDLE:
			g_fCold_Huddle = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case COLD_CONVAR_NEED:
			g_iCold_Need = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case COLD_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				FreezingCold_Reset();
			}

			g_bFreezingCold_Enabled = val;
		}
	}
}

public void OnMapEnd_FreezingCold()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	FreezingCold_Reset();
}

bool g_bCold_Active;
float g_fCold_Next;
float g_fCold_Ends;
Handle g_hCold_Hud;

void FreezingCold_OnPluginStart()
{
	g_hCold_Hud = CreateModeHud();
}

void FreezingCold_Reset()
{
	g_bCold_Active = false;
	g_fCold_Next = 0.0;
}

public void Event_RoundStart_FreezingCold()
{
	FreezingCold_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Freezing Cold is on: when the cold snap comes, {olive}huddle {lightgreen}with other humans!", THIS_MODE_INFO.tag);
}

void FreezingCold_Start()
{
	g_bCold_Active = true;
	g_fCold_Ends = GetGameTime() + float(g_iCold_Last);

	CPrintToChatAll("%s A {olive}COLD SNAP {lightgreen}hits! Stay within {olive}%d {lightgreen}units of {olive}%d {lightgreen}other human%s to keep warm.",
		THIS_MODE_INFO.tag, RoundToNearest(g_fCold_Huddle), g_iCold_Need, g_iCold_Need == 1 ? "" : "s");
	PrintCenterTextAll("COLD SNAP! HUDDLE UP!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 80);
}

int FreezingCold_Neighbours(int client)
{
	float me[3], other[3];
	GetClientAbsOrigin(client, me);

	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsHumanAlive(i))
			continue;

		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(me, other) <= g_fCold_Huddle)
			count++;
	}

	return count;
}

public void OnTick_FreezingCold()
{
	if (g_iCold_Every == 0)
		g_bCold_Active = g_bZombiesSeen;    // all the time once the zombies are out
	else if (!g_bCold_Active)
	{
		if (HazardDue(g_fCold_Next, g_iCold_Every))
			FreezingCold_Start();

		return;
	}
	else if (GetGameTime() >= g_fCold_Ends)
	{
		g_bCold_Active = false;
		CPrintToChatAll("%s The cold snap is over.", THIS_MODE_INFO.tag);
		return;
	}

	if (!g_bCold_Active)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanAlive(i))
			continue;

		int near = FreezingCold_Neighbours(i);
		bool warm = near >= g_iCold_Need;
		if (!IsFakeClient(i))
		{
			SetHudTextParams(-1.0, HUD_Y_COLD, 1.1, warm ? 255 : 120, 200, 255, 255, 0, 0.0, 0.0, 0.0);
			if (warm)
				ShowModeHud(i, g_hCold_Hud, "Warm - %d human%s close by", near, near == 1 ? "" : "s");
			else
			{
				ShowModeHud(i, g_hCold_Hud, "FREEZING! Get close to %d other human%s (-%d HP/s)", g_iCold_Need, g_iCold_Need == 1 ? "" : "s", g_iCold_Damage);
				ScreenTint(i, 160, 220, 255, 60, 0.3, 0.6);
			}
		}

		if (!warm)
			HurtPlayer(i, g_iCold_Damage);
	}
}

public Action Cmd_FreezingColdToggle(int client, int args)
{
	if (!g_bFreezingCold_Enabled)
	{
		CReplyToCommand(client, "%s Freezing Cold is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	FreezingCold_Reset();

	CPrintToChatAll("%s Freezing Cold is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When the cold snap comes, {olive}huddle {lightgreen}with other humans!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* FreezingCold Settings */
public Action Cmd_FreezingColdSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_FreezingColdSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Cold snap now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bCold_Active && g_iCold_Every > 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_FreezingColdSettings(Menu menu, MenuAction action, int param1, int param2)
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
				FreezingCold_Start();
				Cmd_FreezingColdSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
