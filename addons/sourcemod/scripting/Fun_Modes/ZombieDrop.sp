/*
    (). FunModes V2:

    @file           ZombieDrop.sp
    @Usage          Functions for the ZombieDrop mode.
                    Once the zombies are out, every few seconds a red ring appears under some humans:
                    after a short warning a random zombie is teleported onto that spot.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_ZombieDrop

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "ZombieDrop"

static int g_iZombieDropIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iZombieDropIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define DROP_CONVAR_EVERY  0
#define DROP_CONVAR_COUNT  1
#define DROP_CONVAR_WARN   2
#define DROP_CONVAR_TOGGLE 3

int g_iDrop_Every;
int g_iDrop_Count;
int g_iDrop_Warn;
bool g_bZombieDrop_Enabled;

public void OnPluginStart_ZombieDrop()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_drop", Cmd_ZombieDropToggle, ADMFLAG_CONVARS, "Turn Zombie Drop On/Off");
	RegAdminCmd("sm_drop_settings", Cmd_ZombieDropSettings, ADMFLAG_CONVARS, "Open Zombie Drop Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		DROP_CONVAR_EVERY, "sm_drop_every",
		"30", "Seconds between two zombie drops",
		("15,20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		DROP_CONVAR_COUNT, "sm_drop_count",
		"1", "Zombies dropped each time",
		("1,2,3,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		DROP_CONVAR_WARN, "sm_drop_warn",
		"3", "Seconds of warning before the zombie lands",
		("2,3,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		DROP_CONVAR_TOGGLE, "sm_drop_enable",
		"1", "Enable/Disable Zombie Drop Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= DROP_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(ZombieDrop_OnConVarChange);

	THIS_MODE_INFO.enableIndex = DROP_CONVAR_TOGGLE;
}

public void InitCvarsValues_ZombieDrop()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iDrop_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, DROP_CONVAR_EVERY, Int);
	g_iDrop_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, DROP_CONVAR_COUNT, Int);
	g_iDrop_Warn = _FUNMODES_CVAR_GET_VALUE(modeIndex, DROP_CONVAR_WARN, Int);
	g_bZombieDrop_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, DROP_CONVAR_TOGGLE, Bool);
}

void ZombieDrop_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case DROP_CONVAR_EVERY:
			g_iDrop_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case DROP_CONVAR_COUNT:
			g_iDrop_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case DROP_CONVAR_WARN:
			g_iDrop_Warn = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case DROP_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				ZombieDrop_Reset();
			}

			g_bZombieDrop_Enabled = val;
		}
	}
}

public void OnMapEnd_ZombieDrop()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	ZombieDrop_Reset();
}

int g_iDrop_WarnColor[4] = { 255, 30, 30, 255 };

float g_fDrop_Next;                 // 0 = schedule when the zombies come

void ZombieDrop_Reset()
{
	g_fDrop_Next = 0.0;
}

public void Event_RoundStart_ZombieDrop()
{
	g_fDrop_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Zombie Drop is on: when a {olive}red ring {lightgreen}appears under you, RUN!", THIS_MODE_INFO.tag);
}

void ZombieDrop_Wave()
{
	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);
	int drops = g_iDrop_Count < count ? g_iDrop_Count : count;

	for (int i = 0; i < drops; i++)
	{
		float pos[3];
		GetClientAbsOrigin(list[i], pos);

		DrawRingAt(pos, 110.0, 5.0, float(g_iDrop_Warn), g_iDrop_WarnColor);
		PrintCenterText(list[i], "ZOMBIE DROP INCOMING - MOVE!");
		EmitAmbientSound(Beacon_Sound, pos, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, _, _, 60);

		DataPack pack;
		CreateDataTimer(float(g_iDrop_Warn), ZombieDrop_DropTimer, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_iRoundNum);
		pack.WriteFloatArray(pos, 3);
	}

	if (drops)
		CPrintToChatAll("%s {olive}%d {lightgreen}zombie%s dropping in {olive}%d {lightgreen}seconds - watch for the red ring%s!",
			THIS_MODE_INFO.tag, drops, drops == 1 ? "" : "s", g_iDrop_Warn, drops == 1 ? "" : "s");
}

Action ZombieDrop_DropTimer(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();

	float pos[3];
	pack.ReadFloatArray(pos, 3);

	if (!THIS_MODE_INFO.isOn || !g_bRoundLive || round != g_iRoundNum)
		return Plugin_Stop;

	int zombie = PickRandomZombie();
	if (!zombie)
		return Plugin_Stop;

	// Someone still standing right on the spot: land on top of them rather than inside them
	float other[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == zombie || !IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(pos, other) < 40.0)
		{
			pos[2] += 80.0;
			break;
		}
	}

	float zero[3];
	TeleportEntity(zombie, pos, NULL_VECTOR, zero);
	DrawPlayerRing(zombie, g_iDrop_WarnColor, 80.0);
	EmitAmbientSound(Beacon_Sound, pos, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN, _, _, 40);
	return Plugin_Stop;
}

public void OnTick_ZombieDrop()
{
	if (HazardDue(g_fDrop_Next, g_iDrop_Every))
		ZombieDrop_Wave();
}

public Action Cmd_ZombieDropToggle(int client, int args)
{
	if (!g_bZombieDrop_Enabled)
	{
		CReplyToCommand(client, "%s Zombie Drop is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	ZombieDrop_Reset();

	CPrintToChatAll("%s Zombie Drop is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When a {olive}red ring {lightgreen}appears under you, RUN!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* ZombieDrop Settings */
public Action Cmd_ZombieDropSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_ZombieDropSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Drop now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_ZombieDropSettings(Menu menu, MenuAction action, int param1, int param2)
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
				ZombieDrop_Wave();
				Cmd_ZombieDropSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
