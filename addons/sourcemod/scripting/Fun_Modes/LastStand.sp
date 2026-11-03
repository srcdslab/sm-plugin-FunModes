/*
    (). FunModes V2:

    @file           LastStand.sp
    @Usage          Functions for the LastStand mode.
                    When only a few humans are left, they get a power boost: more health and more speed.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_LastStand

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "LastStand"
#define LASTSTAND_DISPLAY_NAME "Last Stand"

static int g_iLastStandIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iLastStandIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define LASTSTAND_CONVAR_AT     0
#define LASTSTAND_CONVAR_HEALTH 1
#define LASTSTAND_CONVAR_SPEED  2
#define LASTSTAND_CONVAR_TOGGLE 3

int g_iLastStand_At;
int g_iLastStand_Health;
float g_fLastStand_Speed;
bool g_bLastStand_Enabled;

public void OnPluginStart_LastStand()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_SURVIVAL;

	/* COMMANDS */
	RegAdminCmd("sm_fm_laststand", Cmd_LastStandToggle, ADMFLAG_CONVARS, "Turn Last Stand On/Off");
	RegAdminCmd("sm_laststand_settings", Cmd_LastStandSettings, ADMFLAG_CONVARS, "Open Last Stand Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		LASTSTAND_CONVAR_AT, "sm_laststand_at",
		"3", "Humans left that triggers the last stand",
		("1,2,3,5,10"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LASTSTAND_CONVAR_HEALTH, "sm_laststand_health",
		"100", "Health added to the last humans",
		("0,50,100,250,500"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LASTSTAND_CONVAR_SPEED, "sm_laststand_speed",
		"1.3", "Speed of the last humans (x normal speed)",
		("1.0,1.15,1.3,1.5"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		LASTSTAND_CONVAR_TOGGLE, "sm_laststand_enable",
		"1", "Enable/Disable Last Stand Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= LASTSTAND_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(LastStand_OnConVarChange);

	THIS_MODE_INFO.enableIndex = LASTSTAND_CONVAR_TOGGLE;
}

public void InitCvarsValues_LastStand()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iLastStand_At = _FUNMODES_CVAR_GET_VALUE(modeIndex, LASTSTAND_CONVAR_AT, Int);
	g_iLastStand_Health = _FUNMODES_CVAR_GET_VALUE(modeIndex, LASTSTAND_CONVAR_HEALTH, Int);
	g_fLastStand_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, LASTSTAND_CONVAR_SPEED, Float);
	g_bLastStand_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, LASTSTAND_CONVAR_TOGGLE, Bool);
}

void LastStand_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case LASTSTAND_CONVAR_AT:
			g_iLastStand_At = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LASTSTAND_CONVAR_HEALTH:
			g_iLastStand_Health = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LASTSTAND_CONVAR_SPEED:
			g_fLastStand_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case LASTSTAND_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				LastStand_Reset();
			}

			g_bLastStand_Enabled = val;
		}
	}
}

public void OnMapEnd_LastStand()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	LastStand_Reset();
}

int g_iLastStand_Color[4] = { 255, 144, 32, 255 };

bool g_bLastStand_Active;           // happened this round
bool g_bLastStand_In[MAXPLAYERS + 1];

void LastStand_Reset()
{
	g_bLastStand_Active = false;
	for (int i = 1; i <= MaxClients; i++)
		g_bLastStand_In[i] = false;

	ResetModeMults(THIS_MODE_INDEX);
}

public void Event_RoundStart_LastStand()
{
	LastStand_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, g_iLastStand_At == 1 ? "LastStand_RoundInfoOne" : "LastStand_RoundInfo", g_iLastStand_At);
}

void LastStand_Trigger()
{
	g_bLastStand_Active = true;

	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanAlive(i))
			continue;

		g_bLastStand_In[i] = true;
		count++;

		if (g_iLastStand_Health > 0)
			SetEntityHealth(i, GetClientHealth(i) + g_iLastStand_Health);
	}

	bool health = g_iLastStand_Health > 0, speed = g_fLastStand_Speed > 1.001;
	if (health && speed)
		CPrintToChatAll("%s %t %t", THIS_MODE_INFO.tag, count == 1 ? "LastStand_TriggeredOne" : "LastStand_Triggered", count, "LastStand_BonusBoth", g_iLastStand_Health, g_fLastStand_Speed);
	else if (health)
		CPrintToChatAll("%s %t %t", THIS_MODE_INFO.tag, count == 1 ? "LastStand_TriggeredOne" : "LastStand_Triggered", count, "LastStand_BonusHealth", g_iLastStand_Health);
	else if (speed)
		CPrintToChatAll("%s %t %t", THIS_MODE_INFO.tag, count == 1 ? "LastStand_TriggeredOne" : "LastStand_Triggered", count, "LastStand_BonusSpeed", g_fLastStand_Speed);
	else
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, count == 1 ? "LastStand_TriggeredOne" : "LastStand_Triggered", count);

	PrintCenterTextAll("%t", "LastStand_Center");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 200);
}

public void OnCheck_LastStand(bool zombiesNow)
{
	if (g_bLastStand_Active)
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (IsClientInGame(i))
				SetSpeedMult(i, THIS_MODE_INDEX, (g_bLastStand_In[i] && IsHumanAlive(i)) ? g_fLastStand_Speed : 1.0);
		}

		return;
	}

	if (!g_bZombiesSeen)
		return;

	int count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanAlive(i))
			count++;
	}

	if (count > 0 && count <= g_iLastStand_At)
		LastStand_Trigger();
}

public void OnTick_LastStand()
{
	if (!g_bLastStand_Active)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bLastStand_In[i] && IsHumanAlive(i))
			DrawPlayerRing(i, g_iLastStand_Color, 40.0);
	}
}

public Action Cmd_LastStandToggle(int client, int args)
{
	if (!g_bLastStand_Enabled)
	{
		CReplyToCommand(client, "%s %t", THIS_MODE_INFO.tag, "FunModes_ModeDisabled", LASTSTAND_DISPLAY_NAME);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	LastStand_Reset();

	CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "FunModes_ModeNowOn" : "FunModes_ModeNowOff", LASTSTAND_DISPLAY_NAME);
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "LastStand_Info");

	return Plugin_Handled;
}

/* LastStand Settings */
public Action Cmd_LastStandSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_LastStandSettings);

	menu.SetTitle("%T", "FunModes_SettingsTitle", client, LASTSTAND_DISPLAY_NAME);

	char buffer[128];
	FormatEx(buffer, sizeof(buffer), "%T", "LastStand_MenuNow", client);
	menu.AddItem("now", buffer, (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bLastStand_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FormatEx(buffer, sizeof(buffer), "%T\n", "FunModes_ShowCvars", client);
	menu.AddItem("cvars", buffer);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_LastStandSettings(Menu menu, MenuAction action, int param1, int param2)
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
				LastStand_Trigger();
				Cmd_LastStandSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
