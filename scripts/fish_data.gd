extends RefCounted
## Fish varieties and how they breed. Guppies follow the guppy breeding game (common
## colours, three generations of recipes, rare mutations); goldfish have their own set.
## Other species have one variety for now (bettas get deeper breeding later).
##
## Variety fields: name, color (body), accent (fins / pattern), pattern
## ("solid", "spots", "half", "stripes", "fade"), mult (price multiplier),
## kind ("common", "recipe", "mutation"), gen (recipe generation).
## Varieties in LOCKED can't be bred or bought until a fish show unlocks them.

const ADULT_AGE := 3
## Days a fish lives, by species (each fish gets this +-15%, see lifespan()). Fish in the Hall
## of Fame stop ageing.
const LIFESPAN := {"guppy": 120, "neon": 100, "goldfish": 240, "betta": 150, "angelfish": 300}
## A valuable fish this close to the end gets a warning.
const OLD_WARN_DAYS := 10
const MUTATION_CHANCE := 0.015
const RECIPE_CHANCE := 0.3

const VARIETIES := {
	"guppy": {
		"normal": {"name": "Normal", "color": "#b9b2a0", "accent": "#d8cfb8", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"red": {"name": "Red", "color": "#e0453a", "accent": "#ff7a5c", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"blue": {"name": "Blue", "color": "#3b6fd1", "accent": "#7aa6ff", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"yellow": {"name": "Yellow", "color": "#f2cf3d", "accent": "#fff08a", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"black": {"name": "Black", "color": "#2b2b30", "accent": "#55555e", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"white": {"name": "White", "color": "#f4f1ea", "accent": "#ffffff", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"grass": {"name": "Grass", "color": "#6fae5a", "accent": "#a4d98a", "pattern": "spots", "mult": 1.0, "kind": "common"},
		"orange": {"name": "Orange", "color": "#f08a2e", "accent": "#ffb36b", "pattern": "solid", "mult": 1.4, "kind": "recipe", "gen": 1},
		"purple": {"name": "Purple", "color": "#8a52c9", "accent": "#c39bff", "pattern": "solid", "mult": 1.4, "kind": "recipe", "gen": 1},
		"pink": {"name": "Pink", "color": "#f08fb8", "accent": "#ffc4dc", "pattern": "solid", "mult": 1.4, "kind": "recipe", "gen": 1},
		"turquoise": {"name": "Turquoise", "color": "#3cc7c0", "accent": "#8af0ea", "pattern": "solid", "mult": 1.4, "kind": "recipe", "gen": 1},
		"leopard": {"name": "Leopard", "color": "#d9a441", "accent": "#3a2a18", "pattern": "spots", "mult": 1.7, "kind": "recipe", "gen": 1},
		"snakeskin": {"name": "Snakeskin", "color": "#8fa05a", "accent": "#2f3a1c", "pattern": "stripes", "mult": 1.7, "kind": "recipe", "gen": 1},
		"dalmatian": {"name": "Dalmatian", "color": "#eeeae2", "accent": "#202020", "pattern": "spots", "mult": 1.7, "kind": "recipe", "gen": 1},
		"half_black": {"name": "Half Black", "color": "#e0453a", "accent": "#202024", "pattern": "half", "mult": 1.7, "kind": "recipe", "gen": 1},
		"mosaic": {"name": "Mosaic", "color": "#6a8fc0", "accent": "#d8e4ff", "pattern": "spots", "mult": 1.7, "kind": "recipe", "gen": 1},
		"gold": {"name": "Gold", "color": "#e5b72e", "accent": "#fff2a0", "pattern": "fade", "mult": 2.0, "kind": "recipe", "gen": 2},
		"sunset": {"name": "Sunset", "color": "#f26a3d", "accent": "#ffd04a", "pattern": "fade", "mult": 2.0, "kind": "recipe", "gen": 2},
		"koi": {"name": "Koi", "color": "#f4f1ea", "accent": "#f08a2e", "pattern": "spots", "mult": 2.0, "kind": "recipe", "gen": 2},
		"pastel": {"name": "Pastel", "color": "#f7d6dc", "accent": "#cfe9ff", "pattern": "fade", "mult": 2.0, "kind": "recipe", "gen": 2},
		"tuxedo": {"name": "Tuxedo", "color": "#d8d8e0", "accent": "#18181c", "pattern": "half", "mult": 2.4, "kind": "recipe", "gen": 2},
		"neon": {"name": "Neon", "color": "#3df0d8", "accent": "#3b6fd1", "pattern": "stripes", "mult": 2.4, "kind": "recipe", "gen": 2},
		"phoenix": {"name": "Phoenix", "color": "#f5883a", "accent": "#ffe14a", "pattern": "fade", "mult": 3.2, "kind": "recipe", "gen": 3},
		"calico": {"name": "Calico", "color": "#e6b98d", "accent": "#202020", "pattern": "spots", "mult": 3.2, "kind": "recipe", "gen": 3},
		"midnight": {"name": "Midnight", "color": "#23265c", "accent": "#8a9bff", "pattern": "fade", "mult": 3.4, "kind": "recipe", "gen": 3},
		"opal": {"name": "Opal", "color": "#bfe3d6", "accent": "#f7d6ff", "pattern": "fade", "mult": 2.8, "kind": "recipe", "gen": 3},
		"tiger": {"name": "Tiger", "color": "#e89a2f", "accent": "#1c1410", "pattern": "stripes", "mult": 3.0, "kind": "recipe", "gen": 3},
		"albino": {"name": "Albino", "color": "#fbf3e6", "accent": "#ff9fb0", "pattern": "solid", "mult": 3.0, "kind": "mutation"},
		"glass": {"name": "Glass", "color": "#cfeaf2", "accent": "#ffffff", "pattern": "fade", "mult": 3.0, "kind": "mutation"},
		"lavender": {"name": "Lavender", "color": "#b79be0", "accent": "#e8dcff", "pattern": "solid", "mult": 3.2, "kind": "mutation"},
		"platinum": {"name": "Platinum", "color": "#d8dbe2", "accent": "#ffffff", "pattern": "fade", "mult": 3.5, "kind": "mutation"},
		"galaxy": {"name": "Galaxy", "color": "#2a2470", "accent": "#e8e0ff", "pattern": "spots", "mult": 4.0, "kind": "mutation"},
		"dragon": {"name": "Dragon", "color": "#c2352e", "accent": "#ffd04a", "pattern": "stripes", "mult": 4.0, "kind": "mutation"},
	},
	"goldfish": {
		"common": {"name": "Common", "color": "#f2862e", "accent": "#ffb36b", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"comet": {"name": "Comet", "color": "#e0402a", "accent": "#ff8a5c", "pattern": "solid", "mult": 1.0, "kind": "common"},
		"shubunkin": {"name": "Shubunkin", "color": "#7aa6d8", "accent": "#e0402a", "pattern": "spots", "mult": 1.0, "kind": "common"},
		"fantail": {"name": "Fantail", "color": "#f2b23d", "accent": "#fff2d0", "pattern": "fade", "mult": 1.0, "kind": "common"},
		"ryukin": {"name": "Ryukin", "color": "#f05a2e", "accent": "#ffffff", "pattern": "half", "mult": 1.5, "kind": "recipe", "gen": 1},
		"calico_fantail": {"name": "Calico Fantail", "color": "#e6b98d", "accent": "#202020", "pattern": "spots", "mult": 1.6, "kind": "recipe", "gen": 1},
		"black_moor": {"name": "Black Moor", "color": "#1c1c22", "accent": "#4a4a58", "pattern": "solid", "mult": 1.8, "kind": "recipe", "gen": 1},
		"oranda": {"name": "Oranda", "color": "#f2862e", "accent": "#ff3a2a", "pattern": "half", "mult": 2.2, "kind": "recipe", "gen": 2},
		"panda": {"name": "Panda Moor", "color": "#f4f1ea", "accent": "#1c1c22", "pattern": "half", "mult": 2.4, "kind": "recipe", "gen": 2},
		"ranchu": {"name": "Ranchu", "color": "#ff6a2a", "accent": "#fff2d0", "pattern": "fade", "mult": 3.0, "kind": "recipe", "gen": 3},
		"lionhead": {"name": "Lionhead", "color": "#d8402a", "accent": "#ffd04a", "pattern": "fade", "mult": 3.4, "kind": "recipe", "gen": 3},
		"bubble_eye": {"name": "Bubble Eye", "color": "#f2b23d", "accent": "#ffe8b0", "pattern": "solid", "mult": 3.0, "kind": "mutation"},
		"telescope": {"name": "Telescope Eye", "color": "#3a2a40", "accent": "#f2862e", "pattern": "spots", "mult": 3.2, "kind": "mutation"},
		"pearlscale": {"name": "Pearlscale", "color": "#f4e8d8", "accent": "#f2862e", "pattern": "spots", "mult": 3.6, "kind": "mutation"},
		"celestial": {"name": "Celestial", "color": "#e8c060", "accent": "#7a5cff", "pattern": "fade", "mult": 4.2, "kind": "mutation"},
	},
	"neon": {"normal": {"name": "", "color": "#3cc7f0", "accent": "#e0453a", "pattern": "stripes", "mult": 1.0, "kind": "common"}},
	"betta": {"normal": {"name": "", "color": "#c2352e", "accent": "#3b6fd1", "pattern": "fade", "mult": 1.0, "kind": "common"}},
	"angelfish": {"normal": {"name": "", "color": "#e8e4d8", "accent": "#202024", "pattern": "stripes", "mult": 1.0, "kind": "common"}},
}

## [parent a, parent b, child] per species (either order).
const RECIPES := {
	"guppy": [
		["red", "yellow", "orange"], ["red", "blue", "purple"], ["red", "white", "pink"], ["blue", "grass", "turquoise"],
		["yellow", "black", "leopard"], ["grass", "black", "snakeskin"], ["black", "white", "dalmatian"],
		["black", "red", "half_black"], ["normal", "blue", "mosaic"],
		["orange", "yellow", "gold"], ["orange", "red", "sunset"], ["orange", "white", "koi"], ["pink", "white", "pastel"],
		["half_black", "black", "tuxedo"], ["turquoise", "blue", "neon"],
		["gold", "sunset", "phoenix"], ["koi", "dalmatian", "calico"], ["tuxedo", "neon", "midnight"],
		["pastel", "turquoise", "opal"], ["leopard", "sunset", "tiger"],
	],
	"goldfish": [
		["comet", "fantail", "ryukin"], ["shubunkin", "fantail", "calico_fantail"], ["common", "shubunkin", "black_moor"],
		["ryukin", "common", "oranda"], ["black_moor", "fantail", "panda"],
		["oranda", "fantail", "ranchu"], ["oranda", "ryukin", "lionhead"],
	],
}

## Mutation pools with weights.
const MUTATIONS := {
	"guppy": {"albino": 3, "glass": 3, "lavender": 2, "platinum": 2, "galaxy": 1, "dragon": 1},
	"goldfish": {"bubble_eye": 3, "telescope": 2, "pearlscale": 1, "celestial": 1},
}

## Locked until won at fish shows, in the order they unlock: [species, variety].
const LOCKED := [["guppy", "galaxy"], ["goldfish", "lionhead"], ["goldfish", "pearlscale"], ["guppy", "dragon"], ["goldfish", "celestial"]]

## What the fish market sells: common varieties of every species (plus a few first
## generation guppies and goldfish), either sex, 1 to 3 stars.
const MARKET := {
	"guppy": ["normal", "red", "blue", "yellow", "black", "white", "grass", "orange", "purple"],
	"goldfish": ["common", "comet", "shubunkin", "fantail", "ryukin"],
	"neon": ["normal"], "betta": ["normal"], "angelfish": ["normal"],
}


static func variety(species: String, v: String) -> Dictionary:
	return VARIETIES[species].get(v, VARIETIES[species].values()[0])


static func commons(species: String) -> Array:
	var out: Array = []
	for v in VARIETIES[species]:
		if VARIETIES[species][v]["kind"] == "common":
			out.append(v)
	return out


static func is_adult(f: Dictionary) -> bool:
	return int(f.get("age", ADULT_AGE)) >= ADULT_AGE


## How many days this fish lives (fixed per fish, from its id).
static func lifespan(f: Dictionary) -> int:
	var base := float(LIFESPAN.get(f.get("species", ""), 120))
	var h := fposmod(float(int(f.get("id", 0))) * 0.6180339887, 1.0)
	return int(round(base * (0.85 + 0.3 * h)))


static func days_left(f: Dictionary) -> int:
	return lifespan(f) - int(f.get("age", 0))


static func recipe_child(species: String, a: String, b: String) -> String:
	for r in RECIPES.get(species, []):
		if (r[0] == a and r[1] == b) or (r[0] == b and r[1] == a):
			return r[2]
	return ""


## "Red Guppy", or "Guppy" for one-variety species.
static func full_name(f: Dictionary, species_name: String) -> String:
	var vname: String = variety(f["species"], f.get("variety", ""))["name"]
	return species_name if vname == "" else "%s %s" % [vname, species_name]
