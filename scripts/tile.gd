class_name Tile
extends Node2D

## 单个花朵棋子：外观、特殊形态（行/列消除、魔力花）、动画
## 输入由 Board._unhandled_input 统一处理（单一输入路径，避免 Area2D 双触发）
## 闲置动效：每种花不同律动，作用于 Sprite 子节点（棋子的 transform 留给移动/消除动画）

enum Special { NONE, LINE_H, LINE_V, BOMB, MAGIC }

const TEXTURES: Array[Texture2D] = [
	preload("res://assets/flowers/rose.png"),
	preload("res://assets/flowers/sunflower.png"),
	preload("res://assets/flowers/sakura.png"),
	preload("res://assets/flowers/tulip.png"),
	preload("res://assets/flowers/lavender.png"),
	preload("res://assets/flowers/lily.png"),
]
const MAGIC_TEXTURE := preload("res://assets/flowers/magic.png")
const BOMB_TEXTURE := preload("res://assets/flowers/bomb.png")
const BADGE_TEXTURE := preload("res://assets/badge.png")

const IDLE_WAVE_STEP := 0.13  # 按棋盘对角线错相位的波浪步长（秒）
const IDLE_KIND_MAGIC := 100  # 特殊形态的闲置动效编号
const IDLE_KIND_BOMB := 101

var cell: Vector2i
var flower_type: int = -1
var special: Special = Special.NONE

var _sprite: Sprite2D
var _badge: Sprite2D = null
var _base_scale := Vector2.ONE
var _idle: Tween = null


func setup(p_type: int, tile_size: float) -> void:
	flower_type = p_type
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURES[p_type]
	var tex_w := float(_sprite.texture.get_width())
	_base_scale = Vector2.ONE * (tile_size * 0.96 / tex_w)
	_sprite.scale = _base_scale
	add_child(_sprite)


func set_flower(p_type: int) -> void:
	flower_type = p_type
	if special != Special.MAGIC:
		_sprite.texture = TEXTURES[p_type]
	start_idle()


func set_special(sp: Special) -> void:
	special = sp
	match sp:
		Special.MAGIC:
			_sprite.texture = MAGIC_TEXTURE
			if _badge != null:
				_badge.visible = false
		Special.BOMB:
			_sprite.texture = BOMB_TEXTURE
			if _badge != null:
				_badge.visible = false
		Special.NONE:
			_sprite.texture = TEXTURES[flower_type]
			if _badge != null:
				_badge.visible = false
		_:
			if _badge == null:
				_badge = Sprite2D.new()
				_badge.texture = BADGE_TEXTURE
				_badge.scale = _base_scale  # 用基准缩放，避免复制到闲置动效中间态
				add_child(_badge)
			_badge.rotation = 0.0 if sp == Special.LINE_H else PI / 2.0
			_badge.visible = true
	start_idle()


## ============ 闲置动效：每种花不同律动 ============

## 启动（或重启）闲置动效；若有进行中的会先kill并复位
func start_idle() -> void:
	if _idle != null and _idle.is_valid():
		_idle.kill()
	_idle = null
	if _sprite == null:
		return
	_sprite.scale = _base_scale
	_sprite.rotation = 0.0
	_sprite.position = Vector2.ZERO
	_idle = create_tween().set_loops()
	var delay := float((cell.x + cell.y) % 7) * IDLE_WAVE_STEP + randf() * 0.06
	if delay > 0.01:
		_idle.tween_interval(delay)
	_build_idle_steps()


func _idle_kind() -> int:
	if special == Special.MAGIC:
		return IDLE_KIND_MAGIC
	if special == Special.BOMB:
		return IDLE_KIND_BOMB
	return flower_type


func _build_idle_steps() -> void:
	match _idle_kind():
		IDLE_KIND_MAGIC:  # 魔力花：缓缓整圈旋转
			_idle.tween_property(_sprite, "rotation", TAU, 6.0).from(0.0) \
				.set_trans(Tween.TRANS_LINEAR)
		IDLE_KIND_BOMB:  # 爆炸花：急促心跳（引信感）
			_idle.tween_property(_sprite, "scale", _base_scale * 1.07, 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.tween_property(_sprite, "scale", _base_scale, 0.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		0:  # 玫瑰：优雅摇曳
			_idle.tween_property(_sprite, "rotation", 0.05, 1.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.tween_property(_sprite, "rotation", -0.05, 1.6) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		1:  # 向日葵：饱满呼吸
			_idle.tween_property(_sprite, "scale", _base_scale * 1.07, 1.0) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.tween_property(_sprite, "scale", _base_scale, 1.0) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		2:  # 樱花：飘浮轻摆
			_idle.tween_property(_sprite, "position:y", -5.0, 1.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.parallel().tween_property(_sprite, "rotation", 0.045, 1.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.tween_property(_sprite, "position:y", 0.0, 1.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.parallel().tween_property(_sprite, "rotation", 0.0, 1.3) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		3:  # 郁金香：风中摆头
			_idle.tween_property(_sprite, "rotation", 0.07, 1.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.tween_property(_sprite, "rotation", -0.07, 1.4) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		4:  # 薰衣草：轻微飘动
			_idle.tween_property(_sprite, "rotation", 0.035, 1.8) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.tween_property(_sprite, "rotation", -0.035, 1.8) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		5:  # 百合：静谧呼吸
			_idle.tween_property(_sprite, "scale", _base_scale * 1.05, 1.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			_idle.tween_property(_sprite, "scale", _base_scale, 1.5) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


var _hint_tween: Tween = null


## 提示（找不到可行步时）：轻微高亮脉动两下；不干扰选中高亮
func hint_wiggle() -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
	modulate = Color.WHITE
	_hint_tween = create_tween()
	for i in range(2):
		_hint_tween.tween_property(self, "modulate", Color(1.32, 1.32, 1.32), 0.18)
		_hint_tween.tween_property(self, "modulate", Color.WHITE, 0.18)


func set_selected(value: bool) -> void:
	if _hint_tween != null and _hint_tween.is_valid():
		_hint_tween.kill()
		_hint_tween = null
		modulate = Color.WHITE
	modulate = Color(1.4, 1.4, 1.4) if value else Color.WHITE


func move_to(target: Vector2) -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", target, 0.22)
	return tween


## 生成特殊花时的提示动画（作用于棋子整体，与精灵闲置动效互不干扰）
func pulse() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 1.3, 0.12)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16)


func pop() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.18)
	tween.tween_callback(queue_free)
