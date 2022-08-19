$global:inDevelopment = @(
    'Phonos',
    'BetaCluster'
);

$global:version = "0.0.2";
$global:mwDir = "A:\wikimedia\mediawiki-local\";
$global:extensionsDir = $(Get-Item -Path "${mwDir}extensions\");
$global:allExtensions = $(Get-ChildItem $extensionsDir);
$global:tidy = $false;
$global:dryrun = $false;
$global:checkout = $false;
$global:sync = $true;

function setGlobal(
    [string]$global,
    [string]$value
) {
    #Write-Host "Setting global:${global} to '${value}'";
    Set-Variable -Name $global -Value $value -Scope Global
}

function runComposer([string]$dir) {
    Write-Host "Running composer update in ${dir}";
    Push-Location -Path $dir;
    $composerOutput = (composer -q update);
    Pop-Location;
}

function runNPM([string]$dir) {
    Write-Host "Running npm install in ${dir}";
    Push-Location -Path $dir;
    $composerOutput = (npm --silent install);
    Pop-Location;
}

function mwScript([string]$script, [string]$opts = '') {
    Write-Host "Running ${script}";
    php $script $opts;
}

function doFetching([string]$extDir) {
    $dryrun = $global:dryrun;
    $sync = $global:sync;

    if($sync -eq $true) {
        Write-Host "Syncing...";
        if($dryrun -eq $true) {
            Write-Host "[dry] Would have run:  git -C ${extDir} fetch -q";
            Write-Host "[dry] Would have run:  git -C ${extDir} rebase -q";
        } else {
            $fetchOutput = ((git -C $extDir fetch -q) | Out-String);
            $pullOutput = ((git -C $extDir rebase -q) | Out-String);
        }
    }
}

function tidyBranch(
    [string]$ext,
    [string]$extDir,
    [string]$branchToDelete,
    [boolean]$dev
) {
    $dryrun = $global:dryrun;

    if($dev -eq $true) {
        Write-Host "Aborting! ${$ext} is an in-development repo!";
    } else {
        if($dryrun -eq $true) {
            Write-Host "[dry] Would have run:  git -C ${extDir} branch -D ${branchToDelete}";
        } else {
            $delOutput = ((git -C $extDir branch -D $branchToDelete) | Out-String);
        }
    }
}

function gitWork(
    [string]$ext,
    [string]$extDir
) {
    $checkout = $global:checkout;
    $tidy = $global:tidy;
    $dryrun = $global:dryrun;

    $defaultBranch = 'master';
    $hasGerritBranches = $false; # review/{user}/{patch number}
    $dev = checkInDevelopment -ext $ext;
    $branches = ((git -C $extDir branch) | Out-String).trim();

    if($branches -match 'main') {
        $defaultBranch = 'main';
    } elseif($branches -match 'master') {
        $defaultBranch = 'master';
    }

    Write-Host "Default branch: ${defaultBranch}";

    if($branches -match 'review\/') {
        Write-Host "Has gerrit review branches";
        $hasGerritBranches = $true;
    }

    if($checkout -eq $true) {
        Write-Host "Ensuring we have checked out ${defaultBranch}";
        $checkoutOutput = ((git -C $extDir checkout -q $defaultBranch) | Out-String);
    }

    if($dev -eq $true) {
        Write-Host "Marked as in development, will not tidy...";
    } else {
        if($tidy -eq $true) {
            Write-Host "Tidying...";
            foreach($branch in ($branches.Split("`n")).trim()) {
                $branch = $branch -replace "^\* ", "";
                if($branch -ne $defaultBranch) {
                    # Tidy if enabled
                    if($dryrun -eq $true) {
                        Write-Host "[dry] Deleting ${branch}";
                        tidyBranch -ext $ext -extDir $extDir -branchToDelete $branch -dev $dev;
                    } else {
                        Write-Host "Deleting ${branch}";
                        tidyBranch -ext $ext -extDir $extDir -branchToDelete $branch -dev $dev;
                    }
                }
            }
        }
    }
}

function checkInDevelopment([string]$ext) {
    if($global:inDevelopment -contains $ext) {
        return $true;
    } else {
        return $false;
    }
}

function gitGud(
    [switch]$help,
    [switch]$tidy,
    [switch]$dryrun,
    [switch]$checkout,
    [string]$repo = 'all',
    [boolean]$mwpull = $true,
    [boolean]$sync = $true
) {
    Write-Host "gitGud v${global:version}";

    if($help) {
        Write-Host "Usage: gitGud [ -tidy ] [ -dryrun ] [ -checkout ] < -repo=name > < -mwpull=$false > < -sync=$false >";
        return;
    }
    
    Write-Host -NoNewline "Settings: ";
    if($dryrun) {
        setGlobal -global dryrun -value $true;
        Write-Host -NoNewline "[dry run=True] ";
    } else {
        setGlobal -global dryrun -value $false;
        Write-Host -NoNewline "[dry run=False] ";
    }
    if($tidy) {
        setGlobal -global tidy -value $true;
        Write-Host -NoNewline "[tidy=True] ";
    } else {
        setGlobal -global tidy -value $false;
        Write-Host -NoNewline "[tidy=False] ";
    }
    if($checkout) {
        setGlobal -global checkout -value $true;
        Write-Host -NoNewline "[checkout=True] ";
    } else {
        setGlobal -global checkout -value $false;
        Write-Host -NoNewline "[checkout=False] ";
    }
    if($sync -eq $true) {
        setGlobal -global sync -value $true;
        Write-Host -NoNewline "[sync=True] ";
    } else {
        setGlobal -global sync -value $false;
        Write-Host -NoNewline "[sync=False] ";
    }
    Write-Host -NoNewline "[mwpull=${mwpull}] ";
    if($repo) {
        Write-Host -NoNewline "[repo=${repo}] ";
    }
    Write-Host "`n";

    if($mwpull) {
        if($global:dryrun) {
            Write-Host "[dry] Updating MediaWiki core...";
        } else {
            Write-Host "Updating MediaWiki core...";
        }
        gitWork -ext 'core' -extDir $global:mwDir;
        doFetching -extDir $global:mwDir;
        Write-Host;
    }

    if($repo -ne 'all') {
        $ext = $repo;
        if(Test-Path -Path $global:extensionsDir$ext) {
            $extDir = $(Get-Item -Path $global:extensionsDir$ext);
        } else {
            Write-Error -Message "${repo} does not exist!" -ErrorAction Stop
        }
        
        if($extDir.PSIsContainer) {
            if($global:dryrun) {
                Write-Host "[dry] Checking ${ext}...";
            } else {
                Write-Host "Checking ${ext}...";
            }
            
            gitWork -ext $ext -extDir $extDir;
            doFetching -extDir $extDir;
        } else {
            Write-Host "${repo} is not a git repo.";
        }

    } else {

        foreach($ext in $global:allExtensions) {
            if(Test-Path -Path $global:extensionsDir$ext) {
                $extDir = $(Get-Item -Path $global:extensionsDir$ext);
            } else {
                Write-Error -Message "${extDir} does not exist!" -ErrorAction Stop
            }
            
            if($extDir.PSIsContainer) {
                if($global:dryrun) {
                    Write-Host "[dry] Checking ${ext}...";
                } else {
                    Write-Host "Checking ${ext}...";
                }
            
                gitWork -ext $ext -extDir $extDir;
                doFetching -extDir $extDir;
                Write-Host;
            }
        }
    }

    if($global:dryrun -eq $false) {
        runComposer -dir $global:mwDir;
        runNPM -dir $global:mwDir;
        mwScript -script "${global:mwDir}maintenance\update.php" -opts "--quick"; 
    } else {
        Write-Host "[dry] Skipping composer, npm etc..`n";
    }
    
    Write-Host "Done!";
}
