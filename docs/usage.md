---
sidebar_position: 2
---

# Usage

QuickZone is designed around a three-tier architecture: Zones (where), Groups (who), and Observers (how).

![Priority](topology_quickzone.png)

```lua
local QuickZone = require(game:GetService("ReplicatedStorage").QuickZone)
local Zone, Group, Observer = QuickZone.Zone, QuickZone.Group, QuickZone.Observer
```

### The Two Workflows

QuickZone offers two ways to structure your code: **Declarative** (Configuration-based) and **Imperative** (Chain-based).

#### Style A: Declarative
Define your object's properties and its relationships in the constructors.

```lua
local localPlayerGroup = Group.localPlayer()

local observer = Observer.new({
    groups = { localPlayerGroup }, -- Immediately subscribes to these groups
    priority = 1,
})

Zone.fromPart(workspace.SafeZone, {
    observers = { observer } -- Immediately attaches to these observers
})
```

#### Style B: Imperative
Create objects first, then link them together. You can do this at any point in their lifecycles.

```lua
local localPlayerGroup = Group.localPlayer()
local observer = Observer.new({ priority = 1 })
local zone = Zone.fromPart(workspace.SafeZone)

-- Link them manually
observer:subscribe(localPlayerGroup)
zone:attach(observer)
```

## 1. Zones

Zones represent physical areas in the world. They are mathematical boundaries that can be static (fixed in space) or dynamic (following a part). They can be created from existing parts or defined manually with a CFrame and Size.

### Creation
The easiest way to create a zone.

```lua
-- Static Zone (Fastest)
-- Ideal for shops, biomes, or permanent regions.
local staticZones = Zone.fromParts(workspace.SafeZones:GetChildren())

-- Dynamic Zone
-- Passing 'true' makes the zone follow the part's CFrame on :update()
local trainZone = Zone.fromPart(workspace.TrainCarriage, { 
    isDynamic = true,
    metadata = { canDamage = true },
    observers = { trainObserver }
})
```

_Note: The third argument (`metadata`) is optional and can be retrieved using `zone:getMetadata()`_

### Manual Creation
Useful for procedural generation or areas without physical parts.

```lua
local zone = Zone.new({
    cframe = CFrame.new(0, 10, 0),
    size = Vector3.new(10, 10, 10),
    shape = 'Block',
    isDynamic = true,
    metadata = { Name = 'Lobby' }
})
```

:::info Performance Optimization: Static vs. Dynamic
QuickZone batches tree rebuilds once per frame. By keeping the Dynamic Tree small, you make sure that these batched rebuilds remain super quick. For maximum perfomance, use `isDynamic = true` for zones attached to moving platforms, vehicles, or projectiles.
:::

### Updating Zones
If you create a zone manually or want to sync a dynamic zone to a new reference, use `:syncToPart()`.

```lua
-- Manually move a dynamic zone
dynamicZone:setPosition(Vector3.new(0, 50, 0))

-- Sync a dynamic zone to its associated part's current CFrame, Size, and Shape
dynamicZone:syncToPart()
```

## 2. Groups
Groups are collections of entities (Parts, Models, Players, etc.). They allow you to categorize entities and set unique performance settings per category.

### Specialized Groups
QuickZone provides built-in abstractions that automatically handle player lifecyles.

```lua
-- Tracks all players in the server
local allPlayers = Group.players()

-- Tracks only the local player (client-side only)
local myPlayer = Group.localPlayer()
```

### Custom Groups
For NPCs, projectiles, or vehicles, create a standard Group.

```lua
local projectiles = Group.new({
    updateRate = 60,   -- Check every frame for high-speed objects
    precision = 0,     -- Query every time it moves
    entities = workspace.Projectiles:GetChildren()
})

local NPCs = Group.new({
    updateRate = 5,    -- Check only 5 times a second
    precision = 2.0    -- Only query if the NPC moves more than 2 studs
})
```

### Managing Entities
You can add BaseParts, Models, Attachments, Bones, or tables with a Position.

```lua
-- Add a Model (tracks the PrimaryPart or Pivot)
-- Note: 'metadata' applies to the entity, not the group.
enemies:add(npcModel, { Team = 'Red' })

-- Add a specific Attachment (tracks the exact point)
-- This is great for offsets if you do not want to track the middle of a part (e.g. sword tip)
enemies:add(sword.TipAttachment, { Damage = 75 })

-- Add a table
local spell = { Position = Vector3.new(10, 5, 0) }
enemies:add(spell)

-- Remove when done
enemies:removeBulk({npcModel, sword.TipAttachment, spell})
```

_Note: The second argument (`metadata`) is optional and will be passed to your event callbacks._

## 3. Observers

Observers act as the logic layer. They subscribe to Groups and attach to Zones to bridge spatial data with game behavior.

### Setup
An Observer listens to its subscribed Groups and checks if they overlap with its attached Zones.

```lua
local observer = Observer.new()

observer:subscribe(allPlayers) -- Who to watch
healingZone:attach(observer)   -- Where to watch
```

### Lifecycle Management
For logic that should persist while an entity is inside a zone (e.g., UI, music, status effects), use the observe methods. These accept a callback that returns a cleanup function, which runs automatically when the entity exits.

```lua
-- Generic observation
observer:observe(function(entity, zone, metadata)
    print("Entered", entity)
    local highlight = Instance.new("Highlight", entity)
    
    return function()
        print("Exited", entity)
        highlight:Destroy()
    end
end)

-- The callback fires when the first entity of a group enters, and the 
-- returned cleanup function fires when the last entity of the group leaves.
observer:observeGroup(function(group, zone)
    print("Group " .. group:getId() .. " has arrived!")
    local boss = workspace.Boss:Clone()
    boss.Parent = workspace
    
    return function()
        print("The group has been wiped out or left.")
        boss:Destroy()
    end
end)

-- Player specific
observer:observePlayer(function(player, zone)
    local forceField = Instance.new("ForceField", player.Character)
    
    return function()
        forceField:Destroy()
    end
end)

-- LocalPlayer specific
observer:observeLocalPlayer(function(zone)
    local sound = workspace.Sounds.SafeZoneAmbience
    sound:Play()

    return function()
        sound:Stop()
    end
end)
```

### Events
For logic that happens exactly once on entry or exit (e.g., playing a sound effect, dealing damage, analytics), use the event listeners.

```lua
-- Individual entity events
observer:onEntered(function(entity, zone, metadata)
    print(entity.Name .. ' entered ' .. zone:getId())
end)
observer:onExited(function(entity, zone, metadata)
    print(entity.Name .. ' exited ' .. zone:getId())
end)

-- Group-level events
observer:onGroupEntered(function(group, zone)
    print('The first member of group ' .. group:getId() .. ' entered!')
end)
observer:onGroupExited(function(group, zone)
    print('The last member of group ' .. group:getId() .. ' left!')
end)

-- Convenient player events
observer:onPlayerEntered(function(player, zone) ... end)
observer:onPlayerExited(function(player, zone) ... end)
observer:onLocalPlayerEntered(function(zone) ... end)
observer:onLocalPlayerExited(function(zone) ... end)
```

### Priority and Resolution
Observers use a priority system to handle overlapping zones. An entity 'belongs' to only one zone state per observer at a time when using priorities.

```lua
local lowPriority = Observer.new({ priority = 0 })
local highPriority = Observer.new({ priority = 10 })

-- If a player is inside Zone A (Low) and Zone B (High) simultaneously:
-- 1. highPriority:onEntered() fires for Zone B.
-- 2. lowPriority:onExited() fires for Zone A.
```

### Observer State
Observers can be toggled to pause logic without destroying the configuration.

```lua
observer:setEnabled(false) -- Fires 'onExited' for everyone inside
task.wait(5)
observer:setEnabled(true)  -- Fires 'onEntered' if they are still there
```

---

## Utility

### Frame Budget
To maintain a high framerate in complex scenes, you can constrain the total CPU time QuickZone is allowed to consume per frame.

```lua
-- Allow 0.5 milliseconds per frame (default is 1ms)
QuickZone:setFrameBudget(0.5)
```

### Immediate Spatial Queries
Perform instant checks without using the Observer/Group pattern.

```lua
-- Get all zones at a specific vector
local zones = QuickZone:getZonesAtPoint(Vector3.new(10, 5, 0))

-- Get the group an entity belongs to
local group = QuickZone:getGroupOfEntity(workspace.Part)
```

---

## Considerations
- **Point-Based Tracking:** QuickZone tracks the precise coordinate of an entity (Center, Attachment, or Pivot). It does not calculate the full volume intersection of the entity itself.

- **Movement Threshold (Precision)**: QuickZone only re-calculates spatial state when an entity moves beyond a certain distance. Setting a higher precision value (e.g., 2.0 studs) significantly reduces overhead for slow-moving objects.

- **Budgeted Latency**: To prevent frame drops, QuickZone 'smears' workload across multiple frames. In high-load scenarios (e.g., thousands of active entities), there may be a slight delay between an entity physically entering a zone and the event firing.