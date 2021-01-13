const logger = require('mocha-logger');
const { expect } = require('chai');
const freeton = require('ton-testing-suite');
const _ = require('underscore');

const BigNumber = require('bignumber.js');
BigNumber.config({ EXPONENTIAL_AT: 257 });


let Bridge;
let key;
let target;


const tonWrapper = new freeton.TonWrapper({
  network: process.env.TON_NETWORK,
  seed: process.env.TON_SEED,
});


describe('Test Bridge relay update', async function() {
  this.timeout(12000000);
  
  before(async function() {
    await tonWrapper.setup();
    
    Bridge = await freeton
      .requireContract(tonWrapper, 'Bridge');
    await Bridge.loadMigration();
    
    logger.log(`Bridge address: ${Bridge.address}`);
  
    key = await tonWrapper.ton.crypto.ed25519Keypair();
  });
  
  describe('Grant ownership', async function() {
    it('Initial check', async () => {
      target = {
        key: `0x${key.public}`,
        ethereumAccount: 123,
        action: true,
      };
      
      const keyOwnership = await Bridge.runLocal('getKeyStatus', { key: target.key });
      
      expect(keyOwnership).to.equal(false, 'Key should not have ownership');
    });
  
    it('Reject not enough times', async function() {
      const {
        bridgeRelayUpdateRequiredRejects,
      } = await Bridge.runLocal('getDetails');
  
      for (const keyId of _.range(bridgeRelayUpdateRequiredRejects.toNumber() - 1)) {
        await Bridge.run('updateBridgeRelays', {
          target,
          _vote: {
            signature: freeton.utils.stringToBytesArray(''),
          },
        }, tonWrapper.keys[keyId]);
      }
  
      const {
        confirmKeys,
        rejectKeys,
      } = await Bridge.runLocal('getBridgeRelayVotes', {
        target
      });
  
      expect(confirmKeys).to.have.lengthOf(0, 'Wrong amount of confirmations');
      expect(rejectKeys)
        .to
        .have
        .lengthOf(bridgeRelayUpdateRequiredRejects.toNumber() - 1, 'Wrong amount of confirmations');
    });
  
    it('Confirm enough times', async function() {
      const {
        bridgeRelayUpdateRequiredConfirmations,
      } = await Bridge.runLocal('getDetails');
      
      for (const keyId of _.range(bridgeRelayUpdateRequiredConfirmations.toNumber())) {
        await Bridge.run('updateBridgeRelays', {
          target,
          _vote: {
            signature: freeton.utils.stringToBytesArray('123'),
          },
        }, tonWrapper.keys[keyId]);
      }
      
      const {
        confirmKeys,
        rejectKeys,
      } = await Bridge.runLocal('getBridgeRelayVotes', {
        target
      });
  
      expect(confirmKeys).to.have.lengthOf(0, 'Wrong amount of confirmations');
      expect(rejectKeys).to.have.lengthOf(0, 'Wrong amount of confirmations');
  
      const keyOwnership = await Bridge.runLocal('getKeyStatus', { key: target.key });
  
      expect(keyOwnership).to.equal(true, 'Key should have ownership');
    });
  });
  
  describe('Remove ownership', async function() {
    it('Confirm enough times', async function() {
      target = {
        key: `0x${key.public}`,
        ethereumAccount: 123,
        action: false,
      };

      const {
        bridgeRelayUpdateRequiredConfirmations,
      } = await Bridge.runLocal('getDetails');
  
      for (const keyId of _.range(bridgeRelayUpdateRequiredConfirmations.toNumber())) {
        await Bridge.run('updateBridgeRelays', {
          target,
          _vote: {
            signature: freeton.utils.stringToBytesArray('123'),
          },
        }, tonWrapper.keys[keyId]);
      }
  
      const {
        confirmKeys,
        rejectKeys,
      } = await Bridge.runLocal('getBridgeRelayVotes', {
        target
      });
  
      expect(confirmKeys).to.have.lengthOf(0, 'Wrong amount of confirmations');
      expect(rejectKeys).to.have.lengthOf(0, 'Wrong amount of rejects');
  
      const keyOwnership = await Bridge.runLocal('getKeyStatus', { key: target.key });
  
      expect(keyOwnership).to.equal(false, 'Key should have ownership');
    });
  });
});
