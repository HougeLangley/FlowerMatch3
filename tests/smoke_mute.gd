extends Node

## 冒烟测试（场景模式）：静音按钮
## 1) 按钮存在且为切换式
## 2) 点击（切换）→ Master 总线静音 + GameState.muted 记录
## 3) 再切换 → 恢复；测试后还原玩家原设置
## 运行：godot --headless --path . tests/smoke_mute.tscn

var _main: Control = null
var _frame := 0
var _failed := false
var _snap_muted := false


func _ready() -> void:
	_snap_muted = GameState.muted
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30:
		_run()


func _run() -> void:
	var btn := _main.get_node("%MuteButton") as TextureButton
	var ok: bool = btn != null and btn.toggle_mode
	print("PASS: 静音按钮存在且为切换式" if ok else "FAIL: 按钮缺失")
	_assert(ok)
	if btn == null:
		_finish()
		return
	GameState.set_muted(false)   # 归一到已知状态
	btn.button_pressed = false
	var bus := AudioServer.get_bus_index("Master")
	btn.button_pressed = true    # 触发 toggled → 应经 main 的接线真正静音
	var ok2: bool = AudioServer.is_bus_mute(bus) and GameState.muted
	print("PASS: 切换后总线静音" if ok2 else "FAIL: 静音未生效")
	_assert(ok2)
	btn.button_pressed = false   # 再切换 → 恢复
	var ok3: bool = not AudioServer.is_bus_mute(bus) and not GameState.muted
	print("PASS: 再切换后恢复有声" if ok3 else "FAIL: 未恢复")
	_assert(ok3)
	_finish()


func _finish() -> void:
	GameState.set_muted(_snap_muted)  # 还原玩家原设置
	get_tree().quit(1 if _failed else 0)


func _assert(cond: bool) -> void:
	if not cond:
		_failed = true
		printerr("ASSERT FAILED")
