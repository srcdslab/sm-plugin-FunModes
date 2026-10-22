/*
    (). FunModes V2:

    @file           AcidRain.sp
    @Usage          Functions for the AcidRain mode.
                    Once the zombies are out, every few seconds it rains acid for a while:
                    whoever has nothing but sky above their head gets hurt, so get under a roof.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_AcidRain

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "AcidRain"

static int g_iAcidRainIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iAcidRainIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define ACID_CONVAR_EVERY   0
#define ACID_CONVAR_LAST    1
#define ACID_CONVAR_DAMAGE  2
#define ACID_CONVAR_ZOMBIES 3
#define ACID_CONVAR_TOGGLE  4

int g_iAcid_Every;
int g_iAcid_Last;
int g_iAcid_Damage;
bool g_bAcid_Zombies;
bool g_bAcidRain_Enabled;

public void OnPluginStart_AcidRain()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_WEATHER;

	/* COMMANDS */
	RegAdminCmd("sm_fm_acid", Cmd_AcidRainToggle, ADMFLAG_CONVARS, "Turn Acid Rain On/Off");
	RegAdminCmd("sm_acid_settings", Cmd_AcidRainSettings, ADMFLAG_CONVARS, "Open Acid Rain Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		ACID_CONVAR_EVERY, "sm_acid_every",
		"60", "Seconds between two acid rains",
		("30,45,60,90,120"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ACID_CONVAR_LAST, "sm_acid_last",
		"10", "Seconds an acid rain lasts",
		("5,10,15,20"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ACID_CONVAR_DAMAGE, "sm_acid_damage",
		"5", "Damage per second under the acid rain",
		("2,3,5,10,20"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		ACID_CONVAR_ZOMBIES, "sm_acid_zombies",
		"0", "The acid rain hurts the zombies too",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		ACID_CONVAR_TOGGLE, "sm_acid_enable",
		"1", "Enable/Disable Acid Rain Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= ACID_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(AcidRain_OnConVarChange);

	THIS_MODE_INFO.enableIndex = ACID_CONVAR_TOGGLE;

	AcidRain_OnPluginStart();
}

public void InitCvarsValues_AcidRain()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iAcid_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, ACID_CONVAR_EVERY, Int);
	g_iAcid_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, ACID_CONVAR_LAST, Int);
	g_iAcid_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, ACID_CONVAR_DAMAGE, Int);
	g_bAcid_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, ACID_CONVAR_ZOMBIES, Bool);
	g_bAcidRain_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, ACID_CONVAR_TOGGLE, Bool);
}

void AcidRain_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case ACID_CONVAR_EVERY:
			g_iAcid_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ACID_CONVAR_LAST:
			g_iAcid_Last = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ACID_CONVAR_DAMAGE:
			g_iAcid_Damage = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case ACID_CONVAR_ZOMBIES:
			g_bAcid_Zombies = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case ACID_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				AcidRain_Reset();
			}

			g_bAcidRain_Enabled = val;
		}
	}
}

public void OnMapEnd_AcidRain()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	AcidRain_Reset();
}

#define ACID_SURF_SKY (0x0002 | 0x0004)     // SURF_SKY2D | SURF_SKY

bool g_bAcid_Active;
float g_fAcid_Next;
float g_fAcid_Ends;
Handle g_hAcid_Hud;

void AcidRain_OnPluginStart()
{
	g_hAcid_Hud = CreateModeHud();
}

void AcidRain_Reset()
{
	g_bAcid_Active = false;
	g_fAcid_Next = 0.0;
}

public void Event_RoundStart_AcidRain()
{
	AcidRain_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Acid Rain is on: when it rains, get {olive}under a roof{lightgreen}!", THIS_MODE_INFO.tag);
}

bool AcidRain_IgnorePlayers(int entity, int mask)
{
	return entity > MaxClients;
}

/* True if nothing but sky (or nothing at all) is straight above the player's head */
bool AcidRain_Exposed(int client)
{
	float eye[3], up[3];
	GetClientEyePosition(client, eye);
	up = eye;
	up[2] += 8192.0;

	TR_TraceRayFilter(eye, up, MASK_SOLID_BRUSHONLY, RayType_EndPoint, AcidRain_IgnorePlayers);
	if (!TR_DidHit())
		return true;

	return (TR_GetSurfaceFlags() & ACID_SURF_SKY) != 0;
}

void AcidRain_Start()
{
	g_bAcid_Active = true;
	g_fAcid_Ends = GetGameTime() + float(g_iAcid_Last);

	CPrintToChatAll("%s {olive}ACID RAIN {lightgreen}for {olive}%d {lightgreen}seconds - get under cover!", THIS_MODE_INFO.tag, g_iAcid_Last);
	PrintCenterTextAll("ACID RAIN! GET UNDER COVER!");
	EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 65);
}

public void OnTick_AcidRain()
{
	if (!g_bAcid_Active)
	{
		if (HazardDue(g_fAcid_Next, g_iAcid_Every))
			AcidRain_Start();

		return;
	}

	if (GetGameTime() >= g_fAcid_Ends)
	{
		g_bAcid_Active = false;
		CPrintToChatAll("%s The acid rain has stopped.", THIS_MODE_INFO.tag);
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!HazardHits(i, g_bAcid_Zombies))
			continue;

		bool exposed = AcidRain_Exposed(i);
		if (!IsFakeClient(i))
		{
			SetHudTextParams(-1.0, 0.48, 1.1, exposed ? 160 : 120, 255, exposed ? 96 : 200, 255, 0, 0.0, 0.0, 0.0);
			if (exposed)
			{
				ShowModeHud(i, g_hAcid_Hud, "ACID RAIN - GET UNDER COVER! (-%d HP/s)", g_iAcid_Damage);
				ScreenTint(i, 120, 255, 60, 50, 0.3, 0.6);
			}
			else
				ShowModeHud(i, g_hAcid_Hud, "Acid rain - you're under cover");
		}

		if (exposed)
			HurtPlayer(i, g_iAcid_Damage);
	}
}

public Action Cmd_AcidRainToggle(int client, int args)
{
	if (!g_bAcidRain_Enabled)
	{
		CReplyToCommand(client, "%s Acid Rain is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	AcidRain_Reset();

	CPrintToChatAll("%s Acid Rain is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s When it rains, get {olive}under a roof{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* AcidRain Settings */
public Action Cmd_AcidRainSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_AcidRainSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Make it rain now", (THIS_MODE_INFO.isOn && g_bRoundLive && !g_bAcid_Active) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_AcidRainSettings(Menu menu, MenuAction action, int param1, int param2)
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
				AcidRain_Start();
				Cmd_AcidRainSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
