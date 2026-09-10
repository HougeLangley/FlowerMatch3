class_name Tile
extends Node2D

## 单个花朵棋子：外观、特殊形态（行/列消除、魔力花）、动画
## 输入由 Board._unhandled_input 统一处理（单一输入路径，避免 Area2D 双触发）

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

var cell: Vector2i
var flower_type: int = -1
var special: Special = Special.NONE

var _sprite: Sprite2D
var _badge: Sprite2D = null


func setup(p_type: int, tile_size: float) -> void:
	flower_type = p_type
	_sprite = Sprite2D.new()
	_sprite.texture = TEXTURES[p_type]
	var tex_w := float(_sprite.texture.get_width())
	_sprite.scale = Vector2.ONE * (tile_size * 0.96 / tex_w)
	add_child(_sprite)


func set_flower(p_type: int) -> void:
	flower_type = p_type
	if special != Special.MAGIC:
		_sprite.texture = TEXTURES[p_type]


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
				_badge.scale = _sprite.scale
				add_child(_badge)
			_badge.rotation = 0.0 if sp == Special.LINE_H else PI / 2.0
			_badge.visible = true


func set_selected(value: bool) -> void:
	modulate = Color(1.4, 1.4, 1.4) if value else Color.WHITE


func move_to(target: Vector2) -> Tween:
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "position", target, 0.22)
	return tween


## 生成特殊花时的提示动画
func pulse() -> void:
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2.ONE * 1.3, 0.12)
	tween.tween_property(self, "scale", Vector2.ONE, 0.16)


func pop() -> void:
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.18)
	tween.tween_callback(queue_free)
