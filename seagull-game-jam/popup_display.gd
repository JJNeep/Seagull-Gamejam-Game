extends Label3D

enum point_types {
	Points, Chips
}

var amount = 0
var point_type : point_types
var size = 32
var life_length = 2

@onready var life : SceneTreeTimer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	text = "+{v1} {v2}".format({"v1": amount, "v2": point_types.keys()[point_type]})
	life = get_tree().create_timer(1+life_length)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if life.time_left < 1:
		transparency = lerpf(transparency,1,delta*10)
		if transparency >= 0.99:  # ← Close enough
			queue_free()
