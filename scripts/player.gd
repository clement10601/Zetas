## 玩家：橫向卷軸操作，手感參考 2D 橫軸 MMO。
## 按鍵走 InputMap（scripts/keys.gd，預設方向鍵＋Z/X/C/V 與 WASD＋K/J/L/I 兩組同時有效）。
## ←→ 走（有一點加減速）、跳鍵 跳、站在單向平台上 ↓＋跳 往下跳、
## 靠近繩子或梯子按 ↑↓ 爬，爬的時候 ←→＋跳 可以跳開。
## 身法（main 依學會的身法開關，見 scripts/cultivation.gd）：
## 輕身術 double_jump 空中再按跳；踏葉 wall_jump 空中貼牆按跳往反方向蹬；
## 御風 glide 下落時按住跳滑翔；土遁 earth_escape 穿過薄牆；御劍 sword_flight 空中按御劍鍵飛一小段。
## 鏡頭往面向的方向多看一點、小跳不晃，站著按住 ↑／↓ 可以往上下看；受傷時輕震。
## 閃避鍵 墨影步：往面向方向閃 120，期間無敵，留下墨色殘影；冷卻 0.6 秒，空中一次。
## main 設 camera_zone（chunks.json 的 camera）時，鏡頭鎖在戰場上並稍微拉遠。
## 美術未到前用色塊。
extends CharacterBody2D

## 動作音效：jump、double_jump、wall_jump、flight、land。main 接到 scripts/audio.gd。
signal sound(name: String)

## 落地速度超過這個才有落地聲（小跳不響）
const LAND_SOUND_SPEED := 500.0

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
const KNOCKBACK := Vector2(240, -280)  # 被打中往反方向彈開
const HURT_LOCK := 0.3          # 彈開後這段時間不吃左右輸入
const DASH_TIME := 0.15         # 墨影步
const DASH_DISTANCE := 120.0
const DASH_COOLDOWN := 0.6
const ZONE_BLEND_TIME := 0.6    # 進出鎖定鏡頭的過渡
const CORNER_NUDGE := 6         # 轉角修正：撞頭或差一點踩上石壁邊時，最多推這麼多像素
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
const ROPE_GRAB := 26.0         # 離繩子多近抓得到（楓之谷式，站在旁邊按 ↑ 就抓）
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
var input_blocked := false      # 按鍵設定畫面開著時不讀鍵盤
var test_input = null           # 測試用：{"left", "right", "up", "down", "jump"} 布林值，設了就不讀鍵盤
var camera: Camera2D
var _cam_ahead := 0.0
var _cam_anchor := 0.0          # 鏡頭跟著的腳底高度
var _cam_y := 0.0
var _look := 0.0
var _look_hold := 0.0
var _shake := 0.0
var _hurt_lock := 0.0
var sitting := 0.0              # 打坐的坐姿還剩幾秒（期間不能動）
var dashing := 0.0              # 墨影步剩下的秒數（main 把這段時間當無敵）
var _dash_cooldown := 0.0
var _dash_used := false         # 空中已經閃過一次
var _dash_was_down := false
var _dash_dir := 1
var _ghost_timer := 0.0
## 鎖定鏡頭的戰場：{x0, x1（世界座標）, zoom, lock_y?}；空的就照平常跟
var camera_zone: Dictionary = {}
var _zone_blend := 0.0
var _zone_last: Dictionary = {}
var _base_limit_top := 0
var sprite: Sprite2D            # 有立繪時用；沒有就是色塊
var rig: Node2D                 # 立繪的軸心放在腳底：走路一頓一頓、跳起拉長、落地壓扁都繞這裡
var shadow: TextureRect

var _walk := 0.0
var _squash := 0.0              # 落地壓扁，1 → 0
var _lunge := 0.0               # 出劍前衝，1 → 0
var _was_on_floor := true
var _time := 0.0

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
	add_child(body)
	rig = Node2D.new()
	rig.name = "Rig"
	rig.position = Vector2(0, SIZE.y / 2)
	add_child(rig)
	shadow = TextureRect.new()
	shadow.texture = preload("res://scripts/actor_view.gd").shadow_texture()
	shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shadow.size = Vector2(50, 13)
	shadow.position = Vector2(-25, SIZE.y / 2 - 6.5)
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.show_behind_parent = true
	add_child(shadow)
	camera = Camera2D.new()
	# 鏡頭自己算位置（見 _update_camera），不掛在玩家身上跟著抖
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
		sprite.material = preload("res://scripts/ink_ui.gd").halo_material("player")
		rig.add_child(sprite)
	sprite.texture = tex
	sprite.scale = Vector2.ONE * height / tex.get_height()
	sprite.position = Vector2(-tex.get_width() * sprite.scale.x / 2, -height)
	get_node("Body").visible = false


func _process(delta: float) -> void:
	if sprite:
		sprite.flip_h = facing < 0
	_animate(delta)
	_update_camera(delta)


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
	var target := Vector2(position.x + _cam_ahead, _cam_y - CAM_HEIGHT + _look)
	# 戰場鎖定：0.6 秒內滑到戰場構圖、拉遠；離開後同樣滑回來
	if not camera_zone.is_empty():
		_zone_last = camera_zone
	_zone_blend = move_toward(_zone_blend, 1.0 if not camera_zone.is_empty() else 0.0, delta / ZONE_BLEND_TIME)
	var zoom := 1.0
	if _zone_blend > 0.0 and not _zone_last.is_empty():
		var k := smoothstep(0.0, 1.0, _zone_blend)
		var z := float(_zone_last.get("zoom", 1.0))
		var view := get_viewport_rect().size / z
		var x0 := float(_zone_last["x0"])
		var x1 := float(_zone_last["x1"])
		var zx := (x0 + x1) / 2 if x1 - x0 <= view.x else clampf(target.x, x0 + view.x / 2, x1 - view.x / 2)
		var zy := float(_zone_last["lock_y"]) if _zone_last.has("lock_y") else camera.limit_bottom - view.y / 2
		target = target.lerp(Vector2(zx, zy), k)
		zoom = lerpf(1.0, z, k)
		camera.limit_top = mini(_base_limit_top, int(zy - view.y / 2) - 1)
	else:
		camera.limit_top = _base_limit_top
	camera.zoom = Vector2.ONE * zoom
	camera.global_position = target
	_shake = maxf(0.0, _shake - 30.0 * delta)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake if _shake > 0.0 else Vector2.ZERO


## 墨影步：水平閃一段，不受重力，撞牆就停；結束後保留走路速度。
func _dash(dir: float, delta: float) -> void:
	if dashing <= 0.0:
		dashing = DASH_TIME
		_dash_dir = int(dir) if dir != 0.0 else facing
		facing = _dash_dir
		_dash_cooldown = DASH_COOLDOWN
		_dash_used = not is_on_floor()
		_ghost_timer = 0.0
		_hurt_lock = 0.0
		sound.emit("dash")
	var part := minf(delta, dashing) / delta   # 最後一格只走剩下的那一點，總距離剛好 120
	dashing = maxf(0.0, dashing - delta)
	if dashing < 0.001:
		dashing = 0.0
	velocity = Vector2(_dash_dir * DASH_DISTANCE / DASH_TIME * part, 0.0)
	collision_mask = base_mask()
	move_and_slide()
	_ghost_timer -= delta
	if _ghost_timer <= 0.0:
		_ghost_timer = 0.03
		_leave_ghost()
	if is_on_wall():
		dashing = 0.0
	if dashing <= 0.0:
		# 還按著同方向就接著跑，否則停住
		velocity.x = _dash_dir * SPEED if int(dir) == _dash_dir else 0.0


## 殘影：立繪的墨色拷貝，原地淡掉。
func _leave_ghost() -> void:
	if sprite == null or not is_inside_tree() or get_parent() == null:
		return
	var g := Sprite2D.new()
	g.texture = sprite.texture
	g.centered = false
	g.flip_h = sprite.flip_h
	g.global_transform = sprite.global_transform
	g.modulate = Color(0.1, 0.09, 0.08, 0.45)
	g.z_index = -1
	get_parent().add_child(g)
	var tw := g.create_tween()
	tw.tween_property(g, "modulate:a", 0.0, 0.25)
	tw.tween_callback(g.queue_free)


## 打坐：坐下一會兒，身邊升起幾縷靈氣。
func sit(seconds: float) -> void:
	sitting = seconds
	velocity = Vector2.ZERO
	if not is_inside_tree() or get_parent() == null:
		return
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	g.width = 24
	g.height = 24
	g.gradient = Gradient.new()
	g.gradient.set_color(0, Color(0.85, 0.97, 0.9, 0.9))
	g.gradient.set_color(1, Color(0.85, 0.97, 0.9, 0.0))
	for i in 8:
		var q := Sprite2D.new()
		q.texture = g
		q.position = position + Vector2(randf_range(-26, 26), SIZE.y / 2 - randf_range(0, 20))
		q.modulate.a = 0.0
		get_parent().add_child(q)
		var tw := q.create_tween()
		tw.tween_interval(i * seconds / 10.0)
		tw.tween_property(q, "modulate:a", 0.8, 0.2)
		tw.parallel().tween_property(q, "position:y", q.position.y - randf_range(60, 100), seconds * 0.6)
		tw.tween_property(q, "modulate:a", 0.0, 0.3)
		tw.tween_callback(q.queue_free)


## 被打中：往遠離 from_x 的方向彈開，短暫不吃左右輸入。
func knock_back(from_x: float) -> void:
	var away := signf(position.x - from_x)
	if away == 0.0:
		away = -float(facing)
	if climbing:
		climbing = false
		rope = {}
		collision_mask = base_mask()
	flying = 0.0
	dashing = 0.0
	sitting = 0.0
	velocity = Vector2(away * KNOCKBACK.x, KNOCKBACK.y)
	_hurt_lock = HURT_LOCK


## 轉角修正（只對實心的石壁有用，單向平台本來就穿得過）：
## 往上跳撞到石壁下緣的角，差幾像素就往旁邊推開；往前撞到石壁頂端的角，差幾像素就推上去。
func _corner_correct(rise_speed: float, dir: float) -> void:
	if rise_speed < 0.0 and is_on_ceiling():
		for k in range(1, CORNER_NUDGE + 1):
			for side in [-1, 1]:
				var shift := Vector2(side * k, 0)
				if not test_move(global_transform.translated(shift), Vector2(0, -4)):
					position += shift
					velocity.y = rise_speed    # 推開後照原本的速度繼續往上
					return
	elif dir != 0.0 and is_on_wall() and not is_on_floor():
		for k in range(1, CORNER_NUDGE + 1):
			var lift := Vector2(0, -k)
			if not test_move(global_transform.translated(lift), Vector2(dir * 3, 0)):
				position += lift + Vector2(dir * 2, 0)
				velocity.y = minf(velocity.y, 0.0)
				return


## 鏡頭震一下（受傷、重重落地）。
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


## 程式做的小動作（立繪只有一張）：站著呼吸、走路一頓一頓往前傾、
## 起跳拉長、下落微扁、落地壓扁揚塵、爬繩左右晃、御風飄、御劍前傾。
func _animate(delta: float) -> void:
	_time += delta
	var grounded := is_on_floor()
	var target_scale := Vector2.ONE
	var target_rot := 0.0
	var bob := 0.0
	var speed := absf(velocity.x)
	if sitting > 0.0:
		# 打坐：盤腿坐下（壓低、略寬），隨呼吸起伏
		var b := sin(_time * 1.6) * 0.02
		target_scale = Vector2(1.12, 0.64 + b)
	elif flying > 0.0:
		target_rot = facing * 0.35
		target_scale = Vector2(1.06, 0.95)
	elif climbing:
		_walk += delta * absf(velocity.y) / 18.0
		target_rot = sin(_walk) * 0.06
	elif grounded:
		if speed > 20.0:
			_walk += delta * speed / 20.0
			bob = -absf(sin(_walk)) * 3.5
			target_rot = facing * 0.07 * speed / SPEED
		else:
			var b := sin(_time * 2.2) * 0.014
			target_scale = Vector2(1.0 - b * 0.5, 1.0 + b)
	elif velocity.y < -120.0:
		target_scale = Vector2(0.92, 1.09)
		target_rot = facing * 0.05
	elif velocity.y > 0.0 and velocity.y <= GLIDE_FALL + 1.0 and glide:
		target_rot = sin(_time * 3.0) * 0.08
	else:
		target_scale = Vector2(1.04, 0.97)
		target_rot = facing * 0.08
	if grounded and not _was_on_floor and not climbing:
		_squash = 1.0
		if is_inside_tree() and get_parent() != null:
			preload("res://scripts/ink_fx.gd").dust(get_parent(), position + Vector2(0, SIZE.y / 2))
	_was_on_floor = grounded
	_squash = move_toward(_squash, 0.0, delta * 6.0)
	_lunge = move_toward(_lunge, 0.0, delta * 5.0)
	target_scale *= Vector2(1.0 + 0.14 * _squash, 1.0 - 0.14 * _squash)
	var k := minf(1.0, delta * 16.0)
	rig.scale = rig.scale.lerp(target_scale, k)
	rig.rotation = lerp_angle(rig.rotation, target_rot + facing * 0.25 * _lunge, k)
	rig.position = Vector2(facing * 10.0 * _lunge, SIZE.y / 2 + bob)
	shadow.modulate.a = move_toward(shadow.modulate.a, 0.55 if grounded else 0.0, delta * 6.0)


## 出劍：往前一衝，畫一道墨痕，前方依筆順寫出「斬」字（字訣，reference-study.md A4）。
## 回傳那個字，打中東西時 main 叫它散成墨點。
func play_attack() -> Node2D:
	_lunge = 1.0
	if not is_inside_tree() or get_parent() == null:
		return null
	preload("res://scripts/ink_fx.gd").slash(get_parent(), position + Vector2(facing * 26.0, -8.0), facing)
	return preload("res://scripts/ink_glyph.gd").spawn(get_parent(), position + Vector2(facing * 62.0, -46.0))


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
	_base_limit_top = int(top)
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
	_zone_blend = 0.0
	dashing = 0.0
	if camera.is_inside_tree():
		camera.global_position = Vector2(position.x + _cam_ahead, _cam_y - CAM_HEIGHT)
		camera.reset_smoothing()


func _read_input() -> Dictionary:
	if test_input != null:
		return test_input
	if input_blocked:
		return {}
	return {
		"left": Input.is_action_pressed("move_left"),
		"right": Input.is_action_pressed("move_right"),
		"up": Input.is_action_pressed("move_up"),
		"down": Input.is_action_pressed("move_down"),
		"jump": Input.is_action_pressed("jump"),
		"fly": Input.is_action_pressed("fly"),
		"dash": Input.is_action_pressed("dash"),
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
	var dash_down: bool = input.get("dash", false)
	var dash_pressed := dash_down and not _dash_was_down and not frozen
	_dash_was_down = dash_down
	_dash_cooldown = maxf(0.0, _dash_cooldown - delta)
	sitting = maxf(0.0, sitting - delta)
	if frozen or sitting > 0.0:
		input = {}
		dashing = 0.0
		jump_pressed = false
		dash_pressed = false
		fly_pressed = false
	var dir := float(input.get("right", false)) - float(input.get("left", false))
	if dir != 0.0:
		facing = int(dir)
	if climbing:
		_climb(input, dir, jump_pressed, delta)
		return
	if _try_grab_rope(input):
		return
	if dashing > 0.0 or (dash_pressed and _dash_cooldown <= 0.0 and not _dash_used and flying <= 0.0):
		_dash(dir, delta)
		return
	if flying > 0.0 or (fly_pressed and sword_flight and not _flight_used and not is_on_floor()):
		if flying <= 0.0:
			sound.emit("flight")
		_fly(input, dir, delta)
		return

	_drop = maxf(0.0, _drop - delta)
	_wall_lock = maxf(0.0, _wall_lock - delta)
	_hurt_lock = maxf(0.0, _hurt_lock - delta)
	collision_mask = base_mask() & ~(PLATFORM_LAYER if _drop > 0.0 else 0)
	_coyote = COYOTE_TIME if is_on_floor() else maxf(0.0, _coyote - delta)
	if is_on_floor():
		_dash_used = false
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
		sound.emit("jump")
	elif jump_pressed and _coyote <= 0.0 and wall_dir != 0:
		velocity = Vector2(-wall_dir * WALL_JUMP.x, WALL_JUMP.y)
		_wall_lock = WALL_JUMP_LOCK
		_jump_buffer = 0.0
		_air_jumps = 1 if double_jump else 0
		sound.emit("wall_jump")
	elif jump_pressed and _coyote <= 0.0 and _air_jumps > 0 and not input.get("down", false):
		velocity.y = DOUBLE_JUMP_VELOCITY
		_air_jumps -= 1
		_jump_buffer = 0.0
		sound.emit("double_jump")

	if _wall_lock <= 0.0 and _hurt_lock <= 0.0:
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
	var was_airborne := not is_on_floor()
	var fall_speed := velocity.y
	var rise_speed := minf(velocity.y, 0.0)
	move_and_slide()
	if was_airborne:
		_corner_correct(rise_speed, dir)
	if was_airborne and is_on_floor() and fall_speed >= LAND_SOUND_SPEED:
		sound.emit("land")
	if was_airborne and is_on_floor() and fall_speed >= HARD_LANDING:
		shake(4.0)


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
		sound.emit("jump")
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
