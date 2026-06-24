// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import "forge-std/Script.sol";
import "../contracts/GoldhavenNFT.sol";
import "../contracts/lib/GoldhavenTypes.sol";

contract SetGoldhavenNftImageURIs is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        GoldhavenNFT nft = GoldhavenNFT(vm.envAddress("GOLDHAVEN_NFT"));

        vm.startBroadcast(pk);
        nft.setComboImageURIs(_classes(), _beasts(), _uris());
        vm.stopBroadcast();
    }

    function _classes() internal pure returns (GoldhavenTypes.ClassId[] memory a) {
        a = new GoldhavenTypes.ClassId[](49);
        a[0] = GoldhavenTypes.ClassId.Zhanjiang;
        a[1] = GoldhavenTypes.ClassId.Zhanjiang;
        a[2] = GoldhavenTypes.ClassId.Zhanjiang;
        a[3] = GoldhavenTypes.ClassId.Zhanjiang;
        a[4] = GoldhavenTypes.ClassId.Zhanjiang;
        a[5] = GoldhavenTypes.ClassId.Zhanjiang;
        a[6] = GoldhavenTypes.ClassId.Zhanjiang;
        a[7] = GoldhavenTypes.ClassId.Yingren;
        a[8] = GoldhavenTypes.ClassId.Yingren;
        a[9] = GoldhavenTypes.ClassId.Yingren;
        a[10] = GoldhavenTypes.ClassId.Yingren;
        a[11] = GoldhavenTypes.ClassId.Yingren;
        a[12] = GoldhavenTypes.ClassId.Yingren;
        a[13] = GoldhavenTypes.ClassId.Yingren;
        a[14] = GoldhavenTypes.ClassId.Fangshi;
        a[15] = GoldhavenTypes.ClassId.Fangshi;
        a[16] = GoldhavenTypes.ClassId.Fangshi;
        a[17] = GoldhavenTypes.ClassId.Fangshi;
        a[18] = GoldhavenTypes.ClassId.Fangshi;
        a[19] = GoldhavenTypes.ClassId.Fangshi;
        a[20] = GoldhavenTypes.ClassId.Fangshi;
        a[21] = GoldhavenTypes.ClassId.Zhenyue;
        a[22] = GoldhavenTypes.ClassId.Zhenyue;
        a[23] = GoldhavenTypes.ClassId.Zhenyue;
        a[24] = GoldhavenTypes.ClassId.Zhenyue;
        a[25] = GoldhavenTypes.ClassId.Zhenyue;
        a[26] = GoldhavenTypes.ClassId.Zhenyue;
        a[27] = GoldhavenTypes.ClassId.Zhenyue;
        a[28] = GoldhavenTypes.ClassId.Shenshe;
        a[29] = GoldhavenTypes.ClassId.Shenshe;
        a[30] = GoldhavenTypes.ClassId.Shenshe;
        a[31] = GoldhavenTypes.ClassId.Shenshe;
        a[32] = GoldhavenTypes.ClassId.Shenshe;
        a[33] = GoldhavenTypes.ClassId.Shenshe;
        a[34] = GoldhavenTypes.ClassId.Shenshe;
        a[35] = GoldhavenTypes.ClassId.Yuhun;
        a[36] = GoldhavenTypes.ClassId.Yuhun;
        a[37] = GoldhavenTypes.ClassId.Yuhun;
        a[38] = GoldhavenTypes.ClassId.Yuhun;
        a[39] = GoldhavenTypes.ClassId.Yuhun;
        a[40] = GoldhavenTypes.ClassId.Yuhun;
        a[41] = GoldhavenTypes.ClassId.Yuhun;
        a[42] = GoldhavenTypes.ClassId.Huanying;
        a[43] = GoldhavenTypes.ClassId.Huanying;
        a[44] = GoldhavenTypes.ClassId.Huanying;
        a[45] = GoldhavenTypes.ClassId.Huanying;
        a[46] = GoldhavenTypes.ClassId.Huanying;
        a[47] = GoldhavenTypes.ClassId.Huanying;
        a[48] = GoldhavenTypes.ClassId.Huanying;
    }

    function _beasts() internal pure returns (GoldhavenTypes.Beast[] memory a) {
        a = new GoldhavenTypes.Beast[](49);
        a[0] = GoldhavenTypes.Beast.Huanglong;
        a[1] = GoldhavenTypes.Beast.Baize;
        a[2] = GoldhavenTypes.Beast.Xuanwu;
        a[3] = GoldhavenTypes.Beast.Zhuque;
        a[4] = GoldhavenTypes.Beast.Baihu;
        a[5] = GoldhavenTypes.Beast.Jiuwei;
        a[6] = GoldhavenTypes.Beast.Dijiang;
        a[7] = GoldhavenTypes.Beast.Huanglong;
        a[8] = GoldhavenTypes.Beast.Baize;
        a[9] = GoldhavenTypes.Beast.Xuanwu;
        a[10] = GoldhavenTypes.Beast.Zhuque;
        a[11] = GoldhavenTypes.Beast.Baihu;
        a[12] = GoldhavenTypes.Beast.Jiuwei;
        a[13] = GoldhavenTypes.Beast.Dijiang;
        a[14] = GoldhavenTypes.Beast.Huanglong;
        a[15] = GoldhavenTypes.Beast.Baize;
        a[16] = GoldhavenTypes.Beast.Xuanwu;
        a[17] = GoldhavenTypes.Beast.Zhuque;
        a[18] = GoldhavenTypes.Beast.Baihu;
        a[19] = GoldhavenTypes.Beast.Jiuwei;
        a[20] = GoldhavenTypes.Beast.Dijiang;
        a[21] = GoldhavenTypes.Beast.Huanglong;
        a[22] = GoldhavenTypes.Beast.Baize;
        a[23] = GoldhavenTypes.Beast.Xuanwu;
        a[24] = GoldhavenTypes.Beast.Zhuque;
        a[25] = GoldhavenTypes.Beast.Baihu;
        a[26] = GoldhavenTypes.Beast.Jiuwei;
        a[27] = GoldhavenTypes.Beast.Dijiang;
        a[28] = GoldhavenTypes.Beast.Huanglong;
        a[29] = GoldhavenTypes.Beast.Baize;
        a[30] = GoldhavenTypes.Beast.Xuanwu;
        a[31] = GoldhavenTypes.Beast.Zhuque;
        a[32] = GoldhavenTypes.Beast.Baihu;
        a[33] = GoldhavenTypes.Beast.Jiuwei;
        a[34] = GoldhavenTypes.Beast.Dijiang;
        a[35] = GoldhavenTypes.Beast.Huanglong;
        a[36] = GoldhavenTypes.Beast.Baize;
        a[37] = GoldhavenTypes.Beast.Xuanwu;
        a[38] = GoldhavenTypes.Beast.Zhuque;
        a[39] = GoldhavenTypes.Beast.Baihu;
        a[40] = GoldhavenTypes.Beast.Jiuwei;
        a[41] = GoldhavenTypes.Beast.Dijiang;
        a[42] = GoldhavenTypes.Beast.Huanglong;
        a[43] = GoldhavenTypes.Beast.Baize;
        a[44] = GoldhavenTypes.Beast.Xuanwu;
        a[45] = GoldhavenTypes.Beast.Zhuque;
        a[46] = GoldhavenTypes.Beast.Baihu;
        a[47] = GoldhavenTypes.Beast.Jiuwei;
        a[48] = GoldhavenTypes.Beast.Dijiang;
    }

    function _uris() internal pure returns (string[] memory a) {
        a = new string[](49);
        a[0] = "ipfs://Qmbj2tXQuKoQ1vdNvVpASXFWvHUJEwfpBBMAuRRpz2AkSH";
        a[1] = "ipfs://QmZ1vqd5JoHDVPQtXDUsJEpp7NQnoHsbBgagA9S4hqdhzq";
        a[2] = "ipfs://QmV9A84Z4GwzdYzZsGBmyfD2uyeqEhgNCa8ycuVytoqZ6S";
        a[3] = "ipfs://QmWhE74aDNYFaHnkVEgzMs91vk4xTpmiEs3F6mqdpkkzzK";
        a[4] = "ipfs://QmaZCDZo3J2Snx34J82EHcQcXsLeyNax7rJbzfjuYQ12MD";
        a[5] = "ipfs://QmdiaSt6q221N7cnCzVe6RojMc3GUgVLJ5esH8qsa9RpKM";
        a[6] = "ipfs://QmUSv4XBBV94BG92hgAUehieJtGtR4BAgAZpyeuXBmnAGZ";
        a[7] = "ipfs://QmcibJ1wmgHUEZTKWM1AJWGUJRouiKdEkLwSS8VkDoWWif";
        a[8] = "ipfs://QmUucUtQiXdsumXTgKsHjaSZCGcwhwREdW2zVPTZMN3WUi";
        a[9] = "ipfs://QmQT9Wy8WxyuSJ5jWiSmNvzF8TJUS3pygLQ8aCc6Ps396L";
        a[10] = "ipfs://QmWvNycxEzL7kjzBTPh3hwYU7r2jfBaDJSDN9yMpR7N6RZ";
        a[11] = "ipfs://QmUYXshUH46Wn3BaEh3oLtTWA9c4JExxBZGAQVta18ugHg";
        a[12] = "ipfs://Qmeysksg6MMAFcoTJbvccHZBydyZrmr6WjuCRnJhGZxgRb";
        a[13] = "ipfs://QmRbAZwXNN7KrzByPUkfjzbeaexdkJ3JCJpo18PBfCPzKz";
        a[14] = "ipfs://QmXjbXzzjpXgYK9XScSsyixVxBvxHL6EyFbdrfPKFJPXW9";
        a[15] = "ipfs://QmcAidp5qczypUcvMU11z5GuUbemFkuvnVQ4nGbnEENzXB";
        a[16] = "ipfs://Qmc9Qz6pa6NNr4bMvBFqdq7XXeuV1gV9TBxX3jihXyKUzH";
        a[17] = "ipfs://QmZoksc7xgQajh8XBFgW8rY9qShbU2rRizYdmE1seGXhch";
        a[18] = "ipfs://Qmac1SAn9jBZomv8sBtawPTmBt4uwcPqig21YeHR8U4cz2";
        a[19] = "ipfs://QmQ6K3pfGbMKGNB3sZQELKrksvVjViCVUxxFeXYZPSSY1E";
        a[20] = "ipfs://QmW48rqrjBatnLXH7UXqkryd5sxWGpLWGBjDjBfYvVqWtw";
        a[21] = "ipfs://QmefTLTPPqWFuKbMiwu36vptPoqH6UzdWX5UDY6kjjbmCC";
        a[22] = "ipfs://QmVi5WMX54hf9brindHF2j3F2MgE21JjJpwj7u4z4S5tin";
        a[23] = "ipfs://QmdpAFhnpxrqVuaPuhq8XHP3PqSNRmkTDXSAZGvgpuf9Nf";
        a[24] = "ipfs://QmTRtEuPujrw8eXLESPkFESm4vxwM5mReBdEL35tFM8q3e";
        a[25] = "ipfs://QmepPpfatCLTR1zSBhfWLX1Dffz7E2DRiBi3q2UN1wmf2u";
        a[26] = "ipfs://QmatxxnMMWwaKcq9sf2QomVNXKVYmsTLo6AFs6h7W81YXb";
        a[27] = "ipfs://QmPZfEafTQ9J1wiYBjH3sith9VqW6AT9gLYjna9W1Aj9je";
        a[28] = "ipfs://QmTQLAQFCh2ED6DQoxMjViHo2QxHDiDt5i4AsXTxUPUF2p";
        a[29] = "ipfs://QmefPQBpABmLAPb4inBvFecZhRokNxNmDQJgB9VC7beEvS";
        a[30] = "ipfs://QmXi546CdNMJ59UwEF6VDSmWAhALLrMu8CS8nvT1H2NkjY";
        a[31] = "ipfs://QmawUNf2zvo2r2xQUPLGkDviDynzGC4RGv7USoLNKeYf8H";
        a[32] = "ipfs://QmVpc2EzcqqXke5LGtvF7C3sNUSVf7xbDcW3Fckfo62odf";
        a[33] = "ipfs://QmU9E84cuxPLsFibz9tjakTKvWXgH7fd1BRyf1AEVtBTmH";
        a[34] = "ipfs://QmQ1DL7sQSo1xWR8JviSTFBbasSTQcwyFT1iVVQmwx2x2N";
        a[35] = "ipfs://QmPeGT9tdPYR6kUHwPeZh2kxix2RSpx9dyFePaok8u3Cre";
        a[36] = "ipfs://QmZXGwXvWHEW1rTfKZgLkNFk7oZYRWeXPhbt3ySvx5uLXd";
        a[37] = "ipfs://QmXxrzDa74N5mLDmYt5F6kWgn2aSJhMcBoPeJ8QdGJmeiV";
        a[38] = "ipfs://Qmah2BLxuKSjJN7kM2XgP1t6JqkqfpD8NRYWaCRXPKsvwx";
        a[39] = "ipfs://QmVwHw7fqP1QUALpknQ8c7fR4gErT4sc58qEon3BbEEHW4";
        a[40] = "ipfs://QmYrnunSTm4n3m3se4e1XrL611QwroFkvNoDsLgYjAzESU";
        a[41] = "ipfs://QmeYN2wqA1qnqNEBJ9XJnQW9kRYdjvXmdcuSVSe6wbaF1T";
        a[42] = "ipfs://QmcVA5weGYsNep2o169MGkyMpyCEKdmeywo634dinhxbAQ";
        a[43] = "ipfs://QmPsrTSKb9HwAN65EjKeSk1LQ73aRJDaPzo6unoL6nfSuY";
        a[44] = "ipfs://QmWzCrWhNsyBn1MVYWey7Q31GVfVeafMUiwuCkqHownAXL";
        a[45] = "ipfs://QmfBChbdo33Sd47RzqmHsuN1HcfBki1tQTmoXbCtgNyiPG";
        a[46] = "ipfs://QmNPsv8hopu1kC531SZuSCegUbpZauUYkBaJ34BseXaVvo";
        a[47] = "ipfs://QmWWhbPUZMZqxHWsdwhkNkVF5thtGBKKZM8MMVmhs3ELoR";
        a[48] = "ipfs://QmNvKtALzF1NFZs3JFg6RS5HZZj6PFmjT9jZFkUaFsc1f3";
    }
}
