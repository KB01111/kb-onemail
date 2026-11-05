param([switch]$Publish, [switch]$SelfTest)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$PSNativeCommandUseErrorActionPreference = $true

function Invoke-Checked([string]$Command, [string[]]$Arguments) {
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Command failed ($LASTEXITCODE)" }
}

function Read-ChannelVersion($Content) {
    $json = if ($Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($Content) } else { [string]$Content }
    $manifest = $json | ConvertFrom-Json
    if ($manifest.version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid published channel version' }
    return [version]$manifest.version
}

if ($SelfTest) {
    if ($Publish) { throw 'SelfTest cannot publish' }
    $json = '{"version":"0.3.370"}'
    foreach ($content in @($json, [Text.Encoding]::UTF8.GetBytes($json))) {
        if ((Read-ChannelVersion $content) -ne [version]'0.3.370') { throw 'Channel decoding failed' }
        if ((Read-ChannelVersion $content) -lt [version]'0.3.369') { throw 'Channel regression comparison failed' }
    }
    foreach ($invalid in @('{"version":"main"}', '{}', 'not-json')) {
        $rejected = $false
        try { $null = Read-ChannelVersion $invalid } catch { $rejected = $true }
        if (!$rejected) { throw 'Malformed channel was accepted' }
    }
    Write-Output 'Channel JSON/text and binary decoding, version ordering and malformed input checks passed.'
    return
}

$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
$override = Join-Path ([IO.Path]::GetTempPath()) ("kb-onemail-release-" + [guid]::NewGuid() + '.json')
$previousKey = $env:TAURI_SIGNING_PRIVATE_KEY
$previousPassword = $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD
$previousVersion = $env:KB_ONEMAIL_RELEASE_VERSION
try {
    if (git status --porcelain) { throw 'Release requires a clean checkout' }
    Invoke-Checked git @('fetch', 'origin', 'main')
    $commit = (git rev-parse HEAD).Trim()
    if ($commit -ne (git rev-parse origin/main).Trim()) { throw 'Release must use the latest origin/main commit' }
    $revision = [int](git rev-list --first-parent --count HEAD)
    $config = Get-Content -Raw desktop/src-tauri/tauri.conf.json | ConvertFrom-Json
    $base = [version]$config.version
    $version = "$($base.Major).$($base.Minor).$revision"
    $tag = "desktop-v$version"
    $env:KB_ONEMAIL_RELEASE_VERSION = $version
    [IO.File]::WriteAllText($override, (@{ version = $version } | ConvertTo-Json))

    if (!$env:TAURI_SIGNING_PRIVATE_KEY) {
        $signingDir = Join-Path $env:USERPROFILE '.config/kb-onemail/signing'
        $protected = [Convert]::FromBase64String([IO.File]::ReadAllText((Join-Path $signingDir 'preview.password.dpapi')))
        $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = [Text.Encoding]::UTF8.GetString(
            [Security.Cryptography.ProtectedData]::Unprotect($protected, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser))
        $env:TAURI_SIGNING_PRIVATE_KEY = [IO.File]::ReadAllText((Join-Path $signingDir 'preview.key'))
    }
    if (!$env:TAURI_SIGNING_PRIVATE_KEY) { throw 'Existing updater signing credentials are required' }
    Invoke-Checked bun @('install', '--frozen-lockfile')
    Invoke-Checked bun @('run', 'typecheck')
    Invoke-Checked bun @('run', 'lint')
    Invoke-Checked bun @('test')
    Invoke-Checked bun @('run', 'build')
    Invoke-Checked bun @('run', 'test:runtime')
    Invoke-Checked cargo @('test', '--manifest-path', 'desktop/src-tauri/Cargo.toml', '--locked', '-j', '2')
    Push-Location desktop
    try {
        Invoke-Checked bun @('install', '--frozen-lockfile')
        Invoke-Checked bunx @('--no-install', 'tauri', 'build', '--config', $override, '--bundles', 'nsis', '--', '--locked', '-j', '2')
    } finally { Pop-Location }
    $target = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $root 'desktop/src-tauri/target' }
    $installer = Join-Path $target "release/bundle/nsis/KB OneMail_${version}_x64-setup.exe"
    if (!(Test-Path -LiteralPath $installer)) { throw 'Expected versioned NSIS installer is missing' }
    Invoke-Checked cargo @('run', '--manifest-path', 'desktop/src-tauri/Cargo.toml', '--example', 'verify-installer', '--locked', '-j', '2', '--', $installer)
    Invoke-Checked bun @('scripts/desktop-release.ts', $installer, $tag, $commit)
    $manifestPath = Join-Path (Split-Path $installer -Parent) 'latest.json'
    if (!$Publish) { Write-Output "Verified local release: $installer"; return }

    # Do not release a build overtaken by a newer main revision.
    Invoke-Checked git @('fetch', 'origin', 'main')
    if ($commit -ne (git rev-parse origin/main).Trim()) { throw 'Main changed during the build; rebuild the latest revision' }
    $repo = 'KB01111/kb-onemail'
    $existing = gh api "repos/$repo/releases?per_page=100" | ConvertFrom-Json
    $immutable = @($existing | Where-Object tag_name -EQ $tag)
    if ($immutable.Count) { throw 'Versioned release already exists; do not replace signed assets' }
    $notes = "KB OneMail $version Windows personal preview. Blue taskbar/tray icon, native Mica titlebar, signed in-app updates. Source: $commit. Requires internet and WebView2. Windows publisher unsigned; updater signatures are verified separately. BetterBox 0.2.1 requires one manual install."
    Invoke-Checked gh @('release', 'create', $tag, '--repo', $repo, '--target', $commit, '--draft', '--prerelease', '--title', "KB OneMail $version - Windows preview", '--notes', $notes)
    Invoke-Checked gh @('release', 'upload', $tag, $installer, "$installer.sig", "$installer.sha256", '--repo', $repo)
    # Verify GitHub's normalized download name before advertising it to installed apps.
    # GitHub gives an unpublished draft an untagged download URL; check its name first.
    $release = gh release view $tag --repo $repo --json assets | ConvertFrom-Json
    $manifest = Get-Content -Raw $manifestPath | ConvertFrom-Json
    $expectedUrl = $manifest.platforms.'windows-x86_64'.url
    $expectedName = [uri]::UnescapeDataString(([uri]$expectedUrl).Segments[-1])
    if (!@($release.assets | Where-Object name -EQ $expectedName).Count) { throw 'Uploaded installer name does not match update manifest' }
    Invoke-Checked gh @('release', 'edit', $tag, '--repo', $repo, '--draft=false')
    $published = gh api "repos/$repo/releases/tags/$tag" | ConvertFrom-Json
    if (!@($published.assets | Where-Object browser_download_url -EQ $expectedUrl).Count) { throw 'Published installer URL does not match update manifest' }
    $channel = @($existing | Where-Object tag_name -EQ 'desktop-preview')
    if (!$channel.Count) {
        Invoke-Checked gh @('release', 'create', 'desktop-preview', '--repo', $repo, '--target', $commit, '--prerelease', '--title', 'KB OneMail preview update channel', '--notes', 'Signed update metadata. Installers live in immutable versioned releases.')
    } else {
        $asset = @($channel[0].assets | Where-Object name -EQ 'latest.json')
        if ($asset.Count) {
            $current = Invoke-WebRequest $asset[0].browser_download_url
            if ((Read-ChannelVersion $current.Content) -ge [version]$version) { throw 'Refusing to regress or replace the update channel' }
        }
    }
    Invoke-Checked gh @('release', 'upload', 'desktop-preview', $manifestPath, '--repo', $repo, '--clobber')
    Write-Output "Published $tag and signed update channel from $commit"
} finally {
    $env:TAURI_SIGNING_PRIVATE_KEY = $previousKey
    $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = $previousPassword
    $env:KB_ONEMAIL_RELEASE_VERSION = $previousVersion
    if (Test-Path -LiteralPath $override) { Remove-Item -LiteralPath $override }
    Pop-Location
}
