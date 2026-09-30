--[[
    树桩锤 / Stump Quake Hammer

    给锤子扩展一个捶地用法：锤子砸到树桩时，会把落点周围范围内的所有树桩一次性震出，
    各自的掉落物照常结算，从而省去用铲子逐个挖掘。

    表现沿用锤子本身的挥击动作与命中音效，不另加特效。
]]

local ACTIONS = GLOBAL.ACTIONS

-- 树桩标签。本体、巨人国、海难、神人四个模式里的全部树桩 prefab 都带此标签，
-- 而同样属于 ACTIONS.DIG 的草、莓果丛、兔子洞、蘑菇、树苗等都不带，可据此单独筛出树桩。
local STUMP_TAG = "stump"

-- 震地作用半径（世界单位，约一格）
local QUAKE_RADIUS = 1

-- 捶地音效，取自本体资源，不依赖任何 DLC
local SOUND_QUAKE = "dontstarve/forest/treeCrumble"
local SOUND_IMPACT = "dontstarve/impacts/impact_stone_lrg_dull"

--------------------------------------------------------------------------
-- 判定
--------------------------------------------------------------------------

-- 树桩的作业动作固定为 ACTIONS.DIG（只认铲子），耐久只剩 1 点
local function IsQuakeableStump(workable)
    return workable.inst:HasTag(STUMP_TAG)
        and workable.action == ACTIONS.DIG
        and workable.workleft > 0
end

local function CanQuake(act)
    local workable = act.target ~= nil and act.target.components.workable or nil
    return workable ~= nil and IsQuakeableStump(workable)
end

--------------------------------------------------------------------------
-- 效果
--------------------------------------------------------------------------

-- 震出一棵树桩：把耐久归零并执行挖掘完成回调，等价于用铲子挖掉，
-- 之后的掉落结算与实体移除都交给树桩自身处理。
-- 刻意不走 workable:WorkedBy：那条路径每棵树都会额外抛一次 working 事件，
-- 雨天里「工具打滑」的判定会被放大到 N 次。
local function ShakeOutStump(stump, doer)
    local workable = stump.components.workable

    if workable.onfinish ~= nil then
        workable.workleft = 0
        workable.onfinish(stump, doer)
    else
        workable:WorkedBy(doer)
    end
end

-- 把落点范围内的所有树桩一次性震出，返回被震出的数量
local function ShakeStumps(doer, x, y, z)
    local stumps = GLOBAL.TheSim:FindEntities(x, y, z, QUAKE_RADIUS, { STUMP_TAG })

    local shaken = 0

    for _, stump in pairs(stumps) do
        -- 有效性判定要紧挨着使用：前面的震出可能已经移除了后面的实体
        local workable = stump:IsValid() and stump.components.workable or nil

        if workable ~= nil and IsQuakeableStump(workable) then
            ShakeOutStump(stump, doer)
            shaken = shaken + 1
        end
    end

    return shaken
end

--------------------------------------------------------------------------
-- 接入
--------------------------------------------------------------------------

-- 让锤击成为树桩上的可选动作。
-- 锤击本就是右键动作（Workable:IsActionValid 对 HAMMER 会校验 right），
-- 而树桩只接受 ACTIONS.DIG，所以过去锤树桩没有任何动作可做，这里补上。
AddComponentPostInit("workable", function(workable)
    local orig_isactionvalid = workable.IsActionValid

    function workable:IsActionValid(action, right)
        if right and action == ACTIONS.HAMMER and IsQuakeableStump(self) then
            return true
        end

        return orig_isactionvalid(self, action, right)
    end
end)

-- 锤击落在树桩上改为捶地，其余情况（拆建筑等）沿用原逻辑。
-- 锤子挥击动画由 SGwilson 的 hammer 状态提供，PerformBufferedAction 排在第 9 帧，
-- 正是锤子砸到地面的瞬间，因此音效挂在这里，时序天然对齐。
local orig_hammer_fn = ACTIONS.HAMMER.fn

ACTIONS.HAMMER.fn = function(act)
    if not CanQuake(act) then
        return orig_hammer_fn(act)
    end

    local doer = act.doer
    local x, y, z = act.target.Transform:GetWorldPosition()

    -- 目标可能在按下与落地之间被别的东西清掉，没有震出任何树桩时就不再出音效
    if ShakeStumps(doer, x, y, z) > 0 then
        if doer ~= nil and doer.SoundEmitter ~= nil then
            doer.SoundEmitter:PlaySound(SOUND_QUAKE)
            doer.SoundEmitter:PlaySound(SOUND_IMPACT)
        end
    end

    -- 按设计不触发镜头震动

    return true
end