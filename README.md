# pplmatch

Package R pour l'appariement des noms des intervenants dans les debates parlementaires avec les tables dimensionnelles des parlementaires. Permet d'obtenir le parti politique, le genre et la circonscription de chaque intervenant.

## Fonctions principales

| Fonction | Description |
|---|---|
| `pplmatchCA()` | Appariement pour la **Chambre des Communes du Canada** (fuzzy via Jaro-Winkler) |
| `pplmatchQC()` | Appariement pour l'**Assemblee nationale du Quebec** (multi-niveaux : deterministe + fuzzy via Python/rapidfuzz) |
| `data_fetch_qc()` | Recupere les debats et la table des deputes QC depuis le datawarehouse CLESSN |
| `ensure_python_deps()` | Installe les dependances Python (rapidfuzz). A appeler une seule fois. |
| `generate_gold_sample()` | Genere un echantillon stratifie pour annotation manuelle (gold standard) |
| `evaluate_matches_qc()` | Calcule precision, recall et F1 contre un gold standard annote |

## Installation

```r
# Installer depuis GitHub
devtools::install_github("clessn/pplmatch")

# Installer les dependances Python (une seule fois)
pplmatch::ensure_python_deps()
```

`ensure_python_deps()` cree un environnement virtuel Python (`~/.virtualenvs/pplmatch`) et y installe `rapidfuzz`. Python 3 doit etre disponible sur le systeme.

## Utilisation rapide

### Quebec - Assemblee nationale

```r
library(pplmatch)

# Option 1 : avec le datawarehouse CLESSN (necessite le package tube)
data <- data_fetch_qc("2022-01-01", "2024-12-31")
result <- pplmatchQC(data$corpus, data$members, verbose = TRUE)

# Option 2 : avec vos propres donnees
corpus <- data.frame(
  speaker = c("Legault", "M. Bérubé", "Le Président", "Des Voix"),
  event_date = as.Date(c("2023-03-15", "2023-03-15", "2023-03-15", "2023-03-15"))
)

members <- data.frame(
  full_name = c("François Legault", "Pascal Bérubé"),
  party_id = c("CAQ", "PQ"),
  gender = c("m", "m"),
  legislature_id = c("43", "43")
)

result <- pplmatchQC(corpus, members, verbose = TRUE)
```

### Canada - Chambre des Communes

```r
library(pplmatch)

result <- pplmatchCA(debates, MPs, max_dist = 0.15)
```

## Format des donnees

### Corpus (donnees d'entree)

Le data frame des debats doit contenir ces colonnes :

| Colonne | Type | Description |
|---|---|---|
| `speaker` | character | Nom de l'intervenant tel qu'il apparait dans les debats |
| `event_date` | Date | Date du debat (format YYYY-MM-DD) |

Les autres colonnes sont conservees telles quelles dans le resultat.

### Names (table des deputes)

Le data frame des parlementaires doit contenir ces colonnes :

| Colonne | Type | Requis | Description |
|---|---|---|---|
| `full_name` | character | oui | Nom complet du depute (ex: "Francois Legault") |
| `party_id` | character | oui | Identifiant du parti (ex: "CAQ", "PLQ", "PQ", "QS") |
| `gender` | character | oui | Genre ("m" ou "f") |
| `legislature_id` | character | oui | Numero de la legislature (ex: "42", "43") |
| `other_names` | character | non | Noms alternatifs separes par des points-virgules (ex: "Legault; F. Legault") |
| `district_id` | character | non | Identifiant de la circonscription |

## Colonnes ajoutees au resultat (pplmatchQC)

| Colonne | Description |
|---|---|
| `legislature` | Numero de la legislature (35-43) determine a partir de `event_date` |
| `speaker_category` | Classification de l'intervenant (voir ci-dessous) |
| `speaker_normalized` | Nom normalise utilise pour l'appariement |
| `matched_name` | Nom complet du depute apparie (ou `NA`) |
| `party_id` | Parti politique du depute apparie |
| `gender` | Genre du depute apparie |
| `district_id` | Circonscription du depute apparie |
| `match_level` | Niveau de l'appariement (voir ci-dessous) |
| `match_score` | Score de similarite (0-100, `NA` pour les matchs deterministes) |

### Classification des intervenants (`speaker_category`)

| Categorie | Description | Exemples |
|---|---|---|
| `person` | Depute individuel | "Legault", "M. Berube", "Francois Legault" |
| `role` | Fonction institutionnelle | "Le President", "La Vice-Presidente" |
| `crowd` | Voix collectives | "Des Voix" |
| `empty` | Champ vide | "", " " |

### Inférence Contextuelle (`contextual`)

Pour les cas ambigus (ex: "M. Lévesque" alors que Mathieu et Sylvain Lévesque sont députés), l'algorithme utilise une approche en deux passes :
1. **Ancrage** : On identifie tous les députés formellement nommés (ex: "Mathieu Lévesque") lors de la même séance (journée).
2. **Inférence** : Si un nom ambigu ("M. Lévesque") correspond à plusieurs candidats, mais qu'un seul d'entre eux a été formellement identifié ce jour-là, l'algorithme infère qu'il s'agit de la même personne.

### Niveaux d'appariement (`match_level`)

| Niveau | Description |
|---|---|
| `deterministic` | Correspondance exacte apres normalisation (nom complet, nom alternatif, ou nom de famille non-ambigu) |
| `fuzzy` | Correspondance par similarite au-dessus du seuil (defaut : 85/100) |
| `contextual` | Ambiguïté résolue par la présence confirmée du député lors de la même séance |
| `ambiguous` | Plusieurs deputes partagent le meme nom de famille dans la legislature (ex: 3 Proulx en leg. 42). **Note:** Si tous les candidats sont du même parti, `party_id` est retourné par consensus. |
| `unmatched` | Aucune correspondance trouvee |
| `role` | L'intervenant est une fonction institutionnelle (pas un depute) |
| `crowd` | L'intervenant est un groupe ("Des Voix") |
| `empty` | Champ speaker vide |

## Pipeline de matching (pplmatchQC)

L'appariement se fait en deux niveaux :

### Preprocessing

Chaque nom d'intervenant est d'abord normalise :
1. Classification (`person` / `role` / `crowd` / `empty`)
2. Pour les `person` :
   - Retrait des chiffres en debut de chaine (ex: "15 725 M. Marissal" -> "M. Marissal")
   - Retrait du suffixe de circonscription (ex: "Picard, Chauveau" -> "Picard")
   - Retrait des mots-cles d'action (ex: "Legault (replique)" -> "Legault")
   - Retrait des titres honorifiques ("M.", "Mme", "M.Caire" -> "Caire")
   - Passage en minuscules, retrait des accents, conservation des lettres et espaces seulement

### Niveau 1 - Deterministe

Tentatives dans cet ordre :
1. Correspondance exacte sur le `full_name` normalise
2. Correspondance exacte sur les `other_names` normalises
3. Correspondance exacte sur le nom de famille seul, **seulement si non-ambigu** dans la legislature

### Niveau 2 - Fuzzy (rapidfuzz)

Si le niveau 1 echoue, comparaison par similarite :
- **Noms complets** : `token_sort_ratio` (60%) + `ratio` (40%)
- **Noms de famille seuls** : `partial_ratio` (50%) + `token_sort_ratio` (30%) + `ratio` (20%)
- Si le score depasse le seuil (`fuzzy_threshold`, defaut 85), le match est accepte
- Si un nom de famille seul matche plusieurs deputes au-dessus du seuil, il est marque `ambiguous`

## Parametres de pplmatchQC

| Parametre | Type | Defaut | Description |
|---|---|---|---|
| `Corpus` | data.frame | - | Debats avec colonnes `speaker` et `event_date` |
| `Names` | data.frame | - | Table des deputes (voir format ci-dessus) |
| `fuzzy_threshold` | numeric | 85 | Score minimum (0-100) pour accepter un match fuzzy. Augmenter pour plus de precision, diminuer pour plus de rappel. |
| `legislatures` | integer vector | 35:43 | Legislatures a traiter (35 = 1994, 43 = 2022-present) |
| `verbose` | logical | FALSE | Afficher la progression et le resume |

## Analyser la qualite des resultats

### Generer un echantillon pour annotation manuelle

```r
matched <- pplmatchQC(corpus, members, verbose = TRUE)

# Genere un CSV de 200 lignes stratifie par match_level
generate_gold_sample(matched, sample_size = 200, output_file = "gold_200.csv")
```

Le CSV contient une colonne vide `correct_name` a remplir manuellement avec le vrai nom du depute (ou laisser vide si l'intervenant n'est pas un depute).

### Evaluer la precision

```r
metrics <- evaluate_matches_qc(matched, "gold_200_annotated.csv")

message(sprintf(
  "Precision: %.1f%%  Recall: %.1f%%  F1: %.1f%%",
  metrics$precision * 100,
  metrics$recall * 100,
  metrics$f1 * 100
))

# Details par ligne
View(metrics$details)
```

## Legislatures couvertes (Quebec)

| Legislature | Debut | Fin |
|---|---|---|
| 35 | 1994-09-12 | 1998-11-25 |
| 36 | 1998-11-30 | 2003-03-12 |
| 37 | 2003-04-14 | 2007-02-21 |
| 38 | 2007-03-26 | 2008-11-05 |
| 39 | 2008-12-08 | 2012-08-01 |
| 40 | 2012-09-04 | 2014-03-05 |
| 41 | 2014-04-07 | 2018-08-23 |
| 42 | 2018-10-01 | 2022-08-28 |
| 43 | 2022-10-03 | 2026-10-05 |

## Prerequis

- **R** >= 4.0
- **Python** >= 3.8 (pour `pplmatchQC`)
- Packages R : `dplyr`, `reticulate`, `tibble`, `purrr`, `stringr`, `fuzzyjoin`, `tidyr`, `jsonlite`
- Package Python : `rapidfuzz` (installe automatiquement par `ensure_python_deps()`)
- Package R `tube` (optionnel, pour `data_fetch_qc()` via le datawarehouse CLESSN)

## Depannage

### "No module named 'rapidfuzz'"

Executer `ensure_python_deps()` pour installer rapidfuzz dans le virtualenv.

### "Cannot find pplmatch Python modules"

Le package n'est pas installe et le repertoire de travail n'est pas la racine du package. Soit installer le package (`devtools::install()`), soit se placer dans le repertoire source (`setwd("chemin/vers/pplmatch")`).

### Tests : tous les tests sont "skipped"

Le virtualenv Python n'est pas actif. Avant de lancer les tests, lancer :

```r
reticulate::use_virtualenv("pplmatch", required = TRUE)
reticulate::py_config()  # Force l'initialisation de Python
```

Ou positionner la variable d'environnement :

```bash
RETICULATE_PYTHON=~/.virtualenvs/pplmatch/bin/python Rscript -e "devtools::test()"
```
