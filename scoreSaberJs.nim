import uri, strutils, sequtils, strformat, os, asyncjs, math, sets
# import httpclient
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

  Player = object
    info: PlayerInfo
    scoreStats: ScoreStats
    scores: seq[Score]

  PlayerState = object
    rob: Player
    basti: Player

  ModeKind = enum
    mkCommon, mkAll

  PageState = object
    mode: ModeKind

  OrderPath = enum
    opRecent = "recent"
    opTop = "top"

const host = r"https://new.scoresaber.com/api/"
const Roberto = "76561199064998839"
const Basti = "76561197972227588"

#proc getPlayer(client: HttpClient, id: int64): PlayerInfo =
#  let pidFull = &"player/{id}/full"
#  let url = host & pidFull
#  echo client.getContent(url)

var firstDrawDone = false

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
    #echo client.getContent(url)
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
        scores.add fromJson(x, Score)

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

  proc postRender() =
    discard

  proc update(ev: Event, n: VNode) =
    getPlayer(Roberto, playerState.rob)
    getPlayer(Basti, playerState.basti)
    getAllScores(Basti, playerState.basti)
    getAllScores(Roberto, playerState.rob)

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
        br()
        span(text &"Rank: {songs[i].rank}")
        br()
        br()

  proc renderAllSongs(): VNode =
    result = buildHtml(tdiv):
      tdiv(class = "split left"):
        #  span(text($playerState.rob))
        p:
          span(text "Roberto # scores:: ")
          span(text($playerState.rob.scores.len))
        p:
          renderSongs(playerState.rob, playerState.rob.scores)

      tdiv(class = "split right"):
        p:
          span(text "Basti # scores:: ")
          span(text($playerState.basti.scores.len))
        p:
          renderSongs(playerState.basti, playerState.basti.scores)

  proc findSong(songs: seq[Score], id: kstring): Score =
    ## returns the index of song corresponding to `id` in `songs`
    for i, s in songs:
      if s.id == id:
        return s

  proc renderCommonSongs(): VNode =
    # find all common songs
    let bastiSet = playerState.basti.scores.mapIt(it.id).toSet
    let robSet = playerState.rob.scores.mapIt(it.id).toSet
    let common = bastiSet * robSet
    let robSongs = playerState.rob.scores.filterIt(it.id in common)
    var bastiSongs: seq[Score]
    for r in robSongs:
      bastiSongs.add findSong(playerState.basti.scores, r.id)

    result = buildHtml(tdiv):
      tdiv(class = "split left"):
        p:
          span(text "Roberto # scores:: ")
          span(text($playerState.rob.scores.len))
        p:
          renderSongs(playerState.rob, robSongs)

      tdiv(class = "split right"):
cd         p:
          span(text "Basti # scores:: ")
          span(text($playerState.basti.scores.len))
        p:
          renderSongs(playerState.basti, bastiSongs)

  proc render(): VNode =
    result = buildHtml(tdiv):
      h1(text "ScoreSaberCompare")

      button(class = "press me", onclick = update):
        text "Update data from ScoreSaber.com"

      button(class = "press me", onclick = showAllSongs):
        text "Show all songs"

      button(class = "press me", onclick = showCommonSongs):
        text "Show common songs"

      case pageState.mode
      of mkAll: renderAllSongs()
      of mkCommon: renderCommonSongs()

      firstDrawDone = true

  setRenderer render, "ROOT", postRender

when isMainModule:
  main()

#var client = newHttpClient()
#discard client.getPlayer(Roberto)
#var xmlHttp = newXMLHTTPRequest()
#discard getPlayer(Roberto)
#discard getPlayer(Roberto)

when isMainModule:
  main()
