## 修為與戰鬥數值。全是純函式，數值集中在這裡調。
## 境界用 tier index（煉氣 0、築基 1……）。
extends RefCounted

## 內容包 grant_exp 的檔次換算成修為
const EXP_REWARD := {"small": 15, "medium": 40, "large": 100}
## 修為到突破門檻的這個比例時，先請導演準備心魔
const HEART_DEMON_PREP := 0.8
const MEDITATE_EXP := 8
const MEDITATE_EXP_IN_SECT := 15
## 身法（docs/design/skill-tree.md）：名稱與領悟條件。
## tier 是境界 index，境界更高一定會；同境界時修為到 need 的 exp_ratio 倍也算（1.0＝圓滿）；
## flag 是事件可以直接傳授的旗標。水遁等雲夢澤有水域再加。
const MOVEMENT_SKILLS := {
	"double_jump": {"name": "輕身術", "note": "空中再按一次跳", "tier": 0, "exp_ratio": 1.0},
	"wall_jump": {"name": "踏葉", "note": "空中貼牆往牆按，再按跳往反方向蹬", "tier": 1},
	"glide": {"name": "御風", "note": "下落時按住跳滑翔", "tier": 1, "exp_ratio": 0.5, "flag": "movement.glide"},
	"earth_escape": {"name": "土遁", "note": "穿過土色薄牆", "tier": 2},
	"sword_flight": {"name": "御劍", "note": "空中按御劍鍵（預設 V 或 I）飛一小段", "tier": 3},
}


## 依境界、修為與旗標，這個身法領悟了沒
static func knows_movement(skill: String, tier: int, exp: int, flags: Dictionary = {}) -> bool:
	var rule: Dictionary = MOVEMENT_SKILLS[skill]
	var at := int(rule["tier"])
	if tier > at or (tier == at and not rule.has("exp_ratio")):
		return true
	if tier == at and exp >= float(rule["exp_ratio"]) * need(tier):
		return true
	return rule.has("flag") and flags.get(rule["flag"], false) == true


## 從 tier 突破到下一境界需要的修為
static func need(tier: int) -> int:
	return 100 * (tier + 1) * (tier + 1)


static func max_hp(tier: int) -> int:
	return 30 + 20 * tier


static func player_damage(tier: int) -> int:
	return 1 + tier


## 敵人要挨幾刀：power 1 的小怪約 4 刀；Boss（boss.* 模板）再乘 BOSS_HP，突破心魔這種高潮至少要打一陣子。
const HITS_PER_POWER := 4.0
const BOSS_HP := 4.0
## Boss 血量剩這個比例以下就發狠：前搖、收招都變短
const BOSS_ENRAGE_AT := 0.5
const BOSS_ENRAGE_SPEED := 0.65


## 敵人強度跟著內容包的最低境界走：以那個境界的出劍傷害換算成刀數
static func enemy_hp(power: float, pack_tier: int, boss := false) -> int:
	var hits := HITS_PER_POWER * power * (BOSS_HP if boss else 1.0)
	return maxi(1, ceili(hits * player_damage(pack_tier)))


static func enemy_damage(power: float, pack_tier: int) -> int:
	return maxi(1, roundi(4.0 * power * (1 + pack_tier)))


## 敵人出招：靠近 → 前搖（朱紅預兆）→ 判定 → 收招破綻。境界越高的內容包，前搖越短。
const ENEMY_WINDUP := 0.45
const ENEMY_WINDUP_MIN := 0.28
const ENEMY_RECOVER := 0.6


static func enemy_windup(pack_tier: int) -> float:
	return maxf(ENEMY_WINDUP_MIN, ENEMY_WINDUP - 0.04 * pack_tier)


static func kill_exp(power: float) -> int:
	return maxi(1, roundi(5.0 * power))
