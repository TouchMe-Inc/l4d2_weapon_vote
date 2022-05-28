#include <sourcemod>
#include <sdktools>
#include <builtinvotes>
#include <colors>

#undef REQUIRE_PLUGIN
#include <readyup>

#pragma semicolon 1
#pragma newdecls required


public Plugin myinfo =
{
	name = "Weapon vote",
	author = "TouchMe",
	description = "Issues weapons based on voting results",
	version = "1.0rc"
};


#define TIMER_VOTE_HIDE         15

#define MAX_MENU_TITLE_LENGTH   64
#define MAX_VOTE_MESSAGE_LENGTH 128

#define MAX_WEAPON_DATA_ID      32
#define MAX_WEAPON_DATA_NAME    64
#define MAX_WEAPON_DATA_CMD     32

#define TEAM_SPECTATOR          1
#define TEAM_SURVIVOR           2 

#define IS_VALID_CLIENT(%1)     (%1 > 0 && %1 <= MaxClients)
#define IS_SURVIVOR(%1)         (GetClientTeam(%1) == TEAM_SURVIVOR)
#define IS_SPECTATOR(%1)        (GetClientTeam(%1) == TEAM_SPECTATOR)
#define IS_VALID_INGAME(%1)     (IS_VALID_CLIENT(%1) && IsClientInGame(%1))
#define IS_VALID_SURVIVOR(%1)   (IS_VALID_INGAME(%1) && IS_SURVIVOR(%1))
#define IS_SURVIVOR_ALIVE(%1)   (IS_VALID_SURVIVOR(%1) && IsPlayerAlive(%1))


enum struct WeaponData
{
	ArrayList id;
	ArrayList name;
	ArrayList cmd;
}

int
	g_iVotingItem = 0,
	g_iWeaponDataNum = 0;

bool
	g_bReadyUpAvailable = false,
	g_bRoundIsLive = false;

Menu
	g_hMenu = null;

Handle
	g_hVote = null;

WeaponData
	g_hWeaponData;


public void OnPluginStart()
{
	InitTranslations();

	InitWeaponData();

	ReadWeaponDataFile();	

	InitMenu();

	RegConsoleCmd("sm_wv", Cmd_ShowMenu);

	HookEvent("player_left_start_area", Event_LeftStartArea, EventHookMode_PostNoCopy);
	HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

/**
  * Called before OnPluginStart.
  *
  * @noreturn
  */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();

	if (engine != Engine_Left4Dead2) {
		strcopy(error, err_max, "Plugin only supports Left 4 Dead 2.");
		return APLRes_SilentFailure;
	}

	return APLRes_Success;
}

/**
  * Loads dictionary files. On failure, stops the plugin execution.
  *
  * @noreturn
  */
void InitTranslations() 
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "translations/weapon_vote.phrases.txt");

	if (FileExists(sPath)) {
		LoadTranslations("weapon_vote.phrases");
	} else {
		SetFailState("Path %s not found", sPath);
	}
}

void InitWeaponData()
{
	g_hWeaponData.id = new ArrayList(MAX_WEAPON_DATA_ID);
	g_hWeaponData.name = new ArrayList(MAX_WEAPON_DATA_NAME);
	g_hWeaponData.cmd = new ArrayList(MAX_WEAPON_DATA_CMD);
}

void AddWeaponData(const char[] sId, const char[] sName, const char[] sCmd)
{
	g_hWeaponData.id.PushString(sId);
	g_hWeaponData.name.PushString(sName);
	g_hWeaponData.cmd.PushString(sCmd);

	g_iWeaponDataNum++;
}

/**
  * File reader. Opens and reads lines in config/weapon_vote.ini.
  *
  * @noreturn
  */
void ReadWeaponDataFile()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/weapon_vote.ini");
	
	if (!FileExists(sPath)) {
		SetFailState("Path %s not found", sPath);
	}

	File file = OpenFile(sPath, "rt");
	if (!file)
	{
		SetFailState("Could not open file!");
		return;
	}
	
	while (!file.EndOfFile())
	{
		char line[255];
		if (!file.ReadLine(line, sizeof(line)))
			break;
		
		/* Trim comments */
		int len = strlen(line);
		bool ignoring = false;
		for (int i=0; i<len; i++)
		{
			if (ignoring)
			{
				if (line[i] == '"')
					ignoring = false;
			} else {
				if (line[i] == '"')
				{
					ignoring = true;
				} else if (line[i] == ';') {
					line[i] = '\0';
					break;
				} else if (line[i] == '/'
							&& i != len - 1
							&& line[i+1] == '/')
				{
					line[i] = '\0';
					break;
				}
			}
		}
		
		TrimString(line);
		
		if ((line[0] == '/' && line[1] == '/')
			|| (line[0] == ';' || line[0] == '\0'))
		{
			continue;
		}
	
		ParseWeaponData(line);
	}
	
	file.Close();
}

/**
  * File line parser.
  *
  * @param sLine 			Line. Pattern: "weapon_*" "*" "sm_*"
  *
  * @noreturn
  */
void ParseWeaponData(const char[] sLine)
{
	int iPos, iNextPos;

	// Get weapon_* id
	char sId[MAX_WEAPON_DATA_ID];
	iNextPos = BreakString(sLine, sId, sizeof(sId));
	iPos = iNextPos;
	

	// Get Weapon name (Menu item name)
	if (iNextPos == -1) {
		// Weapon name not found
		return;
	}

	char sName[MAX_WEAPON_DATA_NAME];
	iNextPos = BreakString(sLine[iPos], sName, sizeof(sName));
	iPos += iNextPos;


	// Get weapon cmd
	if (iNextPos == -1) {
		// Cmd not found
		return;
	}

	char sCmd[MAX_WEAPON_DATA_CMD];
	BreakString(sLine[iPos], sCmd, sizeof(sCmd));

	AddWeaponData(sId, sName, sCmd);
}

/**
  * Global event. Called when all plugins loaded.
  *
  * @noreturn
  */
public void OnAllPluginsLoaded() {
	g_bReadyUpAvailable = LibraryExists("readyup");
}

/**
  * Global event. Called when a library is removed.
  *
  * @param sName 			Library name.
  *
  * @noreturn
  */
public void OnLibraryRemoved(const char[] sName) {
	if (StrEqual(sName, "readyup")) g_bReadyUpAvailable = false;
}

/**
  * Global event. Called when a library is added.
  *
  * @param sName 			Library name.
  *
  * @noreturn
  */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, "readyup")) {
		g_bReadyUpAvailable = true;
	}
}

/**
  * @requared readyup
  * Global event. Called when all players are ready.
  *
  * @noreturn
  */
public void OnRoundIsLive() {
	g_hMenu.Cancel();
}

/**
  * Out of safe zone event.
  *
  * @params  				see events.inc > HookEvent.
  *
  * @noreturn
  */
public Action Event_LeftStartArea(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) 
	{
		g_bRoundIsLive = true;
		g_hMenu.Cancel();
	}	
}

/**
  * Round start event.
  *
  * @params  				see events.inc > HookEvent.
  *
  * @noreturn
  */
public Action Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
	if (!g_bReadyUpAvailable) {
		g_bRoundIsLive = false;
	}
}

/**
  * Global listener for the chat commands.
  *
  * @param iClient			Client index.
  * @param sArgs			Chat argument string.
  *
  * @return Plugin_Handled | Plugin_Continue
  */
public Action OnClientSayCommand(int iClient, const char[] sCommand, const char[] sArgs)
{
	if(iClient && !IsFakeClient(iClient))
    {
		char sClearCmd[MAX_WEAPON_DATA_CMD];
		char sCmd[MAX_WEAPON_DATA_CMD];

		for (int item = 0; item < g_iWeaponDataNum; item++)
		{
			g_hWeaponData.cmd.GetString(item, sCmd, sizeof(sCmd));
			strcopy(sClearCmd, sizeof(sClearCmd), sCmd[3]);

			if ((sArgs[0] == '/' || sArgs[0] == '!') && StrContains(sArgs, sClearCmd) != -1)
			{
				if (CanClientStartVote(iClient)) {
					StartVote(iClient, item);
				}
				
				return Plugin_Handled;
			}
		}
    }

	return Plugin_Continue;
}

/**
  * Called when a client is sending a command.
  *
  * @param iClient			Client index.
  * @param iArgs			Number of arguments.
  *
  * @return Plugin_Handled | Plugin_Continue
  */
public Action OnClientCommand(int iClient, int sArgs)
{
	if(iClient && !IsFakeClient(iClient))
    {
		char sArgCmd[MAX_WEAPON_DATA_CMD];
		char sCmd[MAX_WEAPON_DATA_CMD];
  		GetCmdArg(0, sArgCmd, sizeof(sArgCmd));

		for (int item = 0; item < g_iWeaponDataNum; item++)
		{
			g_hWeaponData.cmd.GetString(item, sCmd, sizeof(sCmd));
			if (StrEqual(sArgCmd, sCmd))
			{
				if (CanClientStartVote(iClient)) {
					StartVote(iClient, item);
				}
				
				return Plugin_Handled;
			}
		}
    }

	return Plugin_Continue;
}

/**
  * Called when the client has entered a menu command.
  *
  * @param iClient			Client index.
  * @param iArgs			Number of arguments.
  *
  * @return Plugin_Handled
  */
public Action Cmd_ShowMenu(int iClient, int iArgs)
{
	if (!iClient || !CanClientStartVote(iClient)) {
		return Plugin_Handled;
	}

	if (g_bReadyUpAvailable && IsInReady()) {
		ToggleReadyPanel(false, iClient);
	}

	g_hMenu.Display(iClient, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

/**
  * Preparing a static menu.
  *
  * @noreturn
  */
void InitMenu()
{
	g_hMenu = new Menu(HandleClickMenu);

	char sMenuTitle[MAX_MENU_TITLE_LENGTH];
	Format(sMenuTitle, sizeof(sMenuTitle), "%t", "MENU_TITLE");
	g_hMenu.SetTitle(sMenuTitle);

	char sWeaponId[MAX_WEAPON_DATA_ID];
	char sWeaponName[MAX_WEAPON_DATA_NAME];

	for (int item = 0; item < g_iWeaponDataNum; item ++)
	{
		g_hWeaponData.id.GetString(item, sWeaponName, sizeof(sWeaponName));
		g_hWeaponData.name.GetString(item, sWeaponName, sizeof(sWeaponName));
		g_hMenu.AddItem(sWeaponId, sWeaponName);
	}
	
	g_hMenu.ExitButton = true;
}

/**
  * Menu item selection handler.
  *
  * @param hMenu		Menu ID.
  * @param iClient		Client index.
  * @param iIndex		Item index.
  *
  * @return				Status code.
  */
public int HandleClickMenu(Menu hMenu, MenuAction iAction, int iClient, int iIndex)
{
	switch (iAction) {
		case MenuAction_Select: {
			// Is a new vote allowed?
			if (!IsNewBuiltinVoteAllowed()) {
				CPrintToChat(iClient, "%t", "IF_COULDOWN", CheckBuiltinVoteDelay());
				return 0;
			}

			StartVote(iClient, iIndex);
		}
		case MenuAction_Cancel: {
			if (g_bReadyUpAvailable) {
				ToggleReadyPanel(true, iClient);
			}
		}
	}

	return 0;
}

/**
  * Start voting.
  *
  * @param iClient		Client index.
  * @param iItem		Weapon index.
  *
  * @return				Status code.
  */
public void StartVote(int iClient, int iItem) 
{
	// Set Item
	g_iVotingItem = iItem;

	// Get all non-spectating players
	int iNumPlayers;
	int[] iPlayers = new int[MaxClients];

	for (int i = 1; i <= MaxClients; i++) 
	{
		if (!IsClientInGame(i) || IsFakeClient(i) || IS_SPECTATOR(i)) {
			continue;
		}

		iPlayers[iNumPlayers++] = i;
	}

	// Create vote
	g_hVote = CreateBuiltinVote(HandleActionVote, BuiltinVoteType_Custom_YesNo, BuiltinVoteAction_Cancel | BuiltinVoteAction_VoteEnd | BuiltinVoteAction_End);
	SetBuiltinVoteInitiator(g_hVote, iClient);
	SetBuiltinVoteResultCallback(g_hVote, HandleVoteResult);

	char sVoteTitle[MAX_VOTE_MESSAGE_LENGTH];
	char sWeaponName[MAX_WEAPON_DATA_NAME];
	g_hWeaponData.name.GetString(g_iVotingItem, sWeaponName, sizeof(sWeaponName));
	Format(sVoteTitle, sizeof(sVoteTitle), "%t", "VOTE_TITLE", iClient, sWeaponName);
	SetBuiltinVoteArgument(g_hVote, sVoteTitle);

	// Show vote
	DisplayBuiltinVote(g_hVote, iPlayers, iNumPlayers, TIMER_VOTE_HIDE);
	FakeClientCommand(iClient, "Vote Yes");
}

/**
 * Called when the action in the vote has completed.
 *
 * @param hVote 			Voting ID.
 * @param iAction			Action: BuiltinVoteAction_End, BuiltinVoteAction_Cancel
 * @param iParam1			(client).
 *
 * @noreturn
 */
public void HandleActionVote(Handle hVote, BuiltinVoteAction iAction, int iParam1, int iParam2)
{
	switch (iAction) {
		case BuiltinVoteAction_End: {
			delete hVote;
			g_hVote = null;
		}
		case BuiltinVoteAction_Cancel: {
			DisplayBuiltinVoteFail(hVote, view_as<BuiltinVoteFailReason>(iParam1));
		}
	}
}

/**
  * Callback when voting is over and results are available.
  *
  * @param hVote 			Voting ID.
  * @param iVotes 			Total votes counted.
  * @param iItemsInfo 		Array of elements sorted by count.
  *
  * @noreturn
  */
public void HandleVoteResult(Handle hVote, int iVotes, int num_clients, const int[][] client_info, int num_items, const int[][] iItemsInfo)
{
	if (g_bReadyUpAvailable) {
		ToggleReadyPanel(true);
	}
	
	for (new iItem = 0; iItem < num_items; iItem++)
	{
		if (iItemsInfo[iItem][BUILTINVOTEINFO_ITEM_INDEX] == BUILTINVOTES_VOTE_YES  && iItemsInfo[iItem][BUILTINVOTEINFO_ITEM_VOTES] > (iVotes / 2)) 
		{
				if (g_bRoundIsLive || g_bReadyUpAvailable && !IsInReady()) {
					DisplayBuiltinVoteFail(hVote, BuiltinVoteFail_Loses);
					return;
				}

				int initiator = GetBuiltinVoteInitiator(hVote);	

				char sVoteMsg[MAX_VOTE_MESSAGE_LENGTH];
				char sWeaponName[MAX_WEAPON_DATA_NAME];
				g_hWeaponData.name.GetString(g_iVotingItem, sWeaponName, sizeof(sWeaponName));
				Format(sVoteMsg, sizeof(sVoteMsg), "%t", "VOTE_PASS", initiator, sWeaponName);
				DisplayBuiltinVotePass(hVote, sVoteMsg);

				if (IS_SURVIVOR_ALIVE(initiator)) {
					char sWeaponId[MAX_WEAPON_DATA_ID];
					g_hWeaponData.id.GetString(g_iVotingItem, sWeaponId, sizeof(sWeaponId));
					GiveClientItem(initiator, sWeaponId);
					return;
				}
		}
	}

	// Vote Failed
	DisplayBuiltinVoteFail(hVote, BuiltinVoteFail_Loses);
	return;
}

/**
  * @param iClient			Client index.
  *
  * @return 				true or false.
  */
bool CanClientStartVote(int iClient) 
{
	if (!IS_VALID_SURVIVOR(iClient)) {
		CPrintToChat(iClient, "%t", "IF_NOT_SURV");
		return false;
	}

	if (g_bReadyUpAvailable) {
		if (!IsInReady()) {
			CPrintToChat(iClient, "%t", "IF_LEFT_READYUP");
			return false;
		}
	} else {
		if (g_bRoundIsLive) {
			CPrintToChat(iClient, "%t", "IF_ROUND_LIVE");
			return false;
		}
	}

	// Is a new vote allowed?
	if (!IsNewBuiltinVoteAllowed()) {
		CPrintToChat(iClient, "%t", "IF_COULDOWN", CheckBuiltinVoteDelay());
		return false;
	}

	return true;
}

/**
  * Gives the player a weapon.
  *
  * @param iClient			Client index.
  * @param sWeaponName 		weapon_*.
  *
  * @noreturn
  */
void GiveClientItem(int iClient, const char[] sWeaponName) 
{
#if (SOURCEMOD_V_MINOR == 11)
	GivePlayerItem(iClient, sWeaponName); // Fixed only in the latest version of sourcemod 1.11
#else
	int iEntity = CreateEntityByName(sWeaponName);
	if (iEntity == -1) {
		return;
	}

	DispatchSpawn(iEntity);
	EquipPlayerWeapon(iClient, iEntity);
#endif
}
