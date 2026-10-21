// Red Light, Green Light module of eventmodes.sp.
// eventmodes.sp calls RLGL_MapStart; modes.sp calls RLGL_Check (every 0.2 s), RLGL_Tick (every second),
// RLGL_RoundStart and RLGL_Stop; physics.sp asks RLGL_SpeedMult.
//
// Once the zombies are out, the screen flips between GREEN LIGHT (a random few seconds) and RED LIGHT
// (a set few seconds). After a short reaction window on red, anyone holding a movement key (walk,
// strafe, jump) takes damage every moment they keep it up. Keys, not speed, so riding elevators and
// moving platforms on ZE maps doesn't count as moving. A countdown (with the server's ZE countdown
// sounds, sound/zr/countdown/N.mp3, when they exist) warns before red, and zombies can be slowed or
// frozen while it's red.

#if defined _em_rlgl_included
 #endinput
#endif
#define _em_rlgl_included

#define RLGL_TAG   "\x07" ... "FF5050[Red Light]\x01 "   // kept apart: \x would eat the hex digits
#define RLGL_MOVE  (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP)
#define RLGL_GRACE 0.6   // seconds to react when it turns red

int g_RlglRedSteps[] = { 2, 3, 4, 5 };
int g_RlglDamageSteps[] = { 10, 25, 50, 1000 };   // per second, 1000 = slay
char g_RlglGreenNames[][] = { "short (3-6 s)", "normal (5-10 s)", "long (8-15 s)" };
int g_RlglGreenMin[] = { 3, 5, 8 };
int g_RlglGreenMax[] = { 6, 10, 15 };

char g_RlglZombieNames[][] = { "normal speed", "slowed (x0.5)", "crawling (x0.2)", "frozen" };
float g_RlglZombieSpeed[] = { 1.0, 0.5, 0.2, 0.0 };
int g_RlglWarnSteps[] = { 0, 3, 5 };
bool g_RlglSoundFile[11];   // zr/countdown/N.mp3 exists on the server

bool g_RlglOn;
int g_RlglWarn = 3;         // countdown seconds before red (0 = none)
bool g_RlglSounds = true;   // play the countdown sounds
int g_RlglZombie = 1;       // index into the zombie speeds on red
bool g_RlglEveryone;        // zombies have to freeze too (else humans only)
int g_RlglRed = 3;          // seconds of red
int g_RlglDamage = 25;      // HP per second while moving on red
int g_RlglGreen = 1;        // index into the green lengths

bool g_RlglStarted;         // first green shown this round
bool g_RlglIsRed;
float g_RlglPhaseEnds;
float g_RlglGraceUntil;
float g_RlglOwed[MAXPLAYERS + 1];   // damage below 1 HP carried to the next check
Handle g_HudRlgl;

void RLGL_PluginStart()
{
	g_HudRlgl = EM_HudSync();
}

bool RLGL_IsOn()
{
	return g_RlglOn;
}

void RLGL_MapStart()
{
	char path[PLATFORM_MAX_PATH];
	for (int n = 1; n <= 10; n++)
	{
		Format(path, sizeof(path), "sound/zr/countdown/%d.mp3", n);
		g_RlglSoundFile[n] = FileExists(path, true);
		if (g_RlglSoundFile[n])
			PrecacheSound(path[6], true);   // without "sound/"
	}
}

// Zombies' speed while it's red, stacked with other modes by physics.sp.
float RLGL_SpeedMult(int client)
{
	if (!g_RlglOn || !g_RlglStarted || !g_RlglIsRed || !g_RoundLive || GetClientTeam(client) != CS_TEAM_T)
		return 1.0;
	return g_RlglZombieSpeed[g_RlglZombie];
}

void RLGL_CountdownSound(int n)
{
	if (!g_RlglSounds || n < 1 || n > 10 || !g_RlglSoundFile[n])
		return;
	char sample[64];
	Format(sample, sizeof(sample), "zr/countdown/%d.mp3", n);
	EmitSoundToAll(sample);
}

void RLGL_Clear()
{
	g_RlglStarted = false;
	g_RlglIsRed = false;
	for (int i = 1; i <= MaxClients; i++)
		g_RlglOwed[i] = 0.0;
}

void RLGL_Stop()
{
	g_RlglOn = false;
	RLGL_Clear();
}

void RLGL_RoundStart()
{
	RLGL_Clear();
	if (g_RlglOn)
		PrintToChatAll(RLGL_TAG ... "Red Light, Green Light is on: when the screen says RED, let go of your movement keys!");
}

bool RLGL_Affects(int client)
{
	if (!IsClientInGame(client) || !IsPlayerAlive(client) || IsFakeClient(client))
		return false;
	int team = GetClientTeam(client);
	return team == CS_TEAM_CT || (g_RlglEveryone && team == CS_TEAM_T);
}

void RLGL_ShowHud()
{
	float now = GetGameTime();
	int left = RoundToCeil(g_RlglPhaseEnds - now);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;
		if (g_RlglIsRed)
		{
			SetHudTextParams(-1.0, 0.36, 1.2, 255, 40, 40, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudRlgl, "RED LIGHT - FREEZE! (%d)", left > 0 ? left : 0);
		}
		else
		{
			SetHudTextParams(-1.0, 0.36, 1.2, 40, 255, 40, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudRlgl, "GREEN LIGHT - GO!");
		}
	}
}

void RLGL_Phase(bool red)
{
	float now = GetGameTime();
	g_RlglIsRed = red;
	if (red)
	{
		g_RlglPhaseEnds = now + float(g_RlglRed);
		g_RlglGraceUntil = now + RLGL_GRACE;
		for (int i = 1; i <= MaxClients; i++)
			g_RlglOwed[i] = 0.0;
	}
	else
		g_RlglPhaseEnds = now + float(GetRandomInt(g_RlglGreenMin[g_RlglGreen], g_RlglGreenMax[g_RlglGreen]));
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, red ? 60 : 140);   // low beep for red, high for green
	RLGL_ShowHud();
}

void RLGL_Check()
{
	if (!g_RlglOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	if (!g_RlglStarted)
	{
		g_RlglStarted = true;
		RLGL_Phase(false);
		return;
	}
	float now = GetGameTime();
	if (now >= g_RlglPhaseEnds)
		RLGL_Phase(!g_RlglIsRed);
	if (!g_RlglIsRed || now < g_RlglGraceUntil)
		return;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!RLGL_Affects(i) || !(GetClientButtons(i) & RLGL_MOVE))
			continue;
		if (g_RlglDamage >= 1000)
		{
			PrintToChatAll(RLGL_TAG ... "%N moved on red!", i);
			ForcePlayerSuicide(i);
			continue;
		}
		g_RlglOwed[i] += float(g_RlglDamage) * 0.2;   // this runs every 0.2 s
		int whole = RoundToFloor(g_RlglOwed[i]);
		if (whole <= 0)
			continue;
		g_RlglOwed[i] -= float(whole);
		PrintCenterText(i, "YOU MOVED ON RED!");
		HurtPlayer(i, whole);
	}
}

void RLGL_Tick()
{
	if (!g_RlglOn || !g_RlglStarted || !g_RoundLive)
		return;
	int left = RoundToCeil(g_RlglPhaseEnds - GetGameTime());
	if (!g_RlglIsRed && g_RlglWarn > 0 && left > 0 && left <= g_RlglWarn)
	{
		// Countdown to red instead of the green text.
		for (int i = 1; i <= MaxClients; i++)
		{
			if (!IsClientInGame(i) || IsFakeClient(i))
				continue;
			SetHudTextParams(-1.0, 0.36, 1.1, 255, 200, 40, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudRlgl, "RED LIGHT IN %d - GET READY TO STOP!", left);
		}
		RLGL_CountdownSound(left);
		return;
	}
	RLGL_ShowHud();   // keep the text up between phase changes
}

// ---------------------------------------------------------------- menu

void RLGLMenu(int client)
{
	Menu menu = new Menu(RLGLHandler);
	char line[64];
	menu.SetTitle(g_RlglOn ? "Red Light, Green Light - ON\nStarts when the zombies come\n " : "Red Light, Green Light - OFF\n ");
	menu.AddItem("toggle", g_RlglOn ? "Turn it OFF" : "Turn it ON");
	Format(line, sizeof(line), "Green lasts: %s", g_RlglGreenNames[g_RlglGreen]);
	menu.AddItem("green", line);
	Format(line, sizeof(line), "Red lasts: %d s", g_RlglRed);
	menu.AddItem("red", line);
	if (g_RlglDamage >= 1000)
		strcopy(line, sizeof(line), "Moving on red: slay");
	else
		Format(line, sizeof(line), "Moving on red: -%d HP/s", g_RlglDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Who must freeze: %s", g_RlglEveryone ? "everyone" : "humans only");
	menu.AddItem("who", line);
	if (g_RlglWarn == 0)
		strcopy(line, sizeof(line), "Countdown before red: none");
	else
		Format(line, sizeof(line), "Countdown before red: %d s", g_RlglWarn);
	menu.AddItem("warn", line);
	Format(line, sizeof(line), "Countdown sounds: %s", g_RlglSounds ? "ON" : "OFF");
	menu.AddItem("sounds", line, g_RlglWarn > 0 ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Zombies on red: %s", g_RlglZombieNames[g_RlglZombie]);
	menu.AddItem("zombie", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int RLGLHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_RlglOn;
			RLGL_Stop();
			g_RlglOn = on;
			PrintToChatAll(RLGL_TAG ... "%N turned Red Light, Green Light %s.", client, on ? "ON - freeze when it says RED" : "OFF");
			LogAction(client, -1, "\"%L\" turned red light green light %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "green"))
			g_RlglGreen = (g_RlglGreen + 1) % sizeof(g_RlglGreenNames);
		else if (StrEqual(info, "red"))
			g_RlglRed = NextInt(g_RlglRedSteps, sizeof(g_RlglRedSteps), g_RlglRed);
		else if (StrEqual(info, "damage"))
			g_RlglDamage = NextInt(g_RlglDamageSteps, sizeof(g_RlglDamageSteps), g_RlglDamage);
		else if (StrEqual(info, "who"))
			g_RlglEveryone = !g_RlglEveryone;
		else if (StrEqual(info, "warn"))
			g_RlglWarn = NextInt(g_RlglWarnSteps, sizeof(g_RlglWarnSteps), g_RlglWarn);
		else if (StrEqual(info, "sounds"))
			g_RlglSounds = !g_RlglSounds;
		else if (StrEqual(info, "zombie"))
			g_RlglZombie = (g_RlglZombie + 1) % sizeof(g_RlglZombieNames);
		RLGLMenu(client);
	}
	return 0;
}
