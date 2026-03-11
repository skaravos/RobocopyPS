Function Invoke-RobocopyParser {
    <#
    .SYNOPSIS
    Parse Robocopy.exe output

    .DESCRIPTION
    This function will try and parse the output from when you run Robocopy.exe and give you information about what PowerShell stream should be used.

    .EXAMPLE
    PS$ >
    #>


    [CmdletBinding()]

    PARAM (
        # Robocopy text
        [Parameter(ValueFromPipeline = $true)]
        [String]
        $InputObject,

        # What unit the sizes are shown as
        [ValidateSet('Auto', 'PB', 'TB', 'GB', 'MB', 'KB', 'Bytes')]
        [String]$Unit = 'Auto',

        # Number of digits after decimal point in rounded numbers.
        [ValidateRange(1,28)]
        [System.Int64]$Precision = 4,

        # Arguments that were used during the call to Robocopy.exe
        # NOTE: currently only used for inclusion in the output object
        [string[]]$RoboArgs
    )

    begin {
        # We have a corresponding $EndTime to measure how long the code ran for
        $StartTime = $(Get-Date)

        # Regex for catching all text that will be sent to Error Stream
        $ErrorFilter = @(
            "The filename, directory name, or volume label syntax is incorrect.",
            "\*\*\*\*\*  You need these to perform Backup copies \(\/B or \/ZB\).",
            "ERROR \d{1,3} \(0x\d\w{1,11}\)",
            "ERROR : ",
            "ERROR: RETRY LIMIT EXCEEDED.",
            "ERROR 123"
        ) -join '|'

        # Regex for catching all text that will be sent to Warning Stream
        $WarningFilter = @(
            "Waiting \d+ seconds... Retrying..."
            "Pausing to wait for free space"
        ) -join '|'

        # Regex filter used for finding strings we want to handle in Robocopy output. This is also used when we find specific strings in the output
        [regex] $HeaderRegex = '\s+Total\s*Copied\s+Skipped\s+Mismatch\s+FAILED\s+Extras'
        [regex] $DirLineRegex = 'Dirs\s*:\s*(?<Total>\d+)\s+(?<Copied>\d+)\s+(?<Skipped>\d+)\s+(?<Mismatch>\d+)\s+(?<Failed>\d+)\s+(?<Extras>\d+)'
        [regex] $FileLineRegex = 'Files\s*:\s*(?<Total>\d+)\s+(?<Copied>\d+)\s+(?<Skipped>\d+)\s+(?<Mismatch>\d+)\s+(?<Failed>\d+)\s+(?<Extras>\d+)'
        [regex] $BytesLineRegex = 'Bytes\s*:\s*(?<Total>\d+)\s+(?<Copied>\d+)\s+(?<Skipped>\d+)\s+(?<Mismatch>\d+)\s+(?<Failed>\d+)\s+(?<Extras>\d+)'
        [regex] $TimeLineRegex = 'Times\s*:\s*(?<TimeElapsed>\d+).*'
        [regex] $EndedLineRegex = 'Ended\s*:\s*(?<EndedTime>.+)'
        [regex] $SpeedLineRegex = 'Speed\s*:\s*(?<Bytes>\d[\d\s,]*)\s+Bytes\/sec'
        [regex] $JobSummaryEndLineRegex = '[-]{78}'
        [regex] $SpeedInMinutesRegex = 'Speed\s:\s+(\d+).(\d+)\sMegaBytes\/min'
        [regex] $FileInfoRegex = "\s*(?<Status>[\*A-Za-z]+|([\*A-Za-z]+\s+[A-Za-z]+)|)\s+(?<Size>[0-9]+)\s+(?<TimeStamp>([0-9]{4}\/[01][0-9]\/[0-3][0-9])\s+([0-2][0-9]:[0-5][0-9]:[0-5][0-9]))\s+(?<path>.+)\s*$"
    }

    Process {
        try {

            If ($InputObject -match $ErrorFilter -or $ForceNextLineIntoError -eq $true) {
                # If any error happened we set $ErrorOccurred to $true.
                # This is used in the output Property Success. If $ErrorOccurred is $true we set Success to $false
                $ErrorOccurred = $true

                If ($null -eq $Message) {
                    $Message = $InputObject
                    $ForceNextLineIntoError = $true
                }
                else {
                    $LastMessage = ("{0}. {1}" -f $Message, $InputObject.trim())
                    $ForceNextLineIntoError = $false
                    $Message = $null
                    $SplitMessage = $LastMessage -split '(ERROR \d \(0x\d{1,11}\) )'
                    [PSCustomObject]@{
                        Value     = $LastMessage
                        Stream    = "Error"
                        Exception = $SplitMessage[2]
                        ErrorID   = $SplitMessage[1]
                    }
                }
            }

            else {
                # Some we will just assign to variables and don't use or don't do anything with
                Switch -Regex ($InputObject) {
                    $FileInfoRegex {
                        $TimeStamp = [DateTime]::Parse($Matches.TimeStamp)
                        $Extension = [System.IO.Path]::GetExtension($Matches.Path)
                        $FileName  = [System.IO.Path]::GetFileName($Matches.Path)

                        [PSCustomObject]@{
                            Extension = $Extension
                            Name      = $FileName
                            FullName  = $Matches.Path
                            Length    = $Matches.Size
                            TimeStamp = $TimeStamp
                            Status    = $Matches.Status
                            Stream    = "Verbose"
                        }
                        break
                    }
                    $WarningFilter {
                        [PSCustomObject]@{
                            Value  = $InputObject
                            Stream = "Warning"
                        }
                        break
                    }
                    #------------------------------------------------------------------------------
                    $JobSummaryEndLineRegex {
                        # not used
                        break
                    }
                    #                  Total     Copied      Skipped  Mismatch    FAILED     Extras
                    $HeaderRegex {
                        # not used
                        break
                    }
                    #    Dirs :            0          0            0         0         0          0
                    $DirLineRegex {
                        $TotalDirs          = $Matches.Total
                        $TotalDirCopied     = $Matches.Copied
                        $TotalDirIgnored    = $Matches.Skipped
                        $TotalDirMismatched = $Matches.Mismatch
                        $TotalDirFailed     = $Matches.Failed
                        $TotalDirExtra      = $Matches.Extras
                        break
                    }
                    #   Files :            0          0            0         0         0          0
                    $FileLineRegex {
                        $TotalFiles          = $Matches.Total
                        $TotalFileCopied     = $Matches.Copied
                        $TotalFileIgnored    = $Matches.Skipped
                        $TotalFileMismatched = $Matches.Mismatch
                        $TotalFileFailed     = $Matches.Failed
                        $TotalFileExtra      = $Matches.Extras
                        break
                    }
                    #   Bytes :            0          0            0         0         0          0
                    $BytesLineRegex {
                        $TotalBytes           = $Matches.Total
                        $TotalBytesCopied     = $Matches.Copied
                        $TotalBytesIgnored    = $Matches.Skipped
                        $TotalBytesMismatched = $Matches.Mismatch
                        $TotalBytesFailed     = $Matches.Failed
                        $TotalBytesExtra      = $Matches.Extras
                        break
                    }
                    #   Times :      0:00:00    0:00:00                          0:00:00    0:00:00
                    $TimeLineRegex {
                        # [TimeSpan]$TotalDuration, [TimeSpan]$CopyDuration, [TimeSpan]$FailedDuration, [TimeSpan]$ExtraDuration = $PSitem | Select-String -Pattern '\d?\d\:\d{2}\:\d{2}' -AllMatches | ForEach-Object { $PSitem.Matches } | ForEach-Object { $PSitem.Value }
                        break
                    }
                    #   Speed :               97152264 Bytes/sec.
                    #   Speed :             97 152 264 Bytes/sec.
                    $SpeedLineRegex {
                        $TotalSpeedBytes = $Matches.Bytes -replace '[\s,]', '' #<- Win11 puts spaces in the byte count
                        break
                    }
                    #   Speed :               5559.097 MegaBytes/min.
                    $SpeedInMinutesRegex {
                        # not used
                        break
                    }
                    #   Ended : March 11, 2026 12:23:23 PM
                    $EndedLineRegex {
                        # not used
                        break
                    }
                    default {
                        # Write all strings to Information stream that we dont have rules for
                        [PSCustomObject]@{
                            Value  = $InputObject
                            Stream = 'Information'
                        }
                    }
                }
            }

        }
        catch {
            Write-Warning "cannot parse output line: ${InputObject}: $($PSItem.Exception.Message)"
            [PSCustomObject]@{
                Value  = $InputObject
                Stream = "Information"
            }
        }
    }

    end {

        # Exit Code lookup "table"
        $LastExitCodeMessage = switch ($LASTEXITCODE) {
            0 { 'No files were copied. No failure was encountered. No files were mismatched. The files already exist in the destination directory; therefore, the copy operation was skipped.' }
            1 { 'All files were copied successfully.' }
            2 { 'There are some additional files in the destination directory that are not present in the source directory. No files were copied.' }
            3 { 'Some files were copied. Additional files were present. No failure was encountered.' }
            4 { 'Some Mismatched files or directories were detected. Examine the output log. Housekeeping might be required.' }
            5 { 'Some files were copied. Some files were mismatched. No failure was encountered.' }
            6 { 'Additional files and mismatched files exist. No files were copied and no failures were encountered. This means that the files already exist in the destination directory.' }
            7 { 'Files were copied, a file mismatch was present, and additional files were present.' }
            8 { 'Several files did not copy.(copy errors occurred and the retry limit was exceeded). Check these errors further.' }
            9 { 'Some files did copy, but copy errors occurred and the retry limit was exceeded. Check these errors further.' }
            10 { 'Copy errors occurred and the retry limit was exceeded. Some Extra files or directories were detected.' }
            11 { 'Some files were copied. Copy errors occurred and the retry limit was exceeded. Some Extra files or directories were detected.' }
            12 { 'Copy errors occurred and the retry limit was exceeded. Some Mismatched files or directories were detected.' }
            13 { 'Some files were copied. Copy errors occurred and the retry limit was exceeded. Some Mismatched files or directories were detected.' }
            14 { 'Copy errors occurred and the retry limit was exceeded. Some Mismatched files or directories were detected. Some Extra files or directories were detected.' }
            15 { 'Some files were copied. Copy errors occurred and the retry limit was exceeded. Some Mismatched files or directories were detected. Some Extra files or directories were detected.' }
            16 { 'Robocopy did not copy any files. Either a usage error or an error due to insufficient access privileges on the source or destination directories.' }
            default { '[WARNING]No message associated with this exit code. ExitCode: {0}' -f $LASTEXITCODE }
        }

        # We have a corresponding $StartTime to measure how long the code ran for
        $EndTime = $(Get-Date)

        $FormatSpeedSplatting = @{
            Unit = $Unit
            Precision = $Precision
        }

        [PSCustomObject]@{
            'Source'                = [System.IO.DirectoryInfo]$Source
            'Destination'           = [System.IO.DirectoryInfo]$Destination
            'Command'               = 'Robocopy.exe ' + ($RoboArgs -join " ")
            'DirCount'              = [int]$TotalDirs
            'FileCount'             = [int]$TotalFiles
            #'Duration'     = $TotalDuration
            'DirCopied'             = [int]$TotalDirCopied
            'FileCopied'            = [int]$TotalFileCopied
            #'CopyDuration' = $CopyDuration
            'DirIgnored'            = [int]$TotalDirIgnored
            'FileIgnored'           = [int]$TotalFileIgnored
            'DirMismatched'         = [int]$TotalDirMismatched
            'FileMismatched'        = [int]$TotalFileMismatched
            'DirFailed'             = [int]$TotalDirFailed
            'FileFailed'            = [int]$TotalFileFailed
            #'FailedDuration'   = $FailedDuration
            'DirExtra'              = [int]$TotalDirExtra
            'FileExtra'             = [int]$TotalFileExtra
            #'ExtraDuration'    = $ExtraDuration
            'TotalTime'             = "{0:g}" -f ($EndTime - $StartTime)
            'StartedTime'           = [datetime]$StartTime
            'EndedTime'             = [datetime]$EndTime
            'TotalSize'             = (Format-SpeedHumanReadable $TotalBytes @FormatSpeedSplatting)
            'TotalSizeCopied'       = (Format-SpeedHumanReadable $TotalBytesCopied @FormatSpeedSplatting)
            'TotalSizeIgnored'      = (Format-SpeedHumanReadable $TotalBytesIgnored @FormatSpeedSplatting)
            'TotalSizeMismatched'   = (Format-SpeedHumanReadable $TotalBytesMismatched @FormatSpeedSplatting)
            'TotalSizeFailed'       = (Format-SpeedHumanReadable $TotalBytesFailed @FormatSpeedSplatting)
            'TotalSizeExtra'        = (Format-SpeedHumanReadable $TotalBytesExtra @FormatSpeedSplatting)
            'TotalSizeBytes'        = [int64]$TotalBytes
            'Speed'                 = (Format-SpeedHumanReadable $TotalSpeedBytes @FormatSpeedSplatting) + '/s'
            'ExitCode'              = $LASTEXITCODE
            'Success'               = If ($LASTEXITCODE -lt 8 -and $ErrorOccurred -ne $true) { $true } else { $false }
            'LastExitCodeMessage'   = [string]$LastExitCodeMessage
        }
    }
}
