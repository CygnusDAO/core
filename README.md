![image](https://user-images.githubusercontent.com/97303883/175981010-f3e6cca7-c79a-48fa-b719-aa3daf7d4404.png)

# **Cygnus Protocol**

This repository contains the smart contracts source code and markets configuration for Cygnus. The repository uses Hardhat as the development environment for compilation, testing and deployment tasks.

# **What is Cygnus?**

Cygnus is a stablecoin lending and leveraged LP farming protocol. It is a non-custodial liquidity market protocol, where users can participate as lenders by supplying DAI or as borrowers by supplying their LP Tokens. Lenders are able to provide DAI in individualized lending pools, earning passive income based on the lending pool's farm APY, while borrowers are able to supply their LP token and borrow against it to farm greater rewards.

Each lending pool is connected to a DEX (TraderJoe, Sushi, etc.). By depositing your LPs in Cygnus, rewards from the masterchef or any other liquidity mining program get reinvested automatically. Users also have the option to reinvest rewards manually if they wish to.

Cygnus uses its own oracle which returns the price of 1 LP token in DAI using Chainlink price feeds. By using third party reliable price feeds, the oracle calculates the [fair reserves](https://blog.alphaventuredao.io/fair-lp-token-pricing/) of each LP token. Anyone is free to use the Oracle for their own project or do their own implementation, if any doubts please reach out to the team so we can guide you.

# <h3> Protocol Features

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
