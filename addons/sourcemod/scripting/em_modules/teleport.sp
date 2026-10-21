// Teleport Shuffle module of eventmodes.sp.
// modes.sp calls TS_Tick (every second), TS_RoundStart and TS_Stop.
//
// Once the zombies are out, every N seconds random pairs of players swap places, after a countdown
// with beeps. Humans swap with humans, or (if set) anyone with anyone - zombies included. With fixed
// partners everyone is paired once a round and always swaps with the same person. Players carrying a
// special map item (EntWatch) are never moved.

#if defined _em_teleport_included
 #endinput
#endif
#define _em_teleport_included

#define TS_TAG "\x07" ... "00E0E0[Teleport Shuffle]\x01 "   // kept apart: \x would eat the hex digits

int g_TsEverySteps[] = { 15, 20, 30, 45, 60, 90 };
int g_TsPairSteps[] = { 1, 2, 3, 5, 10 };
int g_TsWarnSteps[] = { 0, 2, 3, 5 };
int g_TsColor[4] = { 0, 224, 224, 255 };

bool g_TsOn;
int g_TsEvery = 30;
int g_TsPairs = 1;          // pairs swapped each time
int g_TsWarn = 3;           // countdown seconds (0 = no warning)
bool g_TsMixed;             // zombies swap too (else humans only)
bool g_TsFixed;             // same partner all round (else random pairs each time)
int g_TsPartner[MAXPLAYERS + 1];   // userid of the fixed partner
bool g_TsPaired;            // fixed partners handed out this round
float g_TsNext;             // 0 = schedule when the zombies come

bool TS_IsOn()
{
	return g_TsOn;
}

void TS_ClearPartners()
{
	g_TsPaired = false;
	for (int i = 1; i <= MaxClients; i++)
		g_TsPartner[i] = 0;
}

void TS_Stop()
{
	g_TsOn = false;
	g_TsNext = 0.0;
	TS_ClearPartners();
}

void TS_RoundStart()
{
	g_TsNext = 0.0;
	TS_ClearPartners();
	if (g_TsOn)
		PrintToChatAll(TS_TAG ... "Teleport Shuffle is on: don't get too comfortable where you're standing!");
}

bool TS_Swappable(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return false;
	if (GetEntityFlags(client) & FL_DUCKING)
		return false;   // could end up stuck in a crawl space
	if (EM_HasMapItem(client))
		return false;   // moving an item holder can break the map's item logic
	int team = GetClientTeam(client);
	return team == CS_TEAM_CT || (g_TsMixed && team == CS_TEAM_T);
}

void TS_SwapPair(int a, int b)
{
	float zero[3], pa[3], pb[3];
	GetClientAbsOrigin(a, pa);
	GetClientAbsOrigin(b, pb);
	TeleportEntity(a, pb, NULL_VECTOR, zero);
	TeleportEntity(b, pa, NULL_VECTOR, zero);
	Ring(a, g_TsColor, 60.0);
	Ring(b, g_TsColor, 60.0);
}

// Fixed partners: everyone who can swap is paired once a round and told who with.
void TS_AssignPartners()
{
	TS_ClearPartners();
	g_TsPaired = true;
	int list[MAXPLAYERS + 1], n = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		int team = GetClientTeam(i);
		if (team == CS_TEAM_CT || (g_TsMixed && team == CS_TEAM_T))
			list[n++] = i;
	}
	for (int i = n - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}
	for (int k = 0; k + 1 < n; k += 2)
	{
		g_TsPartner[list[k]] = GetClientUserId(list[k + 1]);
		g_TsPartner[list[k + 1]] = GetClientUserId(list[k]);
		PrintToChat(list[k], TS_TAG ... "You'll swap places with \x07" ... "00E0E0%N\x01 all round!", list[k + 1]);
		PrintToChat(list[k + 1], TS_TAG ... "You'll swap places with \x07" ... "00E0E0%N\x01 all round!", list[k]);
	}
}

void TS_SwapFixed()
{
	if (!g_TsPaired)
		TS_AssignPartners();
	int list[MAXPLAYERS + 1], n = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (TS_Swappable(i))
			list[n++] = i;
	for (int i = n - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}
	bool used[MAXPLAYERS + 1];
	int swapped = 0;
	for (int k = 0; k < n && swapped < g_TsPairs; k++)
	{
		int a = list[k];
		int b = g_TsPartner[a] != 0 ? GetClientOfUserId(g_TsPartner[a]) : 0;
		if (used[a] || b == 0 || used[b] || !TS_Swappable(b))
			continue;
		used[a] = true;
		used[b] = true;
		TS_SwapPair(a, b);
		PrintToChat(a, TS_TAG ... "You swapped places with your partner %N!", b);
		PrintToChat(b, TS_TAG ... "You swapped places with your partner %N!", a);
		swapped++;
	}
	if (swapped > 0)
	{
		PrintToChatAll(TS_TAG ... "%d pair%s of partners swapped places!", swapped, swapped == 1 ? "" : "s");
		EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 180);
	}
}

void TS_Swap()
{
	if (g_TsFixed)
	{
		TS_SwapFixed();
		return;
	}
	int list[MAXPLAYERS + 1], n = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (TS_Swappable(i))
			list[n++] = i;
	for (int i = n - 1; i > 0; i--)   // shuffle
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}

	float zero[3], pa[3], pb[3];
	int swapped = 0;
	for (int k = 0; k + 1 < n && swapped < g_TsPairs; k += 2)
	{
		int a = list[k], b = list[k + 1];
		GetClientAbsOrigin(a, pa);
		GetClientAbsOrigin(b, pb);
		TeleportEntity(a, pb, NULL_VECTOR, zero);
		TeleportEntity(b, pa, NULL_VECTOR, zero);
		Ring(a, g_TsColor, 60.0);
		Ring(b, g_TsColor, 60.0);
		if (g_TsPairs <= 2)
			PrintToChatAll(TS_TAG ... "%N and %N swapped places!", a, b);
		else
		{
			PrintToChat(a, TS_TAG ... "You swapped places with %N!", b);
			PrintToChat(b, TS_TAG ... "You swapped places with %N!", a);
		}
		swapped++;
	}
	if (swapped > 2)
		PrintToChatAll(TS_TAG ... "%d pairs swapped places!", swapped);
	if (swapped > 0)
		EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 180);
}

void TS_Tick()
{
	if (!g_TsOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (g_TsNext == 0.0)
		g_TsNext = now + float(g_TsEvery);
	int left = RoundToCeil(g_TsNext - now);
	if (g_TsWarn > 0 && left > 0 && left <= g_TsWarn)
	{
		PrintCenterTextAll("TELEPORT SHUFFLE IN %d...", left);
		EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 120);
	}
	if (left <= 0)
	{
		TS_Swap();
		g_TsNext = now + float(g_TsEvery);
	}
}

// ---------------------------------------------------------------- menu

void TSMenu(int client)
{
	Menu menu = new Menu(TSHandler);
	char line[64];
	menu.SetTitle(g_TsOn ? "Teleport Shuffle - ON\nStarts when the zombies come\n " : "Teleport Shuffle - OFF\n ");
	menu.AddItem("toggle", g_TsOn ? "Turn Teleport Shuffle OFF" : "Turn Teleport Shuffle ON");
	menu.AddItem("now", "Swap now", (g_TsOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_TsEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Pairs swapped each time: %d", g_TsPairs);
	menu.AddItem("pairs", line);
	if (g_TsWarn == 0)
		strcopy(line, sizeof(line), "Warning countdown: off");
	else
		Format(line, sizeof(line), "Warning countdown: %d s", g_TsWarn);
	menu.AddItem("warn", line);
	Format(line, sizeof(line), "Who swaps: %s", g_TsMixed ? "anyone (zombies too)" : "humans only");
	menu.AddItem("mixed", line);
	Format(line, sizeof(line), "Partners: %s", g_TsFixed ? "same partner all round" : "random each time");
	menu.AddItem("fixed", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int TSHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_TsOn;
			TS_Stop();
			g_TsOn = on;
			PrintToChatAll(TS_TAG ... "%N turned Teleport Shuffle %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned teleport shuffle %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			TS_Swap();
		else if (StrEqual(info, "every"))
			g_TsEvery = NextInt(g_TsEverySteps, sizeof(g_TsEverySteps), g_TsEvery);
		else if (StrEqual(info, "pairs"))
			g_TsPairs = NextInt(g_TsPairSteps, sizeof(g_TsPairSteps), g_TsPairs);
		else if (StrEqual(info, "warn"))
			g_TsWarn = NextInt(g_TsWarnSteps, sizeof(g_TsWarnSteps), g_TsWarn);
		else if (StrEqual(info, "mixed"))
		{
			g_TsMixed = !g_TsMixed;
			TS_ClearPartners();
		}
		else if (StrEqual(info, "fixed"))
		{
			g_TsFixed = !g_TsFixed;
			TS_ClearPartners();
		}
		TSMenu(client);
	}
	return 0;
}
