# Visual-PS5 — PS5 Homebrew Studio 1.1.6

IDE visuel local pour Windows : conception d’interfaces, gestion de projets, inspection du code, génération d’UI C++20 et orchestration des compilations avec des toolchains communautaires PS5.

**État linguistique :** l’interface reste en espagnol. Le manuel français est disponible ; la traduction de l’interface sera réalisée séparément.

## Nouveautés de la version 1.1.6

- Ajoute la vue **Structure** pour distinguer les écrans visuels modifiables des états de menus détectés dans le C++ natif : arbre avec recherche, graphe de transitions, libellés repérés et accès direct aux lignes du code source. Les transitions C++ sont déduites statiquement et doivent être vérifiées.
- Ajoute la vue **Structure** pour distinguer les écrans visuels modifiables des états de menus détectés dans le C++ natif : arbre avec recherche, graphe de transitions, libellés repérés et accès direct aux lignes du code source. Les transitions C++ sont déduites statiquement et doivent être vérifiées.
- Correction des boutons d’action des fenêtres UltraPack et Présentation.
- Les builds OpenGL natifs des projets créés par l’IDE utilisent le `build.ps1` et les dépendances locales du projet. Cette voie évite la préparation redondante du SDK partagé qui peut échouer sous WSL/DrvFS sans `metadata`.
- Sélection de l’icône, des fonds de sélection/lancement et de la musique avant compilation ; gestion des écrans et de l’ordre des calques par écran.
- La compilation OpenGL et l’empaquetage UltraPack sont confirmés par le mainteneur dans son environnement Windows/WSL. Les builds Vulkan complets, la conversion ATRAC9 et l’exécution sur une PS5 physique restent à vérifier. Voir [les problèmes connus et l’état de validation](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md).

## Documentation

- [Manuel utilisateur français](docs/USER-MANUAL.fr-FR.md)
- [Manuel espagnol](docs/MANUAL.es-ES.md)
- [Manuel anglais](docs/USER-MANUAL.en-GB.md)
- [Manuel allemand](docs/USER-MANUAL.de-DE.md)
- [Manuel chinois simplifié](docs/USER-MANUAL.zh-CN.md)
- [Manuel japonais](docs/USER-MANUAL.ja-JP.md)
- [Manuel russe](docs/USER-MANUAL.ru-RU.md)
- [Crédits et attributions upstream](docs/CREDITS.md)
- [Matrice SDK et projets upstream](release/UPSTREAM-SDK-MATRIX.md)
- [Changelog](docs/CHANGELOG.md)
- [Problèmes connus et état de validation](PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md)

## Démarrage rapide

1. Téléchargez ou construisez le paquet de la branche à utiliser.
2. Extrayez-le dans un dossier accessible en écriture sous Windows 10/11.
3. Lancez `PS5-Homebrew-Studio/start.bat` et ouvrez http://127.0.0.1:47813/ si le navigateur ne démarre pas.

PowerShell 7 est recommandé ; Windows PowerShell 5.1 est aussi pris en charge. Les builds natifs exigent Git, WSL/Linux et les dépendances de la template choisie. Le service écoute uniquement sur 127.0.0.1.

Une compilation et un empaquetage réussis ne prouvent pas le fonctionnement sur une PS5 physique ; consultez le document des problèmes connus pour l’état de validation. Visual-PS5 n’est pas un SDK officiel Sony et ne fournit aucun fichier propriétaire, firmware, clé, jeu ou BIOS.