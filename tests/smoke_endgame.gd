extends Node

## 冒烟测试（场景模式）：实例化真实主场景并触发结算，覆盖 _end_game 路径
## 运行：godot --headless --path . tests/smoke_endgame.tscn

var _main: Control = null
var _frame := 0


func _ready() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	add_child(_main)


func _process(_delta: float) -> void:
	_frame += 1
	if _frame == 30 and _main != null:
		_main._end_game(true)
		var overlay := _main.get_node("%ResultOverlay") as Control
		var ok: bool = overlay != null and overlay.visible
		print("PASS: endgame overlay shown" if ok else "FAIL: overlay hidden")
		var stars := _main.get_node("%StarsBox")
		var ok2: bool = stars != null and stars.get_child_count() == 3
		print("PASS: 3 star slots" if ok2 else "FAIL: stars box")
		get_tree().quit(0 if ok and ok2 else 1)
