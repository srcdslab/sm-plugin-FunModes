/*
    (). FunModes V2:

    @file           BossZombie.sp
    @Usage          Functions for the BossZombie mode.
                    A little after the first zombies come, a random zombie becomes the boss: huge health (more
                    for every living human), faster, red, with a health bar for everyone. Killing it rewards the humans.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_BossZombie

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "BossZombie"

static int g_iBossZombieIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iBossZombieIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define BOSS_CONVAR_HEALTH   0
#define BOSS_CONVAR_PERHUMAN 1
#define BOSS_CONVAR_SPEED    2
#define BOSS_CONVAR_DELAY    3
#define BOSS_CONVAR_REWARD   4
#define BOSS_CONVAR_TOGGLE   5

int g_iBoss_Health;
int g_iBoss_PerHuman;
float g_fBoss_Speed;
int g_iBoss_Delay;
int g_iBoss_Reward;
bool g_bBossZombie_Enabled;

public void OnPluginStart_BossZombie()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_ZOMBIES;

	/* COMMANDS */
	RegAdminCmd("sm_fm_boss", Cmd_BossZombieToggle, ADMFLAG_CONVARS, "Turn Boss Zombie On/Off");
	RegAdminCmd("sm_boss_settings", Cmd_BossZombieSettings, ADMFLAG_CONVARS, "Open Boss Zombie Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		BOSS_CONVAR_HEALTH, "sm_boss_health",
		"20000", "Base health of the boss",
		("10000,20000,50000,100000,200000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BOSS_CONVAR_PERHUMAN, "sm_boss_per_human",
		"1000", "Extra health of the boss per living human",
		("0,500,1000,2500,5000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BOSS_CONVAR_SPEED, "sm_boss_speed",
		"1.3", "Speed of the boss (x normal speed)",
		("1.0,1.15,1.3,1.5"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		BOSS_CONVAR_DELAY, "sm_boss_delay",
		"15", "Seconds after the first zombie before the boss rises",
		("0,15,30,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BOSS_CONVAR_REWARD, "sm_boss_reward",
		"1", ("Reward for killing the boss [0 = nothing, 1 = +50 HP to every human, 2 = HE grenade to every human]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		BOSS_CONVAR_TOGGLE, "sm_boss_enable",
		"1", "Enable/Disable Boss Zombie Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= BOSS_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(BossZombie_OnConVarChange);

	THIS_MODE_INFO.enableIndex = BOSS_CONVAR_TOGGLE;

	BossZombie_OnPluginStart();
}

public void InitCvarsValues_BossZombie()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iBoss_Health = _FUNMODES_CVAR_GET_VALUE(modeIndex, BOSS_CONVAR_HEALTH, Int);
	g_iBoss_PerHuman = _FUNMODES_CVAR_GET_VALUE(modeIndex, BOSS_CONVAR_PERHUMAN, Int);
	g_fBoss_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, BOSS_CONVAR_SPEED, Float);
	g_iBoss_Delay = _FUNMODES_CVAR_GET_VALUE(modeIndex, BOSS_CONVAR_DELAY, Int);
	g_iBoss_Reward = _FUNMODES_CVAR_GET_VALUE(modeIndex, BOSS_CONVAR_REWARD, Int);
	g_bBossZombie_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, BOSS_CONVAR_TOGGLE, Bool);
}

void BossZombie_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case BOSS_CONVAR_HEALTH:
			g_iBoss_Health = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BOSS_CONVAR_PERHUMAN:
			g_iBoss_PerHuman = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BOSS_CONVAR_SPEED:
			g_fBoss_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case BOSS_CONVAR_DELAY:
			g_iBoss_Delay = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BOSS_CONVAR_REWARD:
			g_iBoss_Reward = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case BOSS_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				BossZombie_Reset();
			}

			g_bBossZombie_Enabled = val;
		}
	}
}

public void OnMapEnd_BossZombie()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	BossZombie_Reset();
}

#define BOSS_BAR 25                     // health bar width

#define BOSS_REWARD_NONE 0
#define BOSS_REWARD_HEAL 1
#define BOSS_REWARD_HE   2

int g_iBoss_Color[4] = { 255, 30, 30, 255 };

int g_iBoss;                        // userid, 0 = none
int g_iBoss_Max;
bool g_bBoss_Done;                  // a boss already came this round
float g_fBoss_At;                   // when the boss appears, 0 = not planned yet
Handle g_hBoss_Hud;

void BossZombie_OnPluginStart()
{
	g_hBoss_Hud = CreateModeHud();
}

/* The boss stops being the boss (speed and colour back to normal) */
void BossZombie_Release()
{
	int boss = GetClientOfUserId(g_iBoss);
	if (boss && IsClientInGame(boss))
	{
		int r, g, b, a;
		GetEntityRenderColor(boss, r, g, b, a);
		SetEntityRenderColor(boss, 255, 255, 255, a);
	}

	g_iBoss = 0;
	ResetModeMults(THIS_MODE_INDEX);
}

void BossZombie_Reset()
{
	BossZombie_Release();
	g_bBoss_Done = false;
	g_fBoss_At = 0.0;
}

public void Event_RoundStart_BossZombie()
{
	g_iBoss = 0;
	g_bBoss_Done = false;
	g_fBoss_At = 0.0;
	ResetModeMults(THIS_MODE_INDEX);

	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Boss Zombie is on: a boss rises {olive}%s {lightgreen}after the zombies come!", THIS_MODE_INFO.tag, g_iBoss_Delay == 0 ? "right" : "soon");
}

public void Event_RoundEnd_BossZombie()
{
	BossZombie_Release();
}

void BossZombie_Make(int zombie)
{
	if (!zombie)
		return;

	BossZombie_Release();

	int humans;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsHumanAlive(i))
			humans++;
	}

	g_iBoss = GetClientUserId(zombie);
	g_bBoss_Done = true;
	g_iBoss_Max = g_iBoss_Health + g_iBoss_PerHuman * humans;
	SetEntityHealth(zombie, g_iBoss_Max);
	SetSpeedMult(zombie, THIS_MODE_INDEX, g_fBoss_Speed);

	int r, g, b, a;
	GetEntityRenderColor(zombie, r, g, b, a);
	SetEntityRenderColor(zombie, 255, 60, 60, a);

	CPrintToChatAll("%s {olive}%N {lightgreen}has become the {olive}BOSS ZOMBIE {lightgreen}with {olive}%d {lightgreen}health! Take it down!", THIS_MODE_INFO.tag, zombie, g_iBoss_Max);
	PrintCenterTextAll("%N IS THE BOSS ZOMBIE!", zombie);
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 40);
}

void BossZombie_Defeated(int boss)
{
	g_iBoss = 0;
	ResetModeMults(THIS_MODE_INDEX);

	CPrintToChatAll("%s The boss {olive}%N {lightgreen}has been {olive}DEFEATED!%s", THIS_MODE_INFO.tag, boss,
		g_iBoss_Reward == BOSS_REWARD_HEAL ? " {lightgreen}Every human gets +50 HP." : (g_iBoss_Reward == BOSS_REWARD_HE ? " {lightgreen}Every human gets an HE grenade." : ""));
	PrintCenterTextAll("THE BOSS IS DEFEATED!");

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanAlive(i))
			continue;

		if (g_iBoss_Reward == BOSS_REWARD_HEAL)
			SetEntityHealth(i, GetClientHealth(i) + 50);
		else if (g_iBoss_Reward == BOSS_REWARD_HE)
			GivePlayerItem(i, "weapon_hegrenade");
	}
}

public void OnCheck_BossZombie(bool zombiesNow)
{
	if (g_iBoss)
	{
		int boss = GetClientOfUserId(g_iBoss);
		if (!boss)
		{
			g_iBoss = 0;
			ResetModeMults(THIS_MODE_INDEX);
			CPrintToChatAll("%s The boss left the server.", THIS_MODE_INFO.tag);
		}
		else if (!IsPlayerAlive(boss))
			BossZombie_Defeated(boss);
		else if (!ZR_IsClientZombie(boss))
		{
			// Cured or moved team
			BossZombie_Release();
			CPrintToChatAll("%s The boss is no longer a zombie.", THIS_MODE_INFO.tag);
		}

		return;
	}

	if (g_bBoss_Done || !zombiesNow)
		return;

	float now = GetGameTime();
	if (g_fBoss_At == 0.0)
		g_fBoss_At = now + float(g_iBoss_Delay);

	if (now >= g_fBoss_At)
		BossZombie_Make(PickRandomZombie());
}

public void OnTick_BossZombie()
{
	int boss = GetClientOfUserId(g_iBoss);
	if (!boss || !IsPlayerAlive(boss))
		return;

	DrawPlayerRing(boss, g_iBoss_Color, 50.0);

	int hp = GetClientHealth(boss);
	int filled = g_iBoss_Max > 0 ? hp * BOSS_BAR / g_iBoss_Max : 0;
	if (filled > BOSS_BAR)
		filled = BOSS_BAR;

	char bar[BOSS_BAR + 1];
	for (int i = 0; i < BOSS_BAR; i++)
		bar[i] = i < filled ? '|' : '.';

	bar[BOSS_BAR] = '\0';

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		SetHudTextParams(-1.0, HUD_Y_BOSS, 1.1, 255, 40, 40, 255, 0, 0.0, 0.0, 0.0);
		ShowModeHud(i, g_hBoss_Hud, "BOSS: %N\n[%s] %d / %d", boss, bar, hp, g_iBoss_Max);
	}
}

public Action Cmd_BossZombieToggle(int client, int args)
{
	if (!g_bBossZombie_Enabled)
	{
		CReplyToCommand(client, "%s Boss Zombie is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	BossZombie_Reset();

	CPrintToChatAll("%s Boss Zombie is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s A boss rises after the zombies come!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* BossZombie Settings */
public Action Cmd_BossZombieSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_BossZombieSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Make a random zombie the boss now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_BossZombieSettings(Menu menu, MenuAction action, int param1, int param2)
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
				BossZombie_Make(PickRandomZombie());
				Cmd_BossZombieSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
