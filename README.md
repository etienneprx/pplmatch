# pplmatch 🎯

**Relier les paroles aux politiciens.**

Ce package R permet d'identifier automatiquement qui parle dans les débats de l'Assemblée nationale du Québec (et du Canada). Il transforme des noms incomplets comme *"M. le Ministre"* ou *"M. Legault"* en données précises : **François Legault**, **CAQ**, **Premier Ministre**.

Il est conçu pour être utilisé facilement par les étudiants et chercheurs du CAPP.

---

## 🛠️ Installation (À faire une seule fois)

Copiez-collez ces commandes dans votre console RStudio.

### 1. Pré-requis
Assurez-vous d'avoir accès au **VPN du CLESSN** ou d'être sur le réseau de l'université, car les données sont sécurisées.

### 2. Installer les packages
```r
# Installer le package 'tube' (pour l'accès aux données CLESSN)
remotes::install_github("clessn/tube")

# Installer pplmatch
remotes::install_github("etienneprx/pplmatch")
```

### 3. Configurer Python (Important !)
Cet outil utilise une petite partie en Python pour faire la reconnaissance "floue" (quand il y a des fautes de frappe). Lancez cette commande **une seule fois** après l'installation :

```r
pplmatch::ensure_python_deps()
```

---

## 🚀 Utilisation Rapide (Recette de cuisine)

Voici comment analyser une période de débats en 3 étapes.

### Étape 1 : Charger et Récupérer les données
On choisit une date de début et de fin. Le format est toujours **"AAAA-MM-JJ"**.

```r
library(pplmatch)
library(dplyr) # Pour manipuler les données

# Exemple : Mai 2012 (Le printemps érable)
# L'outil va chercher automatiquement dans les archives (Datalake) ou les données récentes.
donnees <- data_fetch_qc("2012-05-01", "2012-05-31")

# On vérifie ce qu'on a récupéré
print(paste(nrow(donnees$corpus), "interventions trouvées."))
```

### Étape 2 : Lancer l'identification (Matching)
C'est ici que la magie opère. On croise le `corpus` (les textes) avec les `members` (la liste des députés).

```r
# verbose = TRUE permet de voir la progression
resultats <- pplmatchQC(donnees$corpus, donnees$members, verbose = TRUE)
```

### Étape 3 : Analyser
Le tableau `resultats` contient maintenant de nouvelles colonnes très utiles.

```r
# Regardons un extrait des colonnes intéressantes
resultats %>%
  select(event_date, speaker, matched_name, party_id, role_status) %>%
  head(10)
```

---

## 📖 Comprendre les résultats

Voici ce que signifient les nouvelles colonnes ajoutées à vos données :

| Colonne | Description | Exemple |
| :--- | :--- | :--- |
| **`speaker`** | Le nom tel qu'écrit dans le transcript (brut). | *"M. Charest"* |
| **`matched_name`** | Le nom complet officiel du député identifié. | *"Jean Charest"* |
| **`party_id`** | Le parti politique du député à ce moment-là. | *"PLQ"* |
| **`role_status`** | **Gouvernement** ou **Opposition** ? Calculé selon la date de l'élection. | *"Government"* |
| **`match_level`** | La fiabilité de l'identification (voir ci-dessous). | *"deterministic"* |

### Les niveaux de confiance (`match_level`)

*   ✅ **deterministic** : On est sûr à 100%. Le nom est exact.
*   ✅ **contextual** : On a utilisé le contexte de la journée pour deviner (ex: distinguer deux "Tremblay").
*   ✅ **role_inferred** : On n'a pas le nom, mais le titre (ex: "Le Ministre") confirme que c'est le **Gouvernement**.
*   ⚠️ **fuzzy** : Il y avait peut-être une faute de frappe, mais on a trouvé un nom très proche.
*   ❌ **ambiguous** : Il y a plusieurs députés avec ce nom et on n'a pas pu trancher.
*   ❌ **unmatched** : Impossible d'identifier la personne.

---

## ❓ Foire aux questions

**Q: J'ai une erreur "Could not fetch from Datawarehouse".**
R: Vérifiez que vous êtes bien connecté au VPN. Vérifiez aussi que vos dates sont au format "AAAA-MM-JJ".

**Q: Ça prend du temps à charger.**
R: C'est normal si vous demandez une période très longue (plusieurs années). Essayez de travailler mois par mois ou année par année.

**Q: C'est quoi "unmatched" ?**
R: Ce sont souvent des gens qui ne sont pas députés (ex: un invité), ou des erreurs dans les vieux documents numérisés (années 90). Pour une analyse scientifique, vous pouvez souvent ignorer ces lignes.

---

*Développé par le CLESSN.*
