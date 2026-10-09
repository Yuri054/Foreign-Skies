class_name Fmt
extends RefCounted
## Number formatting shared by the economy UI. Money is GBP millions and every flow is shown
## per month; amounts (stockpiles) are plain quantities.

const GOOD := Color(0.55, 0.85, 0.55)
const BAD := Color(0.95, 0.5, 0.45)
const WARN := Color(0.95, 0.75, 0.4)
const DIM := Color(1, 1, 1, 0.6)


## Money in GBP millions, optionally with an explicit sign.
static func money(m: float, signed := false) -> String:
	if absf(m) < 0.05:
		return "0" if not signed else "+0.0"
	return ("%+.1f" if signed else "%.1f") % m


## Thousand tonnes as "850 kt" or "12.4 Mt".
static func kt(amount: float, signed := false) -> String:
	var sign := "+" if signed and amount > 0.5 else ""
	if absf(amount) >= 1000.0:
		return "%s%.1f Mt" % [sign, amount / 1000.0]
	return "%s%d kt" % [sign, roundi(amount)]


## A yearly figure shown per month.
static func monthly(per_year: float) -> float:
	return per_year / 12.0


## A head count as "39.6M", "412k" or "850".
static func people(n: float) -> String:
	if absf(n) >= 1_000_000.0:
		return "%.1fM" % (n / 1_000_000.0)
	if absf(n) >= 1000.0:
		return "%dk" % roundi(n / 1000.0)
	return str(roundi(n))


## Thousands separators: 1234567 -> "1,234,567".
static func thousands(n: int) -> String:
	var s := str(absi(n))
	for i in range(s.length() - 3, 0, -3):
		s = s.insert(i, ",")
	return ("-" if n < 0 else "") + s
