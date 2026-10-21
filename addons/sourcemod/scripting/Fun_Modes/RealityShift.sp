
/*
    (). FunModes V2:

    @file           RealityShift.sp
    @Usage          Functions for the RealityShift Mode.
*/

#pragma semicolon 1
#pragma newdecls required

#define _FM_RealityShift

#undef THIS_MODE_NAME
#define THIS_MODE_NAME "RealityShift"

static int g_iRealityShiftIndex = -1;

#undef THIS_MODE_INDEX
#define THIS_MODE_INDEX g_iRealityShiftIndex

#undef THIS_MODE_INFO
#define THIS_MODE_INFO g_ModesInfo[THIS_MODE_INDEX]

#define REALITYSHIFT_CONVAR_TIMER_INTERVAL 0
#define REALITYSHIFT_CONVAR_MODE 1
#define REALITYSHIFT_CONVAR_TOGGLE 2
#define REALITYSHIFT_CONVAR_PAIRS 3
#define REALITYSHIFT_CONVAR_MIXED 4
#define REALITYSHIFT_CONVAR_WARN 5

Handle g_hRealityShiftTimer;

int g_iRealityShiftAssigned[MAXPLAYERS + 1];
bool g_bRealityShiftSwapped[MAXPLAYERS + 1];

float g_fRealityShift_TimerInterval;
int g_iRealityShift_Mode;
bool g_bRealityShift_Enabled;
int g_iRealityShift_Pairs;
bool g_bRealityShift_Mixed;
int g_iRealityShift_Warn;

Handle g_hRealityShiftCountdown;
int g_iRealityShiftCountdown;

public void OnPluginStart_RealityShift()
{
	// Important, this must be first before filling any other mode info!
	FUNMODES_REGISTER_MODE()

	THIS_MODE_INFO.name = THIS_MODE_NAME;
	THIS_MODE_INFO.tag = "{gold}[FunModes-" ... THIS_MODE_NAME ... "]{lightgreen}";
	THIS_MODE_INFO.category = FM_CAT_CHAOS;

    RegAdminCmd("sm_fm_rs", Cmd_RealityShiftToggle, ADMFLAG_CONVARS, "Turn RealityShift Mode On/Off");
    RegAdminCmd("sm_realityshift_settings", Cmd_RealityShiftSettings, ADMFLAG_CONVARS, "Open RealityShift Sttings Menu");

    DECLARE_FM_CVAR(
        REALITYSHIFT_CONVAR_TIMER_INTERVAL, "sm_realityshift_timer_interval",
        "30.0", "After how many seconds to keep swapping positions",
        ("15.0,30.0,45.0,60.0"), CONVAR_FLOAT
    );
    THIS_MODE_INFO.cvars[REALITYSHIFT_CONVAR_TIMER_INTERVAL].HookChange(RealityShift_OnConVarChange);

    DECLARE_FM_CVAR(
        REALITYSHIFT_CONVAR_MODE, "sm_realityshift_mode",
        "0", "RealityShift Mode [0 = Random Swaps 1 = Assigned Swaps [At round start]]",
        ("0,1"), CONVAR_INT
    );
    THIS_MODE_INFO.cvars[REALITYSHIFT_CONVAR_MODE].HookChange(RealityShift_OnConVarChange);

    DECLARE_FM_CVAR(
        REALITYSHIFT_CONVAR_TOGGLE, "sm_realityshift_enable",
        "1", "Enable/Disable RealityShift Mode (This differs from turning it on/off)",
        ("0,1"), CONVAR_BOOL
    );
    THIS_MODE_INFO.cvars[REALITYSHIFT_CONVAR_TOGGLE].HookChange(RealityShift_OnConVarChange);

    DECLARE_FM_CVAR(
        REALITYSHIFT_CONVAR_PAIRS, "sm_realityshift_pairs",
        "0", "Random swaps: how many pairs swap each time (0 = everyone)",
        ("0,1,2,3,5"), CONVAR_INT
    );

    THIS_MODE_INFO.cvars[REALITYSHIFT_CONVAR_PAIRS].HookChange(RealityShift_OnConVarChange);

    DECLARE_FM_CVAR(
        REALITYSHIFT_CONVAR_MIXED, "sm_realityshift_mixed",
        "0", "Zombies are swapped too (humans and zombies can swap with each other)",
        ("0,1"), CONVAR_BOOL
    );

    THIS_MODE_INFO.cvars[REALITYSHIFT_CONVAR_MIXED].HookChange(RealityShift_OnConVarChange);

    DECLARE_FM_CVAR(
        REALITYSHIFT_CONVAR_WARN, "sm_realityshift_warn",
        "3", "Seconds of countdown with beeps before each swap (0 = none)",
        ("0,3,5"), CONVAR_INT
    );

    THIS_MODE_INFO.cvars[REALITYSHIFT_CONVAR_WARN].HookChange(RealityShift_OnConVarChange);

    THIS_MODE_INFO.enableIndex = REALITYSHIFT_CONVAR_TOGGLE;
}

public void InitCvarsValues_RealityShift()
{
    int modeIndex = THIS_MODE_INFO.index;

    g_fRealityShift_TimerInterval =
        _FUNMODES_CVAR_GET_VALUE(modeIndex, REALITYSHIFT_CONVAR_TIMER_INTERVAL, Float);

    g_iRealityShift_Mode =
        _FUNMODES_CVAR_GET_VALUE(modeIndex, REALITYSHIFT_CONVAR_MODE, Int);

    g_bRealityShift_Enabled =
        _FUNMODES_CVAR_GET_VALUE(modeIndex, REALITYSHIFT_CONVAR_TOGGLE, Bool);

    g_iRealityShift_Pairs =
        _FUNMODES_CVAR_GET_VALUE(modeIndex, REALITYSHIFT_CONVAR_PAIRS, Int);

    g_bRealityShift_Mixed =
        _FUNMODES_CVAR_GET_VALUE(modeIndex, REALITYSHIFT_CONVAR_MIXED, Bool);

    g_iRealityShift_Warn =
        _FUNMODES_CVAR_GET_VALUE(modeIndex, REALITYSHIFT_CONVAR_WARN, Int);
}

void RealityShift_OnConVarChange(int modeIndex, int cvarIndex, const char[] oldValue, const char[] newValue)
{
    switch (cvarIndex)
    {
        case REALITYSHIFT_CONVAR_TIMER_INTERVAL:
        {
            g_fRealityShift_TimerInterval =
                _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Float);

            if (THIS_MODE_INFO.isOn)
                RealityShift_StartTimer(g_fRealityShift_TimerInterval);
        }

        case REALITYSHIFT_CONVAR_MODE:
        {
            g_iRealityShift_Mode =
                _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

            if (THIS_MODE_INFO.isOn && g_iRealityShift_Mode == 1)
                RealityShift_AssignPlayers(true);
        }

        case REALITYSHIFT_CONVAR_TOGGLE:
        {
            bool val =
                _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

            if (THIS_MODE_INFO.isOn)
                CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, val, THIS_MODE_INFO.index);

            g_bRealityShift_Enabled = val;
        }

        case REALITYSHIFT_CONVAR_PAIRS:
            g_iRealityShift_Pairs =
                _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);

        case REALITYSHIFT_CONVAR_MIXED:
            g_bRealityShift_Mixed =
                _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Bool);

        case REALITYSHIFT_CONVAR_WARN:
            g_iRealityShift_Warn =
                _FUNMODES_CVAR_GET_VALUE(modeIndex, cvarIndex, Int);
    }
}

public void OnMapEnd_RealityShift()
{
    CHANGE_MODE_INFO(THIS_MODE_INFO, isOn, false, THIS_MODE_INFO.index);
    g_hRealityShiftTimer = null;
    g_hRealityShiftCountdown = null;
}

public void OnClientPutInServer_RealityShift(int client)
{
    g_iRealityShiftAssigned[client] = 0;
    g_bRealityShiftSwapped[client] = false;
}

public void OnClientDisconnect_RealityShift(int client)
{
    g_iRealityShiftAssigned[client] = 0;
    g_bRealityShiftSwapped[client] = false;
}

public void ZR_OnClientInfected_RealityShift(int client)
{
    #pragma unused client

    if (!THIS_MODE_INFO.isOn)
        return;

    if (!g_bMotherZombie && g_hRealityShiftTimer == null)
    {
        RealityShift_StartTimer(g_fRealityShift_TimerInterval);

        if (g_iRealityShift_Mode == 1)
            RealityShift_AssignPlayers(true);
    }
}

public Action Cmd_RealityShiftToggle(int client, int args)
{
    if (!g_bRealityShift_Enabled)
    {
        CReplyToCommand(client, "%s RealityShift Mode is currently Disabled", THIS_MODE_INFO.tag);
        return Plugin_Handled;
    }

    CHANGE_MODE_INFO(
        THIS_MODE_INFO,
        isOn,
        !THIS_MODE_INFO.isOn,
        THIS_MODE_INFO.index
    );

    THIS_MODE_INFO.byRoulette = false;

    CPrintToChatAll(
        "%s RealityShift Mode is now %s!",
        THIS_MODE_INFO.tag,
        THIS_MODE_INFO.isOn ? "On" : "Off"
    );

    if (THIS_MODE_INFO.isOn)
    {
        FunModes_HookEvent(
            g_bEvent_RoundStart,
            "round_start",
            Event_RoundStart
        );

        FunModes_HookEvent(
            g_bEvent_RoundEnd,
            "round_end",
            Event_RoundEnd
        );

        CPrintToChatAll(
            "%s Each human will be swapped with another one!",
            THIS_MODE_INFO.tag
        );

        if (g_iRealityShift_Mode == 0)
        {
            CPrintToChatAll(
                "%s The positions will be swapped randomly.",
                THIS_MODE_INFO.tag
            );
        }

        int interval = RoundToNearest(g_fRealityShift_TimerInterval);

        CPrintToChatAll(
            "%s Positions will be swapped every {olive}%d seconds!",
            THIS_MODE_INFO.tag,
            interval
        );

        FunModes_RestartRound();
    }
    else
    {
        delete g_hRealityShiftTimer;
        delete g_hRealityShiftCountdown;
    }

    return Plugin_Handled;
}

public Action Cmd_RealityShiftSettings(int client, int args)
{
    if (!client)
        return Plugin_Handled;

    Menu menu = new Menu(Menu_RealityShiftSettings);

    menu.SetTitle("%s - Settings", THIS_MODE_INFO.name);

    menu.AddItem("now", "Swap positions now", (THIS_MODE_INFO.isOn && !g_bRoundEnd && g_hRealityShiftCountdown == null) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
    menu.AddItem("cvars", "Show Cvars\n");

    menu.ExitBackButton = true;

    menu.Display(client, MENU_TIME_FOREVER);

    return Plugin_Handled;
}

int Menu_RealityShiftSettings(Menu menu, MenuAction action, int param1, int param2)
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
                RealityShift_Shift();
                Cmd_RealityShiftSettings(param1, 0);
            }
            else
                ShowCvarsInfo(param1, THIS_MODE_INFO);
        }
    }

    return 0;
}

void RealityShift_StartTimer(float interval)
{
    for (int i = 1; i <= MaxClients; i++)
        g_iRealityShiftAssigned[i] = 0;

    delete g_hRealityShiftTimer;

    g_hRealityShiftTimer =
        CreateTimer(
            interval,
            RealityShift_Timer,
            _,
            TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT
        );
}

Action RealityShift_Timer(Handle timer)
{
    if (g_bRoundEnd || !g_bMotherZombie)
    {
        g_hRealityShiftTimer = null;
        return Plugin_Stop;
    }

    RealityShift_Shift();
    return Plugin_Continue;
}

/* Swaps now, or after a countdown with beeps */
void RealityShift_Shift()
{
    if (g_iRealityShift_Warn <= 0)
    {
        RealityShift_AssignPlayers(_, g_iRealityShift_Mode == 0);
        return;
    }

    if (g_hRealityShiftCountdown != null)
        return;

    g_iRealityShiftCountdown = g_iRealityShift_Warn;
    RealityShift_CountdownTick();
    g_hRealityShiftCountdown =
        CreateTimer(
            1.0,
            RealityShift_CountdownTimer,
            _,
            TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT
        );
}

Action RealityShift_CountdownTimer(Handle timer)
{
    if (!THIS_MODE_INFO.isOn || g_bRoundEnd)
    {
        g_hRealityShiftCountdown = null;
        return Plugin_Stop;
    }

    if (g_iRealityShiftCountdown <= 0)
    {
        g_hRealityShiftCountdown = null;
        RealityShift_AssignPlayers(_, g_iRealityShift_Mode == 0);
        return Plugin_Stop;
    }

    RealityShift_CountdownTick();
    return Plugin_Continue;
}

void RealityShift_CountdownTick()
{
    PrintCenterTextAll("Positions swap in %d...", g_iRealityShiftCountdown);
    EmitSoundToAll(Beacon_Sound, _, _, _, _, _, 100 + 20 * (g_iRealityShift_Warn - g_iRealityShiftCountdown));
    g_iRealityShiftCountdown--;
}

/* Alive, on a team that swaps and not carrying a map item */
bool RealityShift_CanSwap(int client)
{
    if (!IsClientInGame(client) || !IsPlayerAlive(client))
        return false;

    if (!ZR_IsClientHuman(client) && !(g_bRealityShift_Mixed && ZR_IsClientZombie(client)))
        return false;

    return !EW_ClientHasItem(client);
}

int GetRandomClientFromArray(int[] arr, int len, int &client)
{
    int count;

    int[] newArr = new int[len];

    for (int i = 0; i < len; i++)
    {
        if (arr[i] == 0)
            continue;

        if (g_bRealityShiftSwapped[arr[i]])
            continue;

        newArr[count++] = arr[i];
    }

    if (!count)
        return -1;

    int index = GetRandomInt(0, count - 1);

    client = newArr[index];

    return index;
}

void RealityShift_AssignPlayers(bool saveOnly = false, bool random = true)
{
    int clients[MAXPLAYERS + 1];

    int count;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!RealityShift_CanSwap(i))
            continue;

        g_bRealityShiftSwapped[i] = false;

        clients[count++] = i;

        if (!random)
        {
            int assignedTo =
                GetClientOfUserId(g_iRealityShiftAssigned[i]);

            if (!assignedTo
            || !RealityShift_CanSwap(assignedTo))
            {
                g_bRealityShiftSwapped[i] = false;

                g_iRealityShiftAssigned[i] = 0;

                continue;
            }

            RealityShift_SwapPositions(i, assignedTo);
        }
    }

    if (!saveOnly && !random)
        return;

    int assignmentsCount = count / 2;

    // Random swaps can be limited to a few pairs
    if (!saveOnly && g_iRealityShift_Pairs > 0 && assignmentsCount > g_iRealityShift_Pairs)
        assignmentsCount = g_iRealityShift_Pairs;

    if (assignmentsCount < 1)
        return;

    for (int i = 0; i < assignmentsCount; i++)
    {
        int client, assignedTo;

        int index =
            GetRandomClientFromArray(clients, count, client);

        if (index == -1)
            continue;

        clients[index] = 0;

        index =
            GetRandomClientFromArray(clients, count, assignedTo);

        if (index == -1)
            continue;

        clients[index] = 0;

        if (saveOnly)
        {
            g_iRealityShiftAssigned[client] =
                GetClientUserId(assignedTo);

            g_iRealityShiftAssigned[assignedTo] =
                GetClientUserId(client);

            CPrintToChat(
                client,
                "%s You will swap with {olive}%N {lightgreen} all round!",
                THIS_MODE_INFO.tag,
                assignedTo
            );

            CPrintToChat(
                assignedTo,
                "%s You will swap with {olive}%N {lightgreen} all round!",
                THIS_MODE_INFO.tag,
                client
            );
        }
        else
        {
            if (!random)
                continue;

            if (g_bRealityShiftSwapped[client]
            || g_bRealityShiftSwapped[assignedTo])
                continue;

            RealityShift_SwapPositions(
                client,
                assignedTo
            );
        }
    }
}

void RealityShift_SwapPositions(int client, int assignedTo)
{
    if (client == assignedTo)
        return;

    if (g_bRealityShiftSwapped[client]
    || g_bRealityShiftSwapped[assignedTo])
        return;

    float clientOrigin[3];
    float assignedToOrigin[3];

    float clientEyeAngles[3];
    float assignedToEyeAngles[3];

    GetClientAbsOrigin(client, clientOrigin);
    GetClientAbsOrigin(assignedTo, assignedToOrigin);

    GetClientEyeAngles(client, clientEyeAngles);
    GetClientEyeAngles(assignedTo, assignedToEyeAngles);

    TeleportEntity(
        client,
        assignedToOrigin,
        assignedToEyeAngles
    );

    TeleportEntity(
        assignedTo,
        clientOrigin,
        clientEyeAngles
    );

    CPrintToChat(
        client,
        "%s You swapped positions with {olive}%N",
        THIS_MODE_INFO.tag,
        assignedTo
    );

    CPrintToChat(
        assignedTo,
        "%s You swapped positions with {olive}%N",
        THIS_MODE_INFO.tag,
        client
    );

    g_bRealityShiftSwapped[client] = true;
    g_bRealityShiftSwapped[assignedTo] = true;
}
