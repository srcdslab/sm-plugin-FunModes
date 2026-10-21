// Buddy System module of eventmodes.sp.
// modes.sp calls Buddy_PluginStart, Buddy_Check (every 0.2 s), Buddy_Tick (every second),
// Buddy_RoundStart and Buddy_Stop.
//
// Once the zombies are out, the living humans are paired up at random (with an odd number, one goes
// solo). If your buddy dies or is infected, you die too - or bleed until you're healed or dead,
// depending on the setting. Optionally you also bleed while you're too far from your buddy.

#if defined _em_buddy_included
 #endinput
#endif
#define _em_buddy_included

#define BD_TAG "\x07" ... "40C0FF[Buddy]\x01 "   // kept apart: \x would eat the hex digits

int g_BdBleeds[] = { 1, 2, 3, 5, 10 };
float g_BdDistances[] = { 0.0, 500.0, 800.0, 1200.0, 2000.0 };   // 0 = no distance rule

bool g_BdOn;
bool g_BdDie = true;        // buddy falls -> you die (else you bleed)
int g_BdBleed = 3;          // HP per second when bleeding / too far
float g_BdMaxDist;          // 0 = off
bool g_BdPaired;            // pairs made this round
int g_Buddy[MAXPLAYERS + 1];        // buddy's userid, 0 = none
bool g_BdBleeding[MAXPLAYERS + 1];
bool g_BdSolo[MAXPLAYERS + 1];      // odd one out this round
Handle g_HudBuddy;

void Buddy_PluginStart()
{
	g_HudBuddy = EM_HudSync();
}

void Buddy_Clear()
{
	g_BdPaired = false;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_Buddy[i] = 0;
		g_BdBleeding[i] = false;
		g_BdSolo[i] = false;
	}
}

void Buddy_Stop()
{
	g_BdOn = false;
	Buddy_Clear();
}

void Buddy_RoundStart()
{
	Buddy_Clear();
	if (g_BdOn)
		PrintToChatAll(BD_TAG ... "Buddy System is on: you get a buddy when the zombies come - keep them alive!");
}

void Buddy_Pair()
{
	Buddy_Clear();
	g_BdPaired = true;

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

	for (int k = 0; k + 1 < n; k += 2)
	{
		int a = list[k], b = list[k + 1];
		g_Buddy[a] = GetClientUserId(b);
		g_Buddy[b] = GetClientUserId(a);
		PrintToChat(a, BD_TAG ... "Your buddy is \x07" ... "40C0FF%N\x01. If they fall, %s", b, g_BdDie ? "so do you!" : "you start bleeding!");
		PrintToChat(b, BD_TAG ... "Your buddy is \x07" ... "40C0FF%N\x01. If they fall, %s", a, g_BdDie ? "so do you!" : "you start bleeding!");
	}
	if (n % 2 == 1)
	{
		g_BdSolo[list[n - 1]] = true;
		PrintToChat(list[n - 1], BD_TAG ... "Odd one out - you're on your own this round.");
	}
	PrintToChatAll(BD_TAG ... "Buddies are paired! %s", g_BdDie ? "If your buddy falls, you fall with them." : "If your buddy falls, you bleed.");
}

void Buddy_Check(bool zombiesNow)
{
	if (!g_BdOn || !g_RoundLive)
		return;
	if (!g_BdPaired)
	{
		if (zombiesNow)
			Buddy_Pair();
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_Buddy[i] == 0 || !IsHuman(i))
			continue;
		int b = GetClientOfUserId(g_Buddy[i]);
		if (b != 0 && IsHuman(b))
			continue;

		g_Buddy[i] = 0;
		if (b == 0)
		{
			// Left the server: not the buddy's fault.
			g_BdSolo[i] = true;
			PrintToChat(i, BD_TAG ... "Your buddy left the server - you're on your own now.");
		}
		else if (g_BdDie)
		{
			PrintToChatAll(BD_TAG ... "%N fell, and takes their buddy %N with them!", b, i);
			ForcePlayerSuicide(i);
		}
		else
		{
			g_BdBleeding[i] = true;
			PrintToChat(i, BD_TAG ... "Your buddy %N fell - you're bleeding %d HP/s!", b, g_BdBleed);
		}
	}
}

void Buddy_Hurt(int client)
{
	int hp = GetClientHealth(client) - g_BdBleed;
	if (hp <= 0)
		ForcePlayerSuicide(client);
	else
		SetEntityHealth(client, hp);
}

void Buddy_Tick()
{
	if (!g_BdOn || !g_BdPaired)
		return;
	float me[3], them[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;
		bool human = IsHuman(i);
		int b = g_Buddy[i] != 0 ? GetClientOfUserId(g_Buddy[i]) : 0;

		if (human && g_BdBleeding[i])
		{
			Buddy_Hurt(i);
			if (!IsFakeClient(i))
			{
				SetHudTextParams(-1.0, 0.22, 1.1, 255, 60, 60, 255, 0, 0.0, 0.0, 0.0);
				EM_ShowHud(i, g_HudBuddy, "YOUR BUDDY FELL - BLEEDING %d HP/s", g_BdBleed);
			}
			continue;
		}
		if (!human)
			continue;

		if (b != 0 && IsHuman(b))
		{
			GetClientAbsOrigin(i, me);
			GetClientAbsOrigin(b, them);
			int dist = RoundToNearest(GetVectorDistance(me, them));
			bool far = g_BdMaxDist > 0.0 && dist > g_BdMaxDist;
			if (far)
				Buddy_Hurt(i);
			if (IsFakeClient(i))
				continue;
			if (far)
			{
				SetHudTextParams(-1.0, 0.22, 1.1, 255, 60, 60, 255, 0, 0.0, 0.0, 0.0);
				EM_ShowHud(i, g_HudBuddy, "TOO FAR FROM YOUR BUDDY %N (%d) - GET BACK! -%d HP/s", b, dist, g_BdBleed);
			}
			else
			{
				SetHudTextParams(-1.0, 0.22, 1.1, 64, 192, 255, 255, 0, 0.0, 0.0, 0.0);
				EM_ShowHud(i, g_HudBuddy, "Buddy: %N (%d units away)", b, dist);
			}
		}
		else if (g_BdSolo[i] && !IsFakeClient(i))
		{
			SetHudTextParams(-1.0, 0.22, 1.1, 64, 192, 255, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudBuddy, "No buddy - you're on your own");
		}
	}
}

// ---------------------------------------------------------------- menu

void BuddyMenu(int client)
{
	Menu menu = new Menu(BuddyHandler);
	char line[64];
	if (!g_BdOn)
		menu.SetTitle("Buddy System - OFF\n ");
	else
		menu.SetTitle(g_BdPaired ? "Buddy System - ON\nBuddies are paired this round\n " : "Buddy System - ON\nPairs are made when the zombies come\n ");

	menu.AddItem("toggle", g_BdOn ? "Turn Buddy System OFF" : "Turn Buddy System ON");
	menu.AddItem("pair", "Make new pairs now", (g_BdOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "If your buddy falls: %s", g_BdDie ? "you die" : "you bleed");
	menu.AddItem("die", line);
	Format(line, sizeof(line), "Bleed: %d HP/s", g_BdBleed);
	menu.AddItem("bleed", line);
	if (g_BdMaxDist <= 0.0)
		strcopy(line, sizeof(line), "Stay close to your buddy: off");
	else
		Format(line, sizeof(line), "Stay within %d of your buddy", RoundToNearest(g_BdMaxDist));
	menu.AddItem("dist", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BuddyHandler(Menu menu, MenuAction action, int client, int item)
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
			if (g_BdOn)
				Buddy_Stop();
			else
			{
				g_BdOn = true;
				Buddy_Clear();
			}
			PrintToChatAll(BD_TAG ... "%N turned the Buddy System %s.", client, g_BdOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned the buddy system %s", client, g_BdOn ? "on" : "off");
		}
		else if (StrEqual(info, "pair"))
			Buddy_Pair();
		else if (StrEqual(info, "die"))
			g_BdDie = !g_BdDie;
		else if (StrEqual(info, "bleed"))
			g_BdBleed = NextInt(g_BdBleeds, sizeof(g_BdBleeds), g_BdBleed);
		else if (StrEqual(info, "dist"))
		{
			float next = g_BdDistances[0];
			for (int i = 0; i < sizeof(g_BdDistances); i++)
			{
				if (g_BdDistances[i] > g_BdMaxDist + 0.5)
				{
					next = g_BdDistances[i];
					break;
				}
			}
			g_BdMaxDist = next;
		}
		BuddyMenu(client);
	}
	return 0;
}

bool Buddy_IsOn()
{
	return g_BdOn;
}
