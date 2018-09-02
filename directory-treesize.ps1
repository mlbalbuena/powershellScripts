<#
.SYNOPSIS
powershell script to to enumerate directory summarizing in tree view directories over a given size

.DESCRIPTION
    To download and execute, run the following commands on each sf node in admin powershell:
    iwr('https://raw.githubusercontent.com/jagilber/powershellScripts/master/directory-treesize.ps1') -UseBasicParsing|iex

    To download and execute with arguments:
    (new-object net.webclient).downloadfile("https://raw.githubusercontent.com/jagilber/powershellScripts/master/directory-treesize.ps1",".\directory-treesize.ps1");
    .\directory-treesize.ps1 c:\windows\system32

    To enable script execution, you may need to Set-ExecutionPolicy Bypass -Force
    
    Requirements:
        - administrator powershell prompt
        - administrative access to machine
        - remote network ports:
            - smb 445
            - rpc endpoint mapper 135
            - rpc ephemeral ports
            - to test access from source machine to remote machine: dir \\%remote machine%\admin$
            
    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.
    
.NOTES
    File Name  : directory-treesize.ps1
    Author     : jagilber
    Version    : 180901 original
    History    : 

.EXAMPLE
    .\directory-treesize.ps1
    enumerate current working directory

.PARAMETER directory
    directory to enumerate

.PARAMETER depth
    subdirectory levels to query

.PARAMETER minSizeGB
    minimum size of directory / file to display in GB

.PARAMETER noTree
    output complete directory and file paths

.PARAMETER showFiles
    output file information

.PARAMETER logFile
    log output to log file

.PARAMETER quiet
    do not display output

.LINK
    https://raw.githubusercontent.com/jagilber/powershellScripts/master/directory-treesize.ps1
#>

[cmdletbinding()]
param(
    $directory = (get-location),
    $depth = 99,
    [float]$minSizeGB = .01,
    [switch]$notree,
    [switch]$showFiles,
    [string]$logFile,
    [switch]$quiet
)

$timer = get-date
$error.Clear()
$ErrorActionPreference = "silentlycontinue"
$sizeObjs = @{}
$drive = Get-PSDrive -Name $directory[0]
$writeDebug = $DebugPreference -ine "silentlycontinue"
$global:logStream = $null
$global:iterator = $null

function main()
{
    log-info "$($directory) drive total: $((($drive.free + $drive.used) / 1GB).ToString(`"F3`")) GB used: $(($drive.used / 1GB).ToString(`"F3`")) GB free: $(($drive.free / 1GB).ToString(`"F3`")) GB"
    log-info "all sizes in GB and are 'uncompressed' and *not* size on disk. enumerating $($directory) sub directories, please wait..." -ForegroundColor Yellow

    $directories = new-object collections.arraylist
    $directories.AddRange(@((Get-ChildItem -Directory -Path $directory -Depth $depth -Force -ErrorAction SilentlyContinue).FullName | Sort-Object))
    $directories.Insert(0, $directory.ToLower().trimend("\"))
    $previousDir = $null
    $totalFiles = 0

    foreach ($subdir in $directories)
    {
        log-info -debug -data "enumerating $($subDir)"
        $files = Get-ChildItem $subdir -Force -File -ErrorAction SilentlyContinue | Sort-Object -Descending -Property Length
        $sum = ($files | Measure-Object -Property Length -Sum)
        $size = [float]($sum.Sum / 1GB).ToString("F7")
    
        if ($showFiles -or $writeDebug)
        {
            log-info "$($subdir) file count: $($files.Count) folder file size bytes: $($sum.Sum)" -foregroundColor Cyan
            foreach ($file in $files)
            {
                $filePath = $file.name
                
                if ($notree)
                {
                    $filePath = $file.fullname    
                }

                if ($notree)
                {
                    log-info "$($filePath),$($file.length)"
                }
                else
                {
                    log-info "`t$($file.length.tostring().padleft(16)) $($filePath)"    
                }
            }
        }

        try
        {
            [void]$sizeObjs.Add($subdir.ToLower(), [float]$size)
            $totalFiles = $totalFiles + $sum.Count
            log-info -debug -data "adding $($subDir) $($size)"
        }
        catch
        {
            Write-Warning "error adding $($subdir)"                
        }
    }

    log-info "directory: $($directory) total files: $($totalFiles) total directories: $($sizeObjs.Count)"
    
    $sortedsizeObjs = $sizeObjs.GetEnumerator() | Sort-Object -Property Key
    $sortedBySize = ($sizeObjs.GetEnumerator() | Where-Object Value -ge $minSizeGB | Sort-Object -Property Value).Value
    $categorySize = [int]([math]::Floor($sortedBySize.Count / 6))
    $redmin = $sortedBySize[($categorySize * 6) - 1]
    $darkredmin = $sortedBySize[($categorySize * 5) - 1]
    $yellowmin = $sortedBySize[($categorySize * 4) - 1]
    $darkyellowmin = $sortedBySize[($categorySize * 3) - 1]
    $greenmin = $sortedBySize[($categorySize * 2) - 1]
    $darkgreenmin = $sortedBySize[($categorySize) - 1]

    [int]$i = 0

    foreach ($sortedDir in $directories)
    {
        log-info -debug -data "checking dir $($sortedDir)"
        $sortedDir = $sortedDir.ToLower()
        [float]$size = 0

        if (!$previousDir)
        {
            $pattern = "$([regex]::Escape($sortedDir))(\\|$)"
            $continueCheck = $true

            if ($i -ge $sortedsizeObjs.count)
            {
                # should only happen on root
                $i = 0
            }

            $i = $foundtree
            $firstmatch = $false

            while ($continueCheck -and $i -lt $sortedSizeObjs.Count)
            {
                $sizeObj = $sortedsizeObjs.get($i)
                
                if ([regex]::IsMatch($sizeObj.Key, $pattern, [text.regularexpressions.regexoptions]::IgnoreCase))
                {
                    $size += [float]$sizeObj.value
                    log-info -debug -data "match: pattern:$($pattern) $($sizeObj.Key),$([float]$sizeObj.Value)"

                    if (!$firstmatch)
                    {
                        $firstmatch = $true
                        $foundtree = $i
                    }
                }
                elseif ($firstmatch)
                {
                    $continueCheck = $false;
                }
                else
                {
                    log-info -debug -data "no match: $($sizeObj.Key) and $($pattern)"
                }

                $i++
            }

            log-info -debug -data "rollup size: $($sortedDir) $([float]$size)"
        }
        else
        {
            $size = [float]$sizeobjs.item($sortedDir)
        }

        switch ([float]$size)
        {
            {$_ -ge $redmin}
            {
                $foreground = "Red"; 
                break;
            }
            {$_ -gt $darkredmin}
            {
                $foreground = "DarkRed"; 
                break;
            }
            {$_ -gt $yellowmin}
            {
                $foreground = "Yellow"; 
                break;
            }
            {$_ -gt $darkyellowmin}
            {
                $foreground = "DarkYellow"; 
                break;
            }
            {$_ -gt $greenmin}
            {
                $foreground = "Green"; 
                break;
            }
            {$_ -gt $darkgreenmin}
            {
                $foreground = "DarkGreen"; 
            }

            default
            {
                $foreground = "Gray"; 
            }
        }

        if ($previousDir -and ([float]$size -lt [float]$minSizeGB))
        {
            log-info -debug -data "skipping below size dir $($sortedDir)"
            continue 
        }

        if ($previousDir)
        {
            if (!$notree)
            {
                while (!$sortedDir.Contains("$($previousDir)\"))
                {
                    $previousDir = "$([io.path]::GetDirectoryName($previousDir))"
                    log-info -debug -data "checking previous dir: $($previousDir)"
                }

                $output = $sortedDir.Replace("$($previousDir)\", "$(`" `" * $previousDir.Length)\")
            }
            else
            {
                $output = $sortedDir
            }

            log-info "$($output)`t$(($size).ToString(`"F3`")) GB" -ForegroundColor $foreground
        }
        else
        {
            # root
            log-info "$($sortedDir)`t$(($size).ToString(`"F3`")) GB" -ForegroundColor $foreground
        }

        $previousDir = "$($sortedDir)"
    }

    log-info "total time $((get-date) - $timer)"
}

function log-info($data, [switch]$debug, $foregroundColor = "White")
{
    if ($debug -and !$writeDebug)
    {
        return
    }

    if ($debug)
    {
        $foregroundColor = "Yellow"
    }

    if (!$quiet)
    {
        write-host $data -ForegroundColor $foregroundColor
    }

    if ($logFile)
    {
        if ($global:logStream -eq $null)
        {
            $global:logStream = new-object System.IO.StreamWriter ($logFile, $true)
        }

        $global:logStream.WriteLine($data)
    }
}

try
{
    main
}
catch
{
    write-host "main exception: $($error | out-string)"   
    $error.Clear()
}
finally
{
    if ($global:logStream)
    {
        $global:logStream.Close() 
        $global:logStream = $null
    }

}