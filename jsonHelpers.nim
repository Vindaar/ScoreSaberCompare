import jsffi, jsbind, macros, strutils
include karax / prelude
import karax / kdom
import karax / jjson

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

proc parseEnum*[T: enum](s: cstring, default: T): T =
  result = strutils.parseEnum[T]($s, default)

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

proc fromJson*(node: JsonNode, dtype: typedesc): dtype

proc fromJson*[T: object](x: var T, n: JsonNode) =
  x = fromJson(n, T)

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
      fromJson(sym, node[name])
  else:
    result.fromJson(node)

proc getFloat*(x: JsonNode): float =
  result = ($(x.getFNum)).parseFloat
