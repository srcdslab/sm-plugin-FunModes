// Quicksand module of eventmodes.sp.
// modes.sp calls QS_Tick (every second), QS_RoundStart and QS_Stop; physics.sp asks QS_SpeedMult.
//
// Once the zombies are out, every N seconds patches of quicksand appear where random humans stand and
// stay for a while. Anyone inside moves at a crawl.

#if defined _em_quicksand_included
 #endinput
#endif
#define _em_quicksand_included

#define QS_TAG "\x07" ... "C09050[Quicksand]\x01 "   // kept apart: \x would eat the hex digits
#define QS_MAX 8

int g_QsEverySteps[] = { 20, 30, 45, 60, 90 };
int g_QsCountSteps[] = { 1, 2, 3, 5, 8 };
int g_QsLastSteps[] = { 10, 15, 20, 30 };
float g_QsRadiusSteps[] = { 120.0, 180.0, 250.0, 350.0 };
float g_QsSlowSteps[] = { 0.15, 0.3, 0.5, 0.7 };
int g_QsColor[4] = { 192, 144, 80, 255 };

bool g_QsOn;
int g_QsEvery = 45;
int g_QsCount = 2;
int g_QsLast = 15;
float g_QsRadius = 180.0;
float g_QsSlow = 0.3;       // speed inside
bool g_QsZombies = true;    // zombies sink too
float g_QsNext;
float g_QsPos[QS_MAX][3];
float g_QsEnds[QS_MAX];

bool QS_IsOn()
{
	return g_QsOn;
}

float QS_SpeedMult(int client)
{
	if (!g_QsOn || !HazardHits(client, g_QsZombies))
		return 1.0;
	float now = GetGameTime(), pos[3];
	GetClientAbsOrigin(client, pos);
	for (int k = 0; k < QS_MAX; k++)
		if (g_QsEnds[k] > now && GetVectorDistance(pos, g_QsPos[k]) <= g_QsRadius)
			return g_QsSlow;
	return 1.0;
}

void QS_Clear()
{
	g_QsNext = 0.0;
	for (int k = 0; k < QS_MAX; k++)
		g_QsEnds[k] = 0.0;
}

void QS_Stop()
{
	g_QsOn = false;
	QS_Clear();
}

void QS_Set(bool on)
{
	QS_Stop();
	g_QsOn = on;
}

void QS_RoundStart()
{
	QS_Clear();
	if (g_QsOn)
		PrintToChatAll(QS_TAG ... "Quicksand is on: avoid the brown patches!");
}

void QS_Spawn()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	float now = GetGameTime();
	int made = 0;
	for (int k = 0; k < QS_MAX && made < g_QsCount && made < n; k++)
	{
		if (g_QsEnds[k] > now)
			continue;
		GetClientAbsOrigin(list[made], g_QsPos[k]);
		g_QsEnds[k] = now + float(g_QsLast);
		made++;
	}
	if (made > 0)
		PrintToChatAll(QS_TAG ... "Quicksand! Get out of the brown patches!");
}

void QS_Tick()
{
	if (!g_QsOn || !g_RoundLive)
		return;
	float now = GetGameTime();
	for (int k = 0; k < QS_MAX; k++)
	{
		if (g_QsEnds[k] <= now)
			continue;
		RingAt(g_QsPos[k], g_QsRadius, g_QsRadius * 0.3, 1.0, g_QsColor, 16.0);   // swirling inwards
	}
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && IsPlayerAlive(i) && QS_SpeedMult(i) < 1.0)
			PrintCenterText(i, "QUICKSAND! Get out!");
	if (HazardDue(g_QsOn, g_QsNext, g_QsEvery))
		QS_Spawn();
}

// ---------------------------------------------------------------- menu

void QSMenu(int client)
{
	Menu menu = new Menu(QSHandler);
	char line[64];
	menu.SetTitle(g_QsOn ? "Quicksand - ON\nStarts when the zombies come\n " : "Quicksand - OFF\n ");
	menu.AddItem("toggle", g_QsOn ? "Turn Quicksand OFF" : "Turn Quicksand ON");
	menu.AddItem("now", "Quicksand now", (g_QsOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_QsEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Patches each time: %d", g_QsCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Patches last: %d s", g_QsLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Patch size: %d", RoundToNearest(g_QsRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Speed inside: %d%%", RoundToNearest(g_QsSlow * 100.0));
	menu.AddItem("slow", line);
	Format(line, sizeof(line), "Zombies sink too: %s", g_QsZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int QSHandler(Menu menu, MenuAction action, int client, int item)
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
			QS_Set(!g_QsOn);
			PrintToChatAll(QS_TAG ... "%N turned Quicksand %s.", client, g_QsOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned quicksand %s", client, g_QsOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			QS_Spawn();
		else if (StrEqual(info, "every"))
			g_QsEvery = NextInt(g_QsEverySteps, sizeof(g_QsEverySteps), g_QsEvery);
		else if (StrEqual(info, "count"))
			g_QsCount = NextInt(g_QsCountSteps, sizeof(g_QsCountSteps), g_QsCount);
		else if (StrEqual(info, "last"))
			g_QsLast = NextInt(g_QsLastSteps, sizeof(g_QsLastSteps), g_QsLast);
		else if (StrEqual(info, "radius"))
			g_QsRadius = NextFloat(g_QsRadiusSteps, sizeof(g_QsRadiusSteps), g_QsRadius);
		else if (StrEqual(info, "slow"))
			g_QsSlow = NextStep(g_QsSlowSteps, sizeof(g_QsSlowSteps), g_QsSlow);
		else if (StrEqual(info, "zombies"))
			g_QsZombies = !g_QsZombies;
		QSMenu(client);
	}
	return 0;
}
