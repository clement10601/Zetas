## 拍裝備頁與各品階周身光效在場景裡的樣子（美術對照用）。
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/equipment_shots.gd -- /tmp/shots
extends SceneTree

var out_dir := "/tmp/shots"


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()
	create_timer(90.0).timeout.connect(func(): printerr("screenshot timeout"); quit(1))


func _shot(name: String, frames := 4) -> void:
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	print("saved ", name)


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = ""
	main.generated_dir = ""
	main.use_director = false
	main.playlog_path = ""
	main.encounter_chance = 0.0
	root.add_child(main)
	for i in 10:
		await process_frame
	for k in ["青玉護腕", "束髮銀冠", "護身符籙", "踏影靴", "雲紋道袍", "金絲腰封", "天青法衣", "鐵釘皮護腕", "銀邊腰封",
			"流雲仙裳", "蓮華冠", "墨焰魔袍", "半面魔紋"]:
		main.state.items[k] = 1
	var grades := {
		"e2_grade0_fan": {"top": "equip.disciple_robe", "belt": "equip.teal_wrap", "shoes": "equip.black_boots"},
		"e3_grade1_fa": {"top": "equip.sky_robe", "belt": "equip.silver_wrap", "cuffs": "equip.iron_bracer", "shoes": "equip.black_boots"},
		"e4_grade2_ling": {"top": "equip.sky_robe", "cuffs": "equip.jade_bracer", "head": "equip.silver_crown", "waist": "equip.talisman_charm", "shoes": "equip.shadow_boots"},
		"e5_grade3_fabao": {"top": "equip.cloud_robe", "belt": "equip.gold_wrap", "cuffs": "equip.jade_bracer", "head": "equip.silver_crown", "shoes": "equip.shadow_boots"},
		"e6_grade4_xian": {"top": "equip.xian_robe", "head": "equip.lotus_crown", "belt": "equip.gold_wrap", "shoes": "equip.shadow_boots"},
		"e7_grade4_mo": {"top": "equip.mo_robe", "head": "equip.demon_mask", "belt": "equip.gold_wrap", "cuffs": "equip.jade_bracer", "shoes": "equip.shadow_boots"},
	}
	main.set_equipment(grades["e5_grade3_fabao"])
	main.open_wardrobe()
	await _shot("e1_gear_page")
	var p = main.wardrobe_panel
	while p.current_slot() != "top":
		p.move_row(1)
	await _shot("e1b_fashion_follows_gear")
	p.close()
	main.state.region = "region.qingyun_sect"
	main.go_home()
	for name in grades:
		main.set_equipment(grades[name])
		main.player.position.x = 600
		main.player.snap_camera()
		await _shot(name, 40)
		print("player_at ", name, " ", main.player.get_global_transform_with_canvas().origin)
	# 時裝蓋在法寶上：外觀換成散修布衣，光效照舊
	main.set_equipment(grades["e5_grade3_fabao"])
	main.state.game_data["look"] = {"outfit": "wanderer"}
	main.apply_look()
	main.player.position.x = 600
	main.player.snap_camera()
	await _shot("e8_fashion_over_fabao", 40)
	print("player_at e8_fashion_over_fabao ", main.player.get_global_transform_with_canvas().origin)
	quit(0)
