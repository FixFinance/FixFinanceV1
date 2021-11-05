## Project Setup
To use this project with truffle install truffle & ganache-cli with the following commands

$ npm i -g truffle

$ npm i -g ganache-cli

to utilise ganache it is usually best to have a folder somewhere outside the project named ganachelauncher, in this folder run the following command

$ echo "ganache-cli -s 0 -q" > ganachelauncher.sh && chmod +x ganachelauncher.sh

you can now run ganahcelauncher.sh to start ganache-cli with the same arguments used every time

once ganache is running you can run truffle commands from within the project such as

$ truffle test

or

$ truffle exec \<insert path to script file\>

hardhat is much more simple, with hardhat you don't need to run any external local instance of an ETH node.

# Fix Finance 
0.1.0 

Max Feldman 

mackx@protonmail.com 

August 2021 

### Abstract
This paper will outline the goals and structure of Fix Finance. Fix Finance aims to allow users to lock in a fixed rate on any yield bearing asset. Fix Finance will also allow users the ability to increase leverage to the yield generated by yield bearing assets. Users using Fix Finance that wish to lock in a fixed lending rate may buy ZCBs (Zero Coupon Bonds), other users that wish to increase leverage to yield may buy YTs (Yield Tokens). This paper will outline the mechanisms used within Fix Finance to construct a system that allows users to efficiently trade ZCB & YT. 
## Zero Coupon Bonds (ZCBs) 
ZCBs are a financial instrument which yield a specific amount of a specific asset on a specific date. ZCBs are sometimes referred to as STRIPs in traditional finance. ZCBs are the most fundamental building block of rate markets with which any type of cash flow structure may be constructed. It should be noted that as ZCBs approach their maturity date their value will approach parity with the payout asset. 
## Yield Tokens (YTs) 
YTs are an Ethereum native financial primitive which beget yield generated from an underlying asset up to a maturity date. If over the course of 1 year 1 aUSDC becomes 1.15 aUSDC 1 aUSDC YT will beget 0.15 aUSDC. Each Yield Token has a date at which it will no longer beget yield, at this date approaches the value of each YT approaches 0 
## ZCBs + YTs 
One key property of ZCBs and YTs is that if a given ZCB and a given YT have the same maturity date and payout the same asset the Net Present Value (NPV) of 1 ZCB + 1 YT will always be equal to 1 unit of the underlying asset. Likewise 1 unit of a given asset will have the same NPV as 1 ZCB + 1 YT. Thus we can design a smart contract system that receives an underlying asset and splits it into ZCBs and YTs. Also, at any time before the maturity date an equal number of ZCBs and YTs may be redeemed for the same amount of units of the underlying asset.
## Wrappers 
Fix Finance aims to be as generalizable as possible. This means that Fix Finance allows for ZCB & YT markets to be created for any interest bearing asset. In order to create ZCB & YT markets for an interest bearing asset, said asset must be put into a form that Fix can work with. We can wrap any asset in a wrapper contract that implements the IWrapper interface to make this happen. 
### Reward & Sub Account Mechanism
Not all yield bearing assets give off yield exclusively in the form of the same token, it is possible that there may be other assets which are yielded to holders of a specific asset. For example holders of aUSDC may not only earn more aUSDC but also wMATIC or stkAAVE. The reward and sub account mechanism handles this external asset yield. Holders of a wrapped asset will receive rewards in external assets when these external assets have been registered by the owner of the wrapper contract as such. All Fix Finance contracts that hold deposits for users should be registered with the sub account mechanism so that these deposits redirect the yield to the depositors. FixCapitalPool contracts will give off all external asset rewards to YT holders before the maturity date, and to ZCB holders after the maturity date.
### Wrapper Fees 
All Wrapper contracts have an owner, this owner has the right to set an annual fee percentage. The fee charged on the wrapper is not to exceed 20% of the total interest generated since the previous fee collection. The fee will be split 50-50 between the owner of the wrapper contract and the Fix Finance treasury. 
## Fix Capital Pools 
Fix Capital Pool (FCP) contracts allow for the creation of ZCBs &YTs on a wrapper asset with a specific maturity date. FCP contracts contain all the logic that handles minting and burning of ZCBs & YTs as well as distribution of funds after the maturity. FCPs may only be linked with contracts that implement the IWrapper interface. Anyone may deploy an FCP that is linked to any wrapper, the deployer of the FCP becomes its owner. The owner of an FCP has the ability to customise slippage and fee constants in AMMs that trade the ZCB & YT of that FCP. 
## Orderbook 
Fix Finance uses a custom on chain orderbook to trade ZCB against YT. Each orderbook contract is based upon a specific ZCB-YT pair originating from the same FixCapitalPool contract. The orderbook allows ‘makers’ to place limit orders to sell/buy a certain amount of ZCB/YT at a price determined by an implied MCR (maturity conversion rate, multiplier which is used to convert from dynamic to static amounts of the underlying asset). The orderbook also allows for ‘takers’ to fill the previously placed limit orders.
### Orderbook Fees 
Every time a limit order is filled a certain percentage of the trade is collected as a fee. Fees collected from the orderbook are split 50-50 between Fix Finance and the owner of the FixCapitalPool contract upon which the orderbook is based.

## Vault Factory 
Vault Factories are customisable margin systems that anyone may deploy and manage to allow users the functionality to borrow at a fixed rate by providing some asset as collateral against which they borrow and sell ZCB. For example: if a user wishes to supply WBTC and sell aUSDC ZCB against it they may open a vault with a Vault Factory that supports WBTC deposits and aUSDC borrowing to perform this action. Currently Vault Factories support the use of wrapped assets, YT and ZCB as collateral. In order for ZCB to be borrowed from a vault the owner of the FCP corresponding to the ZCB must whitelist the Vault Factory in question to directly mint ZCB against collateral. The major benefit of the Vault Factory is that it allows for users to borrow at a fixed rate. The Vault Factory may be used in a variety of ways to express opinions that were previously not possible to distill into a trade. 
### Stability Fees 
The owner of a Vault Factory may choose to employ the use of a stability fee, a stability in the context of Fix Finance Vault Factories are constant fee rates which are charged on borrowed assets. At any given time the total obligation of a vault is originalObligation * (StabilityFeeAPR + 1)^yearsOpen. All stability fees are to be split 50-50 between the owner of the Vault Factory and the Fix Finance treasury. 
### Time Spread Trading 
One extra use case that the Vault Factory supports is capital efficient trading of time spreads. This means that for a vault with collateral of ZCB on IWrapper A and maturity b from which ZCB on A at maturity c is borrowed, the collateral requirements will be based on the implied market rate of A between maturities b and c. For the purpose of time spread trading it makes much more sense to not charge a stability fee to allow for the development of an efficient market and yield curves. For this purpose specific Vault Factories may be created which charge no
stability fee and where only spread trading is supported (supplied and borrowed assets must be based on the same IWrapper). 
### 3 Types of Vault Factories 
There are 3 types of Vault Factories: 

1\. No Stability Fee (NSF) Vault Factory 

2\. Different Base Stability Fee (DBSF) Vault Factory 

3\. Same Base No Stability Fee (SBNSF) Vault Factory 

NSF Vault Factories are very simple in that there are no stability fees and vaults may be opened with any combination of the supported assets used as collateral and borrowed. DBSF Vault Factories are the only type of Vault Factory that have stability fees, the first two letters DB mean ‘different base’ this means that DBSF Vault Factories are meant for vaults where the IWrappers (or bases) of the supplied and borrowed assets are different, thus DBSF is not meant for time spread trades. SBNSF is like NSF in that no stability fee is charged; however any vault created in a SBNSF Vault Factory must have supplied and borrowed assets of the same base, thus only time spread trades are allowed in a SBNSF Vault Factory. Where the creator of a Vault Factory wants to charge stability fees on cross asset vaults and allow for time spread trading without stability fees it is very likely that they will create two Vault Factories, the first being a DBSF and the second being a SBNSF Vault Factory. 
### Flashloan Vault Management 
Vaults created in the vault factories may be managed with flashloans, this allows users to achieve their desired leverage in one transaction without having to continuously deposit collateral into vault, then borrow from vault, then deposit collateral, etc... 
## Vault Health Contract 
The Margin Manager makes use of a Vault Health contract which takes into account the value and rates of the assets in a vault to determine if the vault may be liquidated or not. The Vault Health contract is ownable and may be customised by the owner to support different assets. 
## Liquidations 
When the Vault Health Contract reports that a vault does not have sufficient collateral it may be liquidated. Depending on how low the collateral in the vault is relative to the obligation a vault will either be liquidated by auction or liquidated instantaneously. Auction liquidations find the bidder that will pay back the vault’s obligation in return for the smallest amount of collateral from the vault. A percentage of the surplus collateral remaining from the vault is taken as a liquidation fee and split 50-50 between the Vault Factory owner and the Fix Finance treasury, the rest of the surplus collateral is returned to the owner of the liquidated vault.
## Fixed Rate Borrowing 
Borrowing at a fixed rate may be achieved through the Margin Manager. Lets walk through the process a user would have to take to borrow DAI against WETH at a fixed rate for 2 years.
1\. Open vault that supplies WETH and borrows 2 year aDAI ZCBs 

2\. Supply WETH to vault 

3\. Borrow aDAI ZCBs from vault 

4\. Exchange aDAI ZCBs for current market value in aDAI 

5\. If the user wishes to have positive exposure to WETH and negative exposure to aDAI ZCBs, meaning no exposure to aDAI itself the user may sell their aDAI acquired in step 4 for WETH which may be resupplied to the vault. 

It should be noted that the fixed borrow rate that the user must pay is determined by the current market rate for 2 year DAI ZCBs versus DAI itself. This is because we know the current DAI value of the debt obligation as well as the DAI value of the debt obligation at maturity thus we can calculate the interest rate between now and then. Another thing that users wishing to borrow should keep in mind is that when trading ZCBs there is a component of rate risk. Recall the age old saying “rates up bonds down, rates down bonds up”. If the market rate of the ZCBs borrowed drops, the current value of the debt obligation increases. On the other hand if the market rate of the ZCBs borrowed rises, the current value of the debt obligation decreases. 
## Fee Capture & Revenue Share 
Fix Finance has fee capture at the following points: 

1\. AMMs & Orderbook

2\. Interest generated by Wrapper assets 

3\. ZCB & YT flashloans 

4\. Liquidation Fees 

5\. Vault Stability Fees 

All fees other than AMM fees are split 50-50 between the Fix Finance treasury and the owners of the various contracts within Fix Finance. 100% of the AMM fees (not distributed to LPs) are sent to the Fix Finance treasury. 
## Implications 
When looked at in aggregate the components of Fix Finance create a trustless and fully comprehensive rate trading experience for any and all yield generating crypto assets. Fix Finance is optimised for deep liquidity and highly efficient markets. Fix Finance will make possible many new strategies with sophistication ranging from simple fixed rate lending to highly complex quant rate trading strategies. THE FUTURE OF FINANCE IS HERE.

## Running locally

Below will run the react app and generate any new typechains

```
npm install
npx hardhat compile
npm start
```
