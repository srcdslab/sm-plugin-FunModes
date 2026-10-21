// Inverted Controls module of eventmodes.sp.
// eventmodes.sp calls IC_PluginStart and IC_RunCmd (every player command); modes.sp calls IC_Tick
// (every second), IC_RoundStart and IC_Stop.
//
// Once the zombies are out, every so often the chosen players' movement is flipped for a few seconds:
// forward walks back, left strafes right. "CONTROLS INVERTED!" shows while it lasts.

#if defined _em_invert_included
 #endinput
#endif
#define _em_invert_included

#define IC_TAG  "\x07" ... "C060FF[Inverted]\x01 "   // kept apart: \x would eat the hex digits
#define IC_MOVE (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT)

enum { IC_ALL = 0, IC_HALF, IC_ONE, IC_EVERYONE, IC_WHO }
char g_IcWhoNames[][] = { "all humans", "half the humans (random)", "one random human", "everyone (zombies too)" };
int g_IcEverySteps[] = { 20, 30, 45, 60, 90, 120 };
int g_IcLastSteps[] = { 3, 5, 8, 10, 15 };

bool g_IcOn;
int g_IcEvery = 45;
int g_IcLast = 5;
int g_IcWho = IC_ALL;
bool g_IcActive;
float g_IcNext;             // 0 = schedule when the zombies come
float g_IcEnds;
bool g_IcFlipped[MAXPLAYERS + 1];
Handle g_HudIc;

void IC_PluginStart()
{
	g_HudIc = EM_HudSync();
}

bool IC_IsOn()
{
	return g_IcOn;
}

void IC_Clear()
{
	g_IcActive = false;
	g_IcNext = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_IcFlipped[i] = false;
}

void IC_Stop()
{
	g_IcOn = false;
	IC_Clear();
}

void IC_RoundStart()
{
	IC_Clear();
	if (g_IcOn)
		PrintToChatAll(IC_TAG ... "Inverted Controls is on: sometimes forward means backwards...");
}

// Flips the movement for players under the effect. True when it changed something.
bool IC_RunCmd(int client, int &buttons, float vel[3])
{
	if (!g_IcActive || !g_IcFlipped[client] || !IsPlayerAlive(client))
		return false;
	vel[0] = -vel[0];
	vel[1] = -vel[1];
	int flipped = buttons & ~IC_MOVE;
	if (buttons & IN_FORWARD)
		flipped |= IN_BACK;
	if (buttons & IN_BACK)
		flipped |= IN_FORWARD;
	if (buttons & IN_MOVELEFT)
		flipped |= IN_MOVERIGHT;
	if (buttons & IN_MOVERIGHT)
		flipped |= IN_MOVELEFT;
	buttons = flipped;
	return true;
}

void IC_Start()
{
	IC_Clear();
	int list[MAXPLAYERS + 1], n = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || IsFakeClient(i))
			continue;
		int team = GetClientTeam(i);
		if (team == CS_TEAM_CT || (g_IcWho == IC_EVERYONE && team == CS_TEAM_T))
			list[n++] = i;
	}
	for (int i = n - 1; i > 0; i--)   // shuffle
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}
	int count = n;
	if (g_IcWho == IC_HALF)
		count = (n + 1) / 2;
	else if (g_IcWho == IC_ONE)
		count = n > 0 ? 1 : 0;

	for (int k = 0; k < count; k++)
		g_IcFlipped[list[k]] = true;
	g_IcActive = count > 0;
	g_IcEnds = GetGameTime() + float(g_IcLast);
	if (!g_IcActive)
	{
		g_IcNext = GetGameTime() + float(g_IcEvery);
		return;
	}
	if (g_IcWho == IC_ONE)
		PrintToChatAll(IC_TAG ... "%N's controls are inverted for %d seconds!", list[0], g_IcLast);
	else
		PrintToChatAll(IC_TAG ... "Controls inverted for %d seconds!", g_IcLast);
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 50);
	IC_ShowHud();
}

void IC_End()
{
	for (int i = 1; i <= MaxClients; i++)
		if (g_IcFlipped[i] && IsClientInGame(i))
			PrintCenterText(i, "Controls back to normal");
	IC_Clear();
	g_IcNext = GetGameTime() + float(g_IcEvery);
}

void IC_ShowHud()
{
	int left = RoundToCeil(g_IcEnds - GetGameTime());
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_IcFlipped[i] || !IsClientInGame(i))
			continue;
		SetHudTextParams(-1.0, 0.44, 1.2, 192, 96, 255, 255, 0, 0.0, 0.0, 0.0);
		EM_ShowHud(i, g_HudIc, "CONTROLS INVERTED! (%d)", left > 0 ? left : 0);
	}
}

void IC_Tick()
{
	if (!g_IcOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (!g_IcActive)
	{
		if (g_IcNext == 0.0)
			g_IcNext = now + float(g_IcEvery);
		if (now >= g_IcNext)
			IC_Start();
		return;
	}
	if (now >= g_IcEnds)
		IC_End();
	else
		IC_ShowHud();
}

// ---------------------------------------------------------------- menu

void ICMenu(int client)
{
	Menu menu = new Menu(ICHandler);
	char line[64];
	menu.SetTitle(g_IcOn ? "Inverted Controls - ON\nStarts when the zombies come\n " : "Inverted Controls - OFF\n ");
	menu.AddItem("toggle", g_IcOn ? "Turn Inverted Controls OFF" : "Turn Inverted Controls ON");
	menu.AddItem("now", "Invert now", (g_IcOn && g_RoundLive && !g_IcActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_IcEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Lasts: %d s", g_IcLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Who: %s", g_IcWhoNames[g_IcWho]);
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ICHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_IcOn;
			IC_Stop();
			g_IcOn = on;
			PrintToChatAll(IC_TAG ... "%N turned Inverted Controls %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned inverted controls %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			IC_Start();
		else if (StrEqual(info, "every"))
			g_IcEvery = NextInt(g_IcEverySteps, sizeof(g_IcEverySteps), g_IcEvery);
		else if (StrEqual(info, "last"))
			g_IcLast = NextInt(g_IcLastSteps, sizeof(g_IcLastSteps), g_IcLast);
		else if (StrEqual(info, "who"))
			g_IcWho = (g_IcWho + 1) % IC_WHO;
		ICMenu(client);
	}
	return 0;
}
