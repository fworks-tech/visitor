# ResourceSystem.gd
# Global resource manager tracking shelter supplies (Food, Water, Ammo, Medicine, Fuel).
extends Node

signal resources_changed(resources: Dictionary)

var food: int = 25
var water: int = 25
var ammo: int = 12
var medicine: int = 6
var fuel: int = 10

func consume_food(amount: int = 1) -> bool:
	if food >= amount:
		food -= amount
		resources_changed.emit(get_resources())
		return true
	food = 0
	resources_changed.emit(get_resources())
	return false

func consume_water(amount: int = 1) -> bool:
	if water >= amount:
		water -= amount
		resources_changed.emit(get_resources())
		return true
	water = 0
	resources_changed.emit(get_resources())
	return false

func consume_ammo(amount: int = 1) -> bool:
	if ammo >= amount:
		ammo -= amount
		resources_changed.emit(get_resources())
		return true
	return false

func consume_medicine(amount: int = 1) -> bool:
	if medicine >= amount:
		medicine -= amount
		resources_changed.emit(get_resources())
		return true
	return false

func consume_fuel(amount: int = 1) -> bool:
	if fuel >= amount:
		fuel -= amount
		resources_changed.emit(get_resources())
		return true
	return false

func add_resources(res_dict: Dictionary) -> void:
	food += res_dict.get("food", 0)
	water += res_dict.get("water", 0)
	ammo += res_dict.get("ammo", 0)
	medicine += res_dict.get("medicine", 0)
	fuel += res_dict.get("fuel", 0)
	resources_changed.emit(get_resources())

func get_resources() -> Dictionary:
	return {
		"food": food,
		"water": water,
		"ammo": ammo,
		"medicine": medicine,
		"fuel": fuel
	}

func get_save_data() -> Dictionary:
	return get_resources()

func load_save_data(data: Dictionary) -> void:
	food = int(data.get("food", 25))
	water = int(data.get("water", 25))
	ammo = int(data.get("ammo", 12))
	medicine = int(data.get("medicine", 6))
	fuel = int(data.get("fuel", 10))
	resources_changed.emit(get_resources())
