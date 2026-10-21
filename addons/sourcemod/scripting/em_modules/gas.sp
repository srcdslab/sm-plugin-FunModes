// Toxic Gas module of eventmodes.sp.
// modes.sp calls TG_Check (every 0.2 s), TG_Tick (every second), TG_RoundStart and TG_Stop.
//
// Once the zombies are out, every N seconds green poison clouds appear where random humans are
// standing and hang there for a while. Anyone inside loses health and sees a green tint.

#if defined _em_gas_included
 #endinput
#endif
#define _em_gas_included

#define TG_TAG "\x07" ... "80FF40[Toxic Gas]\x01 "   // kept apart: \x would eat the hex digits
#define TG_MAX 8

int g_TgEverySteps[] = { 20, 30, 45, 60, 90 };
int g_TgCountSteps[] = { 1, 2, 3, 5, 8 };
int g_TgLastSteps[] = { 10, 15, 20, 30 };
float g_TgRadiusSteps[] = { 150.0, 200.0, 300.0, 400.0 };
int g_TgDamageSteps[] = { 3, 5, 10, 20 };   // per second
int g_TgColor[4] = { 128, 255, 64, 255 };

bool g_TgOn;
int g_TgEvery = 45;
int g_TgCount = 2;
int g_TgLast = 15;
float g_TgRadius = 200.0;
int g_TgDamage = 5;
bool g_TgZombies;
float g_TgNext;

float g_TgPos[TG_MAX][3];
float g_TgEnds[TG_MAX];     // 0 = slot free
float g_TgOwed[MAXPLAYERS + 1];

bool TG_IsOn()
{
	return g_TgOn;
}

void TG_Clear()
{
	g_TgNext = 0.0;
	for (int k = 0; k < TG_MAX; k++)
		g_TgEnds[k] = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_TgOwed[i] = 0.0;
}

void TG_Stop()
{
	g_TgOn = false;
	TG_Clear();
}

void TG_Set(bool on)
{
	TG_Stop();
	g_TgOn = on;
}

void TG_RoundStart()
{
	TG_Clear();
	if (g_TgOn)
		PrintToChatAll(TG_TAG ... "Toxic Gas is on: stay out of the green clouds!");
}

void TG_Release()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	float now = GetGameTime();
	int made = 0;
	for (int k = 0; k < TG_MAX && made < g_TgCount && made < n; k++)
	{
		if (g_TgEnds[k] > now)
			continue;
		GetClientAbsOrigin(list[made], g_TgPos[k]);
		g_TgEnds[k] = now + float(g_TgLast);
		made++;
	}
	if (made > 0)
	{
		PrintToChatAll(TG_TAG ... "Toxic gas is leaking - get out of the green clouds!");
		EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 55);
	}
}

void TG_Check()
{
	if (!g_TgOn || !g_RoundLive)
		return;
	float now = GetGameTime(), pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_TgZombies))
			continue;
		GetClientAbsOrigin(i, pos);
		bool inside = false;
		for (int k = 0; k < TG_MAX && !inside; k++)
			inside = g_TgEnds[k] > now && GetVectorDistance(pos, g_TgPos[k]) <= g_TgRadius;
		if (!inside)
			continue;
		g_TgOwed[i] += float(g_TgDamage) * 0.2;
		int whole = RoundToFloor(g_TgOwed[i]);
		if (whole > 0)
		{
			g_TgOwed[i] -= float(whole);
			if (!IsFakeClient(i))
				ScreenTint(i, 60, 200, 40, 90, 0.2, 0.4);
			HurtPlayer(i, whole);
		}
	}
}

void TG_Tick()
{
	if (!g_TgOn || !g_RoundLive)
		return;
	float now = GetGameTime();
	for (int k = 0; k < TG_MAX; k++)
	{
		if (g_TgEnds[k] <= now)
			continue;
		// A few stacked rings make the cloud look like a puffy dome.
		RingAt(g_TgPos[k], g_TgRadius, g_TgRadius * 0.9, 1.0, g_TgColor, 20.0);
		float up[3];
		up = g_TgPos[k];
		up[2] += 40.0;
		RingAt(up, g_TgRadius * 0.8, g_TgRadius * 0.7, 1.0, g_TgColor, 20.0);
		up[2] += 40.0;
		RingAt(up, g_TgRadius * 0.5, g_TgRadius * 0.4, 1.0, g_TgColor, 20.0);
	}
	if (HazardDue(g_TgOn, g_TgNext, g_TgEvery))
		TG_Release();
}

// ---------------------------------------------------------------- menu

void TGMenu(int client)
{
	Menu menu = new Menu(TGHandler);
	char line[64];
	menu.SetTitle(g_TgOn ? "Toxic Gas - ON\nStarts when the zombies come\n " : "Toxic Gas - OFF\n ");
	menu.AddItem("toggle", g_TgOn ? "Turn Toxic Gas OFF" : "Turn Toxic Gas ON");
	menu.AddItem("now", "Release gas now", (g_TgOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_TgEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Clouds each time: %d", g_TgCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Clouds last: %d s", g_TgLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Cloud size: %d", RoundToNearest(g_TgRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Poison: -%d HP/s", g_TgDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Hurts zombies too: %s", g_TgZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int TGHandler(Menu menu, MenuAction action, int client, int item)
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
			TG_Set(!g_TgOn);
			PrintToChatAll(TG_TAG ... "%N turned Toxic Gas %s.", client, g_TgOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned toxic gas %s", client, g_TgOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			TG_Release();
		else if (StrEqual(info, "every"))
			g_TgEvery = NextInt(g_TgEverySteps, sizeof(g_TgEverySteps), g_TgEvery);
		else if (StrEqual(info, "count"))
			g_TgCount = NextInt(g_TgCountSteps, sizeof(g_TgCountSteps), g_TgCount);
		else if (StrEqual(info, "last"))
			g_TgLast = NextInt(g_TgLastSteps, sizeof(g_TgLastSteps), g_TgLast);
		else if (StrEqual(info, "radius"))
			g_TgRadius = NextFloat(g_TgRadiusSteps, sizeof(g_TgRadiusSteps), g_TgRadius);
		else if (StrEqual(info, "damage"))
			g_TgDamage = NextInt(g_TgDamageSteps, sizeof(g_TgDamageSteps), g_TgDamage);
		else if (StrEqual(info, "zombies"))
			g_TgZombies = !g_TgZombies;
		TGMenu(client);
	}
	return 0;
}
