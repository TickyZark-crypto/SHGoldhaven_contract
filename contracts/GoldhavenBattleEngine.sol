// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GoldhavenTypes as T} from "./lib/GoldhavenTypes.sol";
import {IGoldhavenBattleEngine} from "./interfaces/IGoldhavenBattleEngine.sol";

/// @notice Size-capped on-chain battle resolver.
/// @dev This version intentionally does not import GoldhavenBattle.sol, because
///      importing the full internal battle library makes the engine exceed EIP-170.
///      Every NFT skill is still resolved on-chain through a compact skill table,
///      bit-packed runtime state, and generic/specialized skill reducers.
contract GoldhavenBattleEngine is IGoldhavenBattleEngine {
    uint256 internal constant BPS = 10_000;
    uint8 internal constant MAX_ROUNDS = 12;

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

    uint256 internal constant F_ANTI_COMBO = 1 << 0;
    uint256 internal constant F_CLEANSE = 1 << 1;
    uint256 internal constant F_ANTI_DELAY = 1 << 2;
    uint256 internal constant F_POJUN = 1 << 3;
    uint256 internal constant F_GUXING = 1 << 4;
    uint256 internal constant F_XUEZHAN = 1 << 5;
    uint256 internal constant F_LINGHUI = 1 << 6;
    uint256 internal constant F_HL = 1 << 7;
    uint256 internal constant F_BZ = 1 << 8;
    uint256 internal constant F_BH = 1 << 9;
    uint256 internal constant F_JW = 1 << 10;
    uint256 internal constant F_USED_POJUN = 1 << 11;
    uint256 internal constant F_USED_GUXING = 1 << 12;
    uint256 internal constant F_USED_COUNTER = 1 << 13;
    uint256 internal constant F_BURN_ARMOR = 1 << 14;

    uint256 internal constant BLK_COMBO = 1 << 0;
    uint256 internal constant BLK_INIT = 1 << 1;
    uint256 internal constant BLK_BURST = 1 << 2;
    uint256 internal constant BLK_FIRST = 1 << 3;
    uint256 internal constant BLK_SHIELD = 1 << 4;
    uint256 internal constant BLK_BREAK = 1 << 5;
    uint256 internal constant BLK_COUNTER = 1 << 6;
    uint256 internal constant BLK_HEAL = 1 << 7;
    uint256 internal constant BLK_RESTORE = 1 << 8;
    uint256 internal constant BLK_CURSE = 1 << 9;
    uint256 internal constant BLK_BEAST = 1 << 10;
    uint256 internal constant BLK_LIFE = 1 << 11;
    uint256 internal constant BLK_LOCK = 1 << 12;
    uint256 internal constant BLK_CLEANSE = 1 << 13;

    bytes internal constant SKILL_TABLE = hex"2260000010201c20000010002260020000202198000000081db0002010001a900008000420d0000020001ce8000004201964001000001838000040001b58000004001f40000004001b58000000221e78000010001e780000800019c80000002023f00000200027d80000001020080080000022600002000023f000004000200800400000258000010000219800004000200801000000200812000000232800800000226004000000251c0000000824540200002825e4000020002008000000141b58000020001a90000080001b5800003000283c0000340025800010000000000000020019c8080010001f40000000222d500000001028a0000028002a30008200002328000100002648000040002260000000082198010000001f40000010202328048000002e18000000082bc0000020002a30000001001db0000000401e78000000011ce8000080002c880400000024b8000040002a30000004002af80000100028a00000010024b80800400024b8000000402c88000088002bc00000000129040004000026480000400032c8000000802ee0000008002bc0010000002710100040002bc0200000002fa8200000001db02000000027102000000029682000000029682000000023f020000000";

    error BadSkill();

    struct S {
        T.Card c;
        int256 atk;
        int256 def;
        int256 spd;
        int256 baseSpd;
        int256 hp;
        int256 maxHp;
        int256 shield;
        int256 last;
        uint256 flags;
        uint256 blocks;
        uint256 used;
        uint8 curse;
        uint8 counter;
        uint16 counterBps;
        uint8 antiBurst;
        uint8 antiSlow;
        uint8 antiCounter;
        int16 tieBias;
        bool dead;
        bool deathDelay;
        bool oneHp;
    }

    function resolve(T.Card calldata cardA, T.Card calldata cardB) external pure returns (T.BattleResult memory r) {
        S memory a = init(cardA);
        S memory b = init(cardB);
        applyFate(a);
        applyFate(b);

        uint8 round;
        for (round = 1; round <= MAX_ROUNDS; round++) {
            if (a.dead || b.dead) break;
            if (first(a, b)) {
                act(a, b, round);
                if (!b.dead && b.hp > 0) act(b, a, round);
            } else {
                act(b, a, round);
                if (!a.dead && a.hp > 0) act(a, b, round);
            }
            settle(a); settle(b);
        }

        bool aw = winnerA(a, b);
        r.winnerSide = aw ? 0 : 1;
        r.winnerTokenId = aw ? cardA.tokenId : cardB.tokenId;
        r.rounds = round > MAX_ROUNDS ? MAX_ROUNDS : round;
        r.hpA = int32(clamp32(a.hp));
        r.hpB = int32(clamp32(b.hp));
    }

    function init(T.Card calldata c) internal pure returns (S memory s) {
        s.c = c;
        s.atk = int256(uint256(c.attack));
        s.def = int256(uint256(c.defense));
        s.spd = int256(uint256(c.speed));
        s.baseSpd = s.spd;
        s.maxHp = int256(uint256(c.hp));
        s.hp = s.maxHp;
        s.counterBps = 4200;
    }

    function applyFate(S memory s) internal pure {
        T.Fate f = s.c.fate;
        if (f == T.Fate.Tanlang) { s.atk = s.atk * 107 / 100; s.def = s.def * 98 / 100; }
        else if (f == T.Fate.Xuanjia) { s.def = s.def * 107 / 100; s.spd = s.spd * 98 / 100; s.baseSpd = s.spd; }
        else if (f == T.Fate.Jixing) { s.spd = s.spd * 107 / 100; s.baseSpd = s.spd; s.maxHp = s.maxHp * 98 / 100; s.hp = s.maxHp; }
        else if (f == T.Fate.Changsheng) { s.maxHp = s.maxHp * 109 / 100; s.hp = s.maxHp; s.atk = s.atk * 98 / 100; }
        else if (f == T.Fate.Pojun) s.flags |= F_POJUN;
        else if (f == T.Fate.Guxing) s.flags |= F_GUXING;
        else if (f == T.Fate.Xuezhan) s.flags |= F_XUEZHAN;
        else if (f == T.Fate.Zhenhun) s.blocks |= BLK_CURSE;
        else if (f == T.Fate.Linghui) s.flags |= F_LINGHUI;
    }

    function act(S memory a, S memory d, uint8 round) internal pure {
        (uint8 phase, T.Skill sk) = skillForRound(a, round);
        (uint16 bm, uint256 tags) = skillData(sk);
        if (phase == 2 && hasBlock(a, BLK_BEAST)) { a.blocks &= ~BLK_BEAST; return; }
        uint256 blocked = blockCheck(a, tags);
        uint256 m = multiplier(a, d, sk, phase, bm);

        if ((tags & TAG_BURST) != 0) {
            if (hasBlock(a, BLK_FIRST)) { a.blocks &= ~BLK_FIRST; if (m > BPS) m = BPS; blocked = BLK_FIRST; }
            if (d.antiBurst > 0) { d.antiBurst--; if (m > BPS) m = BPS; }
        }
        if (m > 0) { uint256 x = damage(a, d, m); a.last = int256(x); take(d, a, x, true); }
        else a.last = 0;

        if ((d.flags & F_BURN_ARMOR) != 0 && a.last > 0) { d.flags &= ~F_BURN_ARMOR; addBlock(a, BLK_BURST | BLK_COMBO); }
        if (!d.dead && blocked == 0) effects(a, d, sk, tags);
        counterKit(a, d, sk);
        a.used |= uint256(1) << uint8(sk);

        if (!d.dead && sk == T.Skill.ShuangRenZhuiHun && a.spd > d.spd) comboHit(a, d, 800);
        if (!d.dead && sk == T.Skill.LianZhuZhongShi) comboHit(a, d, 4500);
    }

    function multiplier(S memory a, S memory d, T.Skill sk, uint8 phase, uint16 bm) internal pure returns (uint256 m) {
        m = bm;
        if (sk == T.Skill.BeiXi && a.spd <= d.spd) m = 5600;
        else if (sk == T.Skill.GuanRiShi && used(a, sk)) m = 9600;
        else if (sk == T.Skill.PoXiao && !used(a, sk)) m = 11200;
        else if ((sk == T.Skill.JueYingSha || sk == T.Skill.LuoXingShi) && hpBps(d) < 3500) m = sk == T.Skill.JueYingSha ? 10800 : 12500;
        else if (sk == T.Skill.ShanHeDingSha && a.hp * d.maxHp < d.hp * a.maxHp) m = 12100;
        else if (sk == T.Skill.TianHuoFanGe && (a.flags & F_USED_COUNTER) != 0) m = 16000;
        if (phase == 0 && (a.flags & F_LINGHUI) != 0) m = m * 108 / 100;
        if (a.c.classId == T.ClassId.Zhanjiang) m = m * 106 / 100;
        if (a.c.classId == T.ClassId.Yingren) m = m * 96 / 100;
        if (a.c.classId == T.ClassId.Huanying) m = m * 88 / 100;
        if (a.c.classId == T.ClassId.Zhenyue) m = m * 101 / 100;
        if (a.c.classId == T.ClassId.Yingren && a.spd > d.spd && m > 0) m = m * (BPS + sqrt(uint256(a.spd - d.spd)) * BPS / (a.c.beast == T.Beast.Baize ? 230 : 270)) / BPS;
        if (a.c.classId == T.ClassId.Fangshi && d.baseSpd > d.spd && m > 0) {
            uint256 bonus = uint256(d.baseSpd - d.spd) * ((a.c.starterSkill == T.Skill.ChiShuiFu) ? 5600 : 10000) / uint256(d.baseSpd);
            uint256 cap = a.c.starterSkill == T.Skill.ChiShuiFu ? 1200 : 2400;
            if (bonus > cap) bonus = cap;
            m = m * (BPS + bonus) / BPS;
        }
        if (a.c.beast == best(a.c.classId) && m > 0) m = m * 102 / 100;
        if (a.c.classId == T.ClassId.Fangshi && a.c.beast != T.Beast.Xuanwu) m = m * 90 / 100;
        if (a.c.classId == T.ClassId.Zhanjiang && a.c.beast != T.Beast.Huanglong) m = m * 98 / 100;
        if (a.c.classId == T.ClassId.Huanying && a.c.beast != T.Beast.Dijiang) m = m * 92 / 100;
        if (a.c.classId == T.ClassId.Huanying && a.c.beast == T.Beast.Dijiang) m = m * 97 / 100;
        if (a.c.classId == T.ClassId.Yuhun) m = m * 93 / 100;
        if ((a.flags & F_POJUN) != 0 && (a.flags & F_USED_POJUN) == 0 && (d.shield > 0 || d.def * 100 > a.atk * 55)) { a.flags |= F_USED_POJUN; addBlock(d, BLK_SHIELD | BLK_BREAK); m = m * 103 / 100; }
        if ((a.flags & F_HL) != 0 && phase == 3) { m = m * 118 / 100; a.flags &= ~F_HL; }
        if ((a.flags & F_BZ) != 0 && phase == 3) { m = m * 102 / 100; a.flags &= ~F_BZ; }
        if ((a.flags & F_BH) != 0 && phase == 3) { m = m * 105 / 100; a.flags &= ~F_BH; }
        if ((a.flags & F_XUEZHAN) != 0 && hpBps(a) < 3500 && phase == 3) { m = m * 117 / 100; a.flags &= ~F_XUEZHAN; }
        if ((a.flags & F_GUXING) != 0 && (a.flags & F_USED_GUXING) == 0 && a.spd > d.spd) { a.flags |= F_USED_GUXING; m = m * 109 / 100; }
    }

    function effects(S memory a, S memory d, T.Skill sk, uint256 tags) internal pure {
        if ((tags & TAG_ANTI_COMBO) != 0) a.flags |= F_ANTI_COMBO;
        if ((tags & TAG_BLOCK_INITIATIVE) != 0) addBlock(d, BLK_INIT | BLK_BURST);
        if ((tags & TAG_ANTI_BURST) != 0) { if (sk == T.Skill.ChiYanJia) a.flags |= F_BURN_ARMOR; else a.antiBurst++; }
        if ((tags & TAG_BLOCK_LIFE) != 0 && hpBps(d) < 3500) addBlock(d, BLK_LIFE);
        if ((tags & TAG_COUNTER) != 0) { a.counter++; a.counterBps = 6000; a.antiBurst++; }
        if ((tags & TAG_COUNTER_CONTROL) != 0) { a.antiCounter++; if (sk != T.Skill.ChiShui || a.spd > d.spd) addBlock(d, BLK_COUNTER); }
        if ((tags & TAG_TRUE_DAMAGE) != 0) trueDamage(a, d, sk);
        if ((tags & TAG_SHIELD) != 0) shieldEffect(a, d, sk);
        if ((tags & TAG_BLOCK_DEFENSE) != 0) { if (sk == T.Skill.HuangLongBengZhen) d.shield = 0; addBlock(d, BLK_SHIELD | BLK_BREAK); }
        if ((tags & TAG_RESTORE) != 0) restore(a, d, sk);
        if ((tags & TAG_BLOCK_HEAL) != 0 && (sk != T.Skill.LiaoYuan || d.hp < a.hp)) addBlock(d, BLK_HEAL | BLK_RESTORE);
        if ((tags & TAG_CURSE) != 0 && (sk != T.Skill.YeXing || a.hp * d.maxHp < d.hp * a.maxHp)) addCurse(a, d);
        if ((tags & TAG_BLOCK_CURSE) != 0) addBlock(d, BLK_CURSE | BLK_RESTORE);
        if ((tags & TAG_CURSE_BURST) != 0) curseBurst(a, d, true, true);
        if ((tags & TAG_SPEED_UP) != 0 && !used(a, sk)) a.spd = a.spd * 112 / 100;
        if ((tags & TAG_SLOW) != 0) slow(d, sk == T.Skill.HanChao ? 500 : 1050);
        if ((tags & TAG_ANTI_SLOW) != 0) a.antiSlow++;
        if ((tags & TAG_WEAKEN) != 0) weaken(d, sk == T.Skill.AnShi ? 9200 : 9000);
        if ((tags & TAG_CLEANSE) != 0) cleanse(a, sk);
        if ((tags & TAG_DELAY_SHIFT) != 0) addBlock(d, sk == T.Skill.WuMianBu ? (BLK_BURST | BLK_SHIELD | BLK_HEAL) : BLK_LOCK);
        if ((tags & TAG_ANTI_DELAY_SHIFT) != 0) a.flags |= F_ANTI_DELAY;
        if ((tags & TAG_BLOCK_BEAST) != 0) addBlock(d, BLK_BEAST);
        if ((tags & TAG_LIFE_SAVE) != 0) { if (sk == T.Skill.ZhenTianBi) a.deathDelay = true; if (sk == T.Skill.BuMieHuoYu && hpBps(a) < 4200) a.oneHp = true; }
        if ((tags & TAG_TIE_BIAS) != 0) a.tieBias++;
        if ((tags & TAG_BEAST_BOND) != 0) beastBond(a, d, sk);
    }

    function trueDamage(S memory a, S memory d, T.Skill sk) internal pure {
        if (sk == T.Skill.BaiHuChuanYun) take(d, a, uint256(a.atk) * ((d.shield > 0 || d.def * 100 > a.atk * 55) ? 7 : 4) / 100, true);
        else if (sk == T.Skill.BaiHuCaiJue && hpBps(d) < 5000) take(d, a, uint256(a.atk) * 8 / 100, true);
        else if (sk == T.Skill.WanXiangGuiKong && d.blocks != 0) { d.blocks = 0; take(d, a, uint256(a.atk) * 14 / 100, true); }
    }

    function shieldEffect(S memory a, S memory d, T.Skill sk) internal pure {
        uint256 n;
        if (sk == T.Skill.DiMai || sk == T.Skill.LiuYun) n = uint256(a.maxHp) * 25 / 1000;
        else if (sk == T.Skill.ShanGu) n = uint256(a.maxHp) * 6 / 100;
        else if (sk == T.Skill.ZhuHuo && a.def > d.def) n = uint256(a.maxHp) * 35 / 1000;
        else if (sk == T.Skill.XuanWuZhen) n = uint256(a.atk) * 60 / 100;
        else if (sk == T.Skill.FuYueZhen) n = uint256(a.maxHp) * 4 / 100;
        else if (sk == T.Skill.ZhenTianBi) n = uint256(a.maxHp) * 6 / 100;
        else if (sk == T.Skill.ZhuQueZhenYue) n = uint256(a.maxHp) * 8 / 100;
        else if (sk == T.Skill.XuShiJie) n = uint256(a.maxHp) * 6 / 100;
        if (n > 0) addShield(a, n);
    }

    function restore(S memory a, S memory d, T.Skill sk) internal pure {
        if (sk == T.Skill.ChaoSheng) heal(a, uint256(a.maxHp) * 4 / 100);
        else if (sk == T.Skill.ZhenWuGuiLiu) heal(a, uint256(a.maxHp) * 9 / 100);
        else if ((sk == T.Skill.GuiYing || sk == T.Skill.BuMieHuoYu) && hpBps(a) < 3800) heal(a, uint256(a.maxHp) * 6 / 100);
        else if (sk == T.Skill.ShiHun) heal(a, uint256(a.last) * 21 / 100);
        else if (sk == T.Skill.SheHunFan) heal(a, uint256(a.last) * 24 / 100);
        else if (sk == T.Skill.HunYin && d.curse > 0) heal(a, uint256(a.last) * 30 / 100);
        else if (sk == T.Skill.WanGuiGuiFan && d.curse > 0) heal(a, uint256(a.maxHp) * 5 * d.curse / 100);
    }

    function beastBond(S memory a, S memory d, T.Skill sk) internal pure {
        if (sk == T.Skill.DiMaiLongWei) { a.antiBurst++; if (a.c.classId == T.ClassId.Zhanjiang) { a.flags |= F_HL; a.antiBurst++; addShield(a, uint256(a.maxHp) * 7 / 100); } }
        else if (sk == T.Skill.WanLingShiPo) { addBlock(d, BLK_INIT); if (a.c.classId == T.ClassId.Yingren && a.spd > d.spd) { addBlock(d, BLK_SHIELD); a.flags |= F_BZ; } }
        else if (sk == T.Skill.BeiMingJia) { addShield(a, uint256(a.maxHp) * (a.c.classId == T.ClassId.Fangshi ? 50 : 70) / 1000); if (a.c.classId == T.ClassId.Fangshi) { heal(a, uint256(a.maxHp) * 2 / 100); a.antiCounter++; a.antiBurst++; } }
        else if (sk == T.Skill.ChiYuNieHuo) { if (a.c.classId == T.ClassId.Zhenyue) { a.counter++; a.counterBps = 3400; a.antiBurst++; addShield(a, uint256(a.maxHp) * 2 / 100); } if (hpBps(a) < 4200) heal(a, uint256(a.maxHp) * 6 / 100); }
        else if (sk == T.Skill.LieKongCaiGu) { if (a.spd > d.spd) addBlock(d, BLK_SHIELD); if (a.c.classId == T.ClassId.Shenshe) { a.flags |= F_BH; if (hpBps(d) < 5000) take(d, a, uint256(a.atk) * 7 / 100, true); } }
        else if (sk == T.Skill.HunQi) { heal(a, uint256(a.last) * (a.c.classId == T.ClassId.Yuhun ? 19 : 16) / 100); if (a.c.classId == T.ClassId.Yuhun) { addCurse(a, d); a.flags |= F_JW; } }
        else if (sk == T.Skill.WuXiangDuanXu) { addBlock(d, BLK_LOCK); if (a.c.classId == T.ClassId.Huanying) { a.flags |= F_ANTI_DELAY; a.tieBias++; addShield(a, uint256(a.maxHp) * 35 / 1000); } }
    }

    function counterKit(S memory a, S memory d, T.Skill sk) internal pure {
        uint256 kt = kitTags(d);
        if ((sk == T.Skill.YanZhen || sk == T.Skill.DingYingQiang || sk == T.Skill.LongYaZhen || sk == T.Skill.WanYueGuanQiang) && (d.spd > a.spd || (kt & (TAG_INITIATIVE | TAG_BURST | TAG_COMBO)) != 0)) addBlock(d, BLK_INIT | BLK_BURST | BLK_COMBO);
        if ((sk == T.Skill.HanChao || sk == T.Skill.ChiShuiFu || sk == T.Skill.FuYueZhen || sk == T.Skill.BeiHaiFengJie || sk == T.Skill.ShuiJingZhenFu) && (kt & (TAG_BLOCK_INITIATIVE | TAG_CONDITIONAL_POWER)) != 0) addBlock(d, BLK_INIT | BLK_BEAST);
        if ((sk == T.Skill.FengQie || sk == T.Skill.PoZhenRen || sk == T.Skill.DuanXi || sk == T.Skill.BaiZeLieXi || sk == T.Skill.WanLingShiPo) && (kt & (TAG_SHIELD | TAG_RESTORE | TAG_COUNTER)) != 0) addBlock(d, BLK_SHIELD | BLK_RESTORE | BLK_COUNTER);
        if ((sk == T.Skill.ShenHui || sk == T.Skill.CaiGuang || sk == T.Skill.BaiHuChuanYun || sk == T.Skill.PoZhouJian || sk == T.Skill.BaiHuCaiJue || sk == T.Skill.LieKongCaiGu) && (kt & (TAG_CURSE | TAG_RESTORE | TAG_SHIELD | TAG_COUNTER)) != 0) addBlock(d, BLK_CURSE | BLK_RESTORE | BLK_SHIELD | BLK_COUNTER);
        if ((sk == T.Skill.CuoXiang || sk == T.Skill.LieXi || sk == T.Skill.WuMianBu || sk == T.Skill.DuanXuYin || sk == T.Skill.DuanXiangCai || sk == T.Skill.WanXiangGuiKong || sk == T.Skill.WuXiangDuanXu) && (kt & (TAG_CONDITIONAL_POWER | TAG_BLOCK_INITIATIVE | TAG_BURST | TAG_INITIATIVE)) != 0) addBlock(d, BLK_LOCK | BLK_BEAST);
    }

    function skillForRound(S memory s, uint8 r) internal pure returns (uint8, T.Skill) {
        uint8 k = (r - 1) & 3;
        if (k == 0) return (0, s.c.attrSkill);
        if (k == 1) return (1, s.c.starterSkill);
        if (k == 2) return (2, s.c.beastSkill);
        return (3, s.c.finisherSkill);
    }

    function skillData(T.Skill s) internal pure returns (uint16 m, uint256 tags) {
        uint256 offset = uint256(uint8(s)) * 6;
        if (offset + 6 > SKILL_TABLE.length) revert BadSkill();
        uint256 raw; bytes memory table = SKILL_TABLE;
        assembly { raw := shr(208, mload(add(add(table, 32), offset))) }
        m = uint16(raw >> 32); tags = uint32(raw);
    }

    function blockCheck(S memory s, uint256 tags) internal pure returns (uint256 b) {
        if (hasBlock(s, BLK_LOCK)) { s.blocks &= ~BLK_LOCK; return BLK_LOCK; }
        if ((tags & TAG_COMBO) != 0 && consume(s, BLK_COMBO)) return BLK_COMBO;
        if ((tags & (TAG_INITIATIVE | TAG_BLOCK_INITIATIVE)) != 0 && consume(s, BLK_INIT | BLK_BURST | BLK_FIRST)) return BLK_INIT;
        if ((tags & TAG_BURST) != 0 && consume(s, BLK_BURST | BLK_FIRST)) return BLK_BURST;
        if ((tags & (TAG_SHIELD | TAG_BLOCK_DEFENSE)) != 0 && consume(s, BLK_SHIELD | BLK_BREAK)) return BLK_SHIELD;
        if ((tags & (TAG_COUNTER | TAG_COUNTER_CONTROL)) != 0 && consume(s, BLK_COUNTER)) return BLK_COUNTER;
        if ((tags & (TAG_RESTORE | TAG_BLOCK_HEAL)) != 0 && consume(s, BLK_HEAL | BLK_RESTORE)) return BLK_RESTORE;
        if ((tags & (TAG_CURSE | TAG_BLOCK_CURSE)) != 0 && consume(s, BLK_CURSE)) return BLK_CURSE;
        if ((tags & TAG_BEAST_BOND) != 0 && consume(s, BLK_BEAST)) return BLK_BEAST;
        if ((tags & TAG_LIFE_SAVE) != 0 && consume(s, BLK_LIFE)) return BLK_LIFE;
        if ((tags & TAG_CLEANSE) != 0 && consume(s, BLK_CLEANSE)) return BLK_CLEANSE;
    }

    function addBlock(S memory s, uint256 b) internal pure { if ((s.flags & F_ANTI_DELAY) != 0) s.flags &= ~F_ANTI_DELAY; else s.blocks |= b; }
    function consume(S memory s, uint256 b) internal pure returns (bool) { uint256 x = s.blocks & b; if (x == 0) return false; s.blocks &= ~x; return true; }
    function hasBlock(S memory s, uint256 b) internal pure returns (bool) { return (s.blocks & b) != 0; }

    function take(S memory d, S memory a, uint256 amount, bool canCounter) internal pure {
        int256 left = int256(amount);
        if (d.shield > 0) { int256 sh = d.shield < left ? d.shield : left; d.shield -= sh; left -= sh; }
        d.hp -= left;
        if (d.hp <= 0) { if (d.oneHp) { d.oneHp = false; d.hp = 1; } else if (!d.deathDelay) d.dead = true; }
        if (canCounter && d.counter > 0 && !d.dead && !a.dead) { d.counter--; d.flags |= F_USED_COUNTER; if (a.antiCounter > 0) a.antiCounter--; else take(a, d, damage(d, a, d.counterBps), false); }
    }

    function damage(S memory a, S memory d, uint256 m) internal pure returns (uint256 x) {
        uint256 df = uint256(d.def > 0 ? d.def : int256(0));
        x = uint256(a.atk > 0 ? a.atk : int256(1)) * (4000 + 720000 / (120 + df)) * m / BPS / BPS;
        if (x == 0 && m > 0) x = 1;
    }

    function slow(S memory s, uint256 rate) internal pure { if (s.antiSlow > 0) s.antiSlow--; else if ((s.flags & F_CLEANSE) != 0) s.flags &= ~F_CLEANSE; else { s.spd = s.spd * int256(BPS - rate) / int256(BPS); if (s.spd < 1) s.spd = 1; } }
    function weaken(S memory s, uint256 rate) internal pure { if ((s.flags & F_CLEANSE) != 0) s.flags &= ~F_CLEANSE; else { s.atk = s.atk * int256(rate) / int256(BPS); if (s.atk < 1) s.atk = 1; } }
    function cleanse(S memory s, T.Skill sk) internal pure { if (sk == T.Skill.MingJing) s.flags |= F_CLEANSE; else if (sk == T.Skill.PoZhouJian) { if (s.curse > 0) s.curse--; if (s.curse >= 2) s.curse--; } else s.blocks = 0; }
    function addCurse(S memory a, S memory d) internal pure { if (consume(d, BLK_CURSE)) return; d.curse++; if (d.curse >= 3) curseBurst(a, d, false, false); }
    function curseBurst(S memory a, S memory d, bool clear, bool strong) internal pure { uint8 n = d.curse; if (n == 0) return; uint256 x = uint256(a.atk) * (strong ? 16 : 13) * n / 100; d.curse = clear ? 0 : (n > 3 ? n - 3 : 0); take(d, a, x, false); heal(a, x * 30 / 100); }
    function addShield(S memory s, uint256 n) internal pure { s.shield += int256(n == 0 ? 1 : n); }
    function heal(S memory s, uint256 n) internal pure { s.hp += int256(n); if (s.hp > s.maxHp) s.hp = s.maxHp; }
    function comboHit(S memory a, S memory d, uint256 m) internal pure { if ((d.flags & F_ANTI_COMBO) != 0) d.flags &= ~F_ANTI_COMBO; else take(d, a, damage(a, d, m), true); }
    function settle(S memory s) internal pure { if (s.hp <= 0 && s.deathDelay) { s.dead = true; s.deathDelay = false; } s.deathDelay = false; }

    function first(S memory a, S memory b) internal pure returns (bool) { if (a.spd != b.spd) return a.spd > b.spd; if (a.atk != b.atk) return a.atk > b.atk; if (a.def != b.def) return a.def > b.def; if (a.c.stakeTime != b.c.stakeTime) return a.c.stakeTime < b.c.stakeTime; if (a.c.stakeId != b.c.stakeId) return a.c.stakeId < b.c.stakeId; return a.c.tokenId < b.c.tokenId; }
    function winnerA(S memory a, S memory b) internal pure returns (bool) { if (a.dead != b.dead) return !a.dead; int256 ah = a.hp + int256(a.tieBias) * 18; int256 bh = b.hp + int256(b.tieBias) * 18; if (ah != bh) return ah > bh; return first(a, b); }
    function hpBps(S memory s) internal pure returns (uint256) { return s.hp <= 0 ? 0 : uint256(s.hp) * BPS / uint256(s.maxHp); }
    function used(S memory s, T.Skill sk) internal pure returns (bool) { return (s.used & (uint256(1) << uint8(sk))) != 0; }
    function kitTags(S memory s) internal pure returns (uint256 t) { (, uint256 a) = skillData(s.c.attrSkill); (, uint256 b) = skillData(s.c.starterSkill); (, uint256 c) = skillData(s.c.beastSkill); (, uint256 d) = skillData(s.c.finisherSkill); t = a | b | c | d; }
    function best(T.ClassId c) internal pure returns (T.Beast) { if (c == T.ClassId.Zhanjiang) return T.Beast.Huanglong; if (c == T.ClassId.Yingren) return T.Beast.Baize; if (c == T.ClassId.Fangshi) return T.Beast.Xuanwu; if (c == T.ClassId.Zhenyue) return T.Beast.Zhuque; if (c == T.ClassId.Shenshe) return T.Beast.Baihu; if (c == T.ClassId.Yuhun) return T.Beast.Jiuwei; return T.Beast.Dijiang; }
    function clamp32(int256 x) internal pure returns (int256) { if (x > type(int32).max) return type(int32).max; if (x < type(int32).min) return type(int32).min; return x; }
    function sqrt(uint256 x) internal pure returns (uint256 z) { if (x == 0) return 0; z = x; uint256 y = (x + 1) / 2; while (y < z) { z = y; y = (x / y + y) / 2; } }
}
