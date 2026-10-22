extends SceneTree
func _init():
	for n in ["fundidora", "robot_mula", "camion"]:
		var ps: PackedScene = load("res://assets/modelos/%s.glb" % n)
		var s := ps.instantiate()
		print(n, ": ", s.get_class())
		for c in s.find_children("*", "", true, false):
			if c is AnimationPlayer:
				print("  ANIM ", c.get_path(), " ", c.get_animation_list())
			elif n == "robot_mula" or c.name in ["luz_estado", "brasa", "pantalla"]:
				print("  ", s.get_path_to(c), " ", c.get_class(), " ", c.position if c is Node3D else "")
		s.free()
	quit()
