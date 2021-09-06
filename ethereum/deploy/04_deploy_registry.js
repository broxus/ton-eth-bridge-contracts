module.exports = async ({getNamedAccounts, deployments}) => {
  const { deployer } = await getNamedAccounts();
  
  const bridge = await deployments.get('Bridge');
  const vaultWrapper = await deployments.get('VaultWrapper');
  
  await deployments.deploy('Registry', {
    from: deployer,
    log: true,
    args: [
      bridge.address,
      vaultWrapper.address
    ]
  });
};

module.exports.tags = ['Deploy_Registry'];
