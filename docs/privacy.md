# Privacy note / Ochrana soukromí

Text you can paste into your library's privacy page (OPAC: *Nástroje → Nástroje
správy → Novinky / HTML přizpůsobení → OpacPrivacy*, or wherever you keep it).

## Česky

> **Obálky knih.** Náš online katalog zobrazuje obálky, anotace a obsahy knih ze
> služby Obálky knih (obalkyknih.cz), kterou spravují Jihočeská vědecká
> knihovna v Českých Budějovicích a Moravská zemská knihovna. Obrázky si načítá přímo váš prohlížeč ze
> serverů obalkyknih.cz. Ty se tak dozví vaši IP adresu, údaje o prohlížeči,
> adresu našeho katalogu a to, obálku které knihy načítáte. Do služby
> neposíláme žádné údaje o vás ani o vašich výpůjčkách.

## English

> **Book covers.** Our online catalogue shows book covers, annotations and
> tables of contents from Obálky knih (obalkyknih.cz), a service run by the
> South Bohemian Research Library in České Budějovice and the Moravian
> Library. Your browser loads these
> images directly from obalkyknih.cz servers, which therefore see your IP
> address, browser details, our catalogue's address and which book's cover is
> loaded. We do not send any data about you or your loans to the service.

## What the Koha server sends / Co posílá server Kohy

The plugin's server side sends Obálky only book identifiers (ISBN, ISSN, ČNB,
OCLC, ISMN), never anything about readers. If you enable the optional recommendations later,
check the Obálky terms again, because reader-based recommendations need loan data.

Server pluginu posílá Obálkám jen identifikátory knih (ISBN, ISSN, ČNB, OCLC,
ISMN), nikdy nic o čtenářích.
