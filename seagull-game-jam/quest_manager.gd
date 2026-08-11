extends Node

@onready var quest_complete = preload("res://quest_complete.tscn")

enum QuestType { GIVEN, HIDDEN }
enum QuestStatus { LOCKED, ACTIVE, COMPLETED }

var all_quests: Dictionary = {
	"disgrace_to_humanity": {
		"name": "Disgrace to Humanity",
		"description": "Kill a human",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "human",
		"requirement": func(node): return node.position.y < -100,
		"status": QuestStatus.LOCKED    # GIVEN quests start locked
	},
		"knock_building": {
		"name": "I Didn't touch it",
		"description": "Knock the falling building off the edge",
		"type": QuestType.HIDDEN,        # Must be given before it can complete
		"checker": "building",
		"requirement": func(node): return node.position.y < -100,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	},
		"steal_chip": {
		"name": "First of Many",
		"description": "Steal a chip from the dude on the beach",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "chip",
		"requirement": func(node): var r = Global.first_chip; Global.first_chip = false; print(r); return r,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	},
		"nuke": {
		"name": "Nuclear Disaster",
		"description": "poo in the nuclear power plant",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "poo",
		"requirement": func(node): return get_tree().get_first_node_in_group("Nuke_centre").global_position.distance_to(node.position) < 20 and node.large and node._edit_started and not node._impact_triggered,
		"status": QuestStatus.LOCKED    # GIVEN quests start locked
	},
		"ocean_poo": {
		"name": "It was the fish",
		"description": "poo in the ocean and meet a new friend",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "poo",
		"requirement": func(node): return node.position.y < 0,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	}
}

# Only quests the player KNOWS about (given + discovered hidden ones)
var known_quests: Array = []
var completed_quests: Array = []

func give_quest(quest_id: String) -> void:
	var quest = all_quests.get(quest_id)
	if not quest:
		return
	if quest.type != QuestType.GIVEN:
		return
	if quest.status == QuestStatus.LOCKED:
		quest.status = QuestStatus.ACTIVE
		known_quests.append(quest_id)  # Make sure this is quest_id, not quest or anything else
		quest_received.emit(quest_id)

# Called by human/player nodes when an event happens
func check_quests(checker_type: String, node: Node) -> void:
	for quest_id in all_quests:
		var quest = all_quests[quest_id]

		# Skip if not active
		if quest.status != QuestStatus.ACTIVE:
			continue
		# Skip if wrong checker
		if quest.checker != checker_type:
			continue
		# Run the requirement
		if quest.requirement.call(node):
			complete_quest(quest_id)

func complete_quest(quest_id: String) -> void:
	var inst = quest_complete.instantiate()
	inst.get_node("Control/Label2/Label2").text = all_quests[quest_id].name
	add_child(inst)
	var quest = all_quests[quest_id]
	quest.status = QuestStatus.COMPLETED
	completed_quests.append(quest_id)
	quest_completed.emit(quest_id)

# Signals for UI to listen to
signal quest_received(quest_id: String)
signal quest_completed(quest_id: String)
signal hidden_quest_discovered(quest_id: String)

func get_active_quests() -> Array:
	var result = []
	for quest_id in QuestManager.known_quests:
		var quest = QuestManager.all_quests[quest_id]
		if quest.status == QuestStatus.ACTIVE:
			result.append({
				"id": quest_id,
				"name": quest.name,
				"description": quest.description
			})
	return result

func get_completed_quests() -> Array:
	var result = []
	for quest_id in QuestManager.completed_quests:
		var quest = QuestManager.all_quests[quest_id]
		result.append({
			"id": quest_id,
			"name": quest.name,
			"description": quest.description,   # Now revealed even if was "???"
		})
	return result

#func _process(delta: float) -> void:
	#print(get_active_quests())
