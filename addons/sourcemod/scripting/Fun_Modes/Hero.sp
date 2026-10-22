/*
    (). FunModes V2:

    @file           Hero.sp
    @Usage          Functions for the Hero mode.
                    When the zombies come, a random human becomes the hero: more health, faster, blue.
                    If the hero falls, the other humans lose health or are all slain (if set).
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Hero

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Hero"

static int g_iHeroIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iHeroIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define HERO_CONVAR_HEALTH 0
#define HERO_CONVAR_SPEED  1
#define HERO_CONVAR_DELAY  2
#define HERO_CONVAR_FALL   3
#define HERO_CONVAR_TOGGLE 4

int g_iHero_Health;
float g_fHero_Speed;
int g_iHero_Delay;
int g_iHero_Fall;
bool g_bHero_Enabled;

public void OnPluginStart_Hero()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_SURVIVAL;

	/* COMMANDS */
	RegAdminCmd("sm_fm_hero", Cmd_HeroToggle, ADMFLAG_CONVARS, "Turn Hero On/Off");
	RegAdminCmd("sm_hero_settings", Cmd_HeroSettings, ADMFLAG_CONVARS, "Open Hero Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		HERO_CONVAR_HEALTH, "sm_hero_health",
		"300", "Health of the hero",
		("150,200,300,500,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HERO_CONVAR_SPEED, "sm_hero_speed",
		"1.2", "Speed of the hero (x normal speed)",
		("1.0,1.1,1.2,1.3,1.5"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		HERO_CONVAR_DELAY, "sm_hero_delay",
		"0", "Seconds after the first zombie before the hero is picked",
		("0,10,30,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HERO_CONVAR_FALL, "sm_hero_fall",
		"1", ("When the hero falls [0 = nothing happens, 1 = every human loses 25 HP, 2 = all humans are slain]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HERO_CONVAR_TOGGLE, "sm_hero_enable",
		"1", "Enable/Disable Hero Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= HERO_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Hero_OnConVarChange);

	THIS_MODE_INFO.enableIndex = HERO_CONVAR_TOGGLE;

	Hero_OnPluginStart();
}

public void InitCvarsValues_Hero()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iHero_Health = _FUNMODES_CVAR_GET_VALUE(modeIndex, HERO_CONVAR_HEALTH, Int);
	g_fHero_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, HERO_CONVAR_SPEED, Float);
	g_iHero_Delay = _FUNMODES_CVAR_GET_VALUE(modeIndex, HERO_CONVAR_DELAY, Int);
	g_iHero_Fall = _FUNMODES_CVAR_GET_VALUE(modeIndex, HERO_CONVAR_FALL, Int);
	g_bHero_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, HERO_CONVAR_TOGGLE, Bool);
}

void Hero_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case HERO_CONVAR_HEALTH:
			g_iHero_Health = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HERO_CONVAR_SPEED:
			g_fHero_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case HERO_CONVAR_DELAY:
			g_iHero_Delay = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HERO_CONVAR_FALL:
			g_iHero_Fall = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HERO_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Hero_Reset();
			}

			g_bHero_Enabled = val;
		}
	}
}

public void OnMapEnd_Hero()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Hero_Reset();
}

#define HERO_FALL_NONE 0
#define HERO_FALL_HURT 1
#define HERO_FALL_SLAY 2

int g_iHero_Color[4] = { 64, 128, 255, 255 };

int g_iHero;                        // userid, 0 = none
bool g_bHero_Done;                  // this round's hero has been picked
float g_fHero_At;
Handle g_hHero_Hud;

void Hero_OnPluginStart()
{
	g_hHero_Hud = CreateModeHud();
}

void Hero_Release()
{
	int hero = GetClientOfUserId(g_iHero);
	if (hero && IsClientInGame(hero))
	{
		int r, g, b, a;
		GetEntityRenderColor(hero, r, g, b, a);
		SetEntityRenderColor(hero, 255, 255, 255, a);
	}

	g_iHero = 0;
	ResetModeMults(THIS_MODE_INDEX);
}

void Hero_Reset()
{
	Hero_Release();
	g_bHero_Done = false;
	g_fHero_At = 0.0;
}

public void Event_RoundStart_Hero()
{
	g_iHero = 0;
	g_bHero_Done = false;
	g_fHero_At = 0.0;
	ResetModeMults(THIS_MODE_INDEX);

	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Hero mode is on: a hero rises when the zombies come - {olive}protect them{lightgreen}!", THIS_MODE_INFO.tag);
}

public void Event_RoundEnd_Hero()
{
	Hero_Release();
}

void Hero_Make(int client)
{
	if (!client)
		return;

	Hero_Release();

	g_iHero = GetClientUserId(client);
	g_bHero_Done = true;
	if (GetClientHealth(client) < g_iHero_Health)
		SetEntityHealth(client, g_iHero_Health);

	SetSpeedMult(client, THIS_MODE_INDEX, g_fHero_Speed);

	int r, g, b, a;
	GetEntityRenderColor(client, r, g, b, a);
	SetEntityRenderColor(client, 100, 160, 255, a);

	CPrintToChatAll("%s {olive}%N {lightgreen}is the {olive}HERO! {lightgreen}(%d HP, faster)%s", THIS_MODE_INFO.tag, client, g_iHero_Health,
		g_iHero_Fall == HERO_FALL_SLAY ? " If the hero falls, every human falls!" : (g_iHero_Fall == HERO_FALL_HURT ? " Keep them alive!" : ""));
	PrintCenterTextAll("%N IS THE HERO!", client);
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 170);
}

void Hero_Fallen(int hero)
{
	g_iHero = 0;
	ResetModeMults(THIS_MODE_INDEX);

	if (g_iHero_Fall == HERO_FALL_SLAY)
	{
		CPrintToChatAll("%s The hero {olive}%N {lightgreen}has fallen! All humans are slain.", THIS_MODE_INFO.tag, hero);
		PrintCenterTextAll("THE HERO HAS FALLEN!");
		SlayAllHumans();
		return;
	}

	CPrintToChatAll("%s The hero {olive}%N {lightgreen}has fallen!%s", THIS_MODE_INFO.tag, hero, g_iHero_Fall == HERO_FALL_HURT ? " Every human loses 25 HP." : "");
	if (g_iHero_Fall != HERO_FALL_HURT)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanAlive(i))
			HurtPlayer(i, 25);
	}
}

public void OnCheck_Hero(bool zombiesNow)
{
	if (g_iHero)
	{
		int hero = GetClientOfUserId(g_iHero);
		if (!hero)
		{
			g_iHero = 0;
			ResetModeMults(THIS_MODE_INDEX);
			CPrintToChatAll("%s The hero left the server.", THIS_MODE_INFO.tag);
		}
		else if (!IsHumanAlive(hero))
		{
			int r, g, b, a;
			GetEntityRenderColor(hero, r, g, b, a);
			SetEntityRenderColor(hero, 255, 255, 255, a);
			Hero_Fallen(hero);
		}

		return;
	}

	if (g_bHero_Done || !zombiesNow)
		return;

	float now = GetGameTime();
	if (g_fHero_At == 0.0)
		g_fHero_At = now + float(g_iHero_Delay);

	if (now >= g_fHero_At)
		Hero_Make(PickRandomHuman());
}

public void OnTick_Hero()
{
	int hero = GetClientOfUserId(g_iHero);
	if (!IsHumanAlive(hero))
		return;

	DrawPlayerRing(hero, g_iHero_Color, 50.0);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		SetHudTextParams(-1.0, 0.26, 1.1, 100, 160, 255, 255, 0, 0.0, 0.0, 0.0);
		if (i == hero)
			ShowModeHud(i, g_hHero_Hud, "YOU ARE THE HERO! (%d HP)", GetClientHealth(hero));
		else
			ShowModeHud(i, g_hHero_Hud, "HERO: %N (%d HP)", hero, GetClientHealth(hero));
	}
}

public Action Cmd_HeroToggle(int client, int args)
{
	if (!g_bHero_Enabled)
	{
		CReplyToCommand(client, "%s Hero is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Hero_Reset();

	CPrintToChatAll("%s Hero is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s A hero rises when the zombies come - {olive}protect them{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Hero Settings */
public Action Cmd_HeroSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_HeroSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Make a random human the hero now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_HeroSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Hero_Make(PickRandomHuman());
				Cmd_HeroSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
