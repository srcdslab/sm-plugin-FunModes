/*
    (). FunModes V2:

    @file           Nuke.sp
    @Usage          Functions for the Nuke mode.
                    Once the zombies are out, a nuclear strike is announced with a countdown: a green bunker
                    appears near a random human, and whoever is outside it when the countdown ends gets hurt.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Nuke

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Nuke"

static int g_iNukeIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iNukeIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define NUKE_CONVAR_EVERY   0
#define NUKE_CONVAR_COUNT   1
#define NUKE_CONVAR_BUNKER  2
#define NUKE_CONVAR_DAMAGE  3
#define NUKE_CONVAR_ZOMBIES 4
#define NUKE_CONVAR_TOGGLE  5

int g_iNuke_Every;
int g_iNuke_Countdown;
float g_fNuke_Bunker;
int g_iNuke_Damage;
bool g_bNuke_Zombies;
bool g_bNuke_Enabled;

public void OnPluginStart_Nuke()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_HAZARDS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_nuke", Cmd_NukeToggle, ADMFLAG_CONVARS, "Turn Nuke Countdown On/Off");
	RegAdminCmd("sm_nuke_settings", Cmd_NukeSettings, ADMFLAG_CONVARS, "Open Nuke Countdown Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		NUKE_CONVAR_EVERY, "sm_nuke_every",
		"0", ("Seconds between two nukes (0 = once a round, a little after the zombies come)"),
		("0,60,90,120,180"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		NUKE_CONVAR_COUNT, "sm_nuke_countdown",
		"20", "Seconds of countdown before the strike",
		("10,15,20,30"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		NUKE_CONVAR_BUNKER, "sm_nuke_bunker",
		"300.0", "Radius of the bunker",
		("200.0,300.0,400.0,600.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		NUKE_CONVAR_DAMAGE, "sm_nuke_damage",
		"100", "Damage outside the bunker (1000 = kill)",
		("50,75,100,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		NUKE_CONVAR_ZOMBIES, "sm_nuke_zombies",
		"0", "Zombies outside the bunker get hit too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		NUKE_CONVAR_TOGGLE, "sm_nuke_enable",
		"1", "Enable/Disable Nuke Countdown Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= NUKE_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Nuke_OnConVarChange);

	THIS_MODE_INFO.enableIndex = NUKE_CONVAR_TOGGLE;

	Nuke_OnPluginStart();
}

public void InitCvarsValues_Nuke()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iNuke_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, NUKE_CONVAR_EVERY, Int);
	g_iNuke_Countdown = _FUNMODES_CVAR_GET_VALUE(modeIndex, NUKE_CONVAR_COUNT, Int);
	g_fNuke_Bunker = _FUNMODES_CVAR_GET_VALUE(modeIndex, NUKE_CONVAR_BUNKER, Float);
	g_iNuke_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, NUKE_CONVAR_DAMAGE, Int);
	g_bNuke_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, NUKE_CONVAR_ZOMBIES, Bool);
	g_bNuke_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, NUKE_CONVAR_TOGGLE, Bool);
}

void Nuke_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case NUKE_CONVAR_EVERY:
			g_iNuke_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case NUKE_CONVAR_COUNT:
			g_iNuke_Countdown = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case NUKE_CONVAR_BUNKER:
			g_fNuke_Bunker = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case NUKE_CONVAR_DAMAGE:
			g_iNuke_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case NUKE_CONVAR_ZOMBIES:
			g_bNuke_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case NUKE_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Nuke_Reset();
			}

			g_bNuke_Enabled = val;
		}
	}
}

public void OnMapEnd_Nuke()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Nuke_Reset();
}

int g_iNuke_BunkerColor[4] = { 64, 255, 64, 255 };

float g_fNuke_Next;
bool g_bNuke_DoneThisRound;
bool g_bNuke_Active;
float g_fNuke_At;                   // when it goes off
float g_fNuke_Pos[3];               // the bunker
Handle g_hNuke_Hud;

void Nuke_OnPluginStart()
{
	g_hNuke_Hud = CreateModeHud();
}

void Nuke_Reset()
{
	g_bNuke_Active = false;
	g_fNuke_Next = 0.0;
	g_bNuke_DoneThisRound = false;
}

public void Event_RoundStart_Nuke()
{
	Nuke_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Nuke Countdown is on: when the siren sounds, get to the {olive}green bunker{lightgreen}!", THIS_MODE_INFO.tag);
}

void Nuke_Launch()
{
	int list[MAXPLAYERS + 1];
	if (!GetShuffledHumans(list))
		return;

	GetClientAbsOrigin(list[0], g_fNuke_Pos);
	g_fNuke_At = GetGameTime() + float(g_iNuke_Countdown);
	g_bNuke_Active = true;
	g_bNuke_DoneThisRound = true;

	CPrintToChatAll("%s {olive}NUCLEAR STRIKE IN %d SECONDS! {lightgreen}Get to the green bunker near {olive}%N{lightgreen}!", THIS_MODE_INFO.tag, g_iNuke_Countdown, list[0]);
	PrintCenterTextAll("NUCLEAR STRIKE IN %d SECONDS!", g_iNuke_Countdown);
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 40);
}

void Nuke_Detonate()
{
	g_bNuke_Active = false;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
			ScreenTint(i, 255, 255, 255, 255, 1.0, 3.0);
	}

	int hit;
	float pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bNuke_Zombies))
			continue;

		GetClientAbsOrigin(i, pos);
		if (GetVectorDistance(pos, g_fNuke_Pos) <= g_fNuke_Bunker)
			continue;

		hit++;
		HurtPlayer(i, g_iNuke_Damage);
	}

	EmitSoundToAll(Explode_Sound, _, _, _, _, _, 40);
	CPrintToChatAll("%s {olive}BOOM! %d {lightgreen}player%s caught outside the bunker.", THIS_MODE_INFO.tag, hit, hit == 1 ? " was" : "s were");
}

public void OnTick_Nuke()
{
	if (g_bNuke_Active)
	{
		int left = RoundToCeil(g_fNuke_At - GetGameTime());
		if (left <= 0)
		{
			Nuke_Detonate();
			return;
		}

		DrawRingAt(g_fNuke_Pos, g_fNuke_Bunker, g_fNuke_Bunker, 1.0, g_iNuke_BunkerColor, 14.0);
		DrawBeamDown(g_fNuke_Pos, 800.0, 1.0, 16.0, g_iNuke_BunkerColor);
		if (left <= 5)
			EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 200);

		float pos[3];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;

			bool safe = false;
			if (IsPlayerAlive(i))
			{
				GetClientAbsOrigin(i, pos);
				safe = GetVectorDistance(pos, g_fNuke_Pos) <= g_fNuke_Bunker;
			}

			SetHudTextParams(-1.0, 0.32, 1.1, safe ? 64 : 255, 255, 64, 255, 0, 0.0, 0.0, 0.0);
			ShowModeHud(i, g_hNuke_Hud, "NUCLEAR STRIKE IN %d\n%s", left, safe ? "You're in the bunker" : "GET TO THE GREEN BUNKER!");
		}

		return;
	}

	if (g_iNuke_Every == 0)
	{
		// Once a round, a little after the zombies come
		if (g_bNuke_DoneThisRound || !g_bZombiesSeen)
			return;

		if (g_fNuke_Next == 0.0)
			g_fNuke_Next = GetGameTime() + 20.0;

		if (GetGameTime() >= g_fNuke_Next)
			Nuke_Launch();
	}
	else if (HazardDue(g_fNuke_Next, g_iNuke_Every))
		Nuke_Launch();
}

public Action Cmd_NukeToggle(int client, int args)
{
	if (!g_bNuke_Enabled)
	{
		CReplyToCommand(client, "%s Nuke Countdown is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Nuke_Reset();

	CPrintToChatAll("%s Nuke Countdown is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When the siren sounds, get to the {olive}green bunker{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Nuke Settings */
public Action Cmd_NukeSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_NukeSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Launch the nuke now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bNuke_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_NukeSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Nuke_Launch();
				Cmd_NukeSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
