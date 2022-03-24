const NFTStaking = artifacts.require("NFTStaking");
const NFT = artifacts.require("NFT");

module.exports = async function (deployer, network, accounts) {
  await deployer.deploy(NFT);
  const nftInstance = await NFT.deployed();

  await nftInstance.mint(5);

  await nftInstance.transferFrom(accounts[0],accounts[1],1);
  await nftInstance.transferFrom(accounts[0],accounts[2],2);

  await deployer.deploy(NFTStaking,'0x77c21c770Db1156e271a3516F89380BA53D594FA',nftInstance.address);
  const stakeInstance = await NFTStaking.deployed();

  await stakeInstance.add('1000000','300',2,1649158936);

  await nftInstance.approve(stakeInstance.address,1,{from: accounts[1]});
  await nftInstance.approve(stakeInstance.address,2,{from: accounts[2]});
  await nftInstance.approve(stakeInstance.address,3,{from: accounts[0]});

   await stakeInstance.stake(0,1,{from: accounts[1]});
   await stakeInstance.stake(0,2,{from: accounts[2]});
   await stakeInstance.stake(0,3,{from: accounts[0]});
};

//truffle run verify NFT NFTStaking --network bsctestnet 