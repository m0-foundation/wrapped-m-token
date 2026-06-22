// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.26;

library EarnersAddresses {
    function getArbitrumEarners() internal pure returns (address[] memory) {
        address[3] memory earners = [
            0x0A1a1A107E45b7Ced86833863f482BC5f4ed82EF,
            0x0B2b2B2076d95dda7817e785989fE353fe955ef9,
            0xB50A1f651A5ACb2679c8f679D782c728f3702E53
        ];
        address[] memory result = new address[](3);
        for (uint256 i = 0; i < 3; ++i) {
            result[i] = earners[i];
        }
        return result;
    }
    function getEthereumEarners() internal pure returns (address[] memory) {
        address[24] memory earners = [
            0x0502d65f26f45d17503E4d34441F5e73Ea143033,
            0x13Ccb6E28F22E2f6783BaDedCe32cc74583A3647,
            0x48Afe17cB6363fD1aaeA50a8CB652C5978972c96,
            0x4Cbc25559DbBD1272EC5B64c7b5F48a2405e6470,
            0x569D7dccBF6923350521ecBC28A555A500c4f0Ec,
            0x7db685961F97c847A4C815D43E9cc0E5647328b9,
            0x81ad394C0Fa87e99Ca46E1aca093BEe020f203f4,
            0x970A7749EcAA4394C8B2Bf5F2471F41FD6b79288,
            0x985DE23260743c2c2f09BFdeC50b048C7a18c461,
            0x9c6e67fA86138Ab49359F595BfE4Fb163D0f16cc,
            0x9F6d1a62bf268Aa05a1218CFc89C69833D2d2a70,
            0xa969cFCd9e583edb8c8B270Dc8CaFB33d6Cf662D,
            0xB50A1f651A5ACb2679c8f679D782c728f3702E53,
            0xB65a66621D7dE34afec9b9AC0755133051550dD7,
            0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb,
            0xcAD001c30E96765aC90307669d578219D4fb1DCe,
            0xCF3166181848eEC4Fd3b9046aE7CB582F34d2e6c,
            0xdd82875f0840AAD58a455A70B88eEd9F59ceC7c7,
            0xDeD796De6a14E255487191963dEe436c45995813,
            0xE0663f2372cAa1459b7ade90812Dc737CE587FA6,
            0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9,
            0xea0C048c728578b1510EBDF9b692E8936D6Fbc90,
            0xfE940BFE535013a52e8e2DF9644f95E3C94fa14B,
            0xfF95c5f35F4ffB9d5f596F898ac1ae38D62749c2
        ];
        address[] memory result = new address[](24);
        for (uint256 i = 0; i < 24; ++i) {
            result[i] = earners[i];
        }
        return result;
    }
    function getPlumeEarners() internal pure returns (address[] memory) {
        address[1] memory earners = [0xE72Fe64840F4EF80E3Ec73a1c749491b5c938CB9];
        address[] memory result = new address[](1);
        for (uint256 i = 0; i < 1; ++i) {
            result[i] = earners[i];
        }
        return result;
    }
}
