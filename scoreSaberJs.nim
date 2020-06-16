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
    info: PlayerInfo
    scoreStats: ScoreStats
    scores: seq[Score]

  PlayerState = object
    rob: Player
    basti: Player

  ModeKind = enum
    mkCommon, mkAll

  OrderPath = enum
    opRecent = "recent"
    opTop = "top"

  PageState = object
    mode: ModeKind
    sortOrder: OrderPath

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

proc main =
  proc getPlayer(id: string, player: var Player) =
    let pidFull = &"player/{id}/full"
    let url = host & pidFull
    makeRequest(url):
      let data = httpRequest.responseText
      let dataJson = parseJson data
      player.info = fromJson(dataJson["playerInfo"], PlayerInfo)
      player.scoreStats = fromJson(dataJson["scoreStats"], ScoreStats)

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

  var playerState = PlayerState()
  var pageState = PageState(mode: mkAll)

  getPlayer(Roberto, playerState.rob)
  getPlayer(Basti, playerState.basti)

  proc renderButton(caption: string,
                    class = "",
                    onClickProc: () -> void): VNode =
    buildHtml:
      button(class = "clear-completed",
             onClick = onClickProc):
        text caption

  proc update(ev: Event, n: VNode) =
    getPlayer(Roberto, playerState.rob)
    getPlayer(Basti, playerState.basti)
    getAllScores(Basti, playerState.basti)
    getAllScores(Roberto, playerState.rob)
    toDelete = not toDelete

  proc deleteState(ev: Event, n: VNode) =
    playerState = PlayerState()
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

  proc renderAllSongs(): VNode =
    result = buildHtml(tdiv):
      tdiv(class = "split left"):
        p:
          span(text "Roberto # scores: ")
          span(text($playerState.rob.scores.len))
        p:
          renderSongs(playerState.rob, playerState.rob.scores)

      tdiv(class = "split right"):
        p:
          span(text "Basti # scores: ")
          span(text($playerState.basti.scores.len))
        p:
          renderSongs(playerState.basti, playerState.basti.scores)

  proc toSongDiff(s: Score): SongDiffIdent =
    SongDiffIdent(id: s.id, diff: s.diff)

  proc toSongDiff(s: seq[Score]): seq[SongDiffIdent] =
    result = s.mapIt(it.toSongDiff)

  proc findSong(songs: seq[Score], s: Score): Score =
    ## returns the index of song corresponding to `id` in `songs`
    for i, el in songs:
      if el.toSongDiff == s.toSongDiff:
        return el

  proc renderCommonSongs(): VNode =
    # find all common songs
    let bastiSet = playerState.basti.scores.toSongDiff.toSet
    let robSet = playerState.rob.scores.toSongDiff.toSet
    let common = bastiSet * robSet
    let robSongs = playerState.rob.scores.filterIt(
      SongDiffIdent(id: it.id,
                    diff: it.diff) in common
    )
    var bastiSongs: seq[Score]
    for r in robSongs:
      bastiSongs.add findSong(playerState.basti.scores, r)

    result = buildHtml(tdiv):
      tdiv(class = "split left"):
        p:
          span(text "Roberto # scores: ")
          span(text($playerState.rob.scores.len))
        p:
          renderSongs(playerState.rob, robSongs)

      tdiv(class = "split right"):
        p:
          span(text "Basti # scores: ")
          span(text($playerState.basti.scores.len))
        p:
          renderSongs(playerState.basti, bastiSongs)

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

      case pageState.mode
      of mkAll: renderAllSongs()
      of mkCommon: renderCommonSongs()

    firstDrawDone = true

  setRenderer render, "ROOT"

when isMainModule:
  main()
