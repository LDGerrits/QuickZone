---
sidebar_position: 1
---

# Introduction

## Overview
QuickZone is a lightweight spatial library for Roblox that replaces expensive physics queries with fast, math-based entity tracking at scale. Instead of the physics engine, it uses geometric math while providing a predictable, budgeted, and flexible solution for zone detection, making it possible to track thousands of entities across hundreds of zones with very little impact on your frame rate.

:::info Point-Based Detection
QuickZone uses point-based detection. It checks if a specific point (e.g., the center of a Part, the position of an Attachment, or the Pivot of a Model) is inside a zone's boundary.

Because it calculates if it is inside or not using geometric math instead of physics-based volume intersections, it is significantly faster than other zone detection libraries.
:::

---

## Core Features

- **Lifecycle Management**: Use the `observe` pattern for 100% reliable cleanup. There is no need for juggling `onEntered` and `onExited` events anymore (do note that QuickZone still supports Event-Driven Programming).

- **Track Anything**: Track BaseParts, Models, Attachments, Bones, Cameras, or even pure Lua tables. If it has a position, QuickZone can track it.

- **Shape Support**: Supports mathematical containment for Blocks, Balls, Cylinders, and Wedges without relying on physics collision meshes.

- **Decoupled Architecture**: Separate game logic from spatial instances. Bind behaviors to categories of entities (Players, NPCs, Projectiles) for a clean, scalable architecture.

- **Budgeted Scheduler**: Remove lag spikes by setting a hard frame budget (e.g., 1ms). Workload is smeared across frames to maintain a flat and predictable performance profile.

- **Zero-Allocation Runtime**: By using contiguous arrays and object pooling, QuickZone reduces GC pressure, avoiding memory-related stutters.

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
* ZonePlus caused a 28% drop in framerate, rendering the game choppy.
* QuickZone handled the load with 98% less memory than ZonePlus.
* QuickZone vs. QuickBounds: QuickZone squeezes out more performance, averaging ~1 FPS higher than QuickBounds. More importantly, QuickZone processed 4x the volume of events (2,271 vs 566).

## Installation

### Wally
The package name + version is

```
ldgerrits/quickzone@^0.4.0
```

### Manual
Download the latest .rbxm model file from the [Releases](https://github.com/LDGerrits/QuickZone/releases) tab and drag it into ReplicatedStorage.

## Quick Start
The following example demonstrates a 'Water Zone' system. It uses an Observer to apply swimming logic to the LocalPlayerGroup only when they are inside a specific area.
```lua
local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local QuickZone = require(ReplicatedStorage.QuickZone)

-- Assign the classes to local variables here if you want
local Group = QuickZone.Group
local Observer = QuickZone.Observer
local Zone = QuickZone.Zone

-- Create a LocalPlayerGroup that automatically tracks the client's character (including respawns)
local myPlayer = Group.localPlayer()

-- Create an observer subscribed to that group. 
-- Priority 42 ensures this logic overrides lower-priority overlaps.
local swimObserver = Observer.new({ 
    priority = 42,
    groups = { myPlayer } 
})

-- Define behavior
swimObserver:observeLocalPlayer(function()
    local chararcter = Players.LocalPlayer.Character
    if not character then return end

    local humanoid = character:FindFirstChild("Humanoid")
    if not humanoid then return end
    
    -- On Enter
    humanoid:SetStateEnabled(Enum.HumanoidStateType.Swimming, true)
    humanoid:ChangeState(Enum.HumanoidStateType.Swimming)

    -- Return cleanup (On Exit)
    return function() 
        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
    end)
end)

-- Create zones based on parts inside workspace.WaterParts,
-- and attach them to the observer automatically.
-- This uses the declarative config pattern to attach everything in one step.
Zone.fromParts(workspace.WaterParts:GetChildren(), { 
    observers = { swimObserver } 
})
```