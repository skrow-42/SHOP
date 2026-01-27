# Move Combat NPC Door Opening Logic

## Current Work
- Moving combat NPC door opening logic from AntiTheftGlobal.lua to globalaiwalkback.lua
- The logic includes monitoring door state changes during combat and sending pulses to closest NPCs to unlock doors

## Tasks
- [x] Add state variables to globalaiwalkback.lua (monitorDoorLocksDuringCombat, combatDoorStates, doorLockStates)
- [x] Move and adapt combat door lock monitoring logic from AntiTheftGlobal.lua
- [x] Move and adapt door lock monitoring logic from AntiTheftGlobal.lua
- [x] Update logic to work in global script context (use world.players[1] instead of self)
- [x] Add startCombatDoorUnlockSequence function for full investigation process with sounds and timing
- [x] Remove moved logic from AntiTheftGlobal.lua
- [x] Test the moved logic for proper functionality

## Technical Details
- Change from player script context to global script context
- Update event sending to use global events
- Adapt nearby.objects/actors access to world.activeActors and cell iteration
- Maintain compatibility with existing door detection in globalaiwalkback.lua
