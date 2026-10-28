/*
    (). FunModes V2:

    @file           Shockwave.sp
    @Usage          Functions for the Shockwave mode.
                    Once the zombies are out, every few seconds a blue ring spreads out from near a human:
                    whoever is on the ground when it goes by gets hurt and thrown up, so jump over it.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Shockwave

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Shockwave"

static int g_iShockwaveIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iShockwaveIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define SHOCKWAVE_CONVAR_EVERY   0
#define SHOCKWAVE_CONVAR_DAMAGE  1
#define SHOCKWAVE_CONVAR_SIZE    2
#define SHOCKWAVE_CONVAR_SPEED   3
#define SHOCKWAVE_CONVAR_ZOMBIES 4
#define SHOCKWAVE_CONVAR_TOGGLE  5

int g_iShockwave_Every;
int g_iShockwave_Damage;
float g_fShockwave_Size;
float g_fShockwave_Speed;
bool g_bShockwave_Zombies;
bool g_bShockwave_Enabled;

public void OnPluginStart_Shockwave()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_shockwave", Cmd_ShockwaveToggle, ADMFLAG_CONVARS, "Turn Shockwave On/Off");
	RegAdminCmd("sm_shockwave_settings", Cmd_ShockwaveSettings, ADMFLAG_CONVARS, "Open Shockwave Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		SHOCKWAVE_CONVAR_EVERY, "sm_shockwave_every",
		"30", "Seconds between two shockwaves",
		("15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		SHOCKWAVE_CONVAR_DAMAGE, "sm_shockwave_damage",
		"25", "Damage of the shockwave (1000 = kill)",
		("15,25,50,75,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		SHOCKWAVE_CONVAR_SIZE, "sm_shockwave_size",
		"1000.0", "How far the shockwave travels",
		("600.0,1000.0,1500.0,2500.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		SHOCKWAVE_CONVAR_SPEED, "sm_shockwave_speed",
		"450.0", "Speed of the shockwave (units per second)",
		("300.0,450.0,600.0,900.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		SHOCKWAVE_CONVAR_ZOMBIES, "sm_shockwave_zombies",
		"0", "The shockwave hits the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		SHOCKWAVE_CONVAR_TOGGLE, "sm_shockwave_enable",
		"1", "Enable/Disable Shockwave Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= SHOCKWAVE_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Shockwave_OnConVarChange);

	THIS_MODE_INFO.enableIndex = SHOCKWAVE_CONVAR_TOGGLE;
}

public void InitCvarsValues_Shockwave()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iShockwave_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, SHOCKWAVE_CONVAR_EVERY, Int);
	g_iShockwave_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, SHOCKWAVE_CONVAR_DAMAGE, Int);
	g_fShockwave_Size = _FUNMODES_CVAR_GET_VALUE(modeIndex, SHOCKWAVE_CONVAR_SIZE, Float);
	g_fShockwave_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, SHOCKWAVE_CONVAR_SPEED, Float);
	g_bShockwave_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, SHOCKWAVE_CONVAR_ZOMBIES, Bool);
	g_bShockwave_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, SHOCKWAVE_CONVAR_TOGGLE, Bool);
}

void Shockwave_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case SHOCKWAVE_CONVAR_EVERY:
			g_iShockwave_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case SHOCKWAVE_CONVAR_DAMAGE:
			g_iShockwave_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case SHOCKWAVE_CONVAR_SIZE:
			g_fShockwave_Size = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case SHOCKWAVE_CONVAR_SPEED:
			g_fShockwave_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case SHOCKWAVE_CONVAR_ZOMBIES:
			g_bShockwave_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case SHOCKWAVE_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Shockwave_Reset();
			}

			g_bShockwave_Enabled = val;
		}
	}
}

public void OnMapEnd_Shockwave()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Shockwave_Reset();
}

#define SHOCKWAVE_WARN 1.5

int g_iShockwave_Color[4] = { 96, 192, 255, 255 };

float g_fShockwave_Next;
bool g_bShockwave_Active;
float g_fShockwave_Center[3];
float g_fShockwave_Start;           // when the wave leaves the centre
float g_fShockwave_LastRadius;
bool g_bShockwave_Hit[MAXPLAYERS + 1];

void Shockwave_Reset()
{
	g_bShockwave_Active = false;
	g_fShockwave_Next = 0.0;
}

public void Event_RoundStart_Shockwave()
{
	Shockwave_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Shockwaves are on: when the blue ring comes, {olive}JUMP {lightgreen}over it!", THIS_MODE_INFO.tag);
}

public void OnTick_Shockwave()
{
	if (!g_bShockwave_Active && HazardDue(g_fShockwave_Next, g_iShockwave_Every))
		Shockwave_Fire();
}

void Shockwave_Fire()
{
	int list[MAXPLAYERS + 1];
	if (!GetShuffledHumans(list))
		return;

	GetClientAbsOrigin(list[0], g_fShockwave_Center);
	g_fShockwave_Center[0] += GetRandomFloat(-200.0, 200.0);
	g_fShockwave_Center[1] += GetRandomFloat(-200.0, 200.0);
	g_fShockwave_Start = GetGameTime() + SHOCKWAVE_WARN;
	g_fShockwave_LastRadius = 0.0;
	g_bShockwave_Active = true;

	for (int i = 1; i <= MaxClients; i++)
		g_bShockwave_Hit[i] = false;

	// Warning: a shrinking ring at the centre
	DrawRingAt(g_fShockwave_Center, 80.0, 10.0, SHOCKWAVE_WARN, g_iShockwave_Color, 12.0);
	DrawBeamDown(g_fShockwave_Center, 600.0, SHOCKWAVE_WARN, 10.0, g_iShockwave_Color);
	CPrintToChatAll("%s {olive}SHOCKWAVE! {lightgreen}Jump when it reaches you!", THIS_MODE_INFO.tag);
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 70);
}

public void OnCheck_Shockwave(bool zombiesNow)
{
	if (!g_bShockwave_Active)
		return;

	float now = GetGameTime();
	if (now < g_fShockwave_Start)
		return;

	if (g_fShockwave_LastRadius == 0.0)
	{
		// The wave itself: one ring that grows over the whole travel time
		// A speed of 0 (set by hand) would never reach anyone: treat it as the slowest wave
		if (g_fShockwave_Speed < 50.0)
			g_fShockwave_Speed = 50.0;

		DrawRingAt(g_fShockwave_Center, 10.0, g_fShockwave_Size, g_fShockwave_Size / g_fShockwave_Speed, g_iShockwave_Color, 20.0);
		EmitAmbientSound(Explode_Sound, g_fShockwave_Center, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN, _, 0.6, 60);
	}

	float radius = (now - g_fShockwave_Start) * g_fShockwave_Speed;
	float pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bShockwave_Hit[i] || !HazardHits(i, g_bShockwave_Zombies))
			continue;

		GetClientAbsOrigin(i, pos);
		float dist = GetVectorDistance(g_fShockwave_Center, pos);

		// The front hasn't reached them, or already went by
		if (dist < g_fShockwave_LastRadius - 40.0 || dist > radius + 40.0)
			continue;

		g_bShockwave_Hit[i] = true;

		// Jumped it!
		if (!(GetEntityFlags(i) & FL_ONGROUND))
			continue;

		PrintCenterText(i, "You didn't jump the shockwave!");
		ShovePlayer(i, 0.0, 0.0, 280.0);
		HurtPlayer(i, g_iShockwave_Damage);
	}

	g_fShockwave_LastRadius = radius;
	if (radius >= g_fShockwave_Size)
		g_bShockwave_Active = false;
}

public Action Cmd_ShockwaveToggle(int client, int args)
{
	if (!g_bShockwave_Enabled)
	{
		CReplyToCommand(client, "%s Shockwave is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Shockwave_Reset();

	CPrintToChatAll("%s Shockwave is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When the blue ring comes, {olive}JUMP {lightgreen}over it!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Shockwave Settings */
public Action Cmd_ShockwaveSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_ShockwaveSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Shockwave now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bShockwave_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_ShockwaveSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Shockwave_Fire();
				Cmd_ShockwaveSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
