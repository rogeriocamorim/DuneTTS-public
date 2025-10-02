local Module = require("utils.Module")
local Helper = require("utils.Helper")
local I18N = require("utils.I18N")

local PlayBoard = Module.lazyRequire("PlayBoard")
local TurnControl = Module.lazyRequire("TurnControl")

-- Runtime URLs injected at upload time by build.py (secrets not committed)
-- Placeholders: replaced on --upload then reverted after
local PRIMARY_URL = "__PRIMARY_URL__"
local GOOGLE_DOC_URL = "__GOOGLE_DOC_URL__"


local SubmitGame = Helper.createClass(nil, {
    fields = {
        -- Confirmations before opening submit screen
        confirmations = {},
        requiredConfirmations = 2,

        -- Partially set on setup, then completed and sorted on each "openSubmitScreen".
        players = {},

        -- Set on setup from settings.
        numberOfPlayers = 0,
        hotseat = false,
        randomizePlayerPositions = false,
        legacy = false,
        useContracts = false,
        riseOfIx = false,
        epicMode = false,
        community = false,
        immortality = false,
        goTo11 = false,
        leaderSelection = nil,
        leaderPoolSize = 0,
        submitGameRankedGame = false,
        uprising = true,
        bloodlines = true,
        -- Internal flag to avoid double registering keep-alive listeners.
        listenerRegistered = false,
        -- Track panel desired states for rewind restoration.
        openPanels = {
            openSubmitScreenPanel = false,
            submitConfirmPanel = false,
            submitScreenPanel = false,
        },

        -- Set on setup.
        startTime = nil,
        token = nil,

        -- Set on submission.
        firstPlayerColor = nil,
        endTime = nil,
        turn = 0,
        gameSubmitted = false,
    }
})

function SubmitGame.onLoad(state)
    if state.SubmitGame then
        SubmitGame.fields = state.SubmitGame.fields
        if SubmitGame.fields.submitGameRankedGame then
            SubmitGame._staticSetUp()
        end
    end
end

function SubmitGame.onSave(state)
    state.SubmitGame = {
        fields = SubmitGame.fields
    }
end

function SubmitGame.setUp(settings)
    if settings.submitGameRankedGame then

        SubmitGame.fields.players = {}
        for _, color in ipairs(PlayBoard.getActivePlayBoardColors()) do
            local player = Helper.findPlayerByColor(color)
            table.insert(SubmitGame.fields.players, {
                steamId = player.steam_id,
                name = player.steam_name,
                color = player.color,
            })
        end
        assert(#SubmitGame.fields.players == 4)

        local fieldNames = {
            "numberOfPlayers",
            "hotseat",
            "randomizePlayerPositions",
            "useContracts",
            "legacy",
            "riseOfIx",
            "epicMode",
            "community",
            "immortality",
            "goTo11",
            "leaderSelection",
            "leaderPoolSize",
            "submitGameRankedGame",
        }

        for _, fieldName in ipairs(fieldNames) do
            SubmitGame.fields[fieldName] = settings[fieldName]
        end

        SubmitGame.fields.startTime = SubmitGame._currentTimestamp()

        SubmitGame._generateToken(SubmitGame.fields.players, function (token)
            SubmitGame.fields.token = token
            SubmitGame._staticSetUp(settings)
        end)

        SubmitGame.fields.confirmations = {}
        SubmitGame.fields.requiredConfirmations = 2
    end
end

function SubmitGame._staticSetUp(settings)
    if SubmitGame.fields.token then
        Global.setVar("openPreSubmitScreen", SubmitGame._openPreSubmitScreen)
        Global.setVar("confirmSubmit", SubmitGame._confirmSubmit)
        Global.setVar("submitGame", SubmitGame._submitGame)
        Global.setVar("closeSubmitConfirmPanel", SubmitGame._closeSubmitConfirmPanel)
        Global.setVar("closeSubmitGameScreen", SubmitGame._closeSubmitGameScreen)

    UI.setAttributes("openSubmitScreenPanel", { active = true })
    SubmitGame.fields.openPanels.openSubmitScreenPanel = true

        -- Register lightweight keep-alive listeners only once to re-activate the panel
        -- if a time rewind (undo) reverted its active attribute.
        if not SubmitGame.fields.listenerRegistered then
            local ensure = function()
                SubmitGame._ensureOpenSubmitPanel()
            end
            Helper.registerEventListener("phaseStart", ensure)
            Helper.registerEventListener("playerTurn", ensure)
            Helper.onceFramesPassed(60).doAfter(function() -- delayed periodic check (~1s)
                ensure()
            end)
            SubmitGame.fields.listenerRegistered = true
        end
    end
end

-- Reassert presence of the submit panel & global callbacks after rewinds.
function SubmitGame._ensureOpenSubmitPanel()
    if not SubmitGame.fields.token or not SubmitGame.fields.submitGameRankedGame then
        return
    end
    local p = SubmitGame.fields.openPanels
    local function ensure(id, desired)
        if desired and UI.getAttribute(id, "active") ~= "True" then
            UI.setAttributes(id, { active = true })
        end
    end
    ensure("openSubmitScreenPanel", p.openSubmitScreenPanel)
    ensure("submitConfirmPanel", p.submitConfirmPanel)
    ensure("submitScreenPanel", p.submitScreenPanel)
    if Global.getVar("openPreSubmitScreen") ~= SubmitGame._openPreSubmitScreen then
        Global.setVar("openPreSubmitScreen", SubmitGame._openPreSubmitScreen)
        Global.setVar("confirmSubmit", SubmitGame._confirmSubmit)
        Global.setVar("submitGame", SubmitGame._submitGame)
        Global.setVar("closeSubmitConfirmPanel", SubmitGame._closeSubmitConfirmPanel)
        Global.setVar("closeSubmitGameScreen", SubmitGame._closeSubmitGameScreen)
    end
end

function SubmitGame._openPreSubmitScreen()
    local confirmedList = {}
    local count = 0
    for color, name in pairs(SubmitGame.fields.confirmations) do
        table.insert(confirmedList, color .. " - " .. name)
        count = count + 1
    end

    local confirmedText = table.concat(confirmedList, "\n")

    UI.setAttribute("submitConfirmList", "text", I18N("confirmedPlayersTitle") .. "\n" .. confirmedText)
    UI.setAttribute("submitConfirmCount", "text", count .. " / " .. SubmitGame.fields.requiredConfirmations .. " confirmed")
    UI.setAttributes("submitConfirmPanel", { active = true })
    SubmitGame.fields.openPanels.submitConfirmPanel = true
end

function SubmitGame._confirmSubmit(player, value, id)
    local color = player.color
    local name = player.steam_name

    local count = 0
    for _ in pairs(SubmitGame.fields.confirmations) do count = count + 1 end
    if count >= SubmitGame.fields.requiredConfirmations then
        UI.setAttributes("submitConfirmPanel", { active = false })
        SubmitGame.fields.openPanels.submitConfirmPanel = false
        SubmitGame._openSubmitScreen()
        return
    end

    if SubmitGame.fields.confirmations[color] then
        broadcastToColor(I18N("confirmationAlreadyGiven"), color, "White")
        return
    end

    SubmitGame.fields.confirmations[color] = name

    local confirmedList = {}
    local count = 0
    for confirmedColor, confirmedName in pairs(SubmitGame.fields.confirmations) do
        table.insert(confirmedList, confirmedColor .. " - " .. confirmedName)
        count = count + 1
    end

    local remaining = SubmitGame.fields.requiredConfirmations - count
    local confirmedText = table.concat(confirmedList, "\n")

    -- Update UI panel
    UI.setAttribute("submitConfirmList", "text", I18N("confirmedPlayersTitle") .. "\n" .. confirmedText)
    UI.setAttribute("submitConfirmCount", "text", count .. " / " .. SubmitGame.fields.requiredConfirmations .. " confirmed")

    -- Update button label accordingly
    if count >= SubmitGame.fields.requiredConfirmations then
        UI.setAttribute("submitConfirmButton", "text", I18N("openSubmissionScreen"))
    else
        UI.setAttribute("submitConfirmButton", "text", I18N("confirmed"))
    end

    -- Feedback
    broadcastToColor(I18N("confirmationRecorded"), color, "White")

    -- Feedback to all players
    if remaining > 0 then
        broadcastToAll(string.format(I18N("confirmationRemaining"), name, color, remaining, remaining == 1 and "" or "s"), "White")
    end

    if count >= SubmitGame.fields.requiredConfirmations then
        broadcastToAll(string.format(I18N("confirmationUnlocked"), confirmedText), "White")
        UI.setAttributes("submitConfirmPanel", { active = false })
        SubmitGame.fields.openPanels.submitConfirmPanel = false
        SubmitGame._openSubmitScreen()
    end
end


function SubmitGame._closeSubmitConfirmPanel()
    UI.setAttributes("submitConfirmPanel", { active = false })
    SubmitGame.fields.openPanels.submitConfirmPanel = false
end

function SubmitGame._closeSubmitGameScreen()
    UI.setAttributes("submitScreenPanel", { active = false })
    SubmitGame.fields.openPanels.submitScreenPanel = false
end

function SubmitGame._openSubmitScreen()
    local playerWith10VP = false

    SubmitGame.fields.firstPlayerColor = TurnControl.getFirstPlayerOfTheGame()

    for _, player in ipairs(SubmitGame.fields.players) do
        local color = player.color

        player.score = PlayBoard.getPlayBoard(color):getScore()
        player.leader = PlayBoard.getLeaderName(color)
        player.spice = PlayBoard.getResource(color, "spice"):get()
        player.solari = PlayBoard.getResource(color, "solari"):get()
        player.water = PlayBoard.getResource(color, "water"):get()
        player.firstPlayer = nil

        playerWith10VP = playerWith10VP or player.score >= 10
    end

    SubmitGame._updateSubmitScreenPanel()

    UI.setAttributes("submitScreenPanel", { active = true })
    UI.setAttributes("submitGameConfirm", { key = "submitGame", interactable = playerWith10VP })
    SubmitGame.fields.openPanels.submitScreenPanel = true
end

function SubmitGame._updateSubmitScreenPanel()

    -- Sort players by score, spice, solari, and water.
    table.sort(SubmitGame.fields.players, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.spice ~= b.spice then return a.spice > b.spice end
        if a.solari ~= b.solari then return a.solari > b.solari end
        return a.water > b.water
    end)

    for i, player in ipairs(SubmitGame.fields.players) do
        player.placement = i

        local attributes = {
            name = player.name,
            leader_name = player.leader,
            victory_points = player.score,
            spice = player.spice,
            solaris = player.solari,
            water = player.water,
        }

        for attribute, value in pairs(attributes) do
            local placementCellIndex = "cell_placement_" .. i
            UI.setAttributes(placementCellIndex, { color = player.color })

            local placementIndex = "placement_" .. i .. "_" .. attribute
            UI.setAttribute(placementIndex, "text", value)

            local cellIndex = "cell_placement_" .. i .. "_" .. attribute
            UI.setAttributes(cellIndex, { color = player.color })
        end
    end
end

function SubmitGame._generateToken(players, tokenSetter)
    SubmitGame._makeWebRequest(PRIMARY_URL .. "/generation/v1/token", "POST", players, function (request)
        if request.is_error then
            Helper.dump("Failed to generate a token:", request.text)
            tokenSetter(0)
        else
            tokenSetter(request.text)
        end
    end)
end

function SubmitGame._submitGame()
    if SubmitGame.fields.gameSubmitted then
        broadcastToAll(I18N("gameAlreadySubmitted"), "Orange")
    else
        SubmitGame.firstPlayerColor = TurnControl.getFirstPlayerOfTheGame()
        SubmitGame.endTime = SubmitGame._currentTimestamp()
        SubmitGame.turn = TurnControl.getCurrentRound()

        SubmitGame._doSubmitGameStats()
        SubmitGame._doSubmitGame()

        UI.setAttributes("submitGameConfirm", {key = "gameSubmitted", interactable = false})
        SubmitGame.fields.gameSubmitted = true
    end
end

function SubmitGame._doSubmitGameStats()
    local fields = SubmitGame.fields
    local body = {
        ["entry.1366590140"] = fields.startTime,
        ["entry.1761818302"] = SubmitGame._currentTimestamp(),
        ["entry.754082197"] = fields.submitGameRankedGame,
        ["entry.1220354769"] = fields.community,
        ["entry.863659574"] = fields.turn,
        ["entry.971195728"] = fields.firstPlayerColor,

        ["entry.1210623"] = fields.players[1].name,
        ["entry.212984148"] = fields.players[1].color,
        ["entry.861602902"] = fields.players[1].leader,
        ["entry.652567690"] = fields.players[1].steamId,
        ["entry.1009208160"] = fields.players[1].score,

        ["entry.1767025989"] = fields.players[2].name,
        ["entry.1733905844"] = fields.players[2].color,
        ["entry.1430075466"] = fields.players[2].leader,
        ["entry.1445792508"] = fields.players[2].steamId,
        ["entry.835381715"] = fields.players[2].score,

        ["entry.852059461"] = fields.players[3].name,
        ["entry.1159019046"] = fields.players[3].color,
        ["entry.1977206887"] = fields.players[3].leader,
        ["entry.813977476"] = fields.players[3].steamId,
        ["entry.1577536866"] = fields.players[3].score,

        ["entry.1953565350"] = fields.players[4].name,
        ["entry.1319735869"] = fields.players[4].color,
        ["entry.910125184"] = fields.players[4].leader,
        ["entry.997583011"] = fields.players[4].steamId,
        ["entry.1265465838"] = fields.players[4].score,

        ["entry.845707618"] = fields.legacy,
        ["entry.2040351705"] = fields.riseOfIx,
        ["entry.744802168"] = fields.immortality,
        ["entry.419313208"] = fields.token,
        ["entry.2086786594"] = fields.epicMode,
        ["entry.530174472"] = fields.goTo11,
        ["entry.959235419"] = fields.leaderSelection,
        ["entry.886901664"] = fields.leaderPoolSize,
        ["entry.831709295"] = fields.numberOfPlayers,

        ["entry.854599203"] = fields.bloodlines,
    }

    local normalizedBody = {}
    for k, v in pairs(body) do
        normalizedBody[k] = type(v) == "string" and v or tostring(v)
    end

    WebRequest.post(GOOGLE_DOC_URL .. "/formResponse", normalizedBody, function (request)
        if request.is_error then
            Helper.dump("Failed to submit stats:", request.text)
        else
            broadcastToAll(I18N("gameSubmitted"), "Red")
        end
    end)
end

function SubmitGame._doSubmitGame()
    local fields = SubmitGame.fields
    local body = {
        token = fields.token,
        endTime = SubmitGame._currentTimestamp(),
        firstPlayerColor = fields.firstPlayerColor,
        community = fields.community,
        numberOfPlayers = fields.numberOfPlayers,
        useContracts = fields.useContracts,
        riseOfIx = fields.riseOfIx,
        epicMode = fields.epicMode,
        imperium = fields.legacy,
        immortality = fields.immortality,
        uprising = true,
        bloodLines = true,
        goTo11 = fields.goTo11,
        leaderSelection = fields.leaderSelection,
        leaderPoolSize = fields.leaderPoolSize,
        rankedGame = fields.submitGameRankedGame,
        playerData = fields.players,
        startTime = fields.startTime,
        endTime = fields.endTime,
        turn = fields.turn,
    }

    SubmitGame._makeWebRequest(PRIMARY_URL .. "/api/games/submit", "POST", body, function (request)
        if request.is_error then
            Helper.dump("Failed to submit game:", request.text)
        else
            broadcastToAll(request.text, "White")
        end
    end)
end

function SubmitGame._makeWebRequest(url, method, body, callback)
    local headers = {
        ["Content-Type"] = "application/json",
        Accept = "application/json"
    }

    local jsonString = JSON.encode(body)

    WebRequest.custom(url, method, true, jsonString, headers, callback)
end

function SubmitGame._currentTimestamp()
    -- Weird: osdateparam != string|osdate...
    return os.date("!%m/%d/%Y %H:%M:%S", os.time(os.date("!*t")))
end

return SubmitGame
