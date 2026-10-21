// Shockwave module of eventmodes.sp.
// modes.sp calls SW_Check (every 0.2 s), SW_Tick (every second), SW_RoundStart and SW_Stop.
//
// Once the zombies are out, every N seconds a warning ring marks a spot near a random human; then a
// shockwave ring races outwards from it. Anyone standing on the ground when the wave passes them gets
// hurt and knocked up - jump over it!

#if defined _em_shockwave_included
 #endinput
#endif
#define _em_shockwave_included

#define SW_TAG  "\x07" ... "60C0FF[Shockwave]\x01 "   // kept apart: \x would eat the hex digits
#define SW_WARN 1.5

int g_SwEverySteps[] = { 15, 20, 30, 45, 60 };
int g_SwDamageSteps[] = { 15, 25, 50, 75, 1000 };   // 1000 = kill
float g_SwSizeSteps[] = { 600.0, 1000.0, 1500.0, 2500.0 };
float g_SwSpeedSteps[] = { 300.0, 450.0, 600.0, 900.0 };
int g_SwColor[4] = { 96, 192, 255, 255 };

bool g_SwOn;
int g_SwEvery = 30;
int g_SwDamage = 25;
float g_SwSize = 1000.0;    // how far the wave travels
float g_SwSpeed = 450.0;    // units per second
bool g_SwZombies;

float g_SwNext;
bool g_SwActive;
float g_SwCenter[3];
float g_SwStart;            // when the wave leaves the centre
float g_SwLastRadius;
bool g_SwHit[MAXPLAYERS + 1];

bool SW_IsOn()
{
	return g_SwOn;
}

void SW_Stop()
{
	g_SwOn = false;
	g_SwActive = false;
	g_SwNext = 0.0;
}

void SW_Set(bool on)
{
	SW_Stop();
	g_SwOn = on;
}

void SW_RoundStart()
{
	g_SwActive = false;
	g_SwNext = 0.0;
	if (g_SwOn)
		PrintToChatAll(SW_TAG ... "Shockwaves are on: when the blue ring comes, JUMP over it!");
}

void SW_Fire()
{
	int list[MAXPLAYERS + 1];
	if (ShuffledHumans(list) == 0)
		return;
	GetClientAbsOrigin(list[0], g_SwCenter);
	g_SwCenter[0] += GetRandomFloat(-200.0, 200.0);
	g_SwCenter[1] += GetRandomFloat(-200.0, 200.0);
	g_SwStart = GetGameTime() + SW_WARN;
	g_SwLastRadius = 0.0;
	g_SwActive = true;
	for (int i = 1; i <= MaxClients; i++)
		g_SwHit[i] = false;

	RingAt(g_SwCenter, 80.0, 10.0, SW_WARN, g_SwColor, 12.0);   // warning: shrinking ring at the centre
	BeamDown(g_SwCenter, 600.0, SW_WARN, 10.0, g_SwColor);
	PrintToChatAll(SW_TAG ... "SHOCKWAVE! Jump when it reaches you!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 70);
}

void SW_Check()
{
	if (!g_SwOn || !g_SwActive || !g_RoundLive)
		return;
	float now = GetGameTime();
	if (now < g_SwStart)
		return;
	if (g_SwLastRadius == 0.0)
	{
		// The wave itself: one ring that grows over the whole travel time.
		RingAt(g_SwCenter, 10.0, g_SwSize, g_SwSize / g_SwSpeed, g_SwColor, 20.0);
		EmitAmbientSound(EXPLODE_SOUND, g_SwCenter, SOUND_FROM_WORLD, SNDLEVEL_RAIDSIREN, _, 0.6, 60);
	}
	float radius = (now - g_SwStart) * g_SwSpeed;
	float pos[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_SwHit[i] || !HazardHits(i, g_SwZombies))
			continue;
		GetClientAbsOrigin(i, pos);
		float d = GetVectorDistance(g_SwCenter, pos);
		if (d < g_SwLastRadius - 40.0 || d > radius + 40.0)
			continue;   // the front hasn't reached them, or already went by
		g_SwHit[i] = true;
		if (!(GetEntityFlags(i) & FL_ONGROUND))
			continue;   // jumped it!
		PrintCenterText(i, "You didn't jump the shockwave!");
		Shove(i, 0.0, 0.0, 280.0);
		HurtPlayer(i, g_SwDamage);
	}
	g_SwLastRadius = radius;
	if (radius >= g_SwSize)
		g_SwActive = false;
}

void SW_Tick()
{
	if (!g_SwActive && HazardDue(g_SwOn, g_SwNext, g_SwEvery))
		SW_Fire();
}

// ---------------------------------------------------------------- menu

void SWMenu(int client)
{
	Menu menu = new Menu(SWHandler);
	char line[64];
	menu.SetTitle(g_SwOn ? "Shockwave - ON\nStarts when the zombies come\n " : "Shockwave - OFF\n ");
	menu.AddItem("toggle", g_SwOn ? "Turn Shockwaves OFF" : "Turn Shockwaves ON");
	menu.AddItem("now", "Shockwave now", (g_SwOn && g_RoundLive && !g_SwActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_SwEvery);
	menu.AddItem("every", line);
	if (g_SwDamage >= 1000)
		strcopy(line, sizeof(line), "Damage: instant kill");
	else
		Format(line, sizeof(line), "Damage: %d", g_SwDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Wave reaches: %d units", RoundToNearest(g_SwSize));
	menu.AddItem("size", line);
	Format(line, sizeof(line), "Wave speed: %d", RoundToNearest(g_SwSpeed));
	menu.AddItem("speed", line);
	Format(line, sizeof(line), "Hits zombies too: %s", g_SwZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SWHandler(Menu menu, MenuAction action, int client, int item)
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
			SW_Set(!g_SwOn);
			PrintToChatAll(SW_TAG ... "%N turned Shockwaves %s.", client, g_SwOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned shockwaves %s", client, g_SwOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			SW_Fire();
		else if (StrEqual(info, "every"))
			g_SwEvery = NextInt(g_SwEverySteps, sizeof(g_SwEverySteps), g_SwEvery);
		else if (StrEqual(info, "damage"))
			g_SwDamage = NextInt(g_SwDamageSteps, sizeof(g_SwDamageSteps), g_SwDamage);
		else if (StrEqual(info, "size"))
			g_SwSize = NextFloat(g_SwSizeSteps, sizeof(g_SwSizeSteps), g_SwSize);
		else if (StrEqual(info, "speed"))
			g_SwSpeed = NextFloat(g_SwSpeedSteps, sizeof(g_SwSpeedSteps), g_SwSpeed);
		else if (StrEqual(info, "zombies"))
			g_SwZombies = !g_SwZombies;
		SWMenu(client);
	}
	return 0;
}
