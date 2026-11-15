#if os(macOS)
// Dutch → English, generated from the texts in the app. {} is an inserted value; \n is a line break.
let translationsTSV = #"""
Je hebt al {} posities open; je budget is {} (Instellingen → Risico).	You already have {} positions open; your budget is {} (Settings → Risk).
Gebruikt {} marge, meer dan één vak ({} = 1/{} van je account).	Uses {} margin, more than one slot ({} = 1/{} of your account).
Totaal risico van al je stops wordt {}%, boven je max van {}%.	Total risk of all your stops becomes {}%, above your max of {}%.
Marge per positie: {} (1/{} van je account). {} van {} in gebruik.	Margin per position: {} (1/{} of your account). {} of {} in use.
risico {}%/{}%{}	risk {}%/{}%{}
Verlies als al je stops geraakt worden: {}	Loss if all your stops are hit: {}
Verlies bij alle stops: {}, plus onbekend risico: {} zonder stop	Loss at all stops: {}, plus unknown risk: {} without a stop
Max. gelijktijdige posities	Max. simultaneous positions
Marge-budget	Margin budget
Bij 3 posities mag één trade standaard hooguit ⅓ van je account als marge gebruiken. In Risico kiest Grip dan een hefboom die daarin past; in Bedrag staat "1 vak" in het lijstje. Grip waarschuwt als je erboven komt.	With 3 positions, one trade may use at most ⅓ of your account as margin by default. In Risk, Grip then picks a leverage that fits; in Amount the list has "1 slot". Grip warns when you go over it.
Max. totaal risico	Max. total risk
Uit	Off
{}% van je account	{}% of your account
Totaal risico	Total risk
Wat je verliest als al je stops tegelijk geraakt worden. Een positie zonder stop telt als onbekend risico en kleurt de statusbalk oranje.	What you lose if all your stops are hit at once. A position without a stop counts as unknown risk and turns the status bar orange.
{} omkeren naar {}?	Reverse {} to {}?
Sluit je {} van {} en opent een {} van dezelfde grootte (market, ≈ {}).\nJe stop en take-profits vervallen; zet daarna een nieuwe stop.	Closes your {} of {} and opens a {} of the same size (market, ≈ {}).\nYour stop and take-profits are cancelled; set a new stop afterwards.
Omkeren	Reverse
{} omgekeerd naar {}. Zet een nieuwe stop.	{} reversed to {}. Set a new stop.
Omkeren mislukt: {}	Reverse failed: {}
Omkeren mislukt	Reverse failed
Je zit {} in {}	You are {} in {}
Hyperliquid heeft één positie per munt. Een {}-order opent geen aparte trade, maar maakt je {} kleiner.\nVerkleinen of sluiten doe je in het tabblad Positie.	Hyperliquid has one position per market. A {} order does not open a separate trade but makes your {} smaller.\nReduce or close in the Position tab.
Naar Positie	To Position
Verkleinen (market)	Reduce (market)
Market bijkopen ({})	Market add ({})
Market {} openen	Open market {}
\nRisico tot je stop: {}{}	\nRisk to your stop: {}{}
\nResultaat van dit deel ≈ {}	\nResult of this part ≈ {}
Vul een grootte in.	Enter a size.
Koppel eerst een account (⇧⌘A), of zet de oefenmodus aan.	Connect an account first (⇧⌘A), or turn on practice mode.
E{} is kleiner dan $10, het minimum van Hyperliquid.	E{} is smaller than $10, the Hyperliquid minimum.
Hyperliquid vereist minimaal $10 per order.	Hyperliquid requires at least $10 per order.
Verkleinorder{} geplaatst: {}	Reduce order{} placed: {}
Take-profits worden geplaatst zodra je entry gevuld is (zie de lichte lijnen in de chart).	Take-profits will be placed as soon as your entry fills (see the faint lines in the chart).
Bijkoop-order{}	Add order{}
{} geplaatst · {}×	{} placed · {}×
{} geplaatst	{} placed
Order verstuurd.	Order sent.
Niet alles geplaatst: {}	Not everything was placed: {}
Order deels geweigerd	Order partly rejected
Order niet geplaatst	Order not placed
{} mislukt: {}	{} failed: {}
{} mislukt	{} failed
{}-trade gesloten: {} niet-gevulde entr{} geannuleerd	{} trade closed: {} unfilled entr{} cancelled
Grip stopt met bijwerken van {}	Grip stops updating {}
Controleer je stop-loss en take-profits zelf.	Check your stop-loss and take-profits yourself.
Entry annuleren	Cancel entry
Stop-loss plaatsen	Place stop-loss
Stop-loss bijwerken	Update stop-loss
Take-profits plaatsen	Place take-profits
Take-profit vergroten	Increase take-profit
Stop-loss op {} voor de hele positie	Stop-loss at {} for the whole position
{} take-profit{} geplaatst	{} take-profit{} placed
Stop-loss naar break-even: {}	Stop-loss to break-even: {}
Stop niet verplaatst: {}	Stop not moved: {}
E1 hier	E1 here
Entry hier	Entry here
Extra entry hier	Extra entry here
Stop-loss hier	Stop-loss here
Take-profit hier	Take-profit here
Bijkopen hier ({})	Add here ({})
Limit long hier	Limit long here
Limit short hier	Limit short here
Positie deels sluiten hier ({}%)	Partly close position here ({}%)
Een market {} zou je {} verkleinen in plaats van een nieuwe trade te openen. Wil je je positie sluiten?	A market {} would reduce your {} instead of opening a new trade. Do you want to close your position?
Hele positie sluiten	Close whole position
Geen chart om vast te leggen.	No chart to capture.
Screenshot bewaard{} · {}	Screenshot saved{} · {}
Screenshot niet bewaard: {}	Screenshot not saved: {}
Kies map	Choose folder
Traden	Trade
Historie	History
Risico	Risk
Bedrag	Amount
Positie	Position
$ marge	$ margin
$ positie	$ position
Verbinding met Hyperliquid weg	Connection to Hyperliquid lost
Grip probeert opnieuw te verbinden…	Grip is trying to reconnect…
Kon markten niet laden: {}	Could not load markets: {}
Kon koersen niet laden: {}	Could not load prices: {}
Dit account is alleen-lezen. Voeg een API-wallet toe in het accountscherm (⇧⌘A) om te handelen.	This account is read-only. Add an API wallet in the accounts window (⇧⌘A) to trade.
Oefenaccount gereset naar {}	Practice account reset to {}
Oefenmodus aan: live koersen, gesimuleerde orders.	Practice mode on: live prices, simulated orders.
Oefenmodus uit: je handelt op je echte account.	Practice mode off: you are trading on your real account.
{} verplaatst naar {}	{} moved to {}
{} geannuleerd	{} cancelled
Hele {}-positie sluiten?	Close whole {} position?
{}% van je {}-positie sluiten?	Close {}% of your {} position?
{} market · ≈ {}\nResultaat van dit deel ≈ {} na fees	{} market · ≈ {}\nResult of this part ≈ {} after fees
\nOpen TP- en SL-orders vervallen.	\nOpen TP and SL orders are cancelled.
Alles sluiten	Close all
Sluit {}%	Close {}%
Te kleine hoeveelheid om te sluiten.	Amount too small to close.
Sluitorder verstuurd.	Close order sent.
Sluiten mislukt	Close failed
Close-order: {}% @ {}	Close order: {}% @ {}
{} toegevoegd @ {} – sleep de lijn om aan te passen	{} added @ {} – drag the line to adjust
Close-order	Close order
VERKLEIN {}  ·  {}	REDUCE {}  ·  {}
TP{} · {}%  wacht op entry	TP{} · {}%  waiting for entry
SLUIT {}%	CLOSE {}%
{} {}  ·  gem. {}  ·  netto {}  ({})	{} {}  ·  avg {}  ·  net {}  ({})
BE {}  ·  break-even na fees{}	BE {}  ·  break-even after fees{}
SLUIT {}%  @ {}  {}	CLOSE {}%  @ {}  {}
Beweeg de muis over de chart en druk dan nog eens.	Move the mouse over the chart and press again.
Ververst	Refreshed
{} {} geopend	{} {} opened
{} {} bijgekocht	{} {} added
Gesloten	Closed
{}-trade gesloten ({})	{} trade closed ({})
Netto {}{} · fees {}	Net {}{} · fees {}
Trade gesloten: netto {}{}	Trade closed: net {}{}
Stop-loss {} geraakt	Stop-loss {} hit
Stop-loss geraakt: {} @ {}	Stop-loss hit: {} @ {}
Deel	Part
{} {} gevuld	{} {} filled
{} gesloten @ {} · {}	{} closed @ {} · {}
{} gevuld: {} @ {} · {}	{} filled: {} @ {} · {}
Resultaat {}	Result {}
Actief account: {}	Active account: {}
Account “{}” verwijderd (ook de sleutel uit de sleutelhanger).	Account “{}” removed (including the key in the keychain).
In het adresveld stond een private key in plaats van een adres. Grip heeft die verwijderd. Was het de sleutel van je hoofdwallet, zet je geld dan voor de zekerheid over naar een nieuwe wallet. Was het een API-wallet, maak dan een nieuwe aan.	The address field contained a private key instead of an address. Grip removed it. If it was the key of your main wallet, move your funds to a new wallet to be safe. If it was an API wallet, create a new one.
Vorige timeframe	Previous timeframe
Volgende timeframe	Next timeframe
Markt openen in nieuwe tab	Open market in new tab
Volgende markt	Next market
Vorige markt	Previous market
Markt {}	Market {}
Overzicht inklappen	Collapse overview
Overzicht posities en orders	Overview of positions and orders
Trendlijn stoppen	Stop trendline
Trendlijn	Trendline
Horizontale lijn op cursor	Horizontal line at cursor
Verticale lijn op cursor	Vertical line at cursor
Meten stoppen	Stop measuring
Meten	Measure
Magneet uit	Magnet off
Magneet aan	Magnet on
Geselecteerde lijn verwijderen	Delete selected line
Chart resetten	Reset chart
Vernieuwen	Refresh
Screenshot van chart	Screenshot of chart
Screenshotmap openen	Open screenshot folder
Nieuwe long	New long
Nieuwe short	New short
Order annuleren (ticket)	Cancel order (ticket)
Market long (Bedrag)	Market long (Amount)
Market short (Bedrag)	Market short (Amount)
Positie sluiten	Close position
Tabblad	Tab
Bedragen tonen	Show amounts
Bedragen verbergen	Hide amounts
Sneltoetsen	Keyboard shortcuts
Order geplaatst	Order placed
Entry gevuld (in trade)	Entry filled (in trade)
Take-profit geraakt	Take-profit hit
Stop-loss geraakt	Stop-loss hit
Trade gesloten	Trade closed
Order geweigerd of mislukt	Order rejected or failed
Verbinding weg / terug	Connection lost / back
Account toevoegen	Add account
Oefenmodus	Practice mode
Nepgeld, live koersen. Geen account nodig.	Fake money, live prices. No account needed.
Handelen	Trading
Alleen-lezen	Read-only
Actief account	Active account
Laatste test geslaagd	Last test passed
Laatste test mislukt	Last test failed
Nog niet getest	Not tested yet
Account koppelen	Connect account
Grip test de verbinding voordat je opslaat. Je sleutel komt alleen in de macOS-sleutelhanger.	Grip tests the connection before you save. Your key only goes into the macOS keychain.
Meer exchanges	More exchanges
Binnenkort	Coming soon
Netwerk	Network
Testnet (oefenen)	Testnet (practice)
Mainnet (echt geld)	Mainnet (real money)
Op Mainnet handel je met echt geld.	On Mainnet you trade with real money.
Adres van je hoofdwallet	Address of your main wallet
Het publieke adres waarmee je op Hyperliquid inlogt (begint met 0x). Daarmee ziet Grip je saldo, posities en historie.	The public address you log in with on Hyperliquid (starts with 0x). Grip uses it to see your balance, positions and history.
Dat was een private key, geen adres. Hij is uit dit veld gehaald. Een private key hoort alleen bij stap 4, en dan alléén die van een API-wallet.	That was a private key, not an address. It has been removed from this field. A private key only belongs in step 4, and only that of an API wallet.
Plak	Paste
API-wallet (om te kunnen handelen)	API wallet (to be able to trade)
Maak op Hyperliquid een API-wallet aan: **More → API → Generate**, kies een naam (bijv. Grip), klik **Authorize** en kopieer de **private key**. Een API-wallet kan handelen, maar **nooit geld opnemen**.	Create an API wallet on Hyperliquid: **More → API → Generate**, choose a name (e.g. Grip), click **Authorize** and copy the **private key**. An API wallet can trade, but **never withdraw funds**.
Open de API-pagina op Hyperliquid {}	Open the API page on Hyperliquid {}
Private key van de API-wallet (laat leeg voor alleen-lezen)	Private key of the API wallet (leave empty for read-only)
Hoort bij API-wallet {}	Belongs to API wallet {}
Dit is geen geldige private key (64 tekens, eventueel met 0x).	This is not a valid private key (64 characters, optionally with 0x).
Zonder sleutel: alleen-lezen. Je kunt de sleutel later toevoegen.	Without a key: read-only. You can add the key later.
Naam	Name
Bezig met testen…	Testing…
Test verbinding	Test connection
Opslaan en gebruiken	Save and use
Test eerst de verbinding	Test the connection first
Geldig adres	Valid address
Geen geldig adres	Not a valid address
Je hoofdadres is {}.	Your main address is {}.
Gebruik dit adres	Use this address
De API-wallet is goedgekeurd op {}.	The API wallet is authorized on {}.
Wissel naar {}	Switch to {}
Alles werkt. Je kunt opslaan en direct handelen.	Everything works. You can save and trade right away.
Verbonden (alleen-lezen). Je kunt opslaan; voeg later een API-wallet toe om te handelen.	Connected (read-only). You can save; add an API wallet later to trade.
Actief	Active
Gebruik dit account	Use this account
Gegevens	Details
Hoofdadres	Main address
Verbergen	Hide
Volledig tonen	Show in full
Adres gekopieerd	Address copied
Kopiëren	Copy
API-wallet	API wallet
Sleutel: ••••••••  (in de sleutelhanger, nooit zichtbaar)	Key: ••••••••  (in the keychain, never visible)
Geldig tot {}	Valid until {}
Geen: alleen-lezen	None: read-only
Private key van de nieuwe API-wallet	Private key of the new API wallet
Opslaan en testen	Save and test
Annuleer	Cancel
API-wallet toevoegen	Add API wallet
Sleutel vervangen	Replace key
Sleutel verwijderen	Remove key
Verbinding	Connection
Verbonden · handelen werkt	Connected · trading works
Verbonden · alleen-lezen	Connected · read-only
Er is een probleem	There is a problem
Test opnieuw	Test again
Laatst getest: {}	Last tested: {}
Account verwijderen	Remove account
“{}” verwijderen?	Remove “{}”?
Verwijderen	Remove
Het account en de API-wallet-sleutel worden uit Grip en de sleutelhanger verwijderd. Op Hyperliquid blijft de API-wallet bestaan; die kun je daar intrekken.	The account and the API wallet key are removed from Grip and the keychain. The API wallet still exists on Hyperliquid; you can revoke it there.
· saldo {}{}	· balance {}{}
Alle	All
Afgeronde trades	Closed trades
Periode	Period
7 dagen	7 days
30 dagen	30 days
90 dagen	90 days
Alles	All
Markt	Market
Exporteer deze trades als CSV	Export these trades as CSV
Netto PnL	Net PnL
Winrate	Win rate
Gem. R	Avg R
Netto = resultaat van de prijs − fees (in en uit) + funding. Gem. exit is volume-gewogen over alle TP's, stop en handmatige exits.	Net = price result − fees (in and out) + funding. Avg exit is volume-weighted over all TPs, stop and manual exits.
Koppel je account (⇧⌘A) om je tradehistorie te zien.	Connect your account (⇧⌘A) to see your trade history.
Historie laden…	Loading history…
Nog geen afgeronde trades in deze periode.	No closed trades in this period yet.
Gem. entry → exit	Avg entry → exit
In/uit	In/out
Bruto	Gross
Netto	Net
Duur	Duration
{} trades geëxporteerd	{} trades exported
Exporteren mislukt: {}	Export failed: {}
{} keer ingestapt, {} keer uitgestapt	Entered {} times, exited {} times
Toon in chart	Show in chart
Gepland risico {} · grootste positie {}	Planned risk {} · largest position {}
liquidatie	liquidation
{} u {} m	{} h {} m
{} d {} u	{} d {} h
Lengte	Length
Kleur	Color
Dikte	Width
Tonen	Show
Indicator verwijderd	Indicator removed
Eigen kleur	Custom color
Dikte {} pt	Width {} pt
Verleng naar links	Extend to the left
Verleng naar rechts (de toekomst in)	Extend to the right (into the future)
Verwijderen (⌫)	Delete (⌫)
Doorgetrokken	Solid
Gestreept	Dashed
Gestippeld	Dotted
Stijl	Style
Voorinstelling	Preset
Eigen	Custom
Stijgend	Rising
Dalend	Falling
Wicks tonen	Show wicks
Randen tonen	Show borders
Stijgende candles hol	Hollow rising candles
Rasterlijnen	Grid lines
Koop/verkoop-markeringen	Buy/sell markers
Alleen huidige trade	Current trade only
Laatste 7 dagen	Last 7 days
Laatste 30 dagen	Last 30 days
Map	Folder
Kies…	Choose…
Ook naar het klembord kopiëren	Also copy to the clipboard
Nieuwe lijnen naar rechts verlengen (de toekomst in)	Extend new lines to the right (into the future)
Magneet: altijd snappen op open/high/low/close	Magnet: always snap to open/high/low/close
Trendlijnen	Trendlines
Met ⌘ ingedrukt zet je de magneet tijdelijk om. Klik een lijn aan voor de werkbalk met kleur, dikte, stijl en verlengen.	Hold ⌘ to switch the magnet temporarily. Click a line for the toolbar with color, width, style and extend.
Standaardstijl herstellen	Restore default style
Rand	Border
Snel:	Quick:
Weergave	View
Bedragen verbergen voor screenshots (⇧⌘H)	Hide amounts for screenshots (⇧⌘H)
Instellingen	Settings
Instellingen (⌘,)	Settings (⌘,)
Let op	Attention
Begrepen	Got it
OEFENEN	PRACTICE
ACCOUNT KOPPELEN	CONNECT ACCOUNT
Verbonden: handelen werkt. Klik om accounts te beheren.	Connected: trading works. Click to manage accounts.
Verbonden, alleen-lezen (geen API-wallet). Klik om er een toe te voegen.	Connected, read-only (no API wallet). Click to add one.
Probleem met de verbinding: {}	Connection problem: {}
Oefenmodus: gesimuleerde orders. Klik om een account te koppelen.	Practice mode: simulated orders. Click to connect an account.
Koppel je Hyperliquid-account.	Connect your Hyperliquid account.
Markt openen in een nieuwe tab (⌘T)	Open market in a new tab (⌘T)
Zoek markt	Search market
Prijs	Price
Volume 24u	Volume 24h
Sorteer op {}	Sort by {}
Laatste uur: {} – {}	Last hour: {} – {}
Vol 1u	Vol 1h
{} {} in het laatste uur	{} {} in the last hour
Vol 24u	Vol 24h
Funding per uur. Positief: longs betalen shorts. Negatief: shorts betalen longs.	Funding per hour. Positive: longs pay shorts. Negative: shorts pay longs.
Waarde van alle open posities op deze markt	Value of all open positions in this market
 24u	 24h
Timeframe {} (⌘{} · of typ {} + ⏎ in de chart)	Timeframe {} (⌘{} · or type {} + ⏎ in the chart)
Aanwijzer (Esc)	Pointer (Esc)
Trendlijn (⌥T) · ⌘ = snap aan/uit	Trendline (⌥T) · ⌘ = snap on/off
Horizontale lijn: klik op een prijs · ⌥H = direct op de cursor	Horizontal line: click a price · ⌥H = right at the cursor
Meten: klik begin en eind · of ⇧-klik in de chart	Measure: click start and end · or ⇧-click in the chart
Indicator toevoegen	Add indicator
Wis alle lijnen voor {}	Clear all lines for {}
Lijnen wissen	Clear lines
Screenshot van de chart (⇧⌘S) – bewaard in {}	Screenshot of the chart (⇧⌘S) – saved in {}
Vernieuwen: opnieuw verbinden en alles herladen (⌘R)	Refresh: reconnect and reload everything (⌘R)
Typ 1 · 5 · 15 · 60 · 4h · D · W, dan ⏎	Type 1 · 5 · 15 · 60 · 4h · D · W, then ⏎
Timeframe kiezen zoals in TradingView	Choose timeframe like in TradingView
Vorige / volgende timeframe	Previous / next timeframe
Chart verschuiven	Scroll the chart
In- en uitzoomen	Zoom in and out
Chart resetten (zoom, positie, schaal)	Reset chart (zoom, position, scale)
Scrollen · knijpen	Scroll · pinch
Zoomen rond de cursor	Zoom around the cursor
Slepen op tijd-as / prijs-as	Drag on time axis / price axis
Horizontaal / verticaal schalen	Scale horizontally / vertically
Dubbelklik op een as	Double-click an axis
As terugzetten	Reset axis
Tekenen & meten	Drawing & measuring
Trendlijn aan/uit	Trendline on/off
Horizontale / verticale lijn op de cursor	Horizontal / vertical line at the cursor
Magneet aan/uit	Magnet on/off
⌘ ingedrukt	⌘ held
Snap tijdelijk omzetten	Switch snapping temporarily
⇧ + klik, klik	⇧ + click, click
Meten: %, candles, tijd	Measure: %, candles, time
Terug naar aanwijzer / annuleren	Back to pointer / cancel
Nieuwe long / short	New long / short
Snel: market long / short / sluiten	Quick: market long / short / close
Screenshot van de chart	Screenshot of the chart
Order plaatsen	Place order
Traden / Historie / Portfolio	Trade / History / Portfolio
Sluiten	Close
Geen open posities	No open positions
{} · gem. {} · netto na fees	{} · avg {} · net after fees
Sluit 50%	Close 50%
Sluit alles	Close all
Market order · huidig netto resultaat {}.	Market order · current net result {}.
Koppel je account (klik rechtsboven op ACCOUNT KOPPELEN of ⇧⌘A) om je portfolio te zien.	Connect your account (click CONNECT ACCOUNT at the top right or ⇧⌘A) to see your portfolio.
Accountwaarde	Account value
Rendement	Return
Open posities	Open positions
Winst / verlies ({})	Profit / loss ({})
Nog geen data.	No data yet.
Tijd	Time
Nul	Zero
Waarde	Value
Gerealiseerde winst per trade (cumulatief, na fees)	Realized profit per trade (cumulative, after fees)
Nog geen afgeronde trades.	No closed trades yet.
Cumulatief	Cumulative
Bedragen zijn verborgen – je kunt deze pagina veilig screenshotten.	Amounts are hidden – you can safely screenshot this page.
Meldingen	Notifications
· handelen	· trading
· alleen-lezen	· read-only
Geen account gekoppeld – je zit in de oefenmodus.	No account connected – you are in practice mode.
Nog geen account gekoppeld.	No account connected yet.
Account koppelen…	Connect account…
Accounts beheren…	Manage accounts…
Koppelen, testen en wisselen van account gaat in het accountscherm (⇧⌘A).	Connecting, testing and switching accounts is done in the accounts window (⇧⌘A).
Koersen	Prices
Koersen van	Prices from
Oefenmodus (papier-traden)	Practice mode (paper trading)
Startsaldo	Starting balance
Reset naar	Reset to
Handel met nepgeld tegen live koersen van Hyperliquid. Orders, fills, fees, historie en portfolio worden lokaal gesimuleerd.	Trade with fake money against live Hyperliquid prices. Orders, fills, fees, history and portfolio are simulated locally.
Standaard risico per trade	Default risk per trade
Max slippage market-orders	Max slippage market orders
Margin-modus	Margin mode
Bedragen verbergen (privacymodus)	Hide amounts (privacy mode)
Melding	Notification
Geluid	Sound
Geluid afspelen ({})	Play sound ({})
Meldingen en geluid	Notifications and sound
Meldingen verschijnen ook als Grip op de achtergrond staat; bij een fill springt het Dock-icoon. Werkt alleen zolang Grip draait. Toestemming voor meldingen regel je in Systeeminstellingen → Meldingen → Grip.	Notifications also appear when Grip is in the background; on a fill the Dock icon bounces. Only works while Grip is running. Allow notifications in System Settings → Notifications → Grip.
Bevestigen	Confirm
Vraag bevestiging bij market orders (openen en sluiten)	Ask for confirmation on market orders (open and close)
Menubalk	Menu bar
Toon positie en netto resultaat in de menubalk	Show position and net result in the menu bar
Welkom bij Grip	Welcome to Grip
Trading op Hyperliquid, gewoon in de chart.	Trading on Hyperliquid, right in the chart.
**Koppel je Hyperliquid-account**: kies Testnet of Mainnet, vul je wallet-adres in en (om te handelen) een API-wallet. Grip test alles voordat je opslaat.	**Connect your Hyperliquid account**: choose Testnet or Mainnet, enter your wallet address and (to trade) an API wallet. Grip tests everything before you save.
Of probeer eerst de **oefenmodus**: nepgeld, live koersen, geen sleutels nodig.	Or try **practice mode** first: fake money, live prices, no keys needed.
Klik **Long** of **Short**, sleep entry, stop-loss en take-profit in de chart en kies je risico. Klaar.	Click **Long** or **Short**, drag entry, stop-loss and take-profit in the chart and choose your risk. Done.
Zonder account kun je de charts, trendlijnen en de risicocalculator gewoon gebruiken.	Without an account you can still use the charts, trendlines and the risk calculator.
Probeer de oefenmodus	Try practice mode
Posities {}	Positions {}
gesorteerd op afstand tot de koers	sorted by distance to the price
klik een regel om naar die markt te gaan	click a row to go to that market
Geen open orders	No open orders
POSITIES	POSITIONS
geen	none
geen stop	no stop
Naar {}	To {}
· {} {} op {}%	· {} {} at {}%
Overzicht inklappen (⌘J)	Collapse overview (⌘J)
Overzicht van alle posities en orders (⌘J)	Overview of all positions and orders (⌘J)
⚠ geen stop	⚠ no stop
Helft sluiten (market)	Close half (market)
Sluit	Close
Hele positie sluiten (market)	Close whole position (market)
Omkeren: long ↔ short, zelfde grootte	Reverse: long ↔ short, same size
Stop naar break-even ({})	Stop to break-even ({})
Koers tussen je stop (links) en je doel (rechts); het streepje is break-even	Price between your stop (left) and your target (right); the tick is break-even
hele positie	whole position
Opslaan	Save
Wijzig	Edit
Prijs aanpassen (of sleep de lijn in de chart)	Edit price (or drag the line in the chart)
Naar de chart van {}	To the chart of {}
Annuleren	Cancel
Alle orders in {} annuleren	Cancel all orders in {}
{} u	{} h
gisteren	yesterday
{} dagen	{} days
Een order ligt dichtbij de koers	An order is close to the price
Tab sluiten	Close tab
Perps-saldo	Perps balance
Oefenaccount	Practice account
Je spot-saldo telt in een standaard account niet mee als marge voor perps. Zet het over naar perps, of zet Unified account aan op Hyperliquid.	Your spot balance does not count as margin for perps in a standard account. Transfer it to perps, or turn on Unified account on Hyperliquid.
Nieuwe long (⌥L)	New long (⌥L)
Nieuwe short (⌥S)	New short (⌥S)
Je kiest je max verlies en waar je stop staat; Grip rekent uit hoe groot de positie wordt.	You choose your max loss and where your stop is; Grip works out how big the position becomes.
Je kiest zelf hoeveel en met welke hefboom. Stop en take-profit zijn optioneel.	You choose how much and with which leverage. Stop and take-profit are optional.
Minder ▾	Less ▾
Meer ▸	More ▸
gespreid instappen · meerdere TP's	scaled entries · multiple TPs
Om te handelen: koppel een account met API-wallet (⇧⌘A).	To trade: connect an account with an API wallet (⇧⌘A).
Verkleinen met	Reduce by
Max verlies trade	Max loss trade
Max verlies	Max loss
Hefboom	Leverage
1 vak (1/{} van je account)	1 slot (1/{} of your account)
{}% van vrije marge	{}% of free margin
Marge	Margin
Positiewaarde	Position value
Grootte	Size
Invullen als marge, positiewaarde of aantal {}	Enter as margin, position value or number of {}
= positie {} · {} · marge {}	= position {} · {} · margin {}
Entry weghalen	Remove entry
Gelijk	Equal
Stop (hele positie)	Stop (whole position)
{}% vanaf {}	{}% from {}
Take-profit weghalen	Remove take-profit
Stop naar break-even na TP1	Stop to break-even after TP1
Resultaat van dit deel ≈	Result of this part ≈
Positie na	Position after
Hefboom · marge	Leverage · margin
Gem. entry bijkoop	Avg entry of add
Gem. entry als alles vult	Avg entry if all fill
Risico hele trade	Risk whole trade
Risico tot stop	Risk to stop
geen stop-loss	no stop-loss
Als alleen E1 vult	If only E1 fills
Winst · R:R	Profit · R:R
Liquidatie ≈	Liquidation ≈
prijs ⇄	price ⇄
Wissel tussen prijs en % vanaf de entry	Switch between price and % from the entry
Nieuwe order	New order
Verkleinen · {}	Reduce · {}
Bijkopen · {} {}	Add · {} {}
+ BIJ	+ ADD
Plaats	Place
Verklein (market)	Reduce (market)
Verklein	Reduce
Koop bij (market)	Add (market)
Plaats {} bijkoop-orders	Place {} add orders
Koop bij	Add
Plaats {} entries	Place {} entries
Plaats limit {}	Place limit {}
Open positie: naar het tabblad Positie	Open position: go to the Position tab
Open positie	Open position
 van portfolio	 of portfolio
netto na fees{}	net after fees{}
Grootte · hefboom	Size · leverage
Gem. entry	Avg entry
Liquidatie	Liquidation
Al gerealiseerd	Already realized
Zet de stop-loss op {}: deze trade kan dan niet meer verliezen (na fees).	Set the stop-loss at {}: this trade can then no longer lose (after fees).
Stop gaat naar break-even na de eerste TP	Stop moves to break-even after the first TP
Bijkopen	Add to position
Extra entry op deze positie. Je stop en take-profits groeien mee.	Extra entry on this position. Your stop and take-profits grow along.
Bijkopen…	Add…
Verkleinen	Reduce
Nu (market)	Now (market)
Op prijs…	At price…
Limit-order die je positie kleiner maakt; de lijn staat in de chart	Limit order that makes your position smaller; the line is in the chart
Geen open positie in {}.	No open position in {}.
Open een trade via Risico of Bedrag. Hier beheer je hem daarna: bijkopen, verkleinen, stop verplaatsen.	Open a trade via Risk or Amount. Here you manage it afterwards: add, reduce, move the stop.
NU	NOW
NA	AFTER
TAKE-PROFITS GROEIEN MEE	TAKE-PROFITS GROW ALONG
Nieuwe TP-ladder in plaats hiervan	New TP ladder instead
Tip: sleep een orderlijn in de chart om de prijs te wijzigen.	Tip: drag an order line in the chart to change the price.
Koersen laden…	Loading prices…
Geen koersdata	No price data
Verleng naar rechts	Extend to the right
Annuleer order	Cancel order
Stop-loss ligt aan de verkeerde kant van de entry.	Stop-loss is on the wrong side of the entry.
Geen risicoruimte meer: je huidige positie kost bij de stop al {} dollar. Zet je stop dichterbij of naar break-even.	No risk room left: your current position already loses {} dollars at the stop. Move your stop closer or to break-even.
Verkleinen kan tot maximaal je hele positie.	You can reduce by at most your whole position.
E{} is kleiner dan het Hyperliquid-minimum van $10 per order.	E{} is smaller than the Hyperliquid minimum of $10 per order.
Positie te klein voor de minimale ordergrootte.	Position too small for the minimum order size.
Geen vrije marge beschikbaar.	No free margin available.
Te weinig vrije marge voor deze grootte: minstens {}× nodig.	Not enough free margin for this size: at least {}× needed.
Lager dan je huidige hefboom ({}×). Hyperliquid staat verlagen met een open positie vaak niet toe.	Lower than your current leverage ({}×). Hyperliquid often does not allow lowering it with an open position.
Te groot: dit vraagt {}× hefboom, maximaal {}× toegestaan.	Too large: this needs {}× leverage, at most {}× allowed.
Risico {}% is meer dan je max van {}%.	Risk {}% is more than your max of {}%.
Let op: de geschatte liquidatieprijs ligt vóór je stop-loss.	Note: the estimated liquidation price is before your stop-loss.
Een of meer take-profits liggen aan de verkeerde kant van de entry.	One or more take-profits are on the wrong side of the entry.
Take-profits onder $10 (het minimum van Hyperliquid) worden samengevoegd: {} in plaats van {}.	Take-profits under $10 (the Hyperliquid minimum) are merged: {} instead of {}.
Hyperliquid gaf HTTP {}: {}	Hyperliquid returned HTTP {}: {}
Onverwacht antwoord van Hyperliquid ({}).	Unexpected answer from Hyperliquid ({}).
Stel eerst je wallet-adres en API-wallet in (Instellingen).	Set your wallet address and API wallet first (Settings).
Onbekende fout	Unknown error
Onvoldoende marge voor deze order.	Insufficient margin for this order.
Deze API-wallet is niet gekoppeld aan je account (of verkeerd netwerk gekozen).	This API wallet is not linked to your account (or the wrong network is selected).
Order te klein: minimaal $10.	Order too small: at least $10.
Reduce-only order zou je positie vergroten.	Reduce-only order would increase your position.
Geen directe match (te weinig liquiditeit binnen slippage).	No immediate match (too little liquidity within slippage).
Geen prijs voor {}.	No price for {}.
Order te klein.	Order too small.
Order bestaat niet meer.	Order no longer exists.
Verbinding met Hyperliquid {}	Connection to Hyperliquid {}
Account gevonden	Account found
API-wallet sleutel	API wallet key
API-wallet goedgekeurd voor dit account	API wallet authorized for this account
Dit is een private key, geen adres. Vul hier het publieke adres van je hoofdwallet in (0x + 40 tekens).	This is a private key, not an address. Enter the public address of your main wallet here (0x + 40 characters).
Eerst een geldig adres invullen.	Enter a valid address first.
Vul het adres van je hoofdwallet in.	Enter the address of your main wallet.
Eerst een adres invullen.	Enter an address first.
Geen geldig adres. Een adres begint met 0x en heeft daarna 40 tekens.	Not a valid address. An address starts with 0x followed by 40 characters.
api.hyperliquid{}.xyz bereikbaar	api.hyperliquid{}.xyz reachable
Kon Hyperliquid niet bereiken: {}	Could not reach Hyperliquid: {}
Geen verbinding.	No connection.
Dit is het adres van een API-wallet, niet van je hoofdaccount. Je hoofdadres is {}.	This is the address of an API wallet, not of your main account. Your main address is {}.
Gebruik eerst je hoofdadres.	Use your main address first.
Dit is een vault-adres. Gebruik het adres van je eigen wallet.	This is a vault address. Use the address of your own wallet.
Gebruik eerst je eigen adres.	Use your own address first.
Subaccounts worden nog niet ondersteund. Gebruik het adres van je hoofdaccount.	Subaccounts are not supported yet. Use the address of your main account.
{} open positie{}	{} open position{}
{}, maar zonder saldo op {}. Klopt het netwerk?	{}, but without balance on {}. Is the network right?
{} · {}. Je saldo staat op spot, niet op perps: zet USDC over naar perps (of zet Unified account aan) om te kunnen handelen.	{} · {}. Your balance is on spot, not perps: transfer USDC to perps (or turn on Unified account) to trade.
Kon het account niet ophalen: {}	Could not fetch the account: {}
Account niet gevonden.	Account not found.
Geen sleutel: alleen-lezen (saldo, posities, historie). Handelen kan niet.	No key: read-only (balance, positions, history). Trading is not possible.
Ongeldige sleutel. Plak de private key van je API-wallet (64 tekens, eventueel met 0x).	Invalid key. Paste the private key of your API wallet (64 characters, optionally with 0x).
Dit is de sleutel van je hoofdwallet. Gebruik die nooit in een app: maak een API-wallet aan (More → API).	This is the key of your main wallet. Never use it in an app: create an API wallet (More → API).
Hoort bij API-wallet {} · bewaard in sleutelhanger	Belongs to API wallet {} · stored in keychain
Goedgekeurd	Authorized
Goedgekeurd als “{}”	Authorized as “{}”
Deze API-wallet is verlopen. Maak een nieuwe aan op Hyperliquid.	This API wallet has expired. Create a new one on Hyperliquid.
 · nog {} dagen geldig	 · valid for {} more days
. Verleng hem binnenkort op Hyperliquid.	. Renew it soon on Hyperliquid.
Deze API-wallet hoort bij een ander account ({}).	This API wallet belongs to another account ({}).
Deze API-wallet is goedgekeurd op {}, niet op {}. Kies het andere netwerk.	This API wallet is authorized on {}, not on {}. Choose the other network.
Nog niet goedgekeurd op {}. Maak hem aan via More → API op Hyperliquid en klik op Authorize.	Not authorized yet on {}. Create it via More → API on Hyperliquid and click Authorize.
Kon de goedkeuring niet controleren: {}	Could not check the authorization: {}
Groen/rood	Green/red
Klassiek	Classic
Hol	Hollow
Monochroom	Monochrome
Blauw/oranje	Blue/orange
EMA (exponentieel gemiddelde)	EMA (exponential average)
SMA (gewoon gemiddelde)	SMA (simple average)
VWAP (volume-gewogen, per dag)	VWAP (volume-weighted, per day)
Standaard account	Standard account
Maand	Month
Automatisch (taal van je Mac)	Automatic (your Mac's language)
Taal	Language
Weergave en taal	Display and language
alles	all
deel	part
Verbonden	Connected
verbroken	disconnected
geopend	opened
1u	1h
Open int.	Open int.
SL hele trade  {}  ({})	SL whole trade  {}  ({})
Hele trade bij stop	Whole trade at stop
Hele trade bij stop: {} ({} van je account), fees en al gerealiseerde delen meegerekend	Whole trade at stop: {} ({} of your account), fees and already realized parts included
Gemiddelden	Moving averages
gem. entry	avg entry
"""#
#endif
