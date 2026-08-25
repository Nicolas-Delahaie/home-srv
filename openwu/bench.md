# Benchmark MLX vs GGUF et gradient de qualité — 5 modèles de code sur MacBook Pro M1 Pro 32 Go

**Date :** 17 août 2026
**Machine :** MacBook Pro 18,3 — M1 Pro 10 cœurs (8P+2E), 32 Go unifiés, macOS Darwin 25.5.0
**Ollama :** 0.32.14 · **Plafond GPU :** ~24,5 Gio (`iogpu.wired_limit_mb=0` → 75 % de 32 Go)

---

## Résumé

**Backend pour le 35B : GGUF.** Non pas parce que MLX serait plus lent — à chaud les deux
sont à égalité stricte (344 contre 345 t/s de prefill) — mais parce que la build MLX pèse
23,7 Gio contre un plafond de 24,5 Gio. Elle ne tient pas, et le prix se paie à chaque
chargement : première inférence deux fois plus lente et pagination systématique.

**Côté qualité, il n'y a pas de classement dans ce rapport, et il ne faut pas en fabriquer
un.** Le protocole qualitatif est exploratoire : un seul tirage par couple modèle × prompt,
à `temperature 0.7`, sorties tronquées. Ce qu'on en tire, ce sont des _observations sur un
tirage_, pas une hiérarchie. La seule chose que cinq observations concordantes autorisent à
dire, c'est qu'aucun des cinq modèles n'a trouvé les points les plus fins (§8).

---

## 1. Périmètre

| Livrable                                       | Couverture                                           |
| ---------------------------------------------- | ---------------------------------------------------- |
| 1. Tableau modèle × prompt × métriques         | **Complet** — 5 modèles × 3 prompts                  |
| 2. Reproductibilité entre runs appariés        | **Complet** sur le couple 35B                        |
| 3. Mémoire à 24576 + saturation GPU            | **Complet** — les 5 modèles                          |
| 4. Jugement qualitatif sur les 3 prompts       | **Exploratoire seulement** — non calibré, voir §7    |
| 5. Verdict MLX/GGUF + classement des 5 modèles | Verdict **complet** · classement **non établi** (§9) |

**Modèles**

| Clé  | Modèle                                        | Architecture                        | Quant. | Poids   |
| ---- | --------------------------------------------- | ----------------------------------- | ------ | ------- |
| 4b   | `qwen3.5:4b-mlx`                              | dense 4,5B                          | nvfp4  | 4,0 Go  |
| 9b   | `qwen3.5:9b-mlx`                              | dense 9,4B                          | nvfp4  | 8,9 Go  |
| 27b  | `qwen3.8:27b-mlx`                             | dense 27B, attention linéaire + MTP | nvfp4  | 18,2 Go |
| 35bg | `oamazonasgabriel/qwen3.6-35b-a3b:q4-24gbGPU` | MoE 34,7B / 3B actifs               | IQ4_XS | 18,7 Go |
| 35bm | `qwen3.6:35b-mlx`                             | MoE 35,1B / 3B actifs               | nvfp4  | 21,9 Go |

**Prompts** (usage réel, stockés dans `~/bench/`) : `p1` refactoring d'une classe de
facturation Java legacy — **2 640 tokens** · `p2` diagnostic d'une stack Docker Compose /
Traefik v3 à trois symptômes — **2 033 tokens** · `p3` arbitrage d'architecture en français
sur un fil d'équipe — **1 443 tokens**. Les deux premiers sont dans la cible 2000–4000 ;
`p3` est en dessous, il ne doit pas servir à conclure sur le prefill.

---

## 2. Défauts du protocole initial, et corrections

Quatre problèmes auraient invalidé les mesures. Ils se reproduiront sur toute campagne
Ollama menée sur cette machine.

**2.1 — Deux serveurs Ollama écoutaient sur 11434.** L'app (IPv6 `*:11434`) et un
`ollama serve` manuel (IPv4 `127.0.0.1:11434`) étaient tous deux liés au port ; selon la
résolution IPv4/IPv6, le CLI et `ollama ps` pouvaient interroger deux serveurs différents.
_Correction :_ serveur de mesure dédié sur le port 11500, `OLLAMA_HOST` explicite partout.

**2.2 — `OLLAMA_CONTEXT_LENGTH` n'égalise pas le contexte.** Le modèle GGUF embarque
`PARAMETER num_ctx 16384` dans son Modelfile, qui **l'emporte sur la variable
d'environnement**. Le protocole d'origine aurait comparé un GGUF à 16384 contre des MLX à
24576 — soit l'allocation du cache KV, pas le backend.
_Correction :_ `options.num_ctx = 24576` passé à chaque requête via l'API, ce qui écrase le
Modelfile comme l'environnement. **Vérifié sur les 19 runs : `CONTEXT = 24576` partout.**

**2.3 — Asymétrie de configuration.** Le GGUF embarque un `SYSTEM` prompt et des `stop` que
les MLX n'ont pas ; sans neutralisation, la comparaison qualitative mesure le Modelfile
autant que le modèle. _Correction :_ `system` commun explicite, `think:false`,
`temperature 0.7`, `top_p 0.95`, `seed 42` pour tous.

**2.4 — `OLLAMA_NUM_PARALLEL` non contraint.** Ollama alloue `num_ctx × num_parallel` de
cache KV ; au-delà de 1, la colonne SIZE est faussée. _Correction :_ forcé à 1, avec
`OLLAMA_MAX_LOADED_MODELS=1`.

---

## 3. Protocole

Le plan initial prévoyait une matrice 5 × 3 en deux sens, soit une quarantaine de runs
enchaînés. **Abandonné :** un ordonnancement direct/inverse annule une dérive _linéaire_,
mais pas le throttling _absolu_ — dès que le SoC régule, tous les runs suivants sont
déprimés ensemble et l'ordre symétrique se contente de répartir équitablement des mesures
toutes fausses. Sans `sudo`, `powermetrics` est indisponible et `pmset -g therm` ne consigne
que des alertes : **le throttling n'est pas détectable programmatiquement ici**, il faut donc
rester sous le seuil par conception.

**Phase A — A-B-B-A (débit, conditions strictes).** 4 runs, `p1` seul, `num_predict=256`
identique pour les deux modèles, déchargement complet et 120 s de repos entre chaque run.
Swap relevé avant et après : toute croissance > 100 Mio invalide le run et arrête la
campagne.

**Phase B — qualité (contenu).** 15 runs, 5 modèles × 3 prompts, `num_predict=3072`,
boucle modèle-majeur (le modèle reste chargé pour ses 3 prompts : 5 chargements au lieu de
15, donc moins de temps et de chaleur).

Métriques lues dans la réponse de `POST /api/generate` (compteurs natifs, non reparsés).
`SIZE`/`CONTEXT`/`PROCESSOR` relevés via `GET /api/ps` pendant que la requête est en vol.

**Conditions d'alimentation** — à connaître avant toute comparaison croisée :

| Phase                  | Horaire             | Alimentation                           |
| ---------------------- | ------------------- | -------------------------------------- |
| A-B-B-A (4 runs)       | 13:57:40 → 14:05:10 | **batterie**, Low Power Mode désactivé |
| Qualité, run 1 (4B/p1) | 14:50:42            | **batterie**                           |
| Qualité, runs 2 à 15   | 14:56:36 → 15:33:47 | **secteur** (branché à 14:56:30)       |

Les 4 runs A-B-B-A sont donc homogènes entre eux. **Les débits de la phase B ne doivent pas
être comparés à ceux de la phase A** : alimentation différente et modèle déjà chaud.

---

## 4. Résultats — débit

### 4.1 A-B-B-A, 35B MLX (A) contre 35B GGUF (B), `p1`, à froid

| run | modèle | prefill   | génération | SIZE     | CONTEXT | PROCESSOR | load   | Δ swap       | validité     |
| --- | ------ | --------- | ---------- | -------- | ------- | --------- | ------ | ------------ | ------------ |
| 1   | A MLX  | 151,4 t/s | 35,19 t/s  | 23,7 Gio | 24576   | 100 % GPU | 11,4 s | +95 Mio      | OK           |
| 2   | B GGUF | 399,6 t/s | 33,27 t/s  | 18,1 Gio | 24576   | 100 % GPU | 8,9 s  | −8 Mio       | OK           |
| 3   | B GGUF | 350,6 t/s | 32,85 t/s  | 18,1 Gio | 24576   | 100 % GPU | 2,4 s  | −32 Mio      | OK           |
| 4   | A MLX  | 183,5 t/s | 34,97 t/s  | 23,7 Gio | 24576   | 100 % GPU | 11,1 s | **+478 Mio** | **INVALIDE** |

Le run 4 est écarté : croissance de swap de 478 Mio, au-delà du seuil posé avant lancement.
La campagne s'est arrêtée là, comme prévu.

**Reproductibilité (cible ±5 %)**

|            | MLX                        | GGUF                       | Cible            |
| ---------- | -------------------------- | -------------------------- | ---------------- |
| Génération | 35,19 / 34,97 → **0,6 %**  | 33,27 / 32,85 → **1,3 %**  | atteinte         |
| Prefill    | 151,4 / 183,5 → **19,2 %** | 399,6 / 350,6 → **13,1 %** | **non atteinte** |

Les débits de génération sont solides. **Les valeurs absolues de prefill sont à ±15 % et ne
doivent pas être citées au chiffre près.** La dérive n'est pas monotone (le MLX accélère
quand le GGUF ralentit), ce qui écarte la chaleur et désigne la pression mémoire.

### 4.2 Matrice complète, 5 modèles × 3 prompts (phase B, modèle chaud sauf `p1`)

| modèle | prompt | tokens in | prefill t/s | génération t/s | SIZE     | CONTEXT | PROCESSOR |
| ------ | ------ | --------- | ----------- | -------------- | -------- | ------- | --------- |
| 4b     | p1     | 2640      | 284,7       | 32,03          | 3,8 Gio  | 24576   | 100 % GPU |
| 4b     | p2     | 2033      | 284,7       | 30,83          | 4,0 Gio  | 24576   | 100 % GPU |
| 4b     | p3     | 1443      | 247,0       | 36,69          | 4,3 Gio  | 24576   | 100 % GPU |
| 9b     | p1     | 2640      | 169,2       | 20,86          | 8,4 Gio  | 24576   | 100 % GPU |
| 9b     | p2     | 2033      | 165,1       | 20,74          | 8,5 Gio  | 24576   | 100 % GPU |
| 9b     | p3     | 1443      | 174,0       | 21,72          | 8,9 Gio  | 24576   | 100 % GPU |
| 27b    | p1     | 2640      | 45,8        | 10,94          | 17,1 Gio | 24576   | 100 % GPU |
| 27b    | p2     | 2033      | 46,3        | 10,16          | 17,6 Gio | 24576   | 100 % GPU |
| 27b    | p3     | 1443      | 48,5        | 9,52           | 18,4 Gio | 24576   | 100 % GPU |
| 35bg   | p1     | 2645      | 355,0       | 31,90          | 18,1 Gio | 24576   | 100 % GPU |
| 35bg   | p2     | 2038      | 326,3       | 31,14          | 18,1 Gio | 24576   | 100 % GPU |
| 35bg   | p3     | 1448      | 364,1       | 32,75          | 18,1 Gio | 24576   | 100 % GPU |
| 35bm   | p1     | 2640      | 183,9       | 33,66          | 23,7 Gio | 24576   | 100 % GPU |
| 35bm   | p2     | 2033      | 344,8       | 34,04          | 20,6 Gio | 24576   | 100 % GPU |
| 35bm   | p3     | 1443      | 343,8       | 34,53          | 20,9 Gio | 24576   | 100 % GPU |

**Le 27B dense est le plus lent de tous** : 10,9 t/s en génération et 46 t/s en prefill,
soit trois fois moins que les MoE 35B. Logique — un dense active ses 27 milliards de
paramètres à chaque token, le MoE seulement 3 milliards. **Ses 27B ne s'achètent qu'au prix
d'une lenteur qui le rend pénible en usage interactif.**

### 4.3 Correction importante : le prefill du 35B MLX

En comparant le premier run après chargement aux suivants :

| modèle      | prefill à froid | à chaud   | ratio     |
| ----------- | --------------- | --------- | --------- |
| 4b MLX      | 284,7           | 265,9     | ×0,93     |
| 9b MLX      | 169,2           | 169,5     | ×1,00     |
| 27b MLX     | 45,8            | 47,4      | ×1,03     |
| 35b GGUF    | 355,0           | 345,2     | ×0,97     |
| **35b MLX** | **183,9**       | **344,2** | **×1,87** |

**Ce n'est pas un effet MLX** : les trois autres modèles MLX ne montrent rien. C'est propre
au 35B MLX, seul modèle à frôler le plafond mémoire. **À chaud, il fait 344,2 t/s contre
345,2 pour le GGUF — strictement à égalité.**

Interprétation : le prefill du MLX n'est pas intrinsèquement lent, il est **ralenti parce
que le modèle ne tient pas**. La première inférence se déroule pendant que macOS récupère de
la mémoire, d'où les +95 et +478 Mio de swap observés en phase A. Son SIZE retombe d'ailleurs
de 23,7 à 20,6 Gio après le premier run.

Le protocole A-B-B-A déchargeait avant chaque run : il n'a donc mesuré **que le chemin à
froid**. Appui : 3 mesures à froid indépendantes (151,4 / 183,5 / 183,9) contre 2 à chaud
(344,8 / 343,8).

---

## 5. Mémoire et saturation GPU

**`PROCESSOR = 100 % GPU` sur les 19 runs, tous modèles confondus.** Ollama n'a jamais
réparti de couches sur le CPU. Le débordement, quand il a lieu, se manifeste en pagination,
pas en offload.

Empreinte au chargement à froid, contexte 24576 :

| modèle   | SIZE à froid | marge sous 24,5 Gio | croissance sur 3 prompts   | swap               |
| -------- | ------------ | ------------------- | -------------------------- | ------------------ |
| 4b       | 3,8 Gio      | 20,7 Gio            | 3,8 → 4,3 Gio              | —                  |
| 9b       | 8,4 Gio      | 16,1 Gio            | 8,4 → 8,9 Gio              | —                  |
| 27b      | 17,1 Gio     | 7,4 Gio             | 17,1 → 18,4 Gio            | —                  |
| **35bg** | **18,1 Gio** | **6,4 Gio**         | **18,1 → 18,1 Gio (figé)** | −8 / −32 Mio       |
| **35bm** | **23,7 Gio** | **0,8 Gio**         | 23,7 → 20,9 Gio            | **+95 / +478 Mio** |

Deux enseignements structurels :

**Le GGUF est le seul à empreinte figée.** llama.cpp préalloue tout le cache KV au
chargement : 18,1 Gio, invariant quels que soient les prompts. Tous les MLX font croître
leur cache à la demande. Conséquence pratique : **le GGUF est prévisible dès le chargement,
un MLX peut dépasser son budget en cours de session** — d'autant plus dangereux qu'il tient
au départ.

**Le 35B MLX ne tient pas à 24576 tokens sur 32 Go.** 0,8 Gio de marge, pagination à chaque
chargement. Ce n'est pas un artefact de mesure, c'est sa condition d'exploitation. Relever
`iogpu.wired_limit_mb` (commande `sudo`, non exécutée) changerait la donne et mériterait
d'être retesté si le MLX reste souhaité.

---

## 6. Verdict backend : GGUF

| critère               | MLX          | GGUF      | avantage       |
| --------------------- | ------------ | --------- | -------------- |
| Génération            | 35,08 t/s    | 33,06 t/s | MLX, +6,1 %    |
| Prefill à chaud       | 344,2 t/s    | 345,2 t/s | **égalité**    |
| Prefill à froid       | 183,9 t/s    | 355,0 t/s | GGUF, ×1,9     |
| Empreinte à 24576     | 23,7 Gio     | 18,1 Gio  | GGUF, −5,6 Gio |
| Marge sous plafond    | 0,8 Gio      | 6,4 Gio   | GGUF           |
| Prévisibilité mémoire | croissante   | figée     | GGUF           |
| Pagination            | systématique | aucune    | GGUF           |

> **Recommandation : `oamazonasgabriel/qwen3.6-35b-a3b:q4-24gbGPU` (GGUF IQ4_XS).**

Le raisonnement n'est **pas** « MLX est plus lent » — à chaud, les deux backends sont à
égalité de prefill et MLX mène même de 6 % en génération. Le raisonnement est : **sur 32 Go,
la build MLX ne rentre pas.** Elle occupe 97 % du budget GPU, pagine à chaque chargement, et
sa première inférence en paie le prix (×1,9 sur le prefill). Avec un `keep_alive` de 5
minutes, chaque reprise de session après une pause repasse par ce chemin à froid.

Le MLX redeviendrait candidat sur une machine à 64 Go, ou après relèvement du plafond GPU —
et il serait alors probablement le meilleur choix, vu son avantage en génération.

---

## 7. Qualité — méthode, et pourquoi elle ne permet pas de classer

Chaque sortie a été confrontée à une **vérité terrain** : la liste des défauts réellement
présents dans le code fourni (13 points pour `p1`, 10 pour `p2`, 8 pour `p3`).

> **Avertissement — ce protocole qualitatif n'est pas calibré.** Il produit des
> illustrations, pas des mesures. Quiconque en tire un classement de modèles dépasse ce que
> les données autorisent.

Quatre défauts, cumulatifs :

**Un seul tirage par cellule.** 15 sorties, une par couple modèle × prompt, à
`temperature 0.7` avec un seed unique. Aucune variance intra-modèle n'est observable, donc
aucun écart inter-modèles n'est attribuable au modèle plutôt qu'au tirage. Il faudrait 5 à
10 tirages par cellule pour commencer à trancher.

**Le comptage de motifs récompense la mention, pas le raisonnement.** Il a produit un
résultat invraisemblable — le 4B à égalité avec le 35B GGUF — et au moins un faux positif
vérifié à la lecture : le 4B crédité d'avoir identifié le problème de réseau alors que le
terme apparaissait dans un paragraphe sans rapport. Les pourcentages de §8 ne doivent pas
être lus comme un score.

**La troncature à 3072 tokens pénalise les verbeux.** Un modèle qui développe longuement
chaque point couvre mécaniquement moins d'items de la grille avant d'être coupé. Le comptage
mesure donc en partie l'ordre de priorisation et la concision, pas la connaissance.

**La lecture de contrôle est elle-même partielle.** Elle a porté sur un symptôme d'un
prompt (§8), choisi parce qu'il discriminait — donc sélectionné après coup. C'est utile pour
illustrer un mode d'échec, pas pour établir un niveau.

Ce que ce protocole autorise malgré tout : constater qu'un modèle **peut** produire une
fabulation (§8), et constater qu'un point n'a été trouvé par **aucun** des cinq — cinq
observations concordantes valant mieux qu'une.

---

## 8. Qualité — le test qui discrimine

Le symptôme 2 du prompt Traefik (un `404` sur `api.acme.fr/v1/health`) s'est révélé le
meilleur discriminant de toute la campagne. **Cause réelle :** le service `api` n'est que sur
le réseau `backend`, alors que Traefik n'observe que le réseau `web`
(`--providers.docker.network=web`). Il ne peut donc pas créer de route utilisable.

| modèle   | diagnostic                                                            | verdict                               |
| -------- | --------------------------------------------------------------------- | ------------------------------------- |
| **35bg** | `api` absent du réseau `web`, Traefik ne peut pas l'atteindre         | **correct**                           |
| 27b      | « la syntaxe `&&` n'est pas supportée par Traefik »                   | faux, et `&&` est la syntaxe correcte |
| 35bm     | le middleware `cors` bloquerait la requête                            | faux                                  |
| 9b       | trois hypothèses empilées, conflit de priorité inventé                | faux, et sans conclusion              |
| 4b       | cache persisté « dans la mémoire du kernel `net.core.netdev_change` » | fabulation complète                   |

**Un seul modèle sur cinq a résolu ce diagnostic.** Et le 35B GGUF est aussi le seul à
raisonner à voix haute en éliminant explicitement ses fausses pistes, puis à nuancer son
propre verdict en notant qu'un `502` serait plus attendu qu'un `404`. C'est la différence
entre un modèle qui cherche et un modèle qui affirme.

Deux pièges Traefik n'ont été trouvés par **aucun** modèle : le suffixe `@file` requis pour
référencer depuis des labels Docker un middleware défini en fichier dynamique, et
l'échappement `$$` du hash `$apr1$` en Docker Compose. Côté Java, aucun n'a relevé le calcul
d'ancienneté en `/365` ignorant les bissextiles ni le `rs2.next()` non vérifié. **C'est le
plafond commun de ces cinq modèles.**

---

## 9. Observations qualitatives — sans classement

**Aucun ordre de mérite n'est proposé ici.** Les éléments ci-dessous décrivent ce qu'a fait
chaque modèle sur un tirage. Un second tirage pourrait les réordonner.

`35bg` **35B GGUF** — seul à résoudre le symptôme 2 sur ce tirage. Écarte explicitement ses
fausses pistes avant de conclure et nuance lui-même son verdict. C'est le comportement le
plus intéressant observé, mais une occurrence ne fait pas une propriété.

`27b` **27B MLX** — meilleure analyse du symptôme 1 des cinq : identifie la collision de nom
de _service_ et en déduit correctement le round-robin entre conteneurs. Correct sur le
conflit ACME. Une affirmation fausse et assurée sur `&&`. **Son vrai handicap n'est pas
qualitatif mais mesuré : 10 t/s, trois fois plus lent que le 35B GGUF** — ça, c'est solide.

`35bm` **35B MLX** — correct sur le conflit ACME, structure et français corrects, en retrait
sur le symptôme 2. Le choix face au GGUF ne se joue pas là mais sur la mémoire (§6).

`4b` **4B MLX** — trouve le routeur dupliqué, structure honorable. A produit une fabulation
caractérisée : un registre kernel `net.core.netdev_change` qui n'existe pas, présenté comme
mécanisme explicatif. **C'est une occurrence vérifiée, pas un taux** — elle prouve que le
modèle peut le faire, pas à quelle fréquence.

`9b` **9B MLX** — sur ce tirage, obtient moins que le 4B (16/31 contre 20/31) et empile les
hypothèses sans trancher.

> **Sur l'inversion 9B / 4B — à ne pas propager.** Les deux sont de la même famille
> `qwen3.5`, même quantification `nvfp4`, avec 9,4 milliards de paramètres contre 4,5.
> L'attente raisonnable est que le 9B domine. Une observation unique contredisant une
> attente solide est d'abord un signal de bruit, pas une découverte — et deux explications
> banales suffisent : le tirage à `temperature 0.7`, et la troncature à 3072 tokens qui
> pénalise le plus verbeux sur une grille comptant des points d'abord arrivés. **Cette
> inversion n'est pas un résultat de ce rapport.** La trancher demande 5 à 10 tirages par
> modèle sur un prompt commun — c'est peu coûteux (petits modèles, faible charge thermique)
> et ce serait la suite utile.

Sur `p3` (arbitrage d'architecture en français), les cinq ont produit une réponse recevable :
position prise, rétention chiffrée, réversibilité abordée. Aucune différence exploitable
n'est apparue — **ce prompt n'a rien discriminé**, ce qui peut tenir au prompt lui-même
autant qu'aux modèles.

### Ce qui peut guider un choix aujourd'hui

Sur des bases **mesurées**, pas qualitatives :

| Modèle       | Fait mesuré et solide                                                      |
| ------------ | -------------------------------------------------------------------------- |
| **35B GGUF** | 33 t/s, 18,1 Gio figés, aucune pagination — le seul sans contre-indication |
| 27B MLX      | **10 t/s** : trop lent pour de l'interactif, quel que soit son niveau      |
| 4B / 9B MLX  | rapides et légers ; niveau réel non établi par cette campagne              |
| 35B MLX      | ne rentre pas à 24576 sur 32 Go (§5)                                       |

Le choix du 35B GGUF comme modèle principal **repose sur la §6, pas sur la qualité** : il est
le seul à combiner un débit correct et une empreinte mémoire prévisible. Sa première place
qualitative sur ce tirage est un argument d'appoint, pas le fondement.

---

## 10. Limites

1. **La phase qualité n'est pas calibrée et ne classe rien** (§7). Un seul tirage par couple
   modèle × prompt, `temperature 0.7`, seed unique, aucune variance intra-modèle mesurée.
   Toute lecture ordinale de la §9 est un abus. Un contre-exemple interne au rapport le
   montre : l'inversion 9B / 4B contredit l'attente pour deux modèles de même famille, et
   s'explique sans rien invoquer d'autre que le bruit.
2. **Sorties tronquées à 3072 tokens.** Les 4B et 9B ont saturé ce plafond sur `p1` et `p2`
   sans conclure. Cela empêche de juger la complétude, et **biaise la grille contre les
   modèles verbeux**, qui atteignent moins d'items avant d'être coupés.
3. **Débits des phases A et B non comparables** : alimentation et état thermique différents,
   modèle chaud en phase B (voir §3).
4. **Prefill à ±15 %** en phase A (reproductibilité hors cible). Seuls les rapports entre
   backends sont robustes.
5. **`p3` fait 1 443 tokens**, sous la cible de 2000. Il ne doit pas servir à conclure sur le
   prefill.
6. **Aucune mesure de température ni de ventilateur.** Le protocole évite le throttling par
   conception mais ne peut pas prouver son absence.
7. **Le 27B n'a pas été soumis au protocole A-B-B-A** ; ses débits viennent de la phase B.

---

## 11. Reproduction

Tout est dans `~/bench/` :

| Fichier                                                         | Rôle                                                                       |
| --------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `serve_env.sh`                                                  | variables du serveur de mesure isolé (port 11500)                          |
| `bench.py`                                                      | harnais : requêtes API, relevé `/api/ps`, mémoire, swap, porte de validité |
| `abba.py`                                                       | campagne A-B-B-A avec refroidissement et arrêt sur swap                    |
| `score.py`                                                      | grille de correction sur vérité terrain                                    |
| `p1_refacto_java.md`, `p2_infra_traefik.md`, `p3_echange_fr.md` | prompts                                                                    |
| `results/abba.csv`, `results/qual.csv`                          | mesures brutes, une ligne par run                                          |
| `results/out/`                                                  | les 19 sorties de modèles                                                  |

```bash
cd ~/bench && source ./serve_env.sh && python3 -u abba.py    # phase A
cd ~/bench && source ./serve_env.sh && python3 -u bench.py qual   # phase B
cd ~/bench && python3 score.py                                # grille qualité
```

**Précaution pour toute reprise.** Sur macOS, `free + inactive` sous-estime grossièrement la
mémoire disponible : le cache fichier (`File-backed pages`) et les pages purgeables sont
réclamés à la demande. Au lancement de cette campagne, 13 Gio « libres » apparents mais
**29,2 Gio réellement récupérables**, pour seulement 5,6 Gio de mémoire applicative anonyme.
Juger sur `free` seul conduit à annuler des campagnes parfaitement viables — ou à en lancer
qui ne le sont pas.
