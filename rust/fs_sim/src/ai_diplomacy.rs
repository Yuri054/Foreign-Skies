//! The AI's diplomacy where the rules lean on it (`scripts/ai/ai_diplomacy.gd`): whether an AI nation joins the war it is called to,
//! whether it would declare one on another (`war_check`, `war_option`), and the odds and desire they are weighed by. Its plans
//! (`ai_plans`) are not ported, so none ever exists.

use crate::gd::{clampf, maxf, minf};
use crate::declare::JoinDecision;
use crate::state::{Data, GameState};

/// What `AIDiplomacy.war_check` finds: the reason a nation would not declare ("" if it would), the casus belli it would use, and the
/// figures weighed.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct WarCheck {
    pub reason: &'static str,
    pub cb: String,
    pub desire: f64,
    pub odds: f64,
    pub need: f64,
}

fn dv(data: &Data, path: &[&str]) -> f64 {
    let mut v = &data.ai.diplomacy;
    for p in path {
        v = &v[*p];
    }
    v.as_f64().unwrap_or_else(|| panic!("ai.json: diplomacy.{} is not a number", path.join(".")))
}

impl GameState {
    /// `AIDiplomacy.side_power`: the fighting power of the armies of a set of nations.
    pub fn side_power(&self, data: &Data, tags: &[String]) -> f64 {
        let mut total = 0.0;
        for a in &self.armies {
            if tags.contains(&a.tag) {
                total += a.power(&data.military);
            }
        }
        total
    }

    /// `AI.temperament`: aggression and caution with tension's push (a tense Europe makes every nation bolder and less careful).
    pub fn temperament(&self, data: &Data, tag: &str) -> (f64, f64) {
        let (a, c) = self.base_temperament(data, tag);
        if self.tension_bonus <= 0.0 {
            return (a, c);
        }
        (clampf(a + self.tension_bonus, 0.0, 1.0), clampf(c - self.tension_bonus * 0.5, 0.0, 1.0))
    }

    /// `AI.required_odds`: the odds a nation wants before it goes to war.
    pub fn required_odds(&self, data: &Data, tag: &str) -> f64 {
        let (a, c) = self.temperament(data, tag);
        let boldness = clampf((a + 1.0 - c) / 2.0, 0.0, 1.0);
        crate::gd::lerpf(data.ai.odds_cautious, data.ai.odds_bold, boldness)
    }

    /// `AIDiplomacy.join_value`: how much a nation wants to join the war it has been asked into.
    pub fn join_value(&self, data: &Data, d: &JoinDecision) -> f64 {
        let j = |k: &str| dv(data, &["join", k]);
        let n = self.nation(&d.tag);
        let mut v = dv(data, &["join", "kind", &d.kind]);
        v += j("w_ally_relation") * self.relation(data, &d.tag, &d.ally) / 100.0;
        if !d.enemies.is_empty() {
            let (mut hostility, mut bordering) = (0.0, 0.0);
            let neighbors = self.neighbor_nations(data, &d.tag);
            for e in &d.enemies {
                hostility += -self.relation(data, &d.tag, e) / 100.0;
                if neighbors.contains(e) {
                    bordering += 1.0;
                }
            }
            v += j("w_enemy_relation") * hostility / d.enemies.len() as f64;
            v += j("w_border") * bordering / d.enemies.len() as f64;
        }
        let mut ours = self.group_side(d.group, &d.side);
        if !ours.contains(&d.tag) {
            ours.push(d.tag.clone());
        }
        let (mine, theirs) = (self.side_power(data, &ours), self.side_power(data, &d.enemies));
        if mine + theirs > 0.0 {
            v += j("w_odds") * ((mine / (mine + theirs)) - 0.5) * 2.0;
        }
        v += j("w_support") * (n.war_support - 50.0) / 50.0;
        let monthly_revenue = maxf(n.budget.revenue, 1.0) / 12.0;
        v -= j("w_debt") * minf(1.0, maxf(0.0, -n.treasury) / monthly_revenue);
        let cost = data.diplomacy.join_decline.iter().find(|(k, _)| *k == d.kind).map(|(_, c)| *c).unwrap();
        v += j("w_decline") * (cost.ally_relations.abs() / 40.0 + cost.prestige.abs() / 10.0) / 2.0;
        v
    }

    /// `AIDiplomacy.joins`.
    pub fn ai_would_join(&self, data: &Data, d: &JoinDecision) -> bool {
        self.join_value(data, d) >= dv(data, &["join", "threshold"])
    }

    /// `AIDiplomacy.unjustified_allowed`: whether one more unjustified war keeps their share of the AI's declarations at or under the cap.
    pub fn unjustified_allowed(&self, data: &Data) -> bool {
        let total = self.ai_declarations.0 + 1;
        let unjustified = self.ai_declarations.1 + 1;
        unjustified as f64 / total as f64 <= data.ai.unjustified_share_max + 0.000001
    }

    /// `AIDiplomacy.in_truce`: whether the two nations made peace less than `truce_days` ago.
    pub fn in_truce(&self, data: &Data, a: &str, b: &str) -> bool {
        let today = self.calendar.days_elapsed as i64;
        let truce = dv(data, &["war", "truce_days"]) as i64;
        for w in self.war_history.iter().rev() {
            if today - w.end_day > truce {
                break;
            }
            if (w.a == a && w.b == b) || (w.a == b && w.b == a) {
                return true;
            }
        }
        false
    }

    /// `AIDiplomacy.has_plan`: whether a nation has a plan to attack another.
    pub fn has_plan(&self, tag: &str, target: &str) -> bool {
        self.ai_plans.iter().any(|p| p["nation"] == tag && p["enemy"] == target && p["posture"] == "offensive")
    }

    fn side_of_tag(&self, tag: &str) -> Vec<String> {
        let mut out = vec![tag.to_string()];
        out.extend(self.allies_of(tag));
        out
    }

    /// `AIDiplomacy.odds_against`: our side's power (with our allies) over the target's and its allies'.
    pub fn odds_against(&self, data: &Data, tag: &str, target: &str) -> f64 {
        let ours = self.side_of_tag(tag);
        let mut theirs = vec![target.to_string()];
        for t in self.allies_of(target) {
            if !ours.contains(&t) && !theirs.contains(&t) {
                theirs.push(t);
            }
        }
        self.side_power(data, &ours) / maxf(self.side_power(data, &theirs), 0.01)
    }

    /// `Diplomacy.grievance`: how much `holder` resents `target`: the grievance or the old rivalry, the greater.
    pub fn grievance_of(&self, holder: &str, target: &str) -> f64 {
        let key = format!("{holder}>{target}");
        maxf(self.grievance.get(&key).copied().unwrap_or(0.0), self.rivalries.get(&key).copied().unwrap_or(0.0))
    }

    /// `Diplomacy.revanche_ids`: the claims `a` made in play on ground `b` holds now.
    pub fn revanche_ids(&self, a: &str, b: &str, from_war: bool) -> Vec<usize> {
        let mut out: Vec<usize> = vec![];
        for claim in &self.claims {
            if claim["holder"] == a && (!from_war || claim["war"].as_bool().unwrap_or(false)) {
                for id in claim["ids"].as_array().into_iter().flatten().filter_map(|x| x.as_u64()) {
                    if self.province_owner[id as usize] == b && !out.contains(&(id as usize)) {
                        out.push(id as usize);
                    }
                }
            }
        }
        out
    }

    /// `Diplomacy.refused_lately`: whether `b` refused a demand of `a`'s in the last `refusal_days`.
    pub fn refused_lately(&self, data: &Data, a: &str, b: &str) -> bool {
        let days = data.diplomacy.raw_war["provocation"].get("refusal_days").and_then(|x| x.as_i64()).unwrap_or(0);
        let today = self.calendar.days_elapsed as i64;
        self.casus_belli.iter().any(|cb| cb.holder == a && cb.target == b && cb.refused_day >= 0 && today - cb.refused_day <= days)
    }

    /// `AIDiplomacy.war_desire`: how much `tag` wants a war with `target`, before odds, gates and the cap.
    pub fn war_desire(&self, data: &Data, tag: &str, target: &str, justified: bool) -> f64 {
        let w = |k: &str| dv(data, &["war", k]);
        let hostile = clampf(-self.relation(data, tag, target) / 100.0, 0.0, 1.0);
        let grievance = self.grievance_of(tag, target) / 100.0;
        let mut desire = w("w_hostile") * hostile + w("w_grievance") * grievance + w("w_tension") * self.tension / 100.0 * hostile;
        if self.has_plan(tag, target) {
            desire += w("w_plan");
        }
        if justified {
            desire += w("w_cb");
        }
        // Ground the target took from it at a peace, or a demand it refused lately.
        if !self.revanche_ids(tag, target, false).is_empty() {
            desire += w("w_revanche");
        }
        if self.refused_lately(data, tag, target) {
            desire += w("w_refused");
        }
        // A nation that stands apart from the quarrels, or that a third power guarantees, is not a target to reach for lightly.
        if self.is_neutral(data, target) {
            desire -= w("neutral_penalty");
        }
        if self.guarantors_of(target).iter().any(|g| g != tag) {
            desire -= w("guaranteed_penalty");
        }
        desire
    }

    /// `AIDiplomacy.war_check`: the weighing of a declaration, with the reason it stops.
    pub fn war_check(&self, data: &Data, tag: &str, target: &str) -> WarCheck {
        let w = |k: &str| dv(data, &["war", k]);
        let mut out = WarCheck { reason: "", cb: "none".to_string(), ..Default::default() };
        if !self.declare_block(data, tag, target).is_empty() {
            out.reason = "blocked";
            return out;
        }
        if self.in_truce(data, tag, target) {
            out.reason = "truce";
            return out;
        }
        let options = self.casus_belli_options(data, tag, target);
        let cb = options[0].clone();
        out.cb = cb.clone();
        let justified = cb != "none";
        let threshold = data.diplomacy.raw_war["provocation"]["retaliation_threshold"].as_f64().unwrap_or(0.0);
        let mut provoked = self.grievance_of(tag, target) >= threshold && justified;
        // Ground the target took at the peace after a war is provocation enough to fight in a calm Europe.
        provoked = provoked || !self.revanche_ids(tag, target, true).is_empty();
        // In a calm Europe the AI starts no wars of its own choosing.
        let may_declare = !self.pressure_ai || self.tension >= self.war_gate(data, &self.scenario_war_gate);
        if !provoked && !may_declare {
            out.reason = "calm";
            return out;
        }
        // An AI goes to war only when its country is mobilized, or it has been provoked past bearing.
        if self.nation(tag).mobilization < data.diplomacy.min_mobilization && !provoked {
            out.reason = "unmobilized";
            return out;
        }
        if !self.can_declare(data, tag, target, &cb) || !self.can_afford(tag, self.points_cost(data, "declare_war", &cb)) {
            out.reason = "cannot";
            return out;
        }
        let (aggression, _) = self.temperament(data, tag);
        let desire = self.war_desire(data, tag, target, justified);
        out.desire = desire;
        if desire * (0.5 + aggression) < w("declare_threshold") {
            out.reason = "desire";
            return out;
        }
        // A casus belli alone is no reason: a defensive tie to someone else's war does not make a nation fight.
        if self.war_desire(data, tag, target, false) < w("min_motive") {
            out.reason = "motive";
            return out;
        }
        let odds = self.odds_against(data, tag, target);
        out.odds = odds;
        if justified {
            out.need = self.required_odds(data, tag) * w("odds_margin");
            if odds < out.need {
                out.reason = "odds";
                return out;
            }
        } else {
            out.need = w("unjustified_odds");
            if !self.has_plan(tag, target) {
                out.reason = "plan";
                return out;
            }
            if aggression < w("unjustified_min_aggression") {
                out.reason = "temper";
                return out;
            }
            if odds < w("unjustified_odds") || !self.unjustified_allowed(data) {
                out.reason = if odds < w("unjustified_odds") { "odds" } else { "cap" };
                return out;
            }
        }
        out
    }

    /// `AIDiplomacy.war_option`: the casus belli an AI nation would declare war on a target with, if it should.
    pub fn war_option(&self, data: &Data, tag: &str, target: &str) -> Option<String> {
        let c = self.war_check(data, tag, target);
        if c.reason.is_empty() {
            Some(c.cb)
        } else {
            None
        }
    }
}
