$BuildDir = "c:\BuildDir"
New-Item -Path "$BuildDir" -ItemType Directory -Force -ErrorAction SilentlyContinue
Invoke-WebRequest -Uri "https://github.com/shawntmeyer/WVD/archive/master.zip" -outfile "$BuildDir\WVD-Master.zip" -UseBasicParsing
Expand-Archive -Path "$BuildDir\WVD-Master.zip" -DestinationPath "$BuildDir"
& "$BuildDir\WVD-Master\Image-Build\Customizations\Prepare-WVDImage.ps1"
Remove-Item -Path "$BuildDir" -Recurse -ErrorAction SilentlyContinue
Get-ChildItem -Path $env:Temp -Recurse -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
