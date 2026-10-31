## 修為與戰鬥數值。全是純函式，數值集中在這裡調。
## 境界用 tier index（煉氣 0、築基 1……）。
extends RefCounted

## 內容包 grant_exp 的檔次換算成修為
const EXP_REWARD := {"small": 15, "medium": 40, "large": 100}
## 修為到突破門檻的這個比例時，先請導演準備心魔
const HEART_DEMON_PREP := 0.8
const MEDITATE_EXP := 8
const MEDITATE_EXP_IN_SECT := 15
## 身法（docs/design/skill-tree.md）：名稱與領悟條件。tier 是境界 index，full 表示該境界修為圓滿也算。
const MOVEMENT_SKILLS := {
	"double_jump": {"name": "輕身術", "note": "空中再按一次跳", "tier": 0, "full": true},
}


## 依境界與修為，這個身法領悟了沒
static func knows_movement(skill: String, tier: int, exp: int) -> bool:
	var rule: Dictionary = MOVEMENT_SKILLS[skill]
	return tier > int(rule["tier"]) or (tier == int(rule["tier"]) and rule.get("full", false) and exp >= need(tier))


## 從 tier 突破到下一境界需要的修為
static func need(tier: int) -> int:
	return 100 * (tier + 1) * (tier + 1)


static func max_hp(tier: int) -> int:
	return 30 + 20 * tier


static func player_damage(tier: int) -> int:
	return 1 + tier


## 敵人強度跟著內容包的最低境界走
static func enemy_hp(power: float, pack_tier: int) -> int:
	return maxi(1, ceili(3.0 * power * (1 + pack_tier)))


static func enemy_damage(power: float, pack_tier: int) -> int:
	return maxi(1, roundi(4.0 * power * (1 + pack_tier)))


static func kill_exp(power: float) -> int:
	return maxi(1, roundi(5.0 * power))
