#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$FullName = 'Alex Morgan',
    [string]$CompanyName = 'Northwind Research',
    [string]$SeedRoot = $env:USERPROFILE,
    [int]$DaysBack = 120,
    [switch]$SkipValidation,
    [switch]$SkipBookmarks,
    [switch]$SkipCatPictures,
    [switch]$SkipFullName,
    [Alias('ForceDownload')]
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-RandomTimestamp {
    param(
        [string]$Path,
        [int]$MaximumDaysBack
    )

    $days = Get-Random -Minimum 3 -Maximum ([Math]::Max(4, $MaximumDaysBack))
    $hours = Get-Random -Minimum 0 -Maximum 23
    $minutes = Get-Random -Minimum 0 -Maximum 59
    $timestamp = (Get-Date).AddDays(-$days).AddHours(-$hours).AddMinutes(-$minutes)

    $item = Get-Item -LiteralPath $Path -Force
    $item.CreationTime = $timestamp
    $item.LastWriteTime = $timestamp.AddMinutes((Get-Random -Minimum 1 -Maximum 180))
    $item.LastAccessTime = $timestamp.AddDays((Get-Random -Minimum 0 -Maximum 7))
}

function Set-SeedTimestamp {
    param(
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Set-RandomTimestamp -Path $Path -MaximumDaysBack $DaysBack
    }
}

function Write-SeedFile {
    param(
        [string]$Path,
        [string]$Content,
        [switch]$NoClobber
    )

    if ((Test-Path -LiteralPath $Path) -and $NoClobber -and -not $Force) {
        return
    }

    $parent = Split-Path -Path $Path -Parent
    New-Item -Path $parent -ItemType Directory -Force | Out-Null

    if ($PSCmdlet.ShouldProcess($Path, 'Write seeded file')) {
        [IO.File]::WriteAllText($Path, $Content, [Text.Encoding]::UTF8)
        Set-SeedTimestamp -Path $Path
    }
}

function New-RtfFile {
    param(
        [string]$Path,
        [string]$Title,
        [string[]]$Lines
    )

    $escapedLines = $Lines | ForEach-Object {
        ($_ -replace '\\', '\\' -replace '\{', '\{' -replace '\}', '\}') + '\par'
    }

    $content = @"
{\rtf1\ansi\deff0
{\fonttbl{\f0 Calibri;}}
\fs28\b $Title\b0\par
\fs22
$($escapedLines -join "`r`n")
}
"@

    Write-SeedFile -Path $Path -Content $content -NoClobber
}

function New-HtmlDocument {
    param(
        [string]$Path,
        [string]$Title,
        [string[]]$Paragraphs
    )

    $body = $Paragraphs | ForEach-Object { "<p>$([Security.SecurityElement]::Escape($_))</p>" }
    $content = @"
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>$Title</title>
  <style>
    body { font-family: Segoe UI, Arial, sans-serif; margin: 40px; color: #222; }
    h1 { font-size: 24px; }
    p { line-height: 1.45; }
  </style>
</head>
<body>
  <h1>$Title</h1>
  $($body -join "`r`n  ")
</body>
</html>
"@

    Write-SeedFile -Path $Path -Content $content -NoClobber
}

function New-CsvFile {
    param(
        [string]$Path,
        [string[]]$Rows
    )

    Write-SeedFile -Path $Path -Content ($Rows -join "`r`n") -NoClobber
}

function New-SimplePdf {
    param(
        [string]$Path,
        [string]$Title,
        [string[]]$Lines
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        return
    }

    $parent = Split-Path -Path $Path -Parent
    New-Item -Path $parent -ItemType Directory -Force | Out-Null

    $escapedTitle = $Title -replace '\\', '\\' -replace '\(', '\(' -replace '\)', '\)'
    $textLines = @("BT /F1 18 Tf 72 740 Td ($escapedTitle) Tj ET")
    $y = 705

    foreach ($line in $Lines) {
        $escapedLine = $line -replace '\\', '\\' -replace '\(', '\(' -replace '\)', '\)'
        $textLines += "BT /F1 11 Tf 72 $y Td ($escapedLine) Tj ET"
        $y -= 20
    }

    $stream = $textLines -join "`n"
    $objects = @(
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        "<< /Length $(([Text.Encoding]::ASCII.GetByteCount($stream))) >>`nstream`n$stream`nendstream"
    )

    $builder = [Text.StringBuilder]::new()
    [void]$builder.Append("%PDF-1.4`n")
    $offsets = @(0)

    for ($i = 0; $i -lt $objects.Count; $i++) {
        $offsets += [Text.Encoding]::ASCII.GetByteCount($builder.ToString())
        [void]$builder.Append("$($i + 1) 0 obj`n$($objects[$i])`nendobj`n")
    }

    $xrefOffset = [Text.Encoding]::ASCII.GetByteCount($builder.ToString())
    [void]$builder.Append("xref`n0 $($objects.Count + 1)`n")
    [void]$builder.Append("0000000000 65535 f `n")

    for ($i = 1; $i -lt $offsets.Count; $i++) {
        [void]$builder.Append(("{0:0000000000} 00000 n `n" -f $offsets[$i]))
    }

    [void]$builder.Append("trailer`n<< /Root 1 0 R /Size $($objects.Count + 1) >>`nstartxref`n$xrefOffset`n%%EOF")

    if ($PSCmdlet.ShouldProcess($Path, 'Create seeded PDF')) {
        [IO.File]::WriteAllBytes($Path, [Text.Encoding]::ASCII.GetBytes($builder.ToString()))
        Set-SeedTimestamp -Path $Path
    }
}

function New-ZipBasedFile {
    param(
        [string]$Path,
        [hashtable]$Entries
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        return
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem

    $parent = Split-Path -Path $Path -Parent
    New-Item -Path $parent -ItemType Directory -Force | Out-Null

    if ($PSCmdlet.ShouldProcess($Path, 'Create seeded Open XML file')) {
        $tempPath = Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null

        try {
            foreach ($entry in $Entries.GetEnumerator()) {
                $entryPath = Join-Path $tempPath $entry.Key
                New-Item -Path (Split-Path -Path $entryPath -Parent) -ItemType Directory -Force | Out-Null
                [IO.File]::WriteAllText($entryPath, $entry.Value, [Text.Encoding]::UTF8)
            }

            if (Test-Path -LiteralPath $Path) {
                Remove-Item -LiteralPath $Path -Force
            }

            [IO.Compression.ZipFile]::CreateFromDirectory($tempPath, $Path)
        } finally {
            if (Test-Path -LiteralPath $tempPath) {
                Remove-Item -LiteralPath $tempPath -Recurse -Force
            }
        }

        Set-SeedTimestamp -Path $Path
    }
}

function New-DocxFile {
    param(
        [string]$Path,
        [string]$Title,
        [string[]]$Paragraphs
    )

    $body = @("<w:p><w:r><w:t>$([Security.SecurityElement]::Escape($Title))</w:t></w:r></w:p>")

    foreach ($paragraph in $Paragraphs) {
        $body += "<w:p><w:r><w:t>$([Security.SecurityElement]::Escape($paragraph))</w:t></w:r></w:p>"
    }

    New-ZipBasedFile -Path $Path -Entries @{
        '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
        '_rels\.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
        'word\document.xml' = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><w:document xmlns:w=`"http://schemas.openxmlformats.org/wordprocessingml/2006/main`"><w:body>$($body -join '')<w:sectPr/></w:body></w:document>"
    }
}

function New-XlsxFile {
    param(
        [string]$Path,
        [string[][]]$Rows
    )

    $rowXml = @()
    $rowNumber = 1

    foreach ($row in $Rows) {
        $cells = @()
        $columnNumber = 1

        foreach ($cell in $row) {
            $columnName = [char](64 + $columnNumber)
            $cells += "<c r=`"$columnName$rowNumber`" t=`"inlineStr`"><is><t>$([Security.SecurityElement]::Escape($cell))</t></is></c>"
            $columnNumber++
        }

        $rowXml += "<row r=`"$rowNumber`">$($cells -join '')</row>"
        $rowNumber++
    }

    New-ZipBasedFile -Path $Path -Entries @{
        '[Content_Types].xml' = '<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>'
        '_rels\.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>'
        'xl\workbook.xml' = '<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Sheet1" sheetId="1" r:id="rId1"/></sheets></workbook>'
        'xl\_rels\workbook.xml.rels' = '<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/></Relationships>'
        'xl\worksheets\sheet1.xml' = "<?xml version=`"1.0`" encoding=`"UTF-8`"?><worksheet xmlns=`"http://schemas.openxmlformats.org/spreadsheetml/2006/main`"><sheetData>$($rowXml -join '')</sheetData></worksheet>"
    }
}

function New-SeedImage {
    param(
        [string]$Path,
        [string]$Label,
        [string]$Format = 'Png'
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        return
    }

    Add-Type -AssemblyName System.Drawing

    $parent = Split-Path -Path $Path -Parent
    New-Item -Path $parent -ItemType Directory -Force | Out-Null

    if ($PSCmdlet.ShouldProcess($Path, 'Create generated image')) {
        $bitmap = [Drawing.Bitmap]::new(1280, 720)
        $graphics = [Drawing.Graphics]::FromImage($bitmap)

        try {
            $background = [Drawing.Color]::FromArgb((Get-Random -Minimum 80 -Maximum 210), (Get-Random -Minimum 80 -Maximum 210), (Get-Random -Minimum 80 -Maximum 210))
            $graphics.Clear($background)

            $font = [Drawing.Font]::new('Segoe UI', 32, [Drawing.FontStyle]::Regular)
            $smallFont = [Drawing.Font]::new('Segoe UI', 18, [Drawing.FontStyle]::Regular)
            $brush = [Drawing.SolidBrush]::new([Drawing.Color]::White)

            $graphics.DrawString($Label, $font, $brush, 80, 90)
            $graphics.DrawString("Generated sample image - $FullName", $smallFont, $brush, 82, 155)

            for ($i = 0; $i -lt 12; $i++) {
                $pen = [Drawing.Pen]::new([Drawing.Color]::FromArgb(100, 255, 255, 255), (Get-Random -Minimum 2 -Maximum 8))
                $graphics.DrawEllipse($pen, (Get-Random -Minimum 40 -Maximum 1100), (Get-Random -Minimum 220 -Maximum 620), (Get-Random -Minimum 40 -Maximum 180), (Get-Random -Minimum 40 -Maximum 180))
                $pen.Dispose()
            }

            if ($Format -eq 'Jpeg') {
                $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Jpeg)
            } else {
                $bitmap.Save($Path, [Drawing.Imaging.ImageFormat]::Png)
            }
        } finally {
            $graphics.Dispose()
            $bitmap.Dispose()
        }

        Set-SeedTimestamp -Path $Path
    }
}

function New-SeedZip {
    param(
        [string]$ZipPath,
        [string[]]$SourcePaths
    )

    if ((Test-Path -LiteralPath $ZipPath) -and -not $Force) {
        return
    }

    $parent = Split-Path -Path $ZipPath -Parent
    New-Item -Path $parent -ItemType Directory -Force | Out-Null

    if ($PSCmdlet.ShouldProcess($ZipPath, 'Create seeded ZIP archive')) {
        if (Test-Path -LiteralPath $ZipPath) {
            Remove-Item -LiteralPath $ZipPath -Force
        }

        Compress-Archive -Path $SourcePaths -DestinationPath $ZipPath -Force
        Set-SeedTimestamp -Path $ZipPath
    }
}

function Copy-CatPictures {
    param(
        [string]$DestinationFolder
    )

    if ($SkipCatPictures) {
        return
    }

    $sourceFolder = Join-Path $PSScriptRoot '..\assets\seed-files\cats'

    if (-not (Test-Path -LiteralPath $sourceFolder)) {
        Write-Warning "Cat picture source folder was not found at $sourceFolder."
        return
    }

    New-Item -Path $DestinationFolder -ItemType Directory -Force | Out-Null
    $catPictures = Get-ChildItem -Path $sourceFolder -File -Filter '*.jpg'

    foreach ($catPicture in $catPictures) {
        $path = Join-Path $DestinationFolder $catPicture.Name

        if ((Test-Path -LiteralPath $path) -and -not $Force) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($path, "Copy seeded cat picture from $($catPicture.FullName)")) {
            Copy-Item -Path $catPicture.FullName -Destination $path -Force
            Set-SeedTimestamp -Path $path
        }
    }
}

function Set-JsonFile {
    param(
        [string]$Path,
        [object]$Object
    )

    $parent = Split-Path -Path $Path -Parent
    New-Item -Path $parent -ItemType Directory -Force | Out-Null
    $json = $Object | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($Path, $json, [Text.Encoding]::UTF8)
    Set-SeedTimestamp -Path $Path
}

function Add-ChromiumBookmarks {
    param(
        [string]$BrowserName,
        [string]$BookmarksPath
    )

    if ((Test-Path -LiteralPath $BookmarksPath) -and -not $Force) {
        Write-Host "$BrowserName bookmarks already exist; leaving them untouched. Use -Force to overwrite."
        return
    }

    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() * 1000
    $bookmarkUrls = @(
        @{ name = 'Gmail'; url = 'https://mail.google.com/' },
        @{ name = 'Outlook'; url = 'https://outlook.live.com/' },
        @{ name = 'Amazon'; url = 'https://www.amazon.com/' },
        @{ name = 'YouTube'; url = 'https://www.youtube.com/' },
        @{ name = 'Wikipedia'; url = 'https://www.wikipedia.org/' },
        @{ name = 'Microsoft Support'; url = 'https://support.microsoft.com/' },
        @{ name = 'GitHub'; url = 'https://github.com/' },
        @{ name = 'Weather'; url = 'https://weather.com/' },
        @{ name = 'Local Bank'; url = 'https://www.example.com/banking' }
    )

    $children = @()
    $id = 10

    foreach ($bookmark in $bookmarkUrls) {
        $children += [ordered]@{
            date_added = "$($now - (Get-Random -Minimum 100000000 -Maximum 9000000000))"
            guid = [guid]::NewGuid().ToString()
            id = "$id"
            name = $bookmark.name
            type = 'url'
            url = $bookmark.url
        }
        $id++
    }

    $bookmarks = [ordered]@{
        checksum = ''
        roots = [ordered]@{
            bookmark_bar = [ordered]@{
                children = $children
                date_added = "$now"
                date_last_used = '0'
                date_modified = "$now"
                guid = [guid]::NewGuid().ToString()
                id = '1'
                name = 'Bookmarks bar'
                type = 'folder'
            }
            other = [ordered]@{
                children = @()
                date_added = "$now"
                date_last_used = '0'
                date_modified = '0'
                guid = [guid]::NewGuid().ToString()
                id = '2'
                name = 'Other bookmarks'
                type = 'folder'
            }
            synced = [ordered]@{
                children = @()
                date_added = "$now"
                date_last_used = '0'
                date_modified = '0'
                guid = [guid]::NewGuid().ToString()
                id = '3'
                name = 'Mobile bookmarks'
                type = 'folder'
            }
        }
        version = 1
    }

    if ($PSCmdlet.ShouldProcess($BookmarksPath, "Seed $BrowserName bookmarks")) {
        Set-JsonFile -Path $BookmarksPath -Object $bookmarks
        Write-Host "Seeded $BrowserName bookmarks at $BookmarksPath"
    }
}

function Set-LocalUserFullName {
    if ($SkipFullName) {
        return
    }

    if (-not (Test-IsAdministrator)) {
        Write-Warning 'Skipping local full name update because this PowerShell session is not elevated.'
        return
    }

    if ($PSCmdlet.ShouldProcess($env:USERNAME, "Set local full name to $FullName")) {
        & net.exe user $env:USERNAME /fullname:"$FullName" | Out-Host
    }
}

$SeedRoot = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($SeedRoot)

$desktop = Join-Path $SeedRoot 'Desktop'
$documents = Join-Path $SeedRoot 'Documents'
$downloads = Join-Path $SeedRoot 'Downloads'
$pictures = Join-Path $SeedRoot 'Pictures'
$screenshots = Join-Path $pictures 'Screenshots'
$cats = Join-Path $pictures 'Cats'
$work = Join-Path $documents 'Work'
$personal = Join-Path $documents 'Personal'
$software = Join-Path $downloads 'Software'

foreach ($folder in @($desktop, $documents, $downloads, $pictures, $screenshots, $cats, $work, $personal, $software)) {
    if ($PSCmdlet.ShouldProcess($folder, 'Create user seed folder')) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
        Set-SeedTimestamp -Path $folder
    }
}

Set-LocalUserFullName

New-RtfFile -Path (Join-Path $work 'meeting-notes-q2.rtf') -Title 'Q2 Planning Notes' -Lines @(
    "Attendees: $FullName, Jordan, Sam",
    "Review open action items for $CompanyName.",
    'Follow up with vendor about renewal pricing.',
    'Prepare updated spreadsheet before Friday.'
)

New-DocxFile -Path (Join-Path $work 'project-outline.docx') -Title 'Project Outline' -Paragraphs @(
    "$CompanyName internal planning notes.",
    'Draft timeline for vendor review and follow-up tasks.',
    'Open questions: pricing, support terms, and delivery window.'
)

New-DocxFile -Path (Join-Path $personal 'resume-draft.docx') -Title "$FullName Resume Draft" -Paragraphs @(
    'Summary: Operations and support background with technical troubleshooting experience.',
    'Skills: Windows, documentation, customer communication, scheduling.',
    'Notes: Update references before sending.'
)

New-RtfFile -Path (Join-Path $personal 'resume-draft.rtf') -Title "$FullName Resume Draft" -Lines @(
    'Summary: Operations and support background with technical troubleshooting experience.',
    'Skills: Windows, documentation, customer communication, scheduling.',
    'Notes: Update references before sending.'
)

New-RtfFile -Path (Join-Path $desktop 'todo-list.rtf') -Title 'To Do' -Lines @(
    'Pay internet bill',
    'Confirm dentist appointment',
    'Pick up groceries',
    'Review downloaded documents'
)

New-CsvFile -Path (Join-Path $work 'expense-tracker.csv') -Rows @(
    'Date,Category,Description,Amount',
    '2026-02-04,Meals,Team lunch,84.17',
    '2026-02-18,Travel,Parking downtown,18.00',
    '2026-03-01,Office,Supplies,42.35',
    '2026-03-15,Software,Cloud storage,9.99'
)

New-CsvFile -Path (Join-Path $personal 'home-budget.csv') -Rows @(
    'Month,Rent,Utilities,Groceries,Subscriptions',
    'January,1450,183.22,429.10,49.96',
    'February,1450,176.88,451.31,49.96',
    'March,1450,169.42,438.22,55.95'
)

New-XlsxFile -Path (Join-Path $work 'expense-tracker.xlsx') -Rows @(
    @('Date', 'Category', 'Description', 'Amount'),
    @('2026-02-04', 'Meals', 'Team lunch', '84.17'),
    @('2026-02-18', 'Travel', 'Parking downtown', '18.00'),
    @('2026-03-01', 'Office', 'Supplies', '42.35'),
    @('2026-03-15', 'Software', 'Cloud storage', '9.99')
)

New-XlsxFile -Path (Join-Path $personal 'home-budget.xlsx') -Rows @(
    @('Month', 'Rent', 'Utilities', 'Groceries', 'Subscriptions'),
    @('January', '1450', '183.22', '429.10', '49.96'),
    @('February', '1450', '176.88', '451.31', '49.96'),
    @('March', '1450', '169.42', '438.22', '55.95')
)

New-SimplePdf -Path (Join-Path $downloads 'invoice-1042.pdf') -Title 'Invoice 1042' -Lines @(
    'Vendor: Contoso Office Supply',
    'Amount due: $128.44',
    'Due date: 2026-04-18',
    "Prepared for: $FullName"
)

New-SimplePdf -Path (Join-Path $documents 'travel-itinerary.pdf') -Title 'Travel Itinerary' -Lines @(
    'Trip: Denver conference',
    'Hotel: Downtown booking confirmation saved separately.',
    'Reminder: Check in after 3 PM.'
)

New-HtmlDocument -Path (Join-Path $downloads 'boarding-pass-summary.html') -Title 'Boarding Pass Summary' -Paragraphs @(
    'This saved page is a placeholder for a recent travel confirmation.',
    'Flight: CLT to DEN. Confirmation: HX4P2Q.',
    'Reminder: Bring ID and check bag size before leaving.'
)

New-HtmlDocument -Path (Join-Path $documents 'benefits-open-enrollment.html') -Title 'Benefits Open Enrollment Notes' -Paragraphs @(
    'Open enrollment notes copied from the HR portal.',
    'Compare medical plan options before the deadline.',
    'Ask payroll about HSA contribution limits.'
)

New-HtmlDocument -Path (Join-Path $downloads 'printer-manual.html') -Title 'Printer Manual' -Paragraphs @(
    'Quick setup notes for a home office printer.',
    'Connect printer to Wi-Fi before adding it in Windows settings.',
    'Replace ink cartridge when print quality warning appears.'
)

Write-SeedFile -Path (Join-Path $downloads 'software-install-notes.txt') -Content @"
Installed software notes

- Chrome and Firefox installed for browser testing.
- LibreOffice handles documents and spreadsheets.
- 7-Zip handles downloaded archives.
- VLC handles media playback.
"@ -NoClobber

Write-SeedFile -Path (Join-Path $software 'readme.txt') -Content @"
Downloaded installers and notes kept here temporarily.
Clean this folder after setup is complete.
"@ -NoClobber

New-SeedImage -Path (Join-Path $pictures 'vacation-photo-001.jpg') -Label 'Beach Trip 2026' -Format 'Jpeg'
New-SeedImage -Path (Join-Path $pictures 'family-photo-002.jpg') -Label 'Weekend Cookout' -Format 'Jpeg'
New-SeedImage -Path (Join-Path $screenshots 'screenshot-portal-login.png') -Label 'Portal Login Screenshot' -Format 'Png'
New-SeedImage -Path (Join-Path $screenshots 'screenshot-order-confirmation.png') -Label 'Order Confirmation' -Format 'Png'
Copy-CatPictures -DestinationFolder $cats

$zipSourcesOne = @(
    (Join-Path $work 'meeting-notes-q2.rtf'),
    (Join-Path $work 'expense-tracker.csv')
)
$zipSourcesTwo = @(
    (Join-Path $pictures 'vacation-photo-001.jpg'),
    (Join-Path $pictures 'family-photo-002.jpg')
)

New-SeedZip -ZipPath (Join-Path $downloads 'q2-reports.zip') -SourcePaths $zipSourcesOne
New-SeedZip -ZipPath (Join-Path $downloads 'photos-march.zip') -SourcePaths $zipSourcesTwo

if (-not $SkipBookmarks) {
    Add-ChromiumBookmarks -BrowserName 'Chrome' -BookmarksPath (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Bookmarks')
    Add-ChromiumBookmarks -BrowserName 'Edge' -BookmarksPath (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Bookmarks')
}

Write-Host 'User profile seeding completed.'
