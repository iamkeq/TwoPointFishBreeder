extends RefCounted
## The playthrough's goals (three star ratings, each a set of targets with a cash reward)
## and achievements (one-off badges). Each target reads a value from Game.stat_value():
##   customers, fish_sold, items_sold, fish_bred, profit (operating profit to date),
##   varieties (new varieties bred), mutations, best_stars, shows_won, grand_won,
##   plots, staff, loans_paid, showcases, reputation, money

const STARS := [
	{"name": "One Star Shop", "reward": 2000, "goals": [
		["customers", 150, "Serve 150 customers"],
		["fish_bred", 30, "Breed 30 fish"],
		["profit", 2000, "Make $2,000 operating profit"],
	]},
	{"name": "Two Star Shop", "reward": 5000, "goals": [
		["customers", 600, "Serve 600 customers"],
		["varieties", 6, "Breed 6 new varieties"],
		["profit", 15000, "Make $15,000 operating profit"],
		["shows_won", 1, "Win a fish show"],
	]},
	{"name": "Three Star Shop", "reward": 10000, "goals": [
		["customers", 1500, "Serve 1,500 customers"],
		["varieties", 15, "Breed 15 new varieties"],
		["best_stars", 5, "Breed a 5★ fish"],
		["profit", 50000, "Make $50,000 operating profit"],
		["grand_won", 1, "Win a Grand Show"],
	]},
]

## [id, name, description, stat, target]
const ACHIEVEMENTS := [
	["first_sale", "Open for Business", "Sell your first fish", "fish_sold", 1],
	["first_fry", "Proud Parent", "Breed your first fry", "fish_bred", 1],
	["first_variety", "Something New", "Breed a new variety", "varieties", 1],
	["varieties_10", "Colour Collector", "Breed 10 new varieties", "varieties", 10],
	["varieties_20", "Living Rainbow", "Breed 20 new varieties", "varieties", 20],
	["mutant", "Happy Accident", "Breed a mutation", "mutations", 1],
	["four_star", "Fine Specimen", "Breed a 4★ fish", "best_stars", 4],
	["five_star", "Perfection", "Breed a 5★ fish", "best_stars", 5],
	["bred_100", "Fish Factory", "Breed 100 fish", "fish_bred", 100],
	["customers_100", "Word Gets Around", "Serve 100 customers", "customers", 100],
	["customers_1000", "Local Favourite", "Serve 1,000 customers", "customers", 1000],
	["sold_100", "Fishmonger", "Sell 100 fish", "fish_sold", 100],
	["items_500", "Well Stocked", "Sell 500 supplies", "items_sold", 500],
	["show_win", "Blue Ribbon", "Win a fish show", "shows_won", 1],
	["grand_win", "Best in Show", "Win a Grand Show", "grand_won", 1],
	["shows_5", "Show Regular", "Win 5 fish shows", "shows_won", 5],
	["expand", "Room to Grow", "Buy a plot of land", "plots", 1],
	["expand_all", "Fish Empire", "Own every plot", "plots", 7],
	["team", "Dream Team", "Have 5 staff", "staff", 5],
	["debt_free", "Debt Free", "Pay off a loan", "loans_paid", 1],
	["showcase_3", "Gallery", "Showcase 3 tanks at once", "showcases", 3],
	["rep_90", "Talk of the Town", "Reach 90% reputation", "reputation", 90],
	["profit_10k", "In the Black", "Make $10,000 operating profit", "profit", 10000],
	["rich", "Big Fish", "Have $50,000 in the bank", "money", 50000],
]
