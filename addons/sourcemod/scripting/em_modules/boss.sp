// Boss Zombie module of eventmodes.sp.
// eventmodes.sp calls BZ_PluginStart; modes.sp calls BZ_Check (every 0.2 s), BZ_Tick (every second),
// BZ_RoundStart, BZ_RoundEnd and BZ_Stop.
//
// Some time after the zombies come, one random zombie becomes the boss: huge health (a base amount
// plus extra per living human), extra speed, a red glow and ring, and a health bar on everyone's
// screen. Killing it rewards the humans. One boss per round (admins can make another).

#if defined _em_boss_included
 #endinput
#endif
#define _em_boss_included

#define BZ_TAG "\x07" ... "FF2020[Boss Zombie]\x01 "   // kept apart: \x would eat the hex digits
#define BZ_BAR 25                                      // health bar width

enum { BZ_R_NONE = 0, BZ_R_HEAL, BZ_R_HE, BZ_REWARDS }
char g_BzRewardNames[][] = { "nothing", "+50 HP to every human", "HE grenade to every human" };
int g_BzHealthSteps[] = { 10000, 20000, 50000, 100000, 200000 };
int g_BzPerHumanSteps[] = { 0, 500, 1000, 2500, 5000 };
float g_BzSpeedSteps[] = { 1.0, 1.15, 1.3, 1.5 };
int g_BzDelaySteps[] = { 0, 15, 30, 60 };
int g_BzColor[4] = { 255, 30, 30, 255 };

bool g_BzOn;
int g_BzHealth = 20000;     // base health
int g_BzPerHuman = 1000;    // extra health per living human when it spawns
float g_BzSpeed = 1.3;
int g_BzDelay = 15;         // seconds after the first zombie
int g_BzReward = BZ_R_HEAL;

int g_Boss;                 // userid, 0 = none
int g_BossMax;
bool g_BossDone;            // a boss already came this round
float g_BossAt;             // when the boss appears, 0 = not planned yet
Handle g_HudBoss;

void BZ_PluginStart()
{
	g_HudBoss = EM_HudSync();
}

bool BZ_IsOn()
{
	return g_BzOn;
}

// The boss's speed, stacked with other modes by physics.sp.
float BZ_SpeedMult(int client)
{
	if (!g_BzOn || g_Boss == 0 || GetClientUserId(client) != g_Boss || GetClientTeam(client) != CS_TEAM_T)
		return 1.0;
	return g_BzSpeed;
}

// The boss stops being the boss (speed and colour back to normal).
void BZ_Release()
{
	int b = GetClientOfUserId(g_Boss);
	if (b != 0 && IsClientInGame(b))
	{
		int r, g, bl, a;
		GetEntityRenderColor(b, r, g, bl, a);
		SetEntityRenderColor(b, 255, 255, 255, a);
	}
	g_Boss = 0;
}

void BZ_Stop()
{
	BZ_Release();
	g_BzOn = false;
	g_BossDone = false;
	g_BossAt = 0.0;
}

void BZ_RoundStart()
{
	g_Boss = 0;
	g_BossDone = false;
	g_BossAt = 0.0;
	if (g_BzOn)
		PrintToChatAll(BZ_TAG ... "Boss Zombie is on: a boss rises %s after the zombies come!", g_BzDelay == 0 ? "right" : "soon");
}

void BZ_RoundEnd()
{
	BZ_Release();
}

int RandomZombie()
{
	int list[MAXPLAYERS + 1], count = 0;
	for (int pass = 0; pass < 2 && count == 0; pass++)   // real players before bots
	{
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_T)
				continue;
			if (pass == 0 && IsFakeClient(i))
				continue;
			list[count++] = i;
		}
	}
	return count == 0 ? 0 : list[GetRandomInt(0, count - 1)];
}

void BZ_Make(int z)
{
	if (z == 0)
		return;
	BZ_Release();
	int humans = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (IsHuman(i))
			humans++;
	g_Boss = GetClientUserId(z);
	g_BossDone = true;
	g_BossMax = g_BzHealth + g_BzPerHuman * humans;
	SetEntityHealth(z, g_BossMax);   // speed comes from BZ_SpeedMult (physics.sp)
	int r, g, b, a;
	GetEntityRenderColor(z, r, g, b, a);
	SetEntityRenderColor(z, 255, 60, 60, a);

	PrintToChatAll(BZ_TAG ... "\x07" ... "FF2020%N\x01 has become the BOSS ZOMBIE with %d health! Take it down!", z, g_BossMax);
	PrintCenterTextAll("%N IS THE BOSS ZOMBIE!", z);
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 40);
}

void BZ_Defeated(int b)
{
	g_Boss = 0;
	PrintToChatAll(BZ_TAG ... "The boss \x07" ... "FF2020%N\x01 has been DEFEATED!%s", b,
		g_BzReward == BZ_R_HEAL ? " Every human gets +50 HP." : (g_BzReward == BZ_R_HE ? " Every human gets an HE grenade." : ""));
	PrintCenterTextAll("THE BOSS IS DEFEATED!");
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i))
			continue;
		if (g_BzReward == BZ_R_HEAL)
			SetEntityHealth(i, GetClientHealth(i) + 50);
		else if (g_BzReward == BZ_R_HE)
			GivePlayerItem(i, "weapon_hegrenade");
	}
}

void BZ_Check(bool zombiesNow)
{
	if (!g_BzOn || !g_RoundLive)
		return;

	if (g_Boss != 0)
	{
		int b = GetClientOfUserId(g_Boss);
		if (b == 0)
		{
			g_Boss = 0;
			PrintToChatAll(BZ_TAG ... "The boss left the server.");
		}
		else if (!IsPlayerAlive(b))
			BZ_Defeated(b);
		else if (GetClientTeam(b) != CS_TEAM_T)
		{
			BZ_Release();   // cured / moved team
			PrintToChatAll(BZ_TAG ... "The boss is no longer a zombie.");
		}
		return;
	}
	if (g_BossDone || !zombiesNow)
		return;
	float now = GetGameTime();
	if (g_BossAt == 0.0)
		g_BossAt = now + float(g_BzDelay);
	if (now >= g_BossAt)
		BZ_Make(RandomZombie());
}

void BZ_Tick()
{
	if (!g_BzOn || g_Boss == 0)
		return;
	int b = GetClientOfUserId(g_Boss);
	if (b == 0 || !IsPlayerAlive(b))
		return;

	Ring(b, g_BzColor, 50.0);

	int hp = GetClientHealth(b);
	int filled = g_BossMax > 0 ? hp * BZ_BAR / g_BossMax : 0;
	if (filled > BZ_BAR)
		filled = BZ_BAR;
	char bar[BZ_BAR + 1];
	for (int k = 0; k < BZ_BAR; k++)
		bar[k] = k < filled ? '|' : '.';
	bar[BZ_BAR] = '\0';
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		SetHudTextParams(-1.0, 0.05, 1.1, 255, 40, 40, 255, 0, 0.0, 0.0, 0.0);
		EM_ShowHud(i, g_HudBoss, "BOSS: %N\n[%s] %d / %d", b, bar, hp, g_BossMax);
	}
}

// ---------------------------------------------------------------- menu

void BZMenu(int client)
{
	Menu menu = new Menu(BZHandler);
	char title[128], line[64];
	int b = GetClientOfUserId(g_Boss);
	if (!g_BzOn)
		strcopy(title, sizeof(title), "Boss Zombie - OFF\n ");
	else if (b != 0)
		Format(title, sizeof(title), "Boss Zombie - ON\nBoss: %N (%d HP)\n ", b, GetClientHealth(b));
	else
		strcopy(title, sizeof(title), g_BossDone ? "Boss Zombie - ON\nThis round's boss is gone\n " : "Boss Zombie - ON\nBoss comes after the zombies\n ");
	menu.SetTitle(title);

	menu.AddItem("toggle", g_BzOn ? "Turn Boss Zombie OFF" : "Turn Boss Zombie ON");
	menu.AddItem("now", "Make a random zombie the boss now", (g_BzOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Base health: %d", g_BzHealth);
	menu.AddItem("health", line);
	Format(line, sizeof(line), "Extra health per human: %d", g_BzPerHuman);
	menu.AddItem("per", line);
	Format(line, sizeof(line), "Speed: x%.2f", g_BzSpeed);
	menu.AddItem("speed", line);
	if (g_BzDelay == 0)
		strcopy(line, sizeof(line), "Appears: with the first zombie");
	else
		Format(line, sizeof(line), "Appears: %d s after the first zombie", g_BzDelay);
	menu.AddItem("delay", line);
	Format(line, sizeof(line), "Reward when killed: %s", g_BzRewardNames[g_BzReward]);
	menu.AddItem("reward", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BZHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_BzOn;
			BZ_Stop();
			g_BzOn = on;
			PrintToChatAll(BZ_TAG ... "%N turned Boss Zombie %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned boss zombie %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
		{
			int z = RandomZombie();
			if (z == 0)
				PrintToChat(client, BZ_TAG ... "There are no living zombies yet.");
			else
				BZ_Make(z);
		}
		else if (StrEqual(info, "health"))
			g_BzHealth = NextInt(g_BzHealthSteps, sizeof(g_BzHealthSteps), g_BzHealth);
		else if (StrEqual(info, "per"))
			g_BzPerHuman = NextInt(g_BzPerHumanSteps, sizeof(g_BzPerHumanSteps), g_BzPerHuman);
		else if (StrEqual(info, "speed"))
		{
			float next = g_BzSpeedSteps[0];
			for (int i = 0; i < sizeof(g_BzSpeedSteps); i++)
			{
				if (g_BzSpeedSteps[i] > g_BzSpeed + 0.01)
				{
					next = g_BzSpeedSteps[i];
					break;
				}
			}
			g_BzSpeed = next;
		}
		else if (StrEqual(info, "delay"))
			g_BzDelay = NextInt(g_BzDelaySteps, sizeof(g_BzDelaySteps), g_BzDelay);
		else if (StrEqual(info, "reward"))
			g_BzReward = (g_BzReward + 1) % BZ_REWARDS;
		BZMenu(client);
	}
	return 0;
}
