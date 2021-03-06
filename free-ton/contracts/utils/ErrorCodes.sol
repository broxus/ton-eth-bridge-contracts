pragma ton-solidity ^0.39.0;
pragma AbiHeader expire;


contract ErrorCodes {
    // Bridge caller
    uint16 ADDRESS_IS_NOT_OWNER = 5001;

    // Bridge
    uint16 BRIDGE_NOT_ACTIVE = 5002;
    uint16 EVENT_CONFIGURATION_NOT_ACTIVE = 5003;
    uint16 KEYS_DIFFERENT_SHAPE = 5004;
    uint16 EVENT_CONFIGURATION_NOT_EXISTS = 5005;
    uint16 EVENT_CONFIGURATION_ALREADY_EXISTS = 5006;
    uint16 EVENT_CONFIGURATION_UPDATE_NOT_EXISTS = 5007;
    uint16 EVENT_CONFIGURATION_UPDATE_ALREADY_EXISTS = 5008;

    // Event configuration contract
    uint16 SENDER_NOT_BRIDGE = 5101;
    uint16 EVENT_BLOCK_NUMBER_LESS_THAN_START = 5102;
    uint16 EVENT_TIMESTAMP_LESS_THAN_START = 5103;

    // Event contract
    uint16 EVENT_NOT_IN_PROGRESS = 5201;
    uint16 SENDER_NOT_EVENT_CONFIGURATION = 5202;
    uint16 KEY_ALREADY_CONFIRMED = 5203;
    uint16 KEY_ALREADY_REJECTED = 5204;
    uint16 EVENT_NOT_CONFIRMED = 5205;
    uint16 TOO_LOW_MSG_VALUE = 5206;

    uint16 WRONG_TVM_KEY = 5301;
}
