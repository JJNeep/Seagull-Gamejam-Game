extends CanvasLayer

const MAX_VISIBLE = 3   # How many quests show in the corner at once

@onready var quest_list = $MarginContainer/VBox/QuestList

func _ready() -> void:
	QuestManager.quest_received.connect(refresh)
	QuestManager.quest_completed.connect(refresh)
	QuestManager.hidden_quest_discovered.connect(refresh)
	refresh()

func refresh(_id: String = "") -> void:
	# Clear existing entries
	for child in quest_list.get_children():
		child.queue_free()

	var active = QuestManager.known_quests.filter(func(id):
		return QuestManager.all_quests[id].status == QuestManager.QuestStatus.ACTIVE
	)

	# Show up to MAX_VISIBLE quests
	for i in min(active.size(), MAX_VISIBLE):
		var quest = QuestManager.all_quests[active[i]]
		var label = Label.new()
		label.text = "▸ " + quest.name
		label.add_theme_color_override("font_color", Color(1, 0.85, 0.4))   # Gold
		quest_list.add_child(label)

	# Show overflow count if needed
	if active.size() > MAX_VISIBLE:
		var overflow = Label.new()
		overflow.text = "  +" + str(active.size() - MAX_VISIBLE) + " more..."
		overflow.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		quest_list.add_child(overflow)
