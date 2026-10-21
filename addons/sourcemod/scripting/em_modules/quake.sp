// Earthquake module of eventmodes.sp.
// modes.sp calls EQ_Check (every 0.2 s), EQ_Tick (every second), EQ_RoundStart and EQ_Stop.
//
// Once the zombies are out, every N seconds the ground shakes for a few seconds: screens shake and
// players get random shoves. Screen shake, shake speed and shove strength are separate settings with
// many levels. Clients can turn screen shake off for themselves, so while the mode is on it runs
// "sm_force_shake 1", and "sm_force_shake 0" when it's turned off.

#if defined _em_quake_included
 #endinput
#endif
#define _em_quake_included

#define EQ_TAG        "\x07" ... "C08040[Earthquake]\x01 "   // kept apart: \x would eat the hex digits
#define EQ_FORCE_CVAR "sm_force_shake"

char g_EqLevelNames[][] = { "off", "tiny", "light", "medium", "strong", "very strong", "extreme", "insane" };
float g_EqShakeLevels[] = { 0.0, 1.5, 3.5, 7.0, 10.0, 14.0, 20.0, 30.0 };       // screen shake amplitude
float g_EqShoveLevels[] = { 0.0, 60.0, 120.0, 220.0, 350.0, 500.0, 700.0, 1000.0 };   // shove speed
char g_EqSpeedNames[][] = { "slow rumble", "normal", "fast", "violent" };
float g_EqSpeedLevels[] = { 40.0, 100.0, 170.0, 255.0 };                       // shake frequency
float g_EqShoveEverySteps[] = { 0.3, 0.6, 1.0, 1.5 };
int g_EqEverySteps[] = { 20, 30, 45, 60, 90, 120 };
int g_EqLastSteps[] = { 3, 5, 8, 10, 15 };

bool g_EqOn;
int g_EqEvery = 45;
int g_EqLast = 5;
int g_EqShake = 3;          // index into the levels
int g_EqSpeed = 1;
int g_EqShove = 3;
float g_EqShoveEvery = 0.6;
bool g_EqEveryone = true;   // zombies are hit too (else humans only)
bool g_EqActive;
float g_EqNext;             // 0 = schedule when the zombies come
float g_EqEnds;
float g_EqNextShove;
bool g_EqForced;            // we set sm_force_shake 1

bool EQ_IsOn()
{
	return g_EqOn;
}

// Make sure players see the shake: sm_force_shake 1 while earthquakes are on, 0 when they're turned off
// (only if we turned it on, so map changes don't touch it otherwise).
void EQ_ForceShake(bool on)
{
	if (!on && !g_EqForced)
		return;
	g_EqForced = on;
	ServerCommand("%s %d", EQ_FORCE_CVAR, on ? 1 : 0);
}

void EQ_Enable()
{
	g_EqOn = true;
	g_EqActive = false;
	g_EqNext = 0.0;
	EQ_ForceShake(true);
}

void EQ_Stop()
{
	g_EqOn = false;
	g_EqActive = false;
	g_EqNext = 0.0;
	EQ_ForceShake(false);
}

void EQ_RoundStart()
{
	g_EqActive = false;
	g_EqNext = 0.0;
	if (g_EqOn)
		PrintToChatAll(EQ_TAG ... "Earthquakes are on: watch your footing on the narrow paths!");
}

bool EQ_Affects(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client))
		return false;
	int team = GetClientTeam(client);
	return team == CS_TEAM_CT || (g_EqEveryone && team == CS_TEAM_T);
}

void EQ_SendShake(int client, float amplitude, float frequency, float seconds)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Shake", client, USERMSG_RELIABLE));
	bf.WriteByte(0);   // SHAKE_START
	bf.WriteFloat(amplitude);
	bf.WriteFloat(frequency);
	bf.WriteFloat(seconds);
	EndMessage();
}

void EQ_Start()
{
	float now = GetGameTime();
	g_EqActive = true;
	g_EqEnds = now + float(g_EqLast);
	g_EqNextShove = now + 0.3;
	EQ_ForceShake(true);

	float amp = g_EqShakeLevels[g_EqShake];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (amp > 0.0 && (EQ_Affects(i) || !IsPlayerAlive(i) || g_EqEveryone))
			EQ_SendShake(i, amp, g_EqSpeedLevels[g_EqSpeed], float(g_EqLast));
		PrintCenterText(i, "EARTHQUAKE!");
	}
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 30);
}

void EQ_Shove()
{
	float power = g_EqShoveLevels[g_EqShove];
	if (power <= 0.0)
		return;
	float vel[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!EQ_Affects(i))
			continue;
		GetEntPropVector(i, Prop_Data, "m_vecVelocity", vel);
		float angle = GetRandomFloat(0.0, 6.2832);
		vel[0] += Cosine(angle) * power;
		vel[1] += Sine(angle) * power;
		if (GetEntityFlags(i) & FL_ONGROUND)
			vel[2] += 60.0;   // a little hop so ground friction doesn't eat the shove
		TeleportEntity(i, NULL_VECTOR, NULL_VECTOR, vel);
	}
}

void EQ_Check()
{
	if (!g_EqOn || !g_EqActive || !g_RoundLive)
		return;
	float now = GetGameTime();
	if (now >= g_EqEnds)
	{
		g_EqActive = false;
		g_EqNext = now + float(g_EqEvery);
		return;
	}
	if (now >= g_EqNextShove)
	{
		EQ_Shove();
		g_EqNextShove = now + g_EqShoveEvery;
	}
}

void EQ_Tick()
{
	if (!g_EqOn || g_EqActive || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (g_EqNext == 0.0)
		g_EqNext = now + float(g_EqEvery);
	if (now >= g_EqNext)
		EQ_Start();
}

// ---------------------------------------------------------------- menu

void EQMenu(int client, int firstItem = 0)
{
	Menu menu = new Menu(EQHandler);
	char line[64];
	menu.SetTitle(g_EqOn ? "Earthquake - ON\nStarts when the zombies come\n(sm_force_shake 1 while on)\n " : "Earthquake - OFF\n ");
	menu.AddItem("toggle", g_EqOn ? "Turn Earthquakes OFF" : "Turn Earthquakes ON");
	menu.AddItem("now", "Earthquake now", (g_EqOn && g_RoundLive && !g_EqActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_EqEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Lasts: %d s", g_EqLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Screen shake: %s", g_EqLevelNames[g_EqShake]);
	menu.AddItem("shake", line);
	Format(line, sizeof(line), "Shake speed: %s", g_EqSpeedNames[g_EqSpeed]);
	menu.AddItem("speed", line, g_EqShake > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Shove strength: %s", g_EqLevelNames[g_EqShove]);
	menu.AddItem("shove", line);
	Format(line, sizeof(line), "Shove every: %.1f s", g_EqShoveEvery);
	menu.AddItem("shoveevery", line, g_EqShove > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Who: %s", g_EqEveryone ? "everyone" : "humans only");
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int EQHandler(Menu menu, MenuAction action, int client, int item)
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
			if (g_EqOn)
				EQ_Stop();
			else
				EQ_Enable();
			PrintToChatAll(EQ_TAG ... "%N turned Earthquakes %s.", client, g_EqOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned earthquakes %s", client, g_EqOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			EQ_Start();
		else if (StrEqual(info, "every"))
			g_EqEvery = NextInt(g_EqEverySteps, sizeof(g_EqEverySteps), g_EqEvery);
		else if (StrEqual(info, "last"))
			g_EqLast = NextInt(g_EqLastSteps, sizeof(g_EqLastSteps), g_EqLast);
		else if (StrEqual(info, "shake"))
			g_EqShake = (g_EqShake + 1) % sizeof(g_EqLevelNames);
		else if (StrEqual(info, "speed"))
			g_EqSpeed = (g_EqSpeed + 1) % sizeof(g_EqSpeedNames);
		else if (StrEqual(info, "shove"))
			g_EqShove = (g_EqShove + 1) % sizeof(g_EqLevelNames);
		else if (StrEqual(info, "shoveevery"))
			g_EqShoveEvery = NextStep(g_EqShoveEverySteps, sizeof(g_EqShoveEverySteps), g_EqShoveEvery);
		else if (StrEqual(info, "who"))
			g_EqEveryone = !g_EqEveryone;
		EQMenu(client, GetMenuSelectionPosition());
	}
	return 0;
}
