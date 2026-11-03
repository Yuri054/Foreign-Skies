//! What the player does in diplomacy (`diplomacy.gd`'s "Buying points", "Improving relations" and "Treaty proposals and gifts",
//! "Cancelling treaties", and the commands `buy_points.gd`, `improve_relations.gd`, `propose_treaty.gd`, `gift.gd`, `cancel_treaty.gd`,
//! `rename_alliance.gd`, `declare_war.gd` that charge diplomacy points for them). Whether a nation accepts a treaty is a plain rule of
//! the game (opinion against a bar), so it is ported.

use crate::gd::{clampf, maxf};
use crate::state::{Data, GameState, RelationProject};
use serde_json::{json, Value};

/// The result of proposing a treaty (`Diplomacy.propose_treaty`).
#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
pub struct Proposal {
    pub ok: bool,
    pub reason: String,
    pub accepted: bool,
}

fn f(v: &Value) -> f64 {
    v.as_f64().unwrap_or_else(|| panic!("diplomacy.json: {v} is not a number"))
}

impl GameState {
    fn today(&self) -> i64 {
        self.calendar.days_elapsed as i64
    }

    // ---------------------------------------------------------------- diplomacy points

    /// `Diplomacy.cost_of`: what an action costs in diplomacy points.
    pub fn points_cost(&self, data: &Data, action: &str, detail: &str) -> f64 {
        let costs = &data.diplomacy.raw_points["costs"];
        if action == "gift" || action == "improve_relations" {
            return f(&costs[action]);
        }
        costs[action].get(detail).map(f).unwrap_or(0.0)
    }

    /// `Diplomacy.purchase_price`: what the next batch of points costs the treasury.
    pub fn purchase_price(&self, data: &Data, tag: &str) -> f64 {
        f(&data.diplomacy.raw_points["purchase"]["base_cost"]) * self.nation(tag).points_price
    }

    /// `Diplomacy.purchase_block`: "full", "money" or "".
    pub fn purchase_block(&self, data: &Data, tag: &str) -> &'static str {
        if !self.nation_index.contains_key(tag) {
            return "unknown";
        }
        if self.nation(tag).diplomacy_points >= data.diplomacy.points_max {
            return "full";
        }
        if self.nation(tag).treasury < self.purchase_price(data, tag) {
            return "money";
        }
        ""
    }

    /// `BuyPoints.execute`: pays for a batch of points; the price of the next rises.
    pub fn buy_points(&mut self, data: &Data, tag: &str) -> bool {
        if !self.purchase_block(data, tag).is_empty() {
            return false;
        }
        let ni = self.nation_index[tag];
        let price = self.purchase_price(data, tag);
        let p = &data.diplomacy.raw_points["purchase"];
        self.nations[ni].treasury -= price;
        self.nations[ni].points_price *= f(&p["price_growth"]);
        self.gain_points(data, tag, f(&p["batch"]));
        true
    }

    // ---------------------------------------------------------------- improving relations

    /// `Diplomacy.improve_block`: "unknown", "at_war", "active", "limit", "maxed" or "".
    pub fn improve_block(&self, data: &Data, from: &str, to: &str) -> &'static str {
        if from == to || !self.nation_index.contains_key(from) || !self.nation_index.contains_key(to) {
            return "unknown";
        }
        if self.at_war(from, to) {
            return "at_war";
        }
        if self.relation_projects.iter().any(|p| p.from == from && p.to == to) {
            return "active";
        }
        if self.relation_projects.iter().filter(|p| p.from == from).count() as i64 >= f(&data.diplomacy.raw_points["improve"]["max_active"]) as i64 {
            return "limit";
        }
        if self.relation(data, from, to) >= data.diplomacy.relation_max - 0.5 {
            return "maxed";
        }
        ""
    }

    /// `ImproveRelations.execute`: starts an effort to improve relations for a year; returns the reason it could not ("" if it did).
    pub fn improve_relations(&mut self, data: &Data, from: &str, to: &str) -> &'static str {
        let reason = self.improve_block(data, from, to);
        if !reason.is_empty() {
            return reason;
        }
        let cost = self.points_cost(data, "improve_relations", "");
        if !self.can_afford(from, cost) {
            return "points";
        }
        let months = f(&data.diplomacy.raw_points["improve"]["months"]) as i64;
        self.relation_projects.push(RelationProject { from: from.to_string(), to: to.to_string(), months_left: months });
        self.spend_points(data, from, cost);
        ""
    }

    // ---------------------------------------------------------------- treaty proposals and gifts

    /// `Diplomacy.proposal_block`: "unknown", "kind", "at_war", "exists" or "".
    pub fn proposal_block(&self, data: &Data, from: &str, to: &str, kind: &str) -> &'static str {
        if from == to || !self.nation_index.contains_key(from) || !self.nation_index.contains_key(to) {
            return "unknown";
        }
        if !["alliance", "guarantee", "nap", "passage"].contains(&kind) {
            return "kind";
        }
        if self.at_war(from, to) {
            return "at_war";
        }
        let host_first = kind == "passage";
        if self.has_treaty(data, kind, if host_first { to } else { from }, if host_first { from } else { to }) {
            return "exists";
        }
        ""
    }

    /// `Diplomacy.prestige_pull`: how much a nation's prestige adds to the regard others have of it when it offers a treaty.
    pub fn prestige_pull(&self, data: &Data, tag: &str) -> f64 {
        let u = &data.diplomacy.raw_points["prestige_uses"];
        let (pull, max) = (f(&u["alliance_pull"]), f(&u["alliance_pull_max"]));
        clampf(self.nation(tag).prestige * pull, -max, max)
    }

    /// `Diplomacy.treaty_acceptable`: whether `to` would agree (opinion against the bar for the kind; an alliance does not cross
    /// opposed blocs; old rivals make no pact or alliance).
    pub fn treaty_acceptable(&self, data: &Data, from: &str, to: &str, kind: &str) -> bool {
        if (kind == "nap" || kind == "alliance") && (self.rivalries.contains_key(&format!("{from}>{to}")) || self.rivalries.contains_key(&format!("{to}>{from}"))) {
            return false;
        }
        if self.relation(data, to, from) + self.prestige_pull(data, from) < f(&data.diplomacy.raw_actions["treaty_accept"][kind]) {
            return false;
        }
        if kind == "alliance" {
            let (a, b) = (self.bloc_of(from), self.bloc_of(to));
            return a.is_empty() || b.is_empty() || a == b;
        }
        true
    }

    /// `ProposeTreaty.execute` (with `Diplomacy.propose_treaty`): `from` proposes a treaty. The effort is spent whether or not they
    /// agree; a refusal gives part of it back.
    pub fn propose_treaty(&mut self, data: &Data, from: &str, to: &str, kind: &str) -> Proposal {
        let reason = self.proposal_block(data, from, to, kind);
        if !reason.is_empty() {
            return Proposal { ok: false, reason: reason.to_string(), accepted: false };
        }
        let cost = self.points_cost(data, "propose", kind);
        if !self.can_afford(from, cost) {
            return Proposal { ok: false, reason: "points".to_string(), accepted: false };
        }
        let accepted = self.treaty_acceptable(data, from, to, kind);
        if accepted {
            if kind == "passage" {
                self.add_treaty(data, kind, to, from, -1, json!({}), "");
            } else if self.add_treaty(data, kind, from, to, -1, json!({}), "") && kind == "alliance" {
                let made = self.treaties.len() - 1;
                self.name_alliance(made);
            }
            let worth = data.diplomacy.raw_points["prestige"]["treaty"].get(kind).map(f).unwrap_or(0.0);
            self.gain_prestige(from, worth);
            self.gain_prestige(to, worth);
        }
        self.spend_points(data, from, cost);
        if !accepted {
            self.gain_points(data, from, cost * f(&data.diplomacy.raw_points["refusal_refund"]));
        }
        Proposal { ok: true, reason: String::new(), accepted }
    }

    /// `Diplomacy.gift_effect`: how much a gift of `amount` would raise the receiver's opinion now.
    pub fn gift_effect(&self, data: &Data, from: &str, to: &str, amount: f64) -> f64 {
        let a = &data.diplomacy.raw_actions;
        let reference = maxf(f(&a["gift_ref_floor"]), f(&a["gift_ref_share"]) * maxf(0.0, self.nation(to).budget.revenue));
        let recent = self.gift_memory.get(&format!("{from}>{to}")).copied().unwrap_or(0.0);
        f(&a["gift_max_relation"]) * (1.0 - (-amount / reference).exp()) * (-recent / reference).exp()
    }

    /// `Gift.execute`: `from` gives `to` money; the receiver thinks better of it. Returns the reason it could not ("" if it did).
    pub fn gift(&mut self, data: &Data, from: &str, to: &str, amount: f64) -> &'static str {
        let cost = self.points_cost(data, "gift", "");
        if !self.can_afford(from, cost) {
            return "points";
        }
        if from == to || !self.nation_index.contains_key(from) || !self.nation_index.contains_key(to) || amount <= 0.0 || amount > self.nation(from).treasury {
            return "refused";
        }
        let (fi, ti) = (self.nation_index[from], self.nation_index[to]);
        self.nations[fi].treasury -= amount;
        self.nations[ti].treasury += amount;
        let effect = self.gift_effect(data, from, to, amount);
        self.change_relation(data, from, to, effect);
        *self.gift_memory.entry(format!("{from}>{to}")).or_insert(0.0) += amount;
        self.spend_points(data, from, cost);
        ""
    }

    // ---------------------------------------------------------------- cancelling

    /// `CancelTreaty.execute`: `canceller` tears up a treaty it is party to, paying the cost in `data/diplomacy.json`. Returns the
    /// reason it could not ("" if it did, "points" or "no").
    pub fn cancel_treaty(&mut self, data: &Data, canceller: &str, treaty_id: u32) -> &'static str {
        let Some(i) = self.treaties.iter().position(|t| t.id == treaty_id) else { return "no" };
        let day = self.today();
        if !self.treaties[i].involves(canceller) || !self.treaties[i].active_on(day) {
            return "no";
        }
        let kind = self.treaties[i].kind.clone();
        let cost = self.points_cost(data, "cancel", &kind);
        if !self.can_afford(canceller, cost) {
            return "points";
        }
        let c = &data.diplomacy.raw_cancel[kind.as_str()];
        let partner = self.treaties[i].other(canceller).to_string();
        self.end_treaty_at(data, i);
        self.change_relation(data, canceller, &partner, f(&c["partner_relations"]));
        let tags: Vec<String> = self.nations.iter().map(|n| n.tag.clone()).collect();
        for tag in tags {
            if tag != canceller && tag != partner {
                self.change_relation(data, canceller, &tag, f(&c["world_relations"]));
            }
        }
        let ci = self.nation_index[canceller];
        self.nations[ci].prestige += f(&c["prestige"]);
        self.spend_points(data, canceller, cost);
        ""
    }

    // ---------------------------------------------------------------- declaring, with points

    /// `DeclareWar.execute`: a declaration that costs diplomacy points. Returns the reason it could not ("" if it did).
    pub fn declare_war_for_points(&mut self, data: &Data, a: &str, b: &str, cb: &str, group: u32) -> &'static str {
        let cost = self.points_cost(data, "declare_war", cb);
        if !self.can_declare(data, a, b, cb) {
            return "no";
        }
        if !self.can_afford(a, cost) {
            return "points";
        }
        if !self.declare_war(data, a, b, cb, group) {
            return "no";
        }
        self.spend_points(data, a, cost);
        ""
    }

    // ---------------------------------------------------------------- naming alliances

    /// `Diplomacy._named_treaty`: the lowest-numbered alliance treaty of `tag`'s circle that carries a name.
    fn named_treaty(&self, tag: &str) -> Option<usize> {
        let circle = self.alliance_circle(tag);
        if circle.len() < 2 {
            return None;
        }
        let day = self.today();
        let mut best: Option<usize> = None;
        for (i, t) in self.treaties.iter().enumerate() {
            if t.kind == "alliance" && t.active_on(day) && t.terms.get("name").is_some() && circle.contains(&t.a) && circle.contains(&t.b) && best.map(|b| t.id < self.treaties[b].id).unwrap_or(true) {
                best = Some(i);
            }
        }
        best
    }

    /// `Diplomacy._name_alliance`: names a fresh alliance after its members unless one of them already stands in a named group.
    fn name_alliance(&mut self, index: usize) {
        let (a, b) = (self.treaties[index].a.clone(), self.treaties[index].b.clone());
        let existing = self.named_treaty(&a).or_else(|| self.named_treaty(&b));
        if let Some(e) = existing {
            let name = self.treaties[e].terms["name"].clone();
            self.treaties[index].terms["name"] = name;
            return;
        }
        if !self.bloc_of(&a).is_empty() || !self.bloc_of(&b).is_empty() {
            return;
        }
        let name = format!("{}–{} Alliance", self.nation(&a).display_name, self.nation(&b).display_name);
        self.treaties[index].terms["name"] = json!(name);
    }

    /// `RenameAlliance.execute`: sets the name of the alliance group `tag` stands in.
    pub fn rename_alliance(&mut self, tag: &str, name: &str) -> bool {
        if !self.nation_index.contains_key(tag) {
            return false;
        }
        let clean: String = name.trim().chars().take(40).collect();
        let Some(t) = self.named_treaty(tag) else { return false };
        if clean.is_empty() || !self.bloc_of(tag).is_empty() {
            return false;
        }
        self.treaties[t].terms["name"] = json!(clean);
        let circle = self.alliance_circle(tag);
        let day = self.today();
        for other in &mut self.treaties {
            if other.kind == "alliance" && other.active_on(day) && other.terms.get("name").is_some() && circle.contains(&other.a) {
                other.terms["name"] = json!(clean);
            }
        }
        true
    }
}
