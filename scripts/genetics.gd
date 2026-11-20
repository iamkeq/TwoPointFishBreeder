extends RefCounted
## How a breeding tank spawns and what the babies turn out to be.
##
## Spawning: only adults of one species breed together (the species with the most adults
## in the tank; others are ignored). Each male can father broods with up to three females,
## so broods = min(females, males x 3). More males than females means they chase the
## females about and only half as many broods come. Each brood is 2 to 4 fry.
##
## Babies: a small chance of a mutation (from the unlocked mutations of that species),
## else a chance of the recipe child if the parents' varieties make one (and it is
## unlocked), else the mother's or father's variety. Stars are the parents' average
## nudged -1/0/+1, with better odds in a clean tank.

const FishData := preload("res://scripts/fish_data.gd")

const BROOD_SIZE := Vector2i(2, 4)
const FEMALES_PER_MALE := 3
const NUDGE_DIRTY := [0.25, 0.6, 0.15]
const NUDGE_NORMAL := [0.2, 0.6, 0.2]
const NUDGE_CLEAN := [0.1, 0.6, 0.3]


## What a tank's fish will do. Returns {"ok", "species", "males", "females", "broods",
## "note", "others"} where males/females are arrays of fish.
static func plan(fish: Array) -> Dictionary:
	var counts := {}
	for f in fish:
		if FishData.is_adult(f):
			counts[f["species"]] = int(counts.get(f["species"], 0)) + 1
	var out := {"ok": false, "species": "", "males": [], "females": [], "broods": 0, "note": "", "others": 0}
	if counts.is_empty():
		out["note"] = "Add adult males and females of the same species."
		return out
	var species := ""
	for s in counts:
		if species == "" or counts[s] > counts[species]:
			species = s
	out["species"] = species
	for f in fish:
		if not FishData.is_adult(f):
			continue
		if f["species"] != species:
			out["others"] = int(out["others"]) + 1
		elif f["sex"] == "m":
			out["males"].append(f)
		else:
			out["females"].append(f)
	var m: int = out["males"].size()
	var fe: int = out["females"].size()
	if m == 0 or fe == 0:
		out["note"] = "Needs at least one male (♂) and one female (♀)."
		return out
	var broods := mini(fe, m * FEMALES_PER_MALE)
	if m > fe:
		broods = maxi(1, broods / 2)
		out["note"] = "Too many males: they chase the females and spawn less. Aim for 1 male to 2-3 females."
	elif fe > m * FEMALES_PER_MALE:
		out["note"] = "%d female(s) have no male to pair with. One male covers up to %d females." % [fe - m * FEMALES_PER_MALE, FEMALES_PER_MALE]
	else:
		out["note"] = "Good ratio."
	out["ok"] = true
	out["broods"] = broods
	return out


## Chance of each baby variety from this mother and father: [[variety, chance], ...] high to low.
static func odds(species: String, mother_v: String, father_v: String, unlocked: Array) -> Array:
	var result := {}
	var pool := {}
	var total_w := 0
	for v in FishData.MUTATIONS.get(species, {}):
		if is_unlocked(species, v, unlocked):
			pool[v] = FishData.MUTATIONS[species][v]
			total_w += int(pool[v])
	var mutation := FishData.MUTATION_CHANCE if total_w > 0 else 0.0
	for v in pool:
		result[v] = float(result.get(v, 0.0)) + mutation * float(pool[v]) / total_w
	var rest := 1.0 - mutation
	var child := FishData.recipe_child(species, mother_v, father_v)
	if child != "" and is_unlocked(species, child, unlocked):
		result[child] = float(result.get(child, 0.0)) + rest * FishData.RECIPE_CHANCE
		rest *= 1.0 - FishData.RECIPE_CHANCE
	result[mother_v] = float(result.get(mother_v, 0.0)) + rest * 0.5
	result[father_v] = float(result.get(father_v, 0.0)) + rest * 0.5
	var out: Array = []
	for v in result:
		out.append([v, result[v]])
	out.sort_custom(func(a, b): return a[1] > b[1])
	return out


static func roll_variety(rng: RandomNumberGenerator, species: String, mother_v: String, father_v: String, unlocked: Array) -> String:
	var r := rng.randf()
	for o in odds(species, mother_v, father_v, unlocked):
		r -= float(o[1])
		if r <= 0.0:
			return o[0]
	return mother_v


static func nudge_odds(dirt: float) -> Array:
	if dirt < 20.0:
		return NUDGE_CLEAN
	if dirt > 50.0:
		return NUDGE_DIRTY
	return NUDGE_NORMAL


static func roll_stars(rng: RandomNumberGenerator, mother: Dictionary, father: Dictionary, dirt: float) -> int:
	var avg := (float(mother["stars"]) + float(father["stars"])) * 0.5
	var o := nudge_odds(dirt)
	var r := rng.randf()
	var nudge := -1 if r < o[0] else (0 if r < o[0] + o[1] else 1)
	return clampi(roundi(avg) + nudge, 1, 5)


static func is_unlocked(species: String, v: String, unlocked: Array) -> bool:
	for l in FishData.LOCKED:
		if l[0] == species and l[1] == v:
			return unlocked.has(species + ":" + v)
	return true


## One brood from a mother and father: an array of new fry (fish dicts without ids).
static func brood(rng: RandomNumberGenerator, mother: Dictionary, father: Dictionary, dirt: float, unlocked: Array) -> Array:
	var out: Array = []
	var gen := maxi(int(mother.get("gen", 0)), int(father.get("gen", 0))) + 1
	for i in rng.randi_range(BROOD_SIZE.x, BROOD_SIZE.y):
		out.append({
			"species": mother["species"],
			"variety": roll_variety(rng, mother["species"], mother["variety"], father["variety"], unlocked),
			"sex": "m" if rng.randf() < 0.5 else "f",
			"stars": roll_stars(rng, mother, father, dirt),
			"age": 0, "bred": true, "gen": gen,
		})
	return out
