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

const setup = deployments.createFixture(async () => {
  await deployments.fixture('Game');
  const {deployer} = await getNamedAccounts();
  const others = await getUnnamedAccounts();
  const game = await ethers.getContract('Game');
  return {
    deployer,
    Game: game,
    others: others.map((acc: string) => ({address: acc})),
  };
});

describe('Game', function () {
  it('initializes correct nft depositors', async function () {
    const {Game: g} = await setup();
    expect(
      await g.depositors('0x465DCa9995D6c2a81A9Be80fBCeD5a770dEE3daE')
    ).to.equal(true);
    expect(
      await g.depositors('0x426923E98e347158D5C471a9391edaEa95516473')
    ).to.equal(true);
    // expect(
    //   await g.depositors('0x63A556c75443b176b5A4078e929e38bEb37a1ff2')
    // ).to.equal(true);
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
    await expect(g.initEnd(Array(256).fill(0))).to.be.revertedWith(
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
