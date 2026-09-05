extends Control

var text = ["Use WASD to move
[T to quit tutorial at any time]",
"Use Space to jump",
"Press Space to toggle flight while in the air",
"Hold Shift to flap while flying and get more lift",
"You can walk through doors to go into buildings
[Press Enter to continue]","Talk to the mafia leader on the beach to
gain quests or find secret achievements by trying things out
[talk to the mafia leader to continue]","",
"Press backspace to look at current quests","Humans come to the beach and hold out chips.
Swoop at them to gain chips","When you have a chip in your bar,
you can drop a package with F","You can do a large poo when you have a full chip bar
[Press Enter to continue]","Press E to squawk","good luck!
[T to end tutorial]"]

var how_far = 0

var poi : Label3D

@onready var player : Player = get_tree().get_first_node_in_group("player")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Label.visible = true
	$Label.text = text[how_far]

var chips

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if how_far == 0 and player.velocity > Vector3.ZERO:
		next_page()
	elif how_far == 1 and player.velocity.y > 0:
		next_page()
	elif how_far == 2 and player.is_gliding:
		next_page()
	elif how_far == 3 and player.is_flapping:
		next_page()
	elif how_far == 5 and get_tree().get_first_node_in_group("quest_guy").cutscene_started:
		next_page()
	elif how_far == 6 and get_tree().get_first_node_in_group("quest_guy").cutscene_started == false:
		next_page()
	elif how_far == 8 and Global.chips > 0:
		next_page()
	elif how_far == 9 and Global.chips < chips:
		next_page()
	#print(Global.chips)
	chips = Global.chips

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("Tutorial"):
		queue_free()
	if (how_far == 4 or how_far == 10) and event.is_action_pressed("next"):
		next_page()
	if how_far == 7 and event.is_action_pressed("quest_menu"):
		next_page()
	if how_far == 11 and event.is_action_pressed("squawk"):
		next_page()

func next_page() -> void:
	how_far += 1
	if how_far == 5:
		poi = Label3D.new()
		poi.global_position = Vector3(26.5,3.5,-23.5)
		poi.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		poi.no_depth_test = true
		poi.text = "📍"
		poi.font_size = 1070
		poi.outline_size = 0
		get_parent().add_child(poi)
	elif how_far == 6:
		poi.queue_free()
	elif how_far == 10:
		QuestManager.give_quest("megapoo")
	$Label.text = text[how_far]
