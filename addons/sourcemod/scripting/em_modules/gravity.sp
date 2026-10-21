// Gravity Waves module of eventmodes.sp.
// modes.sp calls GW_Tick (every second), GW_RoundStart and GW_Stop; physics.sp asks GW_GravityMult.
//
// Once the zombies are out, every N seconds gravity drops for a few seconds: huge, floaty jumps.

#if defined _em_gravity_included
 #endinput
#endif
#define _em_gravity_included

#define GW_TAG "\x07" ... "A0A0FF[Gravity Waves]\x01 "   // kept apart: \x would eat the hex digits

int g_GwEverySteps[] = { 20, 30, 45, 60, 90 };
int g_GwLastSteps[] = { 3, 5, 8, 10, 15 };
float g_GwGravSteps[] = { 0.15, 0.25, 0.4, 0.6 };

bool g_GwOn;
int g_GwEvery = 45;
int g_GwLast = 8;
float g_GwGrav = 0.25;      // x normal gravity
bool g_GwEveryone = true;   // zombies float too
bool g_GwActive;
float g_GwNext;
float g_GwEnds;

bool GW_IsOn()
{
	return g_GwOn;
}

float GW_GravityMult(int client)
{
	return (g_GwOn && g_GwActive && HazardHits(client, g_GwEveryone)) ? g_GwGrav : 1.0;
}

void GW_Stop()
{
	g_GwOn = false;
	g_GwActive = false;
	g_GwNext = 0.0;
}

void GW_Set(bool on)
{
	GW_Stop();
	g_GwOn = on;
}

void GW_RoundStart()
{
	g_GwActive = false;
	g_GwNext = 0.0;
	if (g_GwOn)
		PrintToChatAll(GW_TAG ... "Gravity Waves are on: sometimes gravity just... lets go.");
}

void GW_Start()
{
	g_GwActive = true;
	g_GwEnds = GetGameTime() + float(g_GwLast);
	PrintToChatAll(GW_TAG ... "GRAVITY WAVE! Low gravity for %d seconds!", g_GwLast);
	PrintCenterTextAll("LOW GRAVITY!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 210);
}

void GW_Tick()
{
	if (!g_GwOn || !g_RoundLive)
		return;
	if (g_GwActive)
	{
		if (GetGameTime() >= g_GwEnds)
		{
			g_GwActive = false;
			PrintCenterTextAll("Gravity is back to normal");
		}
		return;
	}
	if (HazardDue(g_GwOn, g_GwNext, g_GwEvery))
		GW_Start();
}

// ---------------------------------------------------------------- menu

void GWMenu(int client)
{
	Menu menu = new Menu(GWHandler);
	char line[64];
	menu.SetTitle(g_GwOn ? "Gravity Waves - ON\nStarts when the zombies come\n " : "Gravity Waves - OFF\n ");
	menu.AddItem("toggle", g_GwOn ? "Turn Gravity Waves OFF" : "Turn Gravity Waves ON");
	menu.AddItem("now", "Gravity wave now", (g_GwOn && g_RoundLive && !g_GwActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_GwEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Lasts: %d s", g_GwLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Gravity: %d%% of normal", RoundToNearest(g_GwGrav * 100.0));
	menu.AddItem("grav", line);
	Format(line, sizeof(line), "Who floats: %s", g_GwEveryone ? "everyone" : "humans only");
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int GWHandler(Menu menu, MenuAction action, int client, int item)
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
			GW_Set(!g_GwOn);
			PrintToChatAll(GW_TAG ... "%N turned Gravity Waves %s.", client, g_GwOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned gravity waves %s", client, g_GwOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			GW_Start();
		else if (StrEqual(info, "every"))
			g_GwEvery = NextInt(g_GwEverySteps, sizeof(g_GwEverySteps), g_GwEvery);
		else if (StrEqual(info, "last"))
			g_GwLast = NextInt(g_GwLastSteps, sizeof(g_GwLastSteps), g_GwLast);
		else if (StrEqual(info, "grav"))
			g_GwGrav = NextStep(g_GwGravSteps, sizeof(g_GwGravSteps), g_GwGrav);
		else if (StrEqual(info, "who"))
			g_GwEveryone = !g_GwEveryone;
		GWMenu(client);
	}
	return 0;
}
