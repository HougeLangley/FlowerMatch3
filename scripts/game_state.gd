extends Node

## 全局状态（Autoload）：关卡进度、星级、最高分持久化

const LEVELS: Array[Dictionary] = [
	{"target": 1200, "moves": 20, "flowers": 6, "theme": 0, "vines": [], "snow": []},
	{"target": 1800, "moves": 24, "flowers": 6, "theme": 1,
		"vines": [[1, 3], [5, 3], [1, 7], [5, 7]], "snow": []},
	{"target": 2400, "moves": 26, "flowers": 6, "theme": 0, "vines": [],
		"snow": [[2, 1], [4, 1], [2, 2], [4, 2], [3, 3], [2, 5], [4, 5], [3, 6]]},
	{"target": 2300, "moves": 30, "flowers": 6, "theme": 1,
		"vines": [[0, 0], [1, 0], [3, 0], [5, 0], [6, 0], [0, 1], [6, 1],
			[0, 9], [0, 10], [6, 9], [6, 10]],
		"snow": [[3, 2], [3, 3], [2, 4], [4, 4], [3, 5]]},
	{"target": 5200, "moves": 30, "flowers": 5, "theme": 0,
		"vines": [[0, 5], [6, 5]],
		"snow": [[1, 2], [5, 2], [2, 4], [4, 4], [1, 7], [5, 7], [3, 9]]},
]
const SAVE_PATH := "user://save.cfg"

var current_level := 1
var unlocked := 1
var stars: Dictionary = {}  # 关卡号(int) -> 星级(int 0..3)
var best: Dictionary = {}   # 关卡号(int) -> 最高分(int)
var muted := false          # 静音设置（持久化）


func _ready() -> void:
	load_data()
	apply_muted()


## 静音开关（全局 Master 总线，含开场视频音频）
func set_muted(value: bool) -> void:
	muted = value
	apply_muted()
	save_data()


func apply_muted() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)


## 星级门槛：1★=目标分，2★=1.35×，3★=1.75×（配玩满步数的结算规则）
static func star_thresholds(target: int) -> Array[int]:
	return [target, int(target * 1.35), int(target * 1.75)]


static func star_rating(target: int, score: int) -> int:
	var t := star_thresholds(target)
	if score >= t[2]:
		return 3
	if score >= t[1]:
		return 2
	if score >= t[0]:
		return 1
	return 0


## 记录一局成绩，返回本次星级；达星即解锁下一关
func record_result(level: int, score: int) -> int:
	var rating := star_rating(LEVELS[level - 1]["target"], score)
	best[level] = maxi(int(best.get(level, 0)), score)
	if rating > 0:
		stars[level] = maxi(int(stars.get(level, 0)), rating)
		if level == unlocked and unlocked < LEVELS.size():
			unlocked += 1
	save_data()
	return rating


func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	unlocked = int(cfg.get_value("progress", "unlocked", 1))
	muted = bool(cfg.get_value("settings", "muted", false))
	if cfg.has_section("stars"):
		for k in cfg.get_section_keys("stars"):
			stars[int(k)] = int(cfg.get_value("stars", k, 0))
	if cfg.has_section("best"):
		for k in cfg.get_section_keys("best"):
			best[int(k)] = int(cfg.get_value("best", k, 0))


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	cfg.set_value("settings", "muted", muted)
	for lv in stars.keys():
		cfg.set_value("stars", str(lv), stars[lv])
	for lv in best.keys():
		cfg.set_value("best", str(lv), best[lv])
	cfg.save(SAVE_PATH)
