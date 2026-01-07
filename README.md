# Decentralized-Public-Key-Infrastructure #
## Automated Certificate Management Environment (ACME) Based on Blockchain ##

### 1. What is ACME
Launched by Let’s Encrypt Certificate Authority, ACME protocol aims to automate the certificate issuance process in Public Key Infrastructure. 

The key task of ACME is to verify requester’s control over the domain (server) through certain challenge. 

The figure below illustrates the typical HTTP challenge:
![alt text](path/to/your/image.png)

### 2. Problem of ACME
ACME requires trusted CA to perform the verification and issuance, CA is prone to single point of failure.

Moreover, the whole Let’s Encrypt project is sponsored mainly by U.S.-based companies as shown below. Potential political centralisation exists. 

![alt text](path/to/your/image.png)

### 2. Proposed solution: ACME based on blockchain
Here we introduce blockchain technologies to make the challenge process more decentralized and transparent.

An evm-based smart contract is constructed to function as Let’s Encrypt CA. It handles domain registration request, verifies domain ownership challenge, and records domain certification info.

![alt text](path/to/your/image.png)
