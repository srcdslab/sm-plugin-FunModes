/*
    (). FunModes V2:

    @file           GhostZombies.sp
    @Usage          Functions for the GhostZombies mode.
                    The zombies are see-through, flicker in and out of sight, or both.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_GhostZombies

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "GhostZombies"

static int g_iGhostZombiesIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iGhostZombiesIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define GHOST_CONVAR_STYLE   0
#define GHOST_CONVAR_ALPHA   1
#define GHOST_CONVAR_FLICKER 2
#define GHOST_CONVAR_TOGGLE  3

int g_iGhost_Style;
int g_iGhost_Alpha;
int g_iGhost_Flicker;
bool g_bGhostZombies_Enabled;

public void OnPluginStart_GhostZombies()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_ZOMBIES;

	/* COMMANDS */
	RegAdminCmd("sm_fm_ghost", Cmd_GhostZombiesToggle, ADMFLAG_CONVARS, "Turn Ghost Zombies On/Off");
	RegAdminCmd("sm_ghost_settings", Cmd_GhostZombiesSettings, ADMFLAG_CONVARS, "Open Ghost Zombies Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		GHOST_CONVAR_STYLE, "sm_ghost_style",
		"0", ("Ghost style [0 = see-through, 1 = flickering, 2 = see-through + flickering]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GHOST_CONVAR_ALPHA, "sm_ghost_alpha",
		"70", ("How visible the see-through zombies are (0 = invisible, 255 = solid)"),
		("15,40,70,100,150"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GHOST_CONVAR_FLICKER, "sm_ghost_flicker",
		"1", ("Flicker speed [0 = slow, 1 = normal, 2 = fast]"),
		("0,1,2"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		GHOST_CONVAR_TOGGLE, "sm_ghost_enable",
		"1", "Enable/Disable Ghost Zombies Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= GHOST_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(GhostZombies_OnConVarChange);

	THIS_MODE_INFO.enableIndex = GHOST_CONVAR_TOGGLE;
}

public void InitCvarsValues_GhostZombies()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iGhost_Style = _FUNMODES_CVAR_GET_VALUE(modeIndex, GHOST_CONVAR_STYLE, Int);
	g_iGhost_Alpha = _FUNMODES_CVAR_GET_VALUE(modeIndex, GHOST_CONVAR_ALPHA, Int);
	g_iGhost_Flicker = _FUNMODES_CVAR_GET_VALUE(modeIndex, GHOST_CONVAR_FLICKER, Int);
	g_bGhostZombies_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, GHOST_CONVAR_TOGGLE, Bool);
}

void GhostZombies_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case GHOST_CONVAR_STYLE:
			g_iGhost_Style = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GHOST_CONVAR_ALPHA:
			g_iGhost_Alpha = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GHOST_CONVAR_FLICKER:
			g_iGhost_Flicker = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case GHOST_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				GhostZombies_Reset();
			}

			g_bGhostZombies_Enabled = val;
		}
	}
}

public void OnMapEnd_GhostZombies()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	GhostZombies_Reset();
}

#define GHOST_SEETHROUGH 0
#define GHOST_FLICKER    1

int g_iGhost_FlickerChance[] = { 4, 10, 20 };       // % chance per 0.2 s to flip visible/hidden

bool g_bGhost_Hidden[MAXPLAYERS + 1];
bool g_bGhost_Touched[MAXPLAYERS + 1];  // we changed how they're drawn

void GhostZombies_SetAlpha(int entity, int alpha)
{
	int r, g, b, a;
	GetEntityRenderColor(entity, r, g, b, a);
	SetEntityRenderMode(entity, alpha >= 255 ? RENDER_NORMAL : RENDER_TRANSALPHA);
	if (a != alpha)
		SetEntityRenderColor(entity, r, g, b, alpha);
}

void GhostZombies_Apply(int client, int alpha)
{
	GhostZombies_SetAlpha(client, alpha);
	for (int slot = 0; slot <= 4; slot++)
	{
		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon != -1)
			GhostZombies_SetAlpha(weapon, alpha);
	}

	g_bGhost_Touched[client] = alpha < 255;
}

void GhostZombies_Restore(int client)
{
	if (g_bGhost_Touched[client] && IsClientInGame(client))
		GhostZombies_Apply(client, 255);

	g_bGhost_Touched[client] = false;
	g_bGhost_Hidden[client] = false;
}

void GhostZombies_Reset()
{
	for (int i = 1; i <= MaxClients; i++)
		GhostZombies_Restore(i);
}

public void Event_RoundEnd_GhostZombies()
{
	GhostZombies_Reset();
}

public void OnCheck_GhostZombies(bool zombiesNow)
{
	bool seeThrough = g_iGhost_Style != GHOST_FLICKER;
	bool flicker = g_iGhost_Style != GHOST_SEETHROUGH;
	int chance = g_iGhost_FlickerChance[(g_iGhost_Flicker < 0 || g_iGhost_Flicker >= sizeof(g_iGhost_FlickerChance)) ? 1 : g_iGhost_Flicker];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
			continue;

		// Died or was cured: back to normal
		if (!IsPlayerAlive(i) || !ZR_IsClientZombie(i))
		{
			GhostZombies_Restore(i);
			continue;
		}

		if (flicker && GetRandomInt(1, 100) <= chance)
			g_bGhost_Hidden[i] = !g_bGhost_Hidden[i];

		int alpha = seeThrough ? g_iGhost_Alpha : 255;
		if (flicker && g_bGhost_Hidden[i])
			alpha = 0;

		GhostZombies_Apply(i, alpha);
	}
}

public Action Cmd_GhostZombiesToggle(int client, int args)
{
	if (!g_bGhostZombies_Enabled)
	{
		CReplyToCommand(client, "%s Ghost Zombies is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	GhostZombies_Reset();

	CPrintToChatAll("%s Ghost Zombies is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s The zombies are now {olive}ghosts{lightgreen}...", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* GhostZombies Settings */
public Action Cmd_GhostZombiesSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_GhostZombiesSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_GhostZombiesSettings(Menu menu, MenuAction action, int param1, int param2)
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
