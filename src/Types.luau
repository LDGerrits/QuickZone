--!strict

--[=[
	@type ShapeType "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"
	@within QuickZone

	The geometric shape of a Zone.
]=]
export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge'
export type BoundingVolume = {
	position: Vector3,
	cframe: CFrame,
	halfSize: Vector3,
	type: ShapeType,
	radiusSq: number?,
	start: Vector3?,
	axis: Vector3?,
	axisLength: number?,
}

export type Node = {
	left: Node?,
	right: Node?,
	min: Vector3,
	max: Vector3,
	id: number, -- -1 for internal nodes
}

--[=[ 
	@interface ZoneConfig
	@within QuickZone
	.cframe CFrame -- The center position and orientation.
	.size Vector3 -- The full dimensions of the zone.
	.shape ShapeType -- The geometric shape ('Block', 'Ball', 'Cylinder', etc).
	.part BasePart? -- Optional part to sync the zone with.
	.isDynamic boolean? -- Optionally set to true if the zone moves/resizes (i.e. not static).
	.metadata any? -- Optional metadata.
]=]
export type ZoneConfig = {
	cframe: CFrame,
	size: Vector3,
	shape: ShapeType?,
	part: BasePart?,
	isDynamic: boolean?,
	metadata: any?,
}

export type QuickZone = {
	Zone: Zone,
	Observer: Observer,
	Group: Group,
	setFrameBudget: (self: QuickZone, ms: number) -> QuickZone,
	getZonesAtPoint: (self: QuickZone, position: Vector3) -> { Zone },
	getObserversAtPoint: (self: QuickZone, position: Vector3) -> { Observer },
	getGroupOfEntity: (self: QuickZone, entity: Entity) -> Group?,
	getZones: (self: QuickZone) -> { Zone },
	getObservers: (self: QuickZone) -> { Observer },
	getGroups: (self: QuickZone) -> { Group },
	getEntities: (self: QuickZone) -> { Entity },
	visualize: (self: QuickZone, enabled: boolean) -> QuickZone,
}

export type Zone = {
	new: (config: ZoneConfig) -> Zone,
	fromPart: (part: BasePart, config: { isDynamic: boolean?, metadata: any? }?) -> Zone,
	fromParts: (parts: { BasePart }, config: { isDynamic: boolean?, metadata: any? }?) -> { Zone },
	attach: (self: Zone, ...Observer) -> Zone,
	detach: (self: Zone, ...Observer) -> Zone,
	syncToPart: (self: Zone) -> Zone,
	setCFrame: (self: Zone, cf: CFrame) -> Zone,
	setPosition: (self: Zone, pos: Vector3) -> Zone,
	setSize: (self: Zone, size: Vector3) -> Zone,
	setShape: (self: Zone, shape: ShapeType) -> Zone,
	setMetadata: (self: Zone, metadata: any?) -> Zone,
	getMetadata: (self: Zone) -> any?,
	getId: (self: Zone) -> number,
	getPart: (self: Zone) -> BasePart?,
	getPosition: (self: Zone) -> Vector3,
	getCFrame: (self: Zone) -> CFrame,
	getSize: (self: Zone) -> Vector3,
	getShape: (self: Zone) -> ShapeType,
	getObservers: (self: Zone) -> { Observer },
	isDynamic: (self: Zone) -> boolean,
	isPointInside: (self: Zone, point: Vector3) -> boolean,
	destroy: (self: Zone) -> (),
}

export type InternalZone = Zone & {
	id: number,
	part: BasePart?,
	dynamic: boolean,
	metadata: any?,
}

export type Callback = (Entity, Zone, any?) -> ()

export type Observer = {
	new: (config: {
		priority: number?,
		enabled: boolean?,
		safety: boolean?,
	}?) -> Observer,
	subscribe: (self: Observer, ...Group) -> Observer,
	unsubscribe: (self: Observer, ...Group) -> Observer,
	setPriority: (self: Observer, n: number) -> Observer,
	setEnabled: (self: Observer, enabled: boolean) -> Observer,
	setSafety: (self: Observer, enabled: boolean) -> Observer,
	isEnabled: (self: Observer) -> boolean,
	isSafe: (self: Observer) -> boolean,
	isPlayerInside: (self: Observer, player: Player) -> boolean,
	isLocalPlayerInside: (self: Observer) -> boolean,
	isEntityInside: (self: Observer, entity: Entity) -> boolean,
	isPointInside: (self: Observer, position: Vector3) -> boolean,
	getEntitiesInside: (self: Observer) -> { Entity },
	getId: (self: Observer) -> number,
	getPriority: (self: Observer) -> number,
	getZones: (self: Observer) -> { Zone },
	getGroups: (self: Observer) -> { Group },
	observe: (self: Observer, callback: (Entity, Zone, any?) -> (() -> ())?) -> () -> (),
	observePlayer: (self: Observer, callback: (Player, Zone) -> (() -> ())?) -> () -> (),
	observeLocalPlayer: (self: Observer, callback: (Zone) -> (() -> ())?) -> () -> (),
	onEntered: (self: Observer, callback: Callback) -> () -> (),
	onExited: (self: Observer, callback: Callback) -> () -> (),
	onLocalPlayerEntered: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onLocalPlayerExited: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onPlayerEntered: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onPlayerExited: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	destroy: (self: Observer) -> (),
}

export type InternalObserver = Observer & {
	id: number,
}

export type Group = {
	new: (config: {
		updateRate: number?,
		precision: number?,
	}?) -> Group,
	players: (config: {
		updateRate: number?,
		precision: number?,
	}?) -> Group,
	localPlayer: (config: {
		updateRate: number?,
		precision: number?,
	}?) -> Group,
	add: (self: Group, entity: Entity, metadata: any?) -> Group,
	remove: (self: Group, ...Entity) -> Group,
	setConfig: (self: Group, {
		updateRate: number?,
		precision: number?,
	}) -> Group,
	setUpdateRate: (self: Group, updateRate: number) -> Group,
	setPrecision: (self: Group, precision: number) -> Group,
	getUpdateRate: (self: Group) -> number,
	getPrecision: (self: Group) -> number,
	getId: (self: Group) -> number,
	getEntities: (self: Group) -> { Entity },
	getObservers: (self: Group) -> { Observer },
	getConfig: (self: Group) -> {
		updateRate: number,
		precision: number,
	},
	contains: (self: Group, entity: Entity) -> boolean,
	destroy: (self: Group) -> (),
}

export type InternalGroup = Group & {
	id: number,
	entities: { Entity },
	entityIndices: { [Entity]: number },
	entityData: { [Entity]: EntityData },
	config: {
		updateRate: number,
		precisionSq: number,
	},
}

--[=[
	@type Entity BasePart | Model | Camera | Attachment | Bone | EntityTable
	@within QuickZone

	An Entity is any object that can be tracked within a Group. It supports native 
	Roblox Instances and custom duck-typed tables.
]=]
export type Entity = BasePart | Model | Camera | Attachment | Bone | EntityTable

--[=[
	@interface EntityTable
	@within QuickZone
	.Position Vector3?
	.WorldPosition Vector3?
	.CFrame CFrame?
	.GetPivot (() -> CFrame)?

	A custom table that mimics the spatial properties of a Roblox Instance. 
	QuickZone will automatically detect which property to use to track this entity.
]=]
export type EntityTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
	[any]: any,
}

export type EntityData = {
	activeObserverMemberships: { [number]: number },
	lastPosition: Vector3,
	strategy: number,
	isDirty: boolean,
}

return nil
