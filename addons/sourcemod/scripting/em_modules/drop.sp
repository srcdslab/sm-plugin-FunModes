// Zombie Drop module of eventmodes.sp.
// modes.sp calls ZD_Tick (every second), ZD_RoundStart and ZD_Stop.
//
// Once the zombies are out, every N seconds a red warning ring appears where a random human is standing;
// when the warning runs out a random zombie is teleported onto that spot. The spot is somewhere a
// human just stood, so it's always a valid place to land.

#if defined _em_drop_included
 #endinput
#endif
#define _em_drop_included

#define ZD_TAG "\x07" ... "B04040[Zombie Drop]\x01 "   // kept apart: \x would eat the hex digits

int g_ZdEverySteps[] = { 15, 20, 30, 45, 60, 90 };
int g_ZdCountSteps[] = { 1, 2, 3, 5 };
int g_ZdWarnSteps[] = { 2, 3, 5 };
int g_ZdWarnColor[4] = { 255, 30, 30, 255 };

bool g_ZdOn;
int g_ZdEvery = 30;
int g_ZdCount = 1;          // zombies dropped each time
int g_ZdWarn = 3;           // seconds of warning
float g_ZdNext;             // 0 = schedule when the zombies come

bool ZD_IsOn()
{
	return g_ZdOn;
}

void ZD_Stop()
{
	g_ZdOn = false;
	g_ZdNext = 0.0;
}

void ZD_RoundStart()
{
	g_ZdNext = 0.0;
	if (g_ZdOn)
		PrintToChatAll(ZD_TAG ... "Zombie Drop is on: when a red ring appears under you, RUN!");
}

void ZD_Wave()
{
	int list[MAXPLAYERS + 1], n = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (IsHuman(i))
			list[n++] = i;
	for (int i = n - 1; i > 0; i--)   // shuffle
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}
	int drops = g_ZdCount < n ? g_ZdCount : n;
	for (int k = 0; k < drops; k++)
	{
		float pos[3];
		GetClientAbsOrigin(list[k], pos);
		if (g_BeamSprite != -1)
		{
			float p[3];
			p = pos;
			p[2] += 8.0;
			TE_SetupBeamRingPoint(p, 220.0, 10.0, g_BeamSprite, g_HaloSprite, 0, 15, float(g_ZdWarn), 8.0, 0.0, g_ZdWarnColor, 10, 0);
			TE_SendToAll();
		}
		PrintCenterText(list[k], "ZOMBIE DROP INCOMING - MOVE!");
		EmitAmbientSound(BEACON_SOUND, pos, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, _, _, 60);

		DataPack pack;
		CreateDataTimer(float(g_ZdWarn), ZD_Timer_Drop, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_RoundNum);
		pack.WriteFloat(pos[0]);
		pack.WriteFloat(pos[1]);
		pack.WriteFloat(pos[2]);
	}
	if (drops > 0)
		PrintToChatAll(ZD_TAG ... "%d zombie%s dropping in %d seconds - watch for the red ring%s!", drops, drops == 1 ? "" : "s",
			g_ZdWarn, drops == 1 ? "" : "s");
}

public Action ZD_Timer_Drop(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();
	float pos[3];
	pos[0] = pack.ReadFloat();
	pos[1] = pack.ReadFloat();
	pos[2] = pack.ReadFloat();
	if (!g_ZdOn || !g_RoundLive || round != g_RoundNum)
		return Plugin_Stop;
	int z = RandomZombie();
	if (z == 0)
		return Plugin_Stop;

	// Someone still standing right on the spot: land on top of them rather than inside them.
	float other[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == z || !IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(pos, other) < 40.0)
		{
			pos[2] += 80.0;
			break;
		}
	}
	float zero[3];
	TeleportEntity(z, pos, NULL_VECTOR, zero);
	Ring(z, g_ZdWarnColor, 80.0);
	EmitAmbientSound(BEACON_SOUND, pos, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN, _, _, 40);
	return Plugin_Stop;
}

void ZD_Tick()
{
	if (!g_ZdOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (g_ZdNext == 0.0)
		g_ZdNext = now + float(g_ZdEvery);
	if (now >= g_ZdNext)
	{
		ZD_Wave();
		g_ZdNext = now + float(g_ZdEvery);
	}
}

// ---------------------------------------------------------------- menu

void ZDMenu(int client)
{
	Menu menu = new Menu(ZDHandler);
	char line[64];
	menu.SetTitle(g_ZdOn ? "Zombie Drop - ON\nStarts when the zombies come\n " : "Zombie Drop - OFF\n ");
	menu.AddItem("toggle", g_ZdOn ? "Turn Zombie Drop OFF" : "Turn Zombie Drop ON");
	menu.AddItem("now", "Drop now", (g_ZdOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_ZdEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Zombies per drop: %d", g_ZdCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Warning: %d s", g_ZdWarn);
	menu.AddItem("warn", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ZDHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_ZdOn;
			ZD_Stop();
			g_ZdOn = on;
			PrintToChatAll(ZD_TAG ... "%N turned Zombie Drop %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned zombie drop %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			ZD_Wave();
		else if (StrEqual(info, "every"))
			g_ZdEvery = NextInt(g_ZdEverySteps, sizeof(g_ZdEverySteps), g_ZdEvery);
		else if (StrEqual(info, "count"))
			g_ZdCount = NextInt(g_ZdCountSteps, sizeof(g_ZdCountSteps), g_ZdCount);
		else if (StrEqual(info, "warn"))
			g_ZdWarn = NextInt(g_ZdWarnSteps, sizeof(g_ZdWarnSteps), g_ZdWarn);
		ZDMenu(client);
	}
	return 0;
}
