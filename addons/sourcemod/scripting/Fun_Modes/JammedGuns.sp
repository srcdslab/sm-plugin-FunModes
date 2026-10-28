/*
    (). FunModes V2:

    @file           JammedGuns.sp
    @Usage          Functions for the JammedGuns mode.
                    Once the zombies are out, every few seconds the guns of some humans jam for a few seconds:
                    they can't shoot until it's over.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_JammedGuns

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "JammedGuns"

static int g_iJammedGunsIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iJammedGunsIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define JAM_CONVAR_EVERY  0
#define JAM_CONVAR_COUNT  1
#define JAM_CONVAR_LAST   2
#define JAM_CONVAR_TOGGLE 3

int g_iJam_Every;
int g_iJam_Count;
int g_iJam_Last;
bool g_bJammedGuns_Enabled;

public void OnPluginStart_JammedGuns()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEAPONS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_jam", Cmd_JammedGunsToggle, ADMFLAG_CONVARS, "Turn Jammed Guns On/Off");
	RegAdminCmd("sm_jam_settings", Cmd_JammedGunsSettings, ADMFLAG_CONVARS, "Open Jammed Guns Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		JAM_CONVAR_EVERY, "sm_jam_every",
		"30", "Seconds between two jams",
		("15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		JAM_CONVAR_COUNT, "sm_jam_count",
		"3", "Guns that jam each time (64 = everyone)",
		("1,2,3,5,64"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		JAM_CONVAR_LAST, "sm_jam_last",
		"3", "Seconds a gun stays jammed",
		("2,3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		JAM_CONVAR_TOGGLE, "sm_jam_enable",
		"1", "Enable/Disable Jammed Guns Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= JAM_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(JammedGuns_OnConVarChange);

	THIS_MODE_INFO.enableIndex = JAM_CONVAR_TOGGLE;
}

public void InitCvarsValues_JammedGuns()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iJam_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, JAM_CONVAR_EVERY, Int);
	g_iJam_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, JAM_CONVAR_COUNT, Int);
	g_iJam_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, JAM_CONVAR_LAST, Int);
	g_bJammedGuns_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, JAM_CONVAR_TOGGLE, Bool);
}

void JammedGuns_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case JAM_CONVAR_EVERY:
			g_iJam_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case JAM_CONVAR_COUNT:
			g_iJam_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case JAM_CONVAR_LAST:
			g_iJam_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case JAM_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				JammedGuns_Reset();
			}

			g_bJammedGuns_Enabled = val;
		}
	}
}

public void OnMapEnd_JammedGuns()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	JammedGuns_Reset();
}

float g_fJam_Next;
float g_fJam_Until[MAXPLAYERS + 1];

void JammedGuns_Reset()
{
	g_fJam_Next = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_fJam_Until[i] = 0.0;
}

public void Event_RoundStart_JammedGuns()
{
	JammedGuns_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Jammed Guns is on: your gun might stop working at the worst moment!", THIS_MODE_INFO.tag);
}

/* Strips the fire buttons while jammed */
public void OnPlayerRunCmd_JammedGuns(int client, int &buttons, float vel[3], bool &changed)
{
	if (g_fJam_Until[client] <= GetGameTime() || !(buttons & (IN_ATTACK | IN_ATTACK2)))
		return;

	buttons &= ~(IN_ATTACK | IN_ATTACK2);
	changed = true;
}

void JammedGuns_Jam(int client)
{
	float until = GetGameTime() + float(g_iJam_Last);
	g_fJam_Until[client] = until;

	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon != -1 && IsValidEntity(weapon) && HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack"))
	{
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", until);
		SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", until);
	}

	PrintCenterText(client, "YOUR GUN JAMMED!");
}

void JammedGuns_Wave()
{
	int list[MAXPLAYERS + 1];
	int humans = GetShuffledHumans(list);
	int count = g_iJam_Count < humans ? g_iJam_Count : humans;

	for (int i = 0; i < count; i++)
		JammedGuns_Jam(list[i]);

	if (count >= humans && humans > 0)
		CPrintToChatAll("%s Everyone's guns jammed for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, g_iJam_Last);
	else if (count > 0)
		CPrintToChatAll("%s {olive}%d {lightgreen}gun%s jammed for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, count, count == 1 ? "" : "s", g_iJam_Last);
}

public void OnTick_JammedGuns()
{
	if (HazardDue(g_fJam_Next, g_iJam_Every))
		JammedGuns_Wave();
}

public Action Cmd_JammedGunsToggle(int client, int args)
{
	if (!g_bJammedGuns_Enabled)
	{
		CReplyToCommand(client, "%s Jammed Guns is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	JammedGuns_Reset();

	CPrintToChatAll("%s Jammed Guns is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Your gun might stop working at the worst moment!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* JammedGuns Settings */
public Action Cmd_JammedGunsSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_JammedGunsSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Jam guns now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_JammedGunsSettings(Menu menu, MenuAction action, int param1, int param2)
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
				JammedGuns_Wave();
				Cmd_JammedGunsSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
