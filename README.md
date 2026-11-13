# Grip

**Trading op Hyperliquid, gewoon in de chart.** Een native macOS-app (SwiftUI + AppKit) die handelen op Hyperliquid snel en overzichtelijk maakt.

![Grip](Resources/AppIcon.png)

🎬 **Demo:** [docs/Grip-app-demo.mp4](docs/Grip-app-demo.mp4), een opname van de echte app (oefenmodus, live koersen), automatisch gemaakt op een Mac van GitHub Actions.

## Wat kan Grip

- **Orders slepen in de chart**: entry, stop-loss en take-profit zet je met de muis. Open orders en TP/SL van een positie verplaats je door de lijn te verslepen.
- **Positiegrootte op basis van risico**: kies hoeveel procent van je portfolio je maximaal wilt verliezen. Grip rekent grootte, hefboom, marge, R:R en een liquidatieschatting uit, inclusief fees.
- **Makkelijk (deels) sluiten**:
  - 25/50/75/100% met één klik (market).
  - Of sleep het oranje ✕ op de positielijn naar een prijs voor een limit close.
- **Trendlijnen**:
  - Tekenen met ⌥T.
  - Houd **⌘** ingedrukt om te snappen op open/high/low/close van een candle (body of wick).
  - Lijnen worden per markt bewaard en blijven staan als je van timeframe wisselt.
  - Selecteren, uiteinden verslepen, ⌫ = verwijderen. Rechtsklik voor verlengen of kleur.
- **Timeframes**: 1m · 5m · 15m · 1h · 4h · 1d · 1w (⌘1 t/m ⌘7).
- **Privacymodus** (⇧⌘H): verbergt alle bedragen en groottes, zodat je veilig een screenshot kunt delen. Percentages en prijzen blijven zichtbaar.
- **Tradehistorie**: afgeronde trades (van open tot volledig dicht), met entry, exit, netto PnL na fees, rendement, R-multiple en duur. Daarnaast winrate, profit factor en gemiddelde R.
- **Portfolio**: winst/verlies en accountwaarde in de tijd (24u, week, maand, alles), plus een curve van je cumulatieve gerealiseerde winst.
- **Oefenmodus**: handel met nepgeld tegen live koersen van Hyperliquid. Orders, fills, fees, historie en portfolio worden lokaal gesimuleerd. Geen wallet of sleutels nodig; aanzetten in Instellingen of in het welkomstscherm.
- **Veilig**:
  - Grip gebruikt een Hyperliquid **API-wallet**. Die kan handelen maar geen geld opnemen.
  - De key staat alleen in de macOS-sleutelhanger.
  - Standaard staat Grip op **testnet**.

## Installeren (zonder Xcode)

1. Ga naar **Actions** → de laatste geslaagde run van *Build Grip* → download het artifact `Grip-…zip`. Is er een release, dan staat de download onder **Releases**.
2. Pak uit en sleep **Grip.app** naar *Programma's*.
3. Eerste keer openen: **rechtsklik → Open**. Of ga naar *Systeeminstellingen → Privacy en beveiliging → Toch openen*. De app is niet door Apple genotariseerd, daarom vraagt macOS dit één keer.

## Eerste keer instellen

1. *Instellingen* (⌘,) → kies **Testnet** of **Mainnet**.
2. Vul het **adres van je wallet** in (alleen-lezen: saldo, posities, historie).
3. Maak op Hyperliquid een API-wallet aan (*More → API*) en plak de **private key van die API-wallet** in Grip. Gebruik nooit de key van je hoofdwallet.

## Sneltoetsen

| Actie | Toets |
|---|---|
| Nieuwe long / short | ⌥L / ⌥S |
| Order plaatsen | ⌘↩ |
| Trendlijn tekenen | ⌥T (houd ⌘ voor snap) |
| Timeframe | ⌘1 … ⌘7 |
| Traden / Historie / Portfolio | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Bedragen verbergen | ⇧⌘H |
| Vernieuwen | ⌘R |

Chart: slepen = schuiven, scrollen = zoomen, prijs-as slepen = schalen, dubbelklik op prijs-as = automatisch schalen.

## Ontwikkeling

- `Sources/GripCore`: platformonafhankelijke logica, getest op macOS en Linux:
  - Hyperliquid API- en WebSocket-client.
  - Ondertekening: msgpack, Keccak-256, EIP-712 en secp256k1.
  - Risicoberekening en tradehistorie.
  - Opslag van tekeningen.
- `Sources/Grip`: de macOS-app (SwiftUI, AppKit-chart, Swift Charts).
- `Tests/GripCoreTests`: o.a. handtekeningen die byte-voor-byte gelijk zijn aan de officiële `hyperliquid-python-sdk`.
- `docs/`: het klikbare prototype en de demovideo.

```bash
swift test                     # tests
./scripts/build-app.sh 0.1.0   # bouwt dist/Grip.app (macOS)
```

Elke push bouwt de app via GitHub Actions. Een tag `v1.2.3` maakt automatisch een release.
