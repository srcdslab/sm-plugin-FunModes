// Sudden Darkness module of eventmodes.sp.
// modes.sp calls SD_Tick (every second), SD_RoundStart and SD_Stop.
//
// Once the zombies are out, every N seconds the lights go out: the humans' screens go dark (dim, dark
// or pitch black) for a few seconds, then slowly come back. Zombies can be left seeing fine.

#if defined _em_darkness_included
 #endinput
#endif
#define _em_darkness_included

#define SD_TAG "\x07" ... "808080[Darkness]\x01 "   // kept apart: \x would eat the hex digits

char g_SdLevelNames[][] = { "dim", "dark", "very dark", "pitch black" };
int g_SdLevelAlpha[] = { 150, 200, 230, 252 };
int g_SdEverySteps[] = { 20, 30, 45, 60, 90 };
int g_SdLastSteps[] = { 3, 5, 8, 10, 15 };

bool g_SdOn;
int g_SdEvery = 45;
int g_SdLast = 8;
int g_SdLevel = 2;
bool g_SdZombies;           // zombies are in the dark too
float g_SdNext;

bool SD_IsOn()
{
	return g_SdOn;
}

void SD_Stop()
{
	g_SdOn = false;
	g_SdNext = 0.0;
}

void SD_Set(bool on)
{
	SD_Stop();
	g_SdOn = on;
}

void SD_RoundStart()
{
	g_SdNext = 0.0;
	if (g_SdOn)
		PrintToChatAll(SD_TAG ... "Sudden Darkness is on: the lights will go out when you least expect it...");
}

void SD_Lights()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T && !g_SdZombies)
			continue;
		ScreenTint(i, 0, 0, 0, g_SdLevelAlpha[g_SdLevel], float(g_SdLast), 2.0);
	}
	PrintToChatAll(SD_TAG ... "The lights went out!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 35);
}

void SD_Tick()
{
	if (HazardDue(g_SdOn, g_SdNext, g_SdEvery))
		SD_Lights();
}

// ---------------------------------------------------------------- menu

void SDMenu(int client)
{
	Menu menu = new Menu(SDHandler);
	char line[64];
	menu.SetTitle(g_SdOn ? "Sudden Darkness - ON\nStarts when the zombies come\n " : "Sudden Darkness - OFF\n ");
	menu.AddItem("toggle", g_SdOn ? "Turn Sudden Darkness OFF" : "Turn Sudden Darkness ON");
	menu.AddItem("now", "Lights out now", (g_SdOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_SdEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Dark for: %d s", g_SdLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "How dark: %s", g_SdLevelNames[g_SdLevel]);
	menu.AddItem("level", line);
	Format(line, sizeof(line), "Zombies in the dark too: %s", g_SdZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SDHandler(Menu menu, MenuAction action, int client, int item)
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
			SD_Set(!g_SdOn);
			PrintToChatAll(SD_TAG ... "%N turned Sudden Darkness %s.", client, g_SdOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned sudden darkness %s", client, g_SdOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			SD_Lights();
		else if (StrEqual(info, "every"))
			g_SdEvery = NextInt(g_SdEverySteps, sizeof(g_SdEverySteps), g_SdEvery);
		else if (StrEqual(info, "last"))
			g_SdLast = NextInt(g_SdLastSteps, sizeof(g_SdLastSteps), g_SdLast);
		else if (StrEqual(info, "level"))
			g_SdLevel = (g_SdLevel + 1) % sizeof(g_SdLevelNames);
		else if (StrEqual(info, "zombies"))
			g_SdZombies = !g_SdZombies;
		SDMenu(client);
	}
	return 0;
}
