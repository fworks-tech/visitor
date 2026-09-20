# ConsequenceSystem.gd
# Global consequence processing subsystem bridge.
extends Node

var consequences_engine: ConsequencesSystem

func _ready() -> void:
	consequences_engine = ConsequencesSystem.new()
	add_child(consequences_engine)

func process_overnight_outcomes() -> Array:
	var shelter_state = {
		"trust": float(GameManager.trust_value),
		"corruption": float(GameManager.corruption_value)
	}
	var logs = consequences_engine.process_day(GameManager.current_day, shelter_state)
	GameManager.trust_value = int(shelter_state.get("trust", GameManager.trust_value))
	GameManager.corruption_value = int(shelter_state.get("corruption", GameManager.corruption_value))
	return logs

func record_decision(visitor: Dictionary, decision: String, current_day: int, shelter_state: Dictionary) -> Dictionary:
	return consequences_engine.record_decision(visitor, decision, current_day, shelter_state)
