extends Node

## 冒烟测试（场景模式）：3D 风格棋盘（透视形变视图）
## ① 主场景在 3D 关卡下：棋盘搬进 SubViewport、生成形变显示层、关闭直连输入
## ② 形变矩阵投影/反投影一致（触摸能落回同一格）
## ③ 端到端：模拟触摸一次真实交换 → 消除成功（说明形变下的输入可用）
## 运行：godot --headless --path . tests/smoke_view3d.tscn

var _main: Control = null
var _frame := 0
var _failed := false
var _score_before := 0
var _move: Array[Vector2i] = []


func _ready() -> void:
	GameState.current_level = 11  # 浮空花岛（3D 关卡）
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30:
		_check_setup()
	elif _frame == 60:
		_check_projection_roundtrip()
		_send_touches()
	elif _frame == 160:
		_check_swap_result()
		get_tree().quit(1 if _failed else 0)


func _check_setup() -> void:
	var view = _main._view3d
	var board = _main._board
	var ok_view: bool = view != null and view is BoardView3D
	var ok_sub: bool = ok_view and board.get_parent() is SubViewport
	var warp := _main.get_node_or_null("BoardWarp") as TextureRect
	var ok_warp: bool = warp != null and warp.material is ShaderMaterial
	var ok_input: bool = ok_view and not board.is_processing_unhandled_input()
	var ok: bool = ok_view and ok_sub and ok_warp and ok_input
	print("PASS: 3D 视图装配（SubViewport + 形变层 + 输入接管）" if ok
		else "FAIL: 装配异常 view=%s sub=%s warp=%s input=%s" % [ok_view, ok_sub, ok_warp, ok_input])
	_assert(ok)


func _check_projection_roundtrip() -> void:
	var view = _main._view3d
	var board = _main._board
	var ok := true
	for cell in [Vector2i(0, 0), Vector2i(3, 5), Vector2i(6, 10)]:
		var pos: Vector2 = board.cell_to_world(cell)
		var back: Vector2 = view.unproject(view.project(pos))
		if back.distance_to(pos) > 0.5:
			ok = false
	print("PASS: 形变投影往返一致（触摸落点准确）" if ok else "FAIL: 投影往返偏差过大")
	_assert(ok)


func _send_touches() -> void:
	var board = _main._board
	var view = _main._view3d
	_move = MatchLogic.find_any_move(board._snapshot(), 7, 11)
	if _move.size() != 2:
		print("FAIL: 找不到可行步")
		_assert(false)
		return
	_score_before = board._score
	var screen_a: Vector2 = view.project(board.cell_to_world(_move[0]))
	var screen_b: Vector2 = view.project(board.cell_to_world(_move[1]))
	view.handle_touch(screen_a, true, false, false)
	view.handle_touch(screen_a, false, false, true)
	view.handle_touch(screen_b, true, false, false)
	view.handle_touch(screen_b, false, false, true)
	print("PASS: 已通过形变视图注入两次触摸（%s → %s）" % [str(_move[0]), str(_move[1])])


func _check_swap_result() -> void:
	var board = _main._board
	var gained: int = board._score - _score_before
	var ok: bool = gained > 0
	print("PASS: 形变棋盘上交换并消除成功（+%d 分）" % gained if ok
		else "FAIL: 触摸未生效（得分未变）")
	_assert(ok)


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")
