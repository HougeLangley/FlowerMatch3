extends Node

## 冒烟测试（场景模式）：系统返回导航
## 1) 未开启"返回键自动退出"（application/config/quit_on_go_back=false）
## 2) 游戏场景按返回 → 回选关界面（本次 bug 修复点）
## 3) 开场场景按返回 → 跳过开场进选关
## 运行：godot --headless --path . tests/smoke_back.tscn
##
## 结构说明：本节点是当前场景，会被换场景过程释放；
## 因此把断言逻辑放到常驻 root 的 Checker 子节点里执行。

func _ready() -> void:
	var checker := preload("res://tests/smoke_back_checker.gd").new()
	checker.name = "BackChecker"
	get_tree().root.add_child.call_deferred(checker)
	get_tree().change_scene_to_file.call_deferred("res://scenes/main.tscn")
