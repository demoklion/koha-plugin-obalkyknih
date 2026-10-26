# Návod: Obálky knih v Koze

Plugin zobrazuje obálky, anotace a obsahy knih ze služby
[Obálky knih](https://www.obalkyknih.cz/) v online katalogu (OPAC)
i ve služebním rozhraní Kohy. Vyžaduje Kohu 24.11 nebo novější.

## 1. Instalace

1. V `koha-conf.xml` musí být povolené pluginy:
   `<enable_plugins>1</enable_plugins>`, potom restart Plack
   (`koha-plack --restart <instance>`).
2. Stáhněte soubor `.kpz` z
   [posledního vydání](https://github.com/demoklion/koha-plugin-obalkyknih/releases/latest).
3. Služební rozhraní → *Administrace → Správa pluginů → Nahrát plugin*.
4. Ještě jednou restartujte Plack, aby se načetla REST cesta pluginu.

## 2. Registrace na obalkyknih.cz

Služba obsluhuje jen registrované katalogy. Registrace je zdarma, pro
nekomerční knihovní použití. V účtu na <https://www.obalkyknih.cz/account>
přidejte (každou hodnotu zvlášť přes „Nová hodnota“):

- **URL adresa katalogu:** každou adresu, na které běží váš OPAC, např.
  `https://katalog.knihovna.cz`. Pokud má služební rozhraní jinou adresu
  nebo port (např. `:8443`), přidejte i tu.
- **IP adresa systému:** veřejnou IP adresu serveru Kohy.

Adresa katalogu slouží pro obrázky (prohlížeč čtenáře posílá hlavičku Referer),
IP adresa pro metadata, která získává server Kohy. Nové údaje mohou začít
platit až po schválení účtu správci Obálek knih.

Nevíte, jakou IP adresu server používá? V nastavení pluginu klikněte na
**Ověřit spojení**. Pokud Obálky přístup odmítnou, stránka ukáže IP adresu
a Referer, které služba viděla.

## 3. Nastavení

*Administrace → Správa pluginů → Obálky knih → Akce → Nastavit*

- **Online katalog / Služební rozhraní:** kde se obálky zobrazují.
- **Vlastní obálka knihovny má přednost:** když má záznam obálku nahranou
  v Koze, obálka z Obálek knih se nezobrazí. Výchozí: zapnuto.
- **Velikost obálek:** zvlášť pro výsledky hledání a pro detail záznamu.
- **Zobrazit anotaci / obsah:** na detailu záznamu.
- **Servery Obálek knih:** v pořadí pro záložní přepnutí; výchozí hodnoty
  není třeba měnit.
- **Sigla knihovny:** nepovinná, jen pro statistiky propagačních bloků.
- **Mezipaměť metadat:** výchozí 0 (vypnuto), dokud Obálky knih nepotvrdí,
  že je krátké ukládání v pořádku. Obrázky se neukládají nikdy.
- **Testovací režim:** jen pro vývojové instance s testovacím serverem.

## 4. Bezpečnostní hlavičky a soukromí

- Pokud posíláte hlavičku Content-Security-Policy, přidejte do `img-src`
  adresu `https://*.obalkyknih.cz`.
- Nenastavujte `Referrer-Policy: no-referrer`, jinak se obálky nenačtou.
- Text pro stránku o ochraně soukromí: [privacy.md](privacy.md).

Podrobnosti: [csp.md](csp.md).

## 5. Obálky ve vlastních blocích

Libovolný prvek s atributem `data-obalkyknih-biblionumber` (nebo
`data-obalkyknih-isbn`) dostane obálku, např. v bloku „Nově v knihovně“
v `OpacMainUserBlock`. Obsah prvku zůstane, pokud Obálky obálku nemají.
Příklad je v [README](../README.md#covers-anywhere-custom-blocks).

## 6. Když obálky nejsou vidět

1. **Ověřit spojení** v nastavení pluginu: odpovídají servery a je server
   registrovaný?
2. V prohlížeči otevřete vývojářské nástroje → Síť (Network): obrázky
   z `cache.obalkyknih.cz` se stavem 404 znamenají, že adresa katalogu není
   registrovaná (nebo chybí Referer).
3. Konzole: hláška `Obálky knih: not_registered` nebo `unavailable`
   znamená problém na straně serveru Kohy.
4. Obálky knih nemají obálky všech knih; u záznamu bez ISBN, ISSN, ČNB
   ani OCLC se nic nezobrazí.
