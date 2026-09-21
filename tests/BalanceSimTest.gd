extends Node

## Balance simulation (`godot --headless --path <project> -- --balance-test`).
## Drives autoload-level economy without scenes: generator burns 2 fuel/day
## (+1 if unchecked), the cellar yields randi_range(2, 4) from day 7 —
## same shapes as HouseScene handlers. Rational policy checks the generator
## daily and farms the cellar; passive ignores everything. Asserts ranges,
## never exact RNG values. Deterministic: seed(42).
##
## NOTE: food has no dawn upkeep (guests eat free once admitted) and water
## has no sink at all — the sim intentionally covers fuel only.

const START_FUEL := 10

var failures: Array = []

func _ready() -> void:
	_run()

func check(cond: bool, label: String) -> void:
	print(("PASS " if cond else "FAIL ") + label)
	if not cond:
		failures.append(label)

func _reset() -> void:
	ResourceSystem.fuel = START_FUEL
	GameManager.current_day = 1
	GameManager.trust_value = 60
	GameManager.morale_value = 50
	GameManager.security_value = 50
	FlagsManager.set_flag("generator_checked", false)

func _dawn_cost(pay_checked: bool) -> int:
	var cost := 2
	if not pay_checked:
		cost += 1
	ResourceSystem.consume_fuel(cost)
	return cost

func _run() -> void:
	seed(42)
	var ratio_curve := [10, 8, 6, 4, 2, 0]
	# Rational: generator checked every dawn, so cost is exactly 2/day.
	_reset()
	var fuel_at_dawn := []
	for day in range(1, 8):
		GameManager.current_day = day
		fuel_at_dawn.append(ResourceSystem.fuel)
		FlagsManager.set_flag("generator_checked", true)
		_dawn_cost(true)
	check(fuel_at_dawn.slice(0, 6) == ratio_curve, "rational fuel hits exactly 0 on day-6 dawn")
	check(ResourceSystem.fuel == 0, "checked generator still runs dry before basement day")
	# Day 7+: cellar farming recovers fuel (real 2-4 shape, 20 seeded runs).
	var ends := []
	for i in 20:
		_reset()
		for day in range(1, 7):
			FlagsManager.set_flag("generator_checked", true)
			_dawn_cost(true)
		FlagsManager.set_flag("generator_checked", true)
		_dawn_cost(true)
		ResourceSystem.add_resources({"fuel": randi_range(2, 4)})
		ends.append(ResourceSystem.fuel)
	check(ends.min() >= 0, "one cellar search covers day-7 cost")
	var mean := 0.0
	for e in ends:
		mean += e
	check(mean / 20.0 >= 1.5, "20 seeded cellar runs average >= 1.5 fuel")
	# Passive: never checks the generator, costs 3/day — dark by dawn 4.
	_reset()
	var dark_by := -1
	for day in range(1, 8):
		GameManager.current_day = day
		FlagsManager.set_flag("generator_checked", false)
		_dawn_cost(false)
		if ResourceSystem.fuel <= 0 and dark_by < 0:
			dark_by = day
	check(dark_by == 4, "passive house goes dark on day-4 dawn")
	check(ResourceSystem.fuel == 0, "passive fuel never recovers without the cellar")

	print("RESULT %d failures" % failures.size())
	for x in failures:
		print("FAILED: ", x)
	get_tree().quit(1 if not failures.is_empty() else 0)
