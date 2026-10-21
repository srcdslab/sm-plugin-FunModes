/*
    (). FunModes V2:

    @file           IceFloor.sp
    @Usage          Functions for the IceFloor mode.
                    Once the zombies are out, every few seconds the floor freezes for a while:
                    sv_friction is lowered so everyone slides, then put back.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_IceFloor

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "IceFloor"

static int g_iIceFloorIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iIceFloorIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define ICE_CONVAR_EVERY  0
#define ICE_CONVAR_LAST   1
#define ICE_CONVAR_LEVEL  2
#define ICE_CONVAR_TOGGLE 3

int g_iIce_Every;
int g_iIce_Last;
int g_iIce_Level;
bool g_bIceFloor_Enabled;

public void OnPluginStart_IceFloor()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_ice", Cmd_IceFloorToggle, ADMFLAG_CONVARS, "Turn Ice Floor On/Off");
	RegAdminCmd("sm_ice_settings", Cmd_IceFloorSettings, ADMFLAG_CONVARS, "Open Ice Floor Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		ICE_CONVAR_EVERY, "sm_ice_every",
		"45", "Seconds between two frozen floors",
		("20,30,45,60,90"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ICE_CONVAR_LAST, "sm_ice_last",
		"10", "Seconds the floor stays frozen",
		("5,8,10,15,20"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ICE_CONVAR_LEVEL, "sm_ice_level",
		"1", ("How slippery [0 = slippery, 1 = very slippery, 2 = ice rink, 3 = pure ice]"),
		("0,1,2,3"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ICE_CONVAR_TOGGLE, "sm_ice_enable",
		"1", "Enable/Disable Ice Floor Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= ICE_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(IceFloor_OnConVarChange);

	THIS_MODE_INFO.enableIndex = ICE_CONVAR_TOGGLE;
}

public void InitCvarsValues_IceFloor()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iIce_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, ICE_CONVAR_EVERY, Int);
	g_iIce_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, ICE_CONVAR_LAST, Int);
	g_iIce_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, ICE_CONVAR_LEVEL, Int);
	g_bIceFloor_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, ICE_CONVAR_TOGGLE, Bool);
}

void IceFloor_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case ICE_CONVAR_EVERY:
			g_iIce_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ICE_CONVAR_LAST:
			g_iIce_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ICE_CONVAR_LEVEL:
			g_iIce_Level = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ICE_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				IceFloor_Reset();
			}

			g_bIceFloor_Enabled = val;
		}
	}
}

public void OnMapEnd_IceFloor()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	IceFloor_Reset();
}

float g_fIce_LevelFriction[] = { 2.0, 1.0, 0.5, 0.15 };    // normal sv_friction is 4

bool g_bIce_Active;
float g_fIce_Next;
float g_fIce_Ends;
bool g_bIce_Applied;                // we changed sv_friction
float g_fIce_OldFriction;

void IceFloor_SetFriction(float value)
{
	ConVar cvar = FindConVar("sv_friction");
	if (cvar == null)
		return;

	int flags = cvar.Flags;
	cvar.Flags = flags & ~FCVAR_NOTIFY;
	cvar.FloatValue = value;
	cvar.Flags = flags;
}

void IceFloor_Freeze(bool on)
{
	ConVar cvar = FindConVar("sv_friction");
	if (cvar == null)
		return;

	if (on)
	{
		if (!g_bIce_Applied)
			g_fIce_OldFriction = cvar.FloatValue;

		g_bIce_Applied = true;

		int level = g_iIce_Level;
		if (level < 0 || level >= sizeof(g_fIce_LevelFriction))
			level = 1;

		IceFloor_SetFriction(g_fIce_LevelFriction[level]);
	}
	else if (g_bIce_Applied)
	{
		IceFloor_SetFriction(g_fIce_OldFriction);
		g_bIce_Applied = false;
	}
}

void IceFloor_Reset()
{
	g_bIce_Active = false;
	g_fIce_Next = 0.0;
	IceFloor_Freeze(false);
}

public void OnPluginEnd_IceFloor()
{
	IceFloor_Freeze(false);
}

public void Event_RoundStart_IceFloor()
{
	IceFloor_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Ice Floor is on: sometimes the ground freezes - mind your step!", THIS_MODE_INFO.tag);
}

public void Event_RoundEnd_IceFloor()
{
	g_bIce_Active = false;
	IceFloor_Freeze(false);
}

void IceFloor_Start()
{
	g_bIce_Active = true;
	g_fIce_Ends = GetGameTime() + float(g_iIce_Last);
	IceFloor_Freeze(true);

	CPrintToChatAll("%s {olive}THE FLOOR IS FROZEN {lightgreen}for {olive}%d {lightgreen}seconds!", THIS_MODE_INFO.tag, g_iIce_Last);
	PrintCenterTextAll("THE FLOOR IS ICE!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 230);
}

public void OnTick_IceFloor()
{
	if (g_bIce_Active)
	{
		if (GetGameTime() >= g_fIce_Ends)
		{
			g_bIce_Active = false;
			IceFloor_Freeze(false);
			PrintCenterTextAll("The ice has melted");
		}

		return;
	}

	if (HazardDue(g_fIce_Next, g_iIce_Every))
		IceFloor_Start();
}

public Action Cmd_IceFloorToggle(int client, int args)
{
	if (!g_bIceFloor_Enabled)
	{
		CReplyToCommand(client, "%s Ice Floor is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	IceFloor_Reset();

	CPrintToChatAll("%s Ice Floor is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Sometimes the ground freezes - mind your step!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* IceFloor Settings */
public Action Cmd_IceFloorSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_IceFloorSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Freeze the floor now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bIce_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_IceFloorSettings(Menu menu, MenuAction action, int param1, int param2)
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
				IceFloor_Start();
				Cmd_IceFloorSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
