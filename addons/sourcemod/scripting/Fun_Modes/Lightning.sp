/*
    (). FunModes V2:

    @file           Lightning.sp
    @Usage          Functions for the Lightning mode.
                    Once the zombies are out, every few seconds bolts land near random humans after a red
                    warning ring, hurting anyone inside.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Lightning

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Lightning"

static int g_iLightningIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iLightningIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define LIGHTNING_CONVAR_EVERY   0
#define LIGHTNING_CONVAR_COUNT   1
#define LIGHTNING_CONVAR_DAMAGE  2
#define LIGHTNING_CONVAR_RADIUS  3
#define LIGHTNING_CONVAR_ZOMBIES 4
#define LIGHTNING_CONVAR_TOGGLE  5

int g_iLightning_Every;
int g_iLightning_Count;
int g_iLightning_Damage;
float g_fLightning_Radius;
bool g_bLightning_Zombies;
bool g_bLightning_Enabled;

public void OnPluginStart_Lightning()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_lightning", Cmd_LightningToggle, ADMFLAG_CONVARS, "Turn Lightning Strikes On/Off");
	RegAdminCmd("sm_lightning_settings", Cmd_LightningSettings, ADMFLAG_CONVARS, "Open Lightning Strikes Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		LIGHTNING_CONVAR_EVERY, "sm_lightning_every",
		"15", "Seconds between two waves of lightning",
		("5,10,15,20,30"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LIGHTNING_CONVAR_COUNT, "sm_lightning_count",
		"2", "Bolts per wave",
		("1,2,3,5,8"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LIGHTNING_CONVAR_DAMAGE, "sm_lightning_damage",
		"50", "Damage of a bolt (1000 = kill)",
		("25,50,75,100,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LIGHTNING_CONVAR_RADIUS, "sm_lightning_radius",
		"150.0", "Radius of a bolt",
		("100.0,150.0,200.0,300.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		LIGHTNING_CONVAR_ZOMBIES, "sm_lightning_zombies",
		"0", "The bolts hurt the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		LIGHTNING_CONVAR_TOGGLE, "sm_lightning_enable",
		"1", "Enable/Disable Lightning Strikes Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= LIGHTNING_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Lightning_OnConVarChange);

	THIS_MODE_INFO.enableIndex = LIGHTNING_CONVAR_TOGGLE;
}

public void InitCvarsValues_Lightning()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iLightning_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, LIGHTNING_CONVAR_EVERY, Int);
	g_iLightning_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, LIGHTNING_CONVAR_COUNT, Int);
	g_iLightning_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, LIGHTNING_CONVAR_DAMAGE, Int);
	g_fLightning_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, LIGHTNING_CONVAR_RADIUS, Float);
	g_bLightning_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, LIGHTNING_CONVAR_ZOMBIES, Bool);
	g_bLightning_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, LIGHTNING_CONVAR_TOGGLE, Bool);
}

void Lightning_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case LIGHTNING_CONVAR_EVERY:
			g_iLightning_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LIGHTNING_CONVAR_COUNT:
			g_iLightning_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LIGHTNING_CONVAR_DAMAGE:
			g_iLightning_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LIGHTNING_CONVAR_RADIUS:
			g_fLightning_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case LIGHTNING_CONVAR_ZOMBIES:
			g_bLightning_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case LIGHTNING_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Lightning_Reset();
			}

			g_bLightning_Enabled = val;
		}
	}
}

public void OnMapEnd_Lightning()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Lightning_Reset();
}

#define LIGHTNING_WARN_TIME 1.5

int g_iLightning_WarnColor[4] = { 255, 40, 40, 255 };
int g_iLightning_BoltColor[4] = { 200, 220, 255, 255 };

float g_fLightning_Next;            // game time of the next wave

void Lightning_Reset()
{
	g_fLightning_Next = 0.0;
}

public void Event_RoundStart_Lightning()
{
	g_fLightning_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Lightning Strikes are on: when you see a {olive}red ring {lightgreen}under you, MOVE!", THIS_MODE_INFO.tag);
}

public void OnTick_Lightning()
{
	if (!g_bZombiesSeen)
		return;

	float now = GetGameTime();

	// A short breather after the zombies come
	if (g_fLightning_Next == 0.0)
		g_fLightning_Next = now + 3.0;

	if (now >= g_fLightning_Next)
	{
		Lightning_Wave();
		g_fLightning_Next = now + float(g_iLightning_Every);
	}
}

void Lightning_Wave()
{
	for (int i = 0; i < g_iLightning_Count; i++)
	{
		int target = PickRandomHuman();
		if (!target)
			return;

		// Near them, not always dead on
		float pos[3];
		GetClientAbsOrigin(target, pos);
		pos[0] += GetRandomFloat(-120.0, 120.0);
		pos[1] += GetRandomFloat(-120.0, 120.0);

		// A ring the size of the blast that shrinks to the centre as the bolt comes
		DrawRingAt(pos, g_fLightning_Radius, 5.0, LIGHTNING_WARN_TIME, g_iLightning_WarnColor, 6.0);
		EmitAmbientSound(Beacon_Sound, pos, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, _, _, 70);
		PrintCenterText(target, "LIGHTNING! MOVE!");

		DataPack pack;
		CreateDataTimer(LIGHTNING_WARN_TIME, Lightning_StrikeTimer, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_iRoundNum);
		pack.WriteFloatArray(pos, 3);
	}
}

Action Lightning_StrikeTimer(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();

	float pos[3];
	pack.ReadFloatArray(pos, 3);

	if (THIS_MODE_INFO.isOn && g_bRoundLive && round == g_iRoundNum)
		Lightning_Strike(pos);

	return Plugin_Stop;
}

void Lightning_Strike(const float pos[3])
{
	float top[3], ground[3];
	ground = pos;
	ground[2] += 4.0;
	top = pos;
	top[2] += 1200.0;

	// Jagged bolt (amplitude) plus a thinner second one for flicker
	TE_SetupBeamPoints(top, ground, g_LaserSprite, g_HaloSprite, 0, 30, 0.35, 18.0, 10.0, 0, 12.0, g_iLightning_BoltColor, 20);
	TE_SendToAll();
	TE_SetupBeamPoints(top, ground, g_LaserSprite, g_HaloSprite, 0, 30, 0.2, 6.0, 4.0, 0, 20.0, g_iLightning_BoltColor, 30);
	TE_SendToAll();
	TE_SetupBeamRingPoint(ground, 10.0, g_fLightning_Radius * 2.0, g_LaserSprite, g_HaloSprite, 0, 15, 0.4, 12.0, 0.0, g_iLightning_BoltColor, 10, 0);
	TE_SendToAll();

	float up[3] = { 0.0, 0.0, 1.0 };
	TE_SetupSparks(ground, up, 8, 6);
	TE_SendToAll();

	EmitAmbientSound(Explode_Sound, ground, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN);

	float other[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bLightning_Zombies))
			continue;

		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(ground, other) > g_fLightning_Radius)
			continue;

		if (GetClientHealth(i) - g_iLightning_Damage <= 0)
			CPrintToChatAll("%s {olive}%N {lightgreen}was struck by lightning!", THIS_MODE_INFO.tag, i);

		HurtPlayer(i, g_iLightning_Damage);
	}
}

public Action Cmd_LightningToggle(int client, int args)
{
	if (!g_bLightning_Enabled)
	{
		CReplyToCommand(client, "%s Lightning Strikes is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Lightning_Reset();

	CPrintToChatAll("%s Lightning Strikes is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When you see a {olive}red ring {lightgreen}under you, MOVE!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Lightning Settings */
public Action Cmd_LightningSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_LightningSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Lightning now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_LightningSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Lightning_Wave();
				Cmd_LightningSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
