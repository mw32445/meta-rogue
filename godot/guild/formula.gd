## The Fighters' Guild: one formula of its price list (godot/guild_prices.txt,
## docs/GUILD.md).
##
## A formula is a number, or arithmetic on numbers and names:
##   + - * /     the four operations; / is exact (7 / 2 = 3.5)
##   ^           to the power of (** means the same); right to left, 2^3^2 = 2^9,
##               and above a sign, -2^2 = -4, as in mathematics; 2^-1 = 0.5
##   ( )         brackets
##   floor ceil round min max pow sqrt abs clamp lerp
##               functions: floor(x), min(a, b, ...), pow(a, b), clamp(x, low,
##               high), lerp(a, b, t) = a + (b - a) * t, ...
##   names       the variables its line allows (k, base, best, sum, n)
## Names and functions may be written in any case. Numbers may have a decimal
## point and an exponent (1.3, .5, 1e6). The arithmetic is in floating point;
## GuildPrices rounds the results to whole gold pieces.
##
## Not Godot's Expression: there ^ is exclusive or, and an Expression can call
## methods of engine objects. A price list someone downloaded must not.
##
## parse() reads a formula once (`error` says why it could not); evaluate()
## computes it for values of its names, as often as needed.
class_name GuildFormula
extends RefCounted

## The most numbers, names, operators and brackets a formula may have. Parsing and
## computing recurse, and GDScript's call stack is short: this keeps both far from
## its end (a formula 100 brackets deep), and no price needs more.
const MAX_TOKENS := 200
## The functions: name -> [fewest, most arguments] (most -1: no limit).
const FUNCTIONS := {
	"floor": [1, 1], "ceil": [1, 1], "round": [1, 1], "sqrt": [1, 1], "abs": [1, 1],
	"min": [2, -1], "max": [2, -1], "pow": [2, 2], "clamp": [3, 3], "lerp": [3, 3],
}

# The nodes of a parsed formula: [_NUM, value], [_VAR, name], [_NEG, a],
# [_ADD, a, b] (and the other operators), [_CALL, name, [arguments]].
const _NUM := 0
const _VAR := 1
const _NEG := 2
const _ADD := 3
const _SUB := 4
const _MUL := 5
const _DIV := 6
const _POW := 7
const _CALL := 8

## The formula as written (without spaces around it).
var text := ""
## Why it could not be parsed ("" when it was).
var error := ""
## Why the last evaluate() failed ("" when it did not).
var last_error := ""

var _tree: Array = []
var _names: Array = []
# while parsing: the tokens and the next one's index
var _tokens: Array = []
var _pos := 0


## Parse s; names are the variables it may use (lower case).
static func parse(s: String, names: Array) -> GuildFormula:
	var f := GuildFormula.new()
	f.text = s.strip_edges()
	f._names = names
	f._tokens = _tokenize(f.text)
	var last: Array = f._tokens[f._tokens.size() - 1]
	if last[0] == "bad":
		f.error = last[1]
	elif f._tokens.size() == 1:
		f.error = "there is no value"
	else:
		f._tree = f._sum()
		if f.error == "" and f._peek() != "end":
			f.error = f._unexpected(f._tokens[f._pos])
	f._tokens = []
	return f


## The value for these values of its names (a Dictionary name -> number). NAN
## when it has none: last_error then says why (the first problem met).
func evaluate(vars: Dictionary) -> float:
	last_error = error
	if error != "":
		return NAN
	var x := _eval(_tree, vars)
	if last_error == "" and is_nan(x):
		last_error = "the result is not a number"
	return NAN if last_error != "" else x


## The text with the given values in place of its names, e.g. "2400 / 2 + ...".
func with_values(vars: Dictionary) -> String:
	var toks := _tokenize(text)
	var out := ""
	var at := 0
	for i in toks.size() - 1:	# the last is "end"
		var t: Array = toks[i]
		if t[0] == "name" and vars.has(t[1]) and toks[i + 1][0] != "(":
			out += text.substr(at, t[2] - at) + number_text(vars[t[1]])
			at = t[3]
	return out + text.substr(at)


# ---- reading ------------------------------------------------------------------

## The tokens of s: [kind, value, start, end]. kind is "num", "name", one of the
## characters + - * / ^ ( ) , ("**" is "^"), then "end"; or, at a character that
## can't be read, "bad" with the message as value.
static func _tokenize(s: String) -> Array:
	var out: Array = []
	var i := 0
	while i < s.length():
		var c := s[i]
		var start := i
		if c == " " or c == "\t":
			i += 1
		elif _digit(c) or (c == "." and i + 1 < s.length() and _digit(s[i + 1])):
			while i < s.length() and (_digit(s[i]) or s[i] == "."):
				i += 1
			if i < s.length() and (s[i] == "e" or s[i] == "E"):	# an exponent: 1e6, 2.5E-3
				var j := i + 1
				if j < s.length() and (s[j] == "+" or s[j] == "-"):
					j += 1
				if j < s.length() and _digit(s[j]):
					i = j
					while i < s.length() and _digit(s[i]):
						i += 1
			var lit := s.substr(start, i - start)
			if lit.count(".") > 1:
				out.append(["bad", "%s is not a number" % quoted(lit), start, i])
				return out
			out.append(["num", lit.to_float(), start, i])
		elif _letter(c):
			while i < s.length() and (_letter(s[i]) or _digit(s[i])):
				i += 1
			out.append(["name", s.substr(start, i - start).to_lower(), start, i])
		elif c == "*" and i + 1 < s.length() and s[i + 1] == "*":
			i += 2
			out.append(["^", "**", start, i])
		elif "+-*/^(),".contains(c):
			i += 1
			out.append([c, c, start, i])
		else:
			out.append(["bad", "unexpected " + quoted(c), start, i + 1])
			return out
		if out.size() > MAX_TOKENS:
			out.append(["bad", "the formula is too long", i, i])
			return out
	out.append(["end", "", s.length(), s.length()])
	return out


static func _digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _letter(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


func _peek() -> String:
	return _tokens[_pos][0]


func _next() -> Array:
	var t: Array = _tokens[_pos]
	if t[0] != "end":
		_pos += 1
	return t


## Why token t can't come where it is.
func _unexpected(t: Array) -> String:
	match t[0]:
		"end":
			return "something is missing at the end"
		"num", "name", "(":
			return "an operator (+ - * / ^) is missing before " + quoted(_token_text(t))
	return "unexpected " + quoted(_token_text(t))


## A token as it is written.
func _token_text(t: Array) -> String:
	return text.substr(t[2], t[3] - t[2])


# The grammar, loosest first:
#   sum     = product (("+" | "-") product)*
#   product = unary (("*" | "/") unary)*
#   unary   = ("-" | "+") unary | power
#   power   = atom ("^" unary)?
#   atom    = number | name | name "(" sum ("," sum)* ")" | "(" sum ")"
# Each returns its node, or [] with `error` set.

func _sum() -> Array:
	var a := _product()
	while error == "" and (_peek() == "+" or _peek() == "-"):
		var op := _ADD if _next()[0] == "+" else _SUB
		var b := _product()
		a = [op, a, b]
	return a


func _product() -> Array:
	var a := _unary()
	while error == "" and (_peek() == "*" or _peek() == "/"):
		var op := _MUL if _next()[0] == "*" else _DIV
		var b := _unary()
		a = [op, a, b]
	return a


func _unary() -> Array:
	if _peek() == "-":
		_next()
		return [_NEG, _unary()]
	if _peek() == "+":
		_next()
		return _unary()
	return _power()


func _power() -> Array:
	var a := _atom()
	if error == "" and _peek() == "^":
		_next()
		return [_POW, a, _unary()]
	return a


func _atom() -> Array:
	if error != "":
		return []
	var t := _next()
	match t[0]:
		"num":
			return [_NUM, t[1]]
		"(":
			var e := _sum()
			if error == "" and _next()[0] != ")":
				error = "expected ')'"
			return e
		"name":
			var word: String = t[1]
			if _peek() == "(":
				return _call(word)
			if FUNCTIONS.has(word):
				error = "%s needs brackets: %s(...)" % [word, word]
				return []
			if not _names.has(word):
				error = "unknown name " + quoted(word)
				return []
			return [_VAR, word]
	error = _unexpected(t)
	return []


func _call(word: String) -> Array:
	_next()	# (
	if not FUNCTIONS.has(word):
		var fmt := "%s is not a function" if _names.has(word) else "unknown function %s"
		error = fmt % quoted(word)
		return []
	var args: Array = []
	if _peek() != ")":
		args.append(_sum())
		while error == "" and _peek() == ",":
			_next()
			args.append(_sum())
	if error == "" and _next()[0] != ")":
		error = "expected ')'"
	if error != "":
		return []
	var fewest: int = FUNCTIONS[word][0]
	var most: int = FUNCTIONS[word][1]
	if args.size() < fewest or (most >= 0 and args.size() > most):
		if most < 0:
			error = "%s takes %d or more arguments" % [word, fewest]
		else:
			error = "%s takes %d argument%s" % [word, fewest, "" if fewest == 1 else "s"]
		return []
	return [_CALL, word, args]


# ---- computing ----------------------------------------------------------------

func _eval(t: Array, vars: Dictionary) -> float:
	match t[0]:
		_NUM:
			return t[1]
		_VAR:
			return float(vars.get(t[1], 0))
		_NEG:
			return -_eval(t[1], vars)
		_ADD:
			return _eval(t[1], vars) + _eval(t[2], vars)
		_SUB:
			return _eval(t[1], vars) - _eval(t[2], vars)
		_MUL:
			return _eval(t[1], vars) * _eval(t[2], vars)
		_DIV:
			var a := _eval(t[1], vars)
			var b := _eval(t[2], vars)
			if b == 0.0:
				return _fail("division by zero")
			return a / b
		_POW:
			return _pow(_eval(t[1], vars), _eval(t[2], vars))
		_CALL:
			var x: Array[float] = []
			for a in t[2]:
				x.append(_eval(a, vars))
			match t[1]:
				"floor":
					return floorf(x[0])
				"ceil":
					return ceilf(x[0])
				"round":
					return roundf(x[0])
				"sqrt":
					if x[0] < 0.0:
						return _fail("the square root of a negative number")
					return sqrt(x[0])
				"abs":
					return absf(x[0])
				"min":
					return x.min()
				"max":
					return x.max()
				"pow":
					return _pow(x[0], x[1])
				"clamp":
					return clampf(x[0], x[1], x[2])
				"lerp":
					return lerpf(x[0], x[1], x[2])
	return _fail("an unknown operation")


func _pow(a: float, b: float) -> float:
	if a == 0.0 and b < 0.0:
		return _fail("division by zero")
	if a < 0.0 and b != floorf(b):
		return _fail("a power of a negative number that is not whole")
	return pow(a, b)


## Note the first problem; NAN.
func _fail(why: String) -> float:
	if last_error == "":
		last_error = why
	return NAN


## 17.0 -> "17", 0.5 -> "0.5".
static func number_text(v: Variant) -> String:
	if v is float and v == floorf(v) and absf(v) < 9e18:
		return str(int(v))
	return str(v)


## Text from a file in a message: in quotes, and cut short if it is long.
static func quoted(s: String) -> String:
	return "'%s'" % shortened(s)


## At most 40 characters: "abc...".
static func shortened(s: String) -> String:
	return s if s.length() <= 40 else s.substr(0, 37) + "..."
