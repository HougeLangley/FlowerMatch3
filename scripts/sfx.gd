extends Node

## 音效管理器（autoload：Sfx）
## - 多声部池：同一音效连发不互相打断（连续消除/连锁爆炸可叠加）
## - 五声音阶音高阶梯：连锁逐级升高，音乐性强于等差机械升调
## - 随机变体与微扰：每次播放略有不同，避免复读机感
## - 位置声场：按棋盘格子位置左右声像 + 距离衰减，声音"发生在那格"

const SOUND_DIR := "res://assets/sounds/"

# 五声音阶音高阶梯（C D E G A），连锁 combo 1..5+ 逐级升高
const POP_LADDER: Array[float] = [1.0, 1.125, 1.25, 1.5, 1.667]
# 实时星星逐颗点亮的音高阶梯
const STAR_LADDER: Array[float] = [1.0, 1.122, 1.26]
# 每关的调性（转调）：让每一关的消除音听起来都不一样（爽感：关卡个性）
const KEY_LADDER: Array[float] = [1.0, 1.122, 1.189, 0.891, 1.06, 0.943, 1.26, 0.841]

var _pools: Dictionary = {}      # 名称 -> {players: Array, next: int, rot: int}
var _variants: Dictionary = {}   # 名称 -> Array[AudioStream]
var _listener: AudioListener2D
var _transpose := 1.0


func _ready() -> void:
	# 听者放在屏幕中心 → 棋盘左右分布声像（Board 中心 x 与屏幕中心一致）
	var view := get_viewport().get_visible_rect().size
	_listener = AudioListener2D.new()
	_listener.position = Vector2(view.x * 0.5, view.y * 0.55)
	add_child(_listener)
	_listener.make_current()
	# 池容量按"同一瞬间最多可能响几个"设定
	_add_pool("select", ["select"], 2)
	_add_pool("swap", ["swap"], 3)
	_add_pool("invalid", ["invalid"], 2)
	_add_pool("pop", ["pop_a", "pop_b", "pop_c"], 6)
	_add_pool("special", ["special"], 4)
	_add_pool("line", ["line"], 3)
	_add_pool("boom", ["boom"], 3)
	_add_pool("magic", ["magic"], 2)
	_add_pool("break", ["break"], 3)
	_add_pool("shuffle", ["shuffle"], 2)
	_add_pool("hint", ["hint"], 2)
	_add_pool("star", ["star"], 2)
	_add_pool("win", ["win"], 1)
	_add_pool("lose", ["lose"], 1)


func _add_pool(name: String, files: Array, voices: int) -> void:
	var streams: Array[AudioStream] = []
	for f in files:
		streams.append(load(SOUND_DIR + str(f) + ".wav"))
	_variants[name] = streams
	var players: Array[AudioStreamPlayer2D] = []
	for i in range(voices):
		var p := AudioStreamPlayer2D.new()
		p.panning_strength = 0.6   # 声像幅度（整板宽度内左右分明但不夸张）
		p.max_distance = 2400.0
		p.attenuation = 0.4        # 由远及近的轻微音量差
		add_child(p)
		players.append(p)
	_pools[name] = {"players": players, "next": 0, "rot": 0}


## 内部：取一个空闲声部播放（轮转）；变体流依次轮换，音高由调用方决定
func _emit(sound: String, pitch: float, pos: Vector2) -> void:
	var pool: Dictionary = _pools.get(sound, {})
	if pool.is_empty():
		return
	var players: Array = pool["players"]
	var idx: int = int(pool["next"])
	pool["next"] = (idx + 1) % players.size()
	var player: AudioStreamPlayer2D = players[idx]
	var streams: Array = _variants[sound]
	var vi := 0
	if streams.size() > 1:
		vi = int(pool["rot"]) % streams.size()
		pool["rot"] = int(pool["rot"]) + 1
	player.stream = streams[vi]
	player.pitch_scale = pitch
	player.position = pos
	player.play()


# ============ 游戏侧调用 API ============

## 设置当前关卡的调性（由 Board 在开局时调用）
func set_level_index(level: int) -> void:
	_transpose = KEY_LADDER[(maxi(level, 1) - 1) % KEY_LADDER.size()]


func play_select(pos: Vector2) -> void:
	_emit("select", randf_range(0.98, 1.05), pos)


## 纵向交换音高略高（同色系里区分方向的手感）
func play_swap(pos: Vector2, vertical: bool) -> void:
	_emit("swap", (1.14 if vertical else 1.0) * randf_range(0.98, 1.03), pos)


func play_invalid(pos: Vector2) -> void:
	_emit("invalid", randf_range(0.98, 1.02), pos)


## 连消：combo 沿五声音阶爬升 + 每次微扰
func play_pop(combo: int, pos: Vector2) -> void:
	var step: int = clampi(combo - 1, 0, POP_LADDER.size() - 1)
	_emit("pop", minf(POP_LADDER[step] * _transpose, 2.2) * randf_range(0.985, 1.015), pos)


## 特殊花生成：同一拍多颗时音高轻微错开
func play_special(pos: Vector2) -> void:
	_emit("special", randf_range(0.94, 1.06) * _transpose, pos)


func play_line(pos: Vector2, vertical: bool) -> void:
	_emit("line", (1.12 if vertical else 1.0) * _transpose * randf_range(0.98, 1.02), pos)


func play_boom(pos: Vector2) -> void:
	_emit("boom", randf_range(0.96, 1.04) * _transpose, pos)


func play_magic(pos: Vector2) -> void:
	_emit("magic", 1.0, pos)


func play_break(pos: Vector2) -> void:
	_emit("break", randf_range(0.92, 1.08), pos)


func play_reshuffle(pos: Vector2) -> void:
	_emit("shuffle", randf_range(0.98, 1.02), pos)


func play_hint(pos: Vector2) -> void:
	_emit("hint", randf_range(0.99, 1.01), pos)


func play_star(index: int) -> void:
	_emit("star", STAR_LADDER[clampi(index, 0, STAR_LADDER.size() - 1)], _screen_center())


func play_win() -> void:
	_emit("win", 1.0, _screen_center())


func play_lose() -> void:
	_emit("lose", 1.0, _screen_center())


func _screen_center() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5
