// Floor is Lava module of eventmodes.sp.
// eventmodes.sp calls FL_PluginStart; modes.sp calls FL_Check (every 0.2 s), FL_Tick (every second),
// FL_RoundStart and FL_Stop.
//
// Once the zombies are out, anyone who stays within a small spot for too long starts burning until they
// move. Riding an elevator or platform counts as moving (it's about the position, not the keys).

#if defined _em_lava_included
 #endinput
#endif
#define _em_lava_included

#define FL_TAG    "\x07" ... "FF6020[Floor is Lava]\x01 "   // kept apart: \x would eat the hex digits
#define FL_SPOT   64.0   // moving less than this counts as standing still

int g_FlAfterSteps[] = { 2, 3, 5, 8, 12 };
int g_FlDamageSteps[] = { 5, 10, 20, 50, 1000 };   // per second, 1000 = slay

bool g_FlOn;
int g_FlAfter = 3;          // seconds still before it burns
int g_FlDamage = 10;
bool g_FlEveryone;          // zombies burn too (else humans only)
float g_FlAnchor[MAXPLAYERS + 1][3];
float g_FlStillSince[MAXPLAYERS + 1];   // 0 = not tracked yet
float g_FlOwed[MAXPLAYERS + 1];
Handle g_HudLava;

void FL_PluginStart()
{
	g_HudLava = EM_HudSync();
}

bool FL_IsOn()
{
	return g_FlOn;
}

void FL_Clear()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_FlStillSince[i] = 0.0;
		g_FlOwed[i] = 0.0;
	}
}

void FL_Stop()
{
	g_FlOn = false;
	FL_Clear();
}

void FL_RoundStart()
{
	FL_Clear();
	if (g_FlOn)
		PrintToChatAll(FL_TAG ... "The floor is lava: once the zombies come, don't stand still for more than %d seconds!", g_FlAfter);
}

bool FL_Affects(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return false;
	int team = GetClientTeam(client);
	return team == CS_TEAM_CT || (g_FlEveryone && team == CS_TEAM_T);
}

void FL_Check()
{
	if (!g_FlOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime(), pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!FL_Affects(i))
		{
			g_FlStillSince[i] = 0.0;
			continue;
		}
		GetClientAbsOrigin(i, pos);
		if (g_FlStillSince[i] == 0.0 || GetVectorDistance(pos, g_FlAnchor[i]) > FL_SPOT)
		{
			g_FlAnchor[i] = pos;
			g_FlStillSince[i] = now;
			g_FlOwed[i] = 0.0;
			continue;
		}
		if (now - g_FlStillSince[i] < float(g_FlAfter))
			continue;
		if (g_FlDamage >= 1000)
		{
			PrintToChatAll(FL_TAG ... "%N stood still too long and melted!", i);
			ForcePlayerSuicide(i);
			continue;
		}
		g_FlOwed[i] += float(g_FlDamage) * 0.2;   // this runs every 0.2 s
		int whole = RoundToFloor(g_FlOwed[i]);
		if (whole > 0)
		{
			g_FlOwed[i] -= float(whole);
			HurtPlayer(i, whole);
		}
	}
}

void FL_Tick()
{
	if (!g_FlOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!FL_Affects(i) || IsFakeClient(i) || g_FlStillSince[i] == 0.0)
			continue;
		float still = now - g_FlStillSince[i];
		if (still >= float(g_FlAfter))
		{
			SetHudTextParams(-1.0, 0.52, 1.1, 255, 80, 20, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudLava, "THE FLOOR IS LAVA - MOVE! (-%d HP/s)", g_FlDamage >= 1000 ? 999 : g_FlDamage);
		}
		else if (still >= float(g_FlAfter) - 1.5)
		{
			SetHudTextParams(-1.0, 0.52, 1.1, 255, 200, 40, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudLava, "Keep moving...");
		}
	}
}

// ---------------------------------------------------------------- menu

void FLMenu(int client)
{
	Menu menu = new Menu(FLHandler);
	char line[64];
	menu.SetTitle(g_FlOn ? "Floor is Lava - ON\nStarts when the zombies come\n " : "Floor is Lava - OFF\n ");
	menu.AddItem("toggle", g_FlOn ? "Turn Floor is Lava OFF" : "Turn Floor is Lava ON");
	Format(line, sizeof(line), "Burns after standing still: %d s", g_FlAfter);
	menu.AddItem("after", line);
	if (g_FlDamage >= 1000)
		strcopy(line, sizeof(line), "Burning: instant kill");
	else
		Format(line, sizeof(line), "Burning: -%d HP/s", g_FlDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Who burns: %s", g_FlEveryone ? "everyone" : "humans only");
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int FLHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_FlOn;
			FL_Stop();
			g_FlOn = on;
			PrintToChatAll(FL_TAG ... "%N turned Floor is Lava %s.", client, on ? "ON - keep moving" : "OFF");
			LogAction(client, -1, "\"%L\" turned floor is lava %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "after"))
			g_FlAfter = NextInt(g_FlAfterSteps, sizeof(g_FlAfterSteps), g_FlAfter);
		else if (StrEqual(info, "damage"))
			g_FlDamage = NextInt(g_FlDamageSteps, sizeof(g_FlDamageSteps), g_FlDamage);
		else if (StrEqual(info, "who"))
			g_FlEveryone = !g_FlEveryone;
		FLMenu(client);
	}
	return 0;
}
