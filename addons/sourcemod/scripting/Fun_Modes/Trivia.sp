/*
    (). FunModes V2:

    @file           Trivia.sp
    @Usage          Functions for the Trivia mode.
                    Every so often a question from configs/FunModes/Trivia.cfg pops up and the players type the
                    answer in chat: the first ones to get it right win a reward. A hint shows half way through.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Trivia

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Trivia"

static int g_iTriviaIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iTriviaIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define TRIVIA_CONVAR_EVERY   0
#define TRIVIA_CONVAR_TIME    1
#define TRIVIA_CONVAR_WINNERS 2
#define TRIVIA_CONVAR_REWARD  3
#define TRIVIA_CONVAR_HINT    4
#define TRIVIA_CONVAR_HIDE    5
#define TRIVIA_CONVAR_HUMANS  6
#define TRIVIA_CONVAR_TOGGLE  7

int g_iTrivia_Every;
int g_iTrivia_Time;
int g_iTrivia_Winners;
int g_iTrivia_Reward;
bool g_bTrivia_Hint;
bool g_bTrivia_Hide;
bool g_bTrivia_HumansOnly;
bool g_bTrivia_Enabled;

public void OnPluginStart_Trivia()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_GAMES;

	/* COMMANDS */
	RegAdminCmd("sm_fm_trivia", Cmd_TriviaToggle, ADMFLAG_CONVARS, "Turn Trivia On/Off");
	RegAdminCmd("sm_trivia_settings", Cmd_TriviaSettings, ADMFLAG_CONVARS, "Open Trivia Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_EVERY, "sm_trivia_every",
		"60", "Seconds between two questions",
		("30,45,60,90,120,180"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_TIME, "sm_trivia_time",
		"30", "Seconds to answer",
		("15,20,30,45"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_WINNERS, "sm_trivia_winners",
		"3", "How many players win (64 = everyone who gets it)",
		("1,3,5,64"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_REWARD, "sm_trivia_reward",
		"0", ("Reward for a right answer [0 = +25 HP, 1 = +50 HP, 2 = HE grenade, 3 = nothing]"),
		("0,1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_HINT, "sm_trivia_hint",
		"1", "Show a hint half way through",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_HIDE, "sm_trivia_hide",
		"1", "Right answers don't show in chat (so nobody copies them)",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_HUMANS, "sm_trivia_humans_only",
		"0", "Only the living humans can answer",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		TRIVIA_CONVAR_TOGGLE, "sm_trivia_enable",
		"1", "Enable/Disable Trivia Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= TRIVIA_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Trivia_OnConVarChange);

	THIS_MODE_INFO.enableIndex = TRIVIA_CONVAR_TOGGLE;

	Trivia_OnPluginStart();
}

public void InitCvarsValues_Trivia()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iTrivia_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_EVERY, Int);
	g_iTrivia_Time = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_TIME, Int);
	g_iTrivia_Winners = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_WINNERS, Int);
	g_iTrivia_Reward = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_REWARD, Int);
	g_bTrivia_Hint = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_HINT, Bool);
	g_bTrivia_Hide = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_HIDE, Bool);
	g_bTrivia_HumansOnly = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_HUMANS, Bool);
	g_bTrivia_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, TRIVIA_CONVAR_TOGGLE, Bool);
}

void Trivia_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case TRIVIA_CONVAR_EVERY:
			g_iTrivia_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case TRIVIA_CONVAR_TIME:
			g_iTrivia_Time = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case TRIVIA_CONVAR_WINNERS:
			g_iTrivia_Winners = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case TRIVIA_CONVAR_REWARD:
			g_iTrivia_Reward = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case TRIVIA_CONVAR_HINT:
			g_bTrivia_Hint = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case TRIVIA_CONVAR_HIDE:
			g_bTrivia_Hide = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case TRIVIA_CONVAR_HUMANS:
			g_bTrivia_HumansOnly = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case TRIVIA_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Trivia_Reset();
			}

			g_bTrivia_Enabled = val;
		}
	}
}

public void OnMapEnd_Trivia()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Trivia_Reset();
}

#define TRIVIA_CONFIG "configs/FunModes/Trivia.cfg"
#define TRIVIA_MAX    500

#define TRIVIA_REWARD_HP25 0
#define TRIVIA_REWARD_HP50 1
#define TRIVIA_REWARD_HE   2
#define TRIVIA_REWARD_NONE 3

char g_sTrivia_Question[TRIVIA_MAX][160];
char g_sTrivia_Answers[TRIVIA_MAX][128];
int g_iTrivia_Count;
int g_iTrivia_Order[TRIVIA_MAX];
int g_iTrivia_Pos;

bool g_bTrivia_Active;
int g_iTrivia_Cur;
float g_fTrivia_Asked;
float g_fTrivia_Ends;
float g_fTrivia_Next;
bool g_bTrivia_Hinted;
int g_iTrivia_Placed;
bool g_bTrivia_Won[MAXPLAYERS + 1];
char g_sTrivia_Results[192];
Handle g_hTrivia_Hud;

void Trivia_OnPluginStart()
{
	g_hTrivia_Hud = CreateModeHud();
}

public void OnMapStart_Trivia()
{
	Trivia_Load();
}

void Trivia_Shuffle()
{
	for (int i = 0; i < g_iTrivia_Count; i++)
		g_iTrivia_Order[i] = i;

	for (int i = g_iTrivia_Count - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = g_iTrivia_Order[i];
		g_iTrivia_Order[i] = g_iTrivia_Order[j];
		g_iTrivia_Order[j] = tmp;
	}

	g_iTrivia_Pos = 0;
}

int Trivia_Load()
{
	g_iTrivia_Count = 0;

	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), TRIVIA_CONFIG);

	KeyValues kv = new KeyValues("Trivia");
	if (!FunModes_LoadKV(kv, path))
		LogError("[FunModes-Trivia] %s", g_sKvError);
	else if (kv.GotoFirstSubKey())
	{
		do
		{
			if (g_iTrivia_Count >= TRIVIA_MAX)
				break;

			kv.GetString("question", g_sTrivia_Question[g_iTrivia_Count], sizeof(g_sTrivia_Question[]), "");
			kv.GetString("answer", g_sTrivia_Answers[g_iTrivia_Count], sizeof(g_sTrivia_Answers[]), "");
			if (g_sTrivia_Question[g_iTrivia_Count][0] && g_sTrivia_Answers[g_iTrivia_Count][0])
				g_iTrivia_Count++;
		} while (kv.GotoNextKey());
	}

	delete kv;
	Trivia_Shuffle();
	return g_iTrivia_Count;
}

/* Lowercase letters and digits, single spaces: "  The U.S.A! " -> "the usa" */
void Trivia_Normalize(const char[] text, char[] out, int maxlen)
{
	int o;
	bool space = false;
	for (int i = 0; text[i] != '\0' && o < maxlen - 1; i++)
	{
		int c = CharToLower(text[i]);
		if (IsCharAlpha(c) || IsCharNumeric(c))
		{
			if (space && o > 0 && o < maxlen - 1)
				out[o++] = ' ';

			space = false;
			out[o++] = c;
		}
		else if (c == ' ')
			space = true;
	}

	out[o] = '\0';
}

bool Trivia_Matches(int question, const char[] typed)
{
	char guess[128], parts[8][64], want[64];
	Trivia_Normalize(typed, guess, sizeof(guess));
	if (!guess[0])
		return false;

	int count = ExplodeString(g_sTrivia_Answers[question], "|", parts, sizeof(parts), sizeof(parts[]));
	for (int i = 0; i < count; i++)
	{
		Trivia_Normalize(parts[i], want, sizeof(want));
		if (want[0] && strcmp(guess, want) == 0)
			return true;
	}

	return false;
}

/* "P____" from the first accepted answer: first letter of each word, the rest blanks */
void Trivia_HintText(int question, char[] out, int maxlen)
{
	char first[64];
	int bar = FindCharInString(g_sTrivia_Answers[question], '|');
	strcopy(first, bar == -1 ? sizeof(first) : (bar + 1 < sizeof(first) ? bar + 1 : sizeof(first)), g_sTrivia_Answers[question]);

	int o;
	bool wordStart = true;
	for (int i = 0; first[i] != '\0' && o < maxlen - 2; i++)
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
			out[o++] = '_';
	}

	out[o] = '\0';
}

void Trivia_Reset()
{
	g_bTrivia_Active = false;
	g_fTrivia_Next = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_bTrivia_Won[i] = false;
}

public void Event_RoundStart_Trivia()
{
	Trivia_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Trivia is on: when a question pops up, {olive}type the answer in chat{lightgreen}!", THIS_MODE_INFO.tag);
}

public void Event_RoundEnd_Trivia()
{
	if (THIS_MODE_INFO.isOn && g_bTrivia_Active)
		CPrintToChatAll("%s Round over - the answer was: {olive}%s", THIS_MODE_INFO.tag, g_sTrivia_Answers[g_iTrivia_Cur]);

	Trivia_Reset();
}

bool Trivia_Plays(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client))
		return false;

	return !g_bTrivia_HumansOnly || IsHumanAlive(client);
}

void Trivia_Ask(int admin)
{
	if (!g_iTrivia_Count && !Trivia_Load())
	{
		if (admin)
			CPrintToChat(admin, "%s No questions loaded - check addons/sourcemod/%s.", THIS_MODE_INFO.tag, TRIVIA_CONFIG);

		LogError("[FunModes-Trivia] No questions in %s", TRIVIA_CONFIG);
		g_fTrivia_Next = GetGameTime() + float(g_iTrivia_Every);
		return;
	}

	Trivia_Reset();
	if (g_iTrivia_Pos >= g_iTrivia_Count)
		Trivia_Shuffle();

	g_iTrivia_Cur = g_iTrivia_Order[g_iTrivia_Pos++];

	float now = GetGameTime();
	g_bTrivia_Active = true;
	g_fTrivia_Asked = now;
	g_fTrivia_Ends = now + float(g_iTrivia_Time);
	g_bTrivia_Hinted = false;
	g_iTrivia_Placed = 0;
	g_sTrivia_Results[0] = '\0';

	CPrintToChatAll("%s {olive}%s {lightgreen}(type the answer in chat - %d s)", THIS_MODE_INFO.tag, g_sTrivia_Question[g_iTrivia_Cur], g_iTrivia_Time);
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 130);
}

void Trivia_Finish()
{
	if (!g_iTrivia_Placed)
		CPrintToChatAll("%s Time's up! Nobody got it. The answer was: {olive}%s", THIS_MODE_INFO.tag, g_sTrivia_Answers[g_iTrivia_Cur]);
	else
		CPrintToChatAll("%s The answer was: {olive}%s {lightgreen}- %s", THIS_MODE_INFO.tag, g_sTrivia_Answers[g_iTrivia_Cur], g_sTrivia_Results);

	Trivia_Reset();
	g_fTrivia_Next = GetGameTime() + float(g_iTrivia_Every);
}

void Trivia_Reward(int client, char[] said, int maxlen)
{
	said[0] = '\0';
	if (!IsPlayerAlive(client))
		return;

	if (g_iTrivia_Reward == TRIVIA_REWARD_HE && ZR_IsClientHuman(client))
	{
		GivePlayerItem(client, "weapon_hegrenade");
		strcopy(said, maxlen, " +HE grenade");
		return;
	}

	// The zombies get health instead of an HE grenade
	int heal = g_iTrivia_Reward == TRIVIA_REWARD_HP25 ? 25 : (g_iTrivia_Reward == TRIVIA_REWARD_NONE ? 0 : 50);
	if (heal > 0)
	{
		SetEntityHealth(client, GetClientHealth(client) + heal);
		FormatEx(said, maxlen, " +%d HP", heal);
	}
}

public void OnClientSayCommand_Trivia(int client, const char[] text, Action &result)
{
	if (!g_bTrivia_Active || client <= 0 || g_bTrivia_Won[client] || !Trivia_Plays(client))
		return;

	char msg[128];
	strcopy(msg, sizeof(msg), text);
	StripQuotes(msg);
	TrimString(msg);

	// Wrong guesses are normal chat
	if (!Trivia_Matches(g_iTrivia_Cur, msg))
		return;

	g_bTrivia_Won[client] = true;
	g_iTrivia_Placed++;

	float took = GetGameTime() - g_fTrivia_Asked;
	if (g_iTrivia_Placed <= g_iTrivia_Winners)
	{
		char reward[32];
		Trivia_Reward(client, reward, sizeof(reward));
		CPrintToChat(client, "%s {olive}Correct! {lightgreen}(#%d, %.1f s)%s", THIS_MODE_INFO.tag, g_iTrivia_Placed, took, reward);

		if (g_iTrivia_Placed <= 5)
			Format(g_sTrivia_Results, sizeof(g_sTrivia_Results), "%s%s%N (%.1f s)", g_sTrivia_Results, g_iTrivia_Placed == 1 ? "" : ", ", client, took);
	}
	else
		CPrintToChat(client, "%s Correct - but the winners are already in.", THIS_MODE_INFO.tag);

	if (g_iTrivia_Winners < 64 && g_iTrivia_Placed >= g_iTrivia_Winners)
		Trivia_Finish();

	if (g_bTrivia_Hide)
		result = Plugin_Handled;
}

public void OnTick_Trivia()
{
	float now = GetGameTime();
	if (!g_bTrivia_Active)
	{
		if (g_fTrivia_Next == 0.0)
			g_fTrivia_Next = now + 20.0;

		if (now >= g_fTrivia_Next)
			Trivia_Ask(0);

		return;
	}

	if (now >= g_fTrivia_Ends)
	{
		Trivia_Finish();
		return;
	}

	if (g_bTrivia_Hint && !g_bTrivia_Hinted && now - g_fTrivia_Asked >= float(g_iTrivia_Time) / 2.0)
	{
		g_bTrivia_Hinted = true;

		char hint[128];
		Trivia_HintText(g_iTrivia_Cur, hint, sizeof(hint));
		CPrintToChatAll("%s Hint: {olive}%s", THIS_MODE_INFO.tag, hint);
	}

	int left = RoundToCeil(g_fTrivia_Ends - now);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!Trivia_Plays(i) || g_bTrivia_Won[i])
			continue;

		SetHudTextParams(-1.0, HUD_Y_TRIVIA, 1.1, 64, 224, 160, 255, 0, 0.0, 0.0, 0.0);
		ShowModeHud(i, g_hTrivia_Hud, "%s\n(%d s - type the answer in chat)", g_sTrivia_Question[g_iTrivia_Cur], left);
	}
}

public Action Cmd_TriviaToggle(int client, int args)
{
	if (!g_bTrivia_Enabled)
	{
		CReplyToCommand(client, "%s Trivia is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Trivia_Reset();

	CPrintToChatAll("%s Trivia is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When a question pops up, {olive}type the answer in chat{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Trivia Settings */
public Action Cmd_TriviaSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_TriviaSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Ask a question now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("reload", "Reload the questions");
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_TriviaSettings(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				DisplayModeInfo(param1, g_iPreviousModeIndex[param1]);
		}

		case MenuAction_Select:
		{
			char info[16];
			menu.GetItem(param2, info, sizeof(info));

			if (strcmp(info, "now") == 0)
			{
				Trivia_Ask(param1);
				Cmd_TriviaSettings(param1, 0);
			}
			else if (strcmp(info, "reload") == 0)
			{
				CPrintToChat(param1, "%s Loaded {olive}%d {lightgreen}questions.", THIS_MODE_INFO.tag, Trivia_Load());
				Cmd_TriviaSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
