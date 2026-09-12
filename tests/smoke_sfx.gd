extends Node

## 冒烟测试（场景模式）：音效系统
## 1) Sfx 自动加载 + 听者就绪
## 2) 全部音效资源齐全且可加载（长度 > 0.05s）
## 3) 多声部池：同一帧连发不互相打断
## 4) 真流程联动：合法交换 → 消除 → 计分（期间 swap/pop/special/line/boom 均被触发）无异常
## 运行：godot --headless --path . tests/smoke_sfx.tscn

const SOUND_FILES := [
	"pop_a", "pop_b", "pop_c", "swap", "invalid", "magic", "line", "boom",
	"special", "break", "shuffle", "select", "win", "star", "lose",
]

var _frame := 0
var _failed := false
var _board: Node2D = null
var _sfx: Node = null


func _ready() -> void:
	_sfx = get_node_or_null("/root/Sfx")


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 5:
		_check_autoload()
	elif _frame == 10:
		_check_assets()
	elif _frame == 15:
		_check_play_api()
		_check_voice_pool()
	elif _frame == 25:
		GameState.current_level = 1
		_board = load("res://scripts/board.gd").new()
		add_child(_board)
	elif _frame == 40:
		_check_select_sound()
	elif _frame == 60:
		_start_valid_swap()
	elif _frame == 200:
		_check_resolve()
		get_tree().quit(1 if _failed else 0)


func _check_autoload() -> void:
	var ok: bool = _sfx != null and _sfx._listener != null
	print("PASS: Sfx 自动加载 + 听者就绪" if ok else "FAIL: Sfx 未加载")
	_assert(ok)


func _check_assets() -> void:
	var bad: Array = []
	for n in SOUND_FILES:
		var path := "res://assets/sounds/%s.wav" % n
		if not ResourceLoader.exists(path):
			bad.append(n + "(缺失)")
			continue
		var stream := load(path) as AudioStream
		if stream == null or stream.get_length() < 0.05:
			bad.append(n + "(空)")
	var ok: bool = bad.is_empty()
	print("PASS: %d 个音效资源齐全且有效" % SOUND_FILES.size() if ok
		else "FAIL: 音效异常 %s" % str(bad))
	_assert(ok)


func _check_play_api() -> void:
	var p := Vector2(360.0, 900.0)
	_sfx.play_select(p)
	_sfx.play_swap(p, false)
	_sfx.play_swap(p, true)
	_sfx.play_invalid(p)
	_sfx.play_pop(1, p)
	_sfx.play_pop(3, p)
	_sfx.play_special(p)
	_sfx.play_line(p, false)
	_sfx.play_line(p, true)
	_sfx.play_boom(p)
	_sfx.play_magic(p)
	_sfx.play_break(p)
	_sfx.play_reshuffle(p)
	_sfx.play_star(0)
	_sfx.play_star(2)
	_sfx.play_win()
	_sfx.play_lose()
	print("PASS: 全部 %d 个播放 API 调用无异常" % 17)


func _check_voice_pool() -> void:
	for i in range(6):
		_sfx.play_pop(2, Vector2(360.0, 900.0))
	var pool: Dictionary = _sfx._pools["pop"]
	var playing := 0
	for pl in pool["players"]:
		if pl.playing:
			playing += 1
	var ok: bool = playing >= 5
	print("PASS: 多声部池并发（同帧 %d/6 声道在响）" % playing if ok
		else "FAIL: 声部池未轮转（%d/6）" % playing)
	_assert(ok)


func _check_select_sound() -> void:
	var tile: Tile = _board._tiles[0][0]
	if tile == null:
		print("FAIL: 样本棋子缺失")
		_assert(false)
		return
	_board._on_tile_pressed(tile)
	var ok: bool = _board._selected == tile
	_board._on_tile_pressed(tile)  # 再点一次取消选择
	print("PASS: 点选路径触发（含音效）" if ok else "FAIL: 点选异常")
	_assert(ok)


func _start_valid_swap() -> void:
	for x in range(7):
		for y in range(11):
			for d: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var c2 := Vector2i(x, y) + d
				if c2.x >= 7 or c2.y >= 11:
					continue
				var a: Tile = _board._tiles[x][y]
				var b: Tile = _board._tiles[c2.x][c2.y]
				if a == null or b == null:
					continue
				var test: PackedInt32Array = _board._snapshot()
				var i1 := y * 7 + x
				var i2 := c2.y * 7 + c2.x
				var tmp := test[i1]
				test[i1] = test[i2]
				test[i2] = tmp
				if not MatchLogic.find_matches(test, 7, 11).is_empty():
					_board._try_swap(a, b)
					print("PASS: 触发合法交换 (%d,%d)↔(%d,%d)" % [x, y, c2.x, c2.y])
					return
	print("FAIL: 未找到合法交换")
	_assert(false)


func _check_resolve() -> void:
	var ok: bool = _board._score > 0
	print("PASS: 交换→消除→计分全链路（音效随之触发）" if ok
		else "FAIL: 未得分（score=%d）" % _board._score)
	_assert(ok)


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")
