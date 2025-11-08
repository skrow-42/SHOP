SHOP - Store and House Owner Patrol - Thieving/Stealing/Stealth AI Overhaul for OpenMW 0.49 and higher

Witness never seen Ai behavior in Morrowind (OpenMW). Stealing is now very hard (optional ErnBurglary - Burglary Overhaul integration). NPCs will follow you around and search for you in interior cells to prevent stealing. (4500 lines AI overhaul)

Please report any bugs or feature requests here:
https://discord.com/channels/260439894298460160/1430304182543323297

or here:

https://www.nexusmods.com/morrowind/mods/57747?tab=posts




Full integration in SHOP:

ErnBurglary - Burglary Overhaul (v1.3.8 and higher) https://github.com/ernmw/ErnBurglary

Daisy Lua Multi Mark https://www.nexusmods.com/morrowind/mods/53260



Features



Automatic Guard Following: NPCs in interior cells automatically recruit as guards based on priority (faction rank, class, etc.) when the player is detected

Intelligent Following: Guards maintain set distance and follow the player through interiors, avoiding obstacles

Line-of-Sight Detection: Advanced LOS system with configurable cone angles and range limits

Stealth Detection: Guards can detect sneaking players and will search if player goes stealth/invisibility/chameleon

Invisibility/Chameleon Detection: Guards detect and remove invisibility and chameleon effects when the player gets too close

Real-Time Wandering: Guards perform realistic wandering patterns during searches

Teleport Handling: Guards instantly return home when player teleports (recall, divine intervention, etc.) 

Path Recording: Guards record and follow player paths for realistic return to their post

Hierarchy System: Lower rank guild NPCs take over following over higher-ranked ones, sending the higher rank NPC to his home location

Faction Rank Filter: Respects faction ranks and disables in guild cells following for currently set ranking members

Disposition Change: -15 disposition is subtracted upon getting hidden from a NPC that is following you and also upon being detected/discovered from stealth

Cell/ NPC Filtering: Configurable blacklists for specific cells or NPCs (or all NPC or Cell names containing input words) EDIT BLACKLISTS IN modules/config.lua

Essential NPCs: Essential NPCs are completely excluded from following script

Enemy cells excluded: Script is turned off in cells with enemies



Requirements

OpenMW: Version 0.49 or higher



Installation


Download the mod archive

Extract the contents to your desired data path

Launch OpenMW launcher and enable SHOP.omwscripts in the list



Configuration


The mod provides extensive configuration options via the Mod Configuration Menu:

Timing Settings

Enter Delay: Time before guard recruitment can happen after entering interior cell (default: 1.5s)

Update Period: How often guard position is updated in the script (default: 1.0s)

Search Time: Min and max search duration when player is hidden (default: 10-15s)

LOS Check Interval: How often Line-of-Sight is checked (default: 1.0s)


Distance Settings


Pick Range: Maximum distance for guard recruitment (default: 1000 units)

Desired Distance: Distance guards maintain from player (default: 100 units)

LOS Range: Maximum line-of-sight distance (default: 1000 units)

Detection Range: Distance for detection by NPC while hidden (default: 75 units)


Behavior Settings


LOS Half Cone: NPC Field of view angle to detect player (default: 170°)

Chameleon Hide Limit: Minimum chameleon % magnitude to invoke hiding from NPC script (default: 1%)

Faction Ignore Rank: Minimum rank to disable script in guild cells (default: 5)

Disable Hello While Following: Prevents greeting messages during following (prevents script interruption upon changing position in the same cell (for example basement transition doors etc.)



Debug Settings (F10 key/openmw.log)


Enable Player Debug: Toggle player script logging 

Enable Global Debug: Toggle global script logging


TODO:


Whitelisting Exterior cell support for niche uses (for example Guard following you on a Dren Plantation - exterior use will find its use limiting to a single cell following)

More sophisticated AI behaviors (adding Idle animations in between following the player)

Locking doors when being followed by NPC will add bounty to the player and if NPC  is a mage, he will open the doors with unlock spell

Change the messages invoked upon being discovered by NPC to Vanilla voice lines and messages

Add Dispotion Check to NPCs which will allow the script to ignore this NPCs based on Disposition Value of NPC

Add option to change Disposition Removal Value upon hiding and being discovered from NPC

Add option to remove Disposition upon hiding and being discovered only once until left that cell



Known Issues
Public Test Status: This is v0.9 public test - expect bugs and incomplete features

Performance: May impact performance in densely populated cells

Compatibility: We will know after testing phase



Changelog


v0.9 (Public Test)

Initial Public Test version


Credits


Author: skrow42

License: GNU Affero General Public License v3.0


Special Thanks: 

OpenMW Discord community for scripting and emotional support

Erin Pentecost for enabling Spotted function integration from her ErnBurglary mod (Burglary Overhaul) https://github.com/erinpentecost
