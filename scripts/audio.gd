## 配樂與音效。清單在 content/audio.json；檔案缺了就靜音，不影響遊戲。
##
## 分層配樂（docs/design/reference-study.md M1、M2、M5）：每首拆三層同時播放、只調音量。
## - base：環境（風、溪、鳥）＋持續音，一直在，自己循環（比較短）。
## - melody：琴笛，玩家走動時淡入，站著不動一陣子就淡出。每圈結尾有一段留白，只剩環境。
## - rhythm：鼓、鑼、木魚，附近有敵人或事件進行中時 0.8 秒淡入。
## - 對話框開著時 melody、rhythm 降 6 dB，base 不降。
## melody 和 rhythm 長度一樣、同時開始，所以一直對齊。換地區時整組交叉淡入淡出。
##
## 整首曲（清單裡寫 file 而不是 layers）：地圖標籤與事件用，當成一直開著的 base 層播，對話時一樣壓低。
## 要放哪一首由 main 的 music_choice() 依玩家所在區塊與事件狀態決定。
##
## 短樂句（M3）：事件開始／完成、突破、心魔現身用目前曲子調性的短句，等到下一拍才播。
## 地區動機（M4）：傳送時奏目的地的動機，和 NPC 說話時奏當地動機。
## 心魔幻境的旋律層用「玩家所在地區」動機的倒影，每區一版。
##
## 音效：play(name) 從版本裡隨機挑一個（不連續重複），用播放器池同時播多個。
## 網頁版瀏覽器要使用者先按過鍵或點過畫面才會出聲；Godot 會在第一次輸入時自動解鎖。
## N 鍵開關配樂（音效與短樂句照常），設定存在 user://audio.cfg。
extends Node

const CROSSFADE := 1.5
const POOL_SIZE := 8
const SETTINGS_PATH := "user://audio.cfg"
const LAYERS := ["base", "melody", "rhythm"]
## 各層淡入、淡出要幾秒（從 0 到滿）
const FADE_IN := {"base": 1.0, "melody": 2.5, "rhythm": 0.8}
const FADE_OUT := {"base": 1.0, "melody": 5.0, "rhythm": 3.0}
## 站著不動超過這麼多秒，旋律層淡出
const IDLE_SECONDS := 10.0
const DUCK_DB := -6.0
const DUCK_RATE := 12.0   # dB／秒
const SILENT_DB := -60.0

var manifest_path := "res://content/audio.json"
var settings_path := SETTINGS_PATH
var music: Dictionary = {}
var sfx: Dictionary = {}
var stingers: Dictionary = {}    # 不分地區的短樂句（例如 heart_demon）
var music_on := true
var current_music := ""          # 目前（或排定）播放的清單 key
var current_region := ""         # 心魔幻境選旋律版本用
var played: Array = []           # 測試用：播過的音效名，短樂句記成 "stinger:<名稱>"
## 各層目標音量（0–1），由 set_mood 決定；測試可以直接讀
var layer_target := {"base": 1.0, "melody": 0.0, "rhythm": 0.0}
var layer_gain := {"base": 1.0, "melody": 0.0, "rhythm": 0.0}
var duck_db := 0.0
var _idle := 0.0
var _sets: Array = []            # 正在播放的曲組：{key, entry, players: {layer: AudioStreamPlayer}, fade, target}
var _pool: Array = []
var _cache: Dictionary = {}      # path -> AudioStream，載不到記 null
var _last_variant: Dictionary = {}


func _ready() -> void:
	var data := _read_json(manifest_path)
	music = data.get("music", {})
	sfx = data.get("sfx", {})
	stingers = data.get("stingers", {})
	_load_settings()
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func _stream(path: String) -> AudioStream:
	if path == "":
		return null
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## 依地圖標籤（例如心魔幻境 illusion）優先，否則用地區的曲子。
func music_key(region: String, tags: Array) -> String:
	for t in tags:
		if music.has("tag." + str(t)):
			return "tag." + str(t)
	return region if music.has(region) else ""


## 某首曲子某一層的檔案；心魔幻境的旋律層依所在地區挑。
func layer_file(key: String, layer: String, region := "") -> String:
	var entry: Dictionary = music.get(key, {})
	if entry.has("file"):
		return str(entry["file"]) if layer == "base" else ""
	if layer == "melody" and entry.has("melody_by_region"):
		var by: Dictionary = entry["melody_by_region"]
		return str(by.get(region, by.values()[0] if not by.is_empty() else ""))
	return str(entry.get("layers", {}).get(layer, ""))


func play_music(key: String, region := "") -> void:
	if key == current_music and (region == current_region or region == ""):
		return
	current_music = key
	if region != "":
		current_region = region
	for s in _sets:
		s["target"] = 0.0
	if key == "" or not music_on:
		return
	var entry: Dictionary = music.get(key, {})
	var players := {}
	for layer in LAYERS:
		var stream := _stream(layer_file(key, layer, current_region))
		if stream == null:
			continue
		if "loop" in stream:
			stream.loop = true
		var p := AudioStreamPlayer.new()
		p.stream = stream
		p.volume_db = SILENT_DB
		add_child(p)
		players[layer] = p
	if players.is_empty():
		return
	for p in players.values():
		p.play()
	_sets.append({"key": key, "entry": entry, "players": players, "fade": 0.0, "target": 1.0})


## 每格由 main 呼叫：玩家有沒有在走、附近有沒有危險、對話框開著沒。
func set_mood(moving: bool, danger: bool, talking: bool, delta: float) -> void:
	_idle = 0.0 if moving else _idle + delta
	layer_target["melody"] = 1.0 if _idle < IDLE_SECONDS else 0.0
	layer_target["rhythm"] = 1.0 if danger else 0.0
	duck_db = move_toward(duck_db, DUCK_DB if talking else 0.0, DUCK_RATE * delta)


func _process(delta: float) -> void:
	for layer in LAYERS:
		var target: float = layer_target[layer]
		var rate: float = 1.0 / (FADE_IN[layer] if target > layer_gain[layer] else FADE_OUT[layer])
		layer_gain[layer] = move_toward(layer_gain[layer], target, rate * delta)
	for s in _sets.duplicate():
		s["fade"] = move_toward(s["fade"], s["target"], delta / CROSSFADE)
		if s["fade"] <= 0.0 and s["target"] <= 0.0:
			for p in s["players"].values():
				p.queue_free()
			_sets.erase(s)
			continue
		var base_db := float(s["entry"].get("volume_db", 0.0))
		for layer in s["players"]:
			var amp: float = s["fade"] * layer_gain[layer]
			var ducked: bool = layer != "base" or s["entry"].has("file")
			var db := base_db + linear_to_db(maxf(amp, 0.001)) + (duck_db if ducked else 0.0)
			s["players"][layer].volume_db = maxf(db, SILENT_DB)


func toggle_music() -> bool:
	music_on = not music_on
	if music_on:
		var key := current_music
		current_music = ""
		play_music(key)
	else:
		for s in _sets:
			s["target"] = 0.0
	_save_settings()
	return music_on


## 距離目前曲子下一拍還有幾秒；沒在播就 0。
func time_to_next_beat() -> float:
	var bpm := 0.0
	var pos := -1.0
	for s in _sets:
		var clock: String = "melody" if s["players"].has("melody") else ("base" if s["entry"].has("file") else "")
		if s["target"] > 0.0 and clock != "":
			bpm = float(s["entry"].get("bpm", 0))
			pos = s["players"][clock].get_playback_position() + AudioServer.get_time_since_last_mix()
	if bpm <= 0.0 or pos < 0.0:
		return 0.0
	var beat := 60.0 / bpm
	var wait := beat - fmod(pos, beat)
	return 0.0 if wait < 0.05 or wait > beat - 0.02 else wait


## 短樂句：先找目前曲子的版本，再找所在地區的、共用的；都沒有就播 fallback 音效。等到下一拍才出聲。
func stinger(name: String, fallback := "") -> void:
	# 目前曲子沒有自己的短樂句（地圖或事件的整首曲）就用所在地區的
	var own: Dictionary = music.get(current_music, {}).get("stingers", {})
	var regional: Dictionary = music.get(current_region, {}).get("stingers", {})
	var path := str(own.get(name, regional.get(name, stingers.get(name, ""))))
	var stream := _stream(path)
	if stream == null:
		if fallback != "":
			play(fallback)
		return
	played.append("stinger:" + name)
	var wait := time_to_next_beat()
	if wait > 0.0 and is_inside_tree():
		get_tree().create_timer(wait).timeout.connect(_play_stream.bind(stream, 0.0, 0.0))
	else:
		_play_stream(stream, 0.0, 0.0)


## 地區動機：傳送時奏目的地的，和 NPC 說話時奏當地的。
func motif(key: String) -> void:
	var stream := _stream(str(music.get(key, {}).get("stingers", {}).get("motif", "")))
	if stream != null:
		played.append("motif:" + key)
		_play_stream(stream, -6.0, 0.0)


func play(name: String, pitch_jitter := 0.04) -> void:
	played.append(name)
	var entry: Dictionary = sfx.get(name, {})
	var files: Array = entry.get("files", [])
	if files.is_empty():
		return
	var i := randi() % files.size()
	if files.size() > 1 and i == int(_last_variant.get(name, -1)):
		i = (i + 1) % files.size()
	_last_variant[name] = i
	var stream := _stream(str(files[i]))
	if stream != null:
		_play_stream(stream, float(entry.get("volume_db", 0.0)), pitch_jitter)


func _play_stream(stream: AudioStream, volume_db: float, pitch_jitter: float) -> void:
	var p: AudioStreamPlayer = null
	for q in _pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _pool[0]
		_pool.push_back(_pool.pop_front())
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _load_settings() -> void:
	if settings_path == "":
		return
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		music_on = bool(cfg.get_value("audio", "music_on", true))


func _save_settings() -> void:
	if settings_path == "":
		return
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music_on", music_on)
	cfg.save(settings_path)
