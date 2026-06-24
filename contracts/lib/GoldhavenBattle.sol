// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GoldhavenTypes as T} from "./GoldhavenTypes.sol";

/// @notice Full on-chain deterministic card generation and v94 battle settlement.
/// @dev No battle randomness is used after mint. Randomness is only consumed when a card is generated.
library GoldhavenBattle {
    uint256 internal constant BPS = 10_000;
    uint8 internal constant MAX_ROUNDS = 12;

    error BadSkill();

    // Core mechanism tags. Kept as bit flags to make the engine chain-friendly.
    uint256 internal constant TAG_COMBO = 1 << 0;
    uint256 internal constant TAG_ANTI_COMBO = 1 << 1;
    uint256 internal constant TAG_INITIATIVE = 1 << 2;
    uint256 internal constant TAG_BLOCK_INITIATIVE = 1 << 3;
    uint256 internal constant TAG_BURST = 1 << 4;
    uint256 internal constant TAG_ANTI_BURST = 1 << 5;
    uint256 internal constant TAG_EXECUTE = 1 << 6;
    uint256 internal constant TAG_BLOCK_LIFE = 1 << 7;
    uint256 internal constant TAG_CONDITIONAL_POWER = 1 << 8;
    uint256 internal constant TAG_COUNTER = 1 << 9;
    uint256 internal constant TAG_COUNTER_CONTROL = 1 << 10;
    uint256 internal constant TAG_TRUE_DAMAGE = 1 << 11;
    uint256 internal constant TAG_SHIELD = 1 << 12;
    uint256 internal constant TAG_BLOCK_DEFENSE = 1 << 13;
    uint256 internal constant TAG_RESTORE = 1 << 14;
    uint256 internal constant TAG_BLOCK_HEAL = 1 << 15;
    uint256 internal constant TAG_CURSE = 1 << 16;
    uint256 internal constant TAG_BLOCK_CURSE = 1 << 17;
    uint256 internal constant TAG_CURSE_BURST = 1 << 18;
    uint256 internal constant TAG_SPEED_UP = 1 << 19;
    uint256 internal constant TAG_SLOW = 1 << 20;
    uint256 internal constant TAG_ANTI_SLOW = 1 << 21;
    uint256 internal constant TAG_WEAKEN = 1 << 22;
    uint256 internal constant TAG_CLEANSE = 1 << 23;
    uint256 internal constant TAG_DELAY_SHIFT = 1 << 24;
    uint256 internal constant TAG_ANTI_DELAY_SHIFT = 1 << 25;
    uint256 internal constant TAG_BLOCK_BEAST = 1 << 26;
    uint256 internal constant TAG_LIFE_SAVE = 1 << 27;
    uint256 internal constant TAG_TIE_BIAS = 1 << 28;
    uint256 internal constant TAG_BEAST_BOND = 1 << 29;

    // Runtime flags.
    uint256 internal constant F_ANTI_COMBO = 1 << 0;
    uint256 internal constant F_BURN_ARMOR = 1 << 1;
    uint256 internal constant F_CLEANSE = 1 << 2;
    uint256 internal constant F_ANTI_DELAY = 1 << 3;
    uint256 internal constant F_POJUN = 1 << 4;
    uint256 internal constant F_GUXING = 1 << 5;
    uint256 internal constant F_XUEZHAN = 1 << 6;
    uint256 internal constant F_LINGHUI = 1 << 7;
    uint256 internal constant F_HUANGLONG_POWER = 1 << 8;
    uint256 internal constant F_XUANWU_POWER = 1 << 9;
    uint256 internal constant F_BAIZE_POWER = 1 << 10;
    uint256 internal constant F_BAIHU_POWER = 1 << 11;
    uint256 internal constant F_JIUWEI_POWER = 1 << 12;
    uint256 internal constant F_USED_POJUN = 1 << 13;
    uint256 internal constant F_USED_GUXING = 1 << 14;
    uint256 internal constant F_USED_COUNTER = 1 << 15;

    enum BlockKey {
        None,
        Combo,
        Initiative,
        Burst,
        FirstStrike,
        SpeedControl,
        BlockInitiative,
        Shield,
        BreakDefense,
        Counter,
        Heal,
        LifeSteal,
        Restore,
        Curse,
        Beast,
        OneHp,
        Life,
        LifeSave,
        EffectLock,
        DelayShift,
        Cleanse
    }

    struct Blocks {
        uint8 combo;
        uint8 initiative;
        uint8 burst;
        uint8 firstStrike;
        uint8 speedControl;
        uint8 blockInitiative;
        uint8 shield;
        uint8 breakDefense;
        uint8 counter;
        uint8 heal;
        uint8 lifeSteal;
        uint8 restore;
        uint8 curse;
        uint8 beast;
        uint8 oneHp;
        uint8 life;
        uint8 lifeSave;
        uint8 effectLock;
        uint8 delayShift;
        uint8 cleanse;
    }

    struct State {
        T.Card card;
        int256 atk;
        int256 def;
        int256 spd;
        int256 baseSpd;
        int256 maxHp;
        int256 hp;
        int256 shield;
        uint8 curse;
        bool dead;
        bool deathDelay;
        bool oneHp;
        uint256 flags;
        uint256 usedFirstMask;
        int256 lastDamage;
        uint8 counter;
        uint16 counterPowerBps;
        uint8 antiBurst;
        uint8 antiSlow;
        uint8 antiCounter;
        int16 tieBias;
        Blocks blocks;
    }

    // ---------------------------------------------------------------------
    // Card generation
    // ---------------------------------------------------------------------

    function makeCard(
        uint256 tokenId,
        uint256 buyUsdWad,
        uint256 vaultAvgUsdWad,
        bytes32 seed
    ) internal pure returns (T.Card memory c) {
        uint32 buyUsd = uint32(buyUsdWad / 1e18);
        uint32 avgUsd = uint32(vaultAvgUsdWad / 1e18);

        c.tokenId = tokenId;
        c.buyUsd = buyUsd;
        c.vaultAvgUsd = avgUsd;
        c.classId = pickClass(seed, 1);
        c.element = elementOf(c.classId);
        c.beast = pickBeast(seed, 2);
        c.attrSkill = pickAttrSkill(c.element, rand(seed, 3, 4));
        c.starterSkill = pickStarterSkill(c.classId, rand(seed, 4, 3));
        c.beastSkill = beastSkillOf(c.beast);
        c.finisherSkill = pickFinisherSkill(c.classId, rand(seed, 5, 3));
        c.fate = T.Fate(rand(seed, 6, 9));

        (int16 atkB, int16 defB, int16 spdB, int16 hpB) = classBonus(c.classId);
        c.attack = uint16(uint256(int256(120 + rand(seed, 7, 21) + sqrt(buyUsd)) + int256(atkB)));
        c.defense = uint16(uint256(int256(10 + rand(seed, 8, 6) + sqrt(avgUsd)) + int256(defB)));
        c.speed = uint16(uint256(int256(300 + rand(seed, 9, 81)) + int256(spdB)));
        c.hp = uint16(uint256(int256(500 + rand(seed, 10, 61)) + int256(hpB)));
    }

    function rand(bytes32 seed, uint256 salt, uint256 modulo) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, salt))) % modulo;
    }

    function pickClass(bytes32 seed, uint256 salt) internal pure returns (T.ClassId) {
        uint256 x = rand(seed, salt, 100);
        if (x < 16) return T.ClassId.Zhanjiang;
        if (x < 32) return T.ClassId.Yingren;
        if (x < 48) return T.ClassId.Fangshi;
        if (x < 64) return T.ClassId.Zhenyue;
        if (x < 80) return T.ClassId.Shenshe;
        if (x < 96) return T.ClassId.Yuhun;
        return T.ClassId.Huanying;
    }

    function pickBeast(bytes32 seed, uint256 salt) internal pure returns (T.Beast) {
        uint256 x = rand(seed, salt, 100);
        if (x < 16) return T.Beast.Huanglong;
        if (x < 32) return T.Beast.Baize;
        if (x < 48) return T.Beast.Xuanwu;
        if (x < 64) return T.Beast.Zhuque;
        if (x < 80) return T.Beast.Baihu;
        if (x < 96) return T.Beast.Jiuwei;
        return T.Beast.Dijiang;
    }

    function elementOf(T.ClassId c) internal pure returns (T.Element) {
        if (c == T.ClassId.Zhanjiang) return T.Element.Earth;
        if (c == T.ClassId.Yingren) return T.Element.Wind;
        if (c == T.ClassId.Fangshi) return T.Element.Water;
        if (c == T.ClassId.Zhenyue) return T.Element.Fire;
        if (c == T.ClassId.Shenshe) return T.Element.Light;
        if (c == T.ClassId.Yuhun) return T.Element.Dark;
        return T.Element.Chaos;
    }

    function classBonus(T.ClassId c) internal pure returns (int16 atk, int16 def, int16 spd, int16 hp) {
        if (c == T.ClassId.Zhanjiang) return (50, 42, 152, 112);
        if (c == T.ClassId.Yingren) return (56, 19, 600, 62);
        if (c == T.ClassId.Fangshi) return (21, 52, 292, 162);
        if (c == T.ClassId.Zhenyue) return (18, 86, 25, 235);
        if (c == T.ClassId.Shenshe) return (76, 0, 330, -10);
        if (c == T.ClassId.Yuhun) return (51, 35, 304, 100);
        return (32, 30, 345, 86);
    }

    function bestBeast(T.ClassId c) internal pure returns (T.Beast) {
        if (c == T.ClassId.Zhanjiang) return T.Beast.Huanglong;
        if (c == T.ClassId.Yingren) return T.Beast.Baize;
        if (c == T.ClassId.Fangshi) return T.Beast.Xuanwu;
        if (c == T.ClassId.Zhenyue) return T.Beast.Zhuque;
        if (c == T.ClassId.Shenshe) return T.Beast.Baihu;
        if (c == T.ClassId.Yuhun) return T.Beast.Jiuwei;
        return T.Beast.Dijiang;
    }

    function pickAttrSkill(T.Element e, uint256 x) internal pure returns (T.Skill) {
        uint8 base;
        if (e == T.Element.Earth) base = uint8(T.Skill.DiMai);
        else if (e == T.Element.Wind) base = uint8(T.Skill.LiuYun);
        else if (e == T.Element.Water) base = uint8(T.Skill.HanChao);
        else if (e == T.Element.Fire) base = uint8(T.Skill.ChiYanJia);
        else if (e == T.Element.Light) base = uint8(T.Skill.ShenHui);
        else if (e == T.Element.Dark) base = uint8(T.Skill.ShiHun);
        else base = uint8(T.Skill.CuoXiang);
        return T.Skill(base + uint8(x));
    }

    function pickStarterSkill(T.ClassId c, uint256 x) internal pure returns (T.Skill) {
        uint8 base;
        if (c == T.ClassId.Zhanjiang) base = uint8(T.Skill.DingYingQiang);
        else if (c == T.ClassId.Yingren) base = uint8(T.Skill.BeiXi);
        else if (c == T.ClassId.Fangshi) base = uint8(T.Skill.XuanWuZhen);
        else if (c == T.ClassId.Zhenyue) base = uint8(T.Skill.ZhuQueDunFan);
        else if (c == T.ClassId.Shenshe) base = uint8(T.Skill.GuanRiShi);
        else if (c == T.ClassId.Yuhun) base = uint8(T.Skill.JiuWeiZhouYin);
        else base = uint8(T.Skill.WuMianBu);
        return T.Skill(base + uint8(x));
    }

    function pickFinisherSkill(T.ClassId c, uint256 x) internal pure returns (T.Skill) {
        uint8 base;
        if (c == T.ClassId.Zhanjiang) base = uint8(T.Skill.WanYueGuanQiang);
        else if (c == T.ClassId.Yingren) base = uint8(T.Skill.JueYingSha);
        else if (c == T.ClassId.Fangshi) base = uint8(T.Skill.BeiHaiFengJie);
        else if (c == T.ClassId.Zhenyue) base = uint8(T.Skill.ZhuQueZhenYue);
        else if (c == T.ClassId.Shenshe) base = uint8(T.Skill.LuoXingShi);
        else if (c == T.ClassId.Yuhun) base = uint8(T.Skill.SanHunZhouBao);
        else base = uint8(T.Skill.WanXiangGuiKong);
        return T.Skill(base + uint8(x));
    }

    function beastSkillOf(T.Beast b) internal pure returns (T.Skill) {
        return T.Skill(uint8(T.Skill.DiMaiLongWei) + uint8(b));
    }

    // ---------------------------------------------------------------------
    // Skill table
    // ---------------------------------------------------------------------

    bytes internal constant SKILL_TABLE = hex"2260000010201c20000010002260020000202198000000081db0002010001a900008000420d0000020001ce8000004201964001000001838000040001b58000004001f40000004001b58000000221e78000010001e780000800019c80000002023f00000200027d80000001020080080000022600002000023f000004000200800400000258000010000219800004000200801000000200812000000232800800000226004000000251c0000000824540200002825e4000020002008000000141b58000020001a90000080001b5800003000283c0000340025800010000000000000020019c8080010001f40000000222d500000001028a0000028002a30008200002328000100002648000040002260000000082198010000001f40000010202328048000002e18000000082bc0000020002a30000001001db0000000401e78000000011ce8000080002c880400000024b8000040002a30000004002af80000100028a00000010024b80800400024b8000000402c88000088002bc00000000129040004000026480000400032c8000000802ee0000008002bc0010000002710100040002bc0200000002fa8200000001db02000000027102000000029682000000029682000000023f020000000";

    function skillData(T.Skill s) internal pure returns (uint16 m, uint256 tags) {
        uint256 offset = uint256(uint8(s)) * 6;
        if (offset + 6 > SKILL_TABLE.length) revert BadSkill();
        uint256 raw;
        bytes memory table = SKILL_TABLE;
        assembly {
            raw := shr(208, mload(add(add(table, 32), offset)))
        }
        m = uint16(raw >> 32);
        tags = uint32(raw);
    }

    // ---------------------------------------------------------------------
    // Battle engine
    // ---------------------------------------------------------------------

    function resolve(T.Card memory ca, T.Card memory cb) internal pure returns (T.BattleResult memory r) {
        State memory a = initState(ca);
        State memory b = initState(cb);
        applyFate(a);
        applyFate(b);

        uint8 round;
        for (round = 1; round <= MAX_ROUNDS; round++) {
            if (a.dead || b.dead) break;
            bool aFirst = isFirst(a, b);
            if (aFirst) {
                act(a, b, round);
                if (!b.dead && b.hp > 0) act(b, a, round);
            } else {
                act(b, a, round);
                if (!a.dead && a.hp > 0) act(a, b, round);
            }
            settleDelayedDeath(a);
            settleDelayedDeath(b);
        }

        bool winnerA;
        if (a.dead && b.dead) winnerA = tieWinnerA(a, b);
        else if (a.dead) winnerA = false;
        else if (b.dead) winnerA = true;
        else winnerA = tieWinnerA(a, b);

        r.winnerSide = winnerA ? 0 : 1;
        r.winnerTokenId = winnerA ? ca.tokenId : cb.tokenId;
        r.rounds = round > MAX_ROUNDS ? MAX_ROUNDS : round;
        r.hpA = int32(boundI32(a.hp));
        r.hpB = int32(boundI32(b.hp));
    }

    function initState(T.Card memory c) internal pure returns (State memory s) {
        s.card = c;
        s.atk = int256(uint256(c.attack));
        s.def = int256(uint256(c.defense));
        s.spd = int256(uint256(c.speed));
        s.baseSpd = s.spd;
        s.maxHp = int256(uint256(c.hp));
        s.hp = s.maxHp;
        s.counterPowerBps = 4200;
    }

    function applyFate(State memory s) internal pure {
        if (s.card.fate == T.Fate.Tanlang) {
            s.atk = (s.atk * 107) / 100;
            s.def = (s.def * 98) / 100;
        } else if (s.card.fate == T.Fate.Xuanjia) {
            s.def = (s.def * 107) / 100;
            s.spd = (s.spd * 98) / 100;
            s.baseSpd = s.spd;
        } else if (s.card.fate == T.Fate.Jixing) {
            s.spd = (s.spd * 107) / 100;
            s.baseSpd = s.spd;
            s.maxHp = (s.maxHp * 98) / 100;
            s.hp = s.maxHp;
        } else if (s.card.fate == T.Fate.Changsheng) {
            s.maxHp = (s.maxHp * 109) / 100;
            s.hp = s.maxHp;
            s.atk = (s.atk * 98) / 100;
        } else if (s.card.fate == T.Fate.Pojun) {
            s.flags |= F_POJUN;
        } else if (s.card.fate == T.Fate.Guxing) {
            s.flags |= F_GUXING;
        } else if (s.card.fate == T.Fate.Xuezhan) {
            s.flags |= F_XUEZHAN;
        } else if (s.card.fate == T.Fate.Zhenhun) {
            s.blocks.curse += 2;
        } else if (s.card.fate == T.Fate.Linghui) {
            s.flags |= F_LINGHUI;
        }
    }

    function act(State memory a, State memory d, uint8 round) internal pure {
        if (a.dead || a.hp <= 0) return;
        (uint8 phase, T.Skill skill) = skillForRound(a, round);
        (uint16 baseM, uint256 tags) = skillData(skill);
        uint256 m = uint256(baseM);

        if (phase == 2 && d.blocks.beast > 0) d.blocks.beast--;
        BlockKey blocked = blockCheck(a, tags);

        if (skill == T.Skill.BeiXi && a.spd <= d.spd) m = 5600;
        if (skill == T.Skill.GuanRiShi && usedFirst(a, skill)) m = 9600;
        if (skill == T.Skill.PoXiao && !usedFirst(a, skill)) m = 11200;
        if (skill == T.Skill.JueYingSha && hpBps(d) < 3500) m = 10800;
        if (skill == T.Skill.LuoXingShi && hpBps(d) < 3500) m = 12500;
        if (skill == T.Skill.ShanHeDingSha && a.hp * d.maxHp < d.hp * a.maxHp) m = 12100;
        if (skill == T.Skill.TianHuoFanGe && hasFlag(a, F_USED_COUNTER)) m = 16000;

        if (isBadFangshiXuanwuCard(a)) m = (m * 92) / 100;
        if (isFangshiSlowChain(a) && m > 0) m = (m * 94) / 100;
        if (isFangshiSlowBeihai(a) && skill == T.Skill.BeiHaiFengJie && m > 0) m = (m * 92) / 100;
        if (isFangshiSlowShuijing(a) && skill == T.Skill.ShuiJingZhenFu && m > 0) m = (m * 95) / 100;
        if (isFangshiSlowZhenwu(a) && skill == T.Skill.ZhenWuGuiLiu && m > 0) m = (m * 97) / 100;
        if (isFangshiXuanwu(a) && skill == T.Skill.BeiMingJia && m > 0) m = (m * 97) / 100;
        if (hasFlag(a, F_LINGHUI) && phase == 0) m = (m * 108) / 100;

        m = applyYingrenSpeedDamage(a, d, m);
        m = applyFangshiWaterSlowDamage(a, d, m);

        if (a.card.beast == bestBeast(a.card.classId) && m > 0) m = (m * 103) / 100;
        if (isYingrenBaize(a) && m > 0) m = (m * 92) / 100;
        if ((isShensheBaihu(a) || isHuanyingDijiang(a)) && m > 0) m = (m * 102) / 100;
        if (isFangshiNonXuanwu(a) && m > 0) m = (m * 90) / 100;
        if (isZhanjiangHuanglong(a) && m > 0) m = (m * 103) / 100;
        if (isZhanjiangNonHuanglong(a) && m > 0) m = (m * 90) / 100;
        if (isYingrenNonBaize(a) && m > 0) m = (m * 92) / 100;
        if (isYingrenJiuwei(a) && m > 0) m = (m * 96) / 100;
        if (isZhenyueZhuque(a) && m > 0) m = (m * 92) / 100;
        if (isZhenyueNonZhuque(a) && m > 0) m = (m * 98) / 100;
        if (isHuanyingDijiang(a) && m > 0) m = (m * 98) / 100;
        if (isHuanyingNonDijiang(a) && m > 0) m = (m * 90) / 100;
        if (isYuhunJiuwei(a) && m > 0) m = (m * 94) / 100;
        if (isYuhunNonJiuwei(a) && m > 0) m = (m * 94) / 100;

        if (hasFlag(a, F_POJUN) && !hasFlag(a, F_USED_POJUN) && (d.shield > 0 || d.def * 100 > a.atk * 55)) {
            a.flags |= F_USED_POJUN;
            addBlock(d, BlockKey.Shield, 1);
            addBlock(d, BlockKey.BreakDefense, 1);
            m = (m * 103) / 100;
        }
        if (hasFlag(a, F_HUANGLONG_POWER) && phase == 3) { m = (m * 118) / 100; a.flags &= ~F_HUANGLONG_POWER; }
        if (hasFlag(a, F_XUANWU_POWER) && phase == 3) { a.flags &= ~F_XUANWU_POWER; }
        if (hasFlag(a, F_BAIZE_POWER) && phase == 3) { m = (m * 105) / 100; a.flags &= ~F_BAIZE_POWER; }
        if (hasFlag(a, F_BAIHU_POWER) && phase == 3) { m = (m * 105) / 100; a.flags &= ~F_BAIHU_POWER; }
        if (hasFlag(a, F_XUEZHAN) && hpBps(a) < 3500 && phase == 3) { m = (m * 117) / 100; a.flags &= ~F_XUEZHAN; }
        if (hasFlag(a, F_JIUWEI_POWER) && phase == 3) { a.flags &= ~F_JIUWEI_POWER; }
        if (hasFlag(a, F_GUXING) && !hasFlag(a, F_USED_GUXING) && a.spd > d.spd) {
            a.flags |= F_USED_GUXING;
            m = (m * 109) / 100;
        }

        if (has(tags, TAG_BURST)) {
            if (a.blocks.firstStrike > 0) { a.blocks.firstStrike--; if (m > 10000) m = 10000; blocked = BlockKey.FirstStrike; }
            if (d.antiBurst > 0) { d.antiBurst--; if (m > 10000) m = 10000; }
        }

        if (m > 0) {
            uint256 x = damage(a, d, m);
            a.lastDamage = int256(x);
            take(d, a, x, true);
        } else {
            a.lastDamage = 0;
        }

        if (hasFlag(d, F_BURN_ARMOR) && a.lastDamage > 0) {
            d.flags &= ~F_BURN_ARMOR;
            addBlock(a, BlockKey.Burst, 1);
            addBlock(a, BlockKey.Combo, 1);
        }

        if (!d.dead) applyEffects(a, d, skill, tags, blocked);
        if (isFangshiXuanwu(a) && !isBadFangshiXuanwuCard(a) && !isSkill(skill, T.Skill.HanChao, T.Skill.XuanWuZhen, T.Skill.ZhenWuGuiLiu)) {
            addShield(a, uint256(a.maxHp) / 1000);
        }
        a.usedFirstMask |= (uint256(1) << uint8(skill));

        if (!d.dead && skill == T.Skill.ShuangRenZhuiHun && a.spd > d.spd) {
            if (hasFlag(d, F_ANTI_COMBO)) d.flags &= ~F_ANTI_COMBO;
            else take(d, a, damage(a, d, 800), true);
        }
        if (!d.dead && skill == T.Skill.LianZhuZhongShi) {
            if (hasFlag(d, F_ANTI_COMBO)) d.flags &= ~F_ANTI_COMBO;
            else take(d, a, damage(a, d, 4500), true);
        }
    }

    function applyEffects(State memory a, State memory d, T.Skill skill, uint256 tags, BlockKey blocked) internal pure {
        if (blocked != BlockKey.None) {
            skillMechanismCounter(a, d, skill);
            return;
        }

        if (has(tags, TAG_ANTI_COMBO)) a.flags |= F_ANTI_COMBO;
        if (has(tags, TAG_BLOCK_INITIATIVE)) {
            if (isSkill(skill, T.Skill.YanZhen, T.Skill.DingYingQiang, T.Skill.WanYueGuanQiang)) {
                if (d.spd > a.spd) { addBlock(d, BlockKey.Initiative, 1); addBlock(d, BlockKey.Burst, 1); }
            } else {
                addBlock(d, BlockKey.Initiative, 1); addBlock(d, BlockKey.Burst, 1);
            }
        }
        if (has(tags, TAG_ANTI_BURST)) {
            if (skill == T.Skill.ChiYanJia) a.flags |= F_BURN_ARMOR;
            else a.antiBurst++;
        }
        if (has(tags, TAG_BLOCK_LIFE) && hpBps(d) < 3500) addBlock(d, BlockKey.OneHp, 1);
        if (has(tags, TAG_COUNTER)) { a.counter++; a.counterPowerBps = 6000; a.antiBurst++; }
        if (has(tags, TAG_COUNTER_CONTROL)) {
            if (isSkill(skill, T.Skill.HuiShen, T.Skill.ShuiJing, T.Skill.ShuiJingZhenFu)) a.antiCounter++;
            if (skill == T.Skill.ChiShui && a.spd > d.spd) addBlock(d, BlockKey.Counter, 1);
            if (skill == T.Skill.FuYueZhen && d.def > d.spd) addBlock(d, BlockKey.Counter, 1);
            if (skill == T.Skill.ShuiJingZhenFu) addBlock(d, BlockKey.Counter, 1);
        }
        if (has(tags, TAG_TRUE_DAMAGE)) applyTrueDamage(a, d, skill);
        if (has(tags, TAG_SHIELD)) applyShield(a, d, skill);
        if (has(tags, TAG_BLOCK_DEFENSE)) {
            if (skill == T.Skill.HuangLongBengZhen) { d.shield = 0; addBlock(d, BlockKey.Shield, 1); }
            else { addBlock(d, BlockKey.Shield, 1); addBlock(d, BlockKey.BreakDefense, 1); }
        }
        if (has(tags, TAG_RESTORE)) applyRestore(a, d, skill);
        if (has(tags, TAG_BLOCK_HEAL)) {
            if (skill != T.Skill.LiaoYuan || d.hp < a.hp) {
                addBlock(d, BlockKey.Heal, 1); addBlock(d, BlockKey.LifeSteal, 1); addBlock(d, BlockKey.Restore, 1);
            }
        }
        if (has(tags, TAG_CURSE)) {
            if (skill != T.Skill.YeXing || a.hp * d.maxHp < d.hp * a.maxHp) addCurse(a, d);
        }
        if (has(tags, TAG_BLOCK_CURSE)) { addBlock(d, BlockKey.Curse, 1); addBlock(d, BlockKey.LifeSteal, 1); }
        if (has(tags, TAG_CURSE_BURST)) curseBurst(a, d, true, true);
        if (has(tags, TAG_SPEED_UP) && !usedFirst(a, skill)) a.spd = (a.spd * 112) / 100;
        if (has(tags, TAG_SLOW)) {
            if (skill == T.Skill.HanChao) slow(d, isBadFangshiXuanwuCard(a) ? 400 : (isFangshiColdSlowChain(a) ? 500 : 700));
            else if (skill == T.Skill.ChiShuiFu) slow(d, isFangshiSlowChain(a) ? 1500 : 1800);
        }
        if (has(tags, TAG_ANTI_SLOW)) a.antiSlow++;
        if (has(tags, TAG_WEAKEN)) weaken(a, d, skill);
        if (has(tags, TAG_CLEANSE)) cleanse(a, skill);
        if (has(tags, TAG_DELAY_SHIFT)) {
            if (skill == T.Skill.WuMianBu) { addBlock(d, BlockKey.Burst, 1); addBlock(d, BlockKey.Shield, 1); addBlock(d, BlockKey.Heal, 1); }
            else d.blocks.effectLock++;
        }
        if (has(tags, TAG_ANTI_DELAY_SHIFT)) a.flags |= F_ANTI_DELAY;
        if (has(tags, TAG_BLOCK_BEAST)) addBlock(d, BlockKey.Beast, 1);
        if (has(tags, TAG_LIFE_SAVE)) {
            if (skill == T.Skill.ZhenTianBi) a.deathDelay = true;
            if (skill == T.Skill.BuMieHuoYu && hpBps(a) < 4200) a.oneHp = true;
        }
        if (has(tags, TAG_TIE_BIAS)) a.tieBias++;
        if (has(tags, TAG_BEAST_BOND)) applyBeastBond(a, d, skill);

        skillMechanismCounter(a, d, skill);
    }

    function applyTrueDamage(State memory a, State memory d, T.Skill skill) internal pure {
        if (skill == T.Skill.BaiHuChuanYun) {
            uint256 p = uint256(a.atk) * ((d.shield > 0 || d.def * 100 > a.atk * 55) ? 7 : 4) / 100;
            take(d, a, p, true);
        } else if (skill == T.Skill.BaiHuCaiJue && hpBps(d) < 5000) {
            take(d, a, uint256(a.atk) * 8 / 100, true);
        } else if (skill == T.Skill.WanXiangGuiKong) {
            if (hasAnyBlock(d)) {
                clearFirstBlock(d);
                take(d, a, uint256(a.atk) * 18 / 100, true);
            }
        }
    }

    function applyShield(State memory a, State memory d, T.Skill skill) internal pure {
        if (skill == T.Skill.DiMai) addShield(a, uint256(a.maxHp) * 25 / 1000);
        else if (skill == T.Skill.ShanGu) addShield(a, uint256(a.maxHp) * 6 / 100);
        else if (skill == T.Skill.LiuYun) addShield(a, uint256(a.maxHp) * 25 / 1000);
        else if (skill == T.Skill.ZhuHuo && a.def > d.def) addShield(a, uint256(a.maxHp) * 35 / 1000);
        else if (skill == T.Skill.XuanWuZhen) addShield(a, uint256(a.atk) * (isBadFangshiXuanwuCard(a) ? 56 : 70) / 100);
        else if (skill == T.Skill.FuYueZhen) addShield(a, uint256(a.maxHp) * 4 / 100);
        else if (skill == T.Skill.ZhenTianBi) addShield(a, uint256(a.maxHp) * 7 / 100);
        else if (skill == T.Skill.ZhuQueZhenYue) addShield(a, uint256(a.maxHp) * 11 / 100);
        else if (skill == T.Skill.XuShiJie) addShield(a, uint256(a.maxHp) * 8 / 100);
    }

    function applyRestore(State memory a, State memory d, T.Skill skill) internal pure {
        if (skill == T.Skill.ChaoSheng) heal(a, uint256(a.maxHp) * 4 / 100);
        else if (skill == T.Skill.ZhenWuGuiLiu) heal(a, uint256(a.maxHp) * (isBadFangshiXuanwuCard(a) ? 8 : 12) / 100);
        else if (skill == T.Skill.GuiYing && hpBps(a) < 3500) heal(a, uint256(a.maxHp) * 8 / 100);
        else if (skill == T.Skill.BuMieHuoYu && hpBps(a) < 3800) heal(a, uint256(a.maxHp) * 8 / 100);
        else if (skill == T.Skill.ShiHun) heal(a, uint256(a.lastDamage) * 25 / 100);
        else if (skill == T.Skill.SheHunFan) heal(a, uint256(a.lastDamage) * 32 / 100);
        else if (skill == T.Skill.HunYin && d.curse > 0) heal(a, uint256(a.lastDamage) * 35 / 100);
        else if (skill == T.Skill.WanGuiGuiFan && d.curse > 0) heal(a, uint256(a.maxHp) * 7 * d.curse / 100);
    }

    function applyBeastBond(State memory a, State memory d, T.Skill skill) internal pure {
        if (skill == T.Skill.DiMaiLongWei) {
            a.antiBurst++;
            if (a.card.classId == T.ClassId.Zhanjiang) { a.flags |= F_HUANGLONG_POWER; a.antiBurst++; addShield(a, uint256(a.maxHp) * 7 / 100); }
        } else if (skill == T.Skill.WanLingShiPo) {
            addBlock(d, BlockKey.Initiative, 1);
            if (a.card.classId == T.ClassId.Yingren && a.spd > d.spd) { addBlock(d, BlockKey.Shield, 1); addBlock(d, BlockKey.Heal, 1); a.flags |= F_BAIZE_POWER; }
        } else if (skill == T.Skill.BeiMingJia) {
            addShield(a, uint256(a.maxHp) * (a.card.classId == T.ClassId.Fangshi ? 85 : 70) / 1000);
            if (a.card.classId == T.ClassId.Fangshi) { heal(a, uint256(a.maxHp) * 20 / 1000); a.antiCounter++; a.antiBurst++; a.flags |= F_XUANWU_POWER; }
        } else if (skill == T.Skill.ChiYuNieHuo) {
            if (a.card.classId == T.ClassId.Zhenyue) { a.counter++; a.counterPowerBps = 4800; a.antiBurst++; addShield(a, uint256(a.maxHp) * 5 / 100); }
            if (hpBps(a) < 4200) heal(a, uint256(a.maxHp) * (a.card.classId == T.ClassId.Zhenyue ? 9 : 8) / 100);
        } else if (skill == T.Skill.LieKongCaiGu) {
            if (a.spd > d.spd) addBlock(d, BlockKey.Shield, 1);
            if (a.card.classId == T.ClassId.Shenshe) { a.flags |= F_BAIHU_POWER; if (hpBps(d) < 5000) take(d, a, uint256(a.atk) * 7 / 100, true); }
        } else if (skill == T.Skill.HunQi) {
            heal(a, uint256(a.lastDamage) * (a.card.classId == T.ClassId.Yuhun ? 24 : (a.card.classId == T.ClassId.Yingren ? 18 : 16)) / 100);
            if (a.card.classId == T.ClassId.Yuhun) { addCurse(a, d); a.flags |= F_JIUWEI_POWER; }
        } else if (skill == T.Skill.WuXiangDuanXu) {
            d.blocks.effectLock++;
            if (a.card.classId == T.ClassId.Huanying) { a.flags |= F_ANTI_DELAY; a.tieBias += 1; addShield(a, uint256(a.maxHp) * 5 / 100); }
        }
    }

    function skillMechanismCounter(State memory a, State memory d, T.Skill skill) internal pure {
        if (isSkill(skill, T.Skill.YanZhen, T.Skill.DingYingQiang, T.Skill.LongYaZhen) || skill == T.Skill.WanYueGuanQiang) {
            if (d.spd > a.spd || kitHasTag(d, TAG_INITIATIVE | TAG_BURST | TAG_COMBO)) {
                addBlock(d, BlockKey.Initiative, 1); addBlock(d, BlockKey.Burst, 1); if (kitHasTag(d, TAG_COMBO)) addBlock(d, BlockKey.Combo, 1);
            }
        }
        if (isSkill(skill, T.Skill.HanChao, T.Skill.ChiShuiFu, T.Skill.FuYueZhen, T.Skill.BeiHaiFengJie) || skill == T.Skill.ShuiJingZhenFu) {
            if (kitHasTag(d, TAG_BLOCK_INITIATIVE | TAG_CONDITIONAL_POWER | TAG_BEAST_BOND) || kitHasAnySkill(d, T.Skill.DingYingQiang, T.Skill.LongYaZhen, T.Skill.WanYueGuanQiang, T.Skill.HuangLongBengZhen)) {
                addBlock(d, BlockKey.Initiative, 1); addBlock(d, BlockKey.BlockInitiative, 1); if (skill == T.Skill.BeiHaiFengJie || skill == T.Skill.ShuiJingZhenFu) addBlock(d, BlockKey.Beast, 1);
            }
        }
        if (isYuhunCurseOrRestoreSkill(skill)) {
            if (kitHasTag(d, TAG_BLOCK_INITIATIVE | TAG_ANTI_BURST | TAG_CONDITIONAL_POWER | TAG_BEAST_BOND)) {
                addBlock(d, BlockKey.Initiative, 1); addBlock(d, BlockKey.BlockInitiative, 1); addBlock(d, BlockKey.Restore, 1);
                if (skill == T.Skill.SanHunZhouBao || skill == T.Skill.DuanPo || skill == T.Skill.SuoHunDeng) addBlock(d, BlockKey.LifeSave, 1);
            }
        }
        if (isZhenyueArmorSkill(skill) && kitHasTag(d, TAG_BURST | TAG_COMBO | TAG_EXECUTE | TAG_TRUE_DAMAGE)) {
            a.antiBurst++; a.flags |= F_ANTI_COMBO; if (skill == T.Skill.ZhuQueDunFan || skill == T.Skill.ChiYuNieHuo) { a.counter++; if (a.counterPowerBps < 5200) a.counterPowerBps = 5200; }
        }
        if (isSkill(skill, T.Skill.FengQie, T.Skill.PoZhenRen, T.Skill.DuanXi, T.Skill.BaiZeLieXi) || skill == T.Skill.WanLingShiPo) {
            if (kitHasTag(d, TAG_SHIELD | TAG_RESTORE | TAG_COUNTER | TAG_COUNTER_CONTROL)) { addBlock(d, BlockKey.Shield, 1); addBlock(d, BlockKey.Restore, 1); addBlock(d, BlockKey.Counter, 1); }
        }
        if (isSkill(skill, T.Skill.ShenHui, T.Skill.CaiGuang, T.Skill.BaiHuChuanYun, T.Skill.PoZhouJian) || skill == T.Skill.BaiHuCaiJue || skill == T.Skill.LieKongCaiGu) {
            if (kitHasTag(d, TAG_CURSE | TAG_RESTORE | TAG_SHIELD | TAG_COUNTER)) { addBlock(d, BlockKey.Curse, 1); addBlock(d, BlockKey.Restore, 1); addBlock(d, BlockKey.Shield, 1); if (skill == T.Skill.BaiHuChuanYun || skill == T.Skill.BaiHuCaiJue || skill == T.Skill.LieKongCaiGu) addBlock(d, BlockKey.Counter, 1); }
        }
        if (isSkill(skill, T.Skill.CuoXiang, T.Skill.LieXi, T.Skill.WuMianBu, T.Skill.DuanXuYin) || skill == T.Skill.DuanXiangCai || skill == T.Skill.WanXiangGuiKong || skill == T.Skill.WuXiangDuanXu) {
            if (kitHasTag(d, TAG_BEAST_BOND | TAG_CONDITIONAL_POWER | TAG_BLOCK_INITIATIVE | TAG_BURST | TAG_INITIATIVE)) {
                if (skill != T.Skill.CuoXiang) { d.blocks.effectLock++; addBlock(d, BlockKey.Beast, 1); }
            }
        }
    }

    // ---------------------------------------------------------------------
    // Small mechanics helpers
    // ---------------------------------------------------------------------

    function skillForRound(State memory s, uint8 round) internal pure returns (uint8 phase, T.Skill skill) {
        uint8 k = (round - 1) % 4;
        if (k == 0) return (0, s.card.attrSkill);
        if (k == 1) return (1, s.card.starterSkill);
        if (k == 2) return (2, s.card.beastSkill);
        return (3, s.card.finisherSkill);
    }

    function blockCheck(State memory s, uint256 tags) internal pure returns (BlockKey) {
        if (s.blocks.effectLock > 0) { s.blocks.effectLock--; return BlockKey.EffectLock; }
        if (has(tags, TAG_COMBO) && consume(s, BlockKey.Combo)) return BlockKey.Combo;
        if (has(tags, TAG_INITIATIVE) && (consume(s, BlockKey.Initiative) || consume(s, BlockKey.SpeedControl))) return BlockKey.Initiative;
        if (has(tags, TAG_BURST) && (consume(s, BlockKey.Burst) || consume(s, BlockKey.FirstStrike))) return BlockKey.Burst;
        if (has(tags, TAG_BLOCK_INITIATIVE) && (consume(s, BlockKey.Initiative) || consume(s, BlockKey.SpeedControl) || consume(s, BlockKey.BlockInitiative) || consume(s, BlockKey.Burst) || consume(s, BlockKey.FirstStrike))) return BlockKey.BlockInitiative;
        if ((has(tags, TAG_SHIELD) || has(tags, TAG_BLOCK_DEFENSE)) && (consume(s, BlockKey.Shield) || consume(s, BlockKey.BreakDefense))) return BlockKey.Shield;
        if ((has(tags, TAG_COUNTER) || has(tags, TAG_COUNTER_CONTROL)) && consume(s, BlockKey.Counter)) return BlockKey.Counter;
        if ((has(tags, TAG_RESTORE) || has(tags, TAG_BLOCK_HEAL)) && (consume(s, BlockKey.Heal) || consume(s, BlockKey.LifeSteal) || consume(s, BlockKey.Restore))) return BlockKey.Restore;
        if ((has(tags, TAG_CURSE) || has(tags, TAG_BLOCK_CURSE)) && (consume(s, BlockKey.Curse) || consume(s, BlockKey.LifeSteal))) return BlockKey.Curse;
        if (has(tags, TAG_BEAST_BOND) && consume(s, BlockKey.Beast)) return BlockKey.Beast;
        if (has(tags, TAG_DELAY_SHIFT) && (consume(s, BlockKey.EffectLock) || consume(s, BlockKey.DelayShift))) return BlockKey.DelayShift;
        if (has(tags, TAG_LIFE_SAVE) && (consume(s, BlockKey.OneHp) || consume(s, BlockKey.LifeSave))) return BlockKey.LifeSave;
        if (has(tags, TAG_CLEANSE) && consume(s, BlockKey.Cleanse)) return BlockKey.Cleanse;
        return BlockKey.None;
    }

    function addBlock(State memory s, BlockKey k, uint8 n) internal pure {
        if (hasFlag(s, F_ANTI_DELAY)) { s.flags &= ~F_ANTI_DELAY; return; }
        if (k == BlockKey.Combo) s.blocks.combo += n;
        else if (k == BlockKey.Initiative) s.blocks.initiative += n;
        else if (k == BlockKey.Burst) s.blocks.burst += n;
        else if (k == BlockKey.FirstStrike) s.blocks.firstStrike += n;
        else if (k == BlockKey.SpeedControl) s.blocks.speedControl += n;
        else if (k == BlockKey.BlockInitiative) s.blocks.blockInitiative += n;
        else if (k == BlockKey.Shield) s.blocks.shield += n;
        else if (k == BlockKey.BreakDefense) s.blocks.breakDefense += n;
        else if (k == BlockKey.Counter) s.blocks.counter += n;
        else if (k == BlockKey.Heal) s.blocks.heal += n;
        else if (k == BlockKey.LifeSteal) s.blocks.lifeSteal += n;
        else if (k == BlockKey.Restore) s.blocks.restore += n;
        else if (k == BlockKey.Curse) s.blocks.curse += n;
        else if (k == BlockKey.Beast) s.blocks.beast += n;
        else if (k == BlockKey.OneHp) s.blocks.oneHp += n;
        else if (k == BlockKey.Life) s.blocks.life += n;
        else if (k == BlockKey.LifeSave) s.blocks.lifeSave += n;
        else if (k == BlockKey.EffectLock) s.blocks.effectLock += n;
        else if (k == BlockKey.DelayShift) s.blocks.delayShift += n;
        else if (k == BlockKey.Cleanse) s.blocks.cleanse += n;
    }

    function consume(State memory s, BlockKey k) internal pure returns (bool) {
        if (k == BlockKey.Combo && s.blocks.combo > 0) { s.blocks.combo--; return true; }
        if (k == BlockKey.Initiative && s.blocks.initiative > 0) { s.blocks.initiative--; return true; }
        if (k == BlockKey.Burst && s.blocks.burst > 0) { s.blocks.burst--; return true; }
        if (k == BlockKey.FirstStrike && s.blocks.firstStrike > 0) { s.blocks.firstStrike--; return true; }
        if (k == BlockKey.SpeedControl && s.blocks.speedControl > 0) { s.blocks.speedControl--; return true; }
        if (k == BlockKey.BlockInitiative && s.blocks.blockInitiative > 0) { s.blocks.blockInitiative--; return true; }
        if (k == BlockKey.Shield && s.blocks.shield > 0) { s.blocks.shield--; return true; }
        if (k == BlockKey.BreakDefense && s.blocks.breakDefense > 0) { s.blocks.breakDefense--; return true; }
        if (k == BlockKey.Counter && s.blocks.counter > 0) { s.blocks.counter--; return true; }
        if (k == BlockKey.Heal && s.blocks.heal > 0) { s.blocks.heal--; return true; }
        if (k == BlockKey.LifeSteal && s.blocks.lifeSteal > 0) { s.blocks.lifeSteal--; return true; }
        if (k == BlockKey.Restore && s.blocks.restore > 0) { s.blocks.restore--; return true; }
        if (k == BlockKey.Curse && s.blocks.curse > 0) { s.blocks.curse--; return true; }
        if (k == BlockKey.Beast && s.blocks.beast > 0) { s.blocks.beast--; return true; }
        if (k == BlockKey.OneHp && s.blocks.oneHp > 0) { s.blocks.oneHp--; return true; }
        if (k == BlockKey.Life && s.blocks.life > 0) { s.blocks.life--; return true; }
        if (k == BlockKey.LifeSave && s.blocks.lifeSave > 0) { s.blocks.lifeSave--; return true; }
        if (k == BlockKey.EffectLock && s.blocks.effectLock > 0) { s.blocks.effectLock--; return true; }
        if (k == BlockKey.DelayShift && s.blocks.delayShift > 0) { s.blocks.delayShift--; return true; }
        if (k == BlockKey.Cleanse && s.blocks.cleanse > 0) { s.blocks.cleanse--; return true; }
        return false;
    }

    function take(State memory d, State memory a, uint256 amount, bool canCounter) internal pure {
        if (amount == 0) return;
        int256 left = int256(amount);
        if (d.shield > 0) {
            int256 sh = d.shield < left ? d.shield : left;
            d.shield -= sh;
            left -= sh;
        }
        d.hp -= left;
        if (d.hp <= 0) {
            if (d.oneHp) { d.oneHp = false; d.hp = 1; }
            else if (d.deathDelay) {}
            else d.dead = true;
        }
        if (canCounter && d.counter > 0 && !d.dead && !a.dead) {
            d.counter--;
            d.flags |= F_USED_COUNTER;
            if (a.antiCounter > 0) a.antiCounter--;
            else take(a, d, damage(d, a, d.counterPowerBps), false);
        }
    }

    function damage(State memory a, State memory d, uint256 mBps) internal pure returns (uint256) {
        if (mBps == 0) return 0;
        uint256 def = uint256(d.def > 0 ? d.def : int256(0));
        uint256 factor = 4000 + (6000 * 120) / (120 + def);
        uint256 out = uint256(a.atk > 0 ? a.atk : int256(1)) * factor * mBps / BPS / BPS;
        return out == 0 ? 1 : out;
    }

    function slow(State memory t, uint256 rateBps) internal pure {
        if (t.antiSlow > 0) { t.antiSlow--; return; }
        if (hasFlag(t, F_CLEANSE)) { t.flags &= ~F_CLEANSE; return; }
        t.spd = (t.spd * int256(BPS - rateBps)) / int256(BPS);
        if (t.spd < 1) t.spd = 1;
    }

    function weaken(State memory, State memory d, T.Skill skill) internal pure {
        if (hasFlag(d, F_CLEANSE)) { d.flags &= ~F_CLEANSE; return; }
        uint256 rate = skill == T.Skill.AnShi ? 9200 : 9000;
        d.atk = (d.atk * int256(rate)) / int256(BPS);
        if (d.atk < 1) d.atk = 1;
    }

    function cleanse(State memory a, T.Skill skill) internal pure {
        if (skill == T.Skill.MingJing) a.flags |= F_CLEANSE;
        else if (skill == T.Skill.PoZhouJian) {
            if (a.curse > 0) a.curse--;
            if (a.curse >= 2) a.curse--;
        } else clearFirstBlock(a);
    }

    function addCurse(State memory a, State memory d) internal pure {
        if (d.blocks.curse > 0) { d.blocks.curse--; return; }
        d.curse++;
        if (d.curse >= 3) curseBurst(a, d, false, false);
    }

    function curseBurst(State memory a, State memory d, bool clear, bool strong) internal pure {
        uint8 layers = d.curse;
        if (layers == 0) return;
        uint256 ratio = strong ? 18 : 15;
        uint256 td = uint256(a.atk) * ratio * layers / 100;
        d.curse = clear ? 0 : (d.curse > 3 ? d.curse - 3 : 0);
        take(d, a, td, false);
        heal(a, td * 30 / 100);
    }

    function addShield(State memory s, uint256 n) internal pure {
        if (n == 0) n = 1;
        s.shield += int256(n);
    }

    function heal(State memory s, uint256 n) internal pure {
        if (n == 0) return;
        s.hp += int256(n);
        if (s.hp > s.maxHp) s.hp = s.maxHp;
    }

    function settleDelayedDeath(State memory s) internal pure {
        if (s.hp <= 0 && s.deathDelay) { s.dead = true; s.deathDelay = false; }
        s.deathDelay = false;
    }

    function isFirst(State memory a, State memory b) internal pure returns (bool) {
        if (a.spd != b.spd) return a.spd > b.spd;
        if (a.atk != b.atk) return a.atk > b.atk;
        if (a.def != b.def) return a.def > b.def;
        if (a.card.stakeTime != b.card.stakeTime) return a.card.stakeTime < b.card.stakeTime;
        if (a.card.stakeId != b.card.stakeId) return a.card.stakeId < b.card.stakeId;
        return a.card.tokenId < b.card.tokenId;
    }

    function tieWinnerA(State memory a, State memory b) internal pure returns (bool) {
        int256 ah = a.hp + int256(a.tieBias) * 18;
        int256 bh = b.hp + int256(b.tieBias) * 18;
        if (ah != bh) return ah > bh;
        if (a.atk != b.atk) return a.atk > b.atk;
        if (a.def != b.def) return a.def > b.def;
        if (a.card.stakeTime != b.card.stakeTime) return a.card.stakeTime < b.card.stakeTime;
        if (a.card.stakeId != b.card.stakeId) return a.card.stakeId < b.card.stakeId;
        return a.card.tokenId < b.card.tokenId;
    }

    // ---------------------------------------------------------------------
    // Combination helpers
    // ---------------------------------------------------------------------

    function isFangshiXuanwu(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Fangshi && s.card.beast == T.Beast.Xuanwu; }
    function isFangshiNonXuanwu(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Fangshi && s.card.beast != T.Beast.Xuanwu; }
    function isBadFangshiXuanwuCard(State memory s) internal pure returns (bool) { return isFangshiXuanwu(s) && s.card.attrSkill == T.Skill.HanChao && s.card.starterSkill == T.Skill.XuanWuZhen && s.card.finisherSkill == T.Skill.ZhenWuGuiLiu && s.card.fate == T.Fate.Pojun; }
    function isFangshiSlowChain(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Fangshi && s.card.starterSkill == T.Skill.ChiShuiFu; }
    function isFangshiColdSlowChain(State memory s) internal pure returns (bool) { return isFangshiSlowChain(s) && s.card.attrSkill == T.Skill.HanChao; }
    function isFangshiSlowBeihai(State memory s) internal pure returns (bool) { return isFangshiSlowChain(s) && s.card.finisherSkill == T.Skill.BeiHaiFengJie; }
    function isFangshiSlowShuijing(State memory s) internal pure returns (bool) { return isFangshiSlowChain(s) && s.card.finisherSkill == T.Skill.ShuiJingZhenFu; }
    function isFangshiSlowZhenwu(State memory s) internal pure returns (bool) { return isFangshiSlowChain(s) && s.card.finisherSkill == T.Skill.ZhenWuGuiLiu; }
    function isShensheBaihu(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Shenshe && s.card.beast == T.Beast.Baihu; }
    function isYingrenBaize(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Yingren && s.card.beast == T.Beast.Baize; }
    function isYingrenNonBaize(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Yingren && s.card.beast != T.Beast.Baize; }
    function isYingrenJiuwei(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Yingren && s.card.beast == T.Beast.Jiuwei; }
    function isZhanjiangHuanglong(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Zhanjiang && s.card.beast == T.Beast.Huanglong; }
    function isZhanjiangNonHuanglong(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Zhanjiang && s.card.beast != T.Beast.Huanglong; }
    function isZhenyueZhuque(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Zhenyue && s.card.beast == T.Beast.Zhuque; }
    function isZhenyueNonZhuque(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Zhenyue && s.card.beast != T.Beast.Zhuque; }
    function isHuanyingDijiang(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Huanying && s.card.beast == T.Beast.Dijiang; }
    function isHuanyingNonDijiang(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Huanying && s.card.beast != T.Beast.Dijiang; }
    function isYuhunJiuwei(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Yuhun && s.card.beast == T.Beast.Jiuwei; }
    function isYuhunNonJiuwei(State memory s) internal pure returns (bool) { return s.card.classId == T.ClassId.Yuhun && s.card.beast != T.Beast.Jiuwei; }

    function applyYingrenSpeedDamage(State memory a, State memory d, uint256 m) internal pure returns (uint256) {
        if (a.card.classId != T.ClassId.Yingren || m == 0 || a.spd <= d.spd) return m;
        uint256 diff = uint256(a.spd - d.spd);
        uint256 divisor = a.card.beast == T.Beast.Baize ? 150 : 180;
        uint256 bonusBps = sqrt(diff) * BPS / divisor;
        return m * (BPS + bonusBps) / BPS;
    }

    function applyFangshiWaterSlowDamage(State memory a, State memory d, uint256 m) internal pure returns (uint256) {
        if (a.card.classId != T.ClassId.Fangshi || a.card.element != T.Element.Water || m == 0 || d.baseSpd <= d.spd) return m;
        uint256 base = uint256(d.baseSpd);
        uint256 loss = uint256(d.baseSpd - d.spd);
        uint256 scaleBps = isFangshiSlowChain(a) ? 9500 : 13500;
        uint256 capBps = isFangshiSlowChain(a) ? 2400 : 3600;
        uint256 bonusBps = loss * scaleBps / base;
        if (bonusBps > capBps) bonusBps = capBps;
        return m * (BPS + bonusBps) / BPS;
    }

    function isYuhunCurseOrRestoreSkill(T.Skill s) internal pure returns (bool) {
        return s == T.Skill.YeXing || s == T.Skill.HunYin || s == T.Skill.JiuWeiZhouYin || s == T.Skill.SheHunFan || s == T.Skill.SuoHunDeng || s == T.Skill.SanHunZhouBao || s == T.Skill.WanGuiGuiFan || s == T.Skill.DuanPo || s == T.Skill.HunQi;
    }

    function isZhenyueArmorSkill(T.Skill s) internal pure returns (bool) {
        return s == T.Skill.ChiYanJia || s == T.Skill.ZhuQueDunFan || s == T.Skill.ChiYuShou || s == T.Skill.ZhenTianBi || s == T.Skill.ZhuQueZhenYue || s == T.Skill.BuMieHuoYu || s == T.Skill.ChiYuNieHuo;
    }

    function kitHasTag(State memory s, uint256 wanted) internal pure returns (bool) {
        (, uint256 a) = skillData(s.card.attrSkill);
        (, uint256 b) = skillData(s.card.starterSkill);
        (, uint256 c) = skillData(s.card.beastSkill);
        (, uint256 d) = skillData(s.card.finisherSkill);
        return ((a | b | c | d) & wanted) != 0;
    }

    function kitHasAnySkill(State memory s, T.Skill a, T.Skill b, T.Skill c, T.Skill d) internal pure returns (bool) {
        return s.card.attrSkill == a || s.card.attrSkill == b || s.card.attrSkill == c || s.card.attrSkill == d ||
            s.card.starterSkill == a || s.card.starterSkill == b || s.card.starterSkill == c || s.card.starterSkill == d ||
            s.card.beastSkill == a || s.card.beastSkill == b || s.card.beastSkill == c || s.card.beastSkill == d ||
            s.card.finisherSkill == a || s.card.finisherSkill == b || s.card.finisherSkill == c || s.card.finisherSkill == d;
    }

    function has(uint256 set, uint256 flag) internal pure returns (bool) { return (set & flag) != 0; }
    function hasFlag(State memory s, uint256 flag) internal pure returns (bool) { return (s.flags & flag) != 0; }
    function usedFirst(State memory s, T.Skill skill) internal pure returns (bool) { return (s.usedFirstMask & (uint256(1) << uint8(skill))) != 0; }

    function isSkill(T.Skill s, T.Skill a, T.Skill b, T.Skill c) internal pure returns (bool) { return s == a || s == b || s == c; }
    function isSkill(T.Skill s, T.Skill a, T.Skill b, T.Skill c, T.Skill d) internal pure returns (bool) { return s == a || s == b || s == c || s == d; }

    function hpBps(State memory s) internal pure returns (uint256) {
        if (s.maxHp <= 0) return 0;
        if (s.hp <= 0) return 0;
        return uint256(s.hp) * BPS / uint256(s.maxHp);
    }

    function hasAnyBlock(State memory s) internal pure returns (bool) {
        // Keep this as short-circuit checks instead of one large OR expression.
        // Solidity's legacy codegen can otherwise hit "Stack too deep" while
        // materializing many nested memory-field reads from s.blocks.
        if (s.blocks.combo > 0) return true;
        if (s.blocks.initiative > 0) return true;
        if (s.blocks.burst > 0) return true;
        if (s.blocks.firstStrike > 0) return true;
        if (s.blocks.speedControl > 0) return true;
        if (s.blocks.blockInitiative > 0) return true;
        if (s.blocks.shield > 0) return true;
        if (s.blocks.breakDefense > 0) return true;
        if (s.blocks.counter > 0) return true;
        if (s.blocks.heal > 0) return true;
        if (s.blocks.lifeSteal > 0) return true;
        if (s.blocks.restore > 0) return true;
        if (s.blocks.curse > 0) return true;
        if (s.blocks.beast > 0) return true;
        if (s.blocks.oneHp > 0) return true;
        if (s.blocks.life > 0) return true;
        if (s.blocks.lifeSave > 0) return true;
        if (s.blocks.effectLock > 0) return true;
        if (s.blocks.delayShift > 0) return true;
        if (s.blocks.cleanse > 0) return true;
        return false;
    }

    function clearFirstBlock(State memory s) internal pure {
        if (s.blocks.combo > 0) s.blocks.combo = 0;
        else if (s.blocks.initiative > 0) s.blocks.initiative = 0;
        else if (s.blocks.burst > 0) s.blocks.burst = 0;
        else if (s.blocks.firstStrike > 0) s.blocks.firstStrike = 0;
        else if (s.blocks.speedControl > 0) s.blocks.speedControl = 0;
        else if (s.blocks.blockInitiative > 0) s.blocks.blockInitiative = 0;
        else if (s.blocks.shield > 0) s.blocks.shield = 0;
        else if (s.blocks.breakDefense > 0) s.blocks.breakDefense = 0;
        else if (s.blocks.counter > 0) s.blocks.counter = 0;
        else if (s.blocks.heal > 0) s.blocks.heal = 0;
        else if (s.blocks.lifeSteal > 0) s.blocks.lifeSteal = 0;
        else if (s.blocks.restore > 0) s.blocks.restore = 0;
        else if (s.blocks.curse > 0) s.blocks.curse = 0;
        else if (s.blocks.beast > 0) s.blocks.beast = 0;
        else if (s.blocks.oneHp > 0) s.blocks.oneHp = 0;
        else if (s.blocks.life > 0) s.blocks.life = 0;
        else if (s.blocks.lifeSave > 0) s.blocks.lifeSave = 0;
        else if (s.blocks.effectLock > 0) s.blocks.effectLock = 0;
        else if (s.blocks.delayShift > 0) s.blocks.delayShift = 0;
        else if (s.blocks.cleanse > 0) s.blocks.cleanse = 0;
    }

    function boundI32(int256 x) internal pure returns (int256) {
        if (x > type(int32).max) return type(int32).max;
        if (x < type(int32).min) return type(int32).min;
        return x;
    }

    function sqrt(uint256 x) internal pure returns (uint256 z) {
        if (x == 0) return 0;
        z = x;
        uint256 y = (x + 1) / 2;
        while (y < z) {
            z = y;
            y = (x / y + y) / 2;
        }
    }
}
