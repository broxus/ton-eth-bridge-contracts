pragma ton-solidity ^0.39.0;

import './IEvent.sol';

interface IProxy {
    function broxusBridgeCallback(
        IEvent.EthereumEventInitData eventData,
        address gasBackAddress
    ) external;
}
