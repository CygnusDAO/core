![image](https://github.com/CygnusDAO/core/assets/97303883/3d52ffa0-9613-4042-aa0d-8645d2acf5f0)

# Architecture

### CygnusTerminal.sol

- Contract where users can mint or redeem their ERC20 pool tokens. The borrowable contract mints CygUSD to users who can then redeem it for USDC, and the collateral contracts mints CygLP to users who can then redeem it for LPs.

### BorrowControl / CollateralControl

- Contract where admins can control pool variables according to governance

### BorrowModel / CollateralModel

- BorrowModel: Accrues interest rates and stores borrow information of each user

- CollateralModel: Prices the collateral (LP) in USDC and determines if a user has sufficient collateral to borrow

### BorrowVoid / Collateral Void

- Strategies for each pool token. Borrowable has a USDC strategy (for example deposit in Stargate and accrue STG) and the Collateral has an LP strategy (deposit in the DEX' farm)

### Borrow / Collateral

- Borrow: Liquidations and Borrows

- Collateral: Flash redeems and seizing of collateral
