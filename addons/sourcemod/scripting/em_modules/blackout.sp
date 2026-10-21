// Blackout / Flashbang module of eventmodes.sp.
// eventmodes.sp calls BO_MapStart; modes.sp calls BO_Tick (every second), BO_RoundStart and BO_Stop.
//
// Once the zombies are out, every N seconds a few random players' screens go black (blackout) or
// white (flashbang) for a moment, then fade back.

#if defined _em_blackout_included
 #endinput
#endif
#define _em_blackout_included

#define BO_TAG         "\x07" ... "B0B0B0[Blackout]\x01 "   // kept apart: \x would eat the hex digits
#define BO_FLASH_SOUND "weapons/flashbang/flashbang_explode2.wav"
#define FFADE_IN       0x0001   // start at the colour, fade back to normal
#define FFADE_PURGE    0x0010   // replace any fade already going

enum { BO_BLACK = 0, BO_WHITE, BO_RANDOM, BO_TYPES }
char g_BoTypeNames[][] = { "black (blackout)", "white (flashbang)", "random" };
int g_BoEverySteps[] = { 10, 15, 20, 30, 45, 60 };
int g_BoCountSteps[] = { 1, 2, 3, 5, 10, 64 };   // 64 = everyone
int g_BoLastSteps[] = { 1, 2, 3, 5 };

bool g_BoOn;
int g_BoEvery = 20;
int g_BoCount = 2;          // players hit each time
int g_BoLast = 2;           // seconds fully dark/bright
int g_BoType = BO_RANDOM;
bool g_BoEveryone;          // zombies too (else humans only)
float g_BoNext;             // 0 = schedule when the zombies come

void BO_MapStart()
{
	PrecacheSound(BO_FLASH_SOUND, true);
}

bool BO_IsOn()
{
	return g_BoOn;
}

void BO_Stop()
{
	g_BoOn = false;
	g_BoNext = 0.0;
}

void BO_RoundStart()
{
	g_BoNext = 0.0;
	if (g_BoOn)
		PrintToChatAll(BO_TAG ... "Blackouts are on: your screen might go dark at the worst moment...");
}

// Screen goes fully `white` or black, stays `hold` seconds, then fades back over a second.
void BO_Fade(int client, bool white, float hold)
{
	BfWrite bf = UserMessageToBfWrite(StartMessageOne("Fade", client, USERMSG_RELIABLE));
	bf.WriteShort(512);                              // fade back over 1 s (units of 1/512 s)
	bf.WriteShort(RoundToNearest(hold * 512.0));     // hold time
	bf.WriteShort(FFADE_IN | FFADE_PURGE);
	int c = white ? 255 : 0;
	bf.WriteByte(c);
	bf.WriteByte(c);
	bf.WriteByte(c);
	bf.WriteByte(255);
	EndMessage();
}

void BO_Hit()
{
	int list[MAXPLAYERS + 1], n = 0;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || IsFakeClient(i))
			continue;
		int team = GetClientTeam(i);
		if (team == CS_TEAM_CT || (g_BoEveryone && team == CS_TEAM_T))
			list[n++] = i;
	}
	for (int i = n - 1; i > 0; i--)   // shuffle
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}
	int count = g_BoCount < n ? g_BoCount : n;
	for (int k = 0; k < count; k++)
	{
		int c = list[k];
		bool white = g_BoType == BO_WHITE || (g_BoType == BO_RANDOM && GetRandomInt(0, 1) == 1);
		BO_Fade(c, white, float(g_BoLast));
		if (white)
		{
			EmitSoundToClient(c, BO_FLASH_SOUND);
			PrintCenterText(c, "FLASHBANGED!");
		}
		else
			PrintCenterText(c, "BLACKOUT!");
	}
	if (count > 0 && count < n)
		PrintToChatAll(BO_TAG ... "%d player%s lost their sight!", count, count == 1 ? "" : "s");
	else if (count > 0)
		PrintToChatAll(BO_TAG ... "Everyone lost their sight!");
}

void BO_Tick()
{
	if (!g_BoOn || !g_RoundLive || !g_ZombiesSeen)
		return;
	float now = GetGameTime();
	if (g_BoNext == 0.0)
		g_BoNext = now + float(g_BoEvery);
	if (now >= g_BoNext)
	{
		BO_Hit();
		g_BoNext = now + float(g_BoEvery);
	}
}

// ---------------------------------------------------------------- menu

void BOMenu(int client)
{
	Menu menu = new Menu(BOHandler);
	char line[64];
	menu.SetTitle(g_BoOn ? "Blackout / Flashbang - ON\nStarts when the zombies come\n " : "Blackout / Flashbang - OFF\n ");
	menu.AddItem("toggle", g_BoOn ? "Turn Blackouts OFF" : "Turn Blackouts ON");
	menu.AddItem("now", "Blackout now", (g_BoOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_BoEvery);
	menu.AddItem("every", line);
	if (g_BoCount >= 64)
		strcopy(line, sizeof(line), "Players hit: everyone");
	else
		Format(line, sizeof(line), "Players hit: %d", g_BoCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "Blind for: %d s", g_BoLast);
	menu.AddItem("last", line);
	Format(line, sizeof(line), "Type: %s", g_BoTypeNames[g_BoType]);
	menu.AddItem("type", line);
	Format(line, sizeof(line), "Who: %s", g_BoEveryone ? "everyone (zombies too)" : "humans only");
	menu.AddItem("who", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BOHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_BoOn;
			BO_Stop();
			g_BoOn = on;
			PrintToChatAll(BO_TAG ... "%N turned Blackouts %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned blackouts %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			BO_Hit();
		else if (StrEqual(info, "every"))
			g_BoEvery = NextInt(g_BoEverySteps, sizeof(g_BoEverySteps), g_BoEvery);
		else if (StrEqual(info, "count"))
			g_BoCount = NextInt(g_BoCountSteps, sizeof(g_BoCountSteps), g_BoCount);
		else if (StrEqual(info, "last"))
			g_BoLast = NextInt(g_BoLastSteps, sizeof(g_BoLastSteps), g_BoLast);
		else if (StrEqual(info, "type"))
			g_BoType = (g_BoType + 1) % BO_TYPES;
		else if (StrEqual(info, "who"))
			g_BoEveryone = !g_BoEveryone;
		BOMenu(client);
	}
	return 0;
}
