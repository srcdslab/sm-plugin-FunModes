// Lightning Strikes module of eventmodes.sp.
// eventmodes.sp calls Lightning_MapStart; modes.sp calls Lightning_Tick (every second),
// Lightning_RoundStart and Lightning_Stop.
//
// Once the zombies are out, every few seconds bolts are aimed near random humans: a red ring warns
// where it lands, 1.5 seconds later the bolt hits and hurts everyone still inside. Keeps holds moving.

#if defined _em_lightning_included
 #endinput
#endif
#define _em_lightning_included

#define LT_TAG        "\x07" ... "B0C4FF[Lightning]\x01 "   // kept apart: \x would eat the hex digits
#define LT_SOUND      "weapons/hegrenade/explode3.wav"
#define LT_WARN_TIME  1.5

int g_LtEverySteps[] = { 5, 10, 15, 20, 30 };
int g_LtCountSteps[] = { 1, 2, 3, 5, 8 };
int g_LtDamageSteps[] = { 25, 50, 75, 100, 1000 };   // 1000 = kill
float g_LtRadiusSteps[] = { 100.0, 150.0, 200.0, 300.0 };

int g_LtWarnColor[4] = { 255, 40, 40, 255 };
int g_LtBoltColor[4] = { 200, 220, 255, 255 };

bool g_LtOn;
int g_LtEvery = 15;         // seconds between waves
int g_LtCount = 2;          // bolts per wave
int g_LtDamage = 50;
float g_LtRadius = 150.0;
bool g_LtZombies;           // bolts hurt zombies too
float g_LtNext;             // game time of the next wave

void Lightning_MapStart()
{
	PrecacheSound(LT_SOUND, true);
}

void Lightning_Stop()
{
	g_LtOn = false;
}

void Lightning_RoundStart()
{
	g_LtNext = 0.0;
	if (g_LtOn)
		PrintToChatAll(LT_TAG ... "Lightning Strikes are on: when you see a red ring under you, MOVE!");
}

void Lightning_Tick()
{
	if (!g_LtOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (g_LtNext == 0.0)
		g_LtNext = now + 3.0;   // a short breather after the zombies come
	if (now >= g_LtNext)
	{
		Lightning_Wave();
		g_LtNext = now + float(g_LtEvery);
	}
}

void Lightning_Wave()
{
	for (int k = 0; k < g_LtCount; k++)
	{
		int target = RandomHuman(0);
		if (target == 0)
			return;
		float pos[3];
		GetClientAbsOrigin(target, pos);
		pos[0] += GetRandomFloat(-120.0, 120.0);   // near them, not always dead on
		pos[1] += GetRandomFloat(-120.0, 120.0);
		Lightning_Warn(pos);
		PrintCenterText(target, "LIGHTNING! MOVE!");

		DataPack pack;
		CreateDataTimer(LT_WARN_TIME, Lightning_Timer_Strike, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_RoundNum);
		pack.WriteFloat(pos[0]);
		pack.WriteFloat(pos[1]);
		pack.WriteFloat(pos[2]);
	}
}

void Lightning_Warn(const float pos[3])
{
	if (g_BeamSprite == -1)
		return;
	float p[3];
	p = pos;
	p[2] += 8.0;
	// A ring the size of the blast that shrinks to the centre as the bolt comes.
	TE_SetupBeamRingPoint(p, g_LtRadius * 2.0, 10.0, g_BeamSprite, g_HaloSprite, 0, 15, LT_WARN_TIME, 6.0, 0.0, g_LtWarnColor, 10, 0);
	TE_SendToAll();
	EmitAmbientSound(BEACON_SOUND, p, SOUND_FROM_WORLD, SNDLEVEL_NORMAL, _, _, 70);   // low warning blip
}

public Action Lightning_Timer_Strike(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();
	float pos[3];
	pos[0] = pack.ReadFloat();
	pos[1] = pack.ReadFloat();
	pos[2] = pack.ReadFloat();
	if (!g_LtOn || !g_RoundLive || round != g_RoundNum)
		return Plugin_Stop;
	Lightning_Strike(pos);
	return Plugin_Stop;
}

void Lightning_Strike(const float pos[3])
{
	float top[3], ground[3];
	ground = pos;
	ground[2] += 4.0;
	top = pos;
	top[2] += 1200.0;

	if (g_BeamSprite != -1)
	{
		// Jagged bolt (amplitude) plus a thinner second one for flicker.
		TE_SetupBeamPoints(top, ground, g_BeamSprite, g_HaloSprite, 0, 30, 0.35, 18.0, 10.0, 0, 12.0, g_LtBoltColor, 20);
		TE_SendToAll();
		TE_SetupBeamPoints(top, ground, g_BeamSprite, g_HaloSprite, 0, 30, 0.2, 6.0, 4.0, 0, 20.0, g_LtBoltColor, 30);
		TE_SendToAll();
		TE_SetupBeamRingPoint(ground, 10.0, g_LtRadius * 2.0, g_BeamSprite, g_HaloSprite, 0, 15, 0.4, 12.0, 0.0, g_LtBoltColor, 10, 0);
		TE_SendToAll();
	}
	float up[3] = { 0.0, 0.0, 1.0 };
	TE_SetupSparks(ground, up, 8, 6);
	TE_SendToAll();
	EmitAmbientSound(LT_SOUND, ground, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN);

	float other[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;
		int team = GetClientTeam(i);
		if (team != CS_TEAM_CT && !(g_LtZombies && team == CS_TEAM_T))
			continue;
		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(ground, other) > g_LtRadius)
			continue;
		int hp = GetClientHealth(i) - g_LtDamage;
		if (hp <= 0)
		{
			PrintToChatAll(LT_TAG ... "%N was struck by lightning!", i);
			ForcePlayerSuicide(i);
		}
		else
			SetEntityHealth(i, hp);
	}
}

// ---------------------------------------------------------------- menu

void LightningMenu(int client)
{
	Menu menu = new Menu(LightningHandler);
	char line[64];
	menu.SetTitle(g_LtOn ? "Lightning Strikes - ON\n " : "Lightning Strikes - OFF\n ");

	menu.AddItem("toggle", g_LtOn ? "Turn Lightning OFF" : "Turn Lightning ON");
	menu.AddItem("now", "Strike now", (g_LtOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_LtEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Bolts per wave: %d", g_LtCount);
	menu.AddItem("count", line);
	if (g_LtDamage >= 1000)
		strcopy(line, sizeof(line), "Damage: instant kill");
	else
		Format(line, sizeof(line), "Damage: %d", g_LtDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Blast radius: %d", RoundToNearest(g_LtRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Hits zombies too: %s", g_LtZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int LightningHandler(Menu menu, MenuAction action, int client, int item)
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
			g_LtOn = !g_LtOn;
			g_LtNext = 0.0;
			PrintToChatAll(LT_TAG ... "%N turned Lightning Strikes %s.", client, g_LtOn ? "ON - watch for red rings" : "OFF");
			LogAction(client, -1, "\"%L\" turned lightning strikes %s", client, g_LtOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			Lightning_Wave();
		else if (StrEqual(info, "every"))
			g_LtEvery = NextInt(g_LtEverySteps, sizeof(g_LtEverySteps), g_LtEvery);
		else if (StrEqual(info, "count"))
			g_LtCount = NextInt(g_LtCountSteps, sizeof(g_LtCountSteps), g_LtCount);
		else if (StrEqual(info, "damage"))
			g_LtDamage = NextInt(g_LtDamageSteps, sizeof(g_LtDamageSteps), g_LtDamage);
		else if (StrEqual(info, "radius"))
			g_LtRadius = NextFloat(g_LtRadiusSteps, sizeof(g_LtRadiusSteps), g_LtRadius);
		else if (StrEqual(info, "zombies"))
			g_LtZombies = !g_LtZombies;
		LightningMenu(client);
	}
	return 0;
}

bool Lightning_IsOn()
{
	return g_LtOn;
}
