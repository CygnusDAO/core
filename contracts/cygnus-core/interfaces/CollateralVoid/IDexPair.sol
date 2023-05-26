// SPDX-License-Identifier: Unlicensed
pragma solidity >=0.8.17;

/// @notice Interface for UniV2 pairs
interface IDexPair {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the number of decimal places used by the token.
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the total supply of the token.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the balance of the specified address.
     * @param owner The address to query the balance of.
     */
    function balanceOf(address owner) external view returns (uint256);

    /**
     * @dev Returns the amount of tokens that an owner has allowed a spender to spend.
     * @param owner The address that owns the tokens.
     * @param spender The address that is approved to spend the tokens.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Approves another address to spend the specified amount of tokens on behalf of the sender.
     * @param spender The address that is approved to spend the tokens.
     * @param value The amount of tokens to be approved for spending.
     */
    function approve(address spender, uint256 value) external returns (bool);

    /**
     * @dev Transfers tokens from the sender's account to the specified address.
     * @param to The address to which the tokens will be transferred.
     * @param value The amount of tokens to be transferred.
     */
    function transfer(address to, uint256 value) external returns (bool);

    /**
     * @dev Transfers tokens from one address to another.
     * @param from The address from which the tokens will be transferred.
     * @param to The address to which the tokens will be transferred.
     * @param value The amount of tokens to be transferred.
     */
    function transferFrom(address from, address to, uint256 value) external returns (bool);

    /**
     * @dev Returns the address of the first token in a pair.
     */
    function token0() external view returns (address);

    /**
     * @dev Returns the address of the second token in a pair.
     */
    function token1() external view returns (address);

    /**
     * @dev Returns the reserves of the token pair and the block timestamp of the last update.
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /**
     * @dev Burns liquidity tokens and removes the corresponding amount of tokens from the reserves.
     * @param to The address to which the underlying tokens will be sent.
     * @return amount0 The amount of the first token in the pair that was sent to the specified address.
     * @return amount1 The amount of the second token in the pair that was sent to the specified address.
     */
    function burn(address to) external returns (uint amount0, uint amount1);

    /**
     * @dev Returns metadata information about the token pair.
     * @return dec0 The number of decimal places used by the first token in the pair.
     * @return dec1 The number of decimal places used by the second token in the pair.
     * @return r0 The current reserve of the first token in the pair.
     * @return r1 The current reserve of the second token in the pair.
     * @return _stable Whether the token pair is stable (i.e., the ratio of reserves is always constant).
     * @return t0 The address of the first token in the pair.
     * @return t1 The address of the second token in the pair.
     */
    function metadata()
        external
        view
        returns (uint256 dec0, uint256 dec1, uint256 r0, uint256 r1, bool _stable, address t0, address t1);
}
