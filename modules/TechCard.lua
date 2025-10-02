local Module = require("utils.Module")
local Helper = require("utils.Helper")
local I18N = require("utils.I18N")
local Dialog = require("utils.Dialog")

-- Exceptional Immediate require for the sake of aliasing.
local CardEffect = require("CardEffect")

local PlayBoard = Module.lazyRequire("PlayBoard")
local Types = Module.lazyRequire("Types")
local LeaderSelection = Module.lazyRequire("LeaderSelection")

-- Function aliasing for a more readable code.
local persuasion = CardEffect.persuasion
local sword = CardEffect.sword
local spice = CardEffect.spice
local water = CardEffect.water
local solari = CardEffect.solari
local deploy = CardEffect.deploy
local troop = CardEffect.troop
local dreadnought = CardEffect.dreadnought
local negotiator = CardEffect.negotiator
local specimen = CardEffect.specimen
local intrigue = CardEffect.intrigue
local trash = CardEffect.trash
local research = CardEffect.research
local beetle = CardEffect.beetle
local influence = CardEffect.influence
local vp = CardEffect.vp
local draw = CardEffect.draw
local shipment = CardEffect.shipment
local control = CardEffect.control
local spy = CardEffect.spy
local contract = CardEffect.contract
local voice = CardEffect.voice
local perDreadnoughtInConflict = CardEffect.perDreadnoughtInConflict
local perSwordCard = CardEffect.perSwordCard
local perFremen = CardEffect.perFremen
local perEmperor = CardEffect.perEmperor
local perFulfilledContract = CardEffect.perFulfilledContract
local choice = CardEffect.choice
local optional = CardEffect.optional
local seat = CardEffect.seat
local fremenBond = CardEffect.fremenBond
-- bloodlines sardaukar commander in conflict
local sardaukarCommanderInConflict = CardEffect.sardaukarCommanderInConflict
-- bloodlines imperial throneship reveal
local imperialThroneship = CardEffect.imperialThroneship
local agentInEmperorSpace = CardEffect.agentInEmperorSpace
local emperorAlliance = CardEffect.emperorAlliance
local spacingGuildAlliance = CardEffect.spacingGuildAlliance
local beneGesseritAlliance = CardEffect.beneGesseritAlliance
local fremenAlliance = CardEffect.fremenAlliance
local fremenFriendship = CardEffect.fremenFriendship
local anyAlliance = CardEffect.anyAlliance
local oneHelix = CardEffect.oneHelix
local twoHelices = CardEffect.twoHelices
local winner = CardEffect.winner
local twoSpies = CardEffect.twoSpies
local spyMakerSpace = CardEffect.spyMakerSpace
local swordmaster = CardEffect.swordmaster
local multiply = CardEffect.multiply

local TechCard = {
    -- bloodlines disable ix techs
    -- windtraps = {cost = 2, hagal = true, acquireBonus = {water(1)}},
    -- detonationDevices = {cost = 3, hagal = true},
    -- memocorders = {cost = 2, hagal = true, acquireBonus = {influence(1)}},
    -- flagship = {cost = 8, hagal = true, acquireBonus = {vp(1)}},
    -- spaceport = {cost = 5, hagal = false, acquireBonus = {draw(2)}},
    -- artillery = {cost = 1, hagal = false},
    -- holoprojectors = {cost = 3, hagal = false},
    -- restrictedOrdnance = {cost = 4, hagal = false, acquireBonus = {persuasion(seat(2))}},
    -- shuttleFleet = {cost = 6, hagal = true, acquireBonus = {choice(2, {influence(1, "emperor"), influence(1, "spacingGuild"), influence(1, "beneGesserit"), influence(1, "fremen")})}},
    -- spySatellites = {cost = 4, hagal = true},
    -- disposalFacility = {cost = 3, hagal = false, acquireBonus = {trash(1)}},
    -- chaumurky = {cost = 4, hagal = true, acquireBonus = {intrigue(2)}},
    -- sonicSnoopers = {cost = 2, hagal = true, acquireBonus = {intrigue(1)}},
    -- trainingDrones = {cost = 3, hagal = true},
    -- troopTransports = {cost = 2, hagal = true},
    -- holtzmanEngine = {cost = 6, hagal = true},
    -- minimicFilm = {cost = 2, hagal = false, acquireBonus = {persuasion(1)}},
    -- invasionShips = {cost = 5, hagal = true, acquireBonus = {troop(4)}},
    -- bloodlines techs
    bl_TrainingDepot = {cost = 1, hagal = true},
    bl_GeneLockedVault = {cost = 2, hagal = true, acquireBonus = {choice(1, draw(1), intrigue(1))}},
    bl_Glowglobes = {cost = 2, hagal = true, acquireBonus = {influence(1)}},
    bl_PlanetaryArray = {cost = 2, hagal = false, acquireBonus = {trash(1)}},
    bl_ServoReceivers = {cost = 2, hagal = true},
    bl_DeliveryBay = {cost = 3, hagal = true, acquireBonus = {draw(1)}},
    bl_PlasteelBlades = {cost = 3, hagal = false, acquireBonus = {solari(4)}},
    bl_SuspensorSuits = {cost = 3, hagal = false},
    bl_RapidDropships = {cost = 4, hagal = true, acquireBonus = {troop(2)}},
    bl_SelfDestroyingMessages = {cost = 4, hagal = true, acquireBonus = {intrigue(2)}},
    bl_NavigationChamber = {cost = 5, hagal = true, acquireBonus = {influence(1)}},
    bl_SardaukarHighCommand = {cost = 7, hagal = true, acquireBonus = {vp(1)}},
    bl_ForbiddenWeapons = {cost = 2, hagal = false, acquireBonus = {'detonation(1)', troop(1)}},
    bl_AdvancedDataAnalysis = {cost = 3, hagal = false},
    bl_OrnithopterFleet = {cost = 4, hagal = true, acquireBonus = {troop(2)}},
    bl_Panopticon = {cost = 5, hagal = true},
    bl_SpyDrones = {cost = 5, hagal = true, acquireBonus = {spy(2)}},
    bl_ChoamTransports = {cost = 6, hagal = false, acquireBonus = {contract(1)}},
}

-- Persistent handler name for Glowglobes button.
-- We register a single global function so that after script reloads the
-- button's click_function still resolves. We store the owning player color
-- on the tech tile using setVar("GlowglobesOwner", color).
function TechCard_onGlowglobesClick(object, clickingColor)
    -- Defensive: ensure this is actually the Glowglobes tile.
    if not object or Helper.getID(object) ~= "bl_Glowglobes" then
        return
    end

    local owner = object.getVar and object.getVar("GlowglobesOwner") or nil
    if not owner then
        -- Owner not recorded; nothing to do.
        return
    end
    if clickingColor ~= owner then
        Dialog.broadcastToColor(I18N("noTouch"), clickingColor, "Purple")
        return
    end
    local deck = PlayBoard.getDrawDeck(owner)
    if not deck then
        Dialog.broadcastToColor(I18N("prescienceVoid"), owner, "Purple")
        return
    end

    if deck.type == "Card" then
        -- Single loose card (not a deck container).
        broadcastToAll(I18N("glowglobesUseSingle", { player = owner }), owner)
        Dialog.broadcastToColor(I18N("prescienceManual"), owner, "Purple")
        return
    end

    -- Determine quantity; if only one card give alternate message.
    local qty = deck.getQuantity and deck.getQuantity() or nil
    if qty == 1 then
        broadcastToAll(I18N("glowglobesUseSingle", { player = owner }), owner)
    else
        broadcastToAll(I18N("glowglobesUse", { player = owner }), owner)
    end
    deck.Container.search(owner, 1)
end

--- Rehydrate existing Glowglobes buttons after reload.
function TechCard.onLoad(state)
    -- Scan all objects for Glowglobes tech tiles lacking our stable button.
    for _, obj in ipairs(getAllObjects() or {}) do
        if Helper.getID and Helper.getID(obj) == "bl_Glowglobes" then
            -- Ensure owner recorded: if absent we cannot safely enforce access.
            local owner = obj.getVar and obj.getVar("GlowglobesOwner") or nil
            if owner then
                -- Replace any transient buttons with our stable handler.
                if obj.clearButtons then obj.clearButtons() end
                obj.createButton({
                    click_function = "TechCard_onGlowglobesClick",
                    function_owner = Global,
                    label = "",
                    position = {0, 0.35, 0},
                    width = 1400,
                    height = 1400,
                    font_size = 100,
                    color = {0,0,0,0},
                    hover_color = {0.2,0.2,0.2,0.15},
                    press_color = {0.5,0.5,0.5,0.15},
                    tooltip = I18N("glowglobesTooltip"),
                })
            end
        end
    end
end

function TechCard._resolveCard(card)
    assert(card)
    local cardName = Helper.getID(card)
    local cardInfo = TechCard[cardName]
    assert(cardInfo, "Unknown card: " .. tostring(cardName))
    cardInfo.name = cardName
    return cardInfo
end

---
function TechCard.getDetails(techCard)
    return TechCard._resolveCard(techCard)
end

---
function TechCard.getCost(techCard)
    return TechCard._resolveCard(techCard).cost
end

---
function TechCard.isHagal(techCard)
    return TechCard._resolveCard(techCard).hagal
end

---
function TechCard.applyBuyEffect(color, techCard)
    Types.assertIsPlayerColor(color)
    assert(techCard)

    local cardName = Helper.getID(techCard)
    
    -- Check if this is the Ornithopter Fleet tech card
    if cardName == "bl_OrnithopterFleet" then
        LeaderSelection.activateOrnithopterFleet(color)
    end

    local bonus = TechCard.getDetails(techCard).acquireBonus
    if bonus then
        local context = {
            color = color,
            player = PlayBoard.getLeader(color),
            cardName = cardName,
            card = techCard,
        }

        for _, bonusItem in ipairs(bonus) do
            CardEffect.evaluate(context, bonusItem)
        end
    end

    -- Passive / activated tech abilities implemented here (after tile placed on board)
    if cardName == "bl_Glowglobes" then
        -- Remove any previously created Glowglobes button so we can resize / upgrade.
        if techCard.clearButtons then techCard.clearButtons() end
        -- Persist owner color on the object so rehydration code can enforce access.
        if techCard.setVar then
            techCard.setVar("GlowglobesOwner", color)
        end
        techCard.createButton({
            click_function = "TechCard_onGlowglobesClick",
            function_owner = Global,
            label = "",
            position = {0, 0.35, 0},
            width = 1400,
            height = 1400,
            font_size = 100,
            color = {0,0,0,0},
            hover_color = {0.2,0.2,0.2,0.15},
            press_color = {0.5,0.5,0.5,0.15},
            tooltip = I18N("glowglobesTooltip"),
        })
    end
end

return TechCard
