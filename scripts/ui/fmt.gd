class_name Fmt
extends RefCounted
## Number formatting shared by the economy UI. Money is gold and every flow is shown per month.

const GOOD := Color(0.55, 0.85, 0.55)
const BAD := Color(0.95, 0.5, 0.45)
const WARN := Color(0.95, 0.75, 0.4)
const DIM := Color(1, 1, 1, 0.6)


## A sum of gold as a bare number (one decimal), optionally with an explicit sign.
static func money(m: float, signed := false) -> String:
	if absf(m) < 0.05:
		return "0" if not signed else "+0.0"
	return ("%+.1f" if signed else "%.1f") % m


## A sum of gold with its unit: "12.5 gold".
static func gold(m: float, signed := false) -> String:
	return "%s gold" % money(m, signed)


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


## 1 -> "1st", 2 -> "2nd", 11 -> "11th", 23 -> "23rd".
static func ordinal(n: int) -> String:
	var tail := n % 100
	if tail >= 11 and tail <= 13:
		return "%dth" % n
	match n % 10:
		1:
			return "%dst" % n
		2:
			return "%dnd" % n
		3:
			return "%drd" % n
	return "%dth" % n

