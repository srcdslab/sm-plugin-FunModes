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
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Hero_Intro");
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

	if (g_iHero_Fall == HERO_FALL_SLAY || g_iHero_Fall == HERO_FALL_HURT)
		CPrintToChatAll("%s %t %t", THIS_MODE_INFO.tag, "Hero_Is", client, g_iHero_Health, g_iHero_Fall == HERO_FALL_SLAY ? "Hero_IsSlay" : "Hero_IsHurt");
	else
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Hero_Is", client, g_iHero_Health);
	PrintCenterTextAll("%t", "Hero_Center", client);
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 170);
}

void Hero_Fallen(int hero)
{
	g_iHero = 0;
	ResetModeMults(THIS_MODE_INDEX);

	if (g_iHero_Fall == HERO_FALL_SLAY)
	{
		CPrintToChatAll("%s %t %t", THIS_MODE_INFO.tag, "Hero_Fallen", hero, "Hero_FallenSlay");
		PrintCenterTextAll("%t", "Hero_FallenCenter");
		SlayAllHumans();
		return;
	}

	if (g_iHero_Fall == HERO_FALL_HURT)
		CPrintToChatAll("%s %t %t", THIS_MODE_INFO.tag, "Hero_Fallen", hero, "Hero_FallenHurt");
	else
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Hero_Fallen", hero);
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
			CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Hero_Left");
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

		SetHudTextParams(-1.0, HUD_Y_HERO, 1.1, 100, 160, 255, 255, 0, 0.0, 0.0, 0.0);
		if (i == hero)
			ShowModeHud(i, g_hHero_Hud, "%t", "Hero_HudYou", GetClientHealth(hero));
		else
			ShowModeHud(i, g_hHero_Hud, "%t", "Hero_Hud", hero, GetClientHealth(hero));
	}
}

public Action Cmd_HeroToggle(int client, int args)
{
	if (!g_bHero_Enabled)
	{
		CReplyToCommand(client, "%s %t", THIS_MODE_INFO.tag, "FM_Disabled", "Hero");
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Hero_Reset();

	CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "FM_NowOn" : "FM_NowOff", "Hero");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "Hero_Hint");

	return Plugin_Handled;
}

/* Hero Settings */
public Action Cmd_HeroSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_HeroSettings);

	menu.SetTitle("%T", "FM_MenuSettings", client, THIS_MODE_INFO.name);

	FM_AddItemT(menu, client, "now", "Hero_MenuNow", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	FM_AddItemT(menu, client, "cvars", "FM_MenuShowCvars", ITEMDRAW_DEFAULT, "\n");

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
