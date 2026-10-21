// Wind Gusts module of eventmodes.sp.
// eventmodes.sp calls WG_PluginStart; modes.sp calls WG_Check (every 0.2 s), WG_Tick (every second),
// WG_RoundStart and WG_Stop.
//
// Once the zombies are out, every N seconds a storm blows for a while: a steady push in one direction
// that swings round every few seconds. Brutal on narrow ZE paths.

#if defined _em_wind_included
 #endinput
#endif
#define _em_wind_included

#define WG_TAG "\x07" ... "C0E0E0[Wind]\x01 "   // kept apart: \x would eat the hex digits

char g_WgLevelNames[][] = { "breeze", "windy", "strong wind", "storm", "hurricane" };
float g_WgLevelPush[] = { 15.0, 30.0, 50.0, 80.0, 120.0 };   // speed added every 0.2 s
int g_WgEverySteps[] = { 0, 30, 45, 60, 90 };   // 0 = all the time
int g_WgLastSteps[] = { 5, 10, 15, 20 };
int g_WgTurnSteps[] = { 2, 3, 5, 8 };

bool g_WgOn;
int g_WgEvery = 45;
int g_WgLast = 10;
int g_WgLevel = 2;
int g_WgTurn = 3;           // seconds between direction changes
bool g_WgEveryone = true;
bool g_WgActive;
float g_WgNext;
float g_WgEnds;
float g_WgTurnAt;
float g_WgAngle;            // radians, 0 = east
Handle g_HudWind;

void WG_PluginStart()
{
	g_HudWind = EM_HudSync();
}

bool WG_IsOn()
{
	return g_WgOn;
}

void WG_Stop()
{
	g_WgOn = false;
	g_WgActive = false;
	g_WgNext = 0.0;
}

void WG_Set(bool on)
{
	WG_Stop();
	g_WgOn = on;
}

void WG_RoundStart()
{
	g_WgActive = false;
	g_WgNext = 0.0;
	if (g_WgOn)
		PrintToChatAll(WG_TAG ... "Wind is on: hold on tight when the storm comes!");
}

void WG_Start()
{
	g_WgActive = true;
	g_WgEnds = GetGameTime() + float(g_WgLast);
	g_WgTurnAt = 0.0;
	if (g_WgEvery > 0)
	{
		PrintToChatAll(WG_TAG ... "A %s is blowing for %d seconds!", g_WgLevelNames[g_WgLevel], g_WgLast);
		PrintCenterTextAll("WIND!");
	}
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 90);
}

// Compass name for the way the wind pushes (Source: +x east, +y north).
void WG_Direction(char[] buf, int len)
{
	char names[][] = { "east", "north-east", "north", "north-west", "west", "south-west", "south", "south-east" };
	int sector = RoundToNearest(g_WgAngle / (3.14159 / 4.0)) % 8;
	if (sector < 0)
		sector += 8;
	strcopy(buf, len, names[sector]);
}

void WG_Check()
{
	if (!g_WgOn || !g_WgActive || !g_RoundLive)
		return;
	float now = GetGameTime();
	if (now >= g_WgTurnAt)
	{
		g_WgAngle = GetRandomFloat(0.0, 6.2832);
		g_WgTurnAt = now + float(g_WgTurn);
	}
	float push = g_WgLevelPush[g_WgLevel];
	float x = Cosine(g_WgAngle) * push, y = Sine(g_WgAngle) * push;
	for (int i = 1; i <= MaxClients; i++)
		if (HazardHits(i, g_WgEveryone))
			Shove(i, x, y, 0.0);
}

void WG_Tick()
{
	if (!g_WgOn || !g_RoundLive)
		return;
	if (g_WgEvery == 0)
	{
		if (!g_WgActive && g_ZombiesSeen)
			WG_Start();
	}
	else if (g_WgActive && GetGameTime() >= g_WgEnds)
	{
		g_WgActive = false;
		PrintCenterTextAll("The wind dies down");
	}
	else if (!g_WgActive && HazardDue(g_WgOn, g_WgNext, g_WgEvery))
		WG_Start();

	if (!g_WgActive)
		return;
	char dir[16];
	WG_Direction(dir, sizeof(dir));
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		SetHudTextParams(-1.0, 0.48, 1.1, 200, 230, 230, 255, 0, 0.0, 0.0, 0.0);
		EM_ShowHud(i, g_HudWind, "%s blowing %s", g_WgLevelNames[g_WgLevel], dir);
	}
}

// ---------------------------------------------------------------- menu

void WGMenu(int client)
{
	Menu menu = new Menu(WGHandler);
	char line[64];
	menu.SetTitle(g_WgOn ? "Wind Gusts - ON\nStarts when the zombies come\n " : "Wind Gusts - OFF\n ");
	menu.AddItem("toggle", g_WgOn ? "Turn Wind OFF" : "Turn Wind ON");
	menu.AddItem("now", "Wind now", (g_WgOn && g_RoundLive && !g_WgActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	if (g_WgEvery == 0)
		strcopy(line, sizeof(line), "Storms: all the time");
	else
		Format(line, sizeof(line), "Storms: every %d s", g_WgEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Storm lasts: %d s", g_WgLast);
	menu.AddItem("last", line, g_WgEvery > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Strength: %s", g_WgLevelNames[g_WgLevel]);
	menu.AddItem("level", line);
	Format(line, sizeof(line), "Changes direction every: %d s", g_WgTurn);
	menu.AddItem("turn", line);
	Format(line, sizeof(line), "Who gets pushed: %s", g_WgEveryone ? "everyone" : "humans only");
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int WGHandler(Menu menu, MenuAction action, int client, int item)
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
			WG_Set(!g_WgOn);
			PrintToChatAll(WG_TAG ... "%N turned Wind %s.", client, g_WgOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned wind gusts %s", client, g_WgOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			WG_Start();
		else if (StrEqual(info, "every"))
		{
			int next = g_WgEverySteps[0];
			for (int i = 0; i < sizeof(g_WgEverySteps); i++)
			{
				if (g_WgEverySteps[i] > g_WgEvery)
				{
					next = g_WgEverySteps[i];
					break;
				}
			}
			g_WgEvery = next;
			g_WgActive = false;
			g_WgNext = 0.0;
		}
		else if (StrEqual(info, "last"))
			g_WgLast = NextInt(g_WgLastSteps, sizeof(g_WgLastSteps), g_WgLast);
		else if (StrEqual(info, "level"))
			g_WgLevel = (g_WgLevel + 1) % sizeof(g_WgLevelNames);
		else if (StrEqual(info, "turn"))
			g_WgTurn = NextInt(g_WgTurnSteps, sizeof(g_WgTurnSteps), g_WgTurn);
		else if (StrEqual(info, "who"))
			g_WgEveryone = !g_WgEveryone;
		WGMenu(client);
	}
	return 0;
}
