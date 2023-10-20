class_name Player
extends CharacterBody2D

enum State {
	STAND,
	RUNNING,
	JUMP,
	FALL,
	LANDING,
	WALL_SLIDING,
	WALL_JUMP,
	ATTACK_1,
	ATTACK_2,
	ATTACK_3,
}

const GROUND_STATES := [State.STAND, State.RUNNING, State.LANDING,State.ATTACK_1,State.ATTACK_2,State.ATTACK_3]
const RUN_SPEED := 160.0
const JUMP_VELOCITY := -320.0
const WALL_JUMP_VELOCITY := Vector2(500, -320)
const FLOOR_ACCELERATION := RUN_SPEED / 0.2
const AIR_ACCELERATION := RUN_SPEED / 0.1

@export var can_combo := false

var defalut_gravity = ProjectSettings.get("physics/2d/default_gravity") as float
var is_first_tick := false
var is_combo_requested := false

@onready var graphics: Node2D = $Graphics
@onready var animation_player = $AnimationPlayer
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var jump_request_timer: Timer = $JumpRequestTimer
@onready var head_checker: RayCast2D = $Graphics/HeadChecker
@onready var foot_checker: RayCast2D = $Graphics/FootChecker
@onready var state_machine: Node = $StateMachine


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		jump_request_timer.start()
	# 长按跳的更高
	if event.is_action_released("jump"):
		jump_request_timer.stop()
		if velocity.y <JUMP_VELOCITY / 2:
			velocity.y = JUMP_VELOCITY / 2
	
	if event.is_action_pressed("attack") and can_combo:
		is_combo_requested = true

func tick_pyhsics(state:State, delta: float) -> void:
	match state:
		State.STAND:
			move(defalut_gravity,delta)
		State.RUNNING:
			move(defalut_gravity,delta)
		State.JUMP:
			move(0.0 if is_first_tick else defalut_gravity,delta)
		State.FALL:
			move(defalut_gravity,delta)
		State.LANDING:
			stand(defalut_gravity,delta)
		State.WALL_SLIDING:
			move(defalut_gravity / 3,delta)
			graphics.scale.x = -get_wall_normal().x
		State.WALL_JUMP:
			if state_machine.state_time < 0.1:
				stand(0.0 if is_first_tick else defalut_gravity, delta)
				graphics.scale.x = get_wall_normal().x
			else:
				move(defalut_gravity,delta)
		State.ATTACK_1, State.ATTACK_1, State.ATTACK_1:
			stand(defalut_gravity, delta)
			
	is_first_tick = false

func move(gravity: float, delta: float) -> void:
	var direction:= Input.get_axis("move_left","move_right")
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, direction * RUN_SPEED, acceleration * delta)
	velocity.y += gravity * delta
	
	if not is_zero_approx(direction):
		graphics.scale.x = -1 if direction < 0 else 1
	
	var was_on_floor := is_on_floor()	
	move_and_slide()

func stand(gravity: float,delta: float) -> void:
	var direction:= Input.get_axis("move_left","move_right")
	var acceleration := FLOOR_ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
	velocity.y += gravity * delta
	
	move_and_slide()
	
func can_wall_slide():
	return is_on_wall() and head_checker.is_colliding() and foot_checker.is_colliding()

func get_next_state(state:State) -> State:
	var can_jump := is_on_floor() or coyote_timer.time_left > 0
	var should_jump = can_jump and jump_request_timer.time_left > 0
	
	if should_jump:
		return State.JUMP
		
	if state in GROUND_STATES and not is_on_floor():
		return State.FALL
	
	var direction := Input.get_axis("move_left","move_right")
	var is_still := is_zero_approx(direction) and is_zero_approx(velocity.x)
	
	match state:
		State.STAND:
			if Input.is_action_just_pressed("attack"):
				return State.ATTACK_1
			if not is_still:
				return State.RUNNING
		State.RUNNING:
			if Input.is_action_just_pressed("attack"):
				return State.ATTACK_1
			if is_still:
				return State.STAND
		State.JUMP:
			if velocity.y > 0:
				return State.FALL
		State.FALL:
			if is_on_floor():
				return State.LANDING if is_still else State.RUNNING
			if can_wall_slide():
				return State.WALL_SLIDING
		State.LANDING:
			if not is_still:
				return State.RUNNING
			if not animation_player.is_playing():
				return State.STAND
		State.WALL_SLIDING:
			if jump_request_timer.time_left > 0:
				return State.WALL_JUMP
			if is_on_floor():
				return State.STAND
			if not is_on_wall():
				return State.FALL
		State.WALL_JUMP:
			if can_wall_slide() and not is_first_tick:
				return State.WALL_SLIDING
			if velocity.y >= 0:
				return State.FALL
		State.ATTACK_1:
			if not animation_player.is_playing():
				return State.ATTACK_2 if is_combo_requested else State.STAND
		State.ATTACK_2:
			if not animation_player.is_playing():
				return State.ATTACK_3 if is_combo_requested else State.STAND
		State.ATTACK_3:
			if not animation_player.is_playing():
				return State.STAND
	return state
	
	
func transition_state(from: State, to: State) -> void:
#	print("[%s] %s=> %s" % [
#		Engine.get_physics_frames(),
#		State.keys()[from] if from != -1 else "<START>",
#		State.keys()[to],
#	])
	if from not in GROUND_STATES and to in GROUND_STATES:
		coyote_timer.stop()
	match to:
		State.STAND:
			animation_player.play("stand")
		State.RUNNING:
			animation_player.play("running")
		State.JUMP:
			animation_player.play("jump")
			velocity.y = JUMP_VELOCITY
			coyote_timer.stop()
			jump_request_timer.stop()
		State.FALL:
			animation_player.play("fall")
			if from in GROUND_STATES:
				coyote_timer.start()
		State.LANDING:
			animation_player.play("landing")
		State.WALL_SLIDING:
			animation_player.play("wall_sliding")
		State.WALL_JUMP:
			animation_player.play("jump")
			velocity = WALL_JUMP_VELOCITY
			velocity.x *= get_wall_normal().x
			jump_request_timer.stop()
		State.ATTACK_1:
			animation_player.play("attack1")
			is_combo_requested = false
		State.ATTACK_2:
			animation_player.play("attack2")
			is_combo_requested = false
		State.ATTACK_3:
			animation_player.play("attack3")
			is_combo_requested = false
	# 慢动作
	# if to == State.WALL_JUMP:
	# 	Engine.time_scale = 0.3
	# if  from == State.WALL_JUMP:
	# 	Engine.time_scale = 1.0
	is_first_tick = true

	
