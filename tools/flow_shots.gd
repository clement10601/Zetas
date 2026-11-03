## 拍玩家各種動作的飄動（站、跑、起跳、下落、御風、御劍），美術對照用。
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/flow_shots.gd -- /tmp/shots
extends SceneTree

var out_dir := "/tmp/shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()
	create_timer(240.0).timeout.connect(func(): printerr("screenshot timeout"); quit(1))


func _shot(name: String, frames := 50) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name, " ", main_ref.player.get_global_transform_with_canvas().origin)


var main_ref: Node


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main_ref = main
	main.save_path = ""
	main.generated_dir = ""
	main.use_director = false
	main.playlog_path = ""
	main.encounter_chance = 0.0
	root.add_child(main)
	for i in 10:
		await process_frame
	var looks := {"a": {}, "b": {"outfit": "xian", "back": "ribbon_cloud", "hair": "high_tail"}}
	main.state.items["流雲仙裳"] = 1
	main.state.tier_index = 3
	main.state.region = "region.qingyun_sect"
	main.go_home()
	for lk in looks:
		main.state.game_data["look"] = looks[lk]
		main.apply_look()
		var p = main.player
		p.set_physics_process(false)   # 定格：不讓重力把空中的姿勢拉回地面
		p.z_index = 50                 # 畫在地標柱子前面，看得清楚
		for st in ["idle", "run", "rise", "fall", "glide", "fly"]:
			p.position = Vector2(420, p.position.y)
			p.snap_camera()
			p.flow_override = st
			p.flying = 999.0 if st == "fly" else 0.0
			await _shot("%s_%s" % [lk, st], 60)
			# 波浪另一個瞬間
			await _shot("%s_%s_2" % [lk, st], 9)
			if lk == "b" and st in ["run", "glide", "fly"]:
				for i in 16:
					await _shot("anim_%s_%02d" % [st, i], 3)
		p.flying = 0.0
		p.flow_override = ""
	quit(0)
