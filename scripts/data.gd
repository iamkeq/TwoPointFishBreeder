extends RefCounted

const FishData := preload("res://scripts/fish_data.gd")
## Everything the shop can build, sell and order. Prices are in whole dollars.

## Fish species. `price` is what a customer pays for a 2-star fish in a plain tank.
const SPECIES := {
	"guppy": {"name": "Guppy", "price": 14, "color": Color("#f08a2e"), "size": 0.8},
	"neon": {"name": "Neon Tetra", "price": 10, "color": Color("#3cc7f0"), "size": 0.7},
	"goldfish": {"name": "Goldfish", "price": 12, "color": Color("#f2b23d"), "size": 1.1},
	"betta": {"name": "Betta", "price": 28, "color": Color("#c2352e"), "size": 1.0},
	"angelfish": {"name": "Angelfish", "price": 40, "color": Color("#e8e4d8"), "size": 1.3},
}

## Price multiplier for 1 to 5 stars.
const STAR_MULT := [0.6, 1.0, 1.6, 2.5, 4.0]

## Fish bought from the wholesaler cost this much more than a customer pays for the same
## fish, even in the best tank (appeal adds at most +50%). Profit comes from breeding.
const WHOLESALE_MULT := 1.6
## What the fish market pays for a grown fish you sell it, as a share of the shop price.
## Far below WHOLESALE_MULT, so buying to sell back never pays; it just clears surplus.
const MARKET_BUY_MULT := 0.4

## Supplies sold off the shelves. Ordered in boxes of `box` units.
const PRODUCTS := {
	"food": {"name": "Fish Food", "cost": 3, "price": 8, "box": 12, "model": "Products/SM_Prop_Product_05"},
	"conditioner": {"name": "Water Conditioner", "cost": 5, "price": 12, "box": 10, "model": "Products/SM_Prop_Product_12"},
	"gravel": {"name": "Gravel Bag", "cost": 4, "price": 10, "box": 8, "model": "Products/SM_Prop_Product_20"},
	"plants": {"name": "Aquarium Plants", "cost": 6, "price": 15, "box": 8, "model": "Products/SM_Prop_Product_31"},
	"filter": {"name": "Tank Filter", "cost": 18, "price": 40, "box": 6, "model": "Products/SM_Prop_Product_40"},
	"net": {"name": "Fish Net", "cost": 2, "price": 6, "box": 12, "model": "Products/SM_Prop_Product_08"},
}

## Things you can build. `size` is the footprint in metres (width along local X, depth
## along local Z) before rotation. `rooms`: where it may go ("show", "back", "hall").
## `appeal`: how much it adds to tanks within APPEAL_RADIUS (decor) or the tank's own base.
const ITEMS := {
	"tank_small": {"name": "Small Tank", "cat": "Tanks", "cost": 150, "size": Vector2(1.0, 0.5),
		"kind": "tank", "capacity": 4, "appeal": 5.0, "height": 1.15, "rooms": ["show", "back", "hall"]},
	"tank_medium": {"name": "Medium Tank", "cat": "Tanks", "cost": 350, "size": Vector2(1.5, 0.75),
		"kind": "tank", "capacity": 8, "appeal": 12.0, "height": 1.3, "rooms": ["show", "back", "hall"]},
	"tank_large": {"name": "Large Tank", "cat": "Tanks", "cost": 800, "size": Vector2(2.5, 1.0),
		"kind": "tank", "capacity": 14, "appeal": 25.0, "height": 1.45, "rooms": ["show", "back", "hall"]},
	"tank_holding": {"name": "Holding Tank (200 gal)", "cat": "Tanks", "cost": 500, "size": Vector2(2.5, 1.0),
		"kind": "holding", "capacity": 20, "appeal": 0.0, "height": 1.45, "rooms": ["back"]},
	"tank_breeding": {"name": "Breeding Tank", "cat": "Tanks", "cost": 400, "size": Vector2(1.5, 0.75),
		"kind": "breeding", "capacity": 6, "appeal": 0.0, "height": 1.2, "rooms": ["back"]},
	"shelf": {"name": "Supply Shelf", "cat": "Shelves", "cost": 200, "size": Vector2(2.0, 0.75),
		"kind": "shelf", "slots": 3, "capacity": 6, "model": "Props/SM_Prop_Shop_Shelf_Basic_01", "rooms": ["show"]},
	"shelf_small": {"name": "Small Shelf", "cat": "Shelves", "cost": 120, "size": Vector2(1.0, 0.5),
		"kind": "shelf", "slots": 2, "capacity": 4, "model": "Props/SM_Prop_Shop_Shelf_Basic_02", "rooms": ["show"]},
	"counter": {"name": "Till Counter", "cat": "Shop", "cost": 300, "size": Vector2(2.0, 1.0),
		"kind": "counter", "model": "Props/SM_Prop_Shop_Desk_01", "rooms": ["show"]},
	"plant": {"name": "Potted Plant", "cat": "Decor", "cost": 40, "size": Vector2(0.5, 0.5),
		"kind": "decor", "appeal": 6.0, "rooms": ["show", "back", "hall"]},
	"flowers": {"name": "Flower Stand", "cat": "Decor", "cost": 90, "size": Vector2(1.0, 0.5),
		"kind": "decor", "appeal": 12.0, "model": "Props/SM_Prop_Flower_Stand_Preset_01", "rooms": ["show", "hall"]},
	"bench": {"name": "Bench", "cat": "Decor", "cost": 80, "size": Vector2(1.5, 0.5),
		"kind": "decor", "appeal": 4.0, "model": "Props/SM_Prop_Bench_01", "rooms": ["show", "hall"]},
	"statue": {"name": "Bear Statue", "cat": "Decor", "cost": 250, "size": Vector2(1.0, 1.0),
		"kind": "decor", "appeal": 20.0, "model": "Props/SM_Prop_Bear_Statue_01", "rooms": ["show", "hall"]},
	"rug": {"name": "Rug", "cat": "Decor", "cost": 30, "size": Vector2(2.0, 1.5),
		"kind": "rug", "appeal": 5.0, "rooms": ["show", "back", "hall"], "walkable": true},
	"boxes": {"name": "Stock Boxes", "cat": "Back Room", "cost": 60, "size": Vector2(1.0, 1.0),
		"kind": "decor", "appeal": 0.0, "model": "Props/SM_Prop_Warehouse_Boxes_Stacked_01", "rooms": ["back"]},
	"pallet": {"name": "Pallet Rack", "cat": "Back Room", "cost": 120, "size": Vector2(2.0, 1.0),
		"kind": "decor", "appeal": 0.0, "model": "Props/SM_Prop_Warehouse_Pallet_Stacked_01", "rooms": ["back"]},
	"desk": {"name": "Office Desk", "cat": "Back Room", "cost": 150, "size": Vector2(1.5, 1.0),
		"kind": "decor", "appeal": 0.0, "model": "Props/SM_Prop_Shop_Desk_03", "rooms": ["back"]},
	"bowl_shelf": {"name": "Fish Bowl Shelf", "cat": "Hall of Fame", "cost": 250, "size": Vector2(1.5, 0.5),
		"kind": "bowls", "capacity": 6, "height": 1.5, "rooms": ["hall"]},
	"trophy_case": {"name": "Trophy Cabinet", "cat": "Hall of Fame", "cost": 300, "size": Vector2(1.5, 0.6),
		"kind": "trophies", "height": 1.9, "rooms": ["hall"]},
}

const CATEGORIES := ["Tanks", "Shelves", "Shop", "Decor", "Back Room", "Hall of Fame"]

## Decor within this many metres of a tank adds its appeal to that tank.
const APPEAL_RADIUS := 4.0
## A showcased tank gets a spotlight and sign: appeal x1.5, costs upkeep every month.
const SHOWCASE_MULT := 1.5
const SHOWCASE_UPKEEP := 60

## Monthly marketing: cost and how many more customers it brings.
const MARKETING := {
	"": {"name": "No marketing", "cost": 0, "boost": 0.0},
	"flyers": {"name": "Flyers", "cost": 300, "boost": 0.3},
	"paper": {"name": "Newspaper Ad", "cost": 650, "boost": 0.6},
	"radio": {"name": "Radio Spot", "cost": 1400, "boost": 1.1},
}

## Staff you can hire. Wages are paid at the end of each month.
const STAFF := {
	"cashier": {"name": "Cashier", "wage": 220, "color": Color("#ffd45c"),
		"desc": "Stands at a till counter and takes payment. Without one, customers give up and leave.",
		"models": ["Characters/Characters/SM_Chr_Clerk_Female_01", "Characters/Characters/SM_Chr_Clerk_Male_01"]},
	"stocker": {"name": "Stocker", "wage": 200, "color": Color("#7fd0ff"),
		"desc": "Carries boxes from the back room to fill the shelves.",
		"models": ["Characters/Characters/SM_Chr_Worker_Female_01", "Characters/Characters/SM_Chr_Worker_Male_01"]},
	"keeper": {"name": "Fish Keeper", "wage": 250, "color": Color("#8dffb0"),
		"desc": "Cleans tanks. Dirty water puts customers off and stops breeding.",
		"models": ["Characters/Characters/SM_Chr_Attendant_Female_01", "Characters/Characters/SM_Chr_Attendant_Male_01"]},
}
const STAFF_NAMES := ["Alex", "Sam", "Jo", "Priya", "Marcus", "Lena", "Theo", "Rosa", "Kai", "Nina",
	"Omar", "Ivy", "Ben", "Mei", "Leo", "Ada", "Finn", "Zoe", "Raj", "Tess"]

## How dirty tanks get each day: a base amount plus some per fish. 0 clean .. 100 filthy.
const DIRT_PER_DAY := 1.5
const DIRT_PER_FISH := 0.6
## Dirt above this stops a breeding pair; a keeper cleans anything dirtier than CLEAN_AT.
const BREED_DIRT_LIMIT := 60.0
const CLEAN_AT := 20.0

const RENT := 350
## Cash in hand at the start, before any loan.
const START_MONEY := 5000

## How you start: cash only, or cash plus a loan you pay back monthly.
const STARTS := {
	"none": {"name": "No debt", "loan": "", "desc": "Start with just your savings. Slow and safe."},
	"small": {"name": "Small loan", "loan": "small", "desc": "A bank loan to build a bit more from day one."},
	"large": {"name": "Large loan", "loan": "large", "desc": "Big money to build big, and big repayments every month."},
}

## Bank loans. You pay back amount x (1 + interest), spread evenly over `months`.
const LOANS := {
	"small": {"name": "Small loan", "amount": 8000, "interest": 0.10, "months": 24},
	"medium": {"name": "Business loan", "amount": 14000, "interest": 0.15, "months": 30},
	"large": {"name": "Large loan", "amount": 25000, "interest": 0.20, "months": 36},
}
## Plots you can buy to grow the shop (see layout.gd). Each also adds to the monthly rent.
const PLOTS := {
	"west": {"name": "West wing", "cost": 9000, "rent": 120, "desc": "3 bays more width on the left, for both rooms."},
	"east": {"name": "East wing", "cost": 9000, "rent": 120, "desc": "3 bays more width on the right, for both rooms."},
	"back": {"name": "Rear extension", "cost": 12000, "rent": 150, "desc": "3 bays more depth for the back room."},
	"hall": {"name": "Hall of Fame", "cost": 6000, "rent": 80, "desc": "A small room off the showroom for your best fish and your show trophies. Fish in it never grow old and its tanks never get dirty. Customers come to see it."},
}

## After this many months of trading the bank will lend again, up to EXTRA_LOANS more times.
const LOAN_WAIT_MONTHS := 3
const EXTRA_LOANS := 2
## Days a breeding pair takes to make a batch of fry.
const BREED_DAYS := 4


## What a customer pays in a plain tank: species price x stars x variety. Fry aren't for sale.
static func fish_price(fish: Dictionary) -> int:
	if not FishData.is_adult(fish):
		return 0
	var sp: Dictionary = SPECIES[fish["species"]]
	var v := FishData.variety(fish["species"], fish.get("variety", ""))
	return int(round(float(sp["price"]) * STAR_MULT[clampi(int(fish["stars"]), 1, 5) - 1] * float(v["mult"])))


## What the fish market pays you for a grown fish (0 for fry: it won't take them).
static func market_buy_price(fish: Dictionary) -> int:
	return int(floor(fish_price(fish) * MARKET_BUY_MULT))


## What the fish market charges for one adult.
static func wholesale_price(species: String, variety: String, stars: int) -> int:
	return int(ceil(fish_price({"species": species, "variety": variety, "stars": stars}) * WHOLESALE_MULT))


## "★★★☆☆ Red Guppy", or "Red Guppy fry (grows up in 2 days)". The sex shows on the icon.
static func fish_label(f: Dictionary) -> String:
	var name := FishData.full_name(f, SPECIES[f["species"]]["name"])
	if not FishData.is_adult(f):
		return "%s fry (grows up in %d day%s)" % [name, FishData.ADULT_AGE - int(f.get("age", 0)),
			"" if FishData.ADULT_AGE - int(f.get("age", 0)) == 1 else "s"]
	var ribbon := "  🎀" if int(f.get("ribbon", 0)) > 0 else ""
	var old := "  ⏳" if FishData.days_left(f) <= FishData.OLD_WARN_DAYS else ""
	return "%s %s%s%s" % [stars_text(int(f["stars"])), name, ribbon, old]


static func stars_text(stars: int) -> String:
	return "★".repeat(stars) + "☆".repeat(5 - stars)
