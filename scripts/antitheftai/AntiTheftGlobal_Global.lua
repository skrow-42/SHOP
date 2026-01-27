--[[
SHOP - Store & House Owner Patrol (NPC in interiors AI overhaul) for OpenMW.
This is the global script for proper write-enabled storage event handling.

Handles storage writes for NPC data and combat memory which cannot be done directly in player script due to read-only storage in player context.
]]

local core = require('openmw.core')
local storage = require('openmw.storage')
local utils = require('scripts.antitheftai.modules.utils')

local npcDataStorage = storage.globalSection('AntiTheftNPCData')

local function log(...)
    local args = {...}
    for i,v in ipairs(args) do
        args[i] = tostring(v)
    end
    print("[AntiTheft-Global]", table.unpack(args))
end

local eventHandlers = {}

function eventHandlers.AntiTheft_StoreNPCData(data)
    if not data or not data.npcId or not data.data then
        log("Received invalid data for AntiTheft_StoreNPCData event")
        return
    end
    local key = "npc_" .. tostring(data.npcId)
    local rotX, rotY, rotZ = 0, 0, 0
    if data.data.rot then
        rotX, rotY, rotZ = utils.getEulerAngles(data.data.rot)
    end
    local success, err = pcall(function()
        npcDataStorage:set(key, {
            cellName = data.data.cell.name or "unknown",
            posX = data.data.pos.x,
            posY = data.data.pos.y,
            posZ = data.data.pos.z,
            rotX = rotX,
            rotY = rotY,
            rotZ = rotZ,
            stored = true
        })
    end)
    if not success then
        print("[AntiTheft-Global] Warning: Failed to store NPC data for npcId " .. tostring(key) .. " - Error: " .. tostring(err))
    else
        log("Stored NPC data for npcId", data.npcId)
    end
end

function eventHandlers.AntiTheft_StoreCombatMemory(data)
    if not data or not data.npcId or data.wasInCombatWithPlayer == nil then
        log("Received invalid data for AntiTheft_StoreCombatMemory event")
        return
    end
    local key = "combat_" .. tostring(data.npcId)
    local success, err = pcall(function()
        npcDataStorage:set(key, {
            wasInCombatWithPlayer = data.wasInCombatWithPlayer,
            stored = true
        })
    end)
    if not success then
        print("[AntiTheft-Global] Warning: Failed to store combat memory for npcId " .. tostring(key) .. " - Error: " .. tostring(err))
    else
        log("Stored combat memory for npcId", data.npcId)
    end
end

return {
    eventHandlers = eventHandlers
}
