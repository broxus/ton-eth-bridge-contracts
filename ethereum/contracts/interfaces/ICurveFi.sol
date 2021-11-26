pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;


interface ICurveFi {
    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount,
        bool _use_underlying
    ) external payable returns (uint256);

    function remove_liquidity_one_coin(uint256 token_amount, int128 i, uint256 min_amount) external;

    function add_liquidity(
        uint256[3] calldata amounts,
        uint256 min_mint_amount,
        bool _use_underlying
    ) external payable returns (uint256);

    function add_liquidity(
        uint256[4] calldata amounts,
        uint256 min_mint_amount,
        bool _use_underlying
    ) external payable returns (uint256);

    function add_liquidity(
        uint256[2] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function add_liquidity(
        uint256[3] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    function add_liquidity(
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external payable;

    // crv.finance: Curve.fi Factory USD Metapool v2
    function add_liquidity(
        address pool,
        uint256[4] calldata amounts,
        uint256 min_mint_amount
    ) external;

    function calc_token_amount(
        uint256[3] tokens,
        bool is_deposit
    ) external returns (uint256);

    function calc_withdraw_one_coin(uint256 token_amount, int128 i) external returns (uint256);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external;

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external;

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function balances(int128) external view returns (uint256);

    function get_virtual_price() external view returns (uint256);
}
