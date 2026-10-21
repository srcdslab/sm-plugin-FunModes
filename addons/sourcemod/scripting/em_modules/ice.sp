// Ice Floor module of eventmodes.sp.
// modes.sp calls IF_Tick (every second), IF_RoundStart and IF_Stop.
//
// Once the zombies are out, every N seconds the floor freezes over for a while: everyone slides around
// as if on ice. It lowers the server's sv_friction for that time (quietly, without the "cvar changed"
// chat spam) and always puts it back.

#if defined _em_ice_included
 #endinput
#endif
#define _em_ice_included

#define IF_TAG "\x07" ... "C0F0FF[Ice Floor]\x01 "   // kept apart: \x would eat the hex digits

char g_IfLevelNames[][] = { "slippery", "very slippery", "ice rink", "pure ice" };
float g_IfLevelFriction[] = { 2.0, 1.0, 0.5, 0.15 };   // normal sv_friction is 4
int g_IfEverySteps[] = { 20, 30, 45, 60, 90 };
int g_IfLastSteps[] = { 5, 8, 10, 15, 20 };

bool g_IfOn;
int g_IfEvery = 45;
int g_IfLast = 10;
int g_IfLevel = 1;
bool g_IfActive;
float g_IfNext;
float g_IfEnds;
bool g_IfApplied;           // we changed sv_friction
float g_IfOldFriction;

bool IF_IsOn()
{
	return g_IfOn;
}

void IF_SetFriction(float value)
{
	ConVar cv = FindConVar("sv_friction");
	if (cv == null)
		return;
	int flags = cv.Flags;
	cv.Flags = flags & ~FCVAR_NOTIFY;
	cv.FloatValue = value;
	cv.Flags = flags;
}

void IF_Freeze(bool on)
{
	ConVar cv = FindConVar("sv_friction");
	if (cv == null)
		return;
	if (on)
	{
		if (!g_IfApplied)
			g_IfOldFriction = cv.FloatValue;
		g_IfApplied = true;
		IF_SetFriction(g_IfLevelFriction[g_IfLevel]);
	}
	else if (g_IfApplied)
	{
		IF_SetFriction(g_IfOldFriction);
		g_IfApplied = false;
	}
}

void IF_Stop()
{
	g_IfOn = false;
	g_IfActive = false;
	g_IfNext = 0.0;
	IF_Freeze(false);
}

void IF_Set(bool on)
{
	IF_Stop();
	g_IfOn = on;
}

void IF_RoundStart()
{
	g_IfActive = false;
	g_IfNext = 0.0;
	IF_Freeze(false);
	if (g_IfOn)
		PrintToChatAll(IF_TAG ... "Ice Floor is on: sometimes the ground freezes - mind your step!");
}

void IF_RoundEnd()
{
	g_IfActive = false;
	IF_Freeze(false);
}

void IF_Start()
{
	g_IfActive = true;
	g_IfEnds = GetGameTime() + float(g_IfLast);
	IF_Freeze(true);
	PrintToChatAll(IF_TAG ... "THE FLOOR IS FROZEN for %d seconds!", g_IfLast);
	PrintCenterTextAll("THE FLOOR IS ICE!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 230);
}

void IF_Tick()
{
	if (!g_IfOn)
		return;
	if (g_IfActive)
	{
		if (!g_RoundLive || GetGameTime() >= g_IfEnds)
		{
			g_IfActive = false;
			IF_Freeze(false);
			PrintCenterTextAll("The ice has melted");
		}
		return;
	}
	if (HazardDue(g_IfOn, g_IfNext, g_IfEvery))
		IF_Start();
}

// ---------------------------------------------------------------- menu

void IFMenu(int client)
{
	Menu menu = new Menu(IFHandler);
	char line[64];
	menu.SetTitle(g_IfOn ? "Ice Floor - ON\nStarts when the zombies come\n " : "Ice Floor - OFF\n ");
	menu.AddItem("toggle", g_IfOn ? "Turn Ice Floor OFF" : "Turn Ice Floor ON");
	menu.AddItem("now", "Freeze the floor now", (g_IfOn && g_RoundLive && !g_IfActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_IfEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Lasts: %d s", g_IfLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "How slippery: %s", g_IfLevelNames[g_IfLevel]);
	menu.AddItem("level", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int IFHandler(Menu menu, MenuAction action, int client, int item)
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
			IF_Set(!g_IfOn);
			PrintToChatAll(IF_TAG ... "%N turned Ice Floor %s.", client, g_IfOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned ice floor %s", client, g_IfOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			IF_Start();
		else if (StrEqual(info, "every"))
			g_IfEvery = NextInt(g_IfEverySteps, sizeof(g_IfEverySteps), g_IfEvery);
		else if (StrEqual(info, "last"))
			g_IfLast = NextInt(g_IfLastSteps, sizeof(g_IfLastSteps), g_IfLast);
		else if (StrEqual(info, "level"))
		{
			g_IfLevel = (g_IfLevel + 1) % sizeof(g_IfLevelNames);
			if (g_IfActive)
				IF_SetFriction(g_IfLevelFriction[g_IfLevel]);
		}
		IFMenu(client);
	}
	return 0;
}
