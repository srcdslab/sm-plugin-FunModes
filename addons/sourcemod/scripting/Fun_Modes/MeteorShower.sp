/*
    (). FunModes V2:

    @file           MeteorShower.sp
    @Usage          Functions for the MeteorShower mode.
                    Once the zombies are out, every few seconds meteors are aimed near random humans:
                    an orange ring and a trail from the sky warn where they land, then each one explodes.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_MeteorShower

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "MeteorShower"

static int g_iMeteorShowerIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iMeteorShowerIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define METEOR_CONVAR_EVERY   0
#define METEOR_CONVAR_COUNT   1
#define METEOR_CONVAR_DAMAGE  2
#define METEOR_CONVAR_RADIUS  3
#define METEOR_CONVAR_KNOCK   4
#define METEOR_CONVAR_ZOMBIES 5
#define METEOR_CONVAR_TOGGLE  6

int g_iMeteor_Every;
int g_iMeteor_Count;
int g_iMeteor_Damage;
float g_fMeteor_Radius;
bool g_bMeteor_Knock;
bool g_bMeteor_Zombies;
bool g_bMeteorShower_Enabled;

public void OnPluginStart_MeteorShower()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_meteor", Cmd_MeteorShowerToggle, ADMFLAG_CONVARS, "Turn Meteor Shower On/Off");
	RegAdminCmd("sm_meteor_settings", Cmd_MeteorShowerSettings, ADMFLAG_CONVARS, "Open Meteor Shower Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		METEOR_CONVAR_EVERY, "sm_meteor_every",
		"30", "Seconds between two meteor showers",
		("15,20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		METEOR_CONVAR_COUNT, "sm_meteor_count",
		"3", "Meteors per shower",
		("1,2,3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		METEOR_CONVAR_DAMAGE, "sm_meteor_damage",
		"50", "Damage at the centre of a meteor (1000 = kill)",
		("25,50,75,100,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		METEOR_CONVAR_RADIUS, "sm_meteor_radius",
		"200.0", "Blast radius of a meteor",
		("150.0,200.0,250.0,350.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		METEOR_CONVAR_KNOCK, "sm_meteor_knockback",
		"1", "Meteors push the players away",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		METEOR_CONVAR_ZOMBIES, "sm_meteor_zombies",
		"0", "Meteors hit the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		METEOR_CONVAR_TOGGLE, "sm_meteor_enable",
		"1", "Enable/Disable Meteor Shower Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= METEOR_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(MeteorShower_OnConVarChange);

	THIS_MODE_INFO.enableIndex = METEOR_CONVAR_TOGGLE;
}

public void InitCvarsValues_MeteorShower()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iMeteor_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, METEOR_CONVAR_EVERY, Int);
	g_iMeteor_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, METEOR_CONVAR_COUNT, Int);
	g_iMeteor_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, METEOR_CONVAR_DAMAGE, Int);
	g_fMeteor_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, METEOR_CONVAR_RADIUS, Float);
	g_bMeteor_Knock = _FUNMODES_CVAR_GET_VALUE(modeIndex, METEOR_CONVAR_KNOCK, Bool);
	g_bMeteor_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, METEOR_CONVAR_ZOMBIES, Bool);
	g_bMeteorShower_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, METEOR_CONVAR_TOGGLE, Bool);
}

void MeteorShower_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case METEOR_CONVAR_EVERY:
			g_iMeteor_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case METEOR_CONVAR_COUNT:
			g_iMeteor_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case METEOR_CONVAR_DAMAGE:
			g_iMeteor_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case METEOR_CONVAR_RADIUS:
			g_fMeteor_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case METEOR_CONVAR_KNOCK:
			g_bMeteor_Knock = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case METEOR_CONVAR_ZOMBIES:
			g_bMeteor_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case METEOR_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				MeteorShower_Reset();
			}

			g_bMeteorShower_Enabled = val;
		}
	}
}

public void OnMapEnd_MeteorShower()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	MeteorShower_Reset();
}

#define METEOR_WARN 2.0

int g_iMeteor_Color[4] = { 255, 128, 32, 255 };
float g_fMeteor_Next;

void MeteorShower_Reset()
{
	g_fMeteor_Next = 0.0;
}

public void Event_RoundStart_MeteorShower()
{
	g_fMeteor_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Meteor Shower is on: look up and watch for {olive}orange rings{lightgreen}!", THIS_MODE_INFO.tag);
}

public void OnTick_MeteorShower()
{
	if (HazardDue(g_fMeteor_Next, g_iMeteor_Every))
		MeteorShower_Wave();
}

void MeteorShower_Wave()
{
	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);
	if (!count)
		return;

	for (int i = 0; i < g_iMeteor_Count; i++)
	{
		float pos[3];
		GetClientAbsOrigin(list[i % count], pos);
		pos[0] += GetRandomFloat(-150.0, 150.0);
		pos[1] += GetRandomFloat(-150.0, 150.0);

		DrawRingAt(pos, g_fMeteor_Radius, 20.0, METEOR_WARN, g_iMeteor_Color);
		DrawBeamDown(pos, 1500.0, METEOR_WARN, 20.0, g_iMeteor_Color);

		DataPack pack;
		CreateDataTimer(METEOR_WARN, MeteorShower_HitTimer, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_iRoundNum);
		pack.WriteFloatArray(pos, 3);
	}

	CPrintToChatAll("%s {olive}METEORS INCOMING!", THIS_MODE_INFO.tag);
}

Action MeteorShower_HitTimer(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();

	float pos[3];
	pack.ReadFloatArray(pos, 3);

	if (THIS_MODE_INFO.isOn && g_bRoundLive && round == g_iRoundNum)
		ExplodeAt(pos, g_fMeteor_Radius, g_iMeteor_Damage, g_bMeteor_Knock ? 400.0 : 0.0, g_bMeteor_Zombies);

	return Plugin_Stop;
}

public Action Cmd_MeteorShowerToggle(int client, int args)
{
	if (!g_bMeteorShower_Enabled)
	{
		CReplyToCommand(client, "%s Meteor Shower is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	MeteorShower_Reset();

	CPrintToChatAll("%s Meteor Shower is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Look up and watch for {olive}orange rings{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* MeteorShower Settings */
public Action Cmd_MeteorShowerSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_MeteorShowerSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Meteors now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_MeteorShowerSettings(Menu menu, MenuAction action, int param1, int param2)
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
				MeteorShower_Wave();
				Cmd_MeteorShowerSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
