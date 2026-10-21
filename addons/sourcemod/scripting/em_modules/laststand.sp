// Last Stand module of eventmodes.sp.
// modes.sp calls LS_Check (every 0.2 s), LS_Tick (every second), LS_RoundStart and LS_Stop;
// physics.sp asks LS_SpeedMult.
//
// Once a round, when the living humans drop to a set number or fewer (after the zombies came), those
// humans get a health boost, extra speed for the rest of the round and a big "LAST STAND!".

#if defined _em_laststand_included
 #endinput
#endif
#define _em_laststand_included

#define LS_TAG "\x07" ... "FF9020[Last Stand]\x01 "   // kept apart: \x would eat the hex digits

int g_LsAtSteps[] = { 1, 2, 3, 5, 10 };
int g_LsHealthSteps[] = { 0, 50, 100, 250, 500 };
float g_LsSpeedSteps[] = { 1.0, 1.15, 1.3, 1.5 };
int g_LsColor[4] = { 255, 144, 32, 255 };

bool g_LsOn;
int g_LsAt = 3;             // humans left that triggers it
int g_LsHealth = 100;       // health added
float g_LsSpeed = 1.3;
bool g_LsActive;            // happened this round
bool g_LsIn[MAXPLAYERS + 1];

bool LS_IsOn()
{
	return g_LsOn;
}

float LS_SpeedMult(int client)
{
	if (!g_LsOn || !g_LsActive || !g_LsIn[client] || GetClientTeam(client) != CS_TEAM_CT)
		return 1.0;
	return g_LsSpeed;
}

void LS_Clear()
{
	g_LsActive = false;
	for (int i = 1; i <= MaxClients; i++)
		g_LsIn[i] = false;
}

void LS_Stop()
{
	g_LsOn = false;
	LS_Clear();
}

void LS_RoundStart()
{
	LS_Clear();
	if (g_LsOn)
		PrintToChatAll(LS_TAG ... "Last Stand is on: when only %d human%s remain, they get a power boost!", g_LsAt, g_LsAt == 1 ? "" : "s");
}

void LS_Trigger()
{
	g_LsActive = true;
	int n = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsHuman(i))
			continue;
		g_LsIn[i] = true;
		n++;
		if (g_LsHealth > 0)
			SetEntityHealth(i, GetClientHealth(i) + g_LsHealth);
	}
	char bonus[64];
	if (g_LsHealth > 0)
		Format(bonus, sizeof(bonus), "+%d HP", g_LsHealth);
	if (g_LsSpeed > 1.001)
		Format(bonus, sizeof(bonus), "%s%sx%.2f speed", bonus, bonus[0] != '\0' ? ", " : "", g_LsSpeed);
	PrintToChatAll(LS_TAG ... "Only %d human%s left - LAST STAND!%s%s", n, n == 1 ? "" : "s", bonus[0] != '\0' ? " " : "", bonus);
	PrintCenterTextAll("LAST STAND!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 200);
}

void LS_Check()
{
	if (!g_LsOn || !g_RoundLive || g_LsActive || !g_ZombiesSeen)
		return;
	int n = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (IsHuman(i))
			n++;
	if (n > 0 && n <= g_LsAt)
		LS_Trigger();
}

void LS_Tick()
{
	if (!g_LsOn || !g_LsActive)
		return;
	for (int i = 1; i <= MaxClients; i++)
		if (g_LsIn[i] && IsHuman(i))
			Ring(i, g_LsColor, 40.0);
}

// ---------------------------------------------------------------- menu

void LSMenu(int client)
{
	Menu menu = new Menu(LSHandler);
	char line[64];
	menu.SetTitle(g_LsOn ? (g_LsActive ? "Last Stand - ON\nHappening now!\n " : "Last Stand - ON\n ") : "Last Stand - OFF\n ");
	menu.AddItem("toggle", g_LsOn ? "Turn Last Stand OFF" : "Turn Last Stand ON");
	menu.AddItem("now", "Trigger it now", (g_LsOn && g_RoundLive && !g_LsActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Starts when %d human%s or fewer remain", g_LsAt, g_LsAt == 1 ? "" : "s");
	menu.AddItem("at", line);
	Format(line, sizeof(line), "Health boost: +%d", g_LsHealth);
	menu.AddItem("health", line);
	Format(line, sizeof(line), "Speed boost: x%.2f", g_LsSpeed);
	menu.AddItem("speed", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int LSHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_LsOn;
			LS_Stop();
			g_LsOn = on;
			PrintToChatAll(LS_TAG ... "%N turned Last Stand %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned last stand %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			LS_Trigger();
		else if (StrEqual(info, "at"))
			g_LsAt = NextInt(g_LsAtSteps, sizeof(g_LsAtSteps), g_LsAt);
		else if (StrEqual(info, "health"))
			g_LsHealth = NextInt(g_LsHealthSteps, sizeof(g_LsHealthSteps), g_LsHealth);
		else if (StrEqual(info, "speed"))
			g_LsSpeed = NextStep(g_LsSpeedSteps, sizeof(g_LsSpeedSteps), g_LsSpeed);
		LSMenu(client);
	}
	return 0;
}
