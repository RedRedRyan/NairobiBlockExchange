**Nairobi Block Exchange (NBX) White Paper** 
The contracts are deloyed 
1. BlockExchangeFactory: 0xb0C3AcD5d1e89aCf92E2b760a00F4795b686517d
    - This is the factory contract that manages the creation of new exchange instances.
  2. BlockExchange: 0xaDEC20c5D695F0aeE06edF66E73Dd1E2Fa1a8552
    - This is the main exchange contract for "Example Company" with token symbol "EXC".
    - It's responsible for managing security tokens, dividends, and governance.
  3. SecurityToken: 0xd120E0C278d1b2aeE35495F94187D61F5229eD33
    - This is the ERC20 token representing "Example Company" shares.
    - Initial supply: 1,000,000 EXC (with 6 decimals)
    - Treasury wallet (0x949aab5677103F953C535D60e5eB9BC94bE19918) now holds all these tokens.
  4. NBXOrderBook: 0xf391EAd8312a21526cb12328e334B3525da603dc
    - This contract handles buy/sell orders for security tokens.
    - It includes matching orders, fee collection, and order management features.
  5. NBXLiquidityProvider: 0x7fDc918018ebF11749Df95467C98bdcEf17EF0FC
    - This contract provides incentives for market makers to add liquidity.
    - It allows users to lock collateral and earn rewards for providing liquidity.
  6. USDT Token Address: 0x000000000000000000000000000000000042ddf1
    - This is the token used for payments, fees, and dividends within the system.



## **1. Executive Summary**  
The Nairobi Block Exchange (NBX) is a blockchain-based SME stock exchange built on the Hedera Hashgraph network. It enables small and medium-sized enterprises (SMEs) to issue security tokens representing company shares, providing investors with access to fractional ownership and liquidity. NBX integrates smart contracts for governance, automated dividend payouts, and regulatory compliance, ensuring a secure, transparent, and efficient capital market for SMEs.

## **2. Introduction**  
### **2.1 The Problem Statement**  
Access to capital remains a significant challenge for SMEs, with traditional stock exchanges imposing high listing costs and strict regulatory requirements. As a result, many SMEs struggle to secure funding through equity markets, limiting their growth potential.

The general public also have a barrier of entry into investement are are there fore sidelined in nation building. 

By bringing more of the population into the investment space, we can help to build a more inclusive and equitable economy.

### **2.2 The Solution**  
NBX leverages blockchain technology to facilitate the issuance and trading of security tokens, democratizing access to investment opportunities while ensuring transparency, regulatory compliance, and security.

## **3. Technology Stack**  
- **Blockchain Infrastructure:** Hedera Hashgraph for fast, low-cost, and secure transactions.  
- **Security Tokens:** Hedera Token Service (HTS) for tokenized shares.  
- **Smart Contracts:** Enforce investor rights, dividend payouts, and governance.  
- **KYC/AML Compliance:** Identity verification and whitelisting of investors.  
- **Auditing & Regulatory Access:** Real-time financial data accessible by regulators.

## **4. User Roles & Flow**  
### **4.1 Individual Investors**  
- Sign up and complete KYC/AML verification.  
- Fund wallets with HBAR or stablecoins.  
- Browse and invest in tokenized SME shares.  
- Trade shares on the secondary market.  
- Receive dividends and participate in governance voting.

### **4.2 SACCOs & Institutions**  
- Conduct bulk investments in SME shares.  
- Manage portfolios with institutional-grade compliance.  
- Provide liquidity by trading shares on NBX.  
- Stake tokens for governance influence.

### **4.3 Regulators (Auditors)**  
- Access real-time blockchain transactions.  
- Verify financial disclosures from SMEs.  
- Ensure compliance with securities laws.  
- Monitor and flag suspicious activities.

### **4.4 Companies (SMEs)**  
- Register and verify company details.
- Issue security tokens representing shares.
- Manage shareholder communications and voting. 
- Distribute dividends via smart contracts.

## **5. Tokenomics & Governance**  
### **5.1 Token Supply & Distribution**  
- **Total Supply:** Determined per company listing (e.g., 1M tokens = 1M shares).
- **Founders’ Allocation:** Reserved portion for early investors and advisors.
- **Public Sale (IPO/STO):** Offering security tokens to investors.

### **5.2 Trading Fees & Platform Revenue**  
- **Transaction Fees:** Small percentage on every trade. 
- **Listing Fees:** Companies pay to list their tokens. 
- **Staking & Governance:** Investors can stake tokens for voting rights.

### **5.3 Liquidity Incentives**  
- **Market Makers:** Incentivized to provide liquidity. 
- **Automated Market Maker (AMM) Model:** Ensures dynamic token pricing.

## **6. Compliance & Regulation**  
- **KYC/AML Verification:** Investors must complete identity verification before trading. 
- **Regulatory Oversight:** On-chain compliance reporting for transparency. 
- **Investor Protection:** Smart contracts enforce compliance and prevent fraud.

## **7. Roadmap & Implementation Plan**  
### **Phase 1: Platform Development**  
- Develop NBX’s smart contracts and security token infrastructure. 
- Integrate KYC/AML solutions for investor verification. 
- Build an intuitive UI for trading and portfolio management.

### **Phase 2: Pilot Testing & Regulatory Compliance**  
- Partner with SMEs for test listings. 
- Work with regulators to refine compliance features. 
- Conduct security audits of the platform.

### **Phase 3: Public Launch & Market Expansion**  
- Onboard SMEs and investors. 
- Expand to institutional investors and SACCOs. 
- Implement liquidity pools and governance mechanisms.

## **8. Conclusion & Future Vision**  
NBX aims to become Africa’s premier blockchain-powered SME stock exchange, providing seamless access to capital markets while ensuring transparency and regulatory compliance. Through tokenized securities, automated governance, and decentralized trading, NBX will empower SMEs and investors alike, fostering economic growth and innovation.

---

