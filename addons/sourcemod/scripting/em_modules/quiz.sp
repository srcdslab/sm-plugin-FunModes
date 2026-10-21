// Math Quiz module of eventmodes.sp.
// eventmodes.sp calls MQ_PluginStart / MQ_ClientPutInServer; modes.sp calls MQ_Tick (every second),
// MQ_RoundStart, MQ_RoundEnd and MQ_Stop.
//
// Every so often the players get a simple sum (each their own, or everyone the same one) and answer by
// typing the number in chat. One try each. A right answer earns the reward, a wrong or missing answer
// gets the penalty. Typed answers can be hidden from chat so nobody can copy them.

#if defined _em_quiz_included
 #endinput
#endif
#define _em_quiz_included

#define MQ_TAG "\x07" ... "FFE060[Math]\x01 "   // kept apart: \x would eat the hex digits

enum { MQ_EASY = 0, MQ_NORMAL, MQ_HARD, MQ_DIFFS }
char g_MqDiffNames[][] = { "Easy", "Normal", "Hard (two steps)" };

enum { MQ_OPS_ALL = 0, MQ_OPS_ADDSUB, MQ_OPS_MULDIV, MQ_OPS_COUNT }
char g_MqOpsNames[][] = { "+  -  x  /", "+  - only", "x  / only" };

enum { MQ_R_HP25 = 0, MQ_R_HP50, MQ_R_HE, MQ_R_NONE, MQ_REWARDS }
char g_MqRewardNames[][] = { "+25 HP", "+50 HP", "HE grenade", "nothing (just for fun)" };

enum { MQ_P_NONE = 0, MQ_P_HP10, MQ_P_HP25, MQ_P_SLAY, MQ_PENALTIES }
char g_MqPenaltyNames[][] = { "nothing", "-10 HP", "-25 HP", "slay" };

int g_MqIntervalSteps[] = { 30, 45, 60, 90, 120 };
int g_MqTimeSteps[] = { 10, 15, 20, 30 };

// settings
bool g_MqOn;
bool g_MqSame;              // everyone gets the same question (else each their own)
bool g_MqFirstOnly;         // only the fastest right answer gets the reward
bool g_MqEveryone;          // zombies get questions too (else humans only)
bool g_MqHide = true;       // typed answers don't show in chat
int g_MqDiff = MQ_NORMAL;
int g_MqOps = MQ_OPS_ALL;
int g_MqInterval = 60;      // seconds between questions
int g_MqTime = 15;          // seconds to answer
int g_MqReward = MQ_R_HP25;
int g_MqPenalty = MQ_P_NONE;

// the question going on now
bool g_MqActive;
float g_MqAskedAt;
float g_MqEndsAt;
float g_MqNextAt;           // 0 = schedule the first one
bool g_MqPending[MAXPLAYERS + 1];   // asked and not answered yet
char g_MqText[MAXPLAYERS + 1][32];
int g_MqAnswer[MAXPLAYERS + 1];
int g_MqAsked;
int g_MqRight;
int g_MqFastest;            // userid
float g_MqFastestTime;
bool g_MqFirstTaken;

int g_MqScore[MAXPLAYERS + 1];      // right answers this map
Handle g_HudQuiz;

// ---------------------------------------------------------------- lifecycle

void MQ_PluginStart()
{
	g_HudQuiz = EM_HudSync();
}

bool MQ_IsOn()
{
	return g_MqOn;
}

void MQ_ClientPutInServer(int client)
{
	g_MqPending[client] = false;
	g_MqScore[client] = 0;
}

void MQ_Clear()
{
	g_MqActive = false;
	g_MqNextAt = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_MqPending[i] = false;
}

void MQ_Stop()
{
	g_MqOn = false;
	MQ_Clear();
	for (int i = 1; i <= MaxClients; i++)
		g_MqScore[i] = 0;
}

void MQ_RoundStart()
{
	MQ_Clear();
	if (g_MqOn)
		PrintToChatAll(MQ_TAG ... "Math Quiz is on: when a question pops up, type the answer in chat!");
}

void MQ_RoundEnd()
{
	MQ_Clear();
}

// ---------------------------------------------------------------- questions

// A simple sum and its answer. Answers are always whole numbers and never negative.
void MQ_Make(char[] text, int len, int &answer)
{
	int addMax = g_MqDiff == MQ_EASY ? 20 : (g_MqDiff == MQ_NORMAL ? 100 : 500);
	int mulMax = g_MqDiff == MQ_EASY ? 5 : (g_MqDiff == MQ_NORMAL ? 12 : 15);

	// Hard: half the time a two-step sum (multiplication first, as written).
	if (g_MqDiff == MQ_HARD && g_MqOps == MQ_OPS_ALL && GetRandomInt(0, 1) == 0)
	{
		int a = GetRandomInt(2, 12), b = GetRandomInt(2, 12);
		if (GetRandomInt(0, 1) == 0)
		{
			int c = GetRandomInt(1, 50);
			Format(text, len, "%d x %d + %d", a, b, c);
			answer = a * b + c;
		}
		else
		{
			int c = GetRandomInt(1, a * b - 1);
			Format(text, len, "%d x %d - %d", a, b, c);
			answer = a * b - c;
		}
		return;
	}

	int op;
	if (g_MqOps == MQ_OPS_ADDSUB)
		op = GetRandomInt(0, 1);
	else if (g_MqOps == MQ_OPS_MULDIV)
		op = GetRandomInt(2, 3);
	else
		op = GetRandomInt(0, 3);

	switch (op)
	{
		case 0:
		{
			int a = GetRandomInt(1, addMax), b = GetRandomInt(1, addMax);
			Format(text, len, "%d + %d", a, b);
			answer = a + b;
		}
		case 1:
		{
			int a = GetRandomInt(2, addMax), b = GetRandomInt(1, a);
			Format(text, len, "%d - %d", a, b);
			answer = a - b;
		}
		case 2:
		{
			int a = GetRandomInt(2, mulMax), b = GetRandomInt(2, mulMax);
			Format(text, len, "%d x %d", a, b);
			answer = a * b;
		}
		default:
		{
			int b = GetRandomInt(2, mulMax), q = GetRandomInt(2, mulMax);
			Format(text, len, "%d / %d", b * q, b);
			answer = q;
		}
	}
}

bool MQ_Eligible(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client))
		return false;
	int team = GetClientTeam(client);
	return team == CS_TEAM_CT || (g_MqEveryone && team == CS_TEAM_T);
}

void MQ_Ask()
{
	MQ_Clear();
	float now = GetGameTime();
	g_MqAskedAt = now;
	g_MqEndsAt = now + float(g_MqTime);
	g_MqAsked = 0;
	g_MqRight = 0;
	g_MqFastest = 0;
	g_MqFirstTaken = false;

	char shared[32];
	int sharedAnswer;
	if (g_MqSame)
		MQ_Make(shared, sizeof(shared), sharedAnswer);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!MQ_Eligible(i))
			continue;
		if (g_MqSame)
		{
			strcopy(g_MqText[i], sizeof(g_MqText[]), shared);
			g_MqAnswer[i] = sharedAnswer;
		}
		else
			MQ_Make(g_MqText[i], sizeof(g_MqText[]), g_MqAnswer[i]);
		g_MqPending[i] = true;
		g_MqAsked++;
		PrintToChat(i, MQ_TAG ... "QUESTION: \x07" ... "FFE060%s = ?\x01  Type the answer in chat (%d s).", g_MqText[i], g_MqTime);
	}
	g_MqActive = g_MqAsked > 0;
	if (!g_MqActive)
		g_MqNextAt = now + float(g_MqInterval);
}

// Whole number, optional minus; anything else is normal chat.
bool MQ_ParseInt(const char[] s, int &value)
{
	int len = strlen(s);
	if (len == 0 || len > 9)
		return false;
	for (int i = 0; i < len; i++)
		if (!IsCharNumeric(s[i]) && !(i == 0 && s[i] == '-' && len > 1))
			return false;
	value = StringToInt(s);
	return true;
}

// Called from eventmodes.sp's OnClientSayCommand.
Action MQ_Say(int client, const char[] sArgs)
{
	if (!g_MqOn || !g_MqActive || client <= 0 || client > MaxClients || !g_MqPending[client])
		return Plugin_Continue;
	char msg[32];
	strcopy(msg, sizeof(msg), sArgs);
	StripQuotes(msg);
	TrimString(msg);
	int value;
	if (!MQ_ParseInt(msg, value))
		return Plugin_Continue;

	g_MqPending[client] = false;   // one try
	if (value == g_MqAnswer[client])
		MQ_Right(client, GetGameTime() - g_MqAskedAt);
	else
		MQ_Wrong(client, false);

	bool anyLeft = false;
	for (int i = 1; i <= MaxClients && !anyLeft; i++)
		anyLeft = g_MqPending[i];
	if (!anyLeft)
		MQ_Finish();
	return g_MqHide ? Plugin_Handled : Plugin_Continue;
}

void MQ_Right(int client, float took)
{
	g_MqRight++;
	g_MqScore[client]++;
	if (g_MqFastest == 0 || took < g_MqFastestTime)
	{
		g_MqFastest = GetClientUserId(client);
		g_MqFastestTime = took;
	}

	if (g_MqFirstOnly && g_MqFirstTaken)
	{
		PrintToChat(client, MQ_TAG ... "Correct (%.1f s) - but someone was faster, no reward this time.", took);
		return;
	}
	g_MqFirstTaken = true;

	char reward[48];
	MQ_GiveReward(client, reward, sizeof(reward));
	PrintToChat(client, MQ_TAG ... "\x07" ... "60FF60Correct!\x01 (%.1f s)%s", took, reward);
}

void MQ_GiveReward(int client, char[] said, int len)
{
	said[0] = '\0';
	if (!IsPlayerAlive(client))
		return;
	int heal = 0;
	if (g_MqReward == MQ_R_HP25)
		heal = 25;
	else if (g_MqReward == MQ_R_HP50)
		heal = 50;
	else if (g_MqReward == MQ_R_HE)
	{
		if (GetClientTeam(client) == CS_TEAM_CT)
		{
			GivePlayerItem(client, "weapon_hegrenade");
			strcopy(said, len, " +HE grenade");
			return;
		}
		heal = 50;   // zombies can't use grenades
	}
	if (heal > 0)
	{
		SetEntityHealth(client, GetClientHealth(client) + heal);
		Format(said, len, " +%d HP", heal);
	}
}

void MQ_Wrong(int client, bool timeout)
{
	if (timeout)
		PrintToChat(client, MQ_TAG ... "Time's up! %s = \x07" ... "FFE060%d", g_MqText[client], g_MqAnswer[client]);
	else
		PrintToChat(client, MQ_TAG ... "\x07" ... "FF6060Wrong!\x01 %s = \x07" ... "FFE060%d", g_MqText[client], g_MqAnswer[client]);

	if (g_MqPenalty == MQ_P_NONE || !IsPlayerAlive(client))
		return;
	if (g_MqPenalty == MQ_P_SLAY)
	{
		ForcePlayerSuicide(client);
		return;
	}
	int hp = GetClientHealth(client) - (g_MqPenalty == MQ_P_HP10 ? 10 : 25);
	if (hp <= 0)
		ForcePlayerSuicide(client);
	else
		SetEntityHealth(client, hp);
}

void MQ_Finish()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_MqPending[i])
			continue;
		g_MqPending[i] = false;
		if (IsClientInGame(i))
			MQ_Wrong(i, true);
	}
	g_MqActive = false;
	g_MqNextAt = GetGameTime() + float(g_MqInterval);

	int fastest = GetClientOfUserId(g_MqFastest);
	if (g_MqRight == 0)
		PrintToChatAll(MQ_TAG ... "Nobody got it right this time (%d asked).", g_MqAsked);
	else if (fastest != 0)
		PrintToChatAll(MQ_TAG ... "%d of %d got it right. Fastest: \x07" ... "FFE060%N\x01 (%.1f s)", g_MqRight, g_MqAsked, fastest, g_MqFastestTime);
	else
		PrintToChatAll(MQ_TAG ... "%d of %d got it right.", g_MqRight, g_MqAsked);
}

void MQ_Tick()
{
	if (!g_MqOn)
		return;
	float now = GetGameTime();
	if (!g_MqActive)
	{
		if (g_MqNextAt == 0.0)
			g_MqNextAt = now + 15.0;   // first question a little into the round
		if (now >= g_MqNextAt)
			MQ_Ask();
		return;
	}
	if (now >= g_MqEndsAt)
	{
		MQ_Finish();
		return;
	}
	int left = RoundToCeil(g_MqEndsAt - now);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!g_MqPending[i] || !IsClientInGame(i))
			continue;
		SetHudTextParams(-1.0, 0.30, 1.1, 255, 224, 96, 255, 0, 0.0, 0.0, 0.0);
		EM_ShowHud(i, g_HudQuiz, "%s = ?\n(%d s - type the answer in chat)", g_MqText[i], left);
	}
}

// Best scorer this map for the menu: 0 if nobody scored yet.
int MQ_Leader()
{
	int best = 0;
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && g_MqScore[i] > 0 && (best == 0 || g_MqScore[i] > g_MqScore[best]))
			best = i;
	return best;
}

// ---------------------------------------------------------------- menu

void QuizMenu(int client, int firstItem = 0)
{
	Menu menu = new Menu(QuizHandler);
	char title[128], line[64];
	int leader = MQ_Leader();
	if (!g_MqOn)
		strcopy(title, sizeof(title), "Math Quiz - OFF\n ");
	else if (leader == 0)
		strcopy(title, sizeof(title), "Math Quiz - ON\n ");
	else
		Format(title, sizeof(title), "Math Quiz - ON\nTop: %N (%d right)\n ", leader, g_MqScore[leader]);
	menu.SetTitle(title);

	menu.AddItem("toggle", g_MqOn ? "Turn Math Quiz OFF" : "Turn Math Quiz ON");
	menu.AddItem("ask", "Ask a question now", (g_MqOn && g_RoundLive && !g_MqActive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Questions: %s", g_MqSame ? "same for everyone" : "different per player");
	menu.AddItem("same", line);
	Format(line, sizeof(line), "Difficulty: %s", g_MqDiffNames[g_MqDiff]);
	menu.AddItem("diff", line);
	Format(line, sizeof(line), "Operations: %s", g_MqOpsNames[g_MqOps]);
	menu.AddItem("ops", line);
	Format(line, sizeof(line), "Every: %d s", g_MqInterval);
	menu.AddItem("every", line);
	Format(line, sizeof(line), "Time to answer: %d s", g_MqTime);
	menu.AddItem("time", line);
	Format(line, sizeof(line), "Right answer: %s", g_MqRewardNames[g_MqReward]);
	menu.AddItem("reward", line);
	Format(line, sizeof(line), "Wrong / no answer: %s", g_MqPenaltyNames[g_MqPenalty]);
	menu.AddItem("penalty", line);
	Format(line, sizeof(line), "Reward goes to: %s", g_MqFirstOnly ? "fastest right answer only" : "every right answer");
	menu.AddItem("first", line);
	Format(line, sizeof(line), "Who gets questions: %s", g_MqEveryone ? "everyone alive" : "humans only");
	menu.AddItem("who", line);
	Format(line, sizeof(line), "Typed answers in chat: %s", g_MqHide ? "hidden" : "shown");
	menu.AddItem("hide", line);
	menu.ExitBackButton = true;
	menu.DisplayAt(client, firstItem, MENU_TIME_FOREVER);
}

public int QuizHandler(Menu menu, MenuAction action, int client, int item)
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
			if (g_MqOn)
				MQ_Stop();
			else
			{
				MQ_Stop();   // fresh scores
				g_MqOn = true;
			}
			PrintToChatAll(MQ_TAG ... "%N turned the Math Quiz %s.", client, g_MqOn ? "ON - get ready to type some answers" : "OFF");
			LogAction(client, -1, "\"%L\" turned the math quiz %s", client, g_MqOn ? "on" : "off");
		}
		else if (StrEqual(info, "ask"))
			MQ_Ask();
		else if (StrEqual(info, "same"))
			g_MqSame = !g_MqSame;
		else if (StrEqual(info, "diff"))
			g_MqDiff = (g_MqDiff + 1) % MQ_DIFFS;
		else if (StrEqual(info, "ops"))
			g_MqOps = (g_MqOps + 1) % MQ_OPS_COUNT;
		else if (StrEqual(info, "every"))
			g_MqInterval = NextInt(g_MqIntervalSteps, sizeof(g_MqIntervalSteps), g_MqInterval);
		else if (StrEqual(info, "time"))
			g_MqTime = NextInt(g_MqTimeSteps, sizeof(g_MqTimeSteps), g_MqTime);
		else if (StrEqual(info, "reward"))
			g_MqReward = (g_MqReward + 1) % MQ_REWARDS;
		else if (StrEqual(info, "penalty"))
			g_MqPenalty = (g_MqPenalty + 1) % MQ_PENALTIES;
		else if (StrEqual(info, "first"))
			g_MqFirstOnly = !g_MqFirstOnly;
		else if (StrEqual(info, "who"))
			g_MqEveryone = !g_MqEveryone;
		else if (StrEqual(info, "hide"))
			g_MqHide = !g_MqHide;
		QuizMenu(client, GetMenuSelectionPosition());   // stay on the same page
	}
	return 0;
}
