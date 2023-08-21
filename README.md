![photo_2023-08-18_15-35-29](https://github.com/CygnusDAO/core/assets/97303883/08f33a6e-010d-41e6-8902-04c5752e7284)

# **Cygnus Protocol**

This repository contains the smart contracts source code and markets configuration for Cygnus. The repository uses Hardhat as the development environment for compilation, testing and deployment tasks.

# **What is Cygnus?**

Cygnus is a 100% on-chain stablecoin lending and leverage trading protocol. It is a non-custodial liquidity market protocol, where users can participate as lenders by supplying USDC or as borrowers by supplying their liquidity tokens. Lenders are able to provide USDC in individualized lending pools, earning passive income based on the lending pool's farm APY, while borrowers are able to supply their LP token and borrow USDC against it or leverage their positions, increasing their earnings through higher trading fees or liquidity mining rewards. As borrowers are borrowing a static value asset (USDC) against their volatile liquidity, they are essentially going long on their underlying assets.

Each lending pool is connected to a DEX (UniswapV3, TraderJoe, Sushi, etc.). By depositing your LPs in Cygnus, rewards from the rewarder contract or any other liquidity mining program get reinvested automatically, decreasing their debt ratio on every reinvestment.
<br />
<br />
<p align="center">
<img src="https://user-images.githubusercontent.com/97303883/190871738-29fa7ef3-2090-4478-93ef-279eff1121b3.svg" width=40% />
</p>

<br />
Cygnus uses its own oracles which returns the price of 1 liquidity token in USDC using Chainlink price feeds. By using third party reliable price feeds, the oracle calculates the <a href="https://blog.alphaventuredao.io/fair-lp-token-pricing/">Fair Reserves</a> of each LP token. This technique is used to price liquidity tokens of protocols such as:

* Balancer
* UniswapV2
* UniswapV3

Anyone is free to use the Oracles for their own project or do their own implementation, if any doubts please reach out to the team so we can guide you.

The main benefit of our oracle is that it is **unaffected by impermanent loss**, making it easier for liquidity providers to track their earnings (since it's all priced in USDC).

Impermanent loss refers to a "situation in which the profit you gain from staking a token in a liquidity pool is less than what you would have earned just holding the asset" (https://www.ledger.com/academy/glossary/impermanent-loss). In other terms, impermanent loss affects individuals, not the price of the LP. Since the oracle prices the liquidity amount in USDc using the fair reserves mechanism, then redeeming the LP at any time means that the user would **always** receive the equivalent of USDC in the underlying LP assets. This greatly simplifies the borrowing and lending experience for all users.

# **Who is Cygnus for?**

1) **Liquidity Providers**. Any user who is already providing liquidity in any pair that is supported by Cygnus can benefit from the protocol, as they can now use their LP token to borrow against their liquidity. Platforms like Compound Finance or Aave provide a similar service but for tokens only (i.e. deposit ETH, borrow USDc). Cygnus is a protocol designed specifically for Liquidity Providers, as such we are unlocking liquidity and efficiency in DeFi. For example an LP decides to deposit their liquidity with Cygnus. The smart contracts then deposit the liquidity back in the DEX and any rewarder program the dex is offering. The user leverages 2x to increase their position in the pool. If the LP Token's underlying assets increase in value, this strategy provides maximum profitability as they owe a static debt against appreciating assets, allowing them to borrow more or just keep earning yield from trading fees/liquidity mining rewards with Cygnus.

2) **Stablecoin holders.** By lending stablecoins to borrowers in specific farms, lenders earn an APY in stablecoins that is more akin to the higher APY's found in DeFi across the more volatile assets. Each lending pool in Cygnus is connected to a DEX. The interest paid by borrowers to borrow this USDC is relative to the farm APY (which are usually higher). This is why Cygnus can provide higher stablecoin yields than some other borrowing/lending platforms who are isolated from DEXes with liquidity mining rewards/trading fees.

# **Protocol Features**

There are NO deposit fees, NO borrow fees or NO lending fees. Users are free to deposit and redeem their positions whenever they want at no cost aside from gas fees.

  <p align="center">
  <img src="https://user-images.githubusercontent.com/97303883/225300674-ec0c0260-ea1b-4dab-9654-e41fc7f72ca2.png" />
</p>
 
