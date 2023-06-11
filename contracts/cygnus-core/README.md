![image](https://github.com/CygnusDAO/core/assets/97303883/654c4f79-bb54-48ea-b703-97e320106032)

# Architecture

### CygnusTerminal.sol

- Contract where users can mint or redeem their ERC20 pool tokens. The borrowable contract mints CygUSD to users who can then redeem it for USDC, and the collateral contracts mints CygLP to users who can then redeem it for LPs.

### BorrowControl / CollateralControl

- Contract where admins can control pool variables according to governance

### BorrowModel / CollateralModel

- BorrowModel: Accrues interest rates and stores borrow information of each user

- CollateralModel: Prices the collateral (LP) in USDC and determines if a user has sufficient collateral to borrow

### Borrow / Collateral

- Borrow: Liquidations and Borrows

- Collateral: Flash redeems and seizing of collateral
