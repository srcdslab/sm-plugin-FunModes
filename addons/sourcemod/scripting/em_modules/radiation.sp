// Radiation module of eventmodes.sp.
// modes.sp calls RD_Check (every 0.2 s), RD_Tick (every second), RD_RoundStart and RD_Stop.
//
// Once the zombies are out, a spot where a human camps too long turns radioactive and stays that way
// for the rest of the round: a pulsing yellow-green zone that hurts anyone standing in it.

#if defined _em_radiation_included
 #endinput
#endif
#define _em_radiation_included

#define RD_TAG   "\x07" ... "D0FF30[Radiation]\x01 "   // kept apart: \x would eat the hex digits
#define RD_MAX   12
#define RD_CAMP  150.0   // staying within this counts as camping

int g_RdAfterSteps[] = { 15, 20, 30, 45, 60 };
float g_RdRadiusSteps[] = { 150.0, 200.0, 300.0 };
int g_RdDamageSteps[] = { 3, 5, 10, 20 };   // per second
int g_RdMaxSteps[] = { 3, 5, 8, 12 };
int g_RdColor[4] = { 208, 255, 48, 255 };

bool g_RdOn;
int g_RdAfter = 30;         // camping seconds before a spot turns radioactive
float g_RdRadius = 200.0;
int g_RdDamage = 5;
int g_RdMax = 5;            // zones at most per round
bool g_RdZombies;

float g_RdZone[RD_MAX][3];
int g_RdZones;
float g_RdAnchor[MAXPLAYERS + 1][3];
float g_RdSince[MAXPLAYERS + 1];   // 0 = not tracked yet
float g_RdOwed[MAXPLAYERS + 1];

bool RD_IsOn()
{
	return g_RdOn;
}

void RD_Clear()
{
	g_RdZones = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_RdSince[i] = 0.0;
		g_RdOwed[i] = 0.0;
	}
}

void RD_Stop()
{
	g_RdOn = false;
	RD_Clear();
}

void RD_Set(bool on)
{
	RD_Stop();
	g_RdOn = on;
}

void RD_RoundStart()
{
	RD_Clear();
	if (g_RdOn)
		PrintToChatAll(RD_TAG ... "Radiation is on: camp in one spot too long and it turns radioactive!");
}

bool RD_InZone(const float pos[3])
{
	for (int z = 0; z < g_RdZones; z++)
		if (GetVectorDistance(pos, g_RdZone[z]) <= g_RdRadius)
			return true;
	return false;
}

void RD_Check()
{
	if (!g_RdOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime(), pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_RdZombies))
		{
			g_RdSince[i] = 0.0;
			continue;
		}
		GetClientAbsOrigin(i, pos);

		// Hurt inside existing zones.
		if (RD_InZone(pos))
		{
			g_RdOwed[i] += float(g_RdDamage) * 0.2;
			int whole = RoundToFloor(g_RdOwed[i]);
			if (whole > 0)
			{
				g_RdOwed[i] -= float(whole);
				PrintCenterText(i, "RADIATION! Get out!");
				HurtPlayer(i, whole);
			}
		}

		// Only humans' camping makes new zones.
		if (GetClientTeam(i) != CS_TEAM_CT)
			continue;
		if (g_RdSince[i] == 0.0 || GetVectorDistance(pos, g_RdAnchor[i]) > RD_CAMP)
		{
			g_RdAnchor[i] = pos;
			g_RdSince[i] = now;
			continue;
		}
		if (now - g_RdSince[i] >= float(g_RdAfter) && g_RdZones < g_RdMax && g_RdZones < RD_MAX && !RD_InZone(g_RdAnchor[i]))
		{
			g_RdZone[g_RdZones++] = g_RdAnchor[i];
			g_RdSince[i] = now;
			PrintToChatAll(RD_TAG ... "%N camped too long - that spot is now RADIOACTIVE!", i);
			EmitAmbientSound(BEACON_SOUND, g_RdAnchor[i], SOUND_FROM_WORLD, SNDLEVEL_NORMAL, _, _, 45);
		}
	}
}

void RD_Tick()
{
	if (!g_RdOn || !g_RoundLive)
		return;
	for (int z = 0; z < g_RdZones; z++)
		RingAt(g_RdZone[z], g_RdRadius, g_RdRadius * 0.85, 1.0, g_RdColor, 10.0);
}

// ---------------------------------------------------------------- menu

void RDMenu(int client)
{
	Menu menu = new Menu(RDHandler);
	char title[96], line[64];
	Format(title, sizeof(title), "Radiation - %s\n%d radioactive zone%s this round\n ", g_RdOn ? "ON" : "OFF", g_RdZones, g_RdZones == 1 ? "" : "s");
	menu.SetTitle(title);
	menu.AddItem("toggle", g_RdOn ? "Turn Radiation OFF" : "Turn Radiation ON");
	menu.AddItem("clear", "Clear all zones now", g_RdZones > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Spot turns radioactive after: %d s camping", g_RdAfter);
	menu.AddItem("after", line);
	Format(line, sizeof(line), "Zone size: %d", RoundToNearest(g_RdRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Radiation: -%d HP/s", g_RdDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Most zones per round: %d", g_RdMax);
	menu.AddItem("max", line);
	Format(line, sizeof(line), "Hurts zombies too: %s", g_RdZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int RDHandler(Menu menu, MenuAction action, int client, int item)
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
			RD_Set(!g_RdOn);
			PrintToChatAll(RD_TAG ... "%N turned Radiation %s.", client, g_RdOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned radiation %s", client, g_RdOn ? "on" : "off");
		}
		else if (StrEqual(info, "clear"))
			RD_Clear();
		else if (StrEqual(info, "after"))
			g_RdAfter = NextInt(g_RdAfterSteps, sizeof(g_RdAfterSteps), g_RdAfter);
		else if (StrEqual(info, "radius"))
			g_RdRadius = NextFloat(g_RdRadiusSteps, sizeof(g_RdRadiusSteps), g_RdRadius);
		else if (StrEqual(info, "damage"))
			g_RdDamage = NextInt(g_RdDamageSteps, sizeof(g_RdDamageSteps), g_RdDamage);
		else if (StrEqual(info, "max"))
			g_RdMax = NextInt(g_RdMaxSteps, sizeof(g_RdMaxSteps), g_RdMax);
		else if (StrEqual(info, "zombies"))
			g_RdZombies = !g_RdZombies;
		RDMenu(client);
	}
	return 0;
}
