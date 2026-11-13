/*
    (). FunModes V2:
        
    @file           Core/Forwards.sp
    @Usage          Modes Forwards Management, don't touch it if you don't know what you are doing!
*/

#pragma semicolon 1

/* Forwards Indexes and Flags */
#define FWDI_InitCvarsValues         0
#define FWDI_OnPluginEnd             1
#define FWDI_OnMapStart              2
#define FWDI_OnMapEnd                3
#define FWDI_OnClientPutInServer     4
#define FWDI_OnClientDisconnect      5
#define FWDI_ZR_OnClientInfected     6
#define FWDI_Event_RoundStart        7
#define FWDI_Event_RoundEnd          8
#define FWDI_Event_PlayerSpawn       9
#define FWDI_Event_PlayerTeam        10
#define FWDI_Event_PlayerDeath       11
#define FWDI_OnTakeDamagePost        12
#define FWDI_OnTakeDamage            13
#define FWDI_OnWeaponEquip           14
#define FWDI_OnFlashlight            15
#define FWDI_OnTick                  16
#define FWDI_OnCheck                 17
#define FWDI_OnPlayerRunCmd          18
#define FWDI_OnClientSayCommand      19
#define FWDI_OnBuyCommand            20
#define FWD_COUNT                    21

#define FWD_InitCvarsValues          (1 << FWDI_InitCvarsValues)
#define FWD_OnPluginEnd              (1 << FWDI_OnPluginEnd)
#define FWD_OnMapStart               (1 << FWDI_OnMapStart)
#define FWD_OnMapEnd                 (1 << FWDI_OnMapEnd)
#define FWD_OnClientPutInServer      (1 << FWDI_OnClientPutInServer)
#define FWD_OnClientDisconnect       (1 << FWDI_OnClientDisconnect)
#define FWD_ZR_OnClientInfected      (1 << FWDI_ZR_OnClientInfected)
#define FWD_Event_RoundStart         (1 << FWDI_Event_RoundStart)
#define FWD_Event_RoundEnd           (1 << FWDI_Event_RoundEnd)
#define FWD_Event_PlayerSpawn        (1 << FWDI_Event_PlayerSpawn)
#define FWD_Event_PlayerTeam         (1 << FWDI_Event_PlayerTeam)
#define FWD_Event_PlayerDeath        (1 << FWDI_Event_PlayerDeath)
#define FWD_OnTakeDamagePost         (1 << FWDI_OnTakeDamagePost)
#define FWD_OnTakeDamage             (1 << FWDI_OnTakeDamage)
#define FWD_OnWeaponEquip            (1 << FWDI_OnWeaponEquip)
#define FWD_OnFlashlight             (1 << FWDI_OnFlashlight)
#define FWD_OnTick                   (1 << FWDI_OnTick)
#define FWD_OnCheck                  (1 << FWDI_OnCheck)
#define FWD_OnPlayerRunCmd           (1 << FWDI_OnPlayerRunCmd)
#define FWD_OnClientSayCommand       (1 << FWDI_OnClientSayCommand)
#define FWD_OnBuyCommand             (1 << FWDI_OnBuyCommand)

/* The modes that define each forward, in the order they were registered: the forwards only loop over them,
   not over every mode (most modes define a handful of forwards, and some forwards run for every player command) */
int g_iFwdModes[FWD_COUNT][MAX_MODES_NUM];
int g_iFwdModesCount[FWD_COUNT];

/* 
* Checks whether a given forward can be executed for the current mode the compiler is reading.
*
* @param %1		The forward name.
*/
#define CHECK_FORWARD_FLAG(%1) \
		if (!(this.flags & FWD_%1)) return;

/* 
* Executes a specific forward with no params for the current FM_Forwards enum struct.
*
* @param %1		The forward name.
*/
#define CALL_FUNCTION_PARAM0(%1) \
		CHECK_FORWARD_FLAG(%1) \
		Call_StartFunction(null, this.fn_%1); \
		Call_Finish();

/* 
* Executes a specific forward with one param for the current FM_Forwards enum struct.
*
* @param %1		The forward name.
* @param %2		The first param.
* @param %3		The type of the first param. That's used for Call_Push*
*/
#define CALL_FUNCTION_PARAM1(%1,%2,%3) \
		CHECK_FORWARD_FLAG(%1) \
		Call_StartFunction(null, this.fn_%1); \
		Call_Push%3(%2); \
		Call_Finish();

/* 
* Executes a specific forward with three params for the current FM_Forwards enum struct.
*
* @param %1		The forward name.
* @param %2		The first param.
* @param %3		The type of the first param. That's used for Call_Push*
* @param %4		The second param.
* @param %5		The type of the second param. That's used for Call_Push*
* @param %6		The third param.
* @param %7		The type of the third param. That's used for Call_Push*
*/
#define CALL_FUNCTION_PARAM3(%1,%2,%3,%4,%5,%6,%7) \
		CHECK_FORWARD_FLAG(%1) \
		Call_StartFunction(null, this.fn_%1); \
		Call_Push%3(%2); \
		Call_Push%5(%4); \
		Call_Push%7(%6); \
		Call_Finish();

/* 
* Executes a specific forward with four params for the current FM_Forwards enum struct.
*
* @param %1		The forward name.
* @param %2		The first param.
* @param %3		The type of the first param. That's used for Call_Push*
* @param %4		The second param.
* @param %5		The type of the second param. That's used for Call_Push*
* @param %6		The third param.
* @param %7		The type of the third param. That's used for Call_Push*
* @param %6		The fourth param.
* @param %7		The type of the fourth param. That's used for Call_Push*
*/
#define CALL_FUNCTION_PARAM4(%1,%2,%3,%4,%5,%6,%7,%8,%9) \
		CHECK_FORWARD_FLAG(%1) \
		Call_StartFunction(null, this.fn_%1); \
		Call_Push%3(%2); \
		Call_Push%5(%4); \
		Call_Push%7(%6); \
		Call_Push%9(%8); \
		Call_Finish();

/*
* Calls a forward with no params on every mode that defines it.
*
* @param %1		The forward name.
*/
#define DECLARE_FM_FORWARD_PARAM0(%1) \
		for (int fwd_i = 0; fwd_i < g_iFwdModesCount[FWDI_%1]; fwd_i++) \
		{ \
			g_ModesInfo[g_iFwdModes[FWDI_%1][fwd_i]].forwards.Call_%1(); \
		}

/*
* Calls a forward with one param on every mode that defines it.
*
* @param %1		The forward name.
* @param %2		The first param.
*/
#define DECLARE_FM_FORWARD_PARAM1(%1,%2) \
		for (int fwd_i = 0; fwd_i < g_iFwdModesCount[FWDI_%1]; fwd_i++) \
		{ \
			g_ModesInfo[g_iFwdModes[FWDI_%1][fwd_i]].forwards.Call_%1(%2); \
		}

/*
* Calls a forward with no params on the modes that define it and are on.
*
* @param %1		The forward name.
*/
#define DECLARE_FM_FORWARD_ON_PARAM0(%1) \
		for (int fwd_i = 0; fwd_i < g_iFwdModesCount[FWDI_%1]; fwd_i++) \
		{ \
			int fwd_m = g_iFwdModes[FWDI_%1][fwd_i]; \
			if (g_ModesInfo[fwd_m].isOn) \
				g_ModesInfo[fwd_m].forwards.Call_%1(); \
		}

/*
* Calls a forward with one param on the modes that define it and are on.
*
* @param %1		The forward name.
* @param %2		The first param.
*/
#define DECLARE_FM_FORWARD_ON_PARAM1(%1,%2) \
		for (int fwd_i = 0; fwd_i < g_iFwdModesCount[FWDI_%1]; fwd_i++) \
		{ \
			int fwd_m = g_iFwdModes[FWDI_%1][fwd_i]; \
			if (g_ModesInfo[fwd_m].isOn) \
				g_ModesInfo[fwd_m].forwards.Call_%1(%2); \
		}

/*
* Calls a forward with three params on every mode that defines it.
*
* @param %1		The forward name.
* @param %2		The first param.
* @param %3		The second param.
* @param %4		The third param.
*/
#define DECLARE_FM_FORWARD_PARAM3(%1,%2,%3,%4) \
		for (int fwd_i = 0; fwd_i < g_iFwdModesCount[FWDI_%1]; fwd_i++) \
		{ \
			g_ModesInfo[g_iFwdModes[FWDI_%1][fwd_i]].forwards.Call_%1(%2,%3,%4); \
		}

/*
* Calls a forward with four params on every mode that defines it.
*
* @param %1		The forward name.
* @param %2		The first param.
* @param %3		The second param.
* @param %4		The third param.
* @param %5		The fourth param.
*/
#define DECLARE_FM_FORWARD_PARAM4(%1,%2,%3,%4,%5) \
		for (int fwd_i = 0; fwd_i < g_iFwdModesCount[FWDI_%1]; fwd_i++) \
		{ \
			g_ModesInfo[g_iFwdModes[FWDI_%1][fwd_i]].forwards.Call_%1(%2,%3,%4,%5); \
		}

/*
* Validates whether a mode can execute this specific forward, and adds the mode to the forward's list.
* Only expanded inside FunModes_ValidateForwards (Core.sp), which provides modeIndex and modeName.
*
* @param %1		The forward name.
* @param %2		The forward name as char[].
*/
#define VALIDATE_FM_ONE_FORWARD(%1,%2) \
		g_ModesInfo[modeIndex].forwards.fn_%1 = FunModes_GetModeForward(%2, modeName); \
		if (g_ModesInfo[modeIndex].forwards.fn_%1 != INVALID_FUNCTION) \
		{ \
			g_ModesInfo[modeIndex].forwards.flags |= FWD_%1; \
			g_iFwdModes[FWDI_%1][g_iFwdModesCount[FWDI_%1]++] = modeIndex; \
		}

/*
* Gets the function ID for all available forwards of a mode.
* Only expanded inside FunModes_ValidateForwards (Core.sp), which provides modeIndex and modeName.
*
* @noparams
*/
#define VALIDATE_FM_FORWARDS() \
		VALIDATE_FM_ONE_FORWARD(InitCvarsValues, "InitCvarsValues") \
		VALIDATE_FM_ONE_FORWARD(OnPluginEnd, "OnPluginEnd") \
		VALIDATE_FM_ONE_FORWARD(OnMapStart, "OnMapStart") \
		VALIDATE_FM_ONE_FORWARD(OnMapEnd, "OnMapEnd") \
		VALIDATE_FM_ONE_FORWARD(OnClientPutInServer, "OnClientPutInServer") \
		VALIDATE_FM_ONE_FORWARD(OnClientDisconnect, "OnClientDisconnect") \
		VALIDATE_FM_ONE_FORWARD(ZR_OnClientInfected, "ZR_OnClientInfected") \
		VALIDATE_FM_ONE_FORWARD(Event_RoundStart, "Event_RoundStart") \
		VALIDATE_FM_ONE_FORWARD(Event_RoundEnd, "Event_RoundEnd") \
		VALIDATE_FM_ONE_FORWARD(Event_PlayerSpawn, "Event_PlayerSpawn") \
		VALIDATE_FM_ONE_FORWARD(Event_PlayerTeam, "Event_PlayerTeam") \
		VALIDATE_FM_ONE_FORWARD(Event_PlayerDeath, "Event_PlayerDeath") \
		VALIDATE_FM_ONE_FORWARD(OnTakeDamagePost, "OnTakeDamagePost") \
		VALIDATE_FM_ONE_FORWARD(OnTakeDamage, "OnTakeDamage") \
		VALIDATE_FM_ONE_FORWARD(OnWeaponEquip, "OnWeaponEquip") \
		VALIDATE_FM_ONE_FORWARD(OnFlashlight, "OnFlashlight") \
		VALIDATE_FM_ONE_FORWARD(OnTick, "OnTick") \
		VALIDATE_FM_ONE_FORWARD(OnCheck, "OnCheck") \
		VALIDATE_FM_ONE_FORWARD(OnPlayerRunCmd, "OnPlayerRunCmd") \
		VALIDATE_FM_ONE_FORWARD(OnClientSayCommand, "OnClientSayCommand") \
		VALIDATE_FM_ONE_FORWARD(OnBuyCommand, "OnBuyCommand")

enum struct FM_Forwards
{
	int flags;

	Function fn_InitCvarsValues;
	void Call_InitCvarsValues()
	{
		CALL_FUNCTION_PARAM0(InitCvarsValues)
	}

	Function fn_OnPluginEnd;
	void Call_OnPluginEnd()
	{
		CALL_FUNCTION_PARAM0(OnPluginEnd)
	}

	Function fn_OnMapStart;
	void Call_OnMapStart()
	{
		CALL_FUNCTION_PARAM0(OnMapStart)
	}

	Function fn_OnMapEnd;
	void Call_OnMapEnd()
	{
		CALL_FUNCTION_PARAM0(OnMapEnd)
	}

	Function fn_OnClientPutInServer;
	void Call_OnClientPutInServer(int client)
	{
		CALL_FUNCTION_PARAM1(OnClientPutInServer, client, Cell)
	}

	Function fn_OnClientDisconnect;
	void Call_OnClientDisconnect(int client)
	{
		CALL_FUNCTION_PARAM1(OnClientDisconnect, client, Cell)
	}

	Function fn_ZR_OnClientInfected;
	void Call_ZR_OnClientInfected(int client)
	{
		CALL_FUNCTION_PARAM1(ZR_OnClientInfected, client, Cell)
	}

	Function fn_Event_RoundStart;
	void Call_Event_RoundStart()
	{
		CALL_FUNCTION_PARAM0(Event_RoundStart)
	}

	Function fn_Event_RoundEnd;
	void Call_Event_RoundEnd()
	{
		CALL_FUNCTION_PARAM0(Event_RoundEnd)
	}

	Function fn_Event_PlayerSpawn;
	void Call_Event_PlayerSpawn(int client)
	{
		CALL_FUNCTION_PARAM1(Event_PlayerSpawn, client, Cell)
	}

	Function fn_Event_PlayerTeam;
	void Call_Event_PlayerTeam(Event event)
	{
		CALL_FUNCTION_PARAM1(Event_PlayerTeam, event, Cell)
	}

	Function fn_Event_PlayerDeath;
	void Call_Event_PlayerDeath(int client)
	{
		CALL_FUNCTION_PARAM1(Event_PlayerDeath, client, Cell)
	}
	
	Function fn_OnTakeDamagePost;
	void Call_OnTakeDamagePost(int victim, int attacker, float damage)
	{
		CALL_FUNCTION_PARAM3(OnTakeDamagePost, victim, Cell, attacker, Cell, damage, Cell)
	}

	Function fn_OnTakeDamage;
	/* The mode can change the attacker and the damage, setting result to Plugin_Changed */
	void Call_OnTakeDamage(int victim, int &attacker, float &damage, Action &result)
	{
		CALL_FUNCTION_PARAM4(OnTakeDamage, victim, Cell, attacker, CellRef, damage, FloatRef, result, CellRef)
	}

	Function fn_OnWeaponEquip;
	void Call_OnWeaponEquip(int client, int weapon, Action &result)
	{
		CALL_FUNCTION_PARAM3(OnWeaponEquip, client, Cell, weapon, Cell, result, CellRef)
	}

	/* The player pressed the flashlight key (impulse 100), only called while the mode is on */
	Function fn_OnFlashlight;
	void Call_OnFlashlight(int client)
	{
		CALL_FUNCTION_PARAM1(OnFlashlight, client, Cell)
	}

	/* Called every second while the mode is on */
	Function fn_OnTick;
	void Call_OnTick()
	{
		CALL_FUNCTION_PARAM0(OnTick)
	}

	/* Called every 0.2 seconds while the mode is on */
	Function fn_OnCheck;
	void Call_OnCheck(bool zombiesNow)
	{
		CALL_FUNCTION_PARAM1(OnCheck, zombiesNow, Cell)
	}

	/* The mode can change the player's buttons and velocity, setting changed to true */
	Function fn_OnPlayerRunCmd;
	void Call_OnPlayerRunCmd(int client, int &buttons, float vel[3], bool &changed)
	{
		CHECK_FORWARD_FLAG(OnPlayerRunCmd)
		Call_StartFunction(null, this.fn_OnPlayerRunCmd);
		Call_PushCell(client);
		Call_PushCellRef(buttons);
		Call_PushArrayEx(vel, 3, SM_PARAM_COPYBACK);
		Call_PushCellRef(changed);
		Call_Finish();
	}

	/* The mode can block a chat message by setting result to Plugin_Handled or Plugin_Stop */
	Function fn_OnClientSayCommand;
	void Call_OnClientSayCommand(int client, const char[] text, Action &result)
	{
		CHECK_FORWARD_FLAG(OnClientSayCommand)
		Call_StartFunction(null, this.fn_OnClientSayCommand);
		Call_PushCell(client);
		Call_PushString(text);
		Call_PushCellRef(result);
		Call_Finish();
	}

	/* The mode can block a buy by setting result to Plugin_Handled or Plugin_Stop */
	Function fn_OnBuyCommand;
	void Call_OnBuyCommand(int client, const char[] weapon, Action &result)
	{
		CHECK_FORWARD_FLAG(OnBuyCommand)
		Call_StartFunction(null, this.fn_OnBuyCommand);
		Call_PushCell(client);
		Call_PushString(weapon);
		Call_PushCellRef(result);
		Call_Finish();
	}
}
