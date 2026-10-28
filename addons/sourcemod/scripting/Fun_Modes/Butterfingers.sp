/*
    (). FunModes V2:

    @file           Butterfingers.sp
    @Usage          Functions for the Butterfingers mode.
                    Once the zombies are out, every few seconds some humans drop their gun on the floor
                    (never a map item).
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Butterfingers

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Butterfingers"

static int g_iButterfingersIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iButterfingersIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define BUTTER_CONVAR_EVERY  0
#define BUTTER_CONVAR_COUNT  1
#define BUTTER_CONVAR_WHICH  2
#define BUTTER_CONVAR_TOGGLE 3

int g_iButter_Every;
int g_iButter_Count;
int g_iButter_Which;
bool g_bButterfingers_Enabled;

public void OnPluginStart_Butterfingers()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEAPONS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_butter", Cmd_ButterfingersToggle, ADMFLAG_CONVARS, "Turn Butterfingers On/Off");
	RegAdminCmd("sm_butter_settings", Cmd_ButterfingersSettings, ADMFLAG_CONVARS, "Open Butterfingers Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		BUTTER_CONVAR_EVERY, "sm_butter_every",
		"30", "Seconds between two drops",
		("15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BUTTER_CONVAR_COUNT, "sm_butter_count",
		"2", "Humans who drop their gun each time (64 = everyone)",
		("1,2,3,5,64"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BUTTER_CONVAR_WHICH, "sm_butter_which",
		"0", ("Gun dropped [0 = the gun in their hands, 1 = their main gun, 2 = their pistol]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BUTTER_CONVAR_TOGGLE, "sm_butter_enable",
		"1", "Enable/Disable Butterfingers Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= BUTTER_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Butterfingers_OnConVarChange);

	THIS_MODE_INFO.enableIndex = BUTTER_CONVAR_TOGGLE;
}

public void InitCvarsValues_Butterfingers()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iButter_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUTTER_CONVAR_EVERY, Int);
	g_iButter_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUTTER_CONVAR_COUNT, Int);
	g_iButter_Which = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUTTER_CONVAR_WHICH, Int);
	g_bButterfingers_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, BUTTER_CONVAR_TOGGLE, Bool);
}

void Butterfingers_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case BUTTER_CONVAR_EVERY:
			g_iButter_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BUTTER_CONVAR_COUNT:
			g_iButter_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BUTTER_CONVAR_WHICH:
			g_iButter_Which = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BUTTER_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Butterfingers_Reset();
			}

			g_bButterfingers_Enabled = val;
		}
	}
}

public void OnMapEnd_Butterfingers()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Butterfingers_Reset();
}

float g_fButter_Next;

void Butterfingers_Reset()
{
	g_fButter_Next = 0.0;
}

public void Event_RoundStart_Butterfingers()
{
	g_fButter_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Butterfingers is on: hold on to your gun!", THIS_MODE_INFO.tag);
}

/* True if the player dropped something */
bool Butterfingers_Drop(int client)
{
	int weapon;
	if (g_iButter_Which == 1)
		weapon = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
	else if (g_iButter_Which == 2)
		weapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	else
		weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");

	if (weapon == -1 || !IsValidEntity(weapon))
		return false;

	// Knife or grenade in hand
	if (weapon != GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) && weapon != GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY))
		return false;

	if (IsMapItem(weapon))
		return false;

	CS_DropWeapon(client, weapon, true);
	PrintCenterText(client, "BUTTERFINGERS! You dropped your gun!");
	return true;
}

void Butterfingers_Wave()
{
	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);

	int dropped;
	for (int i = 0; i < count && dropped < g_iButter_Count; i++)
	{
		if (Butterfingers_Drop(list[i]))
			dropped++;
	}

	if (dropped)
		CPrintToChatAll("%s {olive}%d {lightgreen}human%s dropped their gun!", THIS_MODE_INFO.tag, dropped, dropped == 1 ? "" : "s");
}

public void OnTick_Butterfingers()
{
	if (HazardDue(g_fButter_Next, g_iButter_Every))
		Butterfingers_Wave();
}

public Action Cmd_ButterfingersToggle(int client, int args)
{
	if (!g_bButterfingers_Enabled)
	{
		CReplyToCommand(client, "%s Butterfingers is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Butterfingers_Reset();

	CPrintToChatAll("%s Butterfingers is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Hold on to your gun!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Butterfingers Settings */
public Action Cmd_ButterfingersSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_ButterfingersSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Drop guns now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_ButterfingersSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Butterfingers_Wave();
				Cmd_ButterfingersSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
