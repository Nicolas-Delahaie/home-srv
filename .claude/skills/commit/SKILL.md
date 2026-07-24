---
name: commit
description: Committe les changements en cours avec un message conforme aux conventions du projet. Se déclenche quand l'utilisateur demande explicitement de committer ou préparer un commit — ex. "committe ça", "prépare le commit", "fais un commit". Ne se déclenche PAS sur une simple validation ("je valide", "c'est bon") ni sur une demande de PR seule (cf. skill `pr`).
---

# Commit

## 0. Conventions

Lire `docs/conventions/git-workflow.md` avant rédaction (`CLAUDE.md` : synthèse + nuance Co-Authored-By).

Format imposé par `commitlint` (`commitlint.config.js`), vérifié en CI (job `commit-messages`). Pas de contrôle local ici : suivre les conventions à la rédaction suffit.

## 1. Délimiter le périmètre

`git status` / `git diff` pour voir tous les changements en cours. Confronter à la conversation :

- **Fichiers liés au sujet discuté** : ceux dont la conversation explique le contexte → à committer.
- **Fichiers modifiés mais jamais abordés dans la conversation** : à exclure de ce commit.
- **Cas ambigu** (pas sûr qu'un fichier soit lié ou non) : ne jamais trancher seul — demander à l'utilisateur avant de committer quoi que ce soit.

Parmi les fichiers en périmètre confirmé, déterminer s'il s'agit d'**une seule modification cohérente** ou de **plusieurs sujets indépendants** (implémentation, doc, config, backlog...).

## 2. Découper en commits si nécessaire

- Plusieurs sujets indépendants → un commit par sujet logique.
- Un seul sujet, même sur plusieurs fichiers → un seul commit.
- Séquence sur un même sujet (rare) : chaque commit fonctionnel isolément — jamais de build cassé en attendant le suivant.
- Cas multi-commits : proposer le découpage (groupes de fichiers + message de chaque commit) et le faire valider avant de committer quoi que ce soit.

## 3. Identifier les candidats de pourquoi

Repérer dans la conversation les **raisons/décisions explicites** derrière les modifications de chaque commit (étape 2) — jamais déduites du seul diff.

Candidat retenu seulement si info **absente du diff et du sujet** : contrainte cachée, décision, risque évité, alternative écartée. Pourquoi générique ou déductible (« améliore la lisibilité », « bonne pratique », « plus propre ») → même pas proposé.

- **Aucun candidat** → étape 4 directement, sans question. Cas normal, pas un échec.
- **Candidat(s)** → `AskUserQuestion`, checkboxes (`multiSelect: true`), un candidat = une option, lots de 4 max (limite de l'outil — au-delà, plusieurs questions/appels).

## 4. Rédiger le message

**Sujet = quoi, corps = pourquoi uniquement.** Le quoi détaillé est déjà dans le diff (`git show`) — le réécrire, c'est du bruit. Corps : seulement si un pourquoi retenu à l'étape 3.

Trois règles, dans cet ordre :

1. **Pourquoi > quoi.** Pas un changelog des modifications — la liste des raisons invisibles dans le code. Ligne visible dans le diff → supprimée.
2. **Zéro superflu.** Test par ligne : « `git show` le montre-t-il déjà ? » Si oui, supprimée. Détail d'implémentation (package, chemin) seulement s'il _est_ la décision. Pas de pourquoi vague ou global.
3. **Pas de troncature.** Le header reste entier — trop long, il passe en corps.

Formes :

- **Aucun pourquoi retenu** → sujet seul, pas de corps. Cas le plus fréquent, et très bien ainsi.
- **Un pourquoi** → accroché au sujet s'il tient dans la limite du header (`<type>(<scope>): <quoi> — <pourquoi>`) ; sinon, corps.
- **Plusieurs pourquoi** → corps en liste à tirets, une ligne par **raison** (jamais par modification), chacune rattachée à ce qu'elle justifie.

### Scope : réutiliser avant d'inventer

Vérifier les scopes déjà utilisés (`git log --format=%s | grep -oE '\([a-zA-Z0-9_-]+\)' | sort -u`) et reprendre le plus proche. Nouveau scope seulement si aucun ne correspond — dérive déjà constatée (`convention`/`conventions`, `tache`/`tickets`, `e1`...`e8`).

## 5. Committer

Un seul appel, message écrit directement dans la commande via heredoc — pas de fichier temporaire, message visible en entier (sauts de ligne inclus) au moment de valider :

```
git commit -F - <<'EOF'
<type>(<scope>): <sujet>

<corps éventuel>
EOF
```

`-m` proscrit : il n'affiche pas le message mis en forme avant validation. Le heredoc le montre tel qu'il sera committé.

Commande de commit seule : pas de `cd`, ni de `git log`/`git status` de vérif accolé.

Pas de validation `commitlint` locale : relève d'un hook (à faire plus tard).

Le déclenchement du skill (demande explicite) est la seule autorisation nécessaire. Ne jamais committer sans déclenchement explicite, ni un fichier resté ambigu à l'étape 1 sans validation de l'utilisateur.
