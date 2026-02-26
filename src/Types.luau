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

export type QuickZone = {
	Zone: ZoneClass,
	Observer: ObserverClass,
	Group: GroupClass,
	setAutoUpdate: (self: QuickZone, enabled: boolean) -> QuickZone,
	update: (self: QuickZone, dt: number) -> QuickZone,
	setFrameBudget: (self: QuickZone, ms: number) -> QuickZone,
	getZones: (self: QuickZone) -> { Zone },
	getObservers: (self: QuickZone) -> { Observer },
	getGroups: (self: QuickZone) -> { Group },
	getPlayerOfEntity: (self: QuickZone, entity: Entity) -> Player?,
	getZonesOfEntity: (self: QuickZone, entity: Entity) -> { Zone },
	getZonesOfPlayer: (self: QuickZone, player: Player) -> { Zone },
	getObserversOfEntity: (self: QuickZone, entity: Entity) -> { Observer },
	getObserversOfPlayer: (self: QuickZone, player: Player) -> { Observer },
	getGroupsOfEntity: (self: QuickZone, entity: Entity) -> { Group },
	getGroupsOfPlayer: (self: QuickZone, player: Player) -> { Group },
	getZonesAtPoint: (self: QuickZone, position: Vector3) -> { Zone },
	getObserversAtPoint: (self: QuickZone, position: Vector3) -> { Observer },
	getEntities: (self: QuickZone) -> { Entity },
	visualize: (self: QuickZone, enabled: boolean) -> QuickZone,
}

export type ZoneClass = {
	new: (
		config: {
			cframe: CFrame,
			size: Vector3,
			shape: ShapeType?,
			part: BasePart?,
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
	onDestroy: (self: Zone, callback: () -> ()) -> () -> (),
	destroy: (self: Zone) -> (),
}

export type InternalZone = Zone & {
	id: number,
	part: BasePart?,
	dynamic: boolean,
	metadata: any?,
	onDestroyCallbacks: { () -> () }?,
}

export type Zones = {
	attach: (self: Zones, observer: Observer) -> Zones,
	detach: (self: Zones, observer: Observer) -> Zones,
	syncToParts: (self: Zones) -> Zones,
	getZones: (self: Zones) -> { Zone },
	getObservers: (self: Zones) -> { Observer },
	getMetadata: (self: Zones) -> any?,
	isDynamic: (self: Zones) -> boolean,
	isPointInside: (self: Zones, point: Vector3) -> boolean,
	setMetadata: (self: Zones, metadata: any?) -> Zones,
	contains: (self: Zones, zone: Zone) -> boolean,
	onDestroy: (self: Zones, callback: () -> ()) -> () -> (),
	destroy: (self: Zones) -> (),
}

export type InternalZones = Zones & {
	isDynamic: boolean,
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
	isPlayerInside: (self: Observer, player: Player) -> boolean,
	isLocalPlayerInside: (self: Observer) -> boolean,
	isEntityInside: (self: Observer, entity: Entity) -> boolean,
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
	iterEntitiesInside: (self: Observer) -> () -> Entity?,
	iterPlayersInside: (self: Observer) -> () -> Player?,
	iterZonesOfEntities: (self: Observer) -> () -> (Entity?, Zone?),
	iterZonesOfPlayers: (self: Observer) -> () -> (Player?, Zone?),
	observe: (self: Observer, callback: (Entity, Zone) -> (() -> ())?) -> () -> (),
	observePlayer: (self: Observer, callback: (Player, Zone) -> (() -> ())?) -> () -> (),
	observeLocalPlayer: (self: Observer, callback: (Zone) -> (() -> ())?) -> () -> (),
	observeGroup: (self: Observer, callback: (Group, Zone) -> (() -> ())?) -> () -> (),
	onEntered: (self: Observer, callback: (Entity, Zone) -> ()) -> () -> (),
	onExited: (self: Observer, callback: (Entity, Zone) -> ()) -> () -> (),
	onPlayerEntered: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onPlayerExited: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onLocalPlayerEntered: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onLocalPlayerExited: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onGroupEntered: (self: Observer, callback: (Group, Zone) -> ()) -> () -> (),
	onGroupExited: (self: Observer, callback: (Group, Zone) -> ()) -> () -> (),
	onTransitioned: (self: Observer, callback: (Entity, Zone, Zone) -> ()) -> () -> (),
	onPlayerTransitioned: (self: Observer, callback: (Player, Zone, Zone) -> ()) -> () -> (),
	onLocalPlayerTransitioned: (self: Observer, callback: (Zone, Zone) -> ()) -> () -> (),
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
	getObservers: (self: Group) -> { Observer },
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
	lastSpatialVersion: number,
	precisionSq: number,
	updateRate: number,
	bucketIndex: number,
}

return nil
