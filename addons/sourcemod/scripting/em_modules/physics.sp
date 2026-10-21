// Shared speed and gravity for eventmodes.sp. modes.sp calls Physics_Apply every 0.2 s.
//
// Several modes change how fast or floaty players are (Boss Zombie, Hero, Last Stand, Quicksand, Zombie
// Frenzy, Gravity Waves). Each only reports a multiplier; this stacks them and applies the result on
// top of the player's own value - which Zombie Reloaded sets per class - instead of overwriting it. If
// something else changes the value meanwhile (ZR on spawn or infection), that becomes the new base.

#if defined _em_physics_included
 #endinput
#endif
#define _em_physics_included

#define PHYS_SPEED_PROP "m_flLaggedMovementValue"

bool g_PhysTouched[MAXPLAYERS + 1];
float g_PhysBase[MAXPLAYERS + 1];
float g_PhysSet[MAXPLAYERS + 1];
bool g_GravTouched[MAXPLAYERS + 1];
float g_GravBase[MAXPLAYERS + 1];
float g_GravSet[MAXPLAYERS + 1];

float Physics_SpeedMult(int client)
{
	return BZ_SpeedMult(client) * Hero_SpeedMult(client) * LS_SpeedMult(client) * QS_SpeedMult(client) * ZF_SpeedMult(client)
		* RLGL_SpeedMult(client) * GG_SpeedMult(client);
}

float Physics_GravityMult(int client)
{
	return GW_GravityMult(client);
}

bool Physics_Near(float a, float b)
{
	return FloatAbs(a - b) < 0.001;
}

void Physics_ApplySpeed(int client, float mult)
{
	float cur = GetEntPropFloat(client, Prop_Data, PHYS_SPEED_PROP);
	if (!g_PhysTouched[client] || !Physics_Near(cur, g_PhysSet[client]))
		g_PhysBase[client] = cur;   // the value to build on (ZR may have set it)
	if (Physics_Near(mult, 1.0))
	{
		if (g_PhysTouched[client])
			SetEntPropFloat(client, Prop_Data, PHYS_SPEED_PROP, g_PhysBase[client]);
		g_PhysTouched[client] = false;
		return;
	}
	float want = g_PhysBase[client] * mult;
	if (!Physics_Near(cur, want))
		SetEntPropFloat(client, Prop_Data, PHYS_SPEED_PROP, want);
	g_PhysSet[client] = want;
	g_PhysTouched[client] = true;
}

void Physics_ApplyGravity(int client, float mult)
{
	float cur = GetEntityGravity(client);
	if (!g_GravTouched[client] || !Physics_Near(cur, g_GravSet[client]))
		g_GravBase[client] = cur > 0.0 ? cur : 1.0;   // 0 means normal gravity
	if (Physics_Near(mult, 1.0))
	{
		if (g_GravTouched[client])
			SetEntityGravity(client, g_GravBase[client]);
		g_GravTouched[client] = false;
		return;
	}
	float want = g_GravBase[client] * mult;
	if (!Physics_Near(cur, want))
		SetEntityGravity(client, want);
	g_GravSet[client] = want;
	g_GravTouched[client] = true;
}

void Physics_Apply()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i))
		{
			g_PhysTouched[i] = false;
			g_GravTouched[i] = false;
			continue;
		}
		bool alive = IsPlayerAlive(i);
		Physics_ApplySpeed(i, alive ? Physics_SpeedMult(i) : 1.0);
		Physics_ApplyGravity(i, alive ? Physics_GravityMult(i) : 1.0);
	}
}
