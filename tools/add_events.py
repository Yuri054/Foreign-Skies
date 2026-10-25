"""Adds the second batch of historical events to data/events.json and two minor focus extras to data/focus.json.
Run once (it skips ids that exist): python3 tools/add_events.py"""
import json

def ev(id, title, text, date, until, actors, options, ai=0, **kw):
    out = {"id": id, "title": title, "text": text, "date": list(date), "actors": actors,
           "options": [{"label": l, "text": t, "effects": e} for l, t, e in options], "ai_option": ai, "until": list(until)}
    out.update(kw)
    return out

R = lambda a, b, n: {"relation": [a, b, n]}
P = lambda a, n: {"prestige": [a, n]}
T = lambda a, n: {"treasury": [a, n]}
S = lambda a, n: {"war_support": [a, n]}
TN = lambda n: {"tension": n}

NEW = [
    ev("chamberlain_overture", "Chamberlain's overture",
       "Britain's colonial secretary hints at an understanding with Germany: a quiet alliance against Russia and France.",
       (1901, 3), (1901, 9), {"a": "GBR", "b": "GER"},
       [("Pursue an understanding", "Talk, and see what Berlin wants.", [R("a", "b", 10), TN(-1), P("a", -1)]),
        ("Keep our hands free", "Splendid isolation has served well enough.", [P("a", 1)])], 1),
    ev("venezuela", "The Venezuela blockade",
       "Germany and Britain are blockading Venezuelan ports to collect unpaid debts, and Washington is watching.",
       (1902, 12), (1903, 4), {"a": "GER", "b": "GBR"},
       [("Join the blockade", "Gunboats make a debtor pay.", [T("a", 1), P("a", 1), R("a", "b", 3), TN(1)]),
        ("Leave it to others", "Not worth the quarrel with America.", [])], 0),
    ev("baghdad_concession", "The Baghdad Railway concession",
       "The Sultan offers a German company the right to build a railway from Konya to the Persian Gulf.",
       (1903, 3), (1903, 9), {"a": "GER", "b": "OTT"},
       [("Take the concession", "German steel and German influence reach the Gulf.", [T("a", -4), R("a", "b", 10), P("a", 1), TN(2)]),
        ("Decline", "The cost and the quarrel are not worth it.", [])], 0),
    ev("delcasse", "The fall of Delcassé",
       "Germany has made it plain that it will not tolerate the French foreign minister's Moroccan policy. Paris must decide whether he stays.",
       (1905, 6), (1905, 10), {"a": "FRA", "b": "GER"},
       [("Let him go", "Peace is worth a minister.", [P("a", -2), R("a", "b", 4), TN(-2)]),
        ("Back him", "France will not take orders from Berlin.", [R("a", "b", -10), TN(5), S("a", 3)])], 0),
    ev("portsmouth", "The Treaty of Portsmouth",
       "American mediation has ended the war with Japan. Russia pays no indemnity, but the army and the treasury are exhausted.",
       (1905, 9), (1906, 2), {"a": "RUS"},
       [("Sign the treaty", "Better peace abroad while the revolution burns at home.", [P("a", -2), S("a", -4), T("a", 2)])], 0),
    ev("persian_revolution", "Persia's constitution",
       "A revolution in Tehran has forced the Shah to grant a parliament, and the great powers circle.",
       (1906, 8), (1907, 2), {"a": "RUS", "b": "GBR"},
       [("Watch and wait", "Keep the Shah's court close.", [R("a", "b", -2)]),
        ("Back the Shah", "A constitution so near the Caucasus is dangerous.", [R("a", "b", -6), P("a", 1), TN(2)])], 0),
    ev("tegetthoff", "The Tegetthoff class",
       "The Austro-Hungarian navy wants four dreadnoughts for the Adriatic, and Italy is watching the slipways.",
       (1910, 3), (1910, 9), {"a": "AUH", "b": "ITA"},
       [("Order the dreadnoughts", "Prestige at sea, and a bill for the Delegations.", [T("a", -6), P("a", 2), R("a", "b", -6), TN(2)]),
        ("Defer the programme", "The treasury cannot bear it.", [P("a", -1)])], 0),
    ev("albanian_revolt", "The Albanian revolt",
       "The mountain clans have risen against the new Ottoman taxes and conscription.",
       (1910, 4), (1910, 10), {"a": "OTT", "b": "ALB"},
       [("Send the army", "Crush it before it spreads.", [T("a", -3), S("a", -2), R("a", "b", -10), TN(2)]),
        ("Offer concessions", "Schools in Albanian, and fewer tax collectors.", [T("a", -1), R("a", "b", 8), P("a", -1)])], 1),
    ev("stolypin", "Stolypin is shot",
       "Russia's reforming prime minister has been assassinated in Kiev. The land reform stalls and the court drifts.",
       (1911, 9), (1912, 3), {"a": "RUS"},
       [("Carry on", "The reform has few friends left.", [P("a", -2), S("a", -3)])], 0),
    ev("morocco_treaty", "The Morocco–Congo treaty",
       "After Agadir, France takes a protectorate in Morocco, and Germany takes a strip of the French Congo.",
       (1911, 11), (1912, 3), {"a": "GER", "b": "FRA"},
       [("Accept the bargain", "A swamp for a nation's pride.", [P("a", -2), S("a", -3), R("a", "b", 3), TN(-2)]),
        ("Grumble and wait", "The public is told it was a humiliation.", [R("a", "b", -4), TN(2)])], 0),
    ev("home_rule", "The Home Rule bill",
       "The Liberal government has introduced Home Rule for Ireland, and Ulster is drilling volunteers.",
       (1912, 4), (1912, 10), {"a": "GBR"},
       [("Press on", "The Commons has its majority.", [S("a", -3), P("a", -1)]),
        ("Seek a compromise", "Exempt the north, and lose the Irish members' enthusiasm.", [S("a", -1)])], 1),
    ev("scutari", "The Scutari crisis",
       "Montenegro's army is besieging Scutari, and Austria-Hungary will not tolerate a Slav port on the Albanian coast.",
       (1913, 4), (1913, 9), {"a": "MNE", "b": "AUH"},
       [("Hold the siege", "Montenegro has paid in blood for the town.", [R("a", "b", -12), P("a", 1), TN(6)]),
        ("Yield to the Powers", "A conference in London decides the town's fate.", [P("a", -2), TN(-3)])], 1),
    ev("second_balkan", "The quarrel over the spoils",
       "The Balkan allies cannot agree on how to share Macedonia, and Bulgaria feels cheated by Serbia and Greece.",
       (1913, 6), (1913, 9), {"a": "BUL", "b": "SRB"},
       [("Strike at Serbia", "Take Macedonia by force before the others settle in.", [R("a", "b", -20), {"grievance": ["b", "a", 15]}, P("a", -2), TN(6)]),
        ("Accept Russian arbitration", "Let the Tsar decide.", [R("a", "b", 4), TN(-2)])], 1),
    ev("zabern", "The Zabern affair",
       "A lieutenant has insulted the people of an Alsatian town, and the army has taken their side against the civil authorities.",
       (1913, 11), (1914, 3), {"a": "GER", "b": "FRA"},
       [("Stand by the army", "The Reichstag protests and the army carries on.", [P("a", -2), S("a", -2), R("a", "b", -5)]),
        ("Rebuke the officers", "The Kaiser is displeased, the Reichstag appeased.", [P("a", -1), S("a", 2)])], 0),
    ev("curragh", "The Curragh incident",
       "Officers at the Curragh camp have said they would resign rather than march on Ulster.",
       (1914, 3), (1914, 6), {"a": "GBR"},
       [("Smooth it over", "The officers keep their commissions.", [S("a", -2), P("a", -1)])], 0),
]

p = "data/events.json"
d = json.load(open(p))
have = {e["id"] for e in d["events"]}
for e in NEW:
    if e["id"] not in have:
        d["events"].append(e)
d["events"].sort(key=lambda e: tuple(e["date"]))
open(p, "w").write(json.dumps(d, indent="\t", ensure_ascii=False) + "\n")

p = "data/focus.json"
f = json.load(open(p))
extras = {
    "MNE": [
        {"id": "black_mountain_levy", "name": "The Black Mountain levy", "desc": "Every man with a rifle, under his own captain.", "x": 3, "y": 0, "days": 70,
         "requires": ["modernise_army"], "effects": {"army_size": 0.15, "war_support": 4}, "ai": 0.8},
        {"id": "cetinje_court", "name": "The court at Cetinje", "desc": "A king, and daughters married into every house of Europe.", "x": 3, "y": 1, "days": 70,
         "requires": ["seek_friends"], "effects": {"prestige": 4, "diplomacy": 0.3}, "ai": 1.0}],
    "LUX": [
        {"id": "minette_steel", "name": "Steel from the Minette", "desc": "Ore and furnaces on the southern border.", "x": 3, "y": 0, "days": 80,
         "requires": ["administrative_reform"], "effects": {"gdp": 0.04, "industry": 0.02}, "ai": 1.0},
        {"id": "customs_ties", "name": "The customs union", "desc": "A small market tied to its big neighbours.", "x": 3, "y": 1, "days": 60,
         "requires": ["minette_steel"], "effects": {"trade": 0.006, "diplomacy": 0.2}, "ai": 0.8}],
}
for tag, ex in extras.items():
    cur = f["nations"][tag]["extra"]
    ids = {x["id"] for x in cur}
    cur.extend(x for x in ex if x["id"] not in ids)
open(p, "w").write(json.dumps(f, indent="\t", ensure_ascii=False) + "\n")
print(len(d["events"]), "events")
