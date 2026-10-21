// Butterfingers module of eventmodes.sp.
// modes.sp calls BF_Tick (every second), BF_RoundStart and BF_Stop.
//
// Once the zombies are out, every N seconds a few humans fumble and drop the gun in their hands - they
// have to pick it back up. Map items (weapons with a name on the map) are never dropped.

#if defined _em_butter_included
 #endinput
#endif
#define _em_butter_included

#define BF_TAG "\x07" ... "FFE080[Butterfingers]\x01 "   // kept apart: \x would eat the hex digits

int g_BfEverySteps[] = { 15, 20, 30, 45, 60 };
int g_BfCountSteps[] = { 1, 2, 3, 5, 64 };   // 64 = everyone
char g_BfWhichNames[][] = { "the gun in their hands", "their main gun", "their pistol" };

bool g_BfOn;
int g_BfEvery = 30;
int g_BfCount = 2;
int g_BfWhich = 0;          // 0 active weapon, 1 primary, 2 pistol
float g_BfNext;

bool BF_IsOn()
{
	return g_BfOn;
}

void BF_Stop()
{
	g_BfOn = false;
	g_BfNext = 0.0;
}

void BF_Set(bool on)
{
	BF_Stop();
	g_BfOn = on;
}

void BF_RoundStart()
{
	g_BfNext = 0.0;
	if (g_BfOn)
		PrintToChatAll(BF_TAG ... "Butterfingers is on: hold on to your gun!");
}

// True if the player dropped something.
bool BF_Drop(int client)
{
	int weapon;
	if (g_BfWhich == 1)
		weapon = GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY);
	else if (g_BfWhich == 2)
		weapon = GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY);
	else
		weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
	if (weapon == -1 || !IsValidEntity(weapon))
		return false;
	if (weapon != GetPlayerWeaponSlot(client, CS_SLOT_PRIMARY) && weapon != GetPlayerWeaponSlot(client, CS_SLOT_SECONDARY))
		return false;   // knife or grenade in hand
	if (EM_IsMapItem(weapon))
		return false;
	CS_DropWeapon(client, weapon, true);
	PrintCenterText(client, "BUTTERFINGERS! You dropped your gun!");
	return true;
}

void BF_Wave()
{
	int list[MAXPLAYERS + 1];
	int n = ShuffledHumans(list);
	int dropped = 0;
	for (int k = 0; k < n && dropped < g_BfCount; k++)
		if (BF_Drop(list[k]))
			dropped++;
	if (dropped > 0)
		PrintToChatAll(BF_TAG ... "%d human%s dropped their gun!", dropped, dropped == 1 ? "" : "s");
}

void BF_Tick()
{
	if (HazardDue(g_BfOn, g_BfNext, g_BfEvery))
		BF_Wave();
}

// ---------------------------------------------------------------- menu

void BFMenu(int client)
{
	Menu menu = new Menu(BFHandler);
	char line[64];
	menu.SetTitle(g_BfOn ? "Butterfingers - ON\nStarts when the zombies come\n " : "Butterfingers - OFF\n ");
	menu.AddItem("toggle", g_BfOn ? "Turn Butterfingers OFF" : "Turn Butterfingers ON");
	menu.AddItem("now", "Drop guns now", (g_BfOn && g_RoundLive) ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);
	Format(line, sizeof(line), "Every: %d s", g_BfEvery);
	menu.AddItem("every", line);
	if (g_BfCount >= 64)
		strcopy(line, sizeof(line), "Humans who drop: everyone");
	else
		Format(line, sizeof(line), "Humans who drop: %d", g_BfCount);
	menu.AddItem("count", line);
	Format(line, sizeof(line), "They drop: %s", g_BfWhichNames[g_BfWhich]);
	menu.AddItem("which", line);
	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BFHandler(Menu menu, MenuAction action, int client, int item)
{
	if (action == MenuAction_End)
		delete menu;
	else if (action == MenuAction_Cancel && item == MenuCancel_ExitBack)
		ModeBack(client);
	else if (action == MenuAction_Select && HasAccess(client))
	{
		char info[16];
		menu.GetItem(item, info, sizeof(info));
		if (StrEqual(info, "toggle"))
		{
			BF_Set(!g_BfOn);
			PrintToChatAll(BF_TAG ... "%N turned Butterfingers %s.", client, g_BfOn ? "ON" : "OFF");
			LogAction(client, -1, "\"%L\" turned butterfingers %s", client, g_BfOn ? "on" : "off");
		}
		else if (StrEqual(info, "now"))
			BF_Wave();
		else if (StrEqual(info, "every"))
			g_BfEvery = NextInt(g_BfEverySteps, sizeof(g_BfEverySteps), g_BfEvery);
		else if (StrEqual(info, "count"))
			g_BfCount = NextInt(g_BfCountSteps, sizeof(g_BfCountSteps), g_BfCount);
		else if (StrEqual(info, "which"))
			g_BfWhich = (g_BfWhich + 1) % sizeof(g_BfWhichNames);
		BFMenu(client);
	}
	return 0;
}
