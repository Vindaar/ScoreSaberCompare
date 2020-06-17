import jsffi, jsbind, macros, strutils
include karax / prelude
import karax / kdom
import karax / jjson

type
  ## NOTE: until 17/06/20 ~7pm the difficulties were given as strings
  ##
  Difficulty* = enum
    dkEasy = 1 #"_Easy_SoloStandard"
    dkNormal = 3# "_Normal_SoloStandard"
    dkHard = 5 #"_Hard_SoloStandard"
    dkExpert = 7 #"_Expert_SoloStandard"
    dkExpertPlus = 9 #"_ExpertPlus_SoloStandard"


proc parseJsonToJs(json: cstring): JsObject {.jsimportgWithName: "JSON.parse".}
proc stringify*(value: JsObject | JsonNode,
                replacer: JsObject,
                space: JsObject): cstring {.jsimportgWithName: "JSON.stringify".}
proc toString*(x: JsObject | JsonNode): cstring =
  result = x.stringify(nil, toJs(2))

proc selectedIndex*(n: Node): cint {.importcpp: "#.selectedIndex".}

proc pretty*(x: JsonNode): cstring =
  result = x.stringify(nil, toJs(2))

proc parseJson*(s: kstring): JsonNode =
  result = % parseJsonToJs(s)

proc parseEnum*[T: enum](s: kstring): T =
  result = strutils.parseEnum[T]($s)

proc parseEnum*[T: enum](s: kstring, default: T): T =
  result = strutils.parseEnum[T]($s, default = default)

#proc parseFloat*(s: kstring): float =
#  result = ($s).parseFloat

proc traverseTree(input: NimNode): NimNode =
  # iterate children
  for i in 0 ..< input.len:
    case input[i].kind
    of nnkSym:
      # if we found a symbol, take it
      result = input[i]
    of nnkBracketExpr:
      # has more children, traverse
      result = traverseTree(input[i])
    else:
      error("Unsupported type: " & $input.kind)

macro getInnerType*(TT: typed): untyped =
  ## macro to get the subtype of a nested type by iterating
  ## the AST
  # traverse the AST
  let res = traverseTree(TT.getTypeInst)
  # assign symbol to result
  result = quote do:
    `res`

proc parseDifficulty*(x: var Difficulty, n: JsonNode) =
  x = Difficulty(n.getNum)

proc fromJson*(node: JsonNode, dtype: typedesc): dtype

proc fromJson*[T: object](x: var T, n: JsonNode) =
  x = fromJson(n, T)

proc fromJson*[T: enum](x: var T, n: JsonNode) =
  x = parseEnum[T](n.getStr, default = T(0))

proc fromJson*[T: bool](x: var T, n: JsonNode) =
  x = if n.getStr == "true": true else: false

proc fromJson*[T: int](x: var T, n: JsonNode) =
  x = n.getNum

proc fromJson*[T: float](x: var T, n: JsonNode) =
  x = parseFloat n.getFNum

proc fromJson*[T: cstring](x: var T, n: JsonNode) =
  x = n.getStr

proc fromJson*[T: seq](x: var T, n: JsonNode) =
  for i in 0 ..< n.len:
    fromJson(x[i], n[i])

proc fromJson*(node: JsonNode, dtype: typedesc): dtype =
  ## simplified version to convert JS JsonNode to dtype
  ## currently only supports sequence types!
  when dtype is object:
    for name, sym in result.fieldPairs:
      when dtype is Score and name == "time":
        discard
      elif dtype is Score and name == "difficulty":
        parseDifficulty(sym, node[name])
      else:
        fromJson(sym, node[name])
  else:
    result.fromJson(node)

proc getFloat*(x: JsonNode): float =
  result = ($(x.getFNum)).parseFloat
