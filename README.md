<div align="center">
	<h1>QuickZone</h1>
	<p>A high-performance, physics-free spatial query library for Roblox. Maintain 60 FPS with 1M+ zones.</p>
	<a href="https://LDGerrits.github.io/QuickZone/"><strong>documentation</strong></a>
</div>
<!--moonwave-hide-before-this-line-->

## Why use QuickZone?

**The Physics Bottleneck.** Traditional zone libraries act as wrappers for Roblox's physics engine (e.g., `GetPartsInPart` or `.Touched`), binding spatial logic to collision meshes. This results in expensive geometry calculations, unpredictable overhead, low flexibility, and much worse performance as the number of zones grows. 

**Clean Architecture.** By separating *what* you track (Groups), *where* you track them (Zones), and *how* you respond (Observers), QuickZone eliminates monolithic, instance-bound logic and keeps your codebase clean. 

**Physics-Free Scaling.** QuickZone achieves *O(N log Z)* scaling by bypassing the physics engine in favor of pure geometric math and a custom Linear Bounding Volume Hierarchy (LBVH). Performance is driven by the number of entities, while the number of zones is virtually irrelevant.

**Agnostic.** Whether you prefer classic event-driven programming, robust lifecycle management, or zero-allocation iterators for ECS architectures, QuickZone can fit your workflow.

**Total Performance Control.** The runtime cost is entirely in your control. Through a budgeted scheduler, the workload is smeared across frames and only consumes as much CPU time as you explicitly allow. Paired with contiguous arrays that produce virtually zero garbage collection (GC) pressure, QuickZone produces a flat, predictable performance profile.

**Unit Tested.** A rigorous unit testing suite ensures stable and predictable behavior across all systems.

## What it offers

- **Endless Scale**: The number of zones has zero impact on performance. Maintain 60 FPS even with over a million zones in your game.

- **Track Anything**: Track Players, BaseParts, Models, Attachments, Bones, Cameras, or even custom tables. If it has a position, QuickZone can track it.

- **Budgeted Scheduler**: Set a hard frame budget (e.g., 1ms) to completely eliminate lag spikes. Workloads are smeared across frames to maintain a flat, predictable performance profile.

- **Shape Support**: Built-in for Blocks, Balls, Cylinders, Wedges and CornerWedges without relying on physics collision meshes..

- **Declarative Lifecycles**: Replace event-based logic with the observe pattern for declarative logic. There is no need to manually track `onEnter` and `onExit` states.

- **Decoupled Architecture**: Separate where tracking happens (Zones) from who is being tracked (Groups) and how the system responds (Observers). Bind complex behaviors to groups of entities with zero boilerplate.

- **ECS-Ready**: Built-in support for zero-allocation iterators and deterministic manual stepping, making it a perfect fit for ECS architectures and data-oriented workflows

- **Zero-Allocation Runtime**: By utilizing contiguous arrays and object pooling, QuickZone produces virtually zero GC pressure to avoid memory-related stutters.

- **Dynamic Zones**: Use moving zones at very little cost. QuickZone maintains separate Static and Dynamic LBVHs for maximum efficiency.

## Contributing

Pull requests are welcome!
Read the [contribution guidelines](CONTRIBUTING.md) to set up your local environment, run tests, and submit code changes.

## License

See the [licence](LICENSE.md) for details.
