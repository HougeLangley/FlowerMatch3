extends Node

## 全局状态（Autoload）：关卡进度、星级、最高分持久化

## 棋盘形状掩码：11 行 × 7 列，'#'=可玩格，'.'=虚空（无棋子、无障碍图，等同墙）
const SHAPES: Dictionary = {
	"rect": [
		"#######", "#######", "#######", "#######", "#######", "#######",
		"#######", "#######", "#######", "#######", "#######",
	],
	"heart": [
		".##.##.", "#######", "#######", "#######", "#######", "#######",
		".#####.", ".#####.", "..###..", "...#...", ".......",
	],
	"diamond": [
		"..###..", ".#####.", "#######", "#######", "#######", "#######",
		"#######", "#######", "#######", ".#####.", "..###..",
	],
	"butterfly": [
		"###.###", "#######", "#######", ".####..", "..###..", "..###..",
		".####..", "#######", "#######", "###.###", "##...##",
	],
	"star": [
		"..###..", "..###..", "#######", "#######", ".#####.", "..###..",
		".#####.", "#######", "#######", "..###..", "..###..",
	],
	"ring": [
		"#######", "#######", "#######", "##...##", "##...##", "##...##",
		"##...##", "##...##", "#######", "#######", "#######",
	],
	"island": [
		".#####.", "#######", "#######", "#######", "#######", "#######",
		"#######", "#######", "#######", "#######", ".#####.",
	],
	"crescent": [
		"..####.", ".#####.", "####...", "####...", "####...", "####...",
		"####...", "####...", "####...", ".#####.", "..####.",
	],
	"flower": [
		"..###..", ".#####.", "#######", "##...##", "##...##", "#.....#",
		"##...##", "##...##", "#######", ".#####.", "..###..",
	],
	"cross": [
		"..###..", "..###..", "#######", "#######", "#######", "#######",
		"#######", "#######", "#######", "..###..", "..###..",
	],
}

## 关卡表：name 显示名，shape 棋盘形状，vines 永久障碍，snow 可破障碍
## theme：0 晴日花园 / 1 樱花飘落 / 2 星空花海 / 3 蝴蝶谷 / 4 云端仙境 / 5 月夜花园
## view3d：true 时该关使用 3D 风格棋盘（透视形变 + 入场旋转）
const LEVELS: Array[Dictionary] = [
	{"name": "花园初遇", "target": 1200, "moves": 20, "flowers": 6, "theme": 0,
		"shape": "rect", "vines": [], "snow": []},
	{"name": "藤蔓缠绕", "target": 1800, "moves": 24, "flowers": 6, "theme": 1,
		"shape": "rect", "vines": [[1, 3], [5, 3], [1, 7], [5, 7]], "snow": []},
	{"name": "破雪开路", "target": 2400, "moves": 26, "flowers": 6, "theme": 0,
		"shape": "rect", "vines": [],
		"snow": [[2, 1], [4, 1], [2, 2], [4, 2], [3, 3], [2, 5], [4, 5], [3, 6]]},
	{"name": "心之花园", "target": 1700, "moves": 28, "flowers": 6, "theme": 1,
		"shape": "heart", "vines": [],
		"snow": [[3, 2], [3, 3], [2, 4], [4, 4], [3, 5]]},
	{"name": "五色盛宴", "target": 5200, "moves": 30, "flowers": 5, "theme": 0,
		"shape": "rect", "vines": [[0, 5], [6, 5]],
		"snow": [[1, 2], [5, 2], [2, 4], [4, 4], [1, 7], [5, 7], [3, 9]]},
	{"name": "钻石花园", "target": 1950, "moves": 26, "flowers": 6, "theme": 2,
		"shape": "diamond", "vines": [],
		"snow": [[3, 2], [3, 3], [3, 4], [2, 5], [4, 5], [3, 6]]},
	{"name": "蝴蝶之翼", "target": 2100, "moves": 28, "flowers": 5, "theme": 3,
		"shape": "butterfly", "vines": [[0, 2], [6, 2]],
		"snow": [[1, 0], [5, 0], [3, 7], [1, 9]]},
	{"name": "星之挑战", "target": 1400, "moves": 28, "flowers": 6, "theme": 2,
		"shape": "star", "vines": [[3, 0], [3, 10]],
		"snow": [[2, 4], [4, 4], [3, 5], [2, 6], [4, 6]]},
	{"name": "回环花径", "target": 1250, "moves": 30, "flowers": 5, "theme": 3,
		"shape": "ring", "vines": [[2, 0], [4, 0]],
		"snow": [[0, 5], [6, 5], [1, 8], [5, 8], [0, 3], [6, 7]]},
	{"name": "花冠盛放", "target": 2100, "moves": 32, "flowers": 6, "theme": 0,
		"shape": "cross", "vines": [[2, 0], [4, 0], [2, 10], [4, 10]],
		"snow": [[1, 3], [5, 3], [3, 5], [1, 7], [5, 7], [3, 8]]},
	{"name": "浮空花岛", "target": 2250, "moves": 28, "flowers": 6, "theme": 4,
		"shape": "island", "view3d": true, "vines": [],
		"snow": [[3, 2], [3, 3], [3, 4], [2, 6], [4, 6]]},
	{"name": "旋转花环", "target": 1450, "moves": 30, "flowers": 5, "theme": 3,
		"shape": "ring", "view3d": true, "vines": [[0, 5], [6, 5]],
		"snow": [[2, 1], [4, 1], [2, 8], [4, 8]]},
	{"name": "月牙秘境", "target": 1450, "moves": 30, "flowers": 6, "theme": 5,
		"shape": "crescent", "view3d": true, "vines": [],
		"snow": [[0, 4], [0, 5], [2, 7], [3, 3]]},
	{"name": "花瓣绽放", "target": 1200, "moves": 32, "flowers": 5, "theme": 4,
		"shape": "flower", "view3d": true, "vines": [[1, 2], [5, 2]],
		"snow": [[3, 0], [3, 10], [1, 8], [5, 8]]},
	{"name": "终极花园", "target": 2650, "moves": 34, "flowers": 6, "theme": 5,
		"shape": "cross", "view3d": true, "vines": [[0, 3], [6, 3], [0, 7], [6, 7]],
		"snow": [[3, 2], [3, 3], [3, 7], [3, 8], [1, 5], [5, 5]]},
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


## 关卡显示名（HUD 与选关界面用）
static func level_name(level: int) -> String:
	return String(LEVELS[level - 1].get("name", "第%d关" % level))


## 关卡棋盘形状掩码（11 行字符串数组，'#'=可玩）
static func shape_of(level: int) -> Array:
	var key := String(LEVELS[level - 1].get("shape", "rect"))
	return SHAPES.get(key, SHAPES["rect"])


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
