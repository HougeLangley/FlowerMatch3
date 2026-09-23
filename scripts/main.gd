extends Control

## 主界面：关卡状态（步数/目标/星级/最高分）、结算弹窗、重开/返回选关

const STAR_GOLD := preload("res://assets/star_gold.png")
const STAR_GRAY := preload("res://assets/star_gray.png")
const UI_FONT := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const BG_PATHS: Array[String] = [
	"res://assets/video/bg_garden.ogv",   # 0 晴日花园
	"res://assets/video/bg_sakura.ogv",   # 1 樱花飘落
	"res://assets/video/bg_starry.ogv",   # 2 星空花海
	"res://assets/video/bg_butterfly.ogv", # 3 蝴蝶谷
	"res://assets/video/bg_cloud.ogv",     # 4 云端仙境
	"res://assets/video/bg_moon.ogv",      # 5 月夜花园
]

@onready var _score_label: Label = %ScoreLabel
@onready var _info_label: Label = %InfoLabel
@onready var _debug_label: Label = %DebugLabel
@onready var _board: Board = %Board
@onready var _overlay: Control = %ResultOverlay
@onready var _result_label: Label = %ResultLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _stars_box: HBoxContainer = %StarsBox
@onready var _live_stars: HBoxContainer = %LiveStars
@onready var _restart_button: Button = %RestartButton
@onready var _levels_button: Button = %LevelsButton
@onready var _bg_video: VideoStreamPlayer = %BgVideo
@onready var _mute_button: TextureButton = %MuteButton

var _level := 1
var _target := 0
var _score := 0
var _moves_left := 0
var _over := false
var _view3d: BoardView3D = null


func _ready() -> void:
	_level = GameState.current_level
	var cfg: Dictionary = GameState.LEVELS[_level - 1]
	_target = cfg["target"]
	_moves_left = cfg["moves"]
	_apply_bg_video(int(cfg.get("theme", 0)))
	_board.score_changed.connect(_on_score_changed)
	_board.move_made.connect(_on_move_made)
	_board.input_received.connect(_on_input_received)
	_board.debug_state.connect(_on_debug_state)
	_restart_button.pressed.connect(_on_restart_pressed)
	_levels_button.pressed.connect(_on_levels_pressed)
	_mute_button.button_pressed = GameState.muted  # 先同步状态再连信号，避免初始化触发
	_mute_button.toggled.connect(_on_mute_toggled)
	_update_ui()
	_show_intro_banner()  # 关卡开场横幅（仪式感）
	if bool(cfg.get("view3d", false)):
		_setup_3d_view()  # 3D 风格棋盘（透视形变 + 入场旋转）


## 3D 风格棋盘：把棋盘搬进 SubViewport，用单应矩阵形变显示（见 BoardView3D）
func _setup_3d_view() -> void:
	_view3d = BoardView3D.new()
	_view3d.name = "BoardView3D"
	add_child(_view3d)
	_view3d.setup(_board, self, get_viewport_rect().size)


## 关卡开场横幅：第 N 关 + 关卡名（仪式感与成就感）
func _show_intro_banner() -> void:
	Sfx.play_star(2)
	_popup_text("第 %d 关\n%s" % [_level, GameState.level_name(_level)],
		Color(0.22, 0.42, 0.3), 68, 0.33, 1.3)


## 居中弹出文字（淡入 + 轻微上浮 → 停留 → 淡出）
func _popup_text(text: String, color: Color, font_size: int, y_ratio: float, hold_sec: float) -> void:
	var label := Label.new()
	label.text = text
	var view := get_viewport_rect().size
	label.size = Vector2(view.x, font_size * 2.6)
	label.position = Vector2(0.0, view.y * y_ratio)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.95))
	label.add_theme_constant_override("outline_size", 14)
	label.z_index = 20
	label.modulate.a = 0.0
	var target_y := label.position.y
	label.position.y += 36.0
	add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "modulate:a", 1.0, 0.3)
	tween.parallel().tween_property(label, "position:y", target_y, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_sec)
	tween.tween_property(label, "modulate:a", 0.0, 0.45)
	tween.tween_callback(label.queue_free)


func _on_score_changed(new_score: int) -> void:
	_score = new_score
	_update_ui()


func _on_move_made() -> void:
	_moves_left -= 1
	_update_ui()
	if _moves_left == 5:
		# 最后 5 步紧张感（爽感：制造“拼一把”的心跳）
		_popup_text("还剩 5 步！加油！", Color(0.95, 0.45, 0.25), 52, 0.3, 1.2)
		Sfx.play_hint(Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y * 0.5))
	# 提前打到三星线 → 完美收官；否则玩满步数后按最终得分结算
	if _score >= GameState.star_thresholds(_target)[2]:
		_end_game(true)
	elif _moves_left <= 0:
		_end_game(_score >= _target)


func _end_game(won: bool) -> void:
	if _over:
		return
	_over = true
	var rating := GameState.record_result(_level, _score)
	_result_label.text = "过关啦！" if won else "还差一点～"
	var detail := "得分 %d ｜ 目标 %d ｜ 最高 %d" % [
		_score, _target, int(GameState.best.get(_level, 0))]
	if rating < 3:
		detail += "\n还差 %d 分升到 %d 星" % [
			GameState.star_thresholds(_target)[rating] - _score, rating + 1]
	_detail_label.text = detail
	var shown := rating if won else 0
	for i in range(_stars_box.get_child_count()):
		var tr := _stars_box.get_child(i) as TextureRect
		if tr != null:
			tr.texture = STAR_GRAY  # 先全灰，过关星星稍后逐颗点亮
	_overlay.visible = true
	if won:
		Sfx.play_win()
		_schedule_star_reveal(shown)
	else:
		Sfx.play_lose()


## 结算星星逐颗点亮（Tween 绑定节点：重开换场景时自动回收，无残留回调）
func _schedule_star_reveal(count: int) -> void:
	var tween := create_tween()
	tween.tween_interval(0.35)  # 先让结算卡片呈现
	for i in range(count):
		tween.tween_callback(_reveal_star.bind(i))
		tween.tween_interval(0.26)


func _reveal_star(index: int) -> void:
	var tr := _stars_box.get_child(index) as TextureRect
	if tr == null:
		return
	tr.texture = STAR_GOLD
	tr.pivot_offset = tr.size * 0.5
	tr.scale = Vector2(0.5, 0.5)
	var tween := tr.create_tween()
	tween.tween_property(tr, "scale", Vector2.ONE, 0.24) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_restart_pressed() -> void:
	get_tree().reload_current_scene()


func _on_mute_toggled(enabled: bool) -> void:
	GameState.set_muted(enabled)


## 根据关卡主题播放循环背景视频（缺失时静退：保留静态背景图）
func _apply_bg_video(theme: int) -> void:
	var path: String = BG_PATHS[theme % BG_PATHS.size()]
	if ResourceLoader.exists(path):
		_bg_video.stream = load(path)
		_bg_video.play()


func _on_levels_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/level_select.tscn")


## 系统返回（侧滑手势/返回键）→ 回选关，而不是退出应用
## （配合 project.godot 的 application/config/quit_on_go_back=false）
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_levels_pressed()


func _update_ui() -> void:
	_score_label.text = "分数: %d" % _score
	_info_label.text = "第%d关 %s ｜ %d 步 ｜ 目标 %d" % [
		_level, GameState.level_name(_level), _moves_left, _target]
	_info_label.add_theme_color_override("font_color",
		Color(0.86, 0.34, 0.24) if _moves_left <= 5 else Color(0.32, 0.4, 0.34))
	_update_live_stars()


## 右上角实时星级：随分数跨过门槛逐颗点亮
func _update_live_stars() -> void:
	var thresholds := GameState.star_thresholds(_target)
	for i in range(_live_stars.get_child_count()):
		var tr := _live_stars.get_child(i) as TextureRect
		if tr == null:
			continue
		if _score >= thresholds[i]:
			if tr.texture != STAR_GOLD:
				tr.texture = STAR_GOLD
				Sfx.play_star(i)  # 实时跨过门槛：清脆的“叮”，由低到高
		else:
			tr.texture = STAR_GRAY


func _on_debug_state(text: String) -> void:
	_debug_label.text = text


func _on_input_received(_pos: Vector2, _cell: Vector2i) -> void:
	pass  # 保留信号用于调试扩展
