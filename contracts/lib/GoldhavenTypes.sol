// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Shared Goldhaven game data. Chinese display names should be mapped off-chain.
library GoldhavenTypes {
    enum ClassId { Zhanjiang, Yingren, Fangshi, Zhenyue, Shenshe, Yuhun, Huanying }
    enum Element { Earth, Wind, Water, Fire, Light, Dark, Chaos }
    enum Beast { Huanglong, Baize, Xuanwu, Zhuque, Baihu, Jiuwei, Dijiang }
    enum Fate { Tanlang, Xuanjia, Jixing, Changsheng, Pojun, Guxing, Xuezhan, Zhenhun, Linghui }

    enum Skill {
        // Attribute skills, 4 for each element.
        DiMai, ShanGu, HouTu, YanZhen,
        LiuYun, JiXing, FengQie, HuiShen,
        HanChao, ChaoSheng, ShuiJing, ChiShui,
        ChiYanJia, ZhuHuo, LiaoYuan, HuoYu,
        ShenHui, PoXiao, MingJing, CaiGuang,
        ShiHun, AnShi, YeXing, HunYin,
        CuoXiang, GuiXu, WuXu, LieXi,

        // Starter skills, 3 for each class.
        DingYingQiang, LongYaZhen, PoJunTa,
        BeiXi, PoZhenRen, DuanXi,
        XuanWuZhen, FuYueZhen, ChiShuiFu,
        ZhuQueDunFan, ZhenTianBi, ChiYuShou,
        GuanRiShi, BaiHuChuanYun, PoZhouJian,
        JiuWeiZhouYin, SheHunFan, SuoHunDeng,
        WuMianBu, XuShiJie, DuanXuYin,

        // Finisher skills, 3 for each class.
        WanYueGuanQiang, HuangLongBengZhen, ShanHeDingSha,
        JueYingSha, ShuangRenZhuiHun, BaiZeLieXi,
        BeiHaiFengJie, ZhenWuGuiLiu, ShuiJingZhenFu,
        ZhuQueZhenYue, TianHuoFanGe, BuMieHuoYu,
        LuoXingShi, BaiHuCaiJue, LianZhuZhongShi,
        SanHunZhouBao, WanGuiGuiFan, DuanPo,
        WanXiangGuiKong, DuanXiangCai, GuiYing,

        // Beast skills, 1 for each beast.
        DiMaiLongWei, WanLingShiPo, BeiMingJia, ChiYuNieHuo, LieKongCaiGu, HunQi, WuXiangDuanXu
    }

    struct Card {
        uint256 tokenId;
        uint256 stakeId;
        uint64 stakeTime;
        uint32 buyUsd;        // floor(USDT amount) used for attack bonus.
        uint32 vaultAvgUsd;   // floor(24h vault average USDT) used for defense bonus.
        uint16 attack;
        uint16 defense;
        uint16 speed;
        uint16 hp;
        ClassId classId;
        Element element;
        Beast beast;
        Skill attrSkill;
        Skill starterSkill;
        Skill beastSkill;
        Skill finisherSkill;
        Fate fate;
    }

    struct BattleResult {
        uint8 winnerSide; // 0 = A, 1 = B.
        uint256 winnerTokenId;
        uint8 rounds;
        int32 hpA;
        int32 hpB;
    }
}
