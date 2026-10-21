// Magnet Pull module of eventmodes.sp.
// modes.sp calls MG_Check (every 0.2 s), MG_Tick (every second), MG_RoundStart and MG_Stop.
//
// Once the zombies are out, every N seconds a magnetic pulse drags the humans for a few seconds -
// towards the middle of the zombie horde, or towards each other.

#if defined _em_magnet_included
 #endinput
#endif
#define _em_magnet_included

#define MG_TAG "\x07" ... "FF40C0[Magnet]\x01 "   // kept apart: \x would eat the hex digits

char g_MgTargetNames[][] = { "the zombies", "each other" };
char g_MgLevelNames[][] = { "weak", "medium", "strong", "very strong" };
float g_MgLevelPull[] = { 20.0, 40.0, 65.0, 100.0 };   // speed added every 0.2 s
int g_MgEverySteps[] = { 20, 30, 45, 60, 90 };
int g_MgLastSteps[] = { 2, 3, 5, 8 };
int g_MgColor[4] = { 255, 64, 192, 255 };

bool g_MgOn;
int g_MgEvery = 45;
int g_MgLast = 3;
int g_MgLevel = 1;
int g_MgTarget = 0;         // 0 = towards the zombies, 1 = towards each other
bool g_MgActive;
float g_MgNext;
float g_MgEnds;

bool MG_IsOn()
{
	return g_MgOn;
}

void MG_Stop()
{
	g_MgOn = false;
	g_MgActive = false;
	g_MgNext = 0.0;
}

void MG_Set(bool on)
{
	MG_Stop();
	g_MgOn = on;
}

void MG_RoundStart()
{
	g_MgActive = false;
	g_MgNext = 0.0;
	if (g_MgOn)
		PrintToChatAll(MG_TAG ... "Magnet is on: sometimes something pulls you towards %s...", g_MgTargetNames[g_MgTarget]);
}

// The middle point of a team; false if nobody's there.
bool MG_Centre(int team, float centre[3])
{
	float pos[3];
	int n = 0;
	centre[0] = 0.0;
	centre[1] = 0.0;
	centre[2] = 0.0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != team)
			continue;
		GetClientAbsOrigin(i, pos);
		AddVectors(centre, pos, centre);
		n++;
	}
	if (n == 0)
		return false;
	ScaleVector(centre, 1.0 / float(n));
	return true;
}

void MG_Start()
{
	g_MgActive = true;
	g_MgEnds = GetGameTime() + float(g_MgLast);
	PrintToChatAll(MG_TAG ... "MAGNETIC PULSE! You're being pulled towards %s!", g_MgTargetNames[g_MgTarget]);
	PrintCenterTextAll("MAGNETIC PULL!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 75);
}

void MG_Check()
{
	if (!g_MgOn || !g_MgActive || !g_RoundLive)
		return;
	if (GetGameTime() >= g_MgEnds)
	{
		g_MgActive = false;
		return;
	}
	float centre[3];
	if (!MG_Centre(g_MgTarget == 0 ? CS_TEAM_T : CS_TEAM_CT, centre))
		return;
	RingAt(centre, 120.0, 20.0, 0.3, g_MgColor, 10.0);
	float pull = g_MgLevelPull[g_MgLevel], pos[3], dir[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i))
			continue;
		GetClientAbsOrigin(i, pos);
		MakeVectorFromPoints(pos, centre, dir);
		dir[2] = 0.0;
		if (GetVectorLength(dir) < 50.0)
			continue;
		NormalizeVector(dir, dir);
		Shove(i, dir[0] * pull, dir[1] * pull, 0.0);
	}
}

void MG_Tick()
{
	if (!g_MgActive && HazardDue(g_MgOn, g_MgNext, g_MgEvery))
		MG_Start();
}

// ---------------------------------------------------------------- menu

void MGMenu(int client)
{
	Menu menu = new Menu(MGHandler);
	char line[64];
	menu.SetTitle(g_MgOn ? "Magnet Pull - ON\nStarts when the zombies come\n " : "Magnet Pull - OFF\n ");
	menu.AddItem("toggle", g_MgOn ? "Turn Magnet OFF" : "Turn Magnet ON");
	menu.AddItem("now", "Pull now", (g_MgOn && g_RoundLive && !g_MgActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_MgEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Pull lasts: %d s", g_MgLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Strength: %s", g_MgLevelNames[g_MgLevel]);
	menu.AddItem("level", line);
	Format(line, sizeof(line), "Pulls humans towards: %s", g_MgTargetNames[g_MgTarget]);
	menu.AddItem("target", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MGHandler(Menu menu, MenuAction action, int client, int item)
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
			MG_Set(!g_MgOn);
			PrintToChatAll(MG_TAG ... "%N turned Magnet %s.", client, g_MgOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned magnet pull %s", client, g_MgOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			MG_Start();
		else if (StrEqual(info, "every"))
			g_MgEvery = NextInt(g_MgEverySteps, sizeof(g_MgEverySteps), g_MgEvery);
		else if (StrEqual(info, "last"))
			g_MgLast = NextInt(g_MgLastSteps, sizeof(g_MgLastSteps), g_MgLast);
		else if (StrEqual(info, "level"))
			g_MgLevel = (g_MgLevel + 1) % sizeof(g_MgLevelNames);
		else if (StrEqual(info, "target"))
			g_MgTarget = (g_MgTarget + 1) % sizeof(g_MgTargetNames);
		MGMenu(client);
	}
	return 0;
}
