# Spreadsheet reader

SheetJS Community Edition 0.20.3, vendored from the official release:
https://cdn.sheetjs.com/xlsx-0.20.3/package/dist/xlsx.full.min.js

SHA-256: `cc015130aa8521e7f088f88898eba949ccdcbfb38df0bd129b44b7273c3a6f41`

The library is loaded only when a user selects a spreadsheet. File parsing happens in the browser. Business Center records a reconciliation result only when the administrator selects Save; the original workbook is not uploaded. Formula values are read from Excel's saved cache; missing/error results require correction in Excel and a new import.

See `SheetJS-LICENSE.txt` for the upstream license.
