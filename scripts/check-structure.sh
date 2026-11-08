#!/usr/bin/env bash
# Fails when a class does a multi-step Core operation itself. Operations that take several steps in a set order
# belong to Core/Groups and Core/Wiring, so a class that looks right on its own can't skip a step. Classes may still
# read Core tables and make single-owner calls (Callbacks.connect, ZoneShapes.setCFrame, ...)
set -euo pipefail
cd "$(dirname "$0")/.."

# One line per owner: its operations that a coordinator now sequences
forbidden=(
	'Routing\.[A-Za-z]+\('
	'Members\.[A-Za-z]+\('
	'Links\.(attach|detach|detachAll|subscribe|unsubscribe|unsubscribeAll|addGroup|dropGroup)\('
	'Entities\.(join|leave|drop|addGroup|dropGroup)\('
	'Memberships\.(move|exit|exitObserver|exitUnsubscribed|leaveZone|groupsChanged|groupDestroyed|addObserver|dropObserver)\('
	'Callbacks\.(addObserver|dropObserver)\('
	'ZoneShapes\.setDynamic\('
	'PlayerTracker\.(subscribe|unsubscribe|dropGroup)\('
	'References\.(link|forget|release)\('
	'Registry\.observer(PriorityMap|Enabled|Safety|UpdateRate|PrecisionSq)\[[^]]*\] ='
)
pattern=$(IFS='|'; echo "${forbidden[*]}")

# grep exits 1 when nothing matches, and 2 on an error, which must fail the check too
status=0
grep -nE "$pattern" src/Classes/*.luau || status=$?
if [ "$status" -eq 0 ]; then
	echo "Classes must leave these operations to Core/Groups and Core/Wiring" >&2
	exit 1
elif [ "$status" -ne 1 ]; then
	echo "check-structure: grep failed" >&2
	exit "$status"
fi
