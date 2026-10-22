/*
    (). FunModes V2:

    @file           Leech.sp
    @Usage          Functions for the Leech mode.
                    Once the zombies are out, the humans' health drains unless they keep hurting zombies,
                    and/or every few seconds the humans who dealt the least damage get hurt.
                    Dealing damage can also heal a little.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Leech

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Leech"

static int g_iLeechIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iLeechIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define LEECH_CONVAR_MODE    0
#define LEECH_CONVAR_WEVERY  1
#define LEECH_CONVAR_WCOUNT  2
#define LEECH_CONVAR_WDAMAGE 3
#define LEECH_CONVAR_DRAIN   4
#define LEECH_CONVAR_GRACE   5
#define LEECH_CONVAR_HEAL    6
#define LEECH_CONVAR_TOGGLE  7

int g_iLeech_Mode;
int g_iLeech_WorstEvery;
int g_iLeech_WorstCount;
int g_iLeech_WorstDamage;
int g_iLeech_Drain;
int g_iLeech_Grace;
int g_iLeech_Heal;
bool g_bLeech_Enabled;

public void OnPluginStart_Leech()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_CHAOS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_leech", Cmd_LeechToggle, ADMFLAG_CONVARS, "Turn Leech On/Off");
	RegAdminCmd("sm_leech_settings", Cmd_LeechSettings, ADMFLAG_CONVARS, "Open Leech Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		LEECH_CONVAR_MODE, "sm_leech_mode",
		"0", ("Leech mode [0 = drain unless you hurt zombies, 1 = punish the worst defenders, 2 = both]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LEECH_CONVAR_WEVERY, "sm_leech_worst_every",
		"20", "Seconds between two worst defenders checks",
		("15,20,30,40,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LEECH_CONVAR_WCOUNT, "sm_leech_worst_count",
		"3", "How many of the worst defenders get hurt",
		("1,2,3,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LEECH_CONVAR_WDAMAGE, "sm_leech_worst_damage",
		"10", "Damage given to the worst defenders",
		("5,10,15,20,30"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LEECH_CONVAR_DRAIN, "sm_leech_drain",
		"2", "Health drained per second",
		("1,2,3,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LEECH_CONVAR_GRACE, "sm_leech_grace",
		"5", "Seconds without drain after hurting a zombie",
		("3,5,10,15"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LEECH_CONVAR_HEAL, "sm_leech_heal",
		"1", "Health back per 100 damage dealt to zombies (up to 150 HP)",
		("0,1,2,5"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		LEECH_CONVAR_TOGGLE, "sm_leech_enable",
		"1", "Enable/Disable Leech Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= LEECH_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Leech_OnConVarChange);

	THIS_MODE_INFO.enableIndex = LEECH_CONVAR_TOGGLE;

	Leech_OnPluginStart();
}

public void InitCvarsValues_Leech()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iLeech_Mode = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_MODE, Int);
	g_iLeech_WorstEvery = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_WEVERY, Int);
	g_iLeech_WorstCount = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_WCOUNT, Int);
	g_iLeech_WorstDamage = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_WDAMAGE, Int);
	g_iLeech_Drain = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_DRAIN, Int);
	g_iLeech_Grace = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_GRACE, Int);
	g_iLeech_Heal = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_HEAL, Int);
	g_bLeech_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, LEECH_CONVAR_TOGGLE, Bool);
}

void Leech_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case LEECH_CONVAR_MODE:
			g_iLeech_Mode = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LEECH_CONVAR_WEVERY:
			g_iLeech_WorstEvery = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LEECH_CONVAR_WCOUNT:
			g_iLeech_WorstCount = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LEECH_CONVAR_WDAMAGE:
			g_iLeech_WorstDamage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LEECH_CONVAR_DRAIN:
			g_iLeech_Drain = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LEECH_CONVAR_GRACE:
			g_iLeech_Grace = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LEECH_CONVAR_HEAL:
			g_iLeech_Heal = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case LEECH_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Leech_Reset();
			}

			g_bLeech_Enabled = val;
		}
	}
}

public void OnMapEnd_Leech()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Leech_Reset();
}

#define LEECH_DRAIN 0
#define LEECH_WORST 1
#define LEECH_BOTH  2

float g_fLeech_WorstNext;
int g_iLeech_Dealt[MAXPLAYERS + 1];         // damage to zombies since the last check
float g_fLeech_LastHit[MAXPLAYERS + 1];
int g_iLeech_Carry[MAXPLAYERS + 1];         // damage towards the next heal
Handle g_hLeech_Hud;

void Leech_OnPluginStart()
{
	g_hLeech_Hud = CreateModeHud();
	HookEvent("player_hurt", Leech_PlayerHurt);
}

void Leech_Reset()
{
	g_fLeech_WorstNext = 0.0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_fLeech_LastHit[i] = 0.0;
		g_iLeech_Carry[i] = 0;
		g_iLeech_Dealt[i] = 0;
	}
}

public void Event_RoundStart_Leech()
{
	Leech_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Leech is on: keep shooting zombies or your health {olive}drains away{lightgreen}!", THIS_MODE_INFO.tag);
}

void Leech_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!THIS_MODE_INFO.isOn)
		return;

	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (!victim || !IsHumanAlive(attacker) || !ZR_IsClientZombie(victim))
		return;

	int damage = event.GetInt("dmg_health");
	g_fLeech_LastHit[attacker] = GetGameTime();
	g_iLeech_Dealt[attacker] += damage;

	if (g_iLeech_Heal <= 0)
		return;

	g_iLeech_Carry[attacker] += damage;
	if (g_iLeech_Carry[attacker] < 100)
		return;

	int heal = (g_iLeech_Carry[attacker] / 100) * g_iLeech_Heal;
	g_iLeech_Carry[attacker] %= 100;

	// Heals up to 150, never takes anything away
	int health = GetClientHealth(attacker);
	if (health < 150)
		SetEntityHealth(attacker, health + heal > 150 ? 150 : health + heal);
}

/* The humans who dealt the least damage since the last check get hurt */
void Leech_PunishWorst()
{
	int list[MAXPLAYERS + 1];

	// Shuffled first, so ties are broken at random, then sorted by damage dealt, lowest first
	int count = GetShuffledHumans(list);
	for (int a = 1; a < count; a++)
	{
		int c = list[a], b = a - 1;
		while (b >= 0 && g_iLeech_Dealt[list[b]] > g_iLeech_Dealt[c])
		{
			list[b + 1] = list[b];
			b--;
		}

		list[b + 1] = c;
	}

	// Never everyone
	int hurt = g_iLeech_WorstCount < count ? g_iLeech_WorstCount : count - 1;
	for (int i = 0; i < hurt; i++)
	{
		CPrintToChatAll("%s {olive}%N {lightgreen}got hurt for being a bad defender ({olive}%d {lightgreen}damage)!", THIS_MODE_INFO.tag, list[i], g_iLeech_Dealt[list[i]]);
		HurtPlayer(list[i], g_iLeech_WorstDamage);
	}

	for (int i = 1; i <= MaxClients; i++)
		g_iLeech_Dealt[i] = 0;
}

public void OnTick_Leech()
{
	if (!g_bZombiesSeen)
		return;

	float now = GetGameTime();
	if (g_iLeech_Mode != LEECH_DRAIN)
	{
		if (g_fLeech_WorstNext == 0.0)
			g_fLeech_WorstNext = now + float(g_iLeech_WorstEvery);

		if (now >= g_fLeech_WorstNext)
		{
			Leech_PunishWorst();
			g_fLeech_WorstNext = now + float(g_iLeech_WorstEvery);
		}

		if (g_iLeech_Mode == LEECH_WORST)
		{
			int left = RoundToCeil(g_fLeech_WorstNext - now);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsHumanAlive(i) || IsFakeClient(i))
					continue;

				SetHudTextParams(-1.0, 0.84, 1.1, 255, 200, 80, 255, 0, 0.0, 0.0, 0.0);
				ShowModeHud(i, g_hLeech_Hud, "Worst defenders get hurt in %d s - your damage: %d", left, g_iLeech_Dealt[i]);
			}

			return;
		}
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHumanAlive(i))
			continue;

		bool feeding = g_fLeech_LastHit[i] > 0.0 && now - g_fLeech_LastHit[i] < float(g_iLeech_Grace);
		if (!IsFakeClient(i))
		{
			SetHudTextParams(-1.0, 0.84, 1.1, feeding ? 120 : 255, feeding ? 255 : 80, feeding ? 120 : 80, 255, 0, 0.0, 0.0, 0.0);
			if (feeding)
				ShowModeHud(i, g_hLeech_Hud, "Leech: fed (%d s)", RoundToCeil(float(g_iLeech_Grace) - (now - g_fLeech_LastHit[i])));
			else
				ShowModeHud(i, g_hLeech_Hud, "LEECH: hurt a zombie to stop the drain (-%d HP/s)", g_iLeech_Drain);
		}

		if (!feeding)
			HurtPlayer(i, g_iLeech_Drain);
	}
}

public Action Cmd_LeechToggle(int client, int args)
{
	if (!g_bLeech_Enabled)
	{
		CReplyToCommand(client, "%s Leech is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Leech_Reset();

	CPrintToChatAll("%s Leech is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Keep shooting zombies or your health {olive}drains away{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Leech Settings */
public Action Cmd_LeechSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_LeechSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_LeechSettings(Menu menu, MenuAction action, int param1, int param2)
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
			ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
