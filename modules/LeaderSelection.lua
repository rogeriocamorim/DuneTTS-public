local Module = require("utils.Module")
local Helper = require("utils.Helper")
local I18N = require("utils.I18N")
local Dialog = require("utils.Dialog")

local Deck = Module.lazyRequire("Deck")
local TurnControl = Module.lazyRequire("TurnControl")
local PlayBoard = Module.lazyRequire("PlayBoard")
local Hagal = Module.lazyRequire("Hagal")
local MainBoard = Module.lazyRequire("MainBoard")
local Board = Module.lazyRequire("Board")

local LeaderSelection = {
    dynamicLeaderSelection = {},
    leaderSelectionPoolSize = 8,
    turnSequence = {},
    -- Track players who have the Ornithopter Fleet tech
    ornithopterFleetPlayers = {},
    -- Target number of leaders to end up with in Community Mode (both mode1 & mode2).
    communityModeTargetLeaderCount = 7,
    -- Hard-coded tweakable knob for Community Mode (Mode 1 extra picks from B∪C). Mode 2 no longer uses fixed removals.
    communityModeMode1AdditionalPicks = 2,  -- Number of random (B∪C) leaders added to Tier A in Mode 1
}

local Stage = {
    INITIALIZED = 1,
    STARTED = 2,
    DONE = 3,
}

---
function LeaderSelection.getSelectionMethods(numberOfPlayers)
    local selectionMode = {
        random = "random",
        reversePick = "reversePick",
        reverseHiddenPick = "reverseHiddenPick",
    }
    if numberOfPlayers == 4 then
        selectionMode.altHiddenPick = "altHiddenPick"
    end
    return selectionMode
end

---
function LeaderSelection.onLoad(state)
    Helper.append(LeaderSelection, Helper.resolveGUIDs(false, {
        deckZone = "23f2b5",
        secondaryTable = "662ced",
    }))

    if state.settings then
        -- Restore ornithopter fleet tracking
        if state.LeaderSelection.ornithopterFleetPlayers then
            LeaderSelection.ornithopterFleetPlayers = state.LeaderSelection.ornithopterFleetPlayers
        end
        
        LeaderSelection._transientSetUp(
            state.settings,
            state.LeaderSelection.leaderSelectionPoolSize,
            state.LeaderSelection.players,
            state.LeaderSelection.stage)
    end
end

---
function LeaderSelection.onSave(state)
    state.LeaderSelection = {
        leaderSelectionPoolSize = LeaderSelection.leaderSelectionPoolSize,
        players = LeaderSelection.players,
        stage = LeaderSelection.stage,
        ornithopterFleetPlayers = LeaderSelection.ornithopterFleetPlayers,
    }
end

---
function LeaderSelection.setUp(settings, activeOpponents)
    LeaderSelection.leaderSelectionPoolSize = settings.leaderPoolSize

    local preContinuation = Helper.createContinuation("LeaderSelection.setUp.preContinuation")
    if settings.numberOfPlayers > 2 then
        preContinuation.run()
    else
        Deck.generateRivalLeaderDeck(
            LeaderSelection.deckZone,
            settings.streamlinedRivals,
            settings.riseOfIx,
            settings.immortality,
            settings.legacy,
            settings.community
        ).doAfter(function (deck)
            LeaderSelection._layoutLeaderDeck(deck, 0).doAfter(preContinuation.run)
        end)
    end

    local postContinuation = Helper.createContinuation("LeaderSelection.setUp.postContinuation")

    local free = settings.tweakLeaderSelection and not settings.community

    preContinuation.doAfter(function ()
        -- Temporary tag to avoid counting the rival leader cards.
        LeaderSelection.deckZone.addTag("Leader")
        Deck.generateLeaderDeck(
            LeaderSelection.deckZone,
            settings.useContracts,
            settings.riseOfIx,
            settings.immortality,
            settings.legacy,
            settings.community,
            free
        ).doAfter(function (deck)
            LeaderSelection.deckZone.removeTag("Leader")

            local start = settings.numberOfPlayers > 2 and 0 or 12
            LeaderSelection._layoutLeaderDeck(deck, start).doAfter(function ()
                local testSetUp = type(settings.leaderSelection) == "table"

                if settings.community then
                    local leaders = LeaderSelection._grabLeaders()

                    -- Community mode filtering logic:
                    --   Target final leader count = LeaderSelection.communityModeTargetLeaderCount (default 7).
                    --   Mode 1: Keep all Tier A + 2 random from (Tier B ∪ Tier C), then remove randomly until only target remain.
                    --   Mode 2: Keep all of (Tier B ∪ Tier C), then remove randomly until only target remain.
                    --   (Legacy fixed removal counts removed; we now trim dynamically to target.)
                    local tier_A = {
                        "stabanTuek", "bl_Esmar", "bl_Hasimir", "bl_Kota", "glossuRabban", "tessiaVernius",
                    }
                    local tier_B = {
                        "amberMetulli", "gurneyHalleck", "irulanCorrino", "bl_Liet", "bl_Piter", "vladimirHarkonnen",
                        "yunaMoritani", "letoAtreides", "armandEcaz",
                    }
                    local tier_C = {
                        "margotFenring", "jessica", "feydRauthaHarkonnen", "shaddamCorrino", "muadDib", "bl_Chani",
                        "bl_Duncan", "bl_Mohiam", "bl_Yrkoon",
                    }

                    local function concat(a, b)
                        local r = { table.unpack(a) }
                        for _, v in ipairs(b) do table.insert(r, v) end
                        return r
                    end

                    local function shuffle(list)
                        for i = #list, 2, -1 do
                            local j = math.random(i)
                            list[i], list[j] = list[j], list[i]
                        end
                    end

                    local mode
                    if settings.communityLeaderMode == "mode1" then
                        mode = 1
                    elseif settings.communityLeaderMode == "mode2" then
                        mode = 2
                    else
                        mode = math.random(1, 2)
                    end
                    local keep = {}

                    local target = LeaderSelection.communityModeTargetLeaderCount or 7
                    if mode == 1 then
                        -- Mode 1: Tier A + N random (B∪C) then trim down to target.
                        for _, id in ipairs(tier_A) do keep[id] = true end
                        local combined = concat(tier_B, tier_C)
                        shuffle(combined)
                        local additionalPicks = LeaderSelection.communityModeMode1AdditionalPicks or 2
                        for i = 1, math.min(additionalPicks, #combined) do
                            keep[combined[i]] = true
                        end
                        -- Trim to target.
                        local current = {}
                        for id,_ in pairs(keep) do table.insert(current, id) end
                        shuffle(current)
                        local excess = math.max(0, #current - target)
                        for i = 1, excess do
                            keep[current[i]] = nil
                        end
                        broadcastToAll(I18N("communityMode1"), {1,1,1})
                    else
                        -- Mode 2: All (B∪C) then trim to target.
                        local combined = concat(tier_B, tier_C)
                        for _, id in ipairs(combined) do keep[id] = true end
                        shuffle(combined)
                        local excess = math.max(0, #combined - target)
                        for i = 1, excess do
                            keep[combined[i]] = nil
                        end
                        broadcastToAll(I18N("communityMode2"), {1,1,1})
                    end

                    -- Destruct leaders not kept
                    for id, leader in pairs(leaders) do
                        if not keep[id] then
                            LeaderSelection._destructLeader(leader)
                        end
                    end
                end

                -- The commander's leaders are always the same. It is not enforced
                -- in a test set up, but it won't work with different leaders.
                if settings.numberOfPlayers == 6 and not testSetUp then
                    local leaders = LeaderSelection._grabLeaders()

                    PlayBoard.setLeader("White", leaders["muadDib"])
                    PlayBoard.setLeader("Purple", leaders["shaddamCorrino"])
                end

                -- Give minimal time to the 2 leaders above to exit the zone.
                Helper.onceFramesPassed(1).doAfter(function ()
                    local players = TurnControl.toCanonicallyOrderedPlayerList(activeOpponents)
                    LeaderSelection._transientSetUp(settings, settings.leaderPoolSize, players, Stage.INITIALIZED)
                end)

                postContinuation.run()
            end)
        end)
    end)

    return postContinuation
end

---
function LeaderSelection._layoutLeaderDeck(deck, start)
    local continuation = Helper.createContinuation("LeaderSelection._layoutLeaderDeck")
    local numberOfLeaders = deck.getQuantity()
    local count = numberOfLeaders

    LeaderSelection._layoutLeaders(start, numberOfLeaders, function (_, position)
        deck.takeObject({
            position = position,
            flip = true,
            callback_function = function (card)
                if card.hasTag("Unselected") then
                    card.flip()
                end
                count = count - 1
                if count == 0 then
                    Helper.onceTimeElapsed(1).doAfter(continuation.run)
                end
            end
        })
    end)

    return continuation
end

---
function LeaderSelection._transientSetUp(settings, leaderSelectionPoolSize, players, stage)
    LeaderSelection.leaderSelectionPoolSize = leaderSelectionPoolSize
    LeaderSelection.players = players
    LeaderSelection.stage = stage

    if LeaderSelection.stage == Stage.DONE then
        return
    end

    -- Do it *before* calling _setUpXxx which could trigger an immediate
    -- TurnControl.start and a subsequent "leaderSelection" phase event.
    Helper.registerEventListener("phaseStart", function (phase, firstPlayer)
        if phase == "leaderSelection" then
            local turnSequence = Helper.shallowCopy(players)
            while turnSequence[1] ~= firstPlayer do
                Helper.cycle(turnSequence)
            end

            if settings.leaderSelection == "reversePick" then
                Helper.reverse(turnSequence)
            elseif settings.leaderSelection == "reverseHiddenPick" then
                Helper.reverse(turnSequence)
            elseif settings.leaderSelection == "altHiddenPick" then
                Helper.reverse(turnSequence)
                if #turnSequence == 4 then
                    Helper.swap(turnSequence, 4, 3)
                else
                    Helper.dump("Skipping 4 <-> 3 for less than 4 players.")
                end
            end

            TurnControl.overridePhaseTurnSequence(turnSequence)
        end
    end)

    local autoStart = not settings.tweakLeaderSelection
    local testSetUp = type(settings.leaderSelection) == "table"

    if testSetUp then
        LeaderSelection._setUpTest(players, settings.leaderSelection)
    elseif settings.leaderSelection == "random" then
        LeaderSelection._setUpPicking(autoStart, true, false)
    elseif settings.leaderSelection == "reversePick" then
        LeaderSelection._setUpPicking(autoStart, false, false)
    elseif settings.leaderSelection == "reverseHiddenPick" then
        LeaderSelection._setUpPicking(autoStart, false, true)
    elseif settings.leaderSelection == "altHiddenPick" then
        LeaderSelection._setUpPicking(autoStart, false, true)
    else
        error(settings.leaderSelection)
    end
end

---
function LeaderSelection._layoutLeaders(start, count, callback)
    local h = LeaderSelection.deckZone.getScale().z
    local colCount = 6
    local origin = LeaderSelection.deckZone.getPosition() - Vector((colCount / 2 - 0.5) * 5, 0, h / 2 - 10)
    for i = start, start + count - 1 do
        local x = (i % colCount) * 5
        local y = math.floor(i / colCount) * 4
        callback(i + 1, origin + Vector(x, 1, y))
    end
end

--- Return all the leaders laid out on the secondary table.
function LeaderSelection._grabLeaders(rival)
    local leaders = {}
    for _, object in ipairs(LeaderSelection.deckZone.getObjects()) do
        if (not rival and object.hasTag("Leader")) or (rival and object.hasTag("RivalLeader")) then
            leaders[Helper.getID(object)] = object
        end
    end
    return leaders
end

---
function LeaderSelection._setUpTest(players, leaderNames)
    local leaders = LeaderSelection._grabLeaders(false)
    local rivals = LeaderSelection._grabLeaders(true)

    for _, color in pairs(players) do
        assert(leaderNames[color], "No leader for color " .. color)
        assert(#LeaderSelection.deckZone.getObjects(), "No leader to select")
        local leader
        if PlayBoard.isRival(color) then
            local leaderName = leaderNames[color]
            leader = rivals[leaderName]
            assert(leader, "Unknown rival leader " .. tostring(leaderName))
        else
            local leaderName = leaderNames[color]
            leader = leaders[leaderName]
            assert(leader, "Unknown leader " .. tostring(leaderName))
        end
        PlayBoard.setLeader(color, leader)
    end

    LeaderSelection.stage = Stage.DONE
    TurnControl.start()
end

---
function LeaderSelection._setUpPicking(autoStart, random, hidden)
    local fontColor = Color(223/255, 151/255, 48/255)

    if LeaderSelection.stage == Stage.INITIALIZED then
        if not random then
            Helper.createAbsoluteButtonWithRoundness(LeaderSelection.secondaryTable, 2, {
                click_function = Helper.registerGlobalCallback(),
                label = I18N("leaderSelectionAdjust"),
                position = LeaderSelection.secondaryTable.getPosition() + Vector(0, 1.8, -28),
                width = 0,
                height = 0,
                font_size = 250,
                font_color = fontColor
            })

            local adjustValue = function (value)
                local numberOfLeaders = #Helper.getKeys(LeaderSelection._grabLeaders())
                local minValue = #LeaderSelection.players
                local maxValue = numberOfLeaders
                LeaderSelection.leaderSelectionPoolSize = math.max(minValue, math.min(maxValue, value))
                LeaderSelection.secondaryTable.editButton({ index = 2, label = tostring(LeaderSelection.leaderSelectionPoolSize) })
            end

            Helper.createAbsoluteButtonWithRoundness(LeaderSelection.secondaryTable, 2, {
                click_function = Helper.registerGlobalCallback(function ()
                    adjustValue(LeaderSelection.leaderSelectionPoolSize - 1)
                end),
                label = "-",
                position = LeaderSelection.secondaryTable.getPosition() + Vector(-1, 1.8, -29),
                width = 400,
                height = 400,
                font_size = 600,
                color = fontColor,
                font_color = { 0, 0, 0, 1 }
            })

            Helper.createAbsoluteButtonWithRoundness(LeaderSelection.secondaryTable, 1, {
                click_function = Helper.registerGlobalCallback(),
                label = tostring(LeaderSelection.leaderSelectionPoolSize),
                position = LeaderSelection.secondaryTable.getPosition() + Vector(0, 1.8, -29),
                width = 0,
                height = 0,
                font_size = 400,
                font_color = fontColor
            })

            Helper.createAbsoluteButtonWithRoundness(LeaderSelection.secondaryTable, 2, {
                click_function = Helper.registerGlobalCallback(function ()
                    adjustValue(LeaderSelection.leaderSelectionPoolSize + 1)
                end),
                label = "+",
                position = LeaderSelection.secondaryTable.getPosition() + Vector(1, 1.8, -29),
                width = 400,
                height = 400,
                font_size = 600,
                color = fontColor,
                font_color = { 0, 0, 0, 1 }
            })
        end

        Helper.createAbsoluteButtonWithRoundness(LeaderSelection.secondaryTable, 2, {
            click_function = Helper.registerGlobalCallback(),
            label = I18N("leaderSelectionExclude"),
            position = LeaderSelection.secondaryTable.getPosition() + Vector(0, 1.8, -30),
            width = 0,
            height = 0,
            font_size = 250,
            font_color = fontColor
        })

        local start = function ()
            local availableLeaderCount = #LeaderSelection._getVisibleLeaders()
            local requiredLeaderCount = #LeaderSelection.players
            -- In 6P mode, 2 players are automatically assigned.
            if availableLeaderCount >= math.min(4, requiredLeaderCount) then
                local visibleLeaders = LeaderSelection._prepareVisibleLeaders(hidden)
                LeaderSelection._createDynamicLeaderSelection(visibleLeaders)
                Helper.clearButtons(LeaderSelection.secondaryTable)
                LeaderSelection.stage = Stage.STARTED
                TurnControl.start()
            else
                broadcastToAll(I18N("notEnoughLeaderLeft"), "Red")
            end
        end

        if autoStart then
            start()
        else
            Helper.createAbsoluteButtonWithRoundness(LeaderSelection.secondaryTable, 2, {
                click_function = Helper.registerGlobalCallback(start),
                label = I18N("start"),
                position = LeaderSelection.secondaryTable.getPosition() + Vector(0, 1.8, -32),
                width = 2200,
                height = 600,
                font_size = 500,
                color = fontColor,
                font_color = { 0, 0, 0, 1 }
            })
        end
    elseif LeaderSelection.stage == Stage.STARTED then
        local visibleLeaders = LeaderSelection._getVisibleLeaders()
        LeaderSelection._createDynamicLeaderSelection(visibleLeaders)
        Helper.clearButtons(LeaderSelection.secondaryTable)

        Helper.onceFramesPassed(1).doAfter(function ()
            for i, color in ipairs(LeaderSelection.players) do
                local leaderCard = PlayBoard.findLeaderCard(color)
                if leaderCard then
                    LeaderSelection._setOnlyVisibleFrom(leaderCard, color)
                end
            end
        end)
    else
        error("Unexpected stage: " .. tostring(LeaderSelection.stage))
    end

    if random then
        local selectedLeaders = {}
        Helper.registerEventListener("playerTurn", function (phase, color)
            if phase == 'leaderSelection' then
                local leader = LeaderSelection._pickAnyLeader(color, PlayBoard.isRival(color), selectedLeaders)
                selectedLeaders[Helper.getID(leader)] = true
            end
        end)
    end

    if hidden then
        Helper.registerEventListener("playerTurn", function (phase, color)
            if phase == 'leaderSelection' then
                local remainingLeaders = {}
                for leader, selected in pairs(LeaderSelection.dynamicLeaderSelection) do
                    if not selected then
                        LeaderSelection._setOnlyVisibleFrom(leader, color)
                        table.insert(remainingLeaders, leader)
                    end
                end
                Helper.shuffle(remainingLeaders)
                LeaderSelection._layoutLeaders(0, #remainingLeaders, function (i, position)
                    remainingLeaders[i].setPosition(position)
                end)
            end
        end)
    end

    Helper.registerEventListener("phaseEnd", function (phase)
        if phase == 'leaderSelection' then
            for leader, selected in pairs(LeaderSelection.dynamicLeaderSelection) do
                if selected then
                    leader.setInvisibleTo({})
                else
                    LeaderSelection._destructLeader(leader)
                end
            end
            LeaderSelection.stage = Stage.DONE
        end

        if phase == 'gameStart' then
            for _, object in ipairs(LeaderSelection.deckZone.getObjects()) do
                object.destruct()
            end

            -- bloodlines tuek's sietch destruct
            if PlayBoard.getLeader("Red").name ~= "bl_Esmar" and PlayBoard.getLeader("Green").name ~= "bl_Esmar" and PlayBoard.getLeader("Yellow").name ~= "bl_Esmar" and PlayBoard.getLeader("Blue").name ~= "bl_Esmar" then
                MainBoard.bl_EsmarBoard.destruct()
                local position = MainBoard.spiceBonusTokens.tueksSietch.getPosition()
                MainBoard.spiceBonusTokens.tueksSietch.setPosition(position + Vector(0, -2, 0))
                
                -- Delay the cleanup to run after MainBoard has finished creating buttons
                Wait.time(function()
                    LeaderSelection.cleanupTueksSietchButtons()
                end, 2) -- Wait 2 seconds for all initialization to complete
            end
        end
    end)
end

-- bloodlines cleanup tuek's sietch buttons when no Esmar leader selected
function LeaderSelection.cleanupTueksSietchButtons()
    -- Remove the snap points that create the visible buttons
    local mainBoard = getObjectFromGUID("483a1a")
    if mainBoard then
        LeaderSelection.removeSnapPointsWithTagFromObject(mainBoard, "spaceTueksSietch_Draw")
        LeaderSelection.removeSnapPointsWithTagFromObject(mainBoard, "spaceTueksSietch_Spice")
    end
    
    -- Clean up any registered spaces and their UI elements
    local spacesToRemove = {"tueksSietch", "spaceTueksSietch_Spice", "spaceTueksSietch_Draw"}
    for _, spaceName in ipairs(spacesToRemove) do
        local space = MainBoard.spaces[spaceName]
        if space then
            if space.zone then
                Helper.clearButtons(space.zone)
                space.zone.destruct()
            end
            if space.park then
                space.park = nil
            end
            MainBoard.spaces[spaceName] = nil
        end
    end
    
    -- Destroy any AgentPark objects that have ONLY the Tuek's Sietch option buttons.
    -- We build the exact localized tooltips to compare instead of using generic substrings
    -- so we don't accidentally match other spaces (e.g. Spice Refinery '4 solari for 1 spice unit').
    local tuekTooltips = {
        -- Main space (base Tuek's Sietch placement)
        I18N("sendAgentTo", { space = I18N("tueksSietch") }):lower(),
        -- Sub-option spaces created for the dialog choices (spice / draw)
        I18N("sendAgentTo", { space = I18N("tueksSietch_Spice") }):lower(),
        I18N("sendAgentTo", { space = I18N("tueksSietch_Draw") }):lower(),
    }
    
    for _, object in ipairs(Global.getObjects()) do
        if Helper._isTransient(object) and object.getName() == "AgentPark" then
            local buttons = object.getButtons() or {}
            local shouldDestroy = false
            
            for _, button in ipairs(buttons) do
                if button.tooltip then
                    local tooltipLower = button.tooltip:lower()
                    for _, exact in ipairs(tuekTooltips) do
                        if tooltipLower == exact then
                            shouldDestroy = true
                            break
                        end
                    end
                    if shouldDestroy then break end
                end
            end
            
            if shouldDestroy then
                Helper.clearButtons(object)
                object.destruct()
            end
        end
    end
end

-- bloodlines remove tuek's sietch tag from mainboard
function LeaderSelection.removeSnapPointsWithTagFromObject(obj, tag)
    local snapPoints = obj.getSnapPoints() or {}
    local newSnapPoints = {}
    
    for _,snapPoint in ipairs(snapPoints) do
        local allow = true
        for _,snapPointTag in ipairs(snapPoint.tags or {}) do
            if tag == snapPointTag then
                allow = false 
                break
            end
        end
        if allow then table.insert(newSnapPoints, snapPoint) end
    end
    
    obj.setSnapPoints(newSnapPoints)
end

-- Ornithopter Fleet tech effect implementation
function LeaderSelection.activateOrnithopterFleet(color)
    -- Mark this player as having the Ornithopter Fleet tech
    LeaderSelection.ornithopterFleetPlayers[color] = true
    
    -- Convert all existing battle tokens to ornithopter tokens
    LeaderSelection.convertExistingBattleTokensToOrnithopter(color)
end

function LeaderSelection.convertExistingBattleTokensToOrnithopter(color)
    local playBoard = PlayBoard.playBoards[color]
    if not playBoard or not playBoard.content or not playBoard.content.board then
        return -- Player board not found
    end
    
    local objectiveTokenTags = {
        "MuadDibObjectiveToken",
        "CrysknifeObjectiveToken", 
        "JokerObjectiveToken"
    }
    
    local board = playBoard.content.board
    local converted = 0
    
    -- Use the same method as the existing conversion code - check snap points and nearby objects
    for _, snapPoint in ipairs(board.getSnapPoints()) do
        for _, tag in ipairs(objectiveTokenTags) do
            if Helper.isElementOf(tag, snapPoint.tags) then
                local absoluteSnapPointPosition = board.positionToWorld(snapPoint.position)
                
                -- Find objects near this snap point
                local radius = 0.5
                local hits = Physics.cast({
                    origin = absoluteSnapPointPosition,
                    direction = Vector(0, 1, 0),
                    type = 2,
                    size = Vector(radius, radius, radius),
                    max_distance = 2,
                })
                
                for _, hit in ipairs(hits) do
                    local object = hit.hit_object
                    if object and object.hasTag(tag) then
                        object.destruct()
                        converted = converted + 1
                    end
                end
                break
            end
        end
    end
    
    -- Now spawn the exact number of ornithopter tokens that were destroyed
    if converted > 0 then
        local ornithopterBag = getObjectFromGUID("f5c927")
        if ornithopterBag then
            -- Find all ornithopter snap points
            local ornithopterSnapPoints = {}
            for _, snapPoint in ipairs(board.getSnapPoints()) do
                if Helper.isElementOf("OrnithopterObjectiveToken", snapPoint.tags) then
                    table.insert(ornithopterSnapPoints, board.positionToWorld(snapPoint.position))
                end
            end
            
            -- Spawn the exact number of tokens that were destroyed
            for i = 1, converted do
                local snapPointIndex = ((i - 1) % #ornithopterSnapPoints) + 1
                local spawnPosition = ornithopterSnapPoints[snapPointIndex]
                
                -- Stack tokens if we have more than snap points
                local stackHeight = math.floor((i - 1) / #ornithopterSnapPoints) * 0.3
                
                ornithopterBag.takeObject({
                    position = spawnPosition + Vector(0, 1 + stackHeight, 0),
                    rotation = Vector(0, 180, 0),
                    smooth = true,
                })
            end
        end
    end
end

function LeaderSelection.hasOrnithopterFleet(color)
    return LeaderSelection.ornithopterFleetPlayers[color] == true
end

function LeaderSelection._setOnlyVisibleFrom(object, color)
    local excludedColors = {}
    for _, otherColor in ipairs(TurnControl.getPlayers()) do
        if otherColor ~= color then
            table.insert(excludedColors, otherColor)
        end
    end
    object.setInvisibleTo(excludedColors)
end

function LeaderSelection._getVisibleLeaders()
    local leaders = {}
    for _, object in ipairs(LeaderSelection.deckZone.getObjects()) do
        if object.hasTag("Leader") or object.hasTag("RivalLeader") then
            if not object.is_face_down then
                table.insert(leaders, object)
            end
        end
    end
    return leaders
end

function LeaderSelection._prepareVisibleLeaders(hidden)
    local leaders = {}
    for _, object in ipairs(LeaderSelection.deckZone.getObjects()) do
        if object.hasTag("Leader") or object.hasTag("RivalLeader") then
            if object.is_face_down then
                LeaderSelection._destructLeader(object)
            else
                table.insert(leaders, object)
                if hidden then
                    object.setInvisibleTo(TurnControl.getPlayers())
                end
            end
        end
    end
    return leaders
end

function LeaderSelection._createDynamicLeaderSelection(leaders)
    Helper.shuffle(leaders)

    local notRivalLeaderCount = 0
    for i, leader in ipairs(leaders) do
        local ok = true
        if not leader.hasTag("RivalLeader") then
            notRivalLeaderCount = notRivalLeaderCount + 1
            ok = notRivalLeaderCount <= LeaderSelection.leaderSelectionPoolSize
        end
        if ok then
            LeaderSelection.dynamicLeaderSelection[leader] = false
            local position = leader.getPosition()
            Helper.createAbsoluteButtonWithRoundness(leader, 1, {
                click_function = Helper.registerGlobalCallback(function (_, color, _)
                    if color == TurnControl.getCurrentPlayer() then
                        LeaderSelection.claimLeader(color, leader)
                    end
                end),
                position = Vector(position.x, 1.9, position.z),
                width = 600,
                height = 900,
                color = Helper.AREA_BUTTON_COLOR,
                hover_color = { 0.7, 0.7, 0.7, 0.7 },
                press_color = { 0.5, 1, 0.5, 0.4 },
                font_color = { 1, 1, 1, 100 },
                tooltip = I18N("claimLeader", { leader = I18N(Helper.getID(leader)) })
            })
        else
            LeaderSelection._destructLeader(leader)
        end
    end
end

---
function LeaderSelection.getSelectableLeaders(rivalLeader)
    local selectableLeaders = {}
    for leader, selected in pairs(LeaderSelection.dynamicLeaderSelection) do
        if not selected then
            if (rivalLeader and leader.hasTag("RivalLeader")) or (not rivalLeader and leader.hasTag("Leader")) then
                table.insert(selectableLeaders, leader)
            end
        end
    end
    return selectableLeaders
end

---
function LeaderSelection._pickAnyLeader(color, rivalLeader, excludedLeaders)
    local allLeaders = LeaderSelection.getSelectableLeaders(rivalLeader)
    local leaders = Helper.filter(allLeaders, function (leader)
        return not excludedLeaders[Helper.getID(leader)]
    end)
    if #leaders == 0 then
        leaders = allLeaders
    end
    assert(#leaders > 0, "No leaders left!")
    local leader = Helper.pickAny(leaders)
    LeaderSelection.claimLeader(color, leader)
    return leader
end

---
function LeaderSelection.claimLeader(color, leader)
    -- Avoid double-claim if something already marked this leader selected
    if LeaderSelection.dynamicLeaderSelection[leader] == true then
        return
    end

    if PlayBoard.isRival(color) and not leader.hasTag("RivalLeader") then
        Dialog.broadcastToColor(I18N("incompatibleRivalLeader"), color, "Purple")
        return
    end

    if not PlayBoard.isRival(color) and not leader.hasTag("Leader") then
        Dialog.broadcastToColor(I18N("incompatibleLeader"), color, "Purple")
        return
    end

    Helper.clearButtons(leader)
    LeaderSelection.dynamicLeaderSelection[leader] = true
    PlayBoard.setLeader(color, leader).doAfter(TurnControl.endOfTurn)
end

---
function LeaderSelection._destructLeader(leader)
    leader.destruct()
end

return LeaderSelection
