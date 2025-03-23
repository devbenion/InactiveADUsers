# Fonction permettant d'obtenir les utilisateurs inactifs d'Active Directory
Function Get-InactiveADUsers {
    param (
        [Parameter(Mandatory=$true)] # Rend obligatoire la spécification du paramètre DaysInactive
        [ValidateRange(1,3650)] # Vérifie que le nombre entré est compris entre 1 et 3650 jours (environ 10 ans)
        [int]$DaysInactive, # Nombre de jours sans connexion après lesquels un utilisateur est considéré comme inactif

        [string]$SearchOU = "", # Optionnel : spécifie une Unité Organisationnelle pour limiter la recherche

        [switch]$NeverLoggedIn # Optionnel : si activé, recherche uniquement les utilisateurs n'ayant jamais ouvert de session
    )
      
    # Calcule la date limite : les utilisateurs avec une dernière connexion avant cette date seront considérés comme inactifs
    $DateCutoff = (Get-Date).AddDays(-$DaysInactive)

    # Vérifie si une unité organisationnelle spécifique a été précisée par l'utilisateur
    if ($SearchOU -ne "") {
        # Vérifie explicitement que l'OU de recherche existe bien avant de procéder
      if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$SearchOU)")) {
        Write-Warning "The specified Search OU '$SearchOU' does not exist. Operation cancelled."
        return # Annule l'opération si l'OU cible n'existe pas
        }
        # Récupère les utilisateurs activés depuis l'Unité Organisationnelle spécifiée avec les propriétés détaillées
        $Users = Get-ADUser -Filter "Enabled -eq 'True'" -SearchBase $SearchOU -Properties DisplayName, sAMAccountName, whenCreated, LastLogonTimestamp, Enabled
    } else {
        # Récupère les utilisateurs activés depuis tout le domaine avec les propriétés détaillées
        $Users = Get-ADUser -Filter "Enabled -eq 'True'" -Properties DisplayName, sAMAccountName, whenCreated, LastLogonTimestamp, Enabled
    }

    # Vérifie si le paramètre NeverLoggedIn est activé
    if ($NeverLoggedIn) {
        # Filtre précisément les utilisateurs jamais connectés et créés avant la date limite définie
        $Users = $Users | Where-Object {
            ($null -eq $_.LastLogonTimestamp -or $_.LastLogonTimestamp -eq 0 -or $_.LastLogonTimestamp -eq "<not set>") -and $_.whenCreated -lt $DateCutoff
        }
    } else {
        # Filtre uniquement les utilisateurs dont la dernière connexion est antérieure à la date limite
        $Users = $Users | Where-Object {
            $_.LastLogonTimestamp -and ([datetime]::FromFileTime($_.LastLogonTimestamp) -lt $DateCutoff)
        }
    }

    # Vérifie si la liste des utilisateurs correspondants est vide
    if ($null -eq $Users -or $Users.Count -eq 0) {
        # Affiche un message indiquant qu'aucun utilisateur ne correspond aux critères spécifiés
        Write-Output "No inactive users found matching the specified criteria."
        return @() # Retourne explicitement un tableau vide
    }

    # Retourne les informations des utilisateurs filtrés en formatant les propriétés affichées
    return $Users | Select-Object DisplayName, sAMAccountName,
        @{Name='Created'; Expression={if ($_.whenCreated) { ($_.whenCreated).ToString("yyyy-MM-dd HH:mm:ss") } else { 'Unknown' }}}, # Formate clairement la date de création du compte
        @{Name='LastLogon'; Expression={if ($_.LastLogonTimestamp) { [datetime]::FromFileTime($_.LastLogonTimestamp).ToString("yyyy-MM-dd HH:mm:ss") } else { 'Never Logged In' }}} # Formate la dernière connexion ou affiche explicitement "Never Logged In"
}

# Fonction permettant la désactivation sécurisée des utilisateurs jugés inactifs avec déplacement vers une OU
Function Disable-InactiveADUsers {
    param (
        [Parameter(Mandatory=$true)] # Obligatoire : nombre de jours d'inactivité pour sélectionner les utilisateurs
        [ValidateRange(1,3650)] # Vérifie que le nombre est compris entre 1 et 3650 jours
        [int]$DaysInactive,

        [Parameter(Mandatory=$true)] # Obligatoire : Unité Organisationnelle cible où les comptes désactivés seront déplacés
        [string]$TargetOU,

        [string]$SearchOU = "", # Optionnel : limite la recherche à une Unité Organisationnelle spécifique

        [switch]$NeverLoggedIn, # Optionnel : sélectionne uniquement les utilisateurs n'ayant jamais ouvert de session

        [bool]$RemoveGroups = $false # Optionnel : permet de supprimer tout les groupes d'appartenance de l'utilisateur mais par défaut ne le fais pas
    )

    # Vérifie explicitement que l'OU cible existe bien avant de procéder
    if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$TargetOU)")) {
        Write-Warning "The specified Target OU '$TargetOU' does not exist. Operation cancelled."
        return
    }

    # Vérifie explicitement que l'OU de recherche existe bien avant de procéder
    if ($SearchOU -ne "") {
        if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$SearchOU)")) {
            Write-Warning "The specified Search OU '$SearchOU' does not exist. Operation cancelled."
            return
        }
    }

    # Appelle la fonction précédente pour obtenir les utilisateurs correspondants aux critères spécifiés
    $Users = @(Get-InactiveADUsers -DaysInactive $DaysInactive -SearchOU $SearchOU -NeverLoggedIn:$NeverLoggedIn)

    # Vérifie si la liste d'utilisateurs est valide et non vide
    if ($Users -isnot [Array] -or $Users.Count -eq 0 -or ($Users[0] -is [string])) {
        Write-Output "No inactive users found matching the specified criteria. Operation cancelled."
        return
    }

    # Affiche la liste des utilisateurs à désactiver et à déplacer
    Write-Output "The following users will be disabled and moved to the OU: $TargetOU"
    $Users | Format-Table -AutoSize

    # Demande une confirmation explicite à l'utilisateur avant de continuer
    $Confirmation = Read-Host "Do you confirm disabling and moving these accounts? (Yes/No)"
    if ($Confirmation -notmatch "^(Yes|Y|y|yes)$") {
        Write-Output "Operation cancelled by the user."
        return
    }

    # Boucle pour désactiver et déplacer chaque utilisateur dans l'OU cible
    foreach ($User in $Users) {
        try {
            # Désactive le compte utilisateur
            Disable-ADAccount -Identity $User.sAMAccountName -ErrorAction Stop
            
            # Déplace le compte utilisateur vers l'OU cible
            Move-ADObject -Identity (Get-ADUser $User.sAMAccountName).DistinguishedName -TargetPath $TargetOU -ErrorAction Stop
            
            # Vérifie si l'option de suppression des groupes est activée
            if ($RemoveGroups) {
                # Récupère tous les groupes de l'utilisateur
                $Groups = Get-ADUser $User.sAMAccountName -Properties MemberOf | Select-Object -ExpandProperty MemberOf
                
                if ($Groups) {
                    # Supprime l'utilisateur de tous ses groupes
                    foreach ($Group in $Groups) {
                        Remove-ADGroupMember -Identity $Group -Members $User.sAMAccountName -Confirm:$false -ErrorAction SilentlyContinue
                    }
                    Write-Output "User disabled, moved, and removed from all groups: $($User.sAMAccountName)"
                } else {
                    Write-Output "User disabled and moved, but had no groups to remove: $($User.sAMAccountName)"
                }
            } else {
                Write-Output "User disabled and moved: $($User.sAMAccountName)"
            }
        }
        catch {
            Write-Warning "Error disabling, moving, or modifying groups for account: $($User.sAMAccountName). Details: $_"
        }
    }
}

# Fonction d'exportation des utilisateurs inactifs vers un fichier CSV
Function Export-InactiveADUsers {
    param (
        [Parameter(Mandatory=$true)] # Obligatoire : spécifie le chemin complet du fichier CSV d'exportation
        [string]$ExportPath,

        [Parameter(Mandatory=$true)] # Obligatoire : nombre de jours d'inactivité pour sélectionner les utilisateurs à exporter
        [ValidateRange(1,3650)] # Vérifie que le nombre est compris entre 1 et 3650 jours
        [int]$DaysInactive,

        [string]$SearchOU = "", # Optionnel : limite la recherche à une Unité Organisationnelle spécifique

        [switch]$NeverLoggedIn # Optionnel : sélectionne uniquement les utilisateurs n'ayant jamais ouvert de session
    )

    # Vérifie que le répertoire spécifié pour l'exportation existe bien
    if (-not (Test-Path -Path (Split-Path $ExportPath))) {
        Write-Warning "The specified export path is not valid. Operation cancelled."
        return # Annule l'opération si le chemin spécifié est invalide
    }

    # Vérifie explicitement que l'OU de recherche existe bien avant de procéder
    if ($SearchOU -ne "") {
        if (-not (Get-ADOrganizationalUnit -LDAPFilter "(distinguishedName=$SearchOU)")) {
            Write-Warning "The specified Search OU '$SearchOU' does not exist. Operation cancelled."
            return
        }
    }

    # Récupère les utilisateurs répondant aux critères d'inactivité définis
    $Users = Get-InactiveADUsers -DaysInactive $DaysInactive -SearchOU $SearchOU -NeverLoggedIn:$NeverLoggedIn

    # Vérifie si des utilisateurs valides ont été récupérés pour l'export
    if (-not ($Users -is [System.Array]) -or $Users.Count -eq 0 -or ($Users -is [string])) {
        Write-Output "No users to export based on provided criteria. Operation cancelled."
        return # Annule l'opération si aucun utilisateur valide n'est trouvé
    }

    # Essaie d'exporter les utilisateurs sélectionnés dans le fichier CSV spécifié
    try {
        $Users | Export-Csv -Path $ExportPath -NoTypeInformation -Encoding UTF8 # Effectue l'exportation vers le fichier CSV
        Write-Output "Successfully exported to: $ExportPath" # Confirme explicitement la réussite de l'opération
    }
    catch {
        Write-Warning "Error during export: $_" # Informe clairement en cas d'erreur lors de l'exportation
    }
}

# Exportation des fonctions du module
Export-ModuleMember -Function Get-InactiveADUsers, Disable-InactiveADUsers, Export-InactiveADUsers