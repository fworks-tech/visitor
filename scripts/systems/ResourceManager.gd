class_name ResourceManager
extends Node

## ResourceManager
## Tracks shelter resources (food, water, ammo, medicine, fuel), daily consumption per survivor,
## scavenging missions (with infection/injury risks), medical treatment, and ammunition usage.

signal resources_changed(current_resources: Dictionary)
signal shortage_occurred(shortage_report: Dictionary)
signal scavenge_completed(result: Dictionary)

# Resource Defaults
const DEFAULT_FOOD: float = 25.0
const DEFAULT_WATER: float = 25.0
const DEFAULT_AMMO: float = 12.0
const DEFAULT_MEDICINE: float = 6.0
const DEFAULT_FUEL: float = 10.0

# Consumption Rates (per survivor per day)
const DAILY_FOOD_PER_SURVIVOR: float = 1.0
const DAILY_WATER_PER_SURVIVOR: float = 1.0
const DAILY_FUEL_PER_DAY: float = 1.5

var resources: Dictionary = {
	"food": DEFAULT_FOOD,
	"water": DEFAULT_WATER,
	"ammo": DEFAULT_AMMO,
	"medicine": DEFAULT_MEDICINE,
	"fuel": DEFAULT_FUEL
}

func _ready() -> void:
	pass

## Returns duplicate of current resource levels
func get_resource_status() -> Dictionary:
	return resources.duplicate()

## Consume daily food, water, and fuel for the total number of survivors in shelter.
## Returns detailed report including any shortages.
func consume_daily_resources(survivor_count: int) -> Dictionary:
	var required_food: float = survivor_count * DAILY_FOOD_PER_SURVIVOR
	var required_water: float = survivor_count * DAILY_WATER_PER_SURVIVOR
	var required_fuel: float = DAILY_FUEL_PER_DAY

	var shortage_food: float = maxf(0.0, required_food - resources["food"])
	var shortage_water: float = maxf(0.0, required_water - resources["water"])
	var shortage_fuel: float = maxf(0.0, required_fuel - resources["fuel"])

	resources["food"] = maxf(0.0, resources["food"] - required_food)
	resources["water"] = maxf(0.0, resources["water"] - required_water)
	resources["fuel"] = maxf(0.0, resources["fuel"] - required_fuel)

	var report: Dictionary = {
		"survivor_count": survivor_count,
		"consumed": {
			"food": required_food - shortage_food,
			"water": required_water - shortage_water,
			"fuel": required_fuel - shortage_fuel
		},
		"shortages": {
			"food": shortage_food,
			"water": shortage_water,
			"fuel": shortage_fuel
		},
		"has_shortage": shortage_food > 0.0 or shortage_water > 0.0 or shortage_fuel > 0.0
	}

	resources_changed.emit(resources.duplicate())

	if report["has_shortage"]:
		shortage_occurred.emit(report)

	return report

## Execute a scavenging mission by sending a survivor out.
## Danger level (0.1 to 1.0) increases resource yield but also risk of infection, injury, or death.
func scavenge(location_danger_level: float, assigned_survivor: Dictionary) -> Dictionary:
	var danger: float = clampf(location_danger_level, 0.1, 1.0)
	var survivor_name: String = assigned_survivor.get("name", "Scavenger")

	# Base yield scaling with danger level
	var yield_food: float = randf_range(1.0, 4.0) * (1.0 + danger)
	var yield_water: float = randf_range(1.0, 4.0) * (1.0 + danger)
	var yield_ammo: float = randf_range(0.0, 3.0) if randf() < danger * 0.8 else 0.0
	var yield_meds: float = randf_range(0.0, 2.0) if randf() < danger * 0.5 else 0.0
	var yield_fuel: float = randf_range(0.0, 3.0) if randf() < danger * 0.6 else 0.0

	# Risk calculations
	var infection_risk: float = danger * 0.35
	var injury_risk: float = danger * 0.40
	var death_risk: float = danger * 0.10

	var returned_infected: bool = randf() < infection_risk
	var returned_injured: bool = randf() < injury_risk
	var died: bool = randf() < death_risk

	if died:
		yield_food *= 0.2
		yield_water *= 0.2

	# Add gathered resources to pool
	resources["food"] += yield_food
	resources["water"] += yield_water
	resources["ammo"] += yield_ammo
	resources["medicine"] += yield_meds
	resources["fuel"] += yield_fuel

	if returned_infected:
		assigned_survivor["is_infected"] = true
		assigned_survivor["infection_progress"] = randf_range(0.15, 0.35)

	if returned_injured:
		assigned_survivor["injured"] = true
		assigned_survivor["health"] = assigned_survivor.get("health", 100.0) - randf_range(25.0, 50.0)

	var result: Dictionary = {
		"survivor_name": survivor_name,
		"danger_level": danger,
		"yield": {
			"food": yield_food,
			"water": yield_water,
			"ammo": yield_ammo,
			"medicine": yield_meds,
			"fuel": yield_fuel
		},
		"survivor_status": {
			"died": died,
			"returned_injured": returned_injured,
			"returned_infected": returned_infected
		}
	}

	resources_changed.emit(resources.duplicate())
	scavenge_completed.emit(result)
	return result

## Use medicine supply to treat a sick/injured/infected survivor
func use_medicine(target_survivor: Dictionary, potency: float = 0.2) -> Dictionary:
	if resources["medicine"] < 1.0:
		return {"success": false, "reason": "No medicine available in shelter reserves."}

	resources["medicine"] -= 1.0
	var treated_infection: bool = false
	var treated_injury: bool = false

	if target_survivor.get("is_infected", false):
		var old_p: float = target_survivor.get("infection_progress", 0.0)
		target_survivor["infection_progress"] = maxf(0.05, old_p - potency)
		target_survivor["suppressed_days"] = target_survivor.get("suppressed_days", 0) + 2
		treated_infection = true

	if target_survivor.get("injured", false):
		target_survivor["injured"] = false
		target_survivor["health"] = minf(100.0, target_survivor.get("health", 50.0) + 40.0)
		treated_injury = true

	resources_changed.emit(resources.duplicate())
	return {
		"success": true,
		"target_name": target_survivor.get("name", "Survivor"),
		"treated_infection": treated_infection,
		"treated_injury": treated_injury,
		"remaining_medicine": resources["medicine"]
	}

## Deduct ammunition for gate defense or execution decisions
func use_ammo(amount: int = 1) -> bool:
	if resources["ammo"] < amount:
		return false
	resources["ammo"] -= amount
	resources_changed.emit(resources.duplicate())
	return true

## Deduct fuel reserves
func use_fuel(amount: float = 1.0) -> bool:
	if resources["fuel"] < amount:
		return false
	resources["fuel"] -= amount
	resources_changed.emit(resources.duplicate())
	return true

## Add resource dictionary to shelter pool
func add_resources(additions: Dictionary) -> Dictionary:
	for key in additions.keys():
		if resources.has(key):
			resources[key] += additions[key]
	resources_changed.emit(resources.duplicate())
	return resources.duplicate()

## Check if shelter possesses at least required amounts
func has_enough_resources(required: Dictionary) -> bool:
	for key in required.keys():
		if resources.get(key, 0.0) < required[key]:
			return false
	return true

## Evaluate if shelter can sustain an additional survivor for N days
func can_feed_new_survivor(current_survivors: int, days_ahead: int = 3) -> bool:
	var project_survivors: int = current_survivors + 1
	var food_needed: float = project_survivors * DAILY_FOOD_PER_SURVIVOR * days_ahead
	var water_needed: float = project_survivors * DAILY_WATER_PER_SURVIVOR * days_ahead
	return resources["food"] >= food_needed and resources["water"] >= water_needed
