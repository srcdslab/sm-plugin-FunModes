// Hot Seat module of eventmodes.sp.
// eventmodes.sp calls HS_MapStart; modes.sp calls HS_Tick (every second), HS_RoundStart and HS_Stop.
//
// Every so often a random player gets a TRUE / FALSE menu with a statement - from
// configs/eventmodes/hotseat.cfg, a quick sum ("7 x 8 = 54"), or a mix. Everyone sees the statement
// and the result in chat. A wrong (or no) answer costs health, a right one can earn some.

#if defined _em_hotseat_included
 #endinput
#endif
#define _em_hotseat_included

#define HS_TAG    "\x07" ... "FFA040[Hot Seat]\x01 "   // kept apart: \x would eat the hex digits
#define HS_CONFIG "configs/eventmodes/hotseat.cfg"
#define HS_MAX    500

enum { HS_SRC_FILE = 0, HS_SRC_MATH, HS_SRC_MIX, HS_SOURCES }
char g_HsSourceNames[][] = { "statements file", "quick sums", "mix of both" };
enum { HS_R_NONE = 0, HS_R_HP25, HS_R_HP50, HS_REWARDS }
char g_HsRewardNames[][] = { "nothing", "+25 HP", "+50 HP" };
int g_HsEverySteps[] = { 20, 30, 45, 60, 90, 120 };
int g_HsTimeSteps[] = { 5, 8, 10, 15 };
int g_HsPenaltySteps[] = { 10, 25, 50, 1000 };   // 1000 = slay
int g_HsPlayerSteps[] = { 1, 2, 3 };

char g_HsStatement[HS_MAX][160];
bool g_HsTrue[HS_MAX];
int g_HsCount;

bool g_HsOn;
int g_HsEvery = 45;
int g_HsTime = 8;
int g_HsSource = HS_SRC_MIX;
int g_HsPenalty = 25;
int g_HsReward = HS_R_HP25;
int g_HsPlayers = 1;        // players in the hot seat at once
bool g_HsHumansOnly = true;
float g_HsNext;

bool g_HsPending[MAXPLAYERS + 1];
char g_HsText[MAXPLAYERS + 1][160];
bool g_HsAnswer[MAXPLAYERS + 1];

void HS_MapStart()
{
	HS_Load();
}

bool HS_IsOn()
{
	return g_HsOn;
}

int HS_Load()
{
	g_HsCount = 0;
	char path[PLATFORM_MAX_PATH], truth[16];
	BuildPath(Path_SM, path, sizeof(path), HS_CONFIG);
	KeyValues kv = new KeyValues("HotSeat");
	if (kv.ImportFromFile(path) && kv.GotoFirstSubKey())
	{
		do
		{
			if (g_HsCount >= HS_MAX)
				break;
			kv.GetString("statement", g_HsStatement[g_HsCount], sizeof(g_HsStatement[]), "");
			kv.GetString("answer", truth, sizeof(truth), "");
			if (g_HsStatement[g_HsCount][0] == '\0')
				continue;
			g_HsTrue[g_HsCount] = truth[0] == 't' || truth[0] == 'T' || truth[0] == 'y' || truth[0] == 'Y' || truth[0] == '1';
			g_HsCount++;
		}
		while (kv.GotoNextKey());
	}
	delete kv;
	return g_HsCount;
}

void HS_Clear()
{
	g_HsNext = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_HsPending[i] = false;
}

void HS_Stop()
{
	g_HsOn = false;
	HS_Clear();
}

void HS_RoundStart()
{
	HS_Clear();
	if (g_HsOn)
		PrintToChatAll(HS_TAG ... "Hot Seat is on: if a TRUE / FALSE menu pops up, answer fast!");
}

// A sum that's right half the time: "7 x 8 = 56" (true) or "7 x 8 = 54" (false).
void HS_MakeSum(char[] text, int len, bool &truth)
{
	int a, b, real;
	char op[4];
	switch (GetRandomInt(0, 2))
	{
		case 0:
		{
			a = GetRandomInt(5, 60);
			b = GetRandomInt(5, 60);
			real = a + b;
			strcopy(op, sizeof(op), "+");
		}
		case 1:
		{
			a = GetRandomInt(20, 99);
			b = GetRandomInt(1, a);
			real = a - b;
			strcopy(op, sizeof(op), "-");
		}
		default:
		{
			a = GetRandomInt(2, 12);
			b = GetRandomInt(2, 12);
			real = a * b;
			strcopy(op, sizeof(op), "x");
		}
	}
	truth = GetRandomInt(0, 1) == 1;
	int shown = real;
	if (!truth)
	{
		int off = GetRandomInt(1, 3) * (GetRandomInt(0, 1) == 1 ? 1 : -1);
		shown = real + off == real ? real + 1 : real + off;
	}
	Format(text, len, "%d %s %d = %d", a, op, b, shown);
}

void HS_Pick(int client)
{
	bool useFile = g_HsCount > 0 && (g_HsSource == HS_SRC_FILE || (g_HsSource == HS_SRC_MIX && GetRandomInt(0, 1) == 1));
	if (useFile)
	{
		int q = GetRandomInt(0, g_HsCount - 1);
		strcopy(g_HsText[client], sizeof(g_HsText[]), g_HsStatement[q]);
		g_HsAnswer[client] = g_HsTrue[q];
	}
	else
		HS_MakeSum(g_HsText[client], sizeof(g_HsText[]), g_HsAnswer[client]);
}

bool HS_Eligible(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client) || g_HsPending[client])
		return false;
	return !g_HsHumansOnly || GetClientTeam(client) == CS_TEAM_CT;
}

void HS_Ask()
{
	int list[MAXPLAYERS + 1], n = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (HS_Eligible(i))
			list[n++] = i;
	for (int i = n - 1; i > 0; i--)   // shuffle
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}
	int count = g_HsPlayers < n ? g_HsPlayers : n;
	for (int k = 0; k < count; k++)
	{
		int c = list[k];
		HS_Pick(c);
		g_HsPending[c] = true;

		Menu menu = new Menu(HSHandler);
		char title[256];
		Format(title, sizeof(title), "HOT SEAT! (%d s)\n \n%s\n ", g_HsTime, g_HsText[c]);
		menu.SetTitle(title);
		menu.AddItem("t", "TRUE");
		menu.AddItem("f", "FALSE");
		menu.ExitButton = false;
		menu.Display(c, g_HsTime);
		PrintToChatAll(HS_TAG ... "\x07" ... "FFA040%N\x01 is in the HOT SEAT: \"%s\"  TRUE or FALSE?", c, g_HsText[c]);
	}
	if (count > 0)
		EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 90);
}

void HS_Result(int client, int said)   // said: 1 true, 0 false, -1 no answer
{
	if (!g_HsPending[client])
		return;
	g_HsPending[client] = false;
	bool right = said != -1 && (said == 1) == g_HsAnswer[client];
	char answer[8];
	strcopy(answer, sizeof(answer), g_HsAnswer[client] ? "TRUE" : "FALSE");
	if (right)
	{
		int heal = g_HsReward == HS_R_HP25 ? 25 : (g_HsReward == HS_R_HP50 ? 50 : 0);
		if (heal > 0 && IsPlayerAlive(client))
			SetEntityHealth(client, GetClientHealth(client) + heal);
		if (heal > 0)
			PrintToChatAll(HS_TAG ... "%N said %s - \x07" ... "60FF60RIGHT!\x01 (+%d HP)", client, answer, heal);
		else
			PrintToChatAll(HS_TAG ... "%N said %s - \x07" ... "60FF60RIGHT!", client, answer);
		return;
	}
	if (said == -1)
		PrintToChatAll(HS_TAG ... "%N didn't answer in time! It was %s.", client, answer);
	else
		PrintToChatAll(HS_TAG ... "%N said %s - \x07" ... "FF6060WRONG!\x01", client, said == 1 ? "TRUE" : "FALSE");
	if (IsPlayerAlive(client))
		HurtPlayer(client, g_HsPenalty);
}

public int HSHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Select)
	{
		char info[4];
		menu.GetItem(item, info, sizeof(info));
		HS_Result(client, info[0] == 't' ? 1 : 0);
	}
	else if (action == MenuAction_Cancel && client > 0 && client <= MaxClients && IsClientInGame(client))
		HS_Result(client, -1);   // ran out of time, or another menu replaced it
	return 0;
}

void HS_Tick()
{
	if (!g_HsOn || !g_RoundLive)
		return;
	float now = GetGameTime();
	if (g_HsNext == 0.0)
		g_HsNext = now + 20.0;
	if (now >= g_HsNext)
	{
		HS_Ask();
		g_HsNext = now + float(g_HsEvery);
	}
}

// ---------------------------------------------------------------- menu

void HSMenu(int client)
{
	Menu menu = new Menu(HSAdminHandler);
	char title[96], line[64];
	Format(title, sizeof(title), "Hot Seat - %s\n%d statements loaded\n ", g_HsOn ? "ON" : "OFF", g_HsCount);
	menu.SetTitle(title);
	menu.AddItem("toggle", g_HsOn ? "Turn Hot Seat OFF" : "Turn Hot Seat ON");
	menu.AddItem("now", "Put someone in the hot seat now", (g_HsOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_HsEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Time to answer: %d s", g_HsTime);
	menu.AddItem("time", line);
	Format(line, sizeof(line), "Questions: %s", g_HsSourceNames[g_HsSource]);
	menu.AddItem("source", line);
	if (g_HsPenalty >= 1000)
		strcopy(line, sizeof(line), "Wrong / no answer: slay");
	else
		Format(line, sizeof(line), "Wrong / no answer: -%d HP", g_HsPenalty);
	menu.AddItem("penalty", line);
	Format(line, sizeof(line), "Right answer: %s", g_HsRewardNames[g_HsReward]);
	menu.AddItem("reward", line);
	Format(line, sizeof(line), "Players at once: %d", g_HsPlayers);
	menu.AddItem("players", line);
	Format(line, sizeof(line), "Who: %s", g_HsHumansOnly ? "humans only" : "everyone alive");
	menu.AddItem("who", line);
	menu.AddItem("reload", "Reload the statements file");
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int HSAdminHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_HsOn;
			HS_Stop();
			g_HsOn = on;
			PrintToChatAll(HS_TAG ... "%N turned Hot Seat %s.", client, on ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned hot seat %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
		{
			HS_Ask();
			return 0;   // our menu would be replaced by theirs if the admin got picked
		}
		else if (StrEqual(info, "every"))
			g_HsEvery = NextInt(g_HsEverySteps, sizeof(g_HsEverySteps), g_HsEvery);
		else if (StrEqual(info, "time"))
			g_HsTime = NextInt(g_HsTimeSteps, sizeof(g_HsTimeSteps), g_HsTime);
		else if (StrEqual(info, "source"))
			g_HsSource = (g_HsSource + 1) % HS_SOURCES;
		else if (StrEqual(info, "penalty"))
			g_HsPenalty = NextInt(g_HsPenaltySteps, sizeof(g_HsPenaltySteps), g_HsPenalty);
		else if (StrEqual(info, "reward"))
			g_HsReward = (g_HsReward + 1) % HS_REWARDS;
		else if (StrEqual(info, "players"))
			g_HsPlayers = NextInt(g_HsPlayerSteps, sizeof(g_HsPlayerSteps), g_HsPlayers);
		else if (StrEqual(info, "who"))
			g_HsHumansOnly = !g_HsHumansOnly;
		else if (StrEqual(info, "reload"))
			PrintToChat(client, HS_TAG ... "Loaded %d statements.", HS_Load());
		HSMenu(client);
	}
	return 0;
}
