import {HardhatRuntimeEnvironment} from 'hardhat/types';
import {DeployFunction} from 'hardhat-deploy/types';

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const {deployments, getNamedAccounts} = hre;
  const {deploy} = deployments;
  const {deployer} = await getNamedAccounts();
  // console.log('deploying from', deployer);
  await deploy('Game', {
    from: deployer,
    log: true,
    // ! this flag if enabled fails the onlyOwner tests
    deterministicDeployment: false,
  });
};
export default func;
func.tags = ['Game'];
