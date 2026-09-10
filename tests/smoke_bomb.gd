extends Node

## 集成冒烟：构造 L 形棋盘 → 驱动消除循环 → 断言交叉点生成爆炸花
## 运行：godot --headless --path . tests/smoke_bomb.tscn

var _board: Node2D = null
var _frame := 0


func _ready() -> void:
	_board = load("res://scripts/board.gd").new()
	add_child(_board)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 10 and _board != null:
		_craft_and_resolve()
	if _frame == 40:
		_verify_bomb()    # 消除后、可能的重排前检查爆炸花
	if _frame == 110:
		_verify_final()   # 尘埃落定后检查网格完整性与得分


func _craft_and_resolve() -> void:
	# 基础网格（无三连）：g = (x + 2y) % 6
	for x in range(7):
		for y in range(11):
			_board._tiles[x][y].set_flower((x + y * 2) % 6)
	# 构造 L 形玫瑰：行0 (0,0)(1,0)(2,0) + 列2 (2,0)(2,1)(2,2)
	_board._tiles[1][0].set_flower(0)
	_board._tiles[2][0].set_flower(0)
	_board._tiles[2][1].set_flower(0)
	_board._tiles[2][2].set_flower(0)
	_board._resolve_matches()


func _verify_bomb() -> void:
	var found_bomb := false
	for x in range(7):
		for y in range(11):
			var t: Tile = _board._tiles[x][y]
			if t != null and t.special == Tile.Special.BOMB:
				found_bomb = true
	print("PASS: bomb created from L intersection" if found_bomb else "FAIL: no bomb on board")
	_assert(found_bomb, "bomb")


func _verify_final() -> void:
	var nulls := 0
	for x in range(7):
		for y in range(11):
			if _board._tiles[x][y] == null:
				nulls += 1
	var ok2: bool = _board._score > 0
	print("PASS: score > 0 (%d)" % _board._score if ok2 else "FAIL: score 0")
	var ok3: bool = nulls == 0
	print("PASS: grid fully registered (no null cells)" if ok3 else "FAIL: %d null cells" % nulls)
	_assert(ok2, "score")
	_assert(ok3, "nulls")
	get_tree().quit(1 if _failed else 0)


var _failed := false

func _assert(cond: bool, label: String) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED: ", label)
