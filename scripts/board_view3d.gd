class_name BoardView3D
extends Node

## 伪 3D 棋盘视图（不引入 3D 渲染管线，架构风险最小）：
##   棋盘 → SubViewport（透明背景，尺寸与主视口一致 → 布局数学不变）
##        → 全屏 TextureRect + 单应矩阵透视形变（board_warp.gdshader）
##   入场时从斜视角旋转归位，平时轻微浮动；触摸用同一矩阵反算回棋盘坐标
## 数学部分为静态函数，可无头单元测试（投影/反投影往返一致）

const SHADER_PATH := "res://shaders/board_warp.gdshader"
const FOCAL := 1.45         # 焦距（以棋盘半宽为单位，越小透视越强）
const ENTER_TIME := 1.5     # 入场旋转时长（秒）
const ENTER_YAW := 0.42     # 入场偏航角（约 24°）
const ENTER_PITCH := -0.30  # 入场俯仰角（约 -17°）
const SWAY_YAW := 0.065     # 常态浮动幅度
const SWAY_PITCH := 0.028
const SWAY_PERIOD := 7.5

var _board: Node2D
var _sub: SubViewport
var _rect: TextureRect
var _shader_mat: ShaderMaterial
var _size := Vector2(720.0, 1565.0)
var _inv: Array = []          # 3×3 单应逆矩阵（屏幕 UV → 棋盘 UV）
var _time := 0.0
var _pointer_down := false
var _active := false


## 接管棋盘：搬进 SubViewport，并挂上形变显示层 + 输入代理
func setup(board: Node2D, host: Node, view_size: Vector2) -> void:
	_board = board
	_size = view_size
	var board_index := board.get_index()
	# 1) 棋盘搬进 SubViewport（透明背景，尺寸与主视口一致）
	_sub = SubViewport.new()
	_sub.name = "BoardSubViewport"
	_sub.size = Vector2i(view_size)
	_sub.transparent_bg = true
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	board.get_parent().remove_child(board)
	_sub.add_child(board)
	host.add_child(_sub)
	# 2) 全屏显示层（插在棋盘原来的绘制位置：背景之上、结算遮罩之下）
	_rect = TextureRect.new()
	_rect.name = "BoardWarp"
	_rect.texture = _sub.get_texture()
	_rect.size = view_size
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shader_mat = ShaderMaterial.new()
	_shader_mat.shader = load(SHADER_PATH)
	_rect.material = _shader_mat
	host.add_child(_rect)
	host.move_child(_rect, board_index)
	# 3) 棋盘不再自己收输入（由本节点映射后转发）
	board.set_process_unhandled_input(false)
	_active = true
	_inv = mat3_inv(make_homography(ENTER_YAW, ENTER_PITCH, view_size.y / view_size.x, FOCAL))
	_apply_matrix(1.0)
	set_process(true)
	set_process_input(true)


func _process(delta: float) -> void:
	if not _active:
		return
	_time += delta
	# 入场旋转：斜视角 → 正对（带缓动），随后常态轻微浮动
	var t := clampf(_time / ENTER_TIME, 0.0, 1.0)
	var e: float = ease(t, 0.32)
	var sway_y := sin(_time * TAU / SWAY_PERIOD) * SWAY_YAW * e
	var sway_p := sin(_time * TAU / (SWAY_PERIOD * 1.37) + 1.1) * SWAY_PITCH * e
	var yaw := lerpf(ENTER_YAW, 0.0, e) + sway_y
	var pitch := lerpf(ENTER_PITCH, 0.0, e) + sway_p
	var aspect := _size.y / _size.x
	_inv = mat3_inv(make_homography(yaw, pitch, aspect, FOCAL))
	_apply_matrix(clampf(absf(yaw) / ENTER_YAW + absf(pitch) / absf(ENTER_PITCH), 0.0, 1.0))


func _apply_matrix(depth: float) -> void:
	if _shader_mat == null:
		return
	_shader_mat.set_shader_parameter("inv_matrix", mat3_to_basis(_inv))
	_shader_mat.set_shader_parameter("depth_shade", depth)


## 输入代理：只接管棋盘区域内的触摸，按同一矩阵反算后转交 Board
## （棋盘已在 SubViewport 内，不会重复收到主视口输入）
func _input(event: InputEvent) -> void:
	if not _active:
		return
	var pos := Vector2.ZERO
	var pressed := false
	var released := false
	var dragging := false
	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventScreenDrag:
		if event.index != 0:
			return
		pos = event.position
		dragging = true
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pos = event.position
		pressed = event.pressed
		released = not event.pressed
	elif event is InputEventMouseMotion and _pointer_down:
		pos = event.position
		dragging = true
	else:
		return
	if pressed and not _inside_board(unproject(pos)):
		return  # 棋盘外（顶部 HUD / 结算按钮）放行，交给 UI
	get_viewport().set_input_as_handled()
	handle_touch(pos, pressed, dragging, released)


## 把屏幕触摸按形变矩阵反算后转发给 Board（独立方法便于无头测试）
func handle_touch(screen_pos: Vector2, pressed: bool, dragging: bool, released: bool) -> void:
	if _board == null:
		return
	var board_pos := unproject(screen_pos)
	if pressed:
		_pointer_down = true
		_board._begin_pointer(board_pos)
	elif dragging:
		_board._update_drag(board_pos)
	elif released:
		_pointer_down = false
		_board._end_pointer()


## 棋盘像素坐标 → 屏幕像素坐标（正投影；供测试与特效定位使用）
func project(board_pos: Vector2) -> Vector2:
	if _inv.is_empty():
		return board_pos
	var fwd: Array = mat3_inv(_inv)
	var uv := Vector2(board_pos.x / _size.x, board_pos.y / _size.y)
	return mat3_apply(fwd, uv) * _size


## 屏幕坐标 → 棋盘坐标（像素空间，棋盘左上为原点）
func unproject(screen_pos: Vector2) -> Vector2:
	if _inv.is_empty():
		return screen_pos
	var uv := Vector2(screen_pos.x / _size.x, screen_pos.y / _size.y)
	var board_uv := mat3_apply(_inv, uv)
	return board_uv * _size


func _inside_board(board_pos: Vector2) -> bool:
	if _board != null and _board.has_method("board_rect"):
		return _board.board_rect().has_point(board_pos)
	var margin := _size.x * 0.06
	return board_pos.x > -margin * 2.0 and board_pos.x < _size.x + margin * 2.0 \
		and board_pos.y > -margin and board_pos.y < _size.y + margin


# ============ 单应矩阵数学（静态，可单测） ============

## 由 yaw/pitch 生成单应矩阵（棋盘 UV → 屏幕 UV），3×3 行主序
static func make_homography(yaw: float, pitch: float, aspect: float, focal: float) -> Array:
	var basis := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	var b0 := basis.x
	var b1 := basis.y
	# 平面点 p=(x,y,0) → 旋转后 q = b0*x + b1*y → 透视投影（焦距 focal）
	var proj := [
		b0.x, b1.x, 0.0,
		b0.y, b1.y, 0.0,
		-b0.z / focal, -b1.z / focal, 1.0,
	]
	# 棋盘 UV → 单位坐标（半宽=1，各向同性）
	var to_unit := [2.0, 0.0, -1.0, 0.0, 2.0 * aspect, -aspect, 0.0, 0.0, 1.0]
	# 单位坐标 → 屏幕 UV
	var to_uv := [0.5, 0.0, 0.5, 0.0, 0.5 / aspect, 0.5, 0.0, 0.0, 1.0]
	return mat3_mul(to_uv, mat3_mul(proj, to_unit))


static func mat3_mul(a: Array, b: Array) -> Array:
	var out := []
	out.resize(9)
	for r in range(3):
		for c in range(3):
			var s := 0.0
			for k in range(3):
				s += float(a[r * 3 + k]) * float(b[k * 3 + c])
			out[r * 3 + c] = s
	return out


static func mat3_inv(m: Array) -> Array:
	var a := float(m[0]); var b := float(m[1]); var c := float(m[2])
	var d := float(m[3]); var e := float(m[4]); var f := float(m[5])
	var g := float(m[6]); var h := float(m[7]); var i := float(m[8])
	var det := a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
	if absf(det) < 1e-9:
		return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]
	var inv_det := 1.0 / det
	return [
		(e * i - f * h) * inv_det, (c * h - b * i) * inv_det, (b * f - c * e) * inv_det,
		(f * g - d * i) * inv_det, (a * i - c * g) * inv_det, (c * d - a * f) * inv_det,
		(d * h - e * g) * inv_det, (b * g - a * h) * inv_det, (a * e - b * d) * inv_det,
	]


## 应用单应矩阵（含透视除法）
static func mat3_apply(m: Array, p: Vector2) -> Vector2:
	var x := float(m[0]) * p.x + float(m[1]) * p.y + float(m[2])
	var y := float(m[3]) * p.x + float(m[4]) * p.y + float(m[5])
	var w := float(m[6]) * p.x + float(m[7]) * p.y + float(m[8])
	if absf(w) < 1e-9:
		return p
	return Vector2(x / w, y / w)


## 行主序 3×3 → Basis（列为矩阵的列向量，供 shader mat3 使用）
static func mat3_to_basis(m: Array) -> Basis:
	return Basis(
		Vector3(float(m[0]), float(m[3]), float(m[6])),
		Vector3(float(m[1]), float(m[4]), float(m[7])),
		Vector3(float(m[2]), float(m[5]), float(m[8])))
