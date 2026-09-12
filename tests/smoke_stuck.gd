extends Node

## 冒烟测试（场景模式）：死局自救（棋盘无可消内容时自动重排）
## ① 构造死局 → _check_deadlock → 重排后有解、无初始消除、无空洞
## ② 特殊花在重排中保留（不被清掉、花色不变）
## ③ 出现「无可消除，重新排列！」提示浮字
## ④ 无效交换路径也能触发自救（玩家乱点也能出来）
## 运行：godot --headless --path . tests/smoke_stuck.tscn

var _board: Node2D = null
var _frame := 0
var _failed := false
var _specials: Dictionary = {}


func _ready() -> void:
	GameState.current_level = 3  # 雪块关（带障碍）
	_board = load("res://scripts/board.gd").new()
	add_child(_board)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 20:
		_make_dead_board()
	elif _frame == 40:
		_check_after_auto_reshuffle()
	elif _frame == 60:
		_make_dead_board()
		_trigger_invalid_swap()
	elif _frame == 130:
		_check_after_invalid_swap()
		get_tree().quit(1 if _failed else 0)


## 把可玩格涂成 2×2 同色方块图案：既无三连、也无任何能成立三连的交换
func _make_dead_board() -> void:
	for x in range(7):
		for y in range(11):
			var tile: Tile = _board._tiles[x][y]
			if tile == null:
				continue
			tile.set_special(Tile.Special.NONE)
			tile.set_flower(((x / 2) + 3 * (y / 2)) % 6)
	# 放两个特殊花，验证重排会保留它们
	_board._tiles[0][0].set_special(Tile.Special.LINE_H)
	_board._tiles[1][0].set_special(Tile.Special.BOMB)
	_specials = {
		Vector2i(0, 0): _board._tiles[0][0].flower_type,
		Vector2i(1, 0): _board._tiles[1][0].flower_type,
	}
	var frozen: bool = not MatchLogic.has_possible_move(_board._snapshot(), 7, 11)
	print("PASS: 已构造死局（无可消内容）" if frozen else "FAIL: 构造的死局居然有解")
	_assert(frozen)
	_check_no_initial_match()


func _check_after_auto_reshuffle() -> void:
	_board._check_deadlock()  # 应触发 _reshuffle()
	_check_no_initial_match()
	var movable: bool = MatchLogic.has_possible_move(_board._snapshot(), 7, 11)
	print("PASS: 死局自动重排后有可行步" if movable else "FAIL: 重排后仍无解")
	_assert(movable)
	var kept := true
	for c in _specials.keys():
		var tile: Tile = _board._tiles[c.x][c.y]
		if tile == null or tile.special == Tile.Special.NONE:
			kept = false
	print("PASS: 重排保留了特殊花" if kept else "FAIL: 特殊花被重排清掉")
	_assert(kept)
	var type_kept := true
	for c in _specials.keys():
		if _board._tiles[c.x][c.y].flower_type != int(_specials[c]):
			type_kept = false
	print("PASS: 特殊花花色不变" if type_kept else "FAIL: 特殊花花色被改")
	_assert(type_kept)
	var has_text := false
	for child in _board.get_children():
		if child is Label and String(child.text).contains("重新排列"):
			has_text = true
	print("PASS: 出现重排提示浮字" if has_text else "FAIL: 缺少重排提示")
	_assert(has_text)
	_check_integrity()


## 模拟玩家点一次无效交换：无效分支里也应检查死局并自救
func _trigger_invalid_swap() -> void:
	for y in range(11):
		for x in range(6):
			var a: Tile = _board._tiles[x][y]
			var b: Tile = _board._tiles[x + 1][y]
			if a == null or b == null:
				continue
			var test: Array[int] = _board._snapshot()
			MatchLogic.swap_cells(test, 7, Vector2i(x, y), Vector2i(x + 1, y))
			if MatchLogic.find_matches(test, 7, 11).is_empty():
				_board._try_swap(a, b)
				print("PASS: 触发一次无效交换 (%d,%d)↔(%d,%d)" % [x, y, x + 1, y])
				return
	print("FAIL: 找不到无效交换样本")
	_assert(false)


func _check_after_invalid_swap() -> void:
	var movable: bool = MatchLogic.has_possible_move(_board._snapshot(), 7, 11)
	print("PASS: 无效交换触发自救（重排后已有解）" if movable else "FAIL: 无效交换后仍是死局")
	_assert(movable)
	_check_no_initial_match()
	_check_integrity()


func _check_no_initial_match() -> void:
	var empty: bool = MatchLogic.find_matches(_board._snapshot(), 7, 11).is_empty()
	print("PASS: 棋盘无初始消除" if empty else "FAIL: 棋盘存在初始消除")
	_assert(empty)


## 网格完整性：障碍格无棋子、可玩格有棋子
func _check_integrity() -> void:
	var bad := 0
	for x in range(7):
		for y in range(11):
			var is_block: bool = _board._blocks.has(Vector2i(x, y))
			var has_tile: bool = _board._tiles[x][y] != null
			if has_tile == is_block:
				bad += 1
	print("PASS: 网格完整（障碍格空、可玩格满）" if bad == 0 else "FAIL: 网格异常 %d 处" % bad)
	_assert(bad == 0)


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")
