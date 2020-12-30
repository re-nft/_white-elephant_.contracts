import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts, network} = hre;
  if (network.name !== 'hardhat') return;
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();
  await deploy('TestGame', {
    from: deployer,
    log: true,
    // ! this flag if enabled fails the onlyOwner tests
    deterministicDeployment: false,
  });
};
export default func;
func.tags = ['TestGame'];
