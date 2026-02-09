--!strict

export type ShapeType = 'Block' | 'Ball' | 'Cylinder' | 'Wedge' | 'CornerWedge'

export type BoundingVolume = {
	Position: Vector3,
	CFrame: CFrame,
	HalfSize: Vector3,
	Shape: ShapeType,

	-- Sphere / cylinder specific
	RadiusSq: number?,

	-- Cylinder specific
	Start: Vector3?,
	Axis: Vector3?,
	AxisLength: number?,
}

export type Node = {
	Left: Node?,
	Right: Node?,
	Min: Vector3,
	Max: Vector3,
	Id: number, -- -1 for internal nodes
}

export type BitZone = {
	-- Factories
	Zone: (cframe: CFrame, size: Vector3, shape: ShapeType, associatedPart: BasePart?) -> Zone,
	ZoneFromPart: (part: BasePart) -> Zone,
	Observer: (priority: number?) -> Observer,
	Group: ({
		UpdateRate: number?,
		Precision: number?,
		SafetyMode: boolean?,
	}?) -> Group,
	GroupPlayers: ({
		UpdateRate: number?,
		Precision: number?,
		SafetyMode: boolean?,
	}?) -> Group,
	GroupLocalPlayer: ({
		UpdateRate: number?,
		Precision: number?,
		SafetyMode: boolean?,
	}?) -> Group,

	-- Global config
	setFrameBudget: (self: BitZone, n: number) -> BitZone,

	-- Getters
	getObserversAtPoint: (self: BitZone, position: Vector3) -> { Observer },
	getGroupOfEntity: (self: BitZone, entity: Entity) -> Group?,
	getZones: (self: BitZone) -> { Zone },
	getObservers: (self: BitZone) -> { Observer },
	getGroups: (self: BitZone) -> { Group },
	getEntities: (self: BitZone) -> { Entity },

	-- Queries
	isEntityValidType: (self: BitZone, entity: any) -> boolean,
	isEntityInAnyGroup: (self: BitZone, entity: Entity) -> boolean,
}

export type Zone = {
	-- Lifecycle
	destroy: (zone: Zone) -> (),

	-- State
	bindToObservers: (zone: Zone, ...Observer) -> Zone,
	unbindFromObservers: (zone: Zone, ...Observer) -> Zone,

	-- Utility
	getObservers: (zone: Zone) -> { Observer },

	-- Props
	Id: number,
	Part: BasePart?,
}

export type Callback = (Entity, Zone, any?) -> ()

export type Observer = {
	-- Lifecycle
	destroy: (self: Observer) -> (),

	-- Config
	setPriority: (self: Observer, n: number) -> Observer,

	-- State
	track: (self: Observer, Group) -> Observer,
	untrack: (self: Observer, Group) -> Observer,

	-- Queries
	isPlayerInside: (self: Observer, player: Player) -> boolean,
	isLocalPlayerInside: (self: Observer) -> boolean,
	isEntityInside: (self: Observer, entity: Entity) -> boolean,
	isPointInside: (self: Observer, position: Vector3) -> boolean,

	-- Getters
	getEntitiesInside: (self: Observer) -> { Entity },
	getEntities: (self: Observer) -> { Entity },
	getZones: (self: Observer) -> { Zone },
	getGroups: (self: Observer) -> { Group },

	-- Events
	onEntered: (self: Observer, callback: Callback) -> () -> (),
	onExited: (self: Observer, callback: Callback) -> () -> (),
	onLocalPlayerEntered: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onLocalPlayerExited: (self: Observer, callback: (Zone) -> ()) -> () -> (),
	onPlayerEntered: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),
	onPlayerExited: (self: Observer, callback: (Player, Zone) -> ()) -> () -> (),

	-- Props
	Id: number,
}

export type Group = {
	-- Lifecycle
	destroy: (self: Group) -> (),

	-- Config
	setUpdateRate: (self: Group, hz: number) -> Group,
	setPrecision: (self: Group, n: number) -> Group,
	setSafetyMode: (self: Group, enabled: boolean) -> Group,
	setConfig: (
		self: Group,
		{
			UpdateRate: number?,
			Precision: number?,
			SafetyMode: boolean?,
		}?
	) -> Group,

	-- State
	add: (self: Group, entity: Entity, customData: any?) -> Group,
	remove: (self: Group, entity: Entity) -> Group,

	-- Getters
	getEntities: (self: Group) -> { Entity },
	getObservers: (self: Group) -> { Observer },
	getConfig: (self: Group) -> {
		UpdateRate: number,
		Precision: number,
		SafetyMode: boolean,
	},

	-- Props
	Id: number,
	_entities: { Entity },
	_entityIndices: { [Entity]: number },
	_entityData: { [Entity]: EntityData },
	_config: {
		UpdateRate: number,
		PrecisionSq: number,
		SafetyMode: boolean,
	},
	_lastProcessedIndex: number,
}

export type EntityTable = {
	Position: Vector3?,
	WorldPosition: Vector3?,
	CFrame: CFrame?,
	GetPivot: ((self: any) -> CFrame)?,
	[any]: any,
}

export type Entity = BasePart | Model | Camera | Attachment | Bone | EntityTable

export type EntityData = {
	ActiveObserverMemberships: { [number]: number },
	LastPosition: Vector3,
	Strategy: number,
	IsDirty: boolean,
}

return nil
