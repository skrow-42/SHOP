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
-- Guard Actions (Recruit, Follow, Search, Home)
----------------------------------------------------------------------

local utils = require('scripts.antitheftai.modules.utils')
local pathModule = require('scripts.antitheftai.modules.path_recording')
local storage = require('scripts.antitheftai.modules.storage')
local types = require('openmw.types')
local self = require('openmw.self')
local core = require('openmw.core')
local actions = {}

local config = require('scripts.antitheftai.modules.config')
local settings = require('scripts.antitheftai.SHOPsettings')
local vars     = settings.vars
local seenMessages = {}

local function log(...)
    if settings.general:get("enableDebug") then
        local args = {...}
        for i, v in ipairs(args) do
            args[i] = tostring(v)
        end
        local msg = table.concat(args, " ")
        if not seenMessages[msg] then
            print("[NPC-AI]", ...)
            seenMessages[msg] = true
        end
    end
end

-- Recruit guard
function actions.recruit(npc, state, detection, self)
    if not npc then return end
    
    log("[RECRUIT] Recruiting NPC", npc.id)
    
    if state.mustCompleteReturn[npc.id] or state.returnInProgress[npc.id] then
        return
    end
    
    local storedData = storage.retrieveNPCData(npc.id, npc.cell, require('openmw.util'))
    
    if storedData then
        state.npcOriginalData[npc.id] = storedData
    elseif not state.npcOriginalData[npc.id] then
        state.npcOriginalData[npc.id] = {
            cell = npc.cell,
            pos = utils.v3(npc.position),
            rot = utils.copyRotation(npc.rotation)
        }
        storage.storeNPCData(npc.id, state.npcOriginalData[npc.id])
    end
    
    local classification = require('scripts.antitheftai.modules.npc_classification')
    local types = require('openmw.types')
    
    state.guard = npc
    state.guardPriority = classification.getNPCPriority(npc, types, self, npc.cell, config, require('openmw.nearby'))
    state.home = state.npcOriginalData[npc.id]

    state.following = false
    state.searching = false
    state.ernBurglarySpottedInvoked = false  -- Reset flag when recruiting a new NPC

    -- Clear invisibility and chameleon removal flags when recruiting
    detection.removedEffects[require('scripts.antitheftai.modules.config').EFFECT_INVIS] = nil
    detection.removedEffects[require('scripts.antitheftai.modules.config').EFFECT_CHAM] = nil
end

-- Follow player
function actions.followPlayer(state, self, config)
    if not (state.guard and state.guard:isValid()) then return end

    log("[FOLLOW] Starting follow for NPC", state.guard.id)

    -- Set hello to 0 when following to prevent greeting packages (only once per NPC)
    if state.originalHelloValues[state.guard.id] and not state.helloSet[state.guard.id] then
        state.guard:sendEvent('AntiTheft_SetHello', {
            value = 0
        })
        state.helloSet[state.guard.id] = true
        log("[FOLLOW] Sent event to set hello to 0 for NPC", state.guard.id, "(original was", state.originalHelloValues[state.guard.id], ")")
    end

    state.guard:sendEvent('StartAIPackage', {
        type = 'Travel',
        destPosition = utils.ring(self.position, state.guard.position, config.DESIRED_DIST),
        cancelOther = true
    })

    if not pathModule.pathRecording[state.guard.id] or
       (not pathModule.pathRecording[state.guard.id].locked and
        not pathModule.pathRecording[state.guard.id].recordingActive) then
        pathModule.startPathRecording(state.guard.id, state.guard)
    end

    state.following = true
    state.searching = false
    state.returningHome = false
    state.lastSeenPlayer = self.position
    log("[FOLLOW] Now following player")

    -- Check for ErnBurglary integration - only invoke once per NPC following start
    if not state.ernBurglarySpottedInvoked then
        local success, mod = pcall(require, "scripts.ErnBurglary.interface")
        if success and mod and mod.interface and mod.interface.spotted and settings.compatibility:get("enableErnBurglarySpotted") then
            print("[NPC-AI] [FOLLOW] Invoking ErnBurglary spotted function")
            mod.interface.spotted(self, state.guard, false)
            state.ernBurglarySpottedInvoked = true
        end
    end
end

-- Start search/wander
function actions.startSearch(state, detection, config)
    if not (state.guard and state.guard:isValid()) then return end
    
    log("[SEARCH] Starting wander at last known location for NPC", state.guard.id)
    log("[SEARCH] Player became invisible")
    
    if pathModule.pathRecording[state.guard.id] and pathModule.pathRecording[state.guard.id].recordingActive then
        pathModule.stopPathRecording(state.guard.id, state.guard.position)
    end
    
    -- Clear the invisibility and chameleon removal flags
    detection.removedEffects[config.EFFECT_INVIS] = nil
    detection.removedEffects[config.EFFECT_CHAM] = nil
    state.invisMessageSent = false
    state.stealthMessageSent = false
    
    if state.lastSeenPlayer then
        log("[SEARCH] Last seen position:", state.lastSeenPlayer)
        state.guard:sendEvent('StartAIPackage', {
            type = 'Travel',
            destPosition = state.lastSeenPlayer,
            cancelOther = true
        })
    end
    
    -- Wander AI
    local function wander(n, dist, dur)
        n:sendEvent('StartAIPackage', {
            type = 'Wander',
            distance = dist,
            duration = dur,
            cancelOther = false
        })
    end
    
    -- Use custom search time if set, otherwise default
    if not state.searchTime then
        state.searchTime = config.SEARCH_WTIME_MIN + math.random() * (config.SEARCH_WTIME_MAX - config.SEARCH_WTIME_MIN)
    end
    wander(state.guard, config.SEARCH_WDIST, state.searchTime)
    state.following = false
    state.searching = true
    state.returningHome = false
    state.searchT = 0
    
    log("[SEARCH] Wandering at last known player location")
end

-- Go home
function actions.goHome(state, core)
    if not state.guard or not state.home then return end

    local guardId = state.guard.id

    if pathModule.pathRecording[guardId] and pathModule.pathRecording[guardId].recordingActive then
        pathModule.stopPathRecording(guardId, state.guard.position)
    end

    state.returnInProgress[guardId] = true
    state.mustCompleteReturn[guardId] = true

    local rotX, rotY, rotZ = utils.getEulerAngles(state.home.rot)

    local waypointCount = pathModule.pathRecording[guardId] and #pathModule.pathRecording[guardId].waypoints or 0
    log("Sending NPC", guardId, "home with", waypointCount, "recorded waypoints")

    -- Include original hello value for restoration
    local originalHello = state.originalHelloValues[guardId] or 0

    core.sendGlobalEvent('AntiTheft_StartReturnHome', {
        npcId = guardId,
        homePosition = state.home.pos,
        homeRotation = {
            x = rotX,
            y = rotY,
            z = rotZ
        },
        originalHelloValue = originalHello
    })

    state.following = false
    state.searching = false
    state.returningHome = true
    state.searchT = 0
    state.guard = nil  -- Clear guard reference to allow recruitment of another NPC
end

-- Send pending returns home
function actions.sendPendingReturnsHome(npc, state, core)
    if not npc then return end

    local storedData = storage.retrieveNPCData(npc.id, npc.cell, require('openmw.util'))
    local npcHome

    if storedData then
        npcHome = storedData
    elseif state.npcOriginalData[npc.id] then
        npcHome = state.npcOriginalData[npc.id]
    else
        npcHome = {
            cell = npc.cell,
            pos = utils.v3(npc.position),
            rot = utils.copyRotation(npc.rotation)
        }
        storage.storeNPCData(npc.id, npcHome)
    end

    state.returnInProgress[npc.id] = true
    state.mustCompleteReturn[npc.id] = true

    local rotX, rotY, rotZ = utils.getEulerAngles(npcHome.rot)

    core.sendGlobalEvent('AntiTheft_StartReturnHome', {
        npcId = npc.id,
        homePosition = npcHome.pos,
        homeRotation = {
            x = rotX,
            y = rotY,
            z = rotZ
        }
    })
end

-- Teleport home instantly (for spell teleports)
function actions.teleportHome(state, core)
    if not state.guard or not state.home then return end

    local guardId = state.guard.id

    if pathModule.pathRecording[guardId] and pathModule.pathRecording[guardId].recordingActive then
        pathModule.stopPathRecording(guardId, state.guard.position)
    end

    state.returnInProgress[guardId] = true
    state.mustCompleteReturn[guardId] = true

    local rotX, rotY, rotZ = utils.getEulerAngles(state.home.rot)

    log("Instantly teleporting NPC", guardId, "home due to spell teleport")

    -- Use global event to teleport the NPC (player script cannot directly teleport NPCs)
    core.sendGlobalEvent('AntiTheft_TeleportHome', {
        npcId = guardId,
        homePosition = state.home.pos,
        homeRotation = {
            x = rotX,
            y = rotY,
            z = rotZ
        }
    })

    state.following = false
    state.searching = false
    state.returningHome = true
    state.searchT = 0
end

return actions