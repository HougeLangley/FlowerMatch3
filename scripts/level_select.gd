extends Control

## 选关界面：关卡按钮 + 星级展示，未解锁置灰

const STAR_GOLD := preload("res://assets/star_gold.png")
const STAR_GRAY := preload("res://assets/star_gray.png")
const UI_FONT := preload("res://assets/fonts/ZCOOLKuaiLe-Regular.ttf")
const PETAL_NORMAL := preload("res://assets/petal_btn_normal.png")
const PETAL_PRESSED := preload("res://assets/petal_btn_pressed.png")
const PETAL_DISABLED := preload("res://assets/petal_btn_disabled.png")

@onready var _grid: GridContainer = %LevelGrid


func _ready() -> void:
	for i in range(GameState.LEVELS.size()):
		_grid.add_child(_make_level_cell(i + 1))


func _make_level_cell(level: int) -> Control:
	var cell := VBoxContainer.new()
	cell.alignment = BoxContainer.ALIGNMENT_CENTER
	cell.add_theme_constant_override("separation", 4)
	var locked := level > GameState.unlocked
	# 花瓣按钮
	var btn := TextureButton.new()
	btn.texture_normal = PETAL_NORMAL
	btn.texture_pressed = PETAL_PRESSED
	btn.texture_disabled = PETAL_DISABLED
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_SCALE
	btn.custom_minimum_size = Vector2(170, 170)
	btn.disabled = locked
	# 关卡数字（显示在花心）
	var label := Label.new()
	label.text = str(level)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_override("font", UI_FONT)
	label.add_theme_font_size_override("font_size", 68)
	label.add_theme_color_override("font_color",
		Color(0.62, 0.64, 0.6) if locked else Color(0.35, 0.3, 0.2))
	btn.add_child(label)
	if not locked:
		btn.pressed.connect(_on_level_pressed.bind(level))
	cell.add_child(btn)
	# 星级
	var stars_box := HBoxContainer.new()
	stars_box.alignment = BoxContainer.ALIGNMENT_CENTER
	var n: int = GameState.stars.get(level, 0)
	for s in range(3):
		var tr := TextureRect.new()
		tr.texture = STAR_GOLD if s < n else STAR_GRAY
		tr.custom_minimum_size = Vector2(42, 42)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stars_box.add_child(tr)
	cell.add_child(stars_box)
	return cell


func _on_level_pressed(level: int) -> void:
	GameState.current_level = level
	get_tree().change_scene_to_file("res://scenes/main.tscn")
