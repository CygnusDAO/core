![image](https://user-images.githubusercontent.com/97303883/175981010-f3e6cca7-c79a-48fa-b719-aa3daf7d4404.png)

# **Cygnus Protocol**

This repository contains the smart contracts source code and markets configuration for Cygnus. The repository uses Hardhat as the development environment for compilation, testing and deployment tasks.

# **What is Cygnus?**

Cygnus is a 100% on-chain stablecoin lending and leveraged LP farming protocol. It is a non-custodial liquidity market protocol, where users can participate as lenders by supplying DAI or as borrowers by supplying their LP Tokens. Lenders are able to provide DAI in individualized lending pools, earning passive income based on the lending pool's farm APY, while borrowers are able to supply their LP token and borrow DAI against it to farm greater rewards. As borrowers are borrowing a static value (DAI) against their LP tokens, they are essentially going long on their underlying assets.

Each lending pool is connected to a DEX (TraderJoe, Sushi, etc.). By depositing your LPs in Cygnus, rewards from the masterchef or any other liquidity mining program get reinvested automatically. Users also have the option to reinvest rewards manually if they wish to.

Cygnus uses its own oracle which returns the price of 1 LP token in DAI using Chainlink price feeds. By using third party reliable price feeds, the oracle calculates the [fair reserves](https://blog.alphaventuredao.io/fair-lp-token-pricing/) of each LP token. Anyone is free to use the Oracle for their own project or do their own implementation, if any doubts please reach out to the team so we can guide you.

# **Who is Cygnus for?**

1) **Liquidity Providers**. Any user who is already providing liquidity in any pair that is supported by Cygnus can benefit from the protocol, as they can now use their LP token to borrow a stable value (DAI) against it. Platforms like Compound Finance or Aave provide a similar service but for tokens only (i.e. deposit AVAX, borrow USDc). Cygnus is a protocol designed specifically for Liquidity Providers, as such we are unlocking liquidity and efficiency in DeFi. For example, an LP can decide to deposit their liquidity with Cygnus. The smart contracts then deposit the liquidity in the DEX auto-compounding rewards constantly. The user borrows 80% of their collateral in DAI to increase their position in the pool. If the LP Token's underlying assets increase in value, this strategy provides maximum profitability as they owe a static debt against appreciating assets, allowing them to borrow more or just keep farming with Cygnus.

2) **Stablecoin holders.** 
By lending stablecoins to borrowers in specific farms, lenders earn an APY in stablecoins that is more akin to the higher APY's found in DeFi across the more volatile assets. Each lending pool in Cygnus is connected to a DEX. As borrowers can farm greater amounts and earn more through higher liquidity mining rewards or trading fees, lenders are compensated with a cut of the yield. This is why Cygnus can provide higher stablecoin yields than some other borrowing/lending platforms who are isolated from DEXes with liquidity mining rewards/trading fees.

# **Protocol Features**

There are NO deposit fees, NO borrow fees or NO lending fees. Users are free to deposit and redeem their positions whenever they want at no cost aside from gas fees.

  ![image](https://user-images.githubusercontent.com/97303883/175662172-723323cb-1f04-46c5-afd6-66bc5ce84faf.png)
  
# **Cygnus architecture**

<h3> Overview </h3>

<p align="center">
<img src="https://user-images.githubusercontent.com/97303883/173560993-d84c9ff9-ced7-4d1c-a301-22dc46122e96.png" />
</p>

# <h3> All contracts </h3>

<p align="center">
<img src="https://user-images.githubusercontent.com/97303883/176365633-56aab2ad-fc31-408d-a419-4f2b2d83df93.png" width="90%" />
</p>
