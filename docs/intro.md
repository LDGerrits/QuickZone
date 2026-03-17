---
sidebar_position: 1
---

# Introduction

## Overview
By bypassing the physics engine in favor of pure geometric math, QuickZone is a predictable, budgeted and flexible solution for spatial tracking that has near-zero impact on your frame rate or memory.

:::info Point-Based Detection
QuickZone uses point-based detection. It checks if a specific point (e.g., the center of a Part, the position of an Attachment, or the Pivot of a Model) is inside a zone's boundary.
:::

---

## Core Features

- **Endless Scale**: The number of zones has zero impact on performance. Maintain 60 FPS even with over a million zones in your game.

- **Track Anything**: Track BaseParts, Models, Attachments, Bones, Cameras, or even custom tables. If it has a position, QuickZone can track it.

- **Budgeted Scheduler**: Set a hard frame budget (e.g., 1ms) to completely eliminate lag spikes. Workloads are smeared across frames to maintain a flat, predictable performance profile.

- **Shape Support**: Support for Blocks, Balls, Cylinders, Wedges and CornerWedges without relying on physics collision meshes.

- **Lifecycle Management**: Use the `observe` pattern for 100% reliable cleanup. Say goodbye to juggling `onEnter` and `onExit` events (though classic event-driven programming is still supported).

- **ECS & Data-Oriented**: Built-in support for zero-allocation iterators and deterministic manual stepping, making it a perfect fit for ECS architectures.

- **Decoupled Architecture**: Separate game logic from spatial instances. Bind behaviors directly to categories of entities (Players, NPCs, Projectiles) for a clean, scalable codebase.

- **Zero-Allocation Runtime**: By utilizing contiguous arrays and object pooling, QuickZone produces close to zero GC pressure, avoiding memory-related stutters.

- **No Dependencies**: QuickZone is a standalone, lightweight library that does not rely on any other external packages.

---

## Performance Benchmarks

We stress-tested QuickZone against the most popular alternatives in two distinct scenarios: **Entity Stress** (lots of moving parts) and **Map Stress** (lots of zones).

_Note: For the QuickZone benchmark, we used a frame budget of 1ms, the entities' update rate was set to 60Hz, and precision was 0.0._

### Test 1: High Zone Count
*Scenario: 500 moving entities, 10,000 zones, recorded over 30 seconds.*

This test highlights the fundamental flaw in traditional Zone-Centric libraries. As map complexity grows, their performance degrades exponentially.

| Metric | QuickZone | ZonePlus | SimpleZone | QuickBounds | Empty Script |
| --- | --- | --- | --- | --- | --- |
| FPS | 59.25 | 3.84 | 5.53 | 58.95 | 59.28 |
| Events/s | 643 | 627 | 519 | 328 | 0 |
| Memory Usage (MB) | 18.57 | 4230 | 99.79 | 17.62 | 0.65 |

**The Result:** QuickZone maintained a perfect 60 FPS.
* ZonePlus and SimpleZone imploded, dropping to 3-5 FPS, making the game unplayable.
* ZonePlus consumed over 4 GB of memory, which would crash most mobile devices instantly.
* QuickZone proved it is *O(N)* relative to entities, not zones. You can add as many zones as you want without performance penalties.
* QuickZone vs. QuickBounds: Both libraries scaled well by maintaining ~60 FPS. However, QuickZone still maintained a slight FPS lead and, more importantly, delivered double the event throughput (643 vs 328) compared to QuickBounds.

### Test 2: High Entity Count
*Scenario: 2,000 moving entities, 100 zones, recorded over 30 seconds.*

| Metric | QuickZone | ZonePlus | SimpleZone | QuickBounds | Empty Script |
| --- | --- | --- | --- | --- | --- |
| FPS | 42.37 | 29.88 | 37.23 | 41.31 | 42.73 |
| Events/s | 2271 | 2482 | 2518 | 566 | 0 |
| Memory Usage (MB) | 2.13 | 159 | 1.77 | 2.60 | 1.04 |

**The Result:** QuickZone is the only library that maintained near-baseline FPS (-1% impact).
* ZonePlus caused a 28% drop in framerate.
* QuickZone handled the load with 98% less memory than ZonePlus.
* QuickZone vs. QuickBounds: QuickZone squeezes out more performance, averaging ~1 FPS higher than QuickBounds. More importantly, QuickZone processed 4x the volume of events (2,271 vs 566).

## Installation

### Wally
The package name + version is

```
ldgerrits/quickzone@^1.2.1
```

### Manual
Download the latest .rbxm model file from the [Releases](https://github.com/LDGerrits/QuickZone/releases) tab and drag it into ReplicatedStorage.

## Quick Start
The following example showcases an anti-gravity system. QuickZone supports three coding styles, so choose the one that fits your architecture.

### Option A: The Lifecycle Approach (Recommended)
Best for clean, modern code. You define relationships in a configuration table (**Declarative**) and use a single function to manage the active state (**Lifecycle**).

```lua
local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Zone, Group, Observer = QuickZone.Zone, QuickZone.Group, QuickZone.Observer

-- Create a group that automatically tracks the client's character (including respawns)
local myPlayer = Group.localPlayer()

-- Create an observer subscribed to the group.
local gravityObserver = Observer.new({ 
    groups = { myPlayer } 
})

-- Define behavior
gravityObserver:observe(function(player, zone)
    local character = player.Character
    local hrp = character and character:FindFirstChild('HumanoidRootPart')
    if not hrp then return end
    
    -- Get the zone's gravity multiplier using metadata.
    local meta = zone:getMetadata()
    local multiplier = meta and meta.GravityMultiplier or 1
    
    -- Create the Anti-Gravity force on enter
    local force = Instance.new('BodyForce')
    force.Name = 'AntiGravityForce'
    force.Force = Vector3.new(0, hrp.AssemblyMass * workspace.Gravity * (1- multiplier), 0)
    force.Parent = hrp

    -- Automatically destroy the force when the player exits the zone
    return function() 
        force:Destroy()
    end
end)

-- Find all current and future instances with the 'Water' tag.
Zone.fromTag('AntiGravity', { 
    observers = { gravityObserver },
    metadata = { GravityMultiplier = 0.4 }
})
```

### Option B: The Event-Driven Approach (ZonePlus / SimpleZone Style)
Best for familiarity or for migrating ZonePlus code to QuickZone. You manually 'wire' objects together (**Imperative**) and use standard events like `onEnter` to trigger one-off actions (**Event-Driven**).

```lua
local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Zone, Group, Observer = QuickZone.Zone, QuickZone.Group, QuickZone.Observer
local localPlayer = game:GetService('Players').LocalPlayer

local myPlayer = Group.localPlayer()
local gravityObserver = Observer.new()

-- Subscribe the logic to the group
gravityObserver:subscribe(myPlayer)

-- Connect events
gravityObserver:onLocalPlayerEnter(function(zone)
    local character = localPlayer.Character
    local hrp = character and character:FindFirstChild('HumanoidRootPart')
    if not hrp then return end

    local ref = zone:getReference() -- This returns the zone's part
    local multiplier = ref and ref:GetAttribute("GravityMultiplier") or 1 -- You can use attributes!

    local force = Instance.new('BodyForce')
    force.Name = 'AntiGravityForce'
    force.Force = Vector3.new(0, hrp.AssemblyMass * workspace.Gravity * (1- multiplier), 0)
    force.Parent = hrp
end)

gravityObserver:onLocalPlayerExit(function(zone)
    local character = localPlayer.Character
    local hrp = character and character:FindFirstChild('HumanoidRootPart')

    if hrp and hrp:FindFirstChild('AntiGravityForce') then
        hrp.AntiGravityForce:Destroy()
    end
end)

local zones = Zone.fromChildren(workspace.AntiGravityParts)
zones:attach(gravityObserver)
```

### Option C: The Polling Approach (Data-Oriented / ECS)
Use iterators to poll state for continuous logic. To enhance ECS workflows, you can also turn off auto-updating and update QuickZone manually. It is even possible to manually link entities to a reference like an Id or an object.

```lua
local Players = game:GetService('Players')
local RunService = game:GetService("RunService")
local QuickZone = require(game.ReplicatedStorage.QuickZone)
local Zone, Group, Observer = QuickZone.Zone, QuickZone.Group, QuickZone.Observer

-- Disable auto-update for deterministic, manual stepping (optional)
QuickZone:setEnabled(false)

local playerGroup = Group.new()
local gravityObserver = Observer.new({ groups = { playerGroup } })
Zone.fromTag('AntiGravity', { 
    observers = { gravityObserver },
    metadata = { GravityMultiplier = 0.4 }
})

local localPlayer = Players.LocalPlayer
local characterModel = localPlayer.Character or localPlayer.CharacterAdded:Wait()

-- Track this Model's physical position, but return the local player in queries
QuickZone:setReference(localPlayer, characterModel)

-- Add the local player to the spatial group (QuickZone tracks the mapped model automatically)
playerGroup:add(localPlayer)

-- Process all spatial movement and LBVH tree updates in a specific order (only needed if :setEnabled(false))
local function spatialSystem(dt)
    QuickZone:update(dt) 
end

local function gravitySystem(dt)
    -- Instead of creating a BodyForce, we apply continuous math statelessly.
    for player, zone in gravityObserver:iterEntitiesInside() do
        local character = localPlayer.Character
        local hrp = character and character:FindFirstChild('HumanoidRootPart')
        if not hrp then continue end

        local meta = zone:getMetadata()
        local multiplier = meta and meta.GravityMultiplier or 1
        
        local upwardForce = hrp.AssemblyMass * workspace.Gravity * (1- multiplier)
        hrp:ApplyImpulse(Vector3.new(0, upwardForce * dt, 0))
    end
end

RunService.Heartbeat:Connect(function(dt)
    spatialSystem(dt)
    gravitySystem(dt)
end)
```