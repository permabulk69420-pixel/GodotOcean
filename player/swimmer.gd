class_name AbyssSwimmer
extends CharacterBody3D

@export var swim_speed := 2.8
@export var turn_speed_degrees := 75.0
@export var acceleration := 3.2
@export var drag := 2.1
@onready var origin: XROrigin3D=$XROrigin3D
@onready var head: XRCamera3D=$XROrigin3D/Head
@onready var left: XRController3D=$XROrigin3D/LeftHand
@onready var right: XRController3D=$XROrigin3D/RightHand
@onready var collider: CollisionShape3D=$BodyShape
@onready var thrusters: AbyssHandThrusters=$HandThrusters
var ocean: AbyssOcean
var terrain: AbyssTerrain
var controls_enabled:=true
var head_depth:=0.0
var submerged:=false
var surface_height:=0.0
var spawned:=false
var desktop_pitch:=0.0
var previous_input:=Vector3.ZERO

func _ready() -> void:
	process_physics_priority=-10
	collision_layer=2
	collision_mask=1
	safe_margin=0.035
	max_slides=5

func deadzone(stick: Vector2) -> Vector2:
	var length:=stick.length()
	if length<=0.15: return Vector2.ZERO
	return stick.normalized()*clampf((length-0.15)/0.85,0,1)

func smooth_turn(amount: float,delta: float) -> void:
	if absf(amount)<0.001: return
	var pivot:=head.global_position
	rotate_y(-amount*deg_to_rad(turn_speed_degrees)*delta)
	# Rotate around the tracked head, preserving room-scale offset rather than orbiting it.
	origin.position+=global_basis.inverse()*(pivot-head.global_position)

func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().use_xr: return
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		smooth_turn(event.relative.x*0.002/deg_to_rad(turn_speed_degrees),1.0)
		desktop_pitch=clampf(desktop_pitch-event.relative.y*0.002,-1.45,1.45)
		head.rotation.x=desktop_pitch
	if event is InputEventKey and event.pressed and event.physical_keycode==KEY_ESCAPE:
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not ocean: return
	var sample:=ocean.sample_surface(head.global_position)
	surface_height=sample.height
	if not spawned:
		var local_head_height:=head.global_position.y-global_position.y
		global_position.y=surface_height+0.38-local_head_height
		spawned=true
	if terrain and not terrain.near_ready:
		velocity=Vector3.ZERO
		return
	head_depth=surface_height-head.global_position.y
	if head_depth>0.08: submerged=true
	elif head_depth< -0.08: submerged=false
	var local_head:=to_local(head.global_position)
	var capsule:=collider.shape as CapsuleShape3D
	var height:=clampf(local_head.y+0.1,0.75,1.9)
	if not is_equal_approx(capsule.height,height): capsule.height=height
	collider.position=Vector3(local_head.x,local_head.y-height*0.5+0.1,local_head.z)
	var planar:=Vector2.ZERO
	var vertical:=0.0
	var turn:=0.0
	if controls_enabled:
		if get_viewport().use_xr:
			if left.get_is_active(): planar=deadzone(left.get_vector2(&'primary'))
			if right.get_is_active():
				var stick:=deadzone(right.get_vector2(&'primary'))
				vertical=stick.y
				turn=stick.x
		else:
			planar=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_W))-float(Input.is_physical_key_pressed(KEY_S))).limit_length()
			vertical=float(Input.is_physical_key_pressed(KEY_SPACE))-float(Input.is_physical_key_pressed(KEY_CTRL))
			turn=float(Input.is_physical_key_pressed(KEY_E))-float(Input.is_physical_key_pressed(KEY_Q))
	smooth_turn(turn,delta)
	var wish: Vector3=head.global_basis.x*planar.x-head.global_basis.z*planar.y+Vector3.UP*vertical
	wish=wish.limit_length()
	previous_input=wish
	var immersion:=clampf((surface_height-(head.global_position.y-1.2))/1.2,0,1)
	var target:=wish*swim_speed
	var response:=acceleration if wish.length_squared()>0.001 else drag
	velocity=velocity.lerp(target,1.0-exp(-response*delta*maxf(immersion,0.1)))
	if controls_enabled and immersion > 0.4 and thrusters.propulsion.length_squared() > 0.0001:
		velocity += thrusters.propulsion * AbyssHandThrusters.PROPULSION_ACCELERATION * delta
		velocity = velocity.limit_length(AbyssHandThrusters.MAX_SPEED)
	# Neutral swimming below the surface; a buoyant torso supports the head near it.
	# As the body leaves water, swimming lift disappears and gravity takes over.
	if head_depth<0.8 and wish.y> -0.15 and immersion>0.3:
		var float_error:=surface_height+0.38-head.global_position.y
		velocity.y+=clampf(float_error*10.0-velocity.y*4.8,-12,8)*delta
	else:
		velocity.y-=9.81*(1.0-immersion)*delta
	if immersion<0.05: velocity.y=minf(velocity.y,0.0)
	motion_mode=CharacterBody3D.MOTION_MODE_FLOATING if immersion>0.4 else CharacterBody3D.MOTION_MODE_GROUNDED
	if terrain:
		var extent:=Vector2(terrain.settings.region_chunks)*terrain.settings.chunk_size*0.5-Vector2.ONE*1.5
		if global_position.x>extent.x and velocity.x>0 or global_position.x< -extent.x and velocity.x<0: velocity.x=0
		if global_position.z>extent.y and velocity.z>0 or global_position.z< -extent.y and velocity.z<0: velocity.z=0
	move_and_slide()
