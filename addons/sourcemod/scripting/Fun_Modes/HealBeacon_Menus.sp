/*
    (). FunModes V2:

    @file           HealBeacon_Menus.sp
    @Usage          Menu Functions for the HealBeacon mode.
*/

#pragma semicolon 1
#pragma newdecls required

int g_iClientMenuUserId[MAXPLAYERS + 1] = { -1, ... };

/* The color names shown to the players (phrases), in the order of g_ColorsList */
static const char g_sHBColorPhrases[][] =
{
	"HealBeacon_ColorWhite",
	"HealBeacon_ColorRed",
	"HealBeacon_ColorLime",
	"HealBeacon_ColorBlue",
	"HealBeacon_ColorYellow",
	"HealBeacon_ColorCyan",
	"HealBeacon_ColorGold"
};

stock void HealBeacon_DisplayMainMenu(int client)
{
	Menu menu = new Menu(MainMenu_Handler);
	menu.SetTitle("%T", "HealBeacon_MenuTitle", client);

	char line[128];
	if (g_aHBPlayers)
	{
		int count = 0;
		for (int i = 0; i < g_aHBPlayers.Length; i++)
		{
			int random = g_aHBPlayers.Get(i);
			if (!IsClientInGame(random) || !IsPlayerAlive(random))
				continue;
	
			char info[32], buffer[64];
			Format(info, sizeof(info), "%d", GetClientUserId(random));
			Format(buffer, sizeof(buffer), "%N", random);
	
			menu.AddItem(info, buffer);
			count++;
		}
	
		if (count <= 0)
		{
			FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuNone", client);
			menu.AddItem("", line, ITEMDRAW_DISABLED);
		}
	}

	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuChoose", client);
	menu.AddItem("choose", line);

	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuClearChosen", client, g_aHB_Chosen.Length);
	menu.AddItem("clear", line, g_aHB_Chosen.Length ? ITEMDRAW_DEFAULT : ITEMDRAW_DISABLED);

	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuSettings", client);
	menu.AddItem("option2", line);
	FormatEx(line, sizeof(line), "%T", "FunModes_ShowCvars", client);
	menu.AddItem("option3", line);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

/* Chosen carriers get a heal beacon every round until they leave, and are never picked as mother zombie */
void HealBeacon_ChooseMenu(int client)
{
	Menu menu = new Menu(HealBeacon_ChooseMenu_Handler);
	menu.SetTitle("%T\n ", "HealBeacon_ChooseTitle", client);

	char info[12], line[128], chosen[32], beacon[32];
	FormatEx(chosen, sizeof(chosen), " %T", "FunModes_TagChosen", client);
	FormatEx(beacon, sizeof(beacon), " %T", "HealBeacon_TagBeacon", client);
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsClientSourceTV(i))
			continue;

		IntToString(GetClientUserId(i), info, sizeof(info));
		FormatEx(line, sizeof(line), "%N%s%s", i, HealBeacon_IsChosen(i) ? chosen : "", g_BeaconPlayersData[i].hasHealBeacon ? beacon : "");
		menu.AddItem(info, line);
	}

	if (!menu.ItemCount)
	{
		FormatEx(line, sizeof(line), "%T", "FunModes_NobodyOnServer", client);
		menu.AddItem("", line, ITEMDRAW_DISABLED);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int HealBeacon_ChooseMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;

		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				HealBeacon_DisplayMainMenu(param1);
		}

		case MenuAction_Select:
		{
			char info[12];
			menu.GetItem(param2, info, sizeof(info));

			int target = GetClientOfUserId(StringToInt(info));
			if (target)
				HealBeacon_ToggleChosen(param1, target);
			else
				CPrintToChat(param1, "%s %t", THIS_MODE_INFO.tag, "FunModes_PlayerLeft");

			HealBeacon_ChooseMenu(param1);
		}
	}

	return 0;
}

public int MainMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				DisplayModeInfo(param1, g_iPreviousModeIndex[param1]);
		}
		case MenuAction_Select:
		{
			char buffer[64];
			menu.GetItem(param2, buffer, sizeof(buffer));
			if (strcmp(buffer, "choose") == 0)
			{
				HealBeacon_ChooseMenu(param1);
				return 0;
			}
			else if (strcmp(buffer, "clear") == 0)
			{
				g_aHB_Chosen.Clear();
				CPrintToChatAll("%s %t", THIS_MODE_INFO.tag, "HealBeacon_ChosenCleared");
				LogAction(param1, -1, "\"%L\" cleared the chosen heal beacon carriers", param1);
				HealBeacon_DisplayMainMenu(param1);
				return 0;
			}
			else if (strcmp(buffer, "option2") == 0)
			{
				HealBeacon_DisplaySettingsMenu(param1);
				return 0;
			}
			else if (strcmp(buffer, "option3") == 0)
			{
				ShowCvarsInfo(param1, THIS_MODE_INFO);
				return 0;
			}

			int userid = StringToInt(buffer);
			int random = GetClientOfUserId(userid);
			if (!random)
			{
				CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "PlayerNotValid", param1);
				return 0;
			}

			if (!g_BeaconPlayersData[random].hasHealBeacon)
			{
				CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_PlayerIsNot", param1);
				return 0;
			}

			HealBeacon_DisplayActionsMenu(param1, random);
		}
	}

	return 0;
}

/* THE SETTINGS MENUS */
stock void HealBeacon_DisplaySettingsMenu(int client)
{
	Menu menu = new Menu(SettingsMenu_Handler);
	char title[128];
	Format(title, sizeof(title), "%T", "HealBeacon_MenuSettings", client);
	menu.SetTitle(title);

	char line[128];
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuDamage", client);
	menu.AddItem("0", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuHeal", client);
	menu.AddItem("1", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuTimer", client);
	menu.AddItem("2", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuBetterDamage", client);
	menu.AddItem("3", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuDefaultColor", client);
	menu.AddItem("4", line);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int SettingsMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				HealBeacon_DisplayMainMenu(param1);
		}

		case MenuAction_Select:
		{
			switch(param2)
			{
				case 0:
				{
					HealBeacon_DisplayBeaconDamageMenu(param1);
				}
				case 1:
				{
					HealBeacon_DisplayBeaconHealMenu(param1);
				}
				case 2:
				{
					HealBeacon_DisplayBeaconTimerMenu(param1);
				}
				case 3:
				{
					if (g_bIsBetterDamageModeOn)
					{
						g_bIsBetterDamageModeOn = false;
						CPrintToChat(param1, "%s %t", THIS_MODE_INFO.tag, "HealBeacon_BetterDamageOff");
					}
					else
					{
						g_bIsBetterDamageModeOn = true;
						CPrintToChat(param1, "%s %t", THIS_MODE_INFO.tag, "HealBeacon_BetterDamageOn");
					}
				}
				case 4:
				{
					HealBeacon_DisplayBeaconDefaultColorMenu(param1);
				}
			}
		}
	}

	return 0;
}

/* BEACON DAMAGE MENU */
stock void HealBeacon_DisplayBeaconDamageMenu(int client)
{
	Menu menu = new Menu(BeaconDamageMenu_Handler);
	char title[512];
	Format(title, sizeof(title), "%T", "HealBeacon_DamageTitle", client, g_fHB_BeaconDamage);
	menu.SetTitle(title);

	menu.AddItem("1", "1");
	menu.AddItem("2", "2");
	menu.AddItem("5", "5");
	menu.AddItem("7", "7");
	menu.AddItem("8", "8");
	menu.AddItem("10", "10");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BeaconDamageMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				HealBeacon_DisplaySettingsMenu(param1);
		}
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int num = StringToInt(buffer);

			_FUNMODES_CVAR_SET_VALUE(THIS_MODE_INFO.index, HB_CONVAR_BEACON_DAMAGE, Float, float(num));

			CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_DamageChange", param1, float(num));
			HealBeacon_DisplayBeaconDamageMenu(param1);
		}
	}

	return 0;
}

/* BEACON HEAL MENU */
stock void HealBeacon_DisplayBeaconHealMenu(int client)
{
	Menu menu = new Menu(BeaconHealMenu_Handler);
	char title[512];
	Format(title, sizeof(title), "%T", "HealBeacon_HealTitle", client, g_iHB_BeaconHeal);
	menu.SetTitle(title);

	for (int i = 1; i <= 7; i++)
	{
		char buffer[5];
		Format(buffer, sizeof(buffer), "%d", i);
		menu.AddItem(buffer, buffer);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BeaconHealMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				HealBeacon_DisplaySettingsMenu(param1);
		}
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int num = StringToInt(buffer);

			_FUNMODES_CVAR_SET_VALUE(THIS_MODE_INFO.index, HB_CONVAR_BEACON_HEAL, Int, num);

			CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_HealChange", param1, num);
			HealBeacon_DisplayBeaconHealMenu(param1);
		}
	}

	return 0;
}

/* BEACON TIMER MENU */
stock void HealBeacon_DisplayBeaconTimerMenu(int client)
{
	Menu menu = new Menu(BeaconTimerMenu_Handler);
	char title[512];
	Format(title, sizeof(title), "%T", "HealBeacon_TimerTitle", client);
	menu.SetTitle(title);

	menu.AddItem("10", "10");
	menu.AddItem("20", "20");
	menu.AddItem("25", "25");
	menu.AddItem("30", "30");
	menu.AddItem("40", "40");
	menu.AddItem("60", "60");

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BeaconTimerMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				HealBeacon_DisplaySettingsMenu(param1);
		}
		case MenuAction_Select:
		{
			char buffer[32];
			menu.GetItem(param2, buffer, sizeof(buffer));
			int num = StringToInt(buffer);

			_FUNMODES_CVAR_SET_VALUE(THIS_MODE_INFO.index, HB_CONVAR_BEACON_TIMER, Float, float(num));

			CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_TimerChange", param1, num);
			HealBeacon_DisplaySettingsMenu(param1);
		}
	}

	return 0;
}

/* BEACON DEFAULT COLOR MENU */
stock void HealBeacon_DisplayBeaconDefaultColorMenu(int client)
{
	Menu menu = new Menu(BeaconDefaultColorMenu_Handler);

	/* CHECK DEFAULT COLOR NAME */
	char colorName[32];
	for (int i = 0; i < sizeof(g_ColorsList); i++)
	{
		char buffers[3][5];
		ExplodeString(g_ColorsList[i].rgb, " ", buffers, 3, sizeof(buffers[]));

		if (StringToInt(buffers[0]) == g_ColorDefault[0] && StringToInt(buffers[1]) == g_ColorDefault[1]
		&& StringToInt(buffers[2]) == g_ColorDefault[2] && 255 == g_ColorDefault[3]) {
			FormatEx(colorName, sizeof(colorName), "%T", g_sHBColorPhrases[i], client);
			break;
		}
	}

	char title[256];
	Format(title, sizeof(title), "%T", "HealBeacon_DefaultColorTitle", client, colorName);
	menu.SetTitle(title);

	for (int i = 0; i < sizeof(g_ColorsList); i++)
	{
		char index[3];
		IntToString(i, index, sizeof(index));
		FormatEx(colorName, sizeof(colorName), "%T", g_sHBColorPhrases[i], client);
		menu.AddItem(index, colorName);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BeaconDefaultColorMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:{
			if (param2 == MenuCancel_ExitBack)
				HealBeacon_DisplaySettingsMenu(param1);
		}
		case MenuAction_Select:
		{
			char info[128];
			menu.GetItem(param2, info, sizeof(info));

			int index = StringToInt(info);
			FM_Color myColor; 
			myColor = g_ColorsList[index];

			char buffers[3][5]; // the splitted buffers from menu item
			ExplodeString(myColor.rgb, " ", buffers, 3, sizeof(buffers[]));

			g_ColorDefault[0] = StringToInt(buffers[0]);
			g_ColorDefault[1] = StringToInt(buffers[1]);
			g_ColorDefault[2] = StringToInt(buffers[2]);
			g_ColorDefault[3] = 255;

			char colorName[32];
			FormatEx(colorName, sizeof(colorName), "%T", g_sHBColorPhrases[index], param1);
			CPrintToChat(param1, "%s %t", THIS_MODE_INFO.tag, "HealBeacon_DefaultColorChange", myColor.name, colorName);
			HealBeacon_DisplayBeaconDefaultColorMenu(param1);
		}
	}

	return 0;
}

/* ACTIONS MENU */
stock void HealBeacon_DisplayActionsMenu(int client, int random)
{
	Menu menu = new Menu(ActionsMenu_Handler);

	g_iClientMenuUserId[client] = GetClientUserId(random);
	char title[128], buffer[32];
	Format(title, sizeof(title), "%T", "HealBeacon_ActionsTitle", client, random);
	menu.SetTitle(title);

	Format(buffer, sizeof(buffer), "%d", GetClientUserId(random));

	char line[128];
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuRepick", client);
	menu.AddItem("", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuColor", client);
	menu.AddItem("", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuDistance", client);
	menu.AddItem("", line);

	char light[128];
	Format(light, sizeof(light), "%T", g_BeaconPlayersData[random].hasNeon ? "HealBeacon_MenuLightOff" : "HealBeacon_MenuLightOn", client);
	menu.AddItem("", light);

	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuTeleport", client);
	menu.AddItem("", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuBring", client);
	menu.AddItem("", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuRemove", client);
	menu.AddItem("", line);
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuSlay", client);
	menu.AddItem("", line);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ActionsMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
				HealBeacon_DisplayMainMenu(param1);
		}
		case MenuAction_Select:
		{
			int random = GetClientOfUserId(g_iClientMenuUserId[param1]);
			if (!random)
			{
				CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "PlayerNotValid", param1);
				HealBeacon_DisplayMainMenu(param1);
				return 0;
			}

			if (!g_BeaconPlayersData[random].hasHealBeacon)
			{
				CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_PlayerIsNot", param1);
				HealBeacon_DisplayMainMenu(param1);
				return 0;
			}

			switch(param2)
			{
				case 0:
				{
					ReplaceBeacon(param1, random, -1);
					HealBeacon_DisplayMainMenu(param1);
				}
				case 1:
				{
					HealBeacon_DisplayColorsMenu(param1);
				}
				case 2:
				{
					HealBeacon_DisplayBeaconDistanceMenu(param1);
				}
				case 3:
				{
					if (g_BeaconPlayersData[random].hasNeon)
					{
						RemoveNeon(random);
						CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_NeonRemove", param1, random);
					}
					else
					{
						SetClientNeon(random);
						CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_NeonAdd", param1, random);
					}

					HealBeacon_DisplayActionsMenu(param1, random);
				}
				case 4:
				{
					float fOrigin[3], fAngles[3];
					GetClientAbsOrigin(random, fOrigin);
					GetClientAbsAngles(random, fAngles);

					TeleportEntity(param1, fOrigin, fAngles, NULL_VECTOR);
					LogAction(param1, random, "[FunModes-HealBeacon] \"%L\" teleported to \"%L\"(HealBeacon Player)", param1, random);
					HealBeacon_DisplayActionsMenu(param1, random);
				}

				case 5:
				{
					float fOrigin[3], fAngles[3];
					GetClientAbsOrigin(param1, fOrigin);
					GetClientAbsAngles(param1, fAngles);

					TeleportEntity(random, fOrigin, fAngles, NULL_VECTOR);
					LogAction(param1, random, "[FunModes-HealBeacon] \"%L\" brought \"%L\"(HealBeacon Player)", param1, random);
					HealBeacon_DisplayActionsMenu(param1, random);
				}
				case 6:
				{
					RemoveBeacon(param1, random);
					HealBeacon_DisplayMainMenu(param1);
				}
				case 7:
				{
					ForcePlayerSuicide(random);
					LogAction(param1, random, "[FunModes-HealBeacon] \"%L\" slayed \"%L\"(HealBeacon Player)", param1, random);
					CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_Slay", param1, random);
					HealBeacon_DisplayMainMenu(param1);
				}
			}
		}
	}

	return 0;
}

stock void HealBeacon_DisplayColorsMenu(int client)
{
	Menu menu = new Menu(ColorsMenu_Handler);
	int random = GetClientOfUserId(g_iClientMenuUserId[client]);
	if (!random)
		return;

	char title[128];
	Format(title, sizeof(title), "%T", "HealBeacon_ColorsTitle", client, random);
	menu.SetTitle(title);

	for (int i = 0; i < sizeof(g_ColorsList); i++)
	{
		char index[3], colorName[32];
		IntToString(i, index, sizeof(index));
		FormatEx(colorName, sizeof(colorName), "%T", g_sHBColorPhrases[i], client);
		menu.AddItem(index, colorName);
	}

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int ColorsMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				int random = GetClientOfUserId(g_iClientMenuUserId[param1]);
				if (!random)
				{
					HealBeacon_DisplayMainMenu(param1);
					CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "PlayerNotValid", param1);
					return 0;
				}

				HealBeacon_DisplayActionsMenu(param1, random);
			}
		}
		case MenuAction_Select:
		{
			int random = GetClientOfUserId(g_iClientMenuUserId[param1]);
			if (!random)
			{
				CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "PlayerNotValid", param1);
				return 0;
			}

			char info[3];
			menu.GetItem(param2, info, sizeof(info));

			int index = StringToInt(info);
			FM_Color myColor;
			myColor = g_ColorsList[index];

			char buffers[3][5];
			ExplodeString(myColor.rgb, " ", buffers, 3, sizeof(buffers[]));

			int color[4];
			color[0] = StringToInt(buffers[0]);
			color[1] = StringToInt(buffers[1]);
			color[2] = StringToInt(buffers[2]);
			color[3] = 255;

			g_BeaconPlayersData[random].SetColor(color);

			char colorName[32];
			FormatEx(colorName, sizeof(colorName), "%T", g_sHBColorPhrases[index], param1);
			CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_ColorChange", param1, random, myColor.name, colorName);
			LogAction(param1, random, "[FunModes-HealBeacon] \"%L\" changed Beacon and Neon colors of \"%L\" to \"%s\"", param1, random, myColor.name);
			HealBeacon_DisplayColorsMenu(param1);
		}
	}

	return 0;
}

stock void HealBeacon_DisplayBeaconDistanceMenu(int client)
{
	Menu menu = new Menu(BeaconDistanceMenu_Handler);
	int random = GetClientOfUserId(g_iClientMenuUserId[client]);
	if (!random)
		return;

	char title[128];
	Format(title, sizeof(title), "%T", "HealBeacon_DistanceTitle", client, random);
	menu.SetTitle(title);

	menu.AddItem("200", "200");
	menu.AddItem("400", "400");
	menu.AddItem("600", "600");
	menu.AddItem("800", "800");
	menu.AddItem("1000", "1000");
	menu.AddItem("1500", "1500");

	char line[256];
	FormatEx(line, sizeof(line), "%T", "HealBeacon_MenuDistanceHint", client);
	menu.AddItem("Empty", line, ITEMDRAW_DISABLED);

	menu.ExitBackButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int BeaconDistanceMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	switch(action)
	{
		case MenuAction_End:
		{
			delete menu;
		}
		case MenuAction_Cancel:
		{
			if (param2 == MenuCancel_ExitBack)
			{
				int random = GetClientOfUserId(g_iClientMenuUserId[param1]);
				if (!random)
				{
					HealBeacon_DisplayMainMenu(param1);
					CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "PlayerNotValid", param1);
					return 0;
				}

				HealBeacon_DisplayActionsMenu(param1, random);
			}
		}
		case MenuAction_Select:
		{
			int random = GetClientOfUserId(g_iClientMenuUserId[param1]);
			if (!random)
			{
				HealBeacon_DisplayMainMenu(param1);
				CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "PlayerNotValid", param1);
				return 0;
			}

			char info[128];
			menu.GetItem(param2, info, sizeof(info));

			int distance = StringToInt(info);
			g_BeaconPlayersData[random].distance = float(distance);

			CPrintToChat(param1, "%s %T", THIS_MODE_INFO.tag, "HealBeacon_DistanceChange", param1, random, float(distance));
			LogAction(param1, random, "[FunModes-HealBeacon] \"%L\" changed Beacon Distance of \"%L\" to \"%d\"", param1, random, distance);
			HealBeacon_DisplayBeaconDistanceMenu(param1);
		}
	}

	return 0;
}
