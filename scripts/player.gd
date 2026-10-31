## 玩家：左右移動、跳躍。M0 用色塊代替美術。
extends CharacterBody2D

const SPEED := 280.0
const JUMP_VELOCITY := -560.0
const GRAVITY := 1500.0
const SIZE := Vector2(28, 52)

var frozen := false
var facing := 1


func _ready() -> void:
	var shape := CollisionShape2D.new()
	shape.shape = RectangleShape2D.new()
	shape.shape.size = SIZE
	add_child(shape)
	var body := ColorRect.new()
	body.color = Color("#e8e2c8")
	body.size = SIZE
	body.position = -SIZE / 2
	add_child(body)
	var cam := Camera2D.new()
	cam.position = Vector2(0, -120)
	add_child(cam)


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
	var dir := 0.0
	if not frozen:
		if Input.is_physical_key_pressed(KEY_LEFT) or Input.is_physical_key_pressed(KEY_A):
			dir -= 1.0
		if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D):
			dir += 1.0
		if is_on_floor() and (Input.is_physical_key_pressed(KEY_UP) or Input.is_physical_key_pressed(KEY_W)):
			velocity.y = JUMP_VELOCITY
	if dir != 0.0:
		facing = int(dir)
	velocity.x = dir * SPEED
	move_and_slide()
