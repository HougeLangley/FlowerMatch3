class_name MatchLogic
extends RefCounted

## 纯逻辑层：只操作 int 网格（行优先），不依赖场景节点。
## 值域：0..type_count-1 为普通花；-1 = 空格；-2 = 魔力花（不参与颜色匹配）。

const DIR_H := 0  # 横向连
const DIR_V := 1  # 纵向连


## 生成无初始消除的网格
static func make_grid(w: int, h: int, type_count: int, rng: RandomNumberGenerator) -> Array[int]:
	var g: Array[int] = []
	g.resize(w * h)
	for y in range(h):
		for x in range(w):
			var banned: Dictionary = {}
			if x >= 2 and g[y * w + x - 1] == g[y * w + x - 2]:
				banned[g[y * w + x - 1]] = true
			if y >= 2 and g[(y - 1) * w + x] == g[(y - 2) * w + x]:
				banned[g[(y - 1) * w + x]] = true
			var t: int = rng.randi_range(0, type_count - 1)
			var guard := 0
			while banned.has(t) and guard < 64:
				t = rng.randi_range(0, type_count - 1)
				guard += 1
			g[y * w + x] = t
	return g


## 查找所有连组：Array of { cells: Array[Vector2i], length: int, dir: DIR_H/DIR_V }
static func find_match_groups(g: Array[int], w: int, h: int) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	# 横向
	for y in range(h):
		var run := 1
		for x in range(1, w + 1):
			var same := false
			if x < w:
				var idx := y * w + x
				same = g[idx] >= 0 and g[idx] == g[idx - 1]
			if same:
				run += 1
			else:
				if run >= 3:
					var cells: Array[Vector2i] = []
					for k in range(run):
						cells.append(Vector2i(x - 1 - k, y))
					groups.append({"cells": cells, "length": run, "dir": DIR_H})
				run = 1
	# 纵向
	for x in range(w):
		var run := 1
		for y in range(1, h + 1):
			var same := false
			if y < h:
				var idx := y * w + x
				same = g[idx] >= 0 and g[idx] == g[idx - w]
			if same:
				run += 1
			else:
				if run >= 3:
					var cells: Array[Vector2i] = []
					for k in range(run):
						cells.append(Vector2i(x, y - 1 - k))
					groups.append({"cells": cells, "length": run, "dir": DIR_V})
				run = 1
	return groups


## 所有被消除的格子（分组并集，当 Set 用）
static func find_matches(g: Array[int], w: int, h: int) -> Dictionary:
	var out: Dictionary = {}
	for grp in find_match_groups(g, w, h):
		for c in grp["cells"]:
			out[c] = true
	return out


static func is_adjacent(a: Vector2i, b: Vector2i) -> bool:
	return abs(a.x - b.x) + abs(a.y - b.y) == 1


## 检测 L/T 形：横竖连组共享格子 → 交叉点生成范围爆炸花
## 返回 Array of { cell: Vector2i 交叉点, cells: Array[Vector2i] 并集, group_indices: Array[int] }
static func find_intersections(groups: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in range(groups.size()):
		for j in range(i + 1, groups.size()):
			if groups[i]["dir"] == groups[j]["dir"]:
				continue
			var shared := _shared_cell(groups[i]["cells"], groups[j]["cells"])
			if shared == Vector2i(-1, -1):
				continue
			var all: Dictionary = {}
			for c in groups[i]["cells"]:
				all[c] = true
			for c in groups[j]["cells"]:
				all[c] = true
			out.append({
				"cell": shared,
				"cells": all.keys(),
				"group_indices": [i, j],
			})
	return out


static func _shared_cell(a: Array, b: Array) -> Vector2i:
	for ca in a:
		if b.has(ca):
			return ca
	return Vector2i(-1, -1)


## 以 center 为中心的 (2*radius+1)² 区域（裁剪到棋盘内）
static func area_cells(center: Vector2i, w: int, h: int, radius: int = 1) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var c := Vector2i(center.x + dx, center.y + dy)
			if c.x >= 0 and c.x < w and c.y >= 0 and c.y < h:
				out.append(c)
	return out


static func swap_cells(g: Array[int], w: int, a: Vector2i, b: Vector2i) -> void:
	var ai := a.y * w + a.x
	var bi := b.y * w + b.x
	var tmp := g[ai]
	g[ai] = g[bi]
	g[bi] = tmp


## 是否存在可行步（尝试所有相邻交换，检测后换回）
static func has_possible_move(g: Array[int], w: int, h: int) -> bool:
	for y in range(h):
		for x in range(w):
			var from := Vector2i(x, y)
			for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
				var to: Vector2i = from + dir
				if to.x >= w or to.y >= h:
					continue
				swap_cells(g, w, from, to)
				var found := not find_matches(g, w, h).is_empty()
				swap_cells(g, w, from, to)
				if found:
					return true
	return false
