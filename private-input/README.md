# private-input/

Put your Microsoft component ZIP here (`mstsc-components-<build>-amd64.zip`, made on
Windows by `windows/Export-MstscComponents.ps1`). `make` picks up the single ZIP it finds
here; alternatively pass `MICROSOFT_COMPONENTS=/path/to/zip`.

Everything in this folder except this README is ignored by Git: the ZIP contains Microsoft's
proprietary files and must never be committed or published.
