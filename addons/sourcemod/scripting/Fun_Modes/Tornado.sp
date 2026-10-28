/*
    (). FunModes V2:

    @file           Tornado.sp
    @Usage          Functions for the Tornado mode.
                    Once the zombies are out, every few seconds a tornado forms near a human and wanders after
                    the humans for a while, pulling in, spinning and lifting whoever gets too close.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Tornado

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Tornado"

static int g_iTornadoIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iTornadoIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define TORNADO_CONVAR_EVERY    0
#define TORNADO_CONVAR_LAST     1
#define TORNADO_CONVAR_RADIUS   2
#define TORNADO_CONVAR_POWER    3
#define TORNADO_CONVAR_SPEED    4
#define TORNADO_CONVAR_EVERYONE 5
#define TORNADO_CONVAR_TOGGLE   6

int g_iTornado_Every;
int g_iTornado_Last;
float g_fTornado_Radius;
int g_iTornado_Power;
float g_fTornado_Speed;
bool g_bTornado_Everyone;
bool g_bTornado_Enabled;

public void OnPluginStart_Tornado()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_tornado", Cmd_TornadoToggle, ADMFLAG_CONVARS, "Turn Tornado On/Off");
	RegAdminCmd("sm_tornado_settings", Cmd_TornadoSettings, ADMFLAG_CONVARS, "Open Tornado Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		TORNADO_CONVAR_EVERY, "sm_tornado_every",
		"60", "Seconds between two tornadoes",
		("30,45,60,90,120"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		TORNADO_CONVAR_LAST, "sm_tornado_last",
		"15", "Seconds a tornado lasts",
		("10,15,20,30"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		TORNADO_CONVAR_RADIUS, "sm_tornado_radius",
		"300.0", "Radius the tornado pulls in",
		("200.0,300.0,400.0,600.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		TORNADO_CONVAR_POWER, "sm_tornado_power",
		"1", ("Tornado power [0 = gentle, 1 = strong, 2 = violent, 3 = F5]"),
		("0,1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		TORNADO_CONVAR_SPEED, "sm_tornado_speed",
		"160.0", "How fast the tornado wanders",
		("100.0,160.0,220.0"), CONVAR_FLOAT
	);

	DECLARE_FM_CVAR(
		TORNADO_CONVAR_EVERYONE, "sm_tornado_everyone",
		"1", "The tornado pulls the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		TORNADO_CONVAR_TOGGLE, "sm_tornado_enable",
		"1", "Enable/Disable Tornado Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= TORNADO_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Tornado_OnConVarChange);

	THIS_MODE_INFO.enableIndex = TORNADO_CONVAR_TOGGLE;
}

public void InitCvarsValues_Tornado()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iTornado_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, TORNADO_CONVAR_EVERY, Int);
	g_iTornado_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, TORNADO_CONVAR_LAST, Int);
	g_fTornado_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, TORNADO_CONVAR_RADIUS, Float);
	g_iTornado_Power = _FUNMODES_CVAR_GET_VALUE(modeIndex, TORNADO_CONVAR_POWER, Int);
	g_fTornado_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, TORNADO_CONVAR_SPEED, Float);
	g_bTornado_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, TORNADO_CONVAR_EVERYONE, Bool);
	g_bTornado_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, TORNADO_CONVAR_TOGGLE, Bool);
}

void Tornado_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case TORNADO_CONVAR_EVERY:
			g_iTornado_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case TORNADO_CONVAR_LAST:
			g_iTornado_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case TORNADO_CONVAR_RADIUS:
			g_fTornado_Radius = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case TORNADO_CONVAR_POWER:
			g_iTornado_Power = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case TORNADO_CONVAR_SPEED:
			g_fTornado_Speed = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

		case TORNADO_CONVAR_EVERYONE:
			g_bTornado_Everyone = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case TORNADO_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Tornado_Reset();
			}

			g_bTornado_Enabled = val;
		}
	}
}

public void OnMapEnd_Tornado()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Tornado_Reset();
}

float g_fTornado_Pull[] = { 25.0, 45.0, 70.0, 110.0 };     // per 0.2 s
int g_iTornado_Color[4] = { 176, 176, 160, 255 };

bool g_bTornado_Active;
float g_fTornado_Next;
float g_fTornado_Ends;
float g_fTornado_Pos[3];
int g_iTornado_Target;              // userid it's heading for
float g_fTornado_Retarget;

void Tornado_Reset()
{
	g_bTornado_Active = false;
	g_fTornado_Next = 0.0;
}

public void Event_RoundStart_Tornado()
{
	Tornado_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Tornadoes are on: if you see one, {olive}RUN {lightgreen}the other way!", THIS_MODE_INFO.tag);
}

void Tornado_Spawn()
{
	int list[MAXPLAYERS + 1];
	if (!GetShuffledHumans(list))
		return;

	GetClientAbsOrigin(list[0], g_fTornado_Pos);
	float angle = GetRandomFloat(0.0, 6.2832);
	g_fTornado_Pos[0] += Cosine(angle) * 400.0;
	g_fTornado_Pos[1] += Sine(angle) * 400.0;

	g_iTornado_Target = GetClientUserId(list[0]);
	g_fTornado_Retarget = GetGameTime() + 3.0;
	g_fTornado_Ends = GetGameTime() + float(g_iTornado_Last);
	g_bTornado_Active = true;

	CPrintToChatAll("%s A {olive}TORNADO {lightgreen}is forming near {olive}%N{lightgreen}!", THIS_MODE_INFO.tag, list[0]);
	PrintCenterTextAll("TORNADO!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 45);
}

public void OnCheck_Tornado(bool zombiesNow)
{
	if (!g_bTornado_Active)
		return;

	float now = GetGameTime();
	if (now >= g_fTornado_Ends)
	{
		g_bTornado_Active = false;
		PrintCenterTextAll("The tornado is gone");
		return;
	}

	// Wander towards the target human (a new one every few seconds)
	int target = GetClientOfUserId(g_iTornado_Target);
	if (now >= g_fTornado_Retarget || !IsHumanAlive(target))
	{
		int list[MAXPLAYERS + 1];
		if (GetShuffledHumans(list))
			g_iTornado_Target = GetClientUserId(list[0]);

		g_fTornado_Retarget = now + 3.0;
		target = GetClientOfUserId(g_iTornado_Target);
	}

	if (IsHumanAlive(target))
	{
		float targetPos[3], dir[3];
		GetClientAbsOrigin(target, targetPos);
		MakeVectorFromPoints(g_fTornado_Pos, targetPos, dir);
		dir[2] = 0.0;

		float dist = GetVectorLength(dir);
		if (dist > 1.0)
		{
			NormalizeVector(dir, dir);
			float step = g_fTornado_Speed * 0.2 < dist ? g_fTornado_Speed * 0.2 : dist;
			g_fTornado_Pos[0] += dir[0] * step;
			g_fTornado_Pos[1] += dir[1] * step;
		}

		// Follow the ground the humans are on
		g_fTornado_Pos[2] = targetPos[2];
	}

	// The funnel: rings stacked up, wider at the top
	for (int h = 0; h < 5; h++)
	{
		float p[3];
		p = g_fTornado_Pos;
		p[2] += float(h) * 70.0;

		float r = g_fTornado_Radius * (0.15 + 0.2 * float(h));
		DrawRingAt(p, r, r * 0.8, 0.25, g_iTornado_Color, 14.0);
	}

	// Pull in, spin round, lift up
	int power = (g_iTornado_Power < 0 || g_iTornado_Power >= sizeof(g_fTornado_Pull)) ? 1 : g_iTornado_Power;
	float pull = g_fTornado_Pull[power];
	float pos[3], to[3];
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bTornado_Everyone))
			continue;

		GetClientAbsOrigin(i, pos);
		MakeVectorFromPoints(pos, g_fTornado_Pos, to);
		to[2] = 0.0;

		float dist = GetVectorLength(to);
		if (dist > g_fTornado_Radius)
			continue;

		if (dist > 1.0)
			NormalizeVector(to, to);

		float closeness = 1.0 - dist / g_fTornado_Radius;
		float lift = dist < g_fTornado_Radius * 0.4 ? pull * 1.2 : 0.0;
		ShovePlayer(i, to[0] * pull - to[1] * pull * closeness, to[1] * pull + to[0] * pull * closeness, lift);
	}
}

public void OnTick_Tornado()
{
	if (!g_bTornado_Active && HazardDue(g_fTornado_Next, g_iTornado_Every))
		Tornado_Spawn();
}

public Action Cmd_TornadoToggle(int client, int args)
{
	if (!g_bTornado_Enabled)
	{
		CReplyToCommand(client, "%s Tornado is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Tornado_Reset();

	CPrintToChatAll("%s Tornado is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s If you see one, {olive}RUN {lightgreen}the other way!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Tornado Settings */
public Action Cmd_TornadoSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_TornadoSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Tornado now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bTornado_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_TornadoSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Tornado_Spawn();
				Cmd_TornadoSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
