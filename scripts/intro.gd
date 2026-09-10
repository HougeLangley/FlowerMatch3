extends Control

## 开场：播放宣传短片，点击任意处跳过，结束/跳过后进入游戏

const GAME_SCENE := "res://scenes/level_select.tscn"

var _entered := false

@onready var _video: VideoStreamPlayer = %Video


func _ready() -> void:
	_video.finished.connect(_enter_game)


func _input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventMouseButton and event.pressed
			and event.button_index == MOUSE_BUTTON_LEFT) \
		or (event is InputEventScreenTouch and event.pressed)
	if tapped:
		_enter_game()


func _enter_game() -> void:
	if _entered:
		return
	_entered = true
	_video.stop()
	get_tree().change_scene_to_file(GAME_SCENE)
