# Architecture

- `Terminal.sol`: Vault token. Users deposit USDC and receive CygUSD (borrowable) or deposit LP and receive CygLP (collateral).
- `Control.sol`: Contract for important admin setter functions
- `Model.sol`: The interest rate model (borrowable) and collateralization model (collateral)
- `Void.sol`: The strategy of the stablecoin (borrowable) and the LP (collateral)
- `Borrow.sol`/`Collateral.sol`: Contracts to with the protocol (aside from depositing/withdrawing into the vault which is done at Terminal).

<div align="center">
<img src="https://github.com/CygnusDAO/core/assets/97303883/261acf25-fe2e-4434-9ca1-7a60aabcf922" />
</div>
