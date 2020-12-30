import {expect} from './chai-setup';
import {
  ethers,
  deployments,
  getUnnamedAccounts,
  getNamedAccounts,
} from 'hardhat';

const advanceToGameStart = async (timestamp: number) => {
  await ethers.provider.send('evm_setNextBlockTimestamp', [timestamp]);
  await ethers.provider.send('evm_mine', []);
};

const advanceTime = async (seconds: number) => {
  await ethers.provider.send('evm_increaseTime', [seconds]);
  await ethers.provider.send('evm_mine', []);
};

const setup = deployments.createFixture(async () => {
  await deployments.fixture('Game');
  await deployments.fixture('TestGame');
  await deployments.fixture('TestERC20');
  await deployments.fixture('TestERC721');
  const {deployer} = await getNamedAccounts();
  const others = await getUnnamedAccounts();
  const game = await ethers.getContract('Game');
  const testGame = await ethers.getContract('TestGame');
  const testErc20 = await ethers.getContract('TestERC20');
  const testErc721 = await ethers.getContract('TestERC721');
  return {
    deployer,
    Game: game,
    TestGame: testGame,
    TestERC20: testErc20,
    TestERC721: testErc721,
    others: others.map((acc: string) => ({address: acc})),
  };
});

describe('Game', function () {
  context('Before Game Start', async function () {
    it('initializes correct nft depositors', async function () {
      const {Game: g} = await setup();
      expect(
        await g.depositors('0x465DCa9995D6c2a81A9Be80fBCeD5a770dEE3daE')
      ).to.equal(true);
      expect(
        await g.depositors('0x426923E98e347158D5C471a9391edaEa95516473')
      ).to.equal(true);
    });

    it('disallows non-whitelisted depositors', async function () {
      const {Game: g} = await setup();
      // deposits with owner account
      await expect(
        g.deposit([ethers.constants.AddressZero], [0])
      ).to.be.revertedWith('you are not allowed to deposit');
    });

    it('adds new whitelisted depositors', async function () {
      const {Game: g, deployer: owner} = await setup();
      await g.addDepositors([owner]);
      expect(await g.depositors(owner)).to.equal(true);
    });

    it('is before game start initially', async function () {
      const {Game: g} = await setup();
      const timeBeforeGameStart = await g.timeBeforeGameStart();
      const latestBlock = await ethers.provider.getBlock('latest');
      const now = latestBlock.timestamp;
      expect(now).to.be.lessThan(timeBeforeGameStart);
    });

    it('disallows to call inits before game start', async function () {
      const {Game: g} = await setup();
      await expect(g.initStart(0, [])).to.be.revertedWith(
        'game has not started yet'
      );
      await expect(g.initEnd(Array(255).fill(0), 0)).to.be.revertedWith(
        'game has not started yet'
      );
    });

    it('successfully init starts the game', async function () {
      const {Game: g} = await setup();
      const timeBeforeGameStart = await g.timeBeforeGameStart();
      await advanceToGameStart(timeBeforeGameStart + 2 * 900);
      // chainlink call
      await expect(g.initStart(1, [0])).to.be.revertedWith(
        'function call to a non-contract account'
      );
    });
  });

  context('Buy Ticket', async function () {
    it('buys the ticket', async function () {
      const {TestGame: g, deployer} = await setup();
      const ticketPrice = await g.ticketPrice();
      await g.buyTicket({value: ticketPrice.toString()});
      const [firstPlayer, num] = await g.player(1);
      expect(firstPlayer).to.equal(deployer);
      expect(num).to.equal(1);
    });

    it('forbids the same acc to buy more than one ticket', async function () {
      const {TestGame: g} = await setup();
      const ticketPrice = await g.ticketPrice();
      await g.buyTicket({value: ticketPrice.toString()});
      await expect(
        g.buyTicket({value: ticketPrice.toString()})
      ).to.be.revertedWith('cant buy more');
    });
  });

  context('Game Start - Unwrap', async function () {
    it('is bueno', async function () {
      const {TestGame: g} = await setup();
      let lastBlock = await ethers.provider.getBlock('latest');
      let timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      const ticketPrice = await g.ticketPrice();
      await g.buyTicket({value: ticketPrice.toString()});
      await advanceTime(1);
      // for testing purposes setting the playersOrder here without entropy
      // in prod, we will construct playersOrder from chainlink's entropies
      // playersOrder is 1-indexed, thus 255 players in total
      const playersOrder = Array(255).fill(0);
      // players[playersOrder] is owner
      playersOrder[0] = 1;
      await g.testSetPlayersOrder(playersOrder);
      await g.unwrap('0');
      expect(await g.currPlayer()).to.equal(1);
      lastBlock = await ethers.provider.getBlock('latest');
      timestamp = lastBlock.timestamp;
      expect(await g.lastAction()).to.equal(timestamp);
    });

    it('forbids to unwrap if not your turn', async function () {
      const {TestGame: g} = await setup();
      const lastBlock = await ethers.provider.getBlock('latest');
      const timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      const ticketPrice = await g.ticketPrice();
      await g.buyTicket({value: ticketPrice.toString()});
      await advanceTime(1);
      const playersOrder = Array(255).fill(0);
      playersOrder[0] = 2;
      await g.testSetPlayersOrder(playersOrder);
      await expect(g.unwrap('0')).to.be.revertedWith('not your turn');
    });

    it('correctly handles 1 missed', async function () {
      const {TestGame: g, others} = await setup();
      let lastBlock = await ethers.provider.getBlock('latest');
      const timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      const ticketPrice = await g.ticketPrice();
      const contract = await ethers.getContract('TestGame', others[1].address);
      await g.buyTicket({value: ticketPrice.toString()});
      await contract.buyTicket({value: ticketPrice.toString()});
      await advanceTime(10800);
      const playersOrder = Array(255).fill(0);
      playersOrder[0] = 1;
      playersOrder[1] = 2;
      await g.testSetPlayersOrder(playersOrder);
      await expect(g.unwrap(0)).to.be.revertedWith('playersSkipped not zero');
      await contract.unwrap(1);
      // next player index
      expect(await contract.currPlayer()).to.be.equal(2);
      lastBlock = await ethers.provider.getBlock('latest');
      expect(await contract.lastAction()).to.be.equal(lastBlock.timestamp);
    });

    it('correctly handles 2 missed', async function () {
      const {TestGame: g, others} = await setup();
      let lastBlock = await ethers.provider.getBlock('latest');
      const timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      const ticketPrice = await g.ticketPrice();
      const c1 = await ethers.getContract('TestGame', others[1].address);
      const c2 = await ethers.getContract('TestGame', others[2].address);
      await g.buyTicket({value: ticketPrice.toString()});
      await c1.buyTicket({value: ticketPrice.toString()});
      await c2.buyTicket({value: ticketPrice.toString()});
      await advanceTime(2 * 10800);
      const playersOrder = Array(255).fill(0);
      playersOrder[0] = 3;
      playersOrder[1] = 1;
      playersOrder[2] = 2;
      await g.testSetPlayersOrder(playersOrder);
      await expect(c2.unwrap(0)).to.be.revertedWith('playersSkipped not zero');
      await expect(c2.unwrap(2)).to.be.revertedWith('not your turn');
      await expect(g.unwrap(0)).to.be.revertedWith('playersSkipped not zero');
      await expect(g.unwrap(2)).to.be.revertedWith('not your turn');
      await expect(c1.unwrap(0)).to.be.revertedWith('playersSkipped not zero');
      await c1.unwrap(2);
      expect(await c1.currPlayer()).to.be.equal(3);
      lastBlock = await ethers.provider.getBlock('latest');
      expect(await c1.lastAction()).to.be.equal(lastBlock.timestamp);
    });

    it('disallows the person that missed the turn to unwrap', async function () {
      const {TestGame: g, others} = await setup();
      const lastBlock = await ethers.provider.getBlock('latest');
      const timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      const ticketPrice = await g.ticketPrice();
      const contract = await ethers.getContract('TestGame', others[1].address);
      await g.buyTicket({value: ticketPrice.toString()});
      await contract.buyTicket({value: ticketPrice.toString()});
      await advanceTime(10800);
      const playersOrder = Array(255).fill(0);
      playersOrder[0] = 1;
      playersOrder[1] = 2;
      await g.testSetPlayersOrder(playersOrder);
      await expect(g.unwrap(1)).to.be.revertedWith('not your turn');
    });
  });

  context('Game Start - Steal', async function () {
    it('steals once just fine', async function () {
      const {TestGame: g, others} = await setup();
      let lastBlock = await ethers.provider.getBlock('latest');
      const timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      const ticketPrice = await g.ticketPrice();
      const c = await ethers.getContract('TestGame', others[1].address);
      await g.buyTicket({value: ticketPrice.toString()});
      await c.buyTicket({value: ticketPrice.toString()});
      const playersOrder = Array(255).fill(0);
      playersOrder[0] = 2;
      playersOrder[1] = 1;
      await g.testSetPlayersOrder(playersOrder);
      await c.unwrap(0);
      await g.steal(1, 0, 0);
      // currPlayer is zero indexed
      expect(await g.currPlayer()).to.be.equal(2);
      lastBlock = await ethers.provider.getBlock('latest');
      expect(await g.lastAction()).to.be.equal(lastBlock.timestamp);
      expect(await g.swaps(1)).to.be.equal(2);
      expect(await g.spaws(2)).to.be.equal(1);
    });

    it('wants to steal from the same acc', async function () {
      const {TestGame: g, others} = await setup();
      let lastBlock = await ethers.provider.getBlock('latest');
      const timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      const ticketPrice = await g.ticketPrice();
      const c = await ethers.getContract('TestGame', others[1].address);
      const d = await ethers.getContract('TestGame', others[2].address);
      await g.buyTicket({value: ticketPrice.toString()});
      await c.buyTicket({value: ticketPrice.toString()});
      await d.buyTicket({value: ticketPrice.toString()});
      const playersOrder = Array(255).fill(0);
      playersOrder[0] = 2;
      playersOrder[1] = 1;
      playersOrder[2] = 3;
      await g.testSetPlayersOrder(playersOrder);
      await c.unwrap(0);
      await g.steal(1, 0, 0);
      // currPlayer is zero indexed
      expect(await g.currPlayer()).to.be.equal(2);
      lastBlock = await ethers.provider.getBlock('latest');
      expect(await g.lastAction()).to.be.equal(lastBlock.timestamp);
      expect(await g.swaps(1)).to.be.equal(2);
      expect(await g.spaws(2)).to.be.equal(1);
      await expect(d.steal(2, 0, 0)).to.be.revertedWith(
        'cant steal from them again'
      );
    });
  });

  context('Finish', async function () {
    it('withdraws all', async function () {
      const {
        TestGame: g,
        TestERC20: e20,
        TestERC721: e721,
        deployer,
      } = await setup();
      // erc20
      let balance = await e20.balanceOf(g.address);
      expect(balance.toString()).to.be.equal(ethers.utils.parseEther('1000'));
      balance = await e20.balanceOf(deployer);
      expect(balance.toString()).to.be.equal('0');
      await g.withdrawERC20(e20.address);
      balance = await e20.balanceOf(g.address);
      expect(balance.toString()).to.be.equal('0');
      balance = await e20.balanceOf(deployer);
      expect(balance.toString()).to.be.equal(ethers.utils.parseEther('1000'));
      // erc721
      await e721.awardItem(g.address);
      let owner = await e721.ownerOf(1);
      expect(owner).to.be.equal(g.address);
      await g.withdrawERC721(e721.address, 1);
      owner = await e721.ownerOf(1);
      expect(owner).to.be.equal(deployer);
      // ether
      await (await ethers.getSigner(deployer)).sendTransaction({
        to: g.address,
        value: ethers.utils.parseEther('1'),
      });
      balance = await ethers.provider.getBalance(g.address);
      expect(balance).to.be.equal(ethers.utils.parseEther('1'));
      const preBalance = await ethers.provider.getBalance(deployer);
      const tx = await g.withdrawEth();
      const receipt = await tx.wait();
      const postBalance = await ethers.provider.getBalance(deployer);
      expect(
        postBalance
          .sub(preBalance)
          .add(receipt.gasUsed.mul(tx.gasPrice))
          .toString()
      ).to.be.equal(ethers.utils.parseEther('1'));
    });

    it('distributes NFTs to players chivalrously', async function () {
      // 20 players. Simulating the worst case here in terms of time complexity
      // such a case would occur if whoever stole from you, was stolen from as well
      // and then that person was stolen from, and so on. And this is the case as
      // much as possible. When would this happen?
      // Let's note that the order in which players take turns is not important here
      // This implies that the playersOrder is arbitrary and we can set it to be
      // equal to the players. i.e. each person takes turn as per who bought
      // ticket the earliest
      const {TestGame: g, others} = await setup();
      const ticketPrice = await g.ticketPrice();
      const cs = [];
      for (let i = 0; i < others.length; i++) {
        cs.push(await ethers.getContract('TestGame', others[i].address));
      }
      const lastBlock = await ethers.provider.getBlock('latest');
      const timestamp = lastBlock.timestamp;
      await g.testSetLastAction(timestamp);
      for (let i = 0; i < cs.length; i++) {
        await cs[i].buyTicket({value: ticketPrice.toString()});
      }
      let i = 0;
      const po = Array(255);
      while (i < 255) po[i++] = i;
      await g.testSetPlayersOrder(po);
      await cs[0].unwrap(0);
      for (let i = 1; i < cs.length; i++) await cs[i].steal(i, i - 1, 0);
      const tx = await g.finito(po, 0, cs.length);
      const {events} = await tx.wait();
      for (let i = 0; i < events.length; i++) {
        if (i === events.length - 1) {
          expect(events[i].args.prizeIx).to.equal(0);
          break;
        }
        const event = events[i];
        const {prizeIx} = event.args;
        expect(prizeIx).to.equal(i + 1);
      }
    });
  });
});
