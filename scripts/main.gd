extends Control

## 主界面：关卡状态（步数/目标/星级/最高分）、结算弹窗、重开/返回选关

const STAR_GOLD := preload("res://assets/star_gold.png")
const STAR_GRAY := preload("res://assets/star_gray.png")

@onready var _score_label: Label = %ScoreLabel
@onready var _info_label: Label = %InfoLabel
@onready var _debug_label: Label = %DebugLabel
@onready var _board: Board = %Board
@onready var _overlay: Control = %ResultOverlay
@onready var _result_label: Label = %ResultLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _stars_box: HBoxContainer = %StarsBox
@onready var _restart_button: Button = %RestartButton
@onready var _levels_button: Button = %LevelsButton

var _level := 1
var _target := 0
var _score := 0
var _moves_left := 0
var _over := false


func _ready() -> void:
	_level = GameState.current_level
	var cfg: Dictionary = GameState.LEVELS[_level - 1]
	_target = cfg["target"]
	_moves_left = cfg["moves"]
	_board.score_changed.connect(_on_score_changed)
	_board.move_made.connect(_on_move_made)
	_board.input_received.connect(_on_input_received)
	_board.debug_state.connect(_on_debug_state)
	_restart_button.pressed.connect(_on_restart_pressed)
	_levels_button.pressed.connect(_on_levels_pressed)
	_update_ui()


func _on_score_changed(new_score: int) -> void:
	_score = new_score
	_update_ui()


func _on_move_made() -> void:
	_moves_left -= 1
	_update_ui()
	if _score >= _target:
		_end_game(true)
	elif _moves_left <= 0:
		_end_game(false)


func _end_game(won: bool) -> void:
	if _over:
		return
	_over = true
	var rating := GameState.record_result(_level, _score)
	_result_label.text = "过关啦！" if won else "还差一点～"
	_detail_label.text = "得分 %d ／ 目标 %d ｜ 最高 %d" % [
		_score, _target, int(GameState.best.get(_level, 0))]
	var shown := rating if won else 0
	for i in range(_stars_box.get_child_count()):
		var tr := _stars_box.get_child(i) as TextureRect
		if tr != null:
			tr.texture = STAR_GOLD if i < shown else STAR_GRAY
	_overlay.visible = true


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_levels_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")


func _update_ui() -> void:
	_score_label.text = "分数: %d" % _score
	_info_label.text = "第%d关 ｜ 步数: %d ｜ 目标: %d" % [_level, _moves_left, _target]


func _on_debug_state(text: String) -> void:
	_debug_label.text = text


func _on_input_received(_pos: Vector2, _cell: Vector2i) -> void:
	pass  # 保留信号用于调试扩展
