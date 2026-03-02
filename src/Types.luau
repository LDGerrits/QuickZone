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
	min: Vector3,
	max: Vector3,
	id: number,
	skipIndex: number,
}

export type Tree = {
	nodes: { Node },
	count: number,
}

export type QuickZone = {
	Zone: ZoneClass,
	Observer: ObserverClass,
	Group: GroupClass,

	setEnabled: (self: QuickZone, enabled: boolean) -> QuickZone,
	rebuildTrees: (self: QuickZone) -> QuickZone,
	update: (self: QuickZone, dt: number) -> QuickZone,
	setFrameBudget: (self: QuickZone, ms: number) -> QuickZone,
	visualize: (self: QuickZone, enabled: boolean) -> QuickZone,

	removeEntity: (self: QuickZone, entity: Entity) -> QuickZone,
	removePlayer: (self: QuickZone, player: Player) -> QuickZone,

	getZones: (self: QuickZone) -> { Zone },
	getObservers: (self: QuickZone) -> { Observer },
	getGroups: (self: QuickZone) -> { Group },
	getEntities: (self: QuickZone) -> { Entity },
	iterZones: (self: QuickZone) -> () -> Zone?,
	iterObservers: (self: QuickZone) -> () -> Observer?,
	iterGroups: (self: QuickZone) -> () -> Group?,
	iterEntities: (self: QuickZone) -> () -> Entity?,

	getZonesAtPoint: (self: QuickZone, position: Vector3) -> { Zone },
	iterZonesAtPoint: (self: QuickZone, position: Vector3) -> () -> Zone?,

	getPlayerOfEntity: (self: QuickZone, entity: Entity) -> Player?,
	getZonesOfEntity: (self: QuickZone, entity: Entity) -> { Zone },
	iterZonesOfEntity: (self: QuickZone, entity: Entity) -> () -> Zone?,
	getGroupsOfEntity: (self: QuickZone, entity: Entity) -> { Group },
	iterGroupsOfEntity: (self: QuickZone, entity: Entity) -> () -> Group?,
	getZonesOfPlayer: (self: QuickZone, player: Player) -> { Zone },
	iterZonesOfPlayer: (self: QuickZone, player: Player) -> () -> Zone?,
	getGroupsOfPlayer: (self: QuickZone, player: Player) -> { Group },
	iterGroupsOfPlayer: (self: QuickZone, player: Player) -> () -> Group?,
}

export type ZoneClass = {
	new: (
		config: {
			cframe: CFrame,
			size: Vector3,
			shape: ShapeType?,
			reference: (BasePart | Attachment)?,
			isDynamic: boolean?,
			metadata: any?,
			observers: { Observer }?,
		}
	) -> Zone,
	fromPart: (part: BasePart, config: { isDynamic: boolean?, metadata: any?, observers: { Observer }? }?) -> Zone,
	fromParts: (
		parts: { BasePart },
		config: { isDynamic: boolean?, metadata: any?, observers: { Observer }? }?
	) -> Zones,
	fromTag: (tag: string, config: { isDynamic: boolean?, metadata: any?, observers: { Observer }? }?) -> Zones,
	fromDescendants: (
		parent: Instance,
		config: { isDynamic: boolean?, metadata: any?, observers: { Observer }? }?
	) -> Zones,
	fromChildren: (
		parent: Instance,
		config: { isDynamic: boolean?, metadata: any?, observers: { Observer }? }?
	) -> Zones,
}

export type Zone = {
	attach: (self: Zone, observer: Observer) -> Zone,
	detach: (self: Zone, observer: Observer) -> Zone,

	sync: (self: Zone) -> Zone,
	setReference: (self: Zone, reference: (BasePart | Attachment)?) -> Zone,
	setAutoSync: (self: Zone, autoSync: boolean) -> Zone,
	setDynamic: (self: Zone, dynamic: boolean) -> Zone,
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

	isDynamic: (self: Zone) -> boolean,
	isPointInside: (self: Zone, point: Vector3) -> boolean,

	onDestroy: (self: Zone, callback: () -> ()) -> () -> (),
	destroy: (self: Zone) -> (),
}

export type InternalZone = Zone & {
	id: number,
	reference: (BasePart | Attachment)?,
	dynamic: boolean,
	metadata: any?,
	autoSync: boolean,
	syncConnections: { RBXScriptConnection }?,
	onDestroyCallbacks: { () -> () }?,
}

export type Zones = {
	attach: (self: Zones, observer: Observer) -> Zones,
	detach: (self: Zones, observer: Observer) -> Zones,

	sync: (self: Zones) -> Zones,
	setAutoSync: (self: Zones, autoSync: boolean) -> Zones,
	setDynamic: (self: Zones, dynamic: boolean) -> Zones,
	getZones: (self: Zones) -> { Zone },
	getMetadata: (self: Zones) -> any?,
	isDynamic: (self: Zones) -> boolean,
	isPointInside: (self: Zones, point: Vector3) -> boolean,
	setMetadata: (self: Zones, metadata: any?) -> Zones,
	contains: (self: Zones, zone: Zone) -> boolean,
	iterZones: (self: Zones) -> () -> Zone?,

	onDestroy: (self: Zones, callback: () -> ()) -> () -> (),
	destroy: (self: Zones) -> (),
}

export type InternalZones = Zones & {
	autoSync: boolean?,
	dynamic: boolean,
	metadata: any?,
	zones: { [Zone]: boolean },
	observers: { [Observer]: boolean },
	onDestroyCallbacks: { () -> () }?,
	onDestroyObserverCleanups: { [Observer]: () -> () },
	onDestroyZoneCleanups: { [Zone]: () -> () },
	add: (self: InternalZones, zone: Zone) -> (),
	remove: (self: InternalZones, zone: Zone) -> (),
}

export type ObserverClass = {
	new: (
		config: {
			groups: { Group }?,
			priority: number?,
			updateRate: number?,
			precision: number?,
			enabled: boolean?,
			safety: boolean?,
		}?
	) -> Observer,
}

export type Observer = {
	subscribe: (self: Observer, group: Group) -> Observer,
	unsubscribe: (self: Observer, group: Group) -> Observer,
	setPriority: (self: Observer, n: number) -> Observer,
	setUpdateRate: (self: Observer, hz: number) -> Observer,
	setPrecision: (self: Observer, n: number) -> Observer,
	setEnabled: (self: Observer, enabled: boolean) -> Observer,
	setSafety: (self: Observer, enabled: boolean) -> Observer,

	isEnabled: (self: Observer) -> boolean,
	isSafe: (self: Observer) -> boolean,
	isPointInside: (self: Observer, position: Vector3) -> boolean,

	getId: (self: Observer) -> number,
	getPriority: (self: Observer) -> number,
	getUpdateRate: (self: Observer) -> number,
	getPrecision: (self: Observer) -> number,
	getZones: (self: Observer) -> { Zone },
	getGroups: (self: Observer) -> { Group },
	getEntitiesInside: (self: Observer) -> { Entity },
	getPlayersInside: (self: Observer) -> { Player },
	getZoneOfEntity: (self: Observer, entity: Entity) -> Zone?,
	getZoneOfPlayer: (self: Observer, player: Player) -> Zone?,
	getEntitiesInZone: (self: Observer, zone: Zone) -> { Entity },
	getPlayersInZone: (self: Observer, zone: Zone) -> { Player },

	iterZones: (self: Observer) -> () -> Zone?,
	iterGroups: (self: Observer) -> () -> Group?,
	iterEntitiesInside: (self: Observer) -> () -> (Entity?, Zone?),
	iterPlayersInside: (self: Observer) -> () -> (Player?, Zone?),
	iterEntitiesInZone: (self: Observer, zone: Zone) -> () -> Entity?,
	iterPlayersInZone: (self: Observer, zone: Zone) -> () -> Player?,

	observe: (self: Observer, callback: (Entity, Zone) -> (() -> ())?) -> () -> (),
	observePlayer: (self: Observer, callback: (Player, Zone) -> (() -> ())?) -> () -> (),
	observeLocalPlayer: (self: Observer, callback: (Zone) -> (() -> ())?) -> () -> (),
	observeGroup: (self: Observer, callback: (Group, Zone) -> (() -> ())?) -> () -> (),
	onEnter: (self: Observer, callback: (Entity, Zone) -> ()) -> () -> (),
	onExit: (self: Observer, callback: (Entity, Zone) -> ()) -> () -> (),
	onPlayerEnter: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onPlayerExit: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onLocalPlayerEnter: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onLocalPlayerExit: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onGroupEnter: (self: Observer, callback: (Group, Zone) -> ()) -> () -> (),
	onGroupExit: (self: Observer, callback: (Group, Zone) -> ()) -> () -> (),
	onTransition: (self: Observer, callback: (Entity, Zone, Zone) -> ()) -> () -> (),
	onPlayerTransition: (self: Observer, callback: (Player, Zone, Zone) -> ()) -> () -> (),
	onLocalPlayerTransition: (self: Observer, callback: (Zone, Zone) -> ()) -> () -> (),

	onDestroy: (self: Observer, callback: () -> ()) -> () -> (),
	destroy: (self: Observer) -> (),
}

export type InternalObserver = Observer & {
	id: number,
	onDestroyCallbacks: { () -> () }?,
}

export type GroupClass = {
	new: (config: {
		entities: { Entity }?,
	}?) -> Group,
	fromTag: (tag: string, config: {
		entities: { Entity }?,
	}?) -> Group,
	players: (config: {
		entities: { Entity }?,
	}?) -> Group,
	localPlayer: (config: {
		entities: { Entity }?,
	}?) -> Group,
}

export type Group = {
	add: (self: Group, entity: Entity) -> Group,
	addBulk: (self: Group, entities: { Entity }) -> Group,
	remove: (self: Group, entity: Entity) -> Group,
	removeBulk: (self: Group, entities: { Entity }) -> Group,
	clear: (self: Group) -> Group,

	getId: (self: Group) -> number,
	getEntities: (self: Group) -> { Entity },
	contains: (self: Group, entity: Entity) -> boolean,
	getPlayers: (self: Group) -> { Player },
	iterEntities: (self: Group) -> () -> Entity?,
	iterPlayers: (self: Group) -> () -> Player?,

	onDestroy: (self: Group, callback: () -> ()) -> () -> (),
	destroy: (self: Group) -> (),
}

export type InternalGroup = Group & {
	id: number,
	entities: { Entity },
	entityIndices: { [Entity]: number },
	onDestroyCallbacks: { () -> () }?,
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
	precisionSq: number,
	updateRate: number,
	bucketIndex: number,
	staticVersion: number,
	dynamicVersion: number,
	logicVersion: number,
	needsStatic: boolean,
	needsDynamic: boolean,
}

return nil
