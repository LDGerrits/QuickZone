<div align="center">
	<h1>QuickZone</h1>
	<p>A flexible, low-overhead spatial library for Roblox. Maintain 60 FPS with over a million zones.</p>
	<a href="https://LDGerrits.github.io/QuickZone/"><strong>View docs</strong></a>
</div>
<!--moonwave-hide-before-this-line-->

## Why use QuickZone?

By bypassing the physics engine in favor of pure geometric math, QuickZone is a predictable, budgeted and flexible solution for spatial tracking that has near-zero impact on your frame rate or memory.

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
