# MemberPointsRewards

Är ett smart kontrakt i Solidity som fungerar som ett medlemsbaserat poängsystem. Vem som helst kan gå med som medlem, tjäna poäng, överföra poäng till andra medlemmar och lösa in poäng mot belöningar (T-shirt / VIP / Hoodie).

Kontraktet kan även ta emot ETH-donationer via `receive()`/`fallback()` och ägaren (owner) kan ta ut donationerna.

---

## Funktionalitet

### Medlemskap
- `join()` – gå med som medlem

### Poängsystem
- `earnPoints(amount)` – medlemmar kan tjäna poäng
- `transferPoints(to, amount)` – överför poäng till annan medlem
- `grantPoints(to, amount)` – owner kan tilldela poäng vid behov

### Belöningar
- `redeem(reward)` – löser in poäng mot en belöning
- `setRewardCost(reward, newCost)` – owner kan justera kostnaderna
- `rewardCost(reward)` – public getter 

### Donationer
- `receive()` och `fallback()` – kontraktet kan ta emot ETH
- `withdrawDonations(to)` – owner kan ta ut kontraktets ETH

---

## Projektstruktur

member-points/
├─ src/
│ └─ MemberPointsRewards.sol
├─ test/
│ └─ MemberPointsRewards.t.sol
├─ script/
│ └─ DeploySepolia.s.sol
└─ README.md

---

## Snabbstart (Foundry)

### Installera OpenZeppelin
```bash
forge install OpenZeppelin/openzeppelin-contracts
Bygg projektet

forge build
Kör tester

forge test
Coverage

forge coverage
Test coverage
Kontraktet src/MemberPointsRewards.sol har 100% coverage (Lines / Statements / Branches / Funcs) enligt forge coverage.

Notering: script/DeploySepolia.s.sol får 0% i coverage eftersom deploy-scripts inte körs av tester, vilket påverkar “Total” i rapporten.

Mitt senaste resultat (forge coverage):

Total: 
╭--------------------------------+-----------------+-----------------+-----------------+-----------------╮
| File                           | % Lines         | % Statements    | % Branches      | % Funcs         |
+========================================================================================================+
| script/DeploySepolia.s.sol     | 0.00% (0/7)     | 0.00% (0/6)     | 100.00% (0/0)   | 0.00% (0/1)     |
|--------------------------------+-----------------+-----------------+-----------------+-----------------|
| src/MemberPointsRewards.sol    | 100.00% (59/59) | 100.00% (67/67) | 100.00% (20/20) | 100.00% (10/10) |
|--------------------------------+-----------------+-----------------+-----------------+-----------------|
| test/MemberPointsRewards.t.sol | 100.00% (6/6)   | 100.00% (3/3)   | 100.00% (0/0)   | 100.00% (3/3)   |
|--------------------------------+-----------------+-----------------+-----------------+-----------------|
| Total                          | 90.28% (65/72)  | 92.11% (70/76)  | 100.00% (20/20) | 92.86% (13/14)  |
╰--------------------------------+-----------------+-----------------+-----------------+-----------------╯

src/MemberPointsRewards.sol: 100% på allt

Etherscan:
https://sepolia.etherscan.io/address/0x56b3376b7b1820f192ed2c8dfaf290769a4a6112

Gasoptimeringar / säkerhetsåtgärder (implementerade + motiverade)
Nedan är åtgärder som jag har implementerat direkt i koden för att förbättra säkerheten och/eller minska gaskostnader.

1) OpenZeppelin Ownable (säker access control)
Vad jag gjorde:
Jag använder Ownable för att begränsa admin-funktioner med onlyOwner:

grantPoints

setRewardCost

withdrawDonations

Varför det är viktigt:
Detta gör att inga andra användare kan manipulera systemets viktiga funktioner. Jag slipper även skriva egen access control-logik, vilket minskar risken för säkerhetsbuggar.

Effekt:
Stabilt och säkert behörighetssystem där bara owner kan utföra känsliga operationer.

2) OpenZeppelin ReentrancyGuard (skydd mot reentrancy vid ETH-uttag)
Vad jag gjorde:
Jag använder nonReentrant i withdrawDonations().

Varför det är viktigt:
När ett kontrakt skickar ETH med .call, kan mottagaren vara ett kontrakt som försöker göra återanrop och tömma kontraktet via reentrancy ( ett klassiskt säkerhetsproblem).

Effekt:
Skyddar ETH-uttag mot återinträdes-attacker. Detta är en tydlig säkerhetsförbättring.

3) Custom errors istället för revert strings (gasoptimering)
Vad jag gjorde:
Jag använder custom errors i vanliga felvägar:

NotMember()

ZeroAmount()

InsufficientPoints(have, need)

Varför det är viktigt:
Custom errors är billigare än revert strings när en transaktion revertar. I ett system där användare ofta kan göra felaktiga anrop ( 0 amount eller saknar medlemskap) sparar detta gas och gör felhantering tydligare.

Effekt:
Mindre gaskostnader på revert paths och tydligare feltyper i debugging.

4) Packad struct för medlemsdata (storage-optimering)
Vad jag gjorde:
Jag använder en packad struct för att spara medlemsdata:

struct Member {
    uint128 points;
    uint64 joinedAt;
    bool exists;
}
Varför det är viktigt:
Storage är dyrt på EVM. Genom att använda mindre datatyper packas datan mer effektivt och kan minska storage-förbrukningen.

Effekt:
Lägre gas när medlemsdata läses/skrivs upprepade gånger.

5) unchecked efter explicit kontroll (gasoptimering)
Vad jag gjorde:
I transferPoints och redeem gör jag först en kontroll att poäng räcker. Därefter subtraherar jag i ett unchecked-block.

Varför det är viktigt:
Solidity lägger annars automatiska overflow-checks. När jag redan vet att värdet är säkert kan jag hoppa över checken och spara gas.

Effekt:
Lägre gas i vanliga flows (transfer/redeem) utan att göra logiken osäker.

6) Public mappings (enkel läsbarhet via auto-getters)
Vad jag gjorde:
Jag valde att exponera members och rewardCost som public:

mapping(address => Member) public members;
mapping(Reward => uint128) public rewardCost;
Varför det är viktigt:
Det gör att man kan läsa information direkt via auto-generated getters (t.ex. i Remix/Etherscan). Det gör kontraktet enklare att verifiera och använda.

Effekt:
Bättre transparens och enklare användning utan att behöva skapa många extra getter-funktioner.

Solidity-element jag använder
Kontraktet innehåller:

Struct: Member

Enum: Reward

Mappings: members, rewardCost

Constructor

Modifier: onlyOwner och nonReentrant (via OpenZeppelin)

Custom errors + require + revert + assert

Events för viktiga händelser

receive() och fallback() för ETH

Viktiga filer
Smart contract: src/MemberPointsRewards.sol

Tester: test/MemberPointsRewards.t.sol

Deploy-script: script/DeploySepolia.s.sol