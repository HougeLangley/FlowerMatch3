extends Node

## 冒烟测试（场景模式）：**逐关闭环测试**
## 对每一关：① 形状校验（虚空格无棋子/无精灵，可玩格有棋子）
##           ② 重力后网格完整（无空洞）
##           ③ 存在可行步
##           ④ 模拟一次真实交换并完成结算（得分 > 0）
## 运行：godot --headless --path . tests/smoke_all_levels.tscn

var _level := 0
var _board: Node2D = null
var _phase := 0
var _frame := 0
var _failed := false
var _score_before := 0


func _process(_delta: float) -> void:
	_frame += 1
	match _phase:
		0:
			if _frame < 5:
				return
			_level += 1
			if _level > GameState.LEVELS.size():
				_finish()
				return
			GameState.current_level = _level
			if _board != null:
				_board.queue_free()
			_board = load("res://scripts/board.gd").new()
			add_child(_board)
			_phase = 1
			_frame = 0
		1:
			if _frame >= 20:
				_check_shape()
				_board._apply_gravity()
				_phase = 2
				_frame = 0
		2:
			if _frame >= 20:
				_check_integrity()
				_phase = 3
				_frame = 0
		3:
			if _frame >= 5:
				_do_move()
				_phase = 4
				_frame = 0
		4:
			if _frame >= 30 and not _board._busy:
				_check_move_result()
				_phase = 0
				_frame = 0


func _check_shape() -> void:
	var mask: Array = GameState.shape_of(_level)
	var void_cells := 0
	var playable := 0
	var bad := 0
	for y in range(11):
		var row := String(mask[y])
		for x in range(7):
			var in_shape: bool = x < row.length() and row[x] == "#"
			var tile: Tile = _board._tiles[x][y]
			var block: bool = _board._blocks.has(Vector2i(x, y))
			var is_void: bool = block and int(_board._blocks[Vector2i(x, y)]) == -2
			if in_shape:
				playable += 1
				if tile == null and not block:
					bad += 1
			else:
				void_cells += 1
				if tile != null or not is_void:
					bad += 1
			# 虚空格不得有障碍精灵
			if is_void and _board._block_sprites.has(Vector2i(x, y)):
				bad += 1
	var ok: bool = bad == 0 and playable >= 30
	print("PASS: L%d %s 形状（可玩 %d 格 / 虚空 %d 格）" % [_level, GameState.level_name(_level), playable, void_cells] if ok
		else "FAIL: L%d 形状异常（可玩 %d 虚空 %d 异常 %d）" % [_level, playable, void_cells, bad])
	_assert(ok)


func _check_integrity() -> void:
	var holes := 0
	for x in range(7):
		for y in range(11):
			if not _board._blocks.has(Vector2i(x, y)) and _board._tiles[x][y] == null:
				holes += 1
	var movable: bool = MatchLogic.has_possible_move(_board._snapshot(), 7, 11)
	var ok: bool = holes == 0 and movable
	print("PASS: L%d 重力后无空洞且有可行步" % _level if ok
		else "FAIL: L%d 空洞 %d / 可行步 %s" % [_level, holes, str(movable)])
	_assert(ok)


func _do_move() -> void:
	_score_before = _board._score
	var mv := MatchLogic.find_any_move(_board._snapshot(), 7, 11)
	if mv.is_empty():
		print("FAIL: L%d 找不到可行步" % _level)
		_assert(false)
		return
	var a: Tile = _board._tiles[mv[0].x][mv[0].y]
	var b: Tile = _board._tiles[mv[1].x][mv[1].y]
	if a == null or b == null:
		print("FAIL: L%d 可行步棋子为空" % _level)
		_assert(false)
		return
	_board._try_swap(a, b)


func _check_move_result() -> void:
	var holes := 0
	for x in range(7):
		for y in range(11):
			if not _board._blocks.has(Vector2i(x, y)) and _board._tiles[x][y] == null:
				holes += 1
	var gained: int = _board._score - _score_before
	var ok: bool = gained > 0 and holes == 0
	print("PASS: L%d 消除成功（+%d 分，无空洞）" % [_level, gained] if ok
		else "FAIL: L%d 消除异常（+%d 分，空洞 %d）" % [_level, gained, holes])
	_assert(ok)


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")


func _finish() -> void:
	print("=== 逐关闭环测试完成：%d 关，%s ===" % [GameState.LEVELS.size(), "全部通过" if not _failed else "存在失败"])
	get_tree().quit(1 if _failed else 0)
