// Trivia module of eventmodes.sp.
// eventmodes.sp calls TV_PluginStart, TV_MapStart and TV_Say (every chat message); modes.sp calls
// TV_Tick (every second), TV_RoundStart, TV_RoundEnd and TV_Stop.
//
// Every so often everyone gets the same general-knowledge question from configs/eventmodes/trivia.cfg
// and types the answer in chat. Several answers can count ("answer" "usa|united states"); case,
// punctuation and extra spaces don't matter, and players can keep guessing until time runs out. The
// first players to get it right win the reward. Halfway through, a hint shows the answer's shape.

#if defined _em_trivia_included
 #endinput
#endif
#define _em_trivia_included

#define TV_TAG    "\x07" ... "40E0A0[Trivia]\x01 "   // kept apart: \x would eat the hex digits
#define TV_CONFIG "configs/eventmodes/trivia.cfg"
#define TV_MAX    500

enum { TV_R_HP25 = 0, TV_R_HP50, TV_R_HE, TV_R_NONE, TV_REWARDS }
char g_TvRewardNames[][] = { "+25 HP", "+50 HP", "HE grenade", "nothing (just for fun)" };
int g_TvEverySteps[] = { 30, 45, 60, 90, 120, 180 };
int g_TvTimeSteps[] = { 15, 20, 30, 45 };
int g_TvWinnerSteps[] = { 1, 3, 5, 64 };   // 64 = everyone who gets it

char g_TvQuestion[TV_MAX][160];
char g_TvAnswers[TV_MAX][128];
int g_TvCount;
int g_TvOrder[TV_MAX];
int g_TvPos;

bool g_TvOn;
int g_TvEvery = 60;
int g_TvTime = 30;
int g_TvWinners = 3;
int g_TvReward = TV_R_HP25;
bool g_TvHint = true;
bool g_TvHide = true;       // right answers don't show in chat (so nobody copies them)
bool g_TvHumansOnly;

bool g_TvActive;
int g_TvCur;
float g_TvAsked;
float g_TvEnds;
float g_TvNext;
bool g_TvHinted;
int g_TvPlaced;
bool g_TvWon[MAXPLAYERS + 1];
char g_TvResults[192];
Handle g_HudTrivia;

void TV_PluginStart()
{
	g_HudTrivia = EM_HudSync();
}

void TV_MapStart()
{
	TV_Load();
}

bool TV_IsOn()
{
	return g_TvOn;
}

void TV_Shuffle()
{
	for (int i = 0; i < g_TvCount; i++)
		g_TvOrder[i] = i;
	for (int i = g_TvCount - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = g_TvOrder[i];
		g_TvOrder[i] = g_TvOrder[j];
		g_TvOrder[j] = tmp;
	}
	g_TvPos = 0;
}

int TV_Load()
{
	g_TvCount = 0;
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), TV_CONFIG);
	KeyValues kv = new KeyValues("Trivia");
	if (kv.ImportFromFile(path) && kv.GotoFirstSubKey())
	{
		do
		{
			if (g_TvCount >= TV_MAX)
				break;
			kv.GetString("question", g_TvQuestion[g_TvCount], sizeof(g_TvQuestion[]), "");
			kv.GetString("answer", g_TvAnswers[g_TvCount], sizeof(g_TvAnswers[]), "");
			if (g_TvQuestion[g_TvCount][0] != '\0' && g_TvAnswers[g_TvCount][0] != '\0')
				g_TvCount++;
		}
		while (kv.GotoNextKey());
	}
	delete kv;
	TV_Shuffle();
	return g_TvCount;
}

// Lowercase letters and digits, single spaces: "  The U.S.A! " -> "the usa".
void TV_Norm(const char[] text, char[] out, int len)
{
	int o = 0;
	bool space = false;
	for (int i = 0; text[i] != '\0' && o < len - 1; i++)
	{
		int c = CharToLower(text[i]);
		if (IsCharAlpha(c) || IsCharNumeric(c))
		{
			if (space && o > 0 && o < len - 1)
				out[o++] = ' ';
			space = false;
			out[o++] = c;
		}
		else if (c == ' ')
			space = true;
	}
	out[o] = '\0';
}

bool TV_Matches(int q, const char[] typed)
{
	char guess[128], parts[8][64], want[64];
	TV_Norm(typed, guess, sizeof(guess));
	if (guess[0] == '\0')
		return false;
	int n = ExplodeString(g_TvAnswers[q], "|", parts, sizeof(parts), sizeof(parts[]));
	for (int k = 0; k < n; k++)
	{
		TV_Norm(parts[k], want, sizeof(want));
		if (want[0] != '\0' && StrEqual(guess, want))
			return true;
	}
	return false;
}

// "P____ (5 letters)" from the first accepted answer: first letter of each word, the rest blanks.
void TV_HintText(int q, char[] out, int len)
{
	char first[64];
	int bar = FindCharInString(g_TvAnswers[q], '|');
	strcopy(first, bar == -1 ? sizeof(first) : (bar + 1 < sizeof(first) ? bar + 1 : sizeof(first)), g_TvAnswers[q]);
	int o = 0;
	bool wordStart = true;
	for (int i = 0; first[i] != '\0' && o < len - 2; i++)
	{
		if (first[i] == ' ')
		{
			out[o++] = ' ';
			wordStart = true;
		}
		else if (wordStart)
		{
			out[o++] = CharToUpper(first[i]);
			wordStart = false;
		}
		else
		{
			out[o++] = '_';
		}
	}
	out[o] = '\0';
}

void TV_Clear()
{
	g_TvActive = false;
	g_TvNext = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_TvWon[i] = false;
}

void TV_Stop()
{
	g_TvOn = false;
	TV_Clear();
}

void TV_RoundStart()
{
	TV_Clear();
	if (g_TvOn)
		PrintToChatAll(TV_TAG ... "Trivia is on: when a question pops up, type the answer in chat!");
}

void TV_RoundEnd()
{
	if (g_TvActive)
		PrintToChatAll(TV_TAG ... "Round over - the answer was: \x07" ... "40E0A0%s", g_TvAnswers[g_TvCur]);
	TV_Clear();
}

bool TV_Plays(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return false;
	return !g_TvHumansOnly || (IsPlayerAlive(client) && GetClientTeam(client) == CS_TEAM_CT);
}

void TV_Ask(int admin)
{
	if (g_TvCount == 0 && TV_Load() == 0)
	{
		if (admin != 0)
			PrintToChat(admin, TV_TAG ... "No questions loaded - check addons/sourcemod/%s.", TV_CONFIG);
		LogError("Trivia: no questions in %s", TV_CONFIG);
		g_TvNext = GetGameTime() + float(g_TvEvery);
		return;
	}
	TV_Clear();
	if (g_TvPos >= g_TvCount)
		TV_Shuffle();
	g_TvCur = g_TvOrder[g_TvPos++];
	float now = GetGameTime();
	g_TvActive = true;
	g_TvAsked = now;
	g_TvEnds = now + float(g_TvTime);
	g_TvHinted = false;
	g_TvPlaced = 0;
	g_TvResults[0] = '\0';
	PrintToChatAll(TV_TAG ... "\x07" ... "40E0A0%s\x01  (type the answer in chat - %d s)", g_TvQuestion[g_TvCur], g_TvTime);
	EmitSoundToAll(BEACON_SOUND, _, _, _, _, _, 130);
}

void TV_Finish()
{
	if (g_TvPlaced == 0)
		PrintToChatAll(TV_TAG ... "Time's up! Nobody got it. The answer was: \x07" ... "40E0A0%s", g_TvAnswers[g_TvCur]);
	else
		PrintToChatAll(TV_TAG ... "The answer was: \x07" ... "40E0A0%s\x01 - %s", g_TvAnswers[g_TvCur], g_TvResults);
	TV_Clear();
	g_TvNext = GetGameTime() + float(g_TvEvery);
}

void TV_Reward(int client, char[] said, int len)
{
	said[0] = '\0';
	if (!IsPlayerAlive(client))
		return;
	if (g_TvReward == TV_R_HE && GetClientTeam(client) == CS_TEAM_CT)
	{
		GivePlayerItem(client, "weapon_hegrenade");
		strcopy(said, len, " +HE grenade");
		return;
	}
	int heal = g_TvReward == TV_R_HP25 ? 25 : (g_TvReward == TV_R_NONE ? 0 : 50);   // zombies get HP instead of an HE
	if (heal > 0)
	{
		SetEntityHealth(client, GetClientHealth(client) + heal);
		Format(said, len, " +%d HP", heal);
	}
}

Action TV_Say(int client, const char[] text)
{
	if (!g_TvOn || !g_TvActive || client <= 0 || g_TvWon[client] || !TV_Plays(client))
		return Plugin_Continue;
	char msg[128];
	strcopy(msg, sizeof(msg), text);
	StripQuotes(msg);
	TrimString(msg);
	if (!TV_Matches(g_TvCur, msg))
		return Plugin_Continue;   // wrong guesses are normal chat

	g_TvWon[client] = true;
	g_TvPlaced++;
	float took = GetGameTime() - g_TvAsked;
	if (g_TvPlaced <= g_TvWinners)
	{
		char reward[32];
		TV_Reward(client, reward, sizeof(reward));
		PrintToChat(client, TV_TAG ... "\x07" ... "60FF60Correct!\x01 (#%d, %.1f s)%s", g_TvPlaced, took, reward);
		if (g_TvPlaced <= 5)
			Format(g_TvResults, sizeof(g_TvResults), "%s%s%N (%.1f s)", g_TvResults, g_TvPlaced == 1 ? "" : ", ", client, took);
	}
	else
		PrintToChat(client, TV_TAG ... "Correct - but the winners are already in.");
	if (g_TvWinners < 64 && g_TvPlaced >= g_TvWinners)
		TV_Finish();
	return g_TvHide ? Plugin_Handled : Plugin_Continue;
}

void TV_Tick()
{
	if (!g_TvOn || !g_RoundLive)
		return;
	float now = GetGameTime();
	if (!g_TvActive)
	{
		if (g_TvNext == 0.0)
			g_TvNext = now + 20.0;
		if (now >= g_TvNext)
			TV_Ask(0);
		return;
	}
	if (now >= g_TvEnds)
	{
		TV_Finish();
		return;
	}
	if (g_TvHint && !g_TvHinted && now - g_TvAsked >= float(g_TvTime) / 2.0)
	{
		g_TvHinted = true;
		char hint[128];
		TV_HintText(g_TvCur, hint, sizeof(hint));
		PrintToChatAll(TV_TAG ... "Hint: \x07" ... "40E0A0%s", hint);
	}
	int left = RoundToCeil(g_TvEnds - now);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!TV_Plays(i) || g_TvWon[i])
			continue;
		SetHudTextParams(-1.0, 0.26, 1.1, 64, 224, 160, 255, 0, 0.0, 0.0, 0.0);
		EM_ShowHud(i, g_HudTrivia, "%s\n(%d s - type the answer in chat)", g_TvQuestion[g_TvCur], left);
	}
}

// ---------------------------------------------------------------- menu

void TVMenu(int client, int firstItem = 0)
{
	Menu menu = new Menu(TVHandler);
	char title[96], line[64];
	Format(title, sizeof(title), "Trivia - %s\n%d questions loaded\n ", g_TvOn ? "ON" : "OFF", g_TvCount);
	menu.SetTitle(title);
	menu.AddItem("toggle", g_TvOn ? "Turn Trivia OFF" : "Turn Trivia ON");
	menu.AddItem("ask", "Ask a question now", (g_TvOn && g_RoundLive && !g_TvActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_TvEvery);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Time to answer: %d s", g_TvTime);
	menu.AddItem("time", line);
	if (g_TvWinners >= 64)
		strcopy(line, sizeof(line), "Winners: everyone who gets it");
	else
		Format(line, sizeof(line), "Winners: first %d", g_TvWinners);
	menu.AddItem("winners", line);
	Format(line, sizeof(line), "Reward: %s", g_TvRewardNames[g_TvReward]);
	menu.AddItem("reward", line);
	Format(line, sizeof(line), "Hint halfway: %s", g_TvHint ? "ON" : "OFF");
	menu.AddItem("hint", line);
	Format(line, sizeof(line), "Right answers in chat: %s", g_TvHide ? "hidden" : "shown");
	menu.AddItem("hide", line);
	Format(line, sizeof(line), "Who plays: %s", g_TvHumansOnly ? "living humans only" : "everyone");
	menu.AddItem("who", line);
	menu.AddItem("reload", "Reload the questions file");
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int TVHandler(Menu menu, MenuAction action, int client, int item)
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
			bool on = !g_TvOn;
			TV_Stop();
			g_TvOn = on;
			PrintToChatAll(TV_TAG ... "%N turned Trivia %s.", client, on ? "ON - get your brains ready" : "OFF");
			LogAction(client, -1, "\"%L\" turned trivia %s", client, on ? "on" : "off");
		}
		else if (StrEqual(info, "ask"))
			TV_Ask(client);
		else if (StrEqual(info, "every"))
			g_TvEvery = NextInt(g_TvEverySteps, sizeof(g_TvEverySteps), g_TvEvery);
		else if (StrEqual(info, "time"))
			g_TvTime = NextInt(g_TvTimeSteps, sizeof(g_TvTimeSteps), g_TvTime);
		else if (StrEqual(info, "winners"))
			g_TvWinners = NextInt(g_TvWinnerSteps, sizeof(g_TvWinnerSteps), g_TvWinners);
		else if (StrEqual(info, "reward"))
			g_TvReward = (g_TvReward + 1) % TV_REWARDS;
		else if (StrEqual(info, "hint"))
			g_TvHint = !g_TvHint;
		else if (StrEqual(info, "hide"))
			g_TvHide = !g_TvHide;
		else if (StrEqual(info, "who"))
			g_TvHumansOnly = !g_TvHumansOnly;
		else if (StrEqual(info, "reload"))
			PrintToChat(client, TV_TAG ... "Loaded %d questions.", TV_Load());
		TVMenu(client, GetMenuSelectionPosition());
	}
	return 0;
}
