# Architecture

Terminal - Vault token. Users deposit USDC and receive CygUSD (borrowable) or deposit LP and receive CygLP (collateral).
Control - Admin rights to set important parameters
Model - The interest rate model (borrowable) and collateralization model (collateral)
Void - The strategy of the stablecoin (borrowable) and the LP (collateral)
Borrow/Collateral - Main user contracts to interact with the protocol (aside from depositing/withdrawing into the vault which is done at `Terminal.sol`)

![core-flow-v2](https://github.com/CygnusDAO/core/assets/97303883/261acf25-fe2e-4434-9ca1-7a60aabcf922)
