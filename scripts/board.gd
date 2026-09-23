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
const VOID := -2  # 形状虚空（不可见墙）：既无棋子也不画障碍精灵
const SIDE_MARGIN := 10.0
const TOP_RATIO := 0.225  # 棋盘上缘占视口高度比例（避开前摄开孔与信息栏）
const DRAG_TRIGGER_RATIO := 0.3  # 拖拽超过 0.3 格宽即触发交换（轻划手感）

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
const VINE_TEXTURE := preload("res://assets/vine.png")
const SNOW_TEXTURE := preload("res://assets/snow.png")

var _rng := RandomNumberGenerator.new()
var _tiles: Array = []  # _tiles[x][y] -> Tile 或 null
var _selected: Tile = null
var _busy := false
var _busy_since := 0  # 输入看门狗：_busy 置 true 的时刻（毫秒）
const BUSY_TIMEOUT_MS := 8000  # 正常最长连锁约 5 秒，超过则视为异常并自愈
const HINT_IDLE_SEC := 6.0     # 玩家静止多久后给提示（略宽于竞品，不打扰）
const HINT_REPEAT_SEC := 4.0   # 之后每隔多久再提醒一次
var _hint_timer := 0.0
var _last_hint: Array[Vector2i] = []  # 最近一次的提示（供测试/诊断）
var _score := 0
var _tile_size := 100.0
var _origin := Vector2.ZERO

# 本关配置（来自 GameState.LEVELS）
var _flower_types := 6            # 花色数（5 色更爽快）
var _blocks: Dictionary = {}      # Vector2i -> HP（-1=永久藤蔓，>=1=可破雪块）
var _block_sprites: Dictionary = {}  # Vector2i -> Sprite2D

# 指针状态（点击选牌 + 按住滑动交换）
var _pointer_down := false
var _drag_start_pos := Vector2.ZERO
var _drag_start_cell := Vector2i(-1, -1)
var _drag_consumed := false


func _ready() -> void:
	_rng.randomize()
	var view := get_viewport_rect().size
	_tile_size = (view.x - SIDE_MARGIN * 2.0) / float(GRID_W)
	_origin = Vector2(SIDE_MARGIN, view.y * TOP_RATIO)
	Sfx.set_level_index(GameState.current_level)  # 每关不同调性
	_add_backdrop(view)      # 先加卡片（树序最底）
	_load_level_config()      # 再加障碍精灵（盖在卡片上）
	_build_grid()


## 每帧：① 输入看门狗（_busy 卡住自愈）② 长时间无操作的可行步提示
func _process(delta: float) -> void:
	if _busy:
		var stuck_ms := Time.get_ticks_msec() - _busy_since
		if stuck_ms > BUSY_TIMEOUT_MS:
			print("[self-heal] 输入看门狗：_busy 卡住 %.1f 秒，已重置" % (stuck_ms / 1000.0))
			_busy = false
			_repair_holes()
			_check_deadlock()
		return
	# 提示：借鉴同类游戏——玩家长时间找不到可消的，主动高亮一个可行步
	_hint_timer += delta
	if _hint_timer >= HINT_IDLE_SEC:
		_hint_timer = HINT_IDLE_SEC - HINT_REPEAT_SEC
		_show_hint()


## 高亮一个可行步（两颗棋子脉动 + 轻提示音）；真无解时交给 _check_deadlock 重排
func _show_hint() -> void:
	var mv := MatchLogic.find_any_move(_snapshot(), GRID_W, GRID_H)
	if mv.is_empty():
		return
	_last_hint = mv
	for c in mv:
		var tile: Tile = _tiles[c.x][c.y]
		if tile != null:
			tile.hint_wiggle()
	Sfx.play_hint(cell_to_world(mv[0]))


## 棋盘可视区域（像素空间）——供 3D 视图与输入代理判断触摸是否落在棋盘内
func board_rect() -> Rect2:
	var view := get_viewport_rect().size
	return Rect2(0.0, _origin.y - _tile_size * 0.7,
		view.x, _tile_size * (GRID_H + 1.4))


func cell_to_world(p_cell: Vector2i) -> Vector2:
	return _origin + Vector2(p_cell) * _tile_size + Vector2.ONE * (_tile_size * 0.5)


func world_to_cell(pos: Vector2) -> Vector2i:
	var local := pos - _origin
	return Vector2i((local / _tile_size).floor())


func is_valid_cell(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_W and cell.y >= 0 and cell.y < GRID_H


func _add_backdrop(view: Vector2) -> void:
	var panel := Sprite2D.new()
	panel.texture = preload("res://assets/panel.png")
	panel.position = Vector2(view.x * 0.5, _origin.y + _tile_size * GRID_H * 0.5)
	# 不用 z_index（画布全局，易误伤）；靠树序：卡片→障碍→棋子
	add_child(panel)


## 读取本关配置：花色数 + 障碍（藤蔓永久 / 雪块可破）
func _load_level_config() -> void:
	var cfg: Dictionary = GameState.LEVELS[GameState.current_level - 1]
	_flower_types = int(cfg.get("flowers", 6))
	# 形状虚空：形状外的格子登记为不可见墙（无棋子、无精灵，等同障碍）
	var mask: Array = GameState.shape_of(GameState.current_level)
	for y in range(GRID_H):
		var row := String(mask[y]) if y < mask.size() else ""
		for x in range(GRID_W):
			if x >= row.length() or row[x] != "#":
				_blocks[Vector2i(x, y)] = VOID
	for v in cfg.get("vines", []):
		_blocks[Vector2i(v[0], v[1])] = -1
	for s in cfg.get("snow", []):
		var c := Vector2i(s[0], s[1])
		if not _blocks.has(c):
			_blocks[c] = 1
	_add_block_sprites()


func _add_block_sprites() -> void:
	for cell in _blocks.keys():
		if int(_blocks[cell]) == VOID:
			continue  # 形状虚空：不画障碍精灵
		var sprite := Sprite2D.new()
		sprite.texture = VINE_TEXTURE if int(_blocks[cell]) < 0 else SNOW_TEXTURE
		var tex_w := float(sprite.texture.get_width())
		sprite.scale = Vector2.ONE * (_tile_size * 0.96 / tex_w)
		sprite.position = cell_to_world(cell)
		add_child(sprite)
		_block_sprites[cell] = sprite


## 相邻消除破坏障碍：雪块 1 点即碎，藤蔓永久不破
func _damage_adjacent_blocks(clear: Dictionary) -> void:
	var hit: Dictionary = {}
	for c in clear.keys():
		for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if _blocks.has(n):
				hit[n] = true
	for n in hit.keys():
		var hp: int = int(_blocks[n])
		if hp < 0:
			continue
		hp -= 1
		if hp <= 0:
			_blocks.erase(n)
			_break_block_sprite(n)
			Sfx.play_break(cell_to_world(n))
		else:
			_blocks[n] = hp
			_flash_block_sprite(n)


func _break_block_sprite(cell: Vector2i) -> void:
	var sprite: Sprite2D = _block_sprites.get(cell)
	if sprite == null:
		return
	_block_sprites.erase(cell)
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", Vector2.ZERO, 0.18)
	tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.18)
	tween.tween_callback(sprite.queue_free)


func _flash_block_sprite(cell: Vector2i) -> void:
	var sprite: Sprite2D = _block_sprites.get(cell)
	if sprite == null:
		return
	var base: Vector2 = sprite.scale
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "scale", base * 1.18, 0.08)
	tween.tween_property(sprite, "scale", base, 0.1)


func _build_grid() -> void:
	var types := MatchLogic.make_grid(GRID_W, GRID_H, _flower_types, _rng, _blocks)
	while not MatchLogic.has_possible_move(types, GRID_W, GRID_H):
		types = MatchLogic.make_grid(GRID_W, GRID_H, _flower_types, _rng, _blocks)
	for x in range(GRID_W):
		var column: Array = []
		for y in range(GRID_H):
			if _blocks.has(Vector2i(x, y)):
				column.append(null)  # 障碍格无棋子
			else:
				column.append(_spawn_tile(Vector2i(x, y), types[y * GRID_W + x], 0))
		_tiles.append(column)


func _spawn_tile(p_cell: Vector2i, p_type: int, rows_above: int) -> Tile:
	var tile := Tile.new()
	tile.setup(p_type, _tile_size)
	tile.cell = p_cell
	tile.position = cell_to_world(p_cell) - Vector2(0.0, _tile_size * rows_above)
	add_child(tile)
	tile.start_idle()  # 开启闲置动效（每种花不同律动）
	return tile




## 当前棋盘的 int 快照（魔力花记为 -2，不参与颜色匹配）
func _snapshot() -> Array[int]:
	var g: Array[int] = []
	g.resize(GRID_W * GRID_H)
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile == null:
				g[y * GRID_W + x] = MatchLogic.EMPTY
			elif tile.special == Tile.Special.MAGIC:
				g[y * GRID_W + x] = MatchLogic.MAGIC
			else:
				g[y * GRID_W + x] = tile.flower_type
	return g


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer()
	elif event is InputEventScreenDrag:
		if event.index == 0:
			_update_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_pointer(event.position)
		else:
			_end_pointer()
	elif event is InputEventMouseMotion and _pointer_down:
		_update_drag(event.position)


func _begin_pointer(pos: Vector2) -> void:
	_pointer_down = true
	_drag_consumed = false
	_drag_start_pos = pos
	_drag_start_cell = world_to_cell(pos)
	_hint_timer = 0.0  # 有操作就重置提示计时
	input_received.emit(pos, _drag_start_cell)
	if not is_valid_cell(_drag_start_cell):
		return
	_on_tile_pressed(_tiles[_drag_start_cell.x][_drag_start_cell.y])
	debug_state.emit("press:%s sel:%s" % [_drag_start_cell,
		_selected.cell if _selected else "-"])


## 按住滑动：拖过触发距离后按主方向与相邻格交换（轻划手感）
func _update_drag(pos: Vector2) -> void:
	if not _pointer_down or _drag_consumed or _busy:
		return
	if not is_valid_cell(_drag_start_cell):
		return
	if pos.distance_to(_drag_start_pos) < _tile_size * DRAG_TRIGGER_RATIO:
		return
	_drag_consumed = true
	var dir := MatchLogic.drag_direction(pos - _drag_start_pos)
	if dir == Vector2i.ZERO:
		return
	var target := _drag_start_cell + dir
	if not is_valid_cell(target):
		return
	var from_tile: Tile = _tiles[_drag_start_cell.x][_drag_start_cell.y]
	var to_tile: Tile = _tiles[target.x][target.y]
	if from_tile != null and to_tile != null:
		_try_swap(from_tile, to_tile)


func _end_pointer() -> void:
	_pointer_down = false
	_drag_consumed = false
	_drag_start_cell = Vector2i(-1, -1)


func _on_tile_pressed(tile: Tile) -> void:
	if _busy or tile == null:
		return
	if _selected == null:
		_selected = tile
		tile.set_selected(true)
		Sfx.play_select(cell_to_world(tile.cell))
	elif _selected == tile:
		tile.set_selected(false)
		_selected = null
	elif MatchLogic.is_adjacent(_selected.cell, tile.cell):
		_try_swap(_selected, tile)
	else:
		_selected.set_selected(false)
		_selected = tile
		tile.set_selected(true)
		Sfx.play_select(cell_to_world(tile.cell))


func _try_swap(a: Tile, b: Tile) -> void:
	_busy = true
	_busy_since = Time.get_ticks_msec()  # 输入看门狗基准
	a.set_selected(false)
	_selected = null
	await _swap_visual(a, b)
	if not (is_instance_valid(a) and is_instance_valid(b)):
		# 棋子可能在交换过程中被销毁（旧版此处报错 → 协程中断 → _busy 永久为 true → 点击全失效）
		print("[self-heal] 交换后棋子已销毁，安全收尾")
		_busy = false
		_check_deadlock()
		return
	if a.special == Tile.Special.MAGIC or b.special == Tile.Special.MAGIC:
		await _resolve_magic(a, b)
		await _resolve_matches([a.cell, b.cell])
		move_made.emit()
	elif MatchLogic.find_matches(_snapshot(), GRID_W, GRID_H).is_empty():
		await _swap_visual(a, b, true)  # 无效交换，换回（不消耗步数）
		Sfx.play_invalid((cell_to_world(a.cell) + cell_to_world(b.cell)) * 0.5)
		_check_deadlock()  # 无效交换也可能是「棋盘已无解」的信号 → 立即自救
	else:
		await _resolve_matches([a.cell, b.cell])
		move_made.emit()
	_busy = false


func _swap_visual(a: Tile, b: Tile, silent := false) -> void:
	if not (is_instance_valid(a) and is_instance_valid(b)):
		return
	var vertical := a.cell.x == b.cell.x  # 同列 = 纵向交换（音色略有区分）
	var mid := (cell_to_world(a.cell) + cell_to_world(b.cell)) * 0.5
	_tiles[a.cell.x][a.cell.y] = b
	_tiles[b.cell.x][b.cell.y] = a
	var tmp := a.cell
	a.cell = b.cell
	b.cell = tmp
	if not silent:
		Sfx.play_swap(mid, vertical)
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
	Sfx.play_magic((cell_to_world(a.cell) + cell_to_world(b.cell)) * 0.5)
	_shake(12.0)
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
		_damage_adjacent_blocks(clear)  # 相邻消除破坏雪块（开图节奏）
		for cr in creations:
			clear.erase(cr["cell"])
		if clear.is_empty():
			break
		var gained := clear.size() * POINTS_PER_TILE * combo
		_score += gained
		score_changed.emit(_score)
		var center := _cells_center(clear.keys())
		Sfx.play_pop(combo, center)
		_clear_cells(clear)
		# 连击浮字 + 连击播报（爽感：越连越有成就感）
		if combo > 1:
			_spawn_float_text(center + Vector2(0, -70), "连锁×%d" % combo,
				Color(0.98, 0.72, 0.15), 56)
		if combo >= 3:
			_spawn_float_text(center + Vector2(0, -140), _combo_callout(combo),
				Color(1.0, 0.52, 0.2), 68)
			Sfx.play_star(combo - 3)
		_spawn_float_text(center, "+%d" % gained, Color(0.2, 0.42, 0.28), 48)
		for cr in creations:
			var tile: Tile = _tiles[cr["cell"].x][cr["cell"].y]
			if tile != null:
				tile.set_special(cr["special"])
				tile.pulse()
				Sfx.play_special(cell_to_world(cr["cell"]))
		await get_tree().create_timer(0.22).timeout
		await _apply_gravity()
	_check_deadlock()


## 死局自救（借鉴同类游戏标准做法：无可消除时自动重排）：
## 先补洞（异常空洞会让棋盘变稀疏、看着“没得消”）再检查可行步
## 注意魔力花也算可行步（与任意相邻棋子交换均有效），由纯逻辑层统一判定
func _check_deadlock() -> void:
	_repair_holes()
	if not MatchLogic.has_possible_move(_snapshot(), GRID_W, GRID_H):
		_reshuffle()


## 兑底：可玩格若有空洞立即补齐（并避免补出即时三连），保证棋盘永远完整
func _repair_holes() -> void:
	var filled := 0
	for x in range(GRID_W):
		for y in range(GRID_H):
			if _blocks.has(Vector2i(x, y)) or _tiles[x][y] != null:
				continue
			var tile := _spawn_tile(Vector2i(x, y), _rng.randi_range(0, _flower_types - 1), 0)
			_tiles[x][y] = tile
			var guard := 0
			while guard < 32 and not MatchLogic.find_matches(_snapshot(), GRID_W, GRID_H).is_empty():
				tile.set_flower(_rng.randi_range(0, _flower_types - 1))
				guard += 1
			filled += 1
	if filled > 0:
		print("[self-heal] 补洞 ", filled, " 格")


## 屏幕轻震（行/列轰炸、爆炸、魔力花时；幅度克制，不影响点控）
func _shake(strength: float) -> void:
	if strength <= 0.0:
		return
	var base := position
	var tween := create_tween()
	for i in range(3):
		tween.tween_property(self, "position",
			base + Vector2(randf_range(-strength, strength), randf_range(-strength, strength)), 0.05)
	tween.tween_property(self, "position", base, 0.06)


## 棋盘中心坐标（提示浮字/音效定位用）
func _board_center() -> Vector2:
	return _origin + Vector2(GRID_W, GRID_H) * _tile_size * 0.5


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
				Sfx.play_line(cell_to_world(c), false)
				_shake(6.0)
			Tile.Special.LINE_V:
				for y in range(GRID_H):
					extra.append(Vector2i(c.x, y))
				Sfx.play_line(cell_to_world(c), true)
				_shake(6.0)
			Tile.Special.BOMB:
				extra.append_array(MatchLogic.area_cells(c, GRID_W, GRID_H, 1))
				Sfx.play_boom(cell_to_world(c))
				_shake(10.0)
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


## 连击鼓励语（越连越夸张，配上升调音效）
func _combo_callout(combo: int) -> String:
	var words := ["太棒了！", "厉害！", "无敌了！", "花开满园！"]
	return words[mini(combo - 3, words.size() - 1)]


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


## 重力：障碍把每列切成若干段，**每段独立下落并补齐**
## （旧版只补「列顶段」→ 藤蔓/雪块之间的段消掉后永久留洞，玩家会觉得棋盘空空/无解）
func _apply_gravity() -> void:
	var last_tween: Tween = null
	for x in range(GRID_W):
		for seg in _column_segments(x):
			var top: int = seg[0]
			var bottom: int = seg[1]
			var write := bottom
			for y in range(bottom, top - 1, -1):
				var tile: Tile = _tiles[x][y]
				if tile == null:
					continue
				if y != write:
					_tiles[x][write] = tile
					_tiles[x][y] = null
					tile.cell = Vector2i(x, write)
					last_tween = tile.move_to(cell_to_world(tile.cell))
				write -= 1
			var fall := write - top + 1
			for y in range(write, top - 1, -1):
				var type := _rng.randi_range(0, _flower_types - 1)
				var tile := _spawn_tile(Vector2i(x, y), type, fall)
				_tiles[x][y] = tile  # 关键：新棋子必须注册进网格，否则不可交互/不参与匹配
				last_tween = tile.move_to(cell_to_world(tile.cell))
	if last_tween != null:
		await last_tween.finished


## 把一列按障碍切成若干可玩段：返回 [[top, bottom], ...]（障碍格不属于任何段）
func _column_segments(x: int) -> Array:
	var segs: Array = []
	var start := 0
	for y in range(GRID_H + 1):
		if y == GRID_H or _blocks.has(Vector2i(x, y)):
			if y > start:
				segs.append([start, y - 1])
			start = y + 1
	return segs


## 无可行步时重排：保留特殊花与障碍，重新着色其余棋子并保证重排后有解；
## 带提示浮字 + 音效 + 全盘脉冲（借鉴同类游戏的「重排」反馈，不静默发生）
func _reshuffle() -> void:
	var keep: Dictionary = {}
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile != null and tile.special != Tile.Special.NONE:
				keep[Vector2i(x, y)] = true  # 特殊花保留（玩家的资产不能被重排吃掉）
	var types := MatchLogic.reshuffle_grid(_snapshot(), GRID_W, GRID_H,
		_flower_types, _rng, keep)
	for x in range(GRID_W):
		for y in range(GRID_H):
			var tile: Tile = _tiles[x][y]
			if tile == null or tile.special != Tile.Special.NONE:
				continue  # 障碍格与特殊花保持原样
			tile.set_flower(types[y * GRID_W + x])
			tile.pulse()
	Sfx.play_reshuffle(_board_center())
	_spawn_float_text(_board_center() + Vector2(0.0, -60.0), "无可消除，重新排列！",
		Color(0.98, 0.72, 0.15), 50)
