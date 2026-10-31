## 玩家：橫向卷軸操作，手感參考 2D 橫軸 MMO。
## ←→ 走（有一點加減速）、Alt／C／空白 跳、站在單向平台上 ↓＋跳 往下跳、
## 靠近繩子或梯子按 ↑↓ 爬，爬的時候 ←→＋跳 可以跳開。
## 身法（main 依學會的身法開關，見 scripts/cultivation.gd）：
## 輕身術 double_jump 空中再按跳；踏葉 wall_jump 空中貼牆按跳往反方向蹬；
## 御風 glide 下落時按住跳滑翔；土遁 earth_escape 穿過薄牆；御劍 sword_flight 空中按 K 飛一小段。
## 鏡頭往面向的方向多看一點、小跳不晃，站著按住 ↑／↓ 可以往上下看；受傷時輕震。
## 美術未到前用色塊。
extends CharacterBody2D

const SPEED := 260.0
const GROUND_ACCEL := 2600.0
const GROUND_DECEL := 3200.0
const AIR_ACCEL := 1500.0
const JUMP_VELOCITY := -660.0   # 約 120 像素高，平台每層間隔 100 左右
const DOUBLE_JUMP_VELOCITY := -600.0  # 再高約 100，合計約 220
const WALL_SLIDE := 120.0       # 貼牆下滑速度上限
const WALL_JUMP := Vector2(260, -600)
const WALL_JUMP_LOCK := 0.15    # 蹬牆後這段時間不吃左右輸入，免得馬上被拉回牆上
const GLIDE_FALL := 60.0        # 御風時的下落速度上限
const FLIGHT_SPEED := 320.0
const FLIGHT_TIME := 1.5
const GRAVITY := 1800.0
const MAX_FALL := 900.0
const CLIMB_SPEED := 170.0
const ROPE_JUMP := Vector2(220, -420)
const COYOTE_TIME := 0.1        # 走出平台邊緣後還能起跳的時間
const JUMP_BUFFER := 0.12       # 落地前一點按跳也算
const TURN_DECEL := 4200.0      # 地上轉身時煞得比較快，不會像溜冰
const FALL_GRAVITY := 1.15      # 下落比上升快一點，跳起來俐落不飄
const APEX_SPEED := 90.0        # 跳到頂點附近（上下速度小於這個）重力減半，留一點滯空感
const APEX_GRAVITY := 0.55
const HARD_LANDING := 750.0     # 落地速度超過這個，鏡頭輕震一下
## 鏡頭：往面向的方向多看一點；只在落地或爬繩時跟上高度，小跳不晃；
## 站著按住 ↑／↓ 一會兒可以往上／往下看。
const CAM_HEIGHT := 110.0       # 鏡頭中心在腳上方多高
const LOOK_AHEAD := 120.0
const LOOK_AHEAD_RATE := 2.2    # 前瞻跟上的速度（越大越快）
const CAM_Y_RATE := 5.0
const CAM_AIR_SLACK := 170.0    # 空中往上超過落腳處這麼多才開始跟
const LOOK_DELAY := 0.45
const LOOK_DIST := 160.0
const DROP_TIME := 0.25         # 往下跳時穿過平台的時間
const ROPE_GRAB := 16.0         # 離繩子多近抓得到
const SIZE := Vector2(28, 52)
const GROUND_LAYER := 1
const PLATFORM_LAYER := 2
const THIN_WALL_LAYER := 4      # 土遁穿得過的薄牆

var frozen := false
var double_jump := false        # 輕身術
var wall_jump := false          # 踏葉
var glide := false              # 御風
var earth_escape := false       # 土遁
var sword_flight := false       # 御劍
var flying := 0.0               # 御劍剩下的秒數
var facing := 1
var climbing := false
var rope := {}                  # 正在爬的繩子
var ropes: Array = []           # main 建地圖時填：{x, top, bottom}，top/bottom 是腳的 y（世界座標）
var floor_y := 560.0            # 地面高度，用來分辨站在地上還是平台上
var test_input = null           # 測試用：{"left", "right", "up", "down", "jump"} 布林值，設了就不讀鍵盤
var camera: Camera2D
var visual: Node2D              # 立繪，腳底在原點，跳躍落地時伸縮

var _cam_ahead := 0.0
var _cam_anchor := 0.0          # 鏡頭跟著的腳底高度
var _cam_y := 0.0
var _look := 0.0
var _look_hold := 0.0
var _shake := 0.0
var _squash := Vector2.ONE
var _was_on_floor := true
var _fall_speed := 0.0
var sprite: Sprite2D            # 有立繪時用；沒有就是色塊

var _coyote := 0.0
var _jump_buffer := 0.0
var _drop := 0.0
var _jump_was_down := false
var _air_jumps := 0
var _wall_lock := 0.0
var _flight_used := false
var _fly_was_down := false


func _ready() -> void:
	collision_layer = 0
	collision_mask = base_mask()
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = SIZE
	add_child(shape)
	var body := ColorRect.new()
	body.name = "Body"
	body.color = Color("#e8e2c8")
	body.size = SIZE
	body.position = -SIZE / 2
	body.pivot_offset = Vector2(SIZE.x / 2, SIZE.y)
	add_child(body)
	visual = Node2D.new()
	visual.position = Vector2(0, SIZE.y / 2)
	add_child(visual)
	# 鏡頭自己算位置（見 _update_camera），不掛在玩家身上跟著抖
	camera = Camera2D.new()
	camera.top_level = true
	add_child(camera)
	snap_camera()


## 換上立繪（面朝右、腳底貼齊圖的底邊），height 是畫面上的身高；碰撞框不變。
func set_look(tex: Texture2D, height: float) -> void:
	if tex == null:
		return
	if sprite == null:
		sprite = Sprite2D.new()
		sprite.centered = false
		visual.add_child(sprite)
	sprite.texture = tex
	sprite.scale = Vector2.ONE * height / tex.get_height()
	sprite.position = Vector2(-tex.get_width() * sprite.scale.x / 2, -height)
	get_node("Body").visible = false


func _process(delta: float) -> void:
	if sprite:
		sprite.flip_h = facing < 0
	_update_visual(delta)
	_update_camera(delta)


## 起跳拉長、落地壓扁，再彈回原狀；跑步時身子往前傾一點。
func _update_visual(delta: float) -> void:
	_squash = _squash.lerp(Vector2.ONE, 1.0 - exp(-14.0 * delta))
	var lean := 0.0 if climbing or flying > 0.0 else 0.06 * velocity.x / SPEED
	visual.scale = _squash
	visual.rotation = lerpf(visual.rotation, lean if is_on_floor() else lean * 0.5, 1.0 - exp(-10.0 * delta))
	var body: ColorRect = get_node("Body")
	body.scale = _squash
	body.rotation = visual.rotation


func _update_camera(delta: float) -> void:
	if not camera.is_inside_tree():
		return
	var input := {} if frozen else _read_input()
	# 前瞻：走動時慢慢偏到面向那邊，停下來就停在那裡，不來回晃
	if absf(velocity.x) > 40.0 and not climbing:
		_cam_ahead = lerpf(_cam_ahead, signf(velocity.x) * LOOK_AHEAD, 1.0 - exp(-LOOK_AHEAD_RATE * delta))
	# 高度：站穩或爬繩時才跟；空中只在掉到下面、或飛得太高時跟
	var f := feet()
	if is_on_floor() or climbing or flying > 0.0 or f > _cam_anchor:
		_cam_anchor = f
	elif f < _cam_anchor - CAM_AIR_SLACK:
		_cam_anchor = f + CAM_AIR_SLACK
	_cam_y = lerpf(_cam_y, _cam_anchor, 1.0 - exp(-CAM_Y_RATE * delta))
	# 站著按住 ↑／↓：往上／往下看
	var look_dir := 0.0
	if is_on_floor() and absf(velocity.x) < 1.0 and not input.get("jump", false):
		look_dir = float(input.get("down", false)) - float(input.get("up", false))
	_look_hold = _look_hold + delta if look_dir != 0.0 else 0.0
	var look_target := look_dir * LOOK_DIST if _look_hold >= LOOK_DELAY else 0.0
	_look = lerpf(_look, look_target, 1.0 - exp(-4.0 * delta))
	camera.global_position = Vector2(position.x + _cam_ahead, _cam_y - CAM_HEIGHT + _look)
	_shake = maxf(0.0, _shake - 30.0 * delta)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake if _shake > 0.0 else Vector2.ZERO


## 鏡頭震一下（受傷、重重落地）。
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## 平常會撞到的東西；學會土遁就不撞薄牆
func base_mask() -> int:
	return GROUND_LAYER | PLATFORM_LAYER | (0 if earth_escape else THIN_WALL_LAYER)


func feet() -> float:
	return position.y + SIZE.y / 2


func on_platform() -> bool:
	return is_on_floor() and feet() < floor_y - 2.0


## 地圖邊界：鏡頭不拍到地圖外。地圖比畫面窄時置中。
func set_camera_limits(left: float, right: float, top: float, bottom: float) -> void:
	var w := get_viewport_rect().size.x
	if right - left < w:
		var mid := (left + right) / 2
		left = mid - w / 2
		right = mid + w / 2
	camera.limit_left = int(left)
	camera.limit_right = int(right)
	camera.limit_top = int(top)
	camera.limit_bottom = int(bottom)


## 傳送後鏡頭直接到位，不要從舊位置滑過來。
func snap_camera() -> void:
	climbing = false
	flying = 0.0
	collision_mask = base_mask()
	_cam_anchor = feet()
	_cam_y = _cam_anchor
	_cam_ahead = facing * LOOK_AHEAD * 0.5
	_look = 0.0
	if camera.is_inside_tree():
		camera.global_position = Vector2(position.x + _cam_ahead, _cam_y - CAM_HEIGHT)
		camera.reset_smoothing()


func _read_input() -> Dictionary:
	if test_input != null:
		return test_input
	return {
		"left": Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A),
		"right": Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D),
		"up": Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W),
		"down": Input.is_physical_key_pressed(KEY_DOWN) or Input.is_physical_key_pressed(KEY_S),
		"jump": Input.is_physical_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_C) or Input.is_physical_key_pressed(KEY_SPACE),
		"fly": Input.is_physical_key_pressed(KEY_K),
	}


func _physics_process(delta: float) -> void:
	var input := _read_input()
	var jump_down: bool = input.get("jump", false)
	# 對話中按住的空白鍵，關掉對話後不算起跳
	var jump_pressed := jump_down and not _jump_was_down and not frozen
	_jump_was_down = jump_down
	var fly_down: bool = input.get("fly", false)
	var fly_pressed := fly_down and not _fly_was_down and not frozen
	_fly_was_down = fly_down
	if frozen:
		input = {}
	var dir := float(input.get("right", false)) - float(input.get("left", false))
	if dir != 0.0:
		facing = int(dir)
	if climbing:
		_climb(input, dir, jump_pressed, delta)
		return
	if _try_grab_rope(input):
		return
	if flying > 0.0 or (fly_pressed and sword_flight and not _flight_used and not is_on_floor()):
		_fly(input, dir, delta)
		return

	_drop = maxf(0.0, _drop - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)
	collision_mask = base_mask() & ~(PLATFORM_LAYER if _drop > 0.0 else 0)
	_coyote = COYOTE_TIME if is_on_floor() else maxf(0.0, _coyote - delta)
	if is_on_floor():
		_air_jumps = 1 if double_jump else 0
		_flight_used = false
	# 踏葉：空中貼著牆、而且往牆那邊按
	var wall_dir := 0
	if wall_jump and not is_on_floor() and is_on_wall_only():
		wall_dir = -int(signf(get_wall_normal().x))
	_jump_buffer = JUMP_BUFFER if jump_pressed else maxf(0.0, _jump_buffer - delta)

	if not is_on_floor():
		var g := GRAVITY
		if velocity.y > 0.0:
			g *= FALL_GRAVITY
		elif absf(velocity.y) < APEX_SPEED:
			g *= APEX_GRAVITY
		velocity.y = minf(velocity.y + g * delta, MAX_FALL)
		if wall_dir != 0 and int(dir) == wall_dir:
			velocity.y = minf(velocity.y, WALL_SLIDE)
		elif glide and jump_down and velocity.y > 0.0:
			velocity.y = minf(velocity.y, GLIDE_FALL)
	if _jump_buffer > 0.0 and input.get("down", false) and on_platform():
		_jump_buffer = 0.0
		_drop = DROP_TIME
		collision_mask = base_mask() & ~PLATFORM_LAYER
		position.y += 2.0
	elif _jump_buffer > 0.0 and _coyote > 0.0 and not input.get("down", false):
		velocity.y = JUMP_VELOCITY
		_jump_buffer = 0.0
		_coyote = 0.0
		_on_jump()
	elif jump_pressed and _coyote <= 0.0 and wall_dir != 0:
		velocity = Vector2(-wall_dir * WALL_JUMP.x, WALL_JUMP.y)
		_wall_lock = WALL_JUMP_LOCK
		_jump_buffer = 0.0
		_on_jump()
		_air_jumps = 1 if double_jump else 0
	elif jump_pressed and _coyote <= 0.0 and _air_jumps > 0 and not input.get("down", false):
		velocity.y = DOUBLE_JUMP_VELOCITY
		_air_jumps -= 1
		_jump_buffer = 0.0
		_on_jump(true)

	if _wall_lock <= 0.0:
		var target := dir * SPEED
		var rate := AIR_ACCEL
		if is_on_floor():
			if dir == 0.0:
				rate = GROUND_DECEL
			elif signf(velocity.x) == -dir:
				rate = TURN_DECEL
			else:
				rate = GROUND_ACCEL
		velocity.x = move_toward(velocity.x, target, rate * delta)
	if not is_on_floor():
		_fall_speed = velocity.y
	move_and_slide()
	if is_on_floor() and not _was_on_floor:
		_on_land(_fall_speed)
	_was_on_floor = is_on_floor()


func _on_jump(air := false) -> void:
	_squash = Vector2(0.86, 1.16)
	if not air:
		_puff(3, 0.0)
	else:
		_puff(4, 0.0, 0.6)


func _on_land(speed: float) -> void:
	var k := clampf(speed / MAX_FALL, 0.0, 1.0)
	_squash = Vector2(1.0 + 0.22 * k, 1.0 - 0.2 * k)
	if speed > 300.0:
		_puff(2 + int(k * 4), k)
	if speed > HARD_LANDING:
		shake(4.0)


static var _dust_tex: Texture2D

## 腳邊揚起幾點淡墨塵。
func _puff(count: int, strength: float, alpha := 0.45) -> void:
	if not is_inside_tree():
		return
	if _dust_tex == null:
		var g := GradientTexture2D.new()
		g.fill = GradientTexture2D.FILL_RADIAL
		g.fill_from = Vector2(0.5, 0.5)
		g.fill_to = Vector2(1.0, 0.5)
		g.width = 32
		g.height = 32
		g.gradient = Gradient.new()
		g.gradient.set_color(0, Color(0.16, 0.15, 0.13, 0.8))
		g.gradient.set_color(1, Color(0.16, 0.15, 0.13, 0.0))
		_dust_tex = g
	for i in count:
		var d := Sprite2D.new()
		d.texture = _dust_tex
		d.top_level = true
		d.z_index = 1
		var side := -1.0 if i % 2 == 0 else 1.0
		d.global_position = global_position + Vector2(side * randf_range(4, 12), SIZE.y / 2 - 4)
		d.scale = Vector2.ONE * randf_range(0.35, 0.55)
		d.modulate.a = alpha
		add_child(d)
		var t := d.create_tween().set_parallel()
		var drift := Vector2(side * randf_range(18, 34) * (1.0 + strength), -randf_range(4, 14))
		t.tween_property(d, "global_position", d.global_position + drift, 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		t.tween_property(d, "scale", d.scale * (1.6 + strength), 0.4)
		t.tween_property(d, "modulate:a", 0.0, 0.4)
		t.chain().tween_callback(d.queue_free)


## 御劍：不受重力，方向鍵往四方飛，時間到或落地就停。一次離地只能飛一次。
func _fly(input: Dictionary, dir: float, delta: float) -> void:
	if flying <= 0.0:
		flying = FLIGHT_TIME
		_flight_used = true
	flying = maxf(0.0, flying - delta)
	var v := float(input.get("down", false)) - float(input.get("up", false))
	velocity = Vector2(dir, v).normalized() * FLIGHT_SPEED if (dir != 0.0 or v != 0.0) else Vector2.ZERO
	collision_mask = base_mask()
	move_and_slide()
	if is_on_floor() and v >= 0.0:
		flying = 0.0


## 按 ↑ 抓住面前的繩子；站在繩子頂端按 ↓ 往下爬。
func _try_grab_rope(input: Dictionary) -> bool:
	if not (input.get("up", false) or input.get("down", false)):
		return false
	for r in ropes:
		if absf(position.x - r["x"]) > ROPE_GRAB:
			continue
		var f := feet()
		var grab_up: bool = input.get("up", false) and f > r["top"] + 4.0 and f <= r["bottom"] + 2.0
		var grab_down: bool = input.get("down", false) and is_on_floor() and absf(f - r["top"]) < 6.0
		if grab_up or grab_down:
			climbing = true
			rope = r
			velocity = Vector2.ZERO
			position.x = r["x"]
			if grab_down:
				position.y += 4.0
			collision_mask = 0
			return true
	return false


func _climb(input: Dictionary, dir: float, jump_pressed: bool, delta: float) -> void:
	if jump_pressed and dir != 0.0:
		_let_go()
		velocity = Vector2(ROPE_JUMP.x * dir, ROPE_JUMP.y)
		move_and_slide()
		return
	var v := float(input.get("down", false)) - float(input.get("up", false))
	position.y += v * CLIMB_SPEED * delta
	var f := feet()
	if f <= rope["top"]:
		# 爬到頂：站上平台
		position.y = rope["top"] - SIZE.y / 2 - 1.0
		_let_go()
	elif f >= rope["bottom"]:
		position.y = rope["bottom"] - SIZE.y / 2 - 1.0
		_let_go()


func _let_go() -> void:
	climbing = false
	rope = {}
	velocity = Vector2.ZERO
	_air_jumps = 1 if double_jump else 0
	collision_mask = base_mask()
