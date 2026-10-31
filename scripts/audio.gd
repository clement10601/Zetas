## 配樂與音效。清單在 content/audio.json；檔案缺了就靜音，不影響遊戲。
## 配樂：play_music(key) 用兩個播放器交叉淡入淡出，同一首不重播。
## 音效：play(name) 從版本裡隨機挑一個（不連續重複），用播放器池同時播多個。
## 網頁版瀏覽器要使用者先按過鍵或點過畫面才會出聲；Godot 會在第一次輸入時自動解鎖，
## 在那之前排定的配樂會靜音播放，解鎖後就聽得到。
## N 鍵開關配樂（音效照常），設定存在 user://audio.cfg。
extends Node

const FADE := 1.5
const POOL_SIZE := 8
const SETTINGS_PATH := "user://audio.cfg"

var manifest_path := "res://content/audio.json"
var settings_path := SETTINGS_PATH
var music: Dictionary = {}
var sfx: Dictionary = {}
var music_on := true
var current_music := ""          # 目前（或排定）播放的清單 key
var played: Array = []           # 測試用：播過的音效名
var _music_players: Array = []
var _active := 0
var _pool: Array = []
var _cache: Dictionary = {}      # path -> AudioStream，載不到記 null
var _last_variant: Dictionary = {}


func _ready() -> void:
	var data := _read_json(manifest_path)
	music = data.get("music", {})
	sfx = data.get("sfx", {})
	_load_settings()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_music_players.append(p)
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
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## 依地圖標籤（例如心魔幻境 illusion）優先，否則用地區的曲子。
func music_key(region: String, tags: Array) -> String:
	for t in tags:
		if music.has("tag." + str(t)):
			return "tag." + str(t)
	return region if music.has(region) else ""


func play_music(key: String) -> void:
	if key == current_music:
		return
	current_music = key
	var old: AudioStreamPlayer = _music_players[_active]
	_fade(old, -60.0, true)
	if key == "" or not music_on:
		return
	var entry: Dictionary = music.get(key, {})
	var stream := _stream(str(entry.get("file", "")))
	if stream == null:
		return
	if "loop" in stream:
		stream.loop = true
	_active = 1 - _active
	var p: AudioStreamPlayer = _music_players[_active]
	p.stream = stream
	p.volume_db = -60.0
	p.play()
	_fade(p, float(entry.get("volume_db", 0.0)), false)


func _fade(p: AudioStreamPlayer, to_db: float, stop_after: bool) -> void:
	if not p.playing:
		return
	if not is_inside_tree():
		p.volume_db = to_db
		if stop_after:
			p.stop()
		return
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, FADE)
	if stop_after:
		tw.tween_callback(p.stop)


func toggle_music() -> bool:
	music_on = not music_on
	if music_on:
		var key := current_music
		current_music = ""
		play_music(key)
	else:
		_fade(_music_players[_active], -60.0, true)
	_save_settings()
	return music_on


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
	if stream == null:
		return
	var p: AudioStreamPlayer = null
	for q in _pool:
		if not q.playing:
			p = q
			break
	if p == null:
		p = _pool[0]
		_pool.push_back(_pool.pop_front())
	p.stream = stream
	p.volume_db = float(entry.get("volume_db", 0.0))
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
