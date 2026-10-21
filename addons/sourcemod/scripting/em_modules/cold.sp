// Freezing Cold module of eventmodes.sp.
// eventmodes.sp calls FC_PluginStart; modes.sp calls FC_Tick (every second), FC_RoundStart and FC_Stop.
//
// Once the zombies are out, every N seconds a cold snap hits for a while: humans lose health unless
// enough other humans are close by - huddle up to stay warm.

#if defined _em_cold_included
 #endinput
#endif
#define _em_cold_included

#define FC_TAG "\x07" ... "A0E0FF[Freezing Cold]\x01 "   // kept apart: \x would eat the hex digits

int g_FcEverySteps[] = { 0, 30, 45, 60, 90 };   // 0 = all the time
int g_FcLastSteps[] = { 10, 15, 20, 30 };
int g_FcDamageSteps[] = { 1, 2, 3, 5, 10 };
float g_FcHuddleSteps[] = { 150.0, 250.0, 400.0 };
int g_FcNeedSteps[] = { 1, 2, 3, 5 };

bool g_FcOn;
int g_FcEvery = 45;
int g_FcLast = 15;
int g_FcDamage = 2;
float g_FcHuddle = 250.0;   // "close by"
int g_FcNeed = 1;           // other humans needed close by
bool g_FcActive;
float g_FcNext;
float g_FcEnds;
Handle g_HudCold;

void FC_PluginStart()
{
	g_HudCold = EM_HudSync();
}

bool FC_IsOn()
{
	return g_FcOn;
}

void FC_Stop()
{
	g_FcOn = false;
	g_FcActive = false;
	g_FcNext = 0.0;
}

void FC_Set(bool on)
{
	FC_Stop();
	g_FcOn = on;
}

void FC_RoundStart()
{
	g_FcActive = false;
	g_FcNext = 0.0;
	if (g_FcOn)
		PrintToChatAll(FC_TAG ... "Freezing Cold is on: when the cold snap comes, huddle with other humans!");
}

void FC_Start()
{
	g_FcActive = true;
	g_FcEnds = GetGameTime() + float(g_FcLast);
	PrintToChatAll(FC_TAG ... "A COLD SNAP hits! Stay within %d units of %d other human%s to keep warm.",
		RoundToNearest(g_FcHuddle), g_FcNeed, g_FcNeed == 1 ? "" : "s");
	PrintCenterTextAll("COLD SNAP! HUDDLE UP!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 80);
}

int FC_Neighbours(int client)
{
	float me[3], other[3];
	GetClientAbsOrigin(client, me);
	int n = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsHuman(i))
			continue;
		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(me, other) <= g_FcHuddle)
			n++;
	}
	return n;
}

void FC_Tick()
{
	if (!g_FcOn || !g_RoundLive)
		return;
	if (g_FcEvery == 0)
		g_FcActive = g_ZombiesSeen;   // all the time once the zombies are out
	else if (!g_FcActive)
	{
		if (HazardDue(g_FcOn, g_FcNext, g_FcEvery))
			FC_Start();
		return;
	}
	else if (GetGameTime() >= g_FcEnds)
	{
		g_FcActive = false;
		PrintToChatAll(FC_TAG ... "The cold snap is over.");
		return;
	}
	if (!g_FcActive)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i))
			continue;
		int near = FC_Neighbours(i);
		bool warm = near >= g_FcNeed;
		if (!IsFakeClient(i))
		{
			SetHudTextParams(-1.0, 0.48, 1.1, warm ? 255 : 120, warm ? 200 : 200, 255, 255, 0, 0.0, 0.0, 0.0);
			if (warm)
				EM_ShowHud(i, g_HudCold, "Warm - %d human%s close by", near, near == 1 ? "" : "s");
			else
			{
				EM_ShowHud(i, g_HudCold, "FREEZING! Get close to %d other human%s (-%d HP/s)", g_FcNeed, g_FcNeed == 1 ? "" : "s", g_FcDamage);
				ScreenTint(i, 160, 220, 255, 60, 0.3, 0.6);
			}
		}
		if (!warm)
			HurtPlayer(i, g_FcDamage);
	}
}

// ---------------------------------------------------------------- menu

void FCMenu(int client)
{
	Menu menu = new Menu(FCHandler);
	char line[64];
	menu.SetTitle(g_FcOn ? "Freezing Cold - ON\nStarts when the zombies come\n " : "Freezing Cold - OFF\n ");
	menu.AddItem("toggle", g_FcOn ? "Turn Freezing Cold OFF" : "Turn Freezing Cold ON");
	menu.AddItem("now", "Cold snap now", (g_FcOn && g_RoundLive && !g_FcActive && g_FcEvery > 0) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	if (g_FcEvery == 0)
		strcopy(line, sizeof(line), "Cold snaps: all the time");
	else
		Format(line, sizeof(line), "Cold snaps: every %d s", g_FcEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Cold snap lasts: %d s", g_FcLast);
	menu.AddItem("last", line, g_FcEvery > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Freezing: -%d HP/s", g_FcDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Huddle distance: %d", RoundToNearest(g_FcHuddle));
	menu.AddItem("huddle", line);
	Format(line, sizeof(line), "Humans needed close by: %d", g_FcNeed);
	menu.AddItem("need", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int FCHandler(Menu menu, MenuAction action, int client, int item)
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
			FC_Set(!g_FcOn);
			PrintToChatAll(FC_TAG ... "%N turned Freezing Cold %s.", client, g_FcOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned freezing cold %s", client, g_FcOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			FC_Start();
		else if (StrEqual(info, "every"))
		{
			int next = g_FcEverySteps[0];
			for (int i = 0; i < sizeof(g_FcEverySteps); i++)
			{
				if (g_FcEverySteps[i] > g_FcEvery)
				{
					next = g_FcEverySteps[i];
					break;
				}
			}
			g_FcEvery = next;
			g_FcActive = false;
			g_FcNext = 0.0;
		}
		else if (StrEqual(info, "last"))
			g_FcLast = NextInt(g_FcLastSteps, sizeof(g_FcLastSteps), g_FcLast);
		else if (StrEqual(info, "damage"))
			g_FcDamage = NextInt(g_FcDamageSteps, sizeof(g_FcDamageSteps), g_FcDamage);
		else if (StrEqual(info, "huddle"))
			g_FcHuddle = NextFloat(g_FcHuddleSteps, sizeof(g_FcHuddleSteps), g_FcHuddle);
		else if (StrEqual(info, "need"))
			g_FcNeed = NextInt(g_FcNeedSteps, sizeof(g_FcNeedSteps), g_FcNeed);
		FCMenu(client);
	}
	return 0;
}
