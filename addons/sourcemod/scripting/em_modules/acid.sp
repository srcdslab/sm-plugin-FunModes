// Acid Rain module of eventmodes.sp.
// eventmodes.sp calls AR_PluginStart; modes.sp calls AR_Tick (every second), AR_RoundStart and AR_Stop.
//
// Once the zombies are out, every N seconds acid rain falls for a while: anyone with open sky above
// their head loses health each second. Get under a roof, a bridge or into a tunnel.

#if defined _em_acid_included
 #endinput
#endif
#define _em_acid_included

#define AR_TAG "\x07" ... "A0FF60[Acid Rain]\x01 "   // kept apart: \x would eat the hex digits
#define AR_SURF_SKY (0x0002 | 0x0004)              // SURF_SKY2D | SURF_SKY

int g_ArEverySteps[] = { 30, 45, 60, 90, 120 };
int g_ArLastSteps[] = { 5, 10, 15, 20 };
int g_ArDamageSteps[] = { 2, 3, 5, 10, 20 };

bool g_ArOn;
int g_ArEvery = 60;
int g_ArLast = 10;
int g_ArDamage = 5;
bool g_ArZombies;
bool g_ArActive;
float g_ArNext;
float g_ArEnds;
Handle g_HudAcid;

void AR_PluginStart()
{
	g_HudAcid = EM_HudSync();
}

bool AR_IsOn()
{
	return g_ArOn;
}

void AR_Stop()
{
	g_ArOn = false;
	g_ArActive = false;
	g_ArNext = 0.0;
}

void AR_Set(bool on)
{
	AR_Stop();
	g_ArOn = on;
}

void AR_RoundStart()
{
	g_ArActive = false;
	g_ArNext = 0.0;
	if (g_ArOn)
		PrintToChatAll(AR_TAG ... "Acid Rain is on: when it rains, get under a roof!");
}

public bool AR_IgnorePlayers(int entity, int mask)
{
	return entity > MaxClients;
}

// True if nothing but sky (or nothing at all) is straight above the player's head.
bool AR_Exposed(int client)
{
	float eye[3], up[3];
	GetClientEyePosition(client, eye);
	up = eye;
	up[2] += 8192.0;
	TR_TraceRayFilter(eye, up, MASK_SOLID_BRUSHONLY, RayType_EndPoint, AR_IgnorePlayers);
	if (!TR_DidHit())
		return true;
	return (TR_GetSurfaceFlags() & AR_SURF_SKY) != 0;
}

void AR_Start()
{
	g_ArActive = true;
	g_ArEnds = GetGameTime() + float(g_ArLast);
	PrintToChatAll(AR_TAG ... "ACID RAIN for %d seconds - get under cover!", g_ArLast);
	PrintCenterTextAll("ACID RAIN! GET UNDER COVER!");
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 65);
}

void AR_Tick()
{
	if (!g_ArOn || !g_RoundLive)
		return;
	if (!g_ArActive)
	{
		if (HazardDue(g_ArOn, g_ArNext, g_ArEvery))
			AR_Start();
		return;
	}
	if (GetGameTime() >= g_ArEnds)
	{
		g_ArActive = false;
		PrintToChatAll(AR_TAG ... "The acid rain has stopped.");
		return;
	}
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_ArZombies))
			continue;
		bool exposed = AR_Exposed(i);
		if (!IsFakeClient(i))
		{
			SetHudTextParams(-1.0, 0.48, 1.1, exposed ? 160 : 120, 255, exposed ? 96 : 200, 255, 0, 0.0, 0.0, 0.0);
			EM_ShowHud(i, g_HudAcid, exposed ? "ACID RAIN - GET UNDER COVER! (-%d HP/s)" : "Acid rain - you're under cover", g_ArDamage);
			if (exposed)
				ScreenTint(i, 120, 255, 60, 50, 0.3, 0.6);
		}
		if (exposed)
			HurtPlayer(i, g_ArDamage);
	}
}

// ---------------------------------------------------------------- menu

void ARMenu(int client)
{
	Menu menu = new Menu(ARHandler);
	char line[64];
	menu.SetTitle(g_ArOn ? "Acid Rain - ON\nStarts when the zombies come\n " : "Acid Rain - OFF\n ");
	menu.AddItem("toggle", g_ArOn ? "Turn Acid Rain OFF" : "Turn Acid Rain ON");
	menu.AddItem("now", "Make it rain now", (g_ArOn && g_RoundLive && !g_ArActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_ArEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Rain lasts: %d s", g_ArLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Acid: -%d HP/s", g_ArDamage);
	menu.AddItem("damage", line);
	Format(line, sizeof(line), "Hurts zombies too: %s", g_ArZombies ? "ON" : "OFF");
	menu.AddItem("zombies", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ARHandler(Menu menu, MenuAction action, int client, int item)
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
			AR_Set(!g_ArOn);
			PrintToChatAll(AR_TAG ... "%N turned Acid Rain %s.", client, g_ArOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned acid rain %s", client, g_ArOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			AR_Start();
		else if (StrEqual(info, "every"))
			g_ArEvery = NextInt(g_ArEverySteps, sizeof(g_ArEverySteps), g_ArEvery);
		else if (StrEqual(info, "last"))
			g_ArLast = NextInt(g_ArLastSteps, sizeof(g_ArLastSteps), g_ArLast);
		else if (StrEqual(info, "damage"))
			g_ArDamage = NextInt(g_ArDamageSteps, sizeof(g_ArDamageSteps), g_ArDamage);
		else if (StrEqual(info, "zombies"))
			g_ArZombies = !g_ArZombies;
		ARMenu(client);
	}
	return 0;
}
