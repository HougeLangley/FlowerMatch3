extends SceneTree

## 无头单元测试：godot --headless --path . -s tests/run_tests.gd
## 退出码 = 失败用例数

const ML := preload("res://scripts/match_logic.gd")
const GS := preload("res://scripts/game_state.gd")

var _failures := 0


func _init() -> void:
	print("== FlowerMatch3 logic tests ==")
	_test_make_grid_shape()
	_test_make_grid_no_initial_matches()
	_test_find_matches()
	_test_is_adjacent()
	_test_has_possible_move_true()
	_test_has_possible_move_obstacles()
	_test_has_possible_move_magic()
	_test_reshuffle_keeps_specials()
	_test_swap_cells()
	_test_match_groups()
	_test_magic_excluded()
	_test_intersections()
	_test_area_cells()
	_test_drag_direction()
	_test_star_system()
	_test_make_grid_blocked()
	_test_level_configs()
	if _failures == 0:
		print("== ALL TESTS PASSED ==")
	else:
		printerr("== FAILURES: %d ==" % _failures)
	quit(_failures)


func _check(cond: bool, label: String) -> void:
	if cond:
		print("  PASS: ", label)
	else:
		_failures += 1
		printerr("  FAIL: ", label)


func _test_make_grid_shape() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var g := ML.make_grid(8, 8, 6, rng)
	_check(g.size() == 64, "make_grid: 64 cells")
	var in_range := true
	for v in g:
		if v < 0 or v >= 6:
			in_range = false
	_check(in_range, "make_grid: values in [0,6)")


func _test_make_grid_no_initial_matches() -> void:
	var rng := RandomNumberGenerator.new()
	for seed in range(20):
		rng.seed = seed
		var g := ML.make_grid(8, 8, 6, rng)
		if not ML.find_matches(g, 8, 8).is_empty():
			_check(false, "make_grid: no initial matches (seed %d)" % seed)
			return
	_check(true, "make_grid: no initial matches (20 seeds)")


func _test_find_matches() -> void:
	# 横向三连 + 横向四连
	var g: Array[int] = [
		0, 0, 0, 1,
		1, 2, 1, 2,
		2, 1, 2, 1,
		3, 3, 3, 3,
	]
	var m := ML.find_matches(g, 4, 4)
	_check(m.size() == 7, "find_matches: 7 matched cells")
	_check(m.has(Vector2i(0, 0)) and m.has(Vector2i(3, 3)), "find_matches: endpoints")


func _test_is_adjacent() -> void:
	_check(ML.is_adjacent(Vector2i(0, 0), Vector2i(1, 0)), "is_adjacent: horizontal")
	_check(ML.is_adjacent(Vector2i(3, 3), Vector2i(3, 4)), "is_adjacent: vertical")
	_check(not ML.is_adjacent(Vector2i(0, 0), Vector2i(1, 1)), "is_adjacent: diagonal rejected")
	_check(not ML.is_adjacent(Vector2i(0, 0), Vector2i(2, 0)), "is_adjacent: distant rejected")


func _test_has_possible_move_true() -> void:
	# 交换 (1,0) 与 (1,1) 后第一行变成 0,0,0
	var g: Array[int] = [
		0, 1, 0,
		1, 0, 2,
		0, 1, 2,
	]
	_check(ML.has_possible_move(g, 3, 3), "has_possible_move: known move detected")
	# 检测过程不得改变网格
	var expect: Array[int] = [0, 1, 0, 1, 0, 2, 0, 1, 2]
	_check(g == expect, "has_possible_move: grid unmutated")


## 回归：障碍格(-1)无棋子不可交换，不能被当成可行步（旧版误判 → 玩家死锁）
func _test_has_possible_move_obstacles() -> void:
	var g: Array[int] = [
		3, 0, -1, 0, 0, -1, -1,
		1, 2, 3, 4, 5, 1, 2,
		2, 3, 4, 5, 1, 2, 3,
	]
	_check(ML.find_matches(g, 7, 3).is_empty(), "obstacle: fixture has no matches")
	_check(not ML.has_possible_move(g, 7, 3),
		"obstacle: move via empty cell is fake → no move")


## 魔力花：与任意相邻棋子交换都有效；被障碍围死则不算可行步
func _test_has_possible_move_magic() -> void:
	var g: Array[int] = [
		1, 2, 3,
		4, ML.MAGIC, 5,
		6, 1, 2,
	]
	_check(ML.has_possible_move(g, 3, 3), "magic: adjacent swap always valid")
	var walled: Array[int] = [
		0, -1, 1,
		-1, ML.MAGIC, -1,
		1, -1, 0,
	]
	_check(not ML.has_possible_move(walled, 3, 3), "magic: walled-in = no move")


## 重排：保留特殊花与障碍；保证无初始消除且有可行步；不改动输入网格
func _test_reshuffle_keeps_specials() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var w := 7
	var h := 4
	# 3×3 障碍块（魔力花放中心，被完全围死，不构成可行步）
	var blocked := {}
	for dx in range(3):
		for dy in range(3):
			blocked[Vector2i(dx, dy)] = -1
	var g := ML.make_grid(w, h, 6, rng, blocked)
	g[1 * w + 1] = ML.MAGIC
	var movable_before: bool = ML.has_possible_move(g, w, h)
	var keep := {Vector2i(1, 1): true}
	var out := ML.reshuffle_grid(g, w, h, 6, rng, keep)
	_check(out[1 * w + 1] == ML.MAGIC, "reshuffle: magic kept in place")
	_check(out[0] == -1 and out[2 * w + 2] == -1, "reshuffle: obstacles untouched")
	_check(ML.find_matches(out, w, h).is_empty(), "reshuffle: no initial matches")
	_check(ML.has_possible_move(out, w, h), "reshuffle: solvable after shuffle")
	_check(g[1 * w + 1] == ML.MAGIC, "reshuffle: input grid not mutated")
	_check(movable_before == true, "reshuffle: fixture itself is playable")


func _test_swap_cells() -> void:
	var g: Array[int] = [1, 2, 3, 4]
	ML.swap_cells(g, 2, Vector2i(0, 0), Vector2i(1, 1))
	var expect: Array[int] = [4, 2, 3, 1]
	_check(g == expect, "swap_cells: diagonal swap")


func _test_match_groups() -> void:
	# 横向四连
	var g4: Array[int] = [
		0, 0, 0, 0, 1,
		1, 2, 1, 2, 2,
		2, 1, 2, 1, 0,
	]
	var gr4 := ML.find_match_groups(g4, 5, 3)
	_check(gr4.size() == 1, "groups: one 4-run")
	_check(gr4[0]["length"] == 4 and gr4[0]["dir"] == ML.DIR_H, "groups: 4-run is horizontal")
	# 纵向五连
	var g5: Array[int] = [
		2, 1, 0,
		2, 0, 1,
		2, 1, 0,
		2, 0, 1,
		2, 1, 0,
	]
	var gr5 := ML.find_match_groups(g5, 3, 5)
	_check(gr5.size() == 1 and gr5[0]["length"] == 5 and gr5[0]["dir"] == ML.DIR_V,
		"groups: vertical 5-run")
	# L 形交叉 → 两组
	var gl: Array[int] = [
		0, 0, 0,
		1, 0, 2,
		1, 0, 2,
	]
	_check(ML.find_match_groups(gl, 3, 3).size() == 2, "groups: L-shape gives 2 groups")


func _test_magic_excluded() -> void:
	# -2（魔力花）不参与颜色匹配，-1（空格）同理
	var g: Array[int] = [
		-2, -2, -2,
		-1, -1, -1,
		0, 1, 2,
	]
	_check(ML.find_matches(g, 3, 3).is_empty(), "magic (-2) and empty (-1) never match")


func _test_intersections() -> void:
	# L 形：行三连 + 列三连共角
	var gl: Array[int] = [
		0, 0, 0,
		1, 2, 0,
		2, 1, 0,
	]
	var groups := ML.find_match_groups(gl, 3, 3)
	_check(groups.size() == 2, "L-shape: 2 groups")
	var its := ML.find_intersections(groups)
	_check(its.size() == 1, "L-shape: 1 intersection")
	_check(its[0]["cell"] == Vector2i(2, 0), "L-shape: intersection at corner (2,0)")
	_check(its[0]["cells"].size() == 5, "L-shape: 5 unique cells")
	# T 形
	var gt: Array[int] = [
		1, 1, 1,
		2, 1, 0,
		0, 1, 2,
	]
	var its2 := ML.find_intersections(ML.find_match_groups(gt, 3, 3))
	_check(its2.size() == 1 and its2[0]["cell"] == Vector2i(1, 0), "T-shape: intersection at (1,0)")
	# 平行连组无交叉
	var gp: Array[int] = [
		0, 0, 0,
		1, 1, 1,
		2, 1, 2,
	]
	_check(ML.find_intersections(ML.find_match_groups(gp, 3, 3)).is_empty(),
		"parallel groups: no intersection")


func _test_area_cells() -> void:
	var center := ML.area_cells(Vector2i(3, 3), 7, 11)
	_check(center.size() == 9, "area_cells: 3x3 at center")
	_check(center.has(Vector2i(2, 2)) and center.has(Vector2i(4, 4)), "area_cells: corners in")
	var edge := ML.area_cells(Vector2i(0, 0), 7, 11)
	_check(edge.size() == 4, "area_cells: clipped at board corner")
	_check(not edge.has(Vector2i(-1, 0)), "area_cells: no negative coords")


func _test_drag_direction() -> void:
	_check(ML.drag_direction(Vector2(50, 5)) == Vector2i.RIGHT, "drag: right")
	_check(ML.drag_direction(Vector2(-50, 8)) == Vector2i.LEFT, "drag: left")
	_check(ML.drag_direction(Vector2(6, 60)) == Vector2i.DOWN, "drag: down")
	_check(ML.drag_direction(Vector2(-3, -60)) == Vector2i.UP, "drag: up")
	_check(ML.drag_direction(Vector2(30, -28)) == Vector2i.RIGHT, "drag: x-dominant tie")
	_check(ML.drag_direction(Vector2.ZERO) == Vector2i.ZERO, "drag: zero delta")


func _test_star_system() -> void:
	# 门槛：1★=目标 2★=1.35x 3★=1.75x
	var t := GS.star_thresholds(1000)
	var expect: Array[int] = [1000, 1350, 1750]
	_check(t == expect, "stars: thresholds 1x/1.35x/1.75x")
	_check(GS.star_rating(1000, 999) == 0, "stars: below target = 0")
	_check(GS.star_rating(1000, 1000) == 1, "stars: target = 1")
	_check(GS.star_rating(1000, 1349) == 1, "stars: just below 2nd = 1")
	_check(GS.star_rating(1000, 1350) == 2, "stars: 1.35x = 2")
	_check(GS.star_rating(1000, 1749) == 2, "stars: just below 3rd = 2")
	_check(GS.star_rating(1000, 1750) == 3, "stars: 1.75x = 3")
	_check(GS.star_rating(1200, 2400) == 3, "stars: level1 2400 = 3")
	var t2 := GS.star_thresholds(2000)
	_check(t2[0] < t2[1] and t2[1] < t2[2], "stars: thresholds monotonic")


func _test_make_grid_blocked() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var blocked := {Vector2i(0, 0): -1, Vector2i(3, 5): 1}
	var g := ML.make_grid(7, 11, 6, rng, blocked)
	_check(g[0] == -1 and g[5 * 7 + 3] == -1, "blocked: cells set to -1")
	var valid := true
	for i in range(g.size()):
		var cell := Vector2i(i % 7, i / 7)
		if not blocked.has(cell) and (g[i] < 0 or g[i] >= 6):
			valid = false
	_check(valid, "blocked: playable cells valid types")
	_check(ML.find_matches(g, 7, 11).is_empty(), "blocked: no initial matches")


func _test_level_configs() -> void:
	var ok := true
	for lv in GS.LEVELS:
		if int(lv["flowers"]) < 4 or int(lv["flowers"]) > 6:
			ok = false
		var seen: Dictionary = {}
		for v in lv["vines"]:
			var c := Vector2i(v[0], v[1])
			if c.x < 0 or c.x >= 7 or c.y < 0 or c.y >= 11 or seen.has(c):
				ok = false
			seen[c] = true
		for s in lv["snow"]:
			var c := Vector2i(s[0], s[1])
			if c.x < 0 or c.x >= 7 or c.y < 0 or c.y >= 11 or seen.has(c):
				ok = false
			seen[c] = true
	_check(ok, "configs: flowers/vines/snow valid & no overlap")
	_check(int(GS.LEVELS[1]["vines"].size()) > 0, "configs: L2 has vines")
	_check(int(GS.LEVELS[2]["snow"].size()) > 0, "configs: L3 has snow")
	_check(int(GS.LEVELS[4]["flowers"]) == 5, "configs: L5 is 5-color (爽快)")
