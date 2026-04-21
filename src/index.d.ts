export type ShapeType = "Block" | "Ball" | "Cylinder" | "Wedge" | "CornerWedge"

export interface EntityTable {
	Position?: Vector3
	WorldPosition?: Vector3
	CFrame?: CFrame
	Transform?: CFrame
	GetPivot?: (self: any) => CFrame
}

export type Entity = Player | BasePart | Model | Camera | Attachment | Bone | EntityTable

export interface Zone {
	setAutoSync(autoSync: boolean): Zone
	setReference(reference: BasePart | Attachment | Bone | undefined): Zone
	sync(): Zone
	setDynamic(isDynamic: boolean): Zone
	setCFrame(cf: CFrame): Zone
	setPosition(pos: Vector3): Zone
	setSize(size: Vector3): Zone
	setShape(shape: ShapeType): Zone
	setMetadata(metadata: any): Zone
	getMetadata(): any
	getId(): number
	getReference(): BasePart | Attachment | Bone | undefined
	getPosition(): CFrame
	getCFrame(): CFrame
	getSize(): Vector3
	getShape(): ShapeType
	isPointInside(point: Vector3): boolean
	isDynamic(): boolean
	onDestroy(callback: () => void): () => void
	destroy(): void
}

export interface Zones {
	sync(): Zones
	getZones(): Zone[]
	isDynamic(): boolean
	isPointInside(point: Vector3): boolean
	setAutoSync(autoSync: boolean): Zones
	setDynamic(isDynamic: boolean): Zones
	setMetadata(metadata: any): Zones
	getMetadata(): any
	contains(zone: Zone): boolean
	iterZones(): () => Zone | undefined
	getReferences(): (BasePart | Attachment | Bone)[]
	iterReferences(): () => [(BasePart | Attachment | Bone) | undefined, Zone | undefined]
	onDestroy(callback: () => void): () => void
	destroy(): void
}

export interface QuickZone {
	configure(config: { enabled?: boolean; autoSyncRate?: number; frameBudget?: number }): QuickZone
	setEnabled(enabled: boolean): QuickZone
	update(dt: number): QuickZone
	setAutoSyncRate(hz: number): QuickZone
	rebuild(): QuickZone
	setReference(entity: Entity, reference?: any): QuickZone
	setFrameBudget(ms: number): QuickZone
	removeEntity(entity: Entity): QuickZone
	getEntityOfReference(reference: any): Entity | undefined
	getReferenceOfEntity(entity: Entity): any
	getObservers(): Observer[]
	getGroups(): Group[]
	getZones(): Zone[]
	getEntities(): Entity[]
	getZonesAtPoint(position: Vector3): Zone[]
	getZonesOfEntity(entity: Entity): Zone[]
	getGroupsOfEntity(entity: Entity): Group[]
	iterGroups(): () => Group | undefined
	iterZones(): () => Zone | undefined
	iterEntities(): () => Entity | undefined
	iterObservers(): () => Observer | undefined
	iterGroupsOfEntity(entity: Entity): () => Group | undefined
	iterZonesOfEntity(entity: Entity): () => Zone | undefined
	iterZonesAtPoint(point: Vector3): () => Zone | undefined
	visualize(enabled: boolean): QuickZone
}

declare const QuickZone: QuickZone
export default QuickZone

export declare const Zone: {
	new (config: {
		cframe: CFrame
		size: Vector3
		shape?: ShapeType
		reference?: BasePart | Attachment | Bone
		isDynamic?: boolean
		metadata?: any
		autoSync?: boolean
		observers?: Observer[]
	}): Zone

	fromPart(part: BasePart, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }): Zone
	fromParts(parts: BasePart[], config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }): Zones
	fromChildren(parent: Instance, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }): Zones
	fromDescendants(parent: Instance, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }): Zones
	fromTag(tag: string, config?: { isDynamic?: boolean; metadata?: any; autoSync?: boolean; observers?: Observer[] }): Zones
}

export interface ObserverConfig {
	groups?: Group[]
	zones?: Zone | Zones[]
	priority?: number
	updateRate?: number
	precision?: number
	enabled?: boolean
	safety?: boolean
}

export interface Observer {
	subscribe(group: Group): Observer
	unsubscribe(group: Group): Observer
	attach(zone: Zone): Observer
	detach(zone: Zone): Observer
	observe(callback: (entity: any, zone: Zone) => (() => void) | undefined): () => void
	onEnter(callback: (entity: any, zone: Zone) => void): () => void
	onExit(callback: (entity: any, zone: Zone) => void): () => void
	observePlayer(callback: (player: Player, zone: Zone) => (() => void) | undefined): () => void
	onPlayerEnter(callback: (player: Player, zone: Zone) => void): () => void
	onPlayerExit(callback: (player: Player, zone: Zone) => void): () => void
	observeLocalPlayer(callback: (zone: Zone) => (() => void) | undefined): () => void
	onLocalPlayerEnter(callback: (zone: Zone) => void): () => void
	onLocalPlayerExit(callback: (zone: Zone) => void): () => void
	observeGroup(callback: (group: Group, zone: Zone) => (() => void) | undefined): () => void
	onGroupEnter(callback: (group: Group, zone: Zone) => void): () => void
	onGroupExit(callback: (group: Group, zone: Zone) => void): () => void
	onTransition(callback: (entity: any, newZone: Zone) => void): () => void
	onPlayerTransition(callback: (player: Player, newZone: Zone) => void): () => void
	onLocalPlayerTransition(callback: (newZone: Zone) => void): () => void
	setEnabled(enabled: boolean): Observer
	setSafety(enabled: boolean): Observer
	setPriority(p: number): Observer
	setUpdateRate(hz: number): Observer
	setPrecision(n: number): Observer
	isEnabled(): boolean
	isPointInside(position: Vector3): boolean
	isSafe(): boolean
	getId(): number
	getPriority(): number
	getUpdateRate(): number
	getPrecision(): number
	getEntitiesInside(): any[]
	getPlayersInside(): Player[]
	getZones(): Zone[]
	getGroups(): Group[]
	getEntityInZone(entity: Entity): Zone | undefined
	getPlayerInZone(player: Player): Zone | undefined
	getEntitiesInZone(zone: Zone): any[]
	getPlayersInZone(zone: Zone): Player[]
	iterZones(): () => Zone | undefined
	iterGroups(): () => Group | undefined
	iterEntitiesInside(): () => [Entity | undefined, Zone | undefined]
	iterPlayersInside(): () => [Player | undefined, Zone | undefined]
	iterEntitiesInZone(zone: Zone): () => Entity | undefined
	iterPlayersInZone(zone: Zone): () => Player | undefined
	onDestroy(callback: () => void): () => void
	destroy(): void
}

export declare const Observer: {
	new (config?: ObserverConfig): Observer
}

export interface GroupConfig {
	entities?: any[]
	autoClean?: boolean
}

export interface Group {
	setAutoClean(enabled: boolean): Group
	add(entity: any): Group
	addBulk(entities: any[]): Group
	remove(entity: any): Group
	removeBulk(entities: any[]): Group
	clear(): Group
	contains(entity: any): boolean
	getId(): number
	getEntities(): any[]
	iterEntities(): () => any | undefined
	onDestroy(callback: () => void): () => void
	destroy(): void
}

export declare const Group: {
	new (config?: GroupConfig): Group
	fromTag(tag: string): Group
	players(): Group
	localPlayer(): Group
}
