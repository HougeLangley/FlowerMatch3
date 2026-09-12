extends Node

## 冒烟测试（场景模式）：闲置动效（每种花不同律动）
## 1) 全部棋子启动闲置动效
## 2) 各类花按各自通道运动（玫瑰旋转 / 樱花浮摆 / 百合呼吸）
## 3) pulse / pop 不与闲置动效冲突
## 运行：godot --headless --path . tests/smoke_idle.tscn

var _board: Node2D = null
var _frame := 0
var _failed := false


func _ready() -> void:
	GameState.current_level = 1
	_board = load("res://scripts/board.gd").new()
	add_child(_board)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 20:
		_check_all_idle()
	elif _frame == 100:
		_check_per_type_motion()
	elif _frame == 130:
		_check_pulse_pop()
		get_tree().quit(1 if _failed else 0)


func _check_all_idle() -> void:
	var ok := true
	for x in range(7):
		for y in range(11):
			var t: Tile = _board._tiles[x][y]
			if t == null:
				continue
			if t._idle == null or not t._idle.is_valid():
				ok = false
	print("PASS: 全部棋子启动闲置动效" if ok else "FAIL: 存在未启动闲置动效的棋子")
	_assert(ok)


func _check_per_type_motion() -> void:
	var rose := false
	var sakura := false
	var lily := false
	for x in range(7):
		for y in range(11):
			var t: Tile = _board._tiles[x][y]
			if t == null:
				continue
			match t.flower_type:
				0:
					if absf(t._sprite.rotation) > 0.001:
						rose = true
				2:
					if absf(t._sprite.position.y) > 0.5:
						sakura = true
				5:
					if absf(t._sprite.scale.x - t._base_scale.x) > 0.001:
						lily = true
	var ok: bool = rose and sakura and lily
	print("PASS: 玫瑰旋转/樱花浮摆/百合呼吸均在动" if ok
		else "FAIL: 部分花未动 rose=%s sakura=%s lily=%s" % [rose, sakura, lily])
	_assert(ok)


func _check_pulse_pop() -> void:
	var t: Tile = _board._tiles[3][5]
	if t == null:
		print("FAIL: 样本棋子缺失")
		_assert(false)
		return
	t.pulse()
	var ok: bool = t._idle != null and t._idle.is_valid()
	print("PASS: pulse 后闲置动效保持有效" if ok else "FAIL: pulse 破坏了闲置动效")
	_assert(ok)
	t.pop()
	print("PASS: pop 执行无异常")


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")
