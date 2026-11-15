#!/usr/bin/env bash
# Fails when a class does a multi-step Core operation itself. Operations that take several steps in a set order
# belong to Core/Groups, Core/Wiring and Core/GroupPresence, so a class that looks right on its own can't skip a step.
# Classes may still read Core tables and make single-owner calls (Callbacks.connect, ZoneShapes.setCFrame, ...)
set -euo pipefail
cd "$(dirname "$0")/.."

# One line per owner: its operations that a coordinator now sequences
forbidden=(
	'Routing\.[A-Za-z]+\('
	'Members\.[A-Za-z]+\('
	'Links\.(attach|detach|detachAll|subscribe|unsubscribe|unsubscribeAll|addGroup|dropGroup)\('
	'Entities\.(join|leave|drop|addGroup|dropGroup)\('
	'Memberships\.(move|exit|exitObserver|exitUnsubscribed|leaveZone|setZoneDestroying)\('
	'GroupPresence\.(groupsChanged|subscriptionChanged|groupDestroyed)\('
	'ZoneShapes\.(setDynamic|allocateSlot|add|remove)\('
	'PlayerTracker\.(subscribe|unsubscribe|dropGroup)\('
	'References\.(link|forget|release)\('
	'Registry\.observers\[[^]]*\] =([^=]|$)'
	'\.(priority|updateRate|precisionSq|enabled|safety|staticZoneCount|dynamicZoneCount|tracked|trackers) =([^=]|$)'
	'Registry\.zone(IdToZoneObj|SlotToZoneObj)\[[^]]*\] =([^=]|$)'
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
check "Ask Memberships.bringsIn or isSubscribed instead of reading groupToObservers per group" \
	'groupToObservers\[' -r src --include='*.luau' \
	--exclude=Links.luau --exclude=Memberships.luau --exclude=Routing.luau

check "Zones are added and removed through Wiring" \
	'ZoneShapes\.(allocateSlot|add|remove)\(' -r src --include='*.luau' --exclude=Wiring.luau --exclude=ZoneShapes.luau

exit "$failed"
