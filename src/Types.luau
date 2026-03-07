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

export type Observer<T = Entity, M = any> = {
	subscribe: (self: Observer<T, M>, group: Group<T>) -> Observer<T, M>,
	unsubscribe: (self: Observer<T, M>, group: Group<T>) -> Observer<T, M>,
	setPriority: (self: Observer<T, M>, n: number) -> Observer<T, M>,
	setUpdateRate: (self: Observer<T, M>, hz: number) -> Observer<T, M>,
	setPrecision: (self: Observer<T, M>, n: number) -> Observer<T, M>,
	setEnabled: (self: Observer<T, M>, enabled: boolean) -> Observer<T, M>,
	setSafety: (self: Observer<T, M>, enabled: boolean) -> Observer<T, M>,

	isEnabled: (self: Observer<T, M>) -> boolean,
	isSafe: (self: Observer<T, M>) -> boolean,
	isPointInside: (self: Observer<T, M>, position: Vector3) -> boolean,

	getId: (self: Observer<T, M>) -> number,
	getPriority: (self: Observer<T, M>) -> number,
	getUpdateRate: (self: Observer<T, M>) -> number,
	getPrecision: (self: Observer<T, M>) -> number,
	getZones: (self: Observer<T, M>) -> { Zone<M> },
	getGroups: (self: Observer<T, M>) -> { Group<T> },
	getEntitiesInside: (self: Observer<T, M>) -> { T },
	getPlayersInside: (self: Observer<T, M>) -> { Player },
	getZoneOfEntity: (self: Observer<T, M>, entity: T) -> Zone<M>?,
	getZoneOfPlayer: (self: Observer<T, M>, player: Player) -> Zone<M>?,
	getEntitiesInZone: (self: Observer<T, M>, zone: Zone<M>) -> { T },
	getPlayersInZone: (self: Observer<T, M>, zone: Zone<M>) -> { Player },

	iterZones: (self: Observer<T, M>) -> () -> Zone<M>?,
	iterGroups: (self: Observer<T, M>) -> () -> Group<T>?,
	iterEntitiesInside: (self: Observer<T, M>) -> () -> (T?, Zone<M>?),
	iterPlayersInside: (self: Observer<T, M>) -> () -> (Player?, Zone<M>?),
	iterEntitiesInZone: (self: Observer<T, M>, zone: Zone<M>) -> () -> T?,
	iterPlayersInZone: (self: Observer<T, M>, zone: Zone<M>) -> () -> Player?,

	observe: (self: Observer<T, M>, callback: (T, Zone<M>) -> (() -> ())?) -> () -> (),
	observePlayer: (self: Observer<T, M>, callback: (Player, Zone<M>) -> (() -> ())?) -> () -> (),
	observeLocalPlayer: (self: Observer<T, M>, callback: (Zone<M>) -> (() -> ())?) -> () -> (),
	observeGroup: (self: Observer<T, M>, callback: (Group<T>, Zone<M>) -> (() -> ())?) -> () -> (),
	onEnter: (self: Observer<T, M>, callback: (T, Zone<M>) -> ()) -> () -> (),
	onExit: (self: Observer<T, M>, callback: (T, Zone<M>) -> ()) -> () -> (),
	onPlayerEnter: (self: Observer<T, M>, callback: (Player, Zone<M>) -> ()) -> () -> (),
	onPlayerExit: (self: Observer<T, M>, callback: (Player, Zone<M>) -> ()) -> () -> (),
	onLocalPlayerEnter: (self: Observer<T, M>, callback: (Zone<M>) -> ()) -> () -> (),
	onLocalPlayerExit: (self: Observer<T, M>, callback: (Zone<M>) -> ()) -> () -> (),
	onGroupEnter: (self: Observer<T, M>, callback: (Group<T>, Zone<M>) -> ()) -> () -> (),
	onGroupExit: (self: Observer<T, M>, callback: (Group<T>, Zone<M>) -> ()) -> () -> (),
	onTransition: (self: Observer<T, M>, callback: (T, Zone<M>, Zone<M>) -> ()) -> () -> (),
	onPlayerTransition: (self: Observer<T, M>, callback: (Player, Zone<M>, Zone<M>) -> ()) -> () -> (),
	onLocalPlayerTransition: (self: Observer<T, M>, callback: (Zone<M>, Zone<M>) -> ()) -> () -> (),

	onDestroy: (self: Observer<T, M>, callback: () -> ()) -> () -> (),
	destroy: (self: Observer<T, M>) -> (),
}

export type ObserverClass = {
	new: <T>(
		config: {
			groups: { Group<T> }?,
			priority: number?,
			updateRate: number?,
			precision: number?,
			enabled: boolean?,
			safety: boolean?,
		}?
	) -> Observer<T, any>,
}

export type InternalObserver<T = Entity, M = any> = Observer<T, M> & {
	id: number,
	onDestroyCallbacks: { () -> () }?,
}

export type QuickZone = {
	Zone: ZoneClass,
	Observer: ObserverClass,
	Group: GroupClass,

	configure: (
		self: QuickZone,
		config: { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }
	) -> QuickZone,
	setEnabled: (self: QuickZone, enabled: boolean) -> QuickZone,
	rebuild: (self: QuickZone) -> QuickZone,
	update: (self: QuickZone, dt: number) -> QuickZone,
	setFrameBudget: (self: QuickZone, ms: number) -> QuickZone,
	setReference: (self: QuickZone, reference: any?, entity: Entity?) -> QuickZone,
	visualize: (self: QuickZone, enabled: boolean) -> QuickZone,
	removeEntity: (self: QuickZone, entity: any) -> QuickZone,

	getEntityOfReference: (self: QuickZone, reference: any) -> Entity?,
	getReferenceOfEntity: (self: QuickZone, entity: Entity) -> any,
	getZones: (self: QuickZone) -> { Zone<any> },
	getObservers: (self: QuickZone) -> { Observer<any, any> },
	getGroups: (self: QuickZone) -> { Group<any> },
	getEntities: (self: QuickZone) -> { any },
	iterZones: (self: QuickZone) -> () -> Zone<any>?,
	iterObservers: (self: QuickZone) -> () -> Observer<any, any>?,
	iterGroups: (self: QuickZone) -> () -> Group<any>?,
	iterEntities: (self: QuickZone) -> () -> any?,
	getZonesAtPoint: (self: QuickZone, position: Vector3) -> { Zone<any> },
	iterZonesAtPoint: (self: QuickZone, position: Vector3) -> () -> Zone<any>?,
	getZonesOfEntity: (self: QuickZone, entity: any) -> { Zone<any> },
	iterZonesOfEntity: (self: QuickZone, entity: any) -> () -> Zone<any>?,
	getGroupsOfEntity: (self: QuickZone, entity: any) -> { Group<any> },
	iterGroupsOfEntity: (self: QuickZone, entity: any) -> () -> Group<any>?,
}

export type ZoneClass = {
	new: <M>(
		config: {
			cframe: CFrame,
			size: Vector3,
			shape: ShapeType?,
			reference: (BasePart | Attachment | Bone)?,
			isDynamic: boolean?,
			metadata: M?,
			autoSync: boolean?,
			observers: { Observer<any, M> }?,
		}
	) -> Zone<M>,

	fromPart: <M>(
		part: BasePart,
		config: { isDynamic: boolean?, metadata: M?, autoSync: boolean?, observers: { Observer<any, M> }? }?
	) -> Zone<M>,

	fromParts: <M>(
		parts: { BasePart },
		config: { isDynamic: boolean?, metadata: M?, autoSync: boolean?, observers: { Observer<any, M> }? }?
	) -> Zones<M>,

	fromTag: <M>(
		tag: string,
		config: { isDynamic: boolean?, metadata: M?, autoSync: boolean?, observers: { Observer<any, M> }? }?
	) -> Zones<M>,

	fromDescendants: <M>(
		parent: Instance,
		config: { isDynamic: boolean?, metadata: M?, autoSync: boolean?, observers: { Observer<any, M> }? }?
	) -> Zones<M>,

	fromChildren: <M>(
		parent: Instance,
		config: { isDynamic: boolean?, metadata: M?, autoSync: boolean?, observers: { Observer<any, M> }? }?
	) -> Zones<M>,
}

export type Zone<M = any> = {
	attach: (self: Zone<M>, observer: any) -> Zone<M>,
	detach: (self: Zone<M>, observer: any) -> Zone<M>,

	sync: (self: Zone<M>) -> Zone<M>,
	setReference: (self: Zone<M>, reference: (BasePart | Attachment | Bone)?) -> Zone<M>,
	setAutoSync: (self: Zone<M>, autoSync: boolean) -> Zone<M>,
	setDynamic: (self: Zone<M>, dynamic: boolean) -> Zone<M>,
	setCFrame: (self: Zone<M>, cf: CFrame) -> Zone<M>,
	setPosition: (self: Zone<M>, pos: Vector3) -> Zone<M>,
	setSize: (self: Zone<M>, size: Vector3) -> Zone<M>,
	setShape: (self: Zone<M>, shape: ShapeType) -> Zone<M>,
	setMetadata: (self: Zone<M>, metadata: M?) -> Zone<M>,

	getMetadata: (self: Zone<M>) -> M?,
	getId: (self: Zone<M>) -> number,
	getReference: (self: Zone<M>) -> (BasePart | Attachment | Bone)?,
	getPosition: (self: Zone<M>) -> Vector3,
	getCFrame: (self: Zone<M>) -> CFrame,
	getSize: (self: Zone<M>) -> Vector3,
	getShape: (self: Zone<M>) -> ShapeType,

	isDynamic: (self: Zone<M>) -> boolean,
	isPointInside: (self: Zone<M>, point: Vector3) -> boolean,

	onDestroy: (self: Zone<M>, callback: () -> ()) -> () -> (),
	destroy: (self: Zone<M>) -> (),
}

export type InternalZone<M = any> = Zone<M> & {
	id: number,
	reference: (BasePart | Attachment | Bone)?,
	dynamic: boolean,
	metadata: M?,
	autoSync: boolean,
	syncConnections: { RBXScriptConnection }?,
	onDestroyCallbacks: { () -> () }?,
}

export type Zones<M = any> = {
	attach: <T>(self: Zones<M>, observer: Observer<T, M>) -> Zones<M>,
	detach: <T>(self: Zones<M>, observer: Observer<T, M>) -> Zones<M>,

	sync: (self: Zones<M>) -> Zones<M>,
	setAutoSync: (self: Zones<M>, autoSync: boolean) -> Zones<M>,
	setDynamic: (self: Zones<M>, dynamic: boolean) -> Zones<M>,
	getZones: (self: Zones<M>) -> { Zone<M> },
	getMetadata: (self: Zones<M>) -> M?,
	isDynamic: (self: Zones<M>) -> boolean,
	isPointInside: (self: Zones<M>, point: Vector3) -> boolean,
	setMetadata: (self: Zones<M>, metadata: M?) -> Zones<M>,
	contains: (self: Zones<M>, zone: Zone<M>) -> boolean,
	iterZones: (self: Zones<M>) -> () -> Zone<M>?,

	onDestroy: (self: Zones<M>, callback: () -> ()) -> () -> (),
	destroy: (self: Zones<M>) -> (),
}

export type InternalZones<M = any> = Zones<M> & {
	autoSync: boolean?,
	dynamic: boolean,
	metadata: M?,
	zones: { [Zone<M>]: boolean },
	observers: { [Observer<any, M>]: boolean },
	onDestroyCallbacks: { () -> () }?,
	onDestroyObserverCleanups: { [Observer<any, M>]: () -> () },
	onDestroyZoneCleanups: { [Zone<M>]: () -> () },
	add: (self: InternalZones<M>, zone: Zone<M>) -> (),
	remove: (self: InternalZones<M>, zone: Zone<M>) -> (),
}

export type GroupClass = {
	new: <T>(config: {
		entities: { T }?,
		autoClean: boolean?,
	}?) -> Group<T>,
	fromTag: (tag: string) -> Group<Entity>,
	players: () -> Group<Player>,
	localPlayer: () -> Group<Player>,
}

export type Group<T = Entity> = {
	add: (self: Group<T>, entity: T) -> Group<T>,
	addBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	remove: (self: Group<T>, entity: T) -> Group<T>,
	removeBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	clear: (self: Group<T>) -> Group<T>,

	setAutoClean: (self: Group<T>, enabled: boolean) -> Group<T>,
	getId: (self: Group<T>) -> number,
	getEntities: (self: Group<T>) -> { T },
	contains: (self: Group<T>, entity: T) -> boolean,
	getPlayers: (self: Group<T>) -> { Player },
	iterEntities: (self: Group<T>) -> () -> T?,
	iterPlayers: (self: Group<T>) -> () -> Player?,

	onDestroy: (self: Group<T>, callback: () -> ()) -> () -> (),
	destroy: (self: Group<T>) -> (),
}

export type InternalGroup<T = Entity> = Group<T> & {
	_add: (self: Group<T>, entity: T) -> Group<T>,
	_addBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	_remove: (self: Group<T>, entity: T) -> Group<T>,
	_removeBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	_clear: (self: Group<T>) -> Group<T>,
	id: number,
	entities: { T },
	entityIndices: { [T]: number },
	isManaged: boolean?,
	autoClean: boolean,
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
