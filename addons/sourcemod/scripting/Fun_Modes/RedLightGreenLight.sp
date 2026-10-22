/*
    (). FunModes V2:

    @file           RLGL.sp
    @Usage          Functions for the RedLightGreenLight Mode.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_RLGL

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "RLGL"

static int g_iRLGLIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iRLGLIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

bool g_bEnableDetecting;
float g_fRLGLRedSince;

/* Walking, strafing or jumping counts as moving (keys, not speed, so elevators and moving platforms don't count) */
#define RLGL_MOVE_KEYS (IN_FORWARD | IN_BACK | IN_MOVELEFT | IN_MOVERIGHT | IN_JUMP)

char countDownPath[PLATFORM_MAX_PATH];

float g_fOriginalSpeed[MAXPLAYERS + 1];

/* Timers */
Handle g_hRLGLTimer;
Handle g_hRLGLDetectTimer;
Handle g_hRLGLWarningTimer;

#define RLGL_CONVAR_TIME_BETWEEN_DAMAGE         0
#define RLGL_CONVAR_FREEZE_TIME                 1
#define RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MIN  2
#define RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MAX  3
#define RLGL_CONVAR_DAMAGE                      4
#define RLGL_CONVAR_WARNING_TIME                5
#define RLGL_CONVAR_ZOMBIES_SPEED               6
#define RLGL_CONVAR_COUNTDOWN_FOLDER            7
#define RLGL_CONVAR_TOGGLE                      8
#define RLGL_CONVAR_GRACE                       9
#define RLGL_CONVAR_EVERYONE                    10

float g_fRLGL_TimeBetweenDamage;
float g_fRLGL_FreezeTime;
float g_fRLGL_RedMin;
float g_fRLGL_RedMax;
float g_fRLGL_Damage;
float g_fRLGL_WarningTime;
float g_fRLGL_ZombieSpeed;
bool g_bRLGL_Enabled;
float g_fRLGL_Grace;
bool g_bRLGL_Everyone;

public void OnPluginStart_RLGL()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_GAMES;

	RegAdminCmd("sm_fm_rlgl", Cmd_RLGLToggle, ADMFLAG_CONVARS, "Enable/Disable RedLightGreenLight mode.");
	RegAdminCmd("sm_rlgl_settings", Cmd_RLGLSettings, ADMFLAG_CONVARS, "Open RLGL Settings Menu");

	DECLARE_FM_CVAR(
		RLGL_CONVAR_TIME_BETWEEN_DAMAGE, "sm_rlgl_time_between_damage",
		"0.1", "The timer interval for player to detect their movement",
		("0.1,0.3,0.5,0.8"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_TIME_BETWEEN_DAMAGE].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_FREEZE_TIME, "sm_rlgl_freeze_time",
		"5.0", "How many seconds the movement detection should be disabled after",
		("2.0,5.0,10.0,15.0"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_FREEZE_TIME].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MIN, "sm_rlgl_time_between_redlights_min",
		"20.0", "After how many seconds to keep repeating the redlights (MIN VALUE)",
		("20.0,30.0,40.0,60.0"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MIN].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MAX, "sm_rlgl_time_between_redlights_max",
		"30.0", "After how many seconds to keep repeating the redlights (MAX VALUE, SET TO 0 to disable min/max)",
		("25.0,35.0,45.0,65.0"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MAX].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_DAMAGE, "sm_rlgl_damage",
		"5.0", "Damage to apply to the player that is moving while its a red light",
		("1.0,2.0,3.0,4.0,5.0"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_DAMAGE].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_WARNING_TIME, "sm_rlgl_warning_time",
		"8.0", "Time in seconds to warn the players before red light is on",
		("5.0,8.0,10.0,15.0,20.0"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_WARNING_TIME].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_ZOMBIES_SPEED, "sm_rlgl_zombies_speed",
		"0.5", "Zombies speed during red light if set to 0 then it is disabled",
		("0.0,0.2,0.5,0.8,1.5,2.0"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_ZOMBIES_SPEED].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_COUNTDOWN_FOLDER, "sm_rlgl_countdown_folder",
		"zr/countdown/$.mp3", "Countdown folder and the files that can be used for sound",
		"", CONVAR_STRING
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_COUNTDOWN_FOLDER].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_TOGGLE, "sm_rlgl_enable",
		"1", "Enable/Disable the RLGL Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_TOGGLE].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_GRACE, "sm_rlgl_grace",
		"0.6", "Seconds the players have to stop once the red light is on",
		("0.0,0.3,0.6,1.0"), CONVAR_FLOAT
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_GRACE].HookChange(RLGL_OnConVarChange);

	DECLARE_FM_CVAR(
		RLGL_CONVAR_EVERYONE, "sm_rlgl_everyone",
		"0", "The zombies have to stop moving on red light too",
		("0,1"), CONVAR_BOOL
	);
	THIS_MODE_INFO.cvars[RLGL_CONVAR_EVERYONE].HookChange(RLGL_OnConVarChange);

	THIS_MODE_INFO.enableIndex = RLGL_CONVAR_TOGGLE;
}

public void InitCvarsValues_RLGL()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_fRLGL_TimeBetweenDamage = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_TIME_BETWEEN_DAMAGE, Float);
	g_fRLGL_FreezeTime = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_FREEZE_TIME, Float);
	g_fRLGL_RedMin = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MIN, Float);
	g_fRLGL_RedMax = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MAX, Float);
	g_fRLGL_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_DAMAGE, Float);
	g_fRLGL_WarningTime = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_WARNING_TIME, Float);
	g_fRLGL_ZombieSpeed = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_ZOMBIES_SPEED, Float);
	g_bRLGL_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_TOGGLE, Bool);
	g_fRLGL_Grace = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_GRACE, Float);
	g_bRLGL_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_EVERYONE, Bool);

	countDownPath = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_COUNTDOWN_FOLDER, String);
}

void RLGL_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case RLGL_CONVAR_TIME_BETWEEN_DAMAGE:
			g_fRLGL_TimeBetweenDamage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_FREEZE_TIME:
			g_fRLGL_FreezeTime = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MIN:
			g_fRLGL_RedMin = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_TIME_BETWEEN_REDLIGHTS_MAX:
			g_fRLGL_RedMax = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_DAMAGE:
			g_fRLGL_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_WARNING_TIME:
			g_fRLGL_WarningTime = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_ZOMBIES_SPEED:
			g_fRLGL_ZombieSpeed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_COUNTDOWN_FOLDER:
			countDownPath = _FUNMODES_CVAR_GET_VALUE(modeIndex, RLGL_CONVAR_COUNTDOWN_FOLDER, String);

		case RLGL_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn)
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, val, THIS_MODE_INFO.index);

			g_bRLGL_Enabled = val;
		}

		case RLGL_CONVAR_GRACE:
			g_fRLGL_Grace = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case RLGL_CONVAR_EVERYONE:
			g_bRLGL_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
	}
}

public void OnMapStart_RLGL()
{
	countDownPath = _FUNMODES_CVAR_GET_VALUE(THIS_MODE_INFO.index, RLGL_CONVAR_COUNTDOWN_FOLDER, String);
	PrintToChatAll("countdown path: %s", countDownPath);
	for (int i = 1; i <= RoundToNearest(g_fRLGL_WarningTime); i++)
	{
		char sndPath[PLATFORM_MAX_PATH];
		strcopy(sndPath, sizeof(sndPath), countDownPath);

		char numStr[3];
		IntToString(i, numStr, sizeof(numStr));
		ReplaceString(sndPath, sizeof(sndPath), "$", numStr);

		PrecacheSound(sndPath);
		FormatEx(sndPath, sizeof(sndPath), "sound/%s", sndPath);
		AddFileToDownloadsTable(sndPath);
	}
}

public void OnMapEnd_RLGL()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);

	g_hRLGLTimer = null;
	g_hRLGLDetectTimer = null;
	g_hRLGLWarningTimer = null;
}

public void OnClientDisconnect_RLGL(int client)
{
	g_fOriginalSpeed[client] = 0.0;
}

public void ZR_OnClientInfected_RLGL(int client)
{
	if (!(THIS_MODE_INFO.isOn && g_bEnableDetecting))
		return;

	if (g_fRLGL_ZombieSpeed <= 0.0)
		return;

	g_fOriginalSpeed[client] = GetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue");
	SetEntPropFloat(client, Prop_Data, "m_flLaggedMovementValue", g_fRLGL_ZombieSpeed);
}

public void Event_RoundStart_RLGL()
{
	delete g_hRLGLWarningTimer;
	delete g_hRLGLTimer;
	delete g_hRLGLDetectTimer;

	if (THIS_MODE_INFO.isOn)
		StartRLGLTimer();
}

void ApplyFade(const char[] sColor)
{
	int color[4];
	if (strcmp(sColor, "Red", false) == 0)
	{
		color[0] = 255;
		color[1] = 0;
	}
	else
	{
		color[0] = 124;
		color[1] = 252;
	}

	color[2] = 0;
	color[3] = 20;

	int count = 0;
	int allHumans[MAXPLAYERS + 1];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		allHumans[count] = i;
		count++;
	}

	if (count == 0)
		return;

	int flags = (FFADE_OUT);

	Handle message = StartMessage("Fade", allHumans, count, 1);
	if (GetUserMessageType() == UM_Protobuf)
	{
		Protobuf pb = UserMessageToProtobuf(message);
		pb.SetInt("duration", 500);
		pb.SetInt("hold_time", 500);
		pb.SetInt("flags", flags);
		pb.SetColor("clr", color);
	}
	else
	{
		BfWrite bf = UserMessageToBfWrite(message);
		bf.WriteShort(500);
		bf.WriteShort(500);
		bf.WriteShort(flags);
		bf.WriteByte(color[0]);
		bf.WriteByte(color[1]);
		bf.WriteByte(color[2]);
		bf.WriteByte(color[3]);
	}

	EndMessage();
}

public Action Cmd_RLGLToggle(int client, int args)
{
	#pragma unused args

	if (!g_bRLGL_Enabled)
	{
		CReplyToCommand(client, "%s RLGL mode is currently disabled!", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	CPrintToChatAll("%s Red Light Green Light is now {olive}%s{lightgreen}.", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "Enabled" : "Disabled");

	delete g_hRLGLTimer;
	delete g_hRLGLDetectTimer;
	delete g_hRLGLWarningTimer;

	if (THIS_MODE_INFO.isOn)
	{
		FunModes_HookEvent(g_bEvent_RoundStart, "round_start", Event_RoundStart);
		StartRLGLTimer();
	}
	else
	{
		g_bEnableDetecting = false;
		SetZombiesSpeed(1.0);
	}

	return Plugin_Handled;
}

Action RLGL_Timer(Handle timer)
{
	g_hRLGLTimer = null;

	if (!THIS_MODE_INFO.isOn)
		return Plugin_Stop;

	delete g_hRLGLWarningTimer;
	g_hRLGLWarningTimer = CreateTimer(1.0, RLGL_Warning_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

	StartRLGLTimer();

	return Plugin_Stop;
}

Action RLGL_Warning_Timer(Handle timer)
{
	if (!THIS_MODE_INFO.isOn)
	{
		g_hRLGLWarningTimer = null;
		return Plugin_Stop;
	}

	static int timePassed;

	char sMessage[256];
	FormatEx(sMessage, sizeof(sMessage), "Warning: Red Light is coming in %d seconds, Do not move after that", (RoundToNearest(g_fRLGL_WarningTime) - timePassed));

	char numStr[3];
	IntToString(RoundToNearest(g_fRLGL_WarningTime) - timePassed, numStr, sizeof(numStr));

	char sndPath[PLATFORM_MAX_PATH];
	strcopy(sndPath, sizeof(sndPath), countDownPath);
	ReplaceString(sndPath, sizeof(sndPath), "$", numStr);

	char sndPath2[PLATFORM_MAX_PATH];
	FormatEx(sndPath2, sizeof(sndPath2), "sound/%s", sndPath);
	bool playSnd = FileExists(sndPath2);
	sndPath2[0] = '\0';

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		SendHudText(i, sMessage, _, 0);
		if (playSnd)
			EmitSoundToClient(i, sndPath);
	}

	timePassed++;

	if (timePassed > RoundToNearest(g_fRLGL_WarningTime))
	{
		ApplyFade("Red");
		g_bEnableDetecting = true;
		g_fRLGLRedSince = GetGameTime();

		if (g_fRLGL_ZombieSpeed > 0.0)
			SetZombiesSpeed(g_fRLGL_ZombieSpeed);

		CreateTimer(g_fRLGL_FreezeTime, RLGL_Detect_Time_Timer, _, TIMER_FLAG_NO_MAPCHANGE);

		timePassed = 0;
		g_hRLGLWarningTimer = null;

		delete g_hRLGLDetectTimer;
		g_hRLGLDetectTimer = CreateTimer(g_fRLGL_TimeBetweenDamage, RLGL_Detect_Timer, _, TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);

		return Plugin_Stop;
	}

	return Plugin_Continue;
}

Action RLGL_Detect_Timer(Handle timer)
{
	if (!THIS_MODE_INFO.isOn || !g_bEnableDetecting)
	{
		g_hRLGLDetectTimer = null;
		return Plugin_Stop;
	}

	// A moment to react when it turns red
	if (GetGameTime() < g_fRLGLRedSince + g_fRLGL_Grace)
		return Plugin_Continue;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		if (GetClientTeam(i) != CS_TEAM_CT && !(g_bRLGL_Everyone && GetClientTeam(i) == CS_TEAM_T))
			continue;

		MoveType moveType = GetEntityMoveType(i);
		if (moveType == MOVETYPE_NOCLIP || moveType == MOVETYPE_NONE)
			continue;

		int buttons = GetClientButtons(i);
		if (buttons & RLGL_MOVE_KEYS)
		{
			SDKHooks_TakeDamage(i, 0, 0, g_fRLGL_Damage);
			SendHudText(i, "STOP MOVING ITS A RED LIGHT!!!", _, 1);
		}
	}

	return Plugin_Continue;
}

Action RLGL_Detect_Time_Timer(Handle timer)
{
	if (!THIS_MODE_INFO.isOn)
		return Plugin_Stop;

	ApplyFade("Green");
	g_bEnableDetecting = false;
	SetZombiesSpeed(1.0);

	delete g_hRLGLDetectTimer;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_CT)
			continue;

		SendHudText(i, "YOU CAN MOVE NOW, ITS A GREEN LIGHT!", _, 2);
	}

	return Plugin_Continue;
}

public void SetZombiesSpeed(float val)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || !IsPlayerAlive(i) || GetClientTeam(i) != CS_TEAM_T)
			continue;

		g_fOriginalSpeed[i] = (val == 1.0) ? 0.0 : GetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue");
		float thisVal = (val == 1.0) ? g_fOriginalSpeed[i] : val;

		if (thisVal == 0.0)
			thisVal = 1.0;

		SetEntPropFloat(i, Prop_Data, "m_flLaggedMovementValue", thisVal);
		CPrintToChat(i, "%s Your speed has been changed to {olive}%.2f", THIS_MODE_INFO.tag, thisVal);
		CPrintToChat(i, "%s This is a part of {olive}Red Light Green Light.{white} An admin decided to have this kicker.", THIS_MODE_INFO.tag);
	}
}

public void StartRLGLTimer()
{
	float time = 10.0;

	if (g_fRLGL_RedMax <= 0.0)
		time = g_fRLGL_RedMin;
	else
		time = GetRandomFloat(g_fRLGL_RedMin, g_fRLGL_RedMax);

	g_hRLGLTimer = CreateTimer(time, RLGL_Timer, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Cmd_RLGLSettings(int client, int args)
{
	#pragma unused args

	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_RLGLSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem(NULL_STRING, "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
	return Plugin_Handled;
}

int Menu_RLGLSettings(Menu menu, MenuAction action, int param1, int param2)
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
			ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
