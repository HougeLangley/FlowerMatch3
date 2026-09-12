extends Node

## 常驻断言器（挂在 /root，换场景不被释放）：由 smoke_back.gd 创建
## 依次验证：项目设置 → 游戏场景返回 → 开场场景返回

const MAIN := "res://scenes/main.tscn"
const LEVELS := "res://scenes/level_select.tscn"
const INTRO := "res://scenes/intro.tscn"

var _phase := 0
var _elapsed := 0.0
var _deadline := 0.0
var _failed := false


func _process(delta: float) -> void:
	_elapsed += delta
	if _phase == 0:
		_phase = 1
		_deadline = _elapsed + 0.6
	elif _phase == 1 and _elapsed >= _deadline:
		_check_setting()
		_try_back_on(MAIN, "游戏场景", 2)
	elif _phase == 2 and _elapsed >= _deadline:
		if _expect_scene(LEVELS, "游戏返回 → 选关界面"):
			get_tree().change_scene_to_file(INTRO)
			_phase = 3
			_deadline = _elapsed + 0.8
	elif _phase == 3 and _elapsed >= _deadline:
		_try_back_on(INTRO, "开场场景", 4)
	elif _phase == 4 and _elapsed >= _deadline:
		if _expect_scene(LEVELS, "开场返回 → 选关界面"):
			_finish()


func _check_setting() -> void:
	var v: bool = bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true))
	print("PASS: 已关闭返回键自动退出" if not v else "FAIL: quit_on_go_back 仍为 true")
	_assert(not v)


## 等目标场景就绪后，向它发送系统返回通知（与 Android 真实事件一致）
func _try_back_on(scene_path: String, label: String, next_phase: int) -> void:
	var cur := get_tree().current_scene
	if cur == null or cur.scene_file_path != scene_path:
		return  # 场景尚未就绪，下一帧再试
	cur.notification(NOTIFICATION_WM_GO_BACK_REQUEST)
	print("PASS: %s触发系统返回" % label)
	_phase = next_phase
	_deadline = _elapsed + 0.8


func _expect_scene(path: String, label: String) -> bool:
	var cur := get_tree().current_scene
	var ok: bool = cur != null and cur.scene_file_path == path
	print("PASS: %s" % label if ok
		else "FAIL: %s（当前场景 %s）" % [label, cur.scene_file_path if cur != null else "null"])
	_assert(ok)
	return ok


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")


func _finish() -> void:
	get_tree().quit(1 if _failed else 0)
