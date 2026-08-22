extends Node

@onready var quest_complete = preload("res://quest_complete.tscn")

enum QuestType { GIVEN, HIDDEN }
enum QuestStatus { LOCKED, ACTIVE, COMPLETED }

var all_quests: Dictionary = {
		"knock_building": {
		"name": "I Didn't touch it",
		"description": "Knock the falling building off the edge",
		"type": QuestType.HIDDEN,        # Must be given before it can complete
		"checker": "building",
		"requirement": func(node): return node.position.y < -1,
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
		"requirement": func(node): var nuke_pos = get_tree().get_first_node_in_group("Nuke_centre").global_position; return node.large and node._edit_started and not node._impact_triggered and (nuke_pos*Vector3(1, 0, 1)).distance_squared_to(node.position*Vector3(1, 0, 1)) < 64 and node.position.y < nuke_pos.y + 13,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	},
		"ocean_poo": {
		"name": "It was the fish",
		"description": "poo in the ocean and meet a new friend",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "poo",
		"requirement": func(node): return node.position.y < 0,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	},
		"dance": {
		"name": "Party Time!",
		"description": "Dance at the party",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "world",
		"requirement": func(node): return node.time_at_party >= 10.0 and node.player_pos.x > -28 and node.player_pos.x < -11 and node.player_pos.y > 12 and node.player_pos.y < 41 and node.player_pos.z > -8 and node.player_pos.z < 10,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	},
		"jacks": {
		"name": "Expose Jacks Food",
		"description": "Expose the secret behind jacks food",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "world",
		"requirement": func(node): return node.player_pos.x > 5 and node.player_pos.x < 13 and node.player_pos.y > 13 and node.player_pos.y < 18.5 and node.player_pos.z > -29 and node.player_pos.z < -21,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	},
		"lighthouse": {
		"name": "Let There be light",
		"description": "Turn on the lighthouse",
		"type": QuestType.GIVEN,        # Must be given before it can complete
		"checker": "world",
		"requirement": func(node): return node.player_pos.distance_to(Vector3(69.8213, 2.912558, 29.58148)) < 5,
		"status": QuestStatus.ACTIVE    # GIVEN quests start locked
	}
}

# Only quests the player KNOWS about (given + discovered hidden ones)
var known_quests: Array = []
var completed_quests: Array = []

# Play the popup once at startup, invisible and silent, so its font atlas (179/81/45px)
# is rasterized now instead of hitching on the first real quest completion.
# It removes itself via the queue_free method track at the end of the "main" animation.
func _ready() -> void:
	var warm = quest_complete.instantiate()
	warm.modulate.a = 0.0
	warm.get_node("ColorRect").mouse_filter = Control.MOUSE_FILTER_IGNORE
	warm.get_node("AudioStreamPlayer").volume_db = -80.0
	add_child(warm)

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
