#!/usr/bin/env bash
# Fails when a class does a multi-step Core operation itself. Operations that take several steps in a set order
# belong to Core/Groups, Core/Wiring and Core/GroupPresence, so a class that looks right on its own can't skip a step.
# Classes may still read Core tables and make single-owner calls (Callbacks.connect, ZoneShapes.setCFrame, ...).
# It also fails when a module writes a field of entity, group, observer or Registry state that another module owns
set -euo pipefail
cd "$(dirname "$0")/.."

# One line per owner: its operations that a coordinator now sequences
forbidden=(
	'Routing\.[A-Za-z]+\('
	'Members\.[A-Za-z]+\('
	'Links\.(attach|detach|detachAll|subscribe|unsubscribe|unsubscribeAll)\('
	'Entities\.(join|leave|drop|dropGroup)\('
	'Memberships\.(move|exit|exitObserver|exitUnsubscribed|leaveZone|setZoneDestroying)\('
	'GroupPresence\.(groupsChanged|subscriptionChanged|groupDestroyed)\('
	'ZoneShapes\.(setDynamic|allocateSlot|add|remove)\('
	'PlayerTracker\.(subscribe|unsubscribe|dropGroup)\('
	'References\.(link|forget|release)\('
	'\.groups =([^=]|$)'
)
pattern=$(IFS='|'; echo "${forbidden[*]}")

failed=0

# grep exits 1 when nothing matches, and 2 on an error, which must fail the check too
check() {
	local message=$1
	shift
	local status=0
	grep -nE "$@" || status=$?
	if [ "$status" -eq 0 ]; then
		echo "$message" >&2
		failed=1
	elif [ "$status" -ne 1 ]; then
		echo "check-structure: grep failed" >&2
		exit "$status"
	fi
}

check "Classes must leave these operations to Core/Groups, Core/Wiring and Core/GroupPresence" \
	"$pattern" src/Classes/*.luau

# Whether a group brings an entity into an observer is Memberships.bringsIn; Routing caches its answers
check "Ask Memberships.bringsIn, isSubscribed or Links.subscribes instead of reading a group's subscribers" \
	'subscribers\[' -r src --include='*.luau' \
	--exclude=Links.luau --exclude=Memberships.luau --exclude=Routing.luau

check "Zones are added and removed through Wiring" \
	'ZoneShapes\.(allocateSlot|add|remove)\(' -r src --include='*.luau' --exclude=Wiring.luau --exclude=ZoneShapes.luau

# The state of entities, groups, observers and Registry, each field with the modules that may write it. Catches a
# direct write such as `data.updateRate = x` or `observer.tracked[e] = z`, not one through a local alias
writers=(
	'\.activeObserverMemberships Memberships'
	'\.(strategy|dropped|members|memberIndices) Entities'
	'\.(linkedObservers|bucketIndex|needsStatic|needsDynamic|staticZoneCount|dynamicZoneCount) Routing'
	'\.(precisionSq|updateRate) Routing,Wiring'
	'\.logicVersion Scheduler,Routing'
	'\.(lastPosition|staticVersion|dynamicVersion) Scheduler,ZoneShapes'
	'\.subscribers Links'
	'\.(autoClean|removalWatches) Members'
	'\.(priority|enabled|safety) Wiring'
	'\.(enteredCallbacks|exitedCallbacks|transitionedCallbacks) Wiring,Callbacks'
	'\.tracked Memberships'
	'\.trackers GroupPresence,Wiring'
	'\.(hasAttached|hasSubscribed) Observer'
	'Registry\.groups Groups'
	'Registry\.(observers|zoneIdToZoneObj|zoneSlotToZoneObj) Wiring'
	'Registry\.autoSyncZones Zone'
)
for rule in "${writers[@]}"; do
	read -r field owners <<<"$rule"
	excludes=(--exclude=Registry.luau)
	for owner in ${owners//,/ }; do
		excludes+=("--exclude=$owner.luau")
	done
	check "Only $owners may write ${field//\\/}" \
		"$field(\[[^]]*\])? *=([^=]|$)" -r src --include='*.luau' "${excludes[@]}"
done

exit "$failed"
