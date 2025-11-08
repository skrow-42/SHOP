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
-- Path Recording System
----------------------------------------------------------------------

local utils = require('scripts.antitheftai.modules.utils')

local pathModule = {}

local config = require('scripts.antitheftai.modules.config')
local seenMessages = {}

local settings = require('scripts.antitheftai.SHOPsettings')

local function log(...)
    if settings.general:get("enableDebug") then
        local args = {...}
        for i, v in ipairs(args) do
            args[i] = tostring(v)
        end
        local msg = table.concat(args, " ")
        if not seenMessages[msg] then
            print("[PathRec]", ...)
            seenMessages[msg] = true
        end
    end
end

-- Storage for path recordings
pathModule.pathRecording = {}

-- Start recording
function pathModule.startPathRecording(npcId, npc)
    if not (npc and npc:isValid()) then return end
    
    if pathModule.pathRecording[npcId] and pathModule.pathRecording[npcId].locked then
        log("Path recording for NPC", npcId, "already locked - using stored path")
        return
    end
    
    log("═══════════════════════════════════════════════════")
    log("Starting FIRST path recording for NPC", npcId)
    log("  Initial position:", npc.position)
    log("  This path will be stored permanently")
    
    pathModule.pathRecording[npcId] = {
        waypoints = { utils.v3(npc.position) },
        recordingActive = true,
        lastSample = 0,
        totalDistance = 0,
        locked = false
    }
    log("═══════════════════════════════════════════════════")
end

-- Update recording
function pathModule.updatePathRecording(npcId, npc, dt, config)
    local recording = pathModule.pathRecording[npcId]
    if not recording or not recording.recordingActive or recording.locked then return end
    
    if not (npc and npc:isValid()) then
        recording.recordingActive = false
        return
    end
    
    recording.lastSample = recording.lastSample + dt
    
    if recording.lastSample >= config.PATH_SAMPLE_INTERVAL then
        recording.lastSample = 0
        
        local lastPos = recording.waypoints[#recording.waypoints]
        local currentPos = utils.v3(npc.position)
        local moved = (currentPos - lastPos):length()
        
        if moved >= config.MIN_MOVEMENT_THRESHOLD then
            table.insert(recording.waypoints, currentPos)
            recording.totalDistance = (recording.totalDistance or 0) + moved
            
            if #recording.waypoints % 5 == 0 then
                log("Path recording for NPC", npcId, ":", #recording.waypoints, "waypoints, total distance:", math.floor(recording.totalDistance))
            end
        end
    end
end

-- Stop recording
function pathModule.stopPathRecording(npcId, finalPosition)
    local recording = pathModule.pathRecording[npcId]
    if not recording then return end
    
    if recording.locked then
        log("Path recording for NPC", npcId, "already locked - skipping stop")
        return
    end
    
    if finalPosition then
        local lastPos = recording.waypoints[#recording.waypoints]
        local moved = (finalPosition - lastPos):length()
        
        local config = require('scripts.antitheftai.modules.config')
        if moved >= config.MIN_MOVEMENT_THRESHOLD then
            table.insert(recording.waypoints, utils.v3(finalPosition))
            recording.totalDistance = (recording.totalDistance or 0) + moved
        end
    end
    
    recording.recordingActive = false
    recording.locked = true
    
    log("═══════════════════════════════════════════════════")
    log("Path recording LOCKED for NPC", npcId)
    log("  Total waypoints:", #recording.waypoints)
    log("  Total distance traveled:", math.floor(recording.totalDistance or 0), "units")
    log("  This path is now permanent and will always be used")
    log("═══════════════════════════════════════════════════")
end

-- Clear recording
function pathModule.clearPathRecording(npcId)
    if pathModule.pathRecording[npcId] and pathModule.pathRecording[npcId].locked then
        log("Path for NPC", npcId, "is locked - NOT clearing")
        return
    end
    
    pathModule.pathRecording[npcId] = nil
    log("Cleared unlocked path recording for NPC", npcId)
end

return pathModule