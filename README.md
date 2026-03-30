<div align="center">
	<h1>QuickZone</h1>
	<p>A high-performance, physics-free spatial query library for Roblox. Maintain 60 FPS with 1M+ zones.</p>
	<a href="https://LDGerrits.github.io/QuickZone/"><strong>View docs</strong></a>
</div>
<!--moonwave-hide-before-this-line-->

## Why use QuickZone?

**The Physics Bottleneck.** Traditional zone libraries act as wrappers for Roblox's physics engine (e.g., `GetPartsInPart` or `.Touched`), binding spatial logic to collision meshes. This results in expensive geometry calculations, unpredictable overhead, low flexibility, and much worse performance as the number of zones grows. 

**Clean Architecture.** QuickZone takes a different approach. By separating *what* you track (Groups), *where* you track them (Zones), and *how* you respond (Observers), it eliminates monolithic, instance-bound logic and keeps your codebase clean. 

**Physics-Free Scaling.** QuickZone achieves *O(N log Z)* scaling by bypassing the physics engine in favor of pure geometric math and a custom Linear Bounding Volume Hierarchy (LBVH). Performance is driven by the number of entities, while the map size is virtually irrelevant.

**Agnostic.** Whether you prefer classic event-driven programming, robust lifecycle management (`observe()`), or zero-allocation polling for ECS architectures, QuickZone can fit your workflow.

**Total Performance Control.** The runtime cost is entirely in your control. Through a budgeted scheduler, the workload is smeared across frames and only consumes as much CPU time as you explicitly allow. Paired with contiguous arrays that produce virtually zero garbage collection (GC) pressure, QuickZone produces a flat, predictable performance profile.

## What it offers

- **Endless Scale**: The number of zones has zero impact on performance. Maintain 60 FPS even with over a million zones in your game.

- **Track Anything**: Track BaseParts, Models, Attachments, Bones, Cameras, or even custom tables. If it has a position, QuickZone can track it.

- **Budgeted Scheduler**: Set a hard frame budget (e.g., 1ms) to completely eliminate lag spikes. Workloads are smeared across frames to maintain a flat, predictable performance profile.

- **Shape Support**: Support for Blocks, Balls, Cylinders, Wedges and CornerWedges without relying on physics collision meshes.

- **Lifecycle Management**: Use the `observe` pattern for 100% reliable cleanup. Say goodbye to juggling `onEnter` and `onExit` events (though classic event-driven programming is still supported).

- **ECS & Data-Oriented**: Built-in support for zero-allocation iterators and deterministic manual stepping, making it a perfect fit for ECS architectures.

- **Decoupled Architecture**: Separate game logic from spatial instances. Bind behaviors directly to categories of entities (Players, NPCs, Projectiles) for a clean, scalable codebase.

- **Zero-Allocation Runtime**: By utilizing contiguous arrays and object pooling, QuickZone produces close to zero GC pressure, avoiding memory-related stutters.

- **No Dependencies**: QuickZone is a standalone, lightweight library that does not rely on any other external packages.
