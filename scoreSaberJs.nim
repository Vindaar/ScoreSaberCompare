import uri, strutils, sequtils, strformat, os, asyncjs, math, sets, hashes, times, algorithm
import ajax, dom, sugar, jsbind
import jsffi except `&`
include karax / prelude
import karax / [kdom, vstyles]
import karax / jjson
import jsonHelpers

type
  PlayerInfo = object
    playerId: kstring
    pp: int
    banned: int
    inactive: int
    name: kstring
    country: kstring
    role: kstring
    badges: seq[kstring]
    history: kstring
    permissions: int
    avatar: kstring
    rank: int
    countryRank: int

  ScoreStats = object
    totalScore: float
    totalRankedScore: float
    averageRankedAccuracy: float
    totalPlayCount: int
    rankedPlayCount: float

  Difficulty = enum
    dkEasy = "_Easy_SoloStandard"
    dkNormal = "_Normal_SoloStandard"
    dkHard = "_Hard_SoloStandard"
    dkExpert = "_Expert_SoloStandard"
    dkExpertPlus = "_ExpertPlus_SoloStandard"

  SongDiffIdent = object
    id: kstring
    diff: Difficulty

  Score = object
    id: kstring
    leaderboardId: int
    score: float
    uScore: float
    playerId: int
    name: kstring
    songSubName: kstring
    songAuthorName: kstring
    levelAuthorName: kstring
    rank: int
    diff: Difficulty
    timeset: kstring
    time: Time # will be set after JsonNode is parsed!


  Player = object
    name: kstring
    info: PlayerInfo
    scoreStats: ScoreStats
    scores: seq[Score]

  PlayerState = object
    numPlayers: int
    players: seq[Player]

  ModeKind = enum
    mkCommon, mkAll

  OrderPath = enum
    opRecent = "recent"
    opTop = "top"

  PageState = object
    mode: ModeKind
    orderKind: OrderPath
    sortOrder: SortOrder
    recentBy: int # index of player that decides recent played order

const host = r"https://new.scoresaber.com/api/"
const Roberto = "76561199064998839"
const Basti = "76561197972227588"

var firstDrawDone = false
var toDelete = false

proc hash(s: SongDiffIdent): Hash =
  result = hash(s.id)
  result = result !& hash($s.diff)
  result = !$result

proc `$`(diff: Difficulty): kstring =
  case diff
  of dkEasy: "Easy"
  of dkMedium: "Medium"
  of dkHard: "Hard"
  of dkExpert: "Expert"
  of dkExpertPlus: "Expert+"

proc color(diff: Difficulty): kstring =
  case diff
  of dkEasy: "#00BF7D"
  of dkMedium: "#A2A500"
  of dkHard: "#00AFF6"
  of dkExpert: "#F7766C"
  of dkExpertPlus: "#E76BF2"

proc initPlayers(num = 2): PlayerState =
  result = PlayerState(numPlayers: num)
  result.players.add Player(name: "Roberto")
  result.players.add Player(name: "Basti")

proc initPageState(mode = mkAll, orderKind = opRecent, recentBy = 0,
                   sortOrder = SortOrder.Descending): PageState =
  result = PageState(mode: mode,
                     orderKind: orderKind,
                     sortOrder: sortOrder,
                     recentBy: recentBy)

template makeRequest(url: cstring, body: untyped): untyped =
  var httpRequest {.inject.} = newXMLHttpRequest()

  if httpRequest.isNil:
    window.alert("Giving up :( Cannot create an XMLHTTP instance")
    return

  proc event(e: Event) =
    if httpRequest.readyState == rsDONE:
      if httpRequest.status == 200:
        body
      else:
        window.alert("There was a problem with the request: " & $httpRequest.status)
    # redraw to propagate changes to karax!
    if firstDrawDone:
      redraw()

  httpRequest.onreadystatechange = event
  httpRequest.open("GET", url)
  httpRequest.send()

template main(p: PlayerState): untyped {.dirty.} = p.players[pageState.recentBy]
template other(p: PlayerState): untyped {.dirty.} = p.players[^(pageState.recentBy + 1)]
const Names = @["Roberto", "Basti"]

proc main =
  var playerState = initPlayers()
  var pageState = initPageState()

  proc getPlayer(id: string, player: var Player) =
    let pidFull = &"player/{id}/full"
    let url = host & pidFull
    makeRequest(url):
      let data = httpRequest.responseText
      let dataJson = parseJson data
      player.info = fromJson(dataJson["playerInfo"], PlayerInfo)
      player.scoreStats = fromJson(dataJson["scoreStats"], ScoreStats)

  getPlayer(Roberto, playerState.main)
  getPlayer(Basti, playerState.other)

  proc renderSelect(idx: kstring,
                    names: seq[kstring],
                    onChangeProc: (e: Event, n: VNode) -> void): VNode =
    result = buildHtml:
      select(id = idx,
             onChange = onChangeProc):
        for i, xy in names:
          option(id = $i,
                 value = xy):
            text xy
    redraw()

  proc getScore(id: string, scores: var seq[Score], orderPath: OrderPath = opRecent,
                offset: int = 1) =
    let pidFull = &"player/{id}/scores/{orderPath}/{offset}"
    let url = host & pidFull
    makeRequest(url):
      let data = httpRequest.responseText
      let dataJson = parseJson data
      for x in dataJson["scores"]:
        var curScore = fromJson(x, Score)
        # parse time
        curScore.time = parseTime($curScore.timeset, "YYYY-MM-dd'T'HH:mm:ss'.000Z'", utc())
        scores.add curScore

  proc getAllScores(id: string, player: var Player) =
    for idx in countup(1, ceil(player.scoreStats.totalPlayCount.float / 8).int):
      getScore(id, player.scores, offset = idx)

  proc renderButton(caption: string,
                    class = "",
                    onClickProc: () -> void): VNode =
    buildHtml:
      button(class = "clear-completed",
             onClick = onClickProc):
        text caption

  proc update(ev: Event, n: VNode) =
    getPlayer(Roberto, playerState.main)
    getPlayer(Basti, playerState.other)
    getAllScores(Basti, playerState.other)
    getAllScores(Roberto, playerState.main)
    toDelete = not toDelete

  proc deleteState(ev: Event, n: VNode) =
    playerState = initPlayers()
    toDelete = not toDelete

  proc showAllSongs(ev: Event, n: VNode) =
    pageState.mode = mkAll
    redraw()

  proc showCommonSongs(ev: Event, n: VNode) =
    pageState.mode = mkCommon
    redraw()

  proc renderSongs(p: Player, songs: seq[Score]): VNode =
    result = buildHtml(tdiv):
      for i in 0 ..< songs.len:
        span(text &"Song: {songs[i].songAuthorName} - {songs[i].name}")
        span(text &" {$songs[i].diff}",
                   style = style(StyleAttr.color, color(songs[i].diff)))
        br()
        span(text &"Rank: {songs[i].rank}")
        span(text &"\tDate: {$songs[i].time}",
                   style = style(StyleAttr.cssFloat, "right"))
        br()
        br()

  proc toSongDiff(s: Score): SongDiffIdent =
    SongDiffIdent(id: s.id, diff: s.diff)

  proc toSongDiff(s: seq[Score]): seq[SongDiffIdent] =
    result = s.mapIt(it.toSongDiff)

  proc findSong(songs: seq[Score], s: Score): Score =
    ## returns the index of song corresponding to `id` in `songs`
    for i, el in songs:
      if el.toSongDiff == s.toSongDiff:
        return el

  proc renderSongSelection(): VNode =
    var mainSongs: seq[Score]
    var otherSongs: seq[Score]
    case pageState.mode
    of mkCommon:
       # find all common songs
       doAssert playerState.numPlayers == 2, "Code after this only works for 2 players right now!"
       let p1Set = playerState.players[0].scores.toSongDiff.toSet
       let p2Set = playerState.players[1].scores.toSongDiff.toSet
       let common = p1Set * p2Set

       mainSongs = playerState.players[pageState.recentBy].scores.filterIt(
         SongDiffIdent(id: it.id,
                       diff: it.diff) in common
       ).sorted(cmp = (proc(a, b: Score): int =
                           result = system.cmp(a.time, b.time)),
                order = pageState.sortOrder)
       for r in mainSongs:
         otherSongs.add findSong(playerState.players[^(pageState.recentBy + 1)].scores, r)
    of mkAll:
       mainSongs = playerState.main.scores.sorted(
         cmp = (proc(a, b: Score): int =
                    result = system.cmp(a.time, b.time)),
         order = pageState.sortOrder)
       otherSongs = playerState.other.scores.sorted(
         cmp = (proc(a, b: Score): int =
                    result = system.cmp(a.time, b.time)),
         order = pageState.sortOrder)

    result = buildHtml(tdiv):
      tdiv(class = "split left"):
        p:
          span(text &"{Names[pageState.recentBy]} # scores: ")
          span(text($playerState.main.scores.len))
        p:
          renderSongs(playerState.main, mainSongs)

      tdiv(class = "split right"):
        p:
          span(text &"{Names[^(pageState.recentBy + 1)]} # scores: ")
          span(text($playerState.other.scores.len))
        p:
          renderSongs(playerState.other, otherSongs)

  proc render(): VNode =
    result = buildHtml(tdiv):
      h1(text "ScoreSaberCompare")

      if not toDelete:
        button(class = "press me", onclick = update):
          text "Update data from ScoreSaber.com"
      else:
        button(class = "press me", onclick = deleteState):
          text "Delete current data"

      button(class = "press me", onclick = showAllSongs):
        text "Show all songs"

      button(class = "press me", onclick = showCommonSongs):
        text "Show common songs"

      renderSelect(
        idx = "0",
        names = Names.mapIt(it.kstring),
        onChangeProc = proc (e: Event, n: VNode) =
                         pageState.recentBy =
                           case $n.value
                           of Names[0]: 0
                           of Names[1]: 1
                           else: 0
      )

      renderSelect(
        idx = "1",
        names = @["Ascending".kstring, "Descending".kstring],
        onChangeProc = proc (e: Event, n: VNode) =
                         pageState.sortOrder =
                           case $n.value
                           of "Ascending": SortOrder.Ascending
                           of "Descending": SortOrder.Descending
                           else: SortOrder.Descending
      )

      renderSongSelection()

    firstDrawDone = true

  setRenderer render, "ROOT"

when isMainModule:
  main()
