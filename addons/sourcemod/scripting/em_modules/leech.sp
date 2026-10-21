// Leech module of eventmodes.sp.
// eventmodes.sp calls LC_PluginStart; modes.sp calls LC_Tick (every second), LC_RoundStart and LC_Stop.
//
// Once the zombies are out, humans slowly lose health unless they keep hurting zombies: damage dealt
// to a zombie stops the drain for a few seconds (and can heal a little). Or (FunModes' Damage Game) every
// N seconds the humans who dealt the least damage get hurt - or both.

#if defined _em_leech_included
 #endinput
#endif
#define _em_leech_included

#define LC_TAG "\x07" ... "C04040[Leech]\x01 "   // kept apart: \x would eat the hex digits

int g_LcDrainSteps[] = { 1, 2, 3, 5 };
int g_LcGraceSteps[] = { 3, 5, 10, 15 };
int g_LcHealSteps[] = { 0, 1, 2, 5 };   // HP back per 100 damage dealt
enum { LC_DRAIN = 0, LC_WORST, LC_BOTH, LC_MODES }
char g_LcModeNames[][] = { "drain unless you hurt zombies", "punish the worst defenders", "both" };
int g_LcWorstEverySteps[] = { 15, 20, 30, 40, 60 };
int g_LcWorstCountSteps[] = { 1, 2, 3, 5 };
int g_LcWorstDamageSteps[] = { 5, 10, 15, 20, 30 };

bool g_LcOn;
int g_LcDrain = 2;          // HP per second
int g_LcGrace = 5;          // seconds of no drain after hurting a zombie
int g_LcHeal = 1;
int g_LcMode = LC_DRAIN;
int g_LcWorstEvery = 20;    // seconds between worst-defender checks
int g_LcWorstCount = 3;     // how many of the worst get hurt
int g_LcWorstDamage = 10;
float g_LcWorstNext;
int g_LcDealt[MAXPLAYERS + 1];   // damage to zombies since the last check
float g_LcLastHit[MAXPLAYERS + 1];
int g_LcCarry[MAXPLAYERS + 1];   // damage towards the next heal
Handle g_HudLeech;

void LC_PluginStart()
{
	g_HudLeech = EM_HudSync();
	HookEvent("player_hurt", LC_PlayerHurt);
}

bool LC_IsOn()
{
	return g_LcOn;
}

void LC_Clear()
{
	g_LcWorstNext = 0.0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_LcLastHit[i] = 0.0;
		g_LcCarry[i] = 0;
		g_LcDealt[i] = 0;
	}
}

void LC_Stop()
{
	g_LcOn = false;
	LC_Clear();
}

void LC_Set(bool on)
{
	LC_Stop();
	g_LcOn = on;
}

void LC_RoundStart()
{
	LC_Clear();
	if (g_LcOn)
		PrintToChatAll(LC_TAG ... "Leech is on: keep shooting zombies or your health drains away!");
}

public void LC_PlayerHurt(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_LcOn)
		return;
	int victim = GetClientOfUserId(event.GetInt("userid"));
	int attacker = GetClientOfUserId(event.GetInt("attacker"));
	if (victim == 0 || attacker == 0 || !IsHuman(attacker) || GetClientTeam(victim) != CS_TEAM_T)
		return;
	g_LcLastHit[attacker] = GetGameTime();
	g_LcDealt[attacker] += event.GetInt("dmg_health");
	if (g_LcHeal <= 0)
		return;
	g_LcCarry[attacker] += event.GetInt("dmg_health");
	if (g_LcCarry[attacker] >= 100)
	{
		int heal = (g_LcCarry[attacker] / 100) * g_LcHeal;
		g_LcCarry[attacker] %= 100;
		int cur = GetClientHealth(attacker);
		if (cur < 150)   // heals up to 150, never takes anything away
			SetEntityHealth(attacker, cur + heal > 150 ? 150 : cur + heal);
	}
}

// The humans who dealt the least damage since the last check get hurt.
void LC_PunishWorst()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);   // shuffled first, so ties are broken at random
	for (int a = 1; a < n; a++)      // then sorted by damage dealt, lowest first
	{
		int c = list[a], b = a - 1;
		while (b >= 0 && g_LcDealt[list[b]] > g_LcDealt[c])
		{
			list[b + 1] = list[b];
			b--;
		}
		list[b + 1] = c;
	}
	int hurt = g_LcWorstCount < n ? g_LcWorstCount : n - 1;   // never everyone
	for (int k = 0; k < hurt; k++)
	{
		PrintToChatAll(LC_TAG ... "%N got hurt for being a bad defender (%d damage)!", list[k], g_LcDealt[list[k]]);
		HurtPlayer(list[k], g_LcWorstDamage);
	}
	for (int i = 1; i <= MaxClients; i++)
		g_LcDealt[i] = 0;
}

void LC_Tick()
{
	if (!g_LcOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (g_LcMode != LC_DRAIN)
	{
		if (g_LcWorstNext == 0.0)
			g_LcWorstNext = now + float(g_LcWorstEvery);
		if (now >= g_LcWorstNext)
		{
			LC_PunishWorst();
			g_LcWorstNext = now + float(g_LcWorstEvery);
		}
		if (g_LcMode == LC_WORST)
		{
			int left = RoundToCeil(g_LcWorstNext - now);
			for (int i = 1; i <= MaxClients; i++)
			{
				if (!IsHuman(i) || IsFakeClient(i))
					continue;
				SetHudTextParams(-1.0, 0.84, 1.1, 255, 200, 80, 255, 0, 0.0, 0.0, 0.0);
				EM_ShowHud(i, g_HudLeech, "Worst defenders get hurt in %d s - your damage: %d", left, g_LcDealt[i]);
			}
			return;
		}
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i))
			continue;
		bool feeding = g_LcLastHit[i] > 0.0 && now - g_LcLastHit[i] < float(g_LcGrace);
		if (!IsFakeClient(i))
		{
			SetHudTextParams(-1.0, 0.84, 1.1, feeding ? 120 : 255, feeding ? 255 : 80, feeding ? 120 : 80, 255, 0, 0.0, 0.0, 0.0);
			if (feeding)
				EM_ShowHud(i, g_HudLeech, "Leech: fed (%d s)", RoundToCeil(float(g_LcGrace) - (now - g_LcLastHit[i])));
			else
				EM_ShowHud(i, g_HudLeech, "LEECH: hurt a zombie to stop the drain (-%d HP/s)", g_LcDrain);
		}
		if (!feeding)
			HurtPlayer(i, g_LcDrain);
	}
}

// ---------------------------------------------------------------- menu

void LCMenu(int client)
{
	Menu menu = new Menu(LCHandler);
	char line[64];
	menu.SetTitle(g_LcOn ? "Leech - ON\nStarts when the zombies come\n " : "Leech - OFF\n ");
	menu.AddItem("toggle", g_LcOn ? "Turn Leech OFF" : "Turn Leech ON");
	Format(line, sizeof(line), "Mode: %s", g_LcModeNames[g_LcMode]);
	menu.AddItem("mode", line);
	Format(line, sizeof(line), "Worst defenders checked every: %d s", g_LcWorstEvery);
	menu.AddItem("wevery", line, g_LcMode != LC_DRAIN ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Worst defenders hurt: %d", g_LcWorstCount);
	menu.AddItem("wcount", line, g_LcMode != LC_DRAIN ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Worst defender damage: %d", g_LcWorstDamage);
	menu.AddItem("wdamage", line, g_LcMode != LC_DRAIN ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Drain: -%d HP/s", g_LcDrain);
	menu.AddItem("drain", line);
	Format(line, sizeof(line), "Hurting a zombie stops it for: %d s", g_LcGrace);
	menu.AddItem("grace", line);
	if (g_LcHeal == 0)
		strcopy(line, sizeof(line), "Heal from damage: off");
	else
		Format(line, sizeof(line), "Heal from damage: +%d HP per 100 dealt", g_LcHeal);
	menu.AddItem("heal", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int LCHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		ModeBack(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "toggle"))
		{
			LC_Set(!g_LcOn);
			PrintToChatAll(LC_TAG ... "%N turned Leech %s.", client, g_LcOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned leech %s", client, g_LcOn ? "on" : "off");
		}
		else if (StrEqual(info, "mode"))
		{
			g_LcMode = (g_LcMode + 1) % LC_MODES;
			g_LcWorstNext = 0.0;
		}
		else if (StrEqual(info, "wevery"))
			g_LcWorstEvery = NextInt(g_LcWorstEverySteps, sizeof(g_LcWorstEverySteps), g_LcWorstEvery);
		else if (StrEqual(info, "wcount"))
			g_LcWorstCount = NextInt(g_LcWorstCountSteps, sizeof(g_LcWorstCountSteps), g_LcWorstCount);
		else if (StrEqual(info, "wdamage"))
			g_LcWorstDamage = NextInt(g_LcWorstDamageSteps, sizeof(g_LcWorstDamageSteps), g_LcWorstDamage);
		else if (StrEqual(info, "drain"))
			g_LcDrain = NextInt(g_LcDrainSteps, sizeof(g_LcDrainSteps), g_LcDrain);
		else if (StrEqual(info, "grace"))
			g_LcGrace = NextInt(g_LcGraceSteps, sizeof(g_LcGraceSteps), g_LcGrace);
		else if (StrEqual(info, "heal"))
			g_LcHeal = NextInt(g_LcHealSteps, sizeof(g_LcHealSteps), g_LcHeal);
		LCMenu(client);
	}
	return 0;
}
