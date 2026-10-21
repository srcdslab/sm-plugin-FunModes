// Tornado module of eventmodes.sp.
// modes.sp calls TN_Check (every 0.2 s), TN_Tick (every second), TN_RoundStart and TN_Stop.
//
// Once the zombies are out, every N seconds a tornado forms near the humans and wanders after them for
// a while. Anyone close is pulled in, spun around and lifted off the ground.

#if defined _em_tornado_included
 #endinput
#endif
#define _em_tornado_included

#define TN_TAG "\x07" ... "B0B0A0[Tornado]\x01 "   // kept apart: \x would eat the hex digits

int g_TnEverySteps[] = { 30, 45, 60, 90, 120 };
int g_TnLastSteps[] = { 10, 15, 20, 30 };
float g_TnRadiusSteps[] = { 200.0, 300.0, 400.0, 600.0 };
char g_TnPowerNames[][] = { "gentle", "strong", "violent", "F5" };
float g_TnPull[] = { 25.0, 45.0, 70.0, 110.0 };   // per 0.2 s
float g_TnSpeedSteps[] = { 100.0, 160.0, 220.0 };
int g_TnColor[4] = { 176, 176, 160, 255 };

bool g_TnOn;
int g_TnEvery = 60;
int g_TnLast = 15;
float g_TnRadius = 300.0;
int g_TnPower = 1;
float g_TnSpeed = 160.0;    // how fast it wanders
bool g_TnEveryone = true;

bool g_TnActive;
float g_TnNext;
float g_TnEnds;
float g_TnPos[3];
int g_TnTarget;             // userid it's heading for
float g_TnRetarget;

bool TN_IsOn()
{
	return g_TnOn;
}

void TN_Stop()
{
	g_TnOn = false;
	g_TnActive = false;
	g_TnNext = 0.0;
}

void TN_Set(bool on)
{
	TN_Stop();
	g_TnOn = on;
}

void TN_RoundStart()
{
	g_TnActive = false;
	g_TnNext = 0.0;
	if (g_TnOn)
		PrintToChatAll(TN_TAG ... "Tornadoes are on: if you see one, RUN the other way!");
}

void TN_Spawn()
{
	int list[MAXPLAYERS + 1];
	if (ShuffledHumans(list) == 0)
		return;
	GetClientAbsOrigin(list[0], g_TnPos);
	float angle = GetRandomFloat(0.0, 6.2832);
	g_TnPos[0] += Cosine(angle) * 400.0;
	g_TnPos[1] += Sine(angle) * 400.0;
	g_TnTarget = GetClientUserId(list[0]);
	g_TnRetarget = GetGameTime() + 3.0;
	g_TnEnds = GetGameTime() + float(g_TnLast);
	g_TnActive = true;
	PrintToChatAll(TN_TAG ... "A TORNADO is forming near %N!", list[0]);
	PrintCenterTextAll("TORNADO!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 45);
}

void TN_Check()
{
	if (!g_TnOn || !g_TnActive || !g_RoundLive)
		return;
	float now = GetGameTime();
	if (now >= g_TnEnds)
	{
		g_TnActive = false;
		PrintCenterTextAll("The tornado is gone");
		return;
	}

	// Wander towards the target human (a new one every few seconds).
	int target = GetClientOfUserId(g_TnTarget);
	if (now >= g_TnRetarget || target == 0 || !IsHuman(target))
	{
		int list[MAXPLAYERS + 1];
		if (ShuffledHumans(list) > 0)
			g_TnTarget = GetClientUserId(list[0]);
		g_TnRetarget = now + 3.0;
		target = GetClientOfUserId(g_TnTarget);
	}
	if (target != 0 && IsHuman(target))
	{
		float tp[3], dir[3];
		GetClientAbsOrigin(target, tp);
		MakeVectorFromPoints(g_TnPos, tp, dir);
		dir[2] = 0.0;
		float dist = GetVectorLength(dir);
		if (dist > 1.0)
		{
			NormalizeVector(dir, dir);
			float step = g_TnSpeed * 0.2 < dist ? g_TnSpeed * 0.2 : dist;
			g_TnPos[0] += dir[0] * step;
			g_TnPos[1] += dir[1] * step;
		}
		g_TnPos[2] = tp[2];   // follow the ground the humans are on
	}

	// The funnel: rings stacked up, wider at the top.
	for (int h = 0; h < 5; h++)
	{
		float p[3];
		p = g_TnPos;
		p[2] += float(h) * 70.0;
		float r = g_TnRadius * (0.15 + 0.2 * float(h));
		RingAt(p, r, r * 0.8, 0.25, g_TnColor, 14.0);
	}

	// Pull in, spin round, lift up.
	float pull = g_TnPull[g_TnPower];
	float pos[3], to[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_TnEveryone))
			continue;
		GetClientAbsOrigin(i, pos);
		MakeVectorFromPoints(pos, g_TnPos, to);
		to[2] = 0.0;
		float d = GetVectorLength(to);
		if (d > g_TnRadius)
			continue;
		if (d > 1.0)
			NormalizeVector(to, to);
		float closeness = 1.0 - d / g_TnRadius;
		float lift = d < g_TnRadius * 0.4 ? pull * 1.2 : 0.0;
		Shove(i, to[0] * pull - to[1] * pull * closeness, to[1] * pull + to[0] * pull * closeness, lift);
	}
}

void TN_Tick()
{
	if (!g_TnActive && HazardDue(g_TnOn, g_TnNext, g_TnEvery))
		TN_Spawn();
}

// ---------------------------------------------------------------- menu

void TNMenu(int client)
{
	Menu menu = new Menu(TNHandler);
	char line[64];
	menu.SetTitle(g_TnOn ? "Tornado - ON\nStarts when the zombies come\n " : "Tornado - OFF\n ");
	menu.AddItem("toggle", g_TnOn ? "Turn Tornadoes OFF" : "Turn Tornadoes ON");
	menu.AddItem("now", "Tornado now", (g_TnOn && g_RoundLive && !g_TnActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_TnEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Lasts: %d s", g_TnLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Size: %d", RoundToNearest(g_TnRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Power: %s", g_TnPowerNames[g_TnPower]);
	menu.AddItem("power", line);
	Format(line, sizeof(line), "Moves at: %d", RoundToNearest(g_TnSpeed));
	menu.AddItem("speed", line);
	Format(line, sizeof(line), "Who gets caught: %s", g_TnEveryone ? "everyone" : "humans only");
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int TNHandler(Menu menu, MenuAction action, int client, int item)
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
			TN_Set(!g_TnOn);
			PrintToChatAll(TN_TAG ... "%N turned Tornadoes %s.", client, g_TnOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned tornadoes %s", client, g_TnOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			TN_Spawn();
		else if (StrEqual(info, "every"))
			g_TnEvery = NextInt(g_TnEverySteps, sizeof(g_TnEverySteps), g_TnEvery);
		else if (StrEqual(info, "last"))
			g_TnLast = NextInt(g_TnLastSteps, sizeof(g_TnLastSteps), g_TnLast);
		else if (StrEqual(info, "radius"))
			g_TnRadius = NextFloat(g_TnRadiusSteps, sizeof(g_TnRadiusSteps), g_TnRadius);
		else if (StrEqual(info, "power"))
			g_TnPower = (g_TnPower + 1) % sizeof(g_TnPowerNames);
		else if (StrEqual(info, "speed"))
			g_TnSpeed = NextFloat(g_TnSpeedSteps, sizeof(g_TnSpeedSteps), g_TnSpeed);
		else if (StrEqual(info, "who"))
			g_TnEveryone = !g_TnEveryone;
		TNMenu(client);
	}
	return 0;
}
