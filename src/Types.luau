--!strict

--[=[
	@type ShapeType "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge" | "Mesh"
	@within QuickZone
	The geometric shape of a Zone.

	`Mesh` resolves containment against the collision geometry of the zone's part
	reference, so it requires a `BasePart` reference to query.
]=]
export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge' | 'Mesh'

--[=[
	@interface EntityTable
	@within QuickZone
	.Position Vector3?
	.WorldPosition Vector3?
	.CFrame CFrame?
	.Transform: CFrame?
	.GetPivot ((any) -> CFrame)?
	A custom table that mimics the spatial properties of a Roblox Instance.
]=]
export type EntityTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	Transform: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
}

--[=[
	@type Entity Player | BasePart | Model | Camera | Attachment | Bone | EntityTable
	@within QuickZone
]=]
export type Entity = Player | BasePart | Model | Camera | Attachment | Bone | EntityTable

export type Phase = 'alive' | 'destroying' | 'dead'

-- A missing phase means alive: zones leave it out until they are destroyed, which keeps their tables small
export type Destroyable = { phase: Phase?, onDestroyCallbacks: { () -> () }? }

export type SyncMode = 'static' | 'dynamic' | 'synced'

-- What a tree needs before the next query: nothing, new bounds for the same leaves, or new leaves. A request only
-- moves it forward (none -> refit -> rebuild), and updating the tree brings it back to none.
export type TreeUpdate = 'none' | 'refit' | 'rebuild'

-- Where a tree's leaves get their boxes: from min and max, or where a leaf has none there, its center plus and minus
-- its half size
export type LeafBoxes = {
	min: { [number]: Vector3 },
	max: { [number]: Vector3 },
	centers: { [number]: Vector3 },
	halfSizes: { [number]: Vector3 },
}

export type Tree = {
	buffer: buffer,
	count: number,
	cost: number,
	refitSkips: number,
	pendingUpdate: TreeUpdate,
}

export type ChangeSlot = {
	version: number,
	all: boolean,
	tree: Tree,
}

export type ZoneChanges = {
	boxesMin: { Vector3 },
	boxesMax: { Vector3 },
	boxCount: number,
	all: boolean,
	boxLimit: number,
	history: { ChangeSlot },
}

export type EntityData = {
	activeObserverMemberships: { [number]: number },
	strategy: number,
	groups: { [number]: true },
	dropped: boolean,
	linkedObservers: { [number]: true }?,
	precisionSq: number,
	updateRate: number,
	bucketIndex: number,
	needsStatic: boolean,
	needsDynamic: boolean,
	logicVersion: number,
	lastPosition: Vector3,
	staticVersion: number,
	dynamicVersion: number,
	clearCenter: Vector3,
	clearRadius: number,
	soleObserver: number?,
}

export type Group<T = any> = {
	add: (self: Group<T>, entity: T) -> Group<T>,
	addBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	remove: (self: Group<T>, entity: T) -> Group<T>,
	removeBulk: (self: Group<T>, entities: { T }) -> Group<T>,
	clear: (self: Group<T>) -> Group<T>,

	setAutoClean: (self: Group<T>, enabled: boolean) -> Group<T>,
	getId: (self: Group<T>) -> number,
	getEntities: (self: Group<T>) -> { T },
	contains: (self: Group<T>, entity: T) -> boolean,
	iterEntities: (self: Group<T>) -> () -> T?,
	onDestroy: (self: Group<T>, callback: () -> ()) -> () -> (),
	destroy: (self: Group<T>) -> (),
}

export type InternalGroup<T = any> = Group<T> & Destroyable & {
	id: number,
	subscribers: { [number]: true },
	members: { Entity },
	memberIndices: { [Entity]: number },
	autoClean: boolean,
	removalWatches: { [Instance]: RBXScriptConnection },
}

export type GroupClass = {
	new: (config: {
		entities: { any }?,
		autoClean: boolean?,
	}?) -> Group<any>,
	fromTag: (tag: string) -> Group<Entity>,
	players: () -> Group<Player>,
	localPlayer: () -> Group<Player>,
}

export type Zone = {
	sync: (self: Zone) -> Zone,
	setReference: (self: Zone, reference: (Attachment | BasePart | Bone)?) -> Zone,
	setAutoSync: (self: Zone, autoSync: boolean) -> Zone,
	setDynamic: (self: Zone, dynamic: boolean) -> Zone,
	setCFrame: (self: Zone, cf: CFrame) -> Zone,
	setPosition: (self: Zone, pos: Vector3) -> Zone,
	setSize: (self: Zone, size: Vector3) -> Zone,
	setShape: (self: Zone, shape: ShapeType) -> Zone,
	setMetadata: (self: Zone, metadata: any?) -> Zone,

	getMetadata: (self: Zone) -> any?,
	getId: (self: Zone) -> number,
	getReference: (self: Zone) -> (Attachment | BasePart | Bone)?,
	getPosition: (self: Zone) -> Vector3,
	getCFrame: (self: Zone) -> CFrame,
	getSize: (self: Zone) -> Vector3,
	getShape: (self: Zone) -> ShapeType,

	isDynamic: (self: Zone) -> boolean,
	isPointInside: (self: Zone, point: Vector3) -> boolean,

	onDestroy: (self: Zone, callback: () -> ()) -> () -> (),
	destroy: (self: Zone) -> (),
}

export type InternalZone = Zone & Destroyable & {
	attach: (self: Zone, observer: any) -> Zone,
	detach: (self: Zone, observer: any) -> Zone,

	id: number,
	slot: number,
	-- Set only while the zone asks for shape Mesh, which follows a part reference
	meshRequested: true?,
	reference: (Attachment | BasePart | Bone)?,
	metadata: any?,
	autoSync: true?,
	syncConnections: { RBXScriptConnection }?,
}

export type Zones = {
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
	getReferences: (self: Zones) -> { Attachment | BasePart | Bone },
	iterReferences: (self: Zones) -> () -> ((Attachment | BasePart | Bone)?, Zone?),

	onDestroy: (self: Zones, callback: () -> ()) -> () -> (),
	destroy: (self: Zones) -> (),
}

export type InternalZones = Zones & Destroyable & {
	attach: (self: Zones, observer: any) -> Zones,
	detach: (self: Zones, observer: any) -> Zones,
	_attachObserver: (self: Zones, observer: any) -> Zones,
	_detachObserver: (self: Zones, observer: any) -> Zones,

	syncMode: SyncMode,
	metadata: any?,
	zones: { [Zone]: boolean },
	observers: { [any]: boolean },
	onDestroyObserverCleanups: { [any]: () -> () },
	onDestroyZoneCleanups: { [any]: () -> () },
	_addZone: (self: InternalZones, zone: Zone) -> (),
	_removeZone: (self: InternalZones, zone: Zone) -> (),
	add: (self: InternalZones, zone: Zone) -> (),
	remove: (self: InternalZones, zone: Zone) -> (),
}

-- Options of the Zone constructors that make zones from parts, for their code. The public signatures in ZoneClass
-- spell them out, so an editor shows the fields rather than this name
export type PartsConfig = { isDynamic: boolean?, metadata: any?, autoSync: boolean? }

export type ZoneClass = {
	new: (
		config: {
			cframe: CFrame,
			size: Vector3,
			shape: ShapeType?,
			reference: (Attachment | BasePart | Bone)?,
			isDynamic: boolean?,
			metadata: any?,
			autoSync: boolean?,
		}
	) -> Zone,
	fromPart: (part: BasePart, config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?) -> Zone,
	fromParts: (
		parts: { BasePart },
		config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	) -> Zones,
	fromTag: (tag: string, config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?) -> Zones,
	fromDescendants: (
		parent: Instance,
		config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	) -> Zones,
	fromChildren: (
		parent: Instance,
		config: { isDynamic: boolean?, metadata: any?, autoSync: boolean? }?
	) -> Zones,
}

export type Observer<T = any> = {
	subscribe: (self: Observer<T>, group: Group<T>) -> Observer<T>,
	unsubscribe: (self: Observer<T>, group: Group<T>) -> Observer<T>,
	attach: (self: Observer<T>, zone: Zone | Zones) -> Observer<T>,
	detach: (self: Observer<T>, zone: Zone | Zones) -> Observer<T>,

	setPriority: (self: Observer<T>, n: number) -> Observer<T>,
	setUpdateRate: (self: Observer<T>, hz: number) -> Observer<T>,
	setPrecision: (self: Observer<T>, n: number) -> Observer<T>,
	setEnabled: (self: Observer<T>, enabled: boolean) -> Observer<T>,
	setSafety: (self: Observer<T>, enabled: boolean) -> Observer<T>,

	isEnabled: (self: Observer<T>) -> boolean,
	isSafe: (self: Observer<T>) -> boolean,
	isPointInside: (self: Observer<T>, position: Vector3) -> boolean,

	getId: (self: Observer<T>) -> number,
	getPriority: (self: Observer<T>) -> number,
	getUpdateRate: (self: Observer<T>) -> number,
	getPrecision: (self: Observer<T>) -> number,
	getZones: (self: Observer<T>) -> { Zone },
	getGroups: (self: Observer<T>) -> { Group<T> },
	getEntitiesInside: (self: Observer<T>) -> { T },
	getPlayersInside: (self: Observer<T>) -> { Player },
	getZoneOfEntity: (self: Observer<T>, entity: T) -> Zone?,
	getZoneOfPlayer: (self: Observer<T>, player: Player) -> Zone?,
	getEntitiesInZone: (self: Observer<T>, zone: Zone | Zones) -> { T },
	getPlayersInZone: (self: Observer<T>, zone: Zone | Zones) -> { Player },

	iterZones: (self: Observer<T>) -> () -> Zone?,
	iterGroups: (self: Observer<T>) -> () -> Group<T>?,
	iterEntitiesInside: (self: Observer<T>) -> () -> (T?, Zone?),
	iterPlayersInside: (self: Observer<T>) -> () -> (Player?, Zone?),
	iterEntitiesInZone: (self: Observer<T>, zone: Zone | Zones) -> () -> T?,
	iterPlayersInZone: (self: Observer<T>, zone: Zone | Zones) -> () -> Player?,

	observe: (self: Observer<T>, callback: (T, Zone, Entity) -> (() -> ())?) -> () -> (),
	observePlayer: (self: Observer<T>, callback: (Player, Zone, Entity) -> (() -> ())?) -> () -> (),
	observeLocalPlayer: (self: Observer<T>, callback: (Zone, Entity) -> (() -> ())?) -> () -> (),
	observeGroup: (self: Observer<T>, callback: (Group<T>, Zone, Entity) -> (() -> ())?) -> () -> (),
	onEnter: (self: Observer<T>, callback: (T, Zone, Entity) -> ()) -> () -> (),
	onExit: (self: Observer<T>, callback: (T, Zone, Entity) -> ()) -> () -> (),
	onPlayerEnter: (self: Observer<T>, callback: (Player, Zone, Entity) -> ()) -> () -> (),
	onPlayerExit: (self: Observer<T>, callback: (Player, Zone, Entity) -> ()) -> () -> (),
	onLocalPlayerEnter: (self: Observer<T>, callback: (Zone, Entity) -> ()) -> () -> (),
	onLocalPlayerExit: (self: Observer<T>, callback: (Zone, Entity) -> ()) -> () -> (),
	onGroupEnter: (self: Observer<T>, callback: (Group<T>, Zone, Entity) -> ()) -> () -> (),
	onGroupExit: (self: Observer<T>, callback: (Group<T>, Zone, Entity) -> ()) -> () -> (),
	onTransition: (self: Observer<T>, callback: (T, Zone, Entity) -> ()) -> () -> (),
	onPlayerTransition: (self: Observer<T>, callback: (Player, Zone, Entity) -> ()) -> () -> (),
	onLocalPlayerTransition: (self: Observer<T>, callback: (Zone, Entity) -> ()) -> () -> (),

	onDestroy: (self: Observer<T>, callback: () -> ()) -> () -> (),
	destroy: (self: Observer<T>) -> (),
}

export type ObserverClass = {
	new: (
		config: {
			groups: { Group<any> }?,
			zones: { Zone | Zones }?,
			priority: number?,
			updateRate: number?,
			precision: number?,
			enabled: boolean?,
			safety: boolean?,
		}?
	) -> Observer<any>,
}

export type InternalObserver<T = any> = Observer<T> & Destroyable & {
	id: number,
	priority: number,
	updateRate: number,
	precisionSq: number,
	enabled: boolean,
	safety: boolean,
	staticZoneCount: number,
	dynamicZoneCount: number,
	tracked: { [Entity]: number },
	enteredCallbacks: { ObserverCallback },
	exitedCallbacks: { ObserverCallback },
	transitionedCallbacks: { ObserverCallback },
	trackers: { Tracker }?,
	hasAttached: boolean,
	hasSubscribed: boolean,
}

export type ObserverCallback = (any, Zone, Entity) -> ()
export type Tracker = (entity: Entity?, destroyedGroupId: number?) -> ()

export type QuickZone = {
	Zone: ZoneClass,
	Observer: ObserverClass,
	Group: GroupClass,

	configure: (
		self: QuickZone,
		config: { enabled: boolean?, autoSyncRate: number?, frameBudget: number? }
	) -> QuickZone,
	setEnabled: (self: QuickZone, enabled: boolean) -> QuickZone,
	setAutoSyncRate: (self: QuickZone, hz: number) -> QuickZone,
	rebuild: (self: QuickZone) -> QuickZone,
	update: (self: QuickZone, dt: number?) -> QuickZone,
	setFrameBudget: (self: QuickZone, ms: number) -> QuickZone,
	setReference: (self: QuickZone, entity: Entity, reference: any?) -> QuickZone,
	visualize: (self: QuickZone, enabled: boolean) -> QuickZone,
	removeEntity: (self: QuickZone, entity: any) -> QuickZone,

	getEntityOfReference: (self: QuickZone, reference: any) -> Entity?,
	getReferenceOfEntity: (self: QuickZone, entity: Entity) -> any,
	getZones: (self: QuickZone) -> { Zone },
	getObservers: (self: QuickZone) -> { Observer<any> },
	getGroups: (self: QuickZone) -> { Group<any> },
	getEntities: (self: QuickZone) -> { any },
	iterZones: (self: QuickZone) -> () -> Zone?,
	iterObservers: (self: QuickZone) -> () -> Observer<any>?,
	iterGroups: (self: QuickZone) -> () -> Group<any>?,
	iterEntities: (self: QuickZone) -> () -> any?,
	getZonesAtPoint: (self: QuickZone, position: Vector3) -> { Zone },
	iterZonesAtPoint: (self: QuickZone, position: Vector3) -> () -> Zone?,
	getZonesOfEntity: (self: QuickZone, entity: any) -> { Zone },
	iterZonesOfEntity: (self: QuickZone, entity: any) -> () -> Zone?,
	getGroupsOfEntity: (self: QuickZone, entity: any) -> { Group<any> },
	iterGroupsOfEntity: (self: QuickZone, entity: any) -> () -> Group<any>?,
}

return nil
