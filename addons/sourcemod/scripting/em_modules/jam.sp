// Jammed Guns module of eventmodes.sp.
// eventmodes.sp calls JG_RunCmd (every player command); modes.sp calls JG_Tick (every second),
// JG_RoundStart and JG_Stop.
//
// Once the zombies are out, every N seconds some humans' guns jam: they can't shoot for a few seconds.
// The fire buttons are blocked and the weapon's next shot is pushed back, so it doesn't even look like
// it fires on their screen.

#if defined _em_jam_included
 #endinput
#endif
#define _em_jam_included

#define JG_TAG "\x07" ... "D0A060[Jammed]\x01 "   // kept apart: \x would eat the hex digits

int g_JgEverySteps[] = { 15, 20, 30, 45, 60 };
int g_JgCountSteps[] = { 1, 2, 3, 5, 64 };   // 64 = everyone
int g_JgLastSteps[] = { 2, 3, 5, 8 };

bool g_JgOn;
int g_JgEvery = 30;
int g_JgCount = 3;
int g_JgLast = 3;
float g_JgNext;
float g_JgUntil[MAXPLAYERS + 1];

bool JG_IsOn()
{
	return g_JgOn;
}

void JG_Clear()
{
	g_JgNext = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_JgUntil[i] = 0.0;
}

void JG_Stop()
{
	g_JgOn = false;
	JG_Clear();
}

void JG_Set(bool on)
{
	JG_Stop();
	g_JgOn = on;
}

void JG_RoundStart()
{
	JG_Clear();
	if (g_JgOn)
		PrintToChatAll(JG_TAG ... "Jammed Guns is on: your gun might stop working at the worst moment!");
}

bool JG_Jammed(int client)
{
	return g_JgOn && g_JgUntil[client] > GetGameTime();
}

// Strips the fire buttons while jammed. True when it changed something.
bool JG_RunCmd(int client, int &buttons)
{
	if (!JG_Jammed(client) || !(buttons & (IN_ATTACK | IN_ATTACK2)))
		return false;
	buttons &= ~(IN_ATTACK | IN_ATTACK2);
	return true;
}

void JG_Jam(int client)
{
	float until = GetGameTime() + float(g_JgLast);
	g_JgUntil[client] = until;
	int weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon != -1 && IsValidEntity(weapon) && HasEntProp(weapon, Prop_Send, "m_flNextPrimaryAttack"))
	{
		SetEntPropFloat(weapon, Prop_Send, "m_flNextPrimaryAttack", until);
		SetEntPropFloat(weapon, Prop_Send, "m_flNextSecondaryAttack", until);
	}
	PrintCenterText(client, "YOUR GUN JAMMED!");
}

void JG_Wave()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	int count = g_JgCount < n ? g_JgCount : n;
	for (int k = 0; k < count; k++)
		JG_Jam(list[k]);
	if (count >= n && n > 0)
		PrintToChatAll(JG_TAG ... "Everyone's guns jammed for %d seconds!", g_JgLast);
	else if (count > 0)
		PrintToChatAll(JG_TAG ... "%d gun%s jammed for %d seconds!", count, count == 1 ? "" : "s", g_JgLast);
}

void JG_Tick()
{
	if (HazardDue(g_JgOn, g_JgNext, g_JgEvery))
		JG_Wave();
}

// ---------------------------------------------------------------- menu

void JGMenu(int client)
{
	Menu menu = new Menu(JGHandler);
	char line[64];
	menu.SetTitle(g_JgOn ? "Jammed Guns - ON\nStarts when the zombies come\n " : "Jammed Guns - OFF\n ");
	menu.AddItem("toggle", g_JgOn ? "Turn Jammed Guns OFF" : "Turn Jammed Guns ON");
	menu.AddItem("now", "Jam guns now", (g_JgOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_JgEvery);
	menu.AddItem("every", line);
	if (g_JgCount >= 64)
		strcopy(line, sizeof(line), "Humans jammed: everyone");
	else
		Format(line, sizeof(line), "Humans jammed: %d", g_JgCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Jammed for: %d s", g_JgLast);
	menu.AddItem("last", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int JGHandler(Menu menu, MenuAction action, int client, int item)
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
			JG_Set(!g_JgOn);
			PrintToChatAll(JG_TAG ... "%N turned Jammed Guns %s.", client, g_JgOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned jammed guns %s", client, g_JgOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			JG_Wave();
		else if (StrEqual(info, "every"))
			g_JgEvery = NextInt(g_JgEverySteps, sizeof(g_JgEverySteps), g_JgEvery);
		else if (StrEqual(info, "count"))
			g_JgCount = NextInt(g_JgCountSteps, sizeof(g_JgCountSteps), g_JgCount);
		else if (StrEqual(info, "last"))
			g_JgLast = NextInt(g_JgLastSteps, sizeof(g_JgLastSteps), g_JgLast);
		JGMenu(client);
	}
	return 0;
}
