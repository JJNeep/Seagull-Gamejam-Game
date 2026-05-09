extends CanvasLayer

const MAX_VISIBLE = 3   # How many quests show in the corner at once

@onready var quest_list = $MarginContainer/VBox/QuestList

var delt

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

func _process(delta: float) -> void:
	delt = delta
	$MarginContainer2/ProgressBar.value = Global.chips
	$MarginContainer3/VBoxContainer/Label.text = str(Global.points)

func create_points_popup(amount,point_type:Global.point_types):
	var label = Label.new()
	label.text = "+{v1} {v2}".format({"v1": amount, "v2": Global.point_types.keys()[point_type]})
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	$MarginContainer3/VBoxContainer/PointsList.add_child(label)
	var tween = get_tree().create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)
