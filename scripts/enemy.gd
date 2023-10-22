extends Node3D

@export var player: Node3D

@export_subgroup("Sound Effects")
@export var attack_sfx: AudioStream
@export var destroy_sfx: AudioStream
@export var hurt_sfx: AudioStream

@onready var raycast = $RayCast
@onready var muzzle_a = $MuzzleA
@onready var muzzle_b = $MuzzleB

var health := 100
var time := 0.0
var target_position: Vector3
var destroyed := false

# When ready, save the initial position

func _ready():
	target_position = position


func _process(delta):
	self.look_at(player.position + Vector3(0, 0.5, 0), Vector3.UP, true)  # Look at player
	target_position.y += (cos(time * 5) * 1) * delta  # Sine movement (up and down)

	time += delta

	position = target_position

# Take damage from player

func damage(amount):
	Audio.play(hurt_sfx)

	health -= amount

	if health <= 0 and !destroyed:
		destroy()

# Destroy the enemy when out of health

func destroy():
	Audio.play(destroy_sfx)

	destroyed = true
	queue_free()

# Shoot when timer hits 0

func _on_timer_timeout():
	raycast.force_raycast_update()

	if raycast.is_colliding():
		var collider = raycast.get_collider()

		if collider.has_method("damage"):  # Raycast collides with player
			
			# Play muzzle flash animation(s)

			muzzle_a.frame = 0
			muzzle_a.play("default")
			muzzle_a.rotation_degrees.z = randf_range(-45, 45)

			muzzle_b.frame = 0
			muzzle_b.play("default")
			muzzle_b.rotation_degrees.z = randf_range(-45, 45)

			Audio.play(attack_sfx)

			collider.damage(5)  # Apply damage to player
