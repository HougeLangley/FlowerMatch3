extends Node

## 冒烟测试（场景模式）：关卡障碍系统
## 1) L2 藤蔓：障碍格无棋子；重力止步于障碍（墙行为）；重后无空洞
## 2) L3 雪块：相邻消除可破；破后格子恢复可填充
## 3) L5：5 花色 + 双障碍共存
## 运行：godot --headless --path . tests/smoke_levels.tscn

var _board: Node2D = null
var _frame := 0
var _failed := false


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10:
		GameState.current_level = 2
		_board = load("res://scripts/board.gd").new()
		add_child(_board)
	elif _frame == 40:
		_check_vines()
	elif _frame == 70:
		_check_wall_gravity()
	elif _frame == 110:
		_check_snow_break()
	elif _frame == 140:
		_free_board()
		GameState.current_level = 3
		_board = load("res://scripts/board.gd").new()
		add_child(_board)
	elif _frame == 170:
		_check_level3_snow()
	elif _frame == 200:
		_free_board()
		GameState.current_level = 5
		_board = load("res://scripts/board.gd").new()
		add_child(_board)
	elif _frame == 230:
		_check_level5()
	elif _frame == 260:
		get_tree().quit(1 if _failed else 0)


func _free_board() -> void:
	if _board != null:
		_board.queue_free()
		_board = null


func _check_vines() -> void:
	var cfg: Dictionary = GameState.LEVELS[1]
	var nulls := 0
	for x in range(7):
		for y in range(11):
			if _board._tiles[x][y] == null:
				nulls += 1
	var ok: bool = nulls == cfg["vines"].size()
	print("PASS: L2 藤蔓格无棋子（%d）" % nulls if ok else "FAIL: 藤蔓格异常 %d" % nulls)
	_assert(ok)
	# 触发重力：清空一处藤蔓上方棋子，验证它不会掉穿藤蔓
	var vine: Vector2i = Vector2i(cfg["vines"][0][0], cfg["vines"][0][1])
	if vine.y > 0 and _board._tiles[vine.x][vine.y - 1] != null:
		_board._tiles[vine.x][vine.y - 1] = null
		_board._apply_gravity()


func _check_wall_gravity() -> void:
	var cfg: Dictionary = GameState.LEVELS[1]
	var vine: Vector2i = Vector2i(cfg["vines"][0][0], cfg["vines"][0][1])
	var blocked_ok: bool = _board._tiles[vine.x][vine.y] == null
	var holes := 0
	for x in range(7):
		for y in range(11):
			var is_block: bool = _board._blocks.has(Vector2i(x, y))
			if _board._tiles[x][y] == null and not is_block:
				holes += 1
	var ok: bool = blocked_ok and holes == 0
	print("PASS: 重力止步于藤蔓，无空洞" if ok else "FAIL: 墙行为异常")
	_assert(ok)


func _check_snow_break() -> void:
	# 在 L2 上模拟雪块破坏（保持状态一致：障碍格先腾空棋子）
	var cell := Vector2i(2, 2)
	var old: Tile = _board._tiles[cell.x][cell.y]
	if old != null:
		old.queue_free()
	_board._tiles[cell.x][cell.y] = null
	_board._blocks[cell] = 1
	_board._add_block_sprites()
	var before: int = _board._blocks.size()
	_board._damage_adjacent_blocks({Vector2i(2, 1): true})  # 相邻消除
	var ok: bool = not _board._blocks.has(cell) and _board._blocks.size() == before - 1
	print("PASS: 相邻消除破雪块" if ok else "FAIL: 雪块未破")
	_assert(ok)
	# 破障后该格可被重力填充
	_board._apply_gravity()
	var ok2: bool = _board._tiles[cell.x][cell.y] != null
	print("PASS: 破障后可填充" if ok2 else "FAIL: 破障格未填充")
	_assert(ok2)


func _check_level3_snow() -> void:
	var cfg: Dictionary = GameState.LEVELS[2]
	var ok: bool = _board._blocks.size() == cfg["snow"].size()
	# 雪块初始 HP 均为 1
	var hp_ok := true
	for c in _board._blocks.keys():
		if int(_board._blocks[c]) != 1:
			hp_ok = false
	print("PASS: L3 雪块数量与 HP 正确" if ok and hp_ok else "FAIL: L3 雪块异常")
	_assert(ok and hp_ok)


func _check_level5() -> void:
	var flowers_ok: bool = _board._flower_types == 5
	var blocks_ok: bool = _board._blocks.size() == 9  # 2 藤蔓 + 7 雪块
	print("PASS: L5 五色 + 双障碍共存" if flowers_ok and blocks_ok
		else "FAIL: L5 配置异常 flowers=%d blocks=%d" % [_board._flower_types, _board._blocks.size()])
	_assert(flowers_ok and blocks_ok)


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")
