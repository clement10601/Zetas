## 拍行囊的物品頁、裝備頁、衣著頁（只列拿到的）。
##   xvfb-run -a godot --path . --rendering-driver opengl3 -s res://tools/bag_shots.gd -- /tmp/shots
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
	for k in ["青玉護腕", "雲紋道袍", "灰青短褐", "赭布長衫", "簪花", "凝氣草", "下品妖丹", "下品妖丹", "陰魂殘絲"]:
		main.gain_item(k)
	main.open_wardrobe()
	var p = main.wardrobe_panel
	await _shot("b1_bag_page")
	while p.current_entry().get("name", "") != "赭布長衫":
		p.move_row(1)
	p.cycle(1)
	await _shot("b2_bag_wear_fashion")
	while p.current_slot() != "top":
		p.move_row(1)
	await _shot("b3_tops_only_owned")
	p.close()
	quit(0)
