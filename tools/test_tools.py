"""Tests of the Python tools: the AI trainer's number handling and the data validator.

    python3 -m unittest discover -s tools -p "test_*.py"
"""
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import ai_train  # noqa: E402
import validate_data  # noqa: E402


class TrainerNumbers(unittest.TestCase):
    def test_theta_round_trip(self):
        cfg = ai_train.read_ai()
        theta = ai_train.initial_theta(cfg)
        values = ai_train.theta_to_values(theta)
        for path, lo, hi, integer in ai_train.PARAMS:
            shipped = ai_train.lookup(cfg, path)
            tolerance = 0.5 if integer else (hi - lo) * 1e-3
            self.assertAlmostEqual(values[path], shipped, delta=tolerance, msg=path)

    def test_values_stay_in_range(self):
        for x in (-5.0, 0.0, 0.5, 1.0, 9.0):
            values = ai_train.theta_to_values([x] * len(ai_train.PARAMS))
            for path, lo, hi, integer in ai_train.PARAMS:
                self.assertTrue(lo <= values[path] <= hi, path)
                if integer:
                    self.assertIsInstance(values[path], int, path)

    def test_infantry_fills_what_guns_and_horse_leave(self):
        values = ai_train.theta_to_values([0.5] * len(ai_train.PARAMS))
        total = values["forces.mix.infantry"] + values["forces.mix.artillery"] + values["forces.mix.cavalry"]
        self.assertAlmostEqual(total, 1.0, delta=0.01)

    def test_advantage_is_the_candidates_gain_over_the_baseline(self):
        nations = ["AAA", "BBB", "CCC", "DDD"]
        # Seed 1: AAA and BBB play the candidate in the first run, CCC and DDD in the second.
        g1, g2 = ["AAA", "BBB"], ["CCC", "DDD"]
        run1 = ({"seed": 1}, "t", g1), {"scores": {"AAA": 3.0, "BBB": 2.0, "CCC": 0.5, "DDD": -1.0}}
        run2 = ({"seed": 1}, "t", g2), {"scores": {"AAA": 1.0, "BBB": 1.0, "CCC": 4.0, "DDD": 2.0}}
        # AAA +2, BBB +1 (candidate run 1 minus baseline run 2); CCC +3.5, DDD +3.0 (run 2 minus run 1)
        self.assertAlmostEqual(ai_train.advantage([run1, run2], nations), 9.5)

    def test_groups_split_the_nations_evenly_and_repeatably(self):
        a, b = ai_train.groups_for(7, ai_train.NATIONS)
        self.assertEqual(sorted(a + b), sorted(ai_train.NATIONS))
        self.assertEqual(len(a), len(b))
        self.assertEqual((a, b), ai_train.groups_for(7, ai_train.NATIONS))


class ApplyingNumbers(unittest.TestCase):
    """apply() rewrites numbers in the text of data/ai.json: a wrong match would change another number."""

    def test_every_value_lands_on_its_own_path_and_nothing_else_moves(self):
        text = (ROOT / "data" / "ai.json").read_text()
        theta = [(i % 7) / 7.0 + 0.05 for i in range(len(ai_train.PARAMS))]
        values = ai_train.theta_to_values(theta)
        new = ai_train.rewrite_values(text, values)
        before, after = json.loads(text), json.loads(new)
        for path, v in values.items():
            self.assertEqual(ai_train.lookup(after, path), v, path)
        self.assertEqual(_without(before, values), _without(after, values), "a number outside the trained ones changed")

    def test_a_key_of_the_same_name_elsewhere_is_left_alone(self):
        text = '{\n\t"a": {\n\t\t"x": {"k": 1},\n\t\t"k": 2\n\t},\n\t"b": {"k": 3}\n}'
        new = ai_train.rewrite_values(text, {"a.k": 20, "b.k": 30})
        self.assertEqual(json.loads(new), {"a": {"x": {"k": 1}, "k": 20}, "b": {"k": 30}})

    def test_the_layout_is_kept(self):
        text = '{\n\t"_note": "k: 1, \\"k\\": 5",\n\t"a": {\n\t\t"k": 2.5\n\t}\n}'
        new = ai_train.rewrite_values(text, {"a.k": 7})
        self.assertEqual(new, text.replace("2.5", "7"))

    def test_a_missing_path_is_an_error(self):
        with self.assertRaises(KeyError):
            ai_train.rewrite_values('{"a": {"k": 1}}', {"a.nope": 2})

    def test_apply_writes_the_file(self):
        with tempfile.TemporaryDirectory() as d:
            ai = Path(d) / "ai.json"
            shutil.copy(ROOT / "data" / "ai.json", ai)
            state = Path(d) / "state.json"
            state.write_text(json.dumps({"theta": [0.5] * len(ai_train.PARAMS)}))
            ai_train.apply(state, ai)
            cfg = json.loads(ai.read_text())
            self.assertEqual(ai_train.lookup(cfg, "offense.max_campaigns"), ai_train.theta_to_values([0.5] * len(ai_train.PARAMS))["offense.max_campaigns"])


def _without(cfg, values):
    out = json.loads(json.dumps(cfg))
    for path in values:
        node = out
        keys = path.split(".")
        for k in keys[:-1]:
            node = node[k]
        node[keys[-1]] = None
    return out


def _project_copy(tmp: Path) -> Path:
    """The project's data as text and tables, with empty stand-ins for the sound files."""
    data = tmp / "data"
    shutil.copytree(ROOT / "data", data, ignore=shutil.ignore_patterns("*.png", "*.mp3", "*.wav", "*.import", "*.uid"))
    for f in (ROOT / "data" / "audio").rglob("*"):
        if f.suffix in (".mp3", ".wav"):
            target = data / "audio" / f.relative_to(ROOT / "data" / "audio")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(b"")
    return tmp


class Validator(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = _project_copy(Path(self._tmp.name))

    def tearDown(self):
        self._tmp.cleanup()

    def _edit(self, rel: str, change):
        path = self.root / "data" / rel
        doc = json.loads(path.read_text(encoding="utf-8"))
        change(doc)
        path.write_text(json.dumps(doc), encoding="utf-8")

    def test_the_shipped_data_is_sound(self):
        self.assertEqual(validate_data.check(self.root), [])

    def test_an_event_waiting_for_nothing_is_found(self):
        def change(d):
            d["events"][0]["requires_event"] = "no_such_event"
        self._edit("events.json", change)
        problems = validate_data.check(self.root)
        self.assertTrue(any("no_such_event" in p for p in problems), problems)

    def test_a_duplicate_event_id_is_found(self):
        def change(d):
            d["events"].append(dict(d["events"][0]))
        self._edit("events.json", change)
        self.assertTrue(any("is used 2 times" in p for p in validate_data.check(self.root)))

    def test_a_claim_on_a_province_that_is_not_on_the_map_is_found(self):
        def change(d):
            d["claims"][0]["provinces"].append("Atlantis")
        self._edit("scenarios/july_1914/scenario.json", change)
        self.assertTrue(any("Atlantis" in p for p in validate_data.check(self.root)))

    def test_an_alliance_with_an_unknown_nation_is_found(self):
        def change(d):
            d["alliances"].append({"a": "FRA", "b": "XXX"})
        self._edit("scenarios/jan_1900/scenario.json", change)
        self.assertTrue(any("unknown nation XXX" in p for p in validate_data.check(self.root)))

    def test_a_missing_trained_parameter_is_found(self):
        def change(d):
            del d["offense"]["odds_bold"]
        self._edit("ai.json", change)
        self.assertTrue(any("offense.odds_bold" in p for p in validate_data.check(self.root)))

    def test_a_playlist_naming_a_missing_piece_is_found(self):
        def change(d):
            d["music"]["war"].append("no_such_piece")
        self._edit("audio.json", change)
        self.assertTrue(any("no_such_piece" in p for p in validate_data.check(self.root)))

    def test_a_focus_requiring_a_missing_focus_is_found(self):
        def change(d):
            tag = next(iter(d["nations"]))
            d["nations"][tag]["tree"][0]["requires"] = ["nonexistent_focus"]
        self._edit("focus.json", change)
        self.assertTrue(any("nonexistent_focus" in p for p in validate_data.check(self.root)))

    def test_broken_json_is_reported_not_raised(self):
        (self.root / "data" / "economy.json").write_text("{ not json")
        self.assertTrue(any("economy.json" in p and "not valid JSON" in p for p in validate_data.check(self.root)))


if __name__ == "__main__":
    unittest.main()
