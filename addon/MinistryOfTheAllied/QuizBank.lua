-- Ministry of the Allied: the Pub Quiz's question bank (Duncan, 2026-11-12).
-- 100 questions on the world as Forever has it (the original game's era),
-- written for the guild (none copied from other sites). The quizmaster can
-- fill a round from here, use their own, or mix the two (Quiz.lua).
--
-- { id, category, question, answer, { other answers that count } }
-- Answers are matched loosely when marking (case, spaces and "the" ignored),
-- and the quizmaster has the last word. TO CHECK before the first quiz night:
-- these were written from memory, and Forever may differ from the original in
-- places. A wrong one is easy to fix or take out by its id.

local _, MOTA = ...

MOTA.QuizBank = {
  CATEGORIES = {
    { key = "lore", name = "Lore" },
    { key = "places", name = "Zones & places" },
    { key = "dungeons", name = "Dungeons & raids" },
    { key = "classes", name = "Classes & spells" },
    { key = "items", name = "Items & professions" },
    { key = "people", name = "Characters" },
  },
  Q = {
    -- Lore
    { "L01", "lore", "Who is the Warchief of the Horde?", "Thrall" },
    { "L02", "lore", "What is the capital city of the night elves?", "Darnassus" },
    { "L03", "lore", "In which great tree is Darnassus built?", "Teldrassil" },
    { "L04", "lore", "Which dragonflight does Onyxia belong to?", "The black dragonflight", { "black" } },
    { "L05", "lore", "Who is Onyxia's father?", "Deathwing", { "neltharion" } },
    { "L06", "lore", "Who leads the Forsaken?", "Sylvanas Windrunner", { "sylvanas" } },
    { "L07", "lore", "Who leads the Burning Legion?", "Sargeras" },
    { "L08", "lore", "Which race fled Gnomeregan and now lives in Ironforge?", "Gnomes", { "gnome" } },
    { "L09", "lore", "What is the capital city of the tauren?", "Thunder Bluff" },
    { "L10", "lore", "Ragnaros is a lord of which element?", "Fire" },
    { "L11", "lore", "Which clan of dwarves rules Blackrock Depths?", "The Dark Iron clan", { "dark iron", "dark iron dwarves" } },
    { "L12", "lore", "What was the name of Thrall's father?", "Durotan" },
    { "L13", "lore", "What is the capital city of the orcs?", "Orgrimmar" },
    { "L14", "lore", "Which troll tribe is allied to the Horde?", "The Darkspear tribe", { "darkspear", "darkspear trolls" } },
    { "L15", "lore", "Which ancient city is the prison of C'Thun?", "Ahn'Qiraj", { "ahnqiraj", "aq" } },
    { "L16", "lore", "Who is regent of Stormwind while the king is missing?", "Highlord Bolvar Fordragon", { "bolvar", "bolvar fordragon" } },
    { "L17", "lore", "What is the name of Stormwind's young prince?", "Anduin Wrynn", { "anduin" } },

    -- Zones & places
    { "P01", "places", "In which zone is the town of Darkshire?", "Duskwood" },
    { "P02", "places", "In which zone is Lakeshire?", "Redridge Mountains", { "redridge" } },
    { "P03", "places", "In which zone is Menethil Harbor?", "Wetlands", { "the wetlands" } },
    { "P04", "places", "Booty Bay is a port in which zone?", "Stranglethorn Vale", { "stranglethorn", "stv" } },
    { "P05", "places", "Which goblin town lies in the desert of Tanaris?", "Gadgetzan" },
    { "P06", "places", "In which snowy zone is the goblin town of Everlook?", "Winterspring" },
    { "P07", "places", "In which zone is the Horde outpost of the Crossroads?", "The Barrens", { "barrens" } },
    { "P08", "places", "Beneath which ruined city does the Undercity lie?", "Lordaeron", { "capital city of lordaeron" } },
    { "P09", "places", "In which zone is Light's Hope Chapel?", "Eastern Plaguelands", { "epl" } },
    { "P10", "places", "In which zone stands the Dark Portal?", "Blasted Lands", { "the blasted lands" } },
    { "P11", "places", "In which zone is Goldshire?", "Elwynn Forest", { "elwynn" } },
    { "P12", "places", "The port of Ratchet is in which zone?", "The Barrens", { "barrens" } },
    { "P13", "places", "In which zone is Cenarion Hold?", "Silithus" },
    { "P14", "places", "Astranaar is the main town of which zone?", "Ashenvale" },
    { "P15", "places", "In which zone is Southshore?", "Hillsbrad Foothills", { "hillsbrad" } },
    { "P16", "places", "Blackrock Mountain lies between Searing Gorge and which other zone?", "Burning Steppes" },
    { "P17", "places", "Which island in Dustwallow Marsh is Jaina Proudmoore's city?", "Theramore Isle", { "theramore" } },

    -- Dungeons & raids
    { "D01", "dungeons", "In which raid is Ragnaros the final boss?", "Molten Core", { "mc" } },
    { "D02", "dungeons", "In which zone is Onyxia's Lair?", "Dustwallow Marsh", { "dustwallow" } },
    { "D03", "dungeons", "Who is the final boss of the Deadmines?", "Edwin VanCleef", { "vancleef", "van cleef" } },
    { "D04", "dungeons", "Which dungeon is a prison inside Stormwind City?", "The Stockade", { "stockade", "stockades", "the stockades" } },
    { "D05", "dungeons", "Which dungeon in the Barrens is home to the Druids of the Fang?", "Wailing Caverns", { "wc" } },
    { "D06", "dungeons", "How many players make a full Molten Core raid?", "40", { "forty" } },
    { "D07", "dungeons", "How many players make a full Zul'Gurub raid?", "20", { "twenty" } },
    { "D08", "dungeons", "In which raid is Nefarian the final boss?", "Blackwing Lair", { "bwl" } },
    { "D09", "dungeons", "Kel'Thuzad is the final boss of which raid?", "Naxxramas", { "naxx" } },
    { "D10", "dungeons", "Which dungeon in Tirisfal Glades is the Scarlet Crusade's stronghold?", "Scarlet Monastery", { "sm" } },
    { "D11", "dungeons", "In which dungeon do you face Baron Rivendare?", "Stratholme", { "strat" } },
    { "D12", "dungeons", "Which dungeon in the Western Plaguelands is a school of necromancy?", "Scholomance", { "scholo" } },
    { "D13", "dungeons", "Hakkar the Soulflayer is the final boss of which raid?", "Zul'Gurub", { "zg", "zulgurub" } },
    { "D14", "dungeons", "Which dungeon in Desolace is home to Princess Theradras?", "Maraudon", { "mara" } },
    { "D15", "dungeons", "In which zone is the entrance to Gnomeregan?", "Dun Morogh" },
    { "D16", "dungeons", "In which dungeon do you face Archmage Arugal?", "Shadowfang Keep", { "sfk" } },
    { "D17", "dungeons", "Which sunken temple of the Atal'ai lies in the Swamp of Sorrows?", "The Temple of Atal'Hakkar", { "sunken temple", "temple of atalhakkar", "st" } },

    -- Classes & spells
    { "C01", "classes", "Which class can tame beasts as pets?", "Hunter", { "hunters" } },
    { "C02", "classes", "Which class uses Soul Shards?", "Warlock", { "warlocks" } },
    { "C03", "classes", "Which class can take bear, cat and travel form?", "Druid", { "druids" } },
    { "C04", "classes", "Which priest spell shields a friend from damage?", "Power Word: Shield", { "power word shield", "pws", "pw shield" } },
    { "C05", "classes", "Which class puts down totems?", "Shaman", { "shamans" } },
    { "C06", "classes", "Which mage spell turns an enemy into a sheep?", "Polymorph", { "poly", "sheep" } },
    { "C07", "classes", "Which paladin spell makes them immune to all damage for a short while?", "Divine Shield", { "bubble" } },
    { "C08", "classes", "What is the first demon a warlock learns to summon?", "The Imp", { "imp" } },
    { "C09", "classes", "Which class can Feign Death?", "Hunter", { "hunters" } },
    { "C10", "classes", "Which class can Vanish?", "Rogue", { "rogues" } },
    { "C11", "classes", "Which rogue poison slows the target's movement?", "Crippling Poison", { "crippling" } },
    { "C12", "classes", "Which class can open portals to the capital cities?", "Mage", { "mages" } },
    { "C13", "classes", "Which class can return home with Astral Recall?", "Shaman", { "shamans" } },
    { "C14", "classes", "Holy, Protection and Retribution are the talent trees of which class?", "Paladin", { "paladins" } },
    { "C15", "classes", "Arms, Fury and Protection are the talent trees of which class?", "Warrior", { "warriors" } },
    { "C16", "classes", "Which class can make Soulstones to bring a friend back?", "Warlock", { "warlocks" } },
    { "C17", "classes", "What do warriors build up to use their abilities?", "Rage" },

    -- Items & professions
    { "I01", "items", "Which profession makes potions and elixirs?", "Alchemy" },
    { "I02", "items", "Which secondary profession makes bandages?", "First Aid" },
    { "I03", "items", "Which profession can break magic items down into dust and essences?", "Enchanting" },
    { "I04", "items", "Which profession makes gadgets, guns and explosives?", "Engineering" },
    { "I05", "items", "Which crafting profession works leather and hides into armour?", "Leatherworking" },
    { "I06", "items", "How many copper make one silver?", "100", { "one hundred", "a hundred" } },
    { "I07", "items", "How many silver make one gold?", "100", { "one hundred", "a hundred" } },
    { "I08", "items", "Which item takes you back to the inn you made your home?", "Hearthstone", { "hearth", "hs" } },
    { "I09", "items", "Which cloth do level 50 to 60 humanoids mostly drop?", "Runecloth" },
    { "I10", "items", "Which cloth comes between wool and mageweave?", "Silk", { "silk cloth" } },
    { "I11", "items", "What colour is an epic item's name?", "Purple", { "violet" } },
    { "I12", "items", "What colour is a legendary item's name?", "Orange" },
    { "I13", "items", "What colour is an uncommon item's name?", "Green" },
    { "I14", "items", "Which legendary sword's bindings drop from Garr and Baron Geddon?", "Thunderfury, Blessed Blade of the Windseeker", { "thunderfury" } },
    { "I15", "items", "Which legendary hammer is made from the Eye of Sulfuras?", "Sulfuras, Hand of Ragnaros", { "sulfuras" } },
    { "I16", "items", "How many slots does a Traveler's Backpack have?", "16", { "sixteen" } },

    -- Characters
    { "N01", "people", "Who is the King of Ironforge?", "Magni Bronzebeard", { "magni", "king magni" } },
    { "N02", "people", "Which high priestess leads the night elves?", "Tyrande Whisperwind", { "tyrande" } },
    { "N03", "people", "Which archdruid holds court in Darnassus?", "Fandral Staghelm", { "fandral", "staghelm" } },
    { "N04", "people", "Who is the High Tinker of the gnomes?", "Gelbin Mekkatorque", { "mekkatorque", "gelbin" } },
    { "N05", "people", "Who rules Theramore Isle?", "Jaina Proudmoore", { "jaina" } },
    { "N06", "people", "Which dragon is the Aspect of Life?", "Alexstrasza" },
    { "N07", "people", "Which troll leads the Darkspear tribe?", "Vol'jin", { "voljin" } },
    { "N08", "people", "Lady Katrana Prestor of Stormwind is secretly which dragon?", "Onyxia" },
    { "N09", "people", "Which gnoll terrorises the west of Elwynn Forest?", "Hogger" },
    { "N10", "people", "Which goblin baron runs Booty Bay?", "Baron Revilgaz", { "revilgaz" } },
    { "N11", "people", "Which Bronzebeard brother is a famous explorer?", "Brann Bronzebeard", { "brann" } },
    { "N12", "people", "In the Barrens, who is Mankrik looking for?", "His wife", { "wife", "olgra", "his wife olgra" } },
    { "N13", "people", "Who leads the tauren as High Chieftain?", "Cairne Bloodhoof", { "cairne" } },
    { "N14", "people", "Which Scarlet commander fights beside High Inquisitor Whitemane?", "Scarlet Commander Mograine", { "mograine", "commander mograine" } },
    { "N15", "people", "Who leads the Cult of the Damned?", "Kel'Thuzad", { "kelthuzad" } },
    { "N16", "people", "Which red dragon do you meet, wounded, in Blackwing Lair?", "Vaelastrasz", { "vael", "vaelastrasz the corrupt" } },
  },
}

-- Loose matching for marking: lower case, no punctuation, no "the", single spaces.
function MOTA.QuizBank.Norm(s)
  s = tostring(s or ""):lower():gsub("[%p]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  return (s:gsub("^the ", ""))
end

-- Whether an answer matches a question's answer (or one of the others that count).
function MOTA.QuizBank.Matches(given, answer, others)
  local Norm = MOTA.QuizBank.Norm
  local g = Norm(given)
  if g == "" then return false end
  if g == Norm(answer) then return true end
  for _, o in ipairs(others or {}) do
    if g == Norm(o) then return true end
  end
  return false
end
