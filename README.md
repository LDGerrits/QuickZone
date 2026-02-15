<div align="center">
	<h1>QuickZone</h1>
	<p>A lightweight spatial library for Roblox that replaces expensive physics queries with fast, math-based entity tracking at scale.</p>
	<a href="https://LDGerrits.github.io/QuickZone/"><strong>View docs</strong></a>
</div>
<!--moonwave-hide-before-this-line-->


## Why use QuickZone?

Instead of using the physics engine, QuickZone performs geometric calculations. It provides a predictable, budgeted, and flexible solution for zone detection while using Linear Bounding Volume Hierarchy (LBVH) in the backend. QuickZone makes it possible to track thousands of entities across hundreds of zones with very little impact on your frame rate and memory.

## What it offers

- **Lifecycle Management**: Use the `observe` pattern for 100% reliable cleanup. There is no need for juggling `onEntered` and `onExited` events anymore.

- **Track Anything**: Track BaseParts, Models, Attachments, Bones, Cameras, or even pure Lua tables. If it has a position, QuickZone can track it.

- **Shape Support**: Supports mathematical containment for Blocks, Balls, Cylinders, and Wedges without relying on physics collision meshes.

- **Decoupled Architecture**: Separate game logic from spatial instances. Bind behaviors to categories of entities (Players, NPCs, Projectiles) for a clean, scalable architecture.

- **Budgeted Scheduler**: Remove lag spikes by setting a hard frame budget (e.g., 1ms). Workload is smeared across frames to maintain a flat and predictable performance profile.

- **Zero-Allocation Runtime**: By using contiguous arrays and object pooling, QuickZone reduces GC pressure, avoiding memory-related stutters.
