--[[
SHOP - Store & House Owner Patrol (NPC in interiors AI overhaul) for OpenMW.
Copyright (C) 2025 Łukasz Walczak

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as
published by the Free Software Foundation, either version 3 of the
License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program.  If not, see <https://www.gnu.org/licenses/>.
]]
----------------------------------------------------------------------
-- Anti-Theft Guard AI  •  v0.9 PUBLIC TEST  •  OpenMW ≥ 0.49
----------------------------------------------------------------------
-- Runtime State Variables
----------------------------------------------------------------------

local state = {}

-- Guard state
state.guard = nil
state.guardPriority = 999
state.home = nil

-- Behavior flags
state.waiting = false
state.following = false
state.searching = false
state.returningHome = false

-- Timers
state.searchT = 0
state.tDelay = 0
state.tLOSCheck = 0
state.tHierarchyCheck = 0
state.tRefresh = 0

-- Position tracking
state.lastSeenPlayer = nil
state.lastPlayerCell = nil
state.lastPlayerPosition = nil

-- Dialog state
state.dialogueWasOpen = false

-- Sneak state tracking
state.wasSneaking = false

-- Hidden state tracking
state.wasHidden = false

-- Effect removal tracking
state.justRemovedInvisibility = false
state.justRemovedChameleon = false
state.invisMessageSent = false
state.stealthMessageSent = false

-- Cell state
state.lastCell = nil
state.cellInitialized = false

-- Force checks
state.forceLOSCheck = false

-- Sneak detection
state.wasSneakHidden = false

-- Spell teleport handling
state.pendingSpellTeleport = false
state.spellCastCell = nil

-- Combat state
state.inCombat = false

-- Storage tables
state.leftBehindGuards = {}
state.npcOriginalData = {}
state.dismissedNPCs = {}
state.mustCompleteReturn = {}
state.returnInProgress = {}
state.doorLockStates = {}
state.npcHasWandered = {}
state.crossCellReturns = {}
state.pendingReturns = {}
state.realTimeWandering = {}



-- Hello value tracking
state.helloSet = {}
state.originalHelloValues = {}

-- Reset function
function state.reset()
    state.guard = nil
    state.guardPriority = 999
    state.home = nil
    state.waiting = false
    state.following = false
    state.searching = false
    state.returningHome = false
    state.searchT = 0
    state.tDelay = 0
    state.tLOSCheck = 0
    state.tHierarchyCheck = 0
    state.tRefresh = 0
    state.lastSeenPlayer = nil
    state.dialogueWasOpen = false
    state.wasSneakHidden = false
    state.wasHidden = false
    state.invisMessageSent = false
    state.stealthMessageSent = false
    state.pendingSpellTeleport = false
    state.spellCastCell = nil
    state.justRecruitedAfterReturn = false
    -- Clear hello tracking on reset
    state.helloSet = {}
end

return state