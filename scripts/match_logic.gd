class_name MatchLogic
extends RefCounted

## 纯逻辑层：只操作 int 网格（行优先），不依赖场景节点。
## 值域：0..type_count-1 为普通花；-1 = 空格；-2 = 魔力花（不参与颜色匹配）。

const DIR_H := 0  # 横向连
const DIR_V := 1  # 纵向连

const EMPTY := -1  # 空格/障碍（无棋子，不可交换）
const MAGIC := -2  # 魔力花（不参与颜色匹配，但与任意相邻棋子交换均有效）


## 生成无初始消除的网格；blocked 中的格子置为 -1（障碍/真空位）
static func make_grid(w: int, h: int, type_count: int, rng: RandomNumberGenerator,
		blocked: Dictionary = {}) -> Array[int]:
	var g: Array[int] = []
	g.resize(w * h)
	for i in range(w * h):
		if blocked.has(Vector2i(i % w, i / w)):
			g[i] = -1
	for y in range(h):
		for x in range(w):
			if g[y * w + x] == -1:
				continue
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


## 拖拽位移 → 主方向单位向量（取绝对值大的轴），零位移返回 ZERO
static func drag_direction(delta: Vector2) -> Vector2i:
	if absf(delta.x) < 0.0001 and absf(delta.y) < 0.0001:
		return Vector2i.ZERO
	if absf(delta.x) >= absf(delta.y):
		return Vector2i.RIGHT if delta.x > 0.0 else Vector2i.LEFT
	return Vector2i.DOWN if delta.y > 0.0 else Vector2i.UP


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


## 重排：保留 keep 格（特殊花）与障碍，其余格重新着色；
## 保证「无初始消除」且「存在可行步」。逐级降级：保留特殊花 → 放弃保留全盘重生成。
static func reshuffle_grid(g: Array[int], w: int, h: int, type_count: int,
		rng: RandomNumberGenerator, keep: Dictionary = {}) -> Array[int]:
	var fallback: Array[int] = _copy_grid(g, w, h)
	for attempt in range(40):
		var out: Array[int] = _recolor(g, w, h, type_count, rng, keep)
		fallback = out
		if find_matches(out, w, h).is_empty() and has_possible_move(out, w, h):
			return out
	# 降级：不动特殊花很难两全时，全盘重生成（放弃保留特殊花）
	var blocked := blocked_of(g, w, h)
	for attempt in range(40):
		var fresh := make_grid(w, h, type_count, rng, blocked)
		fallback = fresh
		if has_possible_move(fresh, w, h):
			return fresh
	return fallback  # 极端兕底（理论上不可达）


## 把网格中的空格（-1）转成 make_grid 需要的 blocked 字典
static func blocked_of(g: Array[int], w: int, h: int) -> Dictionary:
	var d: Dictionary = {}
	for y in range(h):
		for x in range(w):
			if g[y * w + x] == EMPTY:
				d[Vector2i(x, y)] = true
	return d


## 重新着色：障碍与 keep 格不动，其余格随机取值（避免与已定的左/上邻居形成三连）
static func _recolor(g: Array[int], w: int, h: int, type_count: int,
		rng: RandomNumberGenerator, keep: Dictionary) -> Array[int]:
	var out: Array[int] = _copy_grid(g, w, h)
	for y in range(h):
		for x in range(w):
			var idx := y * w + x
			if out[idx] == EMPTY or keep.has(Vector2i(x, y)):
				continue
			var banned: Dictionary = {}
			if x >= 2 and out[idx - 1] >= 0 and out[idx - 1] == out[idx - 2]:
				banned[out[idx - 1]] = true
			if y >= 2 and out[idx - w] >= 0 and out[idx - w] == out[idx - 2 * w]:
				banned[out[idx - w]] = true
			var t: int = rng.randi_range(0, type_count - 1)
			var guard := 0
			while banned.has(t) and guard < 64:
				t = rng.randi_range(0, type_count - 1)
				guard += 1
			out[idx] = t
	return out


static func _copy_grid(g: Array[int], w: int, h: int) -> Array[int]:
	var out: Array[int] = []
	out.resize(w * h)
	for i in range(w * h):
		out[i] = g[i]
	return out


static func swap_cells(g: Array[int], w: int, a: Vector2i, b: Vector2i) -> void:
	var ai := a.y * w + a.x
	var bi := b.y * w + b.x
	var tmp := g[ai]
	g[ai] = g[bi]
	g[bi] = tmp


## 是否存在玩家真的可以执行的可行步（与真实交换规则一致）
## 规则：障碍格无棋子不可交换；魔力花与任意相邻棋子交换均有效
static func has_possible_move(g: Array[int], w: int, h: int) -> bool:
	for y in range(h):
		for x in range(w):
			var from := Vector2i(x, y)
			for dir in [Vector2i.RIGHT, Vector2i.DOWN]:
				var to: Vector2i = from + dir
				if to.x >= w or to.y >= h:
					continue
				var a: int = g[from.y * w + from.x]
				var b: int = g[to.y * w + to.x]
				if a == EMPTY or b == EMPTY:
					continue  # 障碍/空格不可交换（旧版遗漏此处 → 误判有解 → 玩家死锁）
				if a == MAGIC or b == MAGIC:
					return true  # 魔力花可任意交换，必定有效
				swap_cells(g, w, from, to)
				var found := not find_matches(g, w, h).is_empty()
				swap_cells(g, w, from, to)
				if found:
					return true
	return false
