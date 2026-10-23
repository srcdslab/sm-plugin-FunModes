/*
    (). FunModes V2:

    @file           Earthquake.sp
    @Usage          Functions for the Earthquake mode.
                    Once the zombies are out, every few seconds an earthquake shakes everyone's screen and
                    shoves the players around for a few seconds. Sets sm_force_shake 1 while it's on.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Earthquake

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Earthquake"

static int g_iEarthquakeIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iEarthquakeIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define QUAKE_CONVAR_EVERY      0
#define QUAKE_CONVAR_LAST       1
#define QUAKE_CONVAR_SHAKE      2
#define QUAKE_CONVAR_SPEED      3
#define QUAKE_CONVAR_SHOVE      4
#define QUAKE_CONVAR_SHOVEEVERY 5
#define QUAKE_CONVAR_EVERYONE   6
#define QUAKE_CONVAR_TOGGLE     7

int g_iQuake_Every;
int g_iQuake_Last;
int g_iQuake_Shake;
int g_iQuake_Speed;
int g_iQuake_Shove;
float g_fQuake_ShoveEvery;
bool g_bQuake_Everyone;
bool g_bEarthquake_Enabled;

public void OnPluginStart_Earthquake()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_quake", Cmd_EarthquakeToggle, ADMFLAG_CONVARS, "Turn Earthquake On/Off");
	RegAdminCmd("sm_quake_settings", Cmd_EarthquakeSettings, ADMFLAG_CONVARS, "Open Earthquake Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		QUAKE_CONVAR_EVERY, "sm_quake_every",
		"45", "Seconds between two earthquakes",
		("20,30,45,60,90,120"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUAKE_CONVAR_LAST, "sm_quake_last",
		"5", "Seconds an earthquake lasts",
		("3,5,8,10,15"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUAKE_CONVAR_SHAKE, "sm_quake_shake",
		"3", ("Screen shake [0 = off, 1 = tiny ... 7 = insane]"),
		("0,1,2,3,4,5,6,7"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUAKE_CONVAR_SPEED, "sm_quake_speed",
		"1", ("Shake speed [0 = slow rumble, 1 = normal, 2 = fast, 3 = violent]"),
		("0,1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUAKE_CONVAR_SHOVE, "sm_quake_shove",
		"3", ("How hard the players get shoved [0 = off, 1 = tiny ... 7 = insane]"),
		("0,1,2,3,4,5,6,7"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		QUAKE_CONVAR_SHOVEEVERY, "sm_quake_shove_every",
		"0.6", "Seconds between two shoves",
		("0.3,0.6,1.0,1.5"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		QUAKE_CONVAR_EVERYONE, "sm_quake_everyone",
		"1", "The zombies are shaken too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		QUAKE_CONVAR_TOGGLE, "sm_quake_enable",
		"1", "Enable/Disable Earthquake Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= QUAKE_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Earthquake_OnConVarChange);

	THIS_MODE_INFO.enableIndex = QUAKE_CONVAR_TOGGLE;
}

public void InitCvarsValues_Earthquake()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iQuake_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_EVERY, Int);
	g_iQuake_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_LAST, Int);
	g_iQuake_Shake = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_SHAKE, Int);
	g_iQuake_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_SPEED, Int);
	g_iQuake_Shove = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_SHOVE, Int);
	g_fQuake_ShoveEvery = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_SHOVEEVERY, Float);
	g_bQuake_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_EVERYONE, Bool);
	g_bEarthquake_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, QUAKE_CONVAR_TOGGLE, Bool);
}

void Earthquake_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case QUAKE_CONVAR_EVERY:
			g_iQuake_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUAKE_CONVAR_LAST:
			g_iQuake_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUAKE_CONVAR_SHAKE:
			g_iQuake_Shake = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUAKE_CONVAR_SPEED:
			g_iQuake_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUAKE_CONVAR_SHOVE:
			g_iQuake_Shove = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case QUAKE_CONVAR_SHOVEEVERY:
			g_fQuake_ShoveEvery = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case QUAKE_CONVAR_EVERYONE:
			g_bQuake_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case QUAKE_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Earthquake_Reset();
				Earthquake_ForceShake(false);
			}

			g_bEarthquake_Enabled = val;
		}
	}
}

#define QUAKE_FORCE_CVAR "sm_force_shake"

float g_fQuake_ShakeLevels[] = { 0.0, 1.5, 3.5, 7.0, 10.0, 14.0, 20.0, 30.0 };          // screen shake amplitude
float g_fQuake_ShoveLevels[] = { 0.0, 60.0, 120.0, 220.0, 350.0, 500.0, 700.0, 1000.0 }; // shove speed
float g_fQuake_SpeedLevels[] = { 40.0, 100.0, 170.0, 255.0 };                           // shake frequency

bool g_bQuake_Active;
float g_fQuake_Next;                // 0 = schedule when the zombies come
float g_fQuake_Ends;
float g_fQuake_NextShove;
bool g_bQuake_Forced;               // we set sm_force_shake 1

/* Make sure the players see the shake: sm_force_shake 1 while earthquakes are on, back to 0 when they're turned off (only if we turned it on) */
void Earthquake_ForceShake(bool on)
{
	if (!on && !g_bQuake_Forced)
		return;

	g_bQuake_Forced = on;
	ServerCommand("%s %d", QUAKE_FORCE_CVAR, on ? 1 : 0);
}

void Earthquake_Reset()
{
	g_bQuake_Active = false;
	g_fQuake_Next = 0.0;
}

void Earthquake_OnToggle(bool on)
{
	Earthquake_ForceShake(on);
}

public void OnMapEnd_Earthquake()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Earthquake_Reset();
	Earthquake_ForceShake(false);
}

public void OnPluginEnd_Earthquake()
{
	Earthquake_ForceShake(false);
}

public void Event_RoundStart_Earthquake()
{
	Earthquake_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Earthquakes are on: watch your footing on the narrow paths!", THIS_MODE_INFO.tag);
}

int Earthquake_Level(int value, int count)
{
	return (value < 0 || value >= count) ? 0 : value;
}

void Earthquake_SendShake(int client, float amplitude, float frequency, float seconds)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Shake", client, USERMSG_RELIABLE));
	bf.WriteByte(0);    // SHAKE_START
	bf.WriteFloat(amplitude);
	bf.WriteFloat(frequency);
	bf.WriteFloat(seconds);
	EndMessage();
}

void Earthquake_Start()
{
	float now = GetGameTime();
	g_bQuake_Active = true;
	g_fQuake_Ends = now + float(g_iQuake_Last);
	g_fQuake_NextShove = now + 0.3;
	Earthquake_ForceShake(true);

	float amp = g_fQuake_ShakeLevels[Earthquake_Level(g_iQuake_Shake, sizeof(g_fQuake_ShakeLevels))];
	float frequency = g_fQuake_SpeedLevels[Earthquake_Level(g_iQuake_Speed, sizeof(g_fQuake_SpeedLevels))];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		if (amp > 0.0 && (HazardHits(i, g_bQuake_Everyone) || !IsPlayerAlive(i) || g_bQuake_Everyone))
			Earthquake_SendShake(i, amp, frequency, float(g_iQuake_Last));

		PrintCenterText(i, "EARTHQUAKE!");
	}

	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 30);
}

void Earthquake_Shove()
{
	float power = g_fQuake_ShoveLevels[Earthquake_Level(g_iQuake_Shove, sizeof(g_fQuake_ShoveLevels))];
	if (power <= 0.0)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bQuake_Everyone))
			continue;

		float angle = GetRandomFloat(0.0, 6.2832);

		// A little hop so the ground friction doesn't eat the shove
		ShovePlayer(i, Cosine(angle) * power, Sine(angle) * power, (GetEntityFlags(i) & FL_ONGROUND) ? 60.0 : 0.0);
	}
}

public void OnCheck_Earthquake(bool zombiesNow)
{
	if (!g_bQuake_Active)
		return;

	float now = GetGameTime();
	if (now >= g_fQuake_Ends)
	{
		g_bQuake_Active = false;
		g_fQuake_Next = now + float(g_iQuake_Every);
		return;
	}

	if (now >= g_fQuake_NextShove)
	{
		Earthquake_Shove();
		g_fQuake_NextShove = now + g_fQuake_ShoveEvery;
	}
}

public void OnTick_Earthquake()
{
	if (!g_bQuake_Active && HazardDue(g_fQuake_Next, g_iQuake_Every))
		Earthquake_Start();
}

public Action Cmd_EarthquakeToggle(int client, int args)
{
	if (!g_bEarthquake_Enabled)
	{
		CReplyToCommand(client, "%s Earthquake is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Earthquake_Reset();

	CPrintToChatAll("%s Earthquake is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Watch your footing on the narrow paths!", THIS_MODE_INFO.tag);

	Earthquake_OnToggle(THIS_MODE_INFO.isOn);

	return Plugin_Handled;
}

/* Earthquake Settings */
public Action Cmd_EarthquakeSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_EarthquakeSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Earthquake now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bQuake_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_EarthquakeSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Earthquake_Start();
				Cmd_EarthquakeSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
