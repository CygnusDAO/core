# **Scripts to quickly test a shuttle**

These are simple scripts which simulate a complete interaction with Cygnus using the CygnusAltairX router.

1) We deploy oracle, orbiters, factory (set orbiters) and deploy router
1) Lender deposits 25,000 DAI
2) Borrower deposits 100 LP Tokens of JOE/AVAX
3) Borrower leverages 6,040 DAI and Cygnus converts to LP and adds it back to rewards pool
4) Checks for reinvestment of masterchef rewards
5) Borrower deleverages everything
6) Lender redeems everything 
7) Borrower redeems everything
8) Check DAI balance of lender
9) Check LP balance of borrower
