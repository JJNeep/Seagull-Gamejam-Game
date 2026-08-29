extends CanvasLayer

var selected_quest_id: String = ""

@onready var active_list    = $Panel/HBox/LeftPanel/ScrollContainer/ActiveList
@onready var completed_list = $Panel/HBox/LeftPanel/ScrollContainer2/CompletedList
@onready var detail_name    = $Panel/HBox/RightPanel/VBox/QuestName
@onready var detail_desc    = $Panel/HBox/RightPanel/VBox/QuestDescription
@onready var detail_status  = $Panel/HBox/RightPanel/VBox/QuestStatus

func _ready() -> void:
	hide()
	QuestManager.quest_received.connect(func(_id): if visible: refresh())
	QuestManager.quest_completed.connect(func(_id): if visible: refresh())
	QuestManager.hidden_quest_discovered.connect(func(_id): if visible: refresh())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_menu"):   # Bind this in Project > Input Map
		if visible:
			close_menu()
		else:
			open_menu()

func open_menu() -> void:
	show()
	refresh()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close_menu() -> void:
	hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func refresh() -> void:
	# Clear lists
	for child in active_list.get_children():
		child.queue_free()
	for child in completed_list.get_children():
		child.queue_free()

	# Populate active quests
	for quest_id in QuestManager.known_quests:
		var quest = QuestManager.all_quests[quest_id]
		if quest.status == QuestManager.QuestStatus.ACTIVE:
			active_list.add_child(make_entry(quest_id, quest, false))

	# Populate completed quests
	for quest_id in QuestManager.completed_quests:
		var quest = QuestManager.all_quests[quest_id]
		completed_list.add_child(make_entry(quest_id, quest, true))

	# Auto-select first active quest if nothing selected
	if selected_quest_id == "" and not QuestManager.known_quests.is_empty():
		show_detail(QuestManager.known_quests[0])

func make_entry(quest_id: String, quest: Dictionary, completed: bool) -> Button:
	var btn = Button.new()
	var prefix = "✓ " if completed else "▸ "
	btn.text = prefix + quest.name
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

	# Highlight selected
	if quest_id == selected_quest_id:
		btn.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	elif completed:
		btn.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))   # Green
	else:
		btn.add_theme_color_override("font_color", Color(1, 1, 1))

	btn.pressed.connect(func(): show_detail(quest_id))
	return btn

func show_detail(quest_id: String) -> void:
	selected_quest_id = quest_id
	var quest = QuestManager.all_quests[quest_id]

	detail_name.text = quest.name

	# Hidden quests show ??? until completed
	if quest.type == QuestManager.QuestType.HIDDEN and quest.status == QuestManager.QuestStatus.ACTIVE:
		detail_desc.text = "???"
	else:
		detail_desc.text = quest.description

	match quest.status:
		QuestManager.QuestStatus.ACTIVE:
			detail_status.text = "Status: In Progress"
			detail_status.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		QuestManager.QuestStatus.COMPLETED:
			detail_status.text = "Status: Completed ✓"
			detail_status.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))

	refresh()   # Re-render list to update highlight

func _on_close_button_pressed() -> void:
	close_menu()


func _on_button_pressed() -> void:
	close_menu()
