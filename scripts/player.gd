extends CharacterBody3D

# signals
signal health_updated

# references
@onready var camera: Camera3D = $Head/Camera
@onready var raycast: RayCast3D = $Head/Camera/RayCast
@onready var muzzle: AnimatedSprite3D = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Muzzle
@onready var container: Node3D = $Head/Camera/SubViewportContainer/SubViewport/CameraItem/Container
@onready var sound_footsteps: AudioStreamPlayer = $SoundFootsteps
@onready var blaster_cooldown: Timer = $Cooldown

# external properties
@export var crosshair: TextureRect

@export_subgroup("Properties")
@export var movement_speed: float = 5.0
@export var jump_strength: float = 8.0
@export var allowed_jumps: int = 2
@export var reset_jumps_on_wall_mount: bool = false

@export_subgroup("Weapons")
@export var weapons: Array[Weapon] = []

@export_subgroup("Sound Effects")
@export var land_sfx: AudioStream
@export var jump_sfx: AudioStreamRandomizer
@export var weapon_change_sfx: AudioStream

# internal properties
var weapon: Weapon
var weapon_index: int = 0
var mouse_sensitivity: int = 700
var gamepad_sensitivity: float = 0.075
var mouse_captured: bool = true
var movement_velocity: Vector3
var rotation_target: Vector3
var input_mouse: Vector2
var container_offset = Vector3(1.2, -1.1, -2.75)
var tween:Tween
var health: int = 100
var gravity: float = 0.0
var previously_floored: bool = false
var can_jump: bool = false
var taken_jumps: int = 0
var can_wall_run: bool = false
var is_wall_running: bool = false
var wall_run_direction: int = 0
var wall_run_rotation: float
var rocket_jump_ground_max_distance: float = 2.0
var rocket_jump_weapon_knockback_clamp: int = 8

func _ready():
	# set current mouse mode to captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# get weapons and initiate the first one
	weapon = weapons[weapon_index] # Weapon must never be nil
	initiate_change_weapon(weapon_index)

func _physics_process(delta):
	# controls
	handle_controls(delta)

	# gravity
	handle_gravity(delta)

	# calculate movement
	var applied_velocity: Vector3
	movement_velocity = transform.basis * movement_velocity

	# check if player has reached height of jump and can begin wall running
	if can_wall_run == false and gravity > 0 and not is_on_floor():
		can_wall_run = true

	# wall running (must be allowed to wall run, on the wall, and havent used last jump by jumping off a wall)
	if can_wall_run and taken_jumps <= allowed_jumps and is_on_wall():
		# get wall vector
		var wall_vectors: Array[Vector3] = [get_wall_normal()]

		# just started to wall run
		if not is_wall_running:
			# allow them to jump off wall
			can_jump = true

			# reset jumps
			if reset_jumps_on_wall_mount:
				taken_jumps = 0

			# get look direction vector
			var look_direction_vector: Vector3 = -global_transform.basis.z

			# get remaining wall vectors
			wall_vectors.push_back(wall_vectors[0].rotated(Vector3.UP, -PI/2))
			wall_vectors.push_back(-wall_vectors[0])
			wall_vectors.push_back(-wall_vectors[1])

			# get dot product of look direction and wall vectors
			var wall_vector_dot_products: Array[float] = []
			for i in wall_vectors.size():
				wall_vector_dot_products.push_back(wall_vectors[i].dot(look_direction_vector))

			# find closest wall vector to look direction vector
			var smallest_vector: int
			for i in wall_vector_dot_products.size():
				if smallest_vector == null:
					smallest_vector = i
				else:
					if wall_vector_dot_products[i] < wall_vector_dot_products[smallest_vector]:
						smallest_vector = i

			# determine direction of wall run
			if smallest_vector == 1:
				wall_run_direction = 1
			elif smallest_vector == 3:
				wall_run_direction = -1
			else:
				wall_run_direction = 0

			# get angle of wall parallel to player with same direction
			wall_run_rotation = Vector2(wall_vectors[smallest_vector].z, wall_vectors[smallest_vector].x).angle()

			# keep rotation target within bounds
			if rotation_target.y + TAU > ((wall_run_rotation + PI/2) + TAU):
				rotation_target.y -= TAU
			elif rotation_target.y + TAU < ((wall_run_rotation - PI/2) + TAU):
				rotation_target.y += TAU

		# prevent falling
		gravity = 0

		# push player toward wall, and push forward perpendicular to wall's normal vector depending on player's initial look direction
		if wall_run_direction == 0:
			movement_velocity = -wall_vectors[0]
		else:
			movement_velocity = -wall_vectors[0] + wall_vectors[0].rotated(Vector3.UP, wall_run_direction * (PI/2)) * movement_speed

		# currently wall running state
		is_wall_running = true
	else: 
		is_wall_running = false
		wall_run_direction = 0

	# apply movement
	applied_velocity = velocity.lerp(movement_velocity, delta * 10)
	applied_velocity.y = -gravity
	velocity = applied_velocity
	move_and_slide()

	# rotation
	if is_wall_running:
		# rotate angle slightly if wall running
		camera.rotation.z = lerp_angle(camera.rotation.z, deg_to_rad(-10 * wall_run_direction), delta * 5)

		# clamp y rotation of camera
		rotation_target.y = clamp(rotation_target.y + TAU, (wall_run_rotation - PI/2) + TAU, (wall_run_rotation + PI/2) + TAU) - TAU
	else:
		# slightly tilt camera and lag behind mouse input for dramatic effect
		camera.rotation.z = lerp_angle(camera.rotation.z, -input_mouse.x * 25 * delta, delta * 5)
	rotation.y = lerp_angle(rotation.y, rotation_target.y, delta * 25)
	camera.rotation.x = lerp_angle(camera.rotation.x, rotation_target.x, delta * 25)	
	container.position = lerp(container.position, container_offset - (basis.inverse() * applied_velocity / 30), delta * 10)

	# movement sound
	sound_footsteps.stream_paused = true
	if is_on_floor() or is_wall_running:
		if abs(velocity.x) > 1 or abs(velocity.z) > 1:
			sound_footsteps.stream_paused = false

	# lerp camera to give sense of falling
	camera.position.y = lerp(camera.position.y, 0.0, delta * 5)

	# landed
	if is_on_floor() and gravity > 1 and !previously_floored:
		Audio.play(land_sfx)
		camera.position.y = -0.1

	# store landed state for next pass
	previously_floored = is_on_floor()

	# falling / respawning
	if position.y < -10:
		get_tree().reload_current_scene()

# mouse movement
func _input(event):
	if event is InputEventMouseMotion and mouse_captured:
		input_mouse = event.relative / mouse_sensitivity
		rotation_target.y -= event.relative.x / mouse_sensitivity
		rotation_target.x -= event.relative.y / mouse_sensitivity

func handle_controls(_delta):
	# mouse capture
	if Input.is_action_just_pressed("mouse_capture"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_captured = true

	# mouse exit
	if Input.is_action_just_pressed("mouse_capture_exit"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		mouse_captured = false
		input_mouse = Vector2.ZERO

	# movement
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	movement_velocity = Vector3(input.x, 0, input.y).normalized() * movement_speed

	# rotation
	var rotation_input := Input.get_vector("camera_right", "camera_left", "camera_down", "camera_up")
	rotation_target -= Vector3(-rotation_input.y, -rotation_input.x, 0).limit_length(1.0) * gamepad_sensitivity
	rotation_target.x = clamp(rotation_target.x, deg_to_rad(-90), deg_to_rad(90))

	# shooting
	action_shoot()

	# jumping
	if Input.is_action_pressed("jump") and can_jump:
		Audio.play(jump_sfx)
		action_jump()

	# weapon switching
	action_weapon_toggle()

# gravity
func handle_gravity(delta):
	gravity += 20 * delta

	# reset on land
	if gravity > 0 and is_on_floor():
		# reset jump ability
		taken_jumps = 0
		can_jump = true

		# reset wall run ability
		can_wall_run = false

		# reset gravity
		gravity = 0

	# prevent first jump if falling
	if taken_jumps == 0 and not is_on_floor() and not is_wall_running:
		can_jump = false

# jumping
func action_jump():
	# disable wall running
	can_wall_run = false

	# record jump
	taken_jumps += 1

	# apply jump to gravity
	gravity = -jump_strength

	# check if at max jumps
	if taken_jumps >= allowed_jumps:
		can_jump = false

# shooting
func action_shoot():
	if Input.is_action_pressed("shoot"):
		# cooldown
		if !blaster_cooldown.is_stopped(): return
		Audio.play(weapon.sound_shoot)

		# visual weapon knockback
		container.position.z += 0.25

		# camera knockback
		camera.rotation.x += 0.025 

		# muzzle flash
		muzzle.play("default")

		# muzzle animation
		muzzle.rotation_degrees.z = randf_range(-45, 45)
		muzzle.scale = Vector3.ONE * randf_range(0.40, 0.75)
		muzzle.position = container.position - weapon.muzzle_position

		# start cooldown
		blaster_cooldown.start(weapon.cooldown)

		# shoot shots depending on set shot amount
		var average_distance: float = 0
		for n in weapon.shot_count:
			# raycast
			raycast.target_position.x = randf_range(-weapon.spread, weapon.spread)
			raycast.target_position.y = randf_range(-weapon.spread, weapon.spread)
			raycast.force_raycast_update()

			# don't create impact when raycast didn't hit
			if !raycast.is_colliding(): continue 

			# get colliding object
			var collider = raycast.get_collider()

			# hitting an enemy
			if collider.has_method("damage"):
				collider.damage(weapon.damage)

			# creating an impact animation
			var impact_instance = weapon.impact.instantiate()
			impact_instance.play("shot")
			get_tree().root.add_child(impact_instance)
			impact_instance.position = raycast.get_collision_point() + (raycast.get_collision_normal() / 10)
			impact_instance.look_at(camera.global_transform.origin, Vector3.UP, true) 

			# save distance of this bullet
			average_distance += self.position.distance_to(impact_instance.position)

		# average the combined distance
		average_distance /= weapon.shot_count

		# apply weapon knockback to player (taking look direction into account)
		movement_velocity += camera.transform.basis.z * weapon.knockback

		# rocket jump mechanic (depending on how far down they are looking and the distance to the ground)
		if not is_on_floor() and average_distance > 0 and average_distance <= rocket_jump_ground_max_distance and camera.rotation.x < 0:
			gravity -= -(float(weapon.knockback) / float(rocket_jump_weapon_knockback_clamp)) * camera.rotation.x

# toggle between available weapons (listed in 'weapons')
func action_weapon_toggle():
	if Input.is_action_just_pressed("weapon_toggle"):
		weapon_index = wrap(weapon_index + 1, 0, weapons.size())
		initiate_change_weapon(weapon_index)

		# audio cue
		Audio.play(weapon_change_sfx)

# initiates the weapon changing animation (tween)
func initiate_change_weapon(index):
	weapon_index = index
	tween = get_tree().create_tween()
	tween.set_ease(Tween.EASE_OUT_IN)
	tween.tween_property(container, "position", container_offset - Vector3(0, 1, 0), 0.1)
	tween.tween_callback(change_weapon) # Changes the model

# switches the weapon model (off-screen)
func change_weapon():
	weapon = weapons[weapon_index]

	# Step 1. Remove previous weapon model(s) from container
	for n in container.get_children():
		container.remove_child(n)

	# Step 2. Place new weapon model in container
	var weapon_model = weapon.model.instantiate()
	container.add_child(weapon_model)
	weapon_model.position = weapon.position
	weapon_model.rotation_degrees = weapon.rotation

	# Step 3. Set model to only render on layer 2 (the weapon camera)
	for child in weapon_model.find_children("*", "MeshInstance3D"):
		child.layers = 2

	# Set weapon data
	raycast.target_position = Vector3(0, 0, -1) * weapon.max_distance
	crosshair.texture = weapon.crosshair

func damage(amount):
	health -= amount

	# update health on HUD
	health_updated.emit(health)

	# reset scene when out of health
	if health < 0:
		get_tree().reload_current_scene()
