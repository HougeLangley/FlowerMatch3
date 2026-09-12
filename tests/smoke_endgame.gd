extends Node

## 冒烟测试（场景模式）：验证结算流程
## 1) 普通移动不提前结算
## 2) 打到三星线立即结算 + 星星逐颗点亮动画完成后全亮
## 3) 玩满步数 1★ 过关 + 仅一颗金星 + 升星提示
## 测试后会恢复 GameState 存档，不留副作用
## 运行：godot --headless --path . tests/smoke_endgame.tscn

const STAR_GOLD := preload("res://assets/star_gold.png")

var _main: Control = null
var _phase := 0
var _elapsed := 0.0
var _wait_until := 0.0
var _failed := false
var _snap_stars: Dictionary = {}
var _snap_best: Dictionary = {}
var _snap_unlocked := 1


func _ready() -> void:
	_snap_stars = GameState.stars.duplicate()
	_snap_best = GameState.best.duplicate()
	_snap_unlocked = GameState.unlocked
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


func _process(delta: float) -> void:
	_elapsed += delta
	if _phase == 0 and _elapsed >= 0.5:
		_phase = 1
		_check_no_early_end()
	elif _phase == 1 and _elapsed >= 1.0:
		_phase = 2
		_check_early_three_star_finish()
	elif _phase == 2 and _elapsed >= _wait_until:
		_phase = 3
		_check_three_star_revealed()
	elif _phase == 3:
		_phase = 4
		_start_playout_one_star_finish()
	elif _phase == 4 and _elapsed >= _wait_until:
		_phase = 5
		_check_one_star_revealed()


func _check_no_early_end() -> void:
	var overlay := _main.get_node("%ResultOverlay") as Control
	_main._on_move_made()  # 模拟一次普通移动（分数 0）
	var ok: bool = overlay != null and not overlay.visible and _main._moves_left == 19
	print("PASS: 普通移动不提前结算（步数 %d）" % _main._moves_left if ok
		else "FAIL: 提前结算或步数异常")
	_assert(ok)


func _check_early_three_star_finish() -> void:
	_main._score = GameState.star_thresholds(_main._target)[2]  # 拉到三星线
	_main._on_move_made()
	var overlay := _main.get_node("%ResultOverlay") as Control
	var ok: bool = overlay != null and overlay.visible
	print("PASS: 打到三星线立即结算" if ok else "FAIL: 未结算")
	_assert(ok)
	var detail := (_main.get_node("%DetailLabel") as Label).text
	var ok3: bool = not detail.contains("还差")
	print("PASS: 三星结算无升星提示" if ok3 else "FAIL: 三星仍有升星提示")
	_assert(ok3)
	# 等待逐颗点亮动画（0.35s 起，每颗 +0.26s，加余量）
	_wait_until = _elapsed + 1.6


func _check_three_star_revealed() -> void:
	var stars := _main.get_node("%StarsBox")
	var all_gold := stars != null and stars.get_child_count() == 3
	if all_gold:
		for i in range(stars.get_child_count()):
			var tr := stars.get_child(i) as TextureRect
			if tr == null or tr.texture != STAR_GOLD:
				all_gold = false
	print("PASS: 点亮动画结束后三星全亮" if all_gold else "FAIL: 星级点亮异常")
	_assert(all_gold)
	_main.queue_free()
	_main = null


## 阶段三：玩满步数、分数刚好达标 → 1 星过关 + 升星提示
func _start_playout_one_star_finish() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)
	# add_child 会同步执行 _ready，可直接操作状态
	_main._score = _main._target           # 刚好达标 → 1★
	_main._moves_left = 1                  # 最后一步
	_main._on_move_made()
	var overlay := _main.get_node("%ResultOverlay") as Control
	var ok: bool = overlay != null and overlay.visible
	print("PASS: 步数用尽后 1★ 过关" if ok else "FAIL: 未结算")
	_assert(ok)
	var detail := (_main.get_node("%DetailLabel") as Label).text
	var ok3: bool = detail.contains("升到 2 星")
	print("PASS: 提示升 2 星" if ok3 else "FAIL: 升星提示缺失")
	_assert(ok3)
	_wait_until = _elapsed + 1.2


func _check_one_star_revealed() -> void:
	var stars := _main.get_node("%StarsBox")
	var gold_count := 0
	for i in range(stars.get_child_count()):
		var tr := stars.get_child(i) as TextureRect
		if tr != null and tr.texture == STAR_GOLD:
			gold_count += 1
	var ok2: bool = gold_count == 1
	print("PASS: 仅一颗金星（%d）" % gold_count if ok2 else "FAIL: 金星数异常")
	_assert(ok2)
	_restore_and_quit()


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")


## 恢复存档快照，避免测试污染本地数据
func _restore_and_quit() -> void:
	GameState.stars = _snap_stars
	GameState.best = _snap_best
	GameState.unlocked = _snap_unlocked
	GameState.save_data()
	get_tree().quit(1 if _failed else 0)
