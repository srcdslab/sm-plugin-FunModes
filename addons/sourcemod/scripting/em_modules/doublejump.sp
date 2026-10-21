// Double Jump module of eventmodes.sp.
// eventmodes.sp calls DJ_RunCmd (every player command); modes.sp calls DJ_Stop.
//
// While on, players can jump again in mid-air (one or more extra jumps), each giving an upward boost.
// Humans, zombies or both. Landing gives the jumps back.

#if defined _em_doublejump_included
 #endinput
#endif
#define _em_doublejump_included

#define DJ_TAG "\x07" ... "80FFFF[Double Jump]\x01 "   // kept apart: \x would eat the hex digits

float g_DjBoostSteps[] = { 200.0, 260.0, 300.0, 350.0, 450.0 };
int g_DjJumpSteps[] = { 1, 2, 3, 5 };

bool g_DjOn;
float g_DjBoost = 260.0;    // upward speed of a mid-air jump
int g_DjJumps = 1;          // extra jumps before landing
bool g_DjHumans = true;
bool g_DjZombies;
int g_DjUsed[MAXPLAYERS + 1];
int g_DjLastButtons[MAXPLAYERS + 1];

bool DJ_IsOn()
{
	return g_DjOn;
}

void DJ_Stop()
{
	g_DjOn = false;
}

void DJ_Set(bool on)
{
	g_DjOn = on;
	for (int i = 1; i <= MaxClients; i++)
		g_DjUsed[i] = 0;
}

void DJ_RunCmd(int client, int buttons)
{
	int last = g_DjLastButtons[client];
	g_DjLastButtons[client] = buttons;
	if (!g_DjOn || !IsPlayerAlive(client))
		return;
	int team = GetClientTeam(client);
	if (!((team == CS_TEAM_CT && g_DjHumans) || (team == CS_TEAM_T && g_DjZombies)))
		return;
	int flags = GetEntityFlags(client);
	if (flags & FL_ONGROUND)
	{
		g_DjUsed[client] = 0;
		return;
	}
	if (!(buttons & IN_JUMP) || (last & IN_JUMP) || g_DjUsed[client] >= g_DjJumps)
		return;
	if (GetEntityMoveType(client) == MOVETYPE_LADDER || (flags & FL_INWATER))
		return;
	g_DjUsed[client]++;
	float vel[3];
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
	vel[2] = g_DjBoost;
	TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
}

// ---------------------------------------------------------------- menu

void DJMenu(int client)
{
	Menu menu = new Menu(DJHandler);
	char line[64];
	menu.SetTitle(g_DjOn ? "Double Jump - ON\n " : "Double Jump - OFF\n ");
	menu.AddItem("toggle", g_DjOn ? "Turn Double Jump OFF" : "Turn Double Jump ON");
	Format(line, sizeof(line), "Jump boost: %d", RoundToNearest(g_DjBoost));
	menu.AddItem("boost", line);
	Format(line, sizeof(line), "Extra jumps in the air: %d", g_DjJumps);
	menu.AddItem("jumps", line);
	Format(line, sizeof(line), "Humans: %s", g_DjHumans ? "ON" : "OFF");
	menu.AddItem("humans", line);
	Format(line, sizeof(line), "Zombies: %s", g_DjZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int DJHandler(Menu menu, MenuAction action, int client, int item)
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
			DJ_Set(!g_DjOn);
			PrintToChatAll(DJ_TAG ... "%N turned Double Jump %s.", client, g_DjOn ? "ON - jump again in mid-air!" : "OFF");
			LogAction(client, -1, "\"%L\" turned double jump %s", client, g_DjOn ? "on" : "off");
		}
		else if (StrEqual(info, "boost"))
			g_DjBoost = NextFloat(g_DjBoostSteps, sizeof(g_DjBoostSteps), g_DjBoost);
		else if (StrEqual(info, "jumps"))
			g_DjJumps = NextInt(g_DjJumpSteps, sizeof(g_DjJumpSteps), g_DjJumps);
		else if (StrEqual(info, "humans"))
			g_DjHumans = !g_DjHumans;
		else if (StrEqual(info, "zombies"))
			g_DjZombies = !g_DjZombies;
		DJMenu(client);
	}
	return 0;
}
