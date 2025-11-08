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
-- GLOBAL SCRIPT – handles NPC teleportation, wandering, and rotation
----------------------------------------------------------------------

local storage = require('openmw.storage')

-- Global scripts must use *global* storage instead of player storage
local settings = storage.globalSection("SettingsSHOPset")
local seenMessages = {}

-- local cache, used by your log() helper
local _enableGlobalDebug = settings:get('enableGlobalDebug') or false
local _enableDebug       = settings:get('enableDebug')       or false

local function log(...)
    if _enableGlobalDebug then
        local args = {...}
        for i, v in ipairs(args) do
            args[i] = tostring(v)
        end
        local msg = table.concat(args, " ")
        if not seenMessages[msg] then
            print("[GlobalWalkBack]", ...)
            seenMessages[msg] = true
        end
    end
end

-- event sent from the player script whenever a setting changes
local function onUpdateSetting(data)
    if not data or not data.key then return end
    -- store it permanently
    settings:set(data.key, data.value)
    -- refresh the local cache so the new value is used immediately
    if data.key == 'enableGlobalDebug' then
        _enableGlobalDebug = data.value
    elseif data.key == 'enableDebug' then
        _enableDebug = data.value
    end
    log('Setting', data.key, 'changed to', tostring(data.value))
end
log("=== GLOBAL SCRIPT LOADING v18.1 ===")

local world = require('openmw.world')
local util  = require('openmw.util')
local core  = require('openmw.core')
local types = require('openmw.types')

local pendingReturns  = {}
local activeRotations = {}
local wanderingNPCs = {}  -- Track NPCs currently wandering
local pendingTeleports = {}  -- Track NPCs waiting to be teleported
local teleportingNPCs = {}  -- Track NPCs currently being teleported home
local teleportTimeouts = {}  -- Track NPCs with 5-minute timeout to return to default position

----------------------------------------------------------------------
-- Helper: find NPC by ID
----------------------------------------------------------------------
local function findNPC(npcId)
    for _, actor in ipairs(world.activeActors) do
        if actor.id == npcId then return actor end
    end
    return nil
end

----------------------------------------------------------------------
-- Finish return: set rotation and restore default behavior
----------------------------------------------------------------------
local function finishReturn(rot)
    local npc = rot.npc

    if not rot.homeRotation then
        log("ERROR: Missing homeRotation for NPC", rot.npcId)
        return
    end

    local homeRotTransform = util.transform.rotateZ(rot.homeRotation.z or 0) *
                             util.transform.rotateY(rot.homeRotation.y or 0) *
                             util.transform.rotateX(rot.homeRotation.x or 0)
    
    npc:teleport(npc.cell.name, npc.position, { rotation = homeRotTransform, onGround = true })

    local player = world.players[1]
    if player then
        player:sendEvent('AntiTheft_NPCReady', { npcId = rot.npcId })
        log("✓ NPC", rot.npcId, "ready – can detect player")
    else
        log("ERROR: Could not find player to send ready event")
    end
end

----------------------------------------------------------------------
-- Begin smooth rotation
----------------------------------------------------------------------
local function startGlobalRotation(npc, targetRotation, duration, homePosition, homeRot)
    if not (npc and npc:isValid()) then
        log("ERROR: Invalid NPC in startGlobalRotation")
        return
    end
    
    if not targetRotation then
        log("ERROR: Missing targetRotation for NPC", npc.id)
        return
    end

    local currentZ = npc.rotation:getAnglesZYX()

    log("Starting smooth rotation for", npc.id,
        "from", math.deg(currentZ), "to", math.deg(targetRotation.z or 0), "deg")

    local targetZ = targetRotation.z or 0
    local diff = targetZ - currentZ
    if diff >  math.pi then diff = diff - 2*math.pi
    elseif diff < -math.pi then diff = diff + 2*math.pi end

    table.insert(activeRotations, {
        npcId             = npc.id,
        npc               = npc,
        startZ            = currentZ,
        targetX           = targetRotation.x or 0,
        targetY           = targetRotation.y or 0,
        targetZ           = targetZ,
        duration          = duration,
        elapsed           = 0,
        diffZ             = diff,
        lastLog           = 0,
        exactHomePosition = homePosition,
        homeRotation      = homeRot
    })
end

----------------------------------------------------------------------
-- Per-frame rotation updater
----------------------------------------------------------------------
local function updateGlobalRotations(dt)
    for i = #activeRotations, 1, -1 do
        local rot = activeRotations[i]
        if not (rot.npc and rot.npc:isValid()) then
            log("NPC became invalid during rotation - cleaning up")
            table.remove(activeRotations, i)
        else
            rot.elapsed = rot.elapsed + dt
            if rot.elapsed >= rot.duration then
                finishReturn(rot)
                table.remove(activeRotations, i)
            else
                local t = rot.elapsed / rot.duration
                local eased = (t < 0.5) and (4*t*t*t)
                              or (1 - math.pow(-2*t + 2, 3)/2)
                local curZ = rot.startZ + rot.diffZ * eased
                local curRot = util.transform.rotateZ(curZ)
                              * util.transform.rotateY(rot.targetY)
                              * util.transform.rotateX(rot.targetX)
                rot.npc:teleport(rot.npc.cell.name, rot.npc.position,
                                 { rotation = curRot, onGround = true })
                rot.lastLog = rot.lastLog + dt
                if rot.lastLog >= 0.5 then
                    log("Rotating NPC", rot.npcId, "...", math.floor(t*100), "%")
                    rot.lastLog = 0
                end
            end
        end
    end
end

----------------------------------------------------------------------
-- Pending-return state machine (for same-cell returns)
----------------------------------------------------------------------
local function processPendingReturns(dt)
    local i = 1
    while i <= #pendingReturns do
        local ret = pendingReturns[i]
        ret.timer     = ret.timer - dt
        ret.totalTime = (ret.totalTime or 0) + dt

        if ret.totalTime > 30 then
            log("WARNING: NPC", ret.npcId, "timeout after 30s – forcing restore")
            local npc = findNPC(ret.npcId)
            if npc and npc:isValid() then npc:sendEvent('RemoveAIPackages') end
            local player = world.players[1]
            if player then
                player:sendEvent('AntiTheft_NPCReady', { npcId = ret.npcId })
            else
                log("ERROR: Could not find player to send ready event")
            end
            table.remove(pendingReturns, i)
            i = i - 1

        elseif ret.timer <= 0 then
            local npc = findNPC(ret.npcId)
            
            if npc and npc:isValid() then
                if ret.phase == 1 then
                    local dist = (npc.position - ret.exactHomePosition):length()
                    local curPos = util.vector3(npc.position.x, npc.position.y, npc.position.z)

                    if ret.lastPosition then
                        local move = (curPos - ret.lastPosition):length()
                        if move < 0.1 then
                            ret.stopCount = (ret.stopCount or 0) + 1
                        else
                            ret.stopCount = 0
                        end
                    end
                    ret.lastPosition = curPos

                    if dist < 35 and (ret.stopCount or 0) >= 3 then
                        npc:sendEvent('RemoveAIPackages')
                        ret.phase = 2
                        ret.timer = 0.01
                        log("NPC", ret.npcId, "arrived home, proceeding to rotation")
                    elseif (ret.phase1Checks or 0) > 100 then
                        if dist < 35 then
                            npc:sendEvent('RemoveAIPackages')
                            ret.phase = 2
                            ret.timer = 0.01
                        else
                            log("Resending travel command for NPC", ret.npcId)
                            npc:sendEvent('RemoveAIPackages')
                            npc:sendEvent('StartAIPackage', {
                                type        = 'Travel',
                                destPosition= ret.exactHomePosition,
                                cancelOther = true
                            })
                            ret.phase1Checks = 0
                        end
                    else
                        ret.phase1Checks = (ret.phase1Checks or 0) + 1
                        ret.timer = 0.2
                    end

                elseif ret.phase == 2 then
                    startGlobalRotation(npc, ret.homeRotation, 0.3, ret.exactHomePosition, ret.homeRotation)
                    table.remove(pendingReturns, i)
                    i = i - 1
                end
            else
                log("WARNING: NPC", ret.npcId, "not found - will retry")
                ret.timer = 1.0
            end
        end
        i = i + 1
    end
end

----------------------------------------------------------------------
-- ★★★ EVENT: Start Wandering (search-style behavior) ★★★
----------------------------------------------------------------------
local function onStartWandering(data)
    if not data or not data.npcId then return end
    
    log("═══════════════════════════════════════════════════")
    log("START WANDERING (search-style) for NPC", data.npcId)
    log("  Wander position:", data.wanderPosition)
    log("  Wander distance:", data.wanderDistance)
    log("  Wander duration:", data.wanderDuration, "seconds")
    
    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        log("  ✓ NPC found - sending search-style AI packages")
        
        -- Clear any existing AI packages
        npc:sendEvent('RemoveAIPackages')
        
        -- ★★★ Give Travel + Wander combo (same as search behavior) ★★★
        -- First travel to last known position (if any)
        if data.wanderPosition then
            npc:sendEvent('StartAIPackage', {
                type = 'Travel',
                destPosition = data.wanderPosition,
                cancelOther = false
            })
        end
        
        -- Then wander around
        npc:sendEvent('StartAIPackage', {
            type = 'Wander',
            distance = data.wanderDistance,
            duration = data.wanderDuration,
            cancelOther = false
        })
        
        -- Track wandering NPC
        wanderingNPCs[data.npcId] = {
            npcId = data.npcId,
            homePosition = data.homePosition,
            homeRotation = data.homeRotation,
            wanderEndTime = core.getRealTime() + data.wanderDuration
        }
        
        log("  ✓ Search-style packages sent (Travel + Wander)")
        log("  NPC will wander for", math.floor(data.wanderDuration), "seconds")
    else
        log("  ⚠ NPC not found in loaded cells")
        log("  NPC will wander when cell loads")
        
        -- Still track it in case cell loads later
        wanderingNPCs[data.npcId] = {
            npcId = data.npcId,
            homePosition = data.homePosition,
            homeRotation = data.homeRotation,
            wanderEndTime = core.getRealTime() + data.wanderDuration
        }
    end
    
    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Start Walking Home (after wandering) ★★★
----------------------------------------------------------------------
local function onStartWalkingHome(data)
    if not data or not data.npcId then return end

    log("═══════════════════════════════════════════════════")
    log("START WALKING HOME for NPC", data.npcId)
    log("  (Wandering complete, now traveling to home)")

    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        log("  ✓ NPC found in loaded cells - sending travel package")
        log("  Home position:", data.homePosition)

        npc:sendEvent('RemoveAIPackages')
        npc:sendEvent('StartAIPackage', {
            type = 'Travel',
            destPosition = data.homePosition,
            cancelOther = true
        })

        log("  ✓ Travel package sent - NPC will walk to home")
        log("  Distance:", math.floor((npc.position - data.homePosition):length()), "units")
    else
        log("  NPC not in loaded cells (unexpected for real-time return)")
    end

    -- Inherit rotation logic from working return function
    table.insert(pendingReturns, {
        npcId              = data.npcId,
        exactHomePosition  = data.homePosition,
        homeRotation       = data.homeRotation,
        timer              = 0.2,
        phase              = 1,
        totalTime          = 0,
        phase1Checks       = 0,
        stopCount          = 0,
        lastPosition       = nil
    })
    log("  ✓ Added to pending returns queue for rotation")

    -- Remove from wandering tracker
    wanderingNPCs[data.npcId] = nil

    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Finalize return (called by player script) ★★★
----------------------------------------------------------------------
local function onFinalizeReturn(data)
    if not data or not data.npcId then return end
    
    log("═══════════════════════════════════════════════════")
    log("FINALIZING RETURN for NPC", data.npcId)
    
    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        log("  Starting rotation to home orientation")
        startGlobalRotation(npc, data.homeRotation, 0.8, data.homePosition, data.homeRotation)
    else
        log("  ERROR: NPC not found - sending ready event anyway")
        local player = world.players[1]
        if player then
            player:sendEvent('AntiTheft_NPCReady', { npcId = data.npcId })
        end
    end
    
    -- Clean up wandering tracker if present
    wanderingNPCs[data.npcId] = nil
    
    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Place returning NPC at simulated position ★★★
----------------------------------------------------------------------
local function onPlaceReturningNPC(data)
    if not data or not data.npcId then return end
    
    log("═══════════════════════════════════════════════════")
    log("PLACING RETURNING NPC", data.npcId)
    log("  At position:", data.currentPosition)
    log("  Cell:", data.cellName)
    
    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        -- Teleport to simulated position with walking rotation
        local walkRot = util.transform.rotateZ(data.walkRotation)
        
        npc:teleport(data.cellName, data.currentPosition, {
            rotation = walkRot,
            onGround = true
        })
        
        log("  ✓ NPC teleported to simulated position")
        
        -- Give Travel AI package to continue walking home
        npc:sendEvent('RemoveAIPackages')
        npc:sendEvent('StartAIPackage', {
            type = 'Travel',
            destPosition = data.homePosition,
            cancelOther = true
        })
        
        log("  ✓ Travel AI package sent - NPC will walk to home")
        log("  Distance remaining:", math.floor((data.homePosition - data.currentPosition):length()), "units")
    else
        log("  ERROR: NPC not found")
    end
    
    -- Clean up wandering tracker if present
    wanderingNPCs[data.npcId] = nil
    
    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Teleport NPC home and finalize ★★★
----------------------------------------------------------------------
local function onTeleportAndFinalize(data)
    if not data or not data.npcId then return end
    
    log("═══════════════════════════════════════════════════")
    log("TELEPORT AND FINALIZE for NPC", data.npcId)
    log("  Position:", data.position)
    
    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        -- Build home rotation
        local homeRotTransform = util.transform.rotateZ(data.homeRotation.z or 0) *
                                 util.transform.rotateY(data.homeRotation.y or 0) *
                                 util.transform.rotateX(data.homeRotation.x or 0)
        
        -- Teleport to home with correct rotation
        npc:teleport(data.cellName, data.position, {
            rotation = homeRotTransform,
            onGround = true
        })
        
        log("  ✓ NPC teleported to home position with correct rotation")
        
        -- Clear AI packages
        npc:sendEvent('RemoveAIPackages')
        
        -- Send ready event immediately (already at home with correct rotation)
        local player = world.players[1]
        if player then
            player:sendEvent('AntiTheft_NPCReady', { npcId = data.npcId })
            log("  ✓ Sent NPCReady event")
        end
    else
        log("  ERROR: NPC not found - sending ready anyway")
        local player = world.players[1]
        if player then
            player:sendEvent('AntiTheft_NPCReady', { npcId = data.npcId })
        end
    end
    
    -- Clean up wandering tracker if present
    wanderingNPCs[data.npcId] = nil
    
    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Cancel NPC return (for LOS detection) ★★★
----------------------------------------------------------------------
local function onCancelReturn(data)
    if not data or not data.npcId then return end
    
    log("═══════════════════════════════════════════════════")
    log("CANCELING RETURN for NPC", data.npcId)
    log("  Reason: Line of sight regained with player")
    
    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        npc:sendEvent('RemoveAIPackages')
        log("  ✓ AI packages removed - NPC can now follow player")
    end
    
    -- Remove from pending returns if present
    for i = #pendingReturns, 1, -1 do
        if pendingReturns[i].npcId == data.npcId then
            table.remove(pendingReturns, i)
            log("  ✓ Removed from pending returns queue")
        end
    end
    
    -- Remove from wandering tracker if present
    if wanderingNPCs[data.npcId] then
        wanderingNPCs[data.npcId] = nil
        log("  ✓ Removed from wandering tracker")
    end
    
    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Teleport Guard (for transition doors) ★★★
----------------------------------------------------------------------
local function onTeleportGuard(data)
    if not data or not data.npcId then return end

    log("═══════════════════════════════════════════════════")
    log("TELEPORT GUARD for transition door - NPC", data.npcId)
    log("  Target position:", data.position)
    log("  Cell:", data.cellName)

    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        -- Teleport guard to player's new position in same cell
        npc:teleport(data.cellName, data.position, { onGround = true })
        log("  ✓ Guard teleported to player's position through transition door")
    else
        log("  ERROR: Guard NPC not found for teleportation")
    end

    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- Finalize return: Directly teleport NPC with rotation (old working script)
----------------------------------------------------------------------
local function finalizeNPCReturn(npcId, homePosition, homeRotation)
    local npc = findNPC(npcId)
    if not (npc and npc:isValid()) then
        log("ERROR: NPC", npcId, "not found or invalid during finalize")
        local player = world.players[1]
        if player then
            player:sendEvent('AntiTheft_NPCReady', { npcId = npcId })
        end
        return false
    end

    npc:sendEvent('RemoveAIPackages')

    log("NPC", npcId, "reached home. Applying direct rotation teleport")
    log("  Target rotation - X:", math.deg(homeRotation.x), "Y:", math.deg(homeRotation.y), "Z:", math.deg(homeRotation.z))

    -- Build final rotation transform
    local finalRot = util.transform.rotateZ(homeRotation.z) *
                     util.transform.rotateY(homeRotation.y) *
                     util.transform.rotateX(homeRotation.x)

    -- Teleport NPC to home position with correct rotation
    npc:teleport(npc.cell.name, homePosition, {
        rotation = finalRot,
        onGround = true
    })

    log("NPC teleported to home with rotation - COMPLETE")

    -- Send ready event immediately
    local player = world.players[1]
    if player then
        player:sendEvent('AntiTheft_NPCReady', { npcId = npcId })
        log("  ✓ Sent NPCReady event")
    end

    return true
end

----------------------------------------------------------------------
-- ★★★ EVENT: Teleport NPC Home (for spell teleports) ★★★
----------------------------------------------------------------------
local function onTeleportHome(data)
    if not data or not data.npcId then return end

    log("═══════════════════════════════════════════════════")
    log("TELEPORT HOME for NPC", data.npcId, "(spell teleport)")
    log("  Home position:", data.homePosition)

    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        -- NPC is loaded, teleport immediately
        finalizeNPCReturn(data.npcId, data.homePosition, data.homeRotation)
    else
        -- NPC not loaded, add to pending teleports for when it loads
        log("  ⚠ NPC not found in loaded cells - adding to pending teleports")
        pendingTeleports[data.npcId] = {
            homePosition = data.homePosition,
            homeRotation = data.homeRotation
        }
    end

    -- Clean up wandering tracker if present
    wanderingNPCs[data.npcId] = nil

    log("═══════════════════════════════════════════════════")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Cleanup request ★★★
----------------------------------------------------------------------
local function onRequestCleanup(data)
    log("Cleanup request received from player script")
    log("  Global script state is clean")
end

----------------------------------------------------------------------
-- EVENT: player script orders a return-home (same cell)
----------------------------------------------------------------------
local function onStartReturnHome(data)
    if not data then
        log("ERROR: Received nil data in onStartReturnHome")
        return
    end

    if not data.npcId then
        log("ERROR: Missing npcId in return home event")
        return
    end

    if not data.homePosition then
        log("ERROR: Missing homePosition for NPC", data.npcId)
        return
    end

    if not data.homeRotation then
        log("ERROR: Missing homeRotation for NPC", data.npcId)
        return
    end

    log("═══════════════════════════════════════════════════")
    log("GLOBAL: Return home request for NPC", data.npcId)
    log("  (Player in same cell - using AI movement)")

    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        log("  ✓ NPC found - sending travel package")
        log("  Current position:", npc.position)
        log("  Home position:", data.homePosition)
        log("  Distance:", math.floor((npc.position - data.homePosition):length()), "units")

        -- Restore hello value if provided
        if data.originalHelloValue ~= nil then
            npc:sendEvent('AntiTheft_SetHello', { value = data.originalHelloValue })
            log("  ✓ Sent event to restore hello value to", data.originalHelloValue, "for NPC", data.npcId)
        end

        npc:sendEvent('RemoveAIPackages')
        npc:sendEvent('StartAIPackage', {
            type        = 'Travel',
            destPosition= data.homePosition,
            cancelOther = true
        })
        log("  ✓ Travel package sent")
    else
        log("  ⚠ NPC not found in loaded cells")
    end

    table.insert(pendingReturns, {
        npcId              = data.npcId,
        exactHomePosition  = data.homePosition,
        homeRotation       = data.homeRotation,
        timer              = 0.2,
        phase              = 1,
        totalTime          = 0,
        phase1Checks       = 0,
        stopCount          = 0,
        lastPosition       = nil
    })
    log("  ✓ Added to pending returns queue")
    log("═══════════════════════════════════════════════════")
end

local function onLowerCellDisposition(data)
    log("=== GLOBAL: LOWERING CELL DISPOSITION ===")
    local player = world.players[1]
    if not player or not player.cell then
        log("ERROR: Could not find player or player cell")
        return
    end

    local playerCell = player.cell
    log("Player cell:", playerCell.name)

    local count = 0
    for _, actor in ipairs(world.activeActors) do
        if actor.type == types.NPC and actor:isValid() and actor.cell == playerCell then
            local currentDisp = types.NPC.getBaseDisposition(actor, player) or 50
            local newDisp = math.max(0, currentDisp - 15)
            log("  Lowering NPC", actor.id, "base disposition:", currentDisp, "->", newDisp)
            types.NPC.modifyBaseDisposition(actor, player, -15)
            count = count + 1
        end
    end
    log("  Processed", count, "NPCs in cell")
    log("=== CELL DISPOSITION LOWERING COMPLETE ===")
end

----------------------------------------------------------------------
-- ★★★ EVENT: Set Hello Value ★★★
----------------------------------------------------------------------
local function onSetHello(data)
    if not data or not data.npcId or data.value == nil then return end

    log("═══════════════════════════════════════════════════")
    log("SETTING HELLO VALUE for NPC", data.npcId, "to", data.value)

    local npc = findNPC(data.npcId)
    if npc and npc:isValid() then
        types.NPC.stats.ai.hello(npc).base = data.value
        log("  ✓ Hello value set to", data.value, "for NPC", data.npcId)
    else
        log("  ERROR: NPC not found for hello value setting")
    end

    log("═══════════════════════════════════════════════════")
end

log("=== GLOBAL SCRIPT LOADED SUCCESSFULLY v18.1 ===")

----------------------------------------------------------------------
return {
    eventHandlers = {
        SHOP_UpdateSetting = onUpdateSetting,
        AntiTheft_StartReturnHome = onStartReturnHome,
        AntiTheft_StartWandering = onStartWandering,
        AntiTheft_StartWalkingHome = onStartWalkingHome,
        AntiTheft_FinalizeReturn = onFinalizeReturn,
        AntiTheft_PlaceReturningNPC = onPlaceReturningNPC,
        AntiTheft_TeleportAndFinalize = onTeleportAndFinalize,
        AntiTheft_CancelReturn = onCancelReturn,
        AntiTheft_TeleportGuard = onTeleportGuard,
        AntiTheft_TeleportHome = onTeleportHome,
        AntiTheft_RequestCleanup = onRequestCleanup,
        AntiTheft_LowerCellDisposition = onLowerCellDisposition
    },
    engineHandlers = {
        onUpdate = function(dt)
            processPendingReturns(dt)
            updateGlobalRotations(dt)

            -- Process pending teleports
            for npcId, teleportData in pairs(pendingTeleports) do
                local npc = findNPC(npcId)
                if npc and npc:isValid() then
                    log("Processing pending teleport for NPC", npcId)
                    finalizeNPCReturn(npcId, teleportData.homePosition, teleportData.homeRotation)
                    pendingTeleports[npcId] = nil
                end
            end

            -- Process 5-minute teleport timeouts
            local currentTime = core.getRealTime()
            for npcId, timeoutData in pairs(teleportTimeouts) do
                if currentTime >= timeoutData.timeoutTime then
                    log("5-minute timeout reached for NPC", npcId, "- teleporting to default position")
                    local npc = findNPC(npcId)
                    if npc and npc:isValid() then
                        finalizeNPCReturn(npcId, timeoutData.homePosition, timeoutData.homeRotation)
                    else
                        log("NPC", npcId, "not found for timeout teleport")
                    end
                    teleportTimeouts[npcId] = nil
                end
            end
        end
    }
}
