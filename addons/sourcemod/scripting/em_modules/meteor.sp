// Meteor Shower module of eventmodes.sp.
// modes.sp calls MT_Tick (every second), MT_RoundStart and MT_Stop.
//
// Once the zombies are out, every N seconds a few meteors are aimed near random humans: an orange ring
// and a glowing trail from the sky warn where they land, then each one explodes with damage and
// knockback.

#if defined _em_meteor_included
 #endinput
#endif
#define _em_meteor_included

#define MT_TAG  "\x07" ... "FF8030[Meteor Shower]\x01 "   // kept apart: \x would eat the hex digits
#define MT_WARN 2.0

int g_MtEverySteps[] = { 15, 20, 30, 45, 60, 90 };
int g_MtCountSteps[] = { 1, 2, 3, 5, 8 };
int g_MtDamageSteps[] = { 25, 50, 75, 100, 1000 };   // 1000 = kill
float g_MtRadiusSteps[] = { 150.0, 200.0, 250.0, 350.0 };
int g_MtColor[4] = { 255, 128, 32, 255 };

bool g_MtOn;
int g_MtEvery = 30;
int g_MtCount = 3;
int g_MtDamage = 50;
float g_MtRadius = 200.0;
bool g_MtKnock = true;
bool g_MtZombies;           // zombies get hit too
float g_MtNext;

bool MT_IsOn()
{
	return g_MtOn;
}

void MT_Stop()
{
	g_MtOn = false;
	g_MtNext = 0.0;
}

void MT_Set(bool on)
{
	MT_Stop();
	g_MtOn = on;
}

void MT_RoundStart()
{
	g_MtNext = 0.0;
	if (g_MtOn)
		PrintToChatAll(MT_TAG ... "Meteor Shower is on: look up and watch for orange rings!");
}

void MT_Wave()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	for (int k = 0; k < g_MtCount && n > 0; k++)
	{
		float pos[3];
		GetClientAbsOrigin(list[k % n], pos);
		pos[0] += GetRandomFloat(-150.0, 150.0);
		pos[1] += GetRandomFloat(-150.0, 150.0);
		RingAt(pos, g_MtRadius, 20.0, MT_WARN, g_MtColor);
		BeamDown(pos, 1500.0, MT_WARN, 20.0, g_MtColor);

		DataPack pack;
		CreateDataTimer(MT_WARN, MT_Timer_Hit, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_RoundNum);
		pack.WriteFloat(pos[0]);
		pack.WriteFloat(pos[1]);
		pack.WriteFloat(pos[2]);
	}
	if (n > 0)
		PrintToChatAll(MT_TAG ... "METEORS INCOMING!");
}

public Action MT_Timer_Hit(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();
	float pos[3];
	pos[0] = pack.ReadFloat();
	pos[1] = pack.ReadFloat();
	pos[2] = pack.ReadFloat();
	if (g_MtOn && g_RoundLive && round == g_RoundNum)
		Explode(pos, g_MtRadius, g_MtDamage, g_MtKnock ? 400.0 : 0.0, g_MtZombies);
	return Plugin_Stop;
}

void MT_Tick()
{
	if (HazardDue(g_MtOn, g_MtNext, g_MtEvery))
		MT_Wave();
}

// ---------------------------------------------------------------- menu

void MTMenu(int client)
{
	Menu menu = new Menu(MTHandler);
	char line[64];
	menu.SetTitle(g_MtOn ? "Meteor Shower - ON\nStarts when the zombies come\n " : "Meteor Shower - OFF\n ");
	menu.AddItem("toggle", g_MtOn ? "Turn Meteor Shower OFF" : "Turn Meteor Shower ON");
	menu.AddItem("now", "Meteors now", (g_MtOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_MtEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Meteors per shower: %d", g_MtCount);
	menu.AddItem("count", line);
	if (g_MtDamage >= 1000)
		strcopy(line, sizeof(line), "Damage: instant kill");
	else
		Format(line, sizeof(line), "Damage: %d", g_MtDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Blast radius: %d", RoundToNearest(g_MtRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Knockback: %s", g_MtKnock ? "ON" : "OFF");
	menu.AddItem("knock", line);
	Format(line, sizeof(line), "Hits zombies too: %s", g_MtZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MTHandler(Menu menu, MenuAction action, int client, int item)
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
			MT_Set(!g_MtOn);
			PrintToChatAll(MT_TAG ... "%N turned Meteor Shower %s.", client, g_MtOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned meteor shower %s", client, g_MtOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			MT_Wave();
		else if (StrEqual(info, "every"))
			g_MtEvery = NextInt(g_MtEverySteps, sizeof(g_MtEverySteps), g_MtEvery);
		else if (StrEqual(info, "count"))
			g_MtCount = NextInt(g_MtCountSteps, sizeof(g_MtCountSteps), g_MtCount);
		else if (StrEqual(info, "damage"))
			g_MtDamage = NextInt(g_MtDamageSteps, sizeof(g_MtDamageSteps), g_MtDamage);
		else if (StrEqual(info, "radius"))
			g_MtRadius = NextFloat(g_MtRadiusSteps, sizeof(g_MtRadiusSteps), g_MtRadius);
		else if (StrEqual(info, "knock"))
			g_MtKnock = !g_MtKnock;
		else if (StrEqual(info, "zombies"))
			g_MtZombies = !g_MtZombies;
		MTMenu(client);
	}
	return 0;
}
