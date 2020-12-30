import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts, network} = hre;
  if (network.name !== 'hardhat') return;
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();
  const g = await deploy('TestGame', {
    from: deployer,
    log: true,
    // ! this flag if enabled fails the onlyOwner tests
    deterministicDeployment: false,
  });
  await deploy('TestERC20', {
    from: deployer,
    log: true,
    args: [g.address],
    // ! this flag if enabled fails the onlyOwner tests
    deterministicDeployment: false,
  });
  await deploy('TestERC721', {
    from: deployer,
    log: true,
    // ! this flag if enabled fails the onlyOwner tests
    deterministicDeployment: false,
  });
};
export default func;
func.tags = ['TestGame'];
