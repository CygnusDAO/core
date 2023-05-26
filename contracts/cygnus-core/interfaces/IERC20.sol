// SPDX-License-Identifier: MIT
pragma solidity >=0.8.17;

/// @title IERC20
/// @author Paul Razvan Berg
/// @notice Implementation for the ERC-20 standard.
///
/// We have followed general OpenZeppelin guidelines: functions revert instead of returning
/// `false` on failure. This behavior is nonetheless conventional and does not conflict with
/// the with the expectations of ERC-20 applications.
///
/// Additionally, an {Approval} event is emitted on calls to {transferFrom}. This allows
/// applications to reconstruct the allowance for all accounts just by listening to said
/// events. Other implementations of the ERC may not emit these events, as it isn't
/// required by the specification.
///
/// Finally, the non-standard {decreaseAllowance} and {increaseAllowance} functions have been
/// added to mitigate the well-known issues around setting allowances.
///
/// @dev Forked from OpenZeppelin
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/token/ERC20/ERC20.sol
interface IERC20 {
    /*//////////////////////////////////////////////////////////////////////////
                                       ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to approve with the zero address as the owner.
    error ERC20_ApproveOwnerZeroAddress();

    /// @notice Thrown when attempting to approve the zero address as the spender.
    error ERC20_ApproveSpenderZeroAddress();

    /// @notice Thrown when attempting to burn tokens from the zero address.
    error ERC20_BurnHolderZeroAddress();

    /// @notice Thrown when attempting to transfer more tokens than there are in the from account.
    error ERC20_FromInsufficientBalance(uint256 senderBalance, uint256 transferAmount);

    /// @notice Thrown when spender attempts to transfer more tokens than the owner had given them allowance for.
    error ERC20_InsufficientAllowance(address owner, address spender, uint256 allowance, uint256 transferAmount);

    /// @notice Thrown when attempting to mint tokens to the zero address.
    error ERC20_MintBeneficiaryZeroAddress();

    /// @notice Thrown when attempting to transfer tokens from the zero address.
    error ERC20_TransferFromZeroAddress();

    /// @notice Thrown when the attempting to transfer tokens to the zero address.
    error ERC20_TransferToZeroAddress();

    /*//////////////////////////////////////////////////////////////////////////
                                       EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when an approval occurs.
    /// @param owner The address of the owner of the tokens.
    /// @param spender The address of the spender.
    /// @param value The maximum value that can be spent.
    event Approval(address indexed owner, address indexed spender, uint256 value);

    /// @notice Emitted when a transfer occurs.
    /// @param from The account sending the tokens.
    /// @param to The account receiving the tokens.
    /// @param amount The amount of tokens transferred.
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                 CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the remaining number of tokens that `spender` will be allowed to spend
    /// on behalf of `owner` through {transferFrom}. This is zero by default.
    ///
    /// @dev This value changes when {approve} or {transferFrom} are called.
    function allowance(address owner, address spender) external view returns (uint256);

    /// @notice Returns the amount of tokens owned by `account`.
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the number of decimals used to get its user representation.
    function decimals() external view returns (uint8);

    /// @notice Returns the name of the token.
    function name() external view returns (string memory);

    /// @notice Returns the symbol of the token, usually a shorter version of the name.
    function symbol() external view returns (string memory);

    /// @notice Returns the amount of tokens in existence.
    function totalSupply() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////////////////
                               NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Sets `value` as the allowance of `spender` over the caller's tokens.
    ///
    /// @dev Emits an {Approval} event.
    ///
    /// IMPORTANT: Beware that changing an allowance with this method brings the risk that someone may
    /// use both the old and the new allowance by unfortunate transaction ordering. One possible solution
    /// to mitigate this race condition is to first reduce the spender's allowance to 0 and set the desired
    /// value afterwards: https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    ///
    /// Requirements:
    ///
    /// - `spender` cannot be the zero address.
    ///
    /// @return a boolean value indicating whether the operation succeeded.
    function approve(address spender, uint256 value) external returns (bool);

    /// @notice Atomically decreases the allowance granted to `spender` by the caller.
    ///
    /// @dev Emits an {Approval} event indicating the updated allowance.
    ///
    /// This is an alternative to {approve} that can be used as a mitigation for problems described
    /// in {IERC20-approve}.
    ///
    /// Requirements:
    ///
    /// - `spender` cannot be the zero address.
    /// - `spender` must have allowance for the caller of at least `value`.
    function decreaseAllowance(address spender, uint256 value) external returns (bool);

    /// @notice Atomically increases the allowance granted to `spender` by the caller.
    ///
    /// @dev Emits an {Approval} event indicating the updated allowance.
    ///
    /// This is an alternative to {approve} that can be used as a mitigation for the problems described above.
    ///
    /// Requirements:
    ///
    /// - `spender` must not be the zero address.
    function increaseAllowance(address spender, uint256 value) external returns (bool);

    /// @notice Moves `amount` tokens from the caller's account to `to`.
    ///
    /// @dev Emits a {Transfer} event.
    ///
    /// Requirements:
    ///
    /// - `to` must not be the zero address.
    /// - The caller must have a balance of at least `amount`.
    ///
    /// @return a boolean value indicating whether the operation succeeded.
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice Moves `amount` tokens from `from` to `to` using the allowance mechanism. `amount`
    /// `is then deducted from the caller's allowance.
    ///
    /// @dev Emits a {Transfer} event and an {Approval} event indicating the updated allowance. This is
    /// not required by the ERC. See the note at the beginning of {ERC-20}.
    ///
    /// Requirements:
    ///
    /// - `from` and `to` must not be the zero address.
    /// - `from` must have a balance of at least `amount`.
    /// - The caller must have approved `from` to spent at least `amount` tokens.
    ///
    /// @return a boolean value indicating whether the operation succeeded.
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
