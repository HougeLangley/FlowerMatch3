extends Node

## 全局状态（Autoload）：关卡进度、星级、最高分持久化

const LEVELS: Array[Dictionary] = [
	{"target": 1200, "moves": 20},
	{"target": 2000, "moves": 22},
	{"target": 3200, "moves": 24},
	{"target": 4800, "moves": 26},
	{"target": 6500, "moves": 28},
]
const SAVE_PATH := "user://save.cfg"

var current_level := 1
var unlocked := 1
var stars: Dictionary = {}  # 关卡号(int) -> 星级(int 0..3)
var best: Dictionary = {}   # 关卡号(int) -> 最高分(int)


func _ready() -> void:
	load_data()


static func star_rating(target: int, score: int) -> int:
	if score >= int(target * 2.4):
		return 3
	if score >= int(target * 1.6):
		return 2
	if score >= target:
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
	if cfg.has_section("stars"):
		for k in cfg.get_section_keys("stars"):
			stars[int(k)] = int(cfg.get_value("stars", k, 0))
	if cfg.has_section("best"):
		for k in cfg.get_section_keys("best"):
			best[int(k)] = int(cfg.get_value("best", k, 0))


func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "unlocked", unlocked)
	for lv in stars.keys():
		cfg.set_value("stars", str(lv), stars[lv])
	for lv in best.keys():
		cfg.set_value("best", str(lv), best[lv])
	cfg.save(SAVE_PATH)
