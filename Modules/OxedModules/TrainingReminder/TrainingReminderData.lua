-- ============================================================================
-- Training Reminder: what each class learns from its trainer on WoW Forever,
-- by level. GENERATED, do not edit by hand.
--
-- Data.spellsByLevel[level] = { { id, cost (copper), requiredIds (spells that
--   must be known first), requiredTalentId, faction, race / races }, ... }
-- Data.overriddenGroups = lists of ranks of one spell, lowest first: knowing a
--   later one counts as knowing the earlier ones.
-- Data.questSpells[spellId] = { { races, level, area or areas, quests }, ... }:
--   spells a class quest teaches.
-- Data.petAbilityIds[spellId] = true: a hunter's pet abilities.
-- Data.tomesByLevel / Data.tomeTaughtSpells: a warlock's demon tomes.
-- Data.trainerFactions: which city reputations give a trainer discount.
-- Only the player's own class is built; the other blocks are skipped.
--
-- The spell tables in this file are used under the MIT License:
--
-- MIT License
--
-- Copyright (c) 2019
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the "Software"), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
-- ============================================================================

local addonName, OxedHub = ...

-- Forever's trainers only: on the main game this file builds nothing.
if OxedHub.IsMainline then return end

local Data = {}
OxedHub.TrainingReminderData = Data

local PLAYER_CLASS
do
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" then PLAYER_CLASS = token end
end
if PLAYER_CLASS == "DRUID" then
local class = Data

local demoralizingRoar = {99, 1735, 9490, 9747, 9898}
local bash = {5211, 6798, 8983}
local swipe = {779, 780, 769, 9754, 9908}
local maul = {6807, 6808, 6809, 8972, 9745, 9880, 9881}
local shred = {5221, 6800, 8992, 9829, 9830}
local ferociousBite = {1328618, 22568, 22827, 22828, 22829}
local rake = {1822, 1823, 1824, 9904}
local dash = {1850, 9821}
local claw = {16942, 3029, 5201, 9849, 9850}
local cower = {8998, 9000, 9892}
local rip = {1079, 9492, 9493, 9752, 9894, 9896}
local ravage = {6785, 6787, 9866, 9867}
local pounce = {9005, 9823, 9827}
local prowl = {5215, 6783, 9913}
local primalBite = {407995, 1238069, 1238070}
local lacerate = {414647, 1328617, 1328616, 414644, 1235826, 1235827} -- Both rank 1 IDs, then ranks 2-5
local bearForm = {5487, 9634} -- Bear Form is replaced when Dire Bear Form is learned

class.overriddenGroups = {
	bearForm,
	lacerate,
	demoralizingRoar,
	bash,
	swipe,
	maul,
	shred,
	ferociousBite,
	rake,
	dash,
	claw,
	cower,
	rip,
	ravage,
	pounce,
	prowl,
	primalBite
}

class.spellsByLevel = {
	[1] = {{id = 1126, cost = 10}},
	[4] = {{id = 8921, cost = 100}, {id = 774, cost = 100}},
	[6] = {{id = 467, cost = 100}, {id = 5177, cost = 100, requiredIds = {5176}}},
	[8] = {{id = 339, cost = 200}, {id = 5186, cost = 200, requiredIds = {5185}}},
	[10] = {
		{id = 99, cost = 300, requiredIds = {5487}},
		{id = 5232, cost = 300, requiredIds = {1126}},
		{id = 8924, cost = 300, requiredIds = {8921}},
		{id = 16689, cost = 300, requiredIds = {339}},
		{id = 1058, cost = 300, requiredIds = {774}}
	},
	[12] = {{id = 5229, cost = 800, requiredIds = {5487}}, {id = 8936, cost = 800}, {id = 437138, cost = 800}},
	[14] = {
		{id = 5211, cost = 900, requiredIds = {5487}},
		{id = 5187, cost = 900, requiredIds = {5186}},
		{id = 782, cost = 900, requiredIds = {467}},
		{id = 5178, cost = 900, requiredIds = {5177}}
	},
	[16] = {
		{id = 8925, cost = 1400, requiredIds = {8924}},
		{id = 1430, cost = 1400, requiredIds = {1058}},
		{id = 779, cost = 1400, requiredIds = {5487}}
	},
	[18] = {
		{id = 1062, cost = 1500, requiredIds = {339}},
		{id = 770, cost = 1500},
		{id = 2637, cost = 1500},
		{id = 6808, cost = 1500, requiredIds = {6807}},
		{id = 16810, cost = 1500, requiredIds = {16689, 1062}},
		{id = 8938, cost = 1500, requiredIds = {8936}}
	},
	[20] = {
		{id = 1735, cost = 2400, requiredIds = {99}},
		{id = 5188, cost = 2400, requiredIds = {5187}},
		{id = 6756, cost = 2400, requiredIds = {5232}},
		{id = 16864, cost = 2400},
		{id = 20484, cost = 2400},
		{id = 5221, cost = 2400, requiredIds = {768}},
		{id = 2912, cost = 2400}
	},
	[22] = {
		{id = 8926, cost = 3300, requiredIds = {8925}},
		{id = 2090, cost = 3300, requiredIds = {1430}},
		{id = 2908, cost = 3300},
		{id = 5179, cost = 3300, requiredIds = {5178}}
	},
	[24] = {
		{id = 1328618, cost = 4300, requiredIds = {768}},
		{id = 1822, cost = 4300, requiredIds = {768}},
		{id = 8939, cost = 4300, requiredIds = {8938}},
		{id = 2782, cost = 4300},
		{id = 1237948, cost = 4300, requiredIds = {437138}},
		{id = 780, cost = 4300, requiredIds = {779}},
		{id = 1075, cost = 4300, requiredIds = {782}}
	},
	[26] = {
		{id = 2893, cost = 4400},
		{id = 1850, cost = 4400, requiredIds = {768}},
		{id = 5189, cost = 4400, requiredIds = {5188}},
		{id = 6809, cost = 4400, requiredIds = {6808}},
		{id = 8949, cost = 4400, requiredIds = {2912}}
	},
	[28] = {
		{id = 5209, cost = 4500, requiredIds = {5487}},
		{id = 3029, cost = 4500, requiredIds = {16942}, requiredTalentId = 16942},
		{id = 8998, cost = 4500, requiredIds = {768}},
		{id = 5195, cost = 4500, requiredIds = {1062}},
		{id = 8927, cost = 4500, requiredIds = {8926}},
		{id = 16811, cost = 4500, requiredIds = {16810, 5195}},
		{id = 2091, cost = 4500, requiredIds = {2090}},
		{id = 9492, cost = 4500, requiredIds = {1079}}
	},
	[30] = {
		{id = 6798, cost = 4600, requiredIds = {5211}},
		{id = 778, cost = 4600, requiredIds = {770}},
		{id = 24974, cost = 4600, requiredIds = {5570}, requiredTalentId = 5570},
		{id = 5234, cost = 4600, requiredIds = {6756}},
		{id = 20739, cost = 4600, requiredIds = {20484}},
		{id = 8940, cost = 4600, requiredIds = {8939}},
		{id = 6800, cost = 4600, requiredIds = {5221}},
		{id = 740, cost = 4600},
		{id = 783, cost = 4600},
		{id = 5180, cost = 4600, requiredIds = {5179}}
	},
	[32] = {
		{id = 9490, cost = 6000, requiredIds = {1735}},
		{id = 22568, cost = 6000, requiredIds = {1328618}},
		{id = 6778, cost = 6000, requiredIds = {5189}},
		{id = 1328829, cost = 6000, requiredIds = {768}},
		{id = 6785, cost = 6000, requiredIds = {768}},
		{id = 5225, cost = 6000, requiredIds = {768}}
	},
	[34] = {
		{id = 1328616, cost = 7000, requiredIds = {414647}},
		{id = 8972, cost = 7000, requiredIds = {6809}},
		{id = 8928, cost = 7000, requiredIds = {8927}},
		{id = 1823, cost = 7000, requiredIds = {1822}},
		{id = 3627, cost = 7000, requiredIds = {2091}},
		{id = 8950, cost = 7000, requiredIds = {8949}},
		{id = 769, cost = 7000, requiredIds = {780}},
		{id = 8914, cost = 7000, requiredIds = {1075}}
	},
	[36] = {
		{id = 22842, cost = 8000, requiredIds = {5487}},
		{id = 9005, cost = 8000, requiredIds = {768}},
		{id = 8941, cost = 8000, requiredIds = {8940}},
		{id = 1237949, cost = 8000, requiredIds = {1237948}},
		{id = 9493, cost = 8000, requiredIds = {9492}}
	},
	[38] = {
		{id = 5201, cost = 9000, requiredIds = {3029}, requiredTalentId = 16942},
		{id = 5196, cost = 9000, requiredIds = {5195}},
		{id = 8903, cost = 9000, requiredIds = {6778}},
		{id = 18657, cost = 9000, requiredIds = {2637}},
		{id = 16812, cost = 9000, requiredIds = {16811, 5196}},
		{id = 8992, cost = 9000, requiredIds = {6800}},
		{id = 8955, cost = 9000, requiredIds = {2908}},
		{id = 6780, cost = 9000, requiredIds = {5180}}
	},
	[40] = {
		{id = 9000, cost = 10000, requiredIds = {8998}},
		{id = 9634, cost = 10000, requiredIds = {5487}},
		{id = 20719, cost = 10000, requiredIds = {768}},
		{id = 22827, cost = 10000, requiredIds = {22568}},
		{id = 16914, cost = 10000},
		{id = 29166, cost = 10000},
		{id = 24975, cost = 10000, requiredIds = {24974}, requiredTalentId = 5570},
		{id = 8907, cost = 10000, requiredIds = {5234}},
		{id = 8929, cost = 10000, requiredIds = {8928}},
		{id = 6783, cost = 10000, requiredIds = {5215}},
		{id = 20742, cost = 10000, requiredIds = {20739}},
		{id = 8910, cost = 10000, requiredIds = {3627}},
		{id = 8918, cost = 10000, requiredIds = {740}}
	},
	[42] = {
		{id = 9747, cost = 11000, requiredIds = {9490}},
		{id = 9749, cost = 11000, requiredIds = {778}},
		{id = 414644, cost = 11000, requiredIds = {1328616}},
		{id = 9745, cost = 11000, requiredIds = {8972}},
		{id = 6787, cost = 11000, requiredIds = {6785}},
		{id = 9750, cost = 11000, requiredIds = {8941}},
		{id = 8951, cost = 11000, requiredIds = {8950}}
	},
	[44] = {
		{id = 22812, cost = 14000},
		{id = 9758, cost = 14000, requiredIds = {8903}},
		{id = 1824, cost = 14000, requiredIds = {1823}},
		{id = 9752, cost = 14000, requiredIds = {9493}},
		{id = 9754, cost = 14000, requiredIds = {769}},
		{id = 9756, cost = 14000, requiredIds = {8914}}
	},
	[46] = {
		{id = 8983, cost = 16000, requiredIds = {6798}},
		{id = 9821, cost = 16000, requiredIds = {1850}},
		{id = 9833, cost = 16000, requiredIds = {8929}},
		{id = 9823, cost = 16000, requiredIds = {9005}},
		{id = 9839, cost = 16000, requiredIds = {8910}},
		{id = 9829, cost = 16000, requiredIds = {8992}},
		{id = 8905, cost = 16000, requiredIds = {6780}}
	},
	[48] = {
		{id = 9849, cost = 17000, requiredIds = {5201}, requiredTalentId = 16942},
		{id = 9852, cost = 17000, requiredIds = {5196}},
		{id = 22828, cost = 17000, requiredIds = {22827}},
		{id = 16813, cost = 17000, requiredIds = {16812, 9852}},
		{id = 9856, cost = 17000, requiredIds = {9750}},
		{id = 1237950, cost = 17000, requiredIds = {1237949}}
	},
	[50] = {
		{id = 9888, cost = 18000, requiredIds = {9758}},
		{id = 17401, cost = 18000, requiredIds = {16914}},
		{id = 24976, cost = 18000, requiredIds = {24975}, requiredTalentId = 5570},
		{id = 1235826, cost = 18000, requiredIds = {414644}},
		{id = 9884, cost = 18000, requiredIds = {8907}},
		{id = 9880, cost = 18000, requiredIds = {9745}},
		{id = 1238069, cost = 18000, requiredIds = {407995}, requiredTalentId = 407995},
		{id = 9866, cost = 18000, requiredIds = {6787}},
		{id = 20747, cost = 18000, requiredIds = {20742}},
		{id = 9875, cost = 18000, requiredIds = {8951}},
		{id = 9862, cost = 18000, requiredIds = {8918}},
		{id = 1238214, cost = 18000, requiredIds = {408120}, requiredTalentId = 408120}
	},
	[52] = {
		{id = 9892, cost = 23000, requiredIds = {9000}},
		{id = 9898, cost = 23000, requiredIds = {9747}},
		{id = 9834, cost = 23000, requiredIds = {9833}},
		{id = 9840, cost = 23000, requiredIds = {9839}},
		{id = 9894, cost = 23000, requiredIds = {9752}}
	},
	[54] = {
		{id = 9907, cost = 24000, requiredIds = {9749}},
		{id = 9904, cost = 24000, requiredIds = {1824}},
		{id = 9857, cost = 24000, requiredIds = {9856}},
		{id = 9830, cost = 24000, requiredIds = {9829}},
		{id = 9901, cost = 24000, requiredIds = {8955}},
		{id = 9908, cost = 24000, requiredIds = {9754}},
		{id = 9910, cost = 24000, requiredIds = {9756}},
		{id = 9912, cost = 24000, requiredIds = {8905}}
	},
	[56] = {
		{id = 22829, cost = 25000, requiredIds = {22828}},
		{id = 9889, cost = 25000, requiredIds = {9888}},
		{id = 9827, cost = 25000, requiredIds = {9823}}
	},
	[58] = {
		{id = 9850, cost = 26000, requiredIds = {9849}, requiredTalentId = 16942},
		{id = 9853, cost = 26000, requiredIds = {9852}},
		{id = 18658, cost = 26000, requiredIds = {18657}},
		{id = 1235827, cost = 26000, requiredIds = {1235826}},
		{id = 9881, cost = 26000, requiredIds = {9880}},
		{id = 9835, cost = 26000, requiredIds = {9834}},
		{id = 17329, cost = 26000, requiredIds = {16813, 9853}},
		{id = 9867, cost = 26000, requiredIds = {9866}},
		{id = 9841, cost = 26000, requiredIds = {9840}},
		{id = 9876, cost = 26000, requiredIds = {9875}}
	},
	[60] = {
		{id = 17402, cost = 28000, requiredIds = {17401}},
		{id = 24977, cost = 28000, requiredIds = {24976}, requiredTalentId = 5570},
		{id = 9885, cost = 28000, requiredIds = {9884}},
		{id = 1238070, cost = 28000, requiredIds = {1238069}, requiredTalentId = 407995},
		{id = 9913, cost = 28000, requiredIds = {6783}},
		{id = 20748, cost = 28000, requiredIds = {20747}},
		{id = 9858, cost = 28000, requiredIds = {9857}},
		{id = 1237951, cost = 28000, requiredIds = {1237950}},
		{id = 9896, cost = 28000, requiredIds = {9894}},
		{id = 9863, cost = 28000, requiredIds = {9862}},
		{id = 1238215, cost = 28000, requiredIds = {1238214}, requiredTalentId = 408120}
	}
}
end

if PLAYER_CLASS == "HUNTER" then
local class = Data

class.spellsByLevel = {
	[1] = {{id = 1494, cost = 10}},
	[4] = {{id = 13163, cost = 100}, {id = 1978, cost = 100}},
	[6] = {{id = 3044, cost = 100}, {id = 1130, cost = 100}},
	[8] = {{id = 5116, cost = 200}, {id = 3127, cost = 200}, {id = 14260, cost = 200}},
	[10] = {
		{id = 13165, cost = 400},
		{id = 13549, cost = 400, requiredIds = {1978}},
		{id = 19883, cost = 400},
		{id = 4187, cost = 10},
		{id = 24545, cost = 10}
	},
	[12] = {
		{id = 14281, cost = 600, requiredIds = {3044}},
		{id = 20736, cost = 600},
		{id = 136, cost = 600, requiredIds = {1515}},
		{id = 2974, cost = 600},
		{id = 4188, cost = 120, requiredIds = {4187}},
		{id = 24549, cost = 120, requiredIds = {24545}}
	},
	[14] = {{id = 6197, cost = 1200}, {id = 1002, cost = 1200}, {id = 1513, cost = 1200}},
	[16] = {{id = 13795, cost = 1500}, {id = 1495, cost = 1500}, {id = 14261, cost = 1500, requiredIds = {14260}}},
	[18] = {
		{id = 14318, cost = 1600, requiredIds = {13165}},
		{id = 2643, cost = 1600},
		{id = 13550, cost = 1600, requiredIds = {13549}},
		{id = 19884, cost = 1600},
		{id = 4189, cost = 400, requiredIds = {4188}},
		{id = 24550, cost = 400, requiredIds = {24549}}
	},
	[20] = {
		{id = 19434, cost = 2100},
		{id = 14282, cost = 2100, requiredIds = {14281}},
		{id = 5118, cost = 2100},
		{id = 781, cost = 2100},
		{id = 14274, cost = 2100, requiredIds = {20736}},
		{id = 674, cost = 2100},
		{id = 1499, cost = 2100},
		{id = 3111, cost = 2100, requiredIds = {136}},
		{id = 24493, cost = 440},
		{id = 23992, cost = 440},
		{id = 24446, cost = 440},
		{id = 14917, cost = 440},
		{id = 24492, cost = 440},
		{id = 24488, cost = 440}
	},
	[22] = {{id = 14323, cost = 7000, requiredIds = {1130}}, {id = 3043, cost = 7000}},
	[24] = {
		{id = 1462, cost = 7200},
		{id = 14262, cost = 7200, requiredIds = {14261}},
		{id = 19885, cost = 7200},
		{id = 4190, cost = 1400, requiredIds = {4189}},
		{id = 24551, cost = 1400, requiredIds = {24550}}
	},
	[26] = {
		{id = 14302, cost = 7400, requiredIds = {13795}},
		{id = 3045, cost = 7400},
		{id = 13551, cost = 7400, requiredIds = {13550}},
		{id = 19880, cost = 7400}
	},
	[28] = {
		{id = 20900, cost = 7500, requiredIds = {19434}},
		{id = 14283, cost = 7500, requiredIds = {14282}},
		{id = 14319, cost = 7500, requiredIds = {14318}},
		{id = 13809, cost = 7500},
		{id = 3661, cost = 7500, requiredIds = {3111}}
	},
	[30] = {
		{id = 13161, cost = 7600},
		{id = 1242634, cost = 7600, requiredIds = {19306}, requiredTalentId = 19306},
		{id = 15629, cost = 7600, requiredIds = {14274}},
		{id = 5384, cost = 7600},
		{id = 14269, cost = 7600, requiredIds = {1495}},
		{id = 14326, cost = 7600, requiredIds = {1513}},
		{id = 24497, cost = 1600, requiredIds = {24493}},
		{id = 24439, cost = 1600, requiredIds = {23992}},
		{id = 24447, cost = 1600, requiredIds = {24446}},
		{id = 4191, cost = 1600, requiredIds = {4190}},
		{id = 14918, cost = 1600, requiredIds = {14917}},
		{id = 24552, cost = 1600, requiredIds = {24551}},
		{id = 24502, cost = 1600, requiredIds = {24492}},
		{id = 24505, cost = 1600, requiredIds = {24488}}
	},
	[32] = {
		{id = 1543, cost = 10000},
		{id = 14263, cost = 10000, requiredIds = {14262}},
		{id = 19878, cost = 10000},
		{id = 1299348, cost = 10000, requiredIds = {1299346}, requiredTalentId = 1299346}
	},
	[34] = {
		{id = 14272, cost = 11000, requiredIds = {781}},
		{id = 13813, cost = 11000},
		{id = 13552, cost = 11000, requiredIds = {13551}}
	},
	[36] = {
		{id = 20901, cost = 13000, requiredIds = {20900}},
		{id = 14284, cost = 13000, requiredIds = {14283}},
		{id = 14303, cost = 13000, requiredIds = {14302}},
		{id = 3662, cost = 13000, requiredIds = {3661}},
		{id = 1293525, cost = 13000, requiredIds = {1293241}, requiredTalentId = 1293241},
		{id = 3034, cost = 13000},
		{id = 4192, cost = 2800, requiredIds = {4191}},
		{id = 24553, cost = 2800, requiredIds = {24552}}
	},
	[38] = {{id = 14320, cost = 15000, requiredIds = {14319}}, {id = 14267, cost = 15000, requiredIds = {2974}}},
	[40] = {
		{id = 1299445, cost = 16000, requiredIds = {13161}},
		{id = 13159, cost = 16000},
		{id = 15630, cost = 16000, requiredIds = {15629}},
		{id = 14310, cost = 16000, requiredIds = {1499}},
		{id = 14324, cost = 16000, requiredIds = {14323}},
		{id = 8737, cost = 16000},
		{id = 14264, cost = 16000, requiredIds = {14263}},
		{id = 19882, cost = 16000},
		{id = 19506, cost = 16000, requiredIds = {1299348}, requiredTalentId = 1299346},
		{id = 1510, cost = 16000},
		{id = 24500, cost = 3600, requiredIds = {24497}},
		{id = 24444, cost = 3600, requiredIds = {24439}},
		{id = 24448, cost = 3600, requiredIds = {24447}},
		{id = 14919, cost = 3600, requiredIds = {14918}},
		{id = 24503, cost = 3600, requiredIds = {24502}},
		{id = 24506, cost = 3600, requiredIds = {24505}}
	},
	[42] = {
		{id = 20909, cost = 22000, requiredIds = {1242634}, requiredTalentId = 19306},
		{id = 13553, cost = 22000, requiredIds = {13552}},
		{id = 4193, cost = 4800, requiredIds = {4192}},
		{id = 24554, cost = 4800, requiredIds = {24553}}
	},
	[44] = {
		{id = 20902, cost = 23000, requiredIds = {20901}},
		{id = 14285, cost = 23000, requiredIds = {14284}},
		{id = 14316, cost = 23000, requiredIds = {13813}},
		{id = 13542, cost = 23000, requiredIds = {3662}},
		{id = 14270, cost = 23000, requiredIds = {14269}}
	},
	[46] = {
		{id = 20043, cost = 28000},
		{id = 14304, cost = 28000, requiredIds = {14303}},
		{id = 14327, cost = 28000, requiredIds = {14326}},
		{id = 14279, cost = 28000, requiredIds = {3034}}
	},
	[48] = {
		{id = 14321, cost = 29000, requiredIds = {14320}},
		{id = 14273, cost = 29000, requiredIds = {14272}},
		{id = 14265, cost = 29000, requiredIds = {14264}},
		{id = 1310785, cost = 29000, requiredIds = {1310687}, requiredTalentId = 1310687},
		{id = 1293526, cost = 29000, requiredIds = {1293525}, requiredTalentId = 1293241},
		{id = 4194, cost = 6400, requiredIds = {4193}},
		{id = 24555, cost = 6400, requiredIds = {24554}}
	},
	[50] = {
		{id = 1299446, cost = 30000, requiredIds = {1299445}},
		{id = 15631, cost = 30000, requiredIds = {15630}},
		{id = 13554, cost = 30000, requiredIds = {13553}},
		{id = 19879, cost = 30000},
		{id = 20905, cost = 30000, requiredIds = {19506}, requiredTalentId = 1299346},
		{id = 14294, cost = 30000, requiredIds = {1510}},
		{id = 24501, cost = 7200, requiredIds = {24500}},
		{id = 24445, cost = 7200, requiredIds = {24444}},
		{id = 24449, cost = 7200, requiredIds = {24448}},
		{id = 14920, cost = 7200, requiredIds = {14919}},
		{id = 24504, cost = 7200, requiredIds = {24503}},
		{id = 24507, cost = 7200, requiredIds = {24506}}
	},
	[52] = {
		{id = 20903, cost = 36000, requiredIds = {20902}},
		{id = 14286, cost = 36000, requiredIds = {14285}},
		{id = 13543, cost = 36000, requiredIds = {13542}}
	},
	[54] = {
		{id = 20910, cost = 37000, requiredIds = {20909}, requiredTalentId = 19306},
		{id = 14317, cost = 37000, requiredIds = {14316}},
		{id = 5041, cost = 8400, requiredIds = {4194}},
		{id = 24629, cost = 8400, requiredIds = {24555}}
	},
	[56] = {
		{id = 20190, cost = 38000, requiredIds = {20043}},
		{id = 14305, cost = 38000, requiredIds = {14304}},
		{id = 14266, cost = 38000, requiredIds = {14265}},
		{id = 14280, cost = 38000, requiredIds = {14279}}
	},
	[58] = {
		{id = 14322, cost = 39000, requiredIds = {14321}},
		{id = 14325, cost = 39000, requiredIds = {14324}},
		{id = 14271, cost = 39000, requiredIds = {14270}},
		{id = 13555, cost = 39000, requiredIds = {13554}},
		{id = 1310786, cost = 39000, requiredIds = {1310785}, requiredTalentId = 1310687},
		{id = 14295, cost = 39000, requiredIds = {14294}}
	},
	[60] = {
		{id = 20904, cost = 42000, requiredIds = {20903}},
		{id = 14287, cost = 42000, requiredIds = {14286}},
		{id = 1299447, cost = 42000, requiredIds = {1299446}},
		{id = 15632, cost = 42000, requiredIds = {15631}},
		{id = 14311, cost = 42000, requiredIds = {14310}},
		{id = 13544, cost = 42000, requiredIds = {13543}},
		{id = 1293527, cost = 42000, requiredIds = {1293526}, requiredTalentId = 1293241},
		{id = 20906, cost = 42000, requiredIds = {20905}, requiredTalentId = 1299346},
		{id = 14268, cost = 42000, requiredIds = {14267}},
		{id = 5042, cost = 10000, requiredIds = {5041}},
		{id = 14921, cost = 10000, requiredIds = {14920}},
		{id = 24630, cost = 10000, requiredIds = {24629}}
	}
}
end

if PLAYER_CLASS == "MAGE" then
local class = Data

class.spellsByLevel = {
	[1] = {{id = 1459, cost = 10}},
	[4] = {{id = 5504, cost = 100}, {id = 116, cost = 100}},
	[6] = {
		{id = 1296017, cost = 100},
		{id = 587, cost = 100},
		{id = 2136, cost = 100},
		{id = 143, cost = 100, requiredIds = {133}}
	},
	[8] = {{id = 5143, cost = 200}, {id = 205, cost = 200, requiredIds = {116}}, {id = 118, cost = 200}},
	[10] = {
		{id = 5505, cost = 300, requiredIds = {5504}},
		{id = 7300, cost = 300, requiredIds = {168}},
		{id = 122, cost = 300}
	},
	[12] = {
		{id = 597, cost = 600, requiredIds = {587}},
		{id = 604, cost = 600},
		{id = 145, cost = 600, requiredIds = {143}},
		{id = 130, cost = 600}
	},
	[14] = {
		{id = 1449, cost = 900},
		{id = 1460, cost = 900, requiredIds = {1459}},
		{id = 2137, cost = 900, requiredIds = {2136}},
		{id = 837, cost = 900, requiredIds = {205}}
	},
	[16] = {{id = 5144, cost = 1700, requiredIds = {5143}}, {id = 2120, cost = 1700}},
	[18] = {{id = 1008, cost = 1800}, {id = 3140, cost = 1800, requiredIds = {145}}, {id = 475, cost = 1800}},
	[20] = {
		{id = 1953, cost = 2100},
		{id = 10, cost = 2100},
		{id = 5506, cost = 2100, requiredIds = {5505}},
		{id = 12051, cost = 2100},
		{id = 543, cost = 2100},
		{id = 7301, cost = 2100, requiredIds = {7300}},
		{id = 7322, cost = 2100, requiredIds = {837}},
		{id = 1463, cost = 2100},
		{id = 12824, cost = 2100, requiredIds = {118}},
		{id = 3561, cost = 2000, faction = "Alliance"},
		{id = 3562, cost = 2000, faction = "Alliance"},
		{id = 3563, cost = 2000, faction = "Horde"},
		{id = 3567, cost = 2000, faction = "Horde"}
	},
	[22] = {
		{id = 8437, cost = 3300, requiredIds = {1449}},
		{id = 990, cost = 3300, requiredIds = {597}},
		{id = 2138, cost = 3300, requiredIds = {2137}},
		{id = 6143, cost = 3300},
		{id = 2948, cost = 3300}
	},
	[24] = {
		{id = 5145, cost = 4300, requiredIds = {5144}},
		{id = 2139, cost = 4300},
		{id = 8450, cost = 4300, requiredIds = {604}},
		{id = 8400, cost = 4300, requiredIds = {3140}},
		{id = 2121, cost = 4300, requiredIds = {2120}},
		{id = 12505, cost = 4300, requiredIds = {11366}, requiredTalentId = 11366}
	},
	[26] = {
		{id = 120, cost = 4800},
		{id = 865, cost = 4800, requiredIds = {122}},
		{id = 8406, cost = 4800, requiredIds = {7322}}
	},
	[28] = {
		{id = 1461, cost = 5500, requiredIds = {1460}},
		{id = 6141, cost = 5500, requiredIds = {10}},
		{id = 759, cost = 5500},
		{id = 400640, cost = 5500, requiredIds = {1312002}, requiredTalentId = 1312002},
		{id = 8494, cost = 5500, requiredIds = {1463}},
		{id = 8444, cost = 5500, requiredIds = {2948}}
	},
	[30] = {
		{id = 8455, cost = 6200, requiredIds = {1008}},
		{id = 1239696, cost = 6200, requiredIds = {400574}, requiredTalentId = 400574},
		{id = 8438, cost = 6200, requiredIds = {8437}},
		{id = 6127, cost = 6200, requiredIds = {5506}},
		{id = 8412, cost = 6200, requiredIds = {2138}},
		{id = 8457, cost = 6200, requiredIds = {543}},
		{id = 8401, cost = 6200, requiredIds = {8400}},
		{id = 7302, cost = 6200},
		{id = 12522, cost = 6200, requiredIds = {12505}, requiredTalentId = 11366},
		{id = 3565, cost = 8000, faction = "Alliance"},
		{id = 3566, cost = 8000, faction = "Horde"}
	},
	[32] = {
		{id = 8416, cost = 8000, requiredIds = {5145}},
		{id = 6129, cost = 8000, requiredIds = {990}},
		{id = 8422, cost = 8000, requiredIds = {2121}},
		{id = 8461, cost = 8000, requiredIds = {6143}},
		{id = 8407, cost = 8000, requiredIds = {8406}}
	},
	[34] = {
		{id = 8492, cost = 9000, requiredIds = {120}},
		{id = 1240044, cost = 9000, requiredIds = {400640}, requiredTalentId = 1312002},
		{id = 6117, cost = 9000},
		{id = 8445, cost = 9000, requiredIds = {8444}}
	},
	[36] = {
		{id = 1326080, cost = 11000, requiredIds = {1326079}, requiredTalentId = 1326079},
		{id = 13018, cost = 11000, requiredIds = {11113}, requiredTalentId = 11113},
		{id = 8427, cost = 11000, requiredIds = {6141}},
		{id = 8451, cost = 11000, requiredIds = {8450}},
		{id = 8402, cost = 11000, requiredIds = {8401}},
		{id = 8495, cost = 11000, requiredIds = {8494}},
		{id = 12523, cost = 11000, requiredIds = {12522}, requiredTalentId = 11366}
	},
	[38] = {
		{id = 8439, cost = 12000, requiredIds = {8438}},
		{id = 3552, cost = 12000, requiredIds = {759}},
		{id = 8413, cost = 12000, requiredIds = {8412}},
		{id = 8408, cost = 12000, requiredIds = {8407}}
	},
	[40] = {
		{id = 1239697, cost = 13000, requiredIds = {1239696}, requiredTalentId = 400574},
		{id = 8417, cost = 13000, requiredIds = {8416}},
		{id = 10138, cost = 13000, requiredIds = {6127}},
		{id = 8458, cost = 13000, requiredIds = {8457}},
		{id = 8423, cost = 13000, requiredIds = {8422}},
		{id = 6131, cost = 13000, requiredIds = {865}},
		{id = 401502, cost = 13000},
		{id = 7320, cost = 13000, requiredIds = {7302}},
		{id = 12825, cost = 13000, requiredIds = {12824}},
		{id = 8446, cost = 13000, requiredIds = {8445}},
		{id = 10059, cost = 15000, faction = "Alliance"},
		{id = 11416, cost = 15000, faction = "Alliance"},
		{id = 11417, cost = 15000, faction = "Horde"},
		{id = 11418, cost = 15000, faction = "Horde"}
	},
	[42] = {
		{id = 10169, cost = 14000, requiredIds = {8455}},
		{id = 10156, cost = 14000, requiredIds = {1461}},
		{id = 10159, cost = 14000, requiredIds = {8492}},
		{id = 10144, cost = 14000, requiredIds = {6129}},
		{id = 10148, cost = 14000, requiredIds = {8402}},
		{id = 8462, cost = 14000, requiredIds = {8461}},
		{id = 1240045, cost = 14000, requiredIds = {1240044}, requiredTalentId = 1312002},
		{id = 12524, cost = 14000, requiredIds = {12523}, requiredTalentId = 11366}
	},
	[44] = {
		{id = 13019, cost = 15000, requiredIds = {13018}, requiredTalentId = 11113},
		{id = 10185, cost = 15000, requiredIds = {8427}},
		{id = 10179, cost = 15000, requiredIds = {8408}},
		{id = 10191, cost = 15000, requiredIds = {8495}}
	},
	[46] = {
		{id = 10201, cost = 20000, requiredIds = {8439}},
		{id = 10197, cost = 20000, requiredIds = {8413}},
		{id = 13031, cost = 20000, requiredIds = {11426}, requiredTalentId = 11426},
		{id = 22782, cost = 21000, requiredIds = {6117}},
		{id = 10205, cost = 20000, requiredIds = {8446}}
	},
	[48] = {
		{id = 10211, cost = 21000, requiredIds = {8417}},
		{id = 1326081, cost = 22000, requiredIds = {1326080}, requiredTalentId = 1326079},
		{id = 10053, cost = 21000, requiredIds = {3552}},
		{id = 10173, cost = 21000, requiredIds = {8451}},
		{id = 10149, cost = 21000, requiredIds = {10148}},
		{id = 10215, cost = 21000, requiredIds = {8423}},
		{id = 1240046, cost = 21000, requiredIds = {1240045}, requiredTalentId = 1312002},
		{id = 12525, cost = 21000, requiredIds = {12524}, requiredTalentId = 11366}
	},
	[50] = {
		{id = 1239699, cost = 23000, requiredIds = {1239697}, requiredTalentId = 400574},
		{id = 10160, cost = 23000, requiredIds = {10159}},
		{id = 10139, cost = 23000, requiredIds = {10138}},
		{id = 10223, cost = 23000, requiredIds = {8458}},
		{id = 10180, cost = 23000, requiredIds = {10179}},
		{id = 1237312, cost = 23000, requiredIds = {401502}},
		{id = 10219, cost = 23000, requiredIds = {7320}},
		{id = 11419, cost = 32000, faction = "Alliance"},
		{id = 11420, cost = 32000, faction = "Horde"}
	},
	[52] = {
		{id = 13020, cost = 24000, requiredIds = {13019}, requiredTalentId = 11113},
		{id = 10186, cost = 24000, requiredIds = {10185}},
		{id = 10145, cost = 24000, requiredIds = {10144}},
		{id = 10177, cost = 24000, requiredIds = {8462}},
		{id = 13032, cost = 24000, requiredIds = {13031}, requiredTalentId = 11426},
		{id = 10192, cost = 24000, requiredIds = {10191}},
		{id = 10206, cost = 24000, requiredIds = {10205}}
	},
	[54] = {
		{id = 10170, cost = 26000, requiredIds = {10169}},
		{id = 10202, cost = 26000, requiredIds = {10201}},
		{id = 10199, cost = 26000, requiredIds = {10197}},
		{id = 10150, cost = 26000, requiredIds = {10149}},
		{id = 10230, cost = 26000, requiredIds = {6131}},
		{id = 12526, cost = 26000, requiredIds = {12525}, requiredTalentId = 11366}
	},
	[56] = {
		{id = 10157, cost = 28000, requiredIds = {10156}},
		{id = 10212, cost = 28000, requiredIds = {10211}},
		{id = 10216, cost = 28000, requiredIds = {10215}},
		{id = 10181, cost = 28000, requiredIds = {10180}},
		{id = 1240047, cost = 28000, requiredIds = {1240046}, requiredTalentId = 1312002}
	},
	[58] = {
		{id = 10161, cost = 29000, requiredIds = {10160}},
		{id = 10054, cost = 29000, requiredIds = {10053}},
		{id = 13033, cost = 29000, requiredIds = {13032}, requiredTalentId = 11426},
		{id = 22783, cost = 29000, requiredIds = {22782}},
		{id = 10207, cost = 29000, requiredIds = {10206}}
	},
	[60] = {
		{id = 1239700, cost = 30000, requiredIds = {1239699}, requiredTalentId = 400574},
		{id = 1326082, cost = 30000, requiredIds = {1326081}, requiredTalentId = 1326079},
		{id = 13021, cost = 30000, requiredIds = {13020}, requiredTalentId = 11113},
		{id = 10187, cost = 30000, requiredIds = {10186}},
		{id = 10174, cost = 30000, requiredIds = {10173}},
		{id = 10225, cost = 30000, requiredIds = {10223}},
		{id = 10151, cost = 30000, requiredIds = {10150}},
		{id = 1237313, cost = 30000, requiredIds = {1237312}},
		{id = 10220, cost = 30000, requiredIds = {10219}},
		{id = 10193, cost = 30000, requiredIds = {10192}},
		{id = 12826, cost = 30000, requiredIds = {12825}},
		{id = 18809, cost = 30000, requiredIds = {12526}, requiredTalentId = 11366}
	}
}
end

if PLAYER_CLASS == "PALADIN" then
local class = Data

local devotionAura = {465, 10290, 643, 10291, 1032, 10292, 10293}
local layOnHands = {633, 2800, 10310}
local retributionAura = {7294, 10298, 10299, 10300, 10301}
local shadowResistanceAura = {19876, 19895, 19896}
local frostResistanceAura = {19888, 19897, 19898}
local fireResistanceAura = {19891, 19899, 19900}

class.overriddenGroups = {
	{20154, 21084}, -- SoR rank 1 is replaced when Judgement is learned
	devotionAura,
	layOnHands,
	retributionAura,
	shadowResistanceAura,
	frostResistanceAura,
	fireResistanceAura
}

class.spellsByLevel = {
	[1] = {{id = 465, cost = 10}},
	[4] = {{id = 19740, cost = 100}, {id = 20271, cost = 100}},
	[6] = {
		{id = 498, cost = 100},
		{id = 639, cost = 100, requiredIds = {635}},
		{id = 679, cost = 100},
		{id = 21082, cost = 100}
	},
	[8] = {{id = 853, cost = 100}, {id = 3127, cost = 100}, {id = 1152, cost = 100}},
	[10] = {
		{id = 1022, cost = 300},
		{id = 10290, cost = 300, requiredIds = {465}},
		{id = 633, cost = 300},
		{id = 25780, cost = 300},
		{id = 1311649, cost = 300},
		{id = 20287, cost = 300, requiredIds = {20154}}
	},
	[12] = {
		{id = 19834, cost = 800, requiredIds = {19740}},
		{id = 678, cost = 800, requiredIds = {679}},
		{id = 20162, cost = 800, requiredIds = {21082}}
	},
	[14] = {{id = 19742, cost = 1400}, {id = 647, cost = 1400, requiredIds = {639}}},
	[16] = {{id = 7294, cost = 1500}},
	[18] = {
		{id = 1044, cost = 1600},
		{id = 5573, cost = 1600, requiredIds = {498}},
		{id = 1311656, cost = 1600, requiredIds = {1311649}},
		{id = 20288, cost = 1600, requiredIds = {20287}}
	},
	[20] = {
		{id = 20217, cost = 3100},
		{id = 26573, cost = 3100},
		{id = 643, cost = 3100, requiredIds = {10290}},
		{id = 879, cost = 3100},
		{id = 19750, cost = 3100},
		{id = 1866, cost = 3100, requiredIds = {678}}
	},
	[22] = {
		{id = 19835, cost = 3400, requiredIds = {19834}},
		{id = 19746, cost = 3400},
		{id = 1026, cost = 3400, requiredIds = {647}},
		{id = 20164, cost = 3400},
		{id = 20305, cost = 3400, requiredIds = {20162}}
	},
	[24] = {
		{id = 5599, cost = 4800, requiredIds = {1022}},
		{id = 19850, cost = 4800, requiredIds = {19742}},
		{id = 5588, cost = 4800, requiredIds = {853}},
		{id = 10322, cost = 4800, requiredIds = {7328}},
		{id = 2878, cost = 4800}
	},
	[26] = {
		{id = 19939, cost = 6100, requiredIds = {19750}},
		{id = 10298, cost = 6100, requiredIds = {7294}},
		{id = 20163, cost = 6100, requiredIds = {1311656}},
		{id = 20289, cost = 6100, requiredIds = {20288}}
	},
	[28] = {
		{id = 5614, cost = 8000, requiredIds = {879}},
		{id = 680, cost = 8000, requiredIds = {1866}},
		{id = 19876, cost = 8000}
	},
	[30] = {
		{id = 20116, cost = 9000, requiredIds = {26573}},
		{id = 10291, cost = 9000, requiredIds = {643}},
		{id = 19752, cost = 9000},
		{id = 1042, cost = 9000, requiredIds = {1026}},
		{id = 2800, cost = 9000, requiredIds = {633}},
		{id = 20915, cost = 9000, requiredIds = {20375}, requiredTalentId = 20375},
		{id = 20165, cost = 9000}
	},
	[32] = {
		{id = 19836, cost = 10000, requiredIds = {19835}},
		{id = 19888, cost = 10000},
		{id = 20306, cost = 10000, requiredIds = {20305}}
	},
	[34] = {
		{id = 19852, cost = 11000, requiredIds = {19850}},
		{id = 642, cost = 11000},
		{id = 19940, cost = 11000, requiredIds = {19939}},
		{id = 20419, cost = 11000, requiredIds = {20163}},
		{id = 20290, cost = 11000, requiredIds = {20289}}
	},
	[36] = {
		{id = 5615, cost = 12000, requiredIds = {5614}},
		{id = 19891, cost = 12000},
		{id = 2495, cost = 12000, requiredIds = {680}},
		{id = 10324, cost = 12000, requiredIds = {10322}},
		{id = 10299, cost = 12000, requiredIds = {10298}}
	},
	[38] = {
		{id = 10278, cost = 13000, requiredIds = {5599}},
		{id = 3472, cost = 13000, requiredIds = {1042}},
		{id = 20166, cost = 13000},
		{id = 5627, cost = 13000, requiredIds = {2878}}
	},
	[40] = {
		{id = 20922, cost = 15000, requiredIds = {20116}},
		{id = 1032, cost = 15000, requiredIds = {10291}},
		{id = 5589, cost = 15000, requiredIds = {5588}},
		{id = 20927, cost = 15000, requiredIds = {20925}, requiredTalentId = 20925},
		{id = 20473, cost = 15000, requiredIds = {1311606}, requiredTalentId = 1311606},
		{id = 750, cost = 15000},
		{id = 20918, cost = 15000, requiredIds = {20915}, requiredTalentId = 20375},
		{id = 20347, cost = 15000, requiredIds = {20165}},
		{id = 19895, cost = 15000, requiredIds = {19876}}
	},
	[42] = {
		{id = 19837, cost = 16000, requiredIds = {19836}},
		{id = 4987, cost = 16000},
		{id = 19941, cost = 16000, requiredIds = {19940}},
		{id = 20421, cost = 16000, requiredIds = {20419}},
		{id = 20291, cost = 16000, requiredIds = {20290}},
		{id = 20307, cost = 16000, requiredIds = {20306}}
	},
	[44] = {
		{id = 19853, cost = 17000, requiredIds = {19852}},
		{id = 10312, cost = 17000, requiredIds = {5615}},
		{id = 19897, cost = 17000, requiredIds = {19888}},
		{id = 24275, cost = 17000},
		{id = 5569, cost = 17000, requiredIds = {2495}}
	},
	[46] = {
		{id = 6940, cost = 21000},
		{id = 10328, cost = 21000, requiredIds = {3472}},
		{id = 10300, cost = 21000, requiredIds = {10299}}
	},
	[48] = {
		{id = 19899, cost = 22000, requiredIds = {19891}},
		{id = 20929, cost = 22000, requiredIds = {20473}, requiredTalentId = 1311606},
		{id = 20772, cost = 21000, requiredIds = {10324}},
		{id = 20356, cost = 22000, requiredIds = {20166}}
	},
	[50] = {
		{id = 20923, cost = 23000, requiredIds = {20922}},
		{id = 10292, cost = 23000, requiredIds = {1032}},
		{id = 1020, cost = 23000, requiredIds = {642}},
		{id = 19942, cost = 23000, requiredIds = {19941}},
		{id = 20928, cost = 23000, requiredIds = {20927}, requiredTalentId = 20925},
		{id = 2812, cost = 23000},
		{id = 10310, cost = 23000, requiredIds = {2800}},
		{id = 1311590, cost = 23000, requiredIds = {1310911}, requiredTalentId = 1310911},
		{id = 20919, cost = 23000, requiredIds = {20918}, requiredTalentId = 20375},
		{id = 20422, cost = 23000, requiredIds = {20421}},
		{id = 20348, cost = 23000, requiredIds = {20347}},
		{id = 20292, cost = 23000, requiredIds = {20291}}
	},
	[52] = {
		{id = 19838, cost = 24000, requiredIds = {19837}},
		{id = 10313, cost = 24000, requiredIds = {10312}},
		{id = 25782, cost = 24000, requiredIds = {19838}},
		{id = 24274, cost = 24000, requiredIds = {24275}},
		{id = 10332, cost = 24000, requiredIds = {5569}},
		{id = 20308, cost = 24000, requiredIds = {20307}},
		{id = 19896, cost = 24000, requiredIds = {19895}},
		{id = 10326, cost = 24000, requiredIds = {5627}}
	},
	[54] = {
		{id = 20729, cost = 25000, requiredIds = {6940}},
		{id = 19854, cost = 25000, requiredIds = {19853}},
		{id = 25894, cost = 25000, requiredIds = {19854}},
		{id = 10308, cost = 25000, requiredIds = {5589}},
		{id = 10329, cost = 25000, requiredIds = {10328}}
	},
	[56] = {
		{id = 19898, cost = 26000, requiredIds = {19897}},
		{id = 20930, cost = 26000, requiredIds = {20929}, requiredTalentId = 1311606},
		{id = 10301, cost = 26000, requiredIds = {10300}}
	},
	[58] = {
		{id = 19943, cost = 27000, requiredIds = {19942}},
		{id = 20423, cost = 27000, requiredIds = {20422}},
		{id = 20293, cost = 27000, requiredIds = {20292}},
		{id = 20357, cost = 27000, requiredIds = {20356}}
	},
	[60] = {
		{id = 20924, cost = 29000, requiredIds = {20923}},
		{id = 10293, cost = 29000, requiredIds = {10292}},
		{id = 10314, cost = 29000, requiredIds = {10313}},
		{id = 19900, cost = 29000, requiredIds = {19899}},
		{id = 25898, cost = 29000, requiredIds = {20217}},
		{id = 25916, cost = 29000, requiredIds = {19740}},
		{id = 25918, cost = 29000, requiredIds = {19742}},
		{id = 24239, cost = 29000, requiredIds = {24274}},
		{id = 1239570, cost = 29000, requiredIds = {20928}, requiredTalentId = 20925},
		{id = 10333, cost = 29000, requiredIds = {10332}},
		{id = 10318, cost = 29000, requiredIds = {2812}},
		{id = 1311595, cost = 29000, requiredIds = {1311590}, requiredTalentId = 1310911},
		{id = 20773, cost = 29000, requiredIds = {20772}},
		{id = 20920, cost = 29000, requiredIds = {20919}, requiredTalentId = 20375},
		{id = 20349, cost = 29000, requiredIds = {20348}}
	}
}
end

if PLAYER_CLASS == "PRIEST" then
local class = Data

class.spellsByLevel = {
	[1] = {{id = 1243, cost = 10}},
	[4] = {{id = 2052, cost = 100, requiredIds = {2050}}, {id = 589, cost = 100}},
	[6] = {{id = 17, cost = 100}, {id = 591, cost = 100, requiredIds = {585}}},
	[8] = {{id = 586, cost = 200}, {id = 139, cost = 200}},
	[10] = {
		{id = 2053, cost = 300, requiredIds = {2052}},
		{id = 8092, cost = 300},
		{id = 2006, cost = 300},
		{id = 594, cost = 300, requiredIds = {589}}
	},
	[12] = {
		{id = 588, cost = 800},
		{id = 1244, cost = 800, requiredIds = {1243}},
		{id = 592, cost = 800, requiredIds = {17}}
	},
	[14] = {
		{id = 528, cost = 900},
		{id = 8122, cost = 900},
		{id = 6074, cost = 900, requiredIds = {139}},
		{id = 598, cost = 900, requiredIds = {591}}
	},
	[16] = {{id = 2054, cost = 1400}, {id = 8102, cost = 1400, requiredIds = {8092}}},
	[18] = {
		{id = 527, cost = 1500},
		{id = 1277371, cost = 1500, requiredIds = {1277370}, race = 1},
		{id = 600, cost = 1500, requiredIds = {592}},
		{id = 970, cost = 1500, requiredIds = {594}},
		{id = 19236, cost = 1500, requiredIds = {13908}, race = 3},
		{id = 19296, cost = 3000, requiredIds = {10797}, race = 4}
	},
	[20] = {
		{id = 2944, cost = 2100},
		{id = 9578, cost = 2100, requiredIds = {586}},
		{id = 6346, cost = 2100},
		{id = 2061, cost = 2100},
		{id = 14914, cost = 2100},
		{id = 7128, cost = 2100, requiredIds = {588}},
		{id = 453, cost = 2100},
		{id = 6075, cost = 2100, requiredIds = {6074}},
		{id = 9484, cost = 2100},
		{id = 19261, cost = 2000, requiredIds = {2652}, race = 5},
		{id = 19281, cost = 3000, requiredIds = {9035}, race = 8}
	},
	[22] = {
		{id = 2055, cost = 3300, requiredIds = {2054}},
		{id = 8103, cost = 3300, requiredIds = {8102}},
		{id = 2096, cost = 3300},
		{id = 2010, cost = 3300, requiredIds = {2006}},
		{id = 984, cost = 3300, requiredIds = {598}}
	},
	[24] = {
		{id = 15262, cost = 5000, requiredIds = {14914}},
		{id = 8129, cost = 5000},
		{id = 1245, cost = 5000, requiredIds = {1244}},
		{id = 3747, cost = 5000, requiredIds = {600}}
	},
	[26] = {
		{id = 1277372, cost = 5200, requiredIds = {1277371}, race = 1},
		{id = 9472, cost = 5200, requiredIds = {2061}},
		{id = 6076, cost = 5200, requiredIds = {6075}},
		{id = 992, cost = 5200, requiredIds = {970}},
		{id = 19238, cost = 5200, requiredIds = {19236}, race = 3},
		{id = 19299, cost = 10000, requiredIds = {19296}, race = 4}
	},
	[28] = {
		{id = 19276, cost = 5300, requiredIds = {2944}},
		{id = 6063, cost = 5300, requiredIds = {2055}},
		{id = 15430, cost = 5300, requiredIds = {15237}, requiredTalentId = 15237},
		{id = 8104, cost = 5300, requiredIds = {8103}},
		{id = 17311, cost = 5300, requiredIds = {15407}, requiredTalentId = 15407},
		{id = 8124, cost = 5300, requiredIds = {8122}},
		{id = 19308, cost = 5000, requiredIds = {18137}, race = 8}
	},
	[30] = {
		{id = 14752, cost = 5600},
		{id = 9579, cost = 5600, requiredIds = {9578}},
		{id = 19271, cost = 5600, requiredIds = {13896}, race = 1},
		{id = 15263, cost = 5600, requiredIds = {15262}},
		{id = 602, cost = 5600, requiredIds = {7128}},
		{id = 605, cost = 5600},
		{id = 6065, cost = 5600, requiredIds = {3747}},
		{id = 596, cost = 5600},
		{id = 976, cost = 5600},
		{id = 1004, cost = 5600, requiredIds = {984}},
		{id = 19262, cost = 6000, requiredIds = {19261}, race = 5},
		{id = 19282, cost = 5000, requiredIds = {19281}, race = 8},
		{id = 1277325, cost = 6000, requiredIds = {1277324}, race = 5},
		{id = 1277332, cost = 5600, requiredIds = {1277331}, race = 3},
		{id = 1277634, cost = 13000, requiredIds = {1277462}, race = 7}
	},
	[32] = {
		{id = 552, cost = 8000},
		{id = 9473, cost = 8000, requiredIds = {9472}},
		{id = 8131, cost = 8000, requiredIds = {8129}},
		{id = 6077, cost = 8000, requiredIds = {6076}},
		{id = 1309595, cost = 8000}
	},
	[34] = {
		{id = 1277374, cost = 9000, requiredIds = {1277372}, race = 1},
		{id = 6064, cost = 9000, requiredIds = {6063}},
		{id = 1706, cost = 9000},
		{id = 8105, cost = 9000, requiredIds = {8104}},
		{id = 10880, cost = 9000, requiredIds = {2010}},
		{id = 2767, cost = 9000, requiredIds = {992}},
		{id = 19240, cost = 9000, requiredIds = {19238}, race = 3},
		{id = 19302, cost = 16000, requiredIds = {19299}, race = 4}
	},
	[36] = {
		{id = 19277, cost = 10000, requiredIds = {19276}},
		{id = 988, cost = 10000, requiredIds = {527}},
		{id = 15264, cost = 10000, requiredIds = {15263}},
		{id = 15431, cost = 10000, requiredIds = {15430}, requiredTalentId = 15237},
		{id = 17312, cost = 10000, requiredIds = {17311}, requiredTalentId = 15407},
		{id = 8192, cost = 10000, requiredIds = {453}},
		{id = 2791, cost = 10000, requiredIds = {1245}},
		{id = 6066, cost = 10000, requiredIds = {6065}},
		{id = 19309, cost = 9000, requiredIds = {19308}, race = 8}
	},
	[38] = {
		{id = 9474, cost = 12000, requiredIds = {9473}},
		{id = 6078, cost = 12000, requiredIds = {6077}},
		{id = 6060, cost = 12000, requiredIds = {1004}}
	},
	[40] = {
		{id = 14818, cost = 13000, requiredIds = {14752}},
		{id = 9592, cost = 13000, requiredIds = {9579}},
		{id = 19273, cost = 13000, requiredIds = {19271}, race = 1},
		{id = 2060, cost = 13000},
		{id = 1006, cost = 13000, requiredIds = {602}},
		{id = 10874, cost = 13000, requiredIds = {8131}},
		{id = 8106, cost = 13000, requiredIds = {8105}},
		{id = 1240720, cost = 13000, requiredIds = {402174}, requiredTalentId = 402174},
		{id = 996, cost = 13000, requiredIds = {596}},
		{id = 9485, cost = 13000, requiredIds = {9484}},
		{id = 1309633, cost = 13000, requiredIds = {1309595}},
		{id = 19264, cost = 13000, requiredIds = {19262}, race = 5},
		{id = 19283, cost = 12000, requiredIds = {19282}, race = 8},
		{id = 1277326, cost = 13000, requiredIds = {1277325}, race = 5},
		{id = 1277333, cost = 13000, requiredIds = {1277332}, race = 3},
		{id = 1277638, cost = 27000, requiredIds = {1277634}, race = 7}
	},
	[42] = {
		{id = 1277376, cost = 14000, requiredIds = {1277374}, race = 1},
		{id = 15265, cost = 14000, requiredIds = {15264}},
		{id = 10898, cost = 14000, requiredIds = {6066}},
		{id = 10888, cost = 14000, requiredIds = {8124}},
		{id = 10957, cost = 14000, requiredIds = {976}},
		{id = 10892, cost = 14000, requiredIds = {2767}},
		{id = 19241, cost = 14000, requiredIds = {19240}, race = 3},
		{id = 19303, cost = 27000, requiredIds = {19302}, race = 4}
	},
	[44] = {
		{id = 19278, cost = 16000, requiredIds = {19277}},
		{id = 10915, cost = 16000, requiredIds = {9474}},
		{id = 27799, cost = 16000, requiredIds = {15431}, requiredTalentId = 15237},
		{id = 10911, cost = 16000, requiredIds = {605}},
		{id = 17313, cost = 16000, requiredIds = {17312}, requiredTalentId = 15407},
		{id = 10909, cost = 16000, requiredIds = {2096}},
		{id = 10927, cost = 16000, requiredIds = {6078}},
		{id = 19310, cost = 14000, requiredIds = {19309}, race = 8}
	},
	[46] = {
		{id = 10963, cost = 17000, requiredIds = {2060}},
		{id = 10945, cost = 17000, requiredIds = {8106}},
		{id = 10881, cost = 17000, requiredIds = {10880}},
		{id = 10933, cost = 17000, requiredIds = {6060}}
	},
	[48] = {
		{id = 15266, cost = 18000, requiredIds = {15265}},
		{id = 10875, cost = 18000, requiredIds = {10874}},
		{id = 10937, cost = 18000, requiredIds = {2791}},
		{id = 10899, cost = 18000, requiredIds = {10898}},
		{id = 1309635, cost = 18000, requiredIds = {1309633}}
	},
	[50] = {
		{id = 1277377, cost = 20000, requiredIds = {1277376}, race = 1},
		{id = 14819, cost = 20000, requiredIds = {14818}},
		{id = 10941, cost = 20000, requiredIds = {9592}},
		{id = 19274, cost = 20000, requiredIds = {19273}, race = 1},
		{id = 10916, cost = 20000, requiredIds = {10915}},
		{id = 10951, cost = 20000, requiredIds = {1006}},
		{id = 1240721, cost = 20000, requiredIds = {1240720}, requiredTalentId = 402174},
		{id = 10960, cost = 20000, requiredIds = {996}},
		{id = 1240826, cost = 20000, requiredIds = {401859}, requiredTalentId = 401859},
		{id = 10928, cost = 20000, requiredIds = {10927}},
		{id = 10893, cost = 20000, requiredIds = {10892}},
		{id = 19242, cost = 20000, requiredIds = {19241}, race = 3},
		{id = 19265, cost = 20000, requiredIds = {19264}, race = 5},
		{id = 19284, cost = 18000, requiredIds = {19283}, race = 8},
		{id = 19304, cost = 36000, requiredIds = {19303}, race = 4},
		{id = 1277327, cost = 20000, requiredIds = {1277326}, race = 5},
		{id = 1277334, cost = 20000, requiredIds = {1277333}, race = 3},
		{id = 1277639, cost = 40000, requiredIds = {1277638}, race = 7}
	},
	[52] = {
		{id = 19279, cost = 24000, requiredIds = {19278}},
		{id = 10964, cost = 24000, requiredIds = {10963}},
		{id = 27800, cost = 24000, requiredIds = {27799}, requiredTalentId = 15237},
		{id = 10946, cost = 24000, requiredIds = {10945}},
		{id = 17314, cost = 24000, requiredIds = {17313}, requiredTalentId = 15407},
		{id = 10953, cost = 24000, requiredIds = {8192}},
		{id = 19311, cost = 22000, requiredIds = {19310}, race = 8}
	},
	[54] = {
		{id = 15267, cost = 25000, requiredIds = {15266}},
		{id = 10900, cost = 25000, requiredIds = {10899}},
		{id = 10934, cost = 25000, requiredIds = {10933}}
	},
	[56] = {
		{id = 10917, cost = 26000, requiredIds = {10916}},
		{id = 10876, cost = 26000, requiredIds = {10875}},
		{id = 10890, cost = 26000, requiredIds = {10888}},
		{id = 10929, cost = 26000, requiredIds = {10928}},
		{id = 10958, cost = 26000, requiredIds = {10957}},
		{id = 1309636, cost = 26000, requiredIds = {1309635}}
	},
	[58] = {
		{id = 1277378, cost = 27000, requiredIds = {1277377}, race = 1},
		{id = 10965, cost = 27000, requiredIds = {10964}},
		{id = 10947, cost = 27000, requiredIds = {10946}},
		{id = 10912, cost = 27000, requiredIds = {10911}},
		{id = 20770, cost = 27000, requiredIds = {10881}},
		{id = 10894, cost = 27000, requiredIds = {10893}},
		{id = 19243, cost = 27000, requiredIds = {19242}, race = 3},
		{id = 19305, cost = 49000, requiredIds = {19304}, race = 4}
	},
	[60] = {
		{id = 19280, cost = 28000, requiredIds = {19279}},
		{id = 27841, cost = 28000, requiredIds = {14819}},
		{id = 10942, cost = 28000, requiredIds = {10941}},
		{id = 19275, cost = 28000, requiredIds = {19274}, race = 1},
		{id = 15261, cost = 28000, requiredIds = {15267}},
		{id = 27801, cost = 28000, requiredIds = {27800}, requiredTalentId = 15237},
		{id = 10952, cost = 28000, requiredIds = {10951}},
		{id = 18807, cost = 28000, requiredIds = {17314}, requiredTalentId = 15407},
		{id = 1316995, cost = 28000, requiredIds = {1240721}, requiredTalentId = 402174},
		{id = 10938, cost = 28000, requiredIds = {10937}},
		{id = 10901, cost = 28000, requiredIds = {10900}},
		{id = 10961, cost = 28000, requiredIds = {10960}},
		{id = 1240827, cost = 28000, requiredIds = {1240826}, requiredTalentId = 401859},
		{id = 27681, cost = 28000, requiredIds = {27841}},
		{id = 10955, cost = 28000, requiredIds = {9485}},
		{id = 19266, cost = 29000, requiredIds = {19265}, race = 5},
		{id = 19285, cost = 27000, requiredIds = {19284}, race = 8},
		{id = 19312, cost = 27000, requiredIds = {19311}, race = 8},
		{id = 1277328, cost = 29000, requiredIds = {1277327}, race = 5},
		{id = 1277335, cost = 28000, requiredIds = {1277334}, race = 3},
		{id = 1277640, cost = 60000, requiredIds = {1277639}, race = 7}
	}
}
end

if PLAYER_CLASS == "ROGUE" then
local class = Data

local stealth = {1784, 1785, 1786, 1787}
local backstab = {53, 2589, 2590, 2591, 8721, 11279, 11280, 11281}
local gouge = {1776, 1777, 8629, 11285, 11286}
local sinisterStrike = {1752, 1757, 1758, 1759, 1760, 8621, 11293, 11294}
local eviscerate = {2098, 6760, 6761, 6762, 8623, 8624, 11299, 11300}
local sap = {6770, 2070, 11297}
local sliceAndDice = {5171, 6774}
local sprint = {2983, 8696, 11305}
local kick = {1766, 1767, 1768, 1769}
local exposeArmor = {8647, 8649, 8650, 11197, 11198}
local garrote = {703, 8631, 8632, 8633, 11289, 11290}
local feint = {1966, 6768, 8637, 11303}
local ambush = {8676, 8724, 8725, 11267, 11268, 11269}
local cripplingPoison = {3420, 3421}
local rupture = {1943, 8639, 8640, 11273, 11274, 11275}
local vanish = {1856, 1857}
local mindNumbingPoison = {5763, 8694, 11400}
local instantPoison = {8687, 8691, 11341, 11342, 11343}
local deadlyPoison = {2835, 2837, 11357, 11358}
local kidneyShot = {408, 8643}
local woundPoison = {13220, 13228, 13229, 13230}
local deathMark = {1316709, 1325756, 1325757, 1325758}
local mutilate = {1310706, 1241582, 1241584}

class.overriddenGroups = {
	stealth,
	backstab,
	gouge,
	sinisterStrike,
	eviscerate,
	sap,
	sliceAndDice,
	sprint,
	kick,
	exposeArmor,
	garrote,
	feint,
	ambush,
	cripplingPoison,
	rupture,
	vanish,
	mindNumbingPoison,
	instantPoison,
	deadlyPoison,
	kidneyShot,
	woundPoison,
	deathMark,
	mutilate
}

class.spellsByLevel = {
	[1] = {{id = 1784, cost = 10}},
	[4] = {{id = 53, cost = 100}, {id = 921, cost = 100}},
	[6] = {{id = 1776, cost = 100}, {id = 1757, cost = 100, requiredIds = {1752}}},
	[8] = {{id = 5277, cost = 200}, {id = 6760, cost = 200, requiredIds = {2098}}},
	[10] = {{id = 674, cost = 300}, {id = 6770, cost = 300}, {id = 5171, cost = 300}, {id = 2983, cost = 300}},
	[12] = {{id = 2589, cost = 900, requiredIds = {53}}, {id = 1766, cost = 900}, {id = 3127, cost = 900}},
	[14] = {{id = 8647, cost = 1100}, {id = 703, cost = 1100}, {id = 1758, cost = 1100, requiredIds = {1757}}},
	[16] = {{id = 6761, cost = 1500, requiredIds = {6760}}, {id = 1966, cost = 1500}, {id = 1804, cost = 1500}},
	[18] = {{id = 8676, cost = 1600}, {id = 1777, cost = 1600, requiredIds = {1776}}, {id = 1328825, cost = 2200}},
	[20] = {
		{id = 2590, cost = 4300, requiredIds = {2589}},
		{id = 3420, cost = 4300, skills = {{skill = 40, level = 1}}},
		{id = 1943, cost = 4300},
		{id = 1785, cost = 4300, requiredIds = {1784}}
	},
	[22] = {
		{id = 1725, cost = 4500},
		{id = 8631, cost = 4500, requiredIds = {703}},
		{id = 1759, cost = 4500, requiredIds = {1758}},
		{id = 1856, cost = 4500}
	},
	[24] = {
		{id = 2836, cost = 6000},
		{id = 6762, cost = 6000, requiredIds = {6761}},
		{id = 5763, cost = 6000, skills = {{skill = 40, level = 100}}},
		{id = 1329283, cost = 6000}
	},
	[26] = {
		{id = 8724, cost = 7000, requiredIds = {8676}},
		{id = 1833, cost = 7000},
		{id = 8649, cost = 7000, requiredIds = {8647}},
		{id = 1767, cost = 7000, requiredIds = {1766}}
	},
	[28] = {
		{id = 2591, cost = 8000, requiredIds = {2590}},
		{id = 6768, cost = 8000, requiredIds = {1966}},
		{id = 8687, cost = 8000, skills = {{skill = 40, level = 120}}},
		{id = 8639, cost = 8000, requiredIds = {1943}},
		{id = 2070, cost = 8000, requiredIds = {6770}}
	},
	[30] = {
		{id = 2835, cost = 9000, skills = {{skill = 40, level = 130}}},
		{id = 1842, cost = 9000, requiredIds = {2836}},
		{id = 8632, cost = 9000, requiredIds = {8631}},
		{id = 408, cost = 9000},
		{id = 1760, cost = 9000, requiredIds = {1759}}
	},
	[32] = {
		{id = 8623, cost = 13000, requiredIds = {6762}},
		{id = 8629, cost = 13000, requiredIds = {1777}},
		{id = 13220, cost = 13000, skills = {{skill = 40, level = 140}}}
	},
	[34] = {
		{id = 8725, cost = 14000, requiredIds = {8724}},
		{id = 2094, cost = 14000, skills = {{skill = 40, level = 1}}},
		{id = 6510, cost = 14000, skills = {{skill = 40, level = 150}}},
		{id = 8696, cost = 14000, requiredIds = {2983}}
	},
	[36] = {
		{id = 8721, cost = 15000, requiredIds = {2591}},
		{id = 8650, cost = 15000, requiredIds = {8649}},
		{id = 8691, cost = 15000, skills = {{skill = 40, level = 160}}},
		{id = 8640, cost = 15000, requiredIds = {8639}}
	},
	[38] = {
		{id = 2837, cost = 16000, skills = {{skill = 40, level = 170}}},
		{id = 8633, cost = 16000, requiredIds = {8632}},
		{id = 8694, cost = 16000, skills = {{skill = 40, level = 170}}},
		{id = 8621, cost = 16000, requiredIds = {1760}}
	},
	[40] = {
		{id = 8624, cost = 19000, requiredIds = {8623}},
		{id = 8637, cost = 19000, requiredIds = {6768}},
		{id = 1860, cost = 19000},
		{id = 1786, cost = 19000, requiredIds = {1785}},
		{id = 13228, cost = 19000, skills = {{skill = 40, level = 180}}}
	},
	[42] = {
		{id = 11267, cost = 22000, requiredIds = {8725}},
		{id = 1768, cost = 22000, requiredIds = {1767}},
		{id = 6774, cost = 22000, requiredIds = {5171}},
		{id = 1857, cost = 22000, requiredIds = {1856}}
	},
	[44] = {
		{id = 11279, cost = 23000, requiredIds = {8721}},
		{id = 11341, cost = 23000, skills = {{skill = 40, level = 200}}},
		{id = 11273, cost = 23000, requiredIds = {8640}},
		{id = 1329549, cost = 23000, requiredIds = {1329283}}
	},
	[46] = {
		{id = 11357, cost = 25000, skills = {{skill = 40, level = 210}}},
		{id = 11197, cost = 25000, requiredIds = {8650}},
		{id = 11289, cost = 25000, requiredIds = {8633}},
		{id = 11285, cost = 25000, requiredIds = {8629}},
		{id = 11293, cost = 25000, requiredIds = {8621}}
	},
	[48] = {
		{id = 1325756, cost = 43000, requiredIds = {1316709}, requiredTalentId = 1316709},
		{id = 11299, cost = 43000, requiredIds = {8624}},
		{id = 11297, cost = 43000, requiredIds = {2070}},
		{id = 13229, cost = 43000, skills = {{skill = 40, level = 220}}}
	},
	[50] = {
		{id = 11268, cost = 44000, requiredIds = {11267}},
		{id = 3421, cost = 44000, skills = {{skill = 40, level = 230}}},
		{id = 8643, cost = 44000, requiredIds = {408}},
		{id = 1241582, cost = 44000, requiredIds = {1310706}, requiredTalentId = 1310706}
	},
	[52] = {
		{id = 11280, cost = 45000, requiredIds = {11279}},
		{id = 11303, cost = 45000, requiredIds = {8637}},
		{id = 11342, cost = 45000, skills = {{skill = 40, level = 240}}},
		{id = 11400, cost = 45000, skills = {{skill = 40, level = 240}}},
		{id = 11274, cost = 45000, requiredIds = {11273}}
	},
	[54] = {
		{id = 11358, cost = 46000, skills = {{skill = 40, level = 250}}},
		{id = 11290, cost = 46000, requiredIds = {11289}},
		{id = 11294, cost = 46000, requiredIds = {11293}}
	},
	[56] = {
		{id = 1325757, cost = 48000, requiredIds = {1325756}, requiredTalentId = 1316709},
		{id = 11300, cost = 48000, requiredIds = {11299}},
		{id = 11198, cost = 48000, requiredIds = {11197}},
		{id = 13230, cost = 48000, skills = {{skill = 40, level = 260}}}
	},
	[58] = {
		{id = 11269, cost = 50000, requiredIds = {11268}},
		{id = 1769, cost = 50000, requiredIds = {1768}},
		{id = 11305, cost = 50000, requiredIds = {8696}}
	},
	[60] = {
		{id = 11281, cost = 51000, requiredIds = {11280}},
		{id = 1325758, cost = 51000, requiredIds = {1325757}, requiredTalentId = 1316709},
		{id = 11286, cost = 51000, requiredIds = {11285}},
		{id = 11343, cost = 51000, skills = {{skill = 40, level = 280}}},
		{id = 1241584, cost = 51000, requiredIds = {1241582}, requiredTalentId = 1310706},
		{id = 11275, cost = 51000, requiredIds = {11274}},
		{id = 1787, cost = 51000, requiredIds = {1786}}
	}
}
end

if PLAYER_CLASS == "SHAMAN" then
local class = Data

class.spellsByLevel = {
	[1] = {{id = 8017, cost = 10}},
	[4] = {{id = 8042, cost = 100}},
	[6] = {{id = 2484, cost = 100}, {id = 332, cost = 100, requiredIds = {331}}},
	[8] = {
		{id = 8044, cost = 100, requiredIds = {8042}},
		{id = 529, cost = 100, requiredIds = {403}},
		{id = 324, cost = 100},
		{id = 8018, cost = 100, requiredIds = {8017}},
		{id = 5730, cost = 100}
	},
	[10] = {{id = 8050, cost = 400}, {id = 8024, cost = 400}, {id = 8075, cost = 400}},
	[12] = {
		{id = 2008, cost = 700},
		{id = 408341, cost = 700},
		{id = 547, cost = 700, requiredIds = {332}},
		{id = 370, cost = 700}
	},
	[14] = {
		{id = 8045, cost = 900, requiredIds = {8044}},
		{id = 548, cost = 900, requiredIds = {529}},
		{id = 8154, cost = 900, requiredIds = {8071}}
	},
	[16] = {
		{id = 526, cost = 1100},
		{id = 325, cost = 1100, requiredIds = {324}},
		{id = 8019, cost = 1100, requiredIds = {8018}}
	},
	[18] = {
		{id = 8052, cost = 1200, requiredIds = {8050}},
		{id = 8027, cost = 1200, requiredIds = {8024}},
		{id = 913, cost = 1200, requiredIds = {547}},
		{id = 6390, cost = 1200, requiredIds = {5730}},
		{id = 8143, cost = 1200}
	},
	[20] = {
		{id = 66842, cost = 2300},
		{id = 8056, cost = 2300},
		{id = 8033, cost = 2300},
		{id = 2645, cost = 2300},
		{id = 8004, cost = 2300},
		{id = 915, cost = 2300, requiredIds = {548}},
		{id = 6363, cost = 2300, requiredIds = {3599}},
		{id = 36936, cost = 2300}
	},
	[22] = {
		{id = 2870, cost = 3300},
		{id = 408342, cost = 3300, requiredIds = {408341}},
		{id = 8166, cost = 3300},
		{id = 437009, cost = 3300},
		{id = 131, cost = 3300}
	},
	[24] = {
		{id = 20609, cost = 3400, requiredIds = {2008}},
		{id = 8046, cost = 3400, requiredIds = {8045}},
		{id = 8181, cost = 3400},
		{id = 939, cost = 3400, requiredIds = {913}},
		{id = 905, cost = 3400, requiredIds = {325}},
		{id = 10399, cost = 3400, requiredIds = {8019}},
		{id = 8155, cost = 3400, requiredIds = {8154}},
		{id = 8160, cost = 3400, requiredIds = {8075}}
	},
	[26] = {
		{id = 6196, cost = 4300},
		{id = 8030, cost = 4300, requiredIds = {8027}},
		{id = 943, cost = 4300, requiredIds = {915}},
		{id = 8190, cost = 4300},
		{id = 5675, cost = 4300}
	},
	[28] = {
		{id = 8184, cost = 5000},
		{id = 8053, cost = 5000, requiredIds = {8052}},
		{id = 8227, cost = 5000},
		{id = 8038, cost = 5000, requiredIds = {8033}},
		{id = 8008, cost = 5000, requiredIds = {8004}},
		{id = 6391, cost = 5000, requiredIds = {6390}},
		{id = 546, cost = 5000}
	},
	[30] = {
		{id = 556, cost = 5700},
		{id = 66843, cost = 5700, requiredIds = {66842}},
		{id = 8177, cost = 5700},
		{id = 6375, cost = 5700, requiredIds = {5394}},
		{id = 10595, cost = 5700},
		{id = 20608, cost = 5700},
		{id = 6364, cost = 5700, requiredIds = {6363}},
		{id = 8232, cost = 5700}
	},
	[32] = {
		{id = 421, cost = 7000},
		{id = 408343, cost = 7000, requiredIds = {408342}},
		{id = 959, cost = 7000, requiredIds = {939}},
		{id = 6041, cost = 7000, requiredIds = {943}},
		{id = 945, cost = 7000, requiredIds = {905}},
		{id = 8012, cost = 7000, requiredIds = {370}},
		{id = 8512, cost = 7000}
	},
	[34] = {
		{id = 8058, cost = 8000, requiredIds = {8056}},
		{id = 16314, cost = 8000, requiredIds = {10399}},
		{id = 6495, cost = 8000},
		{id = 10406, cost = 8000, requiredIds = {8155}}
	},
	[36] = {
		{id = 20610, cost = 9000, requiredIds = {20609}},
		{id = 10412, cost = 9000, requiredIds = {8046}},
		{id = 16339, cost = 9000, requiredIds = {8030}},
		{id = 8010, cost = 9000, requiredIds = {8008}},
		{id = 10585, cost = 9000, requiredIds = {8190}},
		{id = 10495, cost = 9000, requiredIds = {5675}},
		{id = 15107, cost = 9000}
	},
	[38] = {
		{id = 8170, cost = 10000},
		{id = 8249, cost = 10000, requiredIds = {8227}},
		{id = 10478, cost = 10000, requiredIds = {8181}},
		{id = 10456, cost = 10000, requiredIds = {8038}},
		{id = 10391, cost = 10000, requiredIds = {6041}},
		{id = 17354, cost = 10000, requiredIds = {16190}, requiredTalentId = 16190},
		{id = 6392, cost = 10000, requiredIds = {6391}},
		{id = 8161, cost = 10000, requiredIds = {8160}}
	},
	[40] = {
		{id = 66844, cost = 12000, requiredIds = {66843}},
		{id = 1064, cost = 12000},
		{id = 930, cost = 12000, requiredIds = {421}},
		{id = 10447, cost = 12000, requiredIds = {8053}},
		{id = 6377, cost = 12000, requiredIds = {6375}},
		{id = 8005, cost = 12000, requiredIds = {959}},
		{id = 8134, cost = 12000, requiredIds = {945}},
		{id = 8737, cost = 12000},
		{id = 6365, cost = 12000, requiredIds = {6364}},
		{id = 8235, cost = 12000, requiredIds = {8232}}
	},
	[42] = {
		{id = 408344, cost = 18000, requiredIds = {408343}},
		{id = 10537, cost = 18000, requiredIds = {8184}},
		{id = 8835, cost = 18000},
		{id = 10613, cost = 18000, requiredIds = {8512}}
	},
	[44] = {
		{id = 10466, cost = 19000, requiredIds = {8010}},
		{id = 10392, cost = 19000, requiredIds = {10391}},
		{id = 10600, cost = 19000, requiredIds = {10595}},
		{id = 16315, cost = 19000, requiredIds = {16314}},
		{id = 10407, cost = 19000, requiredIds = {10406}}
	},
	[46] = {
		{id = 10622, cost = 20000, requiredIds = {1064}},
		{id = 16341, cost = 20000, requiredIds = {16339}},
		{id = 10472, cost = 20000, requiredIds = {8058}},
		{id = 10586, cost = 20000, requiredIds = {10585}},
		{id = 10496, cost = 20000, requiredIds = {10495}},
		{id = 15111, cost = 20000, requiredIds = {15107}}
	},
	[48] = {
		{id = 20776, cost = 21000, requiredIds = {20610}},
		{id = 2860, cost = 21000, requiredIds = {930}},
		{id = 10413, cost = 21000, requiredIds = {10412}},
		{id = 10526, cost = 21000, requiredIds = {8249}},
		{id = 16355, cost = 21000, requiredIds = {10456}},
		{id = 10395, cost = 21000, requiredIds = {8005}},
		{id = 10431, cost = 21000, requiredIds = {8134}},
		{id = 17359, cost = 21000, requiredIds = {17354}, requiredTalentId = 16190},
		{id = 10427, cost = 21000, requiredIds = {6392}}
	},
	[50] = {
		{id = 10462, cost = 25000, requiredIds = {6377}},
		{id = 15207, cost = 25000, requiredIds = {10392}},
		{id = 1239242, cost = 25000, requiredIds = {408521}, requiredTalentId = 408521},
		{id = 10437, cost = 25000, requiredIds = {6365}},
		{id = 10486, cost = 25000, requiredIds = {8235}}
	},
	[52] = {
		{id = 408345, cost = 26000, requiredIds = {408344}},
		{id = 10448, cost = 26000, requiredIds = {10447}},
		{id = 10467, cost = 26000, requiredIds = {10466}},
		{id = 10442, cost = 26000, requiredIds = {8161}},
		{id = 10614, cost = 26000, requiredIds = {10613}}
	},
	[54] = {
		{id = 10623, cost = 27000, requiredIds = {10622}},
		{id = 10479, cost = 27000, requiredIds = {10478}},
		{id = 16316, cost = 27000, requiredIds = {16315}},
		{id = 10408, cost = 27000, requiredIds = {10407}}
	},
	[56] = {
		{id = 10605, cost = 28000, requiredIds = {2860}},
		{id = 16342, cost = 28000, requiredIds = {16341}},
		{id = 10627, cost = 28000, requiredIds = {8835}},
		{id = 10396, cost = 28000, requiredIds = {10395}},
		{id = 15208, cost = 28000, requiredIds = {15207}},
		{id = 10432, cost = 28000, requiredIds = {10431}},
		{id = 10587, cost = 28000, requiredIds = {10586}},
		{id = 10497, cost = 28000, requiredIds = {10496}},
		{id = 15112, cost = 28000, requiredIds = {15111}}
	},
	[58] = {
		{id = 10538, cost = 32000, requiredIds = {10537}},
		{id = 16387, cost = 32000, requiredIds = {10526}},
		{id = 10473, cost = 32000, requiredIds = {10472}},
		{id = 16356, cost = 32000, requiredIds = {16355}},
		{id = 1325256, cost = 32000, requiredIds = {17359}, requiredTalentId = 16190},
		{id = 10428, cost = 32000, requiredIds = {10427}}
	},
	[60] = {
		{id = 20777, cost = 33000, requiredIds = {20776}},
		{id = 10414, cost = 33000, requiredIds = {10413}},
		{id = 10463, cost = 33000, requiredIds = {10462}},
		{id = 10468, cost = 33000, requiredIds = {10467}},
		{id = 10601, cost = 33000, requiredIds = {10600}},
		{id = 1239243, cost = 33000, requiredIds = {1239242}, requiredTalentId = 408521},
		{id = 10438, cost = 33000, requiredIds = {10437}},
		{id = 16362, cost = 33000, requiredIds = {10486}}
	}
}
end

if PLAYER_CLASS == "WARLOCK" then
local class = Data

class.spellsByLevel = {
	[1] = {{id = 348, cost = 10}},
	[4] = {{id = 172, cost = 100}, {id = 702, cost = 100}},
	[6] = {{id = 1454, cost = 100}, {id = 695, cost = 100, requiredIds = {686}}},
	[8] = {{id = 980, cost = 200}, {id = 5782, cost = 200}},
	[10] = {
		{id = 6201, cost = 300, requiredIds = {1120}},
		{id = 696, cost = 300, requiredIds = {687}},
		{id = 1120, cost = 300},
		{id = 707, cost = 300, requiredIds = {348}}
	},
	[12] = {
		{id = 1108, cost = 800, requiredIds = {702}},
		{id = 755, cost = 800},
		{id = 705, cost = 800, requiredIds = {695}}
	},
	[14] = {{id = 6222, cost = 1000, requiredIds = {172}}, {id = 704, cost = 1000}, {id = 689, cost = 1000}},
	[16] = {{id = 1455, cost = 1600, requiredIds = {1454}}, {id = 5697, cost = 1600}},
	[18] = {
		{id = 1014, cost = 1700, requiredIds = {980}},
		{id = 693, cost = 1700, requiredIds = {1120}},
		{id = 5676, cost = 1700}
	},
	[20] = {
		{id = 440892, cost = 2500},
		{id = 706, cost = 2500},
		{id = 3698, cost = 2500, requiredIds = {755}},
		{id = 1094, cost = 2500, requiredIds = {707}},
		{id = 5740, cost = 2500},
		{id = 698, cost = 2500},
		{id = 1088, cost = 2500, requiredIds = {705}}
	},
	[22] = {
		{id = 6202, cost = 3800, requiredIds = {6201}},
		{id = 6205, cost = 3800, requiredIds = {1108}},
		{id = 699, cost = 3800, requiredIds = {689}},
		{id = 126, cost = 3800}
	},
	[24] = {
		{id = 6223, cost = 4800, requiredIds = {6222}},
		{id = 5138, cost = 4800},
		{id = 8288, cost = 4800, requiredIds = {1120}},
		{id = 5500, cost = 4800},
		{id = 18867, cost = 4800, requiredIds = {17877}, requiredTalentId = 17877}
	},
	[26] = {
		{id = 1714, cost = 5000},
		{id = 132, cost = 5000},
		{id = 1456, cost = 5000, requiredIds = {1455}},
		{id = 17919, cost = 5000, requiredIds = {5676}}
	},
	[28] = {
		{id = 6217, cost = 6000, requiredIds = {1014}},
		{id = 710, cost = 6000},
		{id = 6366, cost = 6000},
		{id = 7658, cost = 6000, requiredIds = {704}},
		{id = 3699, cost = 6000, requiredIds = {3698}},
		{id = 1106, cost = 6000, requiredIds = {1088}}
	},
	[30] = {
		{id = 20752, cost = 7000, requiredIds = {693}},
		{id = 1311676, cost = 7000, requiredIds = {440892}},
		{id = 1086, cost = 7000, requiredIds = {706}},
		{id = 709, cost = 7000, requiredIds = {699}},
		{id = 1949, cost = 7000},
		{id = 2941, cost = 7000, requiredIds = {1094}},
		{id = 1098, cost = 7000}
	},
	[32] = {
		{id = 1293818, cost = 8000, requiredIds = {1293817}, requiredTalentId = 1293817},
		{id = 7646, cost = 8000, requiredIds = {6205}},
		{id = 6213, cost = 8000, requiredIds = {5782}},
		{id = 6229, cost = 8000},
		{id = 18868, cost = 8000, requiredIds = {18867}, requiredTalentId = 17877}
	},
	[34] = {
		{id = 7648, cost = 9000, requiredIds = {6223}},
		{id = 5699, cost = 9000, requiredIds = {6202}},
		{id = 6226, cost = 9000, requiredIds = {5138}},
		{id = 6219, cost = 9000, requiredIds = {5740}},
		{id = 17920, cost = 9000, requiredIds = {17919}}
	},
	[36] = {
		{id = 17951, cost = 10000, requiredIds = {6366}},
		{id = 2362, cost = 10000, requiredIds = {1120}},
		{id = 3700, cost = 10000, requiredIds = {3699}},
		{id = 11687, cost = 10000, requiredIds = {1456}},
		{id = 7641, cost = 10000, requiredIds = {1106}}
	},
	[38] = {
		{id = 11711, cost = 11000, requiredIds = {6217}},
		{id = 2970, cost = 11000, requiredIds = {132}},
		{id = 7651, cost = 11000, requiredIds = {709}},
		{id = 8289, cost = 11000, requiredIds = {8288}},
		{id = 18879, cost = 11000, requiredIds = {18265}, requiredTalentId = 18265}
	},
	[40] = {
		{id = 17962, cost = 14000, requiredIds = {1293818}, requiredTalentId = 1293817},
		{id = 20755, cost = 14000, requiredIds = {20752}},
		{id = 1311677, cost = 14000, requiredIds = {1311676}},
		{id = 11733, cost = 14000, requiredIds = {1086}},
		{id = 5484, cost = 14000},
		{id = 11665, cost = 14000, requiredIds = {2941}},
		{id = 18869, cost = 14000, requiredIds = {18868}, requiredTalentId = 17877}
	},
	[42] = {
		{id = 7659, cost = 15000, requiredIds = {7658}},
		{id = 11707, cost = 15000, requiredIds = {7646}},
		{id = 6789, cost = 15000},
		{id = 11683, cost = 15000, requiredIds = {1949}},
		{id = 17921, cost = 15000, requiredIds = {17920}},
		{id = 11739, cost = 15000, requiredIds = {6229}}
	},
	[44] = {
		{id = 11671, cost = 16000, requiredIds = {7648}},
		{id = 11703, cost = 16000, requiredIds = {6226}},
		{id = 11693, cost = 16000, requiredIds = {3700}},
		{id = 11659, cost = 16000, requiredIds = {7641}},
		{id = 11725, cost = 16000, requiredIds = {1098}}
	},
	[46] = {
		{id = 17952, cost = 20000, requiredIds = {17951}},
		{id = 11729, cost = 20000, requiredIds = {5699}},
		{id = 11699, cost = 20000, requiredIds = {7651}},
		{id = 11688, cost = 20000, requiredIds = {11687}},
		{id = 11677, cost = 20000, requiredIds = {6219}}
	},
	[48] = {
		{id = 11712, cost = 21000, requiredIds = {11711}},
		{id = 18647, cost = 21000, requiredIds = {710}},
		{id = 18930, cost = 21000, requiredIds = {17962}, requiredTalentId = 1293817},
		{id = 17727, cost = 21000, requiredIds = {2362}},
		{id = 18870, cost = 21000, requiredIds = {18869}, requiredTalentId = 17877},
		{id = 18880, cost = 21000, requiredIds = {18879}, requiredTalentId = 18265},
		{id = 6353, cost = 21000}
	},
	[50] = {
		{id = 20756, cost = 22000, requiredIds = {20755}},
		{id = 1311680, cost = 22000, requiredIds = {1311677}},
		{id = 11719, cost = 22000, requiredIds = {1714}},
		{id = 17925, cost = 22000, requiredIds = {6789}},
		{id = 11734, cost = 22000, requiredIds = {11733}},
		{id = 11743, cost = 22000, requiredIds = {2970}},
		{id = 11667, cost = 22000, requiredIds = {11665}},
		{id = 1293812, cost = 22000, requiredIds = {412758}, requiredTalentId = 412758},
		{id = 17922, cost = 22000, requiredIds = {17921}}
	},
	[52] = {
		{id = 11708, cost = 23000, requiredIds = {11707}},
		{id = 11675, cost = 23000, requiredIds = {8289}},
		{id = 11694, cost = 23000, requiredIds = {11693}},
		{id = 11660, cost = 23000, requiredIds = {11659}},
		{id = 11740, cost = 23000, requiredIds = {11739}}
	},
	[54] = {
		{id = 18931, cost = 24000, requiredIds = {18930}, requiredTalentId = 1293817},
		{id = 11672, cost = 24000, requiredIds = {11671}},
		{id = 11700, cost = 24000, requiredIds = {11699}},
		{id = 11704, cost = 24000, requiredIds = {11703}},
		{id = 11684, cost = 24000, requiredIds = {11683}},
		{id = 17928, cost = 24000, requiredIds = {5484}}
	},
	[56] = {
		{id = 17953, cost = 25000, requiredIds = {17952}},
		{id = 11717, cost = 25000, requiredIds = {7659}},
		{id = 6215, cost = 25000, requiredIds = {6213}},
		{id = 11689, cost = 25000, requiredIds = {11688}},
		{id = 18871, cost = 25000, requiredIds = {18870}, requiredTalentId = 17877},
		{id = 17924, cost = 25000, requiredIds = {6353}}
	},
	[58] = {
		{id = 11713, cost = 26000, requiredIds = {11712}},
		{id = 11730, cost = 26000, requiredIds = {11729}},
		{id = 17926, cost = 26000, requiredIds = {17925}},
		{id = 11678, cost = 26000, requiredIds = {11677}},
		{id = 17923, cost = 26000, requiredIds = {17922}},
		{id = 18881, cost = 26000, requiredIds = {18880}, requiredTalentId = 18265},
		{id = 11726, cost = 26000, requiredIds = {11725}}
	},
	[60] = {
		{id = 603, cost = 27000},
		{id = 18932, cost = 27000, requiredIds = {18931}, requiredTalentId = 1293817},
		{id = 20757, cost = 27000, requiredIds = {20756}},
		{id = 17728, cost = 27000, requiredIds = {17727}},
		{id = 11735, cost = 27000, requiredIds = {11734}},
		{id = 11695, cost = 27000, requiredIds = {11694}},
		{id = 11668, cost = 27000, requiredIds = {11667}},
		{id = 1293813, cost = 27000, requiredIds = {1293812}, requiredTalentId = 412758},
		{id = 11661, cost = 27000, requiredIds = {11660}}
	}
}
end

if PLAYER_CLASS == "WARRIOR" then
local class = Data

local battleShout = {6673, 5242, 6192, 11549, 11550, 11551}
local charge = {100, 6178, 11578}
local rend = {772, 6546, 6547, 6548, 11572, 11573, 11574}
local thunderClap = {6343, 8198, 8204, 8205, 11580, 11581}
local hamstring = {1715, 7372, 7373}
local heroicStrike = {78, 284, 285, 1608, 11564, 11565, 11566, 11567}
local overpower = {7384, 7887, 11584, 11585}
local shieldBash = {72, 1671, 1672}
local demoralizingShout = {1160, 6190, 11554, 11555, 11556}
local revenge = {6572, 6574, 7379, 11600, 11601}
local mockingBlow = {694, 7400, 7402, 20559, 20560}
local cleave = {845, 7369, 11608, 11609, 20569}
local slam = {1240193, 1464, 8820, 11604, 11605}
local sunderArmor = {7386, 7405, 8380, 11596, 11597}
local execute = {5308, 20658, 20660, 20661, 20662}
local pummel = {6552, 6554}
local intercept = {20252, 20616, 20617}
local bloodthirst = {23881, 23892, 23893, 23894}
local mortalStrike = {12294, 21551, 21552, 21553}
local shieldSlam = {23922, 23923, 23924, 23925}

class.overriddenGroups = {
	battleShout,
	charge,
	rend,
	thunderClap,
	hamstring,
	heroicStrike,
	overpower,
	shieldBash,
	demoralizingShout,
	revenge,
	mockingBlow,
	cleave,
	slam,
	sunderArmor,
	execute,
	pummel,
	intercept,
	bloodthirst,
	mortalStrike,
	shieldSlam
}

class.spellsByLevel = {
	[1] = {{id = 6673, cost = 10}},
	[4] = {{id = 100, cost = 100}, {id = 772, cost = 100}},
	[6] = {{id = 3127, cost = 100}, {id = 6343, cost = 100}},
	[8] = {{id = 1715, cost = 200}, {id = 284, cost = 200, requiredIds = {78}}},
	[10] = {{id = 2687, cost = 700}, {id = 6546, cost = 700, requiredIds = {772}}},
	[12] = {{id = 5242, cost = 900, requiredIds = {6673}}, {id = 7384, cost = 900}, {id = 72, cost = 900}},
	[14] = {{id = 1160, cost = 1100}, {id = 6572, cost = 1100, requiredIds = {71}}, {id = 1310185, cost = 1100}},
	[16] = {
		{id = 285, cost = 1500, requiredIds = {284}},
		{id = 694, cost = 1500},
		{id = 2565, cost = 1500, requiredIds = {71}}
	},
	[18] = {{id = 676, cost = 3200, requiredIds = {71}}, {id = 8198, cost = 3200, requiredIds = {6343}}},
	[20] = {
		{id = 845, cost = 3400},
		{id = 674, cost = 3400},
		{id = 6547, cost = 3400, requiredIds = {6546}},
		{id = 20230, cost = 3400},
		{id = 1240193, cost = 3400},
		{id = 402927, cost = 3400}
	},
	[22] = {
		{id = 6192, cost = 5500, requiredIds = {5242}},
		{id = 5246, cost = 5500},
		{id = 7405, cost = 5500, requiredIds = {7386}}
	},
	[24] = {
		{id = 6190, cost = 6400, requiredIds = {1160}},
		{id = 5308, cost = 6400},
		{id = 1608, cost = 6400, requiredIds = {285}},
		{id = 6574, cost = 6400, requiredIds = {6572}}
	},
	[26] = {
		{id = 1161, cost = 7600},
		{id = 6178, cost = 7600, requiredIds = {100}},
		{id = 7400, cost = 7600, requiredIds = {694}}
	},
	[28] = {
		{id = 7887, cost = 11000, requiredIds = {7384}},
		{id = 871, cost = 11000, requiredIds = {71}},
		{id = 8204, cost = 11000, requiredIds = {8198}}
	},
	[30] = {
		{id = 18499, cost = 12000, requiredIds = {2458}},
		{id = 7369, cost = 12000, requiredIds = {845}},
		{id = 6548, cost = 12000, requiredIds = {6547}},
		{id = 1464, cost = 12000, requiredIds = {1240193}}
	},
	[32] = {
		{id = 11549, cost = 13000, requiredIds = {6192}},
		{id = 20658, cost = 13000, requiredIds = {5308}},
		{id = 7372, cost = 13000, requiredIds = {1715}},
		{id = 11564, cost = 13000, requiredIds = {1608}},
		{id = 1671, cost = 13000, requiredIds = {72}}
	},
	[34] = {
		{id = 11554, cost = 14000, requiredIds = {6190}},
		{id = 7379, cost = 14000, requiredIds = {6574}},
		{id = 8380, cost = 14000, requiredIds = {7405}}
	},
	[36] = {{id = 7402, cost = 18000, requiredIds = {7400}}, {id = 1680, cost = 18000, requiredIds = {2458}}},
	[38] = {
		{id = 6552, cost = 19000, requiredIds = {2458}},
		{id = 8820, cost = 19000, requiredIds = {1464}},
		{id = 8205, cost = 19000, requiredIds = {8204}}
	},
	[40] = {
		{id = 11608, cost = 23000, requiredIds = {7369}},
		{id = 20660, cost = 23000, requiredIds = {20658}},
		{id = 11565, cost = 23000, requiredIds = {11564}},
		{id = 750, cost = 23000},
		{id = 11572, cost = 23000, requiredIds = {6548}}
	},
	[42] = {{id = 11550, cost = 30000, requiredIds = {11549}}, {id = 20616, cost = 30000, requiredIds = {20252}}},
	[44] = {
		{id = 11555, cost = 31000, requiredIds = {11554}},
		{id = 11584, cost = 31000, requiredIds = {7887}},
		{id = 11600, cost = 31000, requiredIds = {7379}}
	},
	[46] = {
		{id = 11578, cost = 32000, requiredIds = {6178}},
		{id = 20559, cost = 32000, requiredIds = {7402}},
		{id = 11604, cost = 32000, requiredIds = {8820}},
		{id = 11596, cost = 32000, requiredIds = {8380}}
	},
	[48] = {
		{id = 23892, cost = 33000, requiredIds = {23881}, requiredTalentId = 23881},
		{id = 20661, cost = 33000, requiredIds = {20660}},
		{id = 11566, cost = 33000, requiredIds = {11565}},
		{id = 21551, cost = 33000, requiredIds = {12294}, requiredTalentId = 12294},
		{id = 23923, cost = 33000, requiredIds = {23922}, requiredTalentId = 23922},
		{id = 11580, cost = 33000, requiredIds = {8205}}
	},
	[50] = {
		{id = 11609, cost = 36000, requiredIds = {11608}},
		{id = 1719, cost = 36000, requiredIds = {2458}},
		{id = 11573, cost = 36000, requiredIds = {11572}}
	},
	[52] = {
		{id = 11551, cost = 39000, requiredIds = {11550}},
		{id = 20617, cost = 39000, requiredIds = {20616}},
		{id = 1672, cost = 39000, requiredIds = {1671}}
	},
	[54] = {
		{id = 23893, cost = 40000, requiredIds = {23892}, requiredTalentId = 23881},
		{id = 11556, cost = 40000, requiredIds = {11555}},
		{id = 7373, cost = 40000, requiredIds = {7372}},
		{id = 21552, cost = 40000, requiredIds = {21551}, requiredTalentId = 12294},
		{id = 11601, cost = 40000, requiredIds = {11600}},
		{id = 23924, cost = 40000, requiredIds = {23923}, requiredTalentId = 23922},
		{id = 11605, cost = 40000, requiredIds = {11604}}
	},
	[56] = {
		{id = 20662, cost = 42000, requiredIds = {20661}},
		{id = 11567, cost = 42000, requiredIds = {11566}},
		{id = 20560, cost = 42000, requiredIds = {20559}}
	},
	[58] = {
		{id = 6554, cost = 48000, requiredIds = {6552}},
		{id = 11597, cost = 48000, requiredIds = {11596}},
		{id = 11581, cost = 48000, requiredIds = {11580}}
	},
	[60] = {
		{id = 23894, cost = 49000, requiredIds = {23893}, requiredTalentId = 23881},
		{id = 20569, cost = 49000, requiredIds = {11609}},
		{id = 21553, cost = 49000, requiredIds = {21552}, requiredTalentId = 12294},
		{id = 11585, cost = 49000, requiredIds = {11584}},
		{id = 11574, cost = 49000, requiredIds = {11573}},
		{id = 23925, cost = 49000, requiredIds = {23924}, requiredTalentId = 23922}
	}
}
end

-- Spells a class quest teaches, not a trainer.
do
-- QuestSpells[<CLASS>][<spellId>] = list of { races = {<addon race ids>}, level = <first-quest min level>, area = <AreaTable id> or areas = {<AreaTable ids>}, quests = {<reward quest ids>} }
local QuestSpells = {
    WARRIOR = {
        [71] = { -- Defensive Stance
            { races = {2, 6, 8}, level = 10, area = 17, quests = {1498} },
            { races = {5}, level = 10, area = 85, quests = {1819} },
            { races = {1}, level = 10, area = 1519, quests = {1665} },
            { races = {3, 7}, level = 10, area = 1537, quests = {1678} },
            { races = {4}, level = 10, area = 1657, quests = {1683} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94003} },
        },
        [355] = { -- Taunt
            { races = {2, 6, 8}, level = 10, area = 17, quests = {1498} },
            { races = {5}, level = 10, area = 85, quests = {1819} },
            { races = {1}, level = 10, area = 1519, quests = {1665} },
            { races = {3, 7}, level = 10, area = 1537, quests = {1678} },
            { races = {4}, level = 10, area = 1657, quests = {1683} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94003} },
        },
        [7386] = { -- Sunder Armor
            { races = {2, 6, 8}, level = 10, area = 17, quests = {1498} },
            { races = {5}, level = 10, area = 85, quests = {1819} },
            { races = {1}, level = 10, area = 1519, quests = {1665} },
            { races = {3, 7}, level = 10, area = 1537, quests = {1678} },
            { races = {4}, level = 10, area = 1657, quests = {1683} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94003} },
        },
        [2458] = { -- Berserker Stance
            { races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 30, area = 17, quests = {1719} },
        },
        [20252] = { -- Intercept
            { races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 30, area = 17, quests = {1719} },
        },
    },
    PALADIN = {
        [635] = { -- Holy Light
            { races = {5}, level = 2, area = 85, quests = {90902} },
        },
        [7328] = { -- Redemption
            { races = {3}, level = 12, area = 1537, quests = {1785} },
            { races = {1}, level = 12, area = 1519, quests = {1788} },
            { races = {5}, level = 12, area = 85, quests = {94441} },
        },
        [5502] = { -- Sense Undead
            { races = {1, 3}, level = 20, areas = {1519, 1537}, quests = {1652} },
        },
        [13819] = { -- Summon Warhorse
            { races = {1, 3}, level = 40, area = 1519, quests = {1661} },
        },
        [23214] = { -- Summon Charger
            { races = {1, 3}, level = 60, area = 1519, quests = {7647} },
        },
    },
    HUNTER = {
        [1515] = { -- Tame Beast
            { races = {2, 8}, level = 10, area = 14, quests = {6082} },
            { races = {6}, level = 10, area = 215, quests = {6088} },
            { races = {3}, level = 10, area = 1, quests = {6085} },
            { races = {4}, level = 10, area = 141, quests = {6102} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94013} },
            { races = {1}, level = 10, area = 12, quests = {94864} },
        },
        [5149] = { -- Beast Training
            { races = {2, 8}, level = 10, area = 14, quests = {6081} },
            { races = {6}, level = 10, area = 215, quests = {6089} },
            { races = {3}, level = 10, area = 1, quests = {6086} },
            { races = {4}, level = 10, area = 141, quests = {6103} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94050} },
            { races = {1}, level = 10, area = 12, quests = {94793} },
        },
        [883] = { -- Call Pet
            { races = {2, 8}, level = 10, area = 14, quests = {6081} },
            { races = {6}, level = 10, area = 215, quests = {6089} },
            { races = {3}, level = 10, area = 1, quests = {6086} },
            { races = {4}, level = 10, area = 141, quests = {6103} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94050} },
            { races = {1}, level = 10, area = 12, quests = {94793} },
        },
        [2641] = { -- Dismiss Pet
            { races = {2, 8}, level = 10, area = 14, quests = {6081} },
            { races = {6}, level = 10, area = 215, quests = {6089} },
            { races = {3}, level = 10, area = 1, quests = {6086} },
            { races = {4}, level = 10, area = 141, quests = {6103} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94050} },
            { races = {1}, level = 10, area = 12, quests = {94793} },
        },
        [6991] = { -- Feed Pet
            { races = {2, 8}, level = 10, area = 14, quests = {6081} },
            { races = {6}, level = 10, area = 215, quests = {6089} },
            { races = {3}, level = 10, area = 1, quests = {6086} },
            { races = {4}, level = 10, area = 141, quests = {6103} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94050} },
            { races = {1}, level = 10, area = 12, quests = {94793} },
        },
        [982] = { -- Revive Pet
            { races = {2, 8}, level = 10, area = 14, quests = {6081} },
            { races = {6}, level = 10, area = 215, quests = {6089} },
            { races = {3}, level = 10, area = 1, quests = {6086} },
            { races = {4}, level = 10, area = 141, quests = {6103} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94050} },
            { races = {1}, level = 10, area = 12, quests = {94793} },
        },
    },
    ROGUE = {
        [2842] = { -- Poisons
            { races = {1, 3, 4, 7, 95}, level = 20, area = 1519, quests = {2359} },
            { races = {2, 5, 8}, level = 20, area = 1637, quests = {2480} },
        },
    },
    PRIEST = {
        [13908] = { -- Desperate Prayer
            { races = {3}, level = 10, areas = {12, 1, 1519, 1537, 1657, 141}, quests = {5635, 5637, 5638, 5639, 5640, 5634, 5636} },
        },
        [13896] = { -- Feedback
            { races = {1}, level = 20, areas = {1519, 1537, 1657}, quests = {5676, 5677, 5678} },
        },
        [10797] = { -- Starshards
            { races = {4}, level = 10, areas = {1657, 12, 141, 1, 1519, 1537}, quests = {5627, 5628, 5629, 5630, 5631, 5632, 5633} },
        },
        [2651] = { -- Elune's Grace
            { races = {4}, level = 20, areas = {1657, 1519, 1537}, quests = {5672, 5673, 5674, 5675} },
        },
        [2652] = { -- Touch of Weakness
            { races = {5}, level = 10, areas = {1497, 14, 215, 1637, 1638}, quests = {5658, 5660, 5661, 5662, 5663} },
        },
        [9035] = { -- Hex of Weakness
            { races = {8}, level = 10, areas = {1637, 14, 215, 1497}, quests = {5652, 5654, 5655, 5656, 5657} },
        },
        [18137] = { -- Shadowguard
            { races = {8}, level = 20, areas = {1638, 1497, 1637}, quests = {5642, 5643, 5680} },
        },
        [1277370] = { -- Divine Grace
            { races = {1}, level = 10, areas = {1519, 12}, quests = {94773, 94774, 94775, 94776, 94777, 94778, 94779} },
        },
        [1277331] = { -- Chastise
            { races = {3}, level = 20, areas = {1537, 1519, 1657}, quests = {5641, 5645, 5647} },
        },
        [1277324] = { -- Dark Sacrifice
            { races = {5}, level = 20, areas = {1638, 1637, 1497}, quests = {5644, 5646, 5679} },
        },
        [1277455] = { -- Confounding Flash
            { races = {7}, level = 10, areas = {1537, 1}, quests = {94817, 94821, 94822, 94823, 94824, 94825, 94826} },
        },
        [1277462] = { -- Contingency Plan
            { races = {7}, level = 20, area = 1537, quests = {94818, 94819, 94820} },
        },
    },
    SHAMAN = {
        [8071] = { -- Stoneskin Totem
            { races = {2, 6}, level = 4, areas = {14, 215}, quests = {1518, 1521} },
            { races = {8}, level = 4, area = 14, quests = {1518} },
            { races = {3}, level = 4, area = 1, quests = {94375} },
            { races = {96}, level = 3, area = 16593, quests = {92468} },
        },
        [3599] = { -- Searing Totem
            { races = {2, 6, 8}, level = 10, area = 17, quests = {1527} },
            { races = {3}, level = 10, area = 1, quests = {94468} },
            { races = {96}, level = 10, area = 16593, quests = {97257} },
        },
        [5394] = { -- Healing Stream Totem
            { races = {2, 6, 8}, level = 20, area = 17, quests = {96} },
            { races = {3}, level = 20, area = 38, quests = {94505} },
        },
    },
    MAGE = {
        [28272] = { -- Polymorph: Pig
            { races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 60, area = 16, quests = {9364} },
        },
        [10140] = { -- Conjure Water Rank 7
            { races = {1, 2, 3, 4, 5, 6, 7, 8, 95, 96}, level = 60, area = 2557, quests = {7463} },
        },
    },
    WARLOCK = {
        [688] = { -- Summon Imp
            { races = {5}, level = 1, area = 85, quests = {1470} },
            { races = {2, 8}, level = 1, area = 14, quests = {1485} },
            { races = {1}, level = 1, area = 12, quests = {1598} },
            { races = {7}, level = 1, area = 1, quests = {1599} },
        },
        [697] = { -- Summon Voidwalker
            { races = {5}, level = 10, area = 1497, quests = {1471} },
            { races = {2, 8}, level = 10, area = 1637, quests = {1504} },
            { races = {1, 7}, level = 10, area = 1519, quests = {1689} },
        },
        [712] = { -- Summon Succubus
            { races = {5}, level = 20, area = 1497, quests = {1474} },
            { races = {2, 8}, level = 20, area = 1637, quests = {1513} },
            { races = {1, 7}, level = 20, area = 1519, quests = {1739} },
        },
        [713] = { -- Summon Incubus
            { races = {5}, level = 20, area = 1497, quests = {65597} },
            { races = {2, 8}, level = 20, area = 1637, quests = {65604} },
            { races = {1, 7}, level = 20, area = 17, quests = {65603} },
        },
        [691] = { -- Summon Felhunter
            { races = {1, 2, 5, 7, 8}, level = 30, area = 17, quests = {1795} },
        },
        [5784] = { -- Summon Felsteed
            { races = {1, 2, 5, 7, 8}, level = 40, area = 17, quests = {4490} },
        },
        [1122] = { -- Inferno
            { races = {1, 2, 5, 7, 8}, level = 50, area = 361, quests = {7603} },
        },
        [18540] = { -- Ritual of Doom
            { races = {1, 2, 5, 7, 8}, level = 60, area = 4, quests = {7583} },
        },
        [23161] = { -- Summon Dreadsteed
            { races = {1, 2, 5, 7, 8}, level = 60, area = 46, quests = {7631} },
        },
    },
    DRUID = {
        [5487] = { -- Bear Form
            { races = {4}, level = 10, area = 1657, quests = {6001} },
            { races = {6}, level = 10, area = 1638, quests = {6002} },
            { races = {95, 96}, level = 10, area = 16593, quests = {94638} },
        },
        [18960] = { -- Teleport: Moonglade
            { races = {4}, level = 10, area = 1657, quests = {5921} },
            { races = {6}, level = 10, area = 1638, quests = {5922} },
            { races = {96}, level = 10, area = 1638, quests = {94913} },
            { races = {95}, level = 10, area = 1519, quests = {94914} },
        },
        [768] = { -- Cat Form
            { races = {4, 95}, level = 20, area = 1657, quests = {98397} },
            { races = {6, 96}, level = 20, area = 1638, quests = {98362} },
        },
        [8946] = { -- Cure Poison
            { races = {4}, level = 14, area = 1657, quests = {6125} },
            { races = {6}, level = 14, area = 1638, quests = {6130} },
        },
        [1066] = { -- Aquatic Form
            { races = {4}, level = 16, area = 1657, quests = {5061} },
            { races = {6}, level = 16, area = 1638, quests = {31} },
        },
    },
}
Data.questSpells = PLAYER_CLASS and QuestSpells[PLAYER_CLASS] or nil
end

-- Hunter: abilities a pet learns. They are never in the hunter's spellbook,
-- so the module learns which the pet has from Beast Training.
if PLAYER_CLASS == "HUNTER" then
Data.petAbilityIds = {
	[4187] = true,
	[24545] = true,
	[4188] = true,
	[24549] = true,
	[4189] = true,
	[24550] = true,
	[24493] = true,
	[23992] = true,
	[24446] = true,
	[14917] = true,
	[24492] = true,
	[24488] = true,
	[4190] = true,
	[24551] = true,
	[24497] = true,
	[24439] = true,
	[24447] = true,
	[4191] = true,
	[14918] = true,
	[24552] = true,
	[24502] = true,
	[24505] = true,
	[4192] = true,
	[24553] = true,
	[24500] = true,
	[24444] = true,
	[24448] = true,
	[14919] = true,
	[24503] = true,
	[24506] = true,
	[4193] = true,
	[24554] = true,
	[4194] = true,
	[24555] = true,
	[24501] = true,
	[24445] = true,
	[24449] = true,
	[14920] = true,
	[24504] = true,
	[24507] = true,
	[5041] = true,
	[24629] = true,
	[5042] = true,
	[14921] = true,
	[24630] = true,
}
end

-- Warlock: demon tomes by level (cost in copper, family of demon), and the
-- pet spell each tome teaches, by the tome's item id.
if PLAYER_CLASS == "WARLOCK" then
Data.tomesByLevel = {
	[4] = {{itemId = 16321, cost = 100, family = "Imp"}},
	[8] = {{itemId = 16302, cost = 100, family = "Imp"}},
	[12] = {{itemId = 16331, cost = 600, family = "Imp"}},
	[14] = {{itemId = 16322, cost = 900, family = "Imp"}, {itemId = 16326, cost = 900, family = "Imp"}},
	[16] = {{itemId = 16351, cost = 1200, family = "Voidwalker"}},
	[18] = {{itemId = 16316, cost = 1500, family = "Imp"}, {itemId = 16357, cost = 1500, family = "Voidwalker"}},
	[20] = {{itemId = 16346, cost = 2000, family = "Voidwalker"}},
	[22] = {
		{id = "SUC:16375", itemId = 16375, cost = 2500, family = "Succubus"},
		{id = "INC:16375", itemId = 16375, cost = 2500, family = "Incubus"},
	},
	[24] = {
		{itemId = 16327, cost = 3000, family = "Imp"},
		{itemId = 16352, cost = 3000, family = "Voidwalker"},
		{itemId = 16363, cost = 3000, family = "Voidwalker"},
	},
	[26] = {
		{itemId = 16323, cost = 4000, family = "Imp"},
		{itemId = 16358, cost = 4000, family = "Voidwalker"},
		{id = "SUC:16379", itemId = 16379, cost = 4000, family = "Succubus"},
		{id = "INC:16379", itemId = 16379, cost = 4000, family = "Incubus"},
	},
	[28] = {
		{itemId = 16317, cost = 5000, family = "Imp"},
		{id = "SUC:16368", itemId = 16368, cost = 5000, family = "Succubus"},
		{id = "INC:16368", itemId = 16368, cost = 5000, family = "Incubus"},
	},
	[30] = {{itemId = 16347, cost = 6000, family = "Voidwalker"}},
	[32] = {
		{itemId = 16353, cost = 7000, family = "Voidwalker"},
		{id = "SUC:16380", itemId = 16380, cost = 7000, family = "Succubus"},
		{id = "INC:16380", itemId = 16380, cost = 7000, family = "Incubus"},
		{itemId = 16384, cost = 7000, family = "Felhunter"},
	},
	[34] = {
		{itemId = 16328, cost = 8000, family = "Imp"},
		{itemId = 16359, cost = 8000, family = "Voidwalker"},
		{id = "SUC:16376", itemId = 16376, cost = 8000, family = "Succubus"},
		{id = "INC:16376", itemId = 16376, cost = 8000, family = "Incubus"},
	},
	[36] = {
		{itemId = 16364, cost = 9000, family = "Voidwalker"},
		{id = "SUC:16371", itemId = 16371, cost = 9000, family = "Succubus"},
		{id = "INC:16371", itemId = 16371, cost = 9000, family = "Incubus"},
		{itemId = 16388, cost = 9000, family = "Felhunter"},
	},
	[38] = {
		{itemId = 16318, cost = 10000, family = "Imp"},
		{itemId = 16324, cost = 10000, family = "Imp"},
		{itemId = 16381, cost = 10000, family = "Felhunter"},
	},
	[40] = {
		{itemId = 16348, cost = 11000, family = "Voidwalker"},
		{itemId = 16354, cost = 11000, family = "Voidwalker"},
		{itemId = 16385, cost = 11000, family = "Felhunter"},
	},
	[42] = {
		{itemId = 16360, cost = 11000, family = "Voidwalker"},
		{itemId = 16390, cost = 11000, family = "Felhunter"},
	},
	[44] = {
		{itemId = 16329, cost = 12000, family = "Imp"},
		{id = "SUC:16372", itemId = 16372, cost = 12000, family = "Succubus"},
		{id = "INC:16372", itemId = 16372, cost = 12000, family = "Incubus"},
	},
	[46] = {
		{id = "SUC:16377", itemId = 16377, cost = 13000, family = "Succubus"},
		{id = "INC:16377", itemId = 16377, cost = 13000, family = "Incubus"},
		{itemId = 16382, cost = 13000, family = "Felhunter"},
	},
	[48] = {
		{itemId = 16319, cost = 14000, family = "Imp"},
		{itemId = 16355, cost = 14000, family = "Voidwalker"},
		{itemId = 16365, cost = 14000, family = "Voidwalker"},
		{itemId = 16386, cost = 14000, family = "Felhunter"},
	},
	[50] = {
		{itemId = 16325, cost = 15000, family = "Imp"},
		{itemId = 16349, cost = 15000, family = "Voidwalker"},
		{itemId = 16361, cost = 15000, family = "Voidwalker"},
	},
	[52] = {
		{id = "SUC:16373", itemId = 16373, cost = 18000, family = "Succubus"},
		{id = "INC:16373", itemId = 16373, cost = 18000, family = "Incubus"},
		{itemId = 16389, cost = 18000, family = "Felhunter"},
	},
	[54] = {{itemId = 16330, cost = 20000, family = "Imp"}, {itemId = 16383, cost = 20000, family = "Felhunter"}},
	[56] = {
		{itemId = 16356, cost = 22000, family = "Voidwalker"},
		{itemId = 16387, cost = 22000, family = "Felhunter"},
	},
	[58] = {
		{itemId = 16320, cost = 24000, family = "Imp"},
		{itemId = 16362, cost = 24000, family = "Voidwalker"},
		{id = "SUC:16378", itemId = 16378, cost = 24000, family = "Succubus"},
		{id = "INC:16378", itemId = 16378, cost = 24000, family = "Incubus"},
	},
	[60] = {
		{itemId = 16350, cost = 26000, family = "Voidwalker"},
		{itemId = 16366, cost = 26000, family = "Voidwalker"},
		{id = "SUC:16374", itemId = 16374, cost = 26000, family = "Succubus"},
		{id = "INC:16374", itemId = 16374, cost = 26000, family = "Incubus"},
	},
}
Data.tomeTaughtSpells = {
	[16321] = 6307,
	[16302] = 7799,
	[16331] = 4511,
	[16322] = 7804,
	[16326] = 2947,
	[16351] = 7812,
	[16316] = 7800,
	[16357] = 17767,
	[16346] = 7809,
	[16375] = 6360,
	[16327] = 8316,
	[16352] = 19438,
	[16363] = 17735,
	[16323] = 7805,
	[16358] = 17850,
	[16379] = 6358,
	[16317] = 7801,
	[16368] = 7815,
	[16347] = 7810,
	[16353] = 19440,
	[16380] = 7870,
	[16384] = 19478,
	[16328] = 8317,
	[16359] = 17851,
	[16376] = 7813,
	[16364] = 17750,
	[16371] = 7816,
	[16388] = 19244,
	[16318] = 7802,
	[16324] = 11766,
	[16381] = 19731,
	[16348] = 7811,
	[16354] = 19441,
	[16385] = 19655,
	[16360] = 17852,
	[16390] = 19480,
	[16329] = 11770,
	[16372] = 11778,
	[16377] = 11784,
	[16382] = 19734,
	[16319] = 11762,
	[16355] = 19442,
	[16365] = 17751,
	[16386] = 19656,
	[16325] = 11767,
	[16349] = 11774,
	[16361] = 17853,
	[16373] = 11779,
	[16389] = 19647,
	[16330] = 11771,
	[16383] = 19736,
	[16356] = 19443,
	[16387] = 19660,
	[16320] = 11763,
	[16362] = 17854,
	[16378] = 11785,
	[16350] = 11775,
	[16374] = 11780,
	[16366] = 17752,
}
end

-- Trainer reputation: factions[id].side (1 Alliance, 2 Horde, 0 both),
-- roles[<CLASS or PET>][<faction>] = the factions whose trainers teach it.
-- Honored with one takes 10% off at its trainers.
Data.trainerFactions = {
	factions = {
		[21] = { side = 0 },
		[47] = { side = 1, city = true },
		[54] = { side = 1, city = true },
		[68] = { side = 2, city = true },
		[69] = { side = 1, city = true },
		[72] = { side = 1, city = true },
		[76] = { side = 2, city = true },
		[81] = { side = 2, city = true },
		[349] = { side = 0 },
		[530] = { side = 2, city = true },
		[609] = { side = 0 },
		[2740] = { side = 1 },
		[2787] = { side = 2 },
	},
	roles = {
		DRUID = {
			Alliance = { 69, 72, 609, 2740 },
			Horde = { 81, 609, 2787 },
		},
		-- Forever's tome vendors charge full price at every standing (Era discounts them, so this is
		-- probably a Forever bug). No GRIMOIRE role means Pricing shows only the base cost for tomes.
		-- GRIMOIRE = {
		-- 	Alliance = { 54, 72 },
		-- 	Horde = { 68, 76 },
		-- },
		HUNTER = {
			Alliance = { 47, 69, 72 },
			Horde = { 76, 81, 530 },
		},
		MAGE = {
			Alliance = { 47, 54, 69, 72, 2740 },
			Horde = { 68, 76, 530 },
		},
		PALADIN = {
			Alliance = { 47, 72 },
			Horde = { 68 },
		},
		PET = {
			Alliance = { 47, 69, 72 },
			Horde = { 76, 81 },
		},
		PRIEST = {
			Alliance = { 47, 54, 69, 72 },
			Horde = { 68, 76, 530 },
		},
		ROGUE = {
			Alliance = { 21, 47, 54, 69, 72, 349 },
			Horde = { 21, 68, 76, 81, 349, 530 },
		},
		SHAMAN = {
			Alliance = { 47 },
			Horde = { 76, 81, 2787 },
		},
		WARLOCK = {
			Alliance = { 47, 54, 72 },
			Horde = { 68, 76 },
		},
		WARRIOR = {
			Alliance = { 47, 54, 69, 72 },
			Horde = { 68, 76, 81 },
		},
	},
	npcs = {
		[2704] = 530,
		[11865] = 47,
		[11866] = 69,
		[11867] = 72,
		[11868] = 76,
		[11869] = 81,
		[11870] = 68,
		[13084] = 47,
	},
}
