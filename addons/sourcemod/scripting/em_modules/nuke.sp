// Nuke Countdown module of eventmodes.sp.
// eventmodes.sp calls NK_PluginStart; modes.sp calls NK_Tick (every second), NK_RoundStart and NK_Stop.
//
// Once the zombies are out, every N seconds (or once a round) a siren sounds and a countdown starts.
// A glowing bunker ring appears near a random human. At zero there's a blinding flash, and everyone
// outside the bunker is hit hard.

#if defined _em_nuke_included
 #endinput
#endif
#define _em_nuke_included

#define NK_TAG "\x07" ... "FFFF40[Nuke]\x01 "   // kept apart: \x would eat the hex digits

int g_NkEverySteps[] = { 0, 60, 90, 120, 180 };   // 0 = once a round
int g_NkCountSteps[] = { 10, 15, 20, 30 };
float g_NkBunkerSteps[] = { 200.0, 300.0, 400.0, 600.0 };
int g_NkDamageSteps[] = { 50, 75, 100, 1000 };   // 1000 = kill
int g_NkBunkerColor[4] = { 64, 255, 64, 255 };

bool g_NkOn;
int g_NkEvery = 0;
int g_NkCount = 20;         // countdown seconds
float g_NkBunker = 300.0;   // bunker radius
int g_NkDamage = 100;
bool g_NkZombies;           // zombies outside the bunker get hit too

float g_NkNext;
bool g_NkDoneThisRound;
bool g_NkActive;
float g_NkAt;               // when it goes off
float g_NkPos[3];           // the bunker
Handle g_HudNuke;

void NK_PluginStart()
{
	g_HudNuke = EM_HudSync();
}

bool NK_IsOn()
{
	return g_NkOn;
}

void NK_Stop()
{
	g_NkOn = false;
	g_NkActive = false;
	g_NkNext = 0.0;
	g_NkDoneThisRound = false;
}

void NK_Set(bool on)
{
	NK_Stop();
	g_NkOn = on;
}

void NK_RoundStart()
{
	g_NkActive = false;
	g_NkNext = 0.0;
	g_NkDoneThisRound = false;
	if (g_NkOn)
		PrintToChatAll(NK_TAG ... "Nuke Countdown is on: when the siren sounds, get to the green bunker!");
}

void NK_Launch()
{
	int list[MAXPLAYERS + 1];
	if (ShuffledHumans(list) == 0)
		return;
	GetClientAbsOrigin(list[0], g_NkPos);
	g_NkAt = GetGameTime() + float(g_NkCount);
	g_NkActive = true;
	g_NkDoneThisRound = true;
	PrintToChatAll(NK_TAG ... "NUCLEAR STRIKE IN %d SECONDS! Get to the green bunker near %N!", g_NkCount, list[0]);
	PrintCenterTextAll("NUCLEAR STRIKE IN %d SECONDS!", g_NkCount);
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 40);
}

void NK_Detonate()
{
	g_NkActive = false;
	float pos[3];
	int hit = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		ScreenTint(i, 255, 255, 255, 255, 1.0, 3.0);
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_NkZombies))
			continue;
		GetClientAbsOrigin(i, pos);
		if (GetVectorDistance(pos, g_NkPos) <= g_NkBunker)
			continue;
		hit++;
		HurtPlayer(i, g_NkDamage);
	}
	EmitSoundToAll(EXPLODE_SOUND, _, _, _, _, _, 40);
	PrintToChatAll(NK_TAG ... "BOOM! %d player%s caught outside the bunker.", hit, hit == 1 ? " was" : "s were");
}

void NK_Tick()
{
	if (!g_NkOn || !g_RoundLive)
		return;
	if (g_NkActive)
	{
		int left = RoundToCeil(g_NkAt - GetGameTime());
		if (left <= 0)
		{
			NK_Detonate();
			return;
		}
		RingAt(g_NkPos, g_NkBunker, g_NkBunker, 1.0, g_NkBunkerColor, 14.0);
		BeamDown(g_NkPos, 800.0, 1.0, 16.0, g_NkBunkerColor);
		if (left <= 5)
			EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 200);
		float pos[3];
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;
			bool safe = false;
			if (IsPlayerAlive(i))
			{
				GetClientAbsOrigin(i, pos);
				safe = GetVectorDistance(pos, g_NkPos) <= g_NkBunker;
			}
			SetHudTextParams(-1.0, 0.32, 1.1, safe ? 64 : 255, 255, safe ? 64 : 64, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudNuke, "NUCLEAR STRIKE IN %d\n%s", left, safe ? "You're in the bunker" : "GET TO THE GREEN BUNKER!");
		}
		return;
	}
	if (g_NkEvery == 0)
	{
		// Once a round, a little after the zombies come.
		if (!g_NkDoneThisRound && g_ZombiesSeen)
		{
			if (g_NkNext == 0.0)
				g_NkNext = GetGameTime() + 20.0;
			if (GetGameTime() >= g_NkNext)
				NK_Launch();
		}
	}
	else if (HazardDue(g_NkOn, g_NkNext, g_NkEvery))
		NK_Launch();
}

// ---------------------------------------------------------------- menu

void NKMenu(int client)
{
	Menu menu = new Menu(NKHandler);
	char line[64];
	menu.SetTitle(g_NkOn ? "Nuke Countdown - ON\n " : "Nuke Countdown - OFF\n ");
	menu.AddItem("toggle", g_NkOn ? "Turn Nuke Countdown OFF" : "Turn Nuke Countdown ON");
	menu.AddItem("now", "Launch a nuke now", (g_NkOn && g_RoundLive && !g_NkActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	if (g_NkEvery == 0)
		strcopy(line, sizeof(line), "How often: once a round");
	else
		Format(line, sizeof(line), "How often: every %d s", g_NkEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Countdown: %d s", g_NkCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Bunker size: %d", RoundToNearest(g_NkBunker));
	menu.AddItem("bunker", line);
	if (g_NkDamage >= 1000)
		strcopy(line, sizeof(line), "Outside the bunker: dead");
	else
		Format(line, sizeof(line), "Outside the bunker: -%d HP", g_NkDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Hits zombies too: %s", g_NkZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int NKHandler(Menu menu, MenuAction action, int client, int item)
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
			NK_Set(!g_NkOn);
			PrintToChatAll(NK_TAG ... "%N turned Nuke Countdown %s.", client, g_NkOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned nuke countdown %s", client, g_NkOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			NK_Launch();
		else if (StrEqual(info, "every"))
		{
			int next = g_NkEverySteps[0];
			for (int i = 0; i < sizeof(g_NkEverySteps); i++)
			{
				if (g_NkEverySteps[i] > g_NkEvery)
				{
					next = g_NkEverySteps[i];
					break;
				}
			}
			g_NkEvery = next;
			g_NkNext = 0.0;
		}
		else if (StrEqual(info, "count"))
			g_NkCount = NextInt(g_NkCountSteps, sizeof(g_NkCountSteps), g_NkCount);
		else if (StrEqual(info, "bunker"))
			g_NkBunker = NextFloat(g_NkBunkerSteps, sizeof(g_NkBunkerSteps), g_NkBunker);
		else if (StrEqual(info, "damage"))
			g_NkDamage = NextInt(g_NkDamageSteps, sizeof(g_NkDamageSteps), g_NkDamage);
		else if (StrEqual(info, "zombies"))
			g_NkZombies = !g_NkZombies;
		NKMenu(client);
	}
	return 0;
}
