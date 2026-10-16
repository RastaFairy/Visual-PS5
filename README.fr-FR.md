# Visual-PS5 — PS5 Homebrew Studio 1.1.0

IDE visuel local pour Windows : conception d’interfaces, gestion de projets, inspection du code, génération d’UI C++20 et orchestration des compilations avec des toolchains communautaires PS5.

**État linguistique :** l’interface reste en espagnol. Le manuel français est disponible ; la traduction de l’interface sera réalisée séparément.

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

## Démarrage rapide

1. Téléchargez ou construisez le paquet de la branche à utiliser.
2. Extrayez-le dans un dossier accessible en écriture sous Windows 10/11.
3. Lancez start.bat et ouvrez http://127.0.0.1:47813/ si le navigateur ne démarre pas.

PowerShell 7 est recommandé ; Windows PowerShell 5.1 est aussi pris en charge. Les builds natifs exigent Git, WSL/Linux et les dépendances de la template choisie. Le service écoute uniquement sur 127.0.0.1.

Le mainteneur indique qu’une image .ffpfsc a été testée avec succès sur matériel réel ; cela ne garantit pas tous les titres ni firmwares. Visual-PS5 n’est pas un SDK officiel Sony et ne fournit aucun fichier propriétaire, firmware, clé, jeu ou BIOS.