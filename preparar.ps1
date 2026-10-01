$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter no esta en PATH. Abri la terminal donde normalmente usas flutter y ejecuta este script.'
}
# Genera Gradle y el wrapper con la version de Flutter instalada en esta PC.
# No sobrescribe lib, test ni pubspec.yaml.
if (-not (Test-Path 'android')) {
    $scaffoldDir = Join-Path ([System.IO.Path]::GetTempPath()) ('gestor_' + [guid]::NewGuid().ToString('N'))
    try {
        & flutter create --platforms=android --android-language=kotlin --org cr.ac.ucr --project-name gestor_archivos --no-pub $scaffoldDir
        if ($LASTEXITCODE -ne 0) { throw 'Fallo flutter create.' }
        Copy-Item (Join-Path $scaffoldDir 'android') -Destination 'android' -Recurse
        Copy-Item (Join-Path $scaffoldDir '.metadata') -Destination '.metadata'
    } finally {
        if (Test-Path $scaffoldDir) { Remove-Item $scaffoldDir -Recurse -Force }
    }
}
$manifestPath = Join-Path $PSScriptRoot 'android\app\src\main\AndroidManifest.xml'
$manifest = [System.IO.File]::ReadAllText($manifestPath)
$manifest = $manifest.Replace('android:label="gestor_archivos"', 'android:label="Mis archivos"')
if ($manifest -notmatch 'android:allowBackup=') {
    $manifest = $manifest.Replace('<application', '<application android:allowBackup="false"')
}
# Permisos para explorar el almacenamiento compartido real.
$permissions = @'
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE" />
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="29" />
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE" android:maxSdkVersion="29" />
'@
if ($manifest -notmatch 'android.permission.MANAGE_EXTERNAL_STORAGE') {
    $manifest = $manifest.Replace('<application', "$permissions`n    <application")
}
if ($manifest -notmatch 'android:requestLegacyExternalStorage=') {
    $manifest = $manifest.Replace('<application', '<application android:requestLegacyExternalStorage="true"')
}
# Adapta el paquete al namespace existente para permitir actualizar el proyecto.
$buildPath = 'android\app\build.gradle.kts'
if (-not (Test-Path $buildPath)) { $buildPath = 'android\app\build.gradle' }
$build = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot $buildPath))
$match = [regex]::Match($build, 'namespace\s*(?:=\s*)?["'']([^"'']+)["'']')
if (-not $match.Success) { throw 'No se encontro namespace en build.gradle. No se modifico MainActivity.' }
$packageName = $match.Groups[1].Value
$activityDir = Join-Path $PSScriptRoot ('android\app\src\main\kotlin\' + $packageName.Replace('.', '\'))
New-Item -ItemType Directory -Force -Path $activityDir | Out-Null
$activity = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'android_template\MainActivity.kt'))
$activity = $activity.Replace('package cr.ac.ucr.gestor_archivos', "package $packageName")
[System.IO.File]::WriteAllText((Join-Path $activityDir 'MainActivity.kt'), $activity, (New-Object System.Text.UTF8Encoding($false)))
[System.IO.File]::WriteAllText($manifestPath, $manifest, (New-Object System.Text.UTF8Encoding($false)))
# Resuelve conflictos de permisos con open_filex en main/debug/profile/flavors.
$androidNs = 'http://schemas.android.com/apk/res/android'
$toolsNs = 'http://schemas.android.com/tools'
Get-ChildItem (Join-Path $PSScriptRoot 'android\app\src') -Filter AndroidManifest.xml -Recurse | ForEach-Object {
    $filePath = $_.FullName
    $xml = New-Object System.Xml.XmlDocument
    $xml.PreserveWhitespace = $true
    $xml.Load($filePath)
    $changed = $false
    foreach ($permission in $xml.SelectNodes('/manifest/uses-permission')) {
        $permissionName = $permission.GetAttribute('name', $androidNs)
        if ($permissionName -in @('android.permission.READ_EXTERNAL_STORAGE', 'android.permission.WRITE_EXTERNAL_STORAGE')) {
            $xmlns = $xml.CreateAttribute('xmlns', 'tools', 'http://www.w3.org/2000/xmlns/')
            $xmlns.Value = $toolsNs
            [void]$xml.DocumentElement.Attributes.SetNamedItem($xmlns)
            $max = $xml.CreateAttribute('android', 'maxSdkVersion', $androidNs)
            $max.Value = '29'
            [void]$permission.Attributes.SetNamedItem($max)
            $values = @($permission.GetAttribute('replace', $toolsNs).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            if ($values -notcontains 'android:maxSdkVersion') { $values += 'android:maxSdkVersion' }
            $replace = $xml.CreateAttribute('tools', 'replace', $toolsNs)
            $replace.Value = $values -join ','
            [void]$permission.Attributes.SetNamedItem($replace)
            $changed = $true
        }
    }
    if ($changed) { $xml.Save($filePath) }
}
$installedActivity = Join-Path $activityDir 'MainActivity.kt'
$installedCode = [System.IO.File]::ReadAllText($installedActivity)
if ($installedCode -notmatch '"dashboard"\s*->' -or $installedCode -notmatch 'gestor/storage') {
    throw 'MainActivity no contiene dashboard. Copia android_template de esta version y ejecuta de nuevo.'
}
Write-Host "Android actualizado: $installedActivity" -ForegroundColor Green
& flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron descargar las dependencias. Revisa el error anterior y tu conexion.' }
Write-Host "`nProyecto preparado. Ahora ejecuta: flutter devices" -ForegroundColor Green
Write-Host 'Luego: flutter run -d ID_DEL_TELEFONO'
