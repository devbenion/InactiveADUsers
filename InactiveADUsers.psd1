<##
    IMPORTANT : Module requis "Active Directory"

    Si lors de l'importation du module vous recevez un message indiquant que le module Active Directory est manquant,
    vous devez l'installer en fonction de votre système :

    Pour Windows 10/11 :
        Add-WindowsCapability -Online -Name 'RSAT.ActiveDirectory.DS-LDS.Tools~~~~0.0.1.0'

    Pour Windows Server :
        Install-WindowsFeature -Name RSAT-AD-PowerShell
#>

@{
    # Version actuelle du module
    ModuleVersion     = '1.0.0' 

    # Nom de l'auteur du module
    Author            = 'Moussa Traore' 

    # Nom de l'entreprise ou organisation associée au module
    CompanyName       = 'Malian Knowledge' 

    # Informations sur le droit d'auteur
    Copyright         = '(c) 2024 Malian Knowledge. All rights reserved.' 

    # Description claire de l'objectif du module
    Description       = 'PowerShell module for managing inactive Active Directory users.' 

    # Version minimale de PowerShell requise pour utiliser ce module
    PowerShellVersion = '5.1' 

    # Fichier principal du module (script PowerShell)
    RootModule        = 'InactiveADUsers.psm1' 
    
    # Dépendance requise (module Active Directory doit être installé)
    RequiredModules   = @('ActiveDirectory') 

    # Liste des fonctions que le module exporte et rend disponibles aux utilisateurs
    FunctionsToExport = @( 
        'Get-InactiveADUsers',
        'Disable-InactiveADUsers',
        'Export-InactiveADUsers'
    )

    # Identifiant unique du module généré aléatoirement avec [guid]::NewGuid()
    GUID              = '01667ccf-0319-480e-acfe-04677c1086b7' 
}
