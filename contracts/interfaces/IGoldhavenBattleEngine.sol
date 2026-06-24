// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {GoldhavenTypes as T} from "../lib/GoldhavenTypes.sol";

interface IGoldhavenBattleEngine {
    function resolve(T.Card calldata cardA, T.Card calldata cardB) external view returns (T.BattleResult memory);
}
