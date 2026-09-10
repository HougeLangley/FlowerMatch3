class_name Board
extends Node2D

## 棋盘控制器：输入、交换、消除循环（含特殊花朵连锁）、重力、音效、粒子

signal score_changed(new_score: int)
signal input_received(pos: Vector2, cell: Vector2i)
signal debug_state(text: String)
signal move_made  # 一次有效交换完成（含消除结算后）

const GRID_W := 7
const GRID_H := 11  # 视觉模型测量：屏幕最大容纳 12 行，留底部边距取 11
const FLOWER_TYPES := 6
const POINTS_PER_TILE := 10
const MAGIC_POINTS_PER_TILE := 15
const SIDE_MARGIN := 10.0
const TOP_RATIO := 0.225  # 棋盘上缘占视口高度比例（避开前摄开孔与信息栏）

const FLOWER_COLORS: Array[Color] = [
	Color(0.85, 0.22, 0.22),   # 玫瑰
	Color(0.98, 0.76, 0.18),   # 向日葵
	Color(0.94, 0.45, 0.62),   # 樱花
	Color(0.95, 0.5, 0.15),    # 郁金香
	Color(0.52, 0.38, 0.76),   # 薰衣草
	Color(0.72, 0.87, 0.95),   # 百合
]
const PETAL_TEXTURE := preload("res://assets/petal.png")
const UI_FONT := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")

var _rng := RandomNumberGenerator.new()
var _tiles: Array = []  # _tiles[x][y] -> Tile 或 null
var _selected: Tile = null
var _busy := false
var _score := 0
var _tile_size := 100.0
var _origin := Vector2.ZERO

var _pop_player: AudioStreamPlayer
var _swap_player: AudioStreamPlayer
var _magic_player: AudioStreamPlayer
var _line_player: AudioStreamPlayer
var _boom_player: AudioStreamPlayer


func _ready() -> void:
	_rng.randomize()
	var view := get_viewport_rect().size
	_tile_size = (view.x - SIDE_MARGIN * 2.0) / float(GRID_W)
	_origin = Vector2(SIDE_MARGIN, view.y * TOP_RATIO)
	_add_backdrop(view)
	_pop_player = _make_player(preload("res://assets/sounds/pop.wav"))
	_swap_player = _make_player(preload("res://assets/sounds/swap.wav"))
	_magic_player = _make_player(preload("res://assets/sounds/magic.wav"))
	_line_player = _make_player(preload("res://assets/sounds/line.wav"))
	_boom_player = _make_player(preload("res://assets/sounds/boom.wav"))
	_build_grid()


func cell_to_world(p_cell: Vector2i) -> Vector2:
	return _origin + Vector2(p_cell) * _tile_size + Vector2.ONE * (_tile_size * 0.5)


func world_to_cell(pos: Vector2) -> Vector2i:
	var local := pos - _origin
	return Vector2i((local / _tile_size).floor())


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_W and cell.y >= 0 and cell.y < GRID_H


func _make_player(stream: AudioStream) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	add_child(player)
	return player


func _add_backdrop(view: Vector2) -> void:
	var panel := Sprite2D.new()
	panel.texture = preload("res://assets/panel.png")
	panel.position = Vector2(view.x * 0.5, _origin.y + _tile_size * GRID_H * 0.5)
	add_child(panel)


func _build_grid() -> void:
	var types := MatchLogic.make_grid(GRID_W, GRID_H, FLOWER_TYPES, _rng)
	while not MatchLogic.has_possible_move(types, GRID_W, GRID_H):
		types = MatchLogic.make_grid(GRID_W, GRID_H, FLOWER_TYPES, _rng)
	for x in range(GRID_W):
		var column: Array = []
		for y in range(GRID_H):
			column.append(_spawn_tile(Vector2i(x, y), types[y * GRID_W + x], 0))
		_tiles.append(column)


func _spawn_tile(p_cell: Vector2i, p_type: int, rows_above: int) -> Tile:
	var tile := Tile.new()
	tile.setup(p_type, _tile_size)
	tile.cell = p_cell
	tile.position = cell_to_world(p_cell) - Vector2(0.0, _tile_size * rows_above)
	add_child(tile)
	return tile




## 当前棋盘的 int 快照（魔力花记为 -2，不参与颜色匹配）
func _snapshot() -> Array[int]:
	var g: Array[int] = []
	g.resize(GRID_W * GRID_H)
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile == null:
				g[y * GRID_W + x] = -1
			elif tile.special == Tile.Special.MAGIC:
				g[y * GRID_W + x] = -2
			else:
				g[y * GRID_W + x] = tile.flower_type
	return g


func _unhandled_input(event: InputEvent) -> void:
	var pos := Vector2.ZERO
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		tapped = true
		pos = event.position
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		tapped = true
		pos = event.position
	if not tapped:
		return
	var cell := world_to_cell(pos)
	input_received.emit(pos, cell)
	if not is_valid_cell(cell):
		return
	_on_tile_pressed(_tiles[cell.x][cell.y])
	debug_state.emit("cell:%s sel:%s" % [cell, _selected.cell if _selected else "-"])


func _on_tile_pressed(tile: Tile) -> void:
	if _busy or tile == null:
		return
	if _selected == null:
		_selected = tile
		tile.set_selected(true)
	elif _selected == tile:
		tile.set_selected(false)
		_selected = null
	elif MatchLogic.is_adjacent(_selected.cell, tile.cell):
		_try_swap(_selected, tile)
	else:
		_selected.set_selected(false)
		_selected = tile
		tile.set_selected(true)


func _try_swap(a: Tile, b: Tile) -> void:
	_busy = true
	a.set_selected(false)
	_selected = null
	await _swap_visual(a, b)
	if a.special == Tile.Special.MAGIC or b.special == Tile.Special.MAGIC:
		await _resolve_magic(a, b)
		await _resolve_matches([a.cell, b.cell])
		move_made.emit()
	elif MatchLogic.find_matches(_snapshot(), GRID_W, GRID_H).is_empty():
		await _swap_visual(a, b)  # 无效交换，换回（不消耗步数）
	else:
		await _resolve_matches([a.cell, b.cell])
		move_made.emit()
	_busy = false


func _swap_visual(a: Tile, b: Tile) -> void:
	_tiles[a.cell.x][a.cell.y] = b
	_tiles[b.cell.x][b.cell.y] = a
	var tmp := a.cell
	a.cell = b.cell
	b.cell = tmp
	_swap_player.play()
	var tween_a := a.move_to(cell_to_world(a.cell))
	b.move_to(cell_to_world(b.cell))
	await tween_a.finished


## 魔力花交换：清除目标颜色的所有花（魔力花+魔力花 = 全盘）
func _resolve_magic(a: Tile, b: Tile) -> void:
	var target_type := -3  # -3 = 全部
	if a.special == Tile.Special.MAGIC and b.special == Tile.Special.MAGIC:
		target_type = -3
	elif a.special == Tile.Special.MAGIC:
		target_type = b.flower_type
	else:
		target_type = a.flower_type
	var clear: Dictionary = {a.cell: true, b.cell: true}
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile == null or tile.special == Tile.Special.MAGIC:
				continue
			if target_type == -3 or tile.flower_type == target_type:
				clear[Vector2i(x, y)] = true
	_score += clear.size() * MAGIC_POINTS_PER_TILE
	score_changed.emit(_score)
	_magic_player.play()
	_clear_cells(clear)
	await get_tree().create_timer(0.25).timeout
	await _apply_gravity()


## 消除循环：找连组 → 生成特殊花 → 连锁触发 → 清除 → 重力，直到无连组
func _resolve_matches(preferred: Array[Vector2i] = []) -> void:
	var combo := 0
	while true:
		var groups := MatchLogic.find_match_groups(_snapshot(), GRID_W, GRID_H)
		if groups.is_empty():
			break
		combo += 1
		var clear: Dictionary = {}
		var creations: Array = []
		# 先检测 L/T 交叉 → 范围爆炸花（消耗的连组不再生成行/列/魔力花）
		var intersections := MatchLogic.find_intersections(groups)
		var consumed: Dictionary = {}
		for it in intersections:
			for gi in it["group_indices"]:
				consumed[gi] = true
			for c in it["cells"]:
				clear[c] = true
			creations.append({"cell": it["cell"], "special": Tile.Special.BOMB})
		for i in range(groups.size()):
			if consumed.has(i):
				continue
			var grp: Dictionary = groups[i]
			for c in grp["cells"]:
				clear[c] = true
			if grp["length"] >= 5:
				creations.append({
					"cell": _pick_creation_cell(grp["cells"], preferred),
					"special": Tile.Special.MAGIC,
				})
			elif grp["length"] == 4:
				var sp: Tile.Special = Tile.Special.LINE_H \
					if grp["dir"] == MatchLogic.DIR_H else Tile.Special.LINE_V
				creations.append({
					"cell": _pick_creation_cell(grp["cells"], preferred),
					"special": sp,
				})
		_expand_special_chains(clear)
		for cr in creations:
			clear.erase(cr["cell"])
		if clear.is_empty():
			break
		var gained := clear.size() * POINTS_PER_TILE * combo
		_score += gained
		score_changed.emit(_score)
		_pop_player.pitch_scale = 1.0 + (combo - 1) * 0.12
		_pop_player.play()
		_clear_cells(clear)
		# 连击浮字
		var center := _cells_center(clear.keys())
		if combo > 1:
			_spawn_float_text(center + Vector2(0, -70), "连锁×%d" % combo,
				Color(0.98, 0.72, 0.15), 56)
		_spawn_float_text(center, "+%d" % gained, Color(0.2, 0.42, 0.28), 48)
		for cr in creations:
			var tile: Tile = _tiles[cr["cell"].x][cr["cell"].y]
			if tile != null:
				tile.set_special(cr["special"])
				tile.pulse()
		await get_tree().create_timer(0.22).timeout
		await _apply_gravity()
	if not _has_magic() and not MatchLogic.has_possible_move(_snapshot(), GRID_W, GRID_H):
		_reshuffle()


## 特殊花连锁：被消除的行/列/魔力花继续引爆
func _expand_special_chains(clear: Dictionary) -> void:
	var processed: Dictionary = {}
	var queue: Array[Vector2i] = []
	for c in clear.keys():
		var tile: Tile = _tiles[c.x][c.y]
		if tile != null and tile.special != Tile.Special.NONE:
			queue.append(c)
	while not queue.is_empty():
		var c: Vector2i = queue.pop_back()
		if processed.has(c):
			continue
		processed[c] = true
		var tile: Tile = _tiles[c.x][c.y]
		if tile == null:
			continue
		var extra: Array[Vector2i] = []
		match tile.special:
			Tile.Special.LINE_H:
				for x in range(GRID_W):
					extra.append(Vector2i(x, c.y))
				_line_player.play()
			Tile.Special.LINE_V:
				for y in range(GRID_H):
					extra.append(Vector2i(c.x, y))
				_line_player.play()
			Tile.Special.BOMB:
				extra.append_array(MatchLogic.area_cells(c, GRID_W, GRID_H, 1))
				_boom_player.play()
			Tile.Special.MAGIC:
				extra.append_array(_cells_of_type(_most_common_type()))
		for e in extra:
			if not clear.has(e):
				clear[e] = true
				var et: Tile = _tiles[e.x][e.y]
				if et != null and et.special != Tile.Special.NONE:
					queue.append(e)


func _clear_cells(clear: Dictionary) -> void:
	for c in clear.keys():
		var tile: Tile = _tiles[c.x][c.y]
		if tile == null:
			continue
		_tiles[c.x][c.y] = null
		_spawn_pop_effect(cell_to_world(c), FLOWER_COLORS[tile.flower_type])
		tile.pop()


## 消除粒子：花瓣飞散
func _spawn_pop_effect(pos: Vector2, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.texture = PETAL_TEXTURE
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 12
	p.lifetime = 0.6
	p.direction = Vector2(0.0, -1.0)
	p.spread = 180.0
	p.initial_velocity_min = 140.0
	p.initial_velocity_max = 300.0
	p.gravity = Vector2(0.0, 600.0)
	p.damping_min = 40.0
	p.damping_max = 80.0
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	p.color = color
	p.position = pos
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.2).timeout.connect(p.queue_free)


## 一组格子的世界坐标中心
func _cells_center(cells: Array) -> Vector2:
	var sum := Vector2.ZERO
	for c in cells:
		sum += cell_to_world(c)
	return sum / max(cells.size(), 1)


## 连击/得分浮字：上浮淡出后自动销毁
func _spawn_float_text(world_pos: Vector2, text: String, color: Color, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.9))
	label.add_theme_constant_override("outline_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 近似居中（按字号估算文本宽度）
	label.position = world_pos + Vector2(-text.length() * font_size * 0.28, -font_size * 0.6)
	label.z_index = 10
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 90.0, 0.6) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5).set_delay(0.25)
	tween.tween_callback(label.queue_free)


## 特殊花生成位置：优先落在交换的棋子上，否则取连组中间
func _pick_creation_cell(cells: Array, preferred: Array[Vector2i]) -> Vector2i:
	for p in preferred:
		if cells.has(p):
			return p
	return cells[cells.size() / 2]


func _most_common_type() -> int:
	var counts: Dictionary = {}
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile != null and tile.special != Tile.Special.MAGIC:
				counts[tile.flower_type] = counts.get(tile.flower_type, 0) + 1
	var best := 0
	var best_count := -1
	for t in counts.keys():
		if counts[t] > best_count:
			best_count = counts[t]
			best = t
	return best


func _cells_of_type(target: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile != null and tile.flower_type == target \
					and tile.special != Tile.Special.MAGIC:
				out.append(Vector2i(x, y))
	return out


func _has_magic() -> bool:
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile != null and tile.special == Tile.Special.MAGIC:
				return true
	return false


func _apply_gravity() -> void:
	var last_tween: Tween = null
	for x in range(GRID_W):
		var write := GRID_H - 1
		for y in range(GRID_H - 1, -1, -1):
			var tile: Tile = _tiles[x][y]
			if tile == null:
				continue
			if y != write:
				_tiles[x][write] = tile
				_tiles[x][y] = null
				tile.cell = Vector2i(x, write)
				last_tween = tile.move_to(cell_to_world(tile.cell))
			write -= 1
		var empty_count := write + 1
		for y in range(write, -1, -1):
			var type := _rng.randi_range(0, FLOWER_TYPES - 1)
			var tile := _spawn_tile(Vector2i(x, y), type, empty_count)
			_tiles[x][y] = tile  # 关键：新棋子必须注册进网格，否则不可交互/不参与匹配
			last_tween = tile.move_to(cell_to_world(tile.cell))
	if last_tween != null:
		await last_tween.finished


## 无可行步时原地重排（保证无初始消除且有解），特殊花重置
func _reshuffle() -> void:
	var types := MatchLogic.make_grid(GRID_W, GRID_H, FLOWER_TYPES, _rng)
	while not MatchLogic.has_possible_move(types, GRID_W, GRID_H):
		types = MatchLogic.make_grid(GRID_W, GRID_H, FLOWER_TYPES, _rng)
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile == null:
				continue
			tile.set_special(Tile.Special.NONE)
			tile.set_flower(types[y * GRID_W + x])
