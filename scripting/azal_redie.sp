/*
Azalty's Redie System - by azalty (STEAM_0:1:57298004)

Credits:
- https://forums.alliedmods.net/showthread.php?p=2198357 : lots of code, ideas, methods
*/

#include <sourcemod>
#include <convar_class>
#include <sdktools>
#include <sdkhooks>
#include <cstrike>
#include <azalib>
#include <colorvariables>

#define PLUGIN_VERSION "0.8.3 BETA"

#define LIFE_ALIVE 0
#define LIFE_DYING 1
#define LIFE_DEAD 2
#define LIFE_RESPAWNABLE 3
#define	LIFE_DISCARDBODY 4
#define COLLISION_GROUP_DEBRIS_TRIGGER 2
#define MAXENTITIES 2048

#define TP_COOLDOWN 0.2

bool g_bIsGhost[MAXPLAYERS + 1];
int g_iCommandUsages[MAXPLAYERS + 1];
int g_iHealth[MAXPLAYERS + 1];
int g_iLastRedie[MAXPLAYERS + 1];
int g_bStripWeapons[MAXPLAYERS + 1];
float g_fLastTP[MAXPLAYERS + 1];

bool g_bConfigsExecuted;
char g_sHookEntities[30][40];

Convar cvarCommands;
Convar cvarTriggerHurt;
Convar cvarDamage;
Convar cvarMaxUsage;
Convar cvarCooldown;
Convar cvarTriggerTeleport;
Convar cvarBlockDoor;
Convar cvarBlockDoorNotify;
Convar cvarBlockKnife;
Convar cvarBlockKnifeNotify;

Convar cvarLogging;

enum struct Preferences
{
	bool noclip;
	bool trigger_teleport;
	
	void Reset()
	{
		this.noclip = false;
		this.trigger_teleport = true;
	}
}

Preferences g_ePreferences[MAXPLAYERS + 1];

public Plugin myinfo =
{
	name = "Azalty's Redie System",
	author = "azalty",
	description = "A redie plugin made to be used in any CS:GO gamemod, without any bugs and well supported. Originally made for jailbreak.",
	version = PLUGIN_VERSION,
	url = "github.com/azalty"
};

public void OnPluginStart()
{
	// Convars
	cvarCommands = new Convar("azal_redie_commands", "sm_redie,sm_ghost", "A list of all the commands you can use to become a ghost.\nIf multiple, put a comma between each one.\nMax: 10 commands.");
	cvarTriggerHurt = new Convar("azal_redie_triggerhurt", "0", "0 = trigger_hurt works normally\n1 = trigger_hurt don't do any damage to ghosts\n2 = trigger_hurt instantly puts ghosts out of the ghost mode", _, true, 0.0, true, 2.0);
	cvarDamage = new Convar("azal_redie_damage", "1", "0 = ghosts are immune to any type of damage\n1 = ghosts take damage normally, and when their health reaches 0, they are removed from the ghost mode", _, true, 0.0, true, 1.0);
	cvarMaxUsage = new Convar("azal_redie_maxusage", "0", "Maximum times you can do the redie command per round.\n0 = no limit", _, true, 0.0);
	cvarCooldown = new Convar("azal_redie_cooldown", "3", "Number of seconds to wait between two Ghost respawns.\n0 = no cooldown", _, true, 0.0);
	cvarTriggerTeleport = new Convar("azal_redie_triggerteleport", "0", "0 = trigger_teleport works normally\n1 = trigger_teleport doesn't get triggered, but an experimental method is used to teleport the Ghost (might not be accurate)\n2 = block trigger_teleport for Ghosts", _, true, 0.0, true, 2.0);
	cvarBlockDoor = new Convar("azal_redie_blockdoor", "1", "When a Ghost blocks a door:\n0 = don't do anything\n1 = kill them\n2 = make them respawn as a Ghost (unghost then ghost again)", _, true, 0.0, true, 2.0);
	cvarBlockDoorNotify = new Convar("azal_redie_blockdoor_notify", "1", "If azal_redie_blockdoor is other than 0, and a Ghost blocks a door:\n0 = don't send a message to everyone\n1 = send a message to everyone in the server saying that the Ghost player is blocking a door", _, true, 0.0, true, 1.0);
	cvarBlockKnife = new Convar("azal_redie_blockknife", "1", "When a Ghost blocks a knife attack:\n0 = don't do anything\n1 = kill them\n2 = make them respawn as a Ghost (unghost then ghost again)", _, true, 0.0, true, 2.0);
	cvarBlockKnifeNotify = new Convar("azal_redie_blockknife_notify", "1", "If azal_redie_blockknife is other than 0, and a Ghost blocks a knife attack:\n0 = don't send a message to everyone\n1 = send a message to everyone in the server saying that the Ghost player blocked a knife attack", _, true, 0.0, true, 1.0);
	
	cvarLogging = new Convar("azal_redie_logging", "1", "0 = minimum logs (important events only, such as if a Ghost blocked a door)\n1 = normal logs (actions experimental hooks, config load confirmation)\n2 = dev logs (a lot of infos)", _, true, 0.0, true, 2.0);
	Convar.CreateConfig("azal_redie");
	
	// Commands
	RegAdminCmd("sm_ghost_test", Cmd_GhostTest, ADMFLAG_CHANGEMAP, "Prints test infos - Redie Ghost");
	
	// Events
	HookEvent("round_start", OnRoundStart);
	HookEvent("round_start", OnRoundEndPre, EventHookMode_Pre);
	HookEvent("player_death", OnPlayerDeathPre, EventHookMode_Pre);
	AddNormalSoundHook(OnNormalSound);
	HookEntityOutput("func_door", "OnBlockedOpening", OnDoorBlocked);
	HookEntityOutput("func_door", "OnBlockedClosing", OnDoorBlocked);
	HookEntityOutput("func_door_rotating", "OnBlockedOpening", OnDoorBlocked);
	HookEntityOutput("func_door_rotating", "OnBlockedClosing", OnDoorBlocked);
	
	// Other
	LoadTranslations("azal_redie.phrases");
	
	// KeyValues
	char kvPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, kvPath, sizeof(kvPath), "configs/azal_redie.cfg"); // Get cfg file
	KeyValues kv = new KeyValues("azal_redie");
	if (!kv.ImportFromFile(kvPath))
		LogMessage("The configs/azal_redie.cfg config file doesn't exist. Most entities, including triggers, won't be blocked!");
	else
	{
		// KeyValues: Cache BlockEntities for quick access
		if (!kv.JumpToKey("BlockEntities"))
			SetFailState("The BlockEntities section is not present in configs/azal_redie.cfg");
		if (kv.GotoFirstSubKey(false))
		{
			int index;
			char section[40];
			do
			{
				kv.GetSectionName(section, sizeof(section));
				if (cvarLogging.IntValue >= 1)
					LogMessage("Blocked %s from config!", section);
				strcopy(g_sHookEntities[index], sizeof(g_sHookEntities[]), section);
				index++;
			}
			while (kv.GotoNextKey(false));
		}
	}
	delete kv;
	
	// Players late load handling
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i))
			OnClientPutInServer(i);
	}
	
	LogMessage("Azal Redie v"...PLUGIN_VERSION..." loaded!");
}

public void OnConfigsExecuted()
{
	if (g_bConfigsExecuted)
		return;
	g_bConfigsExecuted = true;
	
	char buffer[1000];
	cvarCommands.GetString(buffer, sizeof(buffer));
	char sCommands[10][40] // 10 commands of 40 characters max
	int amount = ExplodeString(buffer, ",", sCommands, sizeof(sCommands), sizeof(sCommands[]));
	for (int i; i < amount; i++)
	{
		RegConsoleCmd(sCommands[i], Cmd_Ghost, "Become a ghost and play after you die, redie mechanic.");
	}
	
	// Late load handling
	for (int i = MAXPLAYERS + 1; i <= MAXENTITIES; i++)
	{
		if (!IsValidEntity(i))
			continue;
		GetEntityClassname(i, buffer, sizeof(buffer));
		OnEntityCreated(i, buffer);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_WeaponCanUse, OnWeaponCanUse);
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_TraceAttack, OnTraceAttack);
}

public void OnClientDisconnect(int client)
{
	g_bIsGhost[client] = false;
	g_iCommandUsages[client] = 0;
	g_iLastRedie[client] = 0;
	g_fLastTP[client] = 0.0;
	g_bStripWeapons[client] = false;
}

Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	if (!g_bIsGhost[victim])
		return Plugin_Continue;
	
	if (!cvarDamage.BoolValue || (0 < attacker <= MaxClients)) // If damage comes from another player, don't take any of it.
		return Plugin_Handled; // Don't do any damage
	
	g_iHealth[victim] -= AzaLib_RoundHalfAwayZero(damage);
	
	if (g_iHealth[victim] <= 0)
		UnGhost(victim);
	else
	{
		if (g_iHealth[victim] > 100)
			g_iHealth[victim] = 100; // Prevents the ghost from being healed over 100HPs
		SetEntityHealth(victim, g_iHealth[victim]);
	}
	
	return Plugin_Handled;
}

Action OnWeaponCanUse(int client, int weapon)
{
	if (!g_bIsGhost[client])
		return Plugin_Continue;
	
	if (g_bStripWeapons[client])
		RemoveEntity(weapon);
	return Plugin_Handled; // Prevents ghosts from equipping weapons on the floor
}

Action OnSetTransmit(int entity, int client)
{
	// entity is asking if they should transmit themselves to client
	if (!g_bIsGhost[entity] || entity == client)
		return Plugin_Continue;
	
	return Plugin_Handled; // Hide, and don't transmit the ghost, making them invisible.
}

Action OnTraceAttack(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &ammotype, int hitbox, int hitgroup)
{
	if (!IsValidEntity(victim) || !g_bIsGhost[victim])
		return Plugin_Continue;
	
	if (cvarBlockKnife.IntValue >= 1)
	{
		if (1 <= attacker <= MaxClients)
			LogMessage("%L blocked the knife attack of %L", victim, attacker);
		else
			LogMessage("%L blocked the knife attack of an unknown player", victim);
		
		UnGhost(victim);
		if (cvarBlockKnife.IntValue == 2)
			Ghost(victim);
		
		char buffer[200];
		GetPhrase("Other_KnifeBlock", buffer, sizeof(buffer), victim);
		CPrintToChat(victim, buffer);
		if (cvarBlockKnifeNotify.BoolValue)
		{
			GetClientName(victim, buffer, sizeof(buffer));
			Format(buffer, sizeof(buffer), "%T%T", "Prefix_Chat", LANG_SERVER, "Other_KnifeBlock_Public", LANG_SERVER, buffer);
			CPrintToChatAll(buffer);
		}
	}
	return Plugin_Handled; // Bullets go through Ghosts.
}

Action OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		g_iCommandUsages[i] = 0;
		g_iLastRedie[i] = 0;
		g_fLastTP[i] = 0.0;
	}
}

Action OnRoundEndPre(Event event, const char[] name, bool dontBroadcast)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (g_bIsGhost[i])
			UnGhost(i, true);
	}
}

Action OnPlayerDeathPre(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	if (!g_bIsGhost[client])
		return Plugin_Continue;
	
	// Remove the ragdoll/dead body
	int entity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
	if (IsValidEntity(entity))
		RemoveEntity(entity);
	
	return Plugin_Handled; // Don't trigger the death notification
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if (!g_bConfigsExecuted)
		return; // Don't do anything. When configs are loaded, OnEntityExecuted will be called again.
	
	int index;
	while (g_sHookEntities[index][0] != '\0') // If the string is NOT empty
	{
		if (StrEqual(classname, g_sHookEntities[index], false))
		{
			SDKHook(entity, SDKHook_Touch, BlockHook);
			SDKHook(entity, SDKHook_StartTouch, BlockHook);
			SDKHook(entity, SDKHook_EndTouch, BlockHook);
			return;
		}
		index++;
	}
	
	// Special hooks
	if (StrEqual(classname, "trigger_teleport"))
	{
		switch (cvarTriggerTeleport.IntValue)
		{
			// case 0: don't do anything
			case 1:
			{
				SDKHook(entity, SDKHook_Touch, TriggerTeleportHook);
				SDKHook(entity, SDKHook_StartTouch, TriggerTeleportHook);
				SDKHook(entity, SDKHook_EndTouch, TriggerTeleportHook);
			}
			case 2:
			{
				SDKHook(entity, SDKHook_Touch, BlockHook);
				SDKHook(entity, SDKHook_StartTouch, BlockHook);
				SDKHook(entity, SDKHook_EndTouch, BlockHook);
			}
		}
	}
	else if (StrEqual(classname, "trigger_hurt"))
	{
		SDKHook(entity, SDKHook_Touch, TriggerHurtHook);
		SDKHook(entity, SDKHook_StartTouch, TriggerHurtHook);
		SDKHook(entity, SDKHook_EndTouch, TriggerHurtHook);
	}
}

Action BlockHook(int entity, int other)
{
	if (! ((0 < other <= MaxClients) && g_bIsGhost[other]) )
		return Plugin_Continue;
	
	return Plugin_Handled; // Blocks collision with the entity, not activating it.
}

// Handles the event, but also teleports the player manually.
Action TriggerTeleportHook(int entity, int other)
{
	if (!(0 < other <= MaxClients) || !g_bIsGhost[other])
		return Plugin_Continue;
	
	if (g_fLastTP[other] > GetGameTime() - TP_COOLDOWN) // The player teleported less than 10 ticks ago. Don't do anything to prevent huge calculations and multiple TPs.
		return Plugin_Handled;
	
	if (!g_ePreferences[other].trigger_teleport) // The player disabled teleport triggers
		return Plugin_Handled;
	
	g_fLastTP[other] = GetGameTime();
	// Teleport the player to the destination
	// KeyValues are Prop_Data
	if (cvarLogging.IntValue == 2)
		LogMessage("trigger_teleport test");
	// https://github.com/scen/ionlib/blob/master/src/sdk/hl2_csgo/game/server/triggers.cpp#L2433
	char sEntityName[40];
	if (HasEntProp(entity, Prop_Data, "m_target"))
		GetEntPropString(entity, Prop_Data, "m_target", sEntityName, sizeof(sEntityName)); // Get the "Remote Destination"
	else
		return Plugin_Handled;
	
	if (cvarLogging.IntValue == 2)
		LogMessage("has target: %s", sEntityName);
	// TODO: Handle "Local Destination Landmark": Prop_Data "m_iLandmark"
	
	char sEntityNameTemp[40];
	//GetEntPropString(entity, Prop_Send, "m_iName", sEntityName, sizeof(sEntityName));
	ArrayList hDestinationsArray = new ArrayList();
	
	// List all "info_teleport_destination"
	int lastEntity = -1;
	while ((lastEntity = FindEntityByClassname(lastEntity, "info_teleport_destination")) != -1)
	{
		GetEntPropString(lastEntity, Prop_Send, "m_iName", sEntityNameTemp, sizeof(sEntityNameTemp));
		if (!StrEqual(sEntityNameTemp, sEntityName))
			continue;
		
		hDestinationsArray.Push(lastEntity);
	}
	
	// List all "info_target"
	lastEntity = -1;
	while ((lastEntity = FindEntityByClassname(lastEntity, "info_target")) != -1)
	{
		GetEntPropString(lastEntity, Prop_Send, "m_iName", sEntityNameTemp, sizeof(sEntityNameTemp));
		if (!StrEqual(sEntityNameTemp, sEntityName))
			continue;
		
		hDestinationsArray.Push(lastEntity);
	}
	
	// Select a random destination from the list
	int random = AzaLib_RandomInt(0, hDestinationsArray.Length - 1);
	lastEntity = hDestinationsArray.Get(random);
	delete hDestinationsArray;
	// "lastEntity" is our chosen destination
	
	// Get the destination and teleport the player to it
	float pos[3];
	GetEntPropVector(lastEntity, Prop_Send, "m_vecOrigin", pos); // retrieves the position of the entity
	TeleportEntity(other, pos, NULL_VECTOR, NULL_VECTOR);
	
	if (cvarLogging.IntValue >= 1)
		LogMessage("Teleported %L", other);
	
	return Plugin_Handled; // Blocks collision with the entity, not activating it.
}

Action TriggerHurtHook(int entity, int other)
{
	if (!(0 < other <= MaxClients) || !g_bIsGhost[other])
		return Plugin_Continue;
	
	switch (cvarTriggerHurt.IntValue)
	{
		case 0:
		{
			if (g_ePreferences[other].noclip) // If the ghost is in noclip, don't deal any damage
				return Plugin_Handled;
			
			return Plugin_Continue;
		}
		case 1:
		{
			return Plugin_Handled; // Don't do any damage to ghosts
		}
		case 2:
		{
			if (!g_ePreferences[other].noclip)
				UnGhost(other);
			return Plugin_Handled;
		}
	}
	return Plugin_Handled;
}

Action Cmd_GhostTest(int client, int args)
{
	if (!client)
		return Plugin_Handled;
	
	ReplyToCommand(client, "m_CollisionGroup: %i", GetEntProp(client, Prop_Send, "m_CollisionGroup"));
	ReplyToCommand(client, "m_nSolidType: %i", GetEntProp(client, Prop_Data, "m_nSolidType"));
	ReplyToCommand(client, "m_usSolidFlags: %i", GetEntProp(client, Prop_Send, "m_usSolidFlags"));
	ReplyToCommand(client, "m_lifeState: %i", GetEntProp(client, Prop_Send, "m_lifeState"));
	ReplyToCommand(client, "IsPlayerAlive -> %s", IsPlayerAlive(client) ? "true" : "false");
	
	return Plugin_Handled;
}

Action Cmd_Ghost(int client, int args)
{
	if (!client)
	{
		ReplyToCommand(client, "You can't run this command from the server's console!");
		return Plugin_Handled;
	}
	
	int team = GetClientTeam(client);
	if (team != CS_TEAM_CT && team != CS_TEAM_T)
	{
		CReplyToCommand(client, "%t", "Command_MustBeInTeam");
		return Plugin_Handled;
	}
	
	if (!g_bIsGhost[client])
	{
		char buffer[200];
		if (IsPlayerAlive(client))
		{
			GetPhrase("Command_MustBeDead", buffer, sizeof(buffer), client);
			CReplyToCommand(client, buffer);
			return Plugin_Handled;
		}
		if (cvarMaxUsage.BoolValue && g_iCommandUsages[client] >= cvarMaxUsage.IntValue)
		{
			GetPhrase("Command_MaxUsages", buffer, sizeof(buffer), client);
			CReplyToCommand(client, buffer);
			return Plugin_Handled;
		}
		if (g_iLastRedie[client] > GetTime() - cvarCooldown.IntValue) // The player did the command less than Xs ago, ask them to wait.
		{
			GetPhrase("Command_Cooldown", buffer, sizeof(buffer), client);
			CReplyToCommand(client, buffer);
			return Plugin_Handled;
		}
		
		g_iCommandUsages[client]++;
		g_iLastRedie[client] = GetTime();
		// Become ghost
		Ghost(client);
		
		GetPhrase("Command_NowGhost", buffer, sizeof(buffer), client);
		CReplyToCommand(client, buffer);
		ShowRedieMenu(client);
	}
	else
	{
		ShowRedieMenu(client, true);
	}
	return Plugin_Handled;
}

void Ghost(int client)
{
	g_ePreferences[client].Reset();
	g_bIsGhost[client] = true;
	g_iHealth[client] = 100;
	g_bStripWeapons[client] = true;
	CS_RespawnPlayer(client);
	g_bStripWeapons[client] = false;
	SetEntProp(client, Prop_Send, "m_lifeState", LIFE_DYING); // IsPlayerAlive will return false!
	SetEntProp(client, Prop_Send, "m_CollisionGroup", COLLISION_GROUP_DEBRIS_TRIGGER); // NoBlock: no collisions with other players
	SetEntProp(client, Prop_Send, "m_bHasDefuser", 0);
}

void UnGhost(int client, bool newRound=false)
{
	if (!newRound)
	{
		SetEntProp(client, Prop_Send, "m_lifeState", LIFE_ALIVE);
		SDKHooks_TakeDamage(client, 0, 0, 5000.0);
		// There is a cooldown on suicides: ForcePlayerSuicide()
		if (IsPlayerAlive(client))
			ForcePlayerSuicide(client);
	}
	g_bIsGhost[client] = false;
}

public Action OnPlayerRunCmd(int client, int& buttons, int& impulse, float vel[3], float angles[3], int& weapon, int& subtype, int& cmdnum, int& tickcount, int& seed, int mouse[2])
{
	if (!g_bIsGhost[client])
		return Plugin_Continue;
	
	if (buttons & IN_USE) // If the player wants to USE
		buttons = buttons ^ IN_USE; // Toggle the USE bit, making it 0, and thus disabling the USE action
	return Plugin_Continue;
}

Action OnNormalSound(int clients[MAXPLAYERS], int& numClients, char sample[PLATFORM_MAX_PATH], int& entity, int& channel, float& volume, int& level, int& pitch, int& flags, char soundEntry[PLATFORM_MAX_PATH], int& seed)
{
	if (!(0 < entity <= MaxClients))
		return Plugin_Continue;
	
	if (g_bIsGhost[entity])
		return Plugin_Stop; // mute every sound coming from Ghosts
	
	return Plugin_Continue;
}

void ShowRedieMenu(int client, bool force=false)
{
	char buffer[200];
	if (!force && GetClientMenu(client) != MenuSource_None)
	{
		GetPhrase("Menu_AlreadyOpen", buffer, sizeof(buffer), client);
		CReplyToCommand(client, buffer);
		return;
	}
	
	Menu menu = new Menu(RedieMenu);
	menu.SetTitle("%T", "Menu_Title", client);
	
	//if (GetEntProp(client, Prop_Send, "movetype") == view_as<int>(MOVETYPE_NOCLIP))
	if (g_ePreferences[client].noclip)
		FormatEx(buffer, sizeof(buffer), "%T", "Menu_DisableNoclip", client);
	else
		FormatEx(buffer, sizeof(buffer), "%T", "Menu_EnableNoclip", client);
	menu.AddItem("noclip", buffer);
	
	if (cvarTriggerTeleport.IntValue == 1)
	{
		if (g_ePreferences[client].trigger_teleport)
			FormatEx(buffer, sizeof(buffer), "%T", "Menu_DisableTriggerTeleport", client);
		else
			FormatEx(buffer, sizeof(buffer), "%T", "Menu_EnableTriggerTeleport", client);
		menu.AddItem("toggle_trigger_teleport", buffer);
	}
	
	FormatEx(buffer, sizeof(buffer), "%T", "Menu_Stop", client);
	menu.AddItem("redie", buffer);
	
	menu.Display(client, MENU_TIME_FOREVER);
}

int RedieMenu(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_Select:
		{
			if (!g_bIsGhost[param1])
				return 0;
			
			char buffer[200];
			menu.GetItem(param2, buffer, sizeof(buffer));
			if (StrEqual(buffer, "noclip"))
			{
				//if (GetEntProp(param1, Prop_Send, "movetype") == view_as<int>(MOVETYPE_NOCLIP))
				if (g_ePreferences[param1].noclip)
				{
					SetEntProp(param1, Prop_Send, "movetype", MOVETYPE_WALK);
					GetPhrase("Menu_NoclipDisabled", buffer, sizeof(buffer), param1);
				}
				else
				{
					SetEntProp(param1, Prop_Send, "movetype", MOVETYPE_NOCLIP);
					GetPhrase("Menu_NoclipEnabled", buffer, sizeof(buffer), param1);
				}
				g_ePreferences[param1].noclip = !g_ePreferences[param1].noclip;
				
				ShowRedieMenu(param1);
			}
			else if (StrEqual(buffer, "toggle_trigger_teleport"))
			{
				g_ePreferences[param1].trigger_teleport = !g_ePreferences[param1].trigger_teleport
				if (g_ePreferences[param1].trigger_teleport)
					GetPhrase("Menu_TriggerTeleportEnabled", buffer, sizeof(buffer), param1);
				else
					GetPhrase("Menu_TriggerTeleportDisabled", buffer, sizeof(buffer), param1);
				
				ShowRedieMenu(param1);
			}
			else // "redie"
			{
				GetPhrase("Menu_NoLongerGhost", buffer, sizeof(buffer), param1);
				
				UnGhost(param1);
			}
			CPrintToChat(param1, buffer);
		}
		case MenuAction_Cancel:
		{
			if (param2 != MenuCancel_Interrupted && param2 != MenuCancel_Exit)
				return 0;
			
			char buffer[200];
			GetPhrase("Menu_Remind", buffer, sizeof(buffer), param1);
			CPrintToChat(param1, buffer);
		}
		case MenuAction_End:
		{
			delete menu;
		}
	}
	return 0;
}

void GetPhrase(char[] phrase, char[] buffer, int bufferSize, int target=LANG_SERVER)
{
	FormatEx(buffer, bufferSize, "%T%T", "Prefix_Chat", target, phrase, target);
}

void OnDoorBlocked(const char[] output, int caller, int activator, float delay)
{
	if (!cvarBlockDoor.BoolValue)
		return;
	
	if (!(0 < activator <= MaxClients) || !g_bIsGhost[activator])
		return;
	
	LogMessage("%L blocked a door", activator);
	UnGhost(activator);
	char buffer[200];
	GetPhrase("Other_DoorBlock", buffer, sizeof(buffer), activator);
	CPrintToChat(activator, buffer);
	
	if (cvarBlockDoor.IntValue == 2)
		Ghost(activator);
	
	if (cvarBlockDoorNotify.BoolValue)
	{
		GetClientName(activator, buffer, sizeof(buffer));
		Format(buffer, sizeof(buffer), "%T%T", "Prefix_Chat", LANG_SERVER, "Other_DoorBlock_Public", LANG_SERVER, buffer);
		CPrintToChatAll(buffer);
	}
}