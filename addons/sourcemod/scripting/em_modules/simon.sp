// Simon Says module of eventmodes.sp.
// eventmodes.sp calls Simon_PluginStart and Simon_RunCmd (every player command); modes.sp calls
// Simon_Check (every 0.2 s), Simon_Tick (every second), Simon_RoundStart and Simon_Stop.
//
// Once the zombies are out, every so often a command pops up: "SIMON SAYS: CROUCH!" means do it within
// the time window; a trick "JUMP!" without "Simon says" means DON'T. "Simon says stand still" means no
// movement keys until the window ends. Getting it wrong costs health (or your life).

#if defined _em_simon_included
 #endinput
#endif
#define _em_simon_included

#define SS_TAG  "\x07" ... "60A0FF[Simon Says]\x01 "   // kept apart: \x would eat the hex digits
#define SS_MOVE (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP)

enum { SS_CROUCH = 0, SS_JUMP, SS_SHOOT, SS_RELOAD, SS_USE, SS_STILL, SS_ACTIONS }
char g_SsActionNames[][] = { "CROUCH", "JUMP", "SHOOT", "RELOAD", "PRESS E", "STAND STILL" };
int g_SsButtons[] = { IN_DUCK, IN_JUMP, IN_ATTACK, IN_RELOAD, IN_USE, SS_MOVE };

int g_SsEverySteps[] = { 15, 20, 30, 45, 60 };
int g_SsWindowSteps[] = { 2, 3, 4, 5 };
int g_SsDamageSteps[] = { 10, 25, 50, 1000 };   // 1000 = slay
int g_SsTrickSteps[] = { 0, 20, 30, 50 };       // % of commands without "Simon says"

bool g_SsOn;
bool g_SsEveryone;          // zombies play too (else humans only)
int g_SsEvery = 20;
int g_SsWindow = 3;
int g_SsDamage = 25;
int g_SsTrick = 30;

bool g_SsActive;
bool g_SsSimon;             // "Simon says" was said this time
int g_SsAction;
float g_SsEnds;
float g_SsNext;             // 0 = schedule the first one
bool g_SsIn[MAXPLAYERS + 1];    // part of this command
bool g_SsDid[MAXPLAYERS + 1];   // pressed the action's key (for STAND STILL: moved)
Handle g_HudSimon;

void Simon_PluginStart()
{
	g_HudSimon = EM_HudSync();
}

bool Simon_IsOn()
{
	return g_SsOn;
}

void Simon_Clear()
{
	g_SsActive = false;
	g_SsNext = 0.0;
	for (int i = 1; i <= MaxClients; i++)
	{
		g_SsIn[i] = false;
		g_SsDid[i] = false;
	}
}

void Simon_Stop()
{
	g_SsOn = false;
	Simon_Clear();
}

void Simon_RoundStart()
{
	Simon_Clear();
	if (g_SsOn)
		PrintToChatAll(SS_TAG ... "Simon Says is on: only do it when SIMON SAYS so!");
}

void Simon_RunCmd(int client, int buttons)
{
	if (g_SsActive && g_SsIn[client] && (buttons & g_SsButtons[g_SsAction]))
		g_SsDid[client] = true;
}

bool Simon_Plays(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
		return false;
	int team = GetClientTeam(client);
	return team == CS_TEAM_CT || (g_SsEveryone && team == CS_TEAM_T);
}

void Simon_ShowHud()
{
	int left = RoundToCeil(g_SsEnds - GetGameTime());
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_SsIn[i] || !IsClientInGame(i))
			continue;
		SetHudTextParams(-1.0, 0.40, 1.2, 96, 160, 255, 255, 0, 0.0, 0.0, 0.0);
		if (g_SsSimon)
			EM_ShowHud(i, g_HudSimon, "SIMON SAYS: %s! (%d)", g_SsActionNames[g_SsAction], left > 0 ? left : 0);
		else
			EM_ShowHud(i, g_HudSimon, "%s! (%d)", g_SsActionNames[g_SsAction], left > 0 ? left : 0);
	}
}

void Simon_Start()
{
	Simon_Clear();
	g_SsAction = GetRandomInt(0, SS_ACTIONS - 1);
	// "Stand still" only makes sense when Simon says it.
	g_SsSimon = g_SsAction == SS_STILL || GetRandomInt(1, 100) > g_SsTrick;
	g_SsEnds = GetGameTime() + float(g_SsWindow);

	int players = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!Simon_Plays(i))
			continue;
		g_SsIn[i] = true;
		players++;
	}
	g_SsActive = players > 0;
	if (!g_SsActive)
	{
		g_SsNext = GetGameTime() + float(g_SsEvery);
		return;
	}
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 110);
	Simon_ShowHud();
}

void Simon_End()
{
	int failed = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_SsIn[i] || !Simon_Plays(i))
			continue;
		bool fail;
		if (g_SsAction == SS_STILL)
			fail = g_SsDid[i];          // moved
		else
			fail = g_SsSimon ? !g_SsDid[i] : g_SsDid[i];
		if (!fail)
			continue;
		failed++;
		if (g_SsSimon && g_SsAction != SS_STILL)
			PrintToChat(i, SS_TAG ... "You didn't %s!", g_SsActionNames[g_SsAction]);
		else if (g_SsSimon)
			PrintToChat(i, SS_TAG ... "You moved!");
		else
			PrintToChat(i, SS_TAG ... "Simon didn't say so!");
		HurtPlayer(i, g_SsDamage);
	}

	if (failed == 0)
		PrintToChatAll(SS_TAG ... "Everyone got it right!");
	else if (!g_SsSimon)
		PrintToChatAll(SS_TAG ... "Simon didn't say! %d player%s fell for it.", failed, failed == 1 ? "" : "s");
	else
		PrintToChatAll(SS_TAG ... "%d player%s failed to %s.", failed, failed == 1 ? "" : "s", g_SsActionNames[g_SsAction]);

	Simon_Clear();
	g_SsNext = GetGameTime() + float(g_SsEvery);
}

void Simon_Check()
{
	if (!g_SsOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (!g_SsActive)
	{
		if (g_SsNext == 0.0)
			g_SsNext = now + 10.0;
		if (now >= g_SsNext)
			Simon_Start();
		return;
	}
	if (now >= g_SsEnds)
		Simon_End();
}

void Simon_Tick()
{
	if (g_SsOn && g_SsActive)
		Simon_ShowHud();
}

// ---------------------------------------------------------------- menu

void SimonMenu(int client)
{
	Menu menu = new Menu(SimonHandler);
	char line[64];
	menu.SetTitle(g_SsOn ? "Simon Says - ON\nStarts when the zombies come\n " : "Simon Says - OFF\n ");
	menu.AddItem("toggle", g_SsOn ? "Turn Simon Says OFF" : "Turn Simon Says ON");
	menu.AddItem("now", "Give a command now", (g_SsOn && g_RoundLive && !g_SsActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_SsEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Time to react: %d s", g_SsWindow);
	menu.AddItem("window", line);
	if (g_SsDamage >= 1000)
		strcopy(line, sizeof(line), "Getting it wrong: slay");
	else
		Format(line, sizeof(line), "Getting it wrong: -%d HP", g_SsDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Trick commands (no \"Simon says\"): %d%%", g_SsTrick);
	menu.AddItem("trick", line);
	Format(line, sizeof(line), "Who plays: %s", g_SsEveryone ? "everyone" : "humans only");
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SimonHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_SsOn;
			Simon_Stop();
			g_SsOn = on;
			PrintToChatAll(SS_TAG ... "%N turned Simon Says %s.", client, on ? "ON - only do it when SIMON SAYS so" : "OFF");
			LogAction(client, -1, "\"%L\" turned simon says %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			Simon_Start();
		else if (StrEqual(info, "every"))
			g_SsEvery = NextInt(g_SsEverySteps, sizeof(g_SsEverySteps), g_SsEvery);
		else if (StrEqual(info, "window"))
			g_SsWindow = NextInt(g_SsWindowSteps, sizeof(g_SsWindowSteps), g_SsWindow);
		else if (StrEqual(info, "damage"))
			g_SsDamage = NextInt(g_SsDamageSteps, sizeof(g_SsDamageSteps), g_SsDamage);
		else if (StrEqual(info, "trick"))
			g_SsTrick = NextInt(g_SsTrickSteps, sizeof(g_SsTrickSteps), g_SsTrick);
		else if (StrEqual(info, "who"))
			g_SsEveryone = !g_SsEveryone;
		SimonMenu(client);
	}
	return 0;
}
