extends Area3D

@export var quest_id: String = ""          # Set this in the Inspector per NPC
@export var npc_yes_dialogue: String = "Excellent! Don't\nlet me down."
@export var npc_no_dialogue: String = "Then leave me!"

var is_gaining_quest = false
var cutscene_started = false               # Prevents cutscene() firing every frame

var first_quest = true

@onready var player: Player = get_parent().get_node("Player")

func _ready() -> void:
	$Camera3D.current = false
	$CanvasLayer.hide()

func _process(delta: float) -> void:
	if is_gaining_quest == false:
		cutscene_started = false           # Reset when not in cutscene
		if has_overlapping_bodies():
			if Input.is_action_just_pressed("select"):  # just_pressed so it fires once
				cutscene()
			$Label3D.transparency = lerpf($Label3D.transparency, 0.0, delta * 10)
		else:
			$Label3D.transparency = lerpf($Label3D.transparency, 1.0, delta * 10)
	else:
		$Label3D.transparency = lerpf($Label3D.transparency, 1.0, delta * 10)
		$Camera3D.position = lerp($Camera3D.position, Vector3(-7.805, 3.759, -6.014), delta * 10)
		$Camera3D.rotation.y = lerp_angle($Camera3D.rotation.y, -127.3, delta * 10)
		$CanvasLayer/Label.visible_ratio = move_toward($CanvasLayer/Label.visible_ratio, 1, delta)
		if $CanvasLayer/Label.visible_ratio == 1 and is_end_dialogue():
			await get_tree().create_timer(2).timeout
			end_cutscene()

func is_end_dialogue() -> bool:
	# Checks if we're on a closing line so we know when to end the cutscene
	return $CanvasLayer/Label.text == npc_no_dialogue or $CanvasLayer/Label.text == npc_yes_dialogue

func cutscene() -> void:
	if cutscene_started:
		return
	
	## Check if player already has an active given quest
	#var has_active = QuestManager.known_quests.any(func(id):
		#var q = QuestManager.all_quests[id]
		#return q.type == QuestManager.QuestType.GIVEN and q.status == QuestManager.QuestStatus.ACTIVE
	#)
	#
	#if has_active:
		## Different dialogue if player already has a quest
		#cutscene_started = true
		#is_gaining_quest = true
		#player.start_cutscene()
		#$Camera3D.current = true
		#$Camera3D.global_position = player.camera.global_position
		#$Camera3D.global_rotation = player.camera.global_rotation
		#Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		#$CanvasLayer/Label.text = "You already have a job!\nFinish that first."
		#$CanvasLayer/Label.visible_ratio = 0
		#$CanvasLayer.show()
		## No buttons, just auto close
		#await get_tree().create_timer(3).timeout
		#end_cutscene()
		#return
	
	# Pick a random locked quest
	var locked_quests = QuestManager.all_quests.keys().filter(func(id):
		var q = QuestManager.all_quests[id]
		return q.type == QuestManager.QuestType.GIVEN and q.status == QuestManager.QuestStatus.LOCKED
	)
	
	if locked_quests.is_empty():
		cutscene_started = true
		is_gaining_quest = true
		player.start_cutscene()
		$Camera3D.current = true
		$Camera3D.global_position = player.camera.global_position
		$Camera3D.global_rotation = player.camera.global_rotation
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		$CanvasLayer/Label.text = "I have nothing\nmore for you."
		$CanvasLayer/Label.visible_ratio = 0
		$CanvasLayer/Button.grab_focus()
		$CanvasLayer.show()
		await get_tree().create_timer(3).timeout
		end_cutscene()
		return
	
	if first_quest:
		first_quest = false
		quest_id = "steal_chip"
	else:
		# Store the chosen quest so the button can give it
		quest_id = locked_quests[randi() % locked_quests.size()]
	
	cutscene_started = true
	is_gaining_quest = true
	player.start_cutscene()
	$Camera3D.current = true
	$Camera3D.global_position = player.camera.global_position
	$Camera3D.global_rotation = player.camera.global_rotation
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	$CanvasLayer/Label.text = "Hello, have you\ncome for a quest?"
	$CanvasLayer/Label.visible_ratio = 0
	$CanvasLayer/Button.grab_focus()
	$CanvasLayer.show()
	$CanvasLayer/Button.show()
	$CanvasLayer/Button2.show()

func end_cutscene() -> void:
	is_gaining_quest = false
	player.end_cutscene()
	$Camera3D.current = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	$CanvasLayer/Button.release_focus()
	$CanvasLayer.hide()

func _on_button_2_pressed() -> void:
	$CanvasLayer/Button.release_focus()
	$CanvasLayer/Button.hide()
	$CanvasLayer/Button2.hide()
	$CanvasLayer/Label.text = npc_no_dialogue
	$CanvasLayer/Label.visible_ratio = 0

func _on_button_pressed() -> void:
	$CanvasLayer/Button.release_focus()
	$CanvasLayer/Button.hide()
	$CanvasLayer/Button2.hide()
	$CanvasLayer/Label.text = npc_yes_dialogue
	$CanvasLayer/Label.visible_ratio = 0
	if quest_id != "":
		QuestManager.give_quest(quest_id)
	else:
		push_warning("QuestGiver has no quest_id set in Inspector!")
