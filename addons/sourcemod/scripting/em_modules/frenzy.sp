// Zombie Frenzy module of eventmodes.sp.
// modes.sp calls ZF_Tick (every second), ZF_RoundStart and ZF_Stop; physics.sp asks ZF_SpeedMult.
//
// Once the zombies are out, every N seconds the zombies go into a frenzy for a few seconds: much
// faster, with a red flash on the humans' screens and a warning.

#if defined _em_frenzy_included
 #endinput
#endif
#define _em_frenzy_included

#define ZF_TAG "\x07" ... "FF2040[Zombie Frenzy]\x01 "   // kept apart: \x would eat the hex digits

int g_ZfEverySteps[] = { 20, 30, 45, 60, 90 };
int g_ZfLastSteps[] = { 3, 5, 8, 10 };
float g_ZfSpeedSteps[] = { 1.2, 1.35, 1.5, 1.75, 2.0 };
int g_ZfColor[4] = { 255, 32, 64, 255 };

bool g_ZfOn;
int g_ZfEvery = 45;
int g_ZfLast = 5;
float g_ZfSpeed = 1.5;
bool g_ZfActive;
float g_ZfNext;
float g_ZfEnds;

bool ZF_IsOn()
{
	return g_ZfOn;
}

float ZF_SpeedMult(int client)
{
	if (!g_ZfOn || !g_ZfActive || GetClientTeam(client) != CS_TEAM_T)
		return 1.0;
	return g_ZfSpeed;
}

void ZF_Stop()
{
	g_ZfOn = false;
	g_ZfActive = false;
	g_ZfNext = 0.0;
}

void ZF_Set(bool on)
{
	ZF_Stop();
	g_ZfOn = on;
}

void ZF_RoundStart()
{
	g_ZfActive = false;
	g_ZfNext = 0.0;
	if (g_ZfOn)
		PrintToChatAll(ZF_TAG ... "Zombie Frenzy is on: when the screen flashes red, the zombies get FAST!");
}

void ZF_Start()
{
	g_ZfActive = true;
	g_ZfEnds = GetGameTime() + float(g_ZfLast);
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i) && GetClientTeam(i) == CS_TEAM_CT)
			ScreenTint(i, 255, 0, 0, 90, 0.3, 1.0);
	PrintToChatAll(ZF_TAG ... "THE ZOMBIES ARE IN A FRENZY for %d seconds!", g_ZfLast);
	PrintCenterTextAll("ZOMBIE FRENZY!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 35);
}

void ZF_Tick()
{
	if (!g_ZfOn || !g_RoundLive)
		return;
	if (g_ZfActive)
	{
		if (GetGameTime() >= g_ZfEnds)
		{
			g_ZfActive = false;
			PrintCenterTextAll("The frenzy is over");
			return;
		}
		for (int i = 1; i <= MaxClients; i++)
			if (IsClientInGame(i) && IsPlayerAlive(i) && GetClientTeam(i) == CS_TEAM_T)
				Ring(i, g_ZfColor, 30.0);
		return;
	}
	if (HazardDue(g_ZfOn, g_ZfNext, g_ZfEvery))
		ZF_Start();
}

// ---------------------------------------------------------------- menu

void ZFMenu(int client)
{
	Menu menu = new Menu(ZFHandler);
	char line[64];
	menu.SetTitle(g_ZfOn ? "Zombie Frenzy - ON\nStarts when the zombies come\n " : "Zombie Frenzy - OFF\n ");
	menu.AddItem("toggle", g_ZfOn ? "Turn Zombie Frenzy OFF" : "Turn Zombie Frenzy ON");
	menu.AddItem("now", "Frenzy now", (g_ZfOn && g_RoundLive && !g_ZfActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_ZfEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Lasts: %d s", g_ZfLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Zombie speed: x%.2f", g_ZfSpeed);
	menu.AddItem("speed", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ZFHandler(Menu menu, MenuAction action, int client, int item)
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
			ZF_Set(!g_ZfOn);
			PrintToChatAll(ZF_TAG ... "%N turned Zombie Frenzy %s.", client, g_ZfOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned zombie frenzy %s", client, g_ZfOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			ZF_Start();
		else if (StrEqual(info, "every"))
			g_ZfEvery = NextInt(g_ZfEverySteps, sizeof(g_ZfEverySteps), g_ZfEvery);
		else if (StrEqual(info, "last"))
			g_ZfLast = NextInt(g_ZfLastSteps, sizeof(g_ZfLastSteps), g_ZfLast);
		else if (StrEqual(info, "speed"))
			g_ZfSpeed = NextStep(g_ZfSpeedSteps, sizeof(g_ZfSpeedSteps), g_ZfSpeed);
		ZFMenu(client);
	}
	return 0;
}
