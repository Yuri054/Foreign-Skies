#!/usr/bin/env python3
"""Writes the great powers' own focus trees into data/focus.json (`nations.<TAG>.tree`, which replaces the template).
Each focus: (id, name, desc, x, y, days, requires, effects, extras). The trees were written for the resource economy
(gdp, trade, growth, food, industry, construction); gold_economy() turns those effects into the gold economy's (income,
civilian_factories, cp) as they are written. Run from the project root."""
import json


def gold_economy(effects):
    """Old effects to new: gdp, trade (x5), growth (x20) and food (x1) are a fraction of base income; industry is
    civilian factories built at once (x25, at least one); construction (IC a day) is CP a day (/16, in quarters)."""
    out = {k: v for k, v in effects.items() if k not in ("gdp", "trade", "growth", "food", "industry", "construction")}
    income = sum(float(effects.get(k, 0.0)) * m for k, m in (("gdp", 5.0), ("trade", 5.0), ("growth", 20.0), ("food", 1.0)))
    if income:
        out["income"] = round(income, 3)
    if "industry" in effects:
        out["civilian_factories"] = max(1, round(float(effects["industry"]) * 25))
    if "construction" in effects:
        out["cp"] = max(0.25, round(float(effects["construction"]) / 16 * 4) / 4)
    return out


def F(id, name, desc, x, y, days, requires, effects, ai=1.0, **extra):
    d = {"id": id, "name": name, "desc": desc, "x": x, "y": y, "days": days, "requires": requires, "effects": gold_economy(effects), "ai": ai}
    d.update(extra)
    return d

TREES = {}

TREES["GER"] = [
    F("industrial_drive", "Industrial drive", "Subsidise the factories and the railways that feed them.", 0, 0, 70, [], {"gdp": 0.012}),
    F("chemical_industry", "Chemicals and electricity", "Dyes, fertilisers, dynamos: the new industries.", 0, 1, 80, ["industrial_drive"], {"industry": 0.04}),
    F("steel_cartels", "The steel cartels", "Krupp, Thyssen and the Ruhr, working to one plan.", 0, 2, 90, ["chemical_industry"], {"industry": 0.03, "construction": 6}),
    F("research_universities", "Universities and research", "The laboratories that the world copies.", 0, 3, 100, ["steel_cartels"], {"gdp": 0.012, "growth": 0.002}),
    F("naval_laws", "The Navy Laws", "Tirpitz's fleet, voted ship by ship.", 1, 0, 80, [], {"prestige": 4, "construction": 3}),
    F("weltpolitik", "Weltpolitik", "A place in the sun, in every ocean.", 1, 1, 90, ["naval_laws"], {"prestige": 6, "diplomacy": 0.5, "relation": [["GBR", -8]]}),
    F("high_seas_fleet", "The High Seas Fleet", "A fleet that makes Britain think twice.", 1, 2, 110, ["weltpolitik"], {"construction": 5, "war_support": 3, "relation": [["GBR", -8]]}, min_aggression=0.4),
    F("army_reform", "Army reform", "More corps, better drilled.", 2, 0, 80, [], {"army_size": 0.06}),
    F("general_staff", "The Great General Staff", "Moltke's school of war, and its maps.", 2, 1, 90, ["army_reform"], {"army_size": 0.05, "war_support": 3}),
    F("rail_mobilisation", "Railway mobilisation", "Timetables and marshalling yards for the great plan.", 2, 2, 100, ["general_staff"], {"construction": 10}),
    F("schlieffen_readiness", "The plan is ready", "Every corps knows its train.", 2, 3, 100, ["rail_mobilisation"], {"army_size": 0.06, "war_support": 4}, min_aggression=0.45),
    F("insurance_state", "The insurance state", "Sickness, accident and old-age insurance win the workers.", 3, 0, 80, [], {"war_support": 4, "growth": 0.002}),
    F("imperial_unity", "Imperial unity", "Reichstag, Bundesrat and the Kaiser, in step.", 3, 1, 90, ["insurance_state"], {"war_support": 5, "diplomacy": 0.3}),
    F("agrarian_compromise", "Farmers and factories", "Tariffs that keep both the Junkers and the Ruhr content.", 3, 2, 80, ["imperial_unity"], {"food": 0.1, "trade": 0.004}),
    F("dual_alliance", "Tend the Dual Alliance", "Vienna is Germany's one sure friend.", 4, 0, 70, [], {"relation": [["AUH", 10]], "diplomacy": 0.5}),
    F("baghdad_railway", "The Baghdad Railway", "Rails to the Gulf, and a friend at Constantinople.", 4, 1, 90, ["dual_alliance"], {"relation": [["OTT", 15]], "trade": 0.006, "prestige": 3}),
    F("mitteleuropa", "Mitteleuropa", "A customs union of the central powers.", 4, 2, 100, ["baghdad_railway"], {"relation": [["AUH", 8], ["ITA", 6]], "gdp": 0.012, "trade": 0.004}),
    F("place_in_the_sun", "A place in the sun", "Colonies, concessions and coaling stations.", 4, 3, 100, ["mitteleuropa", "weltpolitik"], {"prestige": 6, "trade": 0.006}),
    F("revision_of_the_map", "Revision of the map", "Germany's claim to a European peace on its own terms.", 3, 3, 90, ["imperial_unity", "schlieffen_readiness"], {"claim": ["FRA"], "prestige": 3}, min_aggression=0.55),
]

TREES["GBR"] = [
    F("imperial_preference", "Imperial preference", "Tariffs that bind the empire's trade.", 0, 0, 80, [], {"trade": 0.008, "gdp": 0.01}),
    F("colonial_office", "The Colonial Office", "Governors, garrisons and the maps in Whitehall.", 0, 1, 80, ["imperial_preference"], {"prestige": 4, "diplomacy": 0.5}),
    F("suez_and_the_routes", "Suez and the sea routes", "Coaling stations from Gibraltar to Singapore.", 0, 2, 90, ["colonial_office"], {"trade": 0.006, "construction": 3}),
    F("imperial_federation", "Imperial federation", "The dominions at the council table.", 0, 3, 100, ["suez_and_the_routes"], {"prestige": 5, "relation": [["FRA", 3]], "war_support": 3}),
    F("two_power_standard", "The two-power standard", "A navy as big as the next two together.", 1, 0, 90, [], {"construction": 6}),
    F("dreadnought_programme", "The dreadnought programme", "All-big-gun ships, as fast as the yards can lay them.", 1, 1, 110, ["two_power_standard"], {"construction": 6, "war_support": 2, "prestige": 3, "relation": [["GER", -6]]}),
    F("room_forty", "Naval intelligence", "Codebreakers and a map of every fleet.", 1, 2, 80, ["dreadnought_programme"], {"points": 10, "diplomacy": 0.3}),
    F("city_of_london", "The City of London", "The world's banker.", 2, 0, 70, [], {"gdp": 0.014, "treasury": 6}),
    F("industrial_modernisation", "Industrial modernisation", "Newer mills, better yards.", 2, 1, 80, ["city_of_london"], {"industry": 0.04}),
    F("shipyards_of_the_clyde", "The yards of the Clyde and Tyne", "Merchant and warship hulls alike.", 2, 2, 90, ["industrial_modernisation"], {"industry": 0.03, "construction": 4}),
    F("liberal_reforms", "Liberal reforms", "Pensions and insurance for the working man.", 3, 0, 80, [], {"war_support": 4, "growth": 0.002}),
    F("education_acts", "Education for all", "Schools and a literate workforce.", 3, 1, 90, ["liberal_reforms"], {"gdp": 0.01, "growth": 0.002}),
    F("home_front", "The people's budget", "A fairer tax that pays for the fleet.", 3, 2, 90, ["education_acts"], {"treasury": 8, "war_support": 3}),
    F("haldane_reforms", "The Haldane reforms", "A small, modern army and a territorial reserve behind it.", 4, 0, 90, [], {"army_size": 0.08}),
    F("expeditionary_force", "The Expeditionary Force", "Six divisions that can be in France in a fortnight.", 4, 1, 100, ["haldane_reforms"], {"army_size": 0.06, "war_support": 2}),
    F("entente_policy", "Entente policy", "Friendship with France, and then with Russia.", 4, 2, 80, [], {"relation": [["FRA", 12], ["RUS", 8]], "diplomacy": 0.5}),
    F("balance_of_power", "The balance of power", "Britain stands against whoever would rule the continent.", 4, 3, 90, ["entente_policy"], {"prestige": 5, "diplomacy": 0.5, "relation": [["GER", -5]]}),
    F("splendid_isolation", "Splendid isolation", "Free of all commitments, and proud of it.", 3, 3, 80, ["home_front"], {"gdp": 0.008, "diplomacy": 0.3, "relation": [["GER", 4]]}),
]

TREES["FRA"] = [
    F("industrial_drive", "Industrial drive", "Subsidise the factories and the railways that feed them.", 0, 0, 70, [], {"gdp": 0.012}),
    F("lorraine_iron", "Lorraine and the Nord", "The basins that feed the forges.", 0, 1, 80, ["industrial_drive"], {"industry": 0.04}),
    F("creusot_and_schneider", "Creusot and Schneider", "Guns, locomotives and steel.", 0, 2, 90, ["lorraine_iron"], {"industry": 0.03, "construction": 5}),
    F("paris_exposition", "The Paris Exposition", "A showcase that sells French goods and French taste.", 0, 3, 80, ["industrial_drive"], {"trade": 0.006, "prestige": 3}),
    F("revanche", "Revanche", "The lost provinces are not forgotten.", 1, 0, 90, [], {"war_support": 6}),
    F("plan_xvii", "Plan XVII", "The offensive that will take Alsace-Lorraine back.", 1, 1, 100, ["revanche"], {"army_size": 0.06, "war_support": 3}, min_aggression=0.4),
    F("lost_provinces", "The lost provinces", "France will have them back.", 1, 2, 90, ["plan_xvii"], {"claim": ["GER"]}, min_aggression=0.55),
    F("three_year_law", "The Three-Year Law", "Keep the conscripts longer, to match Germany's numbers.", 2, 0, 90, [], {"army_size": 0.08, "war_support": -2}),
    F("colonial_army", "The colonial army", "African and Asian troops for the metropolitan army.", 2, 1, 90, ["three_year_law"], {"army_size": 0.06}),
    F("fortress_line", "The eastern forts", "Verdun, Toul, Epinal and Belfort.", 2, 2, 100, ["colonial_army"], {"construction": 8, "war_support": 2}),
    F("laic_republic", "The secular republic", "A state above its quarrels with the Church.", 3, 0, 80, [], {"war_support": 3, "growth": 0.002}),
    F("small_farms", "The small farms", "Peasant France feeds itself.", 3, 1, 80, ["laic_republic"], {"food": 0.1}),
    F("savings_and_loans", "The savers' loans", "French savings, lent abroad for French influence.", 3, 2, 90, ["small_farms"], {"treasury": 8, "diplomacy": 0.3}),
    F("franco_russian_alliance", "The Franco-Russian alliance", "Russian numbers behind French guns.", 4, 0, 70, [], {"relation": [["RUS", 12]], "diplomacy": 0.5}),
    F("entente_cordiale", "The Entente Cordiale", "A friendship across the Channel.", 4, 1, 80, ["franco_russian_alliance"], {"relation": [["GBR", 14]], "prestige": 3}),
    F("moroccan_protectorate", "The Moroccan question", "France's claim to rule in Morocco.", 4, 2, 90, ["entente_cordiale"], {"prestige": 5, "relation": [["GER", -6]]}),
    F("diplomatic_net", "A web of friends", "Spain, Italy and the small states, one by one.", 4, 3, 90, ["moroccan_protectorate"], {"diplomacy": 0.8, "relation": [["ITA", 8], ["ESP", 6]]}),
    F("civil_service", "A civil service of merit", "The prefects and the grandes ecoles.", 3, 3, 90, ["savings_and_loans"], {"gdp": 0.012, "growth": 0.002}),
]

TREES["RUS"] = [
    F("witte_system", "The Witte system", "State railways and state loans to build an industry.", 0, 0, 80, [], {"gdp": 0.012, "construction": 4}),
    F("trans_siberian", "The Trans-Siberian", "A railway across a continent.", 0, 1, 100, ["witte_system"], {"construction": 8, "trade": 0.004}),
    F("donbas_and_baku", "The Donbas and Baku", "The fuel of a modern state.", 0, 2, 90, ["trans_siberian"], {"industry": 0.04}),
    F("putilov_works", "The Putilov works", "Guns and locomotives from St Petersburg.", 0, 3, 100, ["donbas_and_baku"], {"industry": 0.03, "construction": 4}),
    F("army_reform", "Army reform", "A bigger army after the Japanese lesson.", 1, 0, 80, [], {"army_size": 0.08}),
    F("great_programme", "The Great Programme", "A vast scheme of corps and railways to the frontier.", 1, 1, 110, ["army_reform"], {"army_size": 0.10, "construction": 10}),
    F("steamroller", "The steamroller", "A reserve of millions, ready to roll.", 1, 2, 100, ["great_programme"], {"army_size": 0.08, "war_support": 3}, min_aggression=0.4),
    F("stolypin_reforms", "The Stolypin reforms", "Peasants made owners of their land.", 2, 0, 90, [], {"food": 0.12, "growth": 0.003}),
    F("duma_and_order", "The Duma and order", "A parliament of limited powers, a state of firm ones.", 2, 1, 80, ["stolypin_reforms"], {"war_support": 5}),
    F("grain_exports", "Grain for the world", "Odessa's elevators and the ports of the Baltic.", 2, 2, 80, ["duma_and_order"], {"trade": 0.006, "gdp": 0.01}),
    F("zemstvo_schools", "Schools and zemstvos", "Literacy in the villages.", 2, 3, 90, ["grain_exports"], {"gdp": 0.01, "growth": 0.002}),
    F("pan_slav_cause", "The Pan-Slav cause", "Patron of the Orthodox and the Slavs.", 3, 0, 80, [], {"prestige": 4, "relation": [["SRB", 10], ["BUL", 6]]}),
    F("balkan_league_patron", "Patron of the Balkan League", "The small kingdoms bound to St Petersburg.", 3, 1, 90, ["pan_slav_cause"], {"relation": [["SRB", 8], ["GRE", 6], ["MNE", 8]], "diplomacy": 0.5}),
    F("the_straits", "The Straits", "Constantinople, and the gate to the Mediterranean.", 3, 2, 110, ["balkan_league_patron"], {"claim": ["OTT"], "prestige": 3}, min_aggression=0.55),
    F("franco_russian_ties", "Ties with France", "French money, French guns, French friendship.", 4, 0, 70, [], {"relation": [["FRA", 12]], "treasury": 8}),
    F("anglo_russian_entente", "The Anglo-Russian Convention", "Persia and Afghanistan settled, and a friend found.", 4, 1, 80, ["franco_russian_ties"], {"relation": [["GBR", 12]], "diplomacy": 0.5}),
    F("baltic_fleet", "The Baltic and Black Sea fleets", "Rebuilt after Tsushima.", 4, 2, 100, ["anglo_russian_entente"], {"construction": 6, "prestige": 3}),
    F("slav_congress", "A Slav congress", "A family of peoples looks to Russia.", 4, 3, 90, ["baltic_fleet", "balkan_league_patron"], {"points": 12, "diplomacy": 0.5}),
]

TREES["AUH"] = [
    F("ausgleich_economy", "Common market of the Dual Monarchy", "Austria and Hungary, one customs area.", 0, 0, 70, [], {"gdp": 0.012}),
    F("skoda_and_steyr", "Skoda and Steyr", "Arms and machines from Bohemia and Styria.", 0, 1, 90, ["ausgleich_economy"], {"industry": 0.04}),
    F("danube_trade", "The Danube and Trieste", "River barges and Adriatic freight.", 0, 2, 90, ["skoda_and_steyr"], {"trade": 0.006, "construction": 4}),
    F("hungarian_wheat", "The Hungarian plain", "Wheat for the whole monarchy.", 0, 3, 80, ["ausgleich_economy"], {"food": 0.12}),
    F("army_modernisation", "Army modernisation", "A common army, newer guns.", 1, 0, 90, [], {"army_size": 0.06}),
    F("conrad_plans", "Conrad's plans", "A war plan for the south and a war plan for the east.", 1, 1, 100, ["army_modernisation"], {"army_size": 0.05, "war_support": 3}, min_aggression=0.4),
    F("balkan_garrisons", "The Balkan garrisons", "Troops and forts on the Serbian border.", 1, 2, 90, ["conrad_plans"], {"construction": 6, "war_support": 2}),
    F("viribus_unitis", "Viribus Unitis", "Dreadnoughts for the Adriatic.", 1, 3, 110, ["balkan_garrisons"], {"construction": 6, "prestige": 3, "relation": [["ITA", -5]]}),
    F("dual_monarchy_reform", "Dual-monarchy reform", "Make the two halves work together.", 2, 0, 90, [], {"gdp": 0.01, "growth": 0.002}),
    F("languages_and_peoples", "Many peoples, one state", "Language laws and schools for each nation.", 2, 1, 90, ["dual_monarchy_reform"], {"war_support": 5}),
    F("emperors_jubilee", "The Emperor's jubilee", "Sixty years on the throne; the dynasty is the glue.", 2, 2, 80, ["languages_and_peoples"], {"war_support": 4, "prestige": 3}),
    F("south_slav_question", "The South Slav question", "Trialism, or the sword.", 2, 3, 90, ["emperors_jubilee"], {"relation": [["SRB", -6]], "war_support": 2}),
    F("german_alliance", "The German alliance", "Berlin's backing, and its price.", 3, 0, 70, [], {"relation": [["GER", 12]], "diplomacy": 0.5}),
    F("triple_alliance_renewal", "Renew the Triple Alliance", "Keep Italy in the alliance.", 3, 1, 90, ["german_alliance"], {"relation": [["ITA", 10], ["GER", 4]], "diplomacy": 0.5}),
    F("bosnia", "Bosnia and Herzegovina", "Make the occupation a part of the state.", 3, 2, 100, ["triple_alliance_renewal"], {"prestige": 5, "relation": [["SRB", -8], ["RUS", -5]]}, min_aggression=0.4),
    F("punish_serbia", "Settle with Serbia", "A small state that will not be kept down.", 3, 3, 100, ["bosnia", "balkan_garrisons"], {"claim": ["SRB"]}, min_aggression=0.55),
    F("balkan_diplomacy", "Balkan diplomacy", "Romania, Bulgaria and Greece, kept near.", 4, 0, 80, [], {"relation": [["ROM", 8], ["BUL", 8]], "diplomacy": 0.5}),
    F("railways_to_salonika", "Railways to Salonika", "A line to the Aegean.", 4, 1, 100, ["balkan_diplomacy"], {"construction": 6, "trade": 0.004}),
]

TREES["ITA"] = [
    F("northern_industry", "The industrial triangle", "Milan, Turin and Genoa.", 0, 0, 80, [], {"gdp": 0.012, "industry": 0.02}),
    F("ansaldo_and_fiat", "Ansaldo and Fiat", "Ships, guns and motor cars.", 0, 1, 90, ["northern_industry"], {"industry": 0.04}),
    F("hydroelectric_power", "Power from the Alps", "Water turned into current.", 0, 2, 90, ["ansaldo_and_fiat"], {"industry": 0.03, "construction": 4}),
    F("southern_question", "The southern question", "Bring the Mezzogiorno into the nation.", 0, 3, 90, ["northern_industry"], {"growth": 0.003, "food": 0.08}),
    F("army_of_the_north", "The army of the north", "Alpine troops and frontier forts.", 1, 0, 90, [], {"army_size": 0.06}),
    F("regia_marina", "The Regia Marina", "A fleet for two seas.", 1, 1, 100, ["army_of_the_north"], {"construction": 6, "prestige": 3}),
    F("mare_nostrum", "Mare nostrum", "The Mediterranean as an Italian lake.", 1, 2, 110, ["regia_marina"], {"prestige": 4, "relation": [["AUH", -4]]}, min_aggression=0.4),
    F("giolitti_era", "The Giolitti era", "Reform and compromise at home.", 2, 0, 80, [], {"war_support": 4, "growth": 0.002}),
    F("universal_suffrage", "Wider suffrage", "A bigger electorate, a steadier state.", 2, 1, 90, ["giolitti_era"], {"war_support": 4}),
    F("emigrants_remittances", "The emigrants' money", "Millions abroad send money home.", 2, 2, 80, ["universal_suffrage"], {"treasury": 6, "gdp": 0.008}),
    F("risorgimento_spirit", "The spirit of the Risorgimento", "A nation that finished one war of unity and wants another.", 2, 3, 90, ["emigrants_remittances"], {"war_support": 5}),
    F("triple_alliance_ties", "The Triple Alliance", "Berlin and Vienna as partners, with reservations.", 3, 0, 70, [], {"relation": [["GER", 8], ["AUH", 6]], "diplomacy": 0.5}),
    F("french_understanding", "The understanding with France", "A secret promise: no attack on France.", 3, 1, 80, ["triple_alliance_ties"], {"relation": [["FRA", 12], ["GBR", 6]], "diplomacy": 0.5}),
    F("libya", "Tripoli", "A colony across the sea.", 3, 2, 100, ["french_understanding", "regia_marina"], {"prestige": 6, "gdp": 0.008, "relation": [["OTT", -10]]}, min_aggression=0.4),
    F("irredenta", "Italia irredenta", "Trento and Trieste are Italian.", 3, 3, 90, ["libya"], {"claim": ["AUH"], "war_support": 3}, min_aggression=0.5),
    F("balkan_ambitions", "Ambitions across the Adriatic", "Albania and the Dalmatian coast.", 4, 0, 90, [], {"prestige": 3, "relation": [["SRB", -3]]}),
    F("diplomatic_service", "A larger diplomatic service", "More envoys, more favours.", 4, 1, 80, ["balkan_ambitions"], {"diplomacy": 0.8}),
]

TREES["OTT"] = [
    F("tanzimat_reforms", "The reform of the state", "Revenue, courts and a ministry that works.", 0, 0, 80, [], {"gdp": 0.014, "growth": 0.002}),
    F("hejaz_and_baghdad_rail", "Railways of the empire", "The Hejaz line and the Baghdad railway.", 0, 1, 100, ["tanzimat_reforms"], {"construction": 8, "trade": 0.004}),
    F("anatolian_agriculture", "Anatolian farming", "Better yields on the plateau.", 0, 2, 80, ["tanzimat_reforms"], {"food": 0.12}),
    F("public_debt_settlement", "Settle the public debt", "Foreign bondholders paid, credit won back.", 0, 3, 90, ["hejaz_and_baghdad_rail"], {"treasury": 6, "diplomacy": 0.3}),
    F("young_turk_revolution", "Young Turk reforms", "A constitution and a modern state.", 1, 0, 90, [], {"gdp": 0.012, "war_support": 4}),
    F("army_of_the_empire", "The reformed army", "German-trained officers, new rifles.", 1, 1, 90, ["young_turk_revolution"], {"army_size": 0.08}),
    F("german_military_mission", "The German military mission", "Officers from Berlin in every corps.", 1, 2, 90, ["army_of_the_empire"], {"army_size": 0.06, "relation": [["GER", 10], ["RUS", -6]]}),
    F("naval_programme", "The new ships", "Dreadnoughts ordered abroad.", 1, 3, 100, ["german_military_mission"], {"construction": 5, "prestige": 3}),
    F("ottomanism", "Ottomanism", "One citizenship for all the sultan's peoples.", 2, 0, 90, [], {"war_support": 5}),
    F("the_holy_cities", "Guardian of the holy cities", "The Caliph's prestige across the Muslim world.", 2, 1, 80, ["ottomanism"], {"prestige": 5, "diplomacy": 0.3}),
    F("provincial_loyalty", "Hold the provinces", "Albanians, Arabs and Macedonians kept in line.", 2, 2, 100, ["the_holy_cities"], {"war_support": 3, "construction": 4}),
    F("balkan_question", "The Balkan question", "Macedonia and Thrace must stay Ottoman.", 2, 3, 90, ["provincial_loyalty"], {"relation": [["BUL", -4], ["SRB", -4], ["GRE", -4]], "war_support": 3}),
    F("sick_man_diplomacy", "The sick man's diplomacy", "Play the great powers against each other.", 3, 0, 70, [], {"diplomacy": 0.5, "relation": [["GBR", 5], ["FRA", 5]]}),
    F("german_friendship", "Friendship with Germany", "A patron, with a price.", 3, 1, 80, ["sick_man_diplomacy"], {"relation": [["GER", 12]], "diplomacy": 0.3}),
    F("russian_fear", "Hold off Russia", "The old enemy to the north.", 3, 2, 90, ["german_friendship"], {"war_support": 4, "construction": 4}),
    F("lost_lands", "The lost lands", "Thessaly, Crete and the islands are not forgotten.", 3, 3, 100, ["russian_fear", "balkan_question"], {"claim": ["GRE"]}, min_aggression=0.55),
]

# Every great power's tree ends in the same repeatable foci, so a nation whose tree is done still has a national effort
# in hand: sound finances (a little growth, up to a limit) and two that may be taken again for ever (max 0), whose
# effects are one-off and fade (war support and prestige drift back, points are spent).
def COMMON(y):
    return [
        F("sound_finances", "Sound finances", "Balanced books and cheap credit for the country's works.", 0, y, 120, [], {"growth": 0.0005}, ai=0.6, repeatable=True, max=8),
        F("grand_manoeuvres", "Grand manoeuvres", "The army shows itself to the nation and to the attaches.", 1, y, 120, [], {"war_support": 2, "prestige": 1}, ai=0.5, repeatable=True, max=0),
        F("diplomatic_missions", "Embassies abroad", "Envoys, visits and banquets in every capital.", 2, y, 120, [], {"points": 8, "prestige": 1}, ai=0.4, repeatable=True, max=0),
    ]

if __name__ == "__main__":
    p = "data/focus.json"
    d = json.load(open(p))
    for tag, tree in TREES.items():
        tree = tree + COMMON(max(f["y"] for f in tree) + 1)
        TREES[tag] = tree
        ids = [f["id"] for f in tree]
        assert len(ids) == len(set(ids)), tag
        for f in tree:
            for r in f["requires"]:
                assert r in ids, (tag, f["id"], r)
            for pair in f["effects"].get("relation", []):
                assert len(pair) == 2
        d["nations"][tag] = {"tree": tree}
    if "nations.<TAG>.tree" not in d["_note"]:
        d["_note"] += " nations.<TAG>.tree, where present, is the nation's whole tree and replaces its template (the great powers have one of their own, written by tools/make_focus_trees.py)."
    json.dump(d, open(p, "w"), indent="\t", ensure_ascii=False)
    print({t: len(v) for t, v in TREES.items()})
