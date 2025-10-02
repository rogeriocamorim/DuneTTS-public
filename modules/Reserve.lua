local Module = require("utils.Module")
local Helper = require("utils.Helper")
local AcquireCard = require("utils.AcquireCard")
local Dialog = require("utils.Dialog")
local I18N = require("utils.I18N")

local Deck = Module.lazyRequire("Deck")
local PlayBoard = Module.lazyRequire("PlayBoard")
local ImperiumCard = Module.lazyRequire("ImperiumCard")

local Reserve = {}

---
function Reserve.onLoad(state)
    Helper.append(Reserve, Helper.resolveGUIDs(false, {
        foldspaceSlotZone = "6b62e0",
        prepareTheWaySlotZone = "cbcd9a",
        theSpiceMustFlowSlotZone = "c087d2"
    }))

    if state.settings then
        Reserve._transientSetUp()
    end
end

---
function Reserve.setUp()
    -- TODO Detect Ilesa Ecaz?
    if false then
        Deck.generateSpecialDeck(Reserve.foldspaceSlotZone, "base", "foldspace")
    else
        Reserve.foldspaceSlotZone.destruct()
    end
    Deck.generateSpecialDeck(Reserve.prepareTheWaySlotZone, "uprising", "prepareTheWay")
    Deck.generateSpecialDeck(Reserve.theSpiceMustFlowSlotZone, "uprising", "theSpiceMustFlow")
    Reserve._transientSetUp()
end

---
function Reserve._transientSetUp()
    -- TODO Detect Ilesa Ecaz?
    if false then
        Reserve.foldspace = AcquireCard.new(Reserve.foldspaceSlotZone, "Imperium", PlayBoard.withLeader(function (_, color)
            local leader = PlayBoard.getLeader(color)
            leader.acquireFoldspace(color)
        end), Deck.getAcquireCardDecalUrl("generic"))
    end
    Reserve.prepareTheWay = AcquireCard.new(Reserve.prepareTheWaySlotZone, "Imperium", PlayBoard.withLeader(function (_, color)
        local leader = PlayBoard.getLeader(color)
        leader.acquirePrepareTheWay(color)
    end), Deck.getAcquireCardDecalUrl("generic"))
    Reserve.theSpiceMustFlow = AcquireCard.new(Reserve.theSpiceMustFlowSlotZone, "Imperium", PlayBoard.withLeader(function (_, color)
        local leader = PlayBoard.getLeader(color)
        leader.acquireTheSpiceMustFlow(color)
    end), Deck.getAcquireCardDecalUrl("generic"))
end

---
function Reserve.acquireFoldspace(color)
    if Reserve.foldspace then
        PlayBoard.giveCardFromZone(color, Reserve.foldspace.zone, false)
        return true
    else
        return false
    end
end

---
function Reserve.acquirePrepareTheWay(color)
    -- Get card info directly from ImperiumCard data since card might not be in zone yet
    local cardInfo = ImperiumCard.prepareTheWay
    local cardCost = cardInfo.cost or 0
    local playerPersuasion = PlayBoard.getResource(color, "persuasion"):get()
    
    if playerPersuasion >= cardCost then
        -- Player has enough persuasion, acquire normally
        PlayBoard.giveCardFromZone(color, Reserve.prepareTheWay.zone, false)
        return true
    else
        -- Player doesn't have enough persuasion, show confirmation dialog
        local cardName = "prepareTheWay"
        printToAll(I18N("persuasionShortageNotice", { 
            player = Player[color].steam_name, 
            card = I18N(cardName),
            cost = cardCost, 
            persuasion = playerPersuasion 
        }), color)
        
        Dialog.showYesOrNoDialog(color, I18N("confirmAcquireWithoutPersuasion", {
            card = I18N(cardName),
            cost = cardCost,
            persuasion = playerPersuasion
        }), Helper.createContinuation("Reserve.acquirePrepareTheWay"), function(confirmed)
            if confirmed then
                printToAll(I18N("playerAcquiredWithoutPersuasion", {
                    player = Player[color].steam_name,
                    card = I18N(cardName)
                }), color)
                PlayBoard.giveCardFromZone(color, Reserve.prepareTheWay.zone, false)
            else
                printToAll(I18N("playerDeclinedAcquisition", {
                    player = Player[color].steam_name,
                    card = I18N(cardName)
                }), color)
            end
        end)
        return true -- Return true to indicate the dialog was shown
    end
end

---
function Reserve.acquireTheSpiceMustFlow(color, toItsHand)
    -- Get card info directly from ImperiumCard data since card might not be in zone yet
    local cardInfo = ImperiumCard.theSpiceMustFlow
    local cardCost = cardInfo.cost or 0
    local playerPersuasion = PlayBoard.getResource(color, "persuasion"):get()
    
    if playerPersuasion >= cardCost then
        -- Player has enough persuasion, acquire normally
        if toItsHand then
            local position = Player[color].getHandTransform().position
            Helper.moveCardFromZone(Reserve.theSpiceMustFlow.zone, position, nil, false, true)
        else
            PlayBoard.giveCardFromZone(color, Reserve.theSpiceMustFlow.zone, false, toItsHand)
        end
        return true
    else
        -- Player doesn't have enough persuasion, show confirmation dialog
        local cardName = "theSpiceMustFlow"
        printToAll(I18N("persuasionShortageNotice", { 
            player = Player[color].steam_name, 
            card = I18N(cardName),
            cost = cardCost, 
            persuasion = playerPersuasion 
        }), color)
        
        Dialog.showYesOrNoDialog(color, I18N("confirmAcquireWithoutPersuasion", {
            card = I18N(cardName),
            cost = cardCost,
            persuasion = playerPersuasion
        }), Helper.createContinuation("Reserve.acquireTheSpiceMustFlow"), function(confirmed)
            if confirmed then
                printToAll(I18N("playerAcquiredWithoutPersuasion", {
                    player = Player[color].steam_name,
                    card = I18N(cardName)
                }), color)
                if toItsHand then
                    local position = Player[color].getHandTransform().position
                    Helper.moveCardFromZone(Reserve.theSpiceMustFlow.zone, position, nil, false, true)
                else
                    PlayBoard.giveCardFromZone(color, Reserve.theSpiceMustFlow.zone, false, toItsHand)
                end
            else
                printToAll(I18N("playerDeclinedAcquisition", {
                    player = Player[color].steam_name,
                    card = I18N(cardName)
                }), color)
            end
        end)
        return true -- Return true to indicate the dialog was shown
    end
end

--- Move a card out of a trash and back into the reserve if necessary.
function Reserve.redirectUntrashableCards(trashBag, card)
    -- The ID is stored in the 'GM Notes' property (the description and/or name
    -- properties store an unpredictable I18N content).
    local cardName = Helper.getID(card)
    local acquireCard = Reserve[cardName]
    if acquireCard then
        trashBag.takeObject({
            guid = card.guid,
            position = acquireCard.zone.getPosition() + Vector(0, 1, 0),
            rotation = Vector(0, 180, 0),
            smooth = false,
        })
    end
end

return Reserve
