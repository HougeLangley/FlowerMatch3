extends SceneTree

## 无头单元测试：godot --headless --path . -s tests/run_tests.gd
## 退出码 = 失败用例数

const ML := preload("res://scripts/match_logic.gd")

var _failures := 0


func _init() -> void:
	print("== FlowerMatch3 logic tests ==")
	_test_make_grid_shape()
	_test_make_grid_no_initial_matches()
	_test_find_matches()
	_test_is_adjacent()
	_test_has_possible_move_true()
	_test_swap_cells()
	_test_match_groups()
	_test_magic_excluded()
	_test_intersections()
	_test_area_cells()
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
