local Module = require("utils.Module")
local Helper = require("utils.Helper")
local AcquireCard = require("utils.AcquireCard")
local Park = require("utils.Park")
local I18N = require("utils.I18N")

local PlayBoard = Module.lazyRequire("PlayBoard")
local MainBoard = Module.lazyRequire("MainBoard")
local Commander = Module.lazyRequire("Commander")

local SardaukarSkillMarket = {
    acquireCards = {},
}

---
function SardaukarSkillMarket.onLoad(state)
    Helper.append(SardaukarSkillMarket, Helper.resolveGUIDs(false, {
        deck = 'fca82e',
        deckZone = 'ae4b3a',
        skillSlots = {
            '57f7e0',
            '48ab99',
            '73db1d',
            '7e3e07',
        },
    }))

    if state.settings then
        SardaukarSkillMarket._transientSetUp(state.settings)
    end
end

---
function SardaukarSkillMarket.setUp(settings)
    SardaukarSkillMarket._transientSetUp(settings)
    Helper.shuffleDeck(SardaukarSkillMarket.deck)
    Helper.onceShuffled(SardaukarSkillMarket.deck).doAfter(function ()
        for i, _ in ipairs(SardaukarSkillMarket.skillSlots) do
            SardaukarSkillMarket._replenish(i)
        end
    end)
end

---
function SardaukarSkillMarket._transientSetUp(settings)
    SardaukarSkillMarket.acquireCards = {}
    
    for i, zone in ipairs(SardaukarSkillMarket.skillSlots) do
        local acquireCard = AcquireCard.new(zone, "SardaukarSkill", PlayBoard.withLeader(function (_, color)
            local leader = PlayBoard.getLeader(color)
            leader.pickSkill(color, i)
        end))

        acquireCard.groundHeight = acquireCard.groundHeight + 0.2
        table.insert(SardaukarSkillMarket.acquireCards, acquireCard)
    end
end

---
function SardaukarSkillMarket.acquireSkill(indexInRow, color)
    local acquireCard = SardaukarSkillMarket.acquireCards[indexInRow]
    local objects = acquireCard.zone.getObjects()

    if #objects > 0 then
        local skill = objects[1]
        printToAll(I18N("acquireSkill", { name = I18N(Helper.getID(skill)) }), color)
        PlayBoard.grantSkillTile(color, skill, false)
        SardaukarSkillMarket._replenish(indexInRow)
        return true
    else
        return false
    end
end

---
function SardaukarSkillMarket._replenish(indexInRow)
    local acquireCard = SardaukarSkillMarket.acquireCards[indexInRow]
    local position = acquireCard.zone.getPosition()

    Helper.moveCardFromZone(SardaukarSkillMarket.deckZone, position, Vector(0, 180, 0), true)
end

return SardaukarSkillMarket
