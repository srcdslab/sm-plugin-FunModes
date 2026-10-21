// Airstrike module of eventmodes.sp.
// modes.sp calls AS_Tick (every second), AS_RoundStart and AS_Stop.
//
// Once the zombies are out, every N seconds a siren and "AIRSTRIKE INCOMING!" warn everyone; a few
// seconds later a carpet of bombs lands around random humans, one after another.

#if defined _em_airstrike_included
 #endinput
#endif
#define _em_airstrike_included

#define AS_TAG    "\x07" ... "D0D040[Airstrike]\x01 "   // kept apart: \x would eat the hex digits
#define AS_SPREAD 300.0

int g_AsEverySteps[] = { 30, 45, 60, 90, 120 };
int g_AsBombSteps[] = { 5, 10, 15, 25 };
int g_AsWarnSteps[] = { 3, 5, 8 };
int g_AsDamageSteps[] = { 20, 35, 50, 75, 1000 };   // 1000 = kill
float g_AsRadiusSteps[] = { 120.0, 180.0, 250.0 };
int g_AsColor[4] = { 255, 220, 64, 255 };

bool g_AsOn;
int g_AsEvery = 60;
int g_AsBombs = 10;
int g_AsWarn = 5;
int g_AsDamage = 35;
float g_AsRadius = 180.0;
bool g_AsZombies;
float g_AsNext;

bool AS_IsOn()
{
	return g_AsOn;
}

void AS_Stop()
{
	g_AsOn = false;
	g_AsNext = 0.0;
}

void AS_Set(bool on)
{
	AS_Stop();
	g_AsOn = on;
}

void AS_RoundStart()
{
	g_AsNext = 0.0;
	if (g_AsOn)
		PrintToChatAll(AS_TAG ... "Airstrikes are on: when the siren sounds, scatter!");
}

void AS_Call()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	if (n == 0)
		return;
	PrintToChatAll(AS_TAG ... "AIRSTRIKE INCOMING in %d seconds - SCATTER!", g_AsWarn);
	PrintCenterTextAll("AIRSTRIKE INCOMING!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 50);

	// Aim now (where the humans are), bombs fall one by one after the warning.
	for (int k = 0; k < g_AsBombs; k++)
	{
		float pos[3];
		GetClientAbsOrigin(list[k % n], pos);
		pos[0] += GetRandomFloat(-AS_SPREAD, AS_SPREAD);
		pos[1] += GetRandomFloat(-AS_SPREAD, AS_SPREAD);
		DataPack pack;
		CreateDataTimer(float(g_AsWarn) + 0.25 * float(k), AS_Timer_Bomb, pack, TIMER_FLAG_NO_MAPCHANGE);
		pack.WriteCell(g_RoundNum);
		pack.WriteFloat(pos[0]);
		pack.WriteFloat(pos[1]);
		pack.WriteFloat(pos[2]);
	}
}

public Action AS_Timer_Bomb(Handle timer, DataPack pack)
{
	pack.Reset();
	int round = pack.ReadCell();
	float pos[3];
	pos[0] = pack.ReadFloat();
	pos[1] = pack.ReadFloat();
	pos[2] = pack.ReadFloat();
	if (g_AsOn && g_RoundLive && round == g_RoundNum)
	{
		BeamDown(pos, 1200.0, 0.3, 6.0, g_AsColor);
		Explode(pos, g_AsRadius, g_AsDamage, 300.0, g_AsZombies);
	}
	return Plugin_Stop;
}

void AS_Tick()
{
	if (HazardDue(g_AsOn, g_AsNext, g_AsEvery))
		AS_Call();
}

// ---------------------------------------------------------------- menu

void ASMenu(int client)
{
	Menu menu = new Menu(ASHandler);
	char line[64];
	menu.SetTitle(g_AsOn ? "Airstrike - ON\nStarts when the zombies come\n " : "Airstrike - OFF\n ");
	menu.AddItem("toggle", g_AsOn ? "Turn Airstrikes OFF" : "Turn Airstrikes ON");
	menu.AddItem("now", "Call an airstrike now", (g_AsOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_AsEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Bombs: %d", g_AsBombs);
	menu.AddItem("bombs", line);
	Format(line, sizeof(line), "Warning: %d s", g_AsWarn);
	menu.AddItem("warn", line);
	if (g_AsDamage >= 1000)
		strcopy(line, sizeof(line), "Damage per bomb: instant kill");
	else
		Format(line, sizeof(line), "Damage per bomb: %d", g_AsDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Blast radius: %d", RoundToNearest(g_AsRadius));
	menu.AddItem("radius", line);
	Format(line, sizeof(line), "Hits zombies too: %s", g_AsZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ASHandler(Menu menu, MenuAction action, int client, int item)
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
			AS_Set(!g_AsOn);
			PrintToChatAll(AS_TAG ... "%N turned Airstrikes %s.", client, g_AsOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned airstrikes %s", client, g_AsOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			AS_Call();
		else if (StrEqual(info, "every"))
			g_AsEvery = NextInt(g_AsEverySteps, sizeof(g_AsEverySteps), g_AsEvery);
		else if (StrEqual(info, "bombs"))
			g_AsBombs = NextInt(g_AsBombSteps, sizeof(g_AsBombSteps), g_AsBombs);
		else if (StrEqual(info, "warn"))
			g_AsWarn = NextInt(g_AsWarnSteps, sizeof(g_AsWarnSteps), g_AsWarn);
		else if (StrEqual(info, "damage"))
			g_AsDamage = NextInt(g_AsDamageSteps, sizeof(g_AsDamageSteps), g_AsDamage);
		else if (StrEqual(info, "radius"))
			g_AsRadius = NextFloat(g_AsRadiusSteps, sizeof(g_AsRadiusSteps), g_AsRadius);
		else if (StrEqual(info, "zombies"))
			g_AsZombies = !g_AsZombies;
		ASMenu(client);
	}
	return 0;
}
