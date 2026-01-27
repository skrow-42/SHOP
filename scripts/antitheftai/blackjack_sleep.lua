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
-- Blackjack Sleep Effect Handler - LOCAL SCRIPT for NPCs
-- Handles sleep effects when NPC is hit by blackjack weapons
-- Integrates with detd_sleep_spell3 from another mod
----------------------------------------------------------------------

local self = require('openmw.self')
local types = require('openmw.types')
local time = require('openmw_aux.time')
local core = require('openmw.core')
local async = require('openmw.async')
local nearby = require('openmw.nearby')  -- For accessing nearby actors
local util = require('openmw.util')  -- For vector3 operations

-- Blackjack weapon IDs that trigger sleep effects
local BLACKJACK_WEAPONS = {
    ['blackjack-wooden'] = true,
    ['blackjack-iron'] = true,
    ['blackjack-imperial'] = true,
    ['blackjack-dwemer'] = true,
    ['blackjack-wooden-operative'] = true,
    ['blackjack-iron-operative'] = true,
    ['blackjack-imperial-operative'] = true,
    ['blackjack-dwemer-operative'] = true,
    ['blackjack-wooden-masterthief'] = true,
    ['blackjack-iron-masterthief'] = true,
    ['blackjack-imperial-masterthief'] = true,
    ['blackjack-dwemer-masterthief'] = true,
    ['blackjack-wooden-weighted'] = true,
    ['blackjack-iron-weighted'] = true,
    ['blackjack-imperial-weighted'] = true,
    ['blackjack-dwemer-weighted'] = true,
    ['blackjack-wooden-nimble'] = true,
    ['blackjack-iron-nimble'] = true,
    ['blackjack-imperial-nimble'] = true,
    ['blackjack-dwemer-nimble'] = true,
    ['blackjack-wooden-masterwork'] = true,
    ['blackjack-iron-masterwork'] = true,
    ['blackjack-imperial-masterwork'] = true,
    ['blackjack-dwemer-masterwork'] = true,
    ['blackjack-wooden-extended'] = true,
    ['blackjack-iron-extended'] = true,
    ['blackjack-imperial-extended'] = true,
    ['blackjack-dwemer-extended'] = true
}

-- List of weighted blackjacks for stun duration bonus
local WEIGHTED_BLACKJACKS = {
    ['blackjack-wooden-weighted'] = true,
    ['blackjack-iron-weighted'] = true,
    ['blackjack-imperial-weighted'] = true,
    ['blackjack-dwemer-weighted'] = true
}

local settings = require('scripts.antitheftai.SHOPsettings')

local SLEEP_SPELL_ID = 'detd_sleep_spell3'
local SLEEP_DURATION = 60  -- seconds
local ILLEGAL_SLEEP_VALUE = 99

-- State tracking
local doOnce = 0
local sleepTimerHandle = nil
local originalHelloValue = nil  -- Store original hello value to restore later
local originalAlarmValue = nil  -- Store original alarm value to restore later
local wasSpottedDuringHit = false  -- Track if player was spotted when blackjack hit occurred
local wasDiscoveredByOthers = false  -- Track if body was discovered by another NPC
local witnessTimer = nil  -- 60-second timer for victim witness detection

print("[BLACKJACK SLEEP] Script loaded for NPC:", self.id)

----------------------------------------------------------------------
-- On Hit Handler - Detects blackjack weapon hits and applies spell
----------------------------------------------------------------------
local function onHit(attack)
    -- Check if hit by a weapon
    if not attack.weapon then
        return  -- Not a weapon attack, allow normal processing
    end
    
    -- Get weapon record ID
    local weaponRecord = types.Weapon.record(attack.weapon)
    if not weaponRecord or not weaponRecord.id then
        return  -- No weapon record, allow normal processing
    end
    
    local weaponId = weaponRecord.id:lower()
    print("[BLACKJACK SLEEP] NPC", self.id, "hit by weapon:", weaponId)
    
    -- Check if it's a blackjack weapon
    if not BLACKJACK_WEAPONS[weaponId] then
        print("[BLACKJACK SLEEP] Not a blackjack weapon, allowing normal hit processing")
        return  -- Not a blackjack, allow normal processing
    end
    
    print("[BLACKJACK SLEEP] ★★★ BLACKJACK HIT DETECTED! ★★★")
    
    -- Check if attacker exists and is the player
    if not attack.attacker then
        print("[BLACKJACK SLEEP] No attacker found, canceling attack anyway")
        if attack.damage then
            for stat, _ in pairs(attack.damage) do
                attack.damage[stat] = 0
            end
        end
        return false
    end
    
    -- Calculate if attack is from behind
    local util = require('openmw.util')
    local npcPos = self.position
    local attackerPos = attack.attacker.position
    
    -- Get NPC's facing direction (forward vector)
    local npcRotation = self.rotation
    local npcForward = npcRotation * util.vector3(0, 1, 0)  -- Forward is +Y in OpenMW
    
    -- Calculate direction from NPC to attacker
    local toAttacker = util.vector3(
        attackerPos.x - npcPos.x,
        attackerPos.y - npcPos.y,
        0  -- Ignore Z for horizontal angle
    )
    
    -- Normalize vectors (get unit vectors)
    local npcForwardNorm = util.vector3(npcForward.x, npcForward.y, 0):normalize()
    local toAttackerNorm = toAttacker:normalize()
    
    -- Calculate dot product (ranges from -1 to 1)
    -- -1 = directly behind, 0 = perpendicular, 1 = directly in front
    local dotProduct = npcForwardNorm.x * toAttackerNorm.x + npcForwardNorm.y * toAttackerNorm.y
    
    print("[BLACKJACK SLEEP] Attack direction check:")
    print("[BLACKJACK SLEEP]   - Dot product:", dotProduct)
    print("[BLACKJACK SLEEP]   - NPC forward:", npcForwardNorm.x, npcForwardNorm.y)
    print("[BLACKJACK SLEEP]   - To attacker:", toAttackerNorm.x, toAttackerNorm.y)
    
    -- Check if attack is from behind (dot product < 0 means behind)
    -- Using threshold of 0.0 means exactly perpendicular or behind
    -- Using -0.3 would allow some side attacks, using 0.3 would be more strict
    local isFromBehind = dotProduct < -0.1
    
    if not isFromBehind then
        print("[BLACKJACK SLEEP] ✗ Attack NOT from behind (frontside/side attack) - sleep will NOT be applied")
        print("[BLACKJACK SLEEP]   - Allowing normal attack processing - NPC will become aggressive!")
        -- Do NOT cancel the attack - let normal combat/crime happen
        return  -- Allow normal attack processing
    end
    
    print("[BLACKJACK SLEEP] ✓ Attack IS from behind - proceeding with sleep application")
    
    -- Check fight value
    local FightValue = types.Actor.stats.ai.fight(self).base
    if FightValue >= 90 then
        print("[BLACKJACK SLEEP] Fight value too high (", FightValue, "), sleep not applied but canceling attack anyway")
        -- Still cancel the attack to prevent combat/crime
        if attack.damage then
            for stat, _ in pairs(attack.damage) do
                attack.damage[stat] = 0
            end
        end
        return false  -- Cancel attack processing
    end
    
    -- Calculate Dynamic Sleep Duration
    -- Formula: (Str + Sneak + Blunt) * 0.1 +/- 15% random variance
    -- Bonus: +15% if weighted blackjack
    local attackerStr = 50
    local attackerSneak = 50
    local attackerBlunt = 50
    
    if attack.attacker.type == types.Player then
        attackerStr = types.Actor.stats.attributes.strength(attack.attacker).modified
        attackerSneak = types.Player.stats.skills.sneak(attack.attacker).modified
        attackerBlunt = types.Player.stats.skills.bluntweapon(attack.attacker).modified
    elseif attack.attacker.type == types.NPC then
        attackerStr = types.Actor.stats.attributes.strength(attack.attacker).modified
        attackerSneak = types.NPC.stats.skills.sneak(attack.attacker).modified
        attackerBlunt = types.NPC.stats.skills.bluntweapon(attack.attacker).modified
    end
    
    local baseDuration = (attackerStr + attackerSneak + attackerBlunt) * 0.1
    
    -- Apply Random Variance (+/- 15%)
    local variance = (math.random() * 0.30) - 0.15 -- -0.15 to +0.15
    local duration = baseDuration * (1.0 + variance)
    
    -- Apply Weighted Bonus
    if WEIGHTED_BLACKJACKS[weaponId] then
        duration = duration * 1.15
        print("[BLACKJACK SLEEP] Weighted blackjack bonus applied (+15%)")
    end
    
    -- Store calculated duration for this knockout instance
    calculatedSleepDuration = duration
    print(string.format("[BLACKJACK SLEEP] Dynamic Stun Duration: %.2fs (Base: %.2f, Stats: Str %d/Snk %d/Blunt %d)", duration, baseDuration, attackerStr, attackerSneak, attackerBlunt))

    -- Apply the sleep spell
    local success, err = pcall(function()
        types.Actor.spells(self):add(SLEEP_SPELL_ID)
        print("[BLACKJACK SLEEP] Sleep spell applied successfully to NPC:", self.id)
        
        -- Send success event to attacker (Player) for XP and Durability handling
        if attack.attacker and attack.attacker.type == types.Player then
            attack.attacker:sendEvent('AntiTheft_BlackjackSuccess', { 
                weapon = attack.weapon 
            })
            print("[BLACKJACK SLEEP] Sent AntiTheft_BlackjackSuccess event to player")
        end
    end)
    
    if not success then
        --print("[BLACKJACK SLEEP] ERROR applying spell:", err)
    else
       -- Check if player was already spotted BEFORE the blackjack hit
        -- ErnBurglary applies a Drain Sneak effect when player is spotted
        local isPlayerSpotted = false
        if attack.attacker then
            local playerEffects = types.Actor.activeEffects(attack.attacker)
            if playerEffects then
                local drainSneakEffect = playerEffects:getEffect(core.magic.EFFECT_TYPE.DrainSkill, 'sneak')
                if drainSneakEffect and drainSneakEffect.magnitude > 0 then
                    isPlayerSpotted = true
                    print("[BLACKJACK SLEEP] Detected Drain Sneak effect - player is spotted")
                end
            end
        end
        
        print("[BLACKJACK SLEEP] ErnBurglary spotted status:", isPlayerSpotted)
        
        -- Store spotted status - event will be sent from repeating check
        wasSpottedDuringHit = isPlayerSpotted
        if isPlayerSpotted then
            print("[BLACKJACK SLEEP] Player was spotted - bounty will be applied from repeating check")
        else
            print("[BLACKJACK SLEEP] Player was NOT spotted - stealthy takedown, no bounty")
        end
        
        -- IMMEDIATELY disable alarm and hello to prevent crime detection
        -- Don't wait for the repeating check - there's a crucial timing window
        if not originalHelloValue then
            originalHelloValue = types.NPC.stats.ai.hello(self).base
            print("[BLACKJACK SLEEP] Stored original hello value:", originalHelloValue)
        end
        
        if not originalAlarmValue then
            originalAlarmValue = types.NPC.stats.ai.alarm(self).base
            print("[BLACKJACK SLEEP] Stored original alarm value:", originalAlarmValue)
        end
        
        types.NPC.stats.ai.hello(self).base = 0
        types.NPC.stats.ai.alarm(self).base = 0
        print("[BLACKJACK SLEEP] IMMEDIATELY disabled hello and alarm to prevent crime detection")
        
        -- Apply blind effect using ActorActiveEffects:set() for 100% blindness
        local blindSuccess, blindErr = pcall(function()
            types.Actor.activeEffects(self):set(100, core.magic.EFFECT_TYPE.Blind)
        end)
        
        if blindSuccess then
            print("[BLACKJACK SLEEP] Applied blind effect (magnitude 100) - NPC is 100% blind")
        else
            print("[BLACKJACK SLEEP] ERROR applying blind effect:", blindErr)
        end
        
        -- Play sound effect for successful blackjack hit
        --local soundPath
        
        --print("[BLACKJACK SLEEP] Checking weapon type for sound. weaponId =", weaponId)
        
        -- Check if wooden blackjack
        --if weaponId == 'blackjack-wooden' or weaponId == 'blackjack-wooden-5' or weaponId == 'blackjack-wooden-10' then
        --    soundPath = "sound/slam/bwooden1.mp3"
        --    print("[BLACKJACK SLEEP] Playing wooden blackjack sound:", soundPath)
        --else
            -- Metal blackjack - play random metal sound (bmetal1 to bmetal5)
         --   local randomNum = math.random(1, 5)
         --   soundPath = "sound/slam/bmetal" .. randomNum .. ".mp3"
         --   print("[BLACKJACK SLEEP] Playing metal blackjack sound:", soundPath)
        --end
        
        -- Play the sound at NPC's position
        --core.sound.playSoundFile3d(soundPath, self, {
         --   volume = 1.0,
          --  pitch = 0.9 + math.random() * 0.2,  -- Random between 0.9 and 1.1
          --  loop = false
        --})
       -- print("[BLACKJACK SLEEP] Sound played successfully")
    end
    
    -- CRITICAL: Zero out all damage to prevent health loss
    if attack.damage then
        print("[BLACKJACK SLEEP] Zeroing out damage to prevent health loss")
        for stat, value in pairs(attack.damage) do
            print("[BLACKJACK SLEEP]   - Removing", value, stat, "damage")
            attack.damage[stat] = 0
        end
    end
    
    -- CRITICAL: Return false to cancel attack processing
    -- This prevents combat detection and bounty/crime
    print("[BLACKJACK SLEEP] Returning false to cancel combat/crime detection")
    return false
end

-- Register the onHit handler using the correct interface name
local I = require('openmw.interfaces')
if I.Combat and I.Combat.addOnHitHandler then
    I.Combat.addOnHitHandler(onHit)
    print("[BLACKJACK SLEEP] OnHit handler registered successfully")
else
    print("[BLACKJACK SLEEP] ERROR: Combat.addOnHitHandler not available!")
    print("[BLACKJACK SLEEP] Available interfaces:", I)
end

----------------------------------------------------------------------
-- Main repeating check (runs every second)
-- Manages fatigue, duration timer, and wakeup logic
----------------------------------------------------------------------
local stopFn = time.runRepeatedly(function()
    -- Safety check: ensure NPC type has necessary functions
    if not types.Actor or not types.Actor.stats or not types.Actor.activeSpells then
        return
    end

    local FightValue = types.Actor.stats.ai.fight(self).base
    local StanceValue = types.Actor.getStance(self)
    local HealthValueB = types.Actor.stats.dynamic.health(self).base
    local HealthValueC = types.Actor.stats.dynamic.health(self).current
    
    -- Check if sleep spell is active
    local isSleepActive = types.Actor.activeSpells(self):isSpellActive(SLEEP_SPELL_ID)
    
    -- If sleep spell is active and NPC is in normal stance, drain fatigue
    if isSleepActive and StanceValue == 0 then
        types.Actor.stats.dynamic.fatigue(self).current = -45
        
        -- **PULSE DETECTION: Scan for conscious NPCs within 800 units**
        -- This runs every second while unconscious
        -- **VISUAL SCAN: Nearby NPCs checking for bodies**
        -- Only scan if not yet discovered to prevent spam and repeated bounties
        if doOnce == 1 and not wasDiscoveredByOthers then
            -- print("[VISUAL SCAN] Emitting detection scan from unconscious NPC", self.id)
            
            local myPos = self.position
            local player = nearby.players[1]  -- Get player from nearby module in NPC script
            
            -- Scan all nearby actors
            for _, actor in ipairs(nearby.actors) do
                if actor.type == types.NPC and actor.id ~= self.id then
                    
                    -- Check if potential observer is conscious (no sleep spell)
                    local isObserverConscious = not types.Actor.activeSpells(actor):isSpellActive(SLEEP_SPELL_ID)
                    
                    if isObserverConscious then
                        local dist = (actor.position - myPos):length()
                        
                        -- Vision range: 1500 units
                        if dist <= 1500 then
                            
                            -- Field of View Check (120 degrees - Frontal Cone)
                            -- This prevents guards from detecting bodies behind them
                            local toTarget = myPos - actor.position
                            local actorForward = actor.rotation:apply(util.vector3(0, 1, 0))
                            local angle = actorForward:dot(toTarget:normalize())
                            
                            -- Dot > 0.5 is approx 60 degrees either side (120 deg total)
                            if angle > 0.5 then 
                                -- Calculate rigorous Line of Sight
                                -- Origin: Observer's Eye Level (90 units up)
                                local observerEyePos = actor.position + util.vector3(0, 0, 90)
                                
                                -- Targets: Victim Body Parts (Prone on ground)
                                local vFeet = myPos + util.vector3(0, 0, 5)     -- Feet
                                local vTorso = myPos + util.vector3(0, 0, 10)   -- Torso
                                local vHead = myPos + util.vector3(0, 0, 15)    -- Head
                                
                                -- Cast Rays with strict collisionType=3 (Actors + World)
                                -- This matches standard detection logic for walls/statics
                                local rayOpts = {
                                    collisionType = 3, -- 3 = World + Actors
                                    ignore = {actor}   -- Ignore the observer
                                }
                                
                                -- Explicitly define helper to check visibility
                                local function checkPart(targetPos, name)
                                    local ray = nearby.castRay(observerEyePos, targetPos, rayOpts)
                                    
                                    -- Debug Logging for Verification
                                    -- Only log if we effectively HIT something that isn't the victim
                                    if ray.hit then
                                        if ray.hitObject and ray.hitObject.id == self.id then
                                            -- Hit the victim -> VISIBLE
                                            -- print("[VISUAL DEBUG]", name, "VISIBLE (Ray hit victim)")
                                            return true
                                        else
                                            -- Hit something else -> BLOCKED
                                            -- print("[VISUAL DEBUG]", name, "BLOCKED by", ray.hitObject and ray.hitObject.recordId or "Unknown Geometry")
                                            return false
                                        end
                                    else
                                        -- Hit nothing -> CLEAR LINE using collisionType logic
                                        -- print("[VISUAL DEBUG]", name, "VISIBLE (Clear Line)")
                                        return true
                                    end
                                end
                                
                                local canSeeFeet = checkPart(vFeet, "Feet")
                                local canSeeTorso = checkPart(vTorso, "Torso")
                                local canSeeHead = checkPart(vHead, "Head")
                                
                                if canSeeFeet or canSeeTorso or canSeeHead then
                                    -- Guard Check Helper (Inline for scope access)
                                    local function isGuard(npc)
                                        if not npc then return false end
                                        local record = types.NPC.record(npc)
                                        if not (record and record.class) then return false end
                                        local class = record.class:lower()
                                        return class:find("guard") or class:find("ordinator") or class:find("buoyant") or class:find("lex")
                                    end

                                    -- NPC discovered the body!
                                    print("[ANTI-THEFT] ★★★ BODY DISCOVERED! Witness:", actor.id, "saw unconscious NPC", self.id)
                                
                                    -- Apply bounty if player wasn't spotted during the hit (and bounty not yet applied)
                                    if not wasSpottedDuringHit and player then
                                        print("[ANTI-THEFT] Crime reported! Applying bounty.")
                                        -- Pass table with AMOUNT and WITNESS ID
                                        -- TARGETING PLAYER SCRIPT directly (corrected from Global)
                                        player:sendEvent("AntiTheft_Relay_SleepBounty", { 
                                            amount = 300, 
                                            npcId = actor.id 
                                        })
                                        wasSpottedDuringHit = true
                                    end
                                    
                                    -- Send discovering NPC into action
                                    if player then
                                        -- Notify player script to expect combat/arrest from this witness (prevents disband)
                                        player:sendEvent("AntiTheft_NotifyWitnessAttack", { npcId = actor.id })
                                        
                                        if isGuard(actor) then
                                            print("[ANTI-THEFT] Witness is GUARD - Initiating ARREST (Pursue + ForceDialog)")
                                            
                                            -- Revert to 'Pursue' pkg as requested.
                                            -- Added 0.3s delay to ensure bounty is applied first (Race Condition Fix).
                                            async:newUnsavableSimulationTimer(0.3, function()
                                                if actor and actor:isValid() and player then
                                                    actor:sendEvent('StartAIPackage', {
                                                        type = 'Pursue',
                                                        target = player
                                                    })
                                                end
                                            end)
                                            
                                            -- Notify player script to monitor distance and force dialogue (Safety Net)
                                        else
                                            print("[ANTI-THEFT] Witness is CIVILIAN")
                                            
                                            -- 50/50 Chance: Combat or Scream/Flee
                                            if math.random() > 0.5 then
                                                print("   -> Decision: COMBAT")
                                                actor:sendEvent('StartAIPackage', {
                                                    type = 'Combat',
                                                    target = player
                                                })
                                            else
                                                print("   -> Decision: SCREAM (Voice)")
                                                -- Attempt to play voice from bed_voices
                                                local bedVoices = require('scripts.antitheftai.modules.bed_voices')
                                                local record = types.NPC.record(actor)
                                                if record and bedVoices then
                                                    local race = record.race:lower()
                                                    local gender = record.isMale and "male" or "female"
                                                    
                                                    -- Normalize race string
                                                    race = race:gsub(" ", "") 
                                                    
                                                    local voicesMap = bedVoices[race]
                                                    if not voicesMap then
                                                        voicesMap = bedVoices[record.race:lower()]
                                                    end
                                                    
                                                    if voicesMap and voicesMap[gender] then
                                                        local list = voicesMap[gender]
                                                        if #list > 0 then
                                                            local entry = list[math.random(#list)]
                                                            core.sound.say(entry.response, entry.file)
                                                            print("[ANTI-THEFT] Played voice:", entry.file)
                                                        end
                                                    else
                                                        print("[ANTI-THEFT] No voice found for", race, gender)
                                                        actor:sendEvent('StartAIPackage', {
                                                            type = 'Combat',
                                                            target = player
                                                        })
                                                    end
                                                end
                                            end
                                        end
                                        
                                        -- **chain reaction ALARM**: Witness alerts other nearby NPCs
                                        -- Radius: 1000 units around the WITNESS position
                                        print("[ANTI-THEFT] Witness shouting alarm! Alerting neighbors within 1000u")
                                        
                                        for _, neighbor in ipairs(nearby.actors) do
                                            -- Filter: Must be NPC, Not Witness, Not Victim
                                            if neighbor.type == types.NPC and neighbor.id ~= actor.id and neighbor.id ~= self.id then
                                                -- Check distance to WITNESS
                                                local distToWitness = (neighbor.position - actor.position):length()
                                                
                                                if distToWitness <= 1000 then
                                                    -- Ensure neighbor is conscious
                                                    local isNeighborConscious = not types.Actor.activeSpells(neighbor):isSpellActive(SLEEP_SPELL_ID)
                                                    
                                                    if isNeighborConscious then
                                                        print("[ANTI-THEFT] Neighbor alerted by alarm:", neighbor.id)
                                                        
                                                        -- Notify player script (prevent disband) + Expect Arrest if Guard
                                                        player:sendEvent("AntiTheft_NotifyWitnessAttack", { npcId = neighbor.id })
                                                        
                                                        -- Engage Combat or Arrest
                                                        if isGuard(neighbor) then
                                                            print("   -> Neighbor is Guard: Arresting (Pursue)")
                                                            async:newUnsavableSimulationTimer(0.35, function()
                                                                if neighbor and neighbor:isValid() and player then
                                                                    neighbor:sendEvent('StartAIPackage', {
                                                                        type = 'Pursue',
                                                                        target = player
                                                                    })
                                                                end
                                                            end)
                                                        else
                                                            print("   -> Neighbor is Civilian: Combat")
                                                            neighbor:sendEvent('StartAIPackage', {
                                                                type = 'Combat',
                                                                target = player
                                                            })
                                                        end
                                                    end
                                                end
                                            end
                                        end
                                    end
                                
                                -- Mark as discovered to STOP further scans
                                wasDiscoveredByOthers = true
                                
                                -- Stop checking other NPCs immediately
                                break
                            end
                        end
                    end
                end
                end
            end
        end
        
        -- Disable NPC interaction (prevent dialogue/recruitment) while unconscious
        if not originalHelloValue then
            -- Store original hello value first time
            originalHelloValue = types.NPC.stats.ai.hello(self).base
            print("[BLACKJACK SLEEP] Stored original hello value:", originalHelloValue)
        end
        
        -- Store original alarm value to prevent crime detection
        if not originalAlarmValue then
            originalAlarmValue = types.NPC.stats.ai.alarm(self).base
            print("[BLACKJACK SLEEP] Stored original alarm value:", originalAlarmValue)
        end
        
        -- Set hello to 0 to prevent interaction
        if types.NPC.stats.ai.hello(self).base ~= 0 then
            types.NPC.stats.ai.hello(self).base = 0
            print("[BLACKJACK SLEEP] Disabled NPC interaction (hello = 0) - NPC cannot be recruited")
        end
        
        -- Set alarm to 0 to prevent crime detection
        if types.NPC.stats.ai.alarm(self).base ~= 0 then
            types.NPC.stats.ai.alarm(self).base = 0
            print("[BLACKJACK SLEEP] Disabled crime detection (alarm = 0) - NPC cannot report crimes")
        end
    end
    
    -- Send global event once when sleep spell activates (if fight value is low)
    -- If player was spotted during blackjack hit, send the bounty event
    if doOnce == 0 and StanceValue == 0 and FightValue < 90 and isSleepActive then
        doOnce = 1
        
        if wasSpottedDuringHit then
            -- Player was spotted - send bounty event (like illegal sleep spell would)
            print("[BLACKJACK SLEEP] Sending bounty event - player was spotted during blackjack")
            local stunBounty = settings.bounties:get('stunNPCBounty') or 300
            core.sendGlobalEvent("AntiTheft_Relay_SleepBounty", stunBounty)
        else
            -- Player was not spotted - stealthy takedown, no bounty event
            print("[BLACKJACK SLEEP] Sleep activated (NO crime event sent - blackjack is legal stealth)")
        end
        
        -- Notify global script that this NPC is now unconscious
        -- Send through player relay since NPC scripts can't send to global directly
        core.sendGlobalEvent('AntiTheft_Relay_NPCUnconscious', {
            npcId = self.id,
            wasSpotted = wasSpottedDuringHit
        })
        print("[BLACKJACK SLEEP] Sent unconscious event via player relay - wasSpotted:", wasSpottedDuringHit)
        
        -- Start custom duration timer (remove spell after DYNAMIC duration seconds)
        local duration = calculatedSleepDuration or SLEEP_DURATION -- Use calculated if available, else default
        print("[BLACKJACK SLEEP] Starting sleep timer for duration:", duration)
        
        if not sleepTimerHandle then
            sleepTimerHandle = async:newUnsavableSimulationTimer(duration, function()
                print("[BLACKJACK SLEEP] Duration timer expired")
                
                -- Wrap in pcall to prevent crash and ensure handle reset
                local success, err = pcall(function()
                    -- Force remove spell without checking active status (safe to remove even if not active)
                    -- Check if types.Actor.spells exists
                    if types.Actor.spells then
                        types.Actor.spells(self):remove(SLEEP_SPELL_ID)
                        print("[BLACKJACK SLEEP] Removed sleep spell")
                    else
                        print("[BLACKJACK SLEEP] ERROR: types.Actor.spells is nil")
                    end

                    -- Check if types.Actor.stats exists
                    if types.Actor.stats and types.Actor.stats.dynamic and types.Actor.stats.dynamic.fatigue then
                        types.Actor.stats.dynamic.fatigue(self).current = 10
                        print("[BLACKJACK SLEEP] Restored fatigue to 10")
                    else
                        print("[BLACKJACK SLEEP] ERROR: types.Actor.stats.dynamic.fatigue is nil")
                    end
                end)
                
                if not success then
                    print("[BLACKJACK SLEEP] CRITICAL ERROR in timer callback:", err)
                    -- Attempt emergency wake up
                    pcall(function() types.Actor.stats.dynamic.fatigue(self).current = 10 end)
                end
                sleepTimerHandle = nil  -- Reset latch
            end)
        end
    end
    
    -- If NPC takes damage while sleeping, wake them up
    if HealthValueB > HealthValueC and isSleepActive then
        print("[BLACKJACK SLEEP] NPC took damage while sleeping, waking up")
        types.Actor.spells(self):remove(SLEEP_SPELL_ID)
        types.Actor.stats.dynamic.fatigue(self).current = 10
        
        -- Cancel the sleep timer if it's running
        if sleepTimerHandle then
            sleepTimerHandle = nil
        end
    end
    
    -- Reset doOnce flag when spell ends AND restore hello/alarm values
    if doOnce == 1 and not isSleepActive then
        doOnce = 0
        print("[BLACKJACK SLEEP] Spell ended, resetting state")
        
        -- Restore original hello value
        if originalHelloValue then
            types.NPC.stats.ai.hello(self).base = originalHelloValue
            print("[BLACKJACK SLEEP] Restored hello value to:", originalHelloValue)
            originalHelloValue = nil  -- Clear stored value
        end
        
        -- Restore original alarm value
        if originalAlarmValue then
            types.NPC.stats.ai.alarm(self).base = originalAlarmValue
            print("[BLACKJACK SLEEP] Restored alarm value to:", originalAlarmValue)
            originalAlarmValue = nil  -- Clear stored value
        end
        
        -- Remove blind effect
        local removeBlindSuccess, removeBlindErr = pcall(function()
            types.Actor.activeEffects(self):remove(core.magic.EFFECT_TYPE.Blind)
        end)
        
        if removeBlindSuccess then
            print("[BLACKJACK SLEEP] Removed blind effect - NPC vision restored")
        else
            print("[BLACKJACK SLEEP] Could not remove blind effect:", removeBlindErr)
        end
        
        -- Notify global script that NPC is conscious again
        -- This will cancel the detection pulse
        -- Notify global script that NPC is conscious again
        -- This will cancel the detection pulse and trigger wake-up wander
        core.sendGlobalEvent('AntiTheft_NPCConscious', {
            npcId = self.id
        })
        print("[BLACKJACK SLEEP] Sent conscious event directly to global - pulse cancelled / wander started")
        
        -- Check if NPC was discovered by others while unconscious
        if not wasDiscoveredByOthers then
            -- NPC was NOT discovered - start 60-second witness timer
            print("[BLACKJACK SLEEP] ★ NPC woke up undiscovered - starting 60-second witness window")
            
            local witnessStartTime = core.getRealTime()
            local witnessEndTime = witnessStartTime + 60
            
            -- Helper function for recursion
            local witnessCallback 
            witnessCallback = function()
                local currentTime = core.getRealTime()
                
                -- Check if 60 seconds have passed
                if currentTime >= witnessEndTime then
                    print("[BLACKJACK SLEEP] Witness window expired - NPC did not spot player")
                    witnessTimer = nil
                    return
                end
                
                -- Check if NPC can see player
                local player = nearby.players[1]
                
                if player then
                    -- Calculate distance to player
                    local dist = (self.position - player.position):length()
                    
                    -- Only check LoS if within reasonable range (e.g., 2000 units)
                    if dist <= 2000 then
                        -- Check line of sight using nearby module
                        -- Use eye level (approx +150 units z) to avoid ground clutter/terrain blocking
                        local zOffset = util.vector3(0, 0, 150)
                        local startPos = self.position + zOffset
                        local endPos = player.position + zOffset
                        local rayResult = nearby.castRay(startPos, endPos)
                        
                        if not rayResult or not rayResult.hit then
                            -- Player spotted! Apply bounty and attack
                            print("[BLACKJACK SLEEP] ★★★ VICTIM SPOTTED PLAYER ★★★")
                            
                            -- CANCEL WAKE UP WANDER IMMEDIATELY
                            core.sendGlobalEvent('AntiTheft_StopWakeUpWander', { npcId = self.id })
                            
                            local stunBounty = settings.bounties:get('stunNPCBounty') or 300
                            
                            -- Guard Check Helper
                            local function isGuard(npc)
                                if not npc then return false end
                                local record = types.NPC.record(npc)
                                if not (record and record.class) then return false end
                                local class = record.class:lower()
                                return class:find("guard") or class:find("ordinator") or class:find("buoyant") or class:find("lex")
                            end

                            -- Apply bounty if player wasn't spotted during the hit (and bounty not yet applied)
                            -- Note: This block runs if player IS spotted just now upon waking
                            print("[BLACKJACK SLEEP] Applying " .. stunBounty .. " gold bounty for witness (Victim)")
                            
                            -- Send bounty event through player relay (Targeting Player Script)
                            player:sendEvent("AntiTheft_Relay_SleepBounty", { 
                                amount = stunBounty, 
                                npcId = self.id 
                            })
                            
                            -- Notify player script to expect combat/arrest from this witness
                            player:sendEvent("AntiTheft_NotifyWitnessAttack", { npcId = self.id })
                            
                            if isGuard(self) then
                                print("[BLACKJACK SLEEP] Victim is GUARD - Initiating ARREST (Pursue + ForceDialog)")
                                
                                -- Revert to 'Pursue' pkg as requested.
                                -- Added 0.3s delay to ensure bounty is applied first
                                async:newUnsavableSimulationTimer(0.3, function()
                                    if self and self:isValid() and player then
                                        self:sendEvent('StartAIPackage', {
                                            type = 'Pursue',
                                            target = player
                                        })
                                    end
                                end)
                                
                                -- Notify player script to monitor distance and force dialogue
                                player:sendEvent("AntiTheft_ExpectArrest", { npcId = self.id })
                            else
                                print("[BLACKJACK SLEEP] Victim is CIVILIAN")
                                
                                -- 50/50 Chance: Combat or Scream/Flee
                                if math.random() > 0.5 then
                                    print("   -> Decision: COMBAT")
                                    self:sendEvent('StartAIPackage', {
                                        type = 'Combat',
                                        target = player
                                    })
                                else
                                    print("   -> Decision: SCREAM (Voice)")
                                    -- Attempt to play voice from bed_voices
                                    local bedVoices = require('scripts.antitheftai.modules.bed_voices')
                                    local record = types.NPC.record(self)
                                    if record and bedVoices then
                                        local race = record.race:lower()
                                        local gender = record.isMale and "male" or "female"
                                        
                                        -- Normalize race string
                                        race = race:gsub(" ", "") 
                                        
                                        local voicesMap = bedVoices[race]
                                        if not voicesMap then
                                            voicesMap = bedVoices[record.race:lower()]
                                        end
                                        
                                        if voicesMap and voicesMap[gender] then
                                            local list = voicesMap[gender]
                                            if #list > 0 then
                                                local entry = list[math.random(#list)]
                                                core.sound.say(entry.response, entry.file)
                                                print("[BLACKJACK SLEEP] Played voice:", entry.file)
                                            end
                                        else
                                            print("[BLACKJACK SLEEP] No voice found for", race, gender)
                                            -- Fallback to combat if no voice
                                            self:sendEvent('StartAIPackage', {
                                                type = 'Combat',
                                                target = player
                                            })
                                        end
                                    end
                                end
                            end
                            
                            -- Cancel witness timer
                            witnessTimer = nil
                            return
                        end
                    end
                end
                
                -- Continue witness timer for next second
                -- Use the FUNCTION itself as the callback, not the handle
                witnessTimer = async:newUnsavableSimulationTimer(1, witnessCallback)
            end
            
            -- Start the timer
            witnessTimer = async:newUnsavableSimulationTimer(1, witnessCallback)
        else
            print("[BLACKJACK SLEEP] NPC was discovered by others - no witness timer")
        end
        
        -- Reset discovered flag for future blackjack hits
        wasDiscoveredByOthers = false
        
        -- Cancel the sleep timer if it's running
        if sleepTimerHandle then
            sleepTimerHandle = nil
        end
    end
    
end, 1 * time.second)  -- Check every second

----------------------------------------------------------------------
-- Return event handlers for body discovery tracking
----------------------------------------------------------------------
return {
    eventHandlers = {
        -- Event sent by global script when this NPC's unconscious body is discovered
        AntiTheft_BodyDiscovered = function(data)
            if data and data.npcId == self.id then
                -- This NPC's body was discovered by another NPC
                wasDiscoveredByOthers = true
                print("[BLACKJACK SLEEP] Body discovered by another NPC - victim will not become witness")
            end
        end
    }
}
