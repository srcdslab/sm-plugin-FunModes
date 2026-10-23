/*
    (). FunModes V2:

    @file           HotSeat.sp
    @Usage          Functions for the HotSeat mode.
                    Every so often a few players get a TRUE / FALSE menu (a statement from
                    configs/FunModes/HotSeat.cfg or a quick sum) and must answer in time: right earns health,
                    wrong or no answer costs health.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_HotSeat

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "HotSeat"

static int g_iHotSeatIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iHotSeatIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define HOTSEAT_CONVAR_EVERY   0
#define HOTSEAT_CONVAR_TIME    1
#define HOTSEAT_CONVAR_SOURCE  2
#define HOTSEAT_CONVAR_PENALTY 3
#define HOTSEAT_CONVAR_REWARD  4
#define HOTSEAT_CONVAR_PLAYERS 5
#define HOTSEAT_CONVAR_HUMANS  6
#define HOTSEAT_CONVAR_TOGGLE  7

int g_iHotSeat_Every;
int g_iHotSeat_Time;
int g_iHotSeat_Source;
int g_iHotSeat_Penalty;
int g_iHotSeat_Reward;
int g_iHotSeat_Players;
bool g_bHotSeat_HumansOnly;
bool g_bHotSeat_Enabled;

public void OnPluginStart_HotSeat()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_GAMES;

	/* COMMANDS */
	RegAdminCmd("sm_fm_hotseat", Cmd_HotSeatToggle, ADMFLAG_CONVARS, "Turn Hot Seat On/Off");
	RegAdminCmd("sm_hotseat_settings", Cmd_HotSeatSettings, ADMFLAG_CONVARS, "Open Hot Seat Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_EVERY, "sm_hotseat_every",
		"45", "Seconds between two hot seats",
		("20,30,45,60,90,120"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_TIME, "sm_hotseat_time",
		"8", "Seconds to answer",
		("5,8,10,15"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_SOURCE, "sm_hotseat_source",
		"2", ("Questions [0 = statements file, 1 = quick sums, 2 = mix of both]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_PENALTY, "sm_hotseat_penalty",
		"25", "Damage for a wrong or missing answer (1000 = slay)",
		("10,25,50,1000"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_REWARD, "sm_hotseat_reward",
		"1", ("Reward for a right answer [0 = nothing, 1 = +25 HP, 2 = +50 HP]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_PLAYERS, "sm_hotseat_players",
		"1", "Players in the hot seat at once",
		("1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_HUMANS, "sm_hotseat_humans_only",
		"1", "Only the living humans are put in the hot seat",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		HOTSEAT_CONVAR_TOGGLE, "sm_hotseat_enable",
		"1", "Enable/Disable Hot Seat Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= HOTSEAT_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(HotSeat_OnConVarChange);

	THIS_MODE_INFO.enableIndex = HOTSEAT_CONVAR_TOGGLE;
}

public void InitCvarsValues_HotSeat()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iHotSeat_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_EVERY, Int);
	g_iHotSeat_Time = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_TIME, Int);
	g_iHotSeat_Source = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_SOURCE, Int);
	g_iHotSeat_Penalty = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_PENALTY, Int);
	g_iHotSeat_Reward = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_REWARD, Int);
	g_iHotSeat_Players = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_PLAYERS, Int);
	g_bHotSeat_HumansOnly = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_HUMANS, Bool);
	g_bHotSeat_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, HOTSEAT_CONVAR_TOGGLE, Bool);
}

void HotSeat_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case HOTSEAT_CONVAR_EVERY:
			g_iHotSeat_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HOTSEAT_CONVAR_TIME:
			g_iHotSeat_Time = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HOTSEAT_CONVAR_SOURCE:
			g_iHotSeat_Source = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HOTSEAT_CONVAR_PENALTY:
			g_iHotSeat_Penalty = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HOTSEAT_CONVAR_REWARD:
			g_iHotSeat_Reward = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HOTSEAT_CONVAR_PLAYERS:
			g_iHotSeat_Players = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HOTSEAT_CONVAR_HUMANS:
			g_bHotSeat_HumansOnly = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case HOTSEAT_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				HotSeat_Reset();
			}

			g_bHotSeat_Enabled = val;
		}
	}
}

public void OnMapEnd_HotSeat()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	HotSeat_Reset();
}

#define HOTSEAT_CONFIG "configs/FunModes/HotSeat.cfg"
#define HOTSEAT_MAX    500

#define HOTSEAT_SRC_FILE 0
#define HOTSEAT_SRC_MATH 1
#define HOTSEAT_SRC_MIX  2

char g_sHotSeat_Statement[HOTSEAT_MAX][160];
bool g_bHotSeat_True[HOTSEAT_MAX];
int g_iHotSeat_Count;

float g_fHotSeat_Next;
bool g_bHotSeat_Pending[MAXPLAYERS + 1];
char g_sHotSeat_Text[MAXPLAYERS + 1][160];
bool g_bHotSeat_Answer[MAXPLAYERS + 1];

public void OnMapStart_HotSeat()
{
	HotSeat_Load();
}

int HotSeat_Load()
{
	g_iHotSeat_Count = 0;

	char path[PLATFORM_MAX_PATH], truth[16];
	BuildPath(Path_SM, path, sizeof(path), HOTSEAT_CONFIG);

	KeyValues kv = new KeyValues("HotSeat");
	if (!FunModes_LoadKV(kv, path))
		LogError("[FunModes-HotSeat] %s", g_sKvError);
	else if (kv.GotoFirstSubKey())
	{
		do
		{
			if (g_iHotSeat_Count >= HOTSEAT_MAX)
				break;

			kv.GetString("statement", g_sHotSeat_Statement[g_iHotSeat_Count], sizeof(g_sHotSeat_Statement[]), "");
			kv.GetString("answer", truth, sizeof(truth), "");
			if (!g_sHotSeat_Statement[g_iHotSeat_Count][0])
				continue;

			g_bHotSeat_True[g_iHotSeat_Count] = truth[0] == 't' || truth[0] == 'T' || truth[0] == 'y' || truth[0] == 'Y' || truth[0] == '1';
			g_iHotSeat_Count++;
		} while (kv.GotoNextKey());
	}

	delete kv;
	return g_iHotSeat_Count;
}

void HotSeat_Reset()
{
	g_fHotSeat_Next = 0.0;
	for (int i = 1; i <= MaxClients; i++)
		g_bHotSeat_Pending[i] = false;
}

public void Event_RoundStart_HotSeat()
{
	HotSeat_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Hot Seat is on: if a {olive}TRUE / FALSE {lightgreen}menu pops up, answer fast!", THIS_MODE_INFO.tag);
}

/* A sum that's right half the time: "7 x 8 = 56" (true) or "7 x 8 = 54" (false) */
void HotSeat_MakeSum(char[] text, int maxlen, bool &truth)
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
		shown = real + GetRandomInt(1, 3) * (GetRandomInt(0, 1) == 1 ? 1 : -1);

	FormatEx(text, maxlen, "%d %s %d = %d", a, op, b, shown);
}

void HotSeat_Pick(int client)
{
	bool useFile = g_iHotSeat_Count > 0 && (g_iHotSeat_Source == HOTSEAT_SRC_FILE || (g_iHotSeat_Source == HOTSEAT_SRC_MIX && GetRandomInt(0, 1) == 1));
	if (useFile)
	{
		int question = GetRandomInt(0, g_iHotSeat_Count - 1);
		strcopy(g_sHotSeat_Text[client], sizeof(g_sHotSeat_Text[]), g_sHotSeat_Statement[question]);
		g_bHotSeat_Answer[client] = g_bHotSeat_True[question];
	}
	else
		HotSeat_MakeSum(g_sHotSeat_Text[client], sizeof(g_sHotSeat_Text[]), g_bHotSeat_Answer[client]);
}

bool HotSeat_Eligible(int client)
{
	if (!IsClientInGame(client) || IsFakeClient(client) || !IsPlayerAlive(client) || g_bHotSeat_Pending[client])
		return false;

	return !g_bHotSeat_HumansOnly || ZR_IsClientHuman(client);
}

void HotSeat_Ask()
{
	int list[MAXPLAYERS + 1], count;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (HotSeat_Eligible(i))
			list[count++] = i;
	}

	for (int i = count - 1; i > 0; i--)
	{
		int j = GetRandomInt(0, i), tmp = list[i];
		list[i] = list[j];
		list[j] = tmp;
	}

	int picked = g_iHotSeat_Players < count ? g_iHotSeat_Players : count;
	for (int i = 0; i < picked; i++)
	{
		int client = list[i];
		HotSeat_Pick(client);
		g_bHotSeat_Pending[client] = true;

		Menu menu = new Menu(Menu_HotSeatQuestion);
		menu.SetTitle("HOT SEAT! (%d s)\n \n%s\n ", g_iHotSeat_Time, g_sHotSeat_Text[client]);
		menu.AddItem("t", "TRUE");
		menu.AddItem("f", "FALSE");
		menu.ExitButton = false;
		menu.Display(client, g_iHotSeat_Time);

		CPrintToChatAll("%s {olive}%N {lightgreen}is in the {olive}HOT SEAT{lightgreen}: \"%s\" TRUE or FALSE?", THIS_MODE_INFO.tag, client, g_sHotSeat_Text[client]);
	}

	if (picked)
		EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 90);
}

/* said: 1 true, 0 false, -1 no answer */
void HotSeat_Result(int client, int said)
{
	if (!g_bHotSeat_Pending[client])
		return;

	g_bHotSeat_Pending[client] = false;

	bool right = said != -1 && (said == 1) == g_bHotSeat_Answer[client];
	char answer[8];
	strcopy(answer, sizeof(answer), g_bHotSeat_Answer[client] ? "TRUE" : "FALSE");

	if (right)
	{
		int heal = g_iHotSeat_Reward == 1 ? 25 : (g_iHotSeat_Reward == 2 ? 50 : 0);
		if (heal > 0 && IsPlayerAlive(client))
			SetEntityHealth(client, GetClientHealth(client) + heal);

		if (heal > 0)
			CPrintToChatAll("%s {olive}%N {lightgreen}said %s - {olive}RIGHT! {lightgreen}(+%d HP)", THIS_MODE_INFO.tag, client, answer, heal);
		else
			CPrintToChatAll("%s {olive}%N {lightgreen}said %s - {olive}RIGHT!", THIS_MODE_INFO.tag, client, answer);

		return;
	}

	if (said == -1)
		CPrintToChatAll("%s {olive}%N {lightgreen}didn't answer in time! It was {olive}%s{lightgreen}.", THIS_MODE_INFO.tag, client, answer);
	else
		CPrintToChatAll("%s {olive}%N {lightgreen}said %s - {red}WRONG!", THIS_MODE_INFO.tag, client, said == 1 ? "TRUE" : "FALSE");

	if (IsPlayerAlive(client))
		HurtPlayer(client, g_iHotSeat_Penalty);
}

int Menu_HotSeatQuestion(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Select:
		{
			char info[4];
			menu.GetItem(param2, info, sizeof(info));
			HotSeat_Result(param1, info[0] == 't' ? 1 : 0);
		}

		// Ran out of time, or another menu replaced it
		case MenuAction_Cancel:
		{
			if (param1 > 0 && param1 <= MaxClients && IsClientInGame(param1))
				HotSeat_Result(param1, -1);
		}
	}

	return 0;
}

public void OnTick_HotSeat()
{
	float now = GetGameTime();
	if (g_fHotSeat_Next == 0.0)
		g_fHotSeat_Next = now + 20.0;

	if (now >= g_fHotSeat_Next)
	{
		HotSeat_Ask();
		g_fHotSeat_Next = now + float(g_iHotSeat_Every);
	}
}

public Action Cmd_HotSeatToggle(int client, int args)
{
	if (!g_bHotSeat_Enabled)
	{
		CReplyToCommand(client, "%s Hot Seat is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	HotSeat_Reset();

	CPrintToChatAll("%s Hot Seat is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s If a {olive}TRUE / FALSE {lightgreen}menu pops up, answer fast!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* HotSeat Settings */
public Action Cmd_HotSeatSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_HotSeatSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Put someone in the hot seat now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("reload", "Reload the statements");
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_HotSeatSettings(Menu menu, MenuAction action, int param1, int param2)
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
				HotSeat_Ask();
			}
			else if (strcmp(info, "reload") == 0)
			{
				CPrintToChat(param1, "%s Loaded {olive}%d {lightgreen}statements.", THIS_MODE_INFO.tag, HotSeat_Load());
				Cmd_HotSeatSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
