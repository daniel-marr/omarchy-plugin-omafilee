# Credits and third-party notices

## Filee

OmaFilee is an unofficial Omarchy front end for
[Filee](https://github.com/KnifeLemon/Filee) by Myeonggu Kim (KnifeLemon) and
the Filee contributors. It is not made, endorsed or supported by the Filee
project. Please report OmaFilee problems here, not to Filee.

All conversion is done by the `filee` command-line tool, which you install
separately from Filee's own releases. OmaFilee does not include or
redistribute any Filee code or binaries.

The donut itself (dropping files on the middle, presets fanned out around it)
is Filee's design, re-implemented here in QML. The default donut layouts in
`FileeModel.js` (`DEFAULT_PROFILES`) are taken from Filee's
`src/Filee.Core/Presets/BuiltInData.cs` at commit
`d7c46e99ad8d0f7dfee4a67e6023c7bbe0a3b73b`, used under Filee's MIT licence:

```
MIT License

Copyright (c) 2026 Myeonggu Kim (KnifeLemon) and Filee contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Omarchy

Built on the Omarchy shell's plugin API and UI components (`qs.Commons`,
`qs.Ui`), which the shell provides at runtime; nothing from Omarchy is bundled.
