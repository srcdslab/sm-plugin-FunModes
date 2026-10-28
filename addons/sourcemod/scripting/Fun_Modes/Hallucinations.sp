/*
    (). FunModes V2:

    @file           Hallucinations.sp
    @Usage          Functions for the Hallucinations mode.
                    Once the zombies are out, every few seconds some humans see or hear things that aren't there:
                    a growl behind them, a colour flash, a lie on screen or a fake danger ring.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_Hallucinations

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "Hallucinations"

static int g_iHallucinationsIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iHallucinationsIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define HALLUC_CONVAR_EVERY   0
#define HALLUC_CONVAR_COUNT   1
#define HALLUC_CONVAR_SOUNDS  2
#define HALLUC_CONVAR_VISUALS 3
#define HALLUC_CONVAR_TOGGLE  4

int g_iHalluc_Every;
int g_iHalluc_Count;
bool g_bHalluc_Sounds;
bool g_bHalluc_Visuals;
bool g_bHallucinations_Enabled;

public void OnPluginStart_Hallucinations()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_CHAOS;

	/* COMMANDS */
	RegAdminCmd("sm_fm_halluc", Cmd_HallucinationsToggle, ADMFLAG_CONVARS, "Turn Hallucinations On/Off");
	RegAdminCmd("sm_halluc_settings", Cmd_HallucinationsSettings, ADMFLAG_CONVARS, "Open Hallucinations Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		HALLUC_CONVAR_EVERY, "sm_halluc_every",
		"20", "Seconds between two hallucinations",
		("10,15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HALLUC_CONVAR_COUNT, "sm_halluc_count",
		"2", "Humans who hallucinate each time (64 = everyone)",
		("1,2,3,5,64"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		HALLUC_CONVAR_SOUNDS, "sm_halluc_sounds",
		"1", "Hallucinations can be fake zombie sounds",
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		HALLUC_CONVAR_VISUALS, "sm_halluc_visuals",
		"1", ("Hallucinations can be flashes, texts and fake rings"),
		("0,1"), CONVAR_BOOL
	);

	DECLARE_FM_CVAR(
		HALLUC_CONVAR_TOGGLE, "sm_halluc_enable",
		"1", "Enable/Disable Hallucinations Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= HALLUC_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(Hallucinations_OnConVarChange);

	THIS_MODE_INFO.enableIndex = HALLUC_CONVAR_TOGGLE;
}

public void InitCvarsValues_Hallucinations()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iHalluc_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, HALLUC_CONVAR_EVERY, Int);
	g_iHalluc_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, HALLUC_CONVAR_COUNT, Int);
	g_bHalluc_Sounds = _FUNMODES_CVAR_GET_VALUE(modeIndex, HALLUC_CONVAR_SOUNDS, Bool);
	g_bHalluc_Visuals = _FUNMODES_CVAR_GET_VALUE(modeIndex, HALLUC_CONVAR_VISUALS, Bool);
	g_bHallucinations_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, HALLUC_CONVAR_TOGGLE, Bool);
}

void Hallucinations_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case HALLUC_CONVAR_EVERY:
			g_iHalluc_Every = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HALLUC_CONVAR_COUNT:
			g_iHalluc_Count = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case HALLUC_CONVAR_SOUNDS:
			g_bHalluc_Sounds = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case HALLUC_CONVAR_VISUALS:
			g_bHalluc_Visuals = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

		case HALLUC_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				Hallucinations_Reset();
			}

			g_bHallucinations_Enabled = val;
		}
	}
}

public void OnMapEnd_Hallucinations()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	Hallucinations_Reset();
}

char g_sHalluc_Sounds[][] =
{
	"npc/zombie/zombie_alert1.wav",
	"npc/zombie/zombie_alert2.wav",
	"npc/zombie/zombie_voice_idle1.wav",
	"npc/fast_zombie/fz_scream1.wav",
	"npc/zombie/zombie_pain1.wav"
};

char g_sHalluc_Lies[][] =
{
	"A ZOMBIE IS RIGHT BEHIND YOU!",
	"LOOK OUT!",
	"Did you hear that?",
	"RUN!",
	"Something is watching you...",
	"YOU ARE THE LAST HUMAN",
	"Your ammo is empty!"
};

int g_iHalluc_FakeColor[4] = { 255, 30, 30, 255 };

float g_fHalluc_Next;

public void OnMapStart_Hallucinations()
{
	for (int i = 0; i < sizeof(g_sHalluc_Sounds); i++)
		PrecacheSound(g_sHalluc_Sounds[i], true);
}

void Hallucinations_Reset()
{
	g_fHalluc_Next = 0.0;
}

public void Event_RoundStart_Hallucinations()
{
	g_fHalluc_Next = 0.0;
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Hallucinations are on: don't trust everything you see and hear...", THIS_MODE_INFO.tag);
}

void Hallucinations_Trick(int client)
{
	int kind = GetRandomInt(0, 3);
	if (!g_bHalluc_Sounds && kind == 0)
		kind = 1;

	if (!g_bHalluc_Visuals && kind != 0)
		kind = g_bHalluc_Sounds ? 0 : -1;

	switch (kind)
	{
		case 0:
		{
			// A growl from just behind them, only they hear it
			float pos[3], ang[3], back[3];
			GetClientAbsOrigin(client, pos);
			GetClientEyeAngles(client, ang);
			GetAngleVectors(ang, back, NULL_VECTOR, NULL_VECTOR);
			pos[0] -= back[0] * 80.0;
			pos[1] -= back[1] * 80.0;
			pos[2] += 40.0;

			EmitSoundToClient(client, g_sHalluc_Sounds[GetRandomInt(0, sizeof(g_sHalluc_Sounds) - 1)], SOUND_FROM_WORLD, SNDCHAN_AUTO,
				SNDLEVEL_NORMAL, SND_NOFLAGS, SNDVOL_NORMAL, SNDPITCH_NORMAL, -1, pos);
		}

		case 1:
			ScreenTint(client, GetRandomInt(0, 255), GetRandomInt(0, 80), GetRandomInt(0, 255), 110, 0.2, 1.0);

		case 2:
			PrintCenterText(client, g_sHalluc_Lies[GetRandomInt(0, sizeof(g_sHalluc_Lies) - 1)]);

		case 3:
		{
			// A fake danger ring that only they see
			float pos[3];
			GetClientAbsOrigin(client, pos);
			pos[2] += 8.0;

			TE_SetupBeamRingPoint(pos, 300.0, 20.0, g_LaserSprite, g_HaloSprite, 0, 15, 1.5, 8.0, 0.0, g_iHalluc_FakeColor, 10, 0);
			TE_SendToClient(client);
		}
	}
}

void Hallucinations_Wave()
{
	int list[MAXPLAYERS + 1];
	int count = GetShuffledHumans(list);
	if (g_iHalluc_Count < count)
		count = g_iHalluc_Count;

	for (int i = 0; i < count; i++)
	{
		if (!IsFakeClient(list[i]))
			Hallucinations_Trick(list[i]);
	}
}

public void OnTick_Hallucinations()
{
	if (HazardDue(g_fHalluc_Next, g_iHalluc_Every))
		Hallucinations_Wave();
}

public Action Cmd_HallucinationsToggle(int client, int args)
{
	if (!g_bHallucinations_Enabled)
	{
		CReplyToCommand(client, "%s Hallucinations is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	Hallucinations_Reset();

	CPrintToChatAll("%s Hallucinations is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Don't trust everything you see and hear...", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* Hallucinations Settings */
public Action Cmd_HallucinationsSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_HallucinationsSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("now", "Make them see things now", (THIS_MODE_INFO.isOn && g_bRoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_HallucinationsSettings(Menu menu, MenuAction action, int param1, int param2)
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
				Hallucinations_Wave();
				Cmd_HallucinationsSettings(param1, 0);
			}
			else
				ShowCvarsInfo(param1, THIS_MODE_INFO);
		}
	}

	return 0;
}
