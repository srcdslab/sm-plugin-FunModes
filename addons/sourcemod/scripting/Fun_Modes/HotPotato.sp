/*
    (). FunModes V2:

    @file           HotPotato.sp
    @Usage          Functions for the HotPotato mode.
                    Once the zombies are out, a human holds a potato with a countdown and passes it on by knifing
                    another human or pressing E next to one. Whoever holds it at zero explodes, hurting humans close by.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_HotPotato

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "HotPotato"

static int g_iHotPotatoIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iHotPotatoIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define POTATO_CONVAR_TIME   0
#define POTATO_CONVAR_BLAST  1
#define POTATO_CONVAR_TOGGLE 2

int g_iPotato_Time;
int g_iPotato_Blast;
bool g_bHotPotato_Enabled;

public void OnPluginStart_HotPotato()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_SURVIVAL;

	/* COMMANDS */
	RegAdminCmd("sm_fm_potato", Cmd_HotPotatoToggle, ADMFLAG_CONVARS, "Turn Hot Potato On/Off");
	RegAdminCmd("sm_potato_settings", Cmd_HotPotatoSettings, ADMFLAG_CONVARS, "Open Hot Potato Settings Menu");

	/* CONVARS */
	DECLARE_FM_CVAR(
		POTATO_CONVAR_TIME, "sm_potato_time",
		"30", "Seconds before the potato explodes",
		("15,20,30,45,60"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		POTATO_CONVAR_BLAST, "sm_potato_blast",
		"50", "Damage to the humans close to the explosion",
		("0,25,50,100"), CONVAR_INT
	);

	DECLARE_FM_CVAR(
		POTATO_CONVAR_TOGGLE, "sm_potato_enable",
		"1", "Enable/Disable Hot Potato Mode (This differs from turning it on/off)",
		("0,1"), CONVAR_BOOL
	);

	for (int i = 0; i <= POTATO_CONVAR_TOGGLE; i++)
		THIS_MODE_INFO.cvars[i].HookChange(HotPotato_OnConVarChange);

	THIS_MODE_INFO.enableIndex = POTATO_CONVAR_TOGGLE;

	HotPotato_OnPluginStart();
}

public void InitCvarsValues_HotPotato()
{
	int modeIndex = THIS_MODE_INFO.index;

	g_iPotato_Time = _FUNMODES_CVAR_GET_VALUE(modeIndex, POTATO_CONVAR_TIME, Int);
	g_iPotato_Blast = _FUNMODES_CVAR_GET_VALUE(modeIndex, POTATO_CONVAR_BLAST, Int);
	g_bHotPotato_Enabled = _FUNMODES_CVAR_GET_VALUE(modeIndex, POTATO_CONVAR_TOGGLE, Bool);
}

void HotPotato_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
	switch (cvarIndex)
	{
		case POTATO_CONVAR_TIME:
			g_iPotato_Time = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case POTATO_CONVAR_BLAST:
			g_iPotato_Blast = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

		case POTATO_CONVAR_TOGGLE:
		{
			bool val = _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);
			if (THIS_MODE_INFO.isOn && !val)
			{
				CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
				HotPotato_Reset();
			}

			g_bHotPotato_Enabled = val;
		}
	}
}

public void OnMapEnd_HotPotato()
{
	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
	HotPotato_Reset();
}

#define POTATO_BLAST_RADIUS 300.0
#define POTATO_PASS_RANGE   100.0

int g_iPotato_Color[4] = { 255, 60, 60, 255 };

int g_iPotato_Holder;               // userid, 0 = nobody
int g_iPotato_Left;                 // seconds left
float g_fPotato_NextAt;             // after an explosion: when the next potato appears
float g_fPotato_PassReady;          // the holder can't pass it on before this (no instant ping-pong)
int g_iPotato_Prev;                 // userid of the last holder ...
float g_fPotato_NoBackUntil;        // ... who can't get it straight back before this
int g_iPotato_LastButtons[MAXPLAYERS + 1];
Handle g_hPotato_Hud;

void HotPotato_OnPluginStart()
{
	g_hPotato_Hud = CreateModeHud();

	// Late load
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			OnClientPutInServer_HotPotato(i);
	}
}

public void OnClientPutInServer_HotPotato(int client)
{
	g_iPotato_LastButtons[client] = 0;
	SDKHook(client, SDKHook_TraceAttack, HotPotato_TraceAttack);
}

/* Nobody holds it any more (the holder's red colour goes too) */
void HotPotato_Drop()
{
	int holder = GetClientOfUserId(g_iPotato_Holder);
	if (holder && IsClientInGame(holder))
		SetEntityRenderColor(holder, 255, 255, 255, 255);

	g_iPotato_Holder = 0;
}

void HotPotato_Reset()
{
	HotPotato_Drop();
	g_fPotato_NextAt = 0.0;
}

public void Event_RoundStart_HotPotato()
{
	HotPotato_Reset();
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Hot Potato is on: once the zombies come, {olive}don't be the one holding it{lightgreen}!", THIS_MODE_INFO.tag);
}

public void Event_RoundEnd_HotPotato()
{
	HotPotato_Drop();
}

bool HotPotato_IsHolder(int client)
{
	return g_iPotato_Holder && GetClientUserId(client) == g_iPotato_Holder;
}

void HotPotato_Give(int client, int from)
{
	if (!client)
		return;

	HotPotato_Drop();
	g_iPotato_Holder = GetClientUserId(client);
	g_fPotato_PassReady = GetGameTime() + 1.0;
	g_iPotato_Prev = from ? GetClientUserId(from) : 0;
	g_fPotato_NoBackUntil = GetGameTime() + 3.0;
	SetEntityRenderColor(client, 255, 80, 80, 255);

	if (from)
		CPrintToChatAll("%s {olive}%N {lightgreen}passed the hot potato to {olive}%N{lightgreen}! (%d s left)", THIS_MODE_INFO.tag, from, client, g_iPotato_Left);
	else
		CPrintToChatAll("%s {olive}%N {lightgreen}has the hot potato! {olive}%d {lightgreen}seconds - knife another human or press E next to one to pass it.", THIS_MODE_INFO.tag, client, g_iPotato_Left);

	PrintCenterText(client, "YOU HAVE THE HOT POTATO! PASS IT ON!");
}

void HotPotato_TryPass(int holder, int target)
{
	if (!THIS_MODE_INFO.isOn || !g_bRoundLive || !HotPotato_IsHolder(holder) || target == holder || !IsHumanAlive(target))
		return;

	float now = GetGameTime();
	if (now < g_fPotato_PassReady)
		return;

	if (g_iPotato_Prev && GetClientUserId(target) == g_iPotato_Prev && now < g_fPotato_NoBackUntil)
	{
		PrintCenterText(holder, "No pass-backs! Find someone else.");
		return;
	}

	HotPotato_Give(target, holder);
}

/* Knife hits between teammates still reach TraceAttack with friendly fire off */
Action HotPotato_TraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (!THIS_MODE_INFO.isOn || attacker < 1 || attacker > MaxClients || !HotPotato_IsHolder(attacker) || !IsHumanAlive(victim))
		return Plugin_Continue;

	char weapon[32];
	GetClientWeapon(attacker, weapon, sizeof(weapon));
	if (strcmp(weapon, "weapon_knife") == 0)
		HotPotato_TryPass(attacker, victim);

	return Plugin_Continue;
}

/* E next to a human passes it too */
public void OnPlayerRunCmd_HotPotato(int client, int &buttons, float vel[3], bool &changed)
{
	bool pressed = (buttons & IN_USE) && !(g_iPotato_LastButtons[client] & IN_USE);
	g_iPotato_LastButtons[client] = buttons;
	if (!pressed || !HotPotato_IsHolder(client))
		return;

	float me[3], pos[3];
	GetClientAbsOrigin(client, me);

	int best;
	float bestDist = POTATO_PASS_RANGE;
	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == client || !IsHumanAlive(i))
			continue;

		GetClientAbsOrigin(i, pos);
		float dist = GetVectorDistance(me, pos);
		if (dist <= bestDist)
		{
			best = i;
			bestDist = dist;
		}
	}

	if (best)
		HotPotato_TryPass(client, best);
}

public void OnCheck_HotPotato(bool zombiesNow)
{
	if (g_iPotato_Holder)
	{
		int holder = GetClientOfUserId(g_iPotato_Holder);
		if (IsHumanAlive(holder))
			return;

		// The holder died, got infected or left before the countdown ran out: it jumps on
		if (holder)
			CPrintToChatAll("%s {olive}%N {lightgreen}dropped the hot potato!", THIS_MODE_INFO.tag, holder);

		HotPotato_Drop();
		if (zombiesNow)
		{
			if (g_iPotato_Left < 10)
				g_iPotato_Left = 10;

			HotPotato_Give(PickRandomHuman(holder), 0);
		}

		return;
	}

	// A new potato once the zombies are out (and a few seconds after an explosion)
	if (!zombiesNow || GetGameTime() < g_fPotato_NextAt)
		return;

	int pick = PickRandomHuman();
	if (pick)
	{
		g_iPotato_Left = g_iPotato_Time;
		HotPotato_Give(pick, 0);
	}
}

void HotPotato_Explode(int holder)
{
	float pos[3], other[3];
	GetClientAbsOrigin(holder, pos);

	HotPotato_Drop();
	g_fPotato_NextAt = GetGameTime() + 3.0;

	if (g_iExplosionSprite != -1)
	{
		TE_SetupExplosion(pos, g_iExplosionSprite, 5.0, 1, 0, RoundToNearest(POTATO_BLAST_RADIUS), 300);
		TE_SendToAll();
	}

	EmitAmbientSound(Explode_Sound, pos, holder, SNDLEVEL_RAIDSIREN);
	CPrintToChatAll("%s {olive}BOOM! %N {lightgreen}was still holding the hot potato!", THIS_MODE_INFO.tag, holder);

	for (int i = 1; i <= MaxClients; i++)
	{
		if (i == holder || g_iPotato_Blast <= 0 || !IsHumanAlive(i))
			continue;

		GetClientAbsOrigin(i, other);
		if (GetVectorDistance(pos, other) <= POTATO_BLAST_RADIUS)
			HurtPlayer(i, g_iPotato_Blast);
	}

	ForcePlayerSuicide(holder);
}

public void OnTick_HotPotato()
{
	int holder = GetClientOfUserId(g_iPotato_Holder);
	if (!IsHumanAlive(holder))
		return;

	g_iPotato_Left--;
	DrawPlayerRing(holder, g_iPotato_Color, 60.0);
	if (g_iPotato_Left <= 5)
	{
		// Higher, more urgent beep
		float pos[3];
		GetClientAbsOrigin(holder, pos);
		EmitAmbientSound(Beacon_Sound, pos, holder, SNDLEVEL_NORMAL, _, _, 150);
	}

	if (g_iPotato_Left <= 0)
	{
		HotPotato_Explode(holder);
		return;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		SetHudTextParams(-1.0, 0.18, 1.1, 255, 60, 60, 255, 0, 0.0, 0.0, 0.0);
		if (i == holder)
			ShowModeHud(i, g_hPotato_Hud, "YOU HAVE THE HOT POTATO! %d s - knife a human or press E next to one", g_iPotato_Left);
		else
			ShowModeHud(i, g_hPotato_Hud, "Hot potato: %N - %d s", holder, g_iPotato_Left);
	}
}

public Action Cmd_HotPotatoToggle(int client, int args)
{
	if (!g_bHotPotato_Enabled)
	{
		CReplyToCommand(client, "%s Hot Potato is currently Disabled", THIS_MODE_INFO.tag);
		return Plugin_Handled;
	}

	CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, !THIS_MODE_INFO.isOn, THIS_MODE_INFO.index);
	THIS_MODE_INFO.byRoulette = false;
	HotPotato_Reset();

	CPrintToChatAll("%s Hot Potato is now {olive}%s{lightgreen}!", THIS_MODE_INFO.tag, THIS_MODE_INFO.isOn ? "On" : "Off");
	if (THIS_MODE_INFO.isOn)
		CPrintToChatAll("%s Once the zombies come, {olive}don't be the one holding it{lightgreen}!", THIS_MODE_INFO.tag);

	return Plugin_Handled;
}

/* HotPotato Settings */
public Action Cmd_HotPotatoSettings(int client, int args)
{
	if (!client)
		return Plugin_Handled;

	Menu menu = new Menu(Menu_HotPotatoSettings);

	menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

	menu.AddItem("cvars", "Show Cvars\n");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

int Menu_HotPotatoSettings(Menu menu, MenuAction action, int param1, int param2)
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
