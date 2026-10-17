# Manuel utilisateur — PS5 Homebrew Studio 1.1.7

Dernière mise à jour : 17 octobre 2026. L’interface de l’application reste en espagnol ; ce manuel traduit ne signifie pas que l’interface soit déjà localisée.

## Nouveautés et validation de la version 1.1.7

- Ajoute des polices TrueType (`.ttf`) sélectionnables pour le texte Unicode sous OpenGL et Vulkan. L’IDE génère des atlas pour les points de code employés par le projet et arrête le build si un glyphe requis manque. Les tests couvrent le cyrillique, le grec, le japonais, le chinois et le coréen ; aucun IME CJK ni façonnage RTL complet n’est inclus. [Guide des polices Unicode](UNICODE-FONTS.en-GB.md).

- L’onglet **Estructura** sépare les écrans modifiables du modèle visuel des états détectés dans le C++ natif. Il propose une recherche, une carte de transitions inférées, les libellés détectés et des liens vers les lignes de déclaration et de rendu. L’analyse statique peut manquer des chemins complexes ; les menus dessinés en C++ ne deviennent pas des composants visuels modifiables.

- Correction des boutons d’action des dialogues UltraPack et Présentation.
- Les builds OpenGL natifs des projets visuels créés par l’IDE utilisent le `build.ps1` local et les dépendances du projet.
- La boîte de dialogue de build natif permet de choisir l’icône, les fonds de sélection/lancement et la musique ; l’éditeur gère les écrans et l’ordre des calques par écran.
- Le mainteneur confirme la compilation OpenGL et l’empaquetage UltraPack dans l’environnement de test Windows/WSL. Les builds Vulkan complets, la conversion ATRAC9 et l’exécution sur une PS5 physique restent non vérifiés. Voir [les problèmes connus](../PS5-Homebrew-Studio/docs/KNOWN-ISSUES.es-ES.md).

## 1. Prérequis

Pour lancer l’IDE : Windows 10/11, des droits de lecture/écriture sur le dossier de l’application et PowerShell 7 recommandé. Le lanceur prend aussi en charge Windows PowerShell 5.1.

Pour compiler : Git, WSL/Linux et les dépendances upstream du backend choisi. SharpProspero/C# nécessite la version .NET de la révision installée. Les projets C++ natifs ont besoin d’une toolchain compatible. UltraPack nécessite Python 3.10 ou ultérieur et le dépôt [PS5 UltraPack](https://github.com/knutwurst/ps5-ultrapack).

## 2. Installation et lancement

1. Téléchargez ou construisez le paquet de la branche à tester.
2. Extrayez-le dans un dossier accessible en écriture, hors des répertoires Windows protégés.
3. Lancez start.bat et laissez la fenêtre PowerShell ouverte.
4. Si le navigateur ne s’ouvre pas, visitez http://127.0.0.1:47813/.
5. Fermez la fenêtre serveur ou utilisez STOP.bat pour arrêter le service.

Le service écoute uniquement sur 127.0.0.1. Ne l’exposez pas au réseau et ne le liez pas à 0.0.0.0. Les projets sont enregistrés par défaut dans Documents/PS5HomebrewStudio/Projects.

## 3. Interface et projet visuel

Le canevas 1920×1080 est une zone de travail virtuelle, pas une capture exacte de l’interface PS5. Le panneau des composants ajoute des contrôles ; l’inspecteur modifie leur géométrie et leurs propriétés ; la hiérarchie organise les éléments et le gestionnaire d’écrans structure l’UI. L’éditeur de flux relie événements et actions comme notify, setText, toggleVisibility, setValue, changeColor et navigate lorsque le composant et le backend le permettent.

Créez le projet, choisissez le backend avant de préparer ses dépendances, ajoutez composants et ressources, utilisez des ID uniques et configurez les écrans. Lancez les diagnostics et corrigez les références invalides. Enregistrez avec Ctrl+S. L’export d’un modèle ou d’un ZIP n’est pas une compilation native.

## 4. Backends et compilation

**SharpProspero / C# :** utilise le pipeline upstream réel et .NET/NativeAOT. Vérifiez la version .NET exigée par le commit installé.

**OpenGL natif / C++20 :** génère un écran compatible avec le contrat ps5-homebrew-ui. Les images sont converties en RGBA8, limitées à 512×512 pixels et à 16 identifiants de texture uniques par écran.

**Vulkan/RADV / C++20 :** crée un titre via PS5_VulkanTemplate et intègre l’UI au module Vulkan compatible. Des révisions compatibles de PS5_Vulkan, PS5_Mesa/RADV, PS5_PayloadSDK et PS5_VKHomebrewUI sont nécessaires.

L’IDE exécute les scripts upstream réels et garde les journaux. Un code de sortie nul ne suffit pas : l’empaquetage natif exige eboot.bin et sce_sys/param.json. L’IDE ne distribue pas de SDK propriétaire Sony et ne garantit pas la compatibilité avec tous les firmwares.

## 5. Empaquetage avec UltraPack

1. Ouvrez Outils et configurez Python 3.10+ et le fichier backend/cli.py d’UltraPack.
2. Enregistrez les paramètres dans la configuration locale .runtime/integrations.json.
3. Sélectionnez un projet natif compilé et choisissez Empaqueter.
4. Choisissez .ffpfs, .ffpfsc ou .pkg. Sous Windows, .pkg exige un helper natif et ses dépendances.
5. Laissez cochée l’option « Vérifier le contenu par rapport à la source » pour transmettre --verify. Cette vérification peut augmenter le temps et la mémoire utilisés.
6. Vérifiez le journal final, le code de sortie, le chemin de sortie et les avertissements. Un ancien artefact ne prouve pas le succès de l’exécution actuelle.

Les fichiers sont rangés par format et horodatage dans packages-ultrapack. L’empaquetage fonctionne en arrière-plan. Le mainteneur indique qu’une image .ffpfsc a été générée et testée avec succès sur matériel réel ; cela ne garantit pas tous les titres, firmwares ou backends.

## 6. Tests et dépannage

Avec Node.js, lancez node --check app.js, node --check runtime/native-generator.js et node runtime/test-native-generator.js depuis le dossier de l’application. Ces tests vérifient JavaScript et le générateur ; ils ne remplacent pas un build avec la toolchain PS5 complète ni un essai sur console.

Si le serveur ne démarre pas, conservez l’erreur complète et vérifiez PowerShell et les droits. En cas d’échec du build, notez le backend, les versions/commits upstream, la sortie et le code de sortie. Pour UltraPack, vérifiez les chemins Python/cli.py, eboot.bin, sce_sys/param.json et les droits du dossier de sortie. Ne partagez pas de secrets.

## 7. Licences et limites

Les SDK, pilotes, modèles et kits UI gardent leurs propres licences. Lisez LICENSE, COPYING, NOTICE et les conditions de redistribution avant toute publication. Visual-PS5 n’est pas un SDK officiel Sony, ne contient ni firmware, ni clés, ni jeux, ni BIOS et n’installe pas automatiquement un titre sur console. L’aperçu n’émule pas la PS5 et ne valide pas l’exécution, le son, les entrées ou la persistance.
